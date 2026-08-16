# ==============================================================================
# Pear profile — package selection (sourced by build-iso.sh)
# ==============================================================================
# Sourced after $BOOTLOADER is parsed and profile.conf is loaded, so it can
# reference both. Defines the arrays/vars the engine uses to build its
# `apt-get install` invocations in Phase 5.
# ==============================================================================

# Installed from the Inled repo in PRODUCTION mode. In LOCAL mode these ship
# instead as locally-built .deb files (installed via /tmp/packages/*.deb).
PROFILE_REPO_PACKAGES=(
    "$PROFILE_SLUG-branding"
    "$PROFILE_SLUG-theme"
    "$PROFILE_SLUG-gnome"
    "$PROFILE_SLUG-global-menu"
    "$PROFILE_SLUG-spotlight-launcher"
    "$PROFILE_SLUG-sddm"
    "$PROFILE_SLUG-plymouth"
    "$PROFILE_SLUG-$BOOTLOADER"
    "$PROFILE_SLUG-calamares"
    "$PROFILE_SLUG-essential"
    "$PROFILE_SLUG-welcome"
    "$PROFILE_SLUG-recovery"
    "$PROFILE_SLUG-bootsound"
    "$PROFILE_SLUG-boot-icons"
    gnome-macos-remap-wayland
)

# Always installed from the repo, in both LOCAL and PRODUCTION mode
PROFILE_COMMON_PACKAGES=(
    droidtux
    macboat
    appinstall
    seafari
    spotlight-python
)

# Installed from the ${DEBIAN_VERSION}-backports suite specifically
PROFILE_BACKPORTS_PACKAGES=(
    scrcpy
)

# apt pin glob used in LOCAL mode so the profile's own package names never
# get pulled from the remote repo once the local .deb build is installed
PROFILE_LOCAL_PIN_GLOB="$PROFILE_SLUG-* gnome-macos-remap-wayland"
