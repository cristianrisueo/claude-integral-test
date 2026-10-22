# The one interface the harness, CI and Cristian use. Every target exits 0 on
# today's repository, fails loudly (non-zero) on a real failure, and prints a
# "skip:" line for each part of the stack that does not exist yet.

SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help
MAKEFLAGS += --no-print-directory

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
COMPOSE_FILE := $(firstword $(wildcard $(ROOT)/docker-compose.yml $(ROOT)/compose.yaml))

.PHONY: help check test e2e up down harness-test spec-lint

help: ## List the targets
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  make %-13s %s\n", $$1, $$2}'

check: harness-test ## Harness tests, then gofmt + go vet (api), lint + typecheck (web), terraform fmt + validate (infra)
	@if [ -d api ]; then \
	  echo "check: api/"; \
	  unformatted="$$(gofmt -l api)"; \
	  if [ -n "$$unformatted" ]; then echo "gofmt -l lists unformatted files:"; echo "$$unformatted"; exit 1; fi; \
	  (cd api && go vet ./...); \
	else echo "skip: api/ (does not exist yet)"; fi
	@if [ -d web ]; then \
	  echo "check: web/"; \
	  (cd web && npm run lint && npm run typecheck); \
	else echo "skip: web/ (does not exist yet)"; fi
	@if [ -d infra ]; then \
	  echo "check: infra/"; \
	  (cd infra && terraform fmt -check -recursive && terraform init -backend=false -input=false >/dev/null && terraform validate); \
	else echo "skip: infra/ (does not exist yet)"; fi

test: ## go test -race (api), npm test (web)
	@if [ -d api ]; then \
	  echo "test: api/"; \
	  (cd api && go test -race -count=1 ./...); \
	else echo "skip: api/ (does not exist yet)"; fi
	@if [ -d web ]; then \
	  echo "test: web/"; \
	  (cd web && npm test -- --run); \
	else echo "skip: web/ (does not exist yet)"; fi

e2e: ## Playwright in e2e/ against the local stack
	@if [ -d e2e ]; then \
	  echo "e2e: e2e/"; \
	  (cd e2e && npx playwright test); \
	else echo "skip: e2e/ (does not exist yet)"; fi

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
