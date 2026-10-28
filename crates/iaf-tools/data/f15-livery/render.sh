#!/bin/sh
# Dev only: rasterises the F-15 livery's markings (our SVGs) into the PNGs the converter composites
# (crates/iaf-tools/src/f15.rs, docs/aircraft-models.md §6.1). About 1 mm per pixel (the band 2.5 mm).
# Needs rsvg-convert (librsvg); setup itself only reads the PNGs.
set -e
cd "$(dirname "$0")"
for spec in roundel:600 kills:820 name_802:470 serial_nose:290 serial_fin:680 emblem_802:130 bird:940 band_133:960; do
	rsvg-convert -w "${spec#*:}" "${spec%%:*}.svg" -o "${spec%%:*}.png"
done
