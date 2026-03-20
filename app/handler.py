import json
import boto3
import csv
import logging
from datetime import datetime
from urllib.parse import unquote_plus

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients (will use LocalStack endpoints)
s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

# DynamoDB table name
TABLE_NAME = 'file-processing-results'

def lambda_handler(event, context):
    """
    Lambda function to process CSV files uploaded to S3.
    Extracts metadata and stores results in DynamoDB.
    """
    
    try:
        # Parse S3 event
        for record in event['Records']:
            # Extract bucket and object key from S3 event
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            logger.info(f"Processing file: {key} from bucket: {bucket}")
            
            # Check if it's a CSV file
            if not key.lower().endswith('.csv'):
                logger.warning(f"Skipping non-CSV file: {key}")
                continue
                
            # Process the CSV file
            result = process_csv_file(bucket, key)
            
            # Store results in DynamoDB
            store_results(result)
            
            logger.info(f"Successfully processed file: {key}")
            
        return {
            'statusCode': 200,
            'body': json.dumps('Files processed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error processing files: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error processing files: {str(e)}')
        }

def process_csv_file(bucket, key):
    """
    Download and analyze CSV file from S3.
    Returns metadata about the file.
    """
    
    try:
        # Download file from S3
        response = s3_client.get_object(Bucket=bucket, Key=key)
        file_content = response['Body'].read().decode('utf-8')
        file_size = response['ContentLength']
        
        # Parse CSV content
        csv_reader = csv.reader(file_content.splitlines())
        
        # Get headers (first row)
        headers = next(csv_reader, [])
        
        # Count rows (excluding header)
        rows = list(csv_reader)
        row_count = len(rows)
        column_count = len(headers)
        
        # Prepare result
        result = {
            'file_id': key,
            'bucket': bucket,
            'object_key': key,
            'uploaded_at': datetime.utcnow().isoformat(),
            'processed_at': datetime.utcnow().isoformat(),
            'file_size': file_size,
            'row_count': row_count,
            'column_count': column_count,
            'headers': headers,
            'status': 'success',
            'error_message': None
        }
        
        logger.info(f"File analysis complete - Rows: {row_count}, Columns: {column_count}")
        return result
        
    except Exception as e:
        error_msg = f"Error processing CSV file: {str(e)}"
        logger.error(error_msg)
        
        # Return error result
        return {
            'file_id': key,
            'bucket': bucket,
            'object_key': key,
            'uploaded_at': datetime.utcnow().isoformat(),
            'processed_at': datetime.utcnow().isoformat(),
            'file_size': 0,
            'row_count': 0,
            'column_count': 0,
            'headers': [],
            'status': 'error',
            'error_message': error_msg
        }

def store_results(result):
    """
    Store processing results in DynamoDB.
    """
    
    try:
        table = dynamodb.Table(TABLE_NAME)
        
        # Put item in DynamoDB
        table.put_item(Item=result)
        
        logger.info(f"Results stored in DynamoDB for file: {result['file_id']}")
        
    except Exception as e:
        logger.error(f"Error storing results in DynamoDB: {str(e)}")
        raise e