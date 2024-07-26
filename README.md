# Vault Workload Identity Federation (WIF) 
### Solving the secret-zero problem through WIF to establish trust with CSP Plugins
Plugins like the AWS Secrets Engine require static security credentials. The operator supplies the long-lived and highly privileged AWS credentials in the plugin configuration. Plugin WIF enables secretless configuration by integrating Vault's identity provider with plugins, providing them an identity source (JWT) that Vault can use to exchange cloud credentials via OIDC. This secretless configuration reduces security concerns associated with using long-lived, highly privileged credentials. This solution is available for AWS, GCP, and Azure secret engines and authentication methods.

## Prerequisites
- Vault Enterprise 1.17 (WIF for AWS Secrets Engine is available from version 1.16).
- [Terraform Provider Vault](https://github.com/hashicorp/terraform-provider-vault)  v4.3.0 or newer.
- A publicly accessible endpoint that provides the Vault Plugin WIF OpenID configuration document and public keys for each Vault namespace. For example:
    - https://vault.foo.com/v1/ns1/ns2/identity/oidc/plugins/.well-known/openid-configuration
    - https://vault.foo.com/v1/ns1/ns2/identity/oidc/plugins/.well-known/keys

## Security Considerations
### Vault Mount isolation & Protecting against privilege escalation
When configuring your cloud provider to trust Vault's OIDC provider, it is recommended to set at least one condition. This ensures segregation between different Vault mounts. We recommend using the `sub` claim, which includes the mount accessor in its value (e.g., `plugin-identity:namespace_id:secret`
) and restricts token requests to the intended mount.


### JWT Payload Examples
#### GCP Secrets Engine mount from a nested `foo/bar` Vault namespace.
```json
{
  "aud": [
    "https://iam.googleapis.com/projects/43515679591/locations/global/workloadIdentityPools/vault-plugin-wif-pool-3db4/providers/vault-plugin-wif-provider"
  ],
  "exp": 1721919156,
  "iat": 1721917356,
  "iss": "https://vault.foo.com/v1/foo/bar/identity/oidc/plugins",
  "nbf": 1721917356,
  "sub": "plugin-identity:ilnzr:secret:gcp_45789da7",
  "vaultproject.io": {
    "accessor": "gcp_45789da7",
    "class": "secret",
    "local": false,
    "namespace_id": "ilnzr",
    "namespace_path": "foo/bar/",
    "path": "gcp/",
    "plugin": "gcp",
    "version": "v0.19.0+builtin"
  }
}
```

#### AWS Auth Method from a nested the `root` namespace.

```json
{
  "aud": [
    "sts.amazonaws.com"
  ],
  "exp": 1721919304,
  "iat": 1721919004,
  "iss": "https://vault.foo.com/v1/identity/oidc/plugins",
  "nbf": 1721919004,
  "sub": "plugin-identity:root:auth:auth_aws_b0779138",
  "vaultproject.io": {
    "accessor": "auth_aws_b0779138",
    "class": "auth",
    "local": false,
    "namespace_id": "root",
    "namespace_path": "",
    "path": "aws/",
    "plugin": "aws",
    "version": "v1.17.2+builtin.vault"
  }
}
```

## Additional Resources
### Tutorials
- [Manage federated workload identities with AWS IAM and Vault Enterprise](https://developer.hashicorp.com/vault/tutorials/enterprise/plugin-workoad-identity-federation)

### Plugin WIF documentation
- Secrets Engines
    - [AWS](https://developer.hashicorp.com/vault/docs/secrets/aws#plugin-workload-identity-federation-wif)
    - [Azure](https://developer.hashicorp.com/vault/docs/secrets/azure#plugin-workload-identity-federation-wif)
    - [GCP](https://developer.hashicorp.com/vault/docs/secrets/gcp#plugin-workload-identity-federation-wif)

- Auth Methods
    - [AWS](https://developer.hashicorp.com/vault/docs/auth/aws#plugin-workload-identity-federation-wif)
    - [Azure](https://developer.hashicorp.com/vault/docs/auth/azure#plugin-workload-identity-federation-wif)
    - [GCP](https://developer.hashicorp.com/vault/docs/auth/gcp#plugin-workload-identity-federation-wif)
- [Vault Identity Tokens API](https://developer.hashicorp.com/vault/api-docs/secret/identity/tokens)