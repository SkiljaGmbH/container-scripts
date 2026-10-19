## VIA umbrella chart

Installs the four VIA modules as subcharts:

| Subchart | Image | Purpose |
|---|---|---|
| `batchreview` | `skilja/vinna_batchreview` | Batch Review web frontend (nginx) |
| `fieldreview` | `skilja/vinna_fieldreview` | Field Review web frontend (nginx), requires `validationservice` |
| `validationservice` | `skilja/validationservice` | Validation Service backend (database) |
| `lookupservice` | `skilja/lookupservice` | Lookup Service backend (database) |

Each module is switched on/off with `<subchart>.enabled` (used as dependency `condition`).

### Requirements outside this chart

- A running **Vinna platform** (runtime config service, process editor). Its URLs are set per module:
  `batchreview.servicesConfig.services.configurationService`,
  `fieldreview.servicesConfig.services.configurationService`, `lookupservice.platform.configServiceUrl`,
  `validationservice.platform.designerUrl`.
- A running **Auth Server** (`global.auth.serverUrl`). With `autoCreateAuthClients: true` the admin client
  (`global.auth.adminClientId` + `existingAdminSecret`) is used to register the public clients
  `BatchReview`, `FieldReview`, `ValidationService` and `LookupService`.
- A database server (`global.database.*`), shared by Validation Service and Lookup Service, each with its
  own database name. The services create their databases on first start, so the DB user needs the right to
  create databases (PostgreSQL: `ALTER ROLE <user> CREATEDB;`, with CloudNativePG `createdb: true` under
  `spec.managed.roles`). Otherwise the first start fails with `permission denied to create database`.
  Alternative: create the databases up front with the DB creation scripts that exist for all modules
  (e.g. run by a DBA). Then the DB user does not need `CREATEDB`, only access to these databases.
  The database names must match `<module>.database.name`.

### Secrets

Create the secrets in the target namespace **before** installing. The key names inside the secrets are
fixed, the secret names are free and only have to match the values.

**Database password** (shared by Validation Service and Lookup Service, key `database-password`):

```bash
kubectl create namespace <namespace>
kubectl create secret generic via-db-secret \
  --from-literal=database-password=<DB_PASSWORD> \
  -n <namespace>
```

PowerShell:

```powershell
kubectl create namespace <namespace>
kubectl create secret generic via-db-secret `
  --from-literal=database-password=<DB_PASSWORD> `
  -n <namespace>
```

```yaml
global:
  database:
    existingSecret: "via-db-secret"   # key: database-password
    password: ""                      # leave empty when existingSecret is set
```

> **CloudNativePG:** CNPG stores the password of the app user in the secret `<cluster>-app` (key
> `password`) in the database namespace. A pod cannot reference a secret in another namespace and the key
> name differs, so copy the value into a new secret (PowerShell):
>
> ```powershell
> $pw = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(
>   (kubectl get secret <cluster>-app -n <db-namespace> -o jsonpath="{.data.password}")))
> kubectl create secret generic via-db-secret --from-literal=database-password=$pw -n <namespace>
> ```

**Admin client secret** (only for `autoCreateAuthClients: true`, key `admin-client-secret`):

```bash
kubectl create secret generic auth-admin-secret \
  --from-literal=admin-client-secret=<ADMIN_CLIENT_SECRET> \
  -n <namespace>
```

PowerShell:

```powershell
kubectl create secret generic auth-admin-secret `
  --from-literal=admin-client-secret=<ADMIN_CLIENT_SECRET> `
  -n <namespace>
```

```yaml
global:
  auth:
    adminClientId: "AdminClient"
    existingAdminSecret: "auth-admin-secret"   # key: admin-client-secret
    adminClientSecret: ""                      # leave empty when existingAdminSecret is set
```

Check a secret (PowerShell):

```powershell
kubectl get secret via-db-secret -n <namespace> -o jsonpath="{.data.database-password}"
```

The output is base64, an empty result means the key name is wrong.

### Install

The subcharts are referenced via `file://../../charts/<subchart>`. Build the `charts/` folder first
(run from `umbrellas/umbrella-via`):

```bash
helm dependency update .
helm upgrade --install via . -n <namespace> -f my-via-values.yaml --wait --timeout 10m
```

PowerShell:

```powershell
helm dependency update .
helm upgrade --install via . -n <namespace> -f my-via-values.yaml --wait --timeout 10m
```

Rerun `helm dependency update` after every change in a subchart, otherwise the old packaged version in
`charts/` is used.

Details on secrets, OAuth clients and storage: see `prerequisites.md` of each subchart.

### Gateway API instead of Ingress

Set `global.gateway.enabled: true` plus `global.gateway.parentRefs` / `hostnames` to render HTTPRoutes
instead of Ingresses for all four modules. The Gateway must already exist. Details and the controller
specific settings per component: `../README.md`.

### Changing the paths

Each module has exactly one path setting. In Gateway mode it is the only thing to change, in Ingress mode
the ingress path must be changed as well.

| Module | Path setting (default) | Ingress mode, additionally |
|---|---|---|
| Batch Review | `batchreview.env.pathBase` (`/batchreview`) | `batchreview.ingress.hosts[].paths[].path` (`/batchreview*`) |
| Field Review | `fieldreview.env.pathBase` (`/fieldreview`) | `fieldreview.ingress.hosts[].paths[].path` |
| Validation Service | `validationservice.config.pathBase` (`/validationservice`) | `validationservice.ingress.hosts[].paths[].path` |
| Lookup Service | `lookupservice.config.pathBase` (`/lookupservice`) | `lookupservice.ingress.hosts[].paths[].path` |

```yaml
validationservice:
  config:
    pathBase: "/vs"
  ingress:                      # Ingress mode only
    hosts:
      - host: my.domain.com
        paths:
          - path: /vs*
            pathType: ImplementationSpecific
```

What follows the path base automatically: HTTPRoute `PathPrefix` (Gateway mode), the app setting
(`VCPV_SERVICEPATHBASE` / `LS_ServicePathBase`, nginx `location` blocks for Batch / Field Review), the probes
of Validation / Lookup Service and the redirect URIs of the registration job.

What does **not** follow automatically:

- **OAuth clients that already exist** keep their old redirect URIs (existing clients are skipped). Add the
  new URIs on the Auth Server.
- **References from other components**: wherever the Vinna platform or other apps are configured with the
  URL of the Validation Service or Lookup Service, that URL has to be changed as well.
- **AWS ALB health check annotation** (`alb.ingress.kubernetes.io/healthcheck-path`), if set.
- **Batch / Field Review** under a path other than the default is supported by the chart (nginx rewrites
  the prefix), but has not been tested with every app version. Check that the app and its assets load
  after the change.

### Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `helm install --wait` times out, release `failed` | One pod never gets ready. The OAuth registration jobs (`post-install`) only run after **all** pods are ready, so no client is registered either | Fix the pod (see below), then install again. Check pods with `kubectl get pods -n <namespace>` |
| Lookup Service stays `0/1`, log: `Unknown platform version: <url>, no auth type set!` / `Auth not ready` | `lookupservice.platform.configServiceUrl` does not point to the Vinna runtime | Set it to the Vinna runtime URL, e.g. `https://my.domain.com/rt` |
| Login: `ID2052` "The specified 'client_id' is invalid" | The client does not exist on the Auth Server (e.g. registration job never ran) | Check the job log right after install: `kubectl logs -n <namespace> -l app.kubernetes.io/component=register-auth-clients` |
| Login: `ID2043` "The specified 'redirect_uri' is not valid" | The client exists but without the redirect URI of this installation (existing clients are skipped, not updated) | Add the redirect URI to the client on the Auth Server, or use a new client ID (Validation / Lookup only) |
| Batch / Field Review redirects to `https://<host>:8080/...` | Browser cached the `301` of an older chart version (< 1.2.1) | Clear the browser cache for the host or use a private window. Current charts redirect relatively |
| Batch / Field Review pod log shows only `kube-probe` requests | Browser requests do not reach the pod (cached redirect, DNS, route) | Test with `curl.exe -sI https://<host>/batchreview/`, check `kubectl describe httproute -n <namespace>` (`Accepted`, `ResolvedRefs`) |
| `helm uninstall` fails with `Release not loaded: ... release: not found` although `helm list` shows it | Inconsistent Helm release record | `helm upgrade --install` again (upgrades a failed release), or remove manually: `kubectl delete secret -n <namespace> -l owner=helm,name=via` and `kubectl delete deploy,svc,cm,httproute,ingress,job -n <namespace> -l app.kubernetes.io/instance=via` |
