#!/usr/bin/env bash
# Renders the preview window to docs/preview.png (requires a GUI session).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/docs/preview.png}"
shift || true

cd "$ROOT"
swift run -c release SeeImage --snapshot "$OUT" "$@"
