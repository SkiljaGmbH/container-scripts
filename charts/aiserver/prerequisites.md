## Prerequisites

This chart is a subchart. It can be deployed in two ways:

- **Standalone:** installed on its own with `helm install`. There is no parent chart, so the chart's
  own `global:` block in `values.yaml` is used. Set the database and Auth Server connection there
  (or override it with `--set` / your own values file).
- **Inside the umbrella (root) chart:** the parent chart provides one shared `global:` block for all
  components. It takes precedence over the defaults in this chart's `values.yaml`, so the connection
  is configured once for everything. Values for this chart go under the `aiserver:` key of the
  parent's values file.

Which settings live where:

| Setting | Standalone | Umbrella chart |
|---|---|---|
| `global.database.*` (server, user, password, `existingSecret`) | this chart's `values.yaml` | set once in the parent |
| `global.auth.*` (`serverUrl`, `trustCertificate`, admin client) | this chart's `values.yaml` | set once in the parent |
| `database.name` | this chart | this chart (`aiserver.database.name`) |
| `auth.serverClientId`, `auth.serverClientSecret`, `auth.existingSecret`, `auth.autoCreateAuthClients` | this chart | this chart (`aiserver.auth.*`) |

The database secret and the admin client secret are therefore shared between components. The
AI Server client secret is specific to this chart, because every component registers its own client
at the Auth Server. The steps below apply to both ways. In the umbrella chart, set the `global.*`
values in the parent's values file instead of this chart's.

Create the secrets you want to manage yourself in the target namespace **before** `helm install`.
Everything that is left empty is handled by the chart (see "What the chart generates").

### 1. Database password secret (recommended)

```bash
kubectl create secret generic aiserver-db-pw-secret \
  --from-literal=database-password=<YOUR_SECRET> \
  -n <namespace>
```

```yaml
global:
  database:
    existingSecret: "aiserver-db-pw-secret"   # key: database-password
```

All components expect the same key `database-password`. Without `existingSecret`,
`global.database.password` is stored in the chart's own Secret.

### 2. AI Server client secret (recommended for production)

```bash
kubectl create secret generic aiserver-auth-secret \
  --from-literal=clientSecret=<YOUR_SECRET> \
  -n <namespace>
```

```yaml
auth:
  serverClientId: "AiServer_K8s"
  existingSecret: "aiserver-auth-secret"   # key: clientSecret
```

Precedence: `auth.existingSecret` > `auth.serverClientSecret` > generated random secret.

Using `existingSecret` is recommended for production: the secret survives `helm uninstall`, so the
secret in the cluster always matches the client registered on the Auth Server (see "Client secret and
Auth Server must match").

### 3. Admin client secret (only for automatic client registration)

Needed if `auth.autoCreateAuthClients: true`. The admin client is shared by all components and
configured once in `global.auth`. In the umbrella chart it is set once in the parent. It can create
and modify any OAuth client on the Auth Server, so prefer `existingAdminSecret` over a plain value.

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

### What the chart generates

If neither `auth.existingSecret` nor `auth.serverClientSecret` is set, the chart generates a random
32-character client secret on first install and keeps it stable across upgrades (it is stored in
`<release>-aiserver-secrets`). Standalone with release name `aiserver` the secret is called
`aiserver-secrets`, in the umbrella with release name `laera` it is `laera-aiserver-secrets`.

Read it with:

```bash
kubectl get secret <release>-aiserver-secrets -n <namespace> \
  -o jsonpath="{.data.clientSecret}" | base64 -d
```

PowerShell:

```powershell
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((kubectl get secret <release>-aiserver-secrets -n <namespace> -o jsonpath="{.data.clientSecret}")))
```

The generated secret is only stable while the Secret exists in the cluster. It is looked up from the
cluster on every upgrade. This has consequences:

- The secret is deleted together with the release (`helm uninstall`). A new install generates a **new**
  random secret.
- `helm template` and `helm install --dry-run=client` have no cluster access and generate a new value
  on every run. Do not apply the output of `helm template` directly, and use `auth.existingSecret`
  with GitOps tools (Argo CD, Flux) that render without cluster access.

### Automatic OAuth client registration

With `auth.autoCreateAuthClients: true`, a Helm `post-install`/`post-upgrade` job registers the
confidential client `auth.serverClientId` at the Auth Server. The job builds a base URL from
`https://<ingress.hosts[0].host><config.pathbase>` and registers:

- Redirect URI: `<base URL>/signin-oidc`
- Post-logout redirect URI: `<base URL>/signout-callback-oidc`

For example, with host `my.domain.com` and `config.pathbase: /aiserver`:

- `https://my.domain.com/aiserver/signin-oidc`
- `https://my.domain.com/aiserver/signout-callback-oidc`

Notes:

- The job runs after the regular resources are created. The pod may start before the client exists,
  so early login failures right after the first install are expected and resolve once the job has run.
- Only `ingress.hosts[0]` is registered, and the scheme is always `https`.
- **An existing client with the same ID is skipped, not updated.** The job never changes the secret or
  the redirect URIs of an existing client ("already exists. Skipping..."). To change them, delete the
  client in the Auth Server and run `helm upgrade` again, or correct the client manually.

Permissions set on the client: `ept:authorization`, `gt:authorization_code`, `rst:code`, `scp:roles`,
`ept:token`, `scp:profile`, `gt:refresh_token`, `ept:end_session`. The `client_credentials` grant is not
used by this client.

Without auto-registration, create the client manually, see
[Configuring the Authorization Server client](https://hub.docker.com/r/skilja/aiserver#configuring-the-authorization-server-client).

**When the job runs:** Helm starts it after all resources of the release are created. With
`helm install --wait`, Helm first waits until **all** pods of the release are Ready, in an umbrella
including the other components. If one pod never gets Ready, the job does not run and no client is
registered (login fails with `ID2052`). Without `--wait`, the job runs right after the resources are
created, independent of the pods. The app may then start before its clients exist; early login
failures right after the first install resolve once the job has run. See `umbrellas/README.md`.

### Client secret and Auth Server must match

Because existing clients are skipped, the secret in the cluster and the secret stored for the client on
the Auth Server can drift apart. Typical situations:

- The release is uninstalled (the generated secret is deleted, the client stays on the Auth Server) and
  installed again.
- An install fails and is repeated.
- The chart is deployed into a new namespace or cluster against the same Auth Server.

Typical symptoms:

- Login fails with `invalid_client` (client secret differs).
- Login fails with `ID2043` ("The specified 'redirect_uri' is not valid for this client application"):
  the client was registered with outdated redirect URIs, or host/path of the ingress changed.

How to avoid it:

- Use `auth.existingSecret` with a fixed secret (see step 2). It survives uninstall/reinstall.
- After an uninstall, delete the AI Server client on the Auth Server before the next install, unless you
  use `existingSecret` with the same value as before.

How to fix it:

1. Delete the client (`auth.serverClientId`) in the Auth Server.
2. Run `helm upgrade` (or `helm install`). The job registers the client again with the current secret
   and redirect URIs.

Alternatively, set the client secret on the Auth Server to the value read from the cluster (see above).

### Storage (persistence)

With `persistence.enabled: true`, a persistent volume is mounted at `/opt/Skilja/AIServer/Models`
and its content (downloaded model files) is kept across pod restarts. Without persistence the
directory is ephemeral and its content is gone after a restart. Remote model configurations are
stored in the database and are not affected by this setting.

Choose the volume type:

- `persistence.type: ebs`: ReadWriteOnce, single node. The StorageClass (e.g. `auto-ebs-sc`) must exist.
- `persistence.type: efs`: ReadWriteMany, multi-node. The StorageClass (e.g. `efs-sc`) must exist.

Size the volume for the content you want to keep (default 16Gi).

The volume is deleted together with the release if the StorageClass uses the reclaim policy `Delete`. After
`helm uninstall`, wait until the PVC is gone before installing again. Installing while the PVC is still
`Terminating` leaves the pod `Pending`.

> **TODO:** S3 as storage backend is not implemented yet. The goal is to share large models across
> pods and nodes without a local volume. The bucket and its permissions must be created beforehand.

### Startup and health probes

The AI Server needs time to start (database setup, LLM processes). The chart therefore uses a
`startupProbe` on `/healthz/ready` (default: up to 30 x 10 s = 5 minutes). Liveness and readiness probes
only start after the startup probe has succeeded. `/healthz/ready` is used on purpose: `/healthz/live` can
answer briefly before initialization is finished, and the pod would then be killed by the liveness probe
during the following busy phase.

If your cluster needs longer (CPU-only nodes, slow first start), raise `startupProbe.failureThreshold`.

### Cluster requirements

- Nodes with `kubernetes.io/arch: amd64` (an arm64 image exists but is not recommended for production).
- GPU mode (`gpu.enabled: true`): GPU nodes matching `gpu.nodeSelector`, and the taint
  `nvidia.com/gpu:NoSchedule` (any value) tolerated via `gpu.tolerations` (default).
- CPU-only mode (`gpu.enabled: false`): works with the same settings, but is much slower and not
  recommended for production. Keep `config.llm.maxProcessCount` / `config.llama.maxProcessCount` at `"1"`:
  `"0"` disables BERT / generative AI processing in the container (only for Gateway / load balancer mode).
- AWS ALB: ingress class, ACM certificate ARN, and the target-group attribute `stickiness.enabled=true`
  if more than one replica is used.
- Optional monitoring: an OpenTelemetry collector reachable at `config.monitoring.OTLP_ENDPOINT`.

> **Note on sticky sessions:** If `replicaCount > 1`, session affinity (LB `stickiness`) is required
> for SignalR/WebSocket connections. A safe workaround is a single replica during initial setup,
> then scale up (plain API calls are unaffected).

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

- Route: `PathPrefix /aiserver`, taken from `config.pathbase`.
- Load balancer health check: `/healthz/ready`.
- Upload size / timeouts: large uploads, 600 s. Sticky sessions: required if `replicaCount > 1`.
  These are controller specific policies, see `umbrellas/README.md`.
- The OAuth redirect URI uses the first hostname from `httpRoute.hostnames` / `global.gateway.hostnames`.
