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
printf 'portal=%s\n' "${GTK_USE_PORTAL-<unset>}"
exit 37
SH
chmod 755 "$work/bin/systemctl" "$work/hook" "$work/launcher"
sed -e "s|/usr/lib/epic-games-launcher/egl-proton-hook|$work/hook|" \
  -e "s|/opt/epic-games-launcher/bin/EpicGamesLauncher|$work/launcher|" \
  "$repo_root/libexec/egl-launch" >"$work/wrapper"
chmod 755 "$work/wrapper"
run_wrapper() {
  local status=0
  env -u GDK_BACKEND -u GTK_USE_PORTAL XDG_CURRENT_DESKTOP=GNOME PATH="$work/bin:$PATH" DISPLAY=:test \
    LD_LIBRARY_PATH=/foreign/appimage "$work/wrapper" 'com.epicgames.launcher://test?a=1&b=2' 'argument with spaces' >"$work/result" || status=$?
  [[ $status == 37 ]]
}
run_wrapper
expected=$(printf '%s\n' 'wayland,x11' '/usr/lib/epic-games-launcher/tray' ':test' \
  'com.epicgames.launcher://test?a=1&b=2' 'argument with spaces' 'portal=<unset>')
[[ $(cat "$work/result") == "$expected" ]]
env PATH="$work/bin:$PATH" GDK_BACKEND=x11 "$work/wrapper" >"$work/override" || [[ $? == 37 ]]
[[ $(head -n1 "$work/override") == x11 ]]
status=0
env PATH="$work/bin:$PATH" APPIMAGE=/foreign/AppImage APPDIR=/foreign \
  GSETTINGS_SCHEMA_DIR=/foreign/schemas GIO_EXTRA_MODULES=/foreign/gio \
  "$work/wrapper" check-appimage >"$work/appimage" || status=$?
[[ $status == 37 ]]
for desktop in KDE GNOME:KDE:Other; do
  env -u GTK_USE_PORTAL PATH="$work/bin:$PATH" XDG_CURRENT_DESKTOP="$desktop" \
    "$work/wrapper" >"$work/portal" || [[ $? == 37 ]]
  [[ $(tail -n1 "$work/portal") == portal=1 ]]
done
for value in 0 ''; do
  env PATH="$work/bin:$PATH" XDG_CURRENT_DESKTOP=KDE GTK_USE_PORTAL="$value" \
    "$work/wrapper" >"$work/portal" || [[ $? == 37 ]]
  [[ $(tail -n1 "$work/portal") == "portal=$value" ]]
done
env -u GTK_USE_PORTAL PATH="$work/bin:$PATH" XDG_CURRENT_DESKTOP=NOTKDE \
  "$work/wrapper" >"$work/portal" || [[ $? == 37 ]]
[[ $(tail -n1 "$work/portal") == 'portal=<unset>' ]]
echo 'ok: Wayland, arguments, AppImage isolation, portal selection and overrides, hook failure and exit status'
