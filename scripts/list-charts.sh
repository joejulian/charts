#!/usr/bin/env bash
set -euo pipefail

find "$(dirname "$0")/../charts" -mindepth 1 -maxdepth 1 -type d | sort

