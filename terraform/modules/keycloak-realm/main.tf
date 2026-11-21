resource "keycloak_realm" "this" {
  realm        = var.realm
  enabled      = true
  display_name = var.display_name

  ssl_required                = "external"
  registration_allowed        = false
  reset_password_allowed      = false
  login_with_email_allowed    = true
  duplicate_emails_allowed    = false
  default_signature_algorithm = "RS256"
  access_token_lifespan       = var.access_token_lifespan
  sso_session_idle_timeout    = "30m"
  sso_session_max_lifespan    = "10h"
  revoke_refresh_token        = true
  refresh_token_max_reuse     = 0
  password_policy             = "length(12) and notUsername and passwordHistory(5)"

  security_defenses {
    headers {
      x_frame_options                     = "DENY"
      content_security_policy             = "frame-src 'self'; frame-ancestors 'self'; object-src 'none';"
      x_content_type_options              = "nosniff"
      strict_transport_security           = "max-age=31536000; includeSubDomains"
      referrer_policy                     = "no-referrer"
      x_robots_tag                        = "none"
      x_xss_protection                    = "0"
      content_security_policy_report_only = ""
    }

    brute_force_detection {
      permanent_lockout                = false
      max_login_failures               = 5
      wait_increment_seconds           = 60
      quick_login_check_milli_seconds  = 1000
      minimum_quick_login_wait_seconds = 60
      max_failure_wait_seconds         = 900
      failure_reset_time_seconds       = 43200
    }
  }
}

resource "keycloak_role" "realm" {
  for_each = var.roles

  realm_id    = keycloak_realm.this.id
  name        = each.key
  description = each.value
}

resource "keycloak_openid_client" "this" {
  for_each = var.clients

  realm_id  = keycloak_realm.this.id
  client_id = each.key
  name      = each.value.name
  enabled   = true

  access_type                  = each.value.access_type
  standard_flow_enabled        = each.value.standard_flow_enabled
  direct_access_grants_enabled = each.value.direct_access_grants_enabled
  service_accounts_enabled     = each.value.service_accounts_enabled
  implicit_flow_enabled        = false
  valid_redirect_uris          = each.value.valid_redirect_uris
  web_origins                  = each.value.web_origins

  # PKCE obrigatório para clients que usam o authorization code flow.
  pkce_code_challenge_method = each.value.standard_flow_enabled ? "S256" : null
}

# Todo token carrega aud=edge-gateway; o gateway rejeita tokens sem ela.
resource "keycloak_openid_audience_protocol_mapper" "gateway" {
  for_each = keycloak_openid_client.this

  realm_id                 = keycloak_realm.this.id
  client_id                = each.value.id
  name                     = "audience-${var.gateway_audience}"
  included_custom_audience = var.gateway_audience
  add_to_access_token      = true
  add_to_id_token          = false
}

locals {
  service_account_roles = merge([
    for client_id, client in var.clients : {
      for role in client.service_account_roles : "${client_id}/${role}" => {
        client_id = client_id
        role      = role
      }
    } if client.service_accounts_enabled
  ]...)
}

resource "keycloak_openid_client_service_account_realm_role" "this" {
  for_each = local.service_account_roles

  realm_id                = keycloak_realm.this.id
  service_account_user_id = keycloak_openid_client.this[each.value.client_id].service_account_user_id
  role                    = keycloak_role.realm[each.value.role].name
}
