# Plasma taskbar / Alt+Tab icon corrections — revisions 2 and 3

The running Wayland window advertised `app_id=EpicGamesLauncher`, while revision
1 installed only `epic-games-launcher.desktop`. KWin looks for the desktop entry
whose ID matches the app_id; its icon selection explicitly falls back to
`wayland` when that desktop lookup has no icon.

Revision 2 installs `EpicGamesLauncher.desktop` as the visible primary entry.
The old desktop ID is retained as a hidden compatibility entry, so existing pins
and MIME associations keep their targets. Both entries use the original Epic
icon assets and wrapper; the Wayland-first/X11-fallback policy is unchanged.

## Validation

- `desktop-file-validate`, ShellCheck, `git diff --check`: passed.
- `makepkg --verifysource --force`: both source checksums passed.
- `makepkg --printsrcinfo`: matched the checked-in `.SRCINFO`.
- The packaging-only revision was built with `makepkg --repackage --nodeps
  --force`, reusing the already-tested Arch release binaries. No Rust, Proton or
  tray implementation changed. The skipped dependency check concerned the
  absent build-only squashfs tool, which is not executed by repackage.
- Package verifier: canonical desktop ID present and visible; old alias hidden
  and otherwise identical; icons present; Epic/EOS/resources unchanged.
- Namcap: no PKGBUILD diagnostics and no new package errors. The previous,
  documented `/opt` exception and upstream warnings remain.
- A Qt/KDesktopFile probe using KWin's actual lookup procedure reproduced the
  old missing desktop entry and `wayland` selection. With the corrected entry it
  selected `EpicGamesLauncher` and rendered the installed PNG successfully.
  The headless probe explicitly used the standard icon roots and hicolor theme;
  this changed only its own process, not the user's icon theme.

## Authorized host update

After the user explicitly approved installation and restart, revision 2 was
installed through pacman. `pacman -Qkk epic-games-launcher-bin` reported **49
files, 0 altered files**. The old launcher process was terminated and the new
installed wrapper launched; no games or user data were deleted or migrated.

A temporary read-only KWin script obtained the new window's ID, then KWin's
`getWindowInfo` confirmed `desktopFile: EpicGamesLauncher`,
`resourceClass: EpicGamesLauncher`, and the expected launcher caption. The
system Qt lookup now resolves `/usr/share/applications/EpicGamesLauncher.desktop`,
reads `Icon=EpicGamesLauncher`, and renders a non-empty icon with native name
`EpicGamesLauncher`. The temporary KWin script and diagnostic D-Bus service were
unloaded after verification. The launcher was left running at that time.

The package is `build/arch/epic-games-launcher-bin-0.97.0-2-x86_64.pkg.tar.zst`.
SHA256: `7101915b90d9d68f74de72825bd8b98b3ece75b48c0f057c8e2c993980ab202f`.

Local logs and the rendered icon are under `build/icon-check/`; package build and
namcap logs are under `build/arch/icon-fix-*`. The full revision-1 runtime/test
record remains in [validation.md](validation.md).

Sources: [KWin app_id/icon selection](https://github.com/KDE/kwin/blob/Plasma/6.8/src/xdgshellwindow.cpp),
[KWin desktop lookup](https://github.com/KDE/kwin/blob/Plasma/6.8/src/window.cpp).

## Revision 3: blank taskbar icon reported after revision 2

The user confirmed Alt+Tab was correct but the taskbar remained blank. The
earlier Qt/KWin probe did not inspect the running Plasma panel, so its success
was insufficient to claim that the taskbar was fixed.

The saved task manager launcher lists contain no Epic pin. A fresh native
`TaskManager::WaylandTasksModel`, using the host's unchanged Papirus-Dark theme,
resolved `applications:EpicGamesLauncher.desktop` and rendered the themed Epic
icon at 16, 22, 32, 48, 64 and 128 pixels. This points to stale lookup state in
the long-running Plasma process; its internal cache was not directly inspected.

Both packaged desktop entries now reference
`/usr/share/icons/hicolor/128x128/apps/EpicGamesLauncher.png` directly. This is
the original upstream asset. Absolute paths are permitted by the desktop entry
specification and handled by KDE's task icon lookup. No global icon theme,
Plasma configuration, cache files or Epic binaries were edited.

Validation of revision 3:

- `makepkg --verifysource --force`: both source checksums passed.
- `makepkg --printsrcinfo`: matched checked-in `.SRCINFO`.
- `makepkg --repackage --nodeps --force`: succeeded, reusing the already-tested
  compiled helpers; no helper code changed. The build-only squashfs dependency
  is still absent on the host and is not needed for repackaging.
- Desktop validation, ShellCheck, wrapper tests and `git diff --check`: passed.
- Package layout/dependency verifier: passed; Epic/EOS/resources remain
  byte-identical to the AppImage.
- Namcap: no new errors; the documented `/opt` exception and upstream warnings
  remain.
- Installed through `sudo -n pacman -U --noconfirm` under the user's existing
  authorization; `pacman -Qkk` reported 49 files and 0 altered files.
- Restarted only the launcher, through transient user unit
  `egl-icon-recheck.service`; Plasma was not restarted.
- After installation, the native WaylandTasksModel rendered the new file-backed
  icon at all six tested sizes. An empty `QIcon::name()` here is expected for a
  direct PNG; `isNull()` and every pixmap check were false.
- CUA/KWin window metadata confirmed the restarted launcher remains a Wayland
  client with `app_id=EpicGamesLauncher`.

The user subsequently confirmed that the Epic icon is visible in the existing
taskbar. This provides visual confirmation from the live Plasma session in
addition to the model-level checks. Alt+Tab had already been confirmed correct
by the user after revision 2.

Package: `build/arch/epic-games-launcher-bin-0.97.0-3-x86_64.pkg.tar.zst`.
SHA256: `dd800c614fb11926439b428768bd3d40352f345b311950a5378732d2a8599bae`.
Evidence: `build/arch/taskbar-*` and `build/icon-check/task-{before,after}.log`.

Sources: [KDE task model](https://github.com/KDE/plasma-workspace/blob/Plasma/6.8/libtaskmanager/waylandtasksmodel.cpp),
[KDE desktop icon lookup](https://github.com/KDE/plasma-workspace/blob/Plasma/6.8/libtaskmanager/tasktools.cpp),
[Desktop entry Icon key](https://specifications.freedesktop.org/desktop-entry/latest/recognized-keys.html).
