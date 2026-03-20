#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Script to create AWS resources in LocalStack
# Run this after LocalStack is up and running

echo "Creating AWS resources in LocalStack..."
require_localstack
require_env UPLOAD_BUCKET
require_env PROCESSED_BUCKET
require_env TRANSCRIPTION_QUEUE_NAME
require_env TABLE_NAME
require_env LAMBDA_ROLE_NAME

# Create S3 bucket
echo "Ensuring S3 buckets exist..."
for bucket in "$UPLOAD_BUCKET" "$PROCESSED_BUCKET"; do
    if aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
        echo "- Bucket already exists: $bucket"
    else
        aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" s3 mb "s3://$bucket"
    fi
done

# List buckets to verify
echo "Verifying S3 buckets..."
aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" s3 ls

# Create SQS queue for media transcription jobs
echo "Ensuring SQS queue exists..."
if aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" sqs get-queue-url \
    --queue-name "$TRANSCRIPTION_QUEUE_NAME" >/dev/null 2>&1; then
    echo "- Queue already exists: $TRANSCRIPTION_QUEUE_NAME"
else
    aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" sqs create-queue \
        --queue-name "$TRANSCRIPTION_QUEUE_NAME"
fi

# Create DynamoDB table
echo "Ensuring DynamoDB table exists..."
if aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" dynamodb describe-table \
    --table-name "$TABLE_NAME" >/dev/null 2>&1; then
    echo "- Table already exists: $TABLE_NAME"
else
    aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" dynamodb create-table \
        --table-name "$TABLE_NAME" \
        --attribute-definitions \
            AttributeName=file_id,AttributeType=S \
        --key-schema \
            AttributeName=file_id,KeyType=HASH \
        --provisioned-throughput \
            ReadCapacityUnits=5,WriteCapacityUnits=5
fi

# Wait for table to be created
echo "Waiting for DynamoDB table to be active..."
aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" dynamodb wait table-exists --table-name "$TABLE_NAME"

# List tables to verify
echo "Verifying DynamoDB table..."
aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" dynamodb list-tables

# Create IAM role for Lambda
echo "Ensuring IAM role exists..."
if aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" iam get-role \
    --role-name "$LAMBDA_ROLE_NAME" >/dev/null 2>&1; then
    echo "- IAM role already exists: $LAMBDA_ROLE_NAME"
else
    aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" iam create-role \
        --role-name "$LAMBDA_ROLE_NAME" \
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
        }'
fi

# Attach policy to role
echo "Ensuring IAM policies are attached..."
aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" iam attach-role-policy \
    --role-name "$LAMBDA_ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Create and attach custom policy for S3 and DynamoDB access
aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" iam put-role-policy \
    --role-name "$LAMBDA_ROLE_NAME" \
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
                    "sqs:SendMessage",
                    "sqs:GetQueueUrl"
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
    }'

echo "AWS resources created successfully!"
echo ""
echo "Resources created:"
echo "- S3 buckets: $UPLOAD_BUCKET, $PROCESSED_BUCKET"
echo "- SQS queue: $TRANSCRIPTION_QUEUE_NAME"
echo "- DynamoDB table: $TABLE_NAME"
echo "- IAM role: $LAMBDA_ROLE_NAME"
echo ""
echo "Next steps:"
echo "1. Run ./scripts/deploy_lambda.sh to deploy the Lambda function"
echo "2. Run ./scripts/upload_test_file.sh to test the pipeline"
