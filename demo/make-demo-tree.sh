#!/bin/bash
# make-demo-tree.sh DIR
#
# Builds a synthetic Google Drive for desktop layout for the demo GIF (see
# demo/demo.tape). Every name, id and email in it is made up. Nothing here
# touches the real ~/Library/CloudStorage or DriveFS data: DIR must be empty or
# new (its parent must exist), and anything under ~/Library is refused.
#
#   DIR/CloudStorage/GoogleDrive-you@company.com/   work account
#   DIR/CloudStorage/GoogleDrive-you@gmail.com/     personal account
#   DIR/Chrome/                                     fake Chrome user-data dir
#   DIR/DriveFS/                                    empty (no DriveFS database)
#   DIR/config                                      drivethru config
#
# Point drivethru at it with:
#   export DRIVETHRU_ROOT="DIR/CloudStorage" DRIVETHRU_CHROME_DIR="DIR/Chrome" \
#          DRIVETHRU_DRIVEFS_DIR="DIR/DriveFS" DRIVETHRU_CONFIG="DIR/config" \
#          DRIVETHRU_CLIPBOARD_FILE="DIR/clipboard" DRIVETHRU_DRY_RUN=1
#
# Ids are derived from a hash of each path, so the tree (and the links shown in
# the GIF) are identical on every run.

set -euo pipefail

XATTR_NAME='com.google.drivefs.item-id#S'
WORK=you@company.com
PERSONAL=you@gmail.com

die() {
  printf 'make-demo-tree: %s\n' "$*" >&2
  exit 1
}

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
  printf 'usage: %s DIR\n' "${0##*/}" >&2
  exit 1
fi

target=$1
while [ "${#target}" -gt 1 ] && [ "${target%/}" != "$target" ]; do
  target=${target%/}
done
if [ -e "$target" ] && [ ! -d "$target" ]; then
  die "$target exists and is not a directory"
fi

# Resolve the absolute path BEFORE creating anything, and refuse ~/Library
# (where the real CloudStorage mounts and DriveFS data live).
if [ -d "$target" ]; then
  root=$(cd -P "$target" && pwd) || die "can't enter $target"
else
  parent=$(/usr/bin/dirname "$target")
  [ -d "$parent" ] || die "parent directory $parent doesn't exist"
  root="$(cd -P "$parent" && pwd)/$(/usr/bin/basename "$target")" ||
    die "can't enter $parent"
fi
home_real=$(cd -P "$HOME" 2>/dev/null && pwd) || home_real=$HOME
case "$root/" in
  "$HOME"/Library/* | "$home_real"/Library/*)
    die "refusing to write under ~/Library: $root"
    ;;
esac
# On case-insensitive APFS, ~/library and /System/Volumes/Data can name the
# same directory with different path strings. Compare existing ancestors by
# filesystem identity before creating the fixture.
if [ -d "$HOME/Library" ]; then
  probe=$root
  while [ ! -d "$probe" ]; do probe=$(/usr/bin/dirname "$probe"); done
  while :; do
    [ ! "$probe" -ef "$HOME/Library" ] || die "refusing to write under ~/Library: $root"
    [ "$probe" != / ] || break
    probe=$(/usr/bin/dirname "$probe")
  done
fi
if [ -d "$root" ] && [ -n "$(/bin/ls -A "$root")" ]; then
  die "$root is not empty"
fi
/bin/mkdir -p "$root"

# id_for SEED PREFIX LENGTH: deterministic Drive-looking id ([A-Za-z0-9_-]).
id_for() {
  local body
  body=$(printf '%s' "$1" | /usr/bin/openssl dgst -sha256 -binary |
    /usr/bin/base64 | /usr/bin/tr '+/' '-_' | /usr/bin/tr -d '=\n')
  printf '%s%s' "$2" "${body:0:$(($3 - ${#2}))}"
}

set_id() {
  /usr/bin/xattr -w "$XATTR_NAME" "$2" "$1"
}

mount_dir() {
  case "$1" in
    work) printf '%s/CloudStorage/GoogleDrive-%s' "$root" "$WORK" ;;
    personal) printf '%s/CloudStorage/GoogleDrive-%s' "$root" "$PERSONAL" ;;
    *) die "unknown account $1" ;;
  esac
}

email_for() {
  case "$1" in
    work) printf '%s' "$WORK" ;;
    *) printf '%s' "$PERSONAL" ;;
  esac
}

# Mount skeletons: the mount root and the Shared drives container have no id;
# My Drive does; hidden bookkeeping folders exist but drivethru prunes them.
for acct in work personal; do
  m=$(mount_dir "$acct")
  /bin/mkdir -p "$m/My Drive" "$m/.shortcut-targets-by-id" "$m/.Trash" "$m/.tmp"
  set_id "$m/My Drive" "$(id_for "$acct:my-drive" 0A 19)"
done
/bin/mkdir -p "$(mount_dir work)/Shared drives"
/bin/mkdir -p "$(mount_dir personal)/Shared drives"

# account | path relative to the mount (trailing / = folder) | mtime (touch -t)
items='
work|My Drive/Board/|202609150900
work|My Drive/Board/Board Deck - Q3 2026.gslides|202609241712
work|My Drive/Board/Board Minutes 2026-07-15.gdoc|202607161030
work|My Drive/Board/Investor Update - August.gdoc|202609020815
work|My Drive/Finance/|202609100900
work|My Drive/Finance/FY2026 Budget.gsheet|202609221405
work|My Drive/Finance/Q3 Forecast.gsheet|202609181120
work|My Drive/Finance/Expense Policy.pdf|202602031000
work|My Drive/Finance/Vendor Contracts/|202605200900
work|My Drive/Finance/Vendor Contracts/Cloud Hosting MSA.pdf|202605201415
work|My Drive/Planning/|202609010900
work|My Drive/Planning/2026 OKRs.gsheet|202609110930
work|My Drive/Planning/Q4 Roadmap.gslides|202609191600
work|My Drive/Planning/Offsite Agenda.gdoc|202608281045
work|My Drive/People/|202608010900
work|My Drive/People/Onboarding/|202608010900
work|My Drive/People/Onboarding/Onboarding Checklist.gdoc|202609081330
work|My Drive/People/Onboarding/Welcome to the Team.gslides|202608141100
work|My Drive/People/Onboarding/Benefits Overview 2026.pdf|202601150900
work|My Drive/People/Onboarding/New Hire Survey.gform|202608141130
work|My Drive/People/Hiring Plan H2.gsheet|202607070900
work|My Drive/People/Interview Rubric - Engineering.gdoc|202606121500
work|My Drive/Marketing/|202607010900
work|My Drive/Marketing/Brand Guidelines.pdf|202604021000
work|My Drive/Marketing/Customer Personas.gslides|202606251345
work|My Drive/Marketing/Logo Final v3.png|202604011700
work|My Drive/Meeting Notes/|202609010900
work|My Drive/Meeting Notes/Weekly Staff Sync.gdoc|202609281000
work|My Drive/Meeting Notes/Customer Advisory Board Notes.gdoc|202609171500
work|Shared drives/Engineering/|202603010900
work|Shared drives/Engineering/Architecture Overview.gdoc|202609120900
work|Shared drives/Engineering/On-call Runbook.gdoc|202609260800
work|Shared drives/Engineering/Incident Postmortems/|202608120900
work|Shared drives/Engineering/Incident Postmortems/2026-08-12 API Outage.gdoc|202608131600
work|Shared drives/Sales/|202603010900
work|Shared drives/Sales/Pricing Calculator.gsheet|202609051015
work|Shared drives/Sales/Sales Deck 2026.gslides|202609231130
personal|My Drive/Home/|202601010900
personal|My Drive/Home/Household Budget 2026.gsheet|202609271930
personal|My Drive/Home/Lease Agreement.pdf|202512011200
personal|My Drive/Home/Home Insurance Policy.pdf|202603150900
personal|My Drive/Receipts/|202601010900
personal|My Drive/Receipts/2026-08-03 Hardware Store.pdf|202608031845
personal|My Drive/Receipts/2026-09-14 Laptop Repair.pdf|202609141210
personal|My Drive/Receipts/2026-09-20 Dentist.pdf|202609201630
personal|My Drive/Photos/|202601010900
personal|My Drive/Photos/Lisbon Trip 2026/|202606200900
personal|My Drive/Photos/Lisbon Trip 2026/IMG_0412.jpg|202606181432
personal|My Drive/Photos/Lisbon Trip 2026/IMG_0413.jpg|202606181433
personal|My Drive/Photos/Lisbon Trip 2026/IMG_0420.HEIC|202606191015
personal|My Drive/Photos/Family Reunion 2026.jpg|202607041900
personal|My Drive/Taxes/|202602010900
personal|My Drive/Taxes/2025 Tax Return.pdf|202604101100
personal|My Drive/Taxes/Deductions Tracker.gsheet|202609010830
personal|My Drive/Travel/|202605010900
personal|My Drive/Travel/Japan Itinerary.gdoc|202609250945
personal|My Drive/Travel/Packing List.gdoc|202609250950
personal|My Drive/Recipes.gdoc|202609061800
personal|My Drive/Resume - 2026.gdoc|202608300900
personal|My Drive/Running Log.gsheet|202609290700
'

# Pass 1: create everything and give it an id.
while IFS='|' read -r acct rel stamp; do
  [ -n "$acct" ] || continue
  m=$(mount_dir "$acct")
  case "$rel" in
    */)
      rel=${rel%/}
      path="$m/$rel"
      /bin/mkdir -p "$path"
      case "$rel" in
        # Depth 2 under Shared drives = a shared-drive root (0A... id).
        "Shared drives/"*/*) set_id "$path" "$(id_for "$acct:$rel" 1 33)" ;;
        "Shared drives/"*) set_id "$path" "$(id_for "$acct:$rel" 0A 19)" ;;
        *) set_id "$path" "$(id_for "$acct:$rel" 1 33)" ;;
      esac
      ;;
    *)
      path="$m/$rel"
      /bin/mkdir -p "${path%/*}"
      case "$rel" in
        *.gdoc | *.gsheet | *.gslides | *.gform | *.gdraw)
          id=$(id_for "$acct:$rel" 1 44)
          printf '{"":"WARNING! DO NOT EDIT THIS FILE! ANY CHANGES MADE WILL BE LOST!","doc_id":"%s","resource_key":"","email":"%s"}' \
            "$id" "$(email_for "$acct")" >"$path"
          ;;
        *.pdf)
          id=$(id_for "$acct:$rel" 1 33)
          printf '%%PDF-1.4\n%% drivethru demo placeholder\n' >"$path"
          ;;
        *)
          id=$(id_for "$acct:$rel" 1 33)
          printf 'drivethru demo placeholder\n' >"$path"
          ;;
      esac
      set_id "$path" "$id"
      ;;
  esac
  printf '%s\t%s\n' "$stamp" "$path" >>"$root/.mtimes"
done <<EOF
$items
EOF

# A Drive shortcut (symlink to the target inside the same mount).
work_mount=$(mount_dir work)
/bin/ln -s "$work_mount/Shared drives/Engineering/Architecture Overview.gdoc" \
  "$work_mount/My Drive/Planning/Architecture Overview.gdoc"

# Pass 2: set modification dates (after all children exist).
while IFS="$(printf '\t')" read -r stamp path; do
  /usr/bin/touch -t "$stamp" "$path"
done <"$root/.mtimes"
/bin/rm -f "$root/.mtimes"
for acct in work personal; do
  m=$(mount_dir "$acct")
  /usr/bin/touch -t 202609010900 "$m/.shortcut-targets-by-id" "$m/.Trash" \
    "$m/.tmp" "$m/My Drive" "$m/Shared drives" "$m"
done
/usr/bin/touch -h -t 202609120905 \
  "$work_mount/My Drive/Planning/Architecture Overview.gdoc"

# Fake Chrome user-data dir: one profile per account.
chrome="$root/Chrome"
/bin/mkdir -p "$chrome/Default" "$chrome/Profile 1"
printf '%s\n' '{"profile":{"last_used":"Default","info_cache":{"Default":{"name":"Work","user_name":"you@company.com","gaia_name":"You"},"Profile 1":{"name":"Personal","user_name":"you@gmail.com","gaia_name":"You"}}}}' \
  >"$chrome/Local State"
printf '%s\n' '{"account_info":[{"email":"you@company.com","full_name":"You"}]}' \
  >"$chrome/Default/Preferences"
printf '%s\n' '{"account_info":[{"email":"you@gmail.com","full_name":"You"}]}' \
  >"$chrome/Profile 1/Preferences"

/bin/mkdir -p "$root/DriveFS"

/bin/cat >"$root/config" <<EOF
# drivethru demo config (synthetic accounts)
label.$WORK = work
label.$PERSONAL = personal
browser = chrome
db = off
notify = false
EOF

printf 'make-demo-tree: built %s\n' "$root" >&2
