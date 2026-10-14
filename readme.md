# ContainerWorld

Helm charts and umbrella charts for running **Laera**, **Vinna** and the **Auth Server** on Kubernetes.

## Structure

```
ContainerWorld/
├── charts/       # individual subcharts (can be installed standalone)
└── umbrellas/    # umbrella charts bundling several subcharts
```

### Charts (`charts/`)

| Chart | Description |
|---|---|
| `aiserver` | AI Server |
| `clsdesigner` | Classification Designer |
| `clsmonitor` | Classification Monitor |
| `iedesigner` | Extraction Designer |
| `iemonitor` | Extraction Monitor |
| `sitemanagement` | Site Management Tool |
| `<authserver>` | Auth Server |
| `<vinna-...>` | Vinna components |

Each chart has its own `prerequisites.md` describing required secrets, dependencies and installation notes.

### Umbrellas (`umbrellas/`)

| Umbrella | Contents |
|---|---|
| `umbrella-laera` | AI Server, designers, monitors and Site Management Tool |
| `<umbrella-vinna>` | Vinna stack |
| `<umbrella-auth>` | Auth Server |

## Prerequisites

- Kubernetes cluster and `kubectl`
- [Helm](https://helm.sh/) 3.x
- Access to the container registry
- Required secrets (see the `prerequisites.md` of the respective chart)

## Installation

1. Read the `prerequisites.md` of the umbrella or chart and create the required secrets.
2. Resolve dependencies:

   ```bash
   cd umbrellas/umbrella-laera
   helm dependency update
   ```

3. Install or upgrade:

   ```bash
   helm upgrade --install laera . -n <namespace> --create-namespace -f values.yaml -f <values-prod.yaml>
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
