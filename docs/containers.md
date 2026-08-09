# Kaštan Container Images

[← Documentation](README.md)

Kaštan publishes separate Linux container images for its command-line and MCP interfaces. They avoid a local
Swift installation and run on both AMD64 and ARM64 hosts.

## Published Images and Tags

| Image | Entrypoint | Purpose |
| --- | --- | --- |
| `ghcr.io/glutexo/kastan-cli` | `kastan` | Interactive and scripted CLI searches. |
| `ghcr.io/glutexo/kastan-mcp` | `kastan-mcp` | MCP communication over standard input and output. |

Use `latest` for the newest stable release, a complete version such as `0.1.2` for a fixed release, or a
minor-version tag such as `0.1` for compatible patch updates. The rolling `main` tag contains the newest commit
on the default branch, while `sha-<commit>` identifies its exact source revision.

Both images run as the unprivileged numeric user `65532` and contain the CA certificates and libraries required
to reach IDOS over HTTPS. They are Linux images, so the macOS-only `--add-to-calendar` CLI option is unavailable;
use `--format ics` and redirect the calendar data to a host file instead.

## CLI Image

Run CLI arguments directly after the image name:

```sh
docker run --rm ghcr.io/glutexo/kastan-cli:latest Praha Brno --time 12:00
docker run --rm ghcr.io/glutexo/kastan-cli:latest departures --station Praha --format json
docker run --rm ghcr.io/glutexo/kastan-cli:latest --language cs --help
```

Each container is otherwise ephemeral. Mount a named volume at `/home/kastan/.config` to preserve stop aliases
between commands:

```sh
docker volume create kastan-config
docker run --rm \
  --volume kastan-config:/home/kastan/.config \
  ghcr.io/glutexo/kastan-cli:latest \
  aliases add home --station "Frýdek,Na Veselé" --timetable odis
docker run --rm \
  --volume kastan-config:/home/kastan/.config \
  ghcr.io/glutexo/kastan-cli:latest \
  aliases list
```

Alternatively, mount one host file and set `KASTAN_ALIAS_DATABASE` to its in-container path. The
[complete CLI guide](cli.md) documents all commands, output formats, aliases, and timetables.

## MCP Image

An MCP client must keep the container's standard input open and must not allocate a pseudo-terminal. Clients
that use a JSON server map commonly accept this configuration:

```json
{
  "mcpServers": {
    "kastan": {
      "command": "docker",
      "args": [
        "run",
        "--rm",
        "--interactive",
        "ghcr.io/glutexo/kastan-mcp:latest"
      ]
    }
  }
}
```

The Docker daemon must be running when the client starts the server. Kaštan needs no credentials, environment
variables, port publication, or persistent volume. The [complete MCP guide](mcp-server.md) documents every tool
and result.

## Local Builds

Build and smoke-test both images from the repository root:

```sh
make test-container-images
```

The default local names are `kastan-cli:local` and `kastan-mcp:local`. Override them when needed:

```sh
make container-images \
  CLI_IMAGE=example/kastan-cli:test \
  MCP_IMAGE=example/kastan-mcp:test
```

The Make targets stamp both images with the current app version and, when available, Git revision in their OCI
metadata. Override them with `CONTAINER_VERSION` and `CONTAINER_REVISION` when reproducing a different build.

The shared Dockerfile also exposes independent targets for tools that do not use the Makefile:

```sh
docker build --target cli --tag kastan-cli:local .
docker build --target mcp --tag kastan-mcp:local .
```

Direct Dockerfile builds use `development` and `unknown` as the version and revision labels unless the caller
sets the `KASTAN_VERSION` and `KASTAN_REVISION` build arguments.

GitHub Actions builds and smoke-tests the native AMD64 images for pull requests. Commits on `main` and version
tags additionally publish both AMD64 and ARM64 variants to GitHub Container Registry.
