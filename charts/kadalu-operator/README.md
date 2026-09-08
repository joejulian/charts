# kadalu-operator

Installs the Kadalu CRD, operator Deployment, and the operator's RBAC. The
operator remains the sole reconciler for generated CSI and storage-server
workloads. Install `kadalu-csi` and `kadalu-storage` in the same namespace to
provide independently versioned component image configuration.

For a migration from Kadalu's monolithic chart, first upgrade once with
`migration.retainComponentRBAC=true`. Install the CSI and storage charts with
Helm ownership takeover enabled, then disable the migration value. The keep
annotation on the handoff revision prevents Helm from deleting adopted RBAC.
