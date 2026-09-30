#!/bin/bash
# Additional browser/popup regressions, sourced by run.sh. Internal --case
# runs source a private copy without main and stub every launch/notification.
# shellcheck disable=SC2317,SC2329  # helpers are called by run.sh or a case
# shellcheck disable=SC2034  # shared globals are consumed by run.sh or the sourced implementation

if [ "${1:-}" = --case ]; then
  # shellcheck source=/dev/null
  . "$BROWSER_LIBRARY"
  trap cleanup EXIT
  SELF=$BROWSER_SELF
  OPEN=$BROWSER_FAKE_OPEN
  OSASCRIPT=$BROWSER_FAKE_OSASCRIPT
  load_config
  discover_mounts
  detect_terminal() { printf 'terminal'; }
  locate_fzf() { FZF=$BROWSER_FAKE_FZF; }
  # These results are synthetic; never inspect installed applications.
  browser_info() {
    BROWSER_INFO_DONE=1
    DEFAULT_BROWSER=com.google.Chrome.beta
    INSTALLED_CHROMES=' com.google.Chrome com.google.Chrome.beta'
  }
  chrome_profile_for_email() {
    case $1 in *'Chrome Beta') printf 'Beta Profile' ;; *) printf 'Stable Profile' ;; esac
  }
  case $2 in
    missing_channel_doctor | missing_channel_open)
      unset DRIVETHRU_CHROME_DIR
      CFG_BROWSER=chrome-canary
      if [ "$2" = missing_channel_doctor ]; then cmd_doctor; else open_items "$BROWSER_ITEM"; fi
      ;;
    email_route_doctor | email_route_open)
      unset DRIVETHRU_CHROME_DIR
      CFG_BROWSER=chrome-beta
      chrome_profile_for_email() { :; }
      if [ "$2" = email_route_doctor ]; then cmd_doctor; else open_items "$BROWSER_ITEM"; fi
      ;;
    default_channel_doctor | default_channel_open)
      unset DRIVETHRU_CHROME_DIR
      CFG_BROWSER=auto
      if [ "$2" = default_channel_doctor ]; then cmd_doctor; else open_items "$BROWSER_ITEM"; fi
      ;;
    live_hook)
      DRIVETHRU_DRY_RUN=0
      CFG_BROWSER=chrome-beta
      # shellcheck disable=SC2016  # expanded deliberately by after_open's bash
      CFG_AFTER_OPEN='printf "%s|%s|%s\n" "$DRIVETHRU_EMAIL" "$DRIVETHRU_URL" "$DRIVETHRU_PROFILE_DIR" >"$BROWSER_HOOK_LOG"'
      open_items "$BROWSER_ITEM"
      ;;
    failed_open_hook)
      DRIVETHRU_DRY_RUN=0
      CFG_BROWSER=default
      # shellcheck disable=SC2016  # expanded deliberately by after_open's bash
      CFG_AFTER_OPEN='printf "hook ran\n" >"$BROWSER_HOOK_LOG"'
      OPEN=/usr/bin/false
      open_items "$BROWSER_ITEM"
      ;;
    async_error)
      DRIVETHRU_DRY_RUN=0
      export BROWSER_LAUNCH_PID=$$
      # Bash permits overriding an absolute command name. Keep logging in
      # the synthetic test tree instead of writing to the real system log.
      function /usr/bin/logger { printf '%s\n' "$*" >>"$BROWSER_ERROR_LOG"; }
      parse_size 117x31
      launch_applescript terminal "$TERMINAL_SCRIPT" "exec '$SELF' --in-popup 'Project plan'"
      # The fake osascript waits for this marker: waiting synchronously for
      # it inside launch_applescript would deadlock and hit the test timeout.
      : >"$BROWSER_RELEASE"
      ;;
    *) printf 'unknown browser review case: %s\n' "$2" >&2; exit 2 ;;
  esac
  exit $?
fi

run_browser_case() {
  local started ended
  LAST_CMD="browser review case $1"
  started=$(now_ms)
  (
    cd "$RUN_CWD" || exit 97
    with_timeout "$DT_TIMEOUT" /usr/bin/env -i \
      HOME="$FHOME" USER="$T_USER" LOGNAME="$T_USER" PATH="$R_PATH" \
      TMPDIR="$TTMP" LANG=en_US.UTF-8 TERM=dumb \
      DRIVETHRU_ROOT="$R_ROOT" DRIVETHRU_DRIVEFS_DIR="$R_DRIVEFS" \
      DRIVETHRU_CHROME_DIR="$R_CHROME" DRIVETHRU_CONFIG="$R_CFG" \
      DRIVETHRU_DRY_RUN=1 DRIVETHRU_TERMINAL=terminal \
      BROWSER_LIBRARY="$T/browser-library.sh" BROWSER_SELF="$DT_ABS" \
      BROWSER_ITEM="$PA/Plan.gdoc" \
      BROWSER_FAKE_OPEN="$T/browser-open" BROWSER_FAKE_OSASCRIPT="$T/browser-osascript" \
      BROWSER_FAKE_FZF="$T/browser-fzf" BROWSER_HOOK_LOG="$T/browser-hook.log" \
      BROWSER_ERROR_LOG="$T/browser-error.log" BROWSER_NOTIFY_LOG="$T/browser-notify.log" \
      BROWSER_RELEASE="$T/browser-release" \
      /bin/bash "$HERE/review-browser.sh" --case "$1" </dev/null >"$T/stdout" 2>"$T/stderr"
  )
  RC=$?
  ended=$(now_ms)
  ELAPSED_MS=$((ended - started))
  OUT=$(cat "$T/stdout")
  ERR=$(cat "$T/stderr")
  [ "$RC" != 124 ] || bad "timed out after ${DT_TIMEOUT}s"
}

want_browser_no_controls() {
  case $OUT$ERR in
    *$'\033'* | *$'\a'*)
      bad 'terminal output contains ESC or BEL'
      # A failing regression must not replay OSC52 through the test report.
      OUT=$(printf '%s' "$OUT" | LC_ALL=C tr -d '\000-\010\013-\037\177')
      ERR=$(printf '%s' "$ERR" | LC_ALL=C tr -d '\000-\010\013-\037\177')
      ;;
  esac
}

g_review_browser() {
  # Sourcing the implementation without its entry point exposes decisions
  # for simulated installation/permission failures, without production hooks.
  sed '/^main "\$@"$/d' "$DT" >"$T/browser-library.sh"
  cat >"$T/browser-fzf" <<'SH'
#!/bin/bash
printf '0.42.0 (synthetic)\n'
SH
  cat >"$T/browser-open" <<'SH'
#!/bin/bash
exit 0
SH
  cat >"$T/browser-osascript" <<'SH'
#!/bin/bash
if [ "$1" = - ]; then
  while [ ! -e "$BROWSER_RELEASE" ]; do sleep 0.02; done
  while kill -0 "$BROWSER_LAUNCH_PID" 2>/dev/null; do sleep 0.02; done
  cat >/dev/null
  printf 'Not authorized to send Apple events to Terminal. (-1743)\n' >&2
  exit 174
fi
printf '%s\n' "$*" >>"$BROWSER_NOTIFY_LOG"
SH
  chmod +x "$T/browser-fzf" "$T/browser-open" "$T/browser-osascript"

  begin "review browser: doctor rejects an unavailable forced Chrome channel"
  run_browser_case missing_channel_doctor
  want_rc 1
  want_out_has "Google Chrome Canary isn't installed"
  want_out_lacks 'No problems found'
  want_out_lacks 'opens in Google Chrome profile'
  end

  begin "review browser: open rejects the same unavailable forced channel"
  run_browser_case missing_channel_open
  want_rc 1
  want_err_has "Google Chrome Canary isn't installed"
  want_dry_lacks_re 'open '
  end

  begin "review browser: forced Chrome without a profile uses email routing in doctor"
  run_browser_case email_route_doctor
  want_rc 0
  want_out_has "$EMAIL_A has no Google Chrome Beta profile; Chrome picks the profile by email"
  want_out_lacks 'default browser with authuser'
  end

  begin "review browser: forced Chrome without a profile opens by email"
  run_browser_case email_route_open
  want_rc 0
  want_dry_re "open -n -b com.google.Chrome.beta --args --profile-email=$EMAIL_A "
  want_dry_lacks_re 'profile-directory='
  end

  begin "review browser: doctor prefers the default Chrome channel"
  run_browser_case default_channel_doctor
  want_rc 0
  want_out_has "$EMAIL_A opens in Google Chrome Beta profile \"Beta Profile\""
  end

  begin "review browser: open prefers the same default Chrome channel"
  run_browser_case default_channel_open
  want_rc 0
  want_dry_re 'open -n -b com.google.Chrome.beta --args --profile-directory=Beta Profile '
  end

  begin "review browser: doctor rejects an invalid terminal environment override"
  XENV=(DRIVETHRU_TERMINAL=kity)
  run_dt doctor
  want_rc 1
  want_out_has 'unknown terminal "kity"'
  want_out_lacks 'ok    popup terminal:'
  want_out_lacks 'No problems found'
  end

  begin "review browser: popup reports an invalid terminal to a hotkey caller"
  XENV=(DRIVETHRU_TERMINAL=kity)
  run_dt popup
  want_rc 1
  want_dry_re 'notify .*unknown terminal "kity"'
  want_dry_lacks_re 'open |osascript '
  end

  begin "review browser: config errors produce a notification before popup launch"
  cfg 'browser = firefox'
  run_dt popup
  want_rc 1
  want_dry_re 'notify Config error: browser = firefox'
  want_err_has 'config error'
  want_dry_lacks_re 'open |osascript '
  end

  begin "review browser: dry-run leaves the after_open command unexecuted"
  cfg "browser = default" "after_open = touch '$T/browser-dry-hook'"
  run_dt open "$PA/Plan.gdoc"
  want_rc 0
  want_dry_re 'after_open touch '
  want_absent "$T/browser-dry-hook"
  end

  local osc=$'\033]52;c;dGVz\a' control_email
  begin "review browser: doctor strips terminal controls from account names and config errors"
  control_email="user${osc}@example.com"
  R_ROOT=$T/browser-control-mounts
  mkdir -p "$R_ROOT/GoogleDrive-$control_email"
  cfg 'browser = default' "label.$control_email = account$osc" "terminal = invalid$osc"
  run_dt doctor
  want_rc 1
  want_out_has 'account]52;'
  want_out_has 'user]52;'
  want_out_has 'terminal = invalid]52;'
  want_browser_no_controls
  end

  begin "review browser: popup dry-run strips terminal controls from the query"
  cfg 'terminal = iterm2'
  run_dt popup "Project$osc"
  want_rc 0
  want_err_has 'Project]52;'
  want_browser_no_controls
  end

  begin "review browser: after_open dry-run strips terminal controls from the command"
  cfg 'browser = default' "after_open = printf '$osc'"
  run_dt open "$PA/Plan.gdoc"
  want_rc 0
  want_err_has "after_open printf ']52;"
  want_browser_no_controls
  end

  begin "review browser: live after_open receives account, URL and profile after a stubbed launch"
  run_browser_case live_hook
  want_rc 0
  if [ -f "$T/browser-hook.log" ]; then
    local hook
    hook=$(cat "$T/browser-hook.log")
    case $hook in
      "$EMAIL_A|$(doc_url "$A_PLAN")?authuser="*'|Stable Profile') ;;
      *) bad "unexpected hook environment: $hook" ;;
    esac
  else
    bad 'live after_open did not execute'
  fi
  rm -f "$T/browser-hook.log"
  end

  begin "review browser: failed browser launch does not execute after_open"
  run_browser_case failed_open_hook
  want_rc 1
  want_absent "$T/browser-hook.log"
  end

  local terminal query expected
  query="Project's plan \$(touch should-not-run)"
  for terminal in iterm2 terminal; do
    begin "review browser: $terminal command preserves popup flag, quoted query and dimensions"
    cfg "terminal = $terminal" 'popup_size = 117x31'
    run_dt popup "$query"
    want_rc 0
    expected=$(printf "'%s'" "$DT_ABS")
    [ "$terminal" != terminal ] || expected="exec $expected"
    expected="$expected --in-popup 'Project'\\''s plan \$(touch should-not-run)' 117x31"
    want_err_has "dry-run: osascript $terminal $expected"
    want_absent "$WORK/should-not-run"
    end
  done

  begin "review browser: detached AppleScript failure logs details and notifies after launcher exits"
  # Production notification and error reporting run against fake osascript
  # and logger; this case never invokes a real app or writes a real log.
  DT_TIMEOUT=5
  run_browser_case async_error
  want_rc 0
  want_faster_than 3000
  local tries=0
  while [ ! -s "$T/browser-notify.log" ] && [ "$tries" -lt 100 ]; do
    sleep 0.02
    tries=$((tries + 1))
  done
  if [ -s "$T/browser-error.log" ]; then
    grep -Fq 'Not authorized to send Apple events to Terminal. (-1743)' "$T/browser-error.log" || bad 'Automation error missing from log'
  else
    bad 'detached failure was not logged'
  fi
  if [ -s "$T/browser-notify.log" ]; then
    grep -Fq "Couldn't open the terminal popup" "$T/browser-notify.log" || bad 'failure notification missing'
  else
    bad 'detached failure did not notify'
  fi
  end
}
