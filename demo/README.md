# Recording the demos

The GIFs record the real picker against made-up Drive files and accounts.
Final panels illustrate captured dry-run clipboard contents or browser routing;
they are not recordings of a paste destination or a Chrome window.

## Regenerate

Requires macOS, Xcode Command Line Tools (for Swift and AppKit), and Homebrew:

```sh
xcode-select --install # if Command Line Tools are not already installed
brew install vhs fzf   # VHS also installs ffmpeg and ttyd
```

From the repository root:

```sh
./demo/render.sh                    # regenerate all three GIFs
./demo/render.sh copy               # only demo/demo.gif
./demo/render.sh accounts markdown  # only these two scenes
```

The wrapper validates captured actions, adds title and key captions, and writes
the finished GIFs. Temporary recordings and synthetic files are cleaned up.
VHS renders the terminal in an isolated headless browser profile.

| Scene | Tape | Finished GIF |
| --- | --- | --- |
| Find a file and copy its link | `demo.tape` | `demo.gif` |
| Narrow by account and open its Chrome profile | `accounts.tape` | `accounts.gif` |
| Select two files and copy Markdown links | `markdown.tape` | `markdown.gif` |

`common.tape` supplies shared recording settings. `session.sh` creates the
synthetic tree with `make-demo-tree.sh`, enables dry-run mode, and builds the
result panels from captured output. It does not use your Drive files, change
the system clipboard, open Chrome, or call Google's API. Demo presentation
lives in this directory; the `drivethru` runtime is unchanged.

For a raw recording, use `vhs -o /tmp/drivethru-copy.gif demo/demo.tape`.
The tapes require `-o`; use the wrapper for captions and capture validation.
