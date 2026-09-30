# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329
# Regression cases recovered from the interrupted release review. Sourced by
# run.sh so every invocation uses its isolated HOME and dry-run action hooks.

review_core_env() {
  R_ROOT=$T/review-core/CloudStorage
  R_DRIVEFS=$T/review-core/DriveFS
  R_CHROME=$T/review-core/Chrome
}

g_review_core() {
  local p db sid row found c variant odd_parent plain_parent osc_name
  if ! "$HERE/make-fixture.sh" "$T/review-core" 2>"$T/review-core.log"; then
    begin 'review: isolated fixture builds'
    bad 'could not create review fixture'
    end
    return
  fi
  p="$T/review-core/CloudStorage/GoogleDrive-$EMAIL_A/$MYDRIVE/Projects/Plan.gdoc"
  db=$T/review-core/DriveFS/$ACCT_A/metadata_sqlite_db
  chmod u+w "$p"
  printf '{"doc_id":"%s","resource_key":""}' "$A_REPORT" >"$p"
  /usr/bin/xattr -d 'com.google.drivefs.item-id#S' "$p"

  begin 'review: uploaded copied stub without xattr uses its own DB id'
  review_core_env
  run_dt link "$p"
  want_rc 0
  want_out "$(doc_url "$A_PLAN")"
  end

  begin 'review: a symlink to a target without xattr still resolves via DB'
  review_core_env
  run_dt link "$R_ROOT/GoogleDrive-$EMAIL_A/$MYDRIVE/Shortcut to Plan.gdoc"
  want_rc 0
  want_out "$(doc_url "$A_PLAN")"
  end

  begin 'review: trailing-newline folder names never resolve to a sibling'
  review_core_env
  plain_parent="$R_ROOT/GoogleDrive-$EMAIL_A/$MYDRIVE/Trailing"
  odd_parent="$plain_parent"$'\n'
  mkdir -p "$plain_parent" "$odd_parent"
  printf synthetic >"$plain_parent/Item.pdf"
  printf synthetic >"$odd_parent/Item.pdf"
  /usr/bin/xattr -w 'com.google.drivefs.item-id#S' "$A_REPORT" "$plain_parent/Item.pdf"
  /usr/bin/xattr -w 'com.google.drivefs.item-id#S' "$A_REPORTCOPY" "$odd_parent/Item.pdf"
  cfg 'db = off'
  run_dt link "$odd_parent/Item.pdf"
  want_rc 0
  want_out "$(file_url "$A_REPORTCOPY")"
  end

  begin 'review: relative dash folder names do not become OLDPWD'
  review_core_env
  RUN_CWD="$R_ROOT/GoogleDrive-$EMAIL_A/$MYDRIVE"
  mkdir -p "$RUN_CWD/-"
  printf synthetic >"$RUN_CWD/-/Item.pdf"
  /usr/bin/xattr -w 'com.google.drivefs.item-id#S' "$A_REPORT" "$RUN_CWD/-/Item.pdf"
  cfg 'db = off'
  run_dt link -- '-/Item.pdf'
  want_rc 0
  want_out "$(file_url "$A_REPORT")"
  end

  begin 'review: Markdown copy and diagnostics strip terminal control sequences'
  review_core_env
  osc_name=$'Report\033]52;c;YXR0YWNr\007.pdf'
  p="$R_ROOT/GoogleDrive-$EMAIL_A/$MYDRIVE/$osc_name"
  printf synthetic >"$p"
  /usr/bin/xattr -w 'com.google.drivefs.item-id#S' "$A_REPORT" "$p"
  cfg 'db = off'
  run_dt link --markdown --copy --notify "$p"
  want_rc 0
  /usr/bin/perl -0777 -ne 'exit 1 if /[\x1b\x07]/' "$T/stdout" "$T/stderr" "$CLIP" || bad 'terminal controls escaped into user output'
  end

  begin 'review: copied stub with inherited xattr uses its own DB id'
  review_core_env
  p="$R_ROOT/GoogleDrive-$EMAIL_A/$MYDRIVE/Projects/Plan.gdoc"
  /usr/bin/xattr -w 'com.google.drivefs.item-id#S' "$A_REPORT" "$p"
  run_dt link "$p"
  want_rc 0
  want_out "$(doc_url "$A_PLAN")"
  end

  begin 'review: NFD database title corrects an inherited NFC file id'
  review_core_env
  p="$R_ROOT/GoogleDrive-$EMAIL_A/$MYDRIVE/Odd Names/$NAME_UNICODE"
  /usr/bin/xattr -w 'com.google.drivefs.item-id#S' "$A_REPORT" "$p"
  run_dt link "$p"
  want_rc 0
  want_out "$(file_url "$A_UNICODE")"
  end

  begin 'review: preview does not advertise the wrong link for copied items'
  run_dt __preview "example${TAB}$MYDRIVE/Projects/Report copy.pdf"
  want_rc 0
  want_out_has 'Link resolved when copied or opened'
  case $OUT in *"$A_REPORT"*|*https://*) bad 'preview claimed an unverified URL' ;; esac
  end

  begin 'review: preview does not call an uploaded item with no xattr pending'
  review_core_env
  /usr/bin/xattr -d 'com.google.drivefs.item-id#S' "$R_ROOT/GoogleDrive-$EMAIL_A/$MYDRIVE/Projects/route.geojson"
  run_dt __preview "example${TAB}$MYDRIVE/Projects/route.geojson"
  want_out_has 'Link resolved when copied or opened'
  case $OUT in *'not uploaded'*) bad 'preview falsely reported not uploaded' ;; esac
  end

  begin 'review: computer backup root is labelled separately from shared drives'
  run_dt __preview "example${TAB}$COMPUTERS/Studio Mac"
  want_out_has 'Computer backup folder'
  end

  begin 'review: Finder metadata at mount root is identified as a file'
  run_dt link "$MA/.DS_Store"
  want_rc 3
  want_err_has 'local Finder file'
  end

  begin 'review: Form editor warning survives copy notification'
  run_dt link --copy --notify "$PA/Signup Survey.gform"
  want_rc 0
  printf '%s\n' "$ERR" | grep 'dry-run: notify' | grep -q 'editor link' || bad 'notification omitted editor warning'
  end

  if [ -n "$FZF" ]; then
    begin 'review: personal fzf options cannot corrupt search or run commands'
    XENV=("FZF_DEFAULT_OPTS=--print-query --no-sort --bind=start:execute(touch $WORK/pwned-fzf)")
    run_dt search --copy-first 'Plan.gdoc'
    want_rc 0
    want_out "$(doc_url "$A_PLAN")"
    want_absent "$WORK/pwned-fzf"
    end

    begin 'review: fzf options file cannot corrupt search records'
    printf '%s\n' '--print-query --no-sort' >"$T/fzf-options"
    XENV=("FZF_DEFAULT_OPTS_FILE=$T/fzf-options")
    run_dt search --limit 1 'Plan.gdoc'
    want_rc 0
    want_out "example${TAB}$MYDRIVE/Projects/Plan.gdoc"
    end

    begin 'review: search --null --links preserves embedded filename newlines'
    run_dt search --null --links 'Line Break.pdf'
    want_rc 0
    c=0
    while IFS= read -r -d '' row; do
      c=$((c + 1))
      [ "$row" = "example${TAB}$MYDRIVE/Odd Names/$NAME_NEWLINE${TAB}$(file_url "$A_NEWLINE")" ] || bad 'NUL search row did not preserve the filename and URL'
    done <"$T/stdout"
    [ "$c" = 1 ] || bad "expected one NUL row, got $c"
    end
  fi

  begin 'review: list --null preserves embedded filename newlines'
  run_dt list --null
  want_rc 0
  found=0
  while IFS= read -r -d '' row; do
    [ "$row" = "example${TAB}$MYDRIVE/Odd Names/$NAME_NEWLINE" ] && found=1
  done <"$T/stdout"
  [ "$found" = 1 ] || bad 'missing complete newline filename in NUL records'
  end

  for c in help 'link --help' 'popup --help' 'search --help'; do
    begin "review: $c prints help without running an action"
    # Intentional splitting of our fixed command strings.
    # shellcheck disable=SC2086
    run_dt $c
    want_rc 0
    want_out_has 'Usage:'
    [ -z "$ERR" ] || bad 'help produced action output'
    end
  done

  variant=${ROOT%/*}/cloudstorage
  if [ -d "$variant" ] && [ "$variant" -ef "$ROOT" ]; then
    begin 'review: case-variant Drive root still resolves symlink shortcuts'
    R_ROOT=$variant
    run_dt link "$variant/GoogleDrive-$EMAIL_A/$MYDRIVE/Shortcut to Plan.gdoc"
    want_rc 0
    want_out "$(doc_url "$A_PLAN")"
    end
  fi

  # A DB update must reject the whole optional DB if a queried column changes.
  for c in 'shortcut_details target_mime_type' 'stable_parents parent_stable_id'; do
    begin "review: schema guard rejects changed $c"
    review_core_env
    sid=${c#* }
    cp "$db" "$T/schema-backup"
    /usr/bin/sqlite3 "$db" "ALTER TABLE ${c%% *} RENAME COLUMN $sid TO changed_column;"
    XENV=(DRIVETHRU_DEBUG=1)
    run_dt link "$R_ROOT/GoogleDrive-$EMAIL_A/$MYDRIVE/Projects/Legacy Scan.pdf"
    want_rc 0
    want_err_has 'unexpected schema'
    want_err_has 'ignoring the database'
    want_out "$(file_url "$A_LEGACY")"
    mv "$T/schema-backup" "$db"
    end
  done
}
