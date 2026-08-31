#!/usr/bin/env bash
set -e -u

# Fast incremental ISO rebuild: pear profile, --nvidia, forky branch, same
# as kickstart.sh but WITHOUT --clean-base (keeps the already-downloaded
# Debian base cache - no re-debootstrap, no re-downloading every package).
#
# Does still pass --clean-target, which is required (not optional) for a
# rebuild to actually pick up anything new - build-iso.sh's own comments
# spell out why: reusing an existing target rootfs as-is skips PHASES 5,
# 5.5 (customize.sh - branding, the Calamares module override, etc.) and 6
# entirely, straight to packaging. --clean-target just re-syncs a fresh
# target from the base cache (a local rsync, fast) and lets those phases
# run again, which is the whole point of a "rebuild".
#
# Use this whenever something changed in profiles/pear/ (customize.sh,
# packages.list, branding, ...) or in a cloned-at-build-time repo
# (pearOS-installer) and you want that reflected in a new ISO without
# paying kickstart.sh's full from-scratch base rebuild cost.
#
# ./incremental.sh -> pearos-forky-nvidia.iso in this directory.
SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)"

# build-iso.sh re-execs itself via pkexec/sudo if not already root, so no
# elevation needed here.
"${SCRIPT_DIR}/build-iso.sh" --profile pear --branch forky --nvidia --clean-target
