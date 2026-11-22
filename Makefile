# Comandos do projeto. O CI chama exatamente estes alvos, então o que passa
# aqui passa lá. Terraform, Helm, promtool e kubeconform rodam via Docker.
SHELL := /bin/bash
.DEFAULT_GOAL := help

TERRAFORM_IMAGE   := hashicorp/terraform:1.10.5
HELM_IMAGE        := alpine/helm:3.17.0
KUBECONFORM_IMAGE := ghcr.io/yannh/kubeconform:v0.6.7
PROMETHEUS_IMAGE  := prom/prometheus:v3.1.0
KONG_IMAGE        := kong:3.9.1
K8S_VERSION       := 1.31.0
# Schemas de CRDs (ServiceMonitor) do catálogo comunitário.
CRDS_SCHEMA_LOCATION := https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json

TF_DIRS := modules/keycloak-realm modules/vault-edge envs/local
CHART   := edge-gateway
CHART_VALUES_VARIANTS := default ci/production-values.yaml ci/inline-config-values.yaml

DOCKER_RUN := docker run --rm
TERRAFORM  := $(DOCKER_RUN) -v $(CURDIR)/terraform:/terraform -w /terraform $(TERRAFORM_IMAGE)
HELM       := $(DOCKER_RUN) -v $(CURDIR)/charts:/charts -w /charts $(HELM_IMAGE)
PROMTOOL   := $(DOCKER_RUN) -v $(CURDIR)/observability/prometheus:/etc/prometheus -w /etc/prometheus --entrypoint promtool $(PROMETHEUS_IMAGE)

.PHONY: help
help: ## Lista os alvos disponíveis
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'

# ---------- Stack local ----------
# Profiles do compose: core, observability, tools. Ex.: make up PROFILES=core
PROFILES ?= core,observability
ALL_PROFILES := core,observability,tools
COMPOSE := COMPOSE_PROFILES=$(PROFILES) docker compose
SERVICE ?= gateway

.PHONY: network up down logs ps seed test-integration smoke clean
network: ## Cria a rede compartilhada portfolio-net (idempotente)
	@docker network inspect portfolio-net > /dev/null 2>&1 || docker network create portfolio-net

up: network ## Sobe a stack (PROFILES=core,observability) e espera os healthchecks
	$(COMPOSE) up -d --build --wait

down: ## Derruba a stack de todos os profiles
	COMPOSE_PROFILES=$(ALL_PROFILES) docker compose down --remove-orphans

logs: ## Segue os logs de um serviço (SERVICE=gateway)
	$(COMPOSE) logs -f $(SERVICE)

ps: ## Estado dos containers
	COMPOSE_PROFILES=$(ALL_PROFILES) docker compose ps

seed: ## Aplica o Terraform local (realm edge-iac e Vault) contra a stack no ar
	$(DOCKER_RUN) --network platform-edge -v $(CURDIR)/terraform:/terraform -w /terraform/envs/local \
		-e TF_VAR_keycloak_url=http://keycloak:8080 -e TF_VAR_vault_address=http://vault:8200 \
		-e TF_VAR_keycloak_admin_password=dev-only-change-me -e TF_VAR_vault_token=dev-only-root-token \
		$(TERRAFORM_IMAGE) init -input=false -no-color > /dev/null
	$(DOCKER_RUN) --network platform-edge -v $(CURDIR)/terraform:/terraform -w /terraform/envs/local \
		-e TF_VAR_keycloak_url=http://keycloak:8080 -e TF_VAR_vault_address=http://vault:8200 \
		-e TF_VAR_keycloak_admin_password=dev-only-change-me -e TF_VAR_vault_token=dev-only-root-token \
		$(TERRAFORM_IMAGE) apply -auto-approve -input=false -no-color

test-integration: ## Smoke tests das políticas contra a stack (exige make up)
	go test -tags smoke -count=1 -v ./tests/smoke/...

smoke: test-integration ## Alias de test-integration

clean: ## Derruba tudo, remove volumes nomeados e imagens locais
	COMPOSE_PROFILES=$(ALL_PROFILES) docker compose down -v --rmi local --remove-orphans

# ---------- Go (upstream stub) ----------
.PHONY: go-lint go-test
go-lint: ## gofmt e go vet (inclui os smoke tests)
	@test -z "$$(gofmt -l .)" || (echo "arquivos sem gofmt:"; gofmt -l .; exit 1)
	go vet ./...
	go vet -tags smoke ./...

go-test: ## Testes unitários Go com race detector
	go test -race -count=1 ./...

# ---------- Gateway ----------
.PHONY: gateway-build gateway-validate lua-test
gateway-build: ## Constrói a imagem do gateway
	docker build -t platform-edge/gateway:dev gateway

gateway-validate: gateway-build ## Valida o kong.yaml com o plugin carregado
	$(DOCKER_RUN) platform-edge/gateway:dev kong config parse /kong/declarative/kong.yaml

lua-test: ## Testes unitários da política token-policy
	$(DOCKER_RUN) -v $(CURDIR)/gateway:/work -w /work --entrypoint luajit $(KONG_IMAGE) spec/run.lua spec/policy_spec.lua

# ---------- Terraform ----------
.PHONY: tf-fmt tf-validate
tf-fmt: ## terraform fmt -check
	$(TERRAFORM) fmt -check -recursive -diff

tf-validate: ## terraform init -backend=false e validate em cada módulo
	@set -e; for dir in $(TF_DIRS); do \
		echo "==> $$dir"; \
		$(DOCKER_RUN) -v $(CURDIR)/terraform:/terraform -w /terraform/$$dir $(TERRAFORM_IMAGE) init -backend=false -input=false -no-color > /dev/null; \
		$(DOCKER_RUN) -v $(CURDIR)/terraform:/terraform -w /terraform/$$dir $(TERRAFORM_IMAGE) validate -no-color; \
	done

# ---------- Helm ----------
.PHONY: helm-lint helm-template kubeconform
helm-lint: ## helm lint estrito com cada conjunto de valores
	$(HELM) lint --strict $(CHART)
	$(HELM) lint --strict $(CHART) -f $(CHART)/ci/production-values.yaml
	$(HELM) lint --strict $(CHART) -f $(CHART)/ci/inline-config-values.yaml

helm-template: ## Renderiza o chart com valores padrão
	$(HELM) template edge $(CHART) --namespace edge

kubeconform: ## Valida os manifestos renderizados contra os schemas do Kubernetes
	@set -eo pipefail; for variant in $(CHART_VALUES_VARIANTS); do \
		echo "==> values: $$variant"; \
		if [ "$$variant" = "default" ]; then extra=""; else extra="-f $(CHART)/$$variant"; fi; \
		$(HELM) template edge $(CHART) --namespace edge $$extra \
		| $(DOCKER_RUN) -i $(KUBECONFORM_IMAGE) -strict -summary -kubernetes-version $(K8S_VERSION) \
			-schema-location default -schema-location '$(CRDS_SCHEMA_LOCATION)' -; \
	done

# ---------- Prometheus ----------
.PHONY: prom-check prom-test
prom-check: ## promtool check config (inclui as regras)
	$(PROMTOOL) check config /etc/prometheus/prometheus.yml

prom-test: ## Testes unitários das regras de alerta
	$(PROMTOOL) test rules rules/tests/slo-edge-gateway.test.yml
	$(PROMTOOL) test rules rules/tests/edge-policies.test.yml

# ---------- Agregados ----------
.PHONY: lint test ci
lint: go-lint gateway-validate tf-fmt tf-validate helm-lint prom-check ## Todos os lints

test: go-test lua-test prom-test ## Todos os testes que não exigem a stack

ci: lint test kubeconform ## Tudo o que o CI roda, exceto os smoke tests
