# zigbee-bridge

This chart deploys one Rust Zigbee-to-MQTT process. The application is in
development; this chart does not establish physical or beta qualification.
There is no default application image. Supply a published repository and an
immutable tag or digest, plus a ConfigMap containing `config.toml`.

The configuration must set `data_dir = "/var/lib/zigbee-bridge/data"`, frontend
`listen = "0.0.0.0:8080"`, assets
`"/usr/share/zigbee-bridge/frontend"`, and `token_env = "ZIGBEE_FRONTEND_TOKEN"`.
Provide that token through `existingSecret`, using a Secret key with the same
name. MQTT credentials can use `ZIGBEE_MQTT_USERNAME` and
`ZIGBEE_MQTT_PASSWORD` in that Secret. Do not put credentials in the ConfigMap.

The default security context runs as UID/GID 10001 with a read-only root
filesystem and no service-account token. Serial devices need an explicitly
selected host-device volume and appropriate group and runtime device access.
Use `extraVolumes`, `extraVolumeMounts`, `podSecurityContext` and
`securityContext` for those settings. TCP coordinators need no host-device
mount. The probes check the frontend listener; device availability is reported
by the service and does not cause Kubernetes to restart it.

`replicaCount` accepts only zero or one. A StatefulSet rollout replaces its
single pod before starting the replacement. This protects one release's
ownership; it cannot prevent another release or process opening the adapter.
Stop the previous adapter owner before starting this one. Do not share its
data directory with Zigbee2MQTT. Preserve the original workload, network and
data for rollback without resetting or re-pairing the coordinator.

Persistence creates a retained StatefulSet PVC by default. An `existingClaim`
must belong to this application. Disabling persistence uses `emptyDir` and
loses registry/configuration changes on pod recreation; use it only for
disposable tests. StatefulSet volume-claim size and storage class are immutable
after creation; follow the storage driver's supported expansion workflow.
The application creates the private `data` child as its own UID with mode 700;
the volume root can remain owned by the storage driver with group write access.
Its registry deliberately refuses a group-readable data directory.

Example render with synthetic values:

```sh
helm lint charts/zigbee-bridge -f charts/zigbee-bridge/ci/render-values.yaml
helm template fixture charts/zigbee-bridge \
  -f charts/zigbee-bridge/ci/render-values.yaml
```

The `ci/render-values.yaml` image and object names are placeholders for render
validation. They are not an installable fixture or a published application.

CI always runs ownership, storage and security render checks. Install/upgrade
and PVC-restart checks run when repository variable `ZIGBEE_BRIDGE_TEST_IMAGE`
names a published image. For a private registry, repository secret
`ZIGBEE_BRIDGE_PULL_CONFIG_JSON` can supply Docker authentication JSON; the
fixture passes it to Kubernetes through stdin. Without an image, CI explicitly
skips installation. The fixture uses a simulated coordinator and an unavailable
loopback MQTT port: it verifies the frontend listener, nonroot private storage
and persistence through replacement, not radio or broker compatibility.
