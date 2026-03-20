#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    echo "Error: $ENV_FILE not found. Copy .env.example to .env and set the required values." >&2
    exit 1
fi

require_env() {
    local name="$1"
    if [[ -z "${!name:-}" ]]; then
        echo "Error: required environment variable '$name' is not set." >&2
        exit 1
    fi
}

require_env LOCALSTACK_CONTAINER
require_env LOCALSTACK_ENDPOINT
require_env AWS_ACCESS_KEY_ID
require_env AWS_SECRET_ACCESS_KEY
require_env AWS_DEFAULT_REGION

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION
export LOCALSTACK_CONTAINER
export LOCALSTACK_ENDPOINT

aws_localstack_mode() {
    if [[ -n "${AWS_LOCALSTACK_MODE:-}" ]]; then
        printf '%s\n' "$AWS_LOCALSTACK_MODE"
        return
    fi

    if command -v aws >/dev/null 2>&1; then
        AWS_LOCALSTACK_MODE="host-aws"
    elif command -v awslocal >/dev/null 2>&1; then
        AWS_LOCALSTACK_MODE="host-awslocal"
    elif command -v docker >/dev/null 2>&1; then
        AWS_LOCALSTACK_MODE="docker-awslocal"
    else
        AWS_LOCALSTACK_MODE="unavailable"
    fi

    export AWS_LOCALSTACK_MODE
    printf '%s\n' "$AWS_LOCALSTACK_MODE"
}

aws_localstack() {
    case "$(aws_localstack_mode)" in
    host-aws)
        aws "$@"
        ;;
    host-awslocal)
        awslocal "$@"
        ;;
    docker-awslocal)
        docker exec \
            -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
            -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
            -e AWS_DEFAULT_REGION="$AWS_DEFAULT_REGION" \
            "$LOCALSTACK_CONTAINER" \
            awslocal "$@"
        ;;
    *)
        echo "Error: neither aws nor awslocal is installed, and docker fallback is unavailable." >&2
        return 1
        ;;
    esac
}

aws_localstack_stage_file() {
    local source_path="$1"

    if [[ ! -f "$source_path" ]]; then
        echo "Error: file not found: $source_path" >&2
        return 1
    fi

    case "$(aws_localstack_mode)" in
    docker-awslocal)
        local target_path="/tmp/$(basename "$source_path").$$"
        docker cp "$source_path" "$LOCALSTACK_CONTAINER:$target_path" >/dev/null
        printf '%s\n' "$target_path"
        ;;
    *)
        printf '%s\n' "$source_path"
        ;;
    esac
}

aws_localstack_unstage_file() {
    local staged_path="$1"

    if [[ "$(aws_localstack_mode)" == "docker-awslocal" ]]; then
        docker exec "$LOCALSTACK_CONTAINER" rm -f "$staged_path" >/dev/null
    fi
}

aws_localstack_s3_upload() {
    local source_path="$1"
    local destination="$2"

    if [[ ! -f "$source_path" ]]; then
        echo "Error: file not found: $source_path" >&2
        return 1
    fi

    case "$(aws_localstack_mode)" in
    docker-awslocal)
        docker exec \
            -i \
            -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
            -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
            -e AWS_DEFAULT_REGION="$AWS_DEFAULT_REGION" \
            "$LOCALSTACK_CONTAINER" \
            awslocal --endpoint-url="$LOCALSTACK_ENDPOINT" s3 cp - "$destination" < "$source_path"
        ;;
    *)
        aws_localstack --endpoint-url="$LOCALSTACK_ENDPOINT" s3 cp "$source_path" "$destination"
        ;;
    esac
}

require_localstack() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "Error: docker is required to run LocalStack." >&2
        return 1
    fi

    if ! docker ps --format '{{.Names}}' | grep -Fxq "$LOCALSTACK_CONTAINER"; then
        echo "Error: LocalStack container '$LOCALSTACK_CONTAINER' is not running." >&2
        echo "Start it with: make up" >&2
        return 1
    fi
}
