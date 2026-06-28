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
  url "https://github.com/yohannescodes/recap-wins/archive/refs/tags/v0.3.1.tar.gz"
  sha256 "7d636f4d8be776d1af5ef586a2200ffd7bb349cb949519a219a242e44405cf06"
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
    assert_match "0.3.1", shell_output("#{bin}/rw --version")
    assert_match "recap-wins", shell_output("#{bin}/rw help")
  end
end
