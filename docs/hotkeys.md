# Hotkeys

Bind a global hotkey to **`drivethru popup`**. It opens the picker in a new
terminal window and returns right away, which is what hotkey tools need: they
have no terminal, and several of them kill or wait on commands that keep
running. Don't bind plain `drivethru`. Without a terminal it refuses to start
("drivethru needs a terminal") and you see nothing.

Use the **absolute path**. Hotkey tools start commands with a minimal `PATH`
(usually `/usr/bin:/bin:/usr/sbin:/sbin`) that doesn't include Homebrew.
`command -v drivethru` prints the path. With Homebrew it is
`/opt/homebrew/bin/drivethru` on Apple silicon and `/usr/local/bin/drivethru`
on Intel. The examples below use `/opt/homebrew/bin/drivethru` and ⌃⌥D; change
both to suit, and pick a combination nothing else uses.
`drivethru popup QUERY` opens the picker with QUERY already typed.

## Before you start

- **Terminal.** The popup uses the `terminal` config key (or
  `DRIVETHRU_TERMINAL`). Otherwise it uses the first one installed of
  Ghostty, kitty, WezTerm, Alacritty, iTerm2, Terminal.
- **Google Drive access prompt.** The first time a terminal app reads your
  Drive folders, macOS asks whether it may access files managed by Google
  Drive, once for each signed-in account. Click Allow. The prompt names the
  terminal, not the hotkey tool, because the picker runs in the terminal.
- **Automation prompt (iTerm2 and Terminal only).** These two are driven with
  AppleScript, so the first popup asks whether your hotkey app may control
  them. Allow it, or fix it later in System Settings → Privacy & Security →
  Automation. Ghostty, kitty, WezTerm and Alacritty are started with `open` and
  don't ask.
- **Try the command the way a hotkey tool runs it** before you bind it:

  ```sh
  env -i HOME="$HOME" USER="$USER" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    /opt/homebrew/bin/drivethru popup
  ```

  If that opens the popup, the bindings below will too. `drivethru doctor`
  explains most setup problems.

## Raycast

The repository ships two Script Commands in `extras/raycast/`:

| Script | What it does |
| --- | --- |
| `drivethru-popup.sh` | Opens the popup. Silent mode: nothing is shown on success, and drivethru's error appears as a HUD on failure. Bind your hotkey to this one. |
| `drivethru-copy-link.sh` | Takes a query, runs `drivethru search --copy-first`, and shows the copied link plus any warnings. Needs fzf; no terminal is required. |

1. Copy the scripts into a folder you keep Raycast scripts in (for example
   `~/.config/raycast/scripts`) and make sure they are executable
   (`chmod +x`).
2. Raycast Settings → Extensions → **+** → Add Script Directory, and choose
   that folder.
3. Select the **drivethru** command, click Record Hotkey, and press ⌃⌥D. (From
   root search: select the command, ⌘K → Configure Command.)

Gotchas:

- Raycast runs scripts in a non-login shell and only appends `/usr/local/bin`
  to `PATH`. Both scripts add `/opt/homebrew/bin`, `/usr/local/bin`,
  `/opt/local/bin` and `~/.local/bin` themselves. For an fzf installation
  elsewhere, set `DRIVETHRU_FZF=/absolute/path/to/fzf` in the script.
- **Copy Google Drive Link needs its own Drive permission.** In that script
  Raycast itself reads your Drive folders, so on first use macOS asks whether
  **Raycast** may access files managed by Google Drive (once per account). If
  every account is denied, drivethru exits 6. If some accounts are readable,
  it searches those and includes a warning in the copy-result toast. Check
  the app's Google Drive access in System Settings → Privacy & Security.
  The popup script doesn't need this permission, because the terminal does
  the reading.
- A command with a required argument opens Raycast to ask for it, so bind the
  hotkey to the popup script, which takes no arguments.

_Status: both scripts pass ShellCheck and were run with a stub `drivethru`.
They have not been run inside Raycast, and the settings paths above come from
Raycast's documentation._

## skhd

In `~/.config/skhd/skhdrc` (or `~/.skhdrc`):

```
ctrl + alt - d : /opt/homebrew/bin/drivethru popup
```

Reload with `skhd --reload`.

- skhd runs the command with `$SHELL -c` (`/bin/bash` if `SHELL` is unset)
  and doesn't wait for it.
- `skhd --install-service` copies the `PATH` of the shell you ran it from into
  its LaunchAgent plist, and that `PATH` stays frozen. Use the absolute path
  anyway.
- skhd needs Accessibility access (System Settings → Privacy & Security →
  Accessibility).
- Output goes to `/tmp/skhd_$USER.out.log` and `/tmp/skhd_$USER.err.log`. Look
  there when nothing happens.
- Upstream skhd (now `asmvik/skhd`) is in maintenance mode, and its README
  points to the `skhd.zig` port.

_Status: untested (skhd isn't installed on the test machine). Syntax and
behaviour are taken from the skhd README and source._

## Hammerspoon

In `~/.hammerspoon/init.lua`:

```lua
hs.hotkey.bind({"ctrl", "alt"}, "d", function()
  hs.task.new("/opt/homebrew/bin/drivethru", nil, {"popup"}):start()
end)
```

Reload the config from the Hammerspoon menu.

- `hs.task` needs the full path to the executable and doesn't use a shell,
  so each argument is a separate list item and no quoting is needed. The task
  inherits Hammerspoon's own minimal environment.
- Don't use `hs.execute`. It waits for the command to finish, and its
  `with_user_env` option starts a login shell each time, which is slow.
- Reloading the config terminates tasks that are still running. That doesn't
  matter here, because `drivethru popup` exits almost at once.
- Grant Hammerspoon Accessibility access when it asks.

_Status: untested (Hammerspoon isn't installed on the test machine). Taken
from the `hs.task` and `hs.hotkey` documentation._

## AeroSpace

In `~/.aerospace.toml`:

```toml
[mode.main.binding]
ctrl-alt-d = 'exec-and-forget /opt/homebrew/bin/drivethru popup'
```

- `exec-and-forget` runs the command with `/bin/bash -c` and doesn't wait for
  it.
- AeroSpace prepends `/opt/homebrew/bin:/opt/homebrew/sbin` to `PATH`, unless
  your config overrides the `[exec]` section. The absolute path works either
  way.
- Check that the key isn't already bound in your config.

**The popup floats itself.** A tiling window manager would otherwise tile the
popup window. When `aerospace` is on `PATH` and the focused window belongs to
the popup's terminal, drivethru runs `aerospace layout floating` before it
shows the picker. You don't need to configure anything.

**Optional: float it on arrival.** The self-float happens after the window has
appeared, so the window can briefly tile first. A window rule can float it
earlier. On AeroSpace 0.21 or later:

```toml
on-window-detected = [
    {
        if = 'test %{app-bundle-id} = com.mitchellh.ghostty && test %{window-title} ~= drivethru',
        run = 'layout floating',
    },
    # ...your other callbacks
]
```

On older versions, use the legacy syntax, which 0.21 still accepts:

```toml
[[on-window-detected]]
if.app-id = 'com.mitchellh.ghostty'
if.window-title-regex-substring = 'drivethru'
run = 'layout floating'
```

- For another terminal, change the bundle id: `net.kovidgoyal.kitty`,
  `com.github.wez.wezterm`, `org.alacritty`, `com.googlecode.iterm2`,
  `com.apple.Terminal`.
- Callbacks run in order, and processing stops at the first one whose `if`
  matches. Put this rule **above** any catch-all rule (`if = 'true'`), or give
  the catch-all `check-further-callbacks = true`.
- AeroSpace warns that some windows set their title only after they appear, and
  it's untested whether the popup's `drivethru` title is visible when the rule
  runs. If the rule doesn't fire, the self-float still handles it.

_Status: the binding syntax and the `test` expressions were checked against
AeroSpace 0.21.3 (`aerospace test` parses both conditions). The rule itself
has not been run against a real popup window._

## Karabiner-Elements

Copy `extras/karabiner/drivethru.json` into
`~/.config/karabiner/assets/complex_modifications/`. Then go to
Karabiner-Elements Settings → Complex Modifications → Add predefined rule, and
enable "drivethru: control-option-D opens the Google Drive picker popup".
Edit the file first if your drivethru isn't at `/opt/homebrew/bin/drivethru`.

The rule it contains:

```json
{
  "type": "basic",
  "from": {
    "key_code": "d",
    "modifiers": { "mandatory": ["control", "option"], "optional": ["caps_lock"] }
  },
  "to": [{ "shell_command": "/opt/homebrew/bin/drivethru popup" }]
}
```

- `shell_command` runs with `/bin/sh -c` and a very small environment (`HOME`,
  `USER`, `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, …). Use the absolute path.
- If you press the key again while an earlier `shell_command` is still
  running, Karabiner kills the earlier one. `drivethru popup` hands the window
  off to `open`/LaunchServices and exits, so the popup isn't affected.
- Output goes to Karabiner's log, cut to 256 characters.

_Status: `extras/karabiner/drivethru.json` passes
`karabiner_cli --lint-complex-modifications` (Karabiner-Elements 16.3.0). The
binding has not been pressed with a real drivethru popup._

## BetterTouchTool

1. Keyboard Shortcuts → add a shortcut and record ⌃⌥D.
2. Pick the action **Execute Shell Script / Task**. Set Launch Path to
   `/bin/bash`, Parameters to `-c`, and the script to
   `/opt/homebrew/bin/drivethru popup`. The async **Execute Terminal Command**
   action works too.

- BTT doesn't give scripts the `PATH` from your terminal. Use the absolute
  path, or start the script with `export PATH=/opt/homebrew/bin:$PATH`.
- BTT needs Accessibility access.

_Status: untested (BetterTouchTool isn't installed on the test machine).
Action names come from the BTT docs and forum and may differ between
versions._

## macOS Shortcuts

1. In the Shortcuts app, create a shortcut with one **Run Shell Script**
   action. Set Shell to `bash` and the script to:

   ```sh
   /opt/homebrew/bin/drivethru popup
   ```

2. Shortcuts → Settings → Advanced → turn on **Allow Running Scripts**.
   Without it, Run Shell Script won't run.
3. Open the shortcut's details (ⓘ) → **Add Keyboard Shortcut**, and press
   ⌃⌥D. macOS reserves some combinations.

- The script gets a minimal `PATH`, so use the absolute path.
- `shortcuts run "<name>"` runs the same shortcut from a terminal, which is a
  quick way to test it.
- Reportedly the keyboard shortcut works even when the Shortcuts app isn't
  running (not verified).

_Status: untested end to end. No shortcut was created on the test machine._

## Finder: copy the link of the selected item

`drivethru install-quick-action` installs the **Copy Google Drive Link** Quick
Action into `~/Library/Services`. It shows up when you right-click a file or
folder in Finder (Quick Actions submenu, or Services). It runs:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"; drivethru link --copy --notify -- "$@"
```

To give it a hotkey, go to System Settings → Keyboard → Keyboard Shortcuts… →
Services → Files and Folders → Copy Google Drive Link. The hotkey works while
Finder is frontmost with something selected. If drivethru fails, for example
because the item hasn't uploaded yet, macOS shows the action's error message.

- If drivethru isn't in `/opt/homebrew/bin` or `/usr/local/bin` (for example
  you run it from a clone or `~/.local/bin`), `install-quick-action` rewrites
  the installed copy to call drivethru by its absolute path. If you move
  drivethru later, run `drivethru install-quick-action` again.
- Whether the Quick Action's runner gets its own "access files managed by
  Google Drive" prompt is untested.

_Status: the bundle passes `plutil -lint`. It was run with
`/usr/bin/automator -i <path> "Copy Google Drive Link.workflow"` and a stub
drivethru: the stub received `link --copy --notify -- <path>` with spaces and
`$` in the path intact, and a failing stub surfaced as an error. The Finder
menu entry and the Services hotkey have not been tried, because the bundle
wasn't installed on the test machine._

## At a glance

| Tool | Runs the command with | `PATH` it gives you | Permission for the tool itself |
| --- | --- | --- | --- |
| Raycast | the script file, non-login shell | Raycast's own, plus `/usr/local/bin` | Drive access, for Copy Google Drive Link only |
| skhd | `$SHELL -c`, not waited on | frozen at `--install-service` time | Accessibility |
| Hammerspoon | `hs.task`, no shell | Hammerspoon's own (minimal) | Accessibility |
| AeroSpace | `/bin/bash -c`, not waited on | Homebrew prepended, unless `[exec]` is overridden | Accessibility |
| Karabiner-Elements | `/bin/sh -c`; a second press kills a still-running command | `/usr/bin:/bin:/usr/sbin:/sbin` | Karabiner's usual setup |
| BetterTouchTool | its script action | not your terminal's | Accessibility |
| Shortcuts | Run Shell Script | minimal | Allow Running Scripts |

## Troubleshooting

- **Nothing happens.** Run the `env -i …` command from
  [Before you start](#before-you-start). If it fails there, it fails from the
  hotkey too; `drivethru doctor` tells you why. If it works there, check the
  tool's own log (skhd: `/tmp/skhd_$USER.err.log`; Karabiner: its Log tab).
- **"drivethru needs a terminal".** You bound `drivethru` instead of
  `drivethru popup`.
- **The popup window opens and closes at once.** Errors inside the popup wait
  for a key press, so a window that disappears without a message usually means
  the terminal couldn't start drivethru at all. Check the path.
- **The popup tiles in AeroSpace.** Check that `aerospace` is in
  `/opt/homebrew/bin` or `/usr/local/bin`, or add the window rule above.
- **"… would like to access files managed by Google Drive" keeps
  appearing.** It's asked once per Drive account and per app. Allow each one.
- **Only some accounts appear.** A denied account is skipped with a warning
  while readable accounts remain searchable. Run `drivethru doctor` from the
  same terminal or launcher to identify missing access.
- **The popup waits for a key after copying.** It has a warning for you to
  read, such as a Form editor link, an unavailable shortcut target, a missing
  resource key or a skipped account. The clipboard already has the link.
- **fzf works in your terminal but not from a hotkey.** Set `DRIVETHRU_FZF`
  to its absolute path in the launcher command or script. Both the picker
  and the Raycast copy-link command need it.
