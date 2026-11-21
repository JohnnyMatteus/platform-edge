output "issuer_path" {
  description = "Path do issuer do realm gerenciado por Terraform."
  value       = module.realm.issuer
}

output "vault_policies" {
  description = "Políticas criadas no Vault."
  value       = module.vault.policies
}

output "gateway_approle_role_name" {
  description = "Papel AppRole do gateway."
  value       = module.vault.gateway_approle_role_name
}
