//! «Epic Games: выбор Proton»: выбор Proton для игр Epic Games Launcher.
//!
//! Окно пишет proton.conf, а запуск выбранного Proton делает egl-proton-router.

mod config;
mod epic;
mod protons;

use std::cell::RefCell;
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::rc::Rc;

use adw::prelude::*;
use gtk::{gio, glib};

use config::{DEFAULT, EPIC, ProtonConfig};
use epic::{Game, HookState};
use protons::ProtonInstall;

const APP_ID: &str = "io.github.dxvsi.EglProton";
const PROTONPLUS_DESKTOP_ID: &str = "com.vysp3r.ProtonPlus.desktop";
const PROTONPLUS_STORE_URI: &str = "appstream://com.vysp3r.ProtonPlus";

fn main() -> glib::ExitCode {
    if std::env::args().nth(1).as_deref() == Some("--list") {
        print_list();
        return glib::ExitCode::SUCCESS;
    }
    let app = adw::Application::builder().application_id(APP_ID).build();
    app.connect_activate(build_window);
    app.run()
}

/// `egl-proton --list`: то же, что видно в окне, текстом (для диагностики).
fn print_list() {
    use std::fmt::Write as _;
    use std::io::Write as _;

    let home = glib::home_dir();
    let status = match epic::apply_hook() {
        HookState::Active(runtimes) => format!("работает ({})", runtimes.join(", ")),
        HookState::NoRuntime => "Epic ещё не скачал Proton".to_owned(),
        HookState::Failed(error) => format!("не подключён: {error}"),
    };
    let config = ProtonConfig::load(&ProtonConfig::path()).unwrap_or_default();
    let mut text = String::new();
    let _ = writeln!(text, "Выбор Proton: {status}");
    let _ = writeln!(text, "По умолчанию: {}", config.default);
    let _ = writeln!(text, "Найденные Proton:");
    for install in protons::discover(&home) {
        let _ = writeln!(text, "  {}\t{}", install.label(), install.dir.display());
    }
    let _ = writeln!(text, "Игры:");
    for game in epic::installed_games(&home) {
        let choice = config
            .games
            .get(&game.app_name)
            .map_or(DEFAULT, String::as_str);
        let _ = writeln!(text, "  {}\t{}\t{}", game.title, game.app_name, choice);
    }
    // Оборванный вывод (например, `| head`) не ошибка.
    let _ = std::io::stdout().write_all(text.as_bytes());
}

struct State {
    config_path: PathBuf,
    config: ProtonConfig,
    /// app_name -> название игры, для комментариев в proton.conf.
    titles: BTreeMap<String, String>,
}

/// Вариант выпадающего списка: значение для proton.conf, название и версия.
struct Choice {
    value: String,
    title: String,
    detail: Option<String>,
}

impl Choice {
    fn new(value: &str, title: &str, detail: Option<&str>) -> Self {
        Self {
            value: value.to_owned(),
            title: title.to_owned(),
            detail: detail.map(str::to_owned),
        }
    }

    /// Одной строкой, для подзаголовка строки с выбранным Proton.
    fn label(&self) -> String {
        match &self.detail {
            Some(detail) => format!("{} ({detail})", self.title),
            None => self.title.clone(),
        }
    }
}

fn proton_choices(installs: &[ProtonInstall], epic_detail: Option<&str>) -> Vec<Choice> {
    let mut choices = vec![Choice::new(EPIC, "GE-Proton от Epic", epic_detail)];
    choices.extend(installs.iter().map(|install| {
        let detail = install
            .version
            .as_deref()
            .filter(|version| *version != install.name);
        Choice::new(&install.dir.to_string_lossy(), &install.name, detail)
    }));
    choices
}

/// Индекс текущего значения. Если выбранного Proton больше нет, он остаётся в списке с пометкой.
fn select_index(choices: &mut Vec<Choice>, value: &str) -> u32 {
    let index = match choices.iter().position(|choice| choice.value == value) {
        Some(index) => index,
        None => {
            choices.push(Choice::new(value, value, Some("не найден")));
            choices.len() - 1
        }
    };
    u32::try_from(index).unwrap_or(0)
}

/// Пункт списка в две строки (название и версия) без обрезки текста, с галочкой у выбранного.
fn list_factory(choices: &[Choice]) -> gtk::SignalListItemFactory {
    let lines: Rc<Vec<(String, Option<String>)>> = Rc::new(
        choices
            .iter()
            .map(|choice| (choice.title.clone(), choice.detail.clone()))
            .collect(),
    );
    let factory = gtk::SignalListItemFactory::new();
    factory.connect_setup(|_, object| {
        let Some(item) = object.downcast_ref::<gtk::ListItem>() else {
            return;
        };
        let title = gtk::Label::builder()
            .xalign(0.0)
            .wrap(true)
            .max_width_chars(44)
            .build();
        let detail = gtk::Label::builder()
            .xalign(0.0)
            .wrap(true)
            .max_width_chars(44)
            .css_classes(["dim-label", "caption"])
            .build();
        let column = gtk::Box::builder()
            .orientation(gtk::Orientation::Vertical)
            .spacing(2)
            .hexpand(true)
            .build();
        column.append(&title);
        column.append(&detail);
        let check = gtk::Image::from_icon_name("object-select-symbolic");
        item.property_expression("selected")
            .bind(&check, "visible", gtk::Widget::NONE);
        let line = gtk::Box::new(gtk::Orientation::Horizontal, 12);
        line.append(&column);
        line.append(&check);
        item.set_child(Some(&line));
    });
    factory.connect_bind(move |_, object| {
        let Some(item) = object.downcast_ref::<gtk::ListItem>() else {
            return;
        };
        let Some(column) = item
            .child()
            .and_then(|line| line.first_child())
            .and_downcast::<gtk::Box>()
        else {
            return;
        };
        let (Some(title), Some(detail)) = (
            column.first_child().and_downcast::<gtk::Label>(),
            column.last_child().and_downcast::<gtk::Label>(),
        ) else {
            return;
        };
        let Some((text, extra)) = usize::try_from(item.position())
            .ok()
            .and_then(|index| lines.get(index))
        else {
            return;
        };
        title.set_text(text);
        detail.set_text(extra.as_deref().unwrap_or_default());
        detail.set_visible(extra.is_some());
    });
    factory
}

/// Выбранный Proton показывается подзаголовком: справа длинные названия обрезаются.
fn combo_row(title: &str, choices: &[Choice], selected: u32) -> adw::ComboRow {
    let labels: Vec<String> = choices.iter().map(Choice::label).collect();
    let labels: Vec<&str> = labels.iter().map(String::as_str).collect();
    adw::ComboRow::builder()
        .title(title)
        .use_subtitle(true)
        .use_markup(false)
        .model(&gtk::StringList::new(&labels))
        .list_factory(&list_factory(choices))
        .selected(selected)
        .build()
}

fn connect_save(
    row: &adw::ComboRow,
    values: Vec<String>,
    state: Rc<RefCell<State>>,
    toasts: &adw::ToastOverlay,
    apply: impl Fn(&mut ProtonConfig, String) + 'static,
) {
    let toasts = toasts.downgrade();
    row.connect_selected_notify(move |row| {
        let Some(value) = usize::try_from(row.selected())
            .ok()
            .and_then(|index| values.get(index))
        else {
            return;
        };
        let mut state = state.borrow_mut();
        apply(&mut state.config, value.clone());
        let message = match state.config.save(&state.config_path, &state.titles) {
            Ok(()) => "Сохранено. Выбор заработает при следующем запуске игры.".to_owned(),
            Err(error) => format!(
                "Не удалось сохранить {}: {error}",
                state.config_path.display()
            ),
        };
        if let Some(toasts) = toasts.upgrade() {
            let toast = adw::Toast::new(&message);
            toast.set_timeout(3);
            toasts.add_toast(toast);
        }
    });
}

fn status_group(hook: &HookState) -> adw::PreferencesGroup {
    let (title, subtitle, icon) = match hook {
        HookState::Active(runtimes) => (
            "Выбор Proton работает",
            format!(
                "Epic запускает игры через Proton, выбранный ниже. Proton от Epic: {}.",
                runtimes.join(", ")
            ),
            "emblem-ok-symbolic",
        ),
        HookState::NoRuntime => (
            "Epic ещё не скачал свой Proton",
            "Запустите любую Windows-игру в Epic один раз. После этого выбор отсюда начнёт работать."
                .to_owned(),
            "dialog-information-symbolic",
        ),
        HookState::Failed(error) => (
            "Выбор Proton не подключён",
            format!("Игры запускаются через Proton от Epic. Причина: {error}"),
            "dialog-warning-symbolic",
        ),
    };
    let row = adw::ActionRow::builder()
        .title(title)
        .subtitle(subtitle.as_str())
        .use_markup(false)
        .build();
    row.add_prefix(&gtk::Image::from_icon_name(icon));
    let group = adw::PreferencesGroup::builder().title("Состояние").build();
    group.add(&row);
    group
}

fn default_group(
    installs: &[ProtonInstall],
    epic_detail: Option<&str>,
    state: &Rc<RefCell<State>>,
    toasts: &adw::ToastOverlay,
) -> adw::PreferencesGroup {
    let mut choices = proton_choices(installs, epic_detail);
    let selected = select_index(&mut choices, &state.borrow().config.default);
    let row = combo_row("Proton для всех игр", &choices, selected);
    let values = choices.into_iter().map(|choice| choice.value).collect();
    connect_save(&row, values, state.clone(), toasts, |config, value| {
        config.default = value
    });

    let group = adw::PreferencesGroup::builder()
        .title("По умолчанию")
        .description("Используется для всех игр, если для игры ниже не выбран другой Proton.")
        .build();
    group.add(&row);
    group
}

fn games_group(
    games: &[Game],
    installs: &[ProtonInstall],
    epic_detail: Option<&str>,
    state: &Rc<RefCell<State>>,
    toasts: &adw::ToastOverlay,
) -> adw::PreferencesGroup {
    let group = adw::PreferencesGroup::builder()
        .title("Игры")
        .description(
            "Отдельный Proton для игры. После смены Proton первый запуск игры может идти дольше: \
             Proton обновит её префикс.",
        )
        .build();

    if games.is_empty() {
        let row = adw::ActionRow::builder()
            .title("Игр пока нет")
            .subtitle("Установите Windows-игру в Epic Games Launcher и нажмите «Обновить» вверху.")
            .build();
        group.add(&row);
        return group;
    }

    for game in games {
        let mut choices = vec![Choice::new(DEFAULT, "Как для всех игр", None)];
        choices.extend(proton_choices(installs, epic_detail));
        let current = state
            .borrow()
            .config
            .games
            .get(&game.app_name)
            .cloned()
            .unwrap_or_else(|| DEFAULT.to_owned());
        let selected = select_index(&mut choices, &current);
        let row = combo_row(&game.title, &choices, selected);
        row.set_tooltip_text(Some(&game.dir));
        let values = choices.into_iter().map(|choice| choice.value).collect();
        let app_name = game.app_name.clone();
        connect_save(&row, values, state.clone(), toasts, move |config, value| {
            if value == DEFAULT {
                config.games.remove(&app_name);
            } else {
                config.games.insert(app_name.clone(), value);
            }
        });
        group.add(&row);
    }
    group
}

fn more_protons_group(window: &adw::ApplicationWindow) -> adw::PreferencesGroup {
    let installed = gio::AppInfo::all()
        .into_iter()
        .find(|app_info| app_info.id().as_deref() == Some(PROTONPLUS_DESKTOP_ID));
    let button = gtk::Button::builder()
        .label(if installed.is_some() {
            "Открыть"
        } else {
            "Установить"
        })
        .valign(gtk::Align::Center)
        .build();
    let window = window.downgrade();
    button.connect_clicked(move |_| {
        if let Some(app_info) = &installed {
            if let Err(error) = app_info.launch(&[], None::<&gio::AppLaunchContext>) {
                eprintln!("egl-proton: не удалось запустить ProtonPlus: {error}");
            }
            return;
        }
        let launcher = gtk::UriLauncher::new(PROTONPLUS_STORE_URI);
        launcher.launch(
            window.upgrade().as_ref(),
            gio::Cancellable::NONE,
            |result| {
                if let Err(error) = result {
                    eprintln!("egl-proton: не удалось открыть магазин приложений: {error}");
                }
            },
        );
    });

    let row = adw::ActionRow::builder()
        .title("ProtonPlus")
        .subtitle("Ставит DW-Proton, Proton-CachyOS, свежий GE-Proton и другие версии.")
        .build();
    row.add_suffix(&button);
    row.set_activatable_widget(Some(&button));

    let group = adw::PreferencesGroup::builder()
        .title("Другие версии Proton")
        .description(
            "Список выше собирается из Steam и ProtonPlus. Поставьте нужную версию \
             через ProtonPlus и нажмите «Обновить» вверху.",
        )
        .build();
    group.add(&row);
    group
}

fn build_page(window: &adw::ApplicationWindow, toasts: &adw::ToastOverlay) -> adw::PreferencesPage {
    let home = glib::home_dir();
    let hook = epic::apply_hook();
    let installs = protons::discover(&home);
    let games = epic::installed_games(&home);

    let config_path = ProtonConfig::path();
    let config = ProtonConfig::load(&config_path).unwrap_or_else(|error| {
        eprintln!(
            "egl-proton: не удалось прочитать {}: {error}",
            config_path.display()
        );
        ProtonConfig::default()
    });
    let titles = games
        .iter()
        .map(|game| (game.app_name.clone(), game.title.clone()))
        .collect();
    let state = Rc::new(RefCell::new(State {
        config_path,
        config,
        titles,
    }));

    let epic_detail = match &hook {
        HookState::Active(runtimes) => Some(runtimes.join(", ")),
        _ => None,
    };

    let page = adw::PreferencesPage::new();
    page.add(&status_group(&hook));
    page.add(&default_group(
        &installs,
        epic_detail.as_deref(),
        &state,
        toasts,
    ));
    page.add(&games_group(
        &games,
        &installs,
        epic_detail.as_deref(),
        &state,
        toasts,
    ));
    page.add(&more_protons_group(window));
    page
}

fn build_window(app: &adw::Application) {
    if let Some(window) = app.active_window() {
        window.present();
        return;
    }

    let toasts = adw::ToastOverlay::new();
    let refresh = gtk::Button::builder()
        .icon_name("view-refresh-symbolic")
        .tooltip_text("Обновить")
        .build();
    let header = adw::HeaderBar::new();
    header.pack_start(&refresh);
    let view = adw::ToolbarView::new();
    view.add_top_bar(&header);
    view.set_content(Some(&toasts));

    let window = adw::ApplicationWindow::builder()
        .application(app)
        .title("Epic Games: выбор Proton")
        .default_width(680)
        .default_height(760)
        .content(&view)
        .build();
    toasts.set_child(Some(&build_page(&window, &toasts)));

    let weak_window = window.downgrade();
    let weak_toasts = toasts.downgrade();
    refresh.connect_clicked(move |_| {
        let (Some(window), Some(toasts)) = (weak_window.upgrade(), weak_toasts.upgrade()) else {
            return;
        };
        toasts.set_child(Some(&build_page(&window, &toasts)));
    });

    window.present();
}
