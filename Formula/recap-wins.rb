# Homebrew formula for recap-wins.
#
# This repo doubles as its own tap:
#   brew tap yohannescodes/recap-wins https://github.com/yohannescodes/recap-wins
#   brew install recap-wins
#
# The formula builds from the source tarball of a tagged release. When cutting a
# new version, bump `url` to the new tag and update `sha256` (see scripts/release.sh,
# which prints both). The installed binary is `rw`.
class RecapWins < Formula
  desc "See what your branch introduced — vitals, feature lists, PR & store notes"
  homepage "https://github.com/yohannescodes/recap-wins"
  url "https://github.com/yohannescodes/recap-wins/archive/refs/tags/v0.1.0.tar.gz"
  # The v0.1.0 tag exists, but the source-tarball sha256 can only be computed
  # from the PUBLIC archive URL — fill it once the repo is public (the tap needs
  # a public repo to resolve this URL anyway). Run scripts/release.sh or:
  #   curl -fsSL <url above> | shasum -a 256
  sha256 "PENDING_PUBLIC_RELEASE_see_docs_RELEASING_md"
  license "MIT"
  head "https://github.com/yohannescodes/recap-wins.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on macos: :ventura

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/rw"
  end

  test do
    # The binary reports its version and the offline help renders without a repo.
    assert_match "0.1.0", shell_output("#{bin}/rw --version")
    assert_match "recap-wins", shell_output("#{bin}/rw help")
  end
end
