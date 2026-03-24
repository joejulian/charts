#!/usr/bin/env bash
set -euo pipefail

helm repo add bjw-s-labs https://bjw-s-labs.github.io/helm-charts/ >/dev/null 2>&1 || true
helm repo update >/dev/null
