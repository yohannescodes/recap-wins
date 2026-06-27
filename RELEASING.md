# Releasing recap-wins

How a new version goes out — what the script does for you, what you do yourself,
and why the order matters.

A release is **two PRs**, not one:

1. Bump the version, sync docs, tag the release.
2. Update the Homebrew formula with the new tag's SHA.

They're split because the formula references a tarball SHA that doesn't exist
until the tag is pushed. Bundling them would mean committing a placeholder
SHA — the kind of thing that bites a week later.

## PR 1 — Code + version bump

1. Land your feature PRs into `main` as usual.
2. From `main`, open a release-prep branch:
   ```sh
   git checkout main && git pull
   git checkout -b release/v<version>
   ```
3. Bump `version: "<version>"` in
   [`Sources/rw/RW.swift`](Sources/rw/RW.swift) (search for the existing
   `version:` line — there's only one).
4. Update [`GUIDE.md`](GUIDE.md) §1 — the `rw --version` example shows the new
   version.
5. Make sure README and GUIDE reflect any new features in the release. Docs and
   code ship together, not as a follow-up.
6. `swift test` must pass. CI runs this; you should too.
7. Commit, push, open the PR, merge.

## Cut the tag

After PR 1 is merged into `main`:

```sh
git checkout main && git pull
scripts/release.sh <version>     # e.g. scripts/release.sh 0.2.0
```

The script:

- Verifies the version matches `RW.swift` (catches a forgotten bump).
- Refuses to run if the tree is dirty or the tag already exists.
- Tags `v<version>` and pushes the tag to `origin`.
- Downloads the GitHub source tarball for the tag and computes its SHA256.
- Prints the `url` + `sha256` lines to paste into the formula.

**Copy those two lines** — you need them for PR 2.

## PR 2 — Homebrew formula

1. From `main` (now with the tag), open a second branch:
   ```sh
   git checkout -b release/v<version>-formula
   ```
2. Edit [`Formula/recap-wins.rb`](Formula/recap-wins.rb):
   - `url` → the new `…/v<version>.tar.gz`
   - `sha256` → the value the script printed
   - The `test do` block asserts a version string — update it to match.
3. Commit, push, open the PR, merge.

## Verify

After PR 2 lands, on a fresh shell:

```sh
brew update
brew upgrade recap-wins
rw --version                       # → the new version
rw --html                          # eyeball a new feature, if applicable
```

If `brew upgrade` doesn't see the new version, the tap cache may be stale —
`brew untap yohannescodes/recap-wins && brew tap yohannescodes/recap-wins https://github.com/yohannescodes/recap-wins`
forces a refetch.

## Version-bump rule of thumb

Semver, loosely:

- **Patch** (`0.x.Y`) — fixes, doc-only changes, internal refactors.
- **Minor** (`0.X.0`) — new commands, new flags, new providers. The norm so
  far.
- **Major** (`X.0.0`) — would only land after a `1.0.0` stability promise,
  which the project hasn't made yet.

## If something goes wrong

**Tag pushed, formula not updated yet.** Safe. The tap still points at the
previous tag; users see no change until PR 2 lands. Take your time.

**Wrong SHA in the formula.** Brew will fail at install. Open a fix-forward PR
with the correct SHA from the tarball (`curl -fsSL <url> | shasum -a 256`).

**Need to retract a tag.** Don't. Cut the next patch instead — deleting a
published tag invalidates any download that already happened.

## SSH note

`scripts/release.sh` does `git push origin "$tag"`, which uses your configured
remote URL. If `origin` is set to SSH and your key isn't authenticating, the
push will fail at the tag step (the script will still have created the local
tag). Either fix the SSH key, or push the tag manually over HTTPS:

```sh
git push https://github.com/yohannescodes/recap-wins.git v<version>
```

Then re-run `scripts/release.sh <version>` skipping the tag step (or just
finish the script's remaining steps manually: download tarball, hash it, paste
the values).
