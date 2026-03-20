import csv
import json
import logging
import struct
from datetime import datetime
from urllib.parse import unquote_plus

import boto3
from lambda_config import DEFAULT_TRANSCRIPTION_ENGINE, TABLE_NAME, TRANSCRIPTION_QUEUE_NAME


logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3_client = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
sqs_client = boto3.client("sqs")

CSV_EXTENSIONS = {".csv"}
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp"}
AUDIO_EXTENSIONS = {".mp3", ".wav", ".m4a", ".aac", ".flac", ".ogg"}
VIDEO_EXTENSIONS = {".mp4", ".mov", ".mkv", ".avi", ".webm"}


def lambda_handler(event, context):
    """
    Process supported uploads from S3 and store extracted metadata in DynamoDB.
    """
    try:
        for record in event["Records"]:
            bucket = record["s3"]["bucket"]["name"]
            key = unquote_plus(record["s3"]["object"]["key"])

            logger.info("Processing file: %s from bucket: %s", key, bucket)

            if has_extension(key, CSV_EXTENSIONS):
                result = process_csv_file(bucket, key)
            elif has_extension(key, IMAGE_EXTENSIONS):
                result = process_image_file(bucket, key)
            elif has_extension(key, AUDIO_EXTENSIONS):
                result = queue_transcription_job(bucket, key, "audio")
            elif has_extension(key, VIDEO_EXTENSIONS):
                result = queue_transcription_job(bucket, key, "video")
            else:
                logger.warning("Skipping unsupported file: %s", key)
                continue

            store_results(result)
            logger.info("Successfully processed file: %s", key)

        return {
            "statusCode": 200,
            "body": json.dumps("Files processed successfully"),
        }
    except Exception as exc:
        logger.error("Error processing files: %s", exc)
        return {
            "statusCode": 500,
            "body": json.dumps(f"Error processing files: {exc}"),
        }


def has_extension(key, extensions):
    lower_key = key.lower()
    return any(lower_key.endswith(extension) for extension in extensions)


def base_result(bucket, key, file_type, file_size, content_type):
    timestamp = datetime.utcnow().isoformat()
    return {
        "file_id": key,
        "bucket": bucket,
        "object_key": key,
        "file_type": file_type,
        "content_type": content_type,
        "uploaded_at": timestamp,
        "processed_at": timestamp,
        "file_size": file_size,
        "status": "success",
        "error_message": None,
    }


def get_s3_object_metadata(bucket, key):
    return s3_client.head_object(Bucket=bucket, Key=key)


def get_s3_object(bucket, key):
    response = s3_client.get_object(Bucket=bucket, Key=key)
    body = response["Body"].read()
    return body, response


def process_csv_file(bucket, key):
    """
    Download and analyze CSV file from S3.
    """
    try:
        file_bytes, response = get_s3_object(bucket, key)
        file_content = file_bytes.decode("utf-8")
        file_size = response["ContentLength"]
        content_type = response.get("ContentType", "text/csv")

        csv_reader = csv.reader(file_content.splitlines())
        headers = next(csv_reader, [])
        rows = list(csv_reader)

        row_count = len(rows)
        column_count = len(headers)

        result = base_result(bucket, key, "csv", file_size, content_type)
        result.update(
            {
                "row_count": row_count,
                "column_count": column_count,
                "headers": headers,
            }
        )

        logger.info("CSV analysis complete - Rows: %s, Columns: %s", row_count, column_count)
        return result
    except Exception as exc:
        return build_error_result(bucket, key, "csv", f"Error processing CSV file: {exc}")


def process_image_file(bucket, key):
    """
    Download and analyze image file from S3.
    """
    try:
        file_bytes, response = get_s3_object(bucket, key)
        file_size = response["ContentLength"]
        content_type = response.get("ContentType", "application/octet-stream")
        image_metadata = extract_image_metadata(file_bytes)

        result = base_result(bucket, key, "image", file_size, content_type)
        result.update(image_metadata)

        logger.info(
            "Image analysis complete - Format: %s, Width: %s, Height: %s",
            image_metadata["image_format"],
            image_metadata["width"],
            image_metadata["height"],
        )
        return result
    except Exception as exc:
        return build_error_result(bucket, key, "image", f"Error processing image file: {exc}")


def queue_transcription_job(bucket, key, file_type):
    """
    Store an initial queued record and hand off heavy transcription work to the worker queue.
    """
    try:
        metadata = get_s3_object_metadata(bucket, key)
        file_size = metadata["ContentLength"]
        content_type = metadata.get("ContentType", "application/octet-stream")
        object_metadata = metadata.get("Metadata", {})
        transcription_engine = object_metadata.get("transcription_engine") or DEFAULT_TRANSCRIPTION_ENGINE

        result = base_result(bucket, key, file_type, file_size, content_type)
        result.update(
            {
                "status": "queued",
                "progress_percent": 0,
                "transcription_engine": transcription_engine,
                "transcript": None,
                "transcript_bucket": None,
                "transcript_key": None,
                "transcription_language": None,
                "media_duration_seconds": None,
            }
        )

        queue_url = sqs_client.get_queue_url(QueueName=TRANSCRIPTION_QUEUE_NAME)["QueueUrl"]
        sqs_client.send_message(
            QueueUrl=queue_url,
            MessageBody=json.dumps(
                {
                    "bucket": bucket,
                    "object_key": key,
                    "file_type": file_type,
                    "transcription_engine": transcription_engine,
                }
            ),
        )

        logger.info("Queued %s transcription job for file: %s", file_type, key)
        return result
    except Exception as exc:
        return build_error_result(bucket, key, file_type, f"Error queueing transcription job: {exc}")


def build_error_result(bucket, key, file_type, error_message):
    logger.error(error_message)
    result = base_result(bucket, key, file_type, 0, None)
    result.update({"status": "error", "error_message": error_message})
    return result


def extract_image_metadata(file_bytes):
    if file_bytes.startswith(b"\x89PNG\r\n\x1a\n"):
        width, height = struct.unpack(">II", file_bytes[16:24])
        return {"image_format": "PNG", "width": width, "height": height}

    if file_bytes.startswith(b"\xff\xd8"):
        return parse_jpeg_metadata(file_bytes)

    if file_bytes.startswith((b"GIF87a", b"GIF89a")):
        width, height = struct.unpack("<HH", file_bytes[6:10])
        return {"image_format": "GIF", "width": width, "height": height}

    if file_bytes.startswith(b"BM"):
        width, height = struct.unpack("<II", file_bytes[18:26])
        return {"image_format": "BMP", "width": width, "height": abs(height)}

    if file_bytes.startswith(b"RIFF") and file_bytes[8:12] == b"WEBP":
        return parse_webp_metadata(file_bytes)

    raise ValueError("Unsupported image format")


def parse_jpeg_metadata(file_bytes):
    index = 2
    while index < len(file_bytes):
        if file_bytes[index] != 0xFF:
            index += 1
            continue

        while index < len(file_bytes) and file_bytes[index] == 0xFF:
            index += 1

        if index >= len(file_bytes):
            break

        marker = file_bytes[index]
        index += 1

        if marker in {0xD8, 0xD9}:
            continue

        if index + 2 > len(file_bytes):
            break

        segment_length = struct.unpack(">H", file_bytes[index:index + 2])[0]
        if segment_length < 2:
            break

        if marker in {
            0xC0,
            0xC1,
            0xC2,
            0xC3,
            0xC5,
            0xC6,
            0xC7,
            0xC9,
            0xCA,
            0xCB,
            0xCD,
            0xCE,
            0xCF,
        }:
            if index + 7 > len(file_bytes):
                break
            height, width = struct.unpack(">HH", file_bytes[index + 3:index + 7])
            return {"image_format": "JPEG", "width": width, "height": height}

        index += segment_length

    raise ValueError("Invalid JPEG metadata")


def parse_webp_metadata(file_bytes):
    chunk_header = file_bytes[12:16]

    if chunk_header == b"VP8 ":
        if len(file_bytes) < 30:
            raise ValueError("Invalid WEBP metadata")
        width, height = struct.unpack("<HH", file_bytes[26:30])
        return {"image_format": "WEBP", "width": width & 0x3FFF, "height": height & 0x3FFF}

    if chunk_header == b"VP8L":
        if len(file_bytes) < 25:
            raise ValueError("Invalid WEBP metadata")
        b0, b1, b2, b3 = file_bytes[21:25]
        width = 1 + (((b1 & 0x3F) << 8) | b0)
        height = 1 + (((b3 & 0x0F) << 10) | (b2 << 2) | ((b1 & 0xC0) >> 6))
        return {"image_format": "WEBP", "width": width, "height": height}

    if chunk_header == b"VP8X":
        if len(file_bytes) < 30:
            raise ValueError("Invalid WEBP metadata")
        width_bytes = file_bytes[24:27]
        height_bytes = file_bytes[27:30]
        width = 1 + int.from_bytes(width_bytes, "little")
        height = 1 + int.from_bytes(height_bytes, "little")
        return {"image_format": "WEBP", "width": width, "height": height}

    raise ValueError("Unsupported WEBP metadata")


def store_results(result):
    """
    Store processing results in DynamoDB.
    """
    try:
        table = dynamodb.Table(TABLE_NAME)
        table.put_item(Item=result)
        logger.info("Results stored in DynamoDB for file: %s", result["file_id"])
    except Exception as exc:
        logger.error("Error storing results in DynamoDB: %s", exc)
        raise
