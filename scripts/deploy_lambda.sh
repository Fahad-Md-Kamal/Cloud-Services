#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

# Script to deploy Lambda function to LocalStack
# Run this after creating AWS resources

echo "Deploying Lambda function..."
require_localstack
require_env UPLOAD_BUCKET
require_env TABLE_NAME
require_env TRANSCRIPTION_QUEUE_NAME
require_env DEFAULT_TRANSCRIPTION_ENGINE
require_env LAMBDA_FUNCTION_NAME
require_env LAMBDA_ROLE_NAME

# Create deployment package
echo "Creating deployment package..."
ZIP_PATH="$REPO_ROOT/function.zip"
PACKAGE_DIR="$(mktemp -d)"
trap 'aws_localstack_unstage_file "${STAGED_ZIP_PATH:-}"; rm -rf "$PACKAGE_DIR"; rm -f "$ZIP_PATH"' EXIT

python3 -m pip install --quiet -r "$REPO_ROOT/requirements-lambda.txt" --target "$PACKAGE_DIR"
cp "$REPO_ROOT"/shared_config.py "$PACKAGE_DIR"/
cp "$REPO_ROOT"/app/*.py "$PACKAGE_DIR"/

(cd "$PACKAGE_DIR" && zip -rq "$ZIP_PATH" .)

STAGED_ZIP_PATH="$(aws_localstack_stage_file "$ZIP_PATH")"

LAMBDA_ROLE_ARN="arn:aws:iam::000000000000:role/$LAMBDA_ROLE_NAME"
LAMBDA_FUNCTION_ARN="arn:aws:lambda:${AWS_DEFAULT_REGION}:000000000000:function:$LAMBDA_FUNCTION_NAME"
LAMBDA_ENVIRONMENT="Variables={LOCALSTACK=true,TABLE_NAME=$TABLE_NAME,TRANSCRIPTION_QUEUE_NAME=$TRANSCRIPTION_QUEUE_NAME,DEFAULT_TRANSCRIPTION_ENGINE=$DEFAULT_TRANSCRIPTION_ENGINE}"

wait_for_lambda_ready() {
    local max_attempts=20
    local attempt=1
    local state=""

    while (( attempt <= max_attempts )); do
        state="$(aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" lambda get-function-configuration \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --query 'State' \
            --output text 2>/dev/null || true)"

        if [[ "$state" == "Active" ]]; then
            return 0
        fi

        if [[ "$state" == "Failed" ]]; then
            echo "Error: Lambda function entered Failed state." >&2
            aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" lambda get-function-configuration \
                --function-name "$LAMBDA_FUNCTION_NAME"
            return 1
        fi

        sleep 2
        ((attempt++))
    done

    echo "Error: Lambda function did not become Active in time." >&2
    aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" lambda get-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME"
    return 1
}

if aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" lambda get-function \
    --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
    echo "Updating existing Lambda function..."
    aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" lambda update-function-code \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --zip-file "fileb://$STAGED_ZIP_PATH"

    aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" lambda update-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler handler.lambda_handler \
        --timeout 60 \
        --memory-size 256 \
        --environment "$LAMBDA_ENVIRONMENT"
else
    echo "Creating Lambda function..."
    aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler handler.lambda_handler \
        --zip-file "fileb://$STAGED_ZIP_PATH" \
        --timeout 60 \
        --memory-size 256 \
        --environment "$LAMBDA_ENVIRONMENT"
fi

echo "Waiting for Lambda function to become active..."
wait_for_lambda_ready

# Refresh permission before configuring the bucket notification.
aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" lambda remove-permission \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --statement-id s3-trigger >/dev/null 2>&1 || true

echo "Adding S3 invoke permission to Lambda..."
aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" lambda add-permission \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --statement-id s3-trigger \
    --action lambda:InvokeFunction \
    --principal s3.amazonaws.com \
    --source-arn "arn:aws:s3:::$UPLOAD_BUCKET"

# Configure S3 event notification to trigger Lambda
echo "Configuring S3 event notification..."
aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" s3api put-bucket-notification-configuration \
    --bucket "$UPLOAD_BUCKET" \
    --notification-configuration "{
        \"LambdaFunctionConfigurations\": [
            {
                \"Id\": \"s3-upload-trigger\",
                \"LambdaFunctionArn\": \"$LAMBDA_FUNCTION_ARN\",
                \"Events\": [
                    \"s3:ObjectCreated:*\"
                ]
            }
        ]
    }"

echo "Lambda function deployed successfully!"
echo ""
echo "Function details:"
echo "- Name: $LAMBDA_FUNCTION_NAME"
echo "- Runtime: python3.9"
echo "- Trigger: S3 uploads to '$UPLOAD_BUCKET' bucket"
echo "- Handler: handler.lambda_handler"
echo ""
echo "You can now upload files to test the pipeline!"
