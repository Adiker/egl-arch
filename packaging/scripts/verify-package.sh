#!/usr/bin/env bash
# Inspect a pacman package without installing it. Optional second argument:
# the original extracted AppImage tree, for byte-for-byte payload comparison.
set -euo pipefail
package=$(realpath "${1:?Usage: verify-package.sh package.pkg.tar.zst [original-appdir]}")
original=${2:-}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
bsdtar -xf "$package" -C "$work"
pkgname=$(sed -n 's/^pkgname = //p' "$work/.PKGINFO")
[[ $pkgname == epic-games-launcher-bin || $pkgname == epic-games-launcher-proton-bin ]]
for file in \
  usr/bin/epic-games-launcher usr/bin/EpicGamesLauncher usr/bin/egl-proton \
  opt/epic-games-launcher/bin/EpicGamesLauncher \
  opt/epic-games-launcher/lib/libEOSSDK-Linux-Shipping.so \
  opt/epic-games-launcher/lib/epic-games-launcher/libEOSSDK-Linux-Shipping.so \
  opt/epic-games-launcher/lib/epic-games-launcher/resources/ThirdPartyNotices.txt \
  usr/lib/epic-games-launcher/egl-proton-hook \
  usr/lib/epic-games-launcher/egl-proton-router \
  usr/lib/epic-games-launcher/tray/libayatana-appindicator3.so.1 \
  usr/lib/systemd/user/egl-fedora-proton-hook.path \
  usr/lib/systemd/user/egl-fedora-proton-hook.service \
  usr/share/applications/EpicGamesLauncher.desktop \
  usr/share/applications/epic-games-launcher.desktop \
  usr/share/applications/io.github.dxvsi.EglProton.desktop \
  usr/share/icons/hicolor/128x128/apps/EpicGamesLauncher.png \
  "usr/share/licenses/$pkgname/LICENSE"; do
  [[ -e $work/$file ]] || { echo "Missing: $file" >&2; exit 1; }
done
[[ $(readlink "$work/usr/bin/EpicGamesLauncher") == epic-games-launcher ]]
# KWin resolves icons by app_id + .desktop, not StartupWMClass on Wayland.
desktop="$work/usr/share/applications/EpicGamesLauncher.desktop"
grep -qxF 'Icon=/usr/share/icons/hicolor/128x128/apps/EpicGamesLauncher.png' "$desktop"
grep -qxF 'StartupWMClass=EpicGamesLauncher' "$desktop"
if grep -qxF 'NoDisplay=true' "$desktop"; then
  echo 'The primary Wayland desktop entry must be visible' >&2
  exit 1
fi
grep -qxF 'NoDisplay=true' "$work/usr/share/applications/epic-games-launcher.desktop"
diff -u "$desktop" <(sed '/^NoDisplay=true$/d' "$work/usr/share/applications/epic-games-launcher.desktop")
[[ ! -e $work/usr/lib/systemd/system && ! -e $work/usr/lib/systemd/user-preset ]]
if find "$work" -name '*update*' -o -name '*.rpm' | grep -q .; then
  echo 'Unexpected updater or RPM in package' >&2
  exit 1
fi
# Only the two Epic EOS libraries and our tray shim may be shipped as libraries.
[[ $(find "$work/opt" "$work/usr/lib/epic-games-launcher" -type f -name '*.so*' | wc -l) == 3 ]]
for dep in gtk3 gtk4 webkit2gtk-4.1 libsoup3 glib2 dconf libayatana-appindicator libadwaita libnotify; do
  grep -qxF "depend = $dep" "$work/.PKGINFO"
done
if grep -Eq '^depend = (dnf|rpm|wine|xorg-xwayland)([<>=]|$)' "$work/.PKGINFO"; then
  echo 'Unexpected Fedora/Wine/XWayland requirement' >&2
  exit 1
fi
shim="$work/usr/lib/epic-games-launcher/tray/libayatana-appindicator3.so.1"
readelf -d "$shim" | grep -qF '[/usr/lib/libayatana-appindicator3.so.1]'
readelf -d "$shim" | grep -qF '[libegl-fedora-tray.so]'
desktop-file-validate "$work"/usr/share/applications/*.desktop
if [[ -n $original ]]; then
  cmp "$original/usr/bin/EpicGamesLauncher" "$work/opt/epic-games-launcher/bin/EpicGamesLauncher"
  cmp "$original/usr/lib/libEOSSDK-Linux-Shipping.so" "$work/opt/epic-games-launcher/lib/libEOSSDK-Linux-Shipping.so"
  diff -r "$original/usr/lib/epic-games-launcher" "$work/opt/epic-games-launcher/lib/epic-games-launcher"
fi
printf 'Package layout, dependencies, tray linkage and desktop entries: OK\n'
[[ -z $original ]] || printf 'Epic binary, EOS SDK and Tauri resources: byte-identical to AppImage\n'
