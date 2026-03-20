#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_CMD="${COMPOSE_CMD:-}"

if [[ -z "$COMPOSE_CMD" ]]; then
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
    else
        echo "Error: docker compose is required." >&2
        exit 1
    fi
fi

echo "Stopping LocalStack..."
$COMPOSE_CMD down --remove-orphans

echo "Removing persisted LocalStack data..."
find "$REPO_ROOT/volume" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

echo "Local environment reset complete."
echo ""
echo "Next steps:"
echo "1. make up"
echo "2. make resources"
echo "3. make deploy"
echo "4. make test"
