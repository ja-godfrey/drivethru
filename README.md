# drivethru

Find a file in any of your Google Drive accounts. Press Enter to copy its web
link, or Ctrl-O to open it in the right Google Chrome profile.

drivethru searches the Google Drive for desktop folders already on your Mac.
It builds links from local metadata: no Google API, OAuth setup, or API key.

![Search for a presentation, copy its link, then select budgets from two accounts](demo/demo.gif)

*Recorded with made-up files and accounts. Browser and clipboard actions are
simulated; the picker is real.*

## Install

Requires macOS 13 or later and Google Drive for desktop using
`~/Library/CloudStorage/GoogleDrive-<email>`. The picker and `search` also need
fzf 0.42 or later; the other commands use macOS system tools.

Install from the Homebrew tap:

```sh
brew install ja-godfrey/tap/drivethru
drivethru doctor
drivethru
```

Or install from source:

```sh
git clone https://github.com/ja-godfrey/drivethru.git
cd drivethru
brew install fzf
install -d "$HOME/.local/bin" "$HOME/.local/share/drivethru"
install -m 755 drivethru "$HOME/.local/bin/drivethru"
cp -R "share/drivethru/Copy Google Drive Link.workflow" "$HOME/.local/share/drivethru/"
```

Add `~/.local/bin` to your shell's `PATH`, or run
`"$HOME/.local/bin/drivethru"` directly. You can also try `./drivethru` from
the source checkout before installing it.

## Use

```sh
drivethru                         # search all mounted accounts
drivethru pick 'board deck'        # start with a query
drivethru popup                    # picker in a new terminal window
drivethru link --copy -- '/path/to/Plan.gdoc'
drivethru open -- '/path/to/Plan.gdoc'
drivethru search --limit 5 'budget'
drivethru search --copy-first 'board deck'
drivethru doctor
```

Type an account label as part of the query to narrow the results. Labels
default to the Gmail username or the first part of a work/school domain;
collisions use full email addresses.

| Picker key | Action |
| --- | --- |
| Enter | Copy the selected link(s) |
| Ctrl-O | Open in the browser as each item's Google account |
| Ctrl-F | Reveal in Finder |
| Ctrl-Y | Copy Markdown links |
| Tab / Shift-Tab | Select several items |
| Ctrl-P | Toggle the preview |
| Esc | Cancel |

The preview shows the item type, account and modification time. The final
link is resolved when you copy or open, so moving through the list does not
read placeholder contents or query Drive's database.

`link --markdown` prints Markdown links; `link --notify` shows a macOS
notification. `list` prints account labels and relative paths separated by
tabs. `search` uses that format, and `--links` adds a URL column. Results go
to stdout; warnings go to stderr. Use `list --null` or `search --null QUERY`
(`-0` also works) for NUL-terminated records when filenames contain newlines.
Tabs inside filenames remain literal; split only the known metadata columns.
`search` returns success with no output if nothing matches;
`search --copy-first` returns exit 1 instead.
The `--copy-first` result is a link followed by a newline, even with `--null`.
Use `drivethru --help` or a subcommand's `--help` for command syntax. The
picker and search ignore ambient `FZF_DEFAULT_OPTS` settings so their output
and key bindings remain consistent.

Bind a global shortcut to **`drivethru popup`** using the executable's
absolute path. It supports Ghostty, kitty, WezTerm, Alacritty, iTerm2 and
Terminal. See [hotkey recipes](docs/hotkeys.md) for Raycast, AeroSpace, skhd,
Hammerspoon, Karabiner-Elements, BetterTouchTool and macOS Shortcuts.

For Finder's **Copy Google Drive Link** Quick Action:

```sh
drivethru install-quick-action
```

It installs into `~/Library/Services`. If you later move the script, run the
installer again to update the action's executable path.

## Accounts and configuration

With `browser = auto`, opening a link uses the installed Chrome profile
matching its Google account, including Chrome Beta, Dev and Canary. If no
matching profile is found, the default browser receives the account email
as `authuser`. Copied links omit that parameter. A browser can still ask you
to sign in or request access.

Optional config: `~/.config/drivethru/config`, or the file named by
`DRIVETHRU_CONFIG`. Create the directory first with
`mkdir -p ~/.config/drivethru`.

```ini
label.you@company.com = work
label.you@gmail.com = personal
browser = auto
terminal = ghostty
popup_size = 130x26
db = auto
notify = false
# after_open = /absolute/path/to/your-window-focus-script
```

`browser` accepts `auto`, `default`, `chrome`, `chrome-beta`, `chrome-dev` or
`chrome-canary`. Omit `terminal` to choose an installed terminal automatically.
`db = off` disables the optional Drive database check. Config is parsed as
text; only an explicitly configured `after_open` command is executed, with
`DRIVETHRU_EMAIL`, `DRIVETHRU_URL` and `DRIVETHRU_PROFILE_DIR` in its environment.

Hotkey tools have a small `PATH`. If fzf is installed somewhere unusual, set
`DRIVETHRU_FZF` to its absolute executable path in your launcher. Likewise,
`DRIVETHRU_TERMINAL` overrides the configured popup terminal.

## Permissions and limits

Allow the terminal or launcher to access files managed by Google Drive when
macOS asks, once per account and app. With several accounts, a denied account
is skipped with a warning while readable accounts remain usable. Exit 6
means the requested path is denied or no account is readable. The Raycast
copy command needs its own Drive permission; the popup's terminal needs the
permission for the interactive picker. iTerm2 and Terminal popups also need
Automation permission for the calling app.
Popups stay open for you to read warnings; press a key to close them.

Listing reads directory entries, and selected items use Drive's extended
attributes and small Google-native placeholder files. An optional check
queries a private temporary copy of Drive's local database to resolve
shortcut targets, resource keys and copied files with stale IDs. That copy
is deleted on exit. drivethru does not change Drive permissions, upload files,
or make a private file accessible to someone who receives its link.

- Only files exposed in the local Drive mounts can be found. Legacy
  `/Volumes/GoogleDrive*` mounts are unsupported.
- Newly created files may have no link until they upload. My Drive itself
  and virtual containers have no share link.
- Google Forms links open the **form editor**. Use Send in Google Forms for
  a respondent link.
- Broken shortcuts can yield the shortcut's own link with a warning. Some
  older items need a resource key that local metadata may not provide.
- Drive's database format is undocumented. If it cannot be read, drivethru
  falls back to available file metadata. Copies that retain an old ID may
  still link to their source until Drive provides authoritative metadata;
  `DRIVETHRU_DEBUG=1` explains resolution decisions. Run `drivethru doctor` to check your setup.

| Exit | Meaning |
| --- | --- |
| 0 | Success; inspect stderr for warnings or skipped accounts |
| 1 | Usage/configuration or other failure, including missing paths or no `--copy-first` match |
| 2 | No Drive mounts found |
| 3 | No usable Drive ID, or path outside a Drive mount |
| 4 | Item has no share link |
| 5 | Missing or failing dependency, including fzf or the popup terminal |
| 6 | Permission denied for the requested path, or no readable account |
| 130 | Picker cancelled or no item selected |

## Development

Runs on the stock `/bin/bash` 3.2. From a checkout on macOS:

```sh
brew install fzf shellcheck
shellcheck -s bash drivethru tests/*.sh extras/raycast/*.sh demo/*.sh
/bin/bash tests/run.sh
```

Tests use synthetic Drive folders and simulate clipboard, browser and popup
actions. Dry-run mode also skips the configured `after_open` hook.
See the [design and implementation notes](docs/DESIGN.md),
[changelog](CHANGELOG.md) and [release guide](packaging/README.md).
The demo can be regenerated with `vhs demo/demo.tape` after installing VHS;
it also uses only synthetic files.

MIT licensed. See [LICENSE](LICENSE).
