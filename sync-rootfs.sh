#!/bin/bash
# ==============================================================================
# Pulsar OS - Fast Clean Rootfs Regenerator & Tester
# ==============================================================================
# Clones rootfs-base -> rootfs-target cleanly, installs local PKG packages,
# and compiles schemas/caches.
# ==============================================================================

set -e

ISO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(realpath -m "$ISO_DIR/../PKG")"
BUILD_DIR="$ISO_DIR/build"

# Arguments
BRANCH="stable"
WITH_NVIDIA=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --branch|-b)
            BRANCH="$2"
            shift 2
            ;;
        --nvidia)
            WITH_NVIDIA=true
            shift
            ;;
        *)
            echo "❌ Unknown option: $1"
            echo "Usage: $0 [--branch stable|forky|rolling] [--nvidia]"
            exit 1
            ;;
    esac
done

if $WITH_NVIDIA; then
    ROOTFS_BASE="$BUILD_DIR/rootfs-base-$BRANCH-nvidia"
    ROOTFS_TARGET="$BUILD_DIR/rootfs-target-$BRANCH-nvidia"
else
    ROOTFS_BASE="$BUILD_DIR/rootfs-base-$BRANCH"
    ROOTFS_TARGET="$BUILD_DIR/rootfs-target-$BRANCH"
fi

if [ ! -d "$ROOTFS_BASE/etc" ]; then
    echo "❌ Error: The base rootfs does not exist at: $ROOTFS_BASE"
    echo "Run build-iso.sh first to generate the virgin base."
    exit 1
fi

echo "=============================================================================="
echo "⚡ Regenerating clean rootfs-target for $BRANCH..."
echo "📂 Base:   $ROOTFS_BASE"
echo "🎯 Target: $ROOTFS_TARGET"
echo "=============================================================================="

cleanup() {
    pkexec /bin/bash -c "
        umount -l '$ROOTFS_TARGET/proc' 2>/dev/null || true
        umount -l '$ROOTFS_TARGET/sys' 2>/dev/null || true
        umount -l '$ROOTFS_TARGET/dev/pts' 2>/dev/null || true
        umount -l '$ROOTFS_TARGET/dev' 2>/dev/null || true
        rm -rf '$ROOTFS_TARGET/tmp/packages' 2>/dev/null || true
    " 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# 1. Unmount and recreate target from clean base
cleanup
echo "🔄 Cloning clean rootfs-base to rootfs-target..."
pkexec /bin/bash -c "
    rm -rf '$ROOTFS_TARGET'
    mkdir -p '$ROOTFS_TARGET'
    rsync -aHAXx --delete '$ROOTFS_BASE/' '$ROOTFS_TARGET/'
"

# 2. Configure mounts & DNS
echo "⚙️ Configuring system mounts and DNS..."
pkexec /bin/bash -c "
    mount -t proc proc '$ROOTFS_TARGET/proc'
    mount -t sysfs sys '$ROOTFS_TARGET/sys'
    mount --bind /dev '$ROOTFS_TARGET/dev'
    mount --bind /dev/pts '$ROOTFS_TARGET/dev/pts'
    echo 'nameserver 8.8.8.8' > '$ROOTFS_TARGET/etc/resolv.conf'
"

# 3. Install packages
echo "📦 Installing local Pulsar OS packages (Debian)..."
DEBS_DIR="$PKG_DIR/debian/build/packages"
if [ -d "$DEBS_DIR" ]; then
    pkexec /bin/bash -c "
        mkdir -p '$ROOTFS_TARGET/tmp/packages'
        cp '$DEBS_DIR'/*.deb '$ROOTFS_TARGET/tmp/packages/' 2>/dev/null || true
        chroot '$ROOTFS_TARGET' /bin/bash -c '
            dpkg -i --force-overwrite /tmp/packages/*.deb 2>/dev/null || apt-get install -f -y --allow-downgrades
            glib-compile-schemas /usr/share/glib-2.0/schemas/
            gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
        '
        chmod -R a+r '$ROOTFS_TARGET/boot' 2>/dev/null || true
    "
fi

cleanup
echo "✅ Clean rootfs successfully regenerated and updated at: $ROOTFS_TARGET"
