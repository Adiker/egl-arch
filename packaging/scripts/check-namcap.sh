#!/usr/bin/env bash
# Keep all diagnostics visible; reject new errors. /opt is an explicit layout
# choice for the unmodified upstream payload, not an accidental misplaced ELF.
set -euo pipefail
work=$(mktemp)
trap 'rm -f "$work"' EXIT
# Arch's merged /usr also exposes bash through /usr/sbin, but package ownership
# records use /usr/bin. Normalize lookup for namcap's shebang ownership rule.
PATH=/usr/bin:$PATH namcap "$@" | tee "$work"
allowed="epic-games-launcher(-proton)?-bin E: ELF files outside of a valid path \('opt/'\)\."
unexpected=$(grep ' E: ' "$work" | grep -vxE "$allowed" || true)
if [[ -n $unexpected ]]; then
  echo 'Unexpected namcap errors; see diagnostics above.' >&2
  exit 1
fi
