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
  `https://<host>/aiserver/signout-callback-oidc`. Existing clients are not updated.
- The first start can take several minutes. The startup probe allows up to 5 minutes by default.
- Resources: `laera-aiserver`, Secret `laera-aiserver-secrets`, PVC `laera-aiserver-models`.

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
