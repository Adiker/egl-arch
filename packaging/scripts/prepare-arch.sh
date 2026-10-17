#!/usr/bin/env bash
# Create a self-contained makepkg directory. --refresh is a maintainer action:
# update the checked-in port-source checksum and .SRCINFO after source edits.
# shellcheck disable=SC2154 # pkgver, pkgrel and sha256sums are loaded from PKGBUILD.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
refresh=0
if [[ ${1:-} == --refresh ]]; then
  refresh=1
  shift
fi
out_dir=$(realpath -m "${1:-$repo_root/build/arch}")
[[ $# -le 1 ]] || { echo 'Usage: prepare-arch.sh [--refresh] [directory]' >&2; exit 2; }
[[ $out_dir != "$repo_root/packaging/arch" ]] || { echo 'Use a separate build directory.' >&2; exit 2; }
# Trusted packaging metadata and function definitions; no build is run here.
export CARCH=x86_64
# shellcheck source=/dev/null
source "$repo_root/packaging/arch/PKGBUILD"
archive="egl-arch-sources-${pkgver}-${pkgrel}.tar.xz"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/egl-arch" "$out_dir"
(
  cd "$repo_root"
  tar -cf - LICENSE README.md libexec tray proton-gui/src \
    proton-gui/Cargo.toml proton-gui/Cargo.lock data tests docs/arch-port.md
) | tar -xf - -C "$stage/egl-arch"
# Git does not retain empty directories (e.g. ones left after removing Fedora
# units). Do not let them change the snapshot between this tree and a checkout.
find "$stage/egl-arch" -depth -type d -empty -delete
LC_ALL=C tar --sort=name --format=gnu --mtime='@0' --owner=0 --group=0 \
  --numeric-owner --mode='u+rwX,go+rX,go-w' -cJf "$out_dir/$archive" \
  -C "$stage" egl-arch
actual=$(sha256sum "$out_dir/$archive")
actual=${actual%% *}
if ((refresh)); then
  sed -i -E "s/'[0-9a-f]{64}' # port sources/'$actual' # port sources/" \
    "$repo_root/packaging/arch/PKGBUILD"
  (cd "$repo_root/packaging/arch"; makepkg --printsrcinfo) >"$stage/.SRCINFO"
  install -m644 "$stage/.SRCINFO" "$repo_root/packaging/arch/.SRCINFO"
elif [[ $actual != "${sha256sums[1]}" ]]; then
  echo 'Port sources differ from PKGBUILD. Maintainers: run prepare-arch.sh --refresh and review the diff.' >&2
  exit 1
fi
install -m644 "$repo_root/packaging/arch/PKGBUILD" "$repo_root/packaging/arch/.SRCINFO" "$out_dir/"
printf 'Prepared %s\nNext: cd %q && makepkg --verifysource && makepkg\n' "$out_dir" "$out_dir"
