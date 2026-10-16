#!/usr/bin/env bash
# Собирает RPM epic-games-launcher. Используется и в CI, и локально.
#
# Использование: build-rpm.sh <каталог сборки>
# Если в <каталог>/SOURCES уже есть AppImage и epic-version.env (от
# fetch-appimage.sh), повторно он не скачивается.
# Результат: <каталог>/RPMS/x86_64/epic-games-launcher-*.rpm

set -euo pipefail

topdir=$(realpath -m "${1:?Использование: build-rpm.sh <каталог сборки>}")
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
pkgrel=$(tr -d '\r\n' <"$repo_root/packaging/RELEASE")
[[ $pkgrel =~ ^[1-9][0-9]*$ ]] || { echo "build-rpm: packaging/RELEASE должен быть числом" >&2; exit 1; }

mkdir -p "$topdir"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
sources="$topdir/SOURCES"
if [[ ! -f $sources/EpicGamesLauncher-x86_64.AppImage || ! -f $sources/epic-version.env ]]; then
  "$repo_root/packaging/scripts/fetch-appimage.sh" "$sources"
fi
# shellcheck source=/dev/null
source "$sources/epic-version.env"
"$repo_root/packaging/scripts/create-source-archive.sh" "$sources" "$pkgrel"

rpmbuild -bb \
  --define "_topdir $topdir" \
  --define "epic_version $EPIC_VERSION" \
  --define "epic_gitrev $EPIC_GITREV" \
  --define "pkgrel $pkgrel" \
  "$repo_root/packaging/rpm/epic-games-launcher.spec"
