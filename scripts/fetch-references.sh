#!/usr/bin/env bash
# Re-vendor the reference repositories listed in references/SOURCES.md.
# Usage: scripts/fetch-references.sh [dir...]   (default: all)
# Clones at the upstream branch tip, strips .git, prints the new commit so
# SOURCES.md can be updated. Review the diff before committing.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)/references"

declare -A REPO=(
  [cdc-badge-development]="krim404/cdc-badge-development main"
  [cdc-badge-os]="krim404/cdc-badge-os release"
  [cdc-badge-plugins]="krim404/cdc-badge-plugins main"
  [cdc-badge-nametag]="riatlabs/cdc-badge-nametag main"
  [cdc-badge-hardware]="riatlabs/cdc-badge main"
  [libtropic-arduino]="tropicsquare/libtropic-arduino main"
  [TCA9555]="robtillaart/TCA9555 master"
  [GxEPD2]="ZinggJM/GxEPD2 master"
  [Adafruit-GFX-Library]="adafruit/Adafruit-GFX-Library master"
)

dirs=("$@"); [ ${#dirs[@]} -eq 0 ] && dirs=("${!REPO[@]}")
for d in "${dirs[@]}"; do
  read -r repo branch <<<"${REPO[$d]:?unknown reference $d}"
  tmp=$(mktemp -d)
  git clone -q --depth 1 -b "$branch" "https://github.com/$repo" "$tmp/src"
  sha=$(git -C "$tmp/src" rev-parse HEAD)
  rm -rf "$tmp/src/.git" "$d"
  mv "$tmp/src" "$d"
  rmdir "$tmp"
  printf '%-24s %s@%s %s\n' "$d" "$repo" "$branch" "$sha"
done
git add -f -A .
