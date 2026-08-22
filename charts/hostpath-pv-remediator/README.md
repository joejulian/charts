# hostpath-pv-remediator

This chart installs a fail-closed Kubernetes controller for guarded recovery of
a host-mounted FUSE filesystem. The controller watches a configured Node
condition, cordons and drains one eligible node at a time, runs a narrowly
constrained repair Job on that node, verifies recovery, recycles affected
DaemonSet Pods, and only then restores the node's prior schedulability.

The chart does not install a CronJob or a repair Job. The controller creates a
repair Job only after the configured signal, freshness, exclusivity, approval,
drain, and timing checks pass.

## Safety defaults

-   Remediation is disabled by default; the controller starts in observe-only
  mode.
-   Manual incident approval is required by default.
-   The default eligible-node selector intentionally matches no ordinary node.
-   The repair ServiceAccount has token automount disabled and receives no RBAC
  bindings.
-   The controller runs non-root with a read-only root filesystem and no Linux
  capabilities.
-   The privileged executor image must be configured by immutable SHA-256 digest.
-   Separate pre-created Leases cover controller leader election and serialize
  remediation so only one node can be repaired at a time.
-   Admission policies are enabled by default with `failurePolicy: Fail` and
  `Deny` enforcement, and cannot be disabled while remediation is active.
-   A second admission policy limits controller Node patches to
  `spec.unschedulable` and an exact list of controller-owned state annotations.
  The controller cannot write the operator-owned `approved-incident`
  annotation.
-   A durable per-incident marker on each node prevents a replacement Job Pod
  from repeating the destructive abort/restart sequence.

## Admission boundary

When `admissionPolicy.enabled` is true, every Job created or updated in the
release namespace must match the controller's exact repair contract. The Job
policy allows only a deterministic `hostpath-pv-remediator-<incident-id>` Job
with:

-   one node-pinned, host-PID repair container;
-   no Job failure policy, indexed completion, alternate manager, or container
  restart rules, plus `podReplacementPolicy: Failed` and `backoffLimit: 0`;
-   the configured immutable image digest and exact repair argument vector;
-   the tokenless repair ServiceAccount;
-   privileged root execution, a read-only container root, and an unconfined
  seccomp profile;
-   `/sys/fs/fuse/connections` and `/var/lib/hostpath-pv-remediator` as its only
  host paths; and
-   no init containers, environment injection, ports, or extra devices.

A separate policy validates the actual Pod after mutating admission runs. It
requires the configured Job-controller identity, exact Job ownership and Node
binding, the same image/arguments/host paths, and rejects sidecars, resource
claims, alternate runtimes, scheduling extensions, and other executable-shape
changes. Another namespace-scoped policy denies Pod exec, attach, port-forward,
and proxy sessions so the privileged executor cannot become an interactive
node-root shell.

Install the chart in a dedicated namespace. The fail-closed policy deliberately
denies unrelated Jobs in that namespace. Disabling the policy removes this API
server boundary and is not recommended for an active remediation deployment.
If Pod Security Admission is enforced, that namespace must explicitly allow
privileged Pods; do not weaken Pod Security labels on a shared namespace.

The policies constrain API shape and accidental or lower-privilege mutation;
they do not make a compromised controller identity safe. The controller is
intentionally trusted to cordon eligible Nodes, evict their workloads, create
the constrained Job, and advance its own Node state annotations. Kubernetes
admission cannot cross-reference the controller's Lease or Node-condition
history, so the executor independently revalidates the exact mount identity and
FUSE backlog immediately before creating its durable attempt marker.

## Install

Kubernetes 1.35 or newer is required for the admission schema used to reject
container restart rules, workload/scheduling groups, resource claims, and every
supported Job retry escape hatch. The policy renders the version-appropriate
workload field for Kubernetes 1.35 and 1.36.

The first release must be observe-only. Configure the final immutable image,
eligible Nodes, condition, and mount identity during this install so the
controller and all admission policies can be verified together:

```console
helm upgrade --install hostpath-pv-remediator ./charts/hostpath-pv-remediator \
  --namespace hostpath-pv-remediator-system \
  --create-namespace \
  --set image.repository=registry.example.invalid/hostpath-pv-remediator \
  --set image.digest=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
  --set-string controller.eligibleNodeSelector=storage.example.invalid/remediation=true \
  --set remediation.enabled=false \
  --set repair.mountTarget=/srv/storage \
  --set repair.expectedFSType=fuse.example \
  --set repair.expectedSource=server.example.invalid:volume \
  --set repair.systemdUnit=srv-storage.mount
```

Wait for that release to become Ready, verify the four admission policies and
bindings exist, and confirm the controller reports healthy observe-only state.
Only then enable remediation with an upgrade:

```console
helm upgrade hostpath-pv-remediator ./charts/hostpath-pv-remediator \
  --namespace hostpath-pv-remediator-system \
  --reuse-values \
  --set remediation.enabled=true
```

The chart rejects active remediation on an initial install and rejects active
remediation when admission policy enforcement is disabled. This prevents a
newly created controller Deployment from racing ahead of its admission
boundary. If the observe-only install fails or is incomplete, repair or
reinstall it in observe-only mode; never use an active upgrade to recover a
failed first release.

The default repository is the controller's public Gitea container registry. If
`image.tag` is empty, the controller image tag defaults to the chart
`appVersion`; setting `image.digest` takes precedence for both the controller
Pod and the repair Job. Active remediation requires the digest form.

For manual approval, inspect the incident ID reported by the controller and set
the exact approval annotation on the affected Node:

```console
kubectl annotate node NODE_NAME \
  hostpath-pv-remediator/approved-incident=INCIDENT_ID
```

## Important values

| Value | Default | Purpose |
| --- | --- | --- |
| `image.repository` | `git.julianfamily.org/joejulian/hostpath-pv-remediator` | Controller and repair image repository. |
| `image.tag` | chart `appVersion` | Mutable controller tag used only when no digest is set. |
| `image.digest` | empty | SHA-256 digest required before active remediation. |
| `remediation.enabled` | `false` | Enables mutations after all checks pass. |
| `remediation.requireApproval` | `true` | Requires the exact incident approval annotation. |
| `controller.eligibleNodeSelector` | `hostpath-pv-remediator/enabled=true` | Limits nodes the controller may inspect or mutate. |
| `controller.conditionType` | `HostpathPVMountProblem` | Node condition that signals the supported failure. |
| `controller.conditionMessageRegexp` | `^hostpath_pv fuse backlog too high:` | Limits remediation to the supported condition message. |
| `repair.mountTarget` | `/tmp/hostpath_pv` | Host mount that is drained, repaired, and verified. |
| `repair.expectedFSType` | `fuse.example` | Exact filesystem type required after repair. |
| `repair.expectedSource` | `example.invalid:/volume` | Exact mount source required after repair. |
| `admissionPolicy.enabled` | `true` | Enforces the exact repair Job at admission. |
| `admissionPolicy.jobControllerUsername` | `system:serviceaccount:kube-system:job-controller` | Only API identity allowed to create generated repair Pods. |

Attempt markers are retained under `/var/lib/hostpath-pv-remediator` on each
node. A failed or interrupted attempt therefore remains fail-closed across Pod,
controller, and node restarts. Re-arming the same incident requires a human to
inspect the node and remove that incident's marker; the chart never removes it
automatically.

The health service exposes metrics on port 8080 and health/readiness endpoints
on port 8081. Run `helm test RELEASE --namespace NAMESPACE` to verify the
readiness endpoint from a restricted, tokenless test Pod.

## RBAC model

The controller can watch and patch Nodes, inspect Pods, use the Eviction API,
create and watch repair Jobs only in its namespace, and update only its two
pre-created Leases. The executor ServiceAccount is intentionally not
referenced by any RoleBinding or ClusterRoleBinding; host repair does not need
Kubernetes API access.
