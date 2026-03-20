from functools import lru_cache
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    localstack_endpoint: str
    aws_default_region: str
    aws_access_key_id: str
    aws_secret_access_key: str
    upload_bucket: str
    processed_bucket: str
    table_name: str
    transcription_queue_name: str
    default_transcription_engine: Literal["openai", "whisper-large-v3", "tiny"]
    whisper_tiny_model: str
    whisper_large_v3_model: str
    whisper_compute_type: str
    whisper_download_root: str
    openai_transcription_model: str
    openai_api_key: str | None = None
    transcription_visibility_timeout_seconds: int
    transcription_poll_wait_seconds: int
    lambda_function_name: str
    lambda_role_name: str
    localstack_container: str
    localstack_docker_endpoint: str

    @property
    def boto3_kwargs(self) -> dict[str, str]:
        return {
            "endpoint_url": self.localstack_endpoint,
            "region_name": self.aws_default_region,
            "aws_access_key_id": self.aws_access_key_id,
            "aws_secret_access_key": self.aws_secret_access_key,
        }


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
