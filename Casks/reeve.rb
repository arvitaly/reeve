cask "reeve" do
  version "0.2.5"
  # Run `make release VERSION=#{version}` (or `make notarize`) and paste the
  # sha256 printed at the end. Update both version and sha256 on every release.
  sha256 "623d7f0b8dc6b915d59f0175ddfd18ff8174ff117123e378289445d4dc8265c9"

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
