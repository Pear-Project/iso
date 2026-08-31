#!/usr/bin/env bash
set -e -u

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)"
"${SCRIPT_DIR}/build-iso.sh" --profile pear --branch forky --clean-base --clean-target
