# kadalu-storage

Owns the Kadalu server ServiceAccount and `kadalu-server-config` ConfigMap.
Storage topology remains in `Kadalustorage` custom resources, while the Kadalu
operator remains the sole owner of generated Services and server StatefulSets.

An image change is reconciled one singleton StatefulSet at a time. Replica and
arbiter pools must be healthy before the first update and between every member.
Roll back by restoring the previous release image; the operator applies the
same serial and heal-gated procedure in reverse.
