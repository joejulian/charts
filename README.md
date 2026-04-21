# Joe Julian Charts

Consolidated Helm chart monorepo for the charts maintained under the `joejulian` GitHub and GitLab namespaces.

## Charts

- `home-assistant`
- `justmount`
- `luanti`
- `minetest`
- `mosquitto`
- `nzbget`
- `onstar2mqtt`
- `openldap`
- `postfix`
- `sonarr`

Deprecated:

- `minetest` in favor of `luanti`

## Automation

- GitHub Actions lint every chart and run install, upgrade, and `helm test` smoke coverage in a kind cluster.
- Releases package changed charts, push them to `oci://ghcr.io/joejulian/charts`, and create per-chart git tags plus GitHub releases.
- Renovate runs on a schedule in GitHub Actions, tracks chart image sources, updates `appVersion`, and runs `scripts/bump-chart.sh` so chart version bumps happen in the same PR before CI runs.
- CI verifies that any `appVersion` change includes an appropriate chart version bump.
- If the `RENOVATE_TOKEN` actor is allowed to merge, safe dependency updates can automerge after CI. Otherwise the PR remains manual.
- Dependabot keeps GitHub Actions dependencies current.

## Local Usage

```sh
helm lint charts/<chart>
./scripts/test-charts.sh charts/<chart>
```

`onstar2mqtt` supports a secret-gated full e2e path because the upstream application requires valid OnStar credentials to stay running.

## Repository Secrets

- `RENOVATE_APP_ID`: GitHub App ID for the Renovate automation app installed on this repository.
- `RENOVATE_APP_PRIVATE_KEY`: GitHub App private key PEM for generating short-lived installation tokens in the Renovate workflow.
- `ONSTAR2MQTT_TEST_SECRET`: optional Kubernetes Secret manifest used to enable credentialed `onstar2mqtt` e2e coverage in CI.
