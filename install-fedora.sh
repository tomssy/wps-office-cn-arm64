#!/usr/bin/env bash
# install-wps-office-cn-aarch64.sh
# Fedora 42 (aarch64) — builds and installs WPS Office CN as an RPM
# Improved version with parallel operations, progress, and safe patching

exec 3>&1  # save stdout for progress messages

PKGVER="12.1.2.26885"
DEB_URL="https://pubwps-wps365-obs.wpscdn.cn/download/Linux/26885/wps-office_${PKGVER}.AK.preread.sw.365_715982_arm64.deb"
BUILDROOT="$HOME/rpmbuild"
WORKDIR="$(mktemp -d -p "$HOME" -t wps-repack-XXXXXX)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXISTING_EXTRACT="$SCRIPT_DIR/build/temp_extracted"

# Use all but one CPU core for parallel jobs
MAX_JOBS=$(nproc 2>/dev/null || echo 4)
MAX_JOBS=$((MAX_JOBS > 1 ? MAX_JOBS - 1 : 1))

log()  { printf "\033[1;32m>>\033[0m %s\n" "$*" >&3; }
warn() { printf "\033[1;33m!!\033[0m %s\n" "$*" >&3; }
err()  { printf "\033[1;31mEE\033[0m %s\n" "$*" >&3; }

# --- Helper: run with retries ---
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

# --- Helper: safe sed on text files only ---
safe_sed() {
    local pattern="$1" replacement="$2" dir="$3"
    find "$dir" -maxdepth 1 -type f -exec grep -Il . {} + 2>/dev/null | \
        xargs -r sed -i "s|$pattern|$replacement|g"
}

# =====================================================================
#  0.  Verify environment
# =====================================================================
DEB_FILE="$SCRIPT_DIR/wps-office_${PKGVER}_arm64.deb"

for cmd in ar bsdtar rpmbuild find xargs; do
    if ! command -v "$cmd" &>/dev/null; then
        err "Required command '$cmd' not found. Install it first."
        exit 1
    fi
done

log "Work dir: $WORKDIR"
log "Max parallel jobs: $MAX_JOBS"

# =====================================================================
#  1.  Download (with resume, multi-source if aria2c available)
# =====================================================================
if [[ -f "$DEB_FILE" ]]; then
    log "Using cached deb: $DEB_FILE ($(du -h "$DEB_FILE" | cut -f1))"
elif command -v aria2c &>/dev/null; then
    log "Downloading with aria2c (multi-connection)..."
    aria2c -c -j8 -x8 -s8 --retry-wait=2 --max-tries=5 \
        -d "$(dirname "$DEB_FILE")" -o "$(basename "$DEB_FILE")" "$DEB_URL"
else
    log "Downloading with curl... (install aria2c for faster downloads)"
    retry curl -fL --retry 3 --retry-delay 5 \
        -C - -o "$DEB_FILE" "$DEB_URL"
fi

if [[ ! -f "$DEB_FILE" ]]; then
    err "Download failed: $DEB_FILE not found"
    exit 1
fi

# =====================================================================
#  2.  Extract the .deb  (use existing extraction if available)
# =====================================================================
cd "$WORKDIR"

if [[ -d "$EXISTING_EXTRACT" ]]; then
    log "Using existing extraction: $EXISTING_EXTRACT"
    mkdir -p extracted
    if rsync -a --link-dest="$EXISTING_EXTRACT" "$EXISTING_EXTRACT"/ extracted/ 2>/dev/null; then
        log "Linked to existing extraction (instant)."
    else
        log "Falling back to full copy (slower)..."
        cp -a "$EXISTING_EXTRACT"/. extracted/
    fi
else
    log "Extracting .deb archive..."
    ar x "$DEB_FILE"
    mkdir -p extracted

    # data.tar.xz or data.tar.zst
    if [[ -f data.tar.xz ]]; then
        bsdtar -xpf data.tar.xz -C extracted &
    elif [[ -f data.tar.zst ]]; then
        bsdtar --zstd -xpf data.tar.zst -C extracted &
    elif [[ -f data.tar.gz ]]; then
        bsdtar -xpf data.tar.gz -C extracted &
    fi
    wait
fi

if [[ ! -d extracted/opt/kingsoft/wps-office ]]; then
    err "Extraction failed: missing opt/kingsoft/wps-office"
    exit 1
fi

# =====================================================================
#  3.  Prepare: patch paths, fix python, apply patches
# =====================================================================
log "Patching paths in wrapper scripts..."
safe_sed '/opt/kingsoft/wps-office' '/usr/lib' extracted/usr/bin

log "Adding LD_PRELOAD for arm64 freetype..."
find extracted/usr/bin -maxdepth 1 -type f -exec grep -Il . {} + 2>/dev/null | \
    xargs -r sed -i '2i export LD_PRELOAD=/usr/lib64/libfreetype.so.6'

log "Fixing python2 shebangs -> python3..."
find extracted/opt/kingsoft/wps-office/office6/ \
    -maxdepth 1 -type f -exec grep -rl '^#!/usr/bin/python$' {} + 2>/dev/null | \
    xargs -r sed -i '1s|^#!/usr/bin/python$|#!/usr/bin/python3|'

log "Fixing python2 urllib calls in wrapper scripts (python2->python3 syntax)..."
find extracted/usr/bin -maxdepth 1 -type f -exec grep -Il . {} + 2>/dev/null | \
    xargs -r sed -i \
        -e 's/import sys, urllib; print urllib\.unquote/import sys, urllib.parse; print(urllib.parse.unquote/g' \
        -e "s/\$(python -c 'import sys, urllib;/\$(python3 -c 'import sys, urllib.parse;/g"

# =====================================================================
#  4.  Assemble RPM build tree (parallel big copies)
# =====================================================================
log "Setting up RPM build tree..."
mkdir -p "$BUILDROOT"/{SPECS,SOURCES,BUILD,RPMS,SRPMS}
PKGROOT="$BUILDROOT/BUILD/wps-office-cn-${PKGVER}"
rm -rf "$PKGROOT"

# --- 4a. Create directories ---
mkdir -p "$PKGROOT/usr/lib"
mkdir -p "$PKGROOT/usr/bin"
mkdir -p "$PKGROOT/usr/share/applications" \
         "$PKGROOT/usr/share/icons" \
         "$PKGROOT/usr/share/mime" \
         "$PKGROOT/usr/share/fonts/wps-office" \
         "$PKGROOT/usr/share/desktop-directories"
mkdir -p "$PKGROOT/etc/fonts/conf.avail" \
         "$PKGROOT/etc/xdg/menus/applications-merged"

# --- 4b. Launch independent copy operations in parallel ---
COPY_PIDS=()

# Copy office6 (biggest: ~3GB)
(
    log "Copying office6 (this is the big one)..."
    cp -a extracted/opt/kingsoft/wps-office/office6 "$PKGROOT/usr/lib/"
    # Remove bundled libs
    rm -f "$PKGROOT"/usr/lib/office6/libstdc++.so*
    rm -f "$PKGROOT"/usr/lib/office6/libjpeg.so*
    rm -f "$PKGROOT"/usr/lib/office6/libfreetype.so*
    # Remove bundled glibc libm from cef (too old for Fedora 42+, shadows system libm via RPATH)
    rm -f "$PKGROOT"/usr/lib/office6/addons/cef/libm.so.6
    # Remove en_US help (saves ~200MB)
    rm -rf "$PKGROOT"/usr/lib/office6/mui/en_US/resource/help
    # Keep zh_CN (user wants CN version)
    log "office6 copied ($(du -sh "$PKGROOT/usr/lib/office6" | cut -f1))."
) &
COPY_PIDS+=($!)

(
    log "Copying bin wrappers..."
    cp -a extracted/usr/bin/* "$PKGROOT/usr/bin/"
) &
COPY_PIDS+=($!)

(
    log "Copying desktop files, icons, mime, fonts..."
    # All share subdirs can run in parallel subshells
    (
        cp -a extracted/usr/share/applications/* "$PKGROOT/usr/share/applications/" 2>/dev/null
    ) &
    (
        cp -a extracted/usr/share/icons/* "$PKGROOT/usr/share/icons/" 2>/dev/null
    ) &
    (
        cp -a extracted/usr/share/mime/* "$PKGROOT/usr/share/mime/" 2>/dev/null
    ) &
    (
        cp -a extracted/usr/share/fonts/wps-office/* "$PKGROOT/usr/share/fonts/wps-office/" 2>/dev/null
    ) &
    (
        cp -a extracted/usr/share/desktop-directories/* "$PKGROOT/usr/share/desktop-directories/" 2>/dev/null
    ) &
    wait
) &
COPY_PIDS+=($!)

(
    log "Copying /etc configs..."
    cp -a extracted/etc/fonts/conf.avail/40-wps-office.conf "$PKGROOT/etc/fonts/conf.avail/" 2>/dev/null
    cp -a extracted/etc/xdg/menus/applications-merged/wps-office.menu "$PKGROOT/etc/xdg/menus/applications-merged/" 2>/dev/null
) &
COPY_PIDS+=($!)

# Wait for all parallel copies to finish
log "Waiting for copy operations to complete..."
fail=0
for pid in "${COPY_PIDS[@]}"; do
    wait "$pid" 2>/dev/null || ((fail++))
done

if (( fail > 0 )); then
    err "$fail copy operation(s) failed."
else
    log "All copy operations completed successfully."
fi

# =====================================================================
#  5.  Generate RPM spec
# =====================================================================
log "Generating RPM spec..."
cat > "$BUILDROOT/SPECS/wps-office-cn.spec" <<EOF
Name:           wps-office-cn
Version:        ${PKGVER//-/_}
Release:        1%{?dist}
Summary:        Kingsoft Office (WPS Office) CN version
License:        LicenseRef-WPS-EULA
URL:            https://linux.wps.cn
BuildArch:      aarch64
AutoReqProv:    no
Requires:       fontconfig, xorg-x11-font-utils, libXrender, desktop-file-utils, shared-mime-info, xdg-utils, sqlite, libtool, libxslt, libjpeg-turbo
Provides:       wps-office
Conflicts:      kingsoft-office, wps-office

%description
Kingsoft Office (WPS Office) CN version, repackaged as an RPM for Fedora aarch64
from the official 365/international arm64 deb build.

%install
mkdir -p %{buildroot}
cp -a ${PKGROOT}/usr %{buildroot}/
cp -a ${PKGROOT}/etc %{buildroot}/

%files
/usr/lib/office6
/usr/bin/*
/usr/share/applications/*
/usr/share/icons/*
/usr/share/mime/*
/usr/share/fonts/wps-office/*
/usr/share/desktop-directories/*
/etc/fonts/conf.avail/40-wps-office.conf
/etc/xdg/menus/applications-merged/wps-office.menu

%post
update-mime-database /usr/share/mime &>/dev/null || :
update-desktop-database &>/dev/null || :
ln -sf /etc/fonts/conf.avail/40-wps-office.conf /etc/fonts/conf.d/40-wps-office.conf &>/dev/null || :
fc-cache -f &>/dev/null || :

%postun
update-mime-database /usr/share/mime &>/dev/null || :
update-desktop-database &>/dev/null || :
rm -f /etc/fonts/conf.d/40-wps-office.conf &>/dev/null || :
EOF

# =====================================================================
#  6.  Build RPM
# =====================================================================
log "Building RPM (this may take a while)..."
export QA_RPATHS=$(( 0x0001|0x0002|0x0004|0x0008|0x0010|0x0020 ))
rpmbuild -bb "$BUILDROOT/SPECS/wps-office-cn.spec"

BUILD_EXIT=$?

# =====================================================================
#  7.  Verify and report
# =====================================================================
if (( BUILD_EXIT == 0 )); then
    RPM_PATH=$(find "$BUILDROOT/RPMS" -name "wps-office-cn-*.rpm" | head -n1)

    if [[ -n "$RPM_PATH" ]]; then
        RPM_SIZE=$(du -h "$RPM_PATH" | cut -f1)
        log "RPM successfully built: $RPM_PATH ($RPM_SIZE)"

        # Quick verification
        log "Verifying RPM contents..."
        MISSING=0
        rpm -qlp "$RPM_PATH" | grep -q '/usr/lib/office6'      || { warn "Missing /usr/lib/office6";      ((MISSING++)); }
        rpm -qlp "$RPM_PATH" | grep -q '/usr/bin/wps'          || { warn "Missing /usr/bin/wps";          ((MISSING++)); }
        rpm -qlp "$RPM_PATH" | grep -q 'zh_CN'                 || { warn "Missing zh_CN localization";    ((MISSING++)); }
        rpm -qlp "$RPM_PATH" | grep -q '/etc/fonts/conf.avail' || { warn "Missing font config";           ((MISSING++)); }

        if (( MISSING == 0 )); then
            log "All expected files present in RPM."
        else
            warn "$MISSING expected file(s) missing from RPM."
        fi

        echo ""
        log "========================================================"
        log "  INSTALL COMMAND (copy & paste):"
        log "    sudo dnf install -y \"$RPM_PATH\""
        log "========================================================"
    else
        err "RPM built but could not find it in $BUILDROOT/RPMS"
    fi
else
    err "RPM build failed (exit code $BUILD_EXIT). Check $BUILDROOT/BUILD for logs."
fi

# Cleanup
rm -rf "$WORKDIR"
log "Done."
