#!/usr/bin/env bash
# Собирает архив исходников egl-fedora с vendored crates для офлайн-сборки RPM.
#
# Использование: create-source-archive.sh <каталог> <ревизия упаковки>
# Результат: <каталог>/egl-fedora-<ревизия>.tar.xz
# В архив идут отслеживаемые и новые неигнорируемые файлы рабочего дерева,
# поэтому локальная сборка не требует коммита.

set -euo pipefail

out_dir=${1:?Использование: create-source-archive.sh <каталог> <ревизия>}
pkgrel=${2:?Использование: create-source-archive.sh <каталог> <ревизия>}
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
name="egl-fedora-$pkgrel"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/$name" "$out_dir"
(
  cd "$repo_root"
  git ls-files -z --cached --others --exclude-standard |
    while IFS= read -r -d '' path; do
      [[ -e $path ]] && printf '%s\0' "$path"
    done |
    tar --null --files-from=- --create --file=-
) | tar --extract --file=- --directory="$stage/$name"

(
  cd "$stage/$name/proton-gui"
  cargo vendor --locked --versioned-dirs --quiet vendor >/dev/null
  mkdir -p .cargo
  cat >.cargo/config.toml <<'EOF'
[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "vendor"
EOF
)

tar --create --xz --file="$out_dir/$name.tar.xz" \
  --sort=name --owner=0 --group=0 --numeric-owner --mtime='@0' \
  --directory="$stage" "$name"
echo "Архив исходников: $out_dir/$name.tar.xz"
