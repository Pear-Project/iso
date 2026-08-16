#!/bin/bash
# ==============================================================================
# Debian Live ISO Builder — generic engine, distro identity lives in profiles/
# ==============================================================================
# This script builds a clean chroot base file system, installs packages from
# a profile's repo (or local builds), and packages everything into a bootable
# hybrid Live CD ISO image. What gets built — package list, extra APT repo,
# branding, boot menu text/theme — comes from profiles/<name>/ (see --profile).
#
# Usage:
#   ./build-iso.sh [--clean-base] [--local] [--profile <name>]
#
# Options:
#   --clean-base    Delete the base Debian cache and download it from scratch.
#   --local         Use local .deb packages from build/packages/ instead of the repo.
#   --profile       Distro profile to build, from profiles/<name>/. Default: pear.
#
# Safety:
#   By default the script NEVER installs packages on the host machine. If host
#   dependencies are missing it aborts with instructions. To allow host package
#   installation, run with ALLOW_HOST_INSTALL=true (dangerous on Arch hosts).
# ==============================================================================

set -e

# Save the original arguments before they get consumed by shift, for auto-elevation
ORIGINAL_ARGS=("$@")

# ==============================================================================
# Parse Arguments
# ==============================================================================
CLEAN_BASE=false
USE_LOCAL_DEBS=false
BOOTLOADER="" # Resolved after the profile loads: --grub/--refind override the profile's default
BOOTLOADER_EXPLICIT=false
BRANCH="stable"
WITH_NVIDIA=false
PULSAR_VERSION=""
PROFILE="pear"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean-base)
            CLEAN_BASE=true
            shift
            ;;
        --local)
            USE_LOCAL_DEBS=true
            shift
            ;;
        --refind)
            BOOTLOADER="refind"
            BOOTLOADER_EXPLICIT=true
            shift
            ;;
        --grub)
            BOOTLOADER="grub"
            BOOTLOADER_EXPLICIT=true
            shift
            ;;
        --nvidia)
            WITH_NVIDIA=true
            shift
            ;;
        --branch|-b)
            BRANCH="$2"
            shift 2
            ;;
        --version|-v)
            PULSAR_VERSION="$2"
            export PULSAR_VERSION
            shift 2
            ;;
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        *)
            echo "❌ Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ "$BRANCH" != "stable" ] && [ "$BRANCH" != "forky" ] && [ "$BRANCH" != "rolling" ]; then
    echo "❌ Error: Branch must be 'stable', 'forky' or 'rolling'. Value received: $BRANCH"
    exit 1
fi

# ==============================================================================
# Load the distro profile
# ==============================================================================
# Loaded early (before the host dependency checks below) because the profile
# can set the default bootloader, which those checks need to already know.
ISO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ISO_DIR/build"
PROFILE_DIR="$ISO_DIR/profiles/$PROFILE"
if [ ! -d "$PROFILE_DIR" ]; then
    echo "❌ Error: Unknown profile '$PROFILE' (expected directory: $PROFILE_DIR)"
    exit 1
fi
for required in profile.conf packages.list repo.sh packages.sh customize.sh; do
    if [ ! -f "$PROFILE_DIR/$required" ]; then
        echo "❌ Error: Profile '$PROFILE' is missing $required"
        exit 1
    fi
done
source "$PROFILE_DIR/profile.conf"

# Resolve the bootloader: --grub/--refind (if passed) win; otherwise fall back
# to the profile's own default, then check it's one the profile supports.
if ! $BOOTLOADER_EXPLICIT; then
    BOOTLOADER="$PROFILE_DEFAULT_BOOTLOADER"
fi
bootloader_supported=false
for bl in "${PROFILE_SUPPORTED_BOOTLOADERS[@]}"; do
    if [ "$bl" = "$BOOTLOADER" ]; then
        bootloader_supported=true
        break
    fi
done
if ! $bootloader_supported; then
    echo "❌ Error: Profile '$PROFILE' does not support the '$BOOTLOADER' bootloader. Supported: ${PROFILE_SUPPORTED_BOOTLOADERS[*]}"
    exit 1
fi

# packages.sh is sourced after $BOOTLOADER is finalized: it references it
# directly (e.g. "$PROFILE_SLUG-$BOOTLOADER") when building its package arrays.
source "$PROFILE_DIR/repo.sh"
source "$PROFILE_DIR/packages.sh"
source "$PROFILE_DIR/customize.sh"

# ==============================================================================
# Check Host Dependencies
# ==============================================================================
check_host_package_installed() {
    local pkg="$1"
    if command -v pacman >/dev/null 2>&1; then
        local arch_pkg="$pkg"
        case "$pkg" in
            grub-pc-bin|grub-efi-amd64-bin)
                arch_pkg="grub"
                ;;
            mtools)
                arch_pkg="mtools"
                ;;
            debian-archive-keyring)
                arch_pkg="debian-archive-keyring"
                ;;
        esac
        pacman -Qs "^${arch_pkg}$" >/dev/null 2>&1
        return $?
    elif command -v dpkg >/dev/null 2>&1; then
        dpkg -l | grep -q "^ii\s\+${pkg}\b" >/dev/null 2>&1
        return $?
    else
        return 0
    fi
}

MISSING_PACKAGES=()

# Check standard commands
CMDS=("mmdebstrap" "fakeroot" "rsync" "jq" "curl" "unzip" "wget" "mksquashfs" "xorriso" "sassc")
if [ "$BOOTLOADER" = "grub" ]; then
    CMDS+=("grub-mkrescue")
fi

for cmd in "${CMDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING_PACKAGES+=("$cmd")
    fi
done

# Command to package name mapping for special cases
if ! command -v convert >/dev/null 2>&1; then
    MISSING_PACKAGES+=("imagemagick")
fi

if ! command -v fuser >/dev/null 2>&1; then
    MISSING_PACKAGES+=("psmisc")
fi

if ! check_host_package_installed "mtools"; then
    MISSING_PACKAGES+=("mtools")
fi

if [ "$BOOTLOADER" = "grub" ]; then
    # We also need the BIOS and UEFI build files for grub-mkrescue
    if ! check_host_package_installed "grub-pc-bin"; then
        MISSING_PACKAGES+=("grub-pc-bin")
    fi
    if ! check_host_package_installed "grub-efi-amd64-bin"; then
        MISSING_PACKAGES+=("grub-efi-amd64-bin")
    fi
fi

# IMPORTANT: Check Debian archive keyring on non-Debian host distros (like Ubuntu/Mint)
if [ ! -f "/usr/share/keyrings/debian-archive-keyring.gpg" ]; then
    MISSING_PACKAGES+=("debian-archive-keyring")
fi

# Install dependencies if they are missing
if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
    echo "⚠️ Essential dependencies detected to be missing from the host: ${MISSING_PACKAGES[*]}"
    echo "These tools are required for the ISO build ($BOOTLOADER)."
    
    # SAFETY GUARD: never touch the host package manager by default.
    # The ISO build runs on the user's own machine (often Arch), and host-level
    # pacman/apt operations (especially 'pacman -Sy' partial upgrades) can break it.
    # Only auto-install when explicitly requested with --install-host-deps.
    if [ "$ALLOW_HOST_INSTALL" != "true" ]; then
        echo "❌ Missing host dependencies. They will NOT auto-install to protect your system."
        echo "   Manually install missing packages (e.g. sudo pacman -S ${MISSING_PACKAGES[*]})"
        echo "   or repeat the command with the variable ALLOW_HOST_INSTALL=true to authorize the installation."
        exit 1
    fi
    
    # Auto-approve if in non-interactive environment (CI, pipeline, no TTY stdin)
    auto_install=false
    if [ "$GITHUB_ACTIONS" = "true" ] || [ ! -t 0 ]; then
        auto_install=true
    else
        read -p "Do you want to install the missing dependencies now? (y/n):" confirm
        confirm=$(echo "$confirm" | tr -d '\r')
        if [[ "$confirm" =~ ^[sSyY]$ ]] || [ -z "$confirm" ]; then
            auto_install=true
        fi
    fi
    
    if [ "$auto_install" = true ]; then
        # Detect package manager and install mapped packages
        pkg_manager=""
        if command -v pacman >/dev/null 2>&1; then
            pkg_manager="pacman"
        elif command -v apt-get >/dev/null 2>&1; then
            pkg_manager="apt"
        fi

        if [ -z "$pkg_manager" ]; then
            echo "❌ Error: A supported package manager (apt or pacman) was not detected."
            exit 1
        fi

        packages_to_install=()
        for item in "${MISSING_PACKAGES[@]}"; do
            case "$item" in
                mmdebstrap|fakeroot|rsync|jq|curl|unzip|wget|xorriso|imagemagick|psmisc|mtools|debian-archive-keyring|sassc)
                    packages_to_install+=("$item")
                    ;;
                mksquashfs)
                    packages_to_install+=("squashfs-tools")
                    ;;
                grub-mkrescue)
                    if [ "$pkg_manager" = "pacman" ]; then
                        packages_to_install+=("grub")
                    else
                        packages_to_install+=("grub-common")
                    fi
                    ;;
                grub-pc-bin|grub-efi-amd64-bin)
                    if [ "$pkg_manager" = "apt" ]; then
                        packages_to_install+=("$item")
                    fi
                    ;;
                *)
                    packages_to_install+=("$item")
                    ;;
            esac
        done

        # Deduplicate
        packages_to_install=($(echo "${packages_to_install[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

        if [ ${#packages_to_install[@]} -gt 0 ]; then
            echo "📥 Installing dependencies on the host using $pkg_manager..."
            if [ "$pkg_manager" = "pacman" ]; then
                # Separate official pacman packages from AUR packages
                pacman_official=()
                aur_packages=()
                for pkg in "${packages_to_install[@]}"; do
                    if pacman -Si "$pkg" >/dev/null 2>&1; then
                        pacman_official+=("$pkg")
                    else
                        aur_packages+=("$pkg")
                    fi
                done

                if [ ${#pacman_official[@]} -gt 0 ]; then
                    echo "📥 Installing official dependencies using pacman..."
                    if command -v pkexec >/dev/null 2>&1 && [ -n "$DISPLAY" ]; then
                        pkexec pacman -S --needed --noconfirm "${pacman_official[@]}"
                    else
                        sudo pacman -S --needed --noconfirm "${pacman_official[@]}"
                    fi
                fi

                if [ ${#aur_packages[@]} -gt 0 ]; then
                    echo "⚠️ The following packages are from the AUR repository and are not in the official repos:"
                    echo "   ${aur_packages[*]}"
                    
                    # Try to locate an AUR helper
                    aur_helper=""
                    if command -v yay >/dev/null 2>&1; then
                        aur_helper="yay"
                    elif command -v paru >/dev/null 2>&1; then
                        aur_helper="paru"
                    fi

                    if [ -n "$aur_helper" ]; then
                        echo "🚀 An AUR helper has been detected: $aur_helper. Installing..."
                        # Run AUR helper as the original non-root user if SUDO_USER is defined
                        if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
                            sudo -u "$SUDO_USER" "$aur_helper" -S --noconfirm "${aur_packages[@]}"
                        else
                            "$aur_helper" -S --noconfirm "${aur_packages[@]}"
                        fi
                    else
                        echo "❌ No AUR helper (like yay or paru) detected."
                        echo "Please install these packages manually before continuing:"
                        echo "   yay -S ${aur_packages[*]}"
                        exit 1
                    fi
                fi
            elif [ "$pkg_manager" = "apt" ]; then
                if command -v pkexec >/dev/null 2>&1 && [ -n "$DISPLAY" ]; then
                    pkexec /bin/bash -c "apt-get update && apt-get install -y ${packages_to_install[*]}"
                else
                    sudo apt-get update && sudo apt-get install -y "${packages_to_install[@]}"
                fi
            fi
            echo "✅ Successfully installed dependencies."
        else
            echo "✅ There are no packages to install for your platform."
        fi
    else
        echo "❌ Error: Host requirements cannot be met. Going out..."
        exit 1
    fi
fi

# ==============================================================================
# Helper: Auto-Elevate to Root
# ==============================================================================
if [ "$EUID" -ne 0 ]; then
    echo "🔐 This script requires superuser privileges to run."
    echo "Re-executing with pkexec..."
    if command -v pkexec >/dev/null 2>&1 && [ -n "$DISPLAY" ]; then
        exec pkexec "$0" "${ORIGINAL_ARGS[@]}"
    else
        exec sudo "$0" "${ORIGINAL_ARGS[@]}"
    fi
fi

SUDO=""

# ==============================================================================
# PHASE 1: Environment Settings and Initialization
# ==============================================================================

# Import global configs if present
if [ -f "../configs/env.sh" ]; then
    source ../configs/env.sh
elif [ -f "configs/env.sh" ]; then
    source configs/env.sh
else
    ARCH="amd64"
    MIRROR="http://deb.debian.org/debian"
fi

# Override Debian version based on the selected branch
case "$BRANCH" in
    stable)
        DEBIAN_VERSION="trixie"
        ;;
    forky)
        DEBIAN_VERSION="forky"
        ;;
    rolling)
        DEBIAN_VERSION="testing"
        ;;
esac

if $WITH_NVIDIA; then
    ROOTFS_BASE="$BUILD_DIR/rootfs-base-$BRANCH-nvidia"
    ROOTFS_TARGET="$BUILD_DIR/rootfs-target-$BRANCH-nvidia"
else
    ROOTFS_BASE="$BUILD_DIR/rootfs-base-$BRANCH"
    ROOTFS_TARGET="$BUILD_DIR/rootfs-target-$BRANCH"
fi

PACKAGE_LIST_FILE="$PROFILE_DIR/packages.list"

# Adjust paths / Fallback to root repo configuration if local config is missing
if [ ! -f "$PACKAGE_LIST_FILE" ]; then
    PACKAGE_LIST_FILE="$ISO_DIR/../profiles/$PROFILE/packages.list"
fi

# Dynamic detection of chroot binary path
CHROOT_BIN=$(command -v chroot || echo "/usr/sbin/chroot")

# Preventative cleanup function to ensure filesystems are unmounted on interruption
cleanup() {
    echo "🧹 Terminating and freeing chroot-mounted resources..."
    $SUDO umount -l "$ROOTFS_TARGET/proc" 2>/dev/null || true
    $SUDO umount -l "$ROOTFS_TARGET/sys" 2>/dev/null || true
    $SUDO umount -l "$ROOTFS_TARGET/dev/pts" 2>/dev/null || true
    $SUDO umount -l "$ROOTFS_TARGET/dev" 2>/dev/null || true

    # Restore original DNS config in target if backup exists
    if [ -f "$ROOTFS_TARGET/etc/resolv.conf.bak" ]; then
        $SUDO mv "$ROOTFS_TARGET/etc/resolv.conf.bak" "$ROOTFS_TARGET/etc/resolv.conf" 2>/dev/null || true
    fi
}

# Preflight: release any leftover mounts from previous interrupted builds.
# This runs once at startup so a fresh build never fails on stale mounts.
preflight_cleanup() {
    echo "🔍 Checking residual mounts from previous builds..."
    # Unmount anything mounted under the build directory (leftover chroot mounts)
    awk '$2 ~ "^'"$BUILD_DIR"'/" || $2 == "'"$BUILD_DIR"'" {print $2}' /proc/self/mounts 2>/dev/null | sort -r | while read -r mp; do
        echo "   Unmounting $mp"
        $SUDO umount -l "$mp" 2>/dev/null || true
    done
    # Free known helper mount points (e.g. ISO verification leftovers)
    for mp in /tmp/iso-mnt /tmp/pulsar-verify /tmp/pulsar-iso; do
        if mountpoint -q "$mp" 2>/dev/null; then
            echo "   Unmounting residual: $mp"
            $SUDO umount -l "$mp" 2>/dev/null || true
        fi
    done
    echo "✅ Residual mnt check completed."
}

trap cleanup EXIT INT TERM
preflight_cleanup

# ==============================================================================
# PHASE 2: Build and Maintain Base Cache
# ==============================================================================

# Auto-cleanup if previous bootstrap was incomplete or corrupted
if [ -d "$ROOTFS_BASE" ] && { [ ! -d "$ROOTFS_BASE/etc" ] || [ ! -d "$ROOTFS_BASE/proc" ] || [ ! -d "$ROOTFS_BASE/boot" ]; }; then
    echo "⚠️ Incomplete or corrupt base cache detected. Cleaning to regenerate..."
    cleanup
    $SUDO rm -rf "$ROOTFS_BASE"
fi

# Detect if the package list has changed since the cache was created
base_list_changed=false
if [ -d "$ROOTFS_BASE" ] && [ -f "$PACKAGE_LIST_FILE" ]; then
    # Generate the current list of packages to install (line-separated, no comments or empty lines)
    if $WITH_NVIDIA; then
        current_list=$(grep -v '^#' "$PACKAGE_LIST_FILE" | grep -v '^$')
    else
        current_list=$(grep -v '^#' "$PACKAGE_LIST_FILE" | grep -v '^$' | grep -v -E 'nvidia-driver|nvidia-settings|broadcom-sta-dkms|dkms|linux-headers-amd64')
    fi
    
    if [ ! -f "$ROOTFS_BASE/etc/build-base-packages.list" ]; then
        echo "🔄 build-base-packages.list was not found in the cache. Regenerating base..."
        base_list_changed=true
    else
        cached_list=$(cat "$ROOTFS_BASE/etc/build-base-packages.list")
        if [ "$current_list" != "$cached_list" ]; then
            echo "🔄 A change has been detected in the required package list with respect to the cached base. Regenerating base..."
            base_list_changed=true
        fi
    fi
fi

if $CLEAN_BASE || [ "$base_list_changed" = true ]; then
    echo "🚨 Base cache cleanup requested or package list change detected..."
    cleanup
    $SUDO rm -rf "$ROOTFS_BASE"
fi

if [ ! -d "$ROOTFS_BASE/etc" ]; then
    mkdir -p "$BUILD_DIR"
    
    if [ ! -f "$PACKAGE_LIST_FILE" ]; then
        echo "❌ Error: Base packages file not found in: $PACKAGE_LIST_FILE"
        exit 1
    fi
    
    echo "--- 📥 Creating Clean Debian Base (mmdebstrap) ---"

    if $WITH_NVIDIA; then
        echo "💚 Including proprietary hardware drivers (NVIDIA, Broadcom STA, DKMS, Headers) in the installation..."
        PACKAGE_LIST=$(grep -v '^#' "$PACKAGE_LIST_FILE" | grep -v '^$' | tr '\n' ',' | sed 's/,$//')
    else
        echo "💙 Excluding proprietary drivers (NVIDIA, Broadcom STA, DKMS, Headers) from installation..."
        PACKAGE_LIST=$(grep -v '^#' "$PACKAGE_LIST_FILE" | grep -v '^$' | grep -v -E 'nvidia-driver|nvidia-settings|broadcom-sta-dkms|dkms|linux-headers-amd64' | tr '\n' ',' | sed 's/,$//')
    fi

    # Add Debian keyring parameter if it exists (required on Ubuntu/Mint hosts)
    KEYRING_PARAM=""
    if [ -f "/usr/share/keyrings/debian-archive-keyring.gpg" ]; then
        KEYRING_PARAM="--keyring=/usr/share/keyrings/debian-archive-keyring.gpg"
        echo "🔑 Using Debian keyring: /usr/share/keyrings/debian-archive-keyring.gpg"
    fi

    # Execute Debian Bootstrap
    $SUDO /usr/bin/mmdebstrap \
        --architecture="$ARCH" \
        --components="main,contrib,non-free,non-free-firmware" \
        --variant=apt \
        $KEYRING_PARAM \
        --include="$PACKAGE_LIST" \
        "$DEBIAN_VERSION" \
        "$ROOTFS_BASE" \
        "$MIRROR"

    # Save the actually used package list in the base cache for future diffs
    if $WITH_NVIDIA; then
        grep -v '^#' "$PACKAGE_LIST_FILE" | grep -v '^$' | $SUDO tee "$ROOTFS_BASE/etc/build-base-packages.list" > /dev/null
    else
        grep -v '^#' "$PACKAGE_LIST_FILE" | grep -v '^$' | grep -v -E 'nvidia-driver|nvidia-settings|broadcom-sta-dkms|dkms|linux-headers-amd64' | $SUDO tee "$ROOTFS_BASE/etc/build-base-packages.list" > /dev/null
    fi

    echo "✅ Base Debian Bootstrap completed in: $ROOTFS_BASE"
else
    echo "✨ Virgin base detected in cache. Jumping bootstrap."
fi

# ==============================================================================
# PHASE 3: Clone clean base for working target
# ==============================================================================

echo "--- 🔄 Cloning Debian base in the working directory (target) ---"
cleanup
$SUDO rm -rf "$ROOTFS_TARGET"
mkdir -p "$ROOTFS_TARGET"

# Sync keeping special attributes
$SUDO rsync -aHAXx --delete "$ROOTFS_BASE/" "$ROOTFS_TARGET/"

# ==============================================================================
# PHASE 4: Mount virtual filesystems and network
# ==============================================================================

echo "⚙️ Configuring virtual mounts and DNS..."
$SUDO mount -t proc proc "$ROOTFS_TARGET/proc"
$SUDO mount -t sysfs sys "$ROOTFS_TARGET/sys"
$SUDO mount --bind /dev "$ROOTFS_TARGET/dev"
$SUDO mount --bind /dev/pts "$ROOTFS_TARGET/dev/pts"

# Ensure working DNS in chroot
if [ -f "$ROOTFS_TARGET/etc/resolv.conf" ]; then
    $SUDO cp "$ROOTFS_TARGET/etc/resolv.conf" "$ROOTFS_TARGET/etc/resolv.conf.bak"
fi
echo "nameserver 8.8.8.8" | $SUDO tee "$ROOTFS_TARGET/etc/resolv.conf" > /dev/null

# Create Plymouth theme directory and symlink in advance to satisfy initramfs hooks
theme_dir="$ROOTFS_TARGET/usr/share/plymouth/themes/$PROFILE_PLYMOUTH_THEME"
$SUDO mkdir -p "$theme_dir"
$SUDO ln -sf . "$theme_dir/images"

# ==============================================================================
# PHASE 5: Configure repositories and install the profile
# ==============================================================================

profile_setup_repo

BACKPORTS_INSTALL_CMD=""
if [ ${#PROFILE_BACKPORTS_PACKAGES[@]} -gt 0 ]; then
    BACKPORTS_INSTALL_CMD="yes | apt-get install -y -t ${DEBIAN_VERSION}-backports ${PROFILE_BACKPORTS_PACKAGES[*]}"
fi

if $USE_LOCAL_DEBS; then
    echo "--- 🛠️ LOCAL DEVELOPMENT MODE: Installing local .deb packages ---"
    pkg_dir_source="$ISO_DIR/../PKG"
    if [ ! -d "$pkg_dir_source" ]; then
        pkg_dir_source="/home/jaime/Documentos/pulsarbase/PKG"
    fi

    if [ -f "$pkg_dir_source/package-and-deploy.sh" ]; then
        echo "🔨 Building all local packages fresh for branch $BRANCH..."
        chmod +x "$pkg_dir_source/package-and-deploy.sh" 2>/dev/null || true
        (cd "$pkg_dir_source" && ./package-and-deploy.sh all --branch "$BRANCH")
    else
        echo "⚠️ Warning: Packaging script not found in $pkg_dir_source/package-and-deploy.sh. An attempt will be made to use pre-existing debs."
    fi

    LOCAL_DEBS_DIR=""
    POSSIBLE_DIRS=(
        "$ISO_DIR/../PKG/build/packages"
        "$ISO_DIR/../build/packages"
        "$ISO_DIR/build/packages"
        "/home/jaime/Documentos/pulsarbase/PKG/build/packages"
    )

    for dir in "${POSSIBLE_DIRS[@]}"; do
        if [ -d "$dir" ] && [ -n "$(ls "$dir"/*.deb 2>/dev/null)" ]; then
            LOCAL_DEBS_DIR="$dir"
            break
        fi
    done

    if [ -z "$LOCAL_DEBS_DIR" ]; then
        echo "❌Error: No local .deb packages found in any of the search paths:"
        for dir in "${POSSIBLE_DIRS[@]}"; do echo "   - $dir"; done
        echo "Run the packager in the PKG/ folder first."
        exit 1
    fi

    echo "📂 Using local packages from: $LOCAL_DEBS_DIR"
    $SUDO mkdir -p "$ROOTFS_TARGET/tmp/packages"
    $SUDO cp "$LOCAL_DEBS_DIR"/*.deb "$ROOTFS_TARGET/tmp/packages/"
    if [ "$BOOTLOADER" = "grub" ]; then
        $SUDO rm -f "$ROOTFS_TARGET/tmp/packages"/$PROFILE_SLUG-refind_*.deb
    else
        $SUDO rm -f "$ROOTFS_TARGET/tmp/packages"/$PROFILE_SLUG-grub_*.deb
    fi

    if [ "$BOOTLOADER" = "grub" ]; then
        BOOTLOADER_PKGS="grub-pc grub-efi-amd64-bin efibootmgr"
    else
        BOOTLOADER_PKGS="refind efibootmgr grub-pc grub-efi-amd64-bin"
    fi

    $SUDO tee "$ROOTFS_TARGET/etc/apt/preferences.d/local-$PROFILE_SLUG" > /dev/null <<EOF
Package: $PROFILE_LOCAL_PIN_GLOB
Pin: release *
Pin-Priority: -1
EOF

    $SUDO "$CHROOT_BIN" "$ROOTFS_TARGET" /bin/bash -c "
        set -e
        export DEBIAN_FRONTEND=noninteractive
        echo 'refind refind/install_to_esp boolean false' | debconf-set-selections
        echo 'DPkg::options { "--force-overwrite"; };' > /etc/apt/apt.conf.d/99force-overwrite
        apt-get update
        $BACKPORTS_INSTALL_CMD
        yes | apt-get install -y --no-install-recommends $BOOTLOADER_PKGS
        yes | apt-get install -y \
            /tmp/packages/*.deb \
            ${PROFILE_COMMON_PACKAGES[*]}
        rm -f /etc/apt/apt.conf.d/99force-overwrite
        apt-get clean
    "
    $SUDO rm -rf "$ROOTFS_TARGET/tmp/packages"
    $SUDO rm -f "$ROOTFS_TARGET/etc/apt/preferences.d/local-$PROFILE_SLUG"
    echo "✅ Local and cross-installed packages successfully."
else
    echo "---🌐 PRODUCTION MODE: Installing packages from APT repository ---"
    if [ "$BOOTLOADER" = "grub" ]; then
        BOOTLOADER_PKGS="grub-pc grub-efi-amd64-bin efibootmgr"
    else
        BOOTLOADER_PKGS="refind efibootmgr grub-pc grub-efi-amd64-bin"
    fi

    $SUDO "$CHROOT_BIN" "$ROOTFS_TARGET" /bin/bash -c "
        set -e
        export DEBIAN_FRONTEND=noninteractive
        echo 'refind refind/install_to_esp boolean false' | debconf-set-selections
        echo 'DPkg::options { "--force-overwrite"; };' > /etc/apt/apt.conf.d/99force-overwrite
        apt-get update
        $BACKPORTS_INSTALL_CMD
        yes | apt-get install -y --no-install-recommends \
            $BOOTLOADER_PKGS \
            ${PROFILE_REPO_PACKAGES[*]} \
            ${PROFILE_COMMON_PACKAGES[*]}
        rm -f /etc/apt/apt.conf.d/99force-overwrite
        apt-get clean
    "
fi

profile_teardown_repo

# Dynamically adjust Calamares configuration inside chroot based on distribution and selected bootloader
echo "⚙️ Configuring Calamares in the chroot target..."
$SUDO mkdir -p "$ROOTFS_TARGET/etc/calamares/modules"

# 1. Adjust modules search path in settings.conf to cover all possible Calamares module install paths
if [ -f "$ROOTFS_TARGET/etc/calamares/settings.conf" ]; then
    $SUDO sed -i 's|modules-search: \[ local, /usr/lib/x86_64-linux-gnu/calamares/modules, /usr/share/calamares/modules \]|modules-search: [ local, /usr/lib/x86_64-linux-gnu/calamares/modules, /usr/lib/calamares/modules, /usr/share/calamares/modules ]|' "$ROOTFS_TARGET/etc/calamares/settings.conf"
fi

# 2. Configure bootloader sequence in settings.conf
if [ "$BOOTLOADER" = "refind" ]; then
    echo "⚙️ Configuring Calamares boot sequence for rEFInd..."
    if [ -f "$ROOTFS_TARGET/etc/calamares/settings.conf" ]; then
        # Check if shellprocess@refind is already in settings.conf, if not add it right after bootloader
        if ! grep -q "shellprocess@refind" "$ROOTFS_TARGET/etc/calamares/settings.conf"; then
            $SUDO sed -i 's/- bootloader/- bootloader\n  - shellprocess@refind/' "$ROOTFS_TARGET/etc/calamares/settings.conf"
        fi
    fi
else
    echo "⚙️ Squid sequence configured for GRUB."
fi

# 3. Create unpackfs.conf, packages.conf, and users.conf
echo "⚙️ Generating Calamares configurations for Debian..."

# unpackfs.conf
cat <<EOF | $SUDO tee "$ROOTFS_TARGET/etc/calamares/modules/unpackfs.conf" > /dev/null
---
unpack:
    - source: "/lib/live/mount/medium/live/filesystem.squashfs"
      sourcefs: "squashfs"
      destination: ""
    - source: "/run/live/medium/live/filesystem.squashfs"
      sourcefs: "squashfs"
      destination: ""
      optional: true
EOF

# packages.conf
cat <<EOF | $SUDO tee "$ROOTFS_TARGET/etc/calamares/modules/packages.conf" > /dev/null
---
backend: apt

operations:
  - install:
      - firmware-linux
      - firmware-linux-nonfree
      - firmware-misc-nonfree
      - firmware-iwlwifi
      - firmware-realtek
      - firmware-atheros
      - firmware-brcm80211
      - intel-microcode
      - amd64-microcode
      - firmware-amd-graphics
  - try_remove:
      - calamares
      - calamares-settings-debian
      - $PROFILE_SLUG-calamares
EOF

# users.conf
cat <<EOF | $SUDO tee "$ROOTFS_TARGET/etc/calamares/modules/users.conf" > /dev/null
---
makeuproot: true
defaultGroups:
    - docker
    - sudo
    - users
    - lpadmin
    - sambashare
autologinUserWithWelcome: true
writeUsersPageToDummy: false
userShell: /bin/bash
EOF

# ==============================================================================
# PHASE 5.5: Profile-specific branding and extra apps
# ==============================================================================

profile_customize

# ==============================================================================
# PHASE 6: Final Tasks (Initramfs regeneration and cleanup)
# ==============================================================================

echo "--- 🔄 Finalizing and updating initramfs ---"
$SUDO "$CHROOT_BIN" "$ROOTFS_TARGET" /bin/bash -c "
    update-initramfs -u -k all
"

echo "✨ Chroot rootfs ready and correctly structured in: $ROOTFS_TARGET"

# ==============================================================================
# PHASE 7: Packaging and Live ISO Generation
# ==============================================================================
echo "---💿 Creating $PROFILE_DISPLAY_NAME Live ISO Image ---"

ISO_STAGING="$BUILD_DIR/iso-staging"
$SUDO rm -rf "$ISO_STAGING"
mkdir -p "$ISO_STAGING/live"
mkdir -p "$ISO_STAGING/boot/grub"

# 0. Clean temporary logs, test accounts, and unmount virtual filesystems prior to packaging
echo "🧹 Sanitizing rootfs target (cleaning test logs, temporary accounts, and cache)..."
$SUDO rm -rf "$ROOTFS_TARGET"/tmp/* "$ROOTFS_TARGET"/var/tmp/* "$ROOTFS_TARGET"/var/log/* 2>/dev/null || true
$SUDO rm -f "$ROOTFS_TARGET"/etc/sudoers.d/$PROFILE_SLUG-user-* 2>/dev/null || true
$SUDO rm -f "$ROOTFS_TARGET"/var/lib/AccountsService/users/* 2>/dev/null || true
$SUDO find "$ROOTFS_TARGET/home" -mindepth 1 -maxdepth 1 ! -name 'live' -exec rm -rf {} + 2>/dev/null || true

echo "Unmounting virtual filesystems in target..."
$SUDO umount -l "$ROOTFS_TARGET/proc" 2>/dev/null || true
$SUDO umount -l "$ROOTFS_TARGET/sys" 2>/dev/null || true
$SUDO umount -l "$ROOTFS_TARGET/dev/pts" 2>/dev/null || true
$SUDO umount -l "$ROOTFS_TARGET/dev" 2>/dev/null || true

# 1. Compress rootfs into SquashFS
echo "📦 Compressing rootfs into SquashFS..."
# Exclude dynamic/temp directories and virtual filesystems to save space and prevent errors
SQUASHFS_OUT="$ISO_STAGING/live/filesystem.squashfs"
$SUDO mksquashfs "$ROOTFS_TARGET" "$SQUASHFS_OUT" \
    -noappend \
    -comp xz \
    -Xbcj x86 \
    -e proc/* \
    -e sys/* \
    -e dev/* \
    -e run/* \
    -e tmp/* \
    -e var/tmp/* \
    -e var/log/* \
    -e root/.bash_history

# 2. Copy Kernel and Initrd to ISO staging
echo "🐧 Copying Kernel and Initrd..."
KERNEL_FILE=$(ls "$ROOTFS_TARGET"/boot/vmlinuz-* 2>/dev/null | head -n 1)
INITRD_FILE=$(ls "$ROOTFS_TARGET"/boot/initrd.img-* 2>/dev/null | head -n 1)

if [ -z "$KERNEL_FILE" ] || [ -z "$INITRD_FILE" ]; then
    echo "❌ Error: Kernel or initrd not found in target chroot."
    exit 1
fi

$SUDO cp "$KERNEL_FILE" "$ISO_STAGING/live/vmlinuz"
$SUDO cp "$INITRD_FILE" "$ISO_STAGING/live/initrd"

KERNEL_PARAMS="boot=live components username=live autologin cow_spacesize=4G module_blacklist=pcspkr i915.modeset=1 amdgpu.modeset=1 amdgpu.dcdebugmask=0x10 radeon.modeset=1 nvme_load=yes plymouth.use-simpledrm=0 quiet splash loglevel=3 noprompt --"
RAM_PARAMS="boot=live components username=live autologin cow_spacesize=4G module_blacklist=pcspkr i915.modeset=1 amdgpu.modeset=1 amdgpu.dcdebugmask=0x10 radeon.modeset=1 nvme_load=yes toram plymouth.use-simpledrm=0 quiet splash loglevel=3 noprompt --"
DEBUG_PARAMS="boot=live components username=live autologin cow_spacesize=4G module_blacklist=pcspkr i915.modeset=1 amdgpu.modeset=1 amdgpu.dcdebugmask=0x10 radeon.modeset=1 nvme_load=yes plymouth.ignore-serial-consoles loglevel=7 rd.debug noprompt --"
LEGACY_PARAMS="boot=live components username=live autologin cow_spacesize=4G module_blacklist=nvidia,nvidia_modeset,nvidia_uvm,nvidia_drm nomodeset nvme_load=yes loglevel=3 noprompt --"

resolve_boot_icons() {
    if [ -d "$ROOTFS_TARGET/usr/share/$PROFILE_BOOT_ICONS_PKG_DIR_NAME" ]; then
        echo "$ROOTFS_TARGET/usr/share/$PROFILE_BOOT_ICONS_PKG_DIR_NAME"
        return
    fi
    if [ -d "$ISO_DIR/../PKG/$PROFILE_BOOT_ICONS_PKG_DIR_NAME" ]; then
        echo "$ISO_DIR/../PKG/$PROFILE_BOOT_ICONS_PKG_DIR_NAME"
        return
    fi
    if [ -d "$PROFILE_DIR/boot-icons" ]; then
        echo "$PROFILE_DIR/boot-icons"
        return
    fi
    echo "🌐 Downloading $PROFILE_BOOT_ICONS_PKG_DIR_NAME from $PROFILE_BOOT_ICONS_REMOTE_REPO..." >&2
    $SUDO rm -rf "$BUILD_DIR/pkg-repo-temp" "$BUILD_DIR/$PROFILE_BOOT_ICONS_PKG_DIR_NAME"
    $SUDO git -c http.version=HTTP/1.1 clone --depth=1 "$PROFILE_BOOT_ICONS_REMOTE_REPO" "$BUILD_DIR/pkg-repo-temp" 2>/dev/null || true
    if [ -d "$BUILD_DIR/pkg-repo-temp/$PROFILE_BOOT_ICONS_PKG_DIR_NAME" ]; then
        $SUDO mkdir -p "$BUILD_DIR/$PROFILE_BOOT_ICONS_PKG_DIR_NAME"
        $SUDO cp -rf "$BUILD_DIR/pkg-repo-temp/$PROFILE_BOOT_ICONS_PKG_DIR_NAME"/* "$BUILD_DIR/$PROFILE_BOOT_ICONS_PKG_DIR_NAME/"
    fi
    $SUDO rm -rf "$BUILD_DIR/pkg-repo-temp"
    echo "$BUILD_DIR/$PROFILE_BOOT_ICONS_PKG_DIR_NAME"
}

if [ "$BOOTLOADER" = "grub" ]; then
    # --------------------------------------------------------------------------
    # GRUB BOOTLOADER PACKAGING
    # --------------------------------------------------------------------------
    echo "⚙️ Configuring GRUB for ISO..."
    $SUDO mkdir -p "$ISO_STAGING/boot/grub"
    
    # Copy the custom GRUB theme to the ISO staging directory
    GRUB_THEME_SRC=""
    if [ -d "$ROOTFS_TARGET/boot/grub/themes/$PROFILE_GRUB_THEME_NAME" ]; then
        GRUB_THEME_SRC="$ROOTFS_TARGET/boot/grub/themes/$PROFILE_GRUB_THEME_NAME"
    elif [ -d "$ROOTFS_TARGET/boot/grub/themes/grub-theme" ]; then
        GRUB_THEME_SRC="$ROOTFS_TARGET/boot/grub/themes/grub-theme"
    fi
    if [ -n "$GRUB_THEME_SRC" ]; then
        echo "🎨 Copying $PROFILE_DISPLAY_NAME GRUB theme ($GRUB_THEME_SRC) to the ISO staging..."
        $SUDO mkdir -p "$ISO_STAGING/boot/grub/themes/$PROFILE_GRUB_THEME_NAME"
        $SUDO cp -rf "$GRUB_THEME_SRC"/* "$ISO_STAGING/boot/grub/themes/$PROFILE_GRUB_THEME_NAME/"
    fi
    BOOT_ICONS_DIR="$(resolve_boot_icons)"
    if [ -d "$BOOT_ICONS_DIR/grub" ]; then
        $SUDO mkdir -p "$ISO_STAGING/boot/grub/themes/$PROFILE_GRUB_THEME_NAME/icons"
        $SUDO cp -f "$BOOT_ICONS_DIR/grub"/icons-1080p/*.png "$ISO_STAGING/boot/grub/themes/$PROFILE_GRUB_THEME_NAME/icons/" 2>/dev/null || true
    fi
    
    # Copy the unicode.pf2 font to avoid broken [?] characters in the GRUB menu
    $SUDO mkdir -p "$ISO_STAGING/boot/grub/fonts"
    if [ -f "/usr/share/grub/unicode.pf2" ]; then
        $SUDO cp "/usr/share/grub/unicode.pf2" "$ISO_STAGING/boot/grub/fonts/"
    elif [ -f "$ROOTFS_TARGET/usr/share/grub/unicode.pf2" ]; then
        $SUDO cp "$ROOTFS_TARGET/usr/share/grub/unicode.pf2" "$ISO_STAGING/boot/grub/fonts/"
    fi
    
    # Create GRUB bootloader configuration
    echo "⚙️ Configuring GRUB boot menu..."
    cat <<EOF | $SUDO tee "$ISO_STAGING/boot/grub/grub.cfg" > /dev/null
set default="0"
set timeout=10

insmod all_video
insmod font
insmod gfxterm
insmod png
insmod jpeg
insmod gfxmenu

if loadfont /boot/grub/fonts/unicode.pf2; then
    set gfxmode=auto
    keep_gfxmode=keep
    terminal_output gfxterm
fi

loadfont /boot/grub/themes/$PROFILE_GRUB_THEME_NAME/terminus-12.pf2
loadfont /boot/grub/themes/$PROFILE_GRUB_THEME_NAME/terminus-14.pf2
loadfont /boot/grub/themes/$PROFILE_GRUB_THEME_NAME/terminus-16.pf2
loadfont /boot/grub/themes/$PROFILE_GRUB_THEME_NAME/terminus-18.pf2
loadfont /boot/grub/themes/$PROFILE_GRUB_THEME_NAME/unifont-16.pf2
set theme=/boot/grub/themes/$PROFILE_GRUB_THEME_NAME/theme.txt

menuentry "$PROFILE_DISPLAY_NAME Live (RAM)" --class $PROFILE_SLUG-ram --class gnu-linux --class os {
    linux /live/vmlinuz $RAM_PARAMS
    initrd /live/initrd
}

menuentry "$PROFILE_DISPLAY_NAME Live (Normal)" --class $PROFILE_SLUG --class gnu-linux --class os {
    linux /live/vmlinuz $KERNEL_PARAMS
    initrd /live/initrd
}

menuentry "$PROFILE_DISPLAY_NAME Live (No Plymouth / Debug)" --class $PROFILE_SLUG-debug --class terminal --class gnu-linux {
    linux /live/vmlinuz $DEBUG_PARAMS
    initrd /live/initrd
}

menuentry "$PROFILE_DISPLAY_NAME Live (Legacy Hardware / GPU nomodeset)" --class $PROFILE_SLUG-legacy --class driver --class gnu-linux {
    linux /live/vmlinuz $LEGACY_PARAMS
    initrd /live/initrd
}
EOF

    # Create GRUB loopback configuration for Ventoy compatibility
    echo "⚙️ Creating loopback.cfg for Ventoy..."
    $SUDO mkdir -p "$ISO_STAGING/boot/grub"
    cat <<'EOF' | $SUDO tee "$ISO_STAGING/boot/grub/loopback.cfg" > /dev/null
# Search for the device containing the ISO file
search --no-floppy --set=imgdev --file $isofile
probe -u $imgdev --set=imgdevuuid

set default="0"
set timeout=10

insmod all_video
insmod font
insmod gfxterm
insmod png
insmod jpeg
insmod gfxmenu

if loadfont /boot/grub/fonts/unicode.pf2; then
    set gfxmode=auto
    keep_gfxmode=keep
    terminal_output gfxterm
fi

loadfont /boot/grub/themes/Particle-circle-window/terminus-12.pf2
loadfont /boot/grub/themes/Particle-circle-window/terminus-14.pf2
loadfont /boot/grub/themes/Particle-circle-window/terminus-16.pf2
loadfont /boot/grub/themes/Particle-circle-window/terminus-18.pf2
loadfont /boot/grub/themes/Particle-circle-window/unifont-16.pf2
set theme=/boot/grub/themes/Particle-circle-window/theme.txt

menuentry "Pulsar OS Live (RAM)" {
    linux /live/vmlinuz archisobasedir=live archisolabel=PULSAR_ISO img_dev=UUID=$imgdevuuid img_loop=$isofile cow_spacesize=4G module_blacklist=pcspkr i915.modeset=1 amdgpu.modeset=1 amdgpu.dcdebugmask=0x10 radeon.modeset=1 nvme_load=yes copytoram=y plymouth.use-simpledrm=0 quiet splash loglevel=3 --
    initrd /live/initrd
}

menuentry "Pulsar OS Live (Normal)" {
    linux /live/vmlinuz archisobasedir=live archisolabel=PULSAR_ISO img_dev=UUID=$imgdevuuid img_loop=$isofile cow_spacesize=4G module_blacklist=pcspkr i915.modeset=1 amdgpu.modeset=1 amdgpu.dcdebugmask=0x10 radeon.modeset=1 nvme_load=yes plymouth.use-simpledrm=0 quiet splash loglevel=3 --
    initrd /live/initrd
}

menuentry "Pulsar OS Live (No Plymouth / Debug)" {
    linux /live/vmlinuz archisobasedir=live archisolabel=PULSAR_ISO img_dev=UUID=$imgdevuuid img_loop=$isofile cow_spacesize=4G module_blacklist=pcspkr i915.modeset=1 amdgpu.modeset=1 radeon.modeset=1 nvme_load=yes plymouth.ignore-serial-consoles loglevel=7 rd.debug --
    initrd /live/initrd
}

menuentry "Pulsar OS Live (Legacy Hardware / GPU nomodeset)" {
    linux /live/vmlinuz archisobasedir=live archisolabel=PULSAR_ISO img_dev=UUID=$imgdevuuid img_loop=$isofile cow_spacesize=4G module_blacklist=nvidia,nvidia_modeset,nvidia_uvm,nvidia_drm nomodeset nvme_load=yes loglevel=3 --
    initrd /live/initrd
}
EOF
    # loopback.cfg above is written with a single-quoted heredoc (its $isofile/
    # $imgdevuuid must stay literal for GRUB to expand at boot time), so profile
    # branding is substituted afterwards instead of interpolated at write time.
    $SUDO sed -i \
        -e "s/Pulsar OS Live/$PROFILE_DISPLAY_NAME Live/g" \
        -e "s/Particle-circle-window/$PROFILE_GRUB_THEME_NAME/g" \
        -e "s/PULSAR_ISO/$PROFILE_ISO_LABEL/g" \
        "$ISO_STAGING/boot/grub/loopback.cfg"

    VER_SUFFIX=""
    if [ -n "$PULSAR_VERSION" ]; then
        VER_SUFFIX="-${PULSAR_VERSION}"
    fi

    if $WITH_NVIDIA; then
        ISO_OUTPUT="$BUILD_DIR/${PROFILE_ISO_PREFIX}-${BRANCH}${VER_SUFFIX}-nvidia.iso"
    else
        ISO_OUTPUT="$BUILD_DIR/${PROFILE_ISO_PREFIX}-${BRANCH}${VER_SUFFIX}.iso"
    fi
    # Create a temporary xorriso wrapper to force -iso-level 3
    # which allows files larger than 4GB (ISO 9660 Level 3 multi-extents)
    # We also set the volume label to $PROFILE_ISO_LABEL so the archiso hook can locate it,
    # and strip out Apple/HFS+/APM arguments to prevent label collision on physical USB drives.
    WRAPPER_PATH="/tmp/xorriso-wrapper"
    cat <<'EOF' > "$WRAPPER_PATH"
#!/bin/bash
args=()
i=1
while [ $i -le $# ]; do
    arg="${!i}"
    case "$arg" in
        -hfsplus)
            # Skip this argument
            ;;
        -apm-block-size)
            # Skip this and the next argument (the size)
            i=$((i + 1))
            ;;
        -hfsplus-file-creator-type)
            # Skip this and the next three arguments
            i=$((i + 3))
            ;;
        -hfs-bless-by)
            # Skip this and the next two arguments
            i=$((i + 2))
            ;;
        -hfsplus-serial-number)
            # Skip this and the next argument
            i=$((i + 1))
            ;;
        *)
            args+=("$arg")
            ;;
    esac
    i=$((i + 1))
done

exec xorriso "${args[@]}" -iso-level 3 -volid PULSAR_ISO
EOF
    # Wrapper above is a single-quoted heredoc so the bash it writes to disk
    # keeps its own $var syntax literal; patch in the profile's volume label after.
    sed -i "s/PULSAR_ISO/$PROFILE_ISO_LABEL/" "$WRAPPER_PATH"
    chmod +x "$WRAPPER_PATH"

    echo "💿 Generating GRUB ISO file at: $ISO_OUTPUT..."
    $SUDO grub-mkrescue --xorriso="$WRAPPER_PATH" -o "$ISO_OUTPUT" "$ISO_STAGING"
    rm -f "$WRAPPER_PATH"

else
    # --------------------------------------------------------------------------
    # rEFInd BOOTLOADER PACKAGING
    # --------------------------------------------------------------------------
    echo "💿 Creating bootable EFI image with rEFInd..."
    $SUDO mkdir -p "$ISO_STAGING/boot"
    $SUDO mkdir -p "$ISO_STAGING/EFI/BOOT"
    EFI_IMG="$ISO_STAGING/boot/efi.img"

    # Create a 350MB empty file and format it as FAT16 (eliminates FAT32 cluster warnings and has space for kernel/initrd)
    $SUDO dd if=/dev/zero of="$EFI_IMG" bs=1M count=350 2>/dev/null
    $SUDO mkfs.vfat -F 16 "$EFI_IMG" >/dev/null

    # Create temporary refind.conf for the ISO boot (full config with theme — goes inside efi.img)
    cat <<EOF > "$BUILD_DIR/refind.conf"
timeout 10
enable_mouse
mouse_speed 4
mouse_size 16
resolution max
default_selection "+,$PROFILE_SLUG,$PROFILE_DISPLAY_NAME Live (RAM)"
#showtools about,reboot,shutdown,firmware,hidden_tags
include themes/$PROFILE_REFIND_THEME_NAME/theme.conf

menuentry "$PROFILE_DISPLAY_NAME Live (RAM)" {
    icon /EFI/BOOT/themes/$PROFILE_REFIND_THEME_NAME/icons/os_${PROFILE_SLUG}_toram.png
    loader /EFI/BOOT/vmlinuz
    initrd /EFI/BOOT/initrd
    options "$RAM_PARAMS"
}

menuentry "$PROFILE_DISPLAY_NAME Live (Normal)" {
    icon /EFI/BOOT/themes/$PROFILE_REFIND_THEME_NAME/icons/os_${PROFILE_SLUG}_normal.png
    loader /EFI/BOOT/vmlinuz
    initrd /EFI/BOOT/initrd
    options "$KERNEL_PARAMS"
}

menuentry "$PROFILE_DISPLAY_NAME Live (No Plymouth / Debug)" {
    icon /EFI/BOOT/themes/$PROFILE_REFIND_THEME_NAME/icons/os_${PROFILE_SLUG}_debug.png
    loader /EFI/BOOT/vmlinuz
    initrd /EFI/BOOT/initrd
    options "$DEBUG_PARAMS"
}

menuentry "$PROFILE_DISPLAY_NAME Live (Legacy Hardware / GPU nomodeset)" {
    icon /EFI/BOOT/themes/$PROFILE_REFIND_THEME_NAME/icons/os_${PROFILE_SLUG}_old.png
    loader /EFI/BOOT/vmlinuz
    initrd /EFI/BOOT/initrd
    options "$LEGACY_PARAMS"
}
EOF

    # Minimal refind.conf for the ISO root (no showtools, no theme — avoids duplicate tool buttons
    # when rEFInd scans both ISO9660 and FAT efi.img filesystems)
    cat <<EOF > "$BUILD_DIR/refind-minimal.conf"
timeout 10
resolution max
default_selection "+,$PROFILE_SLUG,$PROFILE_DISPLAY_NAME Live (RAM)"

menuentry "$PROFILE_DISPLAY_NAME Live (RAM)" {
    loader /EFI/BOOT/vmlinuz
    initrd /EFI/BOOT/initrd
    options "$RAM_PARAMS"
}

menuentry "$PROFILE_DISPLAY_NAME Live (Normal)" {
    loader /EFI/BOOT/vmlinuz
    initrd /EFI/BOOT/initrd
    options "$KERNEL_PARAMS"
}

menuentry "$PROFILE_DISPLAY_NAME Live (No Plymouth / Debug)" {
    loader /EFI/BOOT/vmlinuz
    initrd /EFI/BOOT/initrd
    options "$DEBUG_PARAMS"
}

menuentry "$PROFILE_DISPLAY_NAME Live (Legacy Hardware / GPU nomodeset)" {
    loader /EFI/BOOT/vmlinuz
    initrd /EFI/BOOT/initrd
    options "$LEGACY_PARAMS"
}
EOF

    # Get the theme (copy from installed rootfs package, local source, or GitHub fallback)
    echo "🎨 Fetching rEFInd macOS theme..."
    $SUDO rm -rf "$BUILD_DIR/refind-mac-theme"
    if [ -d "$ROOTFS_TARGET/usr/share/refind/themes/$PROFILE_REFIND_THEME_NAME" ]; then
        echo "📂 Copying rEFInd theme from the $PROFILE_SLUG-refind package installed in rootfs..."
        $SUDO cp -r "$ROOTFS_TARGET/usr/share/refind/themes/$PROFILE_REFIND_THEME_NAME" "$BUILD_DIR/refind-mac-theme"
    elif [ -d "$ISO_DIR/../refind" ]; then
        echo "📂 Copying local theme from: $ISO_DIR/../refind"
        $SUDO cp -r "$ISO_DIR/../refind" "$BUILD_DIR/refind-mac-theme"
        $SUDO rm -rf "$BUILD_DIR/refind-mac-theme/.git"
    else
        echo "🌐 Downloading theme from GitHub..."
        $SUDO git -c http.version=HTTP/1.1 -c http.postBuffer=524288000 -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 clone --depth=1 "$PROFILE_REFIND_THEME_REPO" "$BUILD_DIR/refind-mac-theme"
    fi
    $SUDO sed -i '/#MENUENTRIES/q' "$BUILD_DIR/refind-mac-theme/theme.conf"
    BOOT_ICONS_DIR="$(resolve_boot_icons)"
    if [ -d "$BOOT_ICONS_DIR" ]; then
        echo "📦 Ensuring custom live boot icons in the rEFInd ISO..."
        $SUDO cp -f "$BOOT_ICONS_DIR/toram.png" "$BUILD_DIR/refind-mac-theme/icons/os_${PROFILE_SLUG}_toram.png" 2>/dev/null || true
        $SUDO cp -f "$BOOT_ICONS_DIR/normal.png" "$BUILD_DIR/refind-mac-theme/icons/os_${PROFILE_SLUG}_normal.png" 2>/dev/null || true
        $SUDO cp -f "$BOOT_ICONS_DIR/debug-noplymouth.png" "$BUILD_DIR/refind-mac-theme/icons/os_${PROFILE_SLUG}_debug.png" 2>/dev/null || true
        $SUDO cp -f "$BOOT_ICONS_DIR/old.png" "$BUILD_DIR/refind-mac-theme/icons/os_${PROFILE_SLUG}_old.png" 2>/dev/null || true
    fi

    # Determine the location of rEFInd files in the chroot (the Debian package nests them under /usr/share/refind/refind)
    REFIND_SHARE_DIR="$ROOTFS_TARGET/usr/share/refind"
    if [ -d "$ROOTFS_TARGET/usr/share/refind/refind" ]; then
        REFIND_SHARE_DIR="$ROOTFS_TARGET/usr/share/refind/refind"
    fi

    # 1. Populate the ISO root /EFI/BOOT folder for direct UEFI boot (resolves QEMU boot problems)
    # NOTE: refind.conf, icons and theme go ONLY inside efi.img to avoid rEFInd
    # processing showtools from two filesystems and duplicating tool buttons.
    # Only the bootloader, driver, kernel and initrd go in the ISO root.
    echo "📂 Copying rEFInd, kernel and initrd files to the ISO staging root..."
    $SUDO cp "$REFIND_SHARE_DIR/refind_x64.efi" "$ISO_STAGING/EFI/BOOT/bootx64.efi"
    $SUDO mkdir -p "$ISO_STAGING/EFI/BOOT/drivers_x64"
    $SUDO cp "$REFIND_SHARE_DIR/drivers_x64/"*iso9660*.efi "$ISO_STAGING/EFI/BOOT/drivers_x64/" 2>/dev/null || true
    $SUDO cp "$BUILD_DIR/refind-minimal.conf" "$ISO_STAGING/EFI/BOOT/refind.conf"
    # Copy kernel and initrd directly to the UEFI boot folder on the ISO
    $SUDO cp "$ISO_STAGING/live/vmlinuz" "$ISO_STAGING/EFI/BOOT/vmlinuz"
    $SUDO cp "$ISO_STAGING/live/initrd" "$ISO_STAGING/EFI/BOOT/initrd"

    # 2. Populate the efi.img for El Torito boot using mtools (resolves cluster size warnings)
    echo "📥 Copying files to efi.img using mtools..."
    $SUDO mmd -i "$EFI_IMG" ::/EFI
    $SUDO mmd -i "$EFI_IMG" ::/EFI/BOOT
    $SUDO mmd -i "$EFI_IMG" ::/EFI/BOOT/drivers_x64
    $SUDO mmd -i "$EFI_IMG" ::/EFI/BOOT/themes
    $SUDO mmd -i "$EFI_IMG" ::/EFI/BOOT/icons

    $SUDO mcopy -i "$EFI_IMG" "$REFIND_SHARE_DIR/refind_x64.efi" ::/EFI/BOOT/bootx64.efi
    $SUDO mcopy -i "$EFI_IMG" "$REFIND_SHARE_DIR/drivers_x64/"*iso9660*.efi ::/EFI/BOOT/drivers_x64/ 2>/dev/null || true
    $SUDO mcopy -i "$EFI_IMG" "$BUILD_DIR/refind.conf" ::/EFI/BOOT/refind.conf
    $SUDO mcopy -s -i "$EFI_IMG" "$REFIND_SHARE_DIR/icons"/* ::/EFI/BOOT/icons/
    $SUDO mmd -i "$EFI_IMG" ::/EFI/BOOT/themes/$PROFILE_REFIND_THEME_NAME
    $SUDO mcopy -s -i "$EFI_IMG" "$BUILD_DIR/refind-mac-theme"/* ::/EFI/BOOT/themes/$PROFILE_REFIND_THEME_NAME/
    # Copy kernel and initrd directly to the efi.img FAT volume using mtools
    $SUDO mcopy -i "$EFI_IMG" "$ISO_STAGING/live/vmlinuz" ::/EFI/BOOT/vmlinuz
    $SUDO mcopy -i "$EFI_IMG" "$ISO_STAGING/live/initrd" ::/EFI/BOOT/initrd

    # Cleanup temp build files
    $SUDO rm -f "$BUILD_DIR/refind.conf"
    $SUDO rm -f "$BUILD_DIR/refind-minimal.conf"
    $SUDO rm -rf "$BUILD_DIR/refind-mac-theme"

    # Copy the custom GRUB theme to the ISO staging directory for Ventoy compatibility
    GRUB_THEME_SRC=""
    if [ -d "$ROOTFS_TARGET/boot/grub/themes/$PROFILE_GRUB_THEME_NAME" ]; then
        GRUB_THEME_SRC="$ROOTFS_TARGET/boot/grub/themes/$PROFILE_GRUB_THEME_NAME"
    elif [ -d "$ROOTFS_TARGET/boot/grub/themes/grub-theme" ]; then
        GRUB_THEME_SRC="$ROOTFS_TARGET/boot/grub/themes/grub-theme"
    fi
    if [ -n "$GRUB_THEME_SRC" ]; then
        $SUDO mkdir -p "$ISO_STAGING/boot/grub/themes/$PROFILE_GRUB_THEME_NAME"
        $SUDO cp -rf "$GRUB_THEME_SRC"/* "$ISO_STAGING/boot/grub/themes/$PROFILE_GRUB_THEME_NAME/"
        if [ -d "$BOOT_ICONS_DIR/grub" ]; then
            $SUDO mkdir -p "$ISO_STAGING/boot/grub/themes/$PROFILE_GRUB_THEME_NAME/icons"
            $SUDO cp -f "$BOOT_ICONS_DIR/grub"/icons-1080p/*.png "$ISO_STAGING/boot/grub/themes/$PROFILE_GRUB_THEME_NAME/icons/" 2>/dev/null || true
        fi
    fi
    # Copy unicode.pf2 for Ventoy's GRUB menus
    $SUDO mkdir -p "$ISO_STAGING/boot/grub/fonts"
    if [ -f "/usr/share/grub/unicode.pf2" ]; then
        $SUDO cp "/usr/share/grub/unicode.pf2" "$ISO_STAGING/boot/grub/fonts/"
    elif [ -f "$ROOTFS_TARGET/usr/share/grub/unicode.pf2" ]; then
        $SUDO cp "$ROOTFS_TARGET/usr/share/grub/unicode.pf2" "$ISO_STAGING/boot/grub/fonts/"
    fi

    # Create GRUB loopback configuration for Ventoy compatibility
    echo "⚙️ Creating loopback.cfg for Ventoy..."
    $SUDO mkdir -p "$ISO_STAGING/boot/grub"
    cat <<'EOF' | $SUDO tee "$ISO_STAGING/boot/grub/loopback.cfg" > /dev/null
# Search for the device containing the ISO file
search --no-floppy --set=imgdev --file $isofile
probe -u $imgdev --set=imgdevuuid

set default="0"
set timeout=10

insmod all_video
insmod font
insmod gfxterm
insmod png
insmod jpeg
insmod gfxmenu

if loadfont /boot/grub/fonts/unicode.pf2; then
    set gfxmode=auto
    keep_gfxmode=keep
    terminal_output gfxterm
fi

loadfont /boot/grub/themes/Particle-circle-window/terminus-12.pf2
loadfont /boot/grub/themes/Particle-circle-window/terminus-14.pf2
loadfont /boot/grub/themes/Particle-circle-window/terminus-16.pf2
loadfont /boot/grub/themes/Particle-circle-window/terminus-18.pf2
loadfont /boot/grub/themes/Particle-circle-window/unifont-16.pf2
set theme=/boot/grub/themes/Particle-circle-window/theme.txt

menuentry "Pulsar OS Live (RAM)" {
    linux /live/vmlinuz archisobasedir=live archisolabel=PULSAR_ISO img_dev=UUID=$imgdevuuid img_loop=$isofile cow_spacesize=4G module_blacklist=pcspkr i915.modeset=1 amdgpu.modeset=1 amdgpu.dcdebugmask=0x10 radeon.modeset=1 nvme_load=yes copytoram=y plymouth.use-simpledrm=0 quiet splash loglevel=3 --
    initrd /live/initrd
}

menuentry "Pulsar OS Live (Normal)" {
    linux /live/vmlinuz archisobasedir=live archisolabel=PULSAR_ISO img_dev=UUID=$imgdevuuid img_loop=$isofile cow_spacesize=4G module_blacklist=pcspkr i915.modeset=1 amdgpu.modeset=1 amdgpu.dcdebugmask=0x10 radeon.modeset=1 nvme_load=yes plymouth.use-simpledrm=0 quiet splash loglevel=3 --
    initrd /live/initrd
}

menuentry "Pulsar OS Live (No Plymouth / Debug)" {
    linux /live/vmlinuz archisobasedir=live archisolabel=PULSAR_ISO img_dev=UUID=$imgdevuuid img_loop=$isofile cow_spacesize=4G module_blacklist=pcspkr i915.modeset=1 amdgpu.modeset=1 radeon.modeset=1 nvme_load=yes plymouth.ignore-serial-consoles loglevel=7 rd.debug --
    initrd /live/initrd
}

menuentry "Pulsar OS Live (Legacy Hardware / GPU nomodeset)" {
    linux /live/vmlinuz archisobasedir=live archisolabel=PULSAR_ISO img_dev=UUID=$imgdevuuid img_loop=$isofile cow_spacesize=4G module_blacklist=nvidia,nvidia_modeset,nvidia_uvm,nvidia_drm nomodeset nvme_load=yes loglevel=3 --
    initrd /live/initrd
}
EOF
    # loopback.cfg above is written with a single-quoted heredoc (its $isofile/
    # $imgdevuuid must stay literal for GRUB to expand at boot time), so profile
    # branding is substituted afterwards instead of interpolated at write time.
    $SUDO sed -i \
        -e "s/Pulsar OS Live/$PROFILE_DISPLAY_NAME Live/g" \
        -e "s/Particle-circle-window/$PROFILE_GRUB_THEME_NAME/g" \
        -e "s/PULSAR_ISO/$PROFILE_ISO_LABEL/g" \
        "$ISO_STAGING/boot/grub/loopback.cfg"

    VER_SUFFIX=""
    if [ -n "$PULSAR_VERSION" ]; then
        VER_SUFFIX="-${PULSAR_VERSION}"
    fi

    if $WITH_NVIDIA; then
        ISO_OUTPUT="$BUILD_DIR/${PROFILE_ISO_PREFIX}-${BRANCH}-refind${VER_SUFFIX}-nvidia.iso"
    else
        ISO_OUTPUT="$BUILD_DIR/${PROFILE_ISO_PREFIX}-${BRANCH}-refind${VER_SUFFIX}.iso"
    fi
    echo "💿 Generating rEFInd ISO file at: $ISO_OUTPUT..."
    # Add a hybrid MBR so the ISO is a valid disk image: balenaEtcher requires it
    # and direct USB flashing (dd) needs it for UEFI to find the GPT ESP partition.
    # grub-mkrescue uses boot_hybrid.img; fall back to the syslinux isohdpfx.bin.
    HYBRID_MBR=""
    for mbr in \
        "/usr/lib/grub/i386-pc/boot_hybrid.img" \
        "/usr/lib/ISOLINUX/isohdpfx.bin" \
        "/usr/lib/syslinux/mbr/isohdpfx.bin"; do
        if [ -f "$mbr" ]; then
            HYBRID_MBR="$mbr"
            break
        fi
    done
    if [ -z "$HYBRID_MBR" ]; then
        echo "❌ Error: No hybrid MBR template found (GRUB's boot_hybrid.img or syslinux's isohdpfx.bin). Install 'grub' or 'syslinux' on the host."
        exit 1
    fi
    $SUDO xorriso -as mkisofs \
      -o "$ISO_OUTPUT" \
      -J -R -V "$PROFILE_ISO_LABEL" \
      -isohybrid-mbr "$HYBRID_MBR" \
      -eltorito-alt-boot \
      -e "boot/efi.img" \
      -no-emul-boot \
      -isohybrid-gpt-basdat \
      "$ISO_STAGING"
fi

echo "=============================================================================="
echo "🎉 $PROFILE_DISPLAY_NAME ISO ($BOOTLOADER) generated successfully!"
echo "📍 Location: $ISO_OUTPUT"
echo "=============================================================================="
