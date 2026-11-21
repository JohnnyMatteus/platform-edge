output "realm_id" {
  description = "ID do realm criado."
  value       = keycloak_realm.this.id
}

output "issuer" {
  description = "Caminho do issuer relativo à URL pública do Keycloak; vai em allowed_issuers do gateway."
  value       = "/realms/${keycloak_realm.this.realm}"
}

output "client_secrets" {
  description = "Segredos gerados pelo Keycloak para os clients confidenciais, por client_id."
  value = {
    for id, client in keycloak_openid_client.this : id => client.client_secret
    if var.clients[id].access_type == "CONFIDENTIAL"
  }
  sensitive = true
}
