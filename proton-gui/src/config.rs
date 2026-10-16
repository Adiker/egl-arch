//! Настройка выбора Proton: ${XDG_CONFIG_HOME}/egl-fedora/proton.conf.
//!
//! Формат читает egl-proton-router: строки `default=<значение>` и
//! `game.<app_name>=<значение>`, где значение `epic`, `default` (только для игры)
//! или абсолютный путь к каталогу Proton.

use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

pub const EPIC: &str = "epic";
pub const DEFAULT: &str = "default";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProtonConfig {
    pub default: String,
    pub games: BTreeMap<String, String>,
}

impl Default for ProtonConfig {
    fn default() -> Self {
        Self {
            default: EPIC.to_owned(),
            games: BTreeMap::new(),
        }
    }
}

impl ProtonConfig {
    pub fn path() -> PathBuf {
        gtk::glib::user_config_dir()
            .join("egl-fedora")
            .join("proton.conf")
    }

    pub fn parse(text: &str) -> Self {
        let mut config = Self::default();
        for line in text.lines() {
            if line.starts_with('#') {
                continue;
            }
            let Some((key, value)) = line.split_once('=') else {
                continue;
            };
            if value.is_empty() {
                continue;
            }
            if key == "default" {
                config.default = value.to_owned();
            } else if let Some(app_name) = key.strip_prefix("game.") {
                if value == DEFAULT {
                    config.games.remove(app_name);
                } else {
                    config.games.insert(app_name.to_owned(), value.to_owned());
                }
            }
        }
        config
    }

    /// Текст файла; `titles` нужны только для комментариев с названиями игр.
    pub fn serialize(&self, titles: &BTreeMap<String, String>) -> String {
        let mut text = String::from(
            "# Proton для игр Epic Games Launcher. Файл пишет «Epic Games: выбор Proton» (egl-proton).\n\
             # epic = GE-Proton, который скачивает сам Epic; иначе путь к каталогу Proton.\n",
        );
        text.push_str(&format!("default={}\n", self.default));
        for (app_name, value) in &self.games {
            if let Some(title) = titles.get(app_name) {
                let title = title.replace(['\n', '\r'], " ");
                text.push_str(&format!("# {title}\n"));
            }
            text.push_str(&format!("game.{app_name}={value}\n"));
        }
        text
    }

    pub fn load(path: &Path) -> io::Result<Self> {
        match fs::read_to_string(path) {
            Ok(text) => Ok(Self::parse(&text)),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(Self::default()),
            Err(error) => Err(error),
        }
    }

    /// Атомарная запись: роутер может читать файл в момент сохранения.
    pub fn save(&self, path: &Path, titles: &BTreeMap<String, String>) -> io::Result<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let tmp = path.with_extension("conf.tmp");
        fs::write(&tmp, self.serialize(titles))?;
        fs::rename(&tmp, path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_router_format() {
        let config = ProtonConfig::parse(
            "# comment\n\
             default=/protons/DW\n\
             game.aaa=epic\n\
             game.bbb=/protons/Cachy\n\
             game.ccc=default\n\
             game.aaa=/protons/GE\n\
             broken line\n",
        );
        assert_eq!(config.default, "/protons/DW");
        assert_eq!(
            config.games.get("aaa").map(String::as_str),
            Some("/protons/GE")
        );
        assert_eq!(
            config.games.get("bbb").map(String::as_str),
            Some("/protons/Cachy")
        );
        assert!(!config.games.contains_key("ccc"));
    }

    #[test]
    fn empty_file_means_epic() {
        assert_eq!(ProtonConfig::parse(""), ProtonConfig::default());
    }

    #[test]
    fn serialize_round_trip() {
        let mut config = ProtonConfig {
            default: "/protons/DW-Proton Latest".to_owned(),
            ..ProtonConfig::default()
        };
        config.games.insert("525aa".to_owned(), EPIC.to_owned());
        let titles = BTreeMap::from([("525aa".to_owned(), "Zenless Zone Zero".to_owned())]);
        let text = config.serialize(&titles);
        assert!(text.contains("# Zenless Zone Zero\ngame.525aa=epic\n"));
        assert_eq!(ProtonConfig::parse(&text), config);
    }
}
