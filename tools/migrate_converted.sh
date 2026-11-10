#!/usr/bin/env bash
# Moves Modern IAF's built data from its folder's old name, assets/converted/iaf-2026, to assets/converted/modern-iaf
# (the project folder's rename of 2026-11-10), and points the setup's stamps there at the new data path, so nothing is
# built or downloaded again. Run it once after pulling; ./start-modern-iaf, the setup wizard and iaf-sim do the same on
# their first run. Safe to run again.
#   tools/migrate_converted.sh [assets-dir (default: $IAF_ASSETS_DIR, else the repo's assets/)]
set -euo pipefail
c=${1:-${IAF_ASSETS_DIR:-$(dirname "$0")/../assets}}/converted
did=
if [[ -d $c/iaf-2026 && ! -e $c/modern-iaf ]]; then
	mv "$c/iaf-2026" "$c/modern-iaf"
	echo "moved $c/iaf-2026 to $c/modern-iaf"
	did=1
elif [[ -d $c/iaf-2026 ]]; then
	echo "both $c/iaf-2026 and $c/modern-iaf exist: kept $c/modern-iaf; the old folder can be deleted" >&2
fi
for s in "$c"/modern-iaf/*.stamp; do
	[[ -f $s ]] && grep -q '^input iaf-2026/' "$s" || continue
	sed -i.bak 's#^input iaf-2026/#input modern-iaf/#' "$s" && rm "$s.bak"
	echo "rewrote $s"
	did=1
done
[[ $did ]] || echo "nothing to do"
