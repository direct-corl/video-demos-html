#!/usr/bin/env bash
# Prune router_demo_offline/GOOD_VIDEOS down to only the run folders that
# router_demo.html actually references. The "used" set is read straight from
# the HTML's  dir:"..."  entries, so this stays in sync if the demo changes.
#
# Usage:
#   ./prune_videos.sh                       # prune the existing GOOD_VIDEOS/ in place
#   ./prune_videos.sh --restore FILE.zip    # unzip FILE first (restores base runs), then prune
#
# NOTE: the two custom clips  fruit_nothink_*  and  fruit_allthink_*  are
# re-encoded (and blurred) and are NOT in GOOD_VIDEOS_small.zip. They are
# included in GOOD_VIDEOS_demo.zip (the pruned, self-contained bundle). If you
# restore from the *small* zip, those two will be reported MISSING — copy them
# from GOOD_VIDEOS_demo.zip or regenerate them.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HTML="$HERE/router_demo.html"
VID="$HERE/GOOD_VIDEOS"

restore=""
[ "${1:-}" = "--restore" ] && restore="${2:-}"

if [ -n "$restore" ]; then
  [ -f "$restore" ] || { echo "zip not found: $restore" >&2; exit 1; }
  echo "Restoring from $restore ..."
  tmp="$(mktemp -d)"
  unzip -q "$restore" -d "$tmp"
  src="$tmp/GOOD_VIDEOS"; [ -d "$src" ] || src="$tmp"   # zips wrap a GOOD_VIDEOS/ dir
  mkdir -p "$VID"
  cp -R "$src/." "$VID/"
  rm -rf "$tmp"
fi

[ -d "$VID" ]  || { echo "no GOOD_VIDEOS folder at $VID" >&2; exit 1; }
[ -f "$HTML" ] || { echo "no router_demo.html at $HTML" >&2; exit 1; }

# 1. collect referenced run folders (relative to GOOD_VIDEOS/)
used="$(mktemp)"
grep -oE 'dir:"[^"]+"' "$HTML" | sed -E 's/^dir:"//; s/"$//' | sort -u > "$used"
echo "Referenced run folders: $(wc -l < "$used" | tr -d ' ')"

# 2. delete every leaf run folder (contains video.mp4) that is NOT referenced
dirs="$(mktemp)"
find "$VID" -mindepth 1 -type d > "$dirs"   # materialise list before deleting
deleted=0
while IFS= read -r d; do
  [ -f "$d/video.mp4" ] || continue
  rel="${d#"$VID"/}"
  if ! grep -qxF "$rel" "$used"; then
    echo "  delete  $rel"
    rm -rf "$d"
    deleted=$((deleted+1))
  fi
done < "$dirs"
rm -f "$dirs"

# 3. inside each kept run folder, keep only the files the demo loads
#    (video.mp4 + wrist_video.mp4); drop meta.json, snapshots, etc.
files_removed=0
while IFS= read -r f; do
  base="$(basename "$f")"
  case "$base" in
    video.mp4|wrist_video.mp4) ;;            # keep
    *) rm -f "$f"; files_removed=$((files_removed+1)) ;;
  esac
done < <(find "$VID" -type f)

# 4. drop any directories left empty (e.g. emptied Science/)
find "$VID" -mindepth 1 -type d -empty -delete

# 4. report referenced folders that are missing on disk
missing=0
while IFS= read -r rel; do
  if [ ! -f "$VID/$rel/video.mp4" ]; then
    echo "  MISSING $rel  (restore or regenerate this folder)"
    missing=$((missing+1))
  fi
done < "$used"
rm -f "$used"

echo "Done. Removed $deleted unused folder(s) and ${files_removed:-0} stray file(s); $missing referenced folder(s) missing."
du -sh "$VID" 2>/dev/null | awk '{print "GOOD_VIDEOS size: " $1}'
