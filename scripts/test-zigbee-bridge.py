#!/usr/bin/env python3
"""Render safety checks for coordinator ownership and private persistent state."""
import pathlib
import subprocess
import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHART = ROOT / "charts/zigbee-bridge"


def render(*arguments, success=True):
    result = subprocess.run(["helm", "template", "fixture", str(CHART), "-f",
        str(CHART / "ci/render-values.yaml"), *arguments], capture_output=True, text=True)
    if success:
        assert result.returncode == 0, result.stderr
        return [obj for obj in yaml.safe_load_all(result.stdout) if obj]
    assert result.returncode != 0, "invalid ownership/image configuration unexpectedly rendered"


for count in (2, -1):
    render("--set", f"replicaCount={count}", success=False)
render("--set-string", "image.repository=", success=False)
render("--set-string", "image.tag=", success=False)
render("--set-string", "image.digest=sha256:broken", success=False)
render("--set-string", "configMapName=", success=False)

for arguments, storage in [
    ([], "new"),
    (["--set", "persistence.existingClaim=fixture-data"], "existing"),
    (["--set", "persistence.enabled=false"], "temporary"),
]:
    objects = render(*arguments)
    stateful = next(obj for obj in objects if obj["kind"] == "StatefulSet")
    spec = stateful["spec"]
    pod = spec["template"]["spec"]
    container = pod["containers"][0]
    service = next(obj for obj in objects if obj["kind"] == "Service")
    assert spec["replicas"] == 1
    assert pod["automountServiceAccountToken"] is False
    assert pod["terminationGracePeriodSeconds"] >= 30
    assert container["securityContext"]["runAsNonRoot"] is True
    assert container["securityContext"]["readOnlyRootFilesystem"] is True
    assert container["securityContext"]["capabilities"]["drop"] == ["ALL"]
    assert pod["securityContext"]["fsGroupChangePolicy"] == "OnRootMismatch"
    assert all(spec["template"]["metadata"]["labels"][key] == value
               for key, value in service["spec"]["selector"].items())
    assert container["envFrom"] == [{"secretRef": {"name": "fixture-credentials"}}]
    assert not any(volume.get("hostPath") for volume in pod["volumes"])
    if storage == "new":
        assert spec["volumeClaimTemplates"][0]["metadata"]["name"] == "data"
        # Omission uses Kubernetes' Retain default, never Delete.
        assert "persistentVolumeClaimRetentionPolicy" not in spec
    else:
        assert "volumeClaimTemplates" not in spec
        data = next(volume for volume in pod["volumes"] if volume["name"] == "data")
        if storage == "existing":
            assert data["persistentVolumeClaim"]["claimName"] == "fixture-data"
        else:
            assert data["emptyDir"] == {}

objects = render("--set", "replicaCount=0", "--set-string", "image.digest=sha256:" + "a" * 64)
stateful = next(obj for obj in objects if obj["kind"] == "StatefulSet")
assert stateful["spec"]["replicas"] == 0
assert stateful["spec"]["template"]["spec"]["containers"][0]["image"].endswith("@sha256:" + "a" * 64)
print("zigbee-bridge ownership, image, persistence and security render checks passed")

objects = render("--set", "maintenance=true")
stateful = next(obj for obj in objects if obj["kind"] == "StatefulSet")
service = next(obj for obj in objects if obj["kind"] == "Service")
pod = stateful["spec"]["template"]
container = pod["spec"]["containers"][0]
assert container["command"] == ["/bin/sleep"]
assert container["args"] == ["infinity"]
assert not any(key.endswith("Probe") for key in container)
assert service["spec"]["selector"]["zigbee-bridge/mode"] != pod["metadata"]["labels"]["zigbee-bridge/mode"]
print("maintenance does not start the adapter owner or receive service traffic")
