# CSV File Processing Pipeline

A serverless file processing pipeline that automatically analyzes CSV files uploaded to S3, extracts metadata, and stores the results in DynamoDB. Built with AWS Lambda, S3, DynamoDB, and LocalStack for local development.

## 🎯 Project Overview

This project demonstrates a complete serverless "Upload → Process → Store Results" workflow:

1. **Upload**: CSV file is uploaded to S3 bucket
2. **Trigger**: S3 event automatically triggers Lambda function  
3. **Process**: Lambda analyzes the CSV file (rows, columns, headers, size)
4. **Store**: Results are saved to DynamoDB with metadata

## 🏗️ Architecture

```
┌─────────┐    ┌─────────┐    ┌──────────┐    ┌──────────┐
│   CSV   │───▶│   S3    │───▶│  Lambda  │───▶│ DynamoDB │
│  Upload │    │ Bucket  │    │ Function │    │  Table   │
└─────────┘    └─────────┘    └──────────┘    └──────────┘
```

## 🚀 Quick Start

### Prerequisites

- Docker and Docker Compose
- AWS CLI
- Python 3.9+ (for local development)

### 1. Start LocalStack

```bash
# Start LocalStack services
docker-compose up -d

# Verify LocalStack is running
curl http://localhost:4566/_localstack/health
```

### 2. Create AWS Resources

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Create S3 buckets, DynamoDB table, and IAM roles
./scripts/create_resources.sh
```

### 3. Deploy Lambda Function

```bash
# Package and deploy Lambda function
./scripts/deploy_lambda.sh
```

### 4. Test the Pipeline

```bash
# Upload sample CSV file and check results
./scripts/upload_test_file.sh
```

## 📁 Project Structure

```
file-processing-pipeline/
├── app/
│   └── handler.py              # Lambda function code
├── scripts/
│   ├── create_resources.sh     # Creates AWS resources
│   ├── deploy_lambda.sh        # Deploys Lambda function
│   └── upload_test_file.sh     # Tests the pipeline
├── data/
│   └── sample.csv              # Test CSV file
├── volume/                     # LocalStack persistence
├── requirements.txt            # Python dependencies
├── docker-compose.yml          # LocalStack configuration
└── README.md                   # This file
```

## 🔧 How It Works

### Lambda Function Process

1. **Event Parsing**: Extracts bucket name and object key from S3 event
2. **File Validation**: Checks if uploaded file is CSV format
3. **Download & Parse**: Downloads file from S3 and parses CSV content
4. **Metadata Extraction**: 
   - File size
   - Row count (excluding headers)
   - Column count
   - Column headers
   - Upload/processing timestamps
5. **Store Results**: Saves metadata to DynamoDB table

### Data Stored in DynamoDB

Each processed file creates a record with:

| Field | Type | Description |
|-------|------|-------------|
| `file_id` | String | Primary key (S3 object key) |
| `bucket` | String | S3 bucket name |
| `object_key` | String | S3 object key |
| `uploaded_at` | String | File upload timestamp |
| `processed_at` | String | Processing completion timestamp |
| `file_size` | Number | File size in bytes |
| `row_count` | Number | Number of data rows (excluding header) |
| `column_count` | Number | Number of columns |
| `headers` | List | Column headers array |
| `status` | String | Processing status (success/error) |
| `error_message` | String | Error details if processing failed |

## 🧪 Testing

### Manual Testing

1. Upload a CSV file:
```bash
aws s3 cp your-file.csv s3://file-uploads/ --endpoint-url=http://localhost:4566
```

2. Check processing logs:
```bash
aws logs describe-log-groups --endpoint-url=http://localhost:4566
```

3. Query results:
```bash
aws dynamodb scan --table-name file-processing-results --endpoint-url=http://localhost:4566
```

### Sample Test Data

The included `sample.csv` contains sales data with:
- 15 data rows + 1 header row
- 6 columns: date, product, region, sales_rep, amount, quantity
- File size: ~1KB

Expected processing results:
- `row_count`: 15
- `column_count`: 6  
- `headers`: ["date", "product", "region", "sales_rep", "amount", "quantity"]
- `status`: "success"

## 🔍 Debugging

### Check Lambda Logs
```bash
# List log groups
aws logs describe-log-groups --endpoint-url=http://localhost:4566

# Get log events
aws logs get-log-events \
    --log-group-name /aws/lambda/file-processor \
    --log-stream-name [STREAM_NAME] \
    --endpoint-url=http://localhost:4566
```

### Check DynamoDB Data
```bash
# Scan all records
aws dynamodb scan \
    --table-name file-processing-results \
    --endpoint-url=http://localhost:4566

# Get specific record
aws dynamodb get-item \
    --table-name file-processing-results \
    --key '{"file_id":{"S":"sample.csv"}}' \
    --endpoint-url=http://localhost:4566
```

### Common Issues

1. **Lambda not triggering**: Check S3 event notification configuration
2. **Permission errors**: Verify IAM role has correct policies attached
3. **CSV parsing errors**: Check file format and encoding (UTF-8 expected)
4. **DynamoDB errors**: Verify table exists and is in ACTIVE state

## 🚀 Extensions & Next Steps

### Easy Extensions

- [ ] Support JSON files
- [ ] Add file format validation
- [ ] Skip empty files
- [ ] Store processing duration
- [ ] Handle duplicate uploads

### Intermediate Extensions  

- [ ] Add API Gateway endpoint to query results
- [ ] Create separate bucket for processed files
- [ ] Add SQS between S3 and Lambda for better scalability
- [ ] Implement dead letter queue for failed processing

### Advanced Extensions

- [ ] Support multiple file formats (JSON, XML, Excel)
- [ ] Add data quality checks and validation
- [ ] Implement Step Functions for complex workflows
- [ ] Add EventBridge for event routing
- [ ] Create web dashboard for monitoring

## 📚 Learning Objectives

This project teaches:

### AWS Services
- **S3**: Object storage, event notifications, bucket policies
- **Lambda**: Event-driven computing, function packaging, environment variables
- **DynamoDB**: NoSQL database operations, item storage and retrieval
- **IAM**: Roles and policies for service permissions
- **CloudWatch Logs**: Application logging and monitoring

### Serverless Concepts
- Event-driven architecture
- Function as a Service (FaaS)
- Managed services integration
- Local development with LocalStack

### Development Skills
- Python AWS SDK (Boto3)
- CSV file processing
- Error handling and logging
- Infrastructure as code
- Shell scripting for automation

## 🔗 Resources

- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)
- [LocalStack Documentation](https://docs.localstack.cloud/)
- [Boto3 Documentation](https://boto3.amazonaws.com/v1/documentation/api/latest/index.html)
- [AWS S3 Event Notifications](https://docs.aws.amazon.com/AmazonS3/latest/userguide/NotificationHowTo.html)

## 📄 License

This project is for educational purposes. Feel free to use and modify as needed.

---

**Portfolio Description**: 
Built a local serverless file processing pipeline using LocalStack, S3, Lambda, and DynamoDB. Implemented event-driven CSV ingestion, metadata extraction, and result persistence with a fully local AWS development workflow.