#!/bin/bash
# Sourced only by teaser.tape. Reuse the isolated fixture and actual CLI capture.
# shellcheck source=demo/session.sh
source "$(dirname "${BASH_SOURCE[0]}")/session.sh" copy || return 1

# Match the illustrative browser pane's folder route while preserving the real
# synthetic file's Drive metadata. All paths remain inside this session's tree.
teaser_folder="$DRIVETHRU_ROOT/GoogleDrive-you@company.com/My Drive/Projects/2026/Q3/Board/Final"
mkdir -p "$teaser_folder" || return 1
mv "$DRIVETHRU_ROOT/GoogleDrive-you@company.com/My Drive/Board/Board Deck - Q3 2026.gslides" \
  "$teaser_folder/Board Deck - Q3 2026.gslides" || return 1

# The split-screen teaser needs a compact result card. The captured clipboard
# still contains the complete, real dry-run URL; only its illustration changes.
demo_result() {
  local name
  [ -s "$demo_tmp/clipboard" ] || return 1
  name=$(sed -n 's/^Copied: //p' "$demo_tmp/actions")
  name=${name%.gslides}
  [ "$name" = 'Board Deck - Q3 2026' ] || return 1
  demo_title 'READY TO PASTE'
  printf '  \033[1;36m%s\033[0m\n\n' "$name"
  printf '  Clipboard preview\n\n'
}

printf 'TEASER READY\n'
