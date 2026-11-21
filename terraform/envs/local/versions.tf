terraform {
  required_version = ">= 1.6"

  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = "~> 5.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.13"
    }
  }

  # Estado local de propósito: este ambiente aplica contra a stack do
  # docker-compose. Ambientes reais usam backend remoto com lock.
}

provider "keycloak" {
  client_id = "admin-cli"
  username  = var.keycloak_admin_username
  password  = var.keycloak_admin_password
  url       = var.keycloak_url
}

provider "vault" {
  address = var.vault_address
  token   = var.vault_token
}
