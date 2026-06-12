# Vault secrets sync to AWS Secrets Manager (WIF)

Terraform example that configures [Vault secrets sync](https://developer.hashicorp.com/vault/docs/sync)
to replicate a KV v2 secret into [AWS Secrets Manager](https://developer.hashicorp.com/vault/docs/sync/awssm)
using **workload identity federation (WIF)** — no static AWS credentials are stored in Vault.

Everything is provisioned with Terraform; no manual CLI steps are required.

## What this creates

| Resource | Purpose |
| --- | --- |
| `vault_identity_oidc` | Sets the public OIDC issuer URL that AWS uses to validate tokens. |
| `vault_identity_oidc_key` | Dedicated RSA key that signs the sync identity tokens. |
| `vault_identity_oidc_role` | Publishes the signing key to the JWKS endpoint (see [Why the OIDC role is required](#why-the-oidc-role-is-required)). |
| `vault_activation_flags` | One-time activation of the secrets sync feature. |
| `aws_iam_openid_connect_provider` | Trusts Vault's secrets sync issuer as an OIDC identity provider. |
| `aws_iam_role` / `aws_iam_role_policy` | Web identity role Vault assumes, scoped to `secretsmanager` on `vault-<tenant_id>-*` secrets. |
| `vault_secrets_sync_aws_destination` | The AWS Secrets Manager destination, configured for WIF. |
| `vault_mount` / `vault_kv_secret_v2` | The tenant's KV v2 mount (`<tenant_id>-kv`) and a demo secret to synchronize. |
| `vault_secrets_sync_association` | Associates the secret with the destination, triggering the sync. |

## How WIF works here

1. Vault signs a short-lived JWT (identity token) with the dedicated OIDC key. The token's
   `sub` claim is `secrets-sync:<namespace>:aws-sm:<destination_name>` and its `aud` claim is the
   audience you configure.
2. Vault calls AWS STS `AssumeRoleWithWebIdentity` with that token.
3. AWS fetches Vault's OIDC discovery document and JWKS (over the public issuer URL) to verify the
   token signature, then checks the IAM role's trust policy conditions (`sub` and `aud`).
4. STS returns short-lived credentials that Vault uses to write secrets to AWS Secrets Manager.

The IAM role trust policy pins both the `sub` and `aud` claims, so only this specific Vault
destination can assume the role.

### Identity token payload example

The JWT Vault signs and presents to AWS STS for this example (root namespace, destination
`app1-aws-sm`). Secrets sync uses a distinct issuer path (`identity/oidc/secrets-sync`) and a
`secrets-sync:<namespace>:<store_type>:<store_name>` subject, unlike the plugin WIF tokens used by
secrets engines and auth methods.

```jsonc
{
  "aud": [
    "vault.example.com/v1/identity/oidc/secrets-sync" // recipient of the token (AWS); must match the OIDC provider client ID and the role trust :aud
  ],
  "exp": 1721919156,                                  // expiry (Unix seconds); set from identity_token_ttl
  "iat": 1721917356,                                  // issued-at (Unix seconds)
  "iss": "https://vault.example.com/v1/identity/oidc/secrets-sync", // issuer that signed the token; AWS fetches its discovery doc + JWKS here
  "nbf": 1721917356,                                  // not-valid-before (Unix seconds)
  "sub": "secrets-sync:root:aws-sm:app1-aws-sm",      // subject identifying this destination: secrets-sync:<namespace>:<store_type>:<store_name>
  "vaultproject.io": {                                // Vault private claim block
    "namespace_id": "root",                           // internal ID of the namespace holding the destination
    "namespace_path": "",                             // namespace path ("" for root; e.g. "foo/bar/" when nested)
    "store_type": "aws-sm",                           // sync destination type
    "store_name": "app1-aws-sm"                       // sync destination name
  }
}
```

The last two `sub` segments come from the destination resource you create:

- `<store_type>` (here `aws-sm`) — you do not set this yourself. Vault assigns it automatically
  based on which destination resource you use: `vault_secrets_sync_aws_destination` is always
  `aws-sm` (the GCP resource is `gcp-sm`, the Azure one is `azure-kv`). It is read-only, surfaced
  as the resource's `.type` attribute.
- `<store_name>` (here `app1-aws-sm`) — this is the `name` you choose on that resource (in this
  example `local.destination_name`, `<tenant_id>-aws-sm`). Rename the destination and the `sub`
  changes with it.

For a destination created in a nested `foo/bar` namespace, `iss` becomes
`https://vault.example.com/v1/foo/bar/identity/oidc/secrets-sync`, the `sub` namespace segment
reflects the namespace, and `namespace_path` is `foo/bar/`.

## Prerequisites

- **Vault Enterprise 2.0.0 or later** — see [Supported Vault versions](#supported-vault-versions).
- Terraform 1.11+ (the destination uses write-only arguments).
- The `hashicorp/vault` provider 6.0.0+ (`vault_activation_flags` and the AWS destination WIF
  fields).
- A publicly reachable HTTPS endpoint that serves Vault's secrets sync OIDC discovery document and
  JWKS, so AWS can validate identity tokens. For example:
  `https://vault.example.com/v1/identity/oidc/secrets-sync/.well-known/openid-configuration`
- AWS credentials with permission to manage IAM (the OIDC provider, role, and policy); the optional
  verification step also reads from Secrets Manager.

### Supported Vault versions

Secret sync with workload identity federation (WIF) requires **Vault Enterprise 2.0.0 or later**.
It was introduced in Vault 2.0.0 (April 14, 2026); earlier release lines support secrets sync only
with static credentials, not WIF.

| Vault release line                                    | Secret sync WIF |
| ----------------------------------------------------- | --------------- |
| 2.0.x (2.0.0, 2.0.1, 2.0.2, …) and all later releases | Supported       |
| 1.21.x                                                | Not supported   |
| 1.20.x and earlier                                    | Not supported   |

This example also requires the `hashicorp/vault` provider 6.0.0+ and Terraform 1.11+ (write-only
arguments).

## Usage

```sh
export VAULT_ADDR="https://vault.example.com"
export VAULT_TOKEN="<token>"

terraform init
terraform apply \
  -var 'public_oidc_issuer_url=https://vault.example.com' \
  -var 'tenant_id=app1'
```

The `public_oidc_issuer_url` must be the externally reachable base URL of Vault (or a proxy in
front of it). AWS contacts this URL directly, so `localhost` will not work. Set `tenant_id` per
tenant (for example `app1`, `app2`) to give each its own isolated set of Vault and AWS resources.

This example creates a non-sensitive demo secret (`{"foo":"bar"}`) with Terraform. Do not put
real secret material in `vault_kv_secret_v2.data_json` for production workflows, because Terraform
stores that source value in state; seed or update production KV data outside Terraform instead.

## Why the OIDC role is required

AWS validates the identity token signature against the keys published at the issuer's JWKS endpoint
(`.../identity/oidc/secrets-sync/.well-known/keys`). Vault only advertises a named OIDC key in that
JWKS when the key is referenced by an **OIDC role** or a **mount**. A secrets sync destination is
neither, so without `vault_identity_oidc_role.publish_key` the JWKS is empty, AWS cannot verify the
token, and `AssumeRoleWithWebIdentity` fails (Vault surfaces this as a generic credential error).

The role in this example issues no tokens; it exists solely to publish the signing key to the JWKS.
You can confirm the behaviour directly:

```sh
# Empty before the role exists, populated afterwards.
curl -sk "$VAULT_ADDR/v1/identity/oidc/secrets-sync/.well-known/keys"
```

## Verify

```sh
# Sync status reported by Vault (expect SYNCED)
terraform output synced_secret_sync_status

# Confirm the secret landed in AWS Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id "$(terraform output -raw expected_aws_secret_name)" \
  --query SecretString --output text
```

Updating or deleting the Vault secret propagates to AWS Secrets Manager automatically.

## Clean up

```sh
terraform destroy \
  -var 'public_oidc_issuer_url=https://vault.example.com' \
  -var 'tenant_id=app1'
```

Activation flags cannot be deactivated through the API, so the secrets sync feature remains enabled
after destroy; Terraform only removes the flag from state.

## Variables

| Variable | Default | Description |
| --- | --- | --- |
| `public_oidc_issuer_url` | _(required)_ | Publicly reachable base URL of Vault for AWS to fetch OIDC metadata. |
| `tenant_id` | `app1` | Tenant/application identifier. All resource names derive from it: `<tenant_id>-kv`, `<tenant_id>-aws-sm`, `<tenant_id>-secrets-sync`, and synced secret prefix `vault-<tenant_id>-`. |
| `aws_region` | `us-east-1` | AWS region for the synced secrets. |
| `aws_audience` | _(derived)_ | Token audience. Defaults to the issuer URL without its scheme (`<host>/v1/identity/oidc/secrets-sync`). |
| `secret_name` | `my-secret` | Name of the demo secret inside the tenant's KV mount. |
