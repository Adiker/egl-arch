# Automated upstream releases

The `Release upstream AppImage` GitHub Actions workflow checks Epic's official
stable metadata every six hours, at minute 17 UTC. GitHub may delay scheduled
runs; the workflow also supports manual dispatch. It runs only on the default
`main` branch in `Adiker/egl-arch`.

Discovery requires agreement between `stable-target.json` and the official
installer redirect. Only the known numeric version plus git-revision format is
accepted. Downgrades and silent content changes under the same version fail for
manual review. An AppImage checksum is measured over HTTPS, not presented as an
upstream signature.

A new upstream version resets `pkgrel` to 1. A changed upstream git revision with
the same numeric version increments `pkgrel`. The workflow downloads the pinned
AppImage, updates its SHA256, and regenerates the deterministic port-source
archive, checksum and `.SRCINFO`. The AppImage itself is never executed.

An unprivileged builder runs makepkg source verification, the full build and
shell/Rust tests inside Arch. Desktop validation, ShellCheck, namcap (with the
documented `/opt` exception), package layout and Epic byte comparisons must pass.
The built package is installed only inside the disposable CI container to check
file integrity, linkage and the Proton panel's CLI. No GUI or actual game launch
is claimed by CI.

After successful validation, a separate job with repository write permission
commits only PKGBUILD and `.SRCINFO`. It refuses to push if `main` changed during
the build. A draft release receives the pacman package, port-source archive,
PKGBUILD, `SRCINFO`, `upstream.json` and `SHA256SUMS` before publication. GitHub
renames leading-dot asset names, so the release uses `SRCINFO`; rename it to
`.SRCINFO` for an AUR checkout. A failed
draft can be completed by the next run. Existing published assets and tags are
not overwritten. A complete release is skipped by scheduled checks.

The first run can complete an existing source-only release without changing its
tag or source archive. Manual `build_current=true` also rebuilds an already
complete version for validation; publishing will still refuse to replace any
different existing asset. For changed integration sources, increase `pkgrel`
and refresh source metadata before dispatching, rather than modifying an existing
release's source archive.

The workflow uses the built-in `GITHUB_TOKEN`; no PAT or AUR SSH key is required.
It does not push to AUR, install anything on users' computers, or add an updater
to the launcher. The AUR PKGBUILD must be updated separately after a release.
Enable Actions if GitHub disables scheduled workflows after repository inactivity.

Manual execution:

```sh
gh workflow run upstream-release.yml --repo Adiker/egl-arch --ref main
```
