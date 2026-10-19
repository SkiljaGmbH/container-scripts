## Prerequisites

This chart is a subchart. It can be deployed in two ways:

- **Standalone:** installed on its own with `helm install`. The chart's own `global:` block in
  `values.yaml` is used.
- **Inside the VIA umbrella chart:** the parent chart provides one shared `global:` block. Values for
  this chart go under the `fieldreview:` key of the parent's values file.

Field Review is a static web frontend (nginx). It has **no database and no secret of its own**. The browser
talks directly to the Vinna runtime configuration service and the Auth Server.

Field Review additionally requires the **Validation Service** (subchart `validationservice`) and a
Vinna runtime installation.

### 1. Vinna runtime configuration service

Set the public URL of the Vinna runtime configuration service (reachable from the user's browser):

```yaml
servicesConfig:
  services:
    configurationService: "https://my.domain.com/rt"
    apiVersion: "2.1"
```

The chart renders `services.config.json` and `default.conf` (nginx) into a ConfigMap. Pods are rolled
automatically when either changes (`checksum/config` annotation).

### 2. Path base and ingress

`env.pathBase` (default `/fieldreview`) drives the nginx location blocks and the OAuth redirect URI.
It must match the ingress path (`/fieldreview*` for AWS ALB with `ImplementationSpecific`).

### 3. Admin client secret (only for automatic client registration)

Needed if `auth.autoCreateAuthClients: true`. The admin client is shared by all components and set once
in `global.auth`. Prefer `existingAdminSecret` over a plain value:

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

> **Client ID:** the FieldReview frontend logs in as `FieldReview`. `auth.webAppClientId` is only used by the
> registration job, the app does not receive it. Keep `FieldReview`. If several installations share one Auth
> Server, add the redirect URIs of each installation to the existing `FieldReview` client instead of using a
> different ID, and set `auth.autoCreateAuthClients: false`.

With `auth.autoCreateAuthClients: true`, a Helm `post-install`/`post-upgrade` job registers the
**public** client `auth.webAppClientId` (default `FieldReview`) with:

- Redirect URI and post-logout redirect URI: `https://<ingress.hosts[0].host><env.pathBase>`
  (e.g. `https://my.domain.com/fieldreview`, case sensitive)
- Permissions: `ept:authorization`, `gt:authorization_code`, `rst:code`, `scp:interactive`
  (Activities), `scp:unattended` (Activities Unattended), `ept:token`, `scp:profile`,
  `gt:refresh_token`, `ept:end_session`. No client secret, no introspection.

Notes:

- **An existing client with the same ID is skipped, not updated.** The auth chart's default seed file
  (`client_registration_seeding_defaults.json`) already creates a `FieldReview` client with sample redirect
  URIs (`https://k8s.contoso.com/fieldreview`). In that case login fails with `ID2043` (invalid
  redirect_uri). Fix: correct the redirect URIs of that client on the Auth Server, or delete it and run
  `helm upgrade` again, or remove it from the seed file before installing the auth chart.
- Only `ingress.hosts[0]` is registered, and the scheme is always `https`.
- The seed file uses `ept:logout`; the job uses `ept:end_session` (OpenIddict 5+ naming), same as all
  other clients registered by the shared script.

### Health probes

No health endpoint is documented. Liveness/readiness probes call `/` on the nginx port.

> **Note:** the app settings (`servicesConfig.defaultAppSettings`) are documented in the Field Review Help on
> the Skilja Partner Portal. Keys not listed fall back to app defaults.

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

- Route: `PathPrefix /fieldreview`, taken from `env.pathBase`.
- Load balancer health check: `/`.
- Upload size / timeouts and sticky sessions: no special requirement.
  These are controller specific policies, see `umbrellas/README.md`.
- The OAuth redirect URI uses the first hostname from `httpRoute.hostnames` / `global.gateway.hostnames`.
