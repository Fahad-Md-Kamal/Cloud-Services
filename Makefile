SHELL := /bin/bash

ifneq ("$(wildcard .env)","")
include .env
export
else
$(error .env file not found. Copy .env.example to .env and set the required values.)
endif

COMPOSE_CMD ?= $(shell if docker compose version >/dev/null 2>&1; then echo "docker compose"; elif command -v docker-compose >/dev/null 2>&1; then echo "docker-compose"; else echo "docker compose"; fi)

.PHONY: help check build up down restart clean reset health resources deploy test logs results api api-local api-logs transcriber rebuild-transcriber transcriber-logs run setup

help:
	@echo "Available targets:"
	@echo "  make check      Verify LocalStack prerequisites"
	@echo "  make build      Build the API and transcriber Docker images"
	@echo "  make up         Start LocalStack, API, and transcriber containers"
	@echo "  make down       Stop LocalStack"
	@echo "  make restart    Restart LocalStack"
	@echo "  make clean      Stop LocalStack and delete persisted local data"
	@echo "  make reset      Rebuild the full local pipeline from a clean state"
	@echo "  make health     Check LocalStack health"
	@echo "  make resources  Create S3, DynamoDB, and IAM resources"
	@echo "  make deploy     Deploy the Lambda function"
	@echo "  make test       Upload the sample CSV and inspect results"
	@echo "  make logs       List LocalStack log groups"
	@echo "  make results    Show DynamoDB processing results"
	@echo "  make api        Start only the FastAPI container"
	@echo "  make api-local  Run the FastAPI service locally with Python"
	@echo "  make api-logs   Show FastAPI container logs"
	@echo "  make transcriber  Start only the media transcriber container"
	@echo "  make rebuild-transcriber  Rebuild and restart the media transcriber"
	@echo "  make transcriber-logs  Show media transcriber container logs"
	@echo "  make run        Start the full local pipeline"
	@echo "  make setup      Alias for make run"

build:
	@$(COMPOSE_CMD) build api transcriber

check:
	@bash -lc 'source scripts/common.sh && require_localstack'

up:
	@$(COMPOSE_CMD) up -d

down:
	@$(COMPOSE_CMD) down

restart: down up

clean:
	@bash ./scripts/reset_environment.sh

reset: clean up resources deploy

health:
	@curl -fsS $(LOCALSTACK_ENDPOINT)/_localstack/health

resources:
	@bash ./scripts/create_resources.sh

deploy: resources
	@bash ./scripts/deploy_lambda.sh

test:
	@bash ./scripts/upload_test_file.sh

logs:
	@bash -lc 'source scripts/common.sh && require_localstack && aws_localstack --endpoint-url="$(LOCALSTACK_ENDPOINT)" logs describe-log-groups'

results:
	@bash -lc 'source scripts/common.sh && require_localstack && require_env TABLE_NAME && aws_localstack --endpoint-url="$(LOCALSTACK_ENDPOINT)" dynamodb scan --table-name "$$TABLE_NAME"'

api:
	@$(COMPOSE_CMD) up -d api

api-local:
	@bash -lc 'set -a && source .env && set +a && python3 -m uvicorn app.api:app --host 0.0.0.0 --port 8000 --reload'

api-logs:
	@$(COMPOSE_CMD) logs -f api

transcriber:
	@$(COMPOSE_CMD) up -d transcriber

rebuild-transcriber:
	@$(COMPOSE_CMD) build transcriber
	@$(COMPOSE_CMD) up -d transcriber

transcriber-logs:
	@$(COMPOSE_CMD) logs -f transcriber

run: up resources deploy

setup: run
