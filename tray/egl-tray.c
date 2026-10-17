// SPDX-License-Identifier: MIT
//
// Подменная libayatana-appindicator3.so.1 для Epic Games Launcher (egl-fedora).
//
// Лаунчер (Tauri, tray-icon) загружает библиотеку трея через dlopen по имени и
// берёт из неё функции через dlsym. egl-launch ставит каталог с этой библиотекой
// первым в LD_LIBRARY_PATH. Здесь определена только app_indicator_set_menu: перед
// передачей меню она добавляет пункт «Выбрать Proton для игр». Остальные функции
// dlsym находит в настоящей библиотеке: она подключена зависимостью по
// абсолютному пути (patchelf при сборке), поэтому имена не путаются.

#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <string.h>

#include <gtk/gtk.h>

#define REAL_LIBRARY "/usr/lib/libayatana-appindicator3.so.1"
#define ITEM_KEY "egl-fedora-proton-item"
#define EPIC_PROCESS "EpicGamesLauncher"
#define CHOOSER "/usr/bin/egl-proton"

typedef void (*set_menu_fn)(void *indicator, GtkMenu *menu);

void app_indicator_set_menu(void *indicator, GtkMenu *menu);

// Каталог библиотеки мог попасть в LD_LIBRARY_PATH других программ: пункт
// добавляем только в трей самого лаунчера.
static gboolean is_epic_launcher(void) {
  return strcmp(program_invocation_short_name, EPIC_PROCESS) == 0;
}

static const char *item_label(void) {
  const gchar *const *languages = g_get_language_names();
  if (languages[0] != NULL && g_str_has_prefix(languages[0], "ru")) {
    return "Выбрать Proton для игр";
  }
  return "Choose Proton for games";
}

static void open_chooser(GtkMenuItem *item, gpointer data) {
  (void)item;
  (void)data;
  gchar *argv[] = {(gchar *)CHOOSER, NULL};
  gchar **envp = g_environ_unsetenv(g_get_environ(), "LD_LIBRARY_PATH");
  GError *error = NULL;
  if (!g_spawn_async(NULL, argv, envp, G_SPAWN_DEFAULT, NULL, NULL, NULL, &error)) {
    g_warning("egl-fedora: не удалось открыть %s: %s", CHOOSER, error->message);
    g_error_free(error);
  }
  g_strfreev(envp);
}

static void add_proton_item(GtkMenu *menu) {
  if (g_object_get_data(G_OBJECT(menu), ITEM_KEY) != NULL) {
    return;
  }
  GtkWidget *item = gtk_menu_item_new_with_label(item_label());
  GtkWidget *separator = gtk_separator_menu_item_new();
  g_signal_connect(item, "activate", G_CALLBACK(open_chooser), NULL);
  gtk_menu_shell_insert(GTK_MENU_SHELL(menu), separator, 0);
  gtk_menu_shell_insert(GTK_MENU_SHELL(menu), item, 0);
  gtk_widget_show(separator);
  gtk_widget_show(item);
  g_object_set_data(G_OBJECT(menu), ITEM_KEY, item);
}

void app_indicator_set_menu(void *indicator, GtkMenu *menu) {
  static set_menu_fn real_set_menu;
  if (real_set_menu == NULL) {
    // Уже загружена как зависимость этой библиотеки.
    void *real = dlopen(REAL_LIBRARY, RTLD_LAZY | RTLD_NOLOAD);
    if (real != NULL) {
      real_set_menu = (set_menu_fn)dlsym(real, "app_indicator_set_menu");
    }
    if (real_set_menu == NULL) {
      g_warning("egl-fedora: не найдена app_indicator_set_menu в %s", REAL_LIBRARY);
      return;
    }
  }
  if (menu != NULL && GTK_IS_MENU(menu) && is_epic_launcher()) {
    add_proton_item(menu);
  }
  real_set_menu(indicator, menu);
}
