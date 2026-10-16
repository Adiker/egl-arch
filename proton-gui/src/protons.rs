//! Поиск установленных Proton: ProtonPlus и ручные установки (compatibilitytools.d),
//! Steam (обычный и Flatpak) и системные пакеты.

use std::collections::BTreeSet;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProtonInstall {
    /// Каталог с исполняемым `proton`; это значение пишется в proton.conf.
    pub dir: PathBuf,
    pub name: String,
    /// Версия из файла `version` (вторая колонка), если есть.
    pub version: Option<String>,
}

impl ProtonInstall {
    pub fn label(&self) -> String {
        match &self.version {
            Some(version) if version != &self.name => format!("{} ({version})", self.name),
            _ => self.name.clone(),
        }
    }
}

fn is_executable(path: &Path) -> bool {
    fs::metadata(path)
        .map(|meta| meta.is_file() && meta.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

/// Значение `"key" "value"` из VDF-файла Steam (первое вхождение).
fn vdf_value(text: &str, key: &str) -> Option<String> {
    vdf_values(text, key).into_iter().next()
}

/// Все значения `"key" "value"` из VDF-файла Steam.
fn vdf_values(text: &str, key: &str) -> Vec<String> {
    let needle = format!("\"{key}\"");
    text.lines()
        .filter_map(|line| {
            let rest = line.trim().strip_prefix(&needle)?.trim();
            let value = rest.strip_prefix('"')?.split('"').next()?;
            (!value.is_empty()).then(|| value.to_owned())
        })
        .collect()
}

pub fn read_install(dir: &Path) -> Option<ProtonInstall> {
    if !is_executable(&dir.join("proton")) {
        return None;
    }
    let dir_name = dir.file_name()?.to_string_lossy().into_owned();
    let name = fs::read_to_string(dir.join("compatibilitytool.vdf"))
        .ok()
        .and_then(|text| vdf_value(&text, "display_name"))
        .unwrap_or(dir_name);
    let version = fs::read_to_string(dir.join("version"))
        .ok()
        .and_then(|text| text.split_whitespace().nth(1).map(str::to_owned));
    Some(ProtonInstall {
        dir: dir.to_path_buf(),
        name,
        version,
    })
}

fn steam_roots(home: &Path) -> Vec<PathBuf> {
    vec![
        home.join(".local/share/Steam"),
        home.join(".steam/root"),
        home.join(".steam/steam"),
        home.join(".var/app/com.valvesoftware.Steam/data/Steam"),
    ]
}

/// Все каталоги, где могут лежать Proton.
pub fn search_dirs(home: &Path) -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    for root in steam_roots(home) {
        dirs.push(root.join("compatibilitytools.d"));
        let library_file = root.join("steamapps/libraryfolders.vdf");
        let mut libraries = vec![root.clone()];
        if let Ok(text) = fs::read_to_string(&library_file) {
            libraries.extend(vdf_values(&text, "path").into_iter().map(PathBuf::from));
        }
        dirs.extend(
            libraries
                .into_iter()
                .map(|library| library.join("steamapps/common")),
        );
    }
    dirs.push(PathBuf::from("/usr/share/steam/compatibilitytools.d"));
    dirs.push(PathBuf::from("/usr/local/share/steam/compatibilitytools.d"));
    dirs
}

pub fn discover(home: &Path) -> Vec<ProtonInstall> {
    let mut seen = BTreeSet::new();
    let mut found = Vec::new();
    for dir in search_dirs(home) {
        let Ok(entries) = fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let Ok(canonical) = fs::canonicalize(&path) else {
                continue;
            };
            if seen.contains(&canonical) {
                continue;
            }
            if let Some(install) = read_install(&path) {
                seen.insert(canonical);
                found.push(install);
            }
        }
    }
    found.sort_by_key(|install| install.label().to_lowercase());
    found
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn temp_dir(name: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("egl-proton-test-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn fake_proton(dir: &Path, executable: bool) {
        fs::create_dir_all(dir).unwrap();
        let proton = dir.join("proton");
        fs::write(&proton, "#!/bin/sh\n").unwrap();
        let mode = if executable { 0o755 } else { 0o644 };
        fs::set_permissions(&proton, fs::Permissions::from_mode(mode)).unwrap();
    }

    #[test]
    fn reads_display_name_and_version() {
        let home = temp_dir("names");
        let dw = home.join(".local/share/Steam/compatibilitytools.d/DW-Proton Latest");
        fake_proton(&dw, true);
        fs::write(
            dw.join("compatibilitytool.vdf"),
            "\"compatibilitytools\"\n{\n  \"compat_tools\"\n  {\n    \"DW-Proton Latest\" // name\n    {\n      \"display_name\" \"DW-Proton Latest\"\n    }\n  }\n}\n",
        )
        .unwrap();
        fs::write(dw.join("version"), "1777248153 dwproton-10.0-26\n").unwrap();

        let found = discover(&home);
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].label(), "DW-Proton Latest (dwproton-10.0-26)");
        fs::remove_dir_all(home).unwrap();
    }

    #[test]
    fn finds_steam_library_protons_and_skips_non_protons() {
        let home = temp_dir("libraries");
        let library = home.join("library");
        let steam = home.join(".local/share/Steam/steamapps");
        fs::create_dir_all(&steam).unwrap();
        fs::write(
            steam.join("libraryfolders.vdf"),
            format!(
                "\"libraryfolders\"\n{{\n  \"1\"\n  {{\n    \"path\"\t\t\"{}\"\n  }}\n}}\n",
                library.display()
            ),
        )
        .unwrap();
        fake_proton(&library.join("steamapps/common/Proton 10.0"), true);
        fake_proton(
            &library.join("steamapps/common/Proton EasyAntiCheat Runtime"),
            false,
        );
        fs::create_dir_all(library.join("steamapps/common/SteamLinuxRuntime_sniper")).unwrap();

        let labels: Vec<String> = discover(&home).iter().map(ProtonInstall::label).collect();
        assert_eq!(labels, vec!["Proton 10.0".to_owned()]);
        fs::remove_dir_all(home).unwrap();
    }

    #[test]
    fn deduplicates_symlinked_steam_roots() {
        let home = temp_dir("symlinks");
        fake_proton(
            &home.join(".local/share/Steam/compatibilitytools.d/GE-Proton10-34"),
            true,
        );
        fs::create_dir_all(home.join(".steam")).unwrap();
        std::os::unix::fs::symlink(home.join(".local/share/Steam"), home.join(".steam/root"))
            .unwrap();

        assert_eq!(discover(&home).len(), 1);
        fs::remove_dir_all(home).unwrap();
    }
}
