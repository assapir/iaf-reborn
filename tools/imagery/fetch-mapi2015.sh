#!/usr/bin/env bash
# Downloads the Survey of Israel 2015 2 m orthophoto sheets (data.gov.il, 79 ZIPs, ~250 MB each, ~20 GB) into
# assets/source/imagery/mapi2015/. data.gov.il sits behind an AWS WAF JavaScript challenge that blocks curl, so the
# links are opened in your web browser (which passes the challenge) a few at a time, and each finished ZIP is
# moved from the browser's download folder into place. Already present sheets are skipped; re-run to resume.
# Licence: data.gov.il open licence, credit "© Survey of Israel 2015, via data.gov.il" (docs/imagery-sources.md §2.1).
#
#   tools/imagery/fetch-mapi2015.sh [--bases] [--batch N] [--downloads DIR]
#     --bases       only the sheets around the airbases (Ramat David, Tel Nof, Ramon; ~2 GB)
#     --batch N     links opened at once (default 4)
#     --downloads   the browser's download folder (default: xdg-user-dir DOWNLOAD, else ~/Downloads)
set -euo pipefail
cd "$(dirname "$0")/../.."
list=tools/imagery/mapi2015_sheets.tsv
dest=assets/source/imagery/mapi2015
batch=4
dl=$(xdg-user-dir DOWNLOAD 2>/dev/null || echo "$HOME/Downloads")
bases=0
while [[ $# -gt 0 ]]; do
	case $1 in
		--bases) bases=1 ;;
		--batch) batch=$2; shift ;;
		--downloads) dl=$2; shift ;;
		*) echo "unknown option $1"; exit 1 ;;
	esac
	shift
done
BASES="shf nzr nzl gdr rng rsh mzr hrd hlz"
mkdir -p "$dest"

urls=()
while IFS=$'\t' read -r name url; do
	f=${url##*/}
	[[ $bases == 1 && " $BASES " != *" ${f%.zip} "* ]] && continue
	[[ -s "$dest/$f" ]] && continue
	urls+=("$url")
done < "$list"
n=${#urls[@]}
[[ $n == 0 ]] && { echo "all sheets present in $dest"; exit 0; }
need=$(( n * 260 ))
free=$(( $(df -Pm "$dest" | awk 'NR==2 {print $4}') ))
echo "$n sheets to fetch (~${need} MB); ${free} MB free on the assets disk"
(( free < need + 2000 )) && { echo "not enough free space (need ~$((need + 2000)) MB incl. conversion headroom)"; exit 1; }

# A finished download: the file exists and the browser's partial file is gone and its size is stable.
finished() {
	local f=$1
	[[ -s "$dl/$f" && ! -e "$dl/$f.part" ]] || return 1
	local a b; a=$(stat -c %s "$dl/$f"); sleep 2; b=$(stat -c %s "$dl/$f")
	[[ $a == "$b" ]]
}

i=0
while (( i < n )); do
	group=("${urls[@]:i:batch}")
	echo "opening ${#group[@]} link(s) in the browser ($((i + 1))–$((i + ${#group[@]})) of $n)…"
	for u in "${group[@]}"; do xdg-open "$u" >/dev/null 2>&1 & sleep 1; done
	for u in "${group[@]}"; do
		f=${u##*/}
		t=0
		until finished "$f"; do
			sleep 5; t=$((t + 5))
			(( t % 60 == 0 )) && echo "  waiting for $f in $dl ($((t / 60)) min)…"
			(( t > 3600 )) && { echo "  $f did not arrive in 60 min; re-run to retry"; exit 1; }
		done
		if unzip -tq "$dl/$f" >/dev/null 2>&1; then
			mv "$dl/$f" "$dest/$f"; echo "  ok $f"
		else
			echo "  $f is not a valid ZIP (challenge page?); removed, re-run to retry"; rm -f "$dl/$f"
		fi
	done
	i=$((i + batch))
done
echo "done: $(ls "$dest"/*.zip 2>/dev/null | wc -l) sheet(s) in $dest"
