#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ISO="$SCRIPT_DIR/build-iso.sh"

if [ ! -x "$BUILD_ISO" ]; then
    echo "❌ Error: $BUILD_ISO not found or not executable."
    exit 1
fi

echo "🐚 Entering chroot (exit the shell to continue to ISO packaging)..."
"$BUILD_ISO" "$@" --chroot

echo "💿 Chroot exited — packaging the ISO from the same rootfs..."
"$BUILD_ISO" "$@"
