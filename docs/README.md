# Kaštan Documentation

[← Project overview](../README.md)

This is the entry point for Kaštan's complete product documentation. Choose the interface you use; each guide
keeps its detailed feature behavior, requirements, and examples outside the concise project overview.

## Use Kaštan

- [macOS app](macos-app.md) — complete feature description, requirements, and Xcode and terminal build steps.
- [CLI](cli.md) — setup for macOS, Windows, and Linux; all commands and options; output formats; localization;
  stop aliases; and timetables.
- [Container images](containers.md) — prebuilt CLI and MCP images, version tags, persistent CLI aliases, client
  configuration, and local image builds.

## Integrate Kaštan

- [MCP server](mcp-server.md) — build and client configuration, the complete read-only tool catalog, arguments,
  limits, output, and errors.
- [WorkOS OAuth](workos-oauth.md) — invite-only AuthKit setup, MCP discovery, token validation, and migration from
  a static credential.
- [Cloud Run deployment](cloud-run.md) — protected remote Streamable HTTP deployment with WorkOS OAuth, scaling
  limits, verification, migration, and removal.
- [Swift library](swift-library.md) — package integration, the provider-neutral data-source API, a complete example,
  public types, and product behavior.

All four interfaces use the same `Kastan` models and search engine. The app and CLI are implemented against
provider-neutral contracts, but their shipped builds currently select IDOS, the only built-in provider. The Swift
library exposes data-source composition, while the MCP server intentionally keeps an IDOS-only public contract. The
individual guides document the subset or presentation of capabilities exposed by each interface.
