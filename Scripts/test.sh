#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/environment.sh
Scripts/format.sh --check
xcrun swift test --disable-sandbox "$@"
