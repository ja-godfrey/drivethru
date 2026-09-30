# Packaging and releases

drivethru ships through a personal Homebrew tap,
[`ja-godfrey/homebrew-tap`](https://github.com/ja-godfrey/homebrew-tap). Users
install it with the fully qualified name:

    brew install ja-godfrey/tap/drivethru

Since Homebrew 6.0, formulae from non-official taps must be trusted.
Installing by the fully qualified name trusts that one formula, so the one-liner
above works on a clean Mac. `brew tap ja-godfrey/tap && brew install drivethru`
does not, unless the user also runs `brew trust --formula ja-godfrey/tap/drivethru`.
Document only the one-liner.

`drivethru.rb` in this directory is the formula **template**. The copy that
Homebrew reads lives at `Formula/drivethru.rb` in the tap repo. The template
keeps `sha256 "REPLACE_WITH_SHA256"`; the tap copy gets the real checksum.

## What the formula does

- Requires macOS Ventura (13) or later and `fzf`.
- Installs `drivethru` into `bin` and the contents of `share/drivethru/`
  (the Finder Quick Action bundle) into `pkgshare`, which is
  `$(brew --prefix)/share/drivethru`.
- Its `test do` block builds a fake `GoogleDrive-test@example.com` mount
  under `testpath` (Homebrew sets `HOME` to `testpath` during `brew test`),
  writes `com.google.drivefs.item-id#S` xattrs, and checks that
  `drivethru link` prints the right Doc and folder URLs, exits 3 for a file
  without an id, and (for stable builds) that `--version` prints the formula
  version.

## Release checklist

Replace `0.1.0` with the version you are releasing.

### 1. Prepare the release commit

1. Set the version string in `drivethru` (`drivethru --version` must print
   it; the formula test checks this).
2. In `CHANGELOG.md`, rename `## [Unreleased]` to `## [0.1.0] - YYYY-MM-DD`,
   add a fresh empty `## [Unreleased]` above it, and update the link
   references at the bottom:

       [Unreleased]: https://github.com/ja-godfrey/drivethru/compare/v0.1.0...HEAD
       [0.1.0]: https://github.com/ja-godfrey/drivethru/releases/tag/v0.1.0

3. Commit, push, and wait for CI (lint + tests on macOS 15 and macOS 26) to
   pass on `main`.

### 2. Tag and publish the GitHub release

    git tag -a v0.1.0 -m "drivethru 0.1.0"
    git push origin v0.1.0
    gh release create v0.1.0 --verify-tag --title "drivethru 0.1.0" \
      --notes "See CHANGELOG.md for details."

Publish a normal release. `brew audit --online` flags a tag whose release is
a draft or a pre-release.

### 3. Compute the tarball's sha256

The formula uses GitHub's source archive for the tag:

    url=https://github.com/ja-godfrey/drivethru/archive/refs/tags/v0.1.0.tar.gz
    curl -fsSL "$url" | shasum -a 256

Sanity-check the archive while you're at it; it must contain the script and
the Quick Action:

    curl -fsSL "$url" | tar -tzf - | grep -E '/drivethru$|/share/drivethru/'

If an archive checksum ever changes, investigate the contents before updating
the formula; an uploaded release asset is an alternative distribution source.

### 4. Update the tap formula

First release only: create the tap repo (public, named `homebrew-tap`) with a
`Formula/` directory.

    gh repo create ja-godfrey/homebrew-tap --public \
      --description "Homebrew tap for drivethru"

(`brew tap-new ja-godfrey/tap` also works and scaffolds CI. It is a developer
command, see the note below. Its generated `tests.yml` includes an
`ubuntu-latest` job; delete it, because the formula is `depends_on :macos`.)

Then, for every release, edit the formula inside Homebrew's own clone of the
tap, which is where `brew audit`, `brew install` and `brew test` read it from:

    brew tap ja-godfrey/tap
    cd "$(brew --repository ja-godfrey/tap)"
    mkdir -p Formula
    cp /path/to/drivethru/packaging/drivethru.rb Formula/drivethru.rb
    # edit Formula/drivethru.rb: set the url tag and replace
    # REPLACE_WITH_SHA256 with the checksum from step 3

### 5. Audit, install and test

Run these by formula name. `brew audit path/to/file.rb` is disabled, and
`brew install ./drivethru.rb` is refused unless the file is in a tap.

    brew audit --new ja-godfrey/tap/drivethru
    brew style ja-godfrey/tap/drivethru
    brew install --build-from-source ja-godfrey/tap/drivethru
    brew test ja-godfrey/tap/drivethru

`--new` implies `--strict` and `--online`. The homebrew-core notability and
repository-age checks do not apply to a personal tap.

Then try it for real:

    drivethru doctor
    drivethru install-quick-action

**Developer mode note.** `audit`, `style`, `test`, `tap-new` and the other
developer commands switch Homebrew into developer mode (even with `--help`),
after which `brew update` follows `main` instead of stable tags. Turn it off
when you're done:

    brew developer off

### 6. Publish the formula

    cd "$(brew --repository ja-godfrey/tap)"
    git add Formula/drivethru.rb
    git commit -m "drivethru 0.1.0"
    git push

Check the published version from a user's point of view:

    brew update
    brew info ja-godfrey/tap/drivethru
    brew upgrade ja-godfrey/tap/drivethru   # or: brew install ja-godfrey/tap/drivethru

### 7. After the release

- Bump the `url` tag in `packaging/drivethru.rb` here to the released version
  (leave the `REPLACE_WITH_SHA256` placeholder), so the template matches the
  tap.
- Add a fresh `## [Unreleased]` section to `CHANGELOG.md` if you haven't
  already.

## Testing an unreleased build

To try the formula against `main` before tagging, use the `head` spec:

    brew install --HEAD ja-godfrey/tap/drivethru
    brew test ja-godfrey/tap/drivethru

The test's `--version` check runs only for stable builds (a HEAD build's
formula version is `HEAD-<commit>`, which the script can't know); the link
checks run either way.

## Automating bumps later

Once releases are routine, either
[`mislav/bump-homebrew-formula-action`](https://github.com/mislav/bump-homebrew-formula-action)
(set `homebrew-tap: ja-godfrey/homebrew-tap`, since it defaults to
homebrew-core, and give it a token with `repo` and `workflow` scopes) or the
`autobump.yml` workflow that `brew tap-new` generates can open the tap PR for
each new tag.

## homebrew-core

Not yet. homebrew-core requires a repository at least 30 days old and, for a
self-submission, 225 stars (or 90 forks or 90 watchers), and maintainers may
object to a formula that only works with proprietary software (Google Drive
for desktop). Revisit once the project has real users.
