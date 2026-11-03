#!/usr/bin/env bash
# Runs as an mmdebstrap --customize-hook: $1 is the rootfs directory. Turns the
# freshly bootstrapped Debian forky rootfs into pearOS (arm64): pearOS apt repo +
# packages, first-boot assistant (OOBE), SDDM, branding, first-boot disk grow.
set -euo pipefail
R="$1"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_SH="$HERE/../profiles/pear/repo.sh"
APT_URL="https://apt.pearos.xyz/aarch64/main/latest"

in_chroot() { chroot "$R" /bin/bash -c "export DEBIAN_FRONTEND=noninteractive LC_ALL=C; $1"; }

echo "--- pearOS apt repository (arm64) ---"
install -d "$R/etc/apt/keyrings" "$R/etc/apt/sources.list.d"
# The signing key is vendored in the amd64 profile's repo.sh (same key, same repo host).
sed -n '/-----BEGIN PGP PUBLIC KEY BLOCK-----/,/-----END PGP PUBLIC KEY BLOCK-----/p' "$REPO_SH" \
    | gpg --dearmor > "$R/etc/apt/keyrings/pearos-archive-keyring.gpg"
chmod 644 "$R/etc/apt/keyrings/pearos-archive-keyring.gpg"
echo "deb [signed-by=/etc/apt/keyrings/pearos-archive-keyring.gpg] $APT_URL ./" > "$R/etc/apt/sources.list.d/pearos.list"
in_chroot "apt-get update"
PEAR_PKGS=$(grep -v '^#' "$HERE/pearos-packages.list" | grep -v '^$' | tr '\n' ' ')
in_chroot "apt-get install -y --no-install-recommends $PEAR_PKGS"

echo "--- first-boot assistant (OOBE): same model as the Calamares 'autouser' job ---"
rm -rf "$R/usr/share/pearOS-installer"
git clone --depth 1 https://github.com/Pear-Project/pearOS-installer.git "$R/usr/share/pearOS-installer"
rm -rf "$R/usr/share/pearOS-installer/.git"
install -Dm755 "$R/usr/share/pearOS-installer/general_bin/bin_post" "$R/usr/local/bin/bin_post"
install -d "$R/etc/skel/.config/autostart"
cat > "$R/etc/skel/.config/autostart/xyz.pearos-post-install.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=pearOS Post Install
GenericName=PostInstall
Comment=Scripts for the after-install time
Icon=/usr/share/pixmaps/pearos-logo.png
Categories=Utility;
Exec=bash /usr/local/bin/bin_post
Terminal=false
EOF
# The Welcome window belongs to the live session; the assistant must be the only thing the person sees.
rm -f "$R/etc/skel/.config/autostart/welcome.desktop"
# Temporary account the assistant runs as; it creates the real user and removes this one.
in_chroot "useradd -m -s /bin/bash default && echo 'default:pearos' | chpasswd && usermod -aG sudo,audio,video,plugdev,netdev,dialout,bluetooth default || usermod -aG sudo,audio,video,plugdev,netdev,dialout default"
in_chroot "cp -dnRT --preserve=mode,timestamps,links -- /etc/skel/. /home/default && chown -hR default:default /home/default"
# The temporary account must never lock the screen while the assistant waits for the person
# (a locked screen has no way back: the account has no password anyone knows). Only /home/default,
# the real account keeps the normal lock-on-idle defaults.
install -d -o 1000 -g 1000 "$R/home/default/.config" 2>/dev/null || install -d "$R/home/default/.config"
printf '[Daemon]\nAutolock=false\nLockOnResume=false\n' > "$R/home/default/.config/kscreenlockerrc"
in_chroot "chown -R default:default /home/default/.config"
echo 'default ALL=(ALL:ALL) NOPASSWD: ALL' > "$R/etc/sudoers.d/010-pearos-default-nopasswd"
chmod 0440 "$R/etc/sudoers.d/010-pearos-default-nopasswd"

echo "--- SDDM: autologin into the assistant, pearOS theme ---"
install -d "$R/etc/sddm.conf.d"
printf '[Autologin]\nUser=default\nSession=plasma\n' > "$R/etc/sddm.conf.d/autologin.conf"
printf '[Theme]\nCurrent=pearOS-dark\n' > "$R/etc/sddm.conf.d/theme.conf"

echo "--- branding / desktop tweaks shared with the amd64 profile ---"
install -d "$R/etc/environment.d"
printf 'GDK_DEBUG=no-portals\n' > "$R/etc/environment.d/90-pearos-gtk-portal-fix.conf"
for cmd in shutdown reboot poweroff halt; do ln -sf "/usr/sbin/$cmd" "$R/usr/local/bin/$cmd"; done
if [ -f "$R/etc/plymouth/plymouthd.conf" ]; then
    sed -i 's/^UseSimpledrm=.*/UseSimpledrm=false/' "$R/etc/plymouth/plymouthd.conf"
fi
in_chroot "plymouth-set-default-theme pear-plymouth" || echo "(pear-plymouth theme not available, keeping the default)"

echo "--- locale, hostname ---"
in_chroot "sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && locale-gen && update-locale LANG=en_US.UTF-8"
echo "pearOS-machine" > "$R/etc/hostname"
printf '127.0.0.1\tlocalhost\n127.0.1.1\tpearOS-machine\n' > "$R/etc/hosts"

echo "--- first boot: grow the root partition to fill the card/disk ---"
install -Dm755 /dev/stdin "$R/usr/local/sbin/pearos-grow-root" <<'EOF'
#!/bin/sh
# Grows the root partition and its ext4 filesystem to the end of the disk.
set -e
root=$(findmnt -no SOURCE /)
disk="/dev/$(lsblk -no PKNAME "$root")"
part=$(cat "/sys/class/block/$(basename "$root")/partition")
growpart "$disk" "$part" || true
resize2fs "$root"
install -d /var/lib/pearos
touch /var/lib/pearos/root-grown
EOF
cat > "$R/etc/systemd/system/pearos-grow-root.service" <<'EOF'
[Unit]
Description=Grow the root partition on first boot
DefaultDependencies=no
After=systemd-remount-fs.service
Before=sysinit.target
ConditionPathExists=!/var/lib/pearos/root-grown

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/pearos-grow-root

[Install]
WantedBy=sysinit.target
EOF
in_chroot "systemctl enable pearos-grow-root.service"

echo "--- services ---"
in_chroot "systemctl enable sddm NetworkManager bluetooth && systemctl set-default graphical.target"

echo "--- fstab (labels set by build-pi-image.sh) ---"
cat > "$R/etc/fstab" <<'EOF'
LABEL=PEAR_ROOT  /              ext4  defaults,noatime  0 1
LABEL=PEAR_BOOT  /boot/firmware vfat  defaults          0 2
EOF

echo "--- initramfs with the final plymouth theme ---"
in_chroot "update-initramfs -u -k all"

echo "--- trim ---"
in_chroot "apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin /tmp/* /var/tmp/*"
rm -f "$R/etc/machine-id" && : > "$R/etc/machine-id"
