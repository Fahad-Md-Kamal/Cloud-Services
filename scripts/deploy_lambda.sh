#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

# Script to deploy Lambda function to LocalStack
# Run this after creating AWS resources

echo "Deploying Lambda function..."
require_localstack

# Create deployment package
echo "Creating deployment package..."
ZIP_PATH="$REPO_ROOT/function.zip"
(cd "$REPO_ROOT/app" && zip -rq "$ZIP_PATH" .)

STAGED_ZIP_PATH="$(aws_localstack_stage_file "$ZIP_PATH")"
trap 'aws_localstack_unstage_file "$STAGED_ZIP_PATH"; rm -f "$ZIP_PATH"' EXIT

wait_for_lambda_ready() {
    local max_attempts=20
    local attempt=1
    local state=""

    while (( attempt <= max_attempts )); do
        state="$(aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" lambda get-function-configuration \
            --function-name file-processor \
            --query 'State' \
            --output text 2>/dev/null || true)"

        if [[ "$state" == "Active" ]]; then
            return 0
        fi

        if [[ "$state" == "Failed" ]]; then
            echo "Error: Lambda function entered Failed state." >&2
            aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" lambda get-function-configuration \
                --function-name file-processor
            return 1
        fi

        sleep 2
        ((attempt++))
    done

    echo "Error: Lambda function did not become Active in time." >&2
    aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" lambda get-function-configuration \
        --function-name file-processor
    return 1
}

if aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" lambda get-function \
    --function-name file-processor >/dev/null 2>&1; then
    echo "Updating existing Lambda function..."
    aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" lambda update-function-code \
        --function-name file-processor \
        --zip-file "fileb://$STAGED_ZIP_PATH"

    aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" lambda update-function-configuration \
        --function-name file-processor \
        --runtime python3.9 \
        --role arn:aws:iam::000000000000:role/lambda-execution-role \
        --handler handler.lambda_handler \
        --timeout 60 \
        --memory-size 256 \
        --environment Variables='{LOCALSTACK=true}'
else
    echo "Creating Lambda function..."
    aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" lambda create-function \
        --function-name file-processor \
        --runtime python3.9 \
        --role arn:aws:iam::000000000000:role/lambda-execution-role \
        --handler handler.lambda_handler \
        --zip-file "fileb://$STAGED_ZIP_PATH" \
        --timeout 60 \
        --memory-size 256 \
        --environment Variables='{LOCALSTACK=true}'
fi

echo "Waiting for Lambda function to become active..."
wait_for_lambda_ready

# Refresh permission before configuring the bucket notification.
aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" lambda remove-permission \
    --function-name file-processor \
    --statement-id s3-trigger >/dev/null 2>&1 || true

echo "Adding S3 invoke permission to Lambda..."
aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" lambda add-permission \
    --function-name file-processor \
    --statement-id s3-trigger \
    --action lambda:InvokeFunction \
    --principal s3.amazonaws.com \
    --source-arn arn:aws:s3:::file-uploads

# Configure S3 event notification to trigger Lambda
echo "Configuring S3 event notification..."
aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" s3api put-bucket-notification-configuration \
    --bucket file-uploads \
    --notification-configuration '{
        "LambdaFunctionConfigurations": [
            {
                "Id": "csv-processor",
                "LambdaFunctionArn": "arn:aws:lambda:us-east-1:000000000000:function:file-processor",
                "Events": [
                    "s3:ObjectCreated:*"
                ]
            }
        ]
    }'

echo "Lambda function deployed successfully!"
echo ""
echo "Function details:"
echo "- Name: file-processor"
echo "- Runtime: python3.9"
echo "- Trigger: S3 uploads to 'file-uploads' bucket"
echo "- Handler: handler.lambda_handler"
echo ""
echo "You can now upload CSV files to test the pipeline!"
