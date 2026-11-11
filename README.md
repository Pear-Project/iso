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
- `--branch stable`, replacing stable with `forky` or `rolling` (mapped to Debian's `trixie`, `forky` and `testing` suites respectively).
- `--local` to package from the packages in the `/PKG` folder, which must be in the same folder that contains the `/ISO` folder
- `--nvidia` Build ISO image with privative drivers (BROADCOM, NVIDIA, etc...)
- `--clean-base` Delete the cached base Debian chroot and rebuild it from scratch.
- `--clean-target` Delete the working target rootfs and re-clone it from the base cache, even if one already exists from a previous run.
- `--chroot` Drop into an interactive shell inside the target rootfs right before compression (proc/sys/dev are still mounted), then stop -- never falls through to packaging the ISO in the same run. **The target rootfs is never deleted automatically**: if one already exists (from an earlier `--chroot` session, a finished build, or days ago), any run -- `--chroot` or plain -- reuses it as-is and skips straight past repo/package install. Pass `--clean-target` to force a fresh one.

The ISO boots via **Ploader** (pearOS's own rebrand of rEFInd 0.14.1, a prebuilt EFI binary+theme vendored under `profiles/<name>/ploader/`) for UEFI, with **syslinux** as the BIOS/legacy fallback -- there's no bootloader choice to make.

### Dependencies: 📌

#### Building from an Arch Linux / CachyOS / Manjaro host
```sh
sudo pacman -S --needed \
  squashfs-tools syslinux xorriso mtools dosfstools \
  binutils libisoburn sassc imagemagick psmisc \
  fakeroot rsync jq curl unzip wget git
```
You'll also need `mmdebstrap` from the AUR (e.g. `yay -S mmdebstrap`), since it bootstraps the Debian chroot regardless of the host distro.

#### Building from a Debian / Ubuntu / Pop!_OS host
```sh
sudo apt-get install -y \
  mmdebstrap squashfs-tools isolinux syslinux-common \
  xorriso mtools dosfstools binutils unzip sassc imagemagick psmisc \
  debian-archive-keyring rsync jq curl wget fakeroot git
```

#### Verify dependencies:
The build script itself checks for missing dependencies and tells you what to install — you don't need to check manually beforehand.

| Package | Purpose |
|---------|---------|
| `mmdebstrap` | Bootstrap the base Debian chroot |
| `squashfs-tools` | Compress the rootfs into a SquashFS image |
| `isolinux` / `syslinux-common` | BIOS boot binaries (`isolinux.bin`, `*.c32` modules) for the ISO -- installed into the profile's own chroot, not the host |
| `xorriso` | Create hybrid ISO images (BIOS + UEFI) |
| `mtools` | Manipulate FAT filesystems (EFI image inside ISO) |
| `dosfstools` | Format FAT partitions (EFI image) |
| `binutils` / `libisoburn` | Linker and ISO manipulation tools |
| `sassc` | SCSS compiler for Plymouth themes |
| `imagemagick` | Image processing for branding assets |
| `psmisc` | Provides `fuser` to kill leftover processes on port 5900 |
| `fakeroot` | Build packages without real root privileges |
| `rsync` | Sync the base chroot into the working target |
| `jq` / `curl` / `wget` / `unzip` / `git` | Download and extract resources during build |


[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/W4V723UZ17)


## Profiles 📌
A profile lives under `profiles/<name>/` and provides:
- `profile.conf` — display name, package-name slug, ISO volume label/filename prefix, Plymouth theme name, boot-icons source
- `packages.list` — the `mmdebstrap` bootstrap package list
- `repo.sh` — defines `profile_setup_repo()` / `profile_teardown_repo()`, configuring the profile's own APT repo and keyring inside the chroot
- `packages.sh` — defines `PROFILE_REPO_PACKAGES`, `PROFILE_COMMON_PACKAGES`, `PROFILE_BACKPORTS_PACKAGES`, `PROFILE_LOCAL_PIN_GLOB`
- `customize.sh` — defines `profile_customize()`, the post-install branding/extra-apps step
- `ploader/` — the vendored Ploader EFI binary (`ploader_x64.efi`) and boot theme (`theme/`)
- `syslinux/` — the BIOS boot menu background (`splash.png`)
- `boot-icons/` — asset files (the profile's APT signing key, if any, is embedded directly in `repo.sh` instead of a separate file)

`profiles/pear/` is the existing Pulsar OS setup. Adding a second, completely different distro is just adding a new `profiles/<name>/` directory — the engine in `build-iso.sh` doesn't change.

## Refreshing the chroot quickly 📌
`sync-rootfs.sh` re-clones `build/rootfs-target-<branch>` from the already-bootstrapped `build/rootfs-base-<branch>` and reinstalls the local `.deb` packages from `PKG/debian/build/packages`, without redoing the full base bootstrap. Useful while iterating on packages. Accepts `--branch|-b <branch>` and `--nvidia`.


## Boot Status sequence 📌
<!-- boot-seq:begin -->

Result: **FAIL TEST ❌**  

**Success score: 85/100**

| Test | Score |
|---|---|
| Boot | 100/100 |
| UI sanity | 50/100 |
| Installable | 100/100 |
| Usability | 90/100 |

Usability checks:

| Check | Result |
|---|---|
| login + desktop | ✅  |
| UI sanity (installed) | ❌ top 88% / dock 100% |
| Konsole opens | ✅  |
| os-release says pearOS | ✅  |
| sudo apt-get dist-upgrade | ✅  |
| Pafari opens | ✅  |
| Calculator opens | ✅  |
| Notes opens | ✅  |
| Finder opens | ✅  |
| Kate opens | ✅  |


> **Why it failed:** The installed desktop looks different from the reference: menu bar 88.4%, dock 100.0% (each must be at least 90%).

This ISO was **not published**; it was saved as a quarantined `FAIL_TEST` build.

One screenshot every 10s.

1. `10s` — ![boot 1](seq/1.png)
2. `20s` — ![boot 2](seq/2.png)
3. `30s` — ![boot 3](seq/3.png)
4. `40s` — ![boot 4](seq/4.png)
5. `50s` — ![boot 5](seq/5.png)
6. `60s` — ![boot 6](seq/6.png)
7. `70s` — ![boot 7](seq/7.png)
8. `80s` — ![boot 8](seq/8.png)
9. `90s` — ![boot 9](seq/9.png)
10. `100s` — desktop ready, then clicked **Install pearOS** in Welcome — ![boot 10](seq/10.png)
11. `110s` — pearOS installer loading — ![boot 11](seq/11.png)
12. `120s` — pearOS installer loading — ![boot 12](seq/12.png)
13. `130s` — Language screen, then selected English — ![boot 13](seq/13.png)
14. `140s` — Language screen, then clicked Next — ![boot 14](seq/14.png)
15. `150s` — Recovery screen, then selected **Install pearOS Goldwing** — ![boot 15](seq/15.png)
16. `160s` — Recovery screen, then clicked **Continue** — ![boot 16](seq/16.png)
17. `170s` — Installer welcome, then clicked **Continue** — ![boot 17](seq/17.png)
18. `180s` — Terms and Conditions, then clicked **Continue** — ![boot 18](seq/18.png)
19. `190s` — ![boot 19](seq/19.png)
20. `200s` — ![boot 20](seq/20.png)
21. `210s` — ![boot 21](seq/21.png)
22. `220s` — ![boot 22](seq/22.png)
23. `230s` — ![boot 23](seq/23.png)
24. `240s` — ![boot 24](seq/24.png)
25. `250s` — ![boot 25](seq/25.png)
26. `260s` — Calamares — ![boot 26](seq/26.png)
27. `270s` — Calamares: Welcome, clicked Next — ![boot 27](seq/27.png)
28. `280s` — Calamares: Location, clicked Next — ![boot 28](seq/28.png)
29. `290s` — Calamares: Keyboard, clicked Next — ![boot 29](seq/29.png)
30. `300s` — Calamares: Partitions, selected Erase disk — ![boot 30](seq/30.png)
31. `310s` — Calamares: Partitions, clicked Next — ![boot 31](seq/31.png)
32. `320s` — Calamares: Summary, clicked Install — ![boot 32](seq/32.png)
33. `330s` — Calamares: installing (2 min) — ![boot 33](seq/33.png)
34. `340s` — Calamares: installation finished — ![boot 34](seq/34.png)
35. `350s` — Installed system: first boot — ![boot 35](seq/35.png)
36. `360s` — Installed system: first boot — ![boot 36](seq/36.png)
37. `370s` — Installed system: first boot — ![boot 37](seq/37.png)
38. `380s` — Installed system: first boot — ![boot 38](seq/38.png)
39. `390s` — Installed system: first boot — ![boot 39](seq/39.png)
40. `400s` — Installed system: reached the login screen / desktop — ![boot 40](seq/40.png)
41. `410s` — First boot: country — ![boot 41](seq/41.png)
42. `420s` — First boot: transfer — ![boot 42](seq/42.png)
43. `430s` — First boot: languages — ![boot 43](seq/43.png)
44. `440s` — First boot: accessibility — ![boot 44](seq/44.png)
45. `450s` — First boot: data & privacy — ![boot 45](seq/45.png)
46. `460s` — First boot: PearID — ![boot 46](seq/46.png)
47. `470s` — First boot: create account — ![boot 47](seq/47.png)
48. `480s` — First boot: account filled in — ![boot 48](seq/48.png)
49. `490s` — First boot: terms — ![boot 49](seq/49.png)
50. `500s` — First boot: location services — ![boot 50](seq/50.png)
51. `510s` — First boot: time zone — ![boot 51](seq/51.png)
52. `520s` — First boot: analytics — ![boot 52](seq/52.png)
53. `530s` — First boot: screen time — ![boot 53](seq/53.png)
54. `540s` — First boot: Piri — ![boot 54](seq/54.png)
55. `550s` — First boot: look — ![boot 55](seq/55.png)
56. `560s` — First boot: updates — ![boot 56](seq/56.png)
57. `570s` — First boot: ready — ![boot 57](seq/57.png)
58. `580s` — First boot: applying settings — ![boot 58](seq/58.png)
59. `590s` — Login screen — ![boot 59](seq/59.png)
60. `600s` — Login screen — ![boot 60](seq/60.png)
61. `610s` — Login screen — ![boot 61](seq/61.png)
62. `620s` — Login screen — ![boot 62](seq/62.png)
63. `630s` — Login screen — ![boot 63](seq/63.png)
64. `640s` — Login screen — ![boot 64](seq/64.png)
65. `650s` — Login screen — ![boot 65](seq/65.png)
66. `660s` — Login screen — ![boot 66](seq/66.png)
67. `670s` — Login screen — ![boot 67](seq/67.png)
68. `680s` — Login screen — ![boot 68](seq/68.png)
69. `690s` — Login screen — ![boot 69](seq/69.png)
70. `700s` — Login screen — ![boot 70](seq/70.png)
71. `710s` — Logging in — ![boot 71](seq/71.png)
72. `720s` — Logging in — ![boot 72](seq/72.png)
73. `730s` — Logging in — ![boot 73](seq/73.png)
74. `740s` — Logging in — ![boot 74](seq/74.png)
75. `750s` — Logging in — ![boot 75](seq/75.png)
76. `760s` — Logging in — ![boot 76](seq/76.png)
77. `770s` — Installed system: desktop — ![boot 77](seq/77.png)
78. `780s` — Konsole opened — ![boot 78](seq/78.png)
79. `790s` — Konsole: cat /etc/os-release — ![boot 79](seq/79.png)
80. `800s` — Konsole: apt-get dist-upgrade succeeded — ![boot 80](seq/80.png)
81. `810s` — App: Pafari opened — ![boot 81](seq/81.png)
82. `820s` — App: Calculator opened — ![boot 82](seq/82.png)
83. `830s` — App: Notes opened — ![boot 83](seq/83.png)
84. `840s` — App: Finder opened — ![boot 84](seq/84.png)
85. `850s` — App: Kate opened — ![boot 85](seq/85.png)

<!-- boot-seq:end -->

## UI Sanity Test 📌
<!-- ui-sanity:begin -->

Result: **menu bar + dock look as expected ✅**  
Compared against the reference `tests/ui-reference/debian/desktop.png` (% of pixels within ±16 per channel; pass ≥ 90%).

| Area | Similarity |
|---|---|
| Top bar (first 30 px) | 94.7% |
| Dock (last 100 px) | 100.0% |

Current frame: ![desktop](seq/10.png)

<!-- ui-sanity:end -->

## Star History

<a href="https://www.star-history.com/?repos=Pear-Project%2Fiso&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=Pear-Project/iso&type=date&theme=dark&legend=top-left&sealed_token=NMIHZsg3VJdXESixt4YJkhd8a0Rw-05CFsfbT8OzOi4mHHyKfZwdiHtohfx4PMWaKv4a7nR5AGWznlBxyOWcrq82-DSYvdXur6JUwnzDU0GX476E7bpU2A" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=Pear-Project/iso&type=date&legend=top-left&sealed_token=NMIHZsg3VJdXESixt4YJkhd8a0Rw-05CFsfbT8OzOi4mHHyKfZwdiHtohfx4PMWaKv4a7nR5AGWznlBxyOWcrq82-DSYvdXur6JUwnzDU0GX476E7bpU2A" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=Pear-Project/iso&type=date&legend=top-left&sealed_token=NMIHZsg3VJdXESixt4YJkhd8a0Rw-05CFsfbT8OzOi4mHHyKfZwdiHtohfx4PMWaKv4a7nR5AGWznlBxyOWcrq82-DSYvdXur6JUwnzDU0GX476E7bpU2A" />
 </picture>
</a>

## Copyright and Licensing  📌
This project is released under the GNU Pubilc License v3 or later

Copyright: Alexandru Balan @ Pear Software and Services S.R.L. based in Romania, Dacia Boulevard 133, floor D, Sector 2, Bucharest C.I.F.: 50888207

## Raspberry Pi (arm64)

Latest boot / first-boot / usability test sequence: [seq-pi/README.md](seq-pi/README.md)
