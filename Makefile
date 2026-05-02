BUNDLE     = Reeve.app
BINARY     = $(BUNDLE)/Contents/MacOS/Reeve
INFOPLIST  = $(BUNDLE)/Contents/Info.plist
CONFIG    ?= debug
VERSION   ?= 0.2.10
ARCH      := $(shell uname -m)

# Filled in by the developer; leave blank to skip codesigning.
# export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
# export APPLE_ID="you@example.com"
# export TEAM_ID="XXXXXXXXXX"
# export NOTARIZE_PASSWORD="@keychain:notarytool"
SIGN_IDENTITY ?=
APPLE_ID      ?=
TEAM_ID       ?=
NOTARIZE_PASSWORD ?=

ZIPFILE = Reeve-$(VERSION).zip

.PHONY: build run release sign notarize clean

build:
	swift build -c $(CONFIG)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp .build/$(ARCH)-apple-macosx/$(CONFIG)/Reeve $(BINARY)
	cp Assets/AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns
	@$(MAKE) --no-print-directory _plist

_plist:
	@printf '<?xml version="1.0" encoding="UTF-8"?>\n\
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n\
<plist version="1.0"><dict>\n\
  <key>CFBundleExecutable</key><string>Reeve</string>\n\
  <key>CFBundleIdentifier</key><string>com.reeve.app</string>\n\
  <key>CFBundleName</key><string>Reeve</string>\n\
  <key>CFBundleVersion</key><string>$(VERSION)</string>\n\
  <key>CFBundleShortVersionString</key><string>$(VERSION)</string>\n\
  <key>LSMinimumSystemVersion</key><string>13.0</string>\n\
  <key>LSUIElement</key><true/>\n\
  <key>NSPrincipalClass</key><string>NSApplication</string>\n\
  <key>NSHighResolutionCapable</key><true/>\n\
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>\n\
  <key>CFBundleIconFile</key><string>AppIcon</string>\n\
</dict></plist>\n' > $(INFOPLIST)

run: build
	open $(BUNDLE)

# ── Release ──────────────────────────────────────────────────────────────────

release:
	$(MAKE) build CONFIG=release VERSION=$(VERSION)
	@if [ -n "$(SIGN_IDENTITY)" ]; then \
	  $(MAKE) sign VERSION=$(VERSION); \
	fi
	ditto -c -k --keepParent $(BUNDLE) $(ZIPFILE)
	@SHA=$$(shasum -a 256 $(ZIPFILE) | awk '{print $$1}'); \
	  echo "\n$$SHA  $(ZIPFILE)"; \
	  sed -i '' "s/version \"[^\"]*\"/version \"$(VERSION)\"/" Casks/reeve.rb; \
	  sed -i '' "s/sha256 \"[^\"]*\"/sha256 \"$$SHA\"/" Casks/reeve.rb; \
	  echo "\nCasks/reeve.rb updated automatically."

publish: release
	@git add Casks/reeve.rb Makefile
	@git commit -m "Release v$(VERSION)"
	@git tag v$(VERSION)
	@git push && git push --tags
	@gh release create v$(VERSION) $(ZIPFILE) --title "v$(VERSION)" --latest
	@CONTENT=$$(base64 < Casks/reeve.rb | tr -d '\n'); \
	  FILE_SHA=$$(gh api repos/arvitaly/homebrew-reeve/contents/Casks/reeve.rb --jq '.sha'); \
	  gh api --method PUT repos/arvitaly/homebrew-reeve/contents/Casks/reeve.rb \
	    --field message="Update cask to v$(VERSION)" \
	    --field content="$$CONTENT" \
	    --field sha="$$FILE_SHA" \
	    --jq '.commit.sha'
	@echo "\nv$(VERSION) published to GitHub and homebrew-reeve tap."

sign:
	codesign --deep --force --options runtime \
	  --sign "$(SIGN_IDENTITY)" \
	  --entitlements Reeve.entitlements \
	  $(BUNDLE)
	@echo "Signed: $(BUNDLE)"

# Requires: APPLE_ID, TEAM_ID, NOTARIZE_PASSWORD env vars and a prior `make release`.
notarize:
	xcrun notarytool submit $(ZIPFILE) \
	  --apple-id "$(APPLE_ID)" \
	  --team-id "$(TEAM_ID)" \
	  --password "$(NOTARIZE_PASSWORD)" \
	  --wait
	xcrun stapler staple $(BUNDLE)
	rm -f $(ZIPFILE)
	ditto -c -k --keepParent $(BUNDLE) $(ZIPFILE)
	@echo ""; shasum -a 256 $(ZIPFILE)
	@echo "\nUpdate Casks/reeve.rb sha256 with the notarized value above."

clean:
	rm -rf $(BUNDLE) .build Reeve-*.zip
