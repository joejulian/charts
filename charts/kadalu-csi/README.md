# kadalu-csi

Owns Kadalu CSI ServiceAccounts and RBAC plus the `kadalu-csi-config`
ConfigMap. A compatible Kadalu operator reads the ConfigMap and remains the
sole owner of the CSIDriver, node-plugin DaemonSet, and provisioner StatefulSet.

Changing this release does not make Helm roll storage clients directly. The
operator fences provisioning, publishes the node-plugin `OnDelete` template,
waits for an explicitly advanced node-by-node rollout, and only then resumes
the controller. Roll back by restoring this release's previous image values;
the same fence and rollout gates apply in reverse.

## Resource budgets

`resources` is optional and is omitted from the ConfigMap when empty, preserving
compatibility with existing operators. Nonempty budgets require an operator that
supports the component resource configuration; deploy that operator first.
CPU, memory, and ephemeral-storage requests and limits are supported. The schema
rejects unknown fields and malformed quantities; the operator additionally
rejects requests larger than their limits before changing workloads.

The value maps container names to Kubernetes ResourceRequirements objects.
Supported names are `kadalu-nodeplugin`, `kadalu-provisioner`,
`csi-node-driver-registrar`, `csi-provisioner`, `csi-resizer`,
`csi-liveness-probe`, and `kadalu-logging`. Containers not listed retain their
existing unconfigured defaults. Shared container names use the same budget in
both CSI workloads.

Changing node-plugin budgets changes its OnDelete template. Provisioning stays
fenced until the explicitly advanced client rollout is current. Evacuate or
unpublish each node's volumes before replacing that client; resource configuration
must not bypass the existing mount-safety gates.
