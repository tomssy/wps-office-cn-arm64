#!/usr/bin/env bash
# install-wps-office-cn-aarch64.sh
# Ubuntu (aarch64) — downloads, patches, and repacks WPS Office CN .deb

exec 3>&1

PKGVER="12.1.2.26885"
DEB_URL="https://pubwps-wps365-obs.wpscdn.cn/download/Linux/26885/wps-office_${PKGVER}.AK.preread.sw.365_715982_arm64.deb"
PKGROOT="$HOME/wps-repack"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXISTING_EXTRACT="$SCRIPT_DIR/build/temp_extracted"

log()  { printf "\033[1;32m>>\033[0m %s\n" "$*" >&3; }
warn() { printf "\033[1;33m!!\033[0m %s\n" "$*" >&3; }
err()  { printf "\033[1;31mEE\033[0m %s\n" "$*" >&3; }

retry() {
    local n=0 max=3
    until "$@"; do
        n=$((n + 1))
        if (( n >= max )); then
            err "Command failed after $max attempts: $*"
            return 1
        fi
        warn "Retrying ($n/$max): $*"
        sleep 2
    done
}

safe_sed() {
    local pattern="$1" replacement="$2" dir="$3"
    find "$dir" -maxdepth 1 -type f -exec grep -Il . {} + 2>/dev/null | \
        xargs -r sed -i "s|$pattern|$replacement|g"
}

# =====================================================================
#  0.  Verify environment
# =====================================================================
DEB_FILE="$SCRIPT_DIR/wps-office_${PKGVER}_arm64.deb"

for cmd in ar bsdtar dpkg-deb find xargs fakeroot; do
    if ! command -v "$cmd" &>/dev/null; then
        err "Required command '$cmd' not found. Install it first."
        exit 1
    fi
done

log "Using PKGROOT: $PKGROOT"

# =====================================================================
#  1.  Download
# =====================================================================
if [[ -f "$DEB_FILE" ]]; then
    log "Using cached deb: $DEB_FILE ($(du -h "$DEB_FILE" | cut -f1))"
elif command -v aria2c &>/dev/null; then
    log "Downloading with aria2c..."
    aria2c -c -j8 -x8 -s8 --retry-wait=2 --max-tries=5 \
        -d "$(dirname "$DEB_FILE")" -o "$(basename "$DEB_FILE")" "$DEB_URL"
else
    log "Downloading with curl..."
    retry curl -fL --retry 3 --retry-delay 5 \
        -C - -o "$DEB_FILE" "$DEB_URL"
fi

if [[ ! -f "$DEB_FILE" ]]; then
    err "Download failed"
    exit 1
fi

# =====================================================================
#  2.  Extract
# =====================================================================
WORKDIR="$(mktemp -d -p "$HOME" -t wps-repack-XXXXXX)"
cd "$WORKDIR"

if [[ -d "$EXISTING_EXTRACT" ]]; then
    log "Using existing extraction: $EXISTING_EXTRACT"
    mkdir -p extracted
    if rsync -a --link-dest="$EXISTING_EXTRACT" "$EXISTING_EXTRACT"/ extracted/ 2>/dev/null; then
        log "Linked to existing extraction."
    else
        cp -a "$EXISTING_EXTRACT"/. extracted/
    fi
else
    log "Extracting .deb..."
    ar x "$DEB_FILE"
    mkdir -p extracted
    if [[ -f data.tar.xz ]]; then
        bsdtar -xpf data.tar.xz -C extracted
    elif [[ -f data.tar.zst ]]; then
        bsdtar --zstd -xpf data.tar.zst -C extracted
    elif [[ -f data.tar.gz ]]; then
        bsdtar -xpf data.tar.gz -C extracted
    fi
fi

if [[ ! -d extracted/opt/kingsoft/wps-office ]]; then
    err "Extraction failed: missing opt/kingsoft/wps-office"
    exit 1
fi

# =====================================================================
#  3.  Patch paths, fix python, remove bundled libs
# =====================================================================
log "Patching paths in wrapper scripts..."
safe_sed '/opt/kingsoft/wps-office' '/usr/lib' extracted/usr/bin

log "Adding LD_PRELOAD for arm64 freetype..."
find extracted/usr/bin -maxdepth 1 -type f -exec grep -Il . {} + 2>/dev/null | \
    xargs -r sed -i '2i export LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libfreetype.so.6'

log "Fixing python2 shebangs -> python3..."
find extracted/opt/kingsoft/wps-office/office6/ \
    -maxdepth 1 -type f -exec grep -rl '^#!/usr/bin/python$' {} + 2>/dev/null | \
    xargs -r sed -i '1s|^#!/usr/bin/python$|#!/usr/bin/python3|'

log "Fixing python2 urllib calls..."
find extracted/usr/bin -maxdepth 1 -type f -exec grep -Il . {} + 2>/dev/null | \
    xargs -r sed -i \
        -e 's/import sys, urllib; print urllib\.unquote/import sys, urllib.parse; print(urllib.parse.unquote/g' \
        -e "s/\$(python -c 'import sys, urllib;/\$(python3 -c 'import sys, urllib.parse;/g"

# =====================================================================
#  4.  Assemble .deb package directory
# =====================================================================
rm -rf "$PKGROOT"
DEB_PKG_DIR="$PKGROOT/wps-office-cn_${PKGVER}_arm64"
mkdir -p "$DEB_PKG_DIR/DEBIAN"
mkdir -p "$DEB_PKG_DIR/usr/lib"
mkdir -p "$DEB_PKG_DIR/usr/bin"
mkdir -p "$DEB_PKG_DIR/usr/share/applications" \
         "$DEB_PKG_DIR/usr/share/icons" \
         "$DEB_PKG_DIR/usr/share/mime" \
         "$DEB_PKG_DIR/usr/share/fonts/wps-office" \
         "$DEB_PKG_DIR/usr/share/desktop-directories"
mkdir -p "$DEB_PKG_DIR/etc/fonts/conf.avail" \
         "$DEB_PKG_DIR/etc/xdg/menus/applications-merged"

log "Copying office6..."
cp -a extracted/opt/kingsoft/wps-office/office6 "$DEB_PKG_DIR/usr/lib/"
rm -f "$DEB_PKG_DIR"/usr/lib/office6/libstdc++.so*
rm -f "$DEB_PKG_DIR"/usr/lib/office6/libjpeg.so*
rm -f "$DEB_PKG_DIR"/usr/lib/office6/libfreetype.so*
rm -f "$DEB_PKG_DIR"/usr/lib/office6/addons/cef/libm.so.6
rm -rf "$DEB_PKG_DIR"/usr/lib/office6/mui/en_US/resource/help

log "Copying bin wrappers..."
cp -a extracted/usr/bin/* "$DEB_PKG_DIR/usr/bin/"

log "Copying desktop files, icons, mime, fonts..."
cp -a extracted/usr/share/applications/* "$DEB_PKG_DIR/usr/share/applications/" 2>/dev/null
cp -a extracted/usr/share/icons/* "$DEB_PKG_DIR/usr/share/icons/" 2>/dev/null
cp -a extracted/usr/share/mime/* "$DEB_PKG_DIR/usr/share/mime/" 2>/dev/null
cp -a extracted/usr/share/fonts/wps-office/* "$DEB_PKG_DIR/usr/share/fonts/wps-office/" 2>/dev/null
cp -a extracted/usr/share/desktop-directories/* "$DEB_PKG_DIR/usr/share/desktop-directories/" 2>/dev/null
cp -a extracted/etc/fonts/conf.avail/40-wps-office.conf "$DEB_PKG_DIR/etc/fonts/conf.avail/" 2>/dev/null
cp -a extracted/etc/xdg/menus/applications-merged/wps-office.menu "$DEB_PKG_DIR/etc/xdg/menus/applications-merged/" 2>/dev/null

# =====================================================================
#  5.  Create DEBIAN/control and scripts
# =====================================================================
log "Creating DEBIAN/control..."
INSTALLED_SIZE=$(du -sk "$DEB_PKG_DIR/usr" | cut -f1)

cat > "$DEB_PKG_DIR/DEBIAN/control" <<EOF
Package: wps-office-cn
Version: ${PKGVER}
Section: office
Priority: optional
Architecture: arm64
Maintainer: maruf <maruf@example.com>
Installed-Size: ${INSTALLED_SIZE}
Depends: fontconfig, libxrender1, desktop-file-utils, shared-mime-info,
 xdg-utils, libglu1-mesa, libpulse0, libxss1, sqlite3, libjpeg-turbo8,
 libfreetype6, libstdc++6
Recommends: cups, curl
Provides: wps-office
Conflicts: kingsoft-office, wps-office
License: LicenseRef-WPS-EULA
Homepage: https://linux.wps.cn
Description: Kingsoft Office (WPS Office) CN version
 Repackaged for Ubuntu aarch64 from the official ARM64 deb,
 with patched paths, python3 fixes, and system library integration.
EOF

cat > "$DEB_PKG_DIR/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
update-mime-database /usr/share/mime &>/dev/null || true
update-desktop-database &>/dev/null || true
ln -sf /etc/fonts/conf.avail/40-wps-office.conf /etc/fonts/conf.d/40-wps-office.conf 2>/dev/null || true
fc-cache -f &>/dev/null || true
ldconfig &>/dev/null || true
EOF
chmod 755 "$DEB_PKG_DIR/DEBIAN/postinst"

cat > "$DEB_PKG_DIR/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
rm -f /etc/fonts/conf.d/40-wps-office.conf 2>/dev/null || true
EOF
chmod 755 "$DEB_PKG_DIR/DEBIAN/prerm"

cat > "$DEB_PKG_DIR/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
update-mime-database /usr/share/mime &>/dev/null || true
update-desktop-database &>/dev/null || true
fc-cache -f &>/dev/null || true
ldconfig &>/dev/null || true
EOF
chmod 755 "$DEB_PKG_DIR/DEBIAN/postrm"

# =====================================================================
#  6.  Build .deb
# =====================================================================
log "Building .deb..."
OUTPUT_DEB="$PKGROOT/wps-office-cn_${PKGVER}_arm64.deb"
fakeroot dpkg-deb -b "$DEB_PKG_DIR" "$OUTPUT_DEB"

if [[ -f "$OUTPUT_DEB" ]]; then
    log "========================================================"
    log "  DEB built: $OUTPUT_DEB ($(du -h "$OUTPUT_DEB" | cut -f1))"
    log "  Install with:"
    log "    sudo apt install -y \"$OUTPUT_DEB\""
    log "========================================================"
else
    err "Build failed"
    exit 1
fi

# Cleanup
rm -rf "$WORKDIR"
log "Done."
