# UniFi Network

Runs UniFi Network with the maintained LinuxServer application, a rootless
startup wrapper, and a MongoDB 8.0 sidecar. Both containers run as UID/GID 999,
drop all capabilities, and support Kubernetes Restricted Pod Security.
MongoDB listens only on the shared pod loopback address, port 27117; it has no
Service or externally reachable database listener.

The chart uses the common v5 library (Kubernetes 1.31+, Helm 3.18+). Controller,
Service, ingress, configMaps and persistence settings use its values interface.
The main image defaults to Chart.appVersion. Deployments should select an
explicit application version pinned by digest, with Renovate updating those
pins. Application image tags are immutable; application major upgrades require
review in the image repository.

Renovate tracks the application
image and MongoDB mirror independently; the mirror deliberately stays on the
application-supported MongoDB 8.0 line. Do not upgrade database majors without
checking UniFi compatibility and rehearsing a logical restore.

## Storage and placement

One retained 16Gi PVC stores `controller/` (configuration, keystore, logs) and
`mongodb/` (database). Override `persistence.data.existingClaim` to use a prepared
claim. A single replica and Recreate strategy prevent concurrent controllers
sharing the same database. Back up both configuration and a logical MongoDB dump
before upgrades; retaining a volume is not a backup.

MongoDB 8 requires AVX on x86-64. The default node selector uses Node Feature
Discovery's standard AVX label. ARM64 deployments should override this selector
with suitable architecture placement after checking MongoDB's CPU requirements.

## Migrating an existing controller

Do not mount an old MongoDB data directory into MongoDB 8. Export the old
controller with mongodump, restore the archive with mongorestore into a fresh
database volume, and copy the controller configuration and keystore into the
new `controller/data/` directory. Rehearse on an isolated network first. Keep
the previous application and storage available for rollback; schema migrations
can make the upgraded database incompatible with the old application.

At cutover stop the original controller, preserve a fresh backup, and retain its
inform address and Service endpoints. Start the new controller only after the
restore finishes. Confirm the expected application version, sites, devices and
recent device connections. `helm test` checks the application status endpoint.
