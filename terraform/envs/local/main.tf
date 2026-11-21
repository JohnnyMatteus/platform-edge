# Ambiente local: aplica os módulos contra a stack do docker-compose.
# O realm se chama "edge-iac" para não colidir com o realm "edge" importado
# do JSON, que é o usado pelo gateway e pelos smoke tests.

module "realm" {
  source = "../../modules/keycloak-realm"

  realm        = "edge-iac"
  display_name = "Edge (gerenciado por Terraform)"

  roles = {
    "payments.read"  = "Consultar pagamentos"
    "payments.write" = "Criar e estornar pagamentos"
    "studios.read"   = "Consultar agenda e aulas dos estúdios"
    "studios.admin"  = "Administrar estúdios, planos e instrutores"
  }

  clients = {
    "studio-portal" = {
      name                  = "Portal dos estúdios (SPA)"
      access_type           = "PUBLIC"
      standard_flow_enabled = true
      valid_redirect_uris   = ["http://localhost:5173/*"]
      web_origins           = ["http://localhost:5173"]
    }
    "payments-ops" = {
      name                  = "Backoffice de pagamentos"
      access_type           = "CONFIDENTIAL"
      standard_flow_enabled = true
      valid_redirect_uris   = ["http://localhost:5174/*"]
      web_origins           = ["http://localhost:5174"]
    }
    "partner-batch" = {
      name                     = "Integração batch de parceiro"
      access_type              = "CONFIDENTIAL"
      service_accounts_enabled = true
      service_account_roles    = ["payments.read", "payments.write"]
    }
  }
}

module "vault" {
  source = "../../modules/vault-edge"

  pki_domain = "edge.internal"
}

# Segredos dos clients confidenciais vão direto para o Vault: ninguém copia
# segredo do console do Keycloak para um arquivo.
resource "vault_kv_secret_v2" "client_secrets" {
  for_each = nonsensitive(toset(keys(module.realm.client_secrets)))

  mount = module.vault.kv_path
  name  = "keycloak/clients/${each.key}"
  # O mount exige check-and-set; cas=0 só permite criar, nunca sobrescrever
  # às cegas uma versão que alguém gravou fora do Terraform.
  options = { cas = "0" }
  data_json = jsonencode({
    client_id     = each.key
    client_secret = module.realm.client_secrets[each.key]
  })
}

# Endereço do Redis do rate limit (ADR 0010). O gateway lê em gateway/*; em
# ambientes com senha, ela entra aqui e o pipeline a injeta no kong.yaml.
resource "vault_kv_secret_v2" "rate_limit_redis" {
  mount   = module.vault.kv_path
  name    = "gateway/rate-limit-redis"
  options = { cas = "0" }
  data_json = jsonencode({
    host = "redis"
    port = 6379
  })
}
