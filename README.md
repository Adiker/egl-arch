# Epic Games Launcher для Fedora (egl-fedora)

Неофициальный RPM с Epic Games Launcher для Fedora. Проект не связан с Epic Games
и не одобрен ею. Epic Games Launcher и EOS SDK внутри пакета остаются
проприетарным ПО Epic Games.

## Что даёт пакет

- **Epic Games Launcher в меню.** Он взят из официального AppImage и работает
  на системных WebKitGTK 4.1, GTK 3 и libsoup 3, нативно в Wayland.
- **Автообновление.** Раз в час система проверяет последний релиз этого
  репозитория и сама ставит новую версию. Делать ничего не нужно.
- **Выбор Proton.** Окно «Epic Games: выбор Proton» открывается прямо из
  трея Epic. В нём можно выбрать, через какой Proton запускать игры: GE-Proton,
  который скачивает сам Epic, DW-Proton, Proton-CachyOS, Proton из Steam и
  другие. Выбирать можно для всех игр сразу или для каждой игры отдельно.

## Установка

1. Скачайте `epic-games-launcher-*.x86_64.rpm` из последнего
   [релиза](https://github.com/DXVSI/egl-fedora/releases/latest).
2. Установите его двойным щелчком или командой:

   ```fish
   sudo dnf install ./epic-games-launcher-*.x86_64.rpm
   ```

3. Откройте Epic Games Launcher из меню приложений и войдите в аккаунт.

## Выбор Proton

Окно «Epic Games: выбор Proton» открывается тремя способами:

- пунктом «Выбрать Proton для игр» в меню трея Epic (первая строка);
- правой кнопкой по ярлыку Epic Games Launcher в меню приложений, пункт
  «Выбрать Proton»;
- кнопкой «Выбрать Proton» в уведомлении. Оно приходит при первом запуске
  каждой игры и говорит, через какой Proton игра запущена. Если для игры
  Proton уже выбран, уведомления нет.

Отдельного значка в меню приложений у окна нет, чтобы не путать его с самим
лаунчером.

Пункт в трее появляется, когда Epic запущен из меню приложений или по ссылке
`com.epicgames.launcher://`. Если в настройках Epic включён запуск вместе с
системой, Epic стартует напрямую и пункта в трее не будет: тогда окно
открывается правым кликом по ярлыку Epic.

В окне:

- «По умолчанию» задаёт Proton для всех игр.
- В разделе «Игры» можно выбрать отдельный Proton для любой установленной игры.
- Новые версии Proton (DW-Proton, Proton-CachyOS, свежий GE-Proton) удобнее
  всего ставить через [ProtonPlus](https://flathub.org/apps/com.vysp3r.ProtonPlus),
  потом нажать «Обновить» в окне.

Выбор работает, когда Epic уже скачал свой Proton: для этого достаточно один раз
запустить любую Windows-игру. Если выбранный Proton удалить, игра запустится
через Proton от Epic.

Как это устроено: Epic запускает игры файлом `proton` из своего каталога
`~/.local/share/com.epicgames.eglv2/compat/runtime/<версия>/`. Пакет заменяет
этот файл маленькой заглушкой, а оригинал сохраняет рядом как `proton.epic`.
Заглушка смотрит в `~/.config/egl-fedora/proton.conf` и запускает выбранный
Proton. Для DW-Proton, GE-Proton и других сборок с protonfixes она дополнительно
передаёт идентификатор игры, чтобы применились фиксы именно для неё. Журнал
запусков: `~/.local/state/egl-fedora/proton.log`.

Пункт в трее добавляет маленькая библиотека `libayatana-appindicator3.so.1` из
`/usr/lib64/egl-fedora/tray/`. Ярлык Epic ставит этот каталог первым в
`LD_LIBRARY_PATH`, лаунчер загружает библиотеку трея оттуда, она добавляет пункт
в меню и передаёт всё остальное настоящей системной библиотеке. Бинарник Epic
не меняется.

## Обновления

Проверить вручную:

```fish
sudo /usr/libexec/egl-fedora/egl-update --check
```

Выключить автообновление:

```fish
sudo systemctl disable --now egl-fedora-update.timer
```

Встроенное самообновление лаунчера в RPM-установке не работает: Epic
поддерживает его только для .deb и AppImage. Новые версии приходят через этот
репозиторий.

## Удаление

```fish
sudo dnf remove epic-games-launcher
```

Игры и настройки Epic остаются в `~/.local/share/com.epicgames.eglv2`. После
удаления пакета игры запускаются через Proton от Epic.

## Сборка

Нужны Fedora, `rpm-build`, `squashfs-tools`, `cargo`, `gcc`, `gtk3-devel`,
`gtk4-devel`, `libadwaita-devel`, `libayatana-appindicator-gtk3`, `patchelf`,
`desktop-file-utils`, `jq` и `curl`.

```fish
packaging/scripts/build-rpm.sh build
```

Скрипт скачивает официальный AppImage текущей стабильной версии, собирает
архив исходников с vendored crates и RPM в `build/RPMS/x86_64/`.

Тесты скриптов Proton идут в `%check`. Пункт в трее проверяется отдельно на
рабочем столе: `tests/tray-shim-check.sh`.

## Релизы

Релизы создаёт GitHub Actions (`.github/workflows/release.yml`). Каждые 4 часа
он проверяет версию Epic. Если для пары «версия Epic + ревизия упаковки» ещё нет
релиза, он собирает RPM и создаёт черновик релиза с `SHA256SUMS` и attestation.
Черновик публикует владелец, после этого обновление получают все установки.

Ревизия упаковки хранится в `packaging/RELEASE`. Чтобы выпустить изменения
этого репозитория без новой версии Epic, увеличьте её.

## Лицензия

Код этого репозитория распространяется под MIT, см. [LICENSE](LICENSE).
