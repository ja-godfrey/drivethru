# shellcheck shell=bash
# shellcheck disable=SC2034,SC2153  # globals shared with run.sh
#
# Helpers for tests/run.sh. Plain bash 3.2: no associative arrays, no mapfile.
#
# A test looks like:
#
#   begin "link: gdoc"
#   run_dt link "$MA/My Drive/Projects/Plan.gdoc"
#   want_rc 0
#   want_out "$(doc_url "$A_PLAN")"
#   end
#
# Every run of drivethru goes through run_dt, which
#   - starts it in a NEW SESSION with no controlling terminal (like a hotkey
#     daemon), stdin from /dev/null, stdout/stderr to files,
#   - uses a clean environment (env -i) that always points DRIVETHRU_ROOT,
#     DRIVETHRU_DRIVEFS_DIR, DRIVETHRU_CHROME_DIR and DRIVETHRU_CONFIG at the
#     fixture, sets DRIVETHRU_DRY_RUN=1 and HOME to the fixture home,
#   - kills it (and its process group) after DT_TIMEOUT seconds, without
#     coreutils `timeout`.

N_PASS=0
N_FAIL=0
N_SKIP=0
FAILED=""
CUR=""
CUR_ERRS=""
VERBOSE=${VERBOSE:-0}

# --------------------------------------------------------------- results --
begin() {
  CUR=$1
  CUR_ERRS=""
  # per-test knobs, reset every time
  XENV=()
  RUN_CWD=$WORK
  R_ROOT=$ROOT
  R_DRIVEFS=$DRIVEFS
  R_CHROME=$CHROME
  R_CFG=$CFG
  R_PATH=$TEST_PATH
  DT_TIMEOUT=20
  : >"$CFG"
  rm -f "$CLIP"
  RC="" OUT="" ERR="" LAST_CMD=""
}

bad() {
  CUR_ERRS="$CUR_ERRS    - $*
"
}

end() {
  if [ -z "$CUR_ERRS" ]; then
    N_PASS=$((N_PASS + 1))
    printf 'PASS %s\n' "$CUR"
  else
    N_FAIL=$((N_FAIL + 1))
    FAILED="$FAILED$CUR
"
    printf 'FAIL %s\n%s' "$CUR" "$CUR_ERRS" | diagnostic_text
    if [ -n "$LAST_CMD" ]; then
      printf '    cmd: %s\n    rc: %s\n' "$LAST_CMD" "$RC"
      printf '%s\n' "$OUT" | diagnostic_text | head -n 8 | sed 's/^/    stdout| /'
      printf '%s\n' "$ERR" | diagnostic_text | head -n 8 | sed 's/^/    stderr| /'
    fi
  fi
}

# Regression fixtures may contain terminal control characters. Failure output
# must show their bytes rather than execute terminal commands in the test log.
diagnostic_text() {
  /usr/bin/perl -pe 's/([\x00-\x08\x0b-\x1f\x7f])/sprintf("\\x%02x", ord($1))/eg'
}

skip() { # NAME REASON
  N_SKIP=$((N_SKIP + 1))
  printf 'SKIP %s (%s)\n' "$1" "$2"
}

# ----------------------------------------------------------- run drivethru --
# with_timeout SECS CMD... -> CMD's status, or 124 when it had to be killed.
# CMD is started through perl's setsid so it has no controlling terminal and
# its whole process group can be killed.
with_timeout() {
  local secs=$1 pid wd rc marker
  shift
  marker=$T/timed-out.$$
  rm -f "$marker"
  /usr/bin/perl -MPOSIX -e '
    if (!defined POSIX::setsid()) {           # already a group leader: fork
      my $p = fork; die "fork: $!" unless defined $p;
      if ($p) { waitpid($p, 0); exit(($? & 127) ? 128 + ($? & 127) : $? >> 8); }
      POSIX::setsid();
    }
    exec @ARGV or die "exec $ARGV[0]: $!\n";' "$@" &
  pid=$!
  (
    trap 'kill "$s" 2>/dev/null; exit 0' TERM
    sleep "$secs" &
    s=$!
    wait "$s"
    : >"$marker"
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
    sleep 1
    kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null
  ) </dev/null >/dev/null 2>&1 &
  wd=$!
  wait "$pid"
  rc=$?
  kill -TERM "$wd" 2>/dev/null
  wait "$wd" 2>/dev/null
  if [ -e "$marker" ]; then
    rm -f "$marker"
    return 124
  fi
  return "$rc"
}

# run_dt ARGS... : run drivethru; sets RC, OUT, ERR, ELAPSED_MS
run_dt() {
  local t0 t1 q a
  LAST_CMD="drivethru"
  for a in "$@"; do
    q=$(printf '%q' "$a")
    LAST_CMD="$LAST_CMD $q"
  done
  t0=$(now_ms)
  (
    cd "$RUN_CWD" || exit 97
    with_timeout "$DT_TIMEOUT" /usr/bin/env -i \
      HOME="$FHOME" USER="$T_USER" LOGNAME="$T_USER" SHELL=/bin/zsh \
      PATH="$R_PATH" TMPDIR="$TTMP" LANG=en_US.UTF-8 TERM=dumb \
      DRIVETHRU_ROOT="$R_ROOT" DRIVETHRU_DRIVEFS_DIR="$R_DRIVEFS" \
      DRIVETHRU_CHROME_DIR="$R_CHROME" DRIVETHRU_CONFIG="$R_CFG" \
      DRIVETHRU_FZF="$FZF" \
      DRIVETHRU_DRY_RUN=1 DRIVETHRU_CLIPBOARD_FILE="$CLIP" \
      ${XENV[@]+"${XENV[@]}"} \
      "$DT" "$@" </dev/null >"$T/stdout" 2>"$T/stderr"
  )
  RC=$?
  t1=$(now_ms)
  ELAPSED_MS=$((t1 - t0))
  OUT=$(cat "$T/stdout")
  ERR=$(cat "$T/stderr")
  if [ "$RC" = 124 ]; then
    bad "timed out after ${DT_TIMEOUT}s (killed)"
  fi
  if [ "$VERBOSE" = 1 ]; then
    printf '    $ %s  -> rc=%s (%sms)\n' "$LAST_CMD" "$RC" "$ELAPSED_MS"
  fi
  return 0
}

now_ms() { /usr/bin/perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; }

# write the config file for this test (one argument per line)
cfg() { printf '%s\n' "$@" >>"$CFG"; }

# ------------------------------------------------------------- assertions --
want_rc() {
  [ "$RC" = "$1" ] || bad "exit status: want $1, got $RC"
}

want_rc_in() { # "3 4"
  local c
  for c in $1; do [ "$RC" = "$c" ] && return 0; done
  bad "exit status: want one of [$1], got $RC"
}

want_rc_nonzero() {
  [ "$RC" != 0 ] || bad "exit status: want non-zero, got 0"
}

want_out() { # exact stdout (trailing newlines ignored)
  [ "$OUT" = "$1" ] || bad "stdout: want [$1], got [$OUT]"
}

want_out_empty() {
  [ -z "$OUT" ] || bad "stdout: want empty, got [$(printf '%s' "$OUT" | head -n 3)]"
}

want_out_line() { # some stdout line equals STR
  printf '%s\n' "$OUT" | grep -Fxq -- "$1" || bad "stdout: no line [$1]"
}

want_out_first() { # first stdout line equals STR
  local first
  first=$(printf '%s\n' "$OUT" | head -n 1)
  [ "$first" = "$1" ] || bad "stdout line 1: want [$1], got [$first]"
}

want_out_has() {
  case "$OUT" in *"$1"*) ;; *) bad "stdout: missing [$1]" ;; esac
}

want_out_lacks() {
  case "$OUT" in *"$1"*) bad "stdout: must not contain [$1]" ;; esac
}

want_out_re() {
  printf '%s\n' "$OUT" | grep -Eq -- "$1" || bad "stdout: no match for /$1/"
}

want_out_lacks_re() {
  local hit
  hit=$(printf '%s\n' "$OUT" | grep -E -- "$1" | head -n 1)
  [ -z "$hit" ] || bad "stdout: must not match /$1/ (line [$hit])"
}

want_err_has() {
  case "$ERR" in *"$1"*) ;; *) bad "stderr: missing [$1]" ;; esac
}

want_err_lacks() {
  case "$ERR" in *"$1"*) bad "stderr: must not contain [$1]" ;; esac
}

want_err_re() {
  printf '%s\n' "$ERR" | grep -Eiq -- "$1" || bad "stderr: no match for /$1/ (case-insensitive)"
}

want_err_lacks_re() {
  local hit
  hit=$(printf '%s\n' "$ERR" | grep -Ei -- "$1" | head -n 1)
  [ -z "$hit" ] || bad "stderr: must not match /$1/ (line [$hit])"
}

want_err_empty() {
  [ -z "$ERR" ] || bad "stderr: want empty, got [$(printf '%s' "$ERR" | head -n 3)]"
}

want_nonempty_err() {
  [ -n "$ERR" ] || bad "stderr: want a message, got nothing"
}

want_clip() { # clipboard file content (trailing newlines ignored)
  local got
  if [ ! -e "$CLIP" ]; then
    bad "clipboard file was not written (want [$1])"
    return
  fi
  got=$(cat "$CLIP")
  [ "$got" = "$1" ] || bad "clipboard: want [$1], got [$got]"
}

want_clip_absent() {
  if [ -s "$CLIP" ]; then
    bad "clipboard must not be written, got [$(head -n 2 "$CLIP")]"
  fi
}

want_faster_than() { # MS
  [ "$ELAPSED_MS" -lt "$1" ] || bad "took ${ELAPSED_MS}ms, want < ${1}ms"
}

# the dry-run lines drivethru printed ("drivethru: dry-run: ...")
dry_lines() {
  # fzf 0.42 draws on stderr. Remove its terminal codes and screen content
  # before comparing action lines captured from the interactive harness.
  printf '%s\n' "$ERR" | /usr/bin/perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\e[()][0-9A-Za-z]//g; s/\r/\n/g' |
    sed -n 's/^.*\(drivethru: dry-run: .*\)$/\1/p'
}

want_dry_re() { # some dry-run line matches ERE
  dry_lines | grep -Eq -- "$1" || bad "no dry-run line matching /$1/"
}

want_dry_lacks_re() {
  local hit
  hit=$(dry_lines | grep -E -- "$1" | head -n 1)
  [ -z "$hit" ] || bad "dry-run line must not match /$1/ (line [$hit])"
}

want_dry_count() { # N dry-run lines matching ERE
  local n
  n=$(dry_lines | grep -Ec -- "$2")
  [ "$n" = "$1" ] || bad "want $1 dry-run line(s) matching /$2/, got $n"
}

want_absent() { # PATH must not exist
  [ ! -e "$1" ] && [ ! -L "$1" ] || bad "must not exist: $1"
}

# escape a fixed string for use inside an ERE
re() { printf '%s' "$1" | sed 's/[][\.*^$?+(){}|/]/\\&/g'; }

# ------------------------------------------------------------- URL builders --
folder_url() { printf 'https://drive.google.com/drive/folders/%s' "$1"; }
doc_url()    { printf 'https://docs.google.com/document/d/%s/edit' "$1"; }
sheet_url()  { printf 'https://docs.google.com/spreadsheets/d/%s/edit' "$1"; }
slides_url() { printf 'https://docs.google.com/presentation/d/%s/edit' "$1"; }
form_url()   { printf 'https://docs.google.com/forms/d/%s/edit' "$1"; }
draw_url()   { printf 'https://docs.google.com/drawings/d/%s/edit' "$1"; }
script_url() { printf 'https://script.google.com/d/%s/edit' "$1"; }
map_url()    { printf 'https://www.google.com/maps/d/edit?mid=%s' "$1"; }
file_url()   { printf 'https://drive.google.com/file/d/%s/view' "$1"; }
openid_url() { printf 'https://drive.google.com/open?id=%s' "$1"; }
with_key()   { # URL KEY
  case "$1" in *\?*) printf '%s&resourcekey=%s' "$1" "$2" ;; *) printf '%s?resourcekey=%s' "$1" "$2" ;; esac
}
# ERE matching URL plus an optional authuser for EMAIL (literal or %40)
re_url_authuser() { # URL EMAIL
  local u e1 e2 sep='\?'
  u=$(re "$1")
  case "$1" in *\?*) sep='&' ;; esac
  e1=$(re "$2")
  e2=$(re "${2%@*}")%40$(re "${2#*@}")
  printf '%s%sauthuser=(%s|%s)' "$u" "$sep" "$e1" "$e2"
}
