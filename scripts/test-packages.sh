#!/usr/bin/env bash
# scripts/test-packages.sh
# Builds and tests every local Swift package. Runs on macOS or Linux (Swift 6.0+).
# Prints the AstroCore accuracy report lines (prefixed "ACCURACY |").
set -euo pipefail
cd "$(dirname "$0")/.."
log="$(mktemp)"
for pkg in AstroCore OpticsCore GeoCore CameraCatalog PlannerKit; do
  echo "== $pkg"
  if ! (cd "Packages/$pkg" && swift test >"$log" 2>&1); then
    cat "$log"
    echo "FAILED: $pkg"
    exit 1
  fi
  grep -E "ACCURACY|Test run with" "$log" || true
done
echo "All package tests passed."
