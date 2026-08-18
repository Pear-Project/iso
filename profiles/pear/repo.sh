# ==============================================================================
# Pear profile — repository setup (sourced by build-iso.sh)
# ==============================================================================
# Defines profile_setup_repo() / profile_teardown_repo(), called by the engine
# right before / after the package-install step of Phase 5. Both run in the
# engine's own shell (sourced, not exec'd) so they see $ROOTFS_TARGET,
# $CHROOT_BIN, $SUDO, $BRANCH, $DEBIAN_VERSION and $PROFILE_DIR directly.
#
# Repo: https://apt.pearos.xyz/<x86_64|aarch64>/<channel>/<release>/ (flat,
# one suite per directory). Mirrors ~/Desktop/importer/pearos-apt-setup.sh --
# see that repo's README.md for the channel/release matrix. This profile
# always uses amd64 (x86_64) / main / latest.
# ==============================================================================

PROFILE_APT_CHANNEL="main"
PROFILE_APT_RELEASE="latest"
PROFILE_APT_URL="https://apt.pearos.xyz/x86_64/$PROFILE_APT_CHANNEL/$PROFILE_APT_RELEASE"

profile_setup_repo() {
    echo "--- 🌐 Configuring APT repositories (Debian Contrib/Backports and pearOS) ---"
    $SUDO sed -i "s/$DEBIAN_VERSION main/$DEBIAN_VERSION main contrib non-free non-free-firmware/g" "$ROOTFS_TARGET/etc/apt/sources.list"
    # backports only exists as a suite for the current stable release (trixie)
    # -- testing/unstable (forky/rolling) have no "-backports" suite at all.
    if [ "$DEBIAN_VERSION" = "trixie" ] && ! grep -q "${DEBIAN_VERSION}-backports" "$ROOTFS_TARGET/etc/apt/sources.list"; then
        echo "deb http://deb.debian.org/debian ${DEBIAN_VERSION}-backports main contrib non-free non-free-firmware" | $SUDO tee -a "$ROOTFS_TARGET/etc/apt/sources.list" > /dev/null
    fi

    # Import the pearOS signing key (fingerprint 0AB2 738C EF7E DC6B 7B45
    # 178D 4C1A 9F3C 131A CA95) straight into the chroot -- same key
    # pearos-apt-setup.sh imports on an already-installed system.
    echo "🔑 Importing the pearOS APT signing key..."
    $SUDO mkdir -p "$ROOTFS_TARGET/etc/apt/keyrings"
    $SUDO tee "$ROOTFS_TARGET/tmp/pearos-archive-key.asc" > /dev/null <<'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGnEdXgBEACyKNbc2suS8/28WFyJdO6EaN5IeljaHliMrd49ivDfw82KvWMf
l7Edey7IzSPOPAy4L6lm7TEPrcLI5yQfaMBpWg0C56UOmtukSgbgMlpOgni3ni1n
BXhS0RAPNfs/jxVNPxPKVoDM82PrsxcXctWP23Zo79xD8wMtz1i3miPkAgBli0+u
W5t2pW9DV/XNqGOc8Pl/0e+FaSFtopar2znNHjhsK4DTU3rFVaPNAx2kTGVS6bA1
A3p/07q5y3uwTnHMMWQjD4zyb2MZ8pWHXWupGMdQTfAzST6iXImVxwNTZB0K7bMd
2qpvIT35REaILDGXvwNoNdwYzTYPgrT9yHeLV7KbubIggSc1Bc4bmP57fO1nIuXL
a9Tel5ysFuivexM0ERMSSrpDeUs2RPYeAjbf3Ip4PEymXiK/DNorMBR7jqm9d+fS
NkRLbu2vxDjx5iY+vEtlkIoKvvB+tEjJXQzCMmQsVwmw1pUARK5HSo0Udxr6Lzco
DsYELpUt1KFwlMPKeaLcWzw61j/ATIYeNegF1zA9BtnkiAGBZuNao7f3JmnPD6w8
ZDJxkYl2xRUjmXnX8aC+84TPjSxQyAef1f62hxljKd2jfNmdDpCcnRvykJmvbm2p
dVRh64xYWTnGM7fidCeHjO3No6f4FKM8DbfKGpR1W0rN8eL8QwpT/mIBVwARAQAB
tFRBbGV4YW5kcnUgQmFsYW4gKFByaXZhdGUga2V5IGZvciBwZWFyT1MgYnkgQWxl
eGFuZHJ1IEJhbGFuKSA8YWxleEBwZWFyLXNvZnR3YXJlLmNvbT6JAk4EEwEKADgW
IQQKsnOM737ca3tFF41MGp88ExrKlQUCacR1eAIbAwULCQgHAgYVCgkICwIEFgID
AQIeAQIXgAAKCRBMGp88ExrKlWMlD/9U/ljfd3mGycQfDqVbfzLeN7BQezx8ihC1
ez32d3faHZnaZDC3GZ8k5wqSy9mODipBreS++tDhGCguOWoWRK3QAhljA+9o+Pa2
0Q+dwaiAHoKeuzGHaZPpJOck0H6OTA1+4xcWBLElF2MAY3ew3xz6aovuGNS/0KPJ
A5rqrLtGLD7xi4GRp+bCiG0R/aitx0SzqvYGzg09+6T7abmvZHLFNHVeyWTq17Gn
iLaFnXBhAsypOni/pSj3xTevRQtahIUYBgXsYgQpmoF4MvYi0sXrrrDvnjtqoQF8
l3YqkF11lLDJxITLKRs3oCBAZCfXiklkEtyWmw3VvOBp0s3TLspa6DSL6vVGKYgg
t2iRxebhFg+5FE4khFg9JftR3y5KuCZ+PuP9NAdizMnDoUkIefFZuWery/y18TSa
sEDpal9WqatMj/ssOv47aGN68wYh5G6/7E+Uz3OdKGEfnGt4iQ+cCcociJuPzf4Y
apT6om5RyKFWqmSaLJfXQOQ64YLaUcZ8xA6z95l5u2aUgP3/gR9BbOIZMXAzuBBP
WFZnrvxYs0nJaIs7xhgZj/mSG2/nyPi4EdMTG5cBOxHl+6yWoLNA1xdqOpXwIj1l
jwN/O4T2N/NL3c1cMj2IIe9arG5MWg5z+pGSSKQ1NL9MPMHeOlKTJgefL/Wj+WLh
GnbMEYCUlbkCDQRpxHV4ARAA3ExY7AXPPWNxAD8WP4GZIBrz07uvXGQysDyy9tKA
l6oRSxZHMZvwyXmdikI/k/30pvTvIfCiUVnTp/Ed285JIE0SU0qW1UjrYDixdjgk
dpYpgzE3IZUpX129aDH1VZlvxPTQtYCH0PjjGRf5kilegUOPFWkxHYFpJdqofEqR
5BsQfKTOiP77t2fP5Gn/bUTlyVA1vltP0LgLGuw20U6UbmrzalWq9TiaUNHBRoed
zmC+hC2G8fsNqUqMwvI3uZApHi1s2CYBkl6Cu+gy7CL05ggA37xyLhtNRgauD/DD
6E3EjXM2mOd9Cg6cCDYqsGH1/ZYY+5oXNgyBdADSpFntpFLneFVx/u80Fo99N/lJ
sjjJTwYVnKxLRV2tGBU8WvfzAIiKUiFWJvtbmhIVAiSXKTqX1VoJhUFexinQPgm/
bqoEGaCptDLHpV4PI9nctqBuM3zMvYHeYttgBmUO+YheIoQcPQGIHPXfNebUFzq5
OrD/UiDnEttmAoY+3me2FBXbeqNUXOiXcWcJ043EAT2mIrC9DL8qImM+2S4WWVVv
YbmGicnge4xq3A2yI8MIhzQ1Mz/dx/n3lmOXgEv6iv68GoY8LRIOm0esqGVOjvfQ
QfJ41dcuhBZK9l40oU6iCvMP6VpXESPG6KVcGcGCci27dKa/V0gfJ8wKw2QY6l7D
7D0AEQEAAYkCNgQYAQoAIBYhBAqyc4zvftxre0UXjUwanzwTGsqVBQJpxHV4AhsM
AAoJEEwanzwTGsqVC/UP+wVD8a72E4ywmtsoo7ODLbF1jGYVrD3zKNzgW55JX1Qv
BGdEHnGsGebxSCmX4NifBX5xxeTbFm5OMNRQqT7Erm6fMQ20JCEVdYLxiJQ1g+z5
eq5mxGAWpw+7LG7q8xKE0kvm7n/d5S03VwCWjcz3AWEnXntAfzqAjefRQwuC+hHN
hs7PwS9zqProb4bNoJ6JFEhW/c6HwTfABGbBAmA7TXtSECZB0tN+p8TtTkLgCkKw
mx/hufyAgyvzl+aEdTUV20HVdqOdul37x0Zt1n+cjAJSpAIDL2c+ECMLe6wn5N6A
ejf6mtPkq/f1j203ozR4ycyH35Jg0Jv6uza8q+DIre6KMv1jAn5/8wIHhK69jOtr
ZIAOxeIBXvoSPGMBMLW4pxF1tXzBxkws4UHVszlGg8FessZK2yq223lzNgP0JL09
7v2lDp/RcXCWWnhnGua+cGGWCoqjZE52mwVTsOwf8AuXDsJi3VB6jMOUkD/ErUMx
l68y4POx8JlTTZMVqXofdMKL0Uq0g0ZpievsyBkLnu4UPRnBZFOJHcx2BcK1uTDr
B3wNzkdsd6OrVowMjBdxPJkOQsaSbpLMW87eUCQQ3p1xJtV+PjhWDLPcjHUR053O
Wv6hbKKe/Cf21HoPu5UA86BkFv6bho6rQiwjhKZHgx2iaiBMKstNp4S6I4D6gHwK
=95MG
-----END PGP PUBLIC KEY BLOCK-----
EOF
    $SUDO "$CHROOT_BIN" "$ROOTFS_TARGET" /bin/bash -c "
        gpg --dearmor -o /etc/apt/keyrings/pearos-archive-keyring.gpg /tmp/pearos-archive-key.asc
        chmod 644 /etc/apt/keyrings/pearos-archive-keyring.gpg
        rm -f /tmp/pearos-archive-key.asc
    "

    echo "deb [signed-by=/etc/apt/keyrings/pearos-archive-keyring.gpg] $PROFILE_APT_URL ./" | \
        $SUDO tee "$ROOTFS_TARGET/etc/apt/sources.list.d/pearos.list" > /dev/null

    # The custom pearOS kernel itself isn't apt-installable -- it's too big
    # for apt.pearos.xyz's GitHub Pages hosting, so it ships as the latest
    # GitHub Release asset of Pear-Project/debian-package-repo instead.
    # Installed here (before Phase 5's PROFILE_REPO_PACKAGES apt-get install,
    # which includes a linux-headers-*-pearos entry) so /lib/modules/<ver>/
    # already exists when the headers package's dkms hook rebuilds
    # nvidia-driver/broadcom-sta-dkms/virtualbox-guest-utils against it.
    echo "🐧 Fetching latest pearOS kernel release..."
    KERNEL_DEB_URL=$(curl -fsSL "https://api.github.com/repos/Pear-Project/debian-package-repo/releases/latest" \
        | jq -r '.assets[] | select(.name | test("^linux-image-.*\\.deb$")) | .browser_download_url' | head -n 1)
    if [ -z "$KERNEL_DEB_URL" ]; then
        echo "❌ Error: no linux-image-*.deb asset found in the latest Pear-Project/debian-package-repo release."
        exit 1
    fi
    KERNEL_DEB_NAME="$(basename "$KERNEL_DEB_URL")"

    # Derive the running kernel's version-pearos suffix from the asset name
    # itself (e.g. "linux-image-6.18.42-pearos_6.18.42-14_amd64.deb" ->
    # "6.18.42-pearos") instead of hardcoding it, so PROFILE_REPO_PACKAGES'
    # linux-headers-*-pearos entry (set in packages.sh) always matches
    # whatever kernel cachy-kernel-watch.yaml most recently published --
    # currently the LTS branch, but this stays correct if that ever changes.
    PEAROS_KERNEL_VERSION="${KERNEL_DEB_NAME#linux-image-}"
    PEAROS_KERNEL_VERSION="${PEAROS_KERNEL_VERSION%%_*}"
    PROFILE_REPO_PACKAGES=("${PROFILE_REPO_PACKAGES[@]/#linux-headers-*-pearos/linux-headers-$PEAROS_KERNEL_VERSION}")
    echo "🐧 Kernel version: $PEAROS_KERNEL_VERSION (headers package: linux-headers-$PEAROS_KERNEL_VERSION)"

    KERNEL_CACHE_DIR="$BUILD_DIR/kernel-cache"
    mkdir -p "$KERNEL_CACHE_DIR"
    if [ ! -f "$KERNEL_CACHE_DIR/$KERNEL_DEB_NAME" ]; then
        echo "📥 Downloading $KERNEL_DEB_NAME..."
        curl -fL -o "$KERNEL_CACHE_DIR/$KERNEL_DEB_NAME.part" "$KERNEL_DEB_URL"
        mv "$KERNEL_CACHE_DIR/$KERNEL_DEB_NAME.part" "$KERNEL_CACHE_DIR/$KERNEL_DEB_NAME"
    else
        echo "📦 Using cached $KERNEL_DEB_NAME (delete $KERNEL_CACHE_DIR to force a re-download)"
    fi

    $SUDO mkdir -p "$ROOTFS_TARGET/tmp/packages"
    $SUDO cp "$KERNEL_CACHE_DIR/$KERNEL_DEB_NAME" "$ROOTFS_TARGET/tmp/packages/"
    echo "📦 Installing $KERNEL_DEB_NAME..."
    $SUDO "$CHROOT_BIN" "$ROOTFS_TARGET" /bin/bash -c "
        set -e
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y /tmp/packages/$KERNEL_DEB_NAME
    "
    $SUDO rm -rf "$ROOTFS_TARGET/tmp/packages"
}

profile_teardown_repo() {
    :
}
