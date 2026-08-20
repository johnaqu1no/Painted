#!/usr/bin/env bash
# Turns one screenshot into the exact sizes App Store Connect accepts for macOS.
#
#   1. Photograph the app however you like — ⌘⇧4 then Space grabs a window.
#   2. tools/store-screenshots.sh ~/Desktop/shot.png
#
# Each output is the shot scaled to fit and padded to the exact pixel size with
# the app's own background, because App Store Connect rejects anything that is
# a pixel off.
set -euo pipefail

SOURCE="${1:?usage: tools/store-screenshots.sh <screenshot.png> [outdir]}"
OUT="${2:-build/store-screenshots}"
BACKGROUND="14171F"

mkdir -p "$OUT"

for size in 1280x800 1440x900 2560x1600 2880x1800; do
    width="${size%x*}"
    height="${size#*x}"
    target="$OUT/sketchy-$size.png"

    sips -Z "$width" "$SOURCE" --out "$OUT/.fit.png" >/dev/null
    sips -p "$height" "$width" --padColor "$BACKGROUND" "$OUT/.fit.png" --out "$target" >/dev/null 2>&1

    echo "$target  $(sips -g pixelWidth -g pixelHeight "$target" | awk '/pixel/ {printf "%s ", $2}')"
done

rm -f "$OUT/.fit.png"
