#!/bin/bash
# Record the actual picker, verify captured actions, then add readable captions.
set -euo pipefail
cd "$(dirname "$0")/.."

for dependency in vhs ffmpeg swift fzf; do
  command -v "$dependency" >/dev/null || { printf 'Missing: %s\n' "$dependency" >&2; exit 1; }
done
render_tmp=$(mktemp -d "${TMPDIR:-/tmp}/drivethru-render.XXXXXX")
cleanup() {
  local result=$?
  if [ "$result" -ne 0 ]; then
    printf 'Demo rendering failed; captured actions follow, if available.\n' >&2
    for log in "$render_tmp"/*/actions; do
      [ ! -f "$log" ] || cat "$log" >&2
    done
  fi
  rm -rf "$render_tmp"
}
trap cleanup EXIT
[ "$#" -gt 0 ] || set -- copy accounts markdown

for scene in "$@"; do
  case "$scene" in
    copy)
      tape=demo/demo.tape; output=demo/demo.gif
      title='Find it. Copy the link.'
      subtitle='Search across your Drive accounts. Press Enter.'
      keys=Enter
      ;;
    accounts)
      tape=demo/accounts.tape; output=demo/accounts.gif
      title='Open in the right account.'
      subtitle='Add an account label. Open with its Chrome profile.'
      keys=Ctrl-O
      ;;
    markdown)
      tape=demo/markdown.tape; output=demo/markdown.gif
      title='Copy several named links.'
      subtitle='Select files from both accounts. Paste once.'
      keys='Tab|Tab|Ctrl-Y'
      ;;
    *) printf 'Unknown scene: %s (use copy, accounts, markdown)\n' "$scene" >&2; exit 1 ;;
  esac
  mkdir "$render_tmp/$scene"
  export DRIVETHRU_DEMO_CAPTURE="$render_tmp/$scene"
  printf 'Recording %s…\n' "$scene"
  vhs -q -o "$render_tmp/$scene/raw.mp4" "$tape"
  [ "$(cat "$DRIVETHRU_DEMO_CAPTURE/status")" = 0 ]
  case "$scene" in
    copy)
      grep -Eq '^https://docs.google.com/presentation/d/[^/?]+/edit$' "$DRIVETHRU_DEMO_CAPTURE/clipboard"
      grep -Fxq 'Copied: Board Deck - Q3 2026' "$DRIVETHRU_DEMO_CAPTURE/actions"
      ;;
    accounts)
      grep -Eq '^drivethru: dry-run: open .*--profile-directory=Default .*--profile-email=you@company.com https://docs.google.com/spreadsheets/d/[^/?]+/edit\?authuser=you@company.com$' "$DRIVETHRU_DEMO_CAPTURE/actions"
      [ "$(grep -c '^drivethru: dry-run: open ' "$DRIVETHRU_DEMO_CAPTURE/actions")" = 1 ]
      ;;
    markdown)
      grep -Fq '[FY2026 Budget](https://docs.google.com/spreadsheets/d/' "$DRIVETHRU_DEMO_CAPTURE/clipboard"
      grep -Fq '[Household Budget 2026](https://docs.google.com/spreadsheets/d/' "$DRIVETHRU_DEMO_CAPTURE/clipboard"
      [ "$(grep -c '^\[' "$DRIVETHRU_DEMO_CAPTURE/clipboard")" = 2 ]
      ;;
  esac
  swift demo/render-caption.swift --output "$render_tmp/$scene/caption.png" \
    --width 1200 --title "$title" --subtitle "$subtitle" --keys "$keys"
  ffmpeg -hide_banner -loglevel error -y -i "$render_tmp/$scene/raw.mp4" \
    -loop 1 -i "$render_tmp/$scene/caption.png" \
    -filter_complex '[1:v][0:v]vstack=inputs=2:shortest=1,fps=15,split[a][b];[a]palettegen[p];[b][p]paletteuse' \
    -loop 0 "$render_tmp/$scene/final.gif"
  mv "$render_tmp/$scene/final.gif" "$output"
  printf 'Wrote %s\n' "$output"
done
