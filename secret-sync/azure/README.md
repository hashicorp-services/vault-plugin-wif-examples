# Vault secrets sync to Azure Key Vault (WIF)

Terraform example that configures [Vault secrets sync](https://developer.hashicorp.com/vault/docs/sync)
to replicate a KV v2 secret into [Azure Key Vault](https://developer.hashicorp.com/vault/docs/sync/azurekv)
using **workload identity federation (WIF)** — no static Azure client secrets are stored in Vault.

Everything is provisioned with Terraform; no manual CLI steps are required.

## What this creates

| Resource | Purpose |
| --- | --- |
| `vault_identity_oidc` | Sets the public OIDC issuer URL that Azure uses to validate tokens. |
| `vault_identity_oidc_key` | Dedicated RSA key that signs the sync identity tokens. |
| `vault_identity_oidc_role` | Publishes the signing key to the JWKS endpoint (see [Why the OIDC role is required](#why-the-oidc-role-is-required)). |
| `vault_activation_flags` | One-time activation of the secrets sync feature. |
| `azuread_application` | App registration representing the Vault sync workload in Entra ID. |
| `azuread_service_principal` | Service principal that receives Key Vault data-plane RBAC. |
| `azuread_application_federated_identity_credential` | Trusts Vault's secrets sync issuer + subject (the WIF trust anchor). |
| `azurerm_resource_group` | Resource group for the Key Vault. |
| `azurerm_key_vault` | The Key Vault (`kv-<tenant_id>-<random>`), RBAC-authorized, that receives the synced secret. |
| `azurerm_role_assignment` | Grants the service principal `Key Vault Secrets Officer` on the vault. |
| `vault_secrets_sync_azure_destination` | The Azure Key Vault destination, configured for WIF. |
| `vault_mount` / `vault_kv_secret_v2` | The tenant's KV v2 mount (`<tenant_id>-kv`) and a demo secret to synchronize. |
| `vault_secrets_sync_association` | Associates the secret with the destination, triggering the sync. |

## How WIF works here

1. Vault signs a short-lived JWT (identity token) with the dedicated OIDC key. The token's
   `sub` claim is `secrets-sync:<namespace>:azure-kv:<destination_name>` and its `aud` claim is
   the audience (`api://AzureADTokenExchange`).
2. Vault presents the token to Microsoft Entra ID to exchange it, through the app registration's
   federated identity credential, for an Azure access token for the service principal.
3. Entra ID fetches Vault's OIDC discovery document and JWKS (over the public issuer URL) to verify
   the token signature, then checks the federated identity credential's `issuer`, `subject`, and
   `audiences` (which pin the exact `sub`).
4. The service principal's `Key Vault Secrets Officer` role on the vault lets Vault set secret
   versions in Azure Key Vault.

The federated identity credential's `subject` pins the exact `sub`, so only this tenant's Vault
destination can federate into the app registration.

### Identity token payload example

The JWT Vault signs and presents to Microsoft Entra ID for this example (root namespace,
destination `app1-azure-kv`). Secrets sync uses a distinct issuer path (`identity/oidc/secrets-sync`)
and a `secrets-sync:<namespace>:<store_type>:<store_name>` subject, unlike the plugin WIF tokens
used by secrets engines and auth methods.

```jsonc
{
  "aud": [
    "api://AzureADTokenExchange"                      // recipient of the token (Azure); must match the federated identity credential's audiences
  ],
  "exp": 1721919156,                                  // expiry (Unix seconds); set from identity_token_ttl
  "iat": 1721917356,                                  // issued-at (Unix seconds)
  "iss": "https://vault.example.com/v1/identity/oidc/secrets-sync", // issuer that signed the token; Azure fetches its discovery doc + JWKS here
  "nbf": 1721917356,                                  // not-valid-before (Unix seconds)
  "sub": "secrets-sync:root:azure-kv:app1-azure-kv",  // subject identifying this destination: secrets-sync:<namespace>:<store_type>:<store_name>
  "vaultproject.io": {                                // Vault private claim block
    "namespace_id": "root",                           // internal ID of the namespace holding the destination
    "namespace_path": "",                             // namespace path ("" for root; e.g. "foo/bar/" when nested)
    "store_type": "azure-kv",                         // sync destination type
    "store_name": "app1-azure-kv"                     // sync destination name
  }
}
```

The last two `sub` segments come from the destination resource you create:

- `<store_type>` (here `azure-kv`) — you do not set this yourself. Vault assigns it automatically
  based on which destination resource you use: `vault_secrets_sync_azure_destination` is always
  `azure-kv` (the AWS resource is `aws-sm`, the GCP one is `gcp-sm`). It is read-only, surfaced
  as the resource's `.type` attribute.
- `<store_name>` (here `app1-azure-kv`) — this is the `name` you choose on that resource (in this
  example `local.destination_name`, `<tenant_id>-azure-kv`). Rename the destination and the `sub`
  changes with it.

For a destination created in a nested `foo/bar` namespace, `iss` becomes
`https://vault.example.com/v1/foo/bar/identity/oidc/secrets-sync`, the `sub` namespace segment
reflects the namespace, and `namespace_path` is `foo/bar/`.

## Prerequisites

- **Vault Enterprise 2.0.0 or later** — see [Supported Vault versions](#supported-vault-versions).
- Terraform 1.11+ (the destination uses write-only arguments).
- The `hashicorp/vault` provider 6.0.0+ (`vault_activation_flags` and the Azure destination WIF
  fields).
- A publicly reachable HTTPS endpoint that serves Vault's secrets sync OIDC discovery document and
  JWKS, so Azure can validate identity tokens. For example:
  `https://vault.example.com/v1/identity/oidc/secrets-sync/.well-known/openid-configuration`
- Azure credentials (for example `az login`, or `ARM_*` environment variables) with permission to:
  - register an Entra ID app + service principal and manage its federated identity credential
    (for example the **Application Developer** directory role), and
  - create a resource group and Key Vault and assign the **Key Vault Secrets Officer** role
    (for example **Contributor** plus **User Access Administrator**, or **Owner**, on the
    subscription).

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
front of it). Azure contacts this URL directly, so `localhost` will not work. Set `tenant_id` per
tenant (for example `app1`, `app2`) to give each its own isolated set of Vault and Azure resources.
The Azure subscription and Entra tenant are taken from the active Azure login.

This example creates a non-sensitive demo secret (`{"foo":"bar"}`) with Terraform. Do not put
real secret material in `vault_kv_secret_v2.data_json` for production workflows, because Terraform
stores that source value in state; seed or update production KV data outside Terraform instead.

## Why the OIDC role is required

Azure validates the identity token signature against the keys published at the issuer's JWKS
endpoint (`.../identity/oidc/secrets-sync/.well-known/keys`). Vault only advertises a named OIDC key
in that JWKS when the key is referenced by an **OIDC role** or a **mount**. A secrets sync
destination is neither, so without `vault_identity_oidc_role.publish_key` the JWKS is empty, Entra
ID cannot verify the token, and the federated credential exchange fails (Vault surfaces this as a
generic credential error).

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

# Your Azure login also needs data-plane access such as Key Vault Secrets User
# on this vault; subscription Owner/Contributor alone is not enough for this command.

# Confirm the secret landed in Azure Key Vault
az keyvault secret show \
  --vault-name "$(terraform output -raw key_vault_name)" \
  --name "$(terraform output -raw expected_azure_secret_name)" \
  --query value -o tsv
```

Updating or deleting the Vault secret propagates to Azure Key Vault automatically.

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
| `public_oidc_issuer_url` | _(required)_ | Publicly reachable base URL of Vault for Azure to fetch OIDC metadata. |
| `tenant_id` | `app1` | Tenant/application identifier. All resource names derive from it: `<tenant_id>-kv`, `<tenant_id>-azure-kv`, `<tenant_id>-secrets-sync-*`, `kv-<tenant_id>-<random>`, and synced secret `vault-<tenant_id>-<secret_name>`. Max 14 characters (Key Vault name limit). |
| `azure_location` | `eastus` | Azure region for the resource group and Key Vault. |
| `azure_audience` | `api://AzureADTokenExchange` | Token audience shared by the identity token, the OIDC key, and the federated identity credential. |
| `secret_name` | `my-secret` | Name of the demo secret inside the tenant's KV mount (letters, digits, hyphens only). |
