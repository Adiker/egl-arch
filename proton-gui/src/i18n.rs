//! Язык подписей: русский при русской локали, иначе английский.
//!
//! Язык берётся так же, как в пункте трея (tray/egl-tray.c): первый из
//! g_get_language_names(), то есть из LANGUAGE, LC_ALL, LC_MESSAGES и LANG.

use std::sync::OnceLock;

use gtk::glib;

pub fn russian() -> bool {
    static RUSSIAN: OnceLock<bool> = OnceLock::new();
    *RUSSIAN.get_or_init(|| {
        glib::language_names()
            .first()
            .is_some_and(|name| name.starts_with("ru"))
    })
}

/// Подпись на языке окна.
pub fn tr<'a>(english: &'a str, russian: &'a str) -> &'a str {
    if self::russian() { russian } else { english }
}
