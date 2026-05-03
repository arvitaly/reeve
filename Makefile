BUNDLE     = Reeve.app
BINARY     = $(BUNDLE)/Contents/MacOS/Reeve
INFOPLIST  = $(BUNDLE)/Contents/Info.plist
HELPER_BIN     = $(BUNDLE)/Contents/MacOS/com.reeve.helper
HELPER_PLIST   = $(BUNDLE)/Contents/Library/LaunchDaemons/com.reeve.helper.plist
HELPER_ENTITLEMENTS = ReeveHelper.entitlements
CONFIG    ?= debug
VERSION   ?= 0.3.1
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

.PHONY: build run release sign notarize clean dev-helper-load dev-helper-unload dev-helper-status

build:
	swift build -c $(CONFIG) --product Reeve
	swift build -c $(CONFIG) --product ReeveHelper
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources $(BUNDLE)/Contents/Library/LaunchDaemons
	cp .build/$(ARCH)-apple-macosx/$(CONFIG)/Reeve $(BINARY)
	cp .build/$(ARCH)-apple-macosx/$(CONFIG)/ReeveHelper $(HELPER_BIN)
	cp Assets/AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns
	@$(MAKE) --no-print-directory _plist
	@$(MAKE) --no-print-directory _helper_plist

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

_helper_plist:
	cp ReeveHelper.plist.template $(HELPER_PLIST)

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
	# Helper first, then app bundle. No --deep — we sign each component
	# individually with its own entitlements (Apple's recommended pattern
	# for SMAppService daemons).
	codesign --force --options runtime --timestamp \
	  --sign "$(SIGN_IDENTITY)" \
	  --entitlements $(HELPER_ENTITLEMENTS) \
	  $(HELPER_BIN)
	codesign --force --options runtime --timestamp \
	  --sign "$(SIGN_IDENTITY)" \
	  --entitlements Reeve.entitlements \
	  $(BUNDLE)
	@echo "Signed: $(HELPER_BIN) and $(BUNDLE)"

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

# ── Local dev helper install (bypass SMAppService) ──────────────────────────
#
# SMAppService refuses unsigned daemons. For local iteration without a
# Developer ID certificate, ad-hoc-sign the helper, point a plist at the
# absolute build path, and launchctl-bootstrap it directly.
#
# Run:  make dev-helper-load
# After:  Reeve will connect via XPC even though Settings shows "Not found".
# Stop:  make dev-helper-unload

DEV_HELPER_LABEL = com.reeve.helper
DEV_HELPER_PLIST_DST = /Library/LaunchDaemons/$(DEV_HELPER_LABEL).plist
DEV_HELPER_BIN_ABS = $(shell pwd)/$(HELPER_BIN)

dev-helper-load: build
	codesign --force --sign - --options runtime --entitlements $(HELPER_ENTITLEMENTS) $(HELPER_BIN)
	@echo '<?xml version="1.0" encoding="UTF-8"?>'                                                  >  /tmp/$(DEV_HELPER_LABEL).plist
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> /tmp/$(DEV_HELPER_LABEL).plist
	@echo '<plist version="1.0"><dict>'                                                             >> /tmp/$(DEV_HELPER_LABEL).plist
	@echo '  <key>Label</key><string>$(DEV_HELPER_LABEL)</string>'                                  >> /tmp/$(DEV_HELPER_LABEL).plist
	@echo '  <key>ProgramArguments</key><array><string>$(DEV_HELPER_BIN_ABS)</string></array>'      >> /tmp/$(DEV_HELPER_LABEL).plist
	@echo '  <key>MachServices</key><dict><key>com.reeve.helper</key><true/></dict>'                >> /tmp/$(DEV_HELPER_LABEL).plist
	@echo '  <key>RunAtLoad</key><false/>'                                                          >> /tmp/$(DEV_HELPER_LABEL).plist
	@echo '</dict></plist>'                                                                         >> /tmp/$(DEV_HELPER_LABEL).plist
	sudo cp /tmp/$(DEV_HELPER_LABEL).plist $(DEV_HELPER_PLIST_DST)
	sudo chown root:wheel $(DEV_HELPER_PLIST_DST)
	sudo chmod 0644 $(DEV_HELPER_PLIST_DST)
	-sudo launchctl bootout system/$(DEV_HELPER_LABEL) 2>/dev/null
	sudo launchctl bootstrap system $(DEV_HELPER_PLIST_DST)
	@echo "\nLoaded.  Reeve.app will connect via XPC; Settings tab will still show 'Not found' (SMAppService only)."

dev-helper-unload:
	-sudo launchctl bootout system/$(DEV_HELPER_LABEL) 2>/dev/null
	sudo rm -f $(DEV_HELPER_PLIST_DST)
	@echo "Unloaded."

dev-helper-status:
	@sudo launchctl print system/$(DEV_HELPER_LABEL) 2>&1 | head -30 || echo "not loaded"
