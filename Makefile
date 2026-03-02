SCHEME = Commandment
CONFIGURATION = Release
DERIVED_DATA = /tmp/rubber-duck-build
ARCHIVE_PATH = $(DERIVED_DATA)/RubberDuck.xcarchive
EXPORT_PATH = $(DERIVED_DATA)/export
APP_NAME = RubberDuck
DMG_PATH = $(DERIVED_DATA)/$(APP_NAME).dmg
DMG_BG_SCRIPT = installer/make-dmg-bg.swift
DMG_BG        = installer/dmg-background.png
BUNDLE_ID = co.blode.rubber-duck
VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0")

CODESIGN_IDENTITY ?= Developer ID Application
TEAM_ID ?= $(APPLE_TEAM_ID)

.PHONY: build test cli-build cli-test cli-binary e2e-swift e2e-cli e2e-smoke e2e smoke-live archive export dmg-background dmg notarize clean unused

CLI_BIN_DIR = cli-bin

cli-binary: ## Build standalone rubber-duck binaries (arm64 + x64) for distribution (requires Node 22)
	cd cli && npm ci && npm run build:binary

build:
	xcodebuild -scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-destination 'generic/platform=macOS' \
		-derivedDataPath $(DERIVED_DATA) \
		MARKETING_VERSION=$(VERSION) \
		build

test:
	xcodebuild -scheme $(SCHEME) \
		-configuration Debug \
		-destination 'generic/platform=macOS' \
		-derivedDataPath $(DERIVED_DATA) \
		MARKETING_VERSION=$(VERSION) \
		test

cli-build:
	cd cli && npm run build

cli-test:
	cd cli && npm run test -- --passWithNoTests

e2e-swift: ## Run Swift Realtime E2E tests (requires /tmp/rubber-duck-live-realtime-test with API key)
	xcodebuild -scheme Commandment -configuration Debug -destination 'generic/platform=macOS' test -only-testing:RubberDuckTests/RealtimeClientLiveSmokeTests -derivedDataPath /tmp/rubber-duck-build

e2e-cli: ## Run CLI daemon integration E2E test (requires OPENAI_API_KEY or ANTHROPIC_API_KEY)
	cd cli && npm run build && npm test -- --reporter=verbose e2e

e2e-smoke: ## Run CLI shell smoke test (requires OPENAI_API_KEY or ANTHROPIC_API_KEY and built CLI)
	cd cli && scripts/e2e-smoke.sh

e2e: e2e-swift e2e-cli e2e-smoke ## Run all E2E tests

smoke-live: ## Run live hardware barge-in smoke test with generated sample clips
	./scripts/live-hardware-smoke.sh run

archive:
	xcodebuild -scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(DERIVED_DATA) \
		-archivePath $(ARCHIVE_PATH) \
		CODE_SIGN_STYLE=Manual \
		CODE_SIGN_IDENTITY="$(CODESIGN_IDENTITY)" \
		DEVELOPMENT_TEAM="$(TEAM_ID)" \
		MARKETING_VERSION=$(VERSION) \
		archive

export: archive
	@printf '<?xml version="1.0" encoding="UTF-8"?>\n\
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n\
	<plist version="1.0">\n\
	<dict>\n\
		<key>method</key>\n\
		<string>developer-id</string>\n\
		<key>teamID</key>\n\
		<string>$(TEAM_ID)</string>\n\
		<key>signingStyle</key>\n\
		<string>manual</string>\n\
		<key>signingCertificate</key>\n\
		<string>Developer ID Application</string>\n\
	</dict>\n\
	</plist>' > $(DERIVED_DATA)/ExportOptions.plist
	xcodebuild -exportArchive \
		-archivePath $(ARCHIVE_PATH) \
		-exportPath $(EXPORT_PATH) \
		-exportOptionsPlist $(DERIVED_DATA)/ExportOptions.plist

dmg-background:
	@echo "Generating DMG background..."
	swift $(DMG_BG_SCRIPT)

dmg: export dmg-background
	@rm -f $(DMG_PATH)
	create-dmg \
		--volname "$(APP_NAME)" \
		--background "$(DMG_BG)" \
		--window-pos 200 120 \
		--window-size 700 460 \
		--icon-size 128 \
		--icon "$(APP_NAME).app" 175 230 \
		--app-drop-link 525 230 \
		--hide-extension "$(APP_NAME).app" \
		--text-size 14 \
		--volicon "$(EXPORT_PATH)/$(APP_NAME).app/Contents/Resources/AppIcon.icns" \
		--no-internet-enable \
		$(DMG_PATH) \
		$(EXPORT_PATH)/$(APP_NAME).app || test -f $(DMG_PATH)
	@echo "DMG created at $(DMG_PATH)"

notarize: dmg
	xcrun notarytool submit $(DMG_PATH) \
		--apple-id "$(NOTARIZE_APPLE_ID)" \
		--password "$(NOTARIZE_PASSWORD)" \
		--team-id "$(TEAM_ID)" \
		--wait
	xcrun stapler staple $(DMG_PATH)
	@echo "Notarized: $(DMG_PATH)"

unused: ## Find unused Swift declarations with Periphery
	periphery scan

clean:
	rm -rf $(DERIVED_DATA)
