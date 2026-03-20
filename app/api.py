import os
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from fastapi import FastAPI, File, HTTPException, UploadFile


LOCALSTACK_ENDPOINT = os.getenv("LOCALSTACK_ENDPOINT", "http://localhost:4566")
AWS_REGION = os.getenv("AWS_DEFAULT_REGION", "us-east-1")
UPLOAD_BUCKET = os.getenv("UPLOAD_BUCKET", "file-uploads")
TABLE_NAME = os.getenv("TABLE_NAME", "file-processing-results")
ALLOWED_EXTENSIONS = {".csv", ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp"}


app = FastAPI(title="File Upload API")


def get_s3_client():
    return boto3.client(
        "s3",
        endpoint_url=LOCALSTACK_ENDPOINT,
        region_name=AWS_REGION,
        aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID", "test"),
        aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY", "test"),
    )


def get_results_table():
    dynamodb = boto3.resource(
        "dynamodb",
        endpoint_url=LOCALSTACK_ENDPOINT,
        region_name=AWS_REGION,
        aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID", "test"),
        aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY", "test"),
    )
    return dynamodb.Table(TABLE_NAME)


def serialize_value(value):
    if isinstance(value, list):
        return [serialize_value(item) for item in value]
    if isinstance(value, dict):
        return {key: serialize_value(item) for key, item in value.items()}
    if isinstance(value, Decimal):
        return int(value) if value % 1 == 0 else float(value)
    return value


@app.get("/health")
def health():
    return {
        "status": "ok",
        "bucket": UPLOAD_BUCKET,
        "endpoint": LOCALSTACK_ENDPOINT,
        "table": TABLE_NAME,
    }


@app.get("/files")
def list_files():
    try:
        table = get_results_table()
        response = table.scan()
        items = response.get("Items", [])

        while "LastEvaluatedKey" in response:
            response = table.scan(ExclusiveStartKey=response["LastEvaluatedKey"])
            items.extend(response.get("Items", []))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to load file metadata: {exc}") from exc

    serialized_items = [serialize_value(item) for item in items]
    serialized_items.sort(key=lambda item: item.get("processed_at", ""), reverse=True)

    return {
        "count": len(serialized_items),
        "items": serialized_items,
    }


@app.get("/files/{file_id}")
def get_file(file_id: str):
    try:
        table = get_results_table()
        response = table.get_item(Key={"file_id": file_id})
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to load file metadata: {exc}") from exc

    item = response.get("Item")
    if not item:
        raise HTTPException(status_code=404, detail="File metadata not found.")

    return serialize_value(item)


@app.post("/upload")
def upload_file(file: UploadFile = File(...)):
    if not file.filename:
        raise HTTPException(status_code=400, detail="Filename is required.")

    if not any(file.filename.lower().endswith(extension) for extension in ALLOWED_EXTENSIONS):
        raise HTTPException(
            status_code=400,
            detail="Supported files: .csv, .png, .jpg, .jpeg, .gif, .bmp, .webp",
        )

    object_key = f"{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S')}_{file.filename}"

    try:
        s3_client = get_s3_client()
        s3_client.upload_fileobj(
            file.file,
            UPLOAD_BUCKET,
            object_key,
            ExtraArgs={"ContentType": file.content_type or "text/csv"},
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Upload failed: {exc}") from exc
    finally:
        file.file.close()

    return {
        "message": "File uploaded successfully. Lambda processing should start automatically.",
        "bucket": UPLOAD_BUCKET,
        "object_key": object_key,
        "filename": file.filename,
    }
