#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

mode="${1:---write}"
if [[ "$mode" != --write && "$mode" != --check ]]; then
    echo 'Usage: Scripts/format.sh [--write|--check]' >&2
    exit 1
fi

if ! command -v mise >/dev/null; then
    echo 'Install mise, then run mise install in this checkout.' >&2
    exit 1
fi

paths=(Package.swift Sources Tests App)
if [[ "$mode" == --check ]]; then
    exec mise exec -- swiftformat "${paths[@]}" --config .swiftformat --cache ignore --lint
fi

# Expand compact callbacks before semicolon removal makes their bodies multiline.
mise exec -- swiftformat "${paths[@]}" --config .swiftformat --cache ignore --rules wrapClosureBodies
exec mise exec -- swiftformat "${paths[@]}" --config .swiftformat --cache ignore
