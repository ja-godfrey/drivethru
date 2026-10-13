#!/bin/bash
# Make the 20-second README teaser from recreated browsers and real pickers.
set -euo pipefail
cd "$(dirname "$0")/.."
for dependency in vhs ffmpeg ffprobe swift fzf; do
  command -v "$dependency" >/dev/null || { printf 'Missing: %s\n' "$dependency" >&2; exit 1; }
done
teaser_tmp=$(mktemp -d "${TMPDIR:-/tmp}/drivethru-teaser.XXXXXX")
cleanup() {
  local result=$?
  if [ "$result" -ne 0 ]; then
    printf 'Teaser rendering failed.\n' >&2
    for log in "$teaser_tmp"/capture-*/actions; do
      [ ! -f "$log" ] || cat "$log" >&2
    done
  fi
  rm -rf "$teaser_tmp"
}
trap cleanup EXIT
mkdir "$teaser_tmp/capture-copy" "$teaser_tmp/capture-accounts" "$teaser_tmp/picker" \
  "$teaser_tmp/accounts" "$teaser_tmp/browser" "$teaser_tmp/account-browser" "$teaser_tmp/composed"
export DRIVETHRU_DEMO_CAPTURE="$teaser_tmp/capture-copy"
printf 'Recording the real picker…\n'
vhs -q -o "$teaser_tmp/picker.mp4" demo/teaser.tape
[ "$(cat "$DRIVETHRU_DEMO_CAPTURE/status")" = 0 ]
grep -Fxq 'Copied: Board Deck - Q3 2026' "$DRIVETHRU_DEMO_CAPTURE/actions"
grep -Eq '^https://docs.google.com/presentation/d/[^/?]+/edit$' "$DRIVETHRU_DEMO_CAPTURE/clipboard"
ffmpeg -hide_banner -loglevel error -i "$teaser_tmp/picker.mp4" \
  -vf fps=15 -start_number 0 "$teaser_tmp/picker/frame-%04d.png"
swift demo/measure-picker.swift --input "$teaser_tmp/picker.mp4" --marker 'READY TO PASTE' --fps 15 \
  >"$teaser_tmp/picker/complete-time.txt"
printf 'Recording search across accounts…\n'
export DRIVETHRU_DEMO_CAPTURE="$teaser_tmp/capture-accounts"
vhs -q -o "$teaser_tmp/accounts.mp4" demo/teaser-accounts.tape
[ "$(cat "$DRIVETHRU_DEMO_CAPTURE/status")" = 0 ]
grep -Eq '^drivethru: dry-run: open .*--profile-directory=Default .*--profile-email=you@company.com https://docs.google.com/spreadsheets/d/[^/?]+/edit\?authuser=you@company.com$' "$DRIVETHRU_DEMO_CAPTURE/actions"
[ "$(grep -c '^drivethru: dry-run: open ' "$DRIVETHRU_DEMO_CAPTURE/actions")" = 1 ]
ffmpeg -hide_banner -loglevel error -i "$teaser_tmp/accounts.mp4" \
  -vf fps=15 -start_number 0 "$teaser_tmp/accounts/frame-%04d.png"
swift demo/measure-picker.swift --input "$teaser_tmp/accounts.mp4" --marker 'OPEN WITH WORK ACCOUNT' --fps 15 \
  >"$teaser_tmp/accounts/complete-time.txt"
printf 'Drawing the folder quest…\n'
swift demo/render-folder-scene.swift --output-dir "$teaser_tmp/browser" --frames 165 --fps 15
swift demo/render-account-scene.swift --output-dir "$teaser_tmp/account-browser" --frames 135 --fps 15
swift demo/compose-teaser.swift --browser-dir "$teaser_tmp/browser" --picker-dir "$teaser_tmp/picker" \
  --account-browser-dir "$teaser_tmp/account-browser" --accounts-dir "$teaser_tmp/accounts" \
  --output-dir "$teaser_tmp/composed" --frames 300 --fps 15
printf 'Encoding GIF and MP4…\n'
ffmpeg -hide_banner -loglevel error -framerate 15 -start_number 0 -i "$teaser_tmp/composed/frame-%04d.png" \
  -filter_complex 'split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle' \
  -loop 0 "$teaser_tmp/teaser.gif"
ffmpeg -hide_banner -loglevel error -framerate 15 -start_number 0 -i "$teaser_tmp/composed/frame-%04d.png" \
  -c:v libx264 -crf 18 -pix_fmt yuv420p -movflags +faststart "$teaser_tmp/teaser.mp4"
duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$teaser_tmp/teaser.gif")
awk -v duration="$duration" 'BEGIN { exit !(duration >= 19.9 && duration <= 20.1) }'
mv "$teaser_tmp/teaser.gif" demo/teaser.gif
mv "$teaser_tmp/teaser.mp4" demo/teaser.mp4
printf 'Wrote demo/teaser.gif and demo/teaser.mp4 (%ss)\n' "$duration"
