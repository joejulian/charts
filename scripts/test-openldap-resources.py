#!/usr/bin/env python3
"""Keep migration budgets conditional without changing the importer."""
import json
from pathlib import Path
import subprocess
import yaml

chart = Path(__file__).resolve().parent.parent / 'charts/openldap'
budget = {'requests': {'cpu': '25m', 'memory': '64Mi'},
          'limits': {'cpu': '2', 'memory': '512Mi'}}


def render(enabled, resources=None):
    args = ['helm', 'template', 'fixture', str(chart), '--set-json',
            'migration.enabled=' + json.dumps(enabled)]
    if resources is not None:
        args += ['--set-json', 'migration.resources=' + json.dumps(resources)]
    docs = yaml.safe_load_all(subprocess.check_output(args, text=True))
    deployment = next(doc for doc in docs if doc and doc['kind'] == 'Deployment')
    return deployment['spec']['template']['spec']['initContainers']


baseline = render(True)
configured = render(True, budget)
importer = next(c for c in configured if c['name'] == 'import-version-migration')
assert importer.pop('resources') == budget
assert baseline == configured
assert render(False) == render(False, budget)
assert all(c['name'] != 'import-version-migration' for c in render(False, budget))
print('OpenLDAP migration resources preserve the import command and disabled migration behavior')
