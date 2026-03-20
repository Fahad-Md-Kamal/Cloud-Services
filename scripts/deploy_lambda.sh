#!/bin/bash

# Script to deploy Lambda function to LocalStack
# Run this after creating AWS resources

echo "Deploying Lambda function..."

# Set LocalStack endpoint
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
ENDPOINT="--endpoint-url=http://localhost:4566"

# Create deployment package
echo "Creating deployment package..."
cd app/
zip -r ../function.zip .
cd ..

# Create Lambda function
echo "Creating Lambda function..."
aws lambda create-function \
    --function-name file-processor \
    --runtime python3.9 \
    --role arn:aws:iam::000000000000:role/lambda-execution-role \
    --handler handler.lambda_handler \
    --zip-file fileb://function.zip \
    --timeout 60 \
    --memory-size 256 \
    --environment Variables='{LOCALSTACK=true}' \
    $ENDPOINT

# Wait a moment for function to be ready
sleep 3

# Configure S3 event notification to trigger Lambda
echo "Configuring S3 event notification..."
aws s3api put-bucket-notification-configuration \
    --bucket file-uploads \
    --notification-configuration '{
        "LambdaConfigurations": [
            {
                "Id": "csv-processor",
                "LambdaFunctionArn": "arn:aws:lambda:us-east-1:000000000000:function:file-processor",
                "Events": [
                    "s3:ObjectCreated:*"
                ]
            }
        ]
    }' \
    $ENDPOINT

# Add permission for S3 to invoke Lambda
echo "Adding S3 invoke permission to Lambda..."
aws lambda add-permission \
    --function-name file-processor \
    --statement-id s3-trigger \
    --action lambda:InvokeFunction \
    --principal s3.amazonaws.com \
    --source-arn arn:aws:s3:::file-uploads \
    $ENDPOINT

# Clean up
rm function.zip

echo "Lambda function deployed successfully!"
echo ""
echo "Function details:"
echo "- Name: file-processor"
echo "- Runtime: python3.9"
echo "- Trigger: S3 uploads to 'file-uploads' bucket"
echo "- Handler: handler.lambda_handler"
echo ""
echo "You can now upload CSV files to test the pipeline!"