# Vault secrets sync to GCP Secret Manager (WIF)

Terraform example that configures [Vault secrets sync](https://developer.hashicorp.com/vault/docs/sync)
to replicate a KV v2 secret into [GCP Secret Manager](https://developer.hashicorp.com/vault/docs/sync/gcpsm)
using **workload identity federation (WIF)** — no static GCP service-account keys are stored in Vault.

Everything is provisioned with Terraform; no manual CLI steps are required.

## What this creates

| Resource | Purpose |
| --- | --- |
| `vault_identity_oidc` | Sets the public OIDC issuer URL that GCP uses to validate tokens. |
| `vault_identity_oidc_key` | Dedicated RSA key that signs the sync identity tokens. |
| `vault_identity_oidc_role` | Publishes the signing key to the JWKS endpoint (see [Why the OIDC role is required](#why-the-oidc-role-is-required)). |
| `vault_activation_flags` | One-time activation of the secrets sync feature. |
| `google_project_service` | Enables the required APIs. Tenant project: Secret Manager, IAM, IAM Credentials, STS, and Cloud Resource Manager (`activate_apis`). Separate WIF project, if used: IAM, STS, IAM Credentials, and Cloud Resource Manager. |
| `google_iam_workload_identity_pool` / `_provider` | Trusts Vault's secrets sync issuer as an OIDC identity provider; created in the WIF project (`wif_project_id`, which defaults to the tenant project). |
| `google_service_account` | Per-tenant service account Vault impersonates through WIF, in the tenant project. |
| `google_service_account_iam_member` | Grants the federated subject `roles/iam.workloadIdentityUser` on the SA. |
| `google_project_iam_custom_role` | Defines the five Secret Manager write permissions Vault's project-level pre-flight check requires. |
| `google_project_iam_member` | Grants that custom role to the service account at the project level. |
| `vault_secrets_sync_gcp_destination` | The GCP Secret Manager destination, configured for WIF. |
| `vault_mount` / `vault_kv_secret_v2` | The tenant's KV v2 mount (`<tenant_id>-kv`) and a demo secret to synchronize. |
| `vault_secrets_sync_association` | Associates the secret with the destination, triggering the sync. |

## How WIF works here

1. Vault signs a short-lived JWT (identity token) with the dedicated OIDC key. The token's
   `sub` claim is `secrets-sync:<namespace>:gcp-sm:<tenant_id>-gcp-sm` and its `aud` claim is the
   audience (the workload identity pool provider resource URL).
2. Vault presents the token to GCP STS to obtain a federated token, then impersonates the service
   account through the IAM Credentials API.
3. GCP fetches Vault's OIDC discovery document and JWKS (over the public issuer URL) to verify the
   token signature, then checks the pool provider's `allowed_audiences` and `attribute_condition`
   (which pins the exact `sub`).
4. The impersonated service account's project-level custom Secret Manager writer role lets Vault
   create, update, delete, and add/destroy versions for synced secrets.

The pool provider's `attribute_condition` and the service account impersonation binding both pin
the exact `sub`, so only this tenant's Vault destination can impersonate the service account.

### Identity token payload example

The JWT Vault signs and presents to GCP STS for this example (root namespace, destination
`app1-gcp-sm`). Secrets sync uses a distinct issuer path (`identity/oidc/secrets-sync`) and a
`secrets-sync:<namespace>:<store_type>:<store_name>` subject, unlike the plugin WIF tokens used by
secrets engines and auth methods.

```jsonc
{
  "aud": [
    "https://iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/app1-secrets-sync-pool-a1b2/providers/app1-secrets-sync-provider" // recipient of the token (GCP); must match the pool provider's allowed_audiences
  ],
  "exp": 1721919156,                                  // expiry (Unix seconds); set from identity_token_ttl
  "iat": 1721917356,                                  // issued-at (Unix seconds)
  "iss": "https://vault.example.com/v1/identity/oidc/secrets-sync", // issuer that signed the token; GCP fetches its discovery doc + JWKS here
  "nbf": 1721917356,                                  // not-valid-before (Unix seconds)
  "sub": "secrets-sync:root:gcp-sm:app1-gcp-sm",      // subject identifying this destination: secrets-sync:<namespace>:<store_type>:<store_name>
  "vaultproject.io": {                                // Vault private claim block
    "namespace_id": "root",                           // internal ID of the namespace holding the destination
    "namespace_path": "",                             // namespace path ("" for root; e.g. "foo/bar/" when nested)
    "store_type": "gcp-sm",                           // sync destination type
    "store_name": "app1-gcp-sm"                       // sync destination name
  }
}
```

The last two `sub` segments come from the destination resource you create:

- `<store_type>` (here `gcp-sm`) — you do not set this yourself. Vault assigns it automatically
  based on which destination resource you use: `vault_secrets_sync_gcp_destination` is always
  `gcp-sm` (the AWS resource is `aws-sm`, the Azure one is `azure-kv`). It is read-only, surfaced
  as the resource's `.type` attribute.
- `<store_name>` (here `app1-gcp-sm`) — this is the `name` you choose on that resource (in this
  example `local.destination_name`, `<tenant_id>-gcp-sm`). Rename the destination and the `sub`
  changes with it.

For a destination created in a nested `foo/bar` namespace, `iss` becomes
`https://vault.example.com/v1/foo/bar/identity/oidc/secrets-sync`, the `sub` namespace segment
reflects the namespace, and `namespace_path` is `foo/bar/`.

Tenants are isolated at three layers — **project** (each tenant's service account, custom role, and
secrets in its own `gcp_project_id`), **identity** (the `attribute_condition` and the
`roles/iam.workloadIdentityUser` binding both pin the exact `sub`, with a dedicated SA per tenant),
and **trust anchor** (the pool and provider live in `wif_project_id`, which defaults to the tenant
project and should be a dedicated central project in production). See
[GCP best practices alignment](#gcp-best-practices-alignment).

## GCP best practices alignment

This example follows Google's [best practices for Workload Identity Federation](https://docs.cloud.google.com/iam/docs/best-practices-for-using-workload-identity-federation):

- **Dedicated project for pools/providers** — when set, `wif_project_id` hosts only the workload
  identity pool and provider, separate from tenant resource projects, so trust configuration stays
  in one place and few principals can modify attribute mappings.
- **Dedicated SA per tenant, co-located with resources** — each tenant has its own service account
  in its own resource project, alongside the secrets it writes.
- **Exact-subject binding** — `roles/iam.workloadIdentityUser` is granted to the specific
  `principal://…/subject/<sub>`, never to all pool members (`principalSet://…/*`).
- **Attribute condition on a shared issuer** — Vault is a multi-tenant issuer, so the provider pins
  the exact token `sub` to stop one tenant's token from federating as another.
- **Audience = provider URL** — guards against confused-deputy replay of tokens issued for another
  API.
- **Immutable, unique subject mapping** — `google.subject` maps to Vault's `sub`
  (`secrets-sync:<ns>:gcp-sm:<dest>`), which is stable, authoritative, and unique per destination.
- **Single provider per pool** — avoids subject collisions.

Hardening beyond this module (org/project-level, out of scope here): enable **data-access audit
logs** for the STS and IAM APIs in both projects; apply the
`constraints/iam.workloadIdentityPoolProviders` **org policy** to deny pool/provider creation
outside the WIF project; and serve the **public issuer endpoint** over TLS you control so the JWKS
cannot be swapped.

## Prerequisites

- **Vault Enterprise 2.0.0 or later** — see [Supported Vault versions](#supported-vault-versions).
- Terraform 1.11+ (the destination uses write-only arguments).
- The `hashicorp/vault` provider 6.0.0+ (`vault_activation_flags` and the GCP destination WIF
  fields).
- A publicly reachable HTTPS endpoint that serves Vault's secrets sync OIDC discovery document and
  JWKS, so GCP can validate identity tokens. For example:
  `https://vault.example.com/v1/identity/oidc/secrets-sync/.well-known/openid-configuration`
- GCP credentials (Application Default Credentials or `GOOGLE_APPLICATION_CREDENTIALS`) with
  permission to manage workload identity pools/providers in the WIF project and, in the tenant
  project, service accounts, custom roles, and the required APIs (including Secret Manager).

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
  -var 'gcp_project_id=my-project' \
  -var 'tenant_id=app1'
```

The `public_oidc_issuer_url` must be the externally reachable base URL of Vault (or a proxy in
front of it). GCP contacts this URL directly, so `localhost` will not work. Set `tenant_id` per
tenant (for example `app1`, `app2`) to give each its own isolated set of Vault and GCP resources.

For production, set `wif_project_id` to a dedicated central project so the workload identity
pool/provider are separated from the tenant's resource project (see
[GCP best practices alignment](#gcp-best-practices-alignment)).

This example creates a non-sensitive demo secret (`{"foo":"bar"}`) with Terraform. Do not put
real secret material in `vault_kv_secret_v2.data_json` for production workflows, because Terraform
stores that source value in state; seed or update production KV data outside Terraform instead.

## Why the OIDC role is required

GCP validates the identity token signature against the keys published at the issuer's JWKS endpoint
(`.../identity/oidc/secrets-sync/.well-known/keys`). Vault only advertises a named OIDC key in that
JWKS when the key is referenced by an **OIDC role** or a **mount**. A secrets sync destination is
neither, so without `vault_identity_oidc_role.publish_key` the JWKS is empty, GCP cannot verify the
token, and the federated token exchange fails (Vault surfaces this as a generic credential error).

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

# Confirm the secret landed in GCP Secret Manager (substitute your project ID)
gcloud secrets versions access latest \
  --project my-project \
  --secret "$(terraform output -raw expected_gcp_secret_name)"
```

Updating or deleting the Vault secret propagates to GCP Secret Manager automatically.

## Clean up

```sh
terraform destroy \
  -var 'public_oidc_issuer_url=https://vault.example.com' \
  -var 'gcp_project_id=my-project' \
  -var 'tenant_id=app1'
```

Activation flags cannot be deactivated through the API, so the secrets sync feature remains enabled
after destroy; Terraform only removes the flag from state.

## Variables

| Variable | Default | Description |
| --- | --- | --- |
| `public_oidc_issuer_url` | _(required)_ | Publicly reachable base URL of Vault for GCP to fetch OIDC metadata. |
| `gcp_project_id` | _(required)_ | The tenant's resource project: service account, custom role, and synced secrets. |
| `wif_project_id` | _(co-located)_ | Dedicated project hosting the workload identity pool/provider. Defaults to `gcp_project_id`; set to a separate central project for production. |
| `tenant_id` | `app1` | Tenant/application identifier. All resource names derive from it: `<tenant_id>-kv`, `<tenant_id>-gcp-sm`, `<tenant_id>-secrets-sync-*`, and synced secret `vault-<tenant_id>-<secret_name>`. |
| `gcp_audience` | _(derived)_ | Token audience. Defaults to the pool provider resource URL. |
| `activate_apis` | _(see variables.tf)_ | GCP APIs to enable for WIF and Secret Manager. |
| `secret_name` | `my-secret` | Name of the demo secret inside the tenant's KV mount. |
