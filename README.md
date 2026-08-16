# Pulsar OS ISO

This repository contains the ISO build script, the configuration files for preinstalled packages, and the Github Actions workflows.  
PulsarOS is built 100% by Github Actions, fully auditable end-to-end, and the ISO images are uploaded to Sourceforge (since Github Releases has very low size limits).

## Prerequisites

The build always produces a Debian-based ISO, but the build script itself can run from either a Debian-family host or an Arch-family host (e.g. building the ISO from CachyOS/Manjaro is fully supported). The build script checks for missing dependencies and tells you what to install. But if you want to set everything up beforehand:

### Building from an Arch Linux / CachyOS / Manjaro host

```bash
sudo pacman -S --needed \
  squashfs-tools grub xorriso mtools dosfstools \
  binutils libisoburn sassc imagemagick psmisc \
  fakeroot rsync jq curl unzip wget git
```

You'll also need `mmdebstrap` from the AUR (e.g. `yay -S mmdebstrap`), since it bootstraps the Debian chroot regardless of the host distro.

### Building from a Debian / Ubuntu / Pop!_OS host

```bash
sudo apt-get install -y \
  mmdebstrap squashfs-tools grub-common grub-efi-amd64-bin grub-pc-bin \
  xorriso mtools dosfstools binutils unzip sassc imagemagick psmisc \
  debian-archive-keyring rsync jq curl wget fakeroot git
```

### What each package does

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

## Building the ISO  
`build-iso.sh` is a generic Debian live-ISO engine: package list, extra APT repo, package selection, branding and boot menu/theme names all come from a **profile** under `profiles/<name>/`, not from the script itself. It accepts the following flags:
- `--profile <name>` Distro profile to build, from `profiles/<name>/`. Default: `pear` (Pulsar OS).
- `--branch stable`, replacing stable with any other Debian branch; currently only stable can be used.
- `--local` to package from the packages in the `/PKG` folder, which must be in the same folder that contains the `/ISO` folder
- `--refind` Build the rEFInd version (must be in the profile's supported-bootloader list)
- `--grub` Build the GRUB version (must be in the profile's supported-bootloader list)
- `--nvidia` Build ISO image with privative drivers (BROADCOM, NVIDIA, etc...)

If neither `--grub` nor `--refind` is passed, the profile's own default bootloader (`PROFILE_DEFAULT_BOOTLOADER`) is used.

### Profiles
A profile lives under `profiles/<name>/` and provides:
- `profile.conf` — display name, package-name slug, default/supported bootloaders, ISO volume label/filename prefix, GRUB/rEFInd theme names, Plymouth theme name, boot-icons source
- `packages.list` — the `mmdebstrap` bootstrap package list
- `repo.sh` — defines `profile_setup_repo()` / `profile_teardown_repo()`, configuring the profile's own APT repo and keyring inside the chroot
- `packages.sh` — defines `PROFILE_REPO_PACKAGES`, `PROFILE_COMMON_PACKAGES`, `PROFILE_BACKPORTS_PACKAGES`, `PROFILE_LOCAL_PIN_GLOB`
- `customize.sh` — defines `profile_customize()`, the post-install branding/extra-apps step
- `keyring.gpg`, `boot-icons/` — asset files

`profile.conf` controls which bootloader(s) the profile builds with: `PROFILE_DEFAULT_BOOTLOADER` (used when `--grub`/`--refind` isn't passed) and `PROFILE_SUPPORTED_BOOTLOADERS` (an array; `build-iso.sh` refuses to build with a bootloader outside this list, e.g. a profile that only ships a GRUB theme can set `PROFILE_SUPPORTED_BOOTLOADERS=(grub)` to reject `--refind` with a clear error instead of producing a broken ISO).

`profiles/pear/` is the existing Pulsar OS setup, migrated as-is. Adding a second, completely different distro is just adding a new `profiles/<name>/` directory — the engine in `build-iso.sh` doesn't change.

## Refreshing the chroot quickly   
`sync-rootfs.sh` re-clones `build/rootfs-target-<branch>` from the already-bootstrapped `build/rootfs-base-<branch>` and reinstalls the local `.deb` packages from `PKG/debian/build/packages`, without redoing the full base bootstrap. Useful while iterating on packages. Accepts:
- `--branch|-b <branch>` Sets the branch, must be `stable`, `forky` or `rolling` (default: `stable`)
- `--nvidia` Uses the NVIDIA variant of the rootfs

## Building from GH Actions  
The ISO version, release name, and branch must be specified.  

## Packages  
PulsarOS is fully declarative; packages are built and obtained from [repo PKG](https://github.com/Inled-Pulsar-OS/PKG)

## License
All the code is licensed under [MIT-INLED](https://license.inled.es)
