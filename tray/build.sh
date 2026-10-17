#!/usr/bin/env bash
# Собирает подменную libayatana-appindicator3.so.1 (см. egl-tray.c).
# Использование: tray/build.sh <каталог>
# CC, CFLAGS and LDFLAGS are supplied by makepkg.

set -euo pipefail

out_dir=${1:?Использование: tray/build.sh <каталог>}
real=/usr/lib/libayatana-appindicator3.so.1
src="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/egl-tray.c"
target="$out_dir/libayatana-appindicator3.so.1"

[[ -e $real ]] || { echo "tray/build.sh: missing $real (install libayatana-appindicator)" >&2; exit 1; }
mkdir -p "$out_dir"
read -ra cflags <<<"${CFLAGS:--O2 -g}"
read -ra ldflags <<<"${LDFLAGS:-}"
read -ra gtk_cflags <<<"$(pkg-config --cflags gtk+-3.0)"
read -ra gtk_libs <<<"$(pkg-config --libs gtk+-3.0)"
"${CC:-gcc}" "${cflags[@]}" -fPIC -shared -Wall -Wextra "${gtk_cflags[@]}" "$src" \
  -o "$target" -Wl,-soname,libegl-fedora-tray.so -Wl,--no-as-needed "$real" \
  "${ldflags[@]}" "${gtk_libs[@]}"
# Зависимость на настоящую библиотеку по абсолютному пути: по имени dlopen
# нашёл бы эту же подменную библиотеку.
patchelf --replace-needed libayatana-appindicator3.so.1 "$real" "$target"
