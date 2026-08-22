SHELL := /bin/bash
COMPOSE := docker compose -f docker-compose.dev.yml

.DEFAULT_GOAL := help
.PHONY: help db-up db-down db-reset migrate-pet migrate-auth info validate lint db-forward db-forward-stop

help:
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

db-up: ## ยก postgres แล้ว migrate ทั้ง pet และ auth
	$(COMPOSE) up -d postgres
	$(COMPOSE) run --rm flyway-auth
	$(COMPOSE) run --rm flyway-pet

db-down: ## ปิด + ลบ volume
	$(COMPOSE) down -v

db-reset: db-down db-up ## ล้างแล้วสร้างใหม่

migrate-pet: ## migrate เฉพาะ pet
	$(COMPOSE) run --rm flyway-pet

migrate-auth: ## migrate เฉพาะ auth
	$(COMPOSE) run --rm flyway-auth

info: ## ดูสถานะ migration ทั้งสอง service
	@echo "--- pet ---"  && $(COMPOSE) run --rm flyway-pet info
	@echo "--- auth ---" && $(COMPOSE) run --rm flyway-auth info

validate: ## ตรวจ checksum
	$(COMPOSE) run --rm flyway-pet validate
	$(COMPOSE) run --rm flyway-auth validate

lint: ## ตรวจกฎพื้นฐานของไฟล์ migration
	@bash scripts/lint.sh

db-forward: ## เปิด tunnel ไป postgres ใน k8s สำหรับ DBeaver (localhost:15432)
	@bash scripts/db-forward.sh -d

db-forward-stop: ## ปิด tunnel
	@bash scripts/db-forward.sh --stop
