#!/bin/bash

# Script to create AWS resources in LocalStack
# Run this after LocalStack is up and running

echo "Creating AWS resources in LocalStack..."

# Set LocalStack endpoint
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
ENDPOINT="--endpoint-url=http://localhost:4566"

# Create S3 bucket
echo "Creating S3 bucket..."
aws s3 mb s3://file-uploads $ENDPOINT
aws s3 mb s3://processed-files $ENDPOINT

# List buckets to verify
echo "Verifying S3 buckets..."
aws s3 ls $ENDPOINT

# Create DynamoDB table
echo "Creating DynamoDB table..."
aws dynamodb create-table \
    --table-name file-processing-results \
    --attribute-definitions \
        AttributeName=file_id,AttributeType=S \
    --key-schema \
        AttributeName=file_id,KeyType=HASH \
    --provisioned-throughput \
        ReadCapacityUnits=5,WriteCapacityUnits=5 \
    $ENDPOINT

# Wait for table to be created
echo "Waiting for DynamoDB table to be active..."
aws dynamodb wait table-exists --table-name file-processing-results $ENDPOINT

# List tables to verify
echo "Verifying DynamoDB table..."
aws dynamodb list-tables $ENDPOINT

# Create IAM role for Lambda
echo "Creating IAM role for Lambda..."
aws iam create-role \
    --role-name lambda-execution-role \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "lambda.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }' \
    $ENDPOINT

# Attach policy to role
echo "Attaching policies to Lambda role..."
aws iam attach-role-policy \
    --role-name lambda-execution-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
    $ENDPOINT

# Create and attach custom policy for S3 and DynamoDB access
aws iam put-role-policy \
    --role-name lambda-execution-role \
    --policy-name lambda-s3-dynamodb-policy \
    --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "s3:GetObject",
                    "s3:PutObject"
                ],
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "dynamodb:PutItem",
                    "dynamodb:GetItem",
                    "dynamodb:Scan",
                    "dynamodb:Query"
                ],
                "Resource": "*"
            }
        ]
    }' \
    $ENDPOINT

echo "AWS resources created successfully!"
echo ""
echo "Resources created:"
echo "- S3 buckets: file-uploads, processed-files"
echo "- DynamoDB table: file-processing-results"
echo "- IAM role: lambda-execution-role"
echo ""
echo "Next steps:"
echo "1. Run ./scripts/deploy_lambda.sh to deploy the Lambda function"
echo "2. Run ./scripts/upload_test_file.sh to test the pipeline"