# Неофициальная упаковка Epic Games Launcher для Fedora (egl-fedora).
# Собирать через packaging/scripts/build-rpm.sh: он скачивает официальный AppImage
# и передаёт версию Epic и ревизию упаковки.

%{!?epic_version:%{error:epic_version не задан, собирайте через packaging/scripts/build-rpm.sh}}
%{!?epic_gitrev:%{error:epic_gitrev не задан, собирайте через packaging/scripts/build-rpm.sh}}
%{!?pkgrel:%{error:pkgrel не задан, собирайте через packaging/scripts/build-rpm.sh}}

%global appname     epic-games-launcher
%global srcname     egl-fedora-%{pkgrel}
%global update_repo DXVSI/egl-fedora

# Бинарники Epic уже собраны: без debuginfo и strip, RUNPATH как в оригинале.
# Наш egl-proton стрипается при установке (install -s): Fedora RUSTFLAGS отключают strip cargo.
%global debug_package   %{nil}
%global _build_id_links none
%global __strip         /bin/true

# EOS SDK лежит внутри пакета: не объявляем его общесистемной библиотекой.
%global __provides_exclude_from ^(%{_prefix}/lib/.*\\.so|%{_libdir}/egl-fedora/.*)$
%global __requires_exclude      ^libEOSSDK-Linux-Shipping\\.so

Name:           %{appname}
Version:        %{epic_version}
Release:        %{pkgrel}.git%{epic_gitrev}%{?dist}
Summary:        Epic Games Launcher with automatic updates and Proton selection (unofficial)
License:        LicenseRef-Proprietary AND MIT
URL:            https://github.com/%{update_repo}
Source0:        EpicGamesLauncher-x86_64.AppImage
Source1:        %{srcname}.tar.xz
ExclusiveArch:  x86_64

BuildRequires:  binutils
BuildRequires:  cargo
BuildRequires:  desktop-file-utils
BuildRequires:  gawk
BuildRequires:  gcc
BuildRequires:  gtk3-devel
BuildRequires:  gtk4-devel
BuildRequires:  libadwaita-devel
BuildRequires:  libayatana-appindicator-gtk3%{?_isa}
BuildRequires:  patchelf
BuildRequires:  rust
BuildRequires:  squashfs-tools
BuildRequires:  systemd-rpm-macros

Requires:       xdg-utils
Requires:       hicolor-icon-theme
# подменная библиотека трея подключает настоящую по абсолютному пути
Requires:       libayatana-appindicator-gtk3%{?_isa}
# egl-update и скрипты Proton
Requires:       /usr/bin/dnf
Requires:       coreutils
Requires:       curl
Requires:       findutils
Requires:       gawk
# подсказка о выборе Proton при первом запуске игры
Requires:       /usr/bin/notify-send
%{?systemd_requires}

%description
Epic Games Launcher %{version}+g%{epic_gitrev} from the official x86_64 AppImage,
installed system-wide and running on the system WebKitGTK 4.1, GTK 3 and
libsoup 3.

The package adds:
- an hourly update check that installs newer packages from GitHub Releases;
- "Epic Games: Proton selection", a window to choose which Proton (GE from Epic,
  DW-Proton, Proton-CachyOS, Steam Proton and others) runs each game.

This package is not affiliated with or endorsed by Epic Games.

%prep
%setup -q -c -T -a 1
# Смещение squashfs = конец ELF-рантайма AppImage (e_shoff + e_shentsize * e_shnum).
offset=$(LC_ALL=C readelf -h %{SOURCE0} | awk '
  /Start of section headers/  {s = $5}
  /Size of section headers/   {z = $5}
  /Number of section headers/ {n = $5}
  END {print s + z * n}')
unsquashfs -q -no-xattrs -o "$offset" -d appdir %{SOURCE0} \
  usr/bin/EpicGamesLauncher \
  usr/lib/libEOSSDK-Linux-Shipping.so \
  usr/lib/%{appname} \
  usr/share/icons
if ! grep -aqF "EpicGamesLauncher/%{epic_version}+g%{epic_gitrev}" appdir/usr/bin/EpicGamesLauncher; then
  echo "Версия в AppImage не совпадает с %{epic_version}+g%{epic_gitrev}" >&2
  exit 1
fi

%build
cd %{srcname}
%set_build_flags
tray/build.sh tray-build
cd proton-gui
cargo build --release --offline --locked

%install
# EOS SDK собран Epic с ${ORIGIN}-путями Unreal Engine; check-rpaths считает их
# невалидными (0x0002) и неправильно упорядоченными (0x0008). Файл не меняем.
export QA_RPATHS=$(( 0x0002 | 0x0008 ))

cd appdir
install -Dpm0755 usr/bin/EpicGamesLauncher %{buildroot}%{_bindir}/EpicGamesLauncher
# RUNPATH бинарника: $ORIGIN/../lib, то есть /usr/lib.
install -Dpm0755 usr/lib/libEOSSDK-Linux-Shipping.so \
  %{buildroot}%{_prefix}/lib/libEOSSDK-Linux-Shipping.so
# Tauri ищет ресурсы в <каталог бинарника>/../lib/<имя пакета>.
install -dm0755 %{buildroot}%{_prefix}/lib/%{appname}
cp -a usr/lib/%{appname}/. %{buildroot}%{_prefix}/lib/%{appname}/
chmod 0755 %{buildroot}%{_prefix}/lib/%{appname}/libEOSSDK-Linux-Shipping.so
for icon in usr/share/icons/hicolor/*/apps/EpicGamesLauncher.png; do
  install -Dpm0644 "$icon" "%{buildroot}%{_datadir}/${icon#usr/share/}"
done

cd ../%{srcname}
for script in egl-launch egl-proton-hook egl-proton-router; do
  install -Dpm0755 libexec/$script %{buildroot}%{_libexecdir}/egl-fedora/$script
done
sed 's|@UPDATE_REPO@|%{update_repo}|g' libexec/egl-update >egl-update
install -Dpm0755 egl-update %{buildroot}%{_libexecdir}/egl-fedora/egl-update
install -Dpsm0755 proton-gui/target/release/egl-proton %{buildroot}%{_bindir}/egl-proton
install -Dpsm0755 tray-build/libayatana-appindicator3.so.1 \
  %{buildroot}%{_libdir}/egl-fedora/tray/libayatana-appindicator3.so.1

for unit in egl-fedora-update.service egl-fedora-update.timer; do
  sed 's|@UPDATE_REPO@|%{update_repo}|g' data/systemd/system/$unit >$unit
  install -Dpm0644 $unit %{buildroot}%{_unitdir}/$unit
done
for unit in egl-fedora-proton-hook.path egl-fedora-proton-hook.service; do
  install -Dpm0644 data/systemd/user/$unit %{buildroot}%{_userunitdir}/$unit
done
install -Dpm0644 data/systemd/system-preset/80-egl-fedora.preset \
  %{buildroot}%{_presetdir}/80-egl-fedora.preset
install -Dpm0644 data/systemd/user-preset/80-egl-fedora.preset \
  %{buildroot}%{_userpresetdir}/80-egl-fedora.preset

desktop-file-install --dir=%{buildroot}%{_datadir}/applications \
  data/applications/%{appname}.desktop \
  data/applications/io.github.dxvsi.EglProton.desktop

install -dm0755 %{buildroot}%{_sharedstatedir}/egl-fedora

%check
cd %{srcname}
tests/proton-hook-test.sh
(cd proton-gui && cargo test --release --offline --locked)
desktop-file-validate %{buildroot}%{_datadir}/applications/*.desktop

%post
%systemd_post egl-fedora-update.timer
%systemd_user_post egl-fedora-proton-hook.path
# Presets применяются один раз, в том числе при обновлении с пакета без этих юнитов.
# Если владелец потом выключит таймер, повторно он не включится.
if [ ! -e %{_sharedstatedir}/egl-fedora/presets-applied ]; then
  systemctl preset egl-fedora-update.timer >/dev/null 2>&1 || :
  systemctl --global preset egl-fedora-proton-hook.path >/dev/null 2>&1 || :
  systemctl start egl-fedora-update.timer >/dev/null 2>&1 || :
  touch %{_sharedstatedir}/egl-fedora/presets-applied
fi

%preun
%systemd_preun egl-fedora-update.timer egl-fedora-update.service
%systemd_user_preun egl-fedora-proton-hook.path

%postun
# Без перезапуска: обновление ставит сама egl-fedora-update.service.
%systemd_postun egl-fedora-update.timer egl-fedora-update.service
%systemd_user_postun egl-fedora-proton-hook.path

%files
%license %{srcname}/LICENSE
%doc %{srcname}/README.md
%{_bindir}/EpicGamesLauncher
%{_bindir}/egl-proton
%{_prefix}/lib/libEOSSDK-Linux-Shipping.so
%{_prefix}/lib/%{appname}/
%{_libexecdir}/egl-fedora/
%{_libdir}/egl-fedora/
%{_unitdir}/egl-fedora-update.service
%{_unitdir}/egl-fedora-update.timer
%{_userunitdir}/egl-fedora-proton-hook.path
%{_userunitdir}/egl-fedora-proton-hook.service
%{_presetdir}/80-egl-fedora.preset
%{_userpresetdir}/80-egl-fedora.preset
%{_datadir}/applications/%{appname}.desktop
%{_datadir}/applications/io.github.dxvsi.EglProton.desktop
%{_datadir}/icons/hicolor/*/apps/EpicGamesLauncher.png
%dir %{_sharedstatedir}/egl-fedora
%ghost %attr(0644,root,root) %{_sharedstatedir}/egl-fedora/presets-applied

%changelog
* Fri Oct 16 2026 DXVSI <DXVSI@users.noreply.github.com> - 0.96.1-4.gite3e236d
- Show the Proton window and notification in English, or in Russian on a Russian locale
- Write log and update messages in English

* Fri Oct 16 2026 DXVSI <DXVSI@users.noreply.github.com> - 0.96.1-3.gite3e236d
- Rename the Proton window to "Epic Games: Proton selection" so it sits next to Epic in the menu
- Notify once per game which Proton it runs on, with a button to change it
- Add "Choose Proton for games" to the Epic tray menu

* Fri Oct 16 2026 DXVSI <DXVSI@users.noreply.github.com> - 0.96.1-2.gite3e236d
- egl-fedora: automatic updates from GitHub Releases and Proton selection
- Repackage official AppImage 0.96.1+ge3e236d
