#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/vendor"
ARCHIVE="$VENDOR_DIR/TruflagSDK.tar.gz"
CHECKSUM_FILE="$VENDOR_DIR/TruflagSDK.tar.gz.sha256"
TARGET_DIR="$VENDOR_DIR/TruflagSDK"

if [ ! -f "$ARCHIVE" ]; then
  echo "Missing archive: $ARCHIVE" >&2
  exit 1
fi

if [ ! -f "$CHECKSUM_FILE" ]; then
  echo "Missing checksum: $CHECKSUM_FILE" >&2
  exit 1
fi

if command -v shasum >/dev/null 2>&1; then
ACTUAL="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
else
  echo "shasum is required to verify archive integrity." >&2
  exit 1
fi

EXPECTED="$(awk '{print $1}' "$CHECKSUM_FILE")"
ACTUAL_LOWER="$(echo "$ACTUAL" | tr '[:upper:]' '[:lower:]')"
EXPECTED_LOWER="$(echo "$EXPECTED" | tr '[:upper:]' '[:lower:]')"
if [ "$ACTUAL_LOWER" != "$EXPECTED_LOWER" ]; then
  echo "Checksum mismatch for TruflagSDK.tar.gz" >&2
  echo "Expected: $EXPECTED" >&2
  echo "Actual:   $ACTUAL" >&2
  exit 1
fi

rm -rf "$TARGET_DIR"
mkdir -p "$VENDOR_DIR"
tar -xzf "$ARCHIVE" -C "$VENDOR_DIR"

echo "SDK extracted to $TARGET_DIR"
