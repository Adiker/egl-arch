#!/usr/bin/env bash
# Скачивает официальный AppImage Epic Games Launcher текущей стабильной версии.
#
# Использование: fetch-appimage.sh <каталог>
# Результат:
#   <каталог>/EpicGamesLauncher-x86_64.AppImage
#   <каталог>/epic-version.env  (EPIC_VERSION=0.96.1, EPIC_GITREV=e3e236d)
#
# Версию берём из stable-target.json и сверяем с тем, куда ведёт официальная
# ссылка на скачивание. Если Epic как раз выкатывает новую версию и они
# расходятся, скрипт падает: нужно повторить позже.

set -euo pipefail

out_dir=${1:?Использование: fetch-appimage.sh <каталог>}
cdn=https://content-download-egs.distro.on.epicgames.com/Builds/EGLv2
stable_url="$cdn/stable-target.json"
download_url=https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncher-x86_64.AppImage
file=EpicGamesLauncher-x86_64.AppImage

curl_https() {
  curl --fail --silent --show-error --proto '=https' --proto-redir '=https' \
    --retry 3 --connect-timeout 15 "$@"
}

full_version=$(curl_https --max-time 60 "$stable_url" | jq -er '.version')
if [[ ! $full_version =~ ^([0-9]+\.[0-9]+\.[0-9]+)\+g([0-9a-f]{7,40})$ ]]; then
  echo "fetch-appimage: неожиданная версия в stable-target.json: $full_version" >&2
  exit 1
fi
version=${BASH_REMATCH[1]}
gitrev=${BASH_REMATCH[2]}
versioned_url="$cdn/$version%2Bg$gitrev/Linux/$file"

redirect=$(curl_https --max-time 60 --head --output /dev/null --write-out '%{redirect_url}' "$download_url")
if [[ ${redirect%%\?*} != "$versioned_url" ]]; then
  echo "fetch-appimage: stable-target.json ($full_version) и ссылка на скачивание (${redirect%%\?*}) расходятся" >&2
  exit 1
fi

mkdir -p "$out_dir"
curl_https --location --max-time 1800 --output "$out_dir/$file.part" "$versioned_url"
# Строка версии лежит в бинарнике внутри сжатого squashfs, её сверяет %prep в spec.
# Здесь проверяем только, что пришёл ELF (рантайм AppImage).
if [[ $(head -c 4 "$out_dir/$file.part" | od -An -tx1 | tr -d ' \n') != 7f454c46 ]]; then
  echo "fetch-appimage: скачанный файл не AppImage" >&2
  exit 1
fi
mv -f "$out_dir/$file.part" "$out_dir/$file"
chmod 0644 "$out_dir/$file"
printf 'EPIC_VERSION=%s\nEPIC_GITREV=%s\n' "$version" "$gitrev" >"$out_dir/epic-version.env"
echo "Скачан Epic Games Launcher $full_version: $out_dir/$file"
