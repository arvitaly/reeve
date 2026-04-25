BUNDLE     = Reeve.app
BINARY     = $(BUNDLE)/Contents/MacOS/Reeve
INFOPLIST  = $(BUNDLE)/Contents/Info.plist
CONFIG    ?= debug

.PHONY: build run clean

build:
	swift build --target Reeve -c $(CONFIG)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp .build/arm64-apple-macosx/$(CONFIG)/Reeve $(BINARY)
	@$(MAKE) --no-print-directory _plist

_plist:
	@printf '<?xml version="1.0" encoding="UTF-8"?>\n\
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n\
<plist version="1.0"><dict>\n\
  <key>CFBundleExecutable</key><string>Reeve</string>\n\
  <key>CFBundleIdentifier</key><string>com.reeve.app</string>\n\
  <key>CFBundleName</key><string>Reeve</string>\n\
  <key>CFBundleVersion</key><string>0.1</string>\n\
  <key>CFBundleShortVersionString</key><string>0.1</string>\n\
  <key>LSMinimumSystemVersion</key><string>13.0</string>\n\
  <key>LSUIElement</key><true/>\n\
  <key>NSPrincipalClass</key><string>NSApplication</string>\n\
  <key>NSHighResolutionCapable</key><true/>\n\
</dict></plist>\n' > $(INFOPLIST)

run: build
	open $(BUNDLE)

clean:
	rm -rf $(BUNDLE) .build
