from dataclasses import asdict, dataclass
import os


@dataclass(frozen=True)
class AwsConnectionSettings:
    endpoint_url: str
    region_name: str
    aws_access_key_id: str
    aws_secret_access_key: str


def require_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Required environment variable '{name}' is not set.")
    return value


def require_envs(*names: str) -> dict[str, str]:
    return {name: require_env(name) for name in names}


def load_localstack_aws_settings() -> AwsConnectionSettings:
    env = require_envs(
        "LOCALSTACK_ENDPOINT",
        "AWS_DEFAULT_REGION",
        "AWS_ACCESS_KEY_ID",
        "AWS_SECRET_ACCESS_KEY",
    )
    return AwsConnectionSettings(
        endpoint_url=env["LOCALSTACK_ENDPOINT"],
        region_name=env["AWS_DEFAULT_REGION"],
        aws_access_key_id=env["AWS_ACCESS_KEY_ID"],
        aws_secret_access_key=env["AWS_SECRET_ACCESS_KEY"],
    )


def boto3_kwargs(settings: AwsConnectionSettings) -> dict[str, str]:
    return asdict(settings)
