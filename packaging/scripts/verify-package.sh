#!/usr/bin/env bash
# Проверяет собранный RPM: состав файлов, зависимости, rpmlint.
# Использование: verify-package.sh <файл.rpm>

set -euo pipefail

rpm_file=$(realpath "${1:?Использование: verify-package.sh <файл.rpm>}")
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
failures=0

fail() {
  echo "verify-package: $*" >&2
  failures=$((failures + 1))
}

files=$(rpm -qlp "$rpm_file")
for path in \
  /usr/bin/EpicGamesLauncher \
  /usr/bin/egl-proton \
  /usr/lib/libEOSSDK-Linux-Shipping.so \
  /usr/lib/epic-games-launcher/libEOSSDK-Linux-Shipping.so \
  /usr/lib/epic-games-launcher/resources/ThirdPartyNotices.txt \
  /usr/libexec/egl-fedora/egl-launch \
  /usr/libexec/egl-fedora/egl-proton-hook \
  /usr/libexec/egl-fedora/egl-proton-router \
  /usr/libexec/egl-fedora/egl-update \
  /usr/lib/systemd/system/egl-fedora-update.service \
  /usr/lib/systemd/system/egl-fedora-update.timer \
  /usr/lib/systemd/user/egl-fedora-proton-hook.path \
  /usr/lib/systemd/user/egl-fedora-proton-hook.service \
  /usr/lib/systemd/system-preset/80-egl-fedora.preset \
  /usr/lib/systemd/user-preset/80-egl-fedora.preset \
  /usr/share/applications/epic-games-launcher.desktop \
  /usr/share/applications/io.github.dxvsi.EglProton.desktop \
  /usr/share/icons/hicolor/128x128/apps/EpicGamesLauncher.png; do
  grep -qxF "$path" <<<"$files" || fail "нет файла $path"
done

requires=$(rpm -qp --requires "$rpm_file")
grep -q '^libEOSSDK' <<<"$requires" && fail "пакет требует libEOSSDK извне"
for dep in 'libwebkit2gtk-4.1.so.0()(64bit)' 'libadwaita-1.so.0()(64bit)' '/usr/bin/dnf' curl; do
  grep -qxF "$dep" <<<"$requires" || fail "нет зависимости $dep"
done
grep -q '^libEOSSDK' <<<"$(rpm -qp --provides "$rpm_file")" && fail "пакет объявляет libEOSSDK как общую библиотеку"

# Адрес релизов подставлен при сборке.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
(cd "$work" && rpm2cpio "$rpm_file" | cpio -idm --quiet ./usr/libexec/egl-fedora/egl-update ./usr/lib/systemd/system/egl-fedora-update.service)
grep -rq '@UPDATE_REPO@' "$work" && fail "не подставлен @UPDATE_REPO@"

rpmlint -r "$repo_root/packaging/rpm/epic-games-launcher.rpmlintrc" "$rpm_file" || fail "rpmlint нашёл ошибки"

if ((failures)); then
  echo "verify-package: ошибок: $failures" >&2
  exit 1
fi
echo "verify-package: $(basename "$rpm_file") в порядке"
