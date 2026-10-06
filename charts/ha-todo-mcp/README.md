# ha-todo-mcp

Deploys the restricted Home Assistant todo MCP bridge as one non-root replica.
Task data stays in Home Assistant. A retained PVC stores encrypted OAuth state;
Recreate updates prevent concurrent file-store writers.

Create a Secret with the configuration variables documented in the
[application README](https://github.com/joejulian/ha-todo-mcp), then reference it
through `existingSecret`. Keep deployment-specific values out of reusable chart
source. For GitOps, use your established encrypted-secret workflow.

`ingress` can reuse multiple existing ingress classes and one TLS certificate.
Only the MCP/OAuth path and its two discovery paths are routed. Health endpoints
remain internal. Set `ingress.host`, `ingress.tlsSecretName`, `ingress.classes`,
and `ingress.enabled`; preserve the path prefix when forwarding requests.

Enable `networkPolicy` with explicit proxy ingress peers and HA/DNS egress rules.
`homeAssistantSelector` optionally admits this bridge into an existing HA ingress
default-deny policy in the same namespace. Values do not grant Kubernetes API
permissions; no service-account token is mounted.

Set `podAnnotations` to a new rollout marker through GitOps after rotating the
Secret or when a restart is required. Keep signing/encryption keys and the PVC
unchanged during ordinary upgrades. Follow the app's release process, update
`appVersion`, and increment the chart version for each application update.

Uninstalling retains OAuth storage. Remove the retained PVC separately after
revoking linked HA sessions. The chart never creates or deletes the HA todo list.

CI uses an isolated fake HA backend and dummy credentials from
`ci/values/ha-todo-mcp.yaml`; it never contacts a real home or identity provider.
