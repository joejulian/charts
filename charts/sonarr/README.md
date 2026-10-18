# Sonarr

Version 2 migrates to common library v5 and requires Kubernetes 1.31+ and
Helm 3.18+. Review values before upgrading; this is a breaking chart upgrade.

| Previous value | Version 2 value |
| --- | --- |
| `image`, `env`, `probes`, container resources | `controllers.main.containers.main.*` |
| `controller.type`, `controller.strategy` | `controllers.main.type`, `controllers.main.strategy` |
| Pod scheduling/security options | `controllers.main.pod.*` or `defaultPodOptions.*` |
| `persistence.<name>.mountPath` | `persistence.<name>.globalMounts[].path` |
| Container-specific mount paths and subpaths | `persistence.<name>.advancedMounts.main.<container>[]` |

The main container is named `main`; the optional metrics sidecar is `exporter`.
The image tag defaults to `Chart.appVersion`. Metrics remain configured through
`metrics`, and the exporter mounts config read-only by default. Enable config
persistence when using the exporter. Use common v5's ingress service identifiers
and port names; service and workload selectors now include controller identifiers.
Because Deployment selectors change, an existing Deployment must be recreated
during the planned major-version migration. Persistent claims/data must be retained.

The exact library version is pinned by `Chart.lock`. Run `helm dependency build`
before linting, rendering, or packaging; do not vendor another common version.
