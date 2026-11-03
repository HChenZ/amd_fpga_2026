#!/usr/bin/env bash
# Current evidence assembler; never removes an existing destination.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${PYTHON:-python}" -X utf8 "$SCRIPT_DIR/assemble.py" "$@"
