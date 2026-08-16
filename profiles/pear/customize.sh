# ==============================================================================
# Pear profile — post-install branding & extra apps (sourced by build-iso.sh)
# ==============================================================================
# Defines profile_customize(), called once by the engine after Calamares
# config generation, before initramfs regeneration (former Phase 5.5).
# ==============================================================================

profile_customize() {
    # Configure spotlight icon to 'view-app-grid'
    echo "⚙️ Customizing Spotlight launcher..."
    $SUDO "$CHROOT_BIN" "$ROOTFS_TARGET" /bin/bash -c "
        set -e
        if [ -f /usr/share/applications/spotlight-python.desktop ]; then
            sed -i 's/^Icon=.*/Icon=view-app-grid/' /usr/share/applications/spotlight-python.desktop
        elif [ -f /usr/share/applications/spotlight-gtk.desktop ]; then
            sed -i 's/^Icon=.*/Icon=view-app-grid/' /usr/share/applications/spotlight-gtk.desktop
        fi
    "

    # Download external winboat dependencies on host and copy to chroot
    echo "📥 Downloading external dependencies (Winboat) on the host..."
    wget -q --timeout=15 --tries=3 -O "$BUILD_DIR/winboat.deb" https://github.com/TibixDev/winboat/releases/download/v0.9.0/winboat-0.9.0-amd64.deb
    $SUDO cp "$BUILD_DIR/winboat.deb" "$ROOTFS_TARGET/tmp/winboat.deb"
    rm -f "$BUILD_DIR/winboat.deb"

    echo "📥 Installing Winboat..."
    $SUDO "$CHROOT_BIN" "$ROOTFS_TARGET" /bin/bash -c "
        set -e
        apt-get install -y /tmp/winboat.deb
        rm -f /tmp/winboat.deb
    "

    # Configure Flathub on the system and install essential Flatpaks
    echo "📦 Configuring Flathub repository and installing Hidamari..."
    $SUDO "$CHROOT_BIN" "$ROOTFS_TARGET" /bin/bash -c "
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
        flatpak install --system -y --noninteractive flathub io.github.jeffshee.Hidamari || true
    "

    # Ensure Pulsar OS official branding and logo in GNOME Settings
    echo "🎨 Applying Pulsar OS branding and logo..."
    $SUDO "$CHROOT_BIN" "$ROOTFS_TARGET" /bin/bash -c "
        cat <<'EOF' > /etc/os-release
NAME=\"Pulsar OS\"
PRETTY_NAME=\"Pulsar OS Pear Edition\"
VERSION_ID=\"rolling\"
VERSION=\"Pear Edition\"
ID=pulsaros
ID_LIKE=debian
HOME_URL=\"https://inled.es\"
DOCUMENTATION_URL=\"https://inled.es\"
SUPPORT_URL=\"https://inled.es\"
BUG_REPORT_URL=\"https://github.com/InledGroup/pulsaros/issues\"
PRIVACY_POLICY_URL=\"https://inled.es\"
LOGO=pulsar-logo
ANSI_COLOR=\"38;2;135;206;235\"
EOF
        mkdir -p /usr/lib
        cp -f /etc/os-release /usr/lib/os-release

        # Ensure the Pulsar OS distributor logo
        if [ -f /usr/share/pixmaps/pulsar-logo.png ]; then
            cp -f /usr/share/pixmaps/pulsar-logo.png /usr/share/pixmaps/distributor-logo.png 2>/dev/null || true
        fi

        gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
    "

    # Configure static autologin for SDDM live user inside the rootfs (using GNOME Wayland)
    echo "⚙️ Configuring static autologin for the live session (Wayland)..."
    $SUDO mkdir -p "$ROOTFS_TARGET/etc/sddm.conf.d"
    cat <<EOF | $SUDO tee "$ROOTFS_TARGET/etc/sddm.conf.d/autologin.conf" > /dev/null
[Autologin]
User=live
Session=gnome
EOF
    $SUDO chmod 644 "$ROOTFS_TARGET/etc/sddm.conf.d/autologin.conf"

    # Force Plymouth to not use SimpleDRM in the configuration file to prevent early boot graphics freezes
    if [ -f "$ROOTFS_TARGET/etc/plymouth/plymouthd.conf" ]; then
        echo "⚙️ Forcing UseSimpledrm=false in /etc/plymouth/plymouthd.conf..."
        $SUDO sed -i 's/^UseSimpledrm=.*/UseSimpledrm=false/' "$ROOTFS_TARGET/etc/plymouth/plymouthd.conf"
    fi
}
