# kadalu-csi

Owns Kadalu CSI ServiceAccounts and RBAC plus the `kadalu-csi-config`
ConfigMap. A compatible Kadalu operator reads the ConfigMap and remains the
sole owner of the CSIDriver, node-plugin DaemonSet, and provisioner StatefulSet.

Changing this release does not make Helm roll storage clients directly. The
operator fences provisioning, publishes the node-plugin `OnDelete` template,
waits for an explicitly advanced node-by-node rollout, and only then resumes
the controller. Roll back by restoring this release's previous image values;
the same fence and rollout gates apply in reverse.
