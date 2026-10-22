## Site Management Tool - Usage

Interactive CLI to grant initial rights (license managers, organization admins, organizations) for the
Laera modules (Classification/Extraction Service, Designer and Online Learning Monitor). This chart
does not deploy a running workload. It only manages a `Secret` with the database connection variables
of all six modules. The CLI pod is started by hand when needed:

- once after the first install, **after** all module pods were Ready once (their first start creates
  the databases),
- again after adding a module.

### Inside the Laera umbrella (recommended)

`site-management-tool.enabled: true` (default) in `umbrellas/umbrella-laera`. The database settings come
from the umbrella's `global.database`. After `helm install` / `helm upgrade` the umbrella prints the
complete steps, with the CLI pod manifest already filled in (Secret name, namespace, image). Show them
again with:

```powershell
helm get notes <release> -n <namespace>
```

### Standalone

Set the `global.database.*` values in this chart's `values.yaml` to the same database connection the
modules use, then:

```powershell
helm install site-management-tool ./charts/sitemanagement -n <namespace>
```

This creates the Secret `site-management-tool-secrets` (`<release>-site-management-tool-secrets` if the
release name does not contain the chart name). Start the pod as shown in the umbrella notes, with that
Secret name.

### DB password

- **`global.database.password`:** the chart writes the password into its own Secret together with all
  other variables. Fine for tests; for production prefer an existing secret.
- **`global.database.existingSecret`:** the existing secret needs these six keys, all with the same DB
  password (in the umbrella in addition to `database-password` used by the modules):

```powershell
kubectl create secret generic laera-db-pw-secret `
  --from-literal=database-password=<YOUR_SECRET> `
  --from-literal=CLSSERVICE_CLSSSQLPASSWORD=<YOUR_SECRET> `
  --from-literal=CLSDESIGNER_SQLPASSWORD=<YOUR_SECRET> `
  --from-literal=OLCLS_OLSQLPASSWORD=<YOUR_SECRET> `
  --from-literal=EXTRSERVICE_EXTRSSQLPASSWORD=<YOUR_SECRET> `
  --from-literal=EXTRDESIGNER_SQLPASSWORD=<YOUR_SECRET> `
  --from-literal=OLEXTR_OLSQLPASSWORD=<YOUR_SECRET> `
  -n <namespace>
```

  The CLI pod then needs a second `secretRef` to this secret (the umbrella notes add it automatically).

### After granting rights

Restart the affected module pods so they pick up the new rights, then delete the CLI pod (it does not
restart on its own):

```powershell
kubectl rollout restart deployment -n <namespace> -l app.kubernetes.io/instance=<release>
kubectl delete pod site-management-tool -n <namespace>
```
