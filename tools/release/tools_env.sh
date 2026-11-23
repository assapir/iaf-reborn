#!/usr/bin/env bash
# The outside programs setup runs, for a release bundle (docs/release.md §1 "The setup tools"): GDAL's command-line
# tools (gdalwarp, gdal_translate, gdalbuildvrt, gdalinfo, ogr2ogr) and curl, from conda-forge's builds (libgdal-core,
# curl), so a player installs neither. Written into <dest> in one layout on every system: bin/ (the programs; on
# Windows their DLLs too), lib/, share/gdal, share/proj, ssl/cacert.pem, licenses/<package>/ (each package's own).
# Settings._use_bundled_tools puts bin/ first on the PATH and sets GDAL_DATA / PROJ_DATA / the CA bundle at start.
#   tools/release/tools_env.sh <dest>
# Needs curl, jq and a network; micromamba is fetched into a temp folder.
set -euo pipefail
dest=${1:?usage: tools/release/tools_env.sh <dest>}
MAMBA=2.10.0-0  # micromamba release (github.com/mamba-org/micromamba-releases)
GDAL=3.13.3     # libgdal-core, the GDAL the checkout's setup is checked with
case $(uname -s)-$(uname -m) in
Linux-x86_64) plat=linux-64 ;;
Darwin-arm64) plat=osx-arm64 ;;
MINGW*-x86_64 | MSYS*-x86_64 | CYGWIN*-x86_64) plat=win-64 ;;
*) echo "tools_env: unsupported system $(uname -s)-$(uname -m)" >&2; exit 2 ;;
esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
exe=micromamba
[[ $plat == win-64 ]] && exe=micromamba.exe
url=https://github.com/mamba-org/micromamba-releases/releases/download/$MAMBA/micromamba-$plat
curl -fsSL --retry 3 -o "$work/$exe" "$url"
want=$(curl -fsSL --retry 3 "$url.sha256" | cut -d' ' -f1)
got=$( (sha256sum "$work/$exe" 2>/dev/null || shasum -a 256 "$work/$exe") | cut -d' ' -f1)
[[ $want == "$got" ]] || { echo "tools_env: micromamba checksum mismatch" >&2; exit 1; }
chmod +x "$work/$exe"
export MAMBA_ROOT_PREFIX="$work/root" CONDA_PKGS_DIRS="$work/pkgs"
env="$work/env"
"$work/$exe" create -q -y -p "$env" -c conda-forge --override-channels "libgdal-core=$GDAL" curl ca-certificates
rm -rf "$dest"
mkdir -p "$dest/bin" "$dest/share" "$dest/ssl" "$dest/licenses"
if [[ $plat == win-64 ]]; then
	src="$env/Library"
	cp "$src"/bin/*.exe "$src"/bin/*.dll "$dest/bin/"
	# The MSVC / UCRT runtime (vc14_runtime, ucrt) sits in the environment's root.
	for f in "$env"/*.dll; do [[ -f $f ]] && cp "$f" "$dest/bin/"; done
else
	src="$env"
	cp -RP "$src/lib" "$dest/lib"
	rm -rf "$dest"/lib/{pkgconfig,cmake} "$dest"/lib/*.a "$dest"/lib/*.la
	cp -P "$src"/bin/{gdal*,ogr*,curl} "$dest/bin/"
	rm -f "$dest"/bin/*-config
fi
cp -R "$src/share/gdal" "$src/share/proj" "$dest/share/"
for c in "$src/ssl/cacert.pem" "$env/ssl/cacert.pem"; do
	[[ -f $c ]] && { cp "$c" "$dest/ssl/cacert.pem"; break; }
done
# Each package's licence files, as conda-forge ships them (GDAL MIT, PROJ MIT, curl's, GEOS LGPL-2.1…), and
# SOURCES.txt: every package's exact build, licence and download, where its source and recipe are.
{
	echo "The programs in this folder are conda-forge's builds (https://conda-forge.org), unchanged. Each package's"
	echo "source code and build recipe: https://github.com/conda-forge/<name>-feedstock at the version below, and"
	echo "the package file itself (its recipe inside, info/recipe) at its URL. On request we send the source of any"
	echo "package below, for three years from this build: open an issue at https://github.com/assapir/iaf-reborn."
	echo
	echo "name version build licence url"
} >"$dest/SOURCES.txt"
for m in "$env"/conda-meta/*.json; do
	jq -r '[.name, .version, .build, (.license // "?"), .url] | join(" ")' "$m" >>"$dest/SOURCES.txt"
	name=$(jq -r .name "$m")
	pkg=$(jq -r '.extracted_package_dir // ""' "$m")
	[[ -d $pkg ]] || pkg=$CONDA_PKGS_DIRS/$(jq -r '"\(.name)-\(.version)-\(.build)"' "$m")
	if [[ -n $pkg && -d $pkg/info/licenses ]]; then
		mkdir -p "$dest/licenses/$name" && cp -R "$pkg/info/licenses/." "$dest/licenses/$name/"
	fi
done
cat "$dest/SOURCES.txt"
[[ -d $dest/licenses/libgdal-core && -d $dest/licenses/curl ]] || { echo "tools_env: licence files missing" >&2; exit 1; }
"$dest/bin/ogr2ogr" --version
du -sh "$dest"
