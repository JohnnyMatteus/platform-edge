variable "keycloak_url" {
  description = "URL do Keycloak."
  type        = string
  default     = "http://localhost:8080"
}

variable "keycloak_admin_username" {
  description = "Usuário administrador do Keycloak."
  type        = string
  default     = "admin"
}

variable "keycloak_admin_password" {
  description = "Senha do administrador do Keycloak (TF_VAR_keycloak_admin_password)."
  type        = string
  sensitive   = true
}

variable "vault_address" {
  description = "Endereço do Vault."
  type        = string
  default     = "http://localhost:8200"
}

variable "vault_token" {
  description = "Token do Vault com permissão de administrar mounts e políticas (TF_VAR_vault_token)."
  type        = string
  sensitive   = true
}
