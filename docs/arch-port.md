# Arch port: architecture and cursor diagnosis

## Payload and paths

The former RPM extracted Epic's binary, EOS SDK and Tauri resources from the
official AppImage. It built a Rust GTK4/libadwaita Proton panel and a GTK3
libayatana-appindicator shim; shell hooks routed per-game Proton choices.
Fedora-specific code also installed an hourly root DNF updater and presets.
The Arch port retains the game integration and removes that update mechanism.

The current pinned Epic release is `0.97.0+g4f63cc1` (verified 2026-10-17).
The official stable metadata and installer redirect agreed on this artifact:

- [Stable metadata](https://content-download-egs.distro.on.epicgames.com/Builds/EGLv2/stable-target.json)
- [Official installer endpoint](https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncher-x86_64.AppImage)
- [Pinned AppImage](https://content-download-egs.distro.on.epicgames.com/Builds/EGLv2/0.97.0%2Bg4f63cc1/Linux/EpicGamesLauncher-x86_64.AppImage)

AppImage SHA256: `5cf8607bb0a8f29a9887249d491c3c41ea3d0e8ed06a86695aa8e3b6000edae6`.
This is a measured payload checksum, not an upstream cryptographic signature.

The private package tree contains `bin/EpicGamesLauncher`,
`lib/libEOSSDK-Linux-Shipping.so` and `lib/epic-games-launcher/`, including the
second upstream EOS copy and Tauri resources. The binary's original
`$ORIGIN/../lib` RUNPATH and Tauri's relative resource layout are preserved.
Only Epic's files are copied there; GTK, WebKit and other general libraries are
resolved from Arch. The Epic binary requires GLIBC up to 2.34.

The tray shim uses `/usr/lib/libayatana-appindicator3.so.1` as its explicit real
library dependency. patchelf changes only this project-built shim. It never
modifies an Epic binary or system library. No Wine or XWayland package is a hard
runtime dependency of this package. GTK's X11 ABI dependencies remain valid.

## Reproduced cursor failure

The analysis used the user's downloaded official AppImage, extracted without
executing it, and small disposable C/GTK probes on the existing Wayland session.
No Epic profile was opened for these probes and no settings were written.

| Environment | GTK | GLib | GSettings backend | GDK cursor theme |
| --- | --- | --- | --- | --- |
| AppImage libraries and module environment | 3.24.33 | 2.72.4 | GKeyfileSettingsBackend | Adwaita |
| Arch libraries | 3.24.52 | 2.90.1 | DConfSettingsBackend | We10XOS-cursors |

The first probe opened Adwaita cursor files successfully 128 times and never
opened We10XOS cursor files. The system probe read We10XOS and size 30. Keeping
the AppImage schemas and `GTK_THEME=Adwaita:light` with **system** libraries still
selected We10XOS, separating the widget theme from the cursor problem.

The shipped GTK hook sets GIO_EXTRA_MODULES to an AppImage-relative Ubuntu
`usr/lib/x86_64-linux-gnu/gio/modules` directory. That directory contains TLS
support but no dconf module. Bundled GIO's default path is also
`/usr/lib/x86_64-linux-gnu/gio/modules`, absent on Arch. Arch's actual module is
`/usr/lib/gio/modules/libdconfsettings.so`. The fallback backend cannot read the
existing dconf preferences and returns the schema default, Adwaita.

Adding Arch's module directory to the bundled GLib was also tested: dconf fails
to load with `undefined symbol: g_assertion_message_cmpint`. Mixing the current
module with GLib 2.72 is not a viable fix. Merely replacing cursor environment
variables does not repair this backend mismatch.

The fix is process-local: bypass AppRun and resolve the entire GTK/GLib/GIO
stack from Arch, with its matching dconf module. No cursor assets or preferences
are changed. GTK's Wayland source confirms it asks GdkScreen for
`gtk-cursor-theme-name`, then passes that name to `wl_cursor_theme_load`:
[GTK source](https://github.com/GNOME/gtk/blob/3.24.52/gdk/wayland/gdkdisplay-wayland.c).

The AppImage hook also exports `GDK_BACKEND=x11`. The wrapper does not execute
that hook and defaults to `wayland,x11`, retaining an explicit X11 override and
fallback. Actual backend selection must be checked in runtime evidence; linked
libX11 alone is not evidence of using X11.

## Compatibility and verification boundaries

### Wayland taskbar and Alt+Tab icon

The running native window was verified to advertise `app_id=EpicGamesLauncher`.
The initial package used `epic-games-launcher.desktop`, which KWin could not find
when resolving the app_id. KWin 6.8's `handleAppIdChanged()` sets desktopFileName
to the app_id; `Window::findDesktopFile()` looks up that exact ID plus `.desktop`.
If the lookup fails, `XdgToplevelWindow::updateIcon()` explicitly chooses the
`wayland` icon. StartupWMClass does not participate in that lookup.

Revision 2 installs `EpicGamesLauncher.desktop` as the primary entry. The previous
desktop ID remains as a NoDisplay compatibility entry, preserving pins and URI
associations. This corrected Alt+Tab on the host, but the user still observed a
blank icon in the existing Plasma panel. A fresh native WaylandTasksModel resolved
the correct desktop entry and rendered `EpicGamesLauncher` at every tested size;
this points to stale icon lookup state in the long-running shell rather than a
missing asset. The shell's internal cache was not directly inspected.

Revision 3 uses the absolute path to Epic's original 128px PNG in both desktop
entries. Absolute `Icon` paths are supported by the desktop entry specification
and KDE's task model; this bypasses theme-name lookup for this application. It
does not clear global caches, change the icon theme, alter Epic binaries, add a
window rule or restart Plasma.

Sources: [KWin icon selection](https://github.com/KDE/kwin/blob/Plasma/6.8/src/xdgshellwindow.cpp),
[KWin desktop lookup](https://github.com/KDE/kwin/blob/Plasma/6.8/src/window.cpp),
[Wayland app_id contract](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/stable/xdg-shell/xdg-shell.xml),
[KDE task icon lookup](https://github.com/KDE/plasma-workspace/blob/Plasma/6.8/libtaskmanager/tasktools.cpp),
[Desktop entry Icon key](https://specifications.freedesktop.org/desktop-entry/latest/recognized-keys.html).

Proton config/log names retain `egl-fedora` deliberately. The Epic data location,
Steam-library discovery, notifications, language selection and fallback are
retained. UMU/protonfixes integration means preserving the existing router's
UMU_ID/STORE handling, not adding a new system umu-run requirement.

A package verification script compares Epic's binary, both EOS copies and all
Tauri resources against the extraction. Unit tests use fake runtimes and explicit
search roots, so installed system Proton builds cannot contaminate assertions.
Game launches, backend fallback and real launcher cursor behavior are separate
runtime checks and must not be inferred from passing unit tests.

Namcap 3.6.0 labels all ELF payloads under `/opt` as an error through its
`questionable_dirs` rule. This is the single explicit exception in
`check-namcap.sh`: the layout preserves the requested private upstream tree and
its relative resource/RUNPATH relationships. Other errors are rejected. Upstream
EOS lacks full RELRO and links older glibc compatibility libraries; these cannot
be changed without modifying Epic's binaries. The project's tray shim is
stripped independently; Epic's binaries are deliberately not stripped.
