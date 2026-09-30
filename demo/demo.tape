# drivethru demo GIF, recorded with charmbracelet VHS (brew install vhs).
#
# Run from the repository root:
#
#   vhs demo/demo.tape
#
# It records against a synthetic Drive tree built by demo/make-demo-tree.sh
# (two made-up accounts, you@company.com and you@gmail.com) in a temp dir, with
# DRIVETHRU_DRY_RUN=1, so nothing real is listed, copied or opened. Never
# `vhs publish` a recording made against real Drive folders.

Output demo/demo.gif

Require fzf
Require openssl

Set Shell "bash"
# About 115 columns, so the picker header (every key) and the links fit on one line.
Set FontSize 17
Set Width 1360
Set Height 600
Set Padding 24
Set Theme "Catppuccin Mocha"
Set WindowBar Colorful
Set CursorBlink false
Set TypingSpeed 75ms

# --- Setup (not recorded) ----------------------------------------------------
Hide
Type@5ms `export DEMO="$(mktemp -d "${TMPDIR:-/tmp}/drivethru-demo.XXXXXX")"`
Enter
Type@5ms `demo/make-demo-tree.sh "$DEMO/tree" 2>/dev/null`
Enter
Type@5ms `export DRIVETHRU_ROOT="$DEMO/tree/CloudStorage" DRIVETHRU_CHROME_DIR="$DEMO/tree/Chrome" DRIVETHRU_DRIVEFS_DIR="$DEMO/tree/DriveFS" DRIVETHRU_CONFIG="$DEMO/tree/config" DRIVETHRU_CLIPBOARD_FILE="$DEMO/clipboard" DRIVETHRU_DRY_RUN=1`
Enter
Type@5ms `export PATH="$PWD:$PATH"`
Enter
# Dry-run mode writes the clipboard text to $DRIVETHRU_CLIPBOARD_FILE instead
# of calling pbcopy. Shadow pbpaste so the recording shows what a real run
# would have copied, and never the recording machine's real clipboard.
Type@5ms `pbpaste() { cat "$DRIVETHRU_CLIPBOARD_FILE"; [ -z "$(tail -c 1 "$DRIVETHRU_CLIPBOARD_FILE")" ] || printf '\n'; }`
Enter
# Hide simulated action diagnostics so the recording shows real CLI output.
# Browser actions are simulated (as noted beside the GIF in README.md).
# fzf draws on /dev/tty, so
# only drivethru's own stderr goes through this filter.
Type@5ms `drivethru() { { command drivethru "$@" 2>&1 1>&3 3>&- | grep -v "^drivethru: dry-run: " >&2; } 3>&1; }`
Enter
Type@5ms "clear"
Enter
Sleep 300ms
Show

# --- 1. Find a file and copy its share link ------------------------------------
Type "drivethru"
Sleep 300ms
Enter
Wait+Screen@10s /\d+\/\d+/
Sleep 1.2s
Type@90ms "board deck"
Sleep 1.6s
Enter
Sleep 1.4s
Type "pbpaste"
Sleep 200ms
Enter
Sleep 2.2s

# --- 2. Multi-select and open each item as its own Google account ---------------
Hide
Type@5ms "clear"
Enter
Sleep 200ms
Show
Type "drivethru"
Sleep 300ms
Enter
Wait+Screen@10s /\d+\/\d+/
Sleep 600ms
Type@90ms "budget"
Sleep 1.2s
Tab
Sleep 500ms
Tab
Sleep 900ms
Ctrl+O
Sleep 3.5s

# --- Cleanup (not recorded) --------------------------------------------------
Hide
Type@5ms `rm -rf "$DEMO"`
Enter
Sleep 300ms
