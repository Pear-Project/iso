#!/usr/bin/env bash
# Builds the pearOS Raspberry Pi (arm64) disk image.
#
#   sudo pi/build-pi-image.sh [--stage rootfs|image|all] [--branch forky] [--version 2026.11]
#                             [--size 8G] [--out DIR] [--work DIR]
#
# Two stages so CI can run the first in a debian:<branch> container (mmdebstrap + an
# up-to-date Debian keyring) and the second directly on the runner (loop devices):
#   rootfs  needs: mmdebstrap, gnupg, git, debian-archive-keyring
#   image   needs: rsync, dosfstools, e2fsprogs, fdisk (sfdisk), xz-utils, losetup
# Both exchange the rootfs through --work (default /var/tmp/pearos-pi).
#
# 1. mmdebstrap: Debian <branch> arm64 rootfs + package list (packages.list)
# 2. customize-rootfs.sh: pearOS packages, first-boot assistant, SDDM, grow-on-first-boot
# 3. disk image: p1 FAT32 PEAR_BOOT (Pi firmware + kernel + EFI fallback) + p2 ext4 PEAR_ROOT
# 4. xz -> pearOS-Goldwing-Beta-<version>-arm64.img.xz (target: under 2 GiB, GitHub's release-asset limit)
#
# Kernels: the Pi firmware path boots the Raspberry Pi kernels (linux-image-rpi-2712 for Pi 5/500,
# linux-image-rpi-v8 for Pi 4, from archive.raspberrypi.com, installed by customize-rootfs.sh). Mainline /
# Debian's linux-image-arm64 has no pinctrl support for the D0 silicon of the Pi 500 (SError panic in
# pinctrl-brcmstb), and blacklisting it breaks the SD card. Debian's kernel stays for the GRUB/UEFI path.
#
# The image boots two ways from the same FAT partition: the Raspberry Pi firmware
# (config.txt/kernel/initrd placed by the raspi-firmware package) and, for QEMU and
# UEFI boards, GRUB at EFI/BOOT/BOOTAA64.EFI.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BRANCH="forky"
VERSION="$(date -u +%Y.%m)"
IMG_SIZE="8G"
OUT="$HERE/../out"
WORK="${WORK:-/var/tmp/pearos-pi}"
STAGE="all"

while [ $# -gt 0 ]; do
    case "$1" in
        --branch)  BRANCH="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --size)    IMG_SIZE="$2"; shift 2 ;;
        --out)     OUT="$2"; shift 2 ;;
        --work)    WORK="$2"; shift 2 ;;
        --stage)   STAGE="$2"; shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done
[ "$(id -u)" -eq 0 ] || exec sudo -E "$0" "$@"
case "$STAGE" in rootfs|image|all) ;; *) echo "bad --stage: $STAGE" >&2; exit 2 ;; esac
[ "$(dpkg --print-architecture)" = "arm64" ] || echo "WARNING: building arm64 on $(dpkg --print-architecture) (needs qemu-user binfmt, slow)"

NAME="pearOS-Goldwing-Beta-$VERSION-arm64"
ROOTFS="$WORK/rootfs"
IMG="$WORK/$NAME.img"
MNT="$WORK/mnt"
LOOP=""

cleanup() {
    set +e
    for m in "$MNT/boot/firmware" "$MNT/dev/pts" "$MNT/dev" "$MNT/proc" "$MNT/sys" "$MNT"; do
        mountpoint -q "$m" && umount -R "$m" 2>/dev/null
    done
    [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null
}
trap cleanup EXIT

mkdir -p "$WORK" "$OUT"

stage_rootfs() {
rm -rf "$ROOTFS"
echo "=== 1/4 rootfs: Debian $BRANCH arm64 ==="
PKGS=$(grep -v '^#' "$HERE/packages.list" | grep -v '^$' | paste -sd, -)
mmdebstrap --architecture=arm64 --variant=minbase \
    --components="main contrib non-free non-free-firmware" \
    --aptopt='APT::Install-Recommends "false"' \
    --dpkgopt='force-confold' \
    --setup-hook='mkdir -p "$1/boot/firmware"' \
    --include="$PKGS" \
    --customize-hook="$HERE/customize-rootfs.sh \"\$1\"" \
    "$BRANCH" "$ROOTFS" "http://deb.debian.org/debian"
echo "rootfs size: $(du -sh "$ROOTFS" | cut -f1)"
}

stage_image() {
[ -d "$ROOTFS" ] || { echo "no rootfs at $ROOTFS (run --stage rootfs first)" >&2; exit 1; }
rm -rf "$IMG" "$MNT"
echo "=== 2/4 disk image ($IMG_SIZE) ==="
truncate -s "$IMG_SIZE" "$IMG"
sfdisk "$IMG" <<'EOF'
label: dos
unit: sectors
start=2048, size=1048576, type=c, bootable
start=1050624, type=83
EOF
LOOP=$(losetup -fP --show "$IMG")
mkfs.vfat -F 32 -n PEAR_BOOT "${LOOP}p1" >/dev/null
# Plasma ships a huge number of tiny files: the default (1 inode per 16 KiB) runs out of
# inodes long before blocks. 1 per 8 KiB, and only 1% reserved (this is a single-user system).
mkfs.ext4 -q -L PEAR_ROOT -i 8192 -m 1 -E lazy_itable_init=1 "${LOOP}p2"
mkdir -p "$MNT"
mount "${LOOP}p2" "$MNT"
mkdir -p "$MNT/boot/firmware"
mount "${LOOP}p1" "$MNT/boot/firmware"

echo "=== 3/4 copy the rootfs, install the UEFI fallback ==="
rsync -aHAX --numeric-ids --exclude=/boot/firmware/ "$ROOTFS"/ "$MNT"/
# vfat has no owners/permissions: copy the firmware files plainly
rsync -rlt --no-perms --no-owner --no-group "$ROOTFS"/boot/firmware/ "$MNT"/boot/firmware/
mount --bind /dev "$MNT/dev"
mount --bind /dev/pts "$MNT/dev/pts"
mount -t proc proc "$MNT/proc"
mount -t sysfs sys "$MNT/sys"
chroot "$MNT" /bin/bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    sed -i "s|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR=\"pearOS Goldwing\"|" /etc/default/grub 2>/dev/null || true
    grep -q "^GRUB_DISABLE_OS_PROBER" /etc/default/grub 2>/dev/null || echo "GRUB_DISABLE_OS_PROBER=true" >> /etc/default/grub
    grub-install --target=arm64-efi --efi-directory=/boot/firmware --removable --no-nvram
    update-grub
'
sync
echo "root filesystem after the copy:"; df -h "$MNT" | tail -1; df -i "$MNT" | tail -1
echo "firmware partition:"; ls "$MNT/boot/firmware" | head -30
# The Pi firmware path must have what it needs, or the image will not boot on real hardware
# (QEMU boots through GRUB with Debian's kernel and does not exercise any of this).
for f in kernel8.img kernel_2712.img initramfs8 initramfs_2712 config.txt cmdline.txt start4.elf bcm2712-rpi-5-b.dtb bcm2712-rpi-500.dtb bcm2711-rpi-4-b.dtb; do
    [ -s "$MNT/boot/firmware/$f" ] || { echo "ERROR: /boot/firmware/$f missing" >&2; exit 1; }
done
for f in lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,5-model-b.bin lib/firmware/brcm/BCM4345C0.raspberrypi,5-model-b.hcd lib/firmware/regulatory.db-debian usr/bin/vcgencmd usr/local/sbin/pearos-fix-autologin; do
    [ -e "$MNT/$f" ] || { echo "ERROR: /$f missing (Wi-Fi/Bluetooth/regdb/autologin)" >&2; exit 1; }
done
echo "pinctrl drivers of the 2712 kernel:"; find "$MNT"/lib/modules/*rpt-rpi-2712 -name 'pinctrl-*bcm*' | head
echo "initramfs_2712 storage/USB modules:"
( zstd -dc "$MNT/boot/firmware/initramfs_2712" 2>/dev/null || xz -dc "$MNT/boot/firmware/initramfs_2712" 2>/dev/null || gzip -dc "$MNT/boot/firmware/initramfs_2712" ) \
    | cpio -t 2>/dev/null | grep -E 'sdhci|mmc_block|nvme|ext4|xhci|rp1' | head -20 || true
for m in "$MNT/boot/firmware" "$MNT/dev/pts" "$MNT/dev" "$MNT/proc" "$MNT/sys" "$MNT"; do umount "$m"; done
e2fsck -fy "${LOOP}p2" >/dev/null || true
losetup -d "$LOOP"; LOOP=""

echo "=== 4/4 compress ==="
ls -lh "$IMG"
xz -T0 -7 -f "$IMG"
mv "$IMG.xz" "$OUT/$NAME.img.xz"
( cd "$OUT" && sha256sum "$NAME.img.xz" > "$NAME.img.xz.sha256" )
SIZE=$(stat -c%s "$OUT/$NAME.img.xz")
printf '%s: %s bytes (%s)\n' "$NAME.img.xz" "$SIZE" "$(numfmt --to=iec "$SIZE")"
if [ "$SIZE" -lt $((2*1024*1024*1024)) ]; then
    echo "OK: under 2 GiB, can be a GitHub release asset"
else
    echo "NOTE: over 2 GiB -- too big for a GitHub release asset, publish to R2 instead"
fi
}

case "$STAGE" in
    rootfs) stage_rootfs ;;
    image)  stage_image ;;
    all)    stage_rootfs; stage_image ;;
esac
