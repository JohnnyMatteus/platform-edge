resource "vault_mount" "kv" {
  path        = var.kv_path
  type        = "kv"
  options     = { version = "2" }
  description = "Segredos da plataforma de entrada (gateway, clients do Keycloak)."
}

resource "vault_kv_secret_backend_v2" "kv" {
  mount        = vault_mount.kv.path
  max_versions = 10
  cas_required = true
}

resource "vault_mount" "pki" {
  path                      = var.pki_path
  type                      = "pki"
  description               = "CA interna para mTLS entre gateway e upstreams."
  default_lease_ttl_seconds = 86400
  max_lease_ttl_seconds     = 86400 * 365
}

resource "vault_pki_secret_backend_root_cert" "ca" {
  backend     = vault_mount.pki.path
  type        = "internal"
  common_name = "edge-internal-ca.${var.pki_domain}"
  ttl         = "8760h"
  key_type    = "ec"
  key_bits    = 256
}

resource "vault_pki_secret_backend_role" "upstream_mtls" {
  backend           = vault_mount.pki.path
  name              = "upstream-mtls"
  allowed_domains   = [var.pki_domain]
  allow_subdomains  = true
  allow_any_name    = false
  enforce_hostnames = true
  server_flag       = true
  client_flag       = true
  key_type          = "ec"
  key_bits          = 256
  max_ttl           = var.pki_max_ttl_seconds
  ttl               = 86400

  depends_on = [vault_pki_secret_backend_root_cert.ca]
}

resource "vault_policy" "gateway" {
  name = "edge-gateway"
  policy = templatefile("${path.module}/policies/edge-gateway.hcl.tftpl", {
    kv_path  = vault_mount.kv.path
    pki_path = vault_mount.pki.path
  })
}

resource "vault_policy" "operator" {
  name = "edge-operator"
  policy = templatefile("${path.module}/policies/edge-operator.hcl.tftpl", {
    kv_path  = vault_mount.kv.path
    pki_path = vault_mount.pki.path
  })
}

resource "vault_auth_backend" "approle" {
  type        = "approle"
  path        = "edge-approle"
  description = "AppRole para workloads da borda fora do Kubernetes."
}

resource "vault_approle_auth_backend_role" "gateway" {
  backend            = vault_auth_backend.approle.path
  role_name          = "edge-gateway"
  token_policies     = [vault_policy.gateway.name]
  token_ttl          = var.gateway_token_ttl_seconds
  token_max_ttl      = var.gateway_token_ttl_seconds * 4
  secret_id_ttl      = var.gateway_secret_id_ttl_seconds
  secret_id_num_uses = 0
  token_type         = "service"
}

resource "vault_audit" "stdout" {
  count = var.enable_audit_log ? 1 : 0

  type = "file"
  path = "edge-stdout"
  options = {
    file_path = "stdout"
  }
}
