# ==============================================================================
# Pear profile — package selection (sourced by build-iso.sh)
# ==============================================================================
# Sourced after profile.conf is loaded, so it can reference PROFILE_SLUG etc.
# Defines the arrays/vars the engine uses to build its `apt-get install`
# invocations in Phase 5.
# ==============================================================================

# Installed from the pearOS repo in PRODUCTION mode. In LOCAL mode these ship
# instead as locally-built .deb files (installed via /tmp/packages/*.deb).
PROFILE_REPO_PACKAGES=(
    # Headers matching the custom kernel installed by profile_customize()
    # (see customize.sh) -- needed to build DKMS modules (nvidia-driver,
    # broadcom-sta-dkms, virtualbox-guest-utils) against it. Placeholder
    # version -- profile_setup_repo() (repo.sh) rewrites this entry in place
    # to match whatever kernel it actually downloaded, once it knows the
    # real version.
    linux-headers-0-pearos
    pearos-appmenu
    pearos-bootsound
    pearos-calculator
    pearos-calendar
    pearos-contacts
    pearos-dock
    pearos-filesystem
    pearos-icons
    pearos-liquidgel
    pearos-livecd-desktop
    pearos-magiclamp
    pearos-muternvf
    pearos-notch
    pearos-notes
    pafari
    pearos-settings
    system-settings
    pearos-todo
    pearos-welcome
    pearos-window-borders
    pearos-window-tinter
    pearos-zshconfig
    hyprvisor
    # Only published on apt.pearos.xyz (system-overview isn't in Debian at
    # all; neofetch's pearOS build is newer than Debian's own)
    system-overview
    neofetch
)

# Always installed from the repo, in both LOCAL and PRODUCTION mode.
PROFILE_COMMON_PACKAGES=(
    # pearos-settings' PearPrivacy plasmoid (usr/share/plasma/plasmoids/
    # PearPrivacy/contents/ui/main.qml) does "import QtWebEngine" and uses
    # WebEngineView directly -- needs the QML plugin, not just the C++
    # widgets lib. Not pearos-welcome (its CMakeLists.txt only links
    # Widgets/DBus/Network -- QWebEngineView is mentioned only in comments
    # about code that was deliberately NOT used). Neither package declares
    # this dependency in its own control file. Remove once upstream fixes it.
    qml6-module-qtwebengine
    libqt6webenginewidgets6
)

# Installed from the ${DEBIAN_VERSION}-backports suite specifically
PROFILE_BACKPORTS_PACKAGES=()

# apt pin glob used in LOCAL mode so the profile's own package names never
# get pulled from the remote repo once the local .deb build is installed
PROFILE_LOCAL_PIN_GLOB="$PROFILE_SLUG-*"
