# ==============================================================================
# Pear profile — post-install branding & extra apps (sourced by build-iso.sh)
# ==============================================================================
# Defines profile_customize(), called once by the engine after Calamares
# config generation, before initramfs regeneration (former Phase 5.5).
# ==============================================================================

profile_customize() {
    # Configure Flathub so Discover/flatpak have somewhere to install from
    echo "📦 Configuring Flathub repository..."
    $SUDO "$CHROOT_BIN" "$ROOTFS_TARGET" /bin/bash -c "
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
    "

    # pearOS-installer: cloned live from GitHub, same as ../iso/build-binary
    # does for the upstream Arch project. Still has Arch/pacman-specific bits
    # (system_install/setup) that won't work on this Debian target as-is --
    # left alone on purpose, to be adapted separately later.
    echo "📥 Cloning pearOS-installer..."
    $SUDO rm -rf "$ROOTFS_TARGET/usr/share/pearOS-installer"
    $SUDO mkdir -p "$ROOTFS_TARGET/usr/share"
    $SUDO git clone --depth 1 https://github.com/Pear-Project/pearOS-installer.git "$ROOTFS_TARGET/usr/share/pearOS-installer"

    # pearos-livecd-desktop's Desktop icon runs `bash bin_install` (a bare
    # filename, no path) -- bash resolves that via $PATH same as any other
    # command, but nothing puts bin_install/bin_post there themselves; their
    # own DEBBUILD says as much ("references a script ... that isn't part
    # of this repo"). Both scripts already cd to an absolute path
    # internally, so copying them onto $PATH as-is is enough to make the
    # icon actually launch something instead of failing outright.
    echo "🔗 Wiring pearOS-installer's bin_install/bin_post onto PATH..."
    $SUDO install -Dm755 "$ROOTFS_TARGET/usr/share/pearOS-installer/general_bin/bin_install" "$ROOTFS_TARGET/usr/local/bin/bin_install"
    $SUDO install -Dm755 "$ROOTFS_TARGET/usr/share/pearOS-installer/general_bin/bin_post" "$ROOTFS_TARGET/usr/local/bin/bin_post"

    # Create the liveuser account at build time -- baked directly into the
    # squashfs, matching ../iso/'s airootfs/etc/passwd approach, instead of
    # relying on live-config's boot-time 0030-user-setup component. That
    # component raced against SDDM's autologin (session starts before the
    # account + /etc/skel copy are ready, so branding only showed up after
    # a manual relog); baking the account in at build time removes the
    # race entirely. live-config still runs its other components at boot;
    # 0030-user-setup itself just no-ops once it sees liveuser already
    # exists (it checks /etc/passwd before doing anything).
    #
    # adduser's own skel-copy is NOT trusted here -- verified directly that
    # it silently gives up partway through .config (almost everything past
    # .config/autostart is missing from the result, including the actual
    # panel/widget layout file), apparently tripping over the same kind of
    # symlink-safety check that only warned-and-skipped once for .themes
    # elsewhere. A plain `cp -a`-style recursive copy of the same skel tree
    # (the exact command ../iso/'s _make_customize_airootfs uses) copies it
    # correctly, so that's run explicitly afterward instead of relying on
    # whatever adduser did.
    echo "👤 Creating liveuser account (build-time, matching ../iso/)..."
    $SUDO "$CHROOT_BIN" "$ROOTFS_TARGET" /bin/bash -c "
        if ! grep -q '^liveuser:' /etc/passwd; then
            adduser --disabled-password --gecos liveuser liveuser
            passwd -d liveuser
            usermod -aG sudo,audio,video,plugdev,netdev,cdrom,dialout,bluetooth liveuser
        fi
        cp -dnRT --preserve=mode,timestamps,links -- /etc/skel/. /home/liveuser
        chown -hR liveuser:liveuser /home/liveuser
    "

    # Configure static autologin for SDDM live user inside the rootfs (Plasma Wayland session)
    echo "⚙️ Configuring static autologin for the live session (Plasma Wayland)..."
    $SUDO mkdir -p "$ROOTFS_TARGET/etc/sddm.conf.d"
    cat <<EOF | $SUDO tee "$ROOTFS_TARGET/etc/sddm.conf.d/autologin.conf" > /dev/null
[Autologin]
User=liveuser
Session=plasma
EOF
    $SUDO chmod 644 "$ROOTFS_TARGET/etc/sddm.conf.d/autologin.conf"

    # Force Plymouth to not use SimpleDRM in the configuration file to prevent early boot graphics freezes
    if [ -f "$ROOTFS_TARGET/etc/plymouth/plymouthd.conf" ]; then
        echo "⚙️ Forcing UseSimpledrm=false in /etc/plymouth/plymouthd.conf..."
        $SUDO sed -i 's/^UseSimpledrm=.*/UseSimpledrm=false/' "$ROOTFS_TARGET/etc/plymouth/plymouthd.conf"
    fi

    # Activate the pear-plymouth theme shipped inside pearos-settings
    # (usr/share/plymouth/themes/pear-plymouth/, already installed by Phase 5
    # since it's part of PROFILE_REPO_PACKAGES). Phase 6's update-initramfs
    # picks this selection up afterward.
    echo "⚙️ Setting Plymouth theme to $PROFILE_PLYMOUTH_THEME..."
    $SUDO "$CHROOT_BIN" "$ROOTFS_TARGET" /bin/bash -c "
        plymouth-set-default-theme $PROFILE_PLYMOUTH_THEME
    "

    # GRUB is install-target only (Ploader/syslinux boot the live session --
    # see build-iso.sh Phase 7), but Calamares' stock "bootloader" module
    # still runs grub-install/update-grub on the installed system, using
    # whatever's already in this chroot's /etc/default/grub and
    # /usr/share/grub/themes/ at that point. Vendored from ../iso/pear/
    # airootfs/usr/share/grub/themes/pearOS/ (their reference project ships
    # the same theme for their own installed-system GRUB). Without setting
    # GRUB_DISTRIBUTOR explicitly, Debian's grub-common falls back to a
    # hardcoded "Debian" (its own `lsb_release -i -s || echo Debian`
    # default, and lsb_release isn't installed here anyway) -- menu entries
    # would read "Debian GNU/Linux" regardless of /etc/os-release branding.
    echo "🎨 Installing pearOS GRUB theme and branding for the installed system..."
    $SUDO mkdir -p "$ROOTFS_TARGET/usr/share/grub/themes"
    $SUDO cp -r "$PROFILE_DIR/grub-theme/pearOS" "$ROOTFS_TARGET/usr/share/grub/themes/pearOS"
    if [ -f "$ROOTFS_TARGET/etc/default/grub" ]; then
        $SUDO sed -i \
            -e 's|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR="pearOS Goldwing"|' \
            -e 's|^#\?GRUB_DISABLE_OS_PROBER=.*|GRUB_DISABLE_OS_PROBER=false|' \
            "$ROOTFS_TARGET/etc/default/grub"
        if ! grep -q '^GRUB_DISTRIBUTOR=' "$ROOTFS_TARGET/etc/default/grub"; then
            echo 'GRUB_DISTRIBUTOR="pearOS Goldwing"' | $SUDO tee -a "$ROOTFS_TARGET/etc/default/grub" > /dev/null
        fi
        if ! grep -q '^GRUB_DISABLE_OS_PROBER=' "$ROOTFS_TARGET/etc/default/grub"; then
            echo 'GRUB_DISABLE_OS_PROBER=false' | $SUDO tee -a "$ROOTFS_TARGET/etc/default/grub" > /dev/null
        fi
        if grep -q '^GRUB_THEME=' "$ROOTFS_TARGET/etc/default/grub"; then
            $SUDO sed -i 's|^GRUB_THEME=.*|GRUB_THEME="/usr/share/grub/themes/pearOS/theme.txt"|' "$ROOTFS_TARGET/etc/default/grub"
        else
            echo 'GRUB_THEME="/usr/share/grub/themes/pearOS/theme.txt"' | $SUDO tee -a "$ROOTFS_TARGET/etc/default/grub" > /dev/null
        fi
    fi

    # Calamares branding + default-user creation, ported from
    # pearOS-archlinux/pear-calamares-config (vendored under
    # profiles/pear/calamares-branding/). That reference project skips the
    # interactive "users" page entirely and auto-creates a fixed
    # default/pearos account via a shellprocess job instead -- same model
    # adopted here, adapted for Debian (chroot not arch-chroot, sudo group
    # not wheel; see calamares-branding/shellprocess-pearos-autouser.conf
    # for the rest of the diff).
    echo "🎨 Installing pearOS Calamares branding..."
    $SUDO mkdir -p "$ROOTFS_TARGET/etc/calamares/branding"
    $SUDO cp -r "$PROFILE_DIR/calamares-branding/pearOS" "$ROOTFS_TARGET/etc/calamares/branding/pearOS"
    $SUDO cp "$PROFILE_DIR/calamares-branding/shellprocess-pearos-autouser.conf" "$ROOTFS_TARGET/etc/calamares/modules/shellprocess-pearos-autouser.conf"

    if [ -f "$ROOTFS_TARGET/etc/calamares/settings.conf" ]; then
        echo "⚙️ Switching Calamares to pearOS branding and default-user creation..."
        $SUDO sed -i 's/^branding: debian$/branding: pearOS/' "$ROOTFS_TARGET/etc/calamares/settings.conf"
        # Drop the interactive "users" step (both the show-phase page and
        # its exec-phase job) -- shellprocess@pearosautouser replaces it.
        $SUDO sed -i '/^  - users$/d' "$ROOTFS_TARGET/etc/calamares/settings.conf"
        if ! grep -q 'shellprocess@pearosautouser' "$ROOTFS_TARGET/etc/calamares/settings.conf"; then
            $SUDO sed -i '/^  - localecfg$/a\  - shellprocess@pearosautouser' "$ROOTFS_TARGET/etc/calamares/settings.conf"
        fi
        if ! grep -q 'id:.*pearosautouser' "$ROOTFS_TARGET/etc/calamares/settings.conf"; then
            if grep -q '^instances:' "$ROOTFS_TARGET/etc/calamares/settings.conf"; then
                $SUDO sed -i '/^instances:/a\
- id:       pearosautouser\
  module:   shellprocess\
  config:   shellprocess-pearos-autouser.conf' "$ROOTFS_TARGET/etc/calamares/settings.conf"
            else
                $SUDO sed -i '/^sequence:/i\
instances:\
- id:       pearosautouser\
  module:   shellprocess\
  config:   shellprocess-pearos-autouser.conf\
' "$ROOTFS_TARGET/etc/calamares/settings.conf"
            fi
        fi
    fi
}
