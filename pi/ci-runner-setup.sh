#!/bin/bash
# Turns a Raspberry Pi 5 (Raspberry Pi OS Lite, 64-bit) into a GitHub Actions runner for the
# Pi image build + boot test. The runner only makes outbound connections: nothing to open in the router.
#
#   sudo bash ci-runner-setup.sh <REPO_URL> <REGISTRATION_TOKEN>
#   e.g. sudo bash ci-runner-setup.sh https://github.com/Pear-Project/iso AAAA...
#
# Get the token at: repo > Settings > Actions > Runners > New self-hosted runner (valid ~1 hour).
# Use it on a PRIVATE repo or only for manual runs: a self-hosted runner executes workflow code.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root (sudo)"; exit 1; }
REPO_URL="${1:?repo url}"; TOKEN="${2:?registration token}"
[ "$(uname -m)" = aarch64 ] || { echo "needs a 64-bit (aarch64) OS"; exit 1; }

apt-get update
apt-get install -y --no-install-recommends curl ca-certificates git jq sudo rsync dosfstools e2fsprogs fdisk \
    xz-utils qemu-system-arm qemu-efi-aarch64 tesseract-ocr ffmpeg python3 python3-pil docker.io

# The CI user: runs the runner, builds in docker, uses KVM for QEMU.
id ci >/dev/null 2>&1 || useradd -m -s /bin/bash ci
usermod -aG docker,kvm ci
echo 'ci ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-ci && chmod 0440 /etc/sudoers.d/90-ci

if [ -e /dev/kvm ]; then echo "KVM: /dev/kvm present"; else echo "WARNING: no /dev/kvm (is this a Pi 5 on a 64-bit kernel?)"; fi
# 4 GB RAM Pi 5: add swap (the QEMU guest gets 2.5 GB). Prefer a USB stick over the SD card:
#   SWAP_FILE=/mnt/usb/swapfile sudo -E bash ci-runner-setup.sh ...
SWAP_FILE="${SWAP_FILE:-/var/swapfile}"
if ! swapon --show | grep -q .; then
    fallocate -l 4G "$SWAP_FILE" && chmod 600 "$SWAP_FILE" && mkswap "$SWAP_FILE" >/dev/null && swapon "$SWAP_FILE"
    grep -q "$SWAP_FILE" /etc/fstab || echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
fi
free -g | sed -n 2p; df -h / | tail -1   # the build + test peak at ~22 GB of disk; 4 GB RAM works with the swap above

# The runner itself (latest release for linux arm64).
sudo -u ci bash -euxc '
  mkdir -p ~/actions-runner && cd ~/actions-runner
  VER=$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name | sed s/^v//)
  curl -fsSL -o runner.tgz "https://github.com/actions/runner/releases/download/v${VER}/actions-runner-linux-arm64-${VER}.tar.gz"
  tar xzf runner.tgz && rm runner.tgz
  ./config.sh --unattended --url "'"$REPO_URL"'" --token "'"$TOKEN"'" --name pi5-ci --labels pi5 --replace
'
cd /home/ci/actions-runner
./svc.sh install ci
./svc.sh start
echo "Done. The runner 'pi5-ci' (labels: self-hosted, Linux, ARM64, pi5) should show up as Idle in GitHub."
