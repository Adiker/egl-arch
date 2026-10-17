#!/usr/bin/env bash
# Test the installed wrapper's contract without launching Epic or touching HOME.
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cat >"$work/bin/systemctl" <<'SH'
#!/bin/sh
exit 1
SH
cat >"$work/hook" <<'SH'
#!/bin/sh
exit 1
SH
cat >"$work/launcher" <<'SH'
#!/bin/sh
if [ "${1:-}" = check-appimage ]; then
  [ -z "${APPIMAGE+x}${APPDIR+x}${GSETTINGS_SCHEMA_DIR+x}${GIO_EXTRA_MODULES+x}" ] || exit 99
fi
printf '%s\n' "$GDK_BACKEND" "$LD_LIBRARY_PATH" "${DISPLAY:-}" "$@"
exit 37
SH
chmod 755 "$work/bin/systemctl" "$work/hook" "$work/launcher"
sed -e "s|/usr/lib/epic-games-launcher/egl-proton-hook|$work/hook|" \
  -e "s|/opt/epic-games-launcher/bin/EpicGamesLauncher|$work/launcher|" \
  "$repo_root/libexec/egl-launch" >"$work/wrapper"
chmod 755 "$work/wrapper"
run_wrapper() {
  local status=0
  env -u GDK_BACKEND PATH="$work/bin:$PATH" DISPLAY=:test \
    LD_LIBRARY_PATH=/foreign/appimage "$work/wrapper" 'com.epicgames.launcher://test?a=1&b=2' 'argument with spaces' >"$work/result" || status=$?
  [[ $status == 37 ]]
}
run_wrapper
expected=$(printf '%s\n' 'wayland,x11' '/usr/lib/epic-games-launcher/tray' ':test' \
  'com.epicgames.launcher://test?a=1&b=2' 'argument with spaces')
[[ $(cat "$work/result") == "$expected" ]]
env PATH="$work/bin:$PATH" GDK_BACKEND=x11 "$work/wrapper" >"$work/override" || [[ $? == 37 ]]
[[ $(head -n1 "$work/override") == x11 ]]
status=0
env PATH="$work/bin:$PATH" APPIMAGE=/foreign/AppImage APPDIR=/foreign \
  GSETTINGS_SCHEMA_DIR=/foreign/schemas GIO_EXTRA_MODULES=/foreign/gio \
  "$work/wrapper" check-appimage >"$work/appimage" || status=$?
[[ $status == 37 ]]
echo 'ok: Wayland preference, X11 override/DISPLAY, URI/argv, AppImage isolation, hook failure and exit status'
