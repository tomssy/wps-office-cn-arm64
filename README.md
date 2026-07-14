# WPS Office CN (ARM64) for Linux

Repackages the official WPS Office Chinese **ARM64** `.deb` into native packages for Fedora, Ubuntu, and Arch Linux, with path patching and bundled library fixes.

## Why this exists

WPS Office only publishes an ARM64 `.deb` for their Chinese/365 build (no official RPM or Arch package for aarch64). This repo automates the repackaging with necessary fixes to run on modern ARM64 Linux distributions.

### Common fixes applied

- **Path patching**: `/opt/kingsoft/wps-office` → `/usr/lib`
- **Python 2 → 3**: Fixes shebangs and `urllib` syntax in wrapper scripts
- **Bundled libm removed**: The CEF addons ship an old `libm.so.6` (glibc ≤ 2.31) which conflicts with `libxml2` on newer glibc. Using system libm instead.
- **Bundled libs stripped**: Removes `libstdc++.so*`, `libjpeg.so*`, `libfreetype.so*` — uses system versions
- **LD_PRELOAD for freetype**: Ensures ARM64 freetype is loaded correctly
- **en_US help removed**: Saves ~200 MB (zh_CN kept)

---

## Fedora 42+

```bash
# Install build tools
sudo dnf install -y binutils bsdtar rpm-build findutils

# Build RPM
./install-fedora.sh

# Install
sudo dnf install -y ~/rpmbuild/RPMS/aarch64/wps-office-cn-*.rpm
```

## Ubuntu 24.04+

```bash
# Install build tools
sudo apt install -y binutils libarchive-tools dpkg-dev fakeroot findutils

# Build .deb
./install-ubuntu.sh

# Install
sudo apt install -y ~/wps-repack/wps-office-cn_*_arm64.deb
```

## Arch Linux (ARM64)

```bash
# Build and install via makepkg
makepkg -si
```

Or install the dependencies manually and build:
```bash
sudo pacman -S --needed base-devel
makepkg -si
```

---

## GitHub Action (manual trigger)

The repo includes a workflow at `.github/workflows/build-rpm.yml` that builds a Fedora RPM using a native ARM64 GitHub runner (`ubuntu-24.04-arm`).

1. Go to **Actions** → **Build RPM (Fedora aarch64)** → **Run workflow**
2. Optionally override the WPS version or Fedora release
3. Download the RPM from the published artifact

> ARM64 runners are **free for public repositories**.

## Requirements

| Distro | Architectures | Build tools needed |
|--------|--------------|-------------------|
| Fedora 42+ | aarch64 | `binutils`, `bsdtar`, `rpm-build`, `findutils` |
| Ubuntu 24.04+ | aarch64 | `binutils`, `libarchive-tools`, `dpkg-dev`, `fakeroot` |
| Arch Linux | aarch64 | `base-devel` |

## Proprietary notice

WPS Office is proprietary software. Use at your own risk. This repo only contains scripts to repackage the official binaries — no proprietary code is hosted here.

## Credits

Based on [Rongronggg9/wps-office-repack](https://github.com/Rongronggg9/wps-office-repack) and the [AUR PKGBUILD](https://aur.archlinux.org/packages/wps-office-cn).
