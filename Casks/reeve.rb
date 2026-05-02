cask "reeve" do
  version "0.2.7"
  # Run `make release VERSION=#{version}` (or `make notarize`) and paste the
  # sha256 printed at the end. Update both version and sha256 on every release.
  sha256 "90dbf5070bfca3f8435b5b055e0caccc046c4a5f867f15146510179d1f841988"

  url "https://github.com/arvitaly/reeve/releases/download/v#{version}/Reeve-#{version}.zip"
  name "Reeve"
  desc "Process intervention tool — observe, limit, release"
  homepage "https://github.com/arvitaly/reeve"

  depends_on macos: ">= :ventura"

  app "Reeve.app"

  zap trash: [
    "~/Library/Preferences/com.reeve.app.plist",
    "~/Library/Application Support/com.reeve.app",
  ]
end
