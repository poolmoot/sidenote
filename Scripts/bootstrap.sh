#!/usr/bin/env bash
# Builds the pinned XcodeGen from source into .tools/ (git-ignored).
# From source rather than a downloaded binary: no Homebrew needed, nothing unsigned to trust.
set -euo pipefail

VERSION="${1:?usage: Scripts/bootstrap.sh <xcodegen-version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/.tools/src/XcodeGen"
BIN="$SRC/.build/release/xcodegen"

if [[ -x "$BIN" ]] && "$BIN" --version | grep -q "$VERSION"; then
  echo "XcodeGen $VERSION is already built."
  exit 0
fi

echo "Building XcodeGen $VERSION from source (takes a minute or two, once)…"
rm -rf "$SRC"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$VERSION" \
  https://github.com/yonaskolb/XcodeGen.git "$SRC"
swift build --quiet -c release --package-path "$SRC" --product xcodegen
"$BIN" --version
