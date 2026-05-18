#!/usr/bin/env bash
# Fetch the AmstradDiag DSK from the upstream GitHub release.
#
# This corpus is freely redistributable and lives outside the harness repo;
# the fixture path stays gitignored and must be fetched per-clone.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${AMSTRAD_DIAG_VERSION:-v1.3}"
URL="https://github.com/llopis/amstrad-diagnostics/releases/download/${VERSION}/AmstradDiag.zip"
DEST="catalog/amstrad-diagnostics/fixtures"

mkdir -p "$DEST"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Fetching $URL"
curl -fsSL "$URL" -o "$tmp/diag.zip"
unzip -o "$tmp/diag.zip" -d "$tmp"
cp "$tmp/AmstradDiag.dsk" "$DEST/AmstradDiag.dsk"

echo "Installed $DEST/AmstradDiag.dsk"
