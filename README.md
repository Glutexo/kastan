# 🌰 Kaštan

<img src="KastanApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-256.png" alt="Kaštan app icon" width="128">

Kaštan is an open-source companion for occasional personal [IDOS](https://idos.cz/en/) searches. Use it as a
native macOS app or from a terminal, or integrate its search engine as a Swift library or local MCP server.

![Kaštan for macOS showing train connections from Prague to Brno](docs/images/kastan-macos-connections.png)

Kaštan reads publicly reachable IDOS web pages. It is intended for personal, low-frequency use rather than as
a stable or guaranteed data API.

## Choose How to Use Kaštan

- [macOS app](docs/macos-app.md) — search connections, station boards, and MHD station timetables in a native app.
- [CLI](docs/cli.md) — run the same searches on macOS, Windows, or Linux and choose human-readable or structured output.
- [Swift library](docs/swift-library.md) — build IDOS search features into a Swift project.
- [MCP server](docs/mcp-server.md) — give a local MCP client read-only access to Kaštan searches.

## Quick Start

The command-line package requires Git and Swift 6.3 or newer:

```sh
git clone https://github.com/Glutexo/kastan.git
cd kastan
swift test
swift run kastan Praha Brno --time 12:00
```

To try the native app, open the Xcode project and run the shared `KastanApp` scheme:

```sh
open KastanApp/KastanApp.xcodeproj
```

## Documentation

README stays focused on getting started. The [complete documentation](docs/README.md) contains platform setup,
full feature descriptions, every CLI command, the Swift API, and MCP configuration and tool behavior.

## Development

```sh
swift build
swift test
swift test --package-path MCPServer
xcodebuild test -project KastanApp/KastanApp.xcodeproj -scheme KastanApp -destination 'platform=macOS'
```

GitHub Actions runs all three test suites for changes to `main` and for pull requests.
