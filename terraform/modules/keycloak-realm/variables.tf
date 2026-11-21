variable "realm" {
  description = "Nome do realm."
  type        = string
}

variable "display_name" {
  description = "Nome exibido na tela de login."
  type        = string
}

variable "access_token_lifespan" {
  description = "Validade do access token. Precisa ficar abaixo do maximum_expiration do plugin jwt do gateway (15m)."
  type        = string
  default     = "5m"
}

variable "gateway_audience" {
  description = "Valor incluído em aud de todos os tokens e conferido pelo plugin token-policy."
  type        = string
  default     = "edge-gateway"
}

variable "roles" {
  description = "Papéis de realm, nome => descrição."
  type        = map(string)
}

variable "clients" {
  description = <<-EOT
    Clients OIDC por client_id. access_type: PUBLIC ou CONFIDENTIAL.
    service_account_roles só vale para clients com service account.
  EOT
  type = map(object({
    name                         = string
    access_type                  = string
    standard_flow_enabled        = optional(bool, false)
    direct_access_grants_enabled = optional(bool, false)
    service_accounts_enabled     = optional(bool, false)
    valid_redirect_uris          = optional(list(string), [])
    web_origins                  = optional(list(string), [])
    service_account_roles        = optional(list(string), [])
  }))

  validation {
    condition     = alltrue([for c in values(var.clients) : contains(["PUBLIC", "CONFIDENTIAL"], c.access_type)])
    error_message = "access_type deve ser PUBLIC ou CONFIDENTIAL."
  }

  validation {
    condition     = alltrue([for c in values(var.clients) : !(c.access_type == "PUBLIC" && c.service_accounts_enabled)])
    error_message = "Client público não pode ter service account."
  }
}
