#!/usr/bin/env python3
"""Verify typed resource configuration without taking generated-pod ownership."""
import json
from pathlib import Path
import subprocess
import yaml

ROOT = Path(__file__).resolve().parent.parent


def render(chart, resources, success=True):
    args = ["helm", "template", "fixture", str(ROOT / "charts" / chart)]
    if resources is not None:
        args += ["--set-json", "resources=" + json.dumps(resources)]
    result = subprocess.run(args, capture_output=True, text=True, check=False)
    if not success:
        assert result.returncode != 0, "invalid resource settings unexpectedly rendered"
        return None
    assert result.returncode == 0, result.stderr
    objects = [o for o in yaml.safe_load_all(result.stdout) if o]
    assert not any(o["kind"] in {"DaemonSet", "StatefulSet", "Pod"} for o in objects)
    return next(o["data"] for o in objects if o["kind"] == "ConfigMap")


budget = {"requests": {"cpu": "1", "memory": "256Mi"},
          "limits": {"cpu": "1", "memory": "2Gi"}}
for chart in ["kadalu-csi", "kadalu-storage"]:
    assert "resources" not in render(chart, None)
    assert "resources" not in render(chart, {})
    value = {"kadalu-nodeplugin": budget} if chart == "kadalu-csi" else budget
    data = render(chart, value)
    assert isinstance(data["resources"], str)
    assert json.loads(data["resources"]) == value
    for invalid in [[], {"requests": []}, {"requests": {"cpu": "bad"}},
                    {"limits": {"cpu": 0}}, {"requests": {"memory": "-1Gi"}}]:
        value = {"kadalu-nodeplugin": invalid} if chart == "kadalu-csi" else invalid
        render(chart, value, success=False)
render("kadalu-csi", {"typo-container": budget}, success=False)
print("Kadalu resource configuration preserves component ownership and rejects malformed budgets")
