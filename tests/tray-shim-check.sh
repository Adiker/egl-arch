#!/usr/bin/env bash
# Проверка подменной библиотеки трея на живом рабочем столе (нужны Wayland или X11).
# Собирает библиотеку и тестовую программу, которая грузит трей как Tauri
# (dlopen по имени, dlsym), и смотрит меню. В %check не запускается.
# Запуск: tests/tray-shim-check.sh

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

"$repo_root/tray/build.sh" "$work/tray"

cat >"$work/probe.c" <<'EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <gtk/gtk.h>

typedef void *(*new_fn)(const char *, const char *, int);
typedef void (*status_fn)(void *, int);
typedef void (*menu_fn)(void *, GtkMenu *);

int main(int argc, char **argv) {
  gtk_init(&argc, &argv);
  void *lib = dlopen("libayatana-appindicator3.so.1", RTLD_LAZY | RTLD_LOCAL);
  if (lib == NULL) {
    fprintf(stderr, "dlopen: %s\n", dlerror());
    return 2;
  }
  new_fn indicator_new = (new_fn)dlsym(lib, "app_indicator_new");
  status_fn set_status = (status_fn)dlsym(lib, "app_indicator_set_status");
  menu_fn set_menu = (menu_fn)dlsym(lib, "app_indicator_set_menu");
  if (indicator_new == NULL || set_status == NULL || set_menu == NULL) {
    fprintf(stderr, "dlsym: %s\n", dlerror());
    return 3;
  }
  Dl_info info;
  dladdr((void *)set_menu, &info);
  printf("set_menu from %s\n", info.dli_fname);

  GtkWidget *menu = gtk_menu_new();
  const char *labels[] = {"Магазин", "Закрыть"};
  for (int i = 0; i < 2; i++) {
    GtkWidget *item = gtk_menu_item_new_with_label(labels[i]);
    gtk_widget_show(item);
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), item);
  }
  void *indicator = indicator_new("egl-fedora-tray-check", "applications-games", 0);
  set_status(indicator, 1);
  set_menu(indicator, GTK_MENU(menu));
  set_menu(indicator, GTK_MENU(menu));

  GList *children = gtk_container_get_children(GTK_CONTAINER(menu));
  for (GList *l = children; l != NULL; l = l->next) {
    if (GTK_IS_SEPARATOR_MENU_ITEM(l->data)) {
      printf("item: ---\n");
    } else {
      printf("item: %s\n", gtk_menu_item_get_label(GTK_MENU_ITEM(l->data)));
    }
  }
  g_list_free(children);
  return 0;
}
EOF
read -ra gtk_flags <<<"$(pkg-config --cflags --libs gtk+-3.0)"
mkdir -p "$work/bin"
gcc -O2 -Wall -Wextra "$work/probe.c" -o "$work/bin/EpicGamesLauncher" "${gtk_flags[@]}" -ldl
cp "$work/bin/EpicGamesLauncher" "$work/bin/other-app"

failures=0
check() {
  if [[ $2 == "$3" ]]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n     ожидалось: %s\n     получено:  %s\n' "$1" "$2" "$3"
    failures=$((failures + 1))
  fi
}

epic=$(LANG=ru_RU.UTF-8 LANGUAGE=ru LD_LIBRARY_PATH="$work/tray" "$work/bin/EpicGamesLauncher" 2>/dev/null)
check "dlopen по имени берёт подменную библиотеку" "set_menu from $work/tray/libayatana-appindicator3.so.1" "$(sed -n 1p <<<"$epic")"
check "пункт добавлен первым и один раз" "$(printf 'item: Выбрать Proton для игр\nitem: ---\nitem: Магазин\nitem: Закрыть')" "$(sed -n '2,$p' <<<"$epic")"

other=$(LANG=ru_RU.UTF-8 LANGUAGE=ru LD_LIBRARY_PATH="$work/tray" "$work/bin/other-app" 2>/dev/null)
check "в чужой программе пункта нет" "$(printf 'item: Магазин\nitem: Закрыть')" "$(sed -n '2,$p' <<<"$other")"

english=$(LANG=en_US.UTF-8 LANGUAGE=en LD_LIBRARY_PATH="$work/tray" "$work/bin/EpicGamesLauncher" 2>/dev/null)
check "английская подпись" "item: Choose Proton for games" "$(sed -n 2p <<<"$english")"

plain=$(LANG=ru_RU.UTF-8 "$work/bin/EpicGamesLauncher" 2>/dev/null)
plain_lib=$(sed -n 's/^set_menu from //p' <<<"$plain")
check "без LD_LIBRARY_PATH грузится системная библиотека" "/usr/lib64/libayatana-appindicator3.so.1.0.0" "$(readlink -f "$plain_lib")"

if ((failures)); then
  echo "Провалено проверок: $failures" >&2
  exit 1
fi
echo "Все проверки пройдены."
