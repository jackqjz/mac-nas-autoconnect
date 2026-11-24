#!/bin/bash
set -euo pipefail
BASE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec /bin/bash "$BASE/control.sh" uninstall
