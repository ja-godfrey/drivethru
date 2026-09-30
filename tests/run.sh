#!/bin/bash
# shellcheck disable=SC2329  # test groups and helpers are called indirectly ("g_$g")
# tests/run.sh [-v] [-k] [GROUP...]
#
# Plain-bash test suite for drivethru (no bats). Builds a synthetic Drive tree
# with tests/make-fixture.sh in a temp dir, runs drivethru against it with
# DRIVETHRU_DRY_RUN=1, and prints one PASS/FAIL/SKIP line per test. Exits 1
# if anything failed.
#
#   -v        show every drivethru command line and its exit status
#   -k        keep the temp dir (path is printed at the end)
#   GROUP     run only these groups (default: all). Groups:
#             meta list labels kinds shortcuts paths options exits open
#             search popup tty doctor config db interactive
#             review_core review_browser safety
#
# Environment: DRIVETHRU_BIN overrides the script under test (default: the
# repo's ./drivethru). Nothing here touches the real ~/Library/CloudStorage,
# DriveFS state, Chrome profile, clipboard or browser.

set -u

HERE=$(cd -P "$(dirname "$0")" && pwd)
REPO=$(cd -P "$HERE/.." && pwd)
DT=${DRIVETHRU_BIN:-$REPO/drivethru}
KEEP=0
VERBOSE=0
GROUPS_WANTED=""
while [ $# -gt 0 ]; do
  case "$1" in
    -v) VERBOSE=1 ;;
    -k) KEEP=1 ;;
    -h|--help) sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) printf 'run.sh: unknown option %s\n' "$1" >&2; exit 2 ;;
    *) GROUPS_WANTED="$GROUPS_WANTED $1" ;;
  esac
  shift
done

ALL_GROUPS='meta list labels kinds shortcuts paths options exits open search popup tty doctor config db interactive review_core review_browser safety'
for g in $GROUPS_WANTED; do
  case " $ALL_GROUPS " in
    *" $g "*) ;;
    *) printf 'run.sh: unknown test group %s\n' "$g" >&2; exit 2 ;;
  esac
done

# shellcheck source=tests/fixture-ids.sh disable=SC1091
. "$HERE/fixture-ids.sh"
# shellcheck source=tests/helpers.sh disable=SC1091
. "$HERE/helpers.sh"

TAB=$(printf '\t')
CR=$(printf '\r')
T_USER=$(id -un)

T=$(mktemp -d "${TMPDIR:-/tmp}/drivethru-tests.XXXXXX") || exit 2
T=$(cd -P "$T" && pwd)
cleanup() {
  chmod -R u+rwx "$T" 2>/dev/null
  if [ "$KEEP" = 1 ]; then
    printf 'kept test dir: %s\n' "$T"
  else
    rm -rf "$T"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

WORK=$T/work
TTMP=$T/tmp
# shellcheck disable=SC2034  # CFG and CHROME are used in helpers.sh
CFG=$T/config
CLIP=$T/clipboard
mkdir -p "$WORK" "$TTMP"

printf 'drivethru tests: %s\n' "$DT"
if ! "$HERE/make-fixture.sh" "$T/fx" 2>"$T/fixture.log"; then
  printf 'FAIL fixture: make-fixture.sh failed\n'
  sed 's/^/    /' "$T/fixture.log"
  exit 1
fi
ROOT=$T/fx/CloudStorage
DRIVEFS=$T/fx/DriveFS
# shellcheck disable=SC2034
CHROME=$T/fx/Chrome
FHOME=$T/fx/home
MA=$ROOT/GoogleDrive-$EMAIL_A
MB=$ROOT/GoogleDrive-$EMAIL_B
MC=$ROOT/GoogleDrive-$EMAIL_C
MDV=$ROOT/GoogleDrive-$EMAIL_D
PA="$MA/$MYDRIVE/Projects"
ODD="$MA/$MYDRIVE/Odd Names"
ALIAS="$FHOME/$EMAIL_A - Google Drive"

# fzf: the script adds these prefixes itself; add fzf's dir only if elsewhere
FZF=${DRIVETHRU_FZF:-}
if [ -z "$FZF" ]; then
  for d in /opt/homebrew/bin /usr/local/bin /opt/local/bin; do
    [ -x "$d/fzf" ] && { FZF=$d/fzf; break; }
  done
fi
FZF_IN_PREFIX=0
[ -n "$FZF" ] || FZF=$(command -v fzf 2>/dev/null || true)
case "$FZF" in
  /opt/homebrew/bin/fzf|/usr/local/bin/fzf|/opt/local/bin/fzf) FZF_IN_PREFIX=1 ;;
esac
TEST_PATH=/usr/bin:/bin:/usr/sbin:/sbin
if [ -n "$FZF" ] && [ "$FZF_IN_PREFIX" = 0 ]; then
  TEST_PATH=$(dirname "$FZF"):$TEST_PATH
fi


DT_ABS=""
if [ -e "$DT" ]; then
  DT_ABS=$(cd -P "$(dirname "$DT")" && pwd)/$(basename "$DT")
fi

want_group() {
  [ -z "$GROUPS_WANTED" ] && return 0
  case " $GROUPS_WANTED " in *" $1 "*) return 0 ;; esac
  return 1
}

# fixture manifest, to prove nothing under the fake Drive/DriveFS/Chrome
# changed (names, sizes, mtimes, modes, contents, xattr names and values)
manifest() {
  (
    cd "$T/fx" || exit 1
    find CloudStorage DriveFS Chrome -exec /usr/bin/stat -f '%N|%z|%m|%Sp' {} + | LC_ALL=C sort
    find CloudStorage DriveFS Chrome -type f -exec /sbin/md5 -r {} + | LC_ALL=C sort
    find CloudStorage DriveFS Chrome -exec /usr/bin/xattr -s -l {} + 2>/dev/null | LC_ALL=C sort
  )
}
manifest >"$T/manifest.before"

# The real clipboard is never written by these tests. To prove drivethru did
# not write it either, check (at the start and the end) only whether it holds a
# fixture id: every synthetic id has a run of ten X's. Nothing else about the
# clipboard is kept, so the user copying things meanwhile is harmless.
# pbpaste is guarded: it could block on a headless machine.
clip_state() {
  with_timeout 5 /bin/sh -c '/usr/bin/pbpaste >/dev/null 2>&1 || exit 2; /usr/bin/pbpaste 2>/dev/null | grep -q XXXXXXXXXX' \
    </dev/null >/dev/null 2>&1
  case $? in 0) printf fixture ;; 1) printf clean ;; *) printf unavailable ;; esac
}
CLIP_STATE0=$(clip_state)

if [ ! -x "$DT" ]; then
  begin "core: $DT exists and is executable"
  bad "not found (the core script is not written yet?)"
  end
  printf '\n%s passed, %s failed, %s skipped\n' "$N_PASS" "$N_FAIL" "$N_SKIP"
  exit 1
fi

# helpers that need the fixture ------------------------------------------------
list_labels() { printf '%s\n' "$OUT" | cut -s -f1 | LC_ALL=C sort -u; }

# the normalized dry-run line that mentions FIXED
dry_line_with() { dry_lines | tr -d "\"'\\\\" | grep -F -- "$1" | head -n 1; }

want_chrome_open() { # URL EMAIL PROFILE_DIR
  local line
  line=$(dry_line_with "$1")
  if [ -z "$line" ]; then
    bad "no dry-run line opening [$1]"
    return
  fi
  case "$line" in *"--profile-directory=$3 "*|*"--profile-directory=$3") ;;
    *) bad "want --profile-directory=$3 in [$line]" ;; esac
  case "$line" in *"--profile-email=$2"*) ;;
    *) bad "want --profile-email=$2 in [$line]" ;; esac
  printf '%s\n' "$line" | grep -Eq 'com\.google\.Chrome( |$)|Google Chrome' ||
    bad "not launched in Google Chrome: [$line]"
}

want_default_open() { # URL EMAIL
  local line
  line=$(dry_lines | tr -d "\"'\\\\" | grep -E -- "$(re_url_authuser "$1" "$2")" | head -n 1)
  if [ -z "$line" ]; then
    bad "no dry-run line opening [$1] with authuser=$2"
    return
  fi
  case "$line" in *--profile-directory*) bad "default-browser open must not pick a Chrome profile: [$line]" ;; esac
}

want_no_authuser_anywhere() {
  want_out_lacks "authuser"
  if [ -e "$CLIP" ] && grep -q authuser "$CLIP"; then bad "clipboard contains authuser"; fi
}

link_is() { # NAME PATH URL : link PATH prints exactly URL, exit 0, clean link
  begin "$1"
  run_dt link "$2"
  want_rc 0
  want_out "$3"
  want_no_authuser_anywhere
  want_out_lacks "usp="
  end
}

# ============================================================== groups ==

g_meta() {
  begin "meta: --help exits 0 and lists the commands"
  run_dt --help
  want_rc 0
  local c
  for c in pick popup link open search list doctor; do want_out_has "$c"; done
  end

  begin "meta: --version prints a version number"
  run_dt --version
  want_rc 0
  want_out_re '[0-9]+\.[0-9]+'
  end

  begin "meta: link with no paths is a usage error (1)"
  run_dt link
  want_rc 1
  want_out_empty
  want_nonempty_err
  end

  begin "meta: unknown option is a usage error (1)"
  run_dt link --bogus-option "$PA/Plan.gdoc"
  want_rc 1
  want_out_empty
  end

  begin "meta: search with a bad option is a usage error (1)"
  run_dt search --bogus-option x
  want_rc 1
  end

  local wf=""
  for wf in "$REPO"/share/drivethru/*.workflow; do [ -d "$wf" ] && break; wf=""; done
  if [ -z "$wf" ]; then
    skip "meta: install-quick-action (dry-run)" "no share/drivethru/*.workflow bundle yet"
  else
    begin "meta: install-quick-action under dry-run touches nothing"
    run_dt install-quick-action
    want_rc 0
    want_dry_re "\.workflow"
    want_dry_re "Library/Services"
    want_absent "$FHOME/Library/Services"
    end
  fi
}

g_list() {
  begin "list: exit 0, label<TAB>relative/path lines"
  run_dt list
  want_rc 0
  want_out_line "example${TAB}$MYDRIVE/Projects/Plan.gdoc"
  want_out_line "example${TAB}$MYDRIVE/Projects/Report.pdf"
  want_out_line "example${TAB}$MYDRIVE/Projects"
  want_out_line "example${TAB}$SHARED/Team Alpha/Specs.gdoc"
  want_out_line "example${TAB}$SHARED/Team Alpha/Assets/logo.png"
  want_out_line "example${TAB}$COMPUTERS/Studio Mac"
  want_out_line "example${TAB}$MYDRIVE/Odd Names/$NAME_QUOTES"
  want_out_line "example${TAB}$MYDRIVE/Odd Names/$NAME_UNICODE"
  want_out_line "example${TAB}$MYDRIVE/Odd Names/$NAME_DOLLAR"
  want_out_line "example${TAB}$MYDRIVE/Odd Names/$NAME_DASH"
  want_out_line "example${TAB}$MYDRIVE/Projects/Draft notes.txt"
  want_out_line "bob${TAB}$MYDRIVE/Photos/beach.jpg"
  want_out_line "bob${TAB}$MYDRIVE/Bob Notes.gdoc"
  want_out_line "$EMAIL_C${TAB}$MYDRIVE/Syllabus.gdoc"
  want_out_line "$EMAIL_D${TAB}$MYDRIVE/Grades.gsheet"
  # every line (except the tail of the name with an embedded newline) has
  # exactly two tab-separated fields, and paths are relative
  local odd
  odd=$(printf '%s\n' "$OUT" | grep -Ev "^[^${TAB}]+${TAB}[^${TAB}]+\$" | grep -Fvx 'Break.pdf' | head -n 3)
  [ -z "$odd" ] || bad "malformed lines: [$odd]"
  want_out_lacks "$ROOT"
  want_out_lacks_re "$TAB/"
  end

  begin "list: prunes hidden names, .Trash, .tmp, .shortcut-targets-by-id, Icon\\r"
  run_dt list
  want_rc 0
  want_out_line "example${TAB}$MYDRIVE/Projects/Plan.gdoc"
  want_out_lacks_re "(^|$TAB|/)\\."
  want_out_lacks ".shortcut-targets-by-id"
  want_out_lacks "Old Deleted.pdf"
  want_out_lacks "upload.part"
  want_out_lacks ".DS_Store"
  want_out_lacks "Icon$CR"
  printf '%s\n' "$OUT" | grep -q '/Inside\.pdf$' && bad "listed a file under .shortcut-targets-by-id"
  end

  begin "list: symlink shortcuts are listed but never followed"
  run_dt list
  want_rc 0
  want_out_line "example${TAB}$MYDRIVE/Shortcut to Projects"
  want_out_line "example${TAB}$MYDRIVE/Shortcut to Plan.gdoc"
  want_out_line "example${TAB}$MYDRIVE/Shortcut to Shared Thing"
  want_out_line "example${TAB}$MYDRIVE/Shortcut to Inside.pdf"
  want_out_line "example${TAB}$MYDRIVE/Broken Shortcut"
  want_out_line "example${TAB}$SHARED/Team Alpha/Assets/Back to Team"
  want_out_lacks "Shortcut to Projects/"
  want_out_lacks "Shortcut to Shared Thing/"
  want_out_lacks "Back to Team/"
  want_faster_than 5000
  end

  begin "list: only GoogleDrive-* mounts (not other providers under the root)"
  run_dt list
  want_rc 0
  want_out_line "bob${TAB}$MYDRIVE/Bob Notes.gdoc"
  want_out_lacks "Stray.pdf"
  want_out_lacks "OneDrive"
  end

  begin "list: every account is listed, including an empty Shared drives"
  run_dt list
  local labels
  labels=$(list_labels | tr '\n' ' ')
  [ "$labels" = "bob $EMAIL_C $EMAIL_D example " ] || bad "labels: got [$labels]"
  end

  begin "list: 5,000 items list fast (no per-item xattr reads or processes)"
  local pm="$T/root-perf/GoogleDrive-perf@example.com/$MYDRIVE" i
  mkdir -p "$pm"
  /usr/bin/xattr -w 'com.google.drivefs.item-id#S' 0APerfMyDriveRootUk9PV "$pm"
  for i in $(seq 1 50); do mkdir "$pm/folder $i"; done
  for i in $(seq 1 50); do
    (cd "$pm/folder $i" && seq 1 99 | sed 's/^/file /; s/$/.pdf/' | tr '\n' '\0' | xargs -0 touch)
  done
  R_ROOT=$T/root-perf
  run_dt list
  want_rc 0
  [ "$(printf '%s\n' "$OUT" | grep -c "^example$TAB")" -ge 5000 ] ||
    bad "want >= 5000 rows, got $(printf '%s\n' "$OUT" | grep -c "^example$TAB")"
  want_faster_than 3000
  end
}

g_labels() {
  begin "labels: gmail -> local part, other -> first domain label, collision -> full emails"
  run_dt list
  want_rc 0
  local labels
  labels=$(list_labels | tr '\n' ' ')
  [ "$labels" = "bob $EMAIL_C $EMAIL_D example " ] || bad "labels: want [bob $EMAIL_C $EMAIL_D example ], got [$labels]"
  printf '%s\n' "$OUT" | grep -q "^umich$TAB" && bad "colliding label 'umich' used"
  end

  begin "labels: config label.<email> overrides the default"
  cfg "label.$EMAIL_A = work"
  run_dt list
  want_rc 0
  want_out_line "work${TAB}$MYDRIVE/Projects/Plan.gdoc"
  printf '%s\n' "$OUT" | grep -q "^example$TAB" && bad "default label still used"
  end

  begin "labels: config override resolves a collision"
  cfg "label.$EMAIL_C = uni"
  run_dt list
  want_rc 0
  want_out_line "uni${TAB}$MYDRIVE/Syllabus.gdoc"
  printf '%s\n' "$OUT" | grep -q "^$EMAIL_C$TAB" && bad "carol still labelled by email"
  end

  begin "labels: googlemail.com -> local part too"
  mkdir -p "$T/root-gm/GoogleDrive-erin@googlemail.com/$MYDRIVE"
  /usr/bin/xattr -w 'com.google.drivefs.item-id#S' 0AErinMyDriveRootUk9PV "$T/root-gm/GoogleDrive-erin@googlemail.com/$MYDRIVE"
  R_ROOT=$T/root-gm
  run_dt list
  want_rc 0
  [ "$(list_labels | tr '\n' ' ')" = "erin " ] || bad "labels: got [$(list_labels | tr '\n' ' ')]"
  end
}

g_kinds() {
  link_is "link: folder"                  "$PA"                               "$(folder_url "$A_PROJECTS")"
  link_is "link: shared-drive root"       "$MA/$SHARED/Team Alpha"            "$(folder_url "$A_TEAM")"
  link_is "link: folder in a shared drive" "$MA/$SHARED/Team Alpha/Assets"    "$(folder_url "$A_ASSETS")"
  link_is "link: Other computers folder"  "$MA/$COMPUTERS/Studio Mac"         "$(folder_url "$A_COMPUTER")"
  link_is "link: gdoc"                    "$PA/Plan.gdoc"                     "$(doc_url "$A_PLAN")"
  link_is "link: gdoc in a shared drive"  "$MA/$SHARED/Team Alpha/Specs.gdoc" "$(doc_url "$A_SPECS")"
  link_is "link: gsheet (invalid resource_key in stub ignored)" "$PA/Budget.gsheet" "$(sheet_url "$A_BUDGET")"
  link_is "link: gslides (null resource_key)" "$PA/Pitch Deck.gslides"        "$(slides_url "$A_DECK")"
  link_is "link: gscript"                 "$PA/Automation.gscript"            "$(script_url "$A_SCRIPT")"
  link_is "link: gmap"                    "$PA/Office Map.gmap"               "$(map_url "$A_MAP")"
  link_is "link: gdraw"                   "$PA/Whiteboard.gdraw"              "$(draw_url "$A_DRAW")"
  link_is "link: other g* stub (gsite) -> open?id=" "$PA/Team Site.gsite"     "$(openid_url "$A_SITE")"
  link_is "link: pdf"                     "$PA/Report.pdf"                    "$(file_url "$A_REPORT")"
  link_is "link: .gs is an ordinary file" "$PA/helpers.gs"                    "$(file_url "$A_GS")"
  link_is "link: .geojson is an ordinary file" "$PA/route.geojson"            "$(file_url "$A_GEOJSON")"
  link_is "link: image in a shared drive" "$MA/$SHARED/Team Alpha/Assets/logo.png" "$(file_url "$A_LOGO")"
  link_is "link: gdoc in another account" "$MB/$MYDRIVE/Bob Notes.gdoc"       "$(doc_url "$B_NOTES")"
  link_is "link: gsheet in a colliding account" "$MDV/$MYDRIVE/Grades.gsheet" "$(sheet_url "$D_GRADES")"

  begin "link: gform prints the editor link and says so"
  run_dt link "$PA/Signup Survey.gform"
  want_rc 0
  want_out "$(form_url "$A_FORM")"
  want_err_re 'editor'
  end

  begin "link: .gdrive stub -> file view + resource key from the stub"
  run_dt link "$PA/Contract.docx.gdrive"
  want_rc 0
  want_out "$(with_key "$(file_url "$A_GDRIVE")" "$A_GDRIVE_KEY")"
  end

  begin "link: stub JSON is read without modifying it (plutil -o -)"
  local before after
  before=$(/sbin/md5 -q "$PA/Contract.docx.gdrive"; /usr/bin/stat -f '%m %Sp' "$PA/Contract.docx.gdrive")
  run_dt link "$PA/Contract.docx.gdrive" "$PA/Plan.gdoc"
  after=$(/sbin/md5 -q "$PA/Contract.docx.gdrive"; /usr/bin/stat -f '%m %Sp' "$PA/Contract.docx.gdrive")
  [ "$before" = "$after" ] || bad "stub changed on disk"
  want_rc 0
  want_out "$(with_key "$(file_url "$A_GDRIVE")" "$A_GDRIVE_KEY")
$(doc_url "$A_PLAN")"
  end

  begin "link: legacy 0B id without a key -> link + warning, exit 0"
  run_dt link "$MB/$MYDRIVE/Old Scan.pdf"
  want_rc 0
  want_out "$(file_url "$B_OLDSCAN")"
  want_err_re 'legacy'
  want_err_re 'resource key'
  end

  begin "link: My Drive root has no share link (exit 4)"
  run_dt link "$MA/$MYDRIVE"
  want_rc 4
  want_out_empty
  want_err_re "My Drive itself can.t be shared"
  end

  begin "link: My Drive root of another account (exit 4)"
  run_dt link "$MB/$MYDRIVE"
  want_rc 4
  want_out_empty
  end

  begin "link: Shared drives container has no share link (exit 4)"
  run_dt link "$MA/$SHARED"
  want_rc 4
  want_out_empty
  want_nonempty_err
  end

  begin "link: empty Shared drives container (exit 4)"
  run_dt link "$MC/$SHARED"
  want_rc 4
  want_out_empty
  end

  begin "link: Other computers container (exit 4)"
  run_dt link "$MA/$COMPUTERS"
  want_rc 4
  want_out_empty
  end

  begin "link: the mount root itself has no link (exit 4)"
  run_dt link "$MA"
  want_rc 4
  want_out_empty
  end

  begin "link: id-less folder inside hidden bookkeeping (exit 3)"
  run_dt link "$MA/.shortcut-targets-by-id/$A_TOP"
  want_rc 3
  want_out_empty
  want_nonempty_err
  end

  begin "link: file without an id -> not uploaded to Drive yet (exit 3)"
  run_dt link "$PA/Draft notes.txt"
  want_rc 3
  want_out_empty
  want_err_re 'not uploaded to Drive yet'
  end
}

g_shortcuts() {
  begin "shortcut (1): symlink to a file in the same mount -> TARGET link"
  run_dt link "$MA/$MYDRIVE/Shortcut to Plan.gdoc"
  want_rc 0
  want_out "$(doc_url "$A_PLAN")"
  want_out_lacks "$A_SC_PLAN"
  end

  link_is "shortcut (1): symlink to a folder -> target folder" \
    "$MA/$MYDRIVE/Shortcut to Projects" "$(folder_url "$A_PROJECTS")"
  link_is "shortcut (2): symlink into .shortcut-targets-by-id (folder)" \
    "$MA/$MYDRIVE/Shortcut to Shared Thing" "$(folder_url "$A_TOP")"
  link_is "shortcut (2): symlink into .shortcut-targets-by-id (file)" \
    "$MA/$MYDRIVE/Shortcut to Inside.pdf" "$(file_url "$A_INSIDE")"
  link_is "shortcut: folder shortcut that points up the tree (loop)" \
    "$MA/$SHARED/Team Alpha/Assets/Back to Team" "$(folder_url "$A_TEAM")"

  begin "shortcut (3): broken symlink -> open?id=SHORTCUT + warning, exit 0"
  run_dt link "$MA/$MYDRIVE/Broken Shortcut"
  want_rc 0
  want_out "$(openid_url "$A_SC_BROKEN")"
  want_err_re "shortcut target isn.t available locally"
  want_err_re "points at the shortcut"
  end

  begin "shortcut (4): regular .gdoc stand-in -> JSON doc_id, not the xattr"
  run_dt link "$MA/$MYDRIVE/Standin Doc.gdoc"
  want_rc 0
  want_out "$(doc_url "$A_STANDIN_DOC_TARGET")"
  want_out_lacks "$A_SC_STANDIN_DOC"
  end

  begin "shortcut (4): binary stand-in with db = off -> its own id, exit 0"
  cfg "db = off"
  run_dt link "$MA/$MYDRIVE/Standin Scan.pdf"
  want_rc 0
  want_out "$(file_url "$A_SC_STANDIN_PDF")"
  end

  begin "shortcut: via an alias path, a broken shortcut stays a shortcut"
  run_dt link "$ALIAS/$MYDRIVE/Broken Shortcut"
  want_rc 0
  want_out "$(openid_url "$A_SC_BROKEN")"
  want_err_re "available locally"
  end

  begin "shortcut: via an alias path, a symlink shortcut -> target"
  run_dt link "$ALIAS/$MYDRIVE/Shortcut to Plan.gdoc"
  want_rc 0
  want_out "$(doc_url "$A_PLAN")"
  end
}

g_paths() {
  link_is "paths: through a symlinked alias to the mount" \
    "$ALIAS/$MYDRIVE/Projects/Plan.gdoc" "$(doc_url "$A_PLAN")"
  link_is "paths: alias to a folder" "$ALIAS/$MYDRIVE/Projects" "$(folder_url "$A_PROJECTS")"
  link_is "paths: name with spaces and quotes" "$ODD/$NAME_QUOTES" "$(file_url "$A_QUOTES")"
  link_is "paths: unicode name" "$ODD/$NAME_UNICODE" "$(file_url "$A_UNICODE")"
  link_is "paths: name with an embedded newline" "$ODD/$NAME_NEWLINE" "$(file_url "$A_NEWLINE")"

  begin "paths: name with \$(...) and backticks is never evaluated"
  run_dt link "$ODD/$NAME_DOLLAR"
  want_rc 0
  want_out "$(file_url "$A_DOLLAR")"
  want_absent "$WORK/pwned"
  want_absent "$WORK/pwned2"
  end

  link_is "paths: through DriveFS/<N>/my-drive (a symlink to My Drive)" \
    "$DRIVEFS/$ACCT_A/my-drive/Projects/Plan.gdoc" "$(doc_url "$A_PLAN")"

  begin "paths: relative path from inside a mount"
  RUN_CWD="$MA/$MYDRIVE"
  run_dt link "Projects/Report.pdf"
  want_rc 0
  want_out "$(file_url "$A_REPORT")"
  end

  begin "paths: relative path with .."
  RUN_CWD="$ODD"
  run_dt link "../Projects/Budget.gsheet"
  want_rc 0
  want_out "$(sheet_url "$A_BUDGET")"
  end

  begin "paths: -- ends options (dash-leading file name)"
  RUN_CWD="$ODD"
  run_dt link -- "$NAME_DASH"
  want_rc 0
  want_out "$(file_url "$A_DASH")"
  end

  begin "paths: DRIVETHRU_ROOT given through a symlink"
  ln -s "$ROOT" "$T/cs-link" 2>/dev/null
  R_ROOT=$T/cs-link
  run_dt link "$PA/Plan.gdoc" "$T/cs-link/GoogleDrive-$EMAIL_A/$MYDRIVE/Projects/Report.pdf"
  want_rc 0
  want_out "$(doc_url "$A_PLAN")
$(file_url "$A_REPORT")"
  end

  begin "paths: a copy outside the mounts keeps the xattr but is not trusted (exit 3)"
  run_dt link "$FHOME/Desktop/Report.pdf"
  want_rc 3
  want_out_empty
  want_out_lacks "$A_REPORT"
  want_nonempty_err
  end

  begin "paths: a non-Drive folder under the CloudStorage root is not trusted (exit 3)"
  run_dt link "$ROOT/OneDrive-Personal/Stray.pdf"
  want_rc 3
  want_out_empty
  end

  begin "paths: nonexistent path fails without output"
  run_dt link "$PA/does not exist.pdf"
  want_rc_nonzero
  want_out_empty
  want_nonempty_err
  end
}

g_options() {
  begin "options: several paths -> one link per line, in order"
  run_dt link "$PA/Plan.gdoc" "$PA/Report.pdf" "$PA"
  want_rc 0
  want_out "$(doc_url "$A_PLAN")
$(file_url "$A_REPORT")
$(folder_url "$A_PROJECTS")"
  end

  begin "options: --markdown -> [name](url)"
  run_dt link --markdown "$PA/Plan.gdoc"
  want_rc 0
  want_out_re "^\\[[^]]*Plan[^]]*\\]\\($(re "$(doc_url "$A_PLAN")")\\)\$"
  end

  begin "options: --markdown with several paths -> one per line"
  run_dt link --markdown "$PA/Plan.gdoc" "$PA/Report.pdf"
  want_rc 0
  want_out_re "^\\[[^]]*Plan[^]]*\\]\\($(re "$(doc_url "$A_PLAN")")\\)\$"
  want_out_re "^\\[[^]]*Report[^]]*\\]\\($(re "$(file_url "$A_REPORT")")\\)\$"
  [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 2 ] || bad "want 2 lines"
  end

  begin "options: --copy prints and copies (dry-run clipboard file)"
  run_dt link --copy "$PA/Plan.gdoc" "$PA/Report.pdf"
  want_rc 0
  want_out "$(doc_url "$A_PLAN")
$(file_url "$A_REPORT")"
  want_clip "$(doc_url "$A_PLAN")
$(file_url "$A_REPORT")"
  want_dry_re 'pbcopy|clipboard|copy'
  want_no_authuser_anywhere
  end

  begin "options: --copy --markdown copies Markdown"
  run_dt link --copy --markdown "$PA/Budget.gsheet"
  want_rc 0
  if [ -e "$CLIP" ]; then
    grep -Eq "^\\[[^]]*Budget[^]]*\\]\\($(re "$(sheet_url "$A_BUDGET")")\\)\$" "$CLIP" ||
      bad "clipboard is not a markdown link: [$(cat "$CLIP")]"
  else
    bad "clipboard file not written"
  fi
  end

  begin "options: --notify under dry-run shows a notification action"
  run_dt link --notify "$PA/Plan.gdoc"
  want_rc 0
  want_out "$(doc_url "$A_PLAN")"
  want_dry_re 'osascript|notif'
  end

  begin "options: link without --copy never writes the clipboard"
  run_dt link "$PA/Plan.gdoc"
  want_rc 0
  want_out "$(doc_url "$A_PLAN")"
  want_clip_absent
  want_dry_lacks_re 'pbcopy'
  end

  begin "options: one bad path among good ones -> non-zero exit"
  run_dt link "$PA/Plan.gdoc" "$PA/Draft notes.txt"
  want_rc_nonzero
  want_err_re 'not uploaded'
  end
}

g_exits() {
  mkdir -p "$T/empty-root"
  begin "exits: no Drive mounts -> list exits 2"
  R_ROOT=$T/empty-root
  run_dt list
  want_rc 2
  want_out_empty
  want_nonempty_err
  end

  begin "exits: no Drive mounts -> search exits 2"
  R_ROOT=$T/empty-root
  run_dt search plan
  want_rc 2
  want_out_empty
  end

  begin "exits: missing CloudStorage root -> exit 2"
  R_ROOT=$T/no-such-root
  run_dt list
  want_rc 2
  end

  # a mount we may not read (what a missing File Provider consent looks like)
  mkdir -p "$T/perm-root/GoogleDrive-erin@example.net/$MYDRIVE"
  chmod 000 "$T/perm-root/GoogleDrive-erin@example.net"
  if [ "$(id -u)" = 0 ]; then
    skip "exits: unreadable mount -> exit 6" "running as root"
  else
    begin "exits: unreadable mount -> list exits 6"
    R_ROOT=$T/perm-root
    run_dt list
    want_rc 6
    want_nonempty_err
    end
  fi
  chmod 755 "$T/perm-root/GoogleDrive-erin@example.net"

  if [ -n "$FZF" ]; then
    # Use the explicit hook: the script adds its own prefixes to PATH.
    begin "exits: fzf missing -> search exits 5 (DRIVETHRU_FZF hook)"
    XENV=("DRIVETHRU_FZF=$T/no-such-fzf")
    run_dt search plan
    want_rc 5
    want_out_empty
    want_err_re 'fzf'
    end

    begin "exits: fzf missing -> doctor reports it and exits 5"
    XENV=("DRIVETHRU_FZF=$T/no-such-fzf")
    run_dt doctor
    want_rc 5
    want_out_re 'FAIL.*fzf'
    end

    begin "exits: DRIVETHRU_FZF pointing at a real fzf still works"
    XENV=("DRIVETHRU_FZF=$FZF")
    run_dt search --limit 1 Budget.gsheet
    want_rc 0
    want_out_first "example${TAB}$MYDRIVE/Projects/Budget.gsheet"
    end
  else
    begin "exits: fzf missing -> search exits 5"
    run_dt search plan
    want_rc 5
    end
  fi
}

g_open() {
  begin "open: prints nothing on stdout, never writes the clipboard"
  run_dt open "$PA/Plan.gdoc"
  want_rc 0
  want_out_empty
  [ -n "$(dry_lines)" ] || bad "nothing was opened (no dry-run line)"
  want_clip_absent
  end

  begin "open: not uploaded -> exit 3, nothing opened"
  run_dt open "$PA/Draft notes.txt"
  want_rc 3
  [ -z "$(dry_lines)" ] || bad "something was opened: [$(dry_lines | head -n 1)]"
  end

  begin "open: browser = default -> default browser + authuser"
  cfg "browser = default"
  run_dt open "$PA/Plan.gdoc"
  want_rc 0
  want_default_open "$(doc_url "$A_PLAN")" "$EMAIL_A"
  end

  begin "open: My Drive root -> drive/my-drive"
  cfg "browser = default"
  run_dt open "$MA/$MYDRIVE"
  want_rc 0
  want_default_open "https://drive.google.com/drive/my-drive" "$EMAIL_A"
  end

  begin "open: Shared drives container -> drive/shared-drives"
  cfg "browser = default"
  run_dt open "$MA/$SHARED"
  want_rc 0
  want_default_open "https://drive.google.com/drive/shared-drives" "$EMAIL_A"
  end

  begin "open: Other computers container -> drive.google.com/"
  cfg "browser = default"
  run_dt open "$MA/$COMPUTERS"
  want_rc 0
  dry_lines | tr -d "\"'\\\\" | grep -Eq 'https://drive\.google\.com/(\?authuser=[^ ]*)?( |$)' ||
    bad "no dry-run line opening https://drive.google.com/"
  end

  begin "open: authuser is appended with & when the URL has a query (gmap)"
  cfg "browser = default"
  run_dt open "$PA/Office Map.gmap"
  want_rc 0
  want_default_open "$(map_url "$A_MAP")" "$EMAIL_A"
  end

  begin "open: broken shortcut opens the shortcut id and warns"
  cfg "browser = default"
  run_dt open "$MA/$MYDRIVE/Broken Shortcut"
  want_rc 0
  want_default_open "$(openid_url "$A_SC_BROKEN")" "$EMAIL_A"
  want_err_re "available locally"
  end

  begin "open: several paths -> one open each"
  cfg "browser = default"
  run_dt open "$PA/Plan.gdoc" "$MB/$MYDRIVE/Bob Notes.gdoc"
  want_rc 0
  want_default_open "$(doc_url "$A_PLAN")" "$EMAIL_A"
  want_default_open "$(doc_url "$B_NOTES")" "$EMAIL_B"
  end

  begin "open: dry-run reports after_open without executing it"
  cfg "browser = default" \
      "after_open = printf '%s|%s|%s\\n' \"\$DRIVETHRU_EMAIL\" \"\$DRIVETHRU_URL\" \"\$DRIVETHRU_PROFILE_DIR\" >>'$T/after.log'"
  rm -f "$T/after.log"
  run_dt open "$MDV/$MYDRIVE/Grades.gsheet"
  want_rc 0
  want_dry_re 'after_open'
  want_absent "$T/after.log"
  end

  # With DRIVETHRU_CHROME_DIR set, drivethru treats that dir as the configured
  # channel's user-data dir and skips installed-app detection (DESIGN.md,
  # implementation notes), so these run whether or not Chrome is installed.

  begin "open: Chrome primary account (case-insensitive) -> Profile 1"
  run_dt open "$PA/Plan.gdoc"
  want_rc 0
  want_chrome_open "$(doc_url "$A_PLAN")" "$EMAIL_A" "$CHROME_PROFILE_A"
  end

  begin "open: primary accounts win over a secondary one in another profile"
  run_dt open "$PA/Plan.gdoc"
  want_chrome_open "$(doc_url "$A_PLAN")" "$EMAIL_A" "$CHROME_PROFILE_A"
  want_dry_lacks_re 'profile-directory=.?Default'
  end

  begin "open: Chrome secondary account (Preferences account_info) -> Profile 2"
  run_dt open "$MC/$MYDRIVE/Syllabus.gdoc"
  want_rc 0
  want_chrome_open "$(doc_url "$C_SYLLABUS")" "$EMAIL_C" "$CHROME_PROFILE_C"
  end

  begin "open: googlemail.com profile matches a gmail.com mount -> Profile 3"
  run_dt open "$MB/$MYDRIVE/Bob Notes.gdoc"
  want_rc 0
  want_chrome_open "$(doc_url "$B_NOTES")" "$EMAIL_B" "$CHROME_PROFILE_B"
  end

  begin "open: gmail dots are ignored (B.O.B@gmail.com == bob@gmail.com)"
  mk_chrome "$T/chrome-dots" "Profile 5=B.O.B@gmail.com"
  R_CHROME=$T/chrome-dots
  run_dt open "$MB/$MYDRIVE/Bob Notes.gdoc"
  want_rc 0
  want_chrome_open "$(doc_url "$B_NOTES")" "$EMAIL_B" "Profile 5"
  end

  begin "open: dots are NOT ignored for non-gmail domains"
  mk_chrome "$T/chrome-nodots" "Profile 6=a.lice@example.com"
  R_CHROME=$T/chrome-nodots
  run_dt open "$PA/Plan.gdoc"
  want_rc 0
  want_default_open "$(doc_url "$A_PLAN")" "$EMAIL_A"
  end

  begin "open: no profile -> default browser + authuser (System/Guest/unlisted dirs ignored)"
  run_dt open "$MDV/$MYDRIVE/Grades.gsheet"
  want_rc 0
  want_default_open "$(sheet_url "$D_GRADES")" "$EMAIL_D"
  want_dry_lacks_re 'System Profile|Guest Profile|Profile 9'
  end

  begin "open: browser = chrome forces Chrome with profile lookup"
  cfg "browser = chrome"
  run_dt open "$PA/Plan.gdoc"
  want_rc 0
  want_chrome_open "$(doc_url "$A_PLAN")" "$EMAIL_A" "$CHROME_PROFILE_A"
  end

  begin "open: My Drive root in Chrome -> drive/my-drive"
  run_dt open "$MA/$MYDRIVE"
  want_rc 0
  want_chrome_open "https://drive.google.com/drive/my-drive" "$EMAIL_A" "$CHROME_PROFILE_A"
  end

  begin "open: Chrome dry-run reports after_open without executing it"
  cfg "after_open = printf '%s|%s\\n' \"\$DRIVETHRU_EMAIL\" \"\$DRIVETHRU_PROFILE_DIR\" >>'$T/after2.log'"
  rm -f "$T/after2.log"
  run_dt open "$PA/Plan.gdoc"
  want_rc 0
  want_dry_re 'after_open'
  want_absent "$T/after2.log"
  end

  begin "open: Chrome dir without Local State -> default browser"
  mkdir -p "$T/chrome-empty"
  R_CHROME=$T/chrome-empty
  run_dt open "$PA/Plan.gdoc"
  want_rc 0
  want_default_open "$(doc_url "$A_PLAN")" "$EMAIL_A"
  end

  begin "open: the mount root opens drive.google.com/"
  cfg "browser = default"
  run_dt open "$MA"
  want_rc 0
  dry_lines | tr -d "\"'\\\\" | grep -Eq 'https://drive\.google\.com/(\?authuser=[^ ]*)?( |$)' ||
    bad "no dry-run line opening https://drive.google.com/"
  end

  # The same profile lookups without jq: DRIVETHRU_JQ pointing nowhere makes
  # drivethru use its JXA (osascript -l JavaScript) JSON fallback.
  begin "open (JXA fallback): primary account -> Profile 1"
  XENV=("DRIVETHRU_JQ=$T/no-such-jq")
  run_dt open "$PA/Plan.gdoc"
  want_rc 0
  want_chrome_open "$(doc_url "$A_PLAN")" "$EMAIL_A" "$CHROME_PROFILE_A"
  end

  begin "open (JXA fallback): secondary account -> Profile 2"
  XENV=("DRIVETHRU_JQ=$T/no-such-jq")
  run_dt open "$MC/$MYDRIVE/Syllabus.gdoc"
  want_rc 0
  want_chrome_open "$(doc_url "$C_SYLLABUS")" "$EMAIL_C" "$CHROME_PROFILE_C"
  end

  begin "open (JXA fallback): googlemail.com == gmail.com -> Profile 3"
  XENV=("DRIVETHRU_JQ=$T/no-such-jq")
  run_dt open "$MB/$MYDRIVE/Bob Notes.gdoc"
  want_rc 0
  want_chrome_open "$(doc_url "$B_NOTES")" "$EMAIL_B" "$CHROME_PROFILE_B"
  end

  begin "open (JXA fallback): gmail dots ignored -> Profile 5"
  XENV=("DRIVETHRU_JQ=$T/no-such-jq")
  R_CHROME=$T/chrome-dots
  run_dt open "$MB/$MYDRIVE/Bob Notes.gdoc"
  want_rc 0
  want_chrome_open "$(doc_url "$B_NOTES")" "$EMAIL_B" "Profile 5"
  end

  begin "open (JXA fallback): no profile -> default browser + authuser"
  XENV=("DRIVETHRU_JQ=$T/no-such-jq")
  run_dt open "$MDV/$MYDRIVE/Grades.gsheet"
  want_rc 0
  want_default_open "$(sheet_url "$D_GRADES")" "$EMAIL_D"
  want_dry_lacks_re 'System Profile|Guest Profile|Profile 9'
  end
}

# mk_chrome DIR "Profile N=email" ... : a minimal Chrome user-data dir
mk_chrome() {
  local d=$1 sep="" p e
  shift
  mkdir -p "$d"
  {
    printf '{"profile":{"info_cache":{'
    for p in "$@"; do
      e=${p#*=}
      printf '%s"%s":{"name":"x","user_name":"%s"}' "$sep" "${p%%=*}" "$e"
      sep=","
      mkdir -p "$d/${p%%=*}"
      printf '{"account_info":[{"email":"%s"}]}\n' "$e" >"$d/${p%%=*}/Preferences"
    done
    printf '}}}\n'
  } >"$d/Local State"
}

g_search() {
  if [ -z "$FZF" ]; then
    skip "search: all" "fzf is not installed"
    return
  fi
  begin "search: top result, label<TAB>path, no terminal needed"
  run_dt search Budget.gsheet
  want_rc 0
  want_out_first "example${TAB}$MYDRIVE/Projects/Budget.gsheet"
  local odd
  odd=$(printf '%s\n' "$OUT" | grep -Ev "^[^${TAB}]+${TAB}[^${TAB}]+\$" | head -n 1)
  [ -z "$odd" ] || bad "malformed line [$odd]"
  end

  begin "search: the label is searchable (bob notes)"
  run_dt search "bob notes"
  want_rc 0
  want_out_first "bob${TAB}$MYDRIVE/Bob Notes.gdoc"
  end

  begin "search: default --limit is 10"
  run_dt search e
  want_rc 0
  [ "$(printf '%s\n' "$OUT" | grep -c .)" = 10 ] || bad "want 10 lines, got $(printf '%s\n' "$OUT" | grep -c .)"
  end

  begin "search: --limit N"
  run_dt search --limit 2 pdf
  want_rc 0
  [ "$(printf '%s\n' "$OUT" | grep -c .)" = 2 ] || bad "want 2 lines, got $(printf '%s\n' "$OUT" | grep -c .)"
  end

  begin "search: --links appends the share link column"
  run_dt search --links --limit 1 Budget.gsheet
  want_rc 0
  want_out "example${TAB}$MYDRIVE/Projects/Budget.gsheet${TAB}$(sheet_url "$A_BUDGET")"
  want_no_authuser_anywhere
  end

  begin "search: --links resolves shortcuts to their target"
  run_dt search --links --limit 1 "Shortcut to Plan"
  want_rc 0
  want_out "example${TAB}$MYDRIVE/Shortcut to Plan.gdoc${TAB}$(doc_url "$A_PLAN")"
  end

  begin "search: --copy-first prints and copies the top link"
  run_dt search --copy-first Budget.gsheet
  want_rc 0
  want_out_has "$(sheet_url "$A_BUDGET")"
  want_clip "$(sheet_url "$A_BUDGET")"
  want_no_authuser_anywhere
  end

  # The Raycast script command calls `search --copy-first -- "$1"`.
  begin "search: -- ends options (query starting with a dash)"
  run_dt search --copy-first -- "$NAME_DASH"
  want_rc 0
  want_out "$(file_url "$A_DASH")"
  want_clip "$(file_url "$A_DASH")"
  end

  begin "search: never shows hidden or bookkeeping items"
  run_dt search --limit 50 pdf
  want_rc 0
  want_out_line "example${TAB}$MYDRIVE/Projects/Report.pdf"
  want_out_lacks "Old Deleted"
  want_out_lacks ".shortcut-targets-by-id"
  want_out_lacks_re "(^|$TAB|/)\\."
  end

  begin "search: no match -> no output, exit 0"
  run_dt search zzqqxxjjvv
  want_rc 0
  want_out_empty
  end

  begin "search: --copy-first with no match -> exit 1, clipboard untouched"
  run_dt search --copy-first zzqqxxjjvv
  want_rc 1
  want_out_empty
  want_clip_absent
  end

  begin "search: colliding account shows its full-email label"
  run_dt search --limit 1 Syllabus
  want_rc 0
  want_out_first "$EMAIL_C${TAB}$MYDRIVE/Syllabus.gdoc"
  end

  if [ "$FZF_IN_PREFIX" = 1 ]; then
    begin "search: works with a hotkey-style PATH (/usr/bin:/bin:/usr/sbin:/sbin)"
    R_PATH=/usr/bin:/bin:/usr/sbin:/sbin
    XENV=(DRIVETHRU_FZF=)
    run_dt search --limit 1 Budget.gsheet
    want_rc 0
    want_out_first "example${TAB}$MYDRIVE/Projects/Budget.gsheet"
    end
  else
    skip "search: hotkey-style PATH" "fzf is not in /opt/homebrew/bin, /usr/local/bin or /opt/local/bin"
  fi
}

g_popup() {
  local line before after f abs_q
  abs_q=$(printf '%q' "$DT_ABS")

  has_abs() { case "$1" in *"$DT_ABS"*|*"$abs_q"*) return 0 ;; esac; return 1; }

  begin "popup: Ghostty command line (all flags before -e), returns at once"
  XENV=(DRIVETHRU_TERMINAL=ghostty)
  run_dt popup
  want_rc 0
  want_faster_than 5000
  line=$(dry_lines | grep -F 'Ghostty' | head -n 1)
  if [ -z "$line" ]; then bad "no Ghostty dry-run line"; else
    printf '%s\n' "$line" | grep -Eq '(^|[ /])open -na Ghostty --args ' || bad "want 'open -na Ghostty --args': [$line]"
    before=${line%% -e *}
    after=${line#* -e }
    for f in --window-width=130 --window-height=26 --title=drivethru \
             --confirm-close-surface=false --window-save-state=never \
             --quit-after-last-window-closed=true; do
      case "$before" in *"$f"*) ;; *) bad "missing $f before -e" ;; esac
      case "$after" in *"$f"*) bad "$f after -e" ;; esac
    done
    has_abs "$after" || bad "absolute drivethru path not after -e: [$line]"
    case "$after" in *--in-popup*) ;; *) bad "missing --in-popup" ;; esac
  fi
  end

  begin "popup: popup_size config and the query are passed on (Ghostty)"
  XENV=(DRIVETHRU_TERMINAL=ghostty)
  cfg "popup_size = 100x20"
  run_dt popup budget
  want_rc 0
  line=$(dry_lines | grep -F 'Ghostty' | head -n 1)
  case "$line" in *--window-width=100*) ;; *) bad "want --window-width=100: [$line]" ;; esac
  case "$line" in *--window-height=20*) ;; *) bad "want --window-height=20: [$line]" ;; esac
  case "$line" in *"--in-popup budget"*) ;; *) bad "want '--in-popup budget': [$line]" ;; esac
  end

  begin "popup: kitty command line"
  XENV=(DRIVETHRU_TERMINAL=kitty)
  run_dt popup
  want_rc 0
  line=$(dry_lines | grep -F 'kitty' | head -n 1)
  if [ -z "$line" ]; then bad "no kitty dry-run line"; else
    printf '%s\n' "$line" | grep -Eq '(^|[ /])open -na kitty --args ' || bad "want 'open -na kitty --args': [$line]"
    for f in "-o remember_window_size=no" "-o initial_window_width=130c" \
             "-o initial_window_height=26c" "-o macos_quit_when_last_window_closed=yes" \
             "-o confirm_os_window_close=0" "--title drivethru"; do
      case "$line" in *"$f"*) ;; *) bad "missing [$f]" ;; esac
    done
    case "$line" in *"$DT_ABS --in-popup"*|*"$abs_q --in-popup"*) ;; *) bad "want 'ABS --in-popup': [$line]" ;; esac
  fi
  end

  begin "popup: kitty uses popup_size in cells"
  XENV=(DRIVETHRU_TERMINAL=kitty)
  cfg "popup_size = 90x15"
  run_dt popup
  line=$(dry_lines | grep -F 'kitty' | head -n 1)
  case "$line" in *initial_window_width=90c*initial_window_height=15c*) ;; *) bad "sizes: [$line]" ;; esac
  end

  begin "popup: WezTerm command line"
  XENV=(DRIVETHRU_TERMINAL=wezterm)
  run_dt popup
  want_rc 0
  line=$(dry_lines | grep -F 'WezTerm' | head -n 1)
  if [ -z "$line" ]; then bad "no WezTerm dry-run line"; else
    printf '%s\n' "$line" | grep -Eq '(^|[ /])open -na WezTerm --args ' || bad "want 'open -na WezTerm --args': [$line]"
    for f in "--config initial_cols=130" "--config initial_rows=26" "start --always-new-process -- "; do
      case "$line" in *"$f"*) ;; *) bad "missing [$f]" ;; esac
    done
    case "$line" in *"-- $DT_ABS --in-popup"*|*"-- $abs_q --in-popup"*) ;; *) bad "want '-- ABS --in-popup': [$line]" ;; esac
  fi
  end

  begin "popup: Alacritty command line"
  XENV=(DRIVETHRU_TERMINAL=alacritty)
  run_dt popup
  want_rc 0
  line=$(dry_lines | grep -F 'Alacritty' | head -n 1)
  if [ -z "$line" ]; then bad "no Alacritty dry-run line"; else
    printf '%s\n' "$line" | grep -Eq '(^|[ /])open -na Alacritty --args ' || bad "want 'open -na Alacritty --args': [$line]"
    for f in "-o window.dimensions.columns=130" "-o window.dimensions.lines=26" "-T drivethru"; do
      case "$line" in *"$f"*) ;; *) bad "missing [$f]" ;; esac
    done
    case "$line" in *"-e $DT_ABS --in-popup"*|*"-e $abs_q --in-popup"*) ;; *) bad "want '-e ABS --in-popup': [$line]" ;; esac
  fi
  end

  begin "popup: iTerm2 via AppleScript (osascript)"
  XENV=(DRIVETHRU_TERMINAL=iterm2)
  run_dt popup
  want_rc 0
  want_dry_re 'osascript'
  has_abs "$ERR" || bad "absolute drivethru path not mentioned"
  end

  begin "popup: Terminal.app via AppleScript (osascript)"
  XENV=(DRIVETHRU_TERMINAL=terminal)
  run_dt popup
  want_rc 0
  want_dry_re 'osascript'
  has_abs "$ERR" || bad "absolute drivethru path not mentioned"
  end

  begin "popup: terminal from the config file"
  cfg "terminal = alacritty"
  run_dt popup
  want_rc 0
  want_dry_re 'open -na Alacritty'
  end

  begin "popup: auto-detects an installed terminal and returns at once"
  run_dt popup
  want_rc 0
  want_faster_than 5000
  [ -n "$(dry_lines)" ] || bad "no dry-run launch line"
  has_abs "$ERR" || bad "absolute drivethru path not mentioned"
  end
}

g_tty() {
  local args
  for args in "" "pick" "pick Budget" "Budget"; do
    begin "tty: 'drivethru $args' with no terminal exits 1 quickly (no hang)"
    DT_TIMEOUT=8
    # shellcheck disable=SC2086  # split the argument list on purpose
    run_dt $args
    want_rc 1
    want_out_empty
    want_err_re 'needs a terminal'
    want_faster_than 4000
    end
  done

  begin "tty: --in-popup with no terminal does not hang"
  # shellcheck disable=SC2034  # read by run_dt
  DT_TIMEOUT=8
  run_dt --in-popup
  want_rc_nonzero
  want_faster_than 7000
  end
}

g_doctor() {
  begin "doctor: healthy fixture -> exit 0, mentions the accounts"
  run_dt doctor
  want_rc 0
  case "$OUT$ERR" in *"$EMAIL_A"*) ;; *) bad "does not mention $EMAIL_A" ;; esac
  end

  begin "doctor: no mounts -> non-zero exit"
  R_ROOT=$T/empty-root
  mkdir -p "$R_ROOT"
  run_dt doctor
  want_rc_nonzero
  end

  begin "doctor: warns about unknown config keys"
  cfg "frobnicate = 1"
  run_dt doctor
  case "$OUT$ERR" in *frobnicate*) ;; *) bad "unknown key not mentioned" ;; esac
  end
}

g_config() {
  begin "config: comments, blank lines, inline comments, spacing"
  cfg "# label.$EMAIL_A = commented-out" \
      "   # indented comment" \
      "" \
      "label.$EMAIL_A = work   # inline comment" \
      "label.$EMAIL_B=bobby" \
      "   label.$EMAIL_C   =   uni   "
  run_dt list
  want_rc 0
  want_out_line "work${TAB}$MYDRIVE/Projects/Plan.gdoc"
  want_out_line "bobby${TAB}$MYDRIVE/Bob Notes.gdoc"
  want_out_line "uni${TAB}$MYDRIVE/Syllabus.gdoc"
  want_out_lacks "commented-out"
  want_out_lacks "inline comment"
  end

  begin "config: unknown keys and junk lines are ignored silently"
  cfg "frobnicate = 1" "this line has no equals sign" "= no key"
  run_dt list
  want_rc 0
  want_out_line "example${TAB}$MYDRIVE/Projects/Plan.gdoc"
  want_err_lacks "frobnicate"
  end

  begin "config: an invalid value for a known key is a config error (1)"
  cfg "browser = netscape-navigator"
  run_dt link "$PA/Plan.gdoc"
  want_rc 1
  want_out_empty
  want_err_has "browser"
  end

  begin "config: invalid popup_size is a config error (1)"
  cfg "popup_size = huge"
  run_dt popup
  want_rc 1
  want_err_has "popup_size"
  end

  begin "config: --help and --version still work with a bad config"
  cfg "browser = netscape-navigator"
  run_dt --help
  want_rc 0
  run_dt --version
  want_rc 0
  end

  begin "config: doctor reports an invalid value"
  cfg "browser = netscape-navigator"
  run_dt doctor
  case "$OUT$ERR" in *netscape-navigator*) ;; *) bad "doctor does not mention the bad value" ;; esac
  end

  begin "config: missing config file is fine"
  R_CFG=$T/no-such-config
  run_dt list
  want_rc 0
  want_out_line "example${TAB}$MYDRIVE/Projects/Plan.gdoc"
  end

  begin "config: values are never executed (labels)"
  cfg "label.$EMAIL_A = \$(touch pwned-cfg1)" \
      "label.$EMAIL_B = \`touch pwned-cfg2\`" \
      "\$(touch pwned-cfg3) = x" \
      "touch pwned-cfg4"
  run_dt list
  want_rc 0
  want_out_line "\$(touch pwned-cfg1)${TAB}$MYDRIVE/Projects/Plan.gdoc"
  local n
  for n in 1 2 3 4; do want_absent "$WORK/pwned-cfg$n"; want_absent "$FHOME/pwned-cfg$n"; done
  end

  begin "config: values are never executed (browser, terminal, popup_size, db, notify)"
  cfg "browser = \$(touch pwned-cfg5)" \
      "terminal = ;touch pwned-cfg6" \
      "popup_size = 1x1;touch pwned-cfg7" \
      "db = \$(touch pwned-cfg8)" \
      "notify = \`touch pwned-cfg9\`"
  run_dt open "$PA/Plan.gdoc"
  run_dt popup
  run_dt link --notify "$PA/Plan.gdoc"
  run_dt doctor
  for n in 5 6 7 8 9; do want_absent "$WORK/pwned-cfg$n"; want_absent "$FHOME/pwned-cfg$n"; done
  end

  begin "config: dry-run does not execute an after_open shell command"
  cfg "browser = default" "after_open = touch '$T/after-ran'; [[ -n \$BASH_VERSION ]] && touch '$T/after-bash'"
  rm -f "$T/after-ran" "$T/after-bash"
  run_dt open "$PA/Plan.gdoc"
  want_rc 0
  want_dry_re 'after_open'
  want_absent "$T/after-ran"
  want_absent "$T/after-bash"
  end

  begin "config: the final line is applied without a trailing newline"
  printf 'label.%s = final-line' "$EMAIL_A" >"$CFG"
  run_dt list
  want_rc 0
  want_out_line "final-line${TAB}$MYDRIVE/Projects/Plan.gdoc"
  end

  begin "config: CRLF line endings are accepted"
  printf 'label.%s = windows-line\r\nbrowser = default\r\n' "$EMAIL_A" >"$CFG"
  run_dt list
  want_rc 0
  want_out_line "windows-line${TAB}$MYDRIVE/Projects/Plan.gdoc"
  end

  begin "config: notify = true applies to link --copy"
  cfg "notify = true"
  run_dt link --copy "$PA/Plan.gdoc"
  want_rc 0
  want_clip "$(doc_url "$A_PLAN")"
  want_dry_re 'notify'
  end
}

db_skip_reason=""
g_db() {
  if ! grep -q 'metadata_sqlite_db' "$DT"; then
    db_skip_reason="the core has no DriveFS database support yet"
  fi
  if ! /usr/bin/sqlite3 -version >/dev/null 2>&1; then
    db_skip_reason="no /usr/bin/sqlite3"
  fi
  if [ -n "$db_skip_reason" ]; then
    skip "db: all DriveFS database tests" "$db_skip_reason"
    return
  fi
  local before_db after_db
  before_db=$(cd "$DRIVEFS" && ls -laR . && /sbin/md5 -r "$ACCT_A"/metadata_sqlite_db*)

  begin "db: legacy file gets its resource key (proto field 140)"
  run_dt link "$PA/Legacy Scan.pdf"
  want_rc 0
  want_out "$(with_key "$(file_url "$A_LEGACY")" "$A_LEGACY_KEY")"
  want_err_lacks_re 'legacy'
  end

  begin "db: legacy folder gets its resource key"
  run_dt link "$MA/$MYDRIVE/Legacy Archive"
  want_rc 0
  want_out "$(with_key "$(folder_url "$A_LEGACYDIR")" "$A_LEGACYDIR_KEY")"
  end

  begin "db: binary shortcut stand-in resolves to its target"
  run_dt link "$MA/$MYDRIVE/Standin Scan.pdf"
  want_rc 0
  want_out "$(file_url "$A_STANDIN_PDF_TARGET")"
  end

  begin "db: binary stand-in to a legacy target carries the target's key"
  run_dt link "$MA/$MYDRIVE/Standin Old.pdf"
  want_rc 0
  want_out "$(with_key "$(file_url "$A_STANDIN_OLD_TARGET")" "$A_STANDIN_OLD_KEY")"
  end

  link_is "db: shortcut resource key from field 132.7 without a target items row" \
    "$MA/$MYDRIVE/Standin Remote.pdf" "$(with_key "$(file_url "$A_STANDIN_REMOTE_TARGET")" "$A_STANDIN_REMOTE_KEY")"
  link_is "db: symlink to a stub stand-in resolves the final target" \
    "$MA/$MYDRIVE/Shortcut to Standin Doc.gdoc" "$(doc_url "$A_STANDIN_DOC_TARGET")"
  link_is "db: symlink to a binary stand-in resolves the final target and key" \
    "$MA/$MYDRIVE/Shortcut to Standin Old.pdf" "$(with_key "$(file_url "$A_STANDIN_OLD_TARGET")" "$A_STANDIN_OLD_KEY")"

  begin "db: an id inherited by a copy inside Drive is corrected"
  run_dt link "$PA/Report copy.pdf"
  want_rc 0
  want_out "$(file_url "$A_REPORTCOPY")"
  end

  link_is "db: the original of that copy keeps its id" "$PA/Report.pdf" "$(file_url "$A_REPORT")"
  link_is "db: NFC name on disk vs NFD title in the DB" "$ODD/$NAME_UNICODE" "$(file_url "$A_UNICODE")"
  link_is "db: ordinary doc is unaffected" "$PA/Plan.gdoc" "$(doc_url "$A_PLAN")"

  begin "db: db = off disables the lookup"
  cfg "db = off"
  run_dt link "$PA/Legacy Scan.pdf"
  want_rc 0
  want_out "$(file_url "$A_LEGACY")"
  want_err_re 'legacy'
  end

  begin "db: corrupt DB -> silent fallback to the xattr"
  rm -rf "$T/drivefs-bad"
  cp -R "$DRIVEFS" "$T/drivefs-bad"
  rm -f "$T/drivefs-bad/$ACCT_A"/metadata_sqlite_db*
  printf 'this is not a sqlite database\n' >"$T/drivefs-bad/$ACCT_A/metadata_sqlite_db"
  R_DRIVEFS=$T/drivefs-bad
  run_dt link "$PA/Legacy Scan.pdf" "$PA/Plan.gdoc"
  want_rc 0
  want_out "$(file_url "$A_LEGACY")
$(doc_url "$A_PLAN")"
  want_err_lacks_re 'sqlite|Error:|malformed|not a database'
  end

  begin "db: unexpected schema -> silent fallback to the xattr"
  rm -rf "$T/drivefs-schema"
  cp -R "$DRIVEFS" "$T/drivefs-schema"
  rm -f "$T/drivefs-schema/$ACCT_A"/metadata_sqlite_db*
  /usr/bin/sqlite3 "$T/drivefs-schema/$ACCT_A/metadata_sqlite_db" \
    "CREATE TABLE items (x TEXT); INSERT INTO items VALUES ('$A_LEGACY');" >/dev/null 2>&1
  R_DRIVEFS=$T/drivefs-schema
  run_dt link "$PA/Legacy Scan.pdf"
  want_rc 0
  want_out "$(file_url "$A_LEGACY")"
  want_err_lacks_re 'sqlite|Error:|no such (column|table)'
  end

  begin "db: open URL keeps the resource key and adds authuser after it"
  cfg "browser = default"
  run_dt open "$PA/Legacy Scan.pdf"
  want_rc 0
  want_default_open "$(with_key "$(file_url "$A_LEGACY")" "$A_LEGACY_KEY")" "$EMAIL_A"
  end

  begin "db: rows still in the -wal file are seen (the WAL is copied too)"
  local wal_key=0-WalOnlyKey_AbCdEfGhIjK wdb
  rm -rf "$T/drivefs-wal"
  cp -R "$DRIVEFS" "$T/drivefs-wal"
  wdb=$T/drivefs-wal/$ACCT_A/metadata_sqlite_db
  # change the key in a transaction that stays in the WAL (no checkpoint),
  # and snapshot db + wal while that connection is still open
  /usr/bin/sqlite3 "$wdb" "PRAGMA wal_autocheckpoint=0;" \
    "UPDATE items SET proto = CAST(replace(CAST(proto AS BLOB), CAST('$A_LEGACY_KEY' AS BLOB), CAST('$wal_key' AS BLOB)) AS TEXT) WHERE id='$A_LEGACY';" \
    ".shell cp '$wdb' '$wdb.snap' && cp '$wdb-wal' '$wdb.snap-wal'" >/dev/null 2>&1
  if [ -s "$wdb.snap-wal" ]; then
    rm -f "$wdb" "$wdb-wal" "$wdb-shm"
    mv "$wdb.snap" "$wdb"
    mv "$wdb.snap-wal" "$wdb-wal"
    R_DRIVEFS=$T/drivefs-wal
    run_dt link "$PA/Legacy Scan.pdf"
    want_rc 0
    want_out "$(with_key "$(file_url "$A_LEGACY")" "$wal_key")"
  else
    bad "could not build a WAL-only fixture (sqlite3 checkpointed?)"
  fi
  end

  begin "db: DRIVETHRU_DEBUG=1 explains the id source"
  XENV=(DRIVETHRU_DEBUG=1)
  run_dt link "$PA/Legacy Scan.pdf"
  want_rc 0
  want_err_re 'db|database|sqlite'
  end

  begin "db: the live DB is never opened in place (no new -wal/-shm, unchanged)"
  after_db=$(cd "$DRIVEFS" && ls -laR . && /sbin/md5 -r "$ACCT_A"/metadata_sqlite_db*)
  [ "$before_db" = "$after_db" ] || bad "DriveFS dir changed"
  end

  begin "db: temporary DB copies are removed"
  local left
  left=$(find "$TTMP" -name 'metadata_sqlite_db*' 2>/dev/null | head -n 3)
  [ -z "$left" ] || bad "left behind: [$left]"
  end
}

# run_pick ACTION... : drive the real fzf picker through expect
run_pick() {
  local a
  LAST_CMD="interactive.exp drivethru pick"
  for a in "$@"; do LAST_CMD="$LAST_CMD $(printf '%q' "$a")"; done
  rm -f "$T/pick.err" "$CLIP"
  (
    cd "$RUN_CWD" || exit 97
    with_timeout 40 /usr/bin/env -i \
      HOME="$FHOME" USER="$T_USER" LOGNAME="$T_USER" SHELL=/bin/zsh \
      PATH="$R_PATH" TMPDIR="$TTMP" LANG=en_US.UTF-8 TERM=xterm-256color \
      VERBOSE="$VERBOSE" PICK_LOG="$T/pick.log" \
      DRIVETHRU_ROOT="$R_ROOT" DRIVETHRU_DRIVEFS_DIR="$R_DRIVEFS" \
      DRIVETHRU_CHROME_DIR="$R_CHROME" DRIVETHRU_CONFIG="$R_CFG" \
      DRIVETHRU_FZF="$FZF" \
      DRIVETHRU_DRY_RUN=1 DRIVETHRU_CLIPBOARD_FILE="$CLIP" \
      ${XENV[@]+"${XENV[@]}"} \
      /usr/bin/expect -f "$HERE/interactive.exp" "$DT" "$T/pick.err" "$@" \
      </dev/null >"$T/stdout" 2>&1
  )
  RC=$?
  OUT=$(cat "$T/stdout")
  ERR=$(cat "$T/pick.err" 2>/dev/null)
  case "$RC" in
    124) bad "expect run timed out" ;;
    96) bad "the picker never showed the expected screen text" ;;
    97) bad "the picker never showed fzf's match counter" ;;
    98) bad "drivethru did not exit after the last key" ;;
  esac
}

# Interactive tests are UI-timing sensitive (keys vs fzf re-ranking), so each
# gets one retry; only the last attempt counts. VERBOSE=1 reports retries.
pick_test() { # NAME FUNCTION [SETUP-CFG-LINE...]
  local name=$1 fn=$2 attempt
  shift 2
  for attempt in 1 2; do
    begin "$name"
    [ $# -gt 0 ] && cfg "$@"
    "$fn"
    if [ -z "$CUR_ERRS" ] || [ "$attempt" = 2 ]; then
      end
      return
    fi
    [ "$VERBOSE" = 1 ] && printf '    (retrying: %s)\n' "$(printf '%s' "$CUR_ERRS" | head -n 1 | sed 's/^ *- //')"
  done
}

want_clip_markdown() { # NAME-FRAGMENT URL
  if [ -e "$CLIP" ]; then
    grep -Eq "^\\[[^]]*$1[^]]*\\]\\($(re "$2")\\)\$" "$CLIP" ||
      bad "clipboard is not a markdown link: [$(cat "$CLIP")]"
  else
    bad "clipboard file not written"
  fi
}

ip_enter() {
  run_pick "type:Budget.gsheet" "key:enter"
  want_rc 0
  want_clip "$(sheet_url "$A_BUDGET")"
  want_err_has "Copied: "
}
ip_ctrl_o() {
  XENV=(FZF_DEFAULT_OPTS=--print-query)
  run_pick "type:Budget.gsheet" "key:ctrl-o"
  want_rc 0
  want_default_open "$(sheet_url "$A_BUDGET")" "$EMAIL_A"
  want_clip_absent
}
ip_ctrl_y() {
  run_pick "type:Budget.gsheet" "key:ctrl-y"
  want_rc 0
  want_clip_markdown Budget "$(sheet_url "$A_BUDGET")"
}
ip_ctrl_f() {
  run_pick "type:Budget.gsheet" "key:ctrl-f"
  want_rc 0
  want_dry_re 'open -R .*Budget\.gsheet'
  want_clip_absent
}
ip_multi() {
  run_pick "type:Budget.gsheet" "key:tab" "key:ctrl-u" "type:Pitch Deck" "key:tab" "key:enter"
  want_rc 0
  if [ -e "$CLIP" ]; then
    grep -Fxq "$(sheet_url "$A_BUDGET")" "$CLIP" || bad "clipboard lacks the sheet link"
    grep -Fxq "$(slides_url "$A_DECK")" "$CLIP" || bad "clipboard lacks the slides link"
    [ "$(grep -c . "$CLIP")" = 2 ] || bad "want 2 lines in the clipboard: [$(cat "$CLIP")]"
  else
    bad "clipboard file not written"
  fi
}
ip_multi_md() {
  run_pick "type:Budget.gsheet" "key:tab" "key:ctrl-u" "type:Pitch Deck" "key:tab" "key:ctrl-y"
  want_rc 0
  if [ -e "$CLIP" ]; then
    [ "$(grep -c '^\[.*\](https://' "$CLIP")" = 2 ] || bad "want 2 markdown lines: [$(cat "$CLIP")]"
  else
    bad "clipboard file not written"
  fi
}
ip_nomatch() {
  run_pick "type:zzqqxxjjvv" "key:enter"
  want_rc 130
  want_clip_absent
  [ -z "$(dry_lines)" ] || bad "a no-match enter must do nothing: [$(dry_lines | head -n 1)]"
}
ip_esc() {
  run_pick "type:Budget" "key:esc"
  want_rc 130
  want_clip_absent
  [ -z "$(dry_lines)" ] || bad "esc must do nothing: [$(dry_lines | head -n 1)]"
}
ip_in_popup() {
  run_pick "sub:--in-popup" "type:Budget.gsheet" "key:enter"
  want_rc 0
  want_clip "$(sheet_url "$A_BUDGET")"
  want_err_has "Copied: "
}
ip_query_arg() {
  run_pick "arg:Pitch Deck" "key:enter"
  want_rc 0
  want_clip "$(slides_url "$A_DECK")"
}
ip_label() {
  run_pick "arg:bob beach" "key:enter"
  want_rc 0
  want_clip "$(file_url "$B_BEACH")"
}
ip_newline() {
  run_pick "arg:Line Break.pdf" "key:enter"
  want_rc 0
  want_clip "$(file_url "$A_NEWLINE")"
}
ip_shortcut() {
  run_pick "arg:Broken Shortcut" "key:enter"
  want_rc 0
  want_clip "$(openid_url "$A_SC_BROKEN")"
  want_err_re "available locally"
}
ip_preview() {
  XENV=(SHELL=/usr/bin/false)
  run_pick "arg:Budget.gsheet" "wait:Link resolved when copied or opened" "sleep:0.3" "key:esc"
  want_rc 130
  local screen
  screen=$(/usr/bin/perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\e[()][0-9A-Za-z]//g; s/\r//g' "$T/pick.log" 2>/dev/null)
  case "$screen" in *ctrl-o*) ;; *) bad "header does not mention ctrl-o" ;; esac
  case "$screen" in *ctrl-y*) ;; *) bad "header does not mention ctrl-y" ;; esac
  case "$screen" in *"$EMAIL_A"*) ;; *) bad "preview does not show the account email" ;; esac
  case "$screen" in *"Link resolved when copied or opened"*) ;; *) bad "preview does not explain link resolution" ;; esac
  case "$screen" in *"https://"*) bad "preview presents an unverified share link" ;; esac
  printf '%s\n' "$screen" | grep -q 'Sheet' || bad "preview does not show the kind (Sheet)"
}
ip_injection() {
  run_pick "type:pwned" "sleep:1.5" "key:ctrl-p" "sleep:0.5" "key:ctrl-p" "sleep:1" "key:esc"
  want_rc 130
  want_absent "$WORK/pwned"
  want_absent "$WORK/pwned2"
  want_absent "$FHOME/pwned"
}

ip_terminal_controls() {
  local mount="$T/pick-controls/GoogleDrive-controls@example.net/$MYDRIVE"
  local name=$'Control\033]52;c;dGVzdA==\007.pdf'
  local item=1ControlNameFixtureXXXXXXXXXXXXXX
  mkdir -p "$mount"
  /usr/bin/xattr -w 'com.google.drivefs.item-id#S' 0AControlRootFixtureXXXXXXXXXXXXXX "$mount"
  printf 'synthetic\n' >"$mount/$name"
  /usr/bin/xattr -w 'com.google.drivefs.item-id#S' "$item" "$mount/$name"
  R_ROOT=$T/pick-controls
  run_pick "arg:Control" "key:enter"
  want_rc 0
  want_clip "$(file_url "$item")"
  # Older fzf renders its own UI to stderr; inspect only drivethru's status.
  if ! /usr/bin/perl -0777 -e '
    $s = <>; $s =~ /Copied: ([^\r\n]*)/ or exit 1;
    exit($1 =~ /[\x00-\x1f\x7f]/ ? 1 : 0);
  ' "$T/pick.err"; then
    bad "Copied status contains terminal controls or is missing"
  fi
}

g_interactive() {
  if [ ! -x /usr/bin/expect ]; then
    skip "interactive: all" "no /usr/bin/expect"
    return
  fi
  if [ -z "$FZF" ]; then
    skip "interactive: all" "fzf is not installed"
    return
  fi
  pick_test "interactive: enter copies the link of the match" ip_enter
  pick_test "interactive: ctrl-o opens despite ambient fzf protocol options" ip_ctrl_o "browser = default"
  pick_test "interactive: ctrl-y copies a Markdown link" ip_ctrl_y
  pick_test "interactive: ctrl-f reveals in Finder (dry-run open -R)" ip_ctrl_f
  pick_test "interactive: tab multi-select, enter copies every selected link" ip_multi
  pick_test "interactive: tab multi-select, ctrl-y copies every link as Markdown" ip_multi_md
  pick_test "interactive: esc cancels with exit 130 and does nothing" ip_esc
  pick_test "interactive: enter with no match exits 130 and does nothing" ip_nomatch
  pick_test "interactive: --in-popup copies, says Copied: NAME, exits 0" ip_in_popup
  pick_test "interactive: pick QUERY starts with that query" ip_query_arg
  pick_test "interactive: the account label is searchable (pick 'bob beach')" ip_label
  pick_test "interactive: a name with an embedded newline (read0/print0)" ip_newline
  pick_test "interactive: broken shortcut -> open?id= link and a warning" ip_shortcut
  pick_test "interactive: preview works with an incompatible ambient SHELL" ip_preview
  pick_test "interactive: preview of a \$(...) name runs nothing" ip_injection
  pick_test "interactive: Copied status escapes filename terminal commands" ip_terminal_controls
}

g_safety() {
  # Fake HOME exercises the guard without referring to any real Drive path.
  local guard=$T/guard-home destination
  mkdir -p "$guard/Library/CloudStorage" "$guard/Library/Application Support/Google/DriveFS"
  ln -s "$guard/Library/CloudStorage" "$T/guard-alias"
  for destination in "$guard/Library/CloudStorage/refused" \
    "$guard/Library/Application Support/Google/DriveFS/refused" \
    "$T/guard-alias/refused"; do
    begin "safety: fixture builder rejects protected ancestor ${destination##*/Library/}"
    with_timeout 10 /usr/bin/env HOME="$guard" TMPDIR="$TTMP" \
      "$HERE/make-fixture.sh" "$destination" >"$T/guard.out" 2>&1
    [ "$?" = 1 ] || bad "fixture builder did not refuse the protected destination"
    grep -q 'refusing to write under' "$T/guard.out" || bad "missing refusal explanation"
    want_absent "$destination"
    end
  done
  if [ -d "$guard/library/cloudstorage" ]; then
    begin "safety: fixture builder rejects a case-variant protected ancestor"
    destination=$guard/library/cloudstorage/refused
    with_timeout 10 /usr/bin/env HOME="$guard" TMPDIR="$TTMP" \
      "$HERE/make-fixture.sh" "$destination" >"$T/guard.out" 2>&1
    [ "$?" = 1 ] || bad "fixture builder accepted a case-variant Drive path"
    want_absent "$destination"
    end
  fi
  if [ -d "/System/Volumes/Data$guard/Library/CloudStorage" ]; then
    begin "safety: fixture builder rejects a Data volume alias of a protected ancestor"
    destination=/System/Volumes/Data$guard/Library/CloudStorage/refused
    with_timeout 10 /usr/bin/env HOME="$guard" TMPDIR="$TTMP" \
      "$HERE/make-fixture.sh" "$destination" >"$T/guard.out" 2>&1
    [ "$?" = 1 ] || bad "fixture builder accepted a Data volume alias of Drive"
    want_absent "$destination"
    end
  fi

  begin "safety: fixture tree, DriveFS dir and Chrome dir are unchanged"
  manifest >"$T/manifest.after"
  if ! cmp -s "$T/manifest.before" "$T/manifest.after"; then
    bad "changed: $(diff "$T/manifest.before" "$T/manifest.after" | grep '^[<>]' | head -n 4 | tr '\n' ' ')"
  fi
  end

  begin "safety: no stray files from name/config injection"
  local hits
  hits=$(find "$T" -name 'pwned*' 2>/dev/null | head -n 3)
  [ -z "$hits" ] || bad "found: $hits"
  end

  begin "safety: TMPDIR left clean"
  hits=$(find "$TTMP" -mindepth 1 2>/dev/null | head -n 3)
  [ -z "$hits" ] || bad "left in TMPDIR: $hits"
  end

  if [ "$CLIP_STATE0" = clean ]; then
    begin "safety: the real clipboard never received a fixture link"
    [ "$(clip_state)" = clean ] || bad "the real clipboard now holds a fixture id"
    end
  else
    skip "safety: real clipboard untouched" "pbpaste unavailable or already holding a fixture id"
  fi
}

# shellcheck source=tests/review-core.sh disable=SC1091
. "$HERE/review-core.sh"
# shellcheck source=tests/review-browser.sh disable=SC1091
. "$HERE/review-browser.sh"

for g in $ALL_GROUPS; do
  if want_group "$g"; then
    "g_$g"
  fi
done

printf '\n%s passed, %s failed, %s skipped\n' "$N_PASS" "$N_FAIL" "$N_SKIP"
if [ "$N_FAIL" -gt 0 ]; then
  printf 'failed:\n%s' "$FAILED" | sed '2,$s/^/  /'
  exit 1
fi
exit 0
