cask "reeve" do
  version "0.1.5"
  # Run `make release VERSION=#{version}` (or `make notarize`) and paste the
  # sha256 printed at the end. Update both version and sha256 on every release.
  sha256 "301fcaaf6eeba45a273a35d5b8460219a640c7335666f83a2974729230a09ff5"

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
