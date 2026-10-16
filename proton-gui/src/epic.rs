//! Данные Epic Games Launcher: установленные Windows-игры и состояние перехвата Proton.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use serde_json::Value;

use crate::i18n::russian;

pub const HOOK: &str = "/usr/libexec/egl-fedora/egl-proton-hook";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Game {
    /// Имя префикса Proton (artifactId), ключ `game.<app_name>` в proton.conf.
    pub app_name: String,
    pub title: String,
    pub dir: String,
}

pub fn data_dir(home: &Path) -> PathBuf {
    home.join(".local/share/com.epicgames.eglv2")
}

/// Названия из кэша каталога: items.<itemId>.item.title.
fn catalog_titles(data_dir: &Path) -> BTreeMap<String, String> {
    let Ok(text) = fs::read_to_string(data_dir.join("cache/prod/catalog-cache.json")) else {
        return BTreeMap::new();
    };
    let Ok(Value::Object(root)) = serde_json::from_str::<Value>(&text) else {
        return BTreeMap::new();
    };
    let Some(Value::Object(items)) = root.get("items") else {
        return BTreeMap::new();
    };
    items
        .iter()
        .filter_map(|(item_id, entry)| {
            let title = entry.get("item")?.get("title")?.as_str()?;
            Some((item_id.clone(), title.to_owned()))
        })
        .collect()
}

/// Установленные Windows-игры из installations.jsonl (последняя запись на installationId).
pub fn parse_installations(text: &str, titles: &BTreeMap<String, String>) -> Vec<Game> {
    let mut latest: BTreeMap<String, Option<Value>> = BTreeMap::new();
    for line in text.lines() {
        let Ok(record) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        let Some(id) = record.get("installationId").and_then(Value::as_str) else {
            continue;
        };
        let deleted = record.get("deleted").and_then(Value::as_bool) == Some(true);
        latest.insert(id.to_owned(), (!deleted).then_some(record));
    }

    let mut games: BTreeMap<String, Game> = BTreeMap::new();
    for record in latest.into_values().flatten() {
        if record.get("platform").and_then(Value::as_str) != Some("Windows") {
            continue;
        }
        let Some(app_name) = record.get("artifactId").and_then(Value::as_str) else {
            continue;
        };
        let dir = record
            .get("dir")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned();
        let title = record
            .get("itemId")
            .and_then(Value::as_str)
            .and_then(|item_id| titles.get(item_id).cloned())
            .or_else(|| {
                Path::new(&dir)
                    .file_name()
                    .map(|name| name.to_string_lossy().into_owned())
            })
            .unwrap_or_else(|| app_name.to_owned());
        games.insert(
            app_name.to_owned(),
            Game {
                app_name: app_name.to_owned(),
                title,
                dir,
            },
        );
    }
    let mut games: Vec<Game> = games.into_values().collect();
    games.sort_by_key(|game| game.title.to_lowercase());
    games
}

pub fn installed_games(home: &Path) -> Vec<Game> {
    let data_dir = data_dir(home);
    let Ok(text) = fs::read_to_string(data_dir.join("installations.jsonl")) else {
        return Vec::new();
    };
    parse_installations(&text, &catalog_titles(&data_dir))
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HookState {
    /// Выбор Proton работает для этих runtime Epic.
    Active(Vec<String>),
    /// Epic ещё не скачал свой Proton.
    NoRuntime,
    Failed(String),
}

fn run_hook(args: &[&str]) -> Result<String, String> {
    let output = Command::new(HOOK).args(args).output().map_err(|error| {
        if russian() {
            format!("не удалось запустить {HOOK}: {error}")
        } else {
            format!("could not run {HOOK}: {error}")
        }
    })?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("{HOOK} {}: {}", args.join(" "), stderr.trim()));
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

pub fn parse_status(text: &str) -> HookState {
    let mut active = Vec::new();
    let mut other = Vec::new();
    for line in text.lines() {
        match line.split_once('\t') {
            Some((runtime, "active")) => active.push(runtime.to_owned()),
            Some((runtime, state)) => other.push(format!("{runtime}: {state}")),
            None => {}
        }
    }
    if !other.is_empty() && active.is_empty() {
        let other = other.join(", ");
        return HookState::Failed(if russian() {
            format!("перехват не подключён ({other})")
        } else {
            format!("the hook is not installed ({other})")
        });
    }
    if active.is_empty() {
        HookState::NoRuntime
    } else {
        HookState::Active(active)
    }
}

/// Ставит заглушку во все готовые runtime и возвращает состояние.
pub fn apply_hook() -> HookState {
    if let Err(error) = run_hook(&["apply"]) {
        return HookState::Failed(error);
    }
    match run_hook(&["status"]) {
        Ok(text) => parse_status(&text),
        Err(error) => HookState::Failed(error),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const INSTALLATIONS: &str = r#"{"version":1,"writtenAt":"2026-10-16T08:40:42Z","entries":0}
{"installationId":"F8","complete":true,"dir":"/home/user/Games/ZenlessZoneZero","platform":"Windows","itemId":"825cd","artifactId":"525aa"}
{"installationId":"F8","deleted":true}
{"installationId":"6A","complete":false,"dir":"/mnt/games/EpicGames/ZenlessZoneZero","platform":"Windows","itemId":"825cd","artifactId":"525aa"}
{"installationId":"6A","complete":true,"dir":"/mnt/games/EpicGames/ZenlessZoneZero","platform":"Windows","itemId":"825cd","artifactId":"525aa"}
{"installationId":"UE","complete":true,"dir":"/home/user/Games/UE","platform":"Linux","itemId":"ue","artifactId":"UE_5"}
{"installationId":"XX","complete":true,"dir":"/home/user/Games/Mystery","platform":"Windows","itemId":"unknown","artifactId":"mystery"}
not json
"#;

    #[test]
    fn keeps_latest_windows_installs() {
        let titles = BTreeMap::from([("825cd".to_owned(), "Zenless Zone Zero".to_owned())]);
        let games = parse_installations(INSTALLATIONS, &titles);
        assert_eq!(
            games,
            vec![
                Game {
                    app_name: "mystery".to_owned(),
                    title: "Mystery".to_owned(),
                    dir: "/home/user/Games/Mystery".to_owned(),
                },
                Game {
                    app_name: "525aa".to_owned(),
                    title: "Zenless Zone Zero".to_owned(),
                    dir: "/mnt/games/EpicGames/ZenlessZoneZero".to_owned(),
                },
            ]
        );
    }

    #[test]
    fn hook_status() {
        assert_eq!(
            parse_status("GE-Proton10-34\tactive\nGE-Proton11-1\tincomplete\n"),
            HookState::Active(vec!["GE-Proton10-34".to_owned()])
        );
        assert_eq!(parse_status(""), HookState::NoRuntime);
        assert!(matches!(
            parse_status("GE-Proton10-34\tinactive\n"),
            HookState::Failed(_)
        ));
    }
}
