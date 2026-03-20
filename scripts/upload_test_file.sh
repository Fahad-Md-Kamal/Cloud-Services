#!/bin/bash

# Script to upload test files and trigger the processing pipeline

echo "Uploading test file to S3..."

# Set LocalStack endpoint
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
ENDPOINT="--endpoint-url=http://localhost:4566"

# Upload the sample CSV file
echo "Uploading sample.csv to file-uploads bucket..."
aws s3 cp data/sample.csv s3://file-uploads/ $ENDPOINT

# Wait a moment for processing
echo "File uploaded! Waiting for processing..."
sleep 5

# Check Lambda logs
echo "Checking Lambda logs..."
aws logs describe-log-groups $ENDPOINT
echo ""

# Check if we can get the latest log group for our Lambda
LOG_GROUP="/aws/lambda/file-processor"
echo "Getting recent Lambda logs..."
aws logs describe-log-streams \
    --log-group-name $LOG_GROUP \
    --order-by LastEventTime \
    --descending \
    $ENDPOINT

# Try to get the latest log events
echo "Latest log events:"
LATEST_STREAM=$(aws logs describe-log-streams \
    --log-group-name $LOG_GROUP \
    --order-by LastEventTime \
    --descending \
    --max-items 1 \
    --query 'logStreams[0].logStreamName' \
    --output text \
    $ENDPOINT)

if [ "$LATEST_STREAM" != "None" ] && [ "$LATEST_STREAM" != "" ]; then
    aws logs get-log-events \
        --log-group-name $LOG_GROUP \
        --log-stream-name $LATEST_STREAM \
        --query 'events[*].message' \
        --output text \
        $ENDPOINT
fi

# Check DynamoDB for results
echo ""
echo "Checking DynamoDB for processing results..."
aws dynamodb scan \
    --table-name file-processing-results \
    --query 'Items[*].[file_id.S,status.S,row_count.N,column_count.N]' \
    --output table \
    $ENDPOINT

echo ""
echo "Pipeline test complete!"
echo "Check the output above to see if your file was processed successfully."