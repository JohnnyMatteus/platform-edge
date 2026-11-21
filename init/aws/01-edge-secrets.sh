#!/usr/bin/env bash
# Bootstrap do LocalStack (profile tools): cria no Secrets Manager os mesmos
# segredos que o Terraform grava no Vault, para comparar as duas abordagens
# (ADR 0009). Valores DEV ONLY.
set -euo pipefail

create_secret() {
  local name="$1" value="$2"
  if awslocal secretsmanager describe-secret --secret-id "$name" >/dev/null 2>&1; then
    echo "secret $name já existe"
    return
  fi
  awslocal secretsmanager create-secret \
    --name "$name" \
    --description "Segredo de client do Keycloak (DEV ONLY)" \
    --secret-string "$value" \
    --tags Key=project,Value=platform-edge Key=environment,Value=local >/dev/null
  echo "secret $name criado"
}

create_secret "edge/keycloak/clients/payments-ops" \
  '{"client_id":"payments-ops","client_secret":"dev-only-payments-ops-secret"}'
create_secret "edge/keycloak/clients/partner-batch" \
  '{"client_id":"partner-batch","client_secret":"dev-only-partner-batch-secret"}'
