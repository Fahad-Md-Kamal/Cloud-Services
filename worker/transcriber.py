import json
import logging
import os
import subprocess
import tempfile
import time
from decimal import Decimal
from pathlib import Path

import boto3
from faster_whisper import WhisperModel
from openai import OpenAI
from shared_config import boto3_kwargs, load_localstack_aws_settings, require_envs


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("transcriber")

AWS_SETTINGS = load_localstack_aws_settings()
WORKER_ENV = require_envs(
    "TRANSCRIPTION_QUEUE_NAME",
    "TABLE_NAME",
    "PROCESSED_BUCKET",
    "WHISPER_TINY_MODEL",
    "WHISPER_LARGE_V3_MODEL",
    "WHISPER_COMPUTE_TYPE",
    "WHISPER_DOWNLOAD_ROOT",
    "OPENAI_TRANSCRIPTION_MODEL",
)
QUEUE_NAME = WORKER_ENV["TRANSCRIPTION_QUEUE_NAME"]
TABLE_NAME = WORKER_ENV["TABLE_NAME"]
PROCESSED_BUCKET = WORKER_ENV["PROCESSED_BUCKET"]
WHISPER_TINY_MODEL = WORKER_ENV["WHISPER_TINY_MODEL"]
WHISPER_LARGE_V3_MODEL = WORKER_ENV["WHISPER_LARGE_V3_MODEL"]
WHISPER_COMPUTE_TYPE = WORKER_ENV["WHISPER_COMPUTE_TYPE"]
WHISPER_DOWNLOAD_ROOT = WORKER_ENV["WHISPER_DOWNLOAD_ROOT"]
OPENAI_TRANSCRIPTION_MODEL = WORKER_ENV["OPENAI_TRANSCRIPTION_MODEL"]
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

s3_client = boto3.client("s3", **boto3_kwargs(AWS_SETTINGS))

sqs_client = boto3.client("sqs", **boto3_kwargs(AWS_SETTINGS))

dynamodb = boto3.resource("dynamodb", **boto3_kwargs(AWS_SETTINGS))

table = dynamodb.Table(TABLE_NAME)
whisper_models = {}
openai_client = None


def get_queue_url():
    return sqs_client.get_queue_url(QueueName=QUEUE_NAME)["QueueUrl"]


def get_model():
    return get_whisper_model(WHISPER_TINY_MODEL)


def get_whisper_model(model_name):
    if model_name not in whisper_models:
        logger.info("Loading Whisper model: %s", model_name)
        whisper_models[model_name] = WhisperModel(
            model_name,
            device="cpu",
            compute_type=WHISPER_COMPUTE_TYPE,
            download_root=WHISPER_DOWNLOAD_ROOT,
        )
    return whisper_models[model_name]


def get_openai_client():
    global openai_client
    if not OPENAI_API_KEY:
        raise RuntimeError("OPENAI_API_KEY is not configured for the transcriber worker.")
    if openai_client is None:
        openai_client = OpenAI(api_key=OPENAI_API_KEY)
    return openai_client


def normalize_media_to_wav(source_path, output_path):
    command = [
        "ffmpeg",
        "-y",
        "-i",
        source_path,
        "-vn",
        "-acodec",
        "pcm_s16le",
        "-ar",
        "16000",
        "-ac",
        "1",
        output_path,
    ]
    subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def probe_duration_seconds(source_path):
    command = [
        "ffprobe",
        "-v",
        "error",
        "-show_entries",
        "format=duration",
        "-of",
        "default=noprint_wrappers=1:nokey=1",
        source_path,
    ]
    result = subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    duration = result.stdout.strip()
    if not duration:
        return None
    return Decimal(f"{float(duration):.3f}")


def transcript_object_key(object_key):
    safe_name = object_key.replace("/", "_")
    return f"transcripts/{safe_name}.json"


def store_transcript_artifact(bucket, object_key, payload):
    key = transcript_object_key(object_key)
    s3_client.put_object(
        Bucket=PROCESSED_BUCKET,
        Key=key,
        Body=json.dumps(payload).encode("utf-8"),
        ContentType="application/json",
    )
    return PROCESSED_BUCKET, key


def mark_job_failed(object_key, error_message):
    logger.error("Transcription failed for %s: %s", object_key, error_message)
    table.update_item(
        Key={"file_id": object_key},
        UpdateExpression="""
            SET #status = :status,
                error_message = :error_message,
                processed_at = :processed_at
        """,
        ExpressionAttributeNames={"#status": "status"},
        ExpressionAttributeValues={
            ":status": "error",
            ":error_message": error_message,
            ":processed_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        },
    )


def update_transcript_record(job, transcript_text, language, duration_seconds, transcript_bucket, transcript_key):
    expression_values = {
        ":status": "success",
        ":transcript": transcript_text,
        ":language": language,
        ":processed_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        ":transcript_bucket": transcript_bucket,
        ":transcript_key": transcript_key,
        ":transcription_engine": job["transcription_engine"],
    }

    update_expression = """
        SET #status = :status,
            transcript = :transcript,
            transcription_language = :language,
            transcription_engine = :transcription_engine,
            processed_at = :processed_at,
            transcript_bucket = :transcript_bucket,
            transcript_key = :transcript_key,
            error_message = :empty_error
    """
    expression_values[":empty_error"] = None

    if duration_seconds is not None:
        update_expression += ", media_duration_seconds = :media_duration_seconds"
        expression_values[":media_duration_seconds"] = duration_seconds

    table.update_item(
        Key={"file_id": job["object_key"]},
        UpdateExpression=update_expression,
        ExpressionAttributeNames={"#status": "status"},
        ExpressionAttributeValues=expression_values,
    )


def transcribe_with_whisper(audio_path, transcription_engine):
    model_name = WHISPER_LARGE_V3_MODEL if transcription_engine == "whisper-large-v3" else WHISPER_TINY_MODEL
    model = get_whisper_model(model_name)
    segments, info = model.transcribe(str(audio_path), vad_filter=True)
    segment_text = [segment.text.strip() for segment in segments if segment.text.strip()]
    transcript_text = " ".join(segment_text).strip()
    return transcript_text, info.language


def transcribe_with_openai(audio_path):
    client = get_openai_client()
    with open(audio_path, "rb") as audio_file:
        response = client.audio.transcriptions.create(
            model=OPENAI_TRANSCRIPTION_MODEL,
            file=audio_file,
            response_format="verbose_json",
        )

    transcript_text = getattr(response, "text", None)
    language = getattr(response, "language", None)

    if transcript_text is None and isinstance(response, dict):
        transcript_text = response.get("text", "")
    if language is None and isinstance(response, dict):
        language = response.get("language")

    transcript_text = transcript_text or ""
    return transcript_text.strip(), language


def transcribe_job(job):
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        source_path = temp_path / Path(job["object_key"]).name
        audio_path = temp_path / "normalized.wav"

        s3_client.download_file(job["bucket"], job["object_key"], str(source_path))
        normalize_media_to_wav(str(source_path), str(audio_path))
        duration_seconds = probe_duration_seconds(str(audio_path))

        if job["transcription_engine"] == "openai":
            transcript_text, language = transcribe_with_openai(str(audio_path))
        else:
            transcript_text, language = transcribe_with_whisper(str(audio_path), job["transcription_engine"])

        transcript_payload = {
            "bucket": job["bucket"],
            "object_key": job["object_key"],
            "file_type": job["file_type"],
            "language": language,
            "transcription_engine": job["transcription_engine"],
            "duration_seconds": float(duration_seconds) if duration_seconds is not None else None,
            "transcript": transcript_text,
        }
        transcript_bucket, transcript_key = store_transcript_artifact(
            job["bucket"], job["object_key"], transcript_payload
        )

        update_transcript_record(
            job,
            transcript_text,
            language,
            duration_seconds,
            transcript_bucket,
            transcript_key,
        )
        logger.info("Stored transcript for %s", job["object_key"])


def process_message(message):
    body = json.loads(message["Body"])
    if not body.get("transcription_engine"):
        raise ValueError("Queue message is missing required transcription_engine.")
    transcribe_job(body)


def run():
    queue_url = get_queue_url()
    logger.info("Polling queue: %s", queue_url)

    while True:
        response = sqs_client.receive_message(
            QueueUrl=queue_url,
            MaxNumberOfMessages=1,
            WaitTimeSeconds=20,
            VisibilityTimeout=120,
        )

        messages = response.get("Messages", [])
        if not messages:
            continue

        for message in messages:
            try:
                process_message(message)
                sqs_client.delete_message(
                    QueueUrl=queue_url,
                    ReceiptHandle=message["ReceiptHandle"],
                )
            except Exception as exc:
                body = json.loads(message["Body"])
                mark_job_failed(body["object_key"], str(exc))
                sqs_client.delete_message(
                    QueueUrl=queue_url,
                    ReceiptHandle=message["ReceiptHandle"],
                )


if __name__ == "__main__":
    run()
