import mimetypes
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from fastapi import FastAPI, File, HTTPException, UploadFile

from shared_config import get_settings


ALLOWED_EXTENSIONS = {
    ".csv",
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".bmp",
    ".webp",
    ".mp3",
    ".wav",
    ".m4a",
    ".aac",
    ".flac",
    ".ogg",
    ".mp4",
    ".mov",
    ".mkv",
    ".avi",
    ".webm",
}
MEDIA_EXTENSIONS = {
    ".mp3",
    ".wav",
    ".m4a",
    ".aac",
    ".flac",
    ".ogg",
    ".mp4",
    ".mov",
    ".mkv",
    ".avi",
    ".webm",
}


app = FastAPI(title="File Upload API")

settings = get_settings()
LOCALSTACK_ENDPOINT = settings.localstack_endpoint
UPLOAD_BUCKET = settings.upload_bucket
TABLE_NAME = settings.table_name
DEFAULT_TRANSCRIPTION_ENGINE = settings.default_transcription_engine


def get_s3_client():
    return boto3.client("s3", **settings.boto3_kwargs)


def get_results_table():
    dynamodb = boto3.resource("dynamodb", **settings.boto3_kwargs)
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
        "default_transcription_engine": DEFAULT_TRANSCRIPTION_ENGINE,
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

    lower_filename = file.filename.lower()

    if not any(lower_filename.endswith(extension) for extension in ALLOWED_EXTENSIONS):
        raise HTTPException(
            status_code=400,
            detail=(
                "Supported files: .csv, .png, .jpg, .jpeg, .gif, .bmp, .webp, "
                ".mp3, .wav, .m4a, .aac, .flac, .ogg, .mp4, .mov, .mkv, .avi"
            ),
        )

    object_key = f"{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S')}_{file.filename}"
    content_type = file.content_type or mimetypes.guess_type(file.filename)[0] or "application/octet-stream"
    extra_args = {"ContentType": content_type}

    is_media_file = any(lower_filename.endswith(extension) for extension in MEDIA_EXTENSIONS)
    transcription_engine = DEFAULT_TRANSCRIPTION_ENGINE if is_media_file else None
    if transcription_engine is not None:
        extra_args["Metadata"] = {"transcription_engine": transcription_engine}

    try:
        s3_client = get_s3_client()
        s3_client.upload_fileobj(
            file.file,
            UPLOAD_BUCKET,
            object_key,
            ExtraArgs=extra_args,
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
        "transcription_engine": transcription_engine,
    }
