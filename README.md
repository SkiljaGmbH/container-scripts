# ContainerWorld

Helm charts and umbrella charts for running Skilja products on Kubernetes.

> **Currently published:** VIA (Batch Review, Field Review, Validation Service, Lookup Service).
> Laera, Vinna and the Auth Server follow.

## Structure

```
ContainerWorld/
├── charts/       # individual subcharts (can be installed standalone)
└── umbrellas/    # umbrella charts bundling several subcharts
```

### Charts (`charts/`)

| Chart | Description |
|---|---|
| `batchreview` | Batch Review web frontend (nginx) |
| `fieldreview` | Field Review web frontend (nginx), requires `validationservice` |
| `validationservice` | Validation Service |
| `lookupservice` | Lookup Service |

Each chart has its own `prerequisites.md` describing required secrets, dependencies and installation notes.

### Umbrellas (`umbrellas/`)

| Umbrella | Contents |
|---|---|
| `umbrella-via` | Batch Review, Field Review, Validation Service and Lookup Service (requires an existing Vinna platform and Auth Server) |

## Prerequisites

- Kubernetes cluster and `kubectl`
- [Helm](https://helm.sh/) 3.x or 4.x
- Ingress controller **or** a Gateway API implementation with an existing Gateway (see `umbrellas/README.md`)
- Access to the container registry
- Required secrets (see the `prerequisites.md` of the respective chart)

## Installation

1. Read the `prerequisites.md` of the umbrella or chart and create the required secrets.
2. Resolve dependencies:

   ```bash
   cd umbrellas/umbrella-via
   helm dependency update
   ```

3. Install or upgrade:

   ```bash
   helm upgrade --install via . -n <namespace> -f values.yaml -f <values-prod.yaml> --wait --timeout 10m
   ```

Individual components can be toggled in the umbrella via `<chart-name>.enabled`.

## Development

- New subcharts live in `charts/<name>` and are referenced in the umbrella as `file://../../charts/<name>`.
- Bump the `version` in a chart's `Chart.yaml` whenever you change it.
- After changing dependencies, run `helm dependency update` and commit the updated `Chart.lock`. The `.tgz` archives in the umbrella's `charts/` folder are not versioned.
- Before committing, run `helm lint .` and `helm template .`

## Conventions

- Secrets never belong in the repo. Values files only reference secret names and keys.
- Branch naming: `users/<Name>/<topic>`

## License

The Helm charts, scripts and documentation in this repository are licensed under the
[MIT License](LICENSE). The Skilja container images referenced by these charts are proprietary
software and are subject to Skilja's own license terms.
