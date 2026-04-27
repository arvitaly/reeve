cask "reeve" do
  version "0.1.1"
  # Run `make release VERSION=#{version}` (or `make notarize`) and paste the
  # sha256 printed at the end. Update both version and sha256 on every release.
  sha256 "14d92d2a0856177ce8512e3257cf79b2a9f87bf7614d081e9be0c49a5fb5fd70"

  url "https://github.com/arvitaly/reeve/releases/download/v#{version}/Reeve-#{version}.zip"
  name "Reeve"
  desc "Process intervention tool — observe, limit, release"
  homepage "https://github.com/arvitaly/reeve"

  depends_on macos: ">= :ventura"

  app "Reeve.app"

  caveat <<~EOS
    Reeve is not notarized. On first launch, macOS will block it.
    To allow it, run:
      xattr -dr com.apple.quarantine /Applications/Reeve.app
    Or right-click Reeve.app → Open → Open.
  EOS

  zap trash: [
    "~/Library/Preferences/com.reeve.app.plist",
    "~/Library/Application Support/com.reeve.app",
  ]
end
