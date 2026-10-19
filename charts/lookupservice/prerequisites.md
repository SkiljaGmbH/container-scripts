## Prerequisites

This chart is a subchart. It can be deployed in two ways:

- **Standalone:** installed on its own with `helm install`. The chart's own `global:` block in
  `values.yaml` is used. Set the database and Auth Server connection there.
- **Inside the VIA umbrella chart:** the parent chart provides one shared `global:` block for all
  components. It takes precedence over the defaults in this chart's `values.yaml`. Values for this
  chart go under the `lookupservice:` key of the parent's values file.

Which settings live where:

| Setting | Standalone | Umbrella chart |
|---|---|---|
| `global.database.*` (server, user, password, `existingSecret`, serverType, SSL) | this chart's `values.yaml` | set once in the parent |
| `global.auth.serverUrl` | this chart's `values.yaml` | set once in the parent |
| `database.name`, `database.type` | this chart | this chart (`lookupservice.database.*`) |
| `auth.clientId`, `platform.*`, `config.*` | this chart | this chart (`lookupservice.*`) |

All application settings map to `LS_*` environment variables (see comments in `values.yaml`).

### 1. Database password secret (recommended)

```bash
kubectl create secret generic via-db-pw-secret \
  --from-literal=database-password=<YOUR_SECRET> \
  -n <namespace>
```

```yaml
global:
  database:
    existingSecret: "via-db-pw-secret"   # key: database-password
```

All components expect the same key `database-password`. Without `existingSecret`,
`global.database.password` is stored in the chart's own Secret `<release>-lookupservice-secrets`.

**DB password and `LS_DbPassword`:** the Lookup Service does not reliably pick up the password from
`LS_DbPassword` alone. With `database.passwordInConnectionStringAddendum: true` (default) the chart also
sets `LS_ConnectionStringAddendum: "Password=$(LS_DbPassword)"`. Kubernetes expands the reference from the
secret-backed variable, so the password never appears in the values or the rendered manifest (only at
runtime inside the container environment). Additional parameters from `database.connectionStringAddendum`
are appended with `;`. Avoid `;` and `=` in the password, they break the connection string.

The database type is derived from `global.database.serverType`
(0 → `SQLServer`, 2 → `PostgreSQL`). Oracle is not documented for the Lookup Service, the chart fails on `serverType: 1` unless `database.type` is set explicitly.

### 2. Auth Server and Vinna platform

- `platform.configServiceUrl` (required): URL of the Vinna runtime configuration service
  (`LS_ConfigurationService`). The host must be resolvable **inside the pod**.
- The Auth Server is discovered via the Vinna platform. `auth.clientId` is passed as `LS_ClientId`
  (default `LookupService`).

### Automatic OAuth client registration

With `auth.autoCreateAuthClients: true` (default), a Helm `post-install`/`post-upgrade` job registers the
**public** client `auth.clientId` (default `LookupService`) at the Auth Server, using the admin client from
`global.auth` (`adminClientId` + `existingAdminSecret` or `adminClientSecret`):

- Grant type Authorization Code, no client secret, no introspection, scopes `roles` and `profile`
  (permissions: `ept:authorization`, `gt:authorization_code`, `rst:code`, `ept:token`, `scp:roles`,
  `scp:profile`, `gt:refresh_token`, `ept:end_session`).
- Redirect URI: `https://<host><config.pathBase>/signin-oidc`
- Post-logout redirect URI: `https://<host><config.pathBase>/signout-callback-oidc`
- `<host>` is the first gateway hostname in Gateway mode, otherwise `ingress.hosts[0].host`. The URIs are
  lowercased, OIDC redirect URIs are case sensitive.

**An existing client with the same ID is skipped, not updated.** If the client already exists (e.g. from
another installation using the same Auth Server), add the new redirect URIs to it manually, or use a
different `auth.clientId`. Otherwise login fails with `ID2043` (invalid redirect_uri).

Set `auth.autoCreateAuthClients: false` to register the client manually.

Self-signed certificates (Auth Server, Vinna) are trusted via thumbprints in `config.trustedCertificates`
(`global.auth.trustCertificate` is not used by this service).

### 3. Storage (optional persistence)

Without persistence, logs are only available via the container console output (`kubectl logs`).
With `persistence.enabled: true`, one PVC (`<release>-lookupservice-data`) is mounted via subPaths:
`config.programDataPath` (default `/app/ProgramData`, file-based SQLite settings), 
`/app/Log` and `/app/certificates`. Set `persistence.storageClass` (e.g. `auto-ebs-sc`).

The image runs as non-root user `app` (UID/GID 1654); `podSecurityContext.fsGroup: 1654` makes the
volume writable.
For `replicaCount > 1` the programData folder must be shared by all instances, i.e. a ReadWriteMany
volume (`persistence.accessMode: ReadWriteMany` with an EFS StorageClass).

### 4. Data protection certificate (optional)

To use a custom data protection certificate, put the `.pfx` into the certificates volume and set
`config.dataProtection.certificatePath`. The password goes into the chart Secret
(`config.dataProtection.certificatePassword`) or an existing secret:

```bash
kubectl create secret generic lookupservice-dp-secret \
  --from-literal=dataprotection-certificate-password=<PFX_PASSWORD> \
  -n <namespace>
```

```yaml
config:
  dataProtection:
    certificatePath: "/app/certificates/default-cert.pfx"
    existingSecret: "lookupservice-dp-secret"   # key: dataprotection-certificate-password -> LS_DataProtectionCertificatePassword
```

### Health probes

Liveness probe: `<config.pathBase>/health/live`, readiness probe: `<config.pathBase>/health/ready`
(default `/lookupservice/health/live` and `/lookupservice/health/ready`). The probe paths in `values.yaml` are
relative to `config.pathBase`, so they follow a changed path base automatically. For the AWS ALB
health check use `alb.ingress.kubernetes.io/healthcheck-path: /lookupservice/health/ready`.

> **Note on sticky sessions:** not required for plain API calls. Keep `replicaCount: 1` unless a shared
> volume / database setup is in place (see Storage).

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

- Route: `PathPrefix /lookupservice`, taken from `config.pathBase`.
- Load balancer health check: `/lookupservice/health/ready`.
- Upload size / timeouts and sticky sessions: no special requirement.
  These are controller specific policies, see `umbrellas/README.md`.
