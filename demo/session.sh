#!/bin/bash
# Sourced by VHS only. All data and actions are redirected to a synthetic tree.
# Result cards below are illustrations, built from the real dry-run output.

demo_scene=${1:?expected copy, accounts or markdown}
case "$demo_scene" in copy | accounts | markdown) ;; *) return 1 ;; esac
demo_repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd) || return 1
demo_tmp=$(mktemp -d "${TMPDIR:-/tmp}/drivethru-recording.XXXXXX") || return 1
trap 'rm -rf "$demo_tmp"' EXIT
"$demo_repo/demo/make-demo-tree.sh" "$demo_tmp/tree" >/dev/null || return 1
export DRIVETHRU_ROOT="$demo_tmp/tree/CloudStorage"
export DRIVETHRU_CHROME_DIR="$demo_tmp/tree/Chrome"
export DRIVETHRU_DRIVEFS_DIR="$demo_tmp/tree/DriveFS"
export DRIVETHRU_CONFIG="$demo_tmp/tree/config"
export DRIVETHRU_CLIPBOARD_FILE="$demo_tmp/clipboard"
export DRIVETHRU_DRY_RUN=1
PS1='$ '
PROMPT_COMMAND=''

demo_title() {
  printf '\033[H\033[2J\n\033[1;32m  %s\033[0m\n\n' "$1"
}

demo_result() {
  local line label url route profile email profile_name
  case "$demo_scene" in
    copy)
      [ -s "$demo_tmp/clipboard" ] || return 1
      demo_title 'READY TO PASTE'
      printf '  \033[1mClipboard preview\033[0m  ·  simulated copy\n\n'
      printf '  \033[36m%s\033[0m\n' "$(cat "$demo_tmp/clipboard")"
      printf '\n\n  One search. One key. A link you can paste anywhere.\n'
      ;;
    markdown)
      [ -s "$demo_tmp/clipboard" ] || return 1
      demo_title 'TWO LINKS, ONE PASTE'
      printf '  \033[1mMarkdown paste preview\033[0m  ·  simulated copy\n\n'
      while IFS= read -r line || [ -n "$line" ]; do
        label=${line#\[}; label=${label%%\]*}
        url=${line#*\]\(}; url=${url%\)}
        printf '  \033[4;36m%s\033[0m\n' "$label"
        printf '  \033[2m%s\033[0m\n\n' "$url"
      done <"$demo_tmp/clipboard"
      printf '\n  File names and URLs copied together as Markdown.\n'
      ;;
    accounts)
      route=$(sed -n '/^drivethru: dry-run: open /p' "$demo_tmp/actions")
      case "$route" in *--profile-directory=*--profile-email=*) ;; *) return 1 ;; esac
      profile=${route#*--profile-directory=}; profile=${profile%% --*}
      profile_name=$(/usr/bin/plutil -extract "profile.info_cache.$profile.name" raw -o - "$DRIVETHRU_CHROME_DIR/Local State") || return 1
      email=${route#*--profile-email=}; email=${email%% *}
      url=${route##* }
      demo_title 'MATCHING CHROME PROFILE'
      printf '  \033[1mBrowser routing preview\033[0m  ·  simulated open\n\n'
      printf '  \033[36m%s\033[0m\n' "$email"
      printf '             │\n             ▼\n'
      printf '  \033[1;32mChrome profile: %s\033[0m\n\n' "$profile_name"
      printf '  %s\n' "${url%%\?*}"
      printf '  \033[36m?%s\033[0m\n' "${url#*\?}"
      printf '\n  Work file → work account.\n'
      ;;
  esac
}

drivethru() {
  local result=0
  "$demo_repo/drivethru" "$@" >"$demo_tmp/stdout" 2>"$demo_tmp/actions" || result=$?
  if [ "$result" -eq 0 ]; then
    demo_result || result=$?
  fi
  if [ -n "${DRIVETHRU_DEMO_CAPTURE:-}" ]; then
    cp "$demo_tmp/actions" "$DRIVETHRU_DEMO_CAPTURE/actions"
    [ ! -f "$demo_tmp/clipboard" ] || cp "$demo_tmp/clipboard" "$DRIVETHRU_DEMO_CAPTURE/clipboard"
    printf '%s\n' "$result" >"$DRIVETHRU_DEMO_CAPTURE/status"
  fi
  [ "$result" -eq 0 ] || cat "$demo_tmp/actions" >&2
  return "$result"
}
printf 'DEMO READY\n'
