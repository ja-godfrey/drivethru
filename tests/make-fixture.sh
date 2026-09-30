#!/bin/bash
# make-fixture.sh DIR
#
# Build a synthetic Google Drive for desktop tree under DIR. Nothing in it is
# real: every id, email and name comes from tests/fixture-ids.sh.
#
#   DIR/CloudStorage/            -> DRIVETHRU_ROOT
#       GoogleDrive-alice@example.com/   My Drive, Shared drives/Team Alpha,
#                                        Other computers, hidden bookkeeping,
#                                        every shortcut form, fake DB
#       GoogleDrive-bob@gmail.com/       My Drive only (no DB)
#       GoogleDrive-carol@umich.edu/     My Drive + EMPTY Shared drives
#       GoogleDrive-dave@umich.edu/      My Drive only (label collides w/ carol)
#       OneDrive-Personal/Stray.pdf      carries a Drive id but is not in Drive
#   DIR/DriveFS/<N>/             -> DRIVETHRU_DRIVEFS_DIR (metadata_sqlite_db
#                                   for alice only, my-drive symlinks)
#   DIR/Chrome/                  -> DRIVETHRU_CHROME_DIR (Local State +
#                                   Preferences)
#   DIR/home/                    -> HOME (alias symlink to alice's mount,
#                                   Desktop copy of a Drive file)
#
# Runs on stock macOS (/bin/bash 3.2, /usr/bin/xattr, /usr/bin/sqlite3).

set -eu

here=$(cd -P "$(dirname "$0")" && pwd)
# shellcheck source=tests/fixture-ids.sh disable=SC1091
. "$here/fixture-ids.sh"

die() { printf 'make-fixture: %s\n' "$*" >&2; exit 1; }

[ $# -eq 1 ] || die "usage: make-fixture.sh DIR"
target=$1
case "$target" in /*) ;; *) target=$PWD/$target ;; esac

# Never build inside the user's real Drive or DriveFS state. Checked before
# anything is created: compare every existing ancestor by filesystem identity.
# String prefixes alone miss case-insensitive paths and /System/Volumes/Data.
anc=$target
while [ ! -d "$anc" ]; do anc=$(dirname "$anc"); done
anc=$(cd -P "$anc" && pwd)
for real in "$HOME/Library/CloudStorage" "$HOME/Library/Application Support/Google"; do
  case "$target/" in "$real"/*) die "refusing to write under $real" ;; esac
  if [ -d "$real" ]; then
    probe=$anc
    while :; do
      [ ! "$probe" -ef "$real" ] || die "refusing to write under $real"
      [ "$probe" != / ] || break
      probe=$(dirname "$probe")
    done
  fi
done
mkdir -p "$target"
DIR=$(cd -P "$target" && pwd)
[ -z "$(ls -A "$DIR")" ] || die "$DIR is not empty"

ROOT=$DIR/CloudStorage
DRIVEFS=$DIR/DriveFS
CHROME=$DIR/Chrome
FHOME=$DIR/home
XA='com.google.drivefs.item-id#S'
DOMAIN_XA='com.apple.file-provider-domain-id'

mkdir -p "$ROOT" "$DRIVEFS" "$CHROME" "$FHOME/Desktop" "$FHOME/.config"

# ---------------------------------------------------------------- DB rows --
# Only alice's account gets a (fake) DriveFS metadata DB. Rows are collected
# as SQL while the tree is built and loaded at the end.
SQL_DIR=$(mktemp -d "${TMPDIR:-/tmp}/drivethru-fixture-sql.XXXXXX")
trap 'rm -rf "$SQL_DIR"' EXIT
SQL_ITEMS=$SQL_DIR/items.sql
SQL_LINKS=$SQL_DIR/links.sql
: >"$SQL_ITEMS"
: >"$SQL_LINKS"
DB_ON=0
SID=100

MIME_FOLDER=application/vnd.google-apps.folder
MIME_SHORTCUT=application/vnd.google-apps.shortcut
MIME_PDF=application/pdf

sql_q() { # escape for a single-quoted SQL literal
  local q="'"
  printf '%s' "${1//$q/$q$q}"
}

hex_of() { printf '%s' "$1" | /usr/bin/od -An -v -tx1 | tr -d ' \n'; }

varint_hex() {
  local n=$1
  while [ "$n" -ge 128 ]; do
    printf '%02x' $(( (n & 127) | 128 ))
    n=$(( n >> 7 ))
  done
  printf '%02x' "$n"
}

pb_bytes() { # FIELD HEXPAYLOAD -> length-delimited protobuf field, hex
  varint_hex $(( ($1 << 3) | 2 ))
  varint_hex $(( ${#2} / 2 ))
  printf '%s' "$2"
}

pb_str() { pb_bytes "$1" "$(hex_of "$2")"; }

# db_add ID PARENT_ID TITLE MIME IS_FOLDER [KEY [SC_TARGET SC_MIME [SC_KEY]]]
db_add() {
  [ "$DB_ON" = 1 ] || return 0
  local id=$1 parent=$2 title=$3 mime=$4 isf=$5 key=${6:-}
  local sc_target=${7:-} sc_mime=${8:-} sc_key=${9:-}
  local proto sub
  proto=$(pb_str 1 "$id")
  [ -n "$parent" ] && proto=$proto$(pb_str 2 "$parent")
  proto=$proto$(pb_str 4 "$mime")
  if [ -n "$sc_target" ]; then
    sub=$(pb_str 1 "$sc_target")$(pb_str 3 "$sc_mime")
    [ -n "$sc_key" ] && sub=$sub$(pb_str 7 "$sc_key")
    proto=$proto$(pb_bytes 132 "$sub")
  fi
  [ -n "$key" ] && proto=$proto$(pb_str 140 "$key")
  SID=$((SID + 1))
  printf "INSERT INTO items (stable_id,id,proto,trashed,starred,is_owner,mime_type,is_folder,modified_date,file_size,is_tombstone,local_title,subscribed,team_drive_stable_id,inaccessible_inheritance_broken) VALUES (%s,'%s',CAST(X'%s' AS TEXT),0,0,1,'%s',%s,1700000000000,NULL,0,'%s',1,NULL,0);\n" \
    "$SID" "$id" "$proto" "$mime" "$isf" "$(sql_q "$title")" >>"$SQL_ITEMS"
  printf "INSERT INTO stable_ids (stable_id,cloud_id) VALUES (%s,'%s');\n" "$SID" "$id" >>"$SQL_ITEMS"
  if [ -n "$parent" ]; then
    printf "INSERT INTO stable_parents SELECT c.stable_id,p.stable_id,0 FROM items c JOIN items p ON p.id='%s' WHERE c.id='%s';\n" \
      "$parent" "$id" >>"$SQL_LINKS"
  fi
  if [ -n "$sc_target" ]; then
    printf "INSERT INTO shortcut_details SELECT s.stable_id,t.stable_id,'%s' FROM items s JOIN items t ON t.id='%s' WHERE s.id='%s';\n" \
      "$sc_mime" "$sc_target" "$id" >>"$SQL_LINKS"
  fi
}

# ------------------------------------------------------------ tree helpers --
M=""      # current mount
E=""      # current account email

setid()   { /usr/bin/xattr -w "$XA" "$2" "$1"; }
setid_s() { /usr/bin/xattr -s -w "$XA" "$2" "$1"; }

# dir_item REL ID PARENT_ID [TITLE_IN_DB]
dir_item() {
  mkdir -p "$M/$1"
  setid "$M/$1" "$2"
  db_add "$2" "$3" "${4:-$(basename "$1")}" "$MIME_FOLDER" 1
}

# raw_file REL [ID]: a file on disk only (no DB row)
raw_file() {
  printf 'synthetic %s\n' "$(basename "$1")" >"$M/$1"
  if [ -n "${2:-}" ]; then setid "$M/$1" "$2"; fi
}

# file_item REL ID PARENT_ID MIME [DB_KEY] [TITLE_IN_DB]
file_item() {
  raw_file "$1" "$2"
  if [ -n "$2" ]; then
    db_add "$2" "$3" "${6:-$(basename "$1")}" "$4" 0 "${5:-}"
  fi
}

# stub_item REL XATTR_ID PARENT_ID MIME DOC_ID RESOURCE_KEY_JSON [MODE]
# RESOURCE_KEY_JSON is a JSON literal: "" , null or "0-...".
stub_item() {
  printf '{"":"WARNING! DO NOT EDIT THIS FILE! ANY CHANGES MADE WILL BE LOST!","doc_id":"%s","resource_key":%s,"email":"%s"}' \
    "$5" "$6" "$E" >"$M/$1"
  setid "$M/$1" "$2"
  chmod "${7:-600}" "$M/$1"
  if [ "$2" = "$5" ]; then
    db_add "$2" "$3" "$(basename "$1")" "$4" 0
  else # shortcut stand-in: xattr is the shortcut, doc_id the target
    db_add "$2" "$3" "$(basename "$1")" "$MIME_SHORTCUT" 0 "" "$5" "$4"
  fi
}

new_mount() { # EMAIL ACCOUNT_NUMBER
  E=$1
  M=$ROOT/GoogleDrive-$1
  mkdir -p "$M"
  /usr/bin/xattr -w "$DOMAIN_XA" "com.google.drivefs.fpext/gdrive-$2" "$M"
  mkdir -p "$DRIVEFS/$2"
  printf 'synthetic\n' >"$M/.DS_Store"
}

# ====================================================== alice@example.com ==
new_mount "$EMAIL_A" "$ACCT_A"
DB_ON=1
MD="$MYDRIVE"
dir_item "$MD" "$A_MYDRIVE" ""
ln -s "$M/$MD" "$DRIVEFS/$ACCT_A/my-drive"

P="$MD/Projects"
dir_item "$P" "$A_PROJECTS" "$A_MYDRIVE"
stub_item "$P/Plan.gdoc"          "$A_PLAN"   "$A_PROJECTS" application/vnd.google-apps.document     "$A_PLAN"   '""' 400
stub_item "$P/Budget.gsheet"      "$A_BUDGET" "$A_PROJECTS" application/vnd.google-apps.spreadsheet  "$A_BUDGET" '"not-a-key"'
stub_item "$P/Pitch Deck.gslides" "$A_DECK"   "$A_PROJECTS" application/vnd.google-apps.presentation "$A_DECK"   'null'
stub_item "$P/Signup Survey.gform" "$A_FORM"  "$A_PROJECTS" application/vnd.google-apps.form         "$A_FORM"   '""'
stub_item "$P/Automation.gscript" "$A_SCRIPT" "$A_PROJECTS" application/vnd.google-apps.script       "$A_SCRIPT" '""'
stub_item "$P/Office Map.gmap"    "$A_MAP"    "$A_PROJECTS" application/vnd.google-apps.map          "$A_MAP"    '""'
stub_item "$P/Whiteboard.gdraw"   "$A_DRAW"   "$A_PROJECTS" application/vnd.google-apps.drawing      "$A_DRAW"   '""'
stub_item "$P/Team Site.gsite"    "$A_SITE"   "$A_PROJECTS" application/vnd.google-apps.site         "$A_SITE"   '""'
stub_item "$P/Contract.docx.gdrive" "$A_GDRIVE" "$A_PROJECTS" application/vnd.openxmlformats-officedocument.wordprocessingml.document "$A_GDRIVE" "\"$A_GDRIVE_KEY\"" 400
file_item "$P/Report.pdf"         "$A_REPORT"  "$A_PROJECTS" "$MIME_PDF"
# A copy made inside Drive that kept the source's id (the DB knows its own id)
raw_file  "$P/Report copy.pdf"    "$A_REPORT"
db_add "$A_REPORTCOPY" "$A_PROJECTS" "Report copy.pdf" "$MIME_PDF" 0
file_item "$P/Legacy Scan.pdf"    "$A_LEGACY"  "$A_PROJECTS" "$MIME_PDF" "$A_LEGACY_KEY"
file_item "$P/Draft notes.txt"    ""           "$A_PROJECTS" text/plain          # not uploaded yet
file_item "$P/helpers.gs"         "$A_GS"      "$A_PROJECTS" application/octet-stream
file_item "$P/route.geojson"      "$A_GEOJSON" "$A_PROJECTS" application/geo+json
printf 'synthetic\n' >"$M/$P/.DS_Store"
printf '' >"$M/$P/$NAME_ICON"

dir_item "$MD/Legacy Archive" "$A_LEGACYDIR" "$A_MYDRIVE"
# the folder's resource key lives only in the DB
printf "UPDATE items SET proto = CAST(CAST(proto AS BLOB) || X'%s' AS TEXT) WHERE id='%s';\n" \
  "$(pb_str 140 "$A_LEGACYDIR_KEY")" "$A_LEGACYDIR" >>"$SQL_LINKS"
file_item "$MD/Legacy Archive/old.txt" "$A_OLDTXT" "$A_LEGACYDIR" text/plain

O="$MD/Odd Names"
dir_item "$O" "$A_ODD" "$A_MYDRIVE"
file_item "$O/$NAME_QUOTES"  "$A_QUOTES"  "$A_ODD" text/plain
file_item "$O/$NAME_UNICODE" "$A_UNICODE" "$A_ODD" "$MIME_PDF" "" "$NAME_UNICODE_NFD"
file_item "$O/$NAME_NEWLINE" "$A_NEWLINE" "$A_ODD" "$MIME_PDF"
file_item "$O/$NAME_DOLLAR"  "$A_DOLLAR"  "$A_ODD" text/plain
file_item "$O/$NAME_DASH"    "$A_DASH"    "$A_ODD" "$MIME_PDF"

# --- shortcuts -------------------------------------------------------------
# (1) symlink to an absolute path in the same mount
ln -s "$M/$P/Plan.gdoc" "$M/$MD/Shortcut to Plan.gdoc"
setid_s "$M/$MD/Shortcut to Plan.gdoc" "$A_SC_PLAN"
db_add "$A_SC_PLAN" "$A_MYDRIVE" "Shortcut to Plan.gdoc" "$MIME_SHORTCUT" 0 "" "$A_PLAN" application/vnd.google-apps.document
ln -s "$M/$P" "$M/$MD/Shortcut to Projects"
setid_s "$M/$MD/Shortcut to Projects" "$A_SC_PROJ"
db_add "$A_SC_PROJ" "$A_MYDRIVE" "Shortcut to Projects" "$MIME_SHORTCUT" 0 "" "$A_PROJECTS" "$MIME_FOLDER"

# (2) symlinks into .shortcut-targets-by-id/<id>/<name>
T="$M/.shortcut-targets-by-id/$A_TOP"
mkdir -p "$T/Shared Thing"                       # <id> dir itself has no id
setid "$T/Shared Thing" "$A_TOP"
printf 'synthetic Inside.pdf\n' >"$T/Shared Thing/Inside.pdf"
setid "$T/Shared Thing/Inside.pdf" "$A_INSIDE"
db_add "$A_TOP" "" "Shared Thing" "$MIME_FOLDER" 1
db_add "$A_INSIDE" "$A_TOP" "Inside.pdf" "$MIME_PDF" 0
ln -s "$T/Shared Thing" "$M/$MD/Shortcut to Shared Thing"
setid_s "$M/$MD/Shortcut to Shared Thing" "$A_SC_THING"
db_add "$A_SC_THING" "$A_MYDRIVE" "Shortcut to Shared Thing" "$MIME_SHORTCUT" 0 "" "$A_TOP" "$MIME_FOLDER"
ln -s "$T/Shared Thing/Inside.pdf" "$M/$MD/Shortcut to Inside.pdf"
setid_s "$M/$MD/Shortcut to Inside.pdf" "$A_SC_INSIDE"
db_add "$A_SC_INSIDE" "$A_MYDRIVE" "Shortcut to Inside.pdf" "$MIME_SHORTCUT" 0 "" "$A_INSIDE" "$MIME_PDF"

# (3) broken shortcut: empty symlink target, only its own id
ln -s '' "$M/$MD/Broken Shortcut"
setid_s "$M/$MD/Broken Shortcut" "$A_SC_BROKEN"
db_add "$A_SC_BROKEN" "$A_MYDRIVE" "Broken Shortcut" "$MIME_SHORTCUT" 0

# (4a) regular .gdoc stand-in: xattr = shortcut id, JSON doc_id = target id
stub_item "$MD/Standin Doc.gdoc" "$A_SC_STANDIN_DOC" "$A_MYDRIVE" application/vnd.google-apps.document "$A_STANDIN_DOC_TARGET" '""'
db_add "$A_STANDIN_DOC_TARGET" "$A_HIDDEN_PARENT" "Standin Doc.gdoc" application/vnd.google-apps.document 0
# (4b) binary stand-ins: only the DB knows the target
raw_file "$MD/Standin Scan.pdf" "$A_SC_STANDIN_PDF"
db_add "$A_SC_STANDIN_PDF" "$A_MYDRIVE" "Standin Scan.pdf" "$MIME_SHORTCUT" 0 "" "$A_STANDIN_PDF_TARGET" "$MIME_PDF"
db_add "$A_STANDIN_PDF_TARGET" "$A_HIDDEN_PARENT" "Standin Scan.pdf" "$MIME_PDF" 0
# ... and one whose (legacy) target has a resource key (proto field 132.7)
raw_file "$MD/Standin Old.pdf" "$A_SC_STANDIN_OLD"
db_add "$A_SC_STANDIN_OLD" "$A_MYDRIVE" "Standin Old.pdf" "$MIME_SHORTCUT" 0 "" "$A_STANDIN_OLD_TARGET" "$MIME_PDF" "$A_STANDIN_OLD_KEY"
db_add "$A_STANDIN_OLD_TARGET" "$A_HIDDEN_PARENT" "Standin Old.pdf" "$MIME_PDF" 0 "$A_STANDIN_OLD_KEY"
# A target known only to stable_ids: its key is available solely in field 132.7.
raw_file "$MD/Standin Remote.pdf" "$A_SC_STANDIN_REMOTE"
db_add "$A_SC_STANDIN_REMOTE" "$A_MYDRIVE" "Standin Remote.pdf" "$MIME_SHORTCUT" 0 "" "$A_STANDIN_REMOTE_TARGET" "$MIME_PDF" "$A_STANDIN_REMOTE_KEY"
SID=$((SID + 1))
printf "INSERT INTO stable_ids (stable_id,cloud_id) VALUES (%s,'%s');\n" "$SID" "$A_STANDIN_REMOTE_TARGET" >>"$SQL_ITEMS"
printf "INSERT INTO shortcut_details SELECT stable_id,%s,'%s' FROM items WHERE id='%s';\n" \
  "$SID" "$MIME_PDF" "$A_SC_STANDIN_REMOTE" >>"$SQL_LINKS"
ln -s "$M/$MD/Standin Doc.gdoc" "$M/$MD/Shortcut to Standin Doc.gdoc"
ln -s "$M/$MD/Standin Old.pdf" "$M/$MD/Shortcut to Standin Old.pdf"
db_add "$A_HIDDEN_PARENT" "" "Invisible parent" "$MIME_FOLDER" 1

# --- Shared drives (virtual container, no id) --------------------------------
mkdir -p "$M/$SHARED"
TA="$SHARED/Team Alpha"
dir_item "$TA" "$A_TEAM" ""
stub_item "$TA/Specs.gdoc" "$A_SPECS" "$A_TEAM" application/vnd.google-apps.document "$A_SPECS" '""'
dir_item "$TA/Assets" "$A_ASSETS" "$A_TEAM"
file_item "$TA/Assets/logo.png" "$A_LOGO" "$A_ASSETS" image/png
# folder shortcut that points back up the tree: following it would loop
ln -s "$M/$TA" "$M/$TA/Assets/Back to Team"
setid_s "$M/$TA/Assets/Back to Team" "$A_SC_TEAM"
db_add "$A_SC_TEAM" "$A_ASSETS" "Back to Team" "$MIME_SHORTCUT" 0 "" "$A_TEAM" "$MIME_FOLDER"
printf "UPDATE items SET team_drive_stable_id=(SELECT stable_id FROM items WHERE id='%s') WHERE id IN ('%s','%s','%s','%s','%s');\n" \
  "$A_TEAM" "$A_TEAM" "$A_SPECS" "$A_ASSETS" "$A_LOGO" "$A_SC_TEAM" >>"$SQL_LINKS"

# --- Other computers (virtual container, no id) -------------------------------
mkdir -p "$M/$COMPUTERS"
dir_item "$COMPUTERS/Studio Mac" "$A_COMPUTER" ""

# --- hidden bookkeeping ---------------------------------------------------------
mkdir -p "$M/.Trash" "$M/.tmp"
file_item ".Trash/Old Deleted.pdf" "$A_TRASHED" "$A_MYDRIVE" "$MIME_PDF"
file_item ".tmp/upload.part" "$A_TMPITEM" "" application/octet-stream
DB_ON=0

# Build alice's DB with the real DriveFS table layout (see DESIGN.md).
DB=$DRIVEFS/$ACCT_A/metadata_sqlite_db
{
  cat <<'SQL'
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS "items" ("stable_id" INTEGER PRIMARY KEY NOT NULL, "id" TEXT UNIQUE NOT NULL, "proto" BLOB, "trashed" BOOLEAN NOT NULL, "starred" BOOLEAN NOT NULL, "is_owner" BOOLEAN NOT NULL, "mime_type" TEXT NOT NULL COLLATE NOCASE, "is_folder" BOOLEAN NOT NULL, "modified_date" INTEGER, "shared_with_me_date" INTEGER, "viewed_by_me_date" INTEGER, "file_size" INTEGER, "is_tombstone" BOOLEAN NOT NULL, "local_title" TEXT, "subscribed" BOOLEAN NOT NULL, "team_drive_stable_id" INTEGER, "inaccessible_inheritance_broken" BOOLEAN NOT NULL);
CREATE TABLE IF NOT EXISTS "stable_ids" ("stable_id" INTEGER PRIMARY KEY NOT NULL, "cloud_id" TEXT);
CREATE INDEX "stable_ids_cloud_id_idx" ON "stable_ids"("cloud_id");
CREATE TABLE IF NOT EXISTS "stable_parents" ("item_stable_id" INTEGER NOT NULL, "parent_stable_id" INTEGER NOT NULL,"local_title_hash" INTEGER NOT NULL, PRIMARY KEY("item_stable_id", "parent_stable_id"));
CREATE TABLE IF NOT EXISTS "shortcut_details" ("shortcut_stable_id" INTEGER PRIMARY KEY NOT NULL, "target_stable_id" INTEGER NOT NULL,  "target_mime_type" TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS "properties" ("property" TEXT PRIMARY KEY NOT NULL, "value" BLOB);
BEGIN;
SQL
  printf "INSERT INTO properties VALUES ('root_id', '%s');\n" "$A_MYDRIVE"
  cat "$SQL_ITEMS" "$SQL_LINKS"
  printf 'COMMIT;\n'
} >"$SQL_DIR/all.sql"
/usr/bin/sqlite3 "$DB" <"$SQL_DIR/all.sql" >/dev/null

# ========================================================== bob@gmail.com ==
new_mount "$EMAIL_B" "$ACCT_B"
dir_item "$MYDRIVE" "$B_MYDRIVE" ""
ln -s "$M/$MYDRIVE" "$DRIVEFS/$ACCT_B/my-drive"
stub_item "$MYDRIVE/Bob Notes.gdoc" "$B_NOTES" "$B_MYDRIVE" application/vnd.google-apps.document "$B_NOTES" '""'
dir_item "$MYDRIVE/Photos" "$B_PHOTOS" "$B_MYDRIVE"
file_item "$MYDRIVE/Photos/beach.jpg" "$B_BEACH" "$B_PHOTOS" image/jpeg
file_item "$MYDRIVE/Old Scan.pdf" "$B_OLDSCAN" "$B_MYDRIVE" "$MIME_PDF"   # 0B id, no DB

# ======================================================== carol@umich.edu ==
new_mount "$EMAIL_C" "$ACCT_C"
dir_item "$MYDRIVE" "$C_MYDRIVE" ""
ln -s "$M/$MYDRIVE" "$DRIVEFS/$ACCT_C/my-drive"
stub_item "$MYDRIVE/Syllabus.gdoc" "$C_SYLLABUS" "$C_MYDRIVE" application/vnd.google-apps.document "$C_SYLLABUS" '""'
mkdir -p "$M/$SHARED"                     # exists but holds no shared drive

# ========================================================= dave@umich.edu ==
new_mount "$EMAIL_D" "$ACCT_D"
dir_item "$MYDRIVE" "$D_MYDRIVE" ""
ln -s "$M/$MYDRIVE" "$DRIVEFS/$ACCT_D/my-drive"
stub_item "$MYDRIVE/Grades.gsheet" "$D_GRADES" "$D_MYDRIVE" application/vnd.google-apps.spreadsheet "$D_GRADES" '""'

# ======================================================= not-Drive places ==
# Another provider's folder next to the Drive mounts, and a Desktop copy: both
# carry a Drive id (cp keeps xattrs) and must NOT be trusted.
mkdir -p "$ROOT/OneDrive-Personal"
printf 'synthetic Stray.pdf\n' >"$ROOT/OneDrive-Personal/Stray.pdf"
setid "$ROOT/OneDrive-Personal/Stray.pdf" "$STRAY_ID"
cp -p "$ROOT/GoogleDrive-$EMAIL_A/$MYDRIVE/Projects/Report.pdf" "$FHOME/Desktop/Report.pdf"
# Finder-style alias path to a mount (as older Drive versions created in ~)
ln -s "$ROOT/GoogleDrive-$EMAIL_A" "$FHOME/$EMAIL_A - Google Drive"

# ================================================================= Chrome ==
# Local State: info_cache is the only source of profile dirs.
#  - Default: nobody signed in, but alice is a SECONDARY web account in it
#    (primary-first lookup must still pick Profile 1)
#  - Profile 1: primary Alice@Example.com (case differs)
#  - Profile 2: primary erin@example.net, secondary Carol@UMich.edu
#  - Profile 3: primary bob@googlemail.com (== bob@gmail.com)
#  - System Profile / Guest Profile claim dave: must be skipped
#  - "Profile 9" exists on disk with dave but is NOT in info_cache: ignored
cat >"$CHROME/Local State" <<'JSON'
{"browser":{"enabled_labs_experiments":[]},
 "profile":{
  "info_cache":{
   "Default":{"name":"Person 1","user_name":"","active_time":1700000000.0},
   "Profile 1":{"name":"Work","user_name":"Alice@Example.com","gaia_id":"100000000000000000001","hosted_domain":"example.com","is_consented_primary_account":false},
   "Profile 2":{"name":"Home","user_name":"erin@example.net","gaia_id":"100000000000000000002","hosted_domain":"NO_HOSTED_DOMAIN"},
   "Profile 3":{"name":"Bob","user_name":"bob@googlemail.com","gaia_id":"100000000000000000003","hosted_domain":"NO_HOSTED_DOMAIN"},
   "System Profile":{"name":"System","user_name":"dave@umich.edu"},
   "Guest Profile":{"name":"Guest","user_name":"dave@umich.edu"}
  },
  "last_used":"Default",
  "profiles_order":["Default","Profile 1","Profile 2","Profile 3"]
 }}
JSON
chrome_prefs() { # DIR EMAIL...
  local d=$1 sep="" e
  shift
  mkdir -p "$CHROME/$d"
  {
    printf '{"account_info":['
    for e in "$@"; do
      printf '%s{"account_id":"x","email":"%s","full_name":"Synthetic","gaia":"1"}' "$sep" "$e"
      sep=","
    done
    printf '],"profile":{"name":"%s"}}\n' "$d"
  } >"$CHROME/$d/Preferences"
}
chrome_prefs "Default" "$EMAIL_A"
chrome_prefs "Profile 1" "Alice@Example.com"
chrome_prefs "Profile 2" "erin@example.net" "Carol@UMich.edu"
chrome_prefs "Profile 3" "bob@googlemail.com"
chrome_prefs "Profile 9" "$EMAIL_D"
chrome_prefs "System Profile" "$EMAIL_D"

printf 'fixture ready: %s\n' "$DIR" >&2
