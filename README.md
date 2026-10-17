# Epic Games Launcher Preview for Arch Linux / EndeavourOS

Unofficial native pacman packaging of Epic's official x86_64 AppImage, with
per-game Proton selection. The launcher runs directly on system GTK3,
WebKitGTK 4.1, libsoup3 and GLib/GIO. KDE Plasma 6 and AMD Radeon are the primary
test environment. This project is not affiliated with Epic Games.

Wayland is preferred: the wrapper defaults to `GDK_BACKEND=wayland,x11`.
GTK may fall back to X11 when Wayland cannot be opened. An available X11 server
is needed only for that fallback. The native launcher does not use Wine;
Windows games still need Proton and may use XWayland themselves.

The wrapper also clears a caller AppImage's identity and module/schema paths,
so opening a link from another AppImage cannot enable Epic's AppImage updater
or load that application's private GTK/GIO modules.

![Proton selection](docs/screenshots/proton-selection.png)

## Build and install

The AUR package is **epic-games-launcher-proton-bin**. It includes this fork's
Proton chooser, runtime router, tray integration and Wayland/cursor/icon fixes;
it conflicts with the separate `epic-games-launcher-bin` package. Replacing that
package preserves Epic's user data and installed games.

```sh
git clone https://aur.archlinux.org/epic-games-launcher-proton-bin.git
cd epic-games-launcher-proton-bin
makepkg --verifysource
makepkg -si
```

Alternatively, build from this source repository as described below.

Use an up-to-date Arch/EndeavourOS x86_64 system. Install the build dependencies
when you are ready to allow system changes:

```sh
sudo pacman -Syu --needed base-devel rust squashfs-tools patchelf desktop-file-utils namcap \
  gtk3 gtk4 libadwaita webkit2gtk-4.1 libsoup3 libayatana-appindicator libnotify xdg-utils
```

The repository's helper creates a standalone directory containing PKGBUILD,
.SRCINFO and a deterministic, checksummed snapshot of the open-source additions:

```sh
packaging/scripts/prepare-arch.sh
cd build/arch
makepkg --verifysource
makepkg --printsrcinfo > actual.SRCINFO
diff -u .SRCINFO actual.SRCINFO
makepkg
../../packaging/scripts/check-namcap.sh PKGBUILD ./*.pkg.tar.zst
../../packaging/scripts/verify-package.sh ./*.pkg.tar.zst src/appdir
```

`makepkg` downloads the pinned official Epic AppImage. Cargo downloads the locked
Rust dependencies during `prepare()`; build and tests run offline. Neither
AppRun nor the AppImage runtime is executed. Run makepkg as your normal user.
Only the following explicit installation step changes the host installation:

```sh
sudo pacman -U ./epic-games-launcher-proton-bin-*.pkg.tar.zst
```

Open **Epic Games Launcher** from the menu or run `epic-games-launcher`.
`EpicGamesLauncher` is a compatibility command pointing to the same wrapper.
The package also handles `com.epicgames.launcher://` links. There are no package
installation scripts, global systemd presets, DNF dependencies or update timers.
Pacman's existing desktop/icon-cache hooks handle menu integration.

The primary desktop entry is `EpicGamesLauncher.desktop`, matching Epic's native
Wayland app_id so Plasma can resolve its icon in the taskbar and Alt+Tab. A hidden
`epic-games-launcher.desktop` compatibility entry preserves old pinned shortcuts
and URI associations without adding a second visible menu entry.
Both entries reference Epic's installed PNG by absolute path, so an already-running
Plasma panel does not depend on refreshing a previously missing themed icon.

## Proton selection

Open **Choose Proton for games** in Epic's tray menu, use **Choose Proton** in
the launcher's desktop action, or run `egl-proton`. The window is intentionally
hidden as a separate application-menu item. English and Russian UI are retained.

Choose one Proton for all games or a separate build for each installed game.
Steam libraries, ProtonPlus directories and system compatibility tools are
searched. Proton builds are not downloaded by this panel. A first-launch
notification can open the panel. Removed selections fall back to Epic's Proton.

Launch a Windows game once so Epic downloads its own runtime. The hook then
replaces the runtime's `proton` script with a router and keeps the original as
`proton.epic`. The router preserves Epic's arguments and game environment. For
external builds with protonfixes it supplies `STORE=egs` and `UMU_ID` from that
build's database, with `umu-default` as the fallback. It does not add a second
`umu-run` process or require a system Wine installation for the launcher.

Configuration remains `${XDG_CONFIG_HOME:-~/.config}/egl-fedora/proton.conf`;
logs remain `${XDG_STATE_HOME:-~/.local/state}/egl-fedora/proton.log`. Existing
Epic data stays in `~/.local/share/com.epicgames.eglv2`; games, prefixes, account
data and configuration are not moved or deleted by packaging.

The wrapper applies the hook and starts the user path watcher for the current
login. To watch new runtimes even before opening the launcher, opt in as your user:

```sh
systemctl --user enable --now egl-fedora-proton-hook.path
```

As in the original project, Epic's built-in autostart may invoke its private ELF
directly and bypass the wrapper/tray addition. Use a user autostart entry invoking
`epic-games-launcher` if you want the same integration at login. The package does
not rewrite your existing autostart files.

## Cursor and graphics

The package deliberately excludes the AppImage's GTK/GLib/GIO libraries and
AppRun hooks. Their Ubuntu module paths prevent the bundled GIO from finding
Arch's dconf backend, so it reads Adwaita defaults instead of KDE's cursor theme.
System libraries read the existing dconf/KDE settings. No cursor theme is
hardcoded, installed or changed globally. See [the diagnosis](docs/arch-port.md).

Explicit backend overrides are supported:

```sh
GDK_BACKEND=wayland epic-games-launcher  # require Wayland, for diagnosis
GDK_BACKEND=x11 epic-games-launcher     # explicitly request X11
```

The wrapper keeps DISPLAY available for fallback. It does not disable WebKit's
sandbox, hardware acceleration, DMA-BUF or AMD drivers. System `libx11` remains
an ELF dependency; this does not make an ordinary Wayland launch use XWayland.
Mesa/RADV and any 32-bit graphics dependencies for games remain managed by your
normal Arch gaming setup, not private copies inside this package.

## Updates and removal

There is no background package updater. Obtain the next reviewed repository
version, prepare a fresh build directory, build it, then install the new package
with `sudo pacman -U`. A locally built package is not automatically available
through `pacman -Syu` unless you separately maintain a pacman repository for it.
Epic can still download games and its game compatibility runtimes normally.
For the AUR package, review and rebuild the updated PKGBUILD with your usual AUR
helper, or run `git pull --ff-only` and `makepkg -si` in its AUR checkout.

```sh
systemctl --user disable --now egl-fedora-proton-hook.path  # if enabled earlier
sudo pacman -R epic-games-launcher-proton-bin
```

The commands above leave user data and games in place. If the router is gone,
the Proton stub calls its saved `proton.epic`. Do not use Epic's own game-removal
or migration commands when you only intend to remove the pacman package.

## Maintaining and testing

After changing port sources, increase `pkgrel`, then refresh and review the
source archive checksum and .SRCINFO:

```sh
packaging/scripts/prepare-arch.sh --refresh
```

The PKGBUILD downloads its checksummed source snapshot from this fork's pinned
GitHub release. The preparation helper generates exactly the same snapshot for
local development. Publish that source archive with the matching `v<pkgver>-<pkgrel>`
release before pushing an updated PKGBUILD and `.SRCINFO` to AUR. Never upload
Epic's AppImage or a compiled pacman package to the AUR Git repository.

Namcap's generic ELF-path rule reports `/opt` as an error. This is the one
documented exception for the deliberately private, unmodified proprietary
payload. `check-namcap.sh` prints every diagnostic and rejects any other error.
Upstream EOS hardening/legacy linkage and Epic's retained debug symbols may also
produce warnings; the package verifier separately checks paths and byte identity.

For an Epic update, explicitly update `pkgver`, `_epic_gitrev` and the AppImage
SHA256 in `packaging/arch/PKGBUILD`, reset `pkgrel`, and run the same preparation
and validation steps. The official stable metadata and installer redirect must
agree; verify the version inside the extracted ELF as well. PKGBUILD never
resolves a moving "latest" URL. Review checksums; never replace them with SKIP.

```sh
tests/proton-hook-test.sh
tests/launcher-wrapper-test.sh
cargo test --locked --manifest-path proton-gui/Cargo.toml
cargo fmt --all --check --manifest-path proton-gui/Cargo.toml
cargo clippy --locked --manifest-path proton-gui/Cargo.toml --all-targets -- -D warnings
tests/tray-shim-check.sh  # needs a desktop; defaults to Wayland first
```

GitHub Actions builds an Arch pacman artifact and validates it in a disposable
container. It does not publish releases or install updates on users' machines.
The previous Fedora implementation is preserved in Git history; historical
Fedora investigation notes are not current installation instructions.

## License

Project additions are MIT licensed. Epic Games Launcher and EOS SDK remain
proprietary Epic software; the MIT license does not cover them. Upstream
ThirdPartyNotices.txt is preserved. No public binary redistribution is performed
by the local build workflow.
