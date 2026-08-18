#!/usr/bin/env bash
set -e -u

# Clean, non-interactive ISO build: pear profile, --nvidia, no --chroot.
# --branch forky: trixie (stable) ships plasma-desktop 6.3.6, forky (testing)
# ships 6.7.2 -- forky is needed for Plasma 6.7.
# ./kickstart.sh -> pearos-forky-nvidia.iso in this directory.
SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)"

# build-iso.sh re-execs itself via pkexec/sudo if not already root, so no
# elevation needed here.
"${SCRIPT_DIR}/build-iso.sh" --profile pear --branch forky --nvidia
