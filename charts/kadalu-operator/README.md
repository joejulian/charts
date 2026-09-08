# kadalu-operator

Installs the Kadalu CRD, operator Deployment, and the operator's RBAC. The
operator remains the sole reconciler for generated CSI and storage-server
workloads. Install `kadalu-csi` and `kadalu-storage` in the same namespace to
provide independently versioned component image configuration.

For a migration from Kadalu's monolithic chart, first upgrade once with
`migration.retainComponentRBAC=true`. Install the CSI and storage charts with
Helm ownership takeover enabled and set
`migration.retainDuringOperatorHandoff=true` on both component releases. Only
then disable the operator migration value. After that operator upgrade
succeeds, disable the two component migration values. The matching keep
annotations on both sides prevent Helm from deleting adopted resources during
the handoff window without permanently orphaning them from uninstall.
