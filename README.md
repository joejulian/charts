# Joe Julian Charts

Consolidated Helm chart monorepo for the charts maintained under the `joejulian` GitHub and GitLab namespaces.

## Charts

- `home-assistant`
- `justmount`
- `minetest`
- `mosquitto`
- `nzbget`
- `onstar2mqtt`
- `openldap`
- `postfix`
- `sonarr`

## Automation

- GitHub Actions lint every chart and run install, upgrade, and `helm test` smoke coverage in a kind cluster.
- Releases package changed charts, push them to `oci://ghcr.io/joejulian/charts`, and create per-chart git tags plus GitHub releases.
- Renovate runs on a schedule in GitHub Actions, tracks chart image sources, and updates `appVersion` automatically. Safe dependency updates can automerge after CI.
- Dependabot keeps GitHub Actions dependencies current.

## Local Usage

```sh
helm lint charts/<chart>
./scripts/test-charts.sh charts/<chart>
```

`onstar2mqtt` supports a secret-gated full e2e path because the upstream application requires valid OnStar credentials to stay running.

## Repository Secrets

- `RENOVATE_TOKEN`: fine-grained GitHub token or Renovate app token with permission to open and update pull requests in this repository.
- `ONSTAR2MQTT_TEST_SECRET`: optional Kubernetes Secret manifest used to enable credentialed `onstar2mqtt` e2e coverage in CI.
