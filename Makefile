# OttoChain Deployment - Docker Compose Helpers
# Run 'make help' for usage

.PHONY: help up down logs ps build clean
.PHONY: base services explorer monitoring full traffic metagraph-genesis metagraph-validator

# Compose file directory
C := compose

help:
	@echo "OttoChain Deployment - Layered Docker Compose"
	@echo ""
	@echo "PROFILES (use with 'make <profile>'):"
	@echo "  base              - Infrastructure only (Redis, Postgres)"
	@echo "  services          - Base + app services (Gateway, Bridge, Indexer, Monitor)"
	@echo "  explorer          - Base + services + explorer UI"
	@echo "  monitoring        - Base + Prometheus/Grafana/Alertmanager"
	@echo "  full              - Everything except metagraph"
	@echo "  traffic           - Services + traffic generator"
	@echo ""
	@echo "METAGRAPH (requires NODE_IP, optionally GENESIS_IP):"
	@echo "  metagraph-genesis   - Start genesis node (all 5 layers)"
	@echo "  metagraph-validator - Start validator node (all 5 layers)"
	@echo ""
	@echo "COMMANDS:"
	@echo "  up                - Alias for 'make services'"
	@echo "  down              - Stop all containers"
	@echo "  logs              - Follow logs (use SERVICES='svc1 svc2' to filter)"
	@echo "  ps                - List running containers"
	@echo "  clean             - Stop all and remove volumes"
	@echo ""
	@echo "ENVIRONMENT:"
	@echo "  cp envs/local.env .env      # Local development"
	@echo "  cp envs/testnet.env .env    # Hetzner testnet"
	@echo ""
	@echo "EXAMPLES:"
	@echo "  make services                    # Start dev environment"
	@echo "  make full                        # Start everything"
	@echo "  make logs SERVICES='gateway'     # Follow gateway logs"
	@echo "  NODE_IP=1.2.3.4 make metagraph-genesis"

# ===== Infrastructure Profiles =====
base:
	docker compose -f $(C)/base.yml up -d

services:
	docker compose -f $(C)/base.yml -f $(C)/services.yml up -d

explorer:
	docker compose -f $(C)/base.yml -f $(C)/services.yml -f $(C)/explorer.yml up -d

monitoring:
	docker compose -f $(C)/base.yml -f $(C)/monitoring.yml up -d

full:
	docker compose -f $(C)/base.yml -f $(C)/services.yml -f $(C)/explorer.yml -f $(C)/monitoring.yml -f $(C)/exporters.yml up -d

full-logging:
	docker compose -f $(C)/base.yml -f $(C)/services.yml -f $(C)/explorer.yml -f $(C)/monitoring.yml -f $(C)/exporters.yml -f $(C)/logging.yml up -d

traffic:
	docker compose -f $(C)/base.yml -f $(C)/services.yml -f $(C)/traffic.yml up -d

# ===== Metagraph =====
metagraph-genesis:
	@if [ -z "$(NODE_IP)" ]; then echo "ERROR: NODE_IP required"; exit 1; fi
	NODE_IP=$(NODE_IP) docker compose -f $(C)/metagraph.yml --profile genesis up -d

metagraph-validator:
	@if [ -z "$(NODE_IP)" ]; then echo "ERROR: NODE_IP required"; exit 1; fi
	@if [ -z "$(GENESIS_IP)" ]; then echo "ERROR: GENESIS_IP required"; exit 1; fi
	NODE_IP=$(NODE_IP) GENESIS_IP=$(GENESIS_IP) docker compose -f $(C)/metagraph.yml --profile validator up -d

metagraph-down:
	docker compose -f $(C)/metagraph.yml --profile genesis --profile validator down

# ===== Convenience =====
up: services

down:
	docker compose -f $(C)/base.yml -f $(C)/services.yml -f $(C)/explorer.yml -f $(C)/monitoring.yml -f $(C)/exporters.yml -f $(C)/logging.yml -f $(C)/traffic.yml down 2>/dev/null || true

logs:
	docker compose -f $(C)/base.yml -f $(C)/services.yml -f $(C)/monitoring.yml logs -f $(SERVICES)

ps:
	docker compose -f $(C)/base.yml -f $(C)/services.yml -f $(C)/monitoring.yml -f $(C)/exporters.yml ps

clean: down metagraph-down
	docker compose -f $(C)/base.yml down -v 2>/dev/null || true
	docker volume prune -f

# ===== Build =====
build:
	docker compose -f $(C)/base.yml -f $(C)/services.yml build

pull:
	docker compose -f $(C)/base.yml -f $(C)/services.yml -f $(C)/explorer.yml -f $(C)/monitoring.yml pull

# ===== Environment Setup =====
env-local:
	cp envs/local.env .env
	@echo "Loaded local environment"

env-testnet:
	cp envs/testnet.env .env
	@echo "Loaded testnet environment - edit .env to set passwords"

# ===== Network =====
network:
	docker network create ottochain 2>/dev/null || true
	docker network create monitoring 2>/dev/null || true
