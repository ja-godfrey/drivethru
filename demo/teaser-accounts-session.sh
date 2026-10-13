#!/bin/bash
# Sourced only by teaser-accounts.tape; reuse the isolated accounts fixture.
# shellcheck source=demo/session.sh
source "$(dirname "${BASH_SOURCE[0]}")/session.sh" accounts || return 1

# Keep both account labels visible at 640px: shorten only this synthetic path,
# preserving its filename and Drive metadata while avoiding horizontal scroll.
mv "$DRIVETHRU_ROOT/GoogleDrive-you@gmail.com/My Drive/Home/Household Budget 2026.gsheet" \
  "$DRIVETHRU_ROOT/GoogleDrive-you@gmail.com/My Drive/Household Budget 2026.gsheet" || return 1

# This compact browser preview illustrates the real dry-run routing decision.
# Browser launches remain simulated by the shared session's dry-run setting.
demo_result() {
  local route profile email profile_name
  [ "$(grep -c '^drivethru: dry-run: open ' "$demo_tmp/actions")" = 1 ] || return 1
  route=$(sed -n '/^drivethru: dry-run: open /p' "$demo_tmp/actions")
  case "$route" in *--profile-directory=*--profile-email=*) ;; *) return 1 ;; esac
  profile=${route#*--profile-directory=}; profile=${profile%% --*}
  email=${route#*--profile-email=}; email=${email%% *}
  profile_name=$(/usr/bin/plutil -extract "profile.info_cache.$profile.name" raw -o - \
    "$DRIVETHRU_CHROME_DIR/Local State") || return 1
  [ "$email" = 'you@company.com' ] && [ "$profile_name" = Work ] || return 1
  demo_title 'OPEN WITH WORK ACCOUNT'
  printf '  Browser preview\n\n'
  printf '  \033[1;36m%s\033[0m\n\n' "$email"
  printf '  \033[1;32mChrome profile: %s\033[0m\n\n' "$profile_name"
}

printf 'TEASER ACCOUNTS READY\n'
