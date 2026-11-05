# Automated upstream releases

The `Release upstream DEB` GitHub Actions workflow checks Epic's official
stable metadata every six hours, at minute 17 UTC. GitHub may delay scheduled
runs; the workflow also supports manual dispatch. It runs only on the default
`main` branch in `Adiker/egl-arch`.

Discovery requires agreement between `stable-target.json` and the official
installer redirect. Only the known numeric version plus git-revision format is
accepted. Downgrades and silent content changes under the same version fail for
manual review. A DEB checksum is measured over HTTPS, not presented as an
upstream signature.

A new upstream version resets `pkgrel` to 1. A changed upstream git revision with
the same numeric version or a source-format migration increments `pkgrel`. The workflow downloads the pinned
DEB, updates its SHA256, and regenerates the deterministic port-source
archive, checksum and `.SRCINFO`. DEB installer scripts are never executed.

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
renames leading-dot asset names, so the source-build metadata asset is named
`SRCINFO`. The separate prebuilt AUR recipe has its own generated `.SRCINFO`.
A failed draft can be completed by the next run. Existing published assets and tags are
not overwritten. A complete release is skipped by scheduled checks.

The first run can complete an existing source-only release without changing its
tag or source archive. Manual `build_current=true` also rebuilds an already
complete version for validation; publishing will still refuse to replace any
different existing asset. For changed integration sources, increase `pkgrel`
and refresh source metadata before dispatching, rather than modifying an existing
release's source archive.

The separate `Sync AUR package` workflow checks the latest published GitHub
release after successful release checks and every six hours as a retry. It
validates the release package checksum and matching package metadata, refuses
downgrades and unexpected recipe or dependency changes, repackages with makepkg,
and pushes only PKGBUILD and .SRCINFO to AUR. After confirming the AUR Git
HEAD matches the checked or pushed commit, it records the verified commit in the
release notes. A newly published release initially says synchronization is
pending; a failure leaves it pending until a successful retry. The note records
a point-in-time verification, not a guarantee against later external changes.
The sync workflow requires GitHub contents-write permission to edit the note.
It needs a dedicated AUR SSH key
registered with the maintainer account and the private key in the GitHub Actions
secret `AUR_SSH_PRIVATE_KEY`. The AUR key can update packages managed by that
account; limit repository access accordingly. The workflow does not install
anything on users' computers or add an updater to the launcher.
Enable Actions if GitHub disables scheduled workflows after repository inactivity.

Manual execution:

```sh
gh workflow run upstream-release.yml --repo Adiker/egl-arch --ref main
gh workflow run aur-sync.yml --repo Adiker/egl-arch --ref main
```
