# Common development commands for every Kaštan interface.

SWIFT ?= swift
XCODEBUILD ?= xcodebuild

APP_PROJECT := KastanApp/KastanApp.xcodeproj
APP_SCHEME := KastanApp
APP_DESTINATION := platform=macOS

.DEFAULT_GOAL := help

.PHONY: help build test test-library test-mcp test-app

help: ## Show the available development commands.
	@printf '%s\n' \
		'Kaštan development commands:' \
		'' \
		'  make build         Build the Swift package, MCP server, and macOS app.' \
		'  make test          Run every test suite.' \
		'  make test-library  Test the shared Swift package and CLI.' \
		'  make test-mcp      Test the MCP server.' \
		'  make test-app      Test the macOS app.'

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
