#!/bin/bash

# Raycast Script Command: copy the share link of the best Google Drive match
# for a query, without opening a terminal.
#
# This one reads the Drive folders from Raycast itself, so on the first run
# macOS asks whether Raycast may access files managed by Google Drive (once per
# Drive account). Click Allow. If every account is denied, drivethru exits 6;
# individual denied accounts are skipped with a warning. Both the picker and
# this command need fzf. See docs/hotkeys.md for setup and troubleshooting.
#
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Copy Google Drive Link
# @raycast.mode compact
#
# Optional parameters:
# @raycast.packageName drivethru
# @raycast.argument1 { "type": "text", "placeholder": "Search Google Drive" }
# @raycast.description Copy the share link of the top drivethru search result.

# Raycast runs scripts in a non-login shell and only appends /usr/local/bin to
# PATH, so add the usual Homebrew and user locations.
export PATH="/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:$HOME/.local/bin:$PATH"

if ! command -v drivethru >/dev/null 2>&1; then
  printf '%s\n' "drivethru is not installed (or not on PATH)"
  exit 1
fi

errfile=$(/usr/bin/mktemp -t drivethru-raycast) || exit 1
trap '/bin/rm -f "$errfile"' EXIT

out=$(drivethru search --copy-first -- "${1:-}" 2>"$errfile")
rc=$?

# Compact mode shows the last stdout line in Raycast's toast, on success and
# on failure alike, so print exactly one line either way.
if [ "$rc" -ne 0 ]; then
  msg=$(/usr/bin/tail -n 1 "$errfile")
  printf '%s\n' "${msg:-drivethru search failed (exit $rc)}"
  exit "$rc"
fi

# Preserve successful warnings too: a skipped account, Form editor URL or
# fallback shortcut link matters even when a link reached the clipboard.
# Keep the toast to one line so Raycast does not hide all but its last line.
warning=$(/usr/bin/sed '/^drivethru: debug:/d; /^drivethru: dry-run:/d; /^$/d' "$errfile" |
  /usr/bin/tr '\n' ' ')
warning=${warning% }
if [ -n "$warning" ]; then
  printf 'Copied %s — %s\n' "${out##*$'\n'}" "$warning"
else
  printf 'Copied %s\n' "${out##*$'\n'}"
fi
