#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

# Script to upload test files and trigger the processing pipeline

echo "Uploading test file to S3..."
require_localstack

# Upload the sample CSV file
echo "Uploading sample.csv to file-uploads bucket..."
SAMPLE_FILE="$REPO_ROOT/data/sample.csv"
aws_localstack_s3_upload "$SAMPLE_FILE" "s3://file-uploads/$(basename "$SAMPLE_FILE")"

# Wait a moment for processing
echo "File uploaded! Waiting for processing..."
sleep 5

# Check Lambda logs
echo "Checking Lambda logs..."
aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" logs describe-log-groups
echo ""

# Check if we can get the latest log group for our Lambda
LOG_GROUP="/aws/lambda/file-processor"
LOG_GROUP_EXISTS=$(aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" logs describe-log-groups \
    --log-group-name-prefix "$LOG_GROUP" \
    --query 'logGroups[0].logGroupName' \
    --output text 2>/dev/null || true)

if [ "$LOG_GROUP_EXISTS" != "None" ] && [ "$LOG_GROUP_EXISTS" != "" ]; then
    echo "Getting recent Lambda logs..."
    aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" logs describe-log-streams \
        --log-group-name "$LOG_GROUP" \
        --order-by LastEventTime \
        --descending

    echo "Latest log events:"
    LATEST_STREAM=$(aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" logs describe-log-streams \
        --log-group-name "$LOG_GROUP" \
        --order-by LastEventTime \
        --descending \
        --max-items 1 \
        --query 'logStreams[0].logStreamName' \
        --output text)

    if [ "$LATEST_STREAM" != "None" ] && [ "$LATEST_STREAM" != "" ]; then
        aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" logs get-log-events \
            --log-group-name "$LOG_GROUP" \
            --log-stream-name "$LATEST_STREAM" \
            --query 'events[*].message' \
            --output text
    else
        echo "No Lambda log streams found yet."
    fi
else
    echo "Lambda log group does not exist yet. This usually means the function was not invoked."
fi

# Check DynamoDB for results
echo ""
echo "Checking DynamoDB for processing results..."
aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" dynamodb scan \
    --table-name file-processing-results \
    --query 'Items[*].[file_id.S,status.S,row_count.N,column_count.N]' \
    --output table

echo ""
echo "Pipeline test complete!"
echo "Check the output above to see if your file was processed successfully."
