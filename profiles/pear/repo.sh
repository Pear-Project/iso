# ==============================================================================
# Pear profile — repository setup (sourced by build-iso.sh)
# ==============================================================================
# Defines profile_setup_repo() / profile_teardown_repo(), called by the engine
# right before / after the package-install step of Phase 5. Both run in the
# engine's own shell (sourced, not exec'd) so they see $ROOTFS_TARGET,
# $CHROOT_BIN, $SUDO, $BRANCH, $DEBIAN_VERSION and $PROFILE_DIR directly.
# ==============================================================================

profile_setup_repo() {
    echo "--- 🌐 Configuring APT repositories (Debian Contrib/Backports and Inled) ---"
    $SUDO sed -i "s/$DEBIAN_VERSION main/$DEBIAN_VERSION main contrib non-free non-free-firmware/g" "$ROOTFS_TARGET/etc/apt/sources.list"
    if ! grep -q "${DEBIAN_VERSION}-backports" "$ROOTFS_TARGET/etc/apt/sources.list"; then
        echo "deb http://deb.debian.org/debian ${DEBIAN_VERSION}-backports main contrib non-free non-free-firmware" | $SUDO tee -a "$ROOTFS_TARGET/etc/apt/sources.list" > /dev/null
    fi

    # Copy the bundled Inled APT GPG keyring directly to the chroot target
    echo "🔑 Copying the pre-packaged Inled GPG keychain..."
    $SUDO mkdir -p "$ROOTFS_TARGET/usr/share/keyrings"
    $SUDO cp "$PROFILE_DIR/keyring.gpg" "$ROOTFS_TARGET/usr/share/keyrings/inled-archive-keyring.gpg"

    echo "deb [signed-by=/usr/share/keyrings/inled-archive-keyring.gpg] https://apt.inled.es $BRANCH main" | \
        $SUDO tee "$ROOTFS_TARGET/etc/apt/sources.list.d/inled.list" > /dev/null

    $SUDO tee "$ROOTFS_TARGET/etc/apt/preferences.d/99inled" > /dev/null <<'EOF'
Package: *
Pin: origin "apt.inled.es"
Pin-Priority: 1001
EOF

    # Create temporary dpkg-diverts to intercept DroidTux's and AppInstall's keyring setup
    echo "⚙️ Setting up temporary dpkg bypasses for DroidTux and AppInstall..."
    $SUDO "$CHROOT_BIN" "$ROOTFS_TARGET" /bin/bash -c "
        dpkg-divert --add --rename --divert /usr/bin/curl.real /usr/bin/curl
        dpkg-divert --add --rename --divert /usr/bin/wget.real /usr/bin/wget
        dpkg-divert --add --rename --divert /usr/bin/gpg.real /usr/bin/gpg
    "

    $SUDO tee "$ROOTFS_TARGET/usr/bin/curl" > /dev/null << 'EOF'
#!/bin/bash
if [[ "$*" == *"apt.inled.es/archive.key"* ]]; then
    echo "dummy-key"
    exit 0
fi
exec /usr/bin/curl.real "$@"
EOF
    $SUDO chmod +x "$ROOTFS_TARGET/usr/bin/curl"

    $SUDO tee "$ROOTFS_TARGET/usr/bin/wget" > /dev/null << 'EOF'
#!/bin/bash
if [[ "$*" == *"apt.inled.es/archive.key"* ]]; then
    echo "dummy-key"
    exit 0
fi
exec /usr/bin/wget.real "$@"
EOF
    $SUDO chmod +x "$ROOTFS_TARGET/usr/bin/wget"

    $SUDO tee "$ROOTFS_TARGET/usr/bin/gpg" > /dev/null << 'EOF'
#!/bin/bash
if [[ "$*" == *"--dearmor"* ]] && [[ "$*" == *"/usr/share/keyrings/inled-archive-keyring.gpg"* ]]; then
    exit 0
fi
exec /usr/bin/gpg.real --yes --batch "$@"
EOF
    $SUDO chmod +x "$ROOTFS_TARGET/usr/bin/gpg"
}

profile_teardown_repo() {
    echo "🧹 Cleaning DroidTux and AppInstall dpkg mocks and bypasses..."
    $SUDO rm -f "$ROOTFS_TARGET/usr/bin/curl"
    $SUDO rm -f "$ROOTFS_TARGET/usr/bin/wget"
    $SUDO rm -f "$ROOTFS_TARGET/usr/bin/gpg"

    $SUDO "$CHROOT_BIN" "$ROOTFS_TARGET" /bin/bash -c "
        dpkg-divert --remove --rename /usr/bin/curl
        dpkg-divert --remove --rename /usr/bin/wget
        dpkg-divert --remove --rename /usr/bin/gpg
    "
}
