## Prerequisites (umbrella-laera)

This umbrella chart deploys the LAERA components as subcharts. Shared settings are configured once
under `global:` in `values.yaml`. See [../README.md](../README.md) for how `global` works.

The document has two parts:

- **General** (sections A to D): applies to the whole umbrella, independent of the components.
- **Modules** (from section "Module 1" on): one section per component with everything that is specific
  to it. New components are appended at the end of the file (see "Adding a new module").

### Components

| # | Component | Subchart key | Enable flag | Details |
|---|---|---|---|---|
| 1 | AI Server | `aiserver` | `aiserver.enabled` | [Module 1: AI Server](#module-1-ai-server) |
| 2 | Classification Designer | `classification-designer` | `classification-designer.enabled` | [Module 2: Classification Designer](#module-2-classification-designer) |
| 3 | Classification Monitor | `classification-monitor` | `classification-monitor.enabled` | [Module 3: Classification Monitor](#module-3-classification-monitor) |
| 4 | Extraction Designer | `extraction-designer` | `extraction-designer.enabled` | [Module 4: Extraction Designer](#module-4-extraction-designer) |
| 5 | Extraction Monitor | `extraction-monitor` | `extraction-monitor.enabled` | [Module 5: Extraction Monitor](#module-5-extraction-monitor) |
| 6 | Site Management Tool | `site-management-tool` | `site-management-tool.enabled` | [Module 6: Site Management Tool](#module-6-site-management-tool) |

---

## General

### A. How values reach the subcharts

- `global:` is shared by all subcharts. Each subchart reads it as `.Values.global.*`. It takes precedence
  over the standalone fallbacks in the subchart's own `values.yaml`.
- Values for a component go under the key of its subchart (for example `aiserver:`). Everything not set
  there falls back to the defaults in the subchart's `values.yaml`. Maps are merged, lists are replaced.
- The key must match the dependency name (or `alias`) in this chart's `Chart.yaml`.
- `global.gateway.*` switches all components between Ingress (`enabled: false`, default) and Gateway API
  (`enabled: true`, one HTTPRoute per component, attached to an existing Gateway via `parentRefs`, with
  `hostnames`). The first hostname is used for the OAuth redirect URIs, the route path is the component's
  path base. A component can override it under `<component>.httpRoute.*`. See
  [../README.md](../README.md#gateway-api-httproute-instead-of-ingress).

### B. Shared secrets (created once, before `helm install`)

```bash
kubectl create secret generic laera-db-secret \
  --from-literal=database-password=<YOUR_SECRET> \
  --from-literal=CLSSERVICE_CLSSSQLPASSWORD=<YOUR_SECRET> \
  --from-literal=CLSDESIGNER_SQLPASSWORD=<YOUR_SECRET> \
  --from-literal=OLCLS_OLSQLPASSWORD=<YOUR_SECRET> \
  --from-literal=EXTRSERVICE_EXTRSSQLPASSWORD=<YOUR_SECRET> \
  --from-literal=EXTRDESIGNER_SQLPASSWORD=<YOUR_SECRET> \
  --from-literal=OLEXTR_OLSQLPASSWORD=<YOUR_SECRET> \
  -n <namespace>

kubectl create secret generic laera-auth-admin-secret \
  --from-literal=admin-client-secret=<ADMIN_SECRET> \
  -n <namespace>
```

```yaml
global:
  database:
    existingSecret: "laera-db-secret"            # key: database-password
  auth:
    serverUrl: "https://my.domain.com/auth"
    adminClientId: "<ADMIN_CLIENT_ID>"
    existingAdminSecret: "laera-auth-admin-secret"   # key: admin-client-secret
```

All components read `database-password`. The six other keys (same password) are only read by the
Site Management Tool (Module 6), which is enabled by default. Without them its CLI cannot connect.

The admin secret is only needed if a component sets `autoCreateAuthClients: true`. It is shared by all
components. It can create and modify any OAuth client on the Auth Server, so use `existingAdminSecret`.

### C. Install

```powershell
helm dependency update .
helm upgrade --install laera . -n <namespace> -f values.yaml --timeout 10m
kubectl wait deployment -n <namespace> -l app.kubernetes.io/instance=laera --for=condition=Available --timeout=15m
```

No `--wait` on purpose: with `--wait`, the OAuth registration jobs run only after **all** pods are Ready.
`kubectl wait` shows the same result per component. See
[../README.md](../README.md#automatic-oauth-client-registration).

Notes:

- The subcharts are packaged into `charts/*.tgz` by `helm dependency update`. These archives are not
  committed to Git. **Run `helm dependency update` after checkout and after every change in a
  subchart under `charts/`**, otherwise the umbrella deploys the old version.
- With `--wait`, one pod that never gets Ready (e.g. a designer without license, the AI Server still
  pulling its image) blocks the OAuth registration of all components.
- With release name `laera` the resources are named `laera-<component>`, for example `laera-aiserver`
  (Deployment, Service, Ingress, Secret `laera-aiserver-secrets`, PVC `laera-aiserver-models`). Other
  services that call a component by its Service name must use this name.

### D. Uninstall and reinstall

```bash
helm uninstall laera -n <namespace>
```

Before installing again:

- Wait until the PVCs of the release are gone (`kubectl get pvc -n <namespace>`). Installing while a PVC
  is still `Terminating` leaves the pod `Pending`.
- Delete the OAuth clients of the components on the Auth Server, unless the component uses
  `existingSecret` with the same secret as before. The registration job skips clients that already
  exist and never updates their secret or redirect URIs.

### Component client secrets (applies to every module)

Every component registers its own OAuth client at the Auth Server and has its own client secret. If you
do not provide one, the chart generates a random secret on first install and keeps it in the release's
Secret. That secret is **deleted with the release** while the client stays on the Auth Server. After a
reinstall the secrets no longer match and login fails with `invalid_client`.

For production, create the client secret of each component yourself and reference it in its module
section.

---

## Modules

Each module section follows the same structure:

1. Subchart key and enable flag
2. Secrets to create beforehand
3. Values to set in the umbrella's `values.yaml`
4. Module-specific notes
5. Link to the component's own `prerequisites.md`

### Module 1: AI Server

**Subchart key:** `aiserver` | **Enable flag:** `aiserver.enabled` | **Details:**
[charts/aiserver/prerequisites.md](../../charts/aiserver/prerequisites.md)

**Secrets to create beforehand (recommended for production):**

```bash
kubectl create secret generic laera-aiserver-auth-secret \
  --from-literal=clientSecret=<YOUR_SECRET> \
  -n <namespace>
```

**Values to set:**

```yaml
aiserver:
  enabled: true
  auth:
    autoCreateAuthClients: true
    serverClientId: "AiServer_K8s"
    existingSecret: "laera-aiserver-auth-secret"   # key: clientSecret
  ingress:
    className: "<ingress class>"
    hosts:
      - host: my.domain.com
        paths:
          - path: /aiserver*
            pathType: ImplementationSpecific
  persistence:
    type: ebs                                       # ebs (RWO) or efs (RWX)
  gpu:
    enabled: false                                  # CPU-only works, but slow; keep config.llm/llama.maxProcessCount at "1"
```

**Notes:**

- The OAuth client is registered with the redirect URIs `https://<host>/aiserver/signin-oidc` and
  `https://<host>/aiserver/signout-callback-oidc`. `<host>` is the first gateway hostname in Gateway
  mode, otherwise the first ingress host. Existing clients are not updated.
- The first start can take several minutes. The startup probe allows up to 5 minutes by default.
- Resources: `laera-aiserver`, Secret `laera-aiserver-secrets`, PVC `laera-aiserver-models`.

---

### Module 2: Classification Designer

**Subchart key:** `classification-designer` | **Enable flag:** `classification-designer.enabled` | **Details:**
[charts/clsdesigner/prerequisites.md](../../charts/clsdesigner/prerequisites.md)

**Secrets to create beforehand (recommended for production):**

```bash
kubectl create secret generic laera-classification-designer-auth-secret \
  --from-literal=classification-client-secret=<YOUR_SECRET> \
  -n <namespace>
```

**Values to set:**

```yaml
classification-designer:
  enabled: true
  env:
    pathBase: "/classificationdesigner"
    databaseName: "ClassificationProjects"
    license: "<LICENSE>"                            # required, the pod does not start without a valid license
  auth:
    autoCreateAuthClients: true
    webAppClientId: "ClsWebDesignerWeb"
    serverClientId: "ClsWebDesignerServer"
    existingServerClientSecret: "laera-classification-designer-auth-secret"   # key: classification-client-secret
  monitor:
    installed: true                                 # only if classification-monitor is enabled too
    endpoint: "https://my.domain.com/classificationmonitor"
  gpu:
    enabled: false                                  # true: image tag "-llm-cuda", GPU node (taint nvidia.com/gpu)
  lesa:
    useGpu: false                                   # CPU-only setup (chart default is true)
```

**Notes:**

- Two OAuth clients: web client `ClsWebDesignerWeb` (public, redirect URI `https://<host>/classificationdesigner`) and server client
  `ClsWebDesignerServer` (confidential, client credentials). Existing clients are not updated.
- The license is a plain string in the values. Keep it out of Git (use a local values file or `--set`).
- `replicaCount > 1` requires sticky sessions (SignalR), see the controller table in
  [../README.md](../README.md#controller-specific-settings).
- Resources: `laera-classification-designer`, Secret `laera-classification-designer-secrets`.

---

### Module 3: Classification Monitor

**Subchart key:** `classification-monitor` | **Enable flag:** `classification-monitor.enabled` | **Details:**
[charts/clsmonitor/prerequisites.md](../../charts/clsmonitor/prerequisites.md)

**Secrets to create beforehand (recommended for production):**

```bash
kubectl create secret generic laera-classification-monitor-auth-secret \
  --from-literal=classificationmonitor-client-secret=<YOUR_SECRET> \
  -n <namespace>
```

**Values to set:**

```yaml
classification-monitor:
  enabled: true
  env:
    pathBase: "/classificationmonitor"
    olDatabaseName: "OLClassification"
    projDatabaseName: "ClassificationProjects"                   # must match classification-designer.env.databaseName
    # Not taken from global.database, set them explicitly:
    olUseSSL: "false"
    olTrustCertificate: "true"
    projUseSSL: "false"
    projTrustCertificate: "true"
  auth:
    autoCreateAuthClients: true
    webAppClientId: "ClsOLMonitorWeb"
    serverClientId: "ClsOLMonitorServer"
    existingServerClientSecret: "laera-classification-monitor-auth-secret"   # key: classificationmonitor-client-secret
  gpu:
    enabled: false
```

**Notes:**

- Two OAuth clients: web client `ClsOLMonitorWeb` (public, redirect URI `https://<host>/classificationmonitor`) and server client
  `ClsOLMonitorServer` (confidential, client credentials). Existing clients are not updated.
- Uses two databases: its own Online Learning database and the project database of the designer.
- Set `classification-designer.monitor.installed: true` and `.endpoint` so the designer uses the monitor.
- Resources: `laera-classification-monitor`, Secret `laera-classification-monitor-secrets`.

---

### Module 4: Extraction Designer

**Subchart key:** `extraction-designer` | **Enable flag:** `extraction-designer.enabled` | **Details:**
[charts/iedesigner/prerequisites.md](../../charts/iedesigner/prerequisites.md)

**Secrets to create beforehand (recommended for production):**

```bash
kubectl create secret generic laera-extraction-designer-auth-secret \
  --from-literal=extraction-client-secret=<YOUR_SECRET> \
  -n <namespace>
```

**Values to set:**

```yaml
extraction-designer:
  enabled: true
  env:
    pathBase: "/extractiondesigner"
    databaseName: "ExtractionProjects"
    license: "<LICENSE>"                            # required, the pod does not start without a valid license
  auth:
    autoCreateAuthClients: true
    webAppClientId: "ExtrWebDesignerWeb"
    serverClientId: "ExtrWebDesignerServer"
    existingServerClientSecret: "laera-extraction-designer-auth-secret"   # key: extraction-client-secret
  monitor:
    installed: true                                 # only if extraction-monitor is enabled too
    endpoint: "https://my.domain.com/extractionmonitor"
  gpu:
    enabled: false                                  # true: image tag "-llm-cuda", GPU node (taint nvidia.com/gpu)
  lesa:
    useGpu: false                                   # CPU-only setup (chart default is true)
```

**Notes:**

- Two OAuth clients: web client `ExtrWebDesignerWeb` (public, redirect URI `https://<host>/extractiondesigner`) and server client
  `ExtrWebDesignerServer` (confidential, client credentials). Existing clients are not updated.
- The license is a plain string in the values. Keep it out of Git (use a local values file or `--set`).
- `replicaCount > 1` requires sticky sessions (SignalR), see the controller table in
  [../README.md](../README.md#controller-specific-settings).
- Resources: `laera-extraction-designer`, Secret `laera-extraction-designer-secrets`.

---

### Module 5: Extraction Monitor

**Subchart key:** `extraction-monitor` | **Enable flag:** `extraction-monitor.enabled` | **Details:**
[charts/iemonitor/prerequisites.md](../../charts/iemonitor/prerequisites.md)

**Secrets to create beforehand (recommended for production):**

```bash
kubectl create secret generic laera-extraction-monitor-auth-secret \
  --from-literal=extraction-client-secret=<YOUR_SECRET> \
  -n <namespace>
```

**Values to set:**

```yaml
extraction-monitor:
  enabled: true
  env:
    pathBase: "/extractionmonitor"
    olDatabaseName: "OLExtraction"
    projDatabaseName: "ExtractionProjects"                   # must match extraction-designer.env.databaseName
    # Not taken from global.database, set them explicitly:
    olUseSSL: "false"
    olTrustCertificate: "true"
    projUseSSL: "false"
    projTrustCertificate: "true"
  auth:
    autoCreateAuthClients: true
    webAppClientId: "ExtrOLMonitorWeb"
    serverClientId: "ExtrOLMonitorServer"
    existingServerClientSecret: "laera-extraction-monitor-auth-secret"   # key: extraction-client-secret
  gpu:
    enabled: false
```

**Notes:**

- Two OAuth clients: web client `ExtrOLMonitorWeb` (public, redirect URI `https://<host>/extractionmonitor`) and server client
  `ExtrOLMonitorServer` (confidential, client credentials). Existing clients are not updated.
- Uses two databases: its own Online Learning database and the project database of the designer.
- Set `extraction-designer.monitor.installed: true` and `.endpoint` so the designer uses the monitor.
- Resources: `laera-extraction-monitor`, Secret `laera-extraction-monitor-secrets`.

---

### Module 6: Site Management Tool

**Subchart key:** `site-management-tool` | **Enable flag:** `site-management-tool.enabled` (default `true`) |
**Details:** [charts/sitemanagement/prerequisites.md](../../charts/sitemanagement/prerequisites.md)

Interactive CLI to grant initial rights (license managers, organization admins, organizations). The chart
creates only a Secret with the database connection variables of all modules, no running workload.

**Secrets to create beforehand:** none of its own. With `global.database.existingSecret`, that secret needs
the six additional keys listed in section B.

**Usage:**

- Run it once after the first install, **after** the module pods were Ready once (their first start
  creates the databases), and again after adding a module.
- `helm install` / `helm upgrade` print the complete steps (CLI pod manifest with Secret name, namespace
  and image). Show them again with `helm get notes laera -n <namespace>`.
- After granting rights, restart the module pods, then delete the CLI pod.
- Resources: Secret `laera-site-management-tool-secrets`.

---

## Adding a new module

1. Add the subchart as a dependency in `Chart.yaml` (with `condition: <key>.enabled`) and run
   `helm dependency update`.
2. Add its entry to the table under "Components" (next number, subchart key, enable flag, link).
3. Copy the template below to the **end of this file**, increase the module number and fill it in.
4. Check whether the component needs new entries in the shared sections A to D. Usually it does not.

<!--
### Module N: <Component name>

**Subchart key:** `<key>` | **Enable flag:** `<key>.enabled` | **Details:**
[charts/<chart>/prerequisites.md](../../charts/<chart>/prerequisites.md)

**Secrets to create beforehand:**

```bash
kubectl create secret generic laera-<key>-<purpose>-secret \
  --from-literal=<key-name>=<YOUR_SECRET> \
  -n <namespace>
```

**Values to set:**

```yaml
<key>:
  enabled: true
  # component-specific settings
```

**Notes:**

- Redirect URIs / ingress paths / special requirements.
- Resource names with release name `laera`.
-->
