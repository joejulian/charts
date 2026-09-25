#!/usr/bin/env python3
"""Verify common-library upgrades preserve workload and exporter wiring."""
import pathlib
import subprocess
import yaml

root = pathlib.Path(__file__).resolve().parent.parent
for name in ("radarr", "sonarr"):
    chart = root / "charts" / name
    for metrics in (False, True):
        args = ["helm", "template", "fixture", str(chart)]
        if metrics:
            args += ["-f", str(chart / "ci/ct-exportarr-values.yaml")]
        objects = [obj for obj in yaml.safe_load_all(subprocess.check_output(args)) if obj]
        deployment = next(obj for obj in objects if obj["kind"] == "Deployment")
        pod = deployment["spec"]["template"]
        containers = {item["name"]: item for item in pod["spec"]["containers"]}
        version = yaml.safe_load((chart / "Chart.yaml").read_text())["appVersion"]
        assert containers["main"]["image"].endswith(":" + str(version))
        assert "livenessProbe" in containers["main"]
        assert ("exporter" in containers) == metrics
        for svc in (obj for obj in objects if obj["kind"] == "Service"):
            assert all(pod["metadata"]["labels"].get(k) == v for k, v in svc["spec"]["selector"].items())
        if metrics:
            exporter = containers["exporter"]
            config = next(m for m in exporter["volumeMounts"] if m["mountPath"] == "/config")
            assert config["readOnly"] is True
            env = {item["name"]: item["value"] for item in exporter["env"]}
            port = 7878 if name == "radarr" else 8989
            assert env["URL"] == f"http://localhost:{port}"
            assert any(obj["kind"] == "ServiceMonitor" for obj in objects)
            assert any(obj["kind"] == "PrometheusRule" for obj in objects)
            service = next(obj for obj in objects if obj["kind"] == "Service" and any(p["name"] == "metrics" for p in obj["spec"]["ports"]))
            assert next(p for p in service["spec"]["ports"] if p["name"] == "metrics")["targetPort"] == int(env["PORT"])

chart = root / "charts" / "home-assistant"
assert not (chart / "charts" / "common").exists(), "stale vendored library shadows Chart.lock"
objects = [obj for obj in yaml.safe_load_all(subprocess.check_output([
    "helm", "template", "fixture", str(chart), "--is-upgrade",
    "--set", "imagePrePull.enabled=true",
])) if obj]
assert any(obj["kind"] == "Deployment" for obj in objects)
assert any(obj["kind"] == "Job" and obj["metadata"]["annotations"].get("helm.sh/hook") == "pre-upgrade" for obj in objects)
print("common v5 workload, service, exporter, and upgrade-hook checks passed")
