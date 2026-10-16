#!/usr/bin/env bash
# Тесты egl-proton-hook и egl-proton-router на поддельном HOME с ненастоящими Proton.
# Запуск: tests/proton-hook-test.sh

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
hook="$repo_root/libexec/egl-proton-hook"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export HOME="$work/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
unset UMU_ID STORE WAYLAND_DISPLAY DISPLAY STEAM_COMPAT_INSTALL_PATH
# Уведомление на английском, русский проверяется отдельно.
unset LANGUAGE LC_ALL LC_MESSAGES
export LANG=C.UTF-8
# Поддельные notify-send и egl-proton для проверки подсказки.
fake_bin="$work/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/notify-send" <<NOTIFY
#!/bin/sh
for arg; do
  case \$arg in --*) ;; *) printf '%s\n' "\$arg" >>'$work/notify.log'; break ;; esac
done
echo choose
NOTIFY
cat >"$fake_bin/egl-proton" <<OPEN
#!/bin/sh
: >'$work/opened'
OPEN
chmod 0755 "$fake_bin/notify-send" "$fake_bin/egl-proton"
export PATH="$fake_bin:$PATH"
runtime_root="$HOME/.local/share/com.epicgames.eglv2/compat/runtime"
app=525aa0efd70f4399b9f64bcd2a5b38c7
export STEAM_COMPAT_DATA_PATH="$HOME/.local/share/com.epicgames.eglv2/compat/compatdata/$app"
conf="$XDG_CONFIG_HOME/egl-fedora/proton.conf"
result="$work/result"
failures=0

check() {
  local name=$1 expected=$2 actual=$3
  if [[ $expected == "$actual" ]]; then
    printf 'ok   %s\n' "$name"
  else
    printf 'FAIL %s\n     ожидалось: %s\n     получено:  %s\n' "$name" "$expected" "$actual"
    failures=$((failures + 1))
  fi
}

# Поддельный Proton пишет, кто он, аргументы и UMU_ID/STORE.
fake_proton() {
  local dir=$1 name=$2
  mkdir -p "$dir"
  cat >"$dir/proton" <<EOF
#!/bin/sh
printf '%s|%s|%s|%s\n' '$name' "\$*" "\${UMU_ID:-}" "\${STORE:-}" > '$result'
EOF
  chmod 0755 "$dir/proton"
}

run_game() {
  rm -f "$result"
  "$runtime_root/GE-Proton10-34/proton" waitforexitandrun 'C:\game.exe' -arg
  cat "$result"
}

# Epic runtime и два сторонних Proton.
fake_proton "$runtime_root/GE-Proton10-34" epic-ge
echo "1 GE-Proton10-34" >"$runtime_root/GE-Proton10-34/version"
dw="$work/protons/DW-Proton Latest"
fake_proton "$dw" dw
mkdir -p "$dw/protonfixes"
printf 'Zenless Zone Zero,egs,%s,umu-825cd0b5286c404289d456d47561cc1a,,,\n' "$app" >"$dw/protonfixes/umu-database.csv"
plain="$work/protons/Proton 10.0"
fake_proton "$plain" valve

# Незаконченная распаковка: нет version.
mkdir -p "$runtime_root/GE-Proton11-1"
touch "$runtime_root/GE-Proton11-1/proton"

"$hook" apply >/dev/null
check "status после apply" "$(printf 'GE-Proton10-34\tactive\nGE-Proton11-1\tincomplete')" "$("$hook" status)"
check "оригинал сохранён как proton.epic" "yes" "$(grep -q epic-ge "$runtime_root/GE-Proton10-34/proton.epic" && echo yes)"

check "без настройки запускается Proton от Epic" "epic-ge|waitforexitandrun C:\\game.exe -arg||" "$(run_game)"

mkdir -p "$(dirname "$conf")"
printf 'default=%s\n' "$dw" >"$conf"
check "default=DW, UMU_ID из базы DW" \
  "dw|waitforexitandrun C:\\game.exe -arg|umu-825cd0b5286c404289d456d47561cc1a|egs" "$(run_game)"

printf 'default=%s\ngame.%s=%s\n' "$dw" "$app" "$plain" >"$conf"
check "настройка игры важнее default, без protonfixes окружение не трогаем" \
  "valve|waitforexitandrun C:\\game.exe -arg||" "$(run_game)"

printf 'default=%s\ngame.%s=epic\n' "$dw" "$app" >"$conf"
check "game=epic" "epic-ge|waitforexitandrun C:\\game.exe -arg||" "$(run_game)"

printf 'default=%s\ngame.%s=default\n' "$dw" "$app" >"$conf"
check "game=default берёт default" \
  "dw|waitforexitandrun C:\\game.exe -arg|umu-825cd0b5286c404289d456d47561cc1a|egs" "$(run_game)"

printf 'default=/nonexistent/proton\n' >"$conf"
check "пропавший Proton: откат на Epic" "epic-ge|waitforexitandrun C:\\game.exe -arg||" "$(run_game)"
check "откат записан в лог" "yes" "$(grep -q '/nonexistent/proton/proton not found' "$XDG_STATE_HOME/egl-fedora/proton.log" && echo yes)"

# Epic заново распаковал Proton поверх заглушки.
fake_proton "$runtime_root/GE-Proton10-34" epic-ge-new
"$hook" apply >/dev/null
check "новый оригинал Epic подхвачен" "yes" "$(grep -q epic-ge-new "$runtime_root/GE-Proton10-34/proton.epic" && echo yes)"
rm -f "$conf"
check "повторный apply не ломает запуск" "epic-ge-new|waitforexitandrun C:\\game.exe -arg||" "$(run_game)"

# Пакет удалён: роутера нет, заглушка запускает proton.epic.
sed -i "s|^router='.*'$|router='$work/missing-router'|" "$runtime_root/GE-Proton10-34/proton"
check "без роутера запускается proton.epic" "epic-ge-new|waitforexitandrun C:\\game.exe -arg||" "$(run_game)"
"$hook" apply >/dev/null
check "apply восстанавливает путь роутера" "yes" "$(grep -qF "router='$repo_root/libexec/egl-proton-router'" "$runtime_root/GE-Proton10-34/proton" && echo yes)"

# Перенос обёртки epic-dw-proton.
legacy="$runtime_root/GE-Proton9-1"
fake_proton "$legacy" legacy-wrapper
printf '# epic-dw-proton wrapper\n' >>"$legacy/proton"
fake_proton "$work/legacy-orig" epic-ge9
mv "$work/legacy-orig/proton" "$legacy/proton.ge-orig"
echo "1 GE-Proton9-1" >"$legacy/version"
"$hook" apply >/dev/null
check "обёртка epic-dw-proton перенесена" "yes" "$(grep -q epic-ge9 "$legacy/proton.epic" && [[ ! -e $legacy/proton.ge-orig ]] && echo yes)"

# --wait дожидается распаковки.
(sleep 2; echo "1 GE-Proton11-1" >"$runtime_root/GE-Proton11-1/version") &
timeout 60 "$hook" apply --wait >/dev/null
wait
check "--wait дождался runtime" "$(printf 'GE-Proton10-34\tactive\nGE-Proton11-1\tactive\nGE-Proton9-1\tactive')" "$("$hook" status)"

# Подсказка о выборе Proton: один раз на игру и только без своего выбора.
wait_for_file() {
  local tries=50
  while ((tries--)); do
    [[ -e $1 ]] && return 0
    sleep 0.1
  done
  return 1
}
export WAYLAND_DISPLAY=test-display
export STEAM_COMPAT_INSTALL_PATH=/games/ZenlessZoneZero
rm -f "$conf" "$work/notify.log" "$work/opened"
rm -rf "$XDG_STATE_HOME/egl-fedora/hint-shown"
run_game >/dev/null
wait_for_file "$work/opened" || true
check "подсказка при первом запуске" "ZenlessZoneZero is running on Epic's GE-Proton" "$(cat "$work/notify.log" 2>/dev/null)"
check "кнопка в подсказке открывает окно" "yes" "$([[ -e $work/opened ]] && echo yes)"
rm -f "$work/notify.log"
run_game >/dev/null
sleep 1
check "второй запуск без подсказки" "" "$(cat "$work/notify.log" 2>/dev/null)"
printf 'default=%s\n' "$dw" >"$conf"
rm -rf "$XDG_STATE_HOME/egl-fedora/hint-shown"
(export LANG=ru_RU.UTF-8; run_game >/dev/null)
wait_for_file "$work/notify.log" || true
check "подсказка по-русски называет Proton по умолчанию" "ZenlessZoneZero запущена через DW-Proton Latest" "$(cat "$work/notify.log" 2>/dev/null)"
rm -f "$work/notify.log"
printf 'game.%s=%s\n' "$app" "$dw" >"$conf"
rm -rf "$XDG_STATE_HOME/egl-fedora/hint-shown"
run_game >/dev/null
sleep 1
check "свой Proton у игры: без подсказки" "" "$(cat "$work/notify.log" 2>/dev/null)"
unset WAYLAND_DISPLAY STEAM_COMPAT_INSTALL_PATH

if ((failures)); then
  echo "Провалено проверок: $failures" >&2
  exit 1
fi
echo "Все проверки пройдены."
