#!/usr/bin/env zsh
# Lint (default) or format (--fix) all Swift sources with swift-format from the Xcode toolchain.
set -euo pipefail
cd "$(dirname "$0")/.."
PATHS=(App Core/Sources Core/Tests)
if [[ "${1:-}" == "--fix" ]]; then
  swift format format --in-place --recursive --configuration .swift-format "${PATHS[@]}"
  echo "formatted"
else
  swift format lint --strict --recursive --configuration .swift-format "${PATHS[@]}"
  echo "lint clean"
fi
