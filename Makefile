# The one interface the harness, CI and Cristian use. Every target exits 0 on
# today's repository, fails loudly (non-zero) on a real failure, and prints a
# "skip:" line for each part of the stack that does not exist yet.

SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help
MAKEFLAGS += --no-print-directory

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
COMPOSE_FILE := $(firstword $(wildcard $(ROOT)/docker-compose.yml $(ROOT)/compose.yaml))

.PHONY: help check check-infra test e2e up down harness-test spec-lint

help: ## List the targets
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  make %-13s %s\n", $$1, $$2}'

check: harness-test ## Harness tests, then gofmt + go vet (src/api), lint + typecheck (src/web)
	@if [ -d src/api ]; then \
	  echo "check: src/api/"; \
	  unformatted="$$(gofmt -l src/api)"; \
	  if [ -n "$$unformatted" ]; then echo "gofmt -l lists unformatted files:"; echo "$$unformatted"; exit 1; fi; \
	  (cd src/api && go vet ./...); \
	else echo "skip: src/api/ (does not exist yet)"; fi
	@if [ -d src/web ]; then \
	  echo "check: src/web/"; \
	  (cd src/web && npm run lint && npm run typecheck); \
	else echo "skip: src/web/ (does not exist yet)"; fi

# Separate from check because terraform cannot run inside the macOS sandbox
# (TLS verification and provider plugins fail): "make check-infra" is in
# sandbox.excludedCommands, "make check" is not. TF_DATA_DIR keeps validation
# away from a folder's own .terraform/, whose initialized backend (the S3
# state of bootstrap/) would need AWS credentials even with -backend=false.
check-infra: ## terraform fmt -check, then init -backend=false + validate in every src/infra folder with .tf files
	@if [ -d src/infra ]; then \
	  export TF_DATA_DIR=.terraform/check-infra; \
	  echo "check-infra: src/infra/"; \
	  terraform -chdir=src/infra fmt -check -recursive; \
	  for dir in $$(find src/infra -name '*.tf' -not -path '*/.terraform/*' -exec dirname {} \; | sort -u); do \
	    echo "check-infra: $$dir/"; \
	    (cd "$$dir" && terraform init -backend=false -input=false >/dev/null && terraform validate); \
	  done; \
	else echo "skip: src/infra/ (does not exist yet)"; fi

test: ## go test -race (src/api), npm test (src/web)
	@if [ -d src/api ]; then \
	  echo "test: src/api/"; \
	  (cd src/api && go test -race -count=1 ./...); \
	else echo "skip: src/api/ (does not exist yet)"; fi
	@if [ -d src/web ]; then \
	  echo "test: src/web/"; \
	  (cd src/web && npm test -- --run); \
	else echo "skip: src/web/ (does not exist yet)"; fi

e2e: ## Playwright in src/e2e/ against the local stack
	@if [ -d src/e2e ]; then \
	  echo "e2e: src/e2e/"; \
	  (cd src/e2e && npx playwright test); \
	else echo "skip: src/e2e/ (does not exist yet)"; fi

up: ## Start the local stack (docker compose up -d --wait)
	@if [ -n "$(COMPOSE_FILE)" ]; then \
	  docker compose -f "$(COMPOSE_FILE)" up -d --wait; \
	else echo "skip: docker-compose.yml (does not exist yet)"; fi

down: ## Stop the local stack, keeping its volumes (never -v)
	@if [ -n "$(COMPOSE_FILE)" ]; then \
	  docker compose -f "$(COMPOSE_FILE)" down; \
	else echo "skip: docker-compose.yml (does not exist yet)"; fi

harness-test: ## Tests of the hooks, change-guard, plan-guard and spec-lint
	@bash .claude/hooks/guard_test.sh
	@bash tools/change-guard_test.sh
	@bash tools/plan-guard_test.sh
	@cd tools/spec-lint && go test -count=1 ./...

spec-lint: ## Lint openspec/ (spec format rules L1-L8)
	@go -C tools/spec-lint run . "$(ROOT)/openspec"
