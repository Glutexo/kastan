# Common development commands for every Kaštan interface.

SWIFT ?= swift
XCODEBUILD ?= xcodebuild
GIT ?= git
HDIUTIL ?= hdiutil
DITTO ?= ditto
LIPO ?= lipo
CODESIGN ?= codesign
UNZIP ?= unzip
DOCKER ?= docker
CURL ?= curl

CLI_IMAGE ?= kastan-cli:local
MCP_IMAGE ?= kastan-mcp:local

APP_PROJECT := KastanApp/KastanApp.xcodeproj
APP_SCHEME := KastanApp
APP_DESTINATION := platform=macOS
APP_NAME := Kaštan
APP_ENTITLEMENTS := KastanApp/KastanApp.entitlements
APP_VERSION := $(shell sed -n 's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);/\1/p' $(APP_PROJECT)/project.pbxproj | head -n 1)
CONTAINER_VERSION ?= $(APP_VERSION)
CONTAINER_REVISION ?= $(shell $(GIT) rev-parse --verify HEAD 2>/dev/null || printf '%s' unknown)

DIST_DIR ?= dist
DIST_BUILD_DIR := .build/distribution
DIST_APP := $(DIST_BUILD_DIR)/Build/Products/Release/$(APP_NAME).app
DMG_ROOT := $(DIST_BUILD_DIR)/dmg-root
DMG_PATH := $(DIST_DIR)/kastan-$(APP_VERSION)-macos.dmg
SOURCE_ZIP_PATH := $(DIST_DIR)/kastan-$(APP_VERSION)-source.zip

.DEFAULT_GOAL := dist

.PHONY: help build test test-library test-mcp test-app container-images test-container-images dist dmg source-zip check-dist

help: ## Show the available development commands.
	@printf '%s\n' \
		'Kaštan development commands:' \
		'' \
		'  make                       Create the macOS DMG and source ZIP.' \
		'  make help                  Show the available development commands.' \
		'  make build                 Build the Swift package, MCP server, and macOS app.' \
		'  make test                  Run every test suite.' \
		'  make test-library          Test the shared Swift package and CLI.' \
		'  make test-mcp              Test the MCP server.' \
		'  make test-app              Test the macOS app.' \
		'  make container-images      Build the CLI and MCP container images.' \
		'  make test-container-images Build and smoke-test both container images.' \
		'  make dist                  Create the macOS DMG and source ZIP.' \
		'  make dmg                   Create a universal macOS DMG.' \
		'  make source-zip            Archive the buildable sources from Git HEAD.'

build: ## Build every Kaštan interface.
	$(SWIFT) build
	$(SWIFT) build --package-path MCPServer
	$(XCODEBUILD) build \
		-project $(APP_PROJECT) \
		-scheme $(APP_SCHEME) \
		-destination '$(APP_DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO

test: test-library test-mcp test-app ## Run every test suite.

test-library: ## Test the shared Swift package and CLI.
	$(SWIFT) test

test-mcp: ## Test the MCP server.
	$(SWIFT) test --package-path MCPServer

test-app: ## Test the macOS app.
	$(XCODEBUILD) test \
		-project $(APP_PROJECT) \
		-scheme $(APP_SCHEME) \
		-destination '$(APP_DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO

container-images: ## Build the CLI and MCP Linux container images.
	$(DOCKER) build \
		--build-arg KASTAN_VERSION="$(CONTAINER_VERSION)" \
		--build-arg KASTAN_REVISION="$(CONTAINER_REVISION)" \
		--target cli \
		--tag "$(CLI_IMAGE)" \
		.
	$(DOCKER) build \
		--build-arg KASTAN_VERSION="$(CONTAINER_VERSION)" \
		--build-arg KASTAN_REVISION="$(CONTAINER_REVISION)" \
		--target mcp \
		--tag "$(MCP_IMAGE)" \
		.

test-container-images: container-images ## Smoke-test the container entry points and CLI resources.
	@for image in "$(CLI_IMAGE)" "$(MCP_IMAGE)"; do \
		test "$$($(DOCKER) image inspect --format '{{ index .Config.Labels "org.opencontainers.image.version" }}' "$$image")" = "$(CONTAINER_VERSION)"; \
		test "$$($(DOCKER) image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$$image")" = "$(CONTAINER_REVISION)"; \
		test "$$($(DOCKER) image inspect --format '{{ .Config.User }}' "$$image")" = '65532:65532'; \
	done
	@test "$$($(DOCKER) run --rm "$(CLI_IMAGE)" --version)" = "$(CONTAINER_VERSION)"
	$(DOCKER) run --rm "$(CLI_IMAGE)" --language cs --help | grep -F '🌰 Použití:'
	@response="$$( { printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"container-smoke-test","version":"1.0"}}}'; sleep 1; } | $(DOCKER) run --rm --interactive "$(MCP_IMAGE)")"; \
		printf '%s\n' "$$response" | grep -F 'kastan-mcp'
	@token='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; \
		container_id="$$($(DOCKER) run --rm --detach \
			--publish 127.0.0.1::8080 \
			--env KASTAN_MCP_BEARER_TOKEN="$$token" \
			"$(MCP_IMAGE)" \
			--transport http --host 0.0.0.0)"; \
		trap '$(DOCKER) rm --force "$$container_id" >/dev/null 2>&1 || true' EXIT HUP INT TERM; \
		port="$$($(DOCKER) port "$$container_id" 8080/tcp | sed -n 's/.*://p' | head -n 1)"; \
		attempt=0; \
		until $(CURL) --fail --silent "http://127.0.0.1:$$port/health" >/dev/null; do \
			attempt=$$((attempt + 1)); \
			if test "$$attempt" -ge 30; then $(DOCKER) logs "$$container_id"; exit 1; fi; \
			sleep 0.2; \
		done; \
		test "$$($(CURL) --silent --output /dev/null --write-out '%{http_code}' \
			--header 'Content-Type: application/json' \
			--header 'Accept: application/json, text/event-stream' \
			--data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"container-http-smoke-test","version":"1.0"}}}' \
			"http://127.0.0.1:$$port/mcp")" = 401; \
		response="$$($(CURL) --fail --silent --show-error \
			--header "Authorization: Bearer $$token" \
			--header 'Content-Type: application/json' \
			--header 'Accept: application/json, text/event-stream' \
			--data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"container-http-smoke-test","version":"1.0"}}}' \
			"http://127.0.0.1:$$port/mcp")"; \
		printf '%s\n' "$$response" | grep -F 'kastan-mcp'

dist: check-dist ## Create every downloadable archive from a clean Git HEAD.
	$(MAKE) dmg
	$(MAKE) source-zip

check-dist:
	@if test -n "$$($(GIT) status --porcelain)"; then \
		printf '%s\n' 'Cannot create matching distribution archives from a dirty Git worktree.' >&2; \
		exit 1; \
	fi

dmg: ## Create an ad-hoc-signed universal macOS DMG.
	mkdir -p "$(DIST_DIR)"
	$(XCODEBUILD) build \
		-project $(APP_PROJECT) \
		-scheme $(APP_SCHEME) \
		-configuration Release \
		-destination 'generic/platform=macOS' \
		-derivedDataPath "$(DIST_BUILD_DIR)" \
		ARCHS='arm64 x86_64' \
		ONLY_ACTIVE_ARCH=NO \
		CODE_SIGN_IDENTITY=- \
		CODE_SIGN_STYLE=Manual \
		CODE_SIGNING_ALLOWED=YES
	$(CODESIGN) \
		--force \
		--sign - \
		--options runtime \
		--timestamp=none \
		--entitlements "$(APP_ENTITLEMENTS)" \
		"$(DIST_APP)"
	$(LIPO) "$(DIST_APP)/Contents/MacOS/KastanApp" -verify_arch arm64 x86_64
	$(CODESIGN) --verify --deep --strict "$(DIST_APP)"
	rm -rf "$(DMG_ROOT)"
	mkdir -p "$(DMG_ROOT)"
	$(DITTO) "$(DIST_APP)" "$(DMG_ROOT)/$(APP_NAME).app"
	ln -s /Applications "$(DMG_ROOT)/Applications"
	rm -f "$(DMG_PATH)"
	$(HDIUTIL) create \
		-volname "$(APP_NAME) $(APP_VERSION)" \
		-srcfolder "$(DMG_ROOT)" \
		-format UDZO \
		"$(DMG_PATH)"
	$(HDIUTIL) verify "$(DMG_PATH)"
	@printf 'Created %s\n' "$(DMG_PATH)"

source-zip: ## Archive the buildable sources from Git HEAD.
	mkdir -p "$(DIST_DIR)"
	rm -f "$(SOURCE_ZIP_PATH)"
	$(GIT) archive \
		--format=zip \
		--prefix="kastan-$(APP_VERSION)/" \
		--output="$(SOURCE_ZIP_PATH)" \
		HEAD
	$(UNZIP) -tq "$(SOURCE_ZIP_PATH)"
	@printf 'Created %s\n' "$(SOURCE_ZIP_PATH)"
