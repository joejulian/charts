# kadalu-storage

Owns the Kadalu server ServiceAccount and `kadalu-server-config` ConfigMap.
Storage topology remains in `Kadalustorage` custom resources, while the Kadalu
operator remains the sole owner of generated Services and server StatefulSets.

An image change is reconciled one singleton StatefulSet at a time. Replica and
arbiter pools must be healthy before the first update and between every member.
Roll back by restoring the previous release image; the operator applies the
same serial and heal-gated procedure in reverse.

## Resource budgets

`resources` is optional and is omitted from the ConfigMap when empty, preserving
compatibility with existing operators. Nonempty budgets require an operator that
supports the component resource configuration; deploy that operator first.
CPU, memory, and ephemeral-storage requests and limits are supported. The schema
rejects unknown fields and malformed quantities; the operator additionally
rejects requests larger than their limits before changing workloads.

The value is one Kubernetes ResourceRequirements object applied to every server
container. For example, `resources.requests.cpu: "1"` and
`resources.limits.cpu: "1"` reserve and cap one core per brick. Server changes use
the existing serial rollout and heal checks. Equal CPU values alone do not
provide exclusive cores; that additionally requires the appropriate node CPU
Manager policy and qualifying pod QoS.
