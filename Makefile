APP_NAME = Sublevel
BUNDLE_DIR = $(APP_NAME).app
CONTENTS_DIR = $(BUNDLE_DIR)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources

.PHONY: all build app run test clean

all: app

build:
	swift build -c release

app: build
	@mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	@rm -rf /tmp/SublevelAppIcon.iconset
	@.build/release/$(APP_NAME) --export-iconset /tmp/SublevelAppIcon.iconset && iconutil -c icns /tmp/SublevelAppIcon.iconset -o AppIcon.icns && rm -rf /tmp/SublevelAppIcon.iconset
	@cp ".build/release/$(APP_NAME)" "$(MACOS_DIR)/$(APP_NAME)"
	@if [ -f AppIcon.icns ]; then cp AppIcon.icns "$(RESOURCES_DIR)/AppIcon.icns"; fi
	@printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0">' \
		'<dict>' \
		'    <key>CFBundleExecutable</key>' \
		'    <string>$(APP_NAME)</string>' \
		'    <key>CFBundleIconFile</key>' \
		'    <string>AppIcon</string>' \
		'    <key>CFBundleIconName</key>' \
		'    <string>AppIcon</string>' \
		'    <key>CFBundleIdentifier</key>' \
		'    <string>com.lucianmarin.sublevel</string>' \
		'    <key>CFBundleName</key>' \
		'    <string>$(APP_NAME)</string>' \
		'    <key>CFBundleDisplayName</key>' \
		'    <string>$(APP_NAME)</string>' \
		'    <key>CFBundlePackageType</key>' \
		'    <string>APPL</string>' \
		'    <key>CFBundleShortVersionString</key>' \
		'    <string>1.0</string>' \
		'    <key>CFBundleVersion</key>' \
		'    <string>1</string>' \
		'    <key>LSMinimumSystemVersion</key>' \
		'    <string>14.0</string>' \
		'    <key>NSHighResolutionCapable</key>' \
		'    <true/>' \
		'    <key>NSPrincipalClass</key>' \
		'    <string>NSApplication</string>' \
		'</dict>' \
		'</plist>' > "$(CONTENTS_DIR)/Info.plist"
	@codesign --force --deep --sign - "$(BUNDLE_DIR)" >/dev/null 2>&1 || true
	@echo "Built $(BUNDLE_DIR)"

run: app
	open "$(BUNDLE_DIR)"

test:
	swift test

clean:
	swift package clean
	rm -rf "$(BUNDLE_DIR)"
