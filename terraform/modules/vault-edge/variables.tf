variable "kv_path" {
  description = "Caminho do secrets engine KV v2 da plataforma de entrada."
  type        = string
  default     = "edge"
}

variable "pki_path" {
  description = "Caminho do secrets engine PKI que emite certificados de mTLS gateway -> upstream."
  type        = string
  default     = "edge-pki"
}

variable "pki_domain" {
  description = "Domínio interno dos upstreams (ex.: svc.cluster.local)."
  type        = string
}

variable "pki_max_ttl_seconds" {
  description = "TTL máximo dos certificados emitidos para upstreams."
  type        = number
  default     = 86400 * 3
}

variable "gateway_token_ttl_seconds" {
  description = "TTL do token Vault obtido pelo gateway via AppRole."
  type        = number
  default     = 3600
}

variable "gateway_secret_id_ttl_seconds" {
  description = "Validade do secret_id do AppRole do gateway."
  type        = number
  default     = 86400
}

variable "enable_audit_log" {
  description = "Habilita audit device em stdout (desligar só se outro audit device já existir)."
  type        = bool
  default     = true
}
