## Prerequisites

This chart is a subchart. It can be deployed in two ways:

- **Standalone:** installed on its own with `helm install`. The chart's own `global:` block in
  `values.yaml` is used. Set the database and Auth Server connection there.
- **Inside the umbrella (root) chart:** the parent chart provides one shared `global:` block for all
  components. It takes precedence over the defaults in this chart's `values.yaml`. Values for this chart go
  under the `extraction-monitor:` key of the parent's values file.

Which settings live where:

| Setting | Standalone | Umbrella chart |
|---|---|---|
| `global.database.*` (server, user, password, `existingSecret`, serverType) | this chart's `values.yaml` | set once in the parent |
| `global.auth.*` (`serverUrl`, admin client) | this chart's `values.yaml` | set once in the parent |
| `env.olDatabaseName`, `env.projDatabaseName`, `env.ol*` / `env.proj*` SSL settings | this chart | this chart |
| `auth.webAppClientId`, `auth.serverClientId`, `auth.serverClientSecret`, `auth.existingServerClientSecret`, `auth.autoCreateAuthClients` | this chart | this chart |

The Extraction Monitor uses two databases: its own Online Learning database (`env.olDatabaseName`, default
`OLExtraction`) and the project database of the designer (`env.projDatabaseName`, default `ExtractionProjects`). The project
database name must match `extraction-designer.env.databaseName`. The SSL / trust settings of both databases are set in
`env.ol*` / `env.proj*`, they are **not** taken from `global.database`.

### 1. Database password secret (recommended)

```bash
kubectl create secret generic extraction-monitor-db-pw-secret \
  --from-literal=database-password=<YOUR_SECRET> \
  -n <namespace>
```

```yaml
global:
  database:
    existingSecret: "extraction-monitor-db-pw-secret"   # key: database-password
```

All components expect the same key `database-password`.

### 2. Server client secret (recommended for production)

```bash
kubectl create secret generic extraction-monitor-auth-secret \
  --from-literal=extraction-client-secret=<YOUR_SECRET> \
  -n <namespace>
```

```yaml
auth:
  existingServerClientSecret: "extraction-monitor-auth-secret"   # key: extraction-client-secret
```

Precedence: `auth.existingServerClientSecret` > `auth.serverClientSecret` > generated random secret. The
generated secret is stored in the chart's Secret `<release>-extraction-monitor-secrets` and kept stable across
upgrades, but it is deleted with `helm uninstall`.

### 3. Admin client secret (only for automatic client registration)

Needed if `auth.autoCreateAuthClients: true` (default). The admin client is shared by all components and
set once in `global.auth`. Prefer `existingAdminSecret` over a plain value:

```bash
kubectl create secret generic auth-admin-secret \
  --from-literal=admin-client-secret=<ADMIN_SECRET> \
  -n <namespace>
```

```yaml
global:
  auth:
    serverUrl: "https://my.domain.com/auth"
    adminClientId: "<ADMIN_CLIENT_ID>"
    existingAdminSecret: "auth-admin-secret"   # key: admin-client-secret
```

### Automatic OAuth client registration

With `auth.autoCreateAuthClients: true`, a Helm `post-install`/`post-upgrade` job registers two clients:

- **Web client** `auth.webAppClientId` (default `ExtrOLMonitorWeb`): public, Authorization Code, scope Profile.
  Redirect and post-logout redirect URI: `https://<host><env.pathBase>` (e.g. `https://my.domain.com/extractionmonitor`).
- **Server client** `auth.serverClientId` (default `ExtrOLMonitorServer`): confidential, Client Credentials,
  introspection, scopes Profile, Email, Roles. Its secret is the server client secret from step 2.

`<host>` is the first gateway hostname in Gateway mode, otherwise `ingress.hosts[0].host`. **Existing clients
are skipped, not updated**: after a host or path change, or after a reinstall with a new generated secret,
correct the client on the Auth Server or delete it and run `helm upgrade` again.

Set `auth.autoCreateAuthClients: false` to register the clients manually.

> **Note on secret key names:** the key name inside each secret (`--from-literal=<key>=...`) must exactly
> match what the templates expect (`database-password`, `extraction-client-secret`, `admin-client-secret`). The secret's
> own resource name is free-form and only needs to match the `existing*Secret` value.

**When the job runs:** Helm starts it after all resources of the release are created. With
`helm install --wait`, Helm first waits until **all** pods of the release are Ready, in an umbrella
including the other components. If one pod never gets Ready, the job does not run and no client is
registered (login fails with `ID2052`). Without `--wait`, the job runs right after the resources are
created, independent of the pods. The app may then start before its clients exist; early login
failures right after the first install resolve once the job has run. See `umbrellas/README.md`.

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

- Route: `PathPrefix /extractionmonitor`, taken from `env.pathBase`.
- Load balancer health check: `/healthz/ready`.
- Upload size / timeouts: 500 MB, 600 s. Sticky sessions: -.
  These are controller specific policies, see `umbrellas/README.md`.
- The OAuth redirect URI uses the first hostname from `httpRoute.hostnames` / `global.gateway.hostnames`.
