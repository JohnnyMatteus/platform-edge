output "kv_path" {
  description = "Mount do KV v2."
  value       = vault_mount.kv.path
}

output "gateway_approle_role_name" {
  description = "Nome do papel AppRole do gateway."
  value       = vault_approle_auth_backend_role.gateway.role_name
}

output "pki_ca_certificate" {
  description = "Certificado da CA interna, para configurar a confiança nos upstreams."
  value       = vault_pki_secret_backend_root_cert.ca.certificate
}

output "policies" {
  description = "Políticas criadas."
  value       = [vault_policy.gateway.name, vault_policy.operator.name]
}
