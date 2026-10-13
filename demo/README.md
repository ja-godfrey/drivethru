# Recording the demos

The README teaser pairs recreated Drive folder clicks and Chrome profile
switching with the real picker. It shows copying a made-up board deck link,
then searching both accounts, filtering to work, and opening a work budget.
It is an illustration, not a benchmark; clipboard and browser actions are
simulated and their previews reflect captured dry-run output.
The three focused GIFs record the real picker against made-up Drive files and
accounts. Final panels illustrate captured dry-run clipboard contents or
browser routing; they are not recordings of a paste destination or a Chrome
window.

## Regenerate

Requires macOS, Xcode Command Line Tools (for Swift and AppKit), and Homebrew:

```sh
xcode-select --install # if Command Line Tools are not already installed
brew install vhs fzf   # VHS also installs ffmpeg and ttyd
```

From the repository root:

```sh
./demo/render-teaser.sh             # 20-second teaser GIF and sharing MP4
./demo/render.sh                    # regenerate all three focused GIFs
./demo/render.sh copy               # only demo/demo.gif
./demo/render.sh accounts markdown  # only these two scenes
```

The teaser renderer writes a 20-second, 1280×800 `demo/teaser.gif` and
`demo/teaser.mp4`. The MP4 is ignored by Git and is available for sharing.
The focused demo wrapper validates captured actions, adds title and key
captions, and writes the finished GIFs. Both renderers clean up temporary
recordings and synthetic files. VHS renders the terminal in an isolated
headless browser profile.

| Scene | Tape | Finished GIF |
| --- | --- | --- |
| Find a file and copy its link | `demo.tape` | `demo.gif` |
| Narrow by account and open its Chrome profile | `accounts.tape` | `accounts.gif` |
| Select two files and copy Markdown links | `markdown.tape` | `markdown.gif` |

The teaser uses `teaser.tape` and `teaser-session.sh` to record the actual
picker in a narrow terminal and validate the copied board deck link. Its
synthetic file is placed under `Projects/2026/Q3/Board/Final` to match the
folder navigation. `teaser-accounts.tape` and `teaser-accounts-session.sh`
record the cross-account budget search, work filter, and Chrome routing.
`render-folder-scene.swift` and `render-account-scene.swift` draw the two
browser recreations; `compose-teaser.swift` combines the panes with a title
that follows the current action: copy links, search all accounts, filter by
account, and open links. The complete installation command stays visible
with a blinking cursor. Each picker plays at its recorded speed, then holds
its result through the end of its scene.

The clocks show time within each illustrated scene and reset for the second
task. `measure-picker.swift` uses on-device text recognition to find each
recording's first visible result at the output frame rate. The browser
renderers supply their scripted completion times (copy confirmation or the
final file-open click, excluding the subsequent Sheets load). Each clock
stops at that endpoint. After both stop, the speed multiple is calculated as
`native / drivethru`, using the tenths displayed by the clocks and rounding
the multiple to one decimal place. It describes this staged demo, not a
measured real-world speedup; the browser side is drawn and drivethru's
browser/clipboard actions are dry runs.

`common.tape` supplies shared recording settings. `session.sh` creates the
synthetic tree with `make-demo-tree.sh`, enables dry-run mode, and builds the
result panels from captured output. It does not use your Drive files, change
the system clipboard, open Chrome, or call Google's API. Demo presentation
lives in this directory; the `drivethru` runtime is unchanged.

For a raw recording, use `vhs -o /tmp/drivethru-copy.gif demo/demo.tape`.
The tapes require `-o`; use the wrapper for captions and capture validation.
