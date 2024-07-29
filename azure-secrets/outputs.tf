output "oidc_config_url" {
  value       = "${local.oidc_base_url}/.well-known/openid-configuration"
  description = "The URL of the OpenID Connect discovery document."
}

