#!/usr/bin/env bash
# Complete current production source set; configurable compiler/tool paths.
set -euo pipefail
cd "$(dirname "$0")/../.."
exec "${PYTHON:-python3}" sim/ascon/run_cpu_regression.py --mode hw "$@"
