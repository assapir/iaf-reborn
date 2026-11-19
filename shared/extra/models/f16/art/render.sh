#!/bin/sh
# Dev only: rasterises the squadrons' art (our SVGs) into the PNGs the game draws on each jet (shared/aircraft/
# tail_number.gd, docs/aircraft-models.md §1.6), 4 mm a pixel. Needs rsvg-convert (librsvg); the game reads only the
# PNGs.
set -e
cd "$(dirname "$0")"
for f in *.svg; do
	rsvg-convert -z 0.25 "$f" -o "${f%.svg}.png"
done
