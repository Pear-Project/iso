<div align='center'>
<p align="center">
  <img width="300" height="300" src="https://github.com/user-attachments/assets/c6bec808-b8b5-42a6-a459-e05656e47c3c" />
  </p>
<img src='https://img.shields.io/github/v/release/pearOS-archlinux/iso?color=%23FDD835&label=version&style=for-the-badge'>

</a>
<img src='https://img.shields.io/github/license/pearOS-archlinux/iso?style=for-the-badge'>
<a href="https://hits.sh/github.com/pearOS-archlinux/iso/"><img alt="Hits" src="https://hits.sh/github.com/pearOS-archlinux/iso.svg?style=for-the-badge&label=Repo%20Views&color=8411cc"/></a></a>

  <p><a href="https://discord.gg/QJPetvVhUb"><img alt="Discord" src="https://discordapp.com/api/guilds/697456171631509515/widget.png?style=banner2"?link=https://discord.gg/yp4xpZeAgW&link=https://discord.gg/yp4xpZeAgW> </a></p>
  
</div>

<br />

---


# pearOS-debian-base 📌
It is pearOS, but with Debian Base. Yes! It uses vanilla debian, less bugs, easier, better etc.

## Why? 📌
A Debian base means the vast APT package ecosystem, a more conservative/stable release cadence, and broader out-of-the-box hardware support than a rolling-release base — while keeping the same pearOS look, feel and app set.

## Ok... How do I build it? 📌
`build-iso.sh` is a generic Debian live-ISO engine: package list, extra APT repo, package selection, branding and boot menu/theme names all come from a **profile** under `profiles/<name>/`, not from the script itself.

```sh
sudo ./build-iso.sh
```

**Note:** The build script must be run as root since it needs to create chroot environments and install packages — if not already root, it re-executes itself via `pkexec` (or `sudo` as a fallback).

It accepts the following flags:
- `--profile <name>` Distro profile to build, from `profiles/<name>/`. Default: `pear` (Pulsar OS).
- `--branch stable`, replacing stable with any other Debian branch; currently only stable can be used.
- `--local` to package from the packages in the `/PKG` folder, which must be in the same folder that contains the `/ISO` folder
- `--refind` Build the rEFInd version (must be in the profile's supported-bootloader list)
- `--grub` Build the GRUB version (must be in the profile's supported-bootloader list)
- `--nvidia` Build ISO image with privative drivers (BROADCOM, NVIDIA, etc...)

If neither `--grub` nor `--refind` is passed, the profile's own default bootloader (`PROFILE_DEFAULT_BOOTLOADER`) is used.

### Dependencies: 📌

#### Building from an Arch Linux / CachyOS / Manjaro host
```sh
sudo pacman -S --needed \
  squashfs-tools grub xorriso mtools dosfstools \
  binutils libisoburn sassc imagemagick psmisc \
  fakeroot rsync jq curl unzip wget git
```
You'll also need `mmdebstrap` from the AUR (e.g. `yay -S mmdebstrap`), since it bootstraps the Debian chroot regardless of the host distro.

#### Building from a Debian / Ubuntu / Pop!_OS host
```sh
sudo apt-get install -y \
  mmdebstrap squashfs-tools grub-common grub-efi-amd64-bin grub-pc-bin \
  xorriso mtools dosfstools binutils unzip sassc imagemagick psmisc \
  debian-archive-keyring rsync jq curl wget fakeroot git
```

#### Verify dependencies:
The build script itself checks for missing dependencies and tells you what to install — you don't need to check manually beforehand.

| Package | Purpose |
|---------|---------|
| `mmdebstrap` | Bootstrap the base Debian chroot |
| `squashfs-tools` | Compress the rootfs into a SquashFS image |
| `grub` / `grub-common` + `grub-pc-bin` + `grub-efi-amd64-bin` | Build the GRUB bootloader for the ISO |
| `xorriso` | Create hybrid ISO images (BIOS + UEFI) |
| `mtools` | Manipulate FAT filesystems (EFI image inside ISO) |
| `dosfstools` | Format FAT partitions (EFI image) |
| `binutils` / `libisoburn` | Linker and ISO manipulation tools |
| `sassc` | SCSS compiler for GRUB and Plymouth themes |
| `imagemagick` | Image processing for branding assets |
| `psmisc` | Provides `fuser` to kill leftover processes on port 5900 |
| `fakeroot` | Build packages without real root privileges |
| `rsync` | Sync the base chroot into the working target |
| `jq` / `curl` / `wget` / `unzip` / `git` | Download and extract resources during build |


[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/W4V723UZ17)


## Profiles 📌
A profile lives under `profiles/<name>/` and provides:
- `profile.conf` — display name, package-name slug, default/supported bootloaders, ISO volume label/filename prefix, GRUB/rEFInd theme names, Plymouth theme name, boot-icons source
- `packages.list` — the `mmdebstrap` bootstrap package list
- `repo.sh` — defines `profile_setup_repo()` / `profile_teardown_repo()`, configuring the profile's own APT repo and keyring inside the chroot
- `packages.sh` — defines `PROFILE_REPO_PACKAGES`, `PROFILE_COMMON_PACKAGES`, `PROFILE_BACKPORTS_PACKAGES`, `PROFILE_LOCAL_PIN_GLOB`
- `customize.sh` — defines `profile_customize()`, the post-install branding/extra-apps step
- `keyring.gpg`, `boot-icons/` — asset files

`profile.conf` controls which bootloader(s) the profile builds with: `PROFILE_DEFAULT_BOOTLOADER` (used when `--grub`/`--refind` isn't passed) and `PROFILE_SUPPORTED_BOOTLOADERS` (an array; `build-iso.sh` refuses to build with a bootloader outside this list).

`profiles/pear/` is the existing Pulsar OS setup. Adding a second, completely different distro is just adding a new `profiles/<name>/` directory — the engine in `build-iso.sh` doesn't change.

## Refreshing the chroot quickly 📌
`sync-rootfs.sh` re-clones `build/rootfs-target-<branch>` from the already-bootstrapped `build/rootfs-base-<branch>` and reinstalls the local `.deb` packages from `PKG/debian/build/packages`, without redoing the full base bootstrap. Useful while iterating on packages. Accepts `--branch|-b <branch>` and `--nvidia`.


## Star History

<a href="https://www.star-history.com/?type=date&legend=top-left&repos=pearOS-archlinux%2Fiso">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=pearOS-archlinux/iso&type=date&theme=dark&legend=top-left&sealed_token=KCoZpQtRPSEfeJaKHJdmS0_mY6Cv50bUn53rlA25Zk-xK6-KJNEOgL9vbIL9nE20I4mYm9HWHfmGXSqyM7W_TnimzH3sqXTzulsuHnp01jqHaj70KM4ElA" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=pearOS-archlinux/iso&type=date&legend=top-left&sealed_token=KCoZpQtRPSEfeJaKHJdmS0_mY6Cv50bUn53rlA25Zk-xK6-KJNEOgL9vbIL9nE20I4mYm9HWHfmGXSqyM7W_TnimzH3sqXTzulsuHnp01jqHaj70KM4ElA" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=pearOS-archlinux/iso&type=date&legend=top-left&sealed_token=KCoZpQtRPSEfeJaKHJdmS0_mY6Cv50bUn53rlA25Zk-xK6-KJNEOgL9vbIL9nE20I4mYm9HWHfmGXSqyM7W_TnimzH3sqXTzulsuHnp01jqHaj70KM4ElA" />
 </picture>
</a>

## Copyright and Licensing  📌
This project is released under the GNU Pubilc License v3 or later

Copyright: Alexandru Balan @ Pear Software and Services S.R.L. based in Romania, Dacia Boulevard 133, floor D, Sector 2, Bucharest C.I.F.: 50888207
