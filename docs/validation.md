# Arch port validation — 2026-10-17

This report records revision 1. The subsequently authorized host update and
Wayland taskbar/Alt+Tab correction are recorded in
[icon-fix-validation.md](icon-fix-validation.md).

Tests were run locally on EndeavourOS / Plasma 6 / Wayland / AMD Radeon and in
an isolated Arch Linux container. No package was installed on the host, no sudo
was used, and no existing Epic profile or game was launched.

## Deliverable

- Package: `build/arch/epic-games-launcher-bin-0.97.0-1-x86_64.pkg.tar.zst`.
- Package SHA256: `ad494836aabe16f256e5a1d9d8b2440c94edff87449fcc9fc606fc94d6bacf3e`.
- Epic version: `0.97.0+g4f63cc1`; official CDN AppImage was downloaded and verified.
- AppImage SHA256: `5cf8607bb0a8f29a9887249d491c3c41ea3d0e8ed06a86695aa8e3b6000edae6`.
- Port source SHA256: `572c257ed119489e45900e8997fb263ab3e7871601fcc75955aba3e4ea71aff9`.
- Container: `archlinux@sha256:061679925e5d5028f2df9395d441ce6c4b9accf0157ff3486c06b6962e014ef1`.
- Container toolchain: Rust 1.99.0, GTK3 3.24.52, GTK4 4.24.1,
  WebKitGTK 4.1 2.54.1, libadwaita 1.10.0, namcap 3.6.0.

## Automated checks

| Check | Result |
| --- | --- |
| `tests/proton-hook-test.sh` | 20 checks passed, fake HOME/runtimes only |
| `tests/launcher-wrapper-test.sh` | Passed: Wayland default, X11 override, DISPLAY, exact URI/argv, inherited AppImage cleanup, failed-hook tolerance, exit status |
| `tests/tray-shim-check.sh` | 5/5 passed on the host desktop |
| `cargo test --locked` | 8/8 passed on host and in the package's release-profile check phase |
| `cargo fmt --all --check` | Passed |
| `cargo clippy --locked --all-targets -- -D warnings` | Passed |
| ShellCheck and desktop-file-validate | Passed |
| `makepkg --verifysource` | Both sources passed; repeated validation used `--force` because a package already existed |
| `makepkg --printsrcinfo` | Byte-for-byte match with checked-in .SRCINFO |
| `makepkg --cleanbuild --force` | Initial full build passed; subsequent source/packaging revisions rebuilt with `makepkg --force` and checks enabled |
| Standalone source snapshot | Matched a separate file-only checkout with no empty directories |
| Package verifier | Expected files/dependencies, no updater, correct private tray linkage; Epic/EOS/resources byte-identical to AppImage |
| Installation in disposable container | `pacman -Qkk`: 48 files, 0 altered; no missing libraries in ldd |
| User systemd units | `systemd-analyze --user verify` passed with an isolated runtime directory |
| Installed `egl-proton --list` | Passed in an empty disposable profile |
| Workflow YAML / git diff whitespace | Passed; no remote CI run or publication performed |

The container image excludes documentation via pacman NoExtract by default.
Validation used a temporary pacman configuration without that exclusion so the
complete package could be verified. The host pacman configuration was untouched.

## Namcap findings

The PKGBUILD itself produces no namcap diagnostics. The package has one known
error: namcap's generic `elfpaths` rule classifies `/opt` as a questionable ELF
location. `/opt/epic-games-launcher` is the explicitly chosen private layout for
the proprietary upstream payload. `check-namcap.sh` prints that error and all
warnings, and rejects every other error; this is not a zero-error namcap claim.

Remaining warnings concern unmodified Epic debug symbols, EOS missing full
RELRO, glibc compatibility dependencies, the tray shim's deliberate dlopen/dlsym
linkage, and command/dconf dependencies that static library analysis cannot
recognize. The shim is stripped; Epic's binaries are not changed. Canonical
`/usr/bin` lookup avoids spurious shebang-ownership warnings caused by the
container PATH preferring merged `/usr/sbin` aliases.

## Native runtime checks

The installed-layout files were exposed through a read-only bubblewrap overlay,
without placing them in host `/usr` or `/opt`. Each run had a disposable HOME,
XDG directories, XDG_RUNTIME_DIR and private D-Bus session. The real Epic profile
was hidden. Only display connections, cursor-theme files and GPU devices were
exposed; no account login or game launch was attempted. The cursor preference
was set only in the disposable dconf database.

- **Wayland:** KWin reported `client_type=wayland` for the Epic window. Strace
  showed successful connection to the Wayland socket, loading
  `/usr/lib/gio/modules/libdconfsettings.so`, and successful reads of We10XOS
  cursor files. It showed no Adwaita cursor reads and no X11 socket connections.
- **AMD:** the launcher and its subprocesses loaded system Mesa EGL/Gallium and
  opened `renderD128`. The device vendor was verified as `0x1002` (AMD).
- **X11 fallback:** with WAYLAND_DISPLAY deliberately pointing to an absent
  socket and DISPLAY still available, the Wayland connect failed with ENOENT,
  then the launcher connected successfully to the X11 socket. KWin reported
  `client_type=x11`. No forced X11 setting was needed.
- **Proton panel:** the packaged `egl-proton` created a window titled
  `Epic Games: Proton selection`, with KWin reporting `client_type=wayland`.
- **Package-only updates:** Epic logged `SelfUpdate.LinuxFlavorUnsupported`,
  confirming this installed layout did not select an AppImage/deb self-updater.

Each smoke run was ended by its bounded timeout; exit 124 is expected here.
The isolated bus emitted accessibility/user-manager warnings because it does not
run the host's user systemd services. The GTK4 panel also reported an unavailable
host Vulkan implicit layer; no driver, renderer, sandbox or global setting was
changed to suppress it.

Screenshot capture returned a lock-screen image. Window backend and syscall
checks succeeded, but visual rendering and the cursor's appearance under the
pointer were not confirmed by screenshot. Login, downloads, a real game's start,
and the live user-systemd watcher after host installation remain untested.
Passing router tests is not a claim that a real game was launched.

Local evidence is retained under `build/arch/`: final-build.log,
container-install.log, linkage.log, proton-list.log, namcap.log and SHA256SUMS.
The local smoke harness and runtime-directory.txt identify the disposable runtime
traces; those raw traces live in /tmp and are not part of the package or sources.
