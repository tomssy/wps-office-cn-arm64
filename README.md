# WPS Office CN for Fedora (aarch64)

Repackages the official WPS Office Chinese ARM64 `.deb` into a Fedora RPM,
with path patching and bundled library fixes for Fedora 42+.

## Usage

```bash
./install-fedora.sh
sudo dnf install -y ~/rpmbuild/RPMS/aarch64/wps-office-cn-*.rpm
```

## What it does

- Downloads the CN ARM64 `.deb` from WPS
- Extracts and patches paths (`/opt/kingsoft/wps-office` → `/usr/lib`)
- Fixes python2 shebangs → python3
- Strips bundled `libm.so.6` from CEF (conflicts with glibc ≥ 2.38 on Fedora 42+)
- Adds `LD_PRELOAD` for system `libfreetype.so.6`
- Builds an RPM and prints the install command

## Requirements

Fedora 42+ aarch64 with: `ar`, `bsdtar`, `rpmbuild`, `find`, `xargs`
