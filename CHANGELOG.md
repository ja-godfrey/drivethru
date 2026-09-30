# Changelog

All notable changes to drivethru are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-09-29

### Added

- Interactive picker (`drivethru` / `drivethru pick [QUERY]`): one fzf list of
  every file and folder in every Google Drive for desktop account on the Mac,
  streamed as it is found, with an account label column you can filter on.
  - `enter` copies the share link, `ctrl-o` opens it in the browser as the
    right Google account, `ctrl-f` reveals it in Finder, `ctrl-y` copies a
    Markdown link, `tab`/`shift-tab` multi-select (every action applies to all
    selected rows), `ctrl-p` toggles the preview, `esc` cancels.
  - Preview shows the kind (Google Doc, Sheet, Slides, Form, folder, shared
    drive, PDF, ...), the account and modified date without reading file
    contents. It explains that the final link is resolved on copy/open.
  - Picker and search isolate their fzf settings from `FZF_DEFAULT_OPTS` and
    `FZF_DEFAULT_OPTS_FILE` so personal defaults cannot alter their protocol.
- Share links built entirely from metadata Drive for desktop already keeps on
  disk: no OAuth, no API key, no network access.
  - Item ids from the `com.google.drivefs.item-id#S` extended attribute, read
    only for the selected items.
  - Type-specific URLs for Google Docs, Sheets, Slides, Forms, Drawings, Apps
    Script and My Maps; folders and shared-drive roots; ordinary files; and
    `.gdrive` stubs for files whose download is blocked.
  - `doc_id` and `resource_key` from Google-native placeholder files, with
    `resourcekey=` added only when a valid key is known, and a warning for
    legacy `0B...` items without one.
  - Shortcuts link to their target; a broken shortcut falls back to the
    shortcut's own link with a warning.
  - Copied links stay clean (no `authuser`, no `usp`).
  - Works with localized folder names ("Meine Ablage", "Mi unidad", ...):
    My Drive and Shared drives are recognised by structure, not by name.
  - Ids are trusted only for paths inside a detected Drive mount, so copies on
    the Desktop that carry a stale id are rejected.
- Optional, read-only check against Drive for desktop's own metadata database
  to catch copies that inherited another file's id, resolve binary shortcut
  stand-ins, and read resource keys of legacy items. The database is copied
  to a private temporary directory, queried there and deleted on exit; any
  failure falls back to xattr-only behaviour. `db = off` disables it.
- Browser routing for `open` and `ctrl-o`: opens the item in the Google Chrome
  profile (stable, Beta, Dev or Canary) that is signed in to the item's
  account, or in the default browser with `authuser=<email>`. Configurable
  with `browser = auto|chrome|chrome-beta|chrome-dev|chrome-canary|default`,
  plus an `after_open` hook for window managers.
- `drivethru popup [QUERY]`: opens the picker in a new, sized terminal window
  for global hotkeys. Supports Ghostty, kitty, WezTerm, Alacritty, iTerm2 and
  Terminal, returns immediately, and floats the window under AeroSpace.
- Non-interactive commands:
  - `drivethru link [--copy] [--markdown] [--notify] PATH...` prints share
    links for paths, including paths reached through symlinks.
  - `drivethru open PATH...` opens paths in the browser as their account.
  - `drivethru search [--limit N] [--links] [--copy-first] QUERY` for scripts
    and launchers.
  - `drivethru list` prints every indexed item.
  - `list --null` and `search --null` (`-0`) emit NUL-terminated records for
    filenames containing newlines.
  - Global and subcommand `--help`, plus a `help` alias.
  - `drivethru doctor` checks the setup and explains problems (missing fzf,
    File Provider consent, legacy `/Volumes/GoogleDrive` mounts, unknown
    config keys, ...).
- Finder Quick Action, installed with `drivethru install-quick-action`.
- Account labels (local part for Gmail addresses, first domain label
  otherwise, full email on collisions), overridable with `label.<email>`.
- Config file at `~/.config/drivethru/config` (or `$DRIVETHRU_CONFIG`) with
  `key = value` lines; it is parsed, never sourced.
- Documented exit codes: 0 ok (possibly with warnings), 1 usage/configuration
  or other failure (including missing paths and no `--copy-first` match), 2 no Drive mounts,
  3 item has no Drive id yet, 4 no share link for this kind of item,
  5 missing or failing dependency (fzf or the popup terminal), 6 permission
  denied for the requested path or all accounts, 130 cancelled. With at least
  one readable account, listing/searching skips denied accounts with a warning.
- Test hooks for scripted use and CI: `DRIVETHRU_ROOT`,
  `DRIVETHRU_DRIVEFS_DIR`, `DRIVETHRU_CHROME_DIR`, `DRIVETHRU_CONFIG`,
  `DRIVETHRU_DRY_RUN`, `DRIVETHRU_CLIPBOARD_FILE`, `DRIVETHRU_DEBUG`,
  `DRIVETHRU_JQ` and `DRIVETHRU_FZF`.
  Dry-run mode also suppresses the configured `after_open` command.
- Runs on the stock macOS `/bin/bash` 3.2 with stock system tools; fzf 0.42+
  is the only extra dependency, and only for the picker and `search`. macOS 13
  or later.
- Hotkey recipes, Raycast script commands, Homebrew installation through
  `ja-godfrey/tap/drivethru` and CI on macOS 15 and macOS 26.

[Unreleased]: https://github.com/ja-godfrey/drivethru/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ja-godfrey/drivethru/releases/tag/v0.1.0
