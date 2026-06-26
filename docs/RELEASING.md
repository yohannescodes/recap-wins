# Releasing recap-wins

recap-wins is distributed as a **Homebrew formula** that builds from a tagged
source tarball. The repo doubles as its own tap, so there's nothing to host — a
git tag plus an updated formula is a release.

## One-time: how users install

```sh
brew tap yohannescodes/recap-wins https://github.com/yohannescodes/recap-wins
brew install recap-wins
```

`brew tap <user>/<repo> <url>` points Homebrew at this repo; it reads
[`Formula/recap-wins.rb`](../Formula/recap-wins.rb). `brew install recap-wins`
then builds and installs the `rw` binary.

## Cutting a release

1. **Bump the version** in `Sources/rw/RW.swift` (the `version:` string) and
   commit it on `main`.

2. **Tag, push, and get the formula values** with the helper:

   ```sh
   scripts/release.sh 0.2.0
   ```

   It verifies the version matches the code and the tree is clean, creates and
   pushes `v0.2.0`, downloads the GitHub source tarball for that tag, and prints
   the `url` + `sha256` lines for the formula.

3. **Update the formula.** Paste the printed `url` and `sha256` into
   `Formula/recap-wins.rb`, and bump the version asserted in its `test` block if
   you changed it. Commit and push on `main`.

4. Users get it with `brew upgrade recap-wins`.

## The repo must be public

A Homebrew tap downloads the source tarball from
`https://github.com/<owner>/<repo>/archive/refs/tags/<tag>.tar.gz`. GitHub serves
that URL **only for public repos** — on a private repo it returns 404 to the
anonymous request `brew` makes, so the tap can't resolve. The `sha256` must also
be computed from that public URL (the authenticated API tarball can differ
byte-for-byte). So: make the repo public first, *then* run `scripts/release.sh`
to get the correct `sha256` and fill the formula.

## Notes

- The formula builds from source (`swift build -c release`), so there are no
  pre-built bottles to manage — it works on any supported macOS/arch.
- `brew install --HEAD recap-wins` installs the latest `main` instead of the
  tagged release, for trying unreleased changes.
- Keep the `0.x.y` version in `RW.swift`, the git tag, and the formula's `test`
  assertion in sync; `scripts/release.sh` checks the first two for you.
