# Maintainer: maruf <maruf@example.com>
# Based on AUR PKGBUILD by Clover Yan, Astro Benzene, et al.

pkgname=wps-office-cn
pkgver=12.1.2.26885
pkgrel=1
pkgdesc="Kingsoft Office (WPS Office) CN version - ARM64"
arch=('aarch64')
license=('LicenseRef-WPS-EULA')
url="https://linux.wps.cn"
options=('!emptydirs' '!strip')
depends=('fontconfig' 'xorg-mkfontscale' 'libxrender' 'desktop-file-utils'
         'shared-mime-info' 'xdg-utils' 'glu' 'sdl2' 'libpulse'
         'hicolor-icon-theme' 'libxss' 'sqlite' 'libtool' 'libxslt'
         'libjpeg-turbo' 'freetype2')
optdepends=('cups: for printing support'
            'pango: for complex text support'
            'curl: URL retrieval utility'
            'ttf-wps-fonts: Symbol fonts for WPS')
conflicts=('kingsoft-office' 'wps-office')
provides=('wps-office')
install=wps-office-cn.install

source=("wps-office_${pkgver}_arm64.deb::https://pubwps-wps365-obs.wpscdn.cn/download/Linux/${pkgver##*.}/wps-office_${pkgver}.AK.preread.sw.365_715982_arm64.deb")
sha256sums=('SKIP')

prepare() {
  ar x "$srcdir/wps-office_${pkgver}_arm64.deb"
  bsdtar -xpf data.tar.xz

  # Patch paths in wrapper scripts
  cd "${srcdir}/usr/bin"
  sed -i 's|/opt/kingsoft/wps-office|/usr/lib|' *

  # LD_PRELOAD for arm64 freetype
  sed -i '2i export LD_PRELOAD=/usr/lib/libfreetype.so' *
}

package() {
  cd "${srcdir}/opt/kingsoft/wps-office/"

  # Main office6
  install -d "${pkgdir}/usr/lib"
  cp -a office6 "${pkgdir}/usr/lib"

  # Remove bundled libs that conflict with system
  rm -f "${pkgdir}"/usr/lib/office6/libstdc++.so*
  rm -f "${pkgdir}"/usr/lib/office6/libjpeg.so*
  rm -f "${pkgdir}"/usr/lib/office6/libfreetype.so*
  # Remove bundled glibc libm from cef (too old, shadows system via RPATH)
  rm -f "${pkgdir}"/usr/lib/office6/addons/cef/libm.so.6
  # Remove en_US help (saves ~200MB)
  rm -rf "${pkgdir}"/usr/lib/office6/mui/en_US/resource/help
  # Keep zh_CN

  # License
  install -Dm644 -t "${pkgdir}/usr/share/licenses/${pkgname}" office6/mui/default/*.html

  # Wrapper scripts
  install -d "${pkgdir}/usr/bin"
  cd "${srcdir}/usr/bin"
  install -m755 * "${pkgdir}/usr/bin"

  # Desktop files
  cd "${srcdir}/usr/share"
  install -d "${pkgdir}/usr/share/applications"
  cp -a applications/* "${pkgdir}/usr/share/applications"

  install -d "${pkgdir}/usr/share/desktop-directories"
  cp -a desktop-directories/* "${pkgdir}/usr/share/desktop-directories"

  install -d "${pkgdir}/usr/share/icons"
  cp -a icons/* "${pkgdir}/usr/share/icons"

  install -d "${pkgdir}/usr/share/fonts/wps-office"
  cp -a fonts/wps-office/* "${pkgdir}/usr/share/fonts/wps-office/" 2>/dev/null

  install -Dm644 -t "${pkgdir}/etc/xdg/menus/applications-merged" \
    "${srcdir}/etc/xdg/menus/applications-merged/wps-office.menu"

  install -Dm644 -t "${pkgdir}/etc/fonts/conf.avail" \
    "${srcdir}/etc/fonts/conf.avail/40-wps-office.conf"
}
