# Vault Workload Identity Federation (WIF) 
### Solving the secret-zero problem through WIF to establish trust with CSP Plugins
Plugins like the AWS Secrets Engine require static security credentials. The operator supplies the long-lived and highly privileged AWS credentials in the plugin configuration. Plugin WIF enables secretless configuration by integrating Vault's identity provider with plugins, providing them an identity source (JWT) that Vault can use to exchange cloud credentials via OIDC. This secretless configuration reduces security concerns associated with using long-lived, highly privileged credentials. This solution is available for AWS, GCP, and Azure secret engines and authentication methods.

## Prerequisites
- **Vault Enterprise 1.17**: The AWS Secrets Engine is available from version 1.16.
- **Terraform Provider Vault v4.3.0**: https://github.com/hashicorp/terraform-provider-vault 
- A publicly accessible endpoint serving the Vault Plugin WIF OpenID configuration document and public keys for each Vault namespace, for example, `https://vault.foo.com/v1/identity/oidc/plugins/.well-known/openid-configuration` or for a namespace `https://vault.foo.com/v1/ns1/identity/oidc/plugins/.well-known/keys`.

## Security Considerations
### Mount isolation & Protecting against privilege escalation
When configuring your cloud provider to trust Vault's OIDC provider, it is recommended to set at least one condition. This ensures segregation between different Vault mounts. We recommend using the sub claim, which includes the mount accessor in its value (e.g., plugin-identity:namespace_id:secret
) and restricts token requests to the intended mount.



## Additional Resources
- Secrets Engines
    - [AWS](https://developer.hashicorp.com/vault/docs/secrets/aws#plugin-workload-identity-federation-wif)
    - [Azure](https://developer.hashicorp.com/vault/docs/secrets/azure#plugin-workload-identity-federation-wif)
    - [GCP](https://developer.hashicorp.com/vault/docs/secrets/gcp#plugin-workload-identity-federation-wif)

- Auth Methods
    - [AWS](https://developer.hashicorp.com/vault/docs/auth/aws#plugin-workload-identity-federation-wif)
    - [Azure](https://developer.hashicorp.com/vault/docs/auth/azure#plugin-workload-identity-federation-wif)
    - [GCP](https://developer.hashicorp.com/vault/docs/auth/gcp#plugin-workload-identity-federation-wif)
- [Identity Tokens API](https://developer.hashicorp.com/vault/api-docs/secret/identity/tokens)