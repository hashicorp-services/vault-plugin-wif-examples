output "secrets_sync_oidc_discovery_url" {
  description = "Secrets sync OIDC discovery document URL. This endpoint must be reachable by AWS."
  value       = "${local.oidc_base_url}/.well-known/openid-configuration"
}

output "wif_audience" {
  description = "Audience (aud) shared by the identity token, the AWS OIDC provider, and the IAM role trust policy."
  value       = local.aws_audience
}

output "wif_role_arn" {
  description = "ARN of the IAM role Vault assumes through AssumeRoleWithWebIdentity."
  value       = aws_iam_role.secrets_sync.arn
}

output "expected_token_subject" {
  description = "The 'sub' claim Vault issues for this destination, matched by the IAM role trust policy."
  value       = local.expected_subject
}

output "destination_name" {
  description = "Name of the Vault AWS Secrets Manager sync destination."
  value       = vault_secrets_sync_aws_destination.this.name
}

output "synced_secret_sync_status" {
  description = "Sync status of the demo secret association (SYNCED once the secret reaches AWS Secrets Manager)."
  value       = [for m in vault_secrets_sync_association.demo.metadata : m.sync_status]
}

output "expected_aws_secret_name" {
  description = "Predicted AWS Secrets Manager secret name produced by the secret name template for the demo secret."
  value       = replace(local.secret_name_template, "{{ .SecretBaseName }}", var.secret_name)
}
