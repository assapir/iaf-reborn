#!/usr/bin/env bash
# Downloads the missing Survey of Israel 2015 sheets with curl, reusing the data.gov.il WAF token (aws-waf-token)
# your Firefox earned (faster than fetch-mapi2015.sh's browser tabs). Present sheets are skipped; re-run to resume.
#   tools/imagery/fetch-mapi2015-curl.sh [--bases]     (--bases: only the sheets around the airbases)
# When it stops with HTTP 202 the token expired: open the printed link in Firefox once (let the download start,
# then cancel it) and re-run.
set -uo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
bases=0; [[ ${1:-} == --bases ]] && bases=1
BASES="shf nzr nzl gdr rng rsh mzr hrd hlz"
dest=$repo/assets/source/imagery/mapi2015
list=$repo/tools/imagery/mapi2015_sheets.tsv
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
token=""
for p in ~/.mozilla/firefox/*/cookies.sqlite; do
	cp "$p" "$tmp/c.sqlite" 2>/dev/null || continue
	t=$(python3 -c "
import sqlite3
c = sqlite3.connect('$tmp/c.sqlite')
r = c.execute(\"select value from moz_cookies where host like '%data.gov.il' and name = 'aws-waf-token' order by expiry desc limit 1\").fetchone()
print(r[0] if r else '')")
	[[ -n $t ]] && token=$t
done
[[ -z $token ]] && { echo "no aws-waf-token for data.gov.il in Firefox: open one sheet link in Firefox first"; exit 1; }
UA="Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"
mkdir -p "$dest"
ok=0; bad=0
while IFS=$'\t' read -r name url; do
	f=${url##*/}
	[[ -s "$dest/$f" ]] && continue
	[[ $bases == 1 && " $BASES " != *" ${f%.zip} "* ]] && continue
	echo "== $f $name"
	code=$(curl -sS -L -A "$UA" -b "aws-waf-token=$token" -o "$dest/$f.part" -w "%{http_code}" "$url")
	if [[ $code == 200 ]] && unzip -tq "$dest/$f.part" >/dev/null 2>&1; then
		mv "$dest/$f.part" "$dest/$f"; ok=$((ok + 1))
	else
		rm -f "$dest/$f.part"; bad=$((bad + 1))
		echo "   failed (HTTP $code) — token expired? open this link in Firefox, cancel the download, re-run:"
		echo "   $url"
		[[ $code == 202 ]] && break
	fi
	sleep 2
done < "$list"
echo "downloaded $ok, failed $bad; $(ls "$dest"/*.zip | wc -l) sheets in $dest"
