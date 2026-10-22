# Umbrella charts

Each folder here is an umbrella chart that combines components from `../charts` as subcharts.

| Umbrella | Purpose |
|---|---|
| `umbrella-laera` | LAERA deployment (AI Server, Classification / Extraction Designer and Monitor, Site Management Tool) |
| `umbrella-via` | VIA deployment (Batch Review, Field Review, Validation Service, Lookup Service), requires an existing Vinna platform |

## How `global` works

Helm passes the `global:` block of an umbrella to every subchart. It overrides the standalone
fallback values in each subchart's own `values.yaml`.

- `global.database.*`: one database server, user and password for all components. Every component
  reads the password from the key `database-password`.
- `global.auth.*`: Auth Server URL and trust settings, plus the admin client used for automatic
  OAuth client registration.
- `global.gateway.*`: Ingress or Gateway API for all components. `enabled: false` (default) renders an
  Ingress per component, `enabled: true` renders an HTTPRoute instead, attached to an existing Gateway
  (`parentRefs`) with the given `hostnames`. The first hostname is also used for the OAuth redirect URIs.
  The route path is each component's path base. See "Gateway API (HTTPRoute) instead of Ingress" below.
- Component specific settings (database name, client ID, client secret, path base, ingress, httpRoute
  overrides) live under the component key, for example `validationservice:`.

```yaml
global:
  database:
    server: "my-db-cluster-rw.database"
    user: "app"
    existingSecret: "db-secret"              # key: database-password
  auth:
    serverUrl: "https://my.domain.com/auth"
    adminClientId: "AdminClient"
    existingAdminSecret: "auth-admin-secret" # key: admin-client-secret
  gateway:
    enabled: true                            # false = Ingress
    parentRefs:
      - name: shared-gateway
        namespace: gateway-infra
        sectionName: https
    hostnames:
      - my.domain.com
```

## Automatic OAuth client registration

With `autoCreateAuthClients: true` on a component, a Helm post-install/post-upgrade job registers
that component's clients at the Auth Server, using the admin client from `global.auth`. Existing
clients are skipped, not updated.

## Gateway API (HTTPRoute) instead of Ingress

All component charts support both Ingress (default) and Gateway API. Only one of both is rendered.
The **Gateway itself is not created** by these charts: it is shared infrastructure and must exist
before installing (Gateway API CRDs, GatewayClass of your controller, Gateway with an HTTPS listener and
certificate, `allowedRoutes` that admits the release namespace).

Switch all components at once in the umbrella:

```yaml
global:
  gateway:
    enabled: true
    parentRefs:
      - name: shared-gateway
        namespace: gateway-infra
        sectionName: https
    hostnames:
      - my.domain.com          # first entry is also used for the OAuth redirect URIs
```

Per component, `<component>.httpRoute.*` overrides the global values: `httpRoute.enabled: false` keeps
one component on Ingress, `parentRefs` / `hostnames` set a different Gateway or host. Each route uses
`PathPrefix` with the component's path base, so the route always matches the app path.
`httpRoute.timeouts` sets Gateway API rule timeouts (`request`, `backendRequest`) if your controller
supports them.

### Changing the path

The app path has a single source: the component's path base (`config.pathbase` for aiserver,
`config.pathBase` for validationservice / lookupservice, `env.pathBase` for all others).

- **Gateway mode:** change only the path base. The HTTPRoute `PathPrefix` and the OAuth redirect URI
  follow automatically. `ingress.*` is ignored.
- **Ingress mode:** change the path base **and** `ingress.hosts[].paths[].path` (e.g. `/validationservice*`).
  If both differ, the app no longer finds its pages and assets.
- A different external path than the app path (URL rewrite, e.g. `/vs` outside and `/validationservice` inside) is
  **not supported**: the apps build redirects and asset URLs from their path base, which breaks behind a
  rewrite. Existing OAuth clients keep their old redirect URIs (existing clients are skipped, not
  updated), so after a path change correct or delete the client on the Auth Server.

### Controller specific settings

Ingress annotations (ALB / NGINX) have no Gateway API equivalent for upload size, sticky sessions and
load balancer health checks. Configure them with the policy resources of **your** Gateway controller
(e.g. AWS Load Balancer Controller: `TargetGroupConfiguration` / `LoadBalancerConfiguration`; Envoy
Gateway: `ClientTrafficPolicy` / `BackendTrafficPolicy`; Cilium / NGINX Gateway Fabric: their policies).
Without them, large uploads or long requests fail at runtime, not at install time.

| Component (chart) | Path | Health check path | Upload size / timeouts | Sticky sessions |
|---|---|---|---|---|
| `batchreview` | `/batchreview` | `/` | default | - |
| `fieldreview` | `/fieldreview` | `/` | default | - |
| `validationservice` | `/validationservice` | `/validationservice/health/ready` | default | - |
| `lookupservice` | `/lookupservice` | `/lookupservice/health/ready` | default | - |
| `aiserver` | `/aiserver` | `/healthz/ready` | large uploads, 600 s | required if `replicaCount > 1` |
| `clsdesigner` | `/classificationdesigner` | `/healthz/ready` | 500 MB, 600 s | required if `replicaCount > 1` (SignalR) |
| `clsmonitor` | `/classificationmonitor` | `/healthz/ready` | 500 MB, 600 s | - |
| `iedesigner` | `/extractiondesigner` | `/healthz/ready` | 500 MB, 600 s | required if `replicaCount > 1` (SignalR) |
| `iemonitor` | `/extractionmonitor` | `/healthz/ready` | 500 MB, 600 s | - |

`default` = no special requirement. Health check paths are the readiness probe paths of the pods.

## Building an umbrella

```bash
cd umbrellas/<umbrella>
helm dependency update
helm lint .
helm template test .
```