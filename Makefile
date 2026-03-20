SHELL := /bin/bash

AWS_ACCESS_KEY_ID := test
AWS_SECRET_ACCESS_KEY := test
AWS_DEFAULT_REGION := us-east-1
LOCALSTACK_ENDPOINT ?= http://localhost:4566
COMPOSE_CMD ?= $(shell if docker compose version >/dev/null 2>&1; then echo "docker compose"; elif command -v docker-compose >/dev/null 2>&1; then echo "docker-compose"; else echo "docker compose"; fi)

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION

.PHONY: help check up down restart clean reset health resources deploy test logs results api run setup

help:
	@echo "Available targets:"
	@echo "  make check      Verify LocalStack prerequisites"
	@echo "  make up         Start LocalStack"
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
	@echo "  make api        Run the FastAPI upload service on port 8000"
	@echo "  make run        Start the full local pipeline"
	@echo "  make setup      Alias for make run"

check:
	@bash -lc 'source scripts/common.sh && require_localstack'

up:
	@$(COMPOSE_CMD) up

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
	@bash -lc 'source scripts/common.sh && require_localstack && aws_localstack --endpoint-url="$(LOCALSTACK_ENDPOINT)" dynamodb scan --table-name file-processing-results'

api:
	@python3 -m uvicorn app.api:app --host 0.0.0.0 --port 8000 --reload

run: up resources deploy

setup: run
