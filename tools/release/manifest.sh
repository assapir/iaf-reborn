#!/usr/bin/env bash
# The release's manifest for the update on start (docs/release.md §7): <dir>/nightly.json lists every bundle in
# <dir> with its game's version, size and SHA-256; the games read it (shared/util/updater.gd, iaf_setup::update).
#   IAF_NIGHTLY=<YYYYMMDD>+<short hash> tools/release/manifest.sh <dir>
# The version is versions.txt's base for the bundle's game + -nightly.$IAF_NIGHTLY, as bundle.sh writes it.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
dir=${1:?usage: IAF_NIGHTLY=<date>+<hash> tools/release/manifest.sh <dir>}
nightly=${IAF_NIGHTLY:?IAF_NIGHTLY=<YYYYMMDD>+<short hash>}
sha() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
{
	echo '{"assets": ['
	sep=""
	for f in "$dir"/*-nightly-*; do
		name=$(basename "$f")
		project=${name%%-nightly-*}
		base=$(awk -v p="$project" '$1 == p {print $2}' "$here/versions.txt")
		[[ -n $base ]] || continue
		printf '%s{"name": "%s", "version": "%s", "size": %d, "sha256": "%s"}\n' \
			"$sep" "$name" "$base-nightly.$nightly" "$(wc -c <"$f")" "$(sha "$f")"
		sep=","
	done
	echo ']}'
} >"$dir/nightly.json"
echo "$dir/nightly.json"
