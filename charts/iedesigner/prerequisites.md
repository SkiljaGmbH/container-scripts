## Prerequisites

This chart is a subchart. It can be deployed in two ways:

- **Standalone:** installed on its own with `helm install`. There is no parent chart, so the chart's own
  `global:` block in `values.yaml` is used. Set the database and Auth Server connection there (or override
  it with `--set` / your own values file).
- **Inside the umbrella (root) chart:** the parent chart provides one shared `global:` block for all
  components. It takes precedence over the defaults in this chart's `values.yaml`. Values for this chart go
  under the key of the subchart in the parent's values file.

Which settings live where:

| Setting | Standalone | Umbrella chart |
|---|---|---|
| `global.database.*` (server, user, password, `existingSecret`) | this chart's `values.yaml` | set once in the parent |
| `global.auth.*` (`serverUrl`, `trustCertificate`, admin client) | this chart's `values.yaml` | set once in the parent |
| `env.databaseName` | this chart | this chart |
| `auth.webAppClientId`, `auth.serverClientId`, `auth.serverClientSecret`, `auth.existingServerClientSecret`, `auth.autoCreateAuthClients` | this chart | this chart |

The database secret and the admin client secret are shared between components. The client secret of the
Extraction Designer is specific to this chart, because every component registers its own clients at the
Auth Server.

Create the secrets you want to manage yourself in the target namespace **before** `helm install`. Everything
that is left empty is handled by the chart (see "What the chart generates").

### Option A: Standalone chart (no umbrella / no `global` values provided)

#### 1. Create the extraction client secret (recommended for production)

```bash
kubectl create secret generic extraction-designer-auth-secret \
  --from-literal=extraction-client-secret=<YOUR_SECRET> \
  -n <namespace>
```

#### 2. Create the database password secret

```bash
kubectl create secret generic extraction-designer-db-pw-secret \
  --from-literal=database-password=<YOUR_SECRET> \
  -n <namespace>
```

All components expect the same key `database-password`.

#### 3. Create the admin client secret (only for automatic client registration)

Needed if `auth.autoCreateAuthClients: true` (default). The admin client can create and modify any OAuth
client on the Auth Server, so prefer `existingAdminSecret` over a plain value.

```bash
kubectl create secret generic auth-admin-secret \
  --from-literal=admin-client-secret=<ADMIN_SECRET> \
  -n <namespace>
```

#### 4. Reference the secrets in your values file

```yaml
auth:
  existingServerClientSecret: "extraction-designer-auth-secret"   # key: extraction-client-secret

global:
  database:
    existingSecret: "extraction-designer-db-pw-secret"            # key: database-password
  auth:
    serverUrl: "https://my.domain.com/auth"
    adminClientId: "<ADMIN_CLIENT_ID>"
    existingAdminSecret: "auth-admin-secret"                          # key: admin-client-secret
```

If you want to use MS Read OCR:

```bash
kubectl create secret generic extraction-designer-ocr-secret \
  --from-literal=microsoft-read-ocr-api-key=<YOUR_SECRET> \
  -n <namespace>
```

```yaml
ocr:
  existingMicrosoftReadOCRApiKeySecret: "extraction-designer-ocr-secret"
```

### Option B: Used within the umbrella chart (`global` values provided by the parent)

When deployed as part of the umbrella chart, the database connection and the admin client are shared and
managed centrally via the parent's `global` block. You do **not** create or reference a separate database or
admin secret at this chart's level. `global.database.existingSecret` (key `database-password`) and
`global.auth.existingAdminSecret` (key `admin-client-secret`), set once at the umbrella level, are used
automatically. See the umbrella's `prerequisites.md` for how to create them.

The extraction client secret is still chart-specific, so you only need to create it for this chart:

```bash
kubectl create secret generic extraction-designer-auth-secret \
  --from-literal=extraction-client-secret=<YOUR_SECRET> \
  -n <namespace>
```

Reference it in the parent's values file under the key of this subchart:

```yaml
auth:
  existingServerClientSecret: "extraction-designer-auth-secret"
```

If you want to use MS Read OCR, create the secret as in Option A and set
`ocr.existingMicrosoftReadOCRApiKeySecret`.

### What the chart generates

If neither `auth.existingServerClientSecret` nor `auth.serverClientSecret` is set, the chart generates a random
32-character secret for the confidential server client on first install and keeps it stable across upgrades.
It is stored in the chart's Secret `<fullname>-secrets` under the key `extraction-client-secret`. Find the
exact name with `kubectl get secret -n <namespace>`.

Read it with:

```bash
kubectl get secret <fullname>-secrets -n <namespace> \
  -o jsonpath="{.data.extraction-client-secret}" | base64 -d
```

PowerShell:

```powershell
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((kubectl get secret <fullname>-secrets -n <namespace> -o jsonpath="{.data.extraction-client-secret}")))
```

The generated secret is only stable while the Secret exists in the cluster. It is looked up from the cluster
on every upgrade. Consequences:

- The secret is deleted together with the release (`helm uninstall`). A new install generates a **new**
  random secret.
- `helm template` and `helm install --dry-run=client` have no cluster access and generate a new value on every
  run. Do not apply the output of `helm template` directly, and use `auth.existingServerClientSecret` with
  GitOps tools (Argo CD, Flux) that render without cluster access.

### Automatic OAuth client registration

With `auth.autoCreateAuthClients: true`, a Helm `post-install`/`post-upgrade` job registers two clients at the
Auth Server:

| Client | Values | Type | Secret |
|---|---|---|---|
| Web app | `auth.webAppClientId` (`ExtrWebDesignerWeb`) | public (authorization code, browser) | none |
| Server | `auth.serverClientId` (`ExtrWebDesignerServer`) | confidential (client credentials, machine-to-machine) | extraction client secret |

The redirect URI and the post-logout redirect URI of the web app client are both
`https://<host><env.pathBase>`, for example `https://my.domain.com/extractiondesigner`. `<host>` is the first
gateway hostname in Gateway mode, otherwise `ingress.hosts[0].host`. Only this one host is registered,
and the scheme is always `https`.

Notes:

- **When the job runs:** Helm starts it after all resources of the release are created. With
  `helm install --wait`, Helm first waits until **all** pods of the release are Ready, in an umbrella
  including the other components. If one pod never gets Ready, the job does not run and no client is
  registered (login fails with `ID2052`). Without `--wait`, the job runs right after the resources are
  created, independent of the pods. The app may then start before its clients exist; early login
  failures right after the first install resolve once the job has run. See `umbrellas/README.md`.
- **Existing clients are skipped, not updated.** The job never changes the secret or the redirect URIs of an
  existing client ("already exists. Skipping..."). To change them, delete the client in the Auth Server and run
  `helm upgrade` again, or correct the client manually.

### Client secret and Auth Server must match

Because existing clients are skipped, the secret in the cluster and the secret stored for the server client on
the Auth Server can drift apart, for example when:

- the release is uninstalled (the generated secret is deleted, the clients stay on the Auth Server) and
  installed again,
- an install fails and is repeated,
- the chart is deployed into a new namespace or cluster against the same Auth Server.

Typical symptoms: the Designer cannot obtain tokens (`invalid_client` in the log), or the browser login fails
with `ID2043` (invalid `redirect_uri`) when the web app client was registered with outdated URIs.

How to avoid it: use `auth.existingServerClientSecret` with a fixed secret (see above). After an uninstall,
delete `ExtrWebDesignerWeb` and `ExtrWebDesignerServer` on the Auth Server before the next install, unless you
use `existingServerClientSecret` with the same value as before.

How to fix it: delete the affected client in the Auth Server and run `helm upgrade`. The job registers it again
with the current secret and URIs.

### Permissions set on the extraction designer clients

If `autoCreateAuthClients` registers these clients automatically, the permission sets used are:

```
# Public client (auth.webAppClientId)
ept:authorization, gt:authorization_code, rst:code, ept:token,
scp:profile, gt:refresh_token, ept:end_session

# Confidential client (auth.serverClientId)
gt:client_credentials, ept:introspection, scp:email, scp:roles,
ept:token, scp:profile
```

Without auto-registration, create the clients manually with the same permissions.

> **Note on sticky sessions:** If `replicaCount > 1`, session affinity (LB `stickiness`) is required for
> SignalR/WebSocket connections. If stickiness isn't working, a safe workaround is to run with a single replica
> during initial setup/configuration, then scale up afterward (plain API calls are unaffected by sticky
> sessions).

### Gateway API (HTTPRoute) instead of Ingress

Set `httpRoute.enabled: true` (or `global.gateway.enabled: true` in the umbrella) to render an
`HTTPRoute` instead of the Ingress. The Gateway must already exist, it is not created by this chart.

```yaml
httpRoute:
  enabled: true
  parentRefs:
    - name: shared-gateway
      namespace: gateway-infra
      sectionName: https
  hostnames:
    - my.domain.com
```

- Route: `PathPrefix /extractiondesigner`, taken from `env.pathBase`.
- Load balancer health check: `/healthz/ready`.
- Upload size / timeouts: 500 MB, 600 s. Sticky sessions: required if `replicaCount > 1` (SignalR).
  These are controller specific policies, see `umbrellas/README.md`.
- The OAuth redirect URI uses the first hostname from `httpRoute.hostnames` / `global.gateway.hostnames`.
