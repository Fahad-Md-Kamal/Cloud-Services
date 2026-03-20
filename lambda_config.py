import os


def require_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Required environment variable '{name}' is not set.")
    return value


TABLE_NAME = require_env("TABLE_NAME")
TRANSCRIPTION_QUEUE_NAME = require_env("TRANSCRIPTION_QUEUE_NAME")
DEFAULT_TRANSCRIPTION_ENGINE = require_env("DEFAULT_TRANSCRIPTION_ENGINE")
