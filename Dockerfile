# syntax=docker/dockerfile:1

ARG SWIFT_VERSION=6.3.3
ARG KASTAN_VERSION=development
ARG KASTAN_REVISION=unknown

FROM swift:${SWIFT_VERSION}-noble AS source

WORKDIR /workspace

# Resolve the remote MCP dependencies before copying sources so dependency downloads
# stay cached when only Kaštan implementation files change. HTTP/1.1 keeps Git
# dependency fetches reliable inside virtualized Docker networks.
COPY Package.swift ./
COPY MCPServer/Package.swift MCPServer/Package.resolved ./MCPServer/
RUN git config --global http.version HTTP/1.1 \
    && swift package --package-path MCPServer resolve

COPY Sources ./Sources
COPY Tests ./Tests
COPY MCPServer/Sources ./MCPServer/Sources
COPY MCPServer/Tests ./MCPServer/Tests

FROM source AS cli-builder

RUN swift build \
        --configuration release \
        --product kastan \
        --static-swift-stdlib \
    && bin_path="$(swift build --configuration release --show-bin-path)" \
    && mkdir -p /artifacts \
    && cp "${bin_path}/kastan" /artifacts/ \
    && cp -R "${bin_path}/kastan_KastanCLI.resources" /artifacts/

FROM source AS mcp-builder

RUN swift build \
        --package-path MCPServer \
        --configuration release \
        --product kastan-mcp \
        --static-swift-stdlib \
    && bin_path="$(swift build --package-path MCPServer --configuration release --show-bin-path)" \
    && mkdir -p /artifacts \
    && cp "${bin_path}/kastan-mcp" /artifacts/

FROM ubuntu:24.04 AS runtime

LABEL org.opencontainers.image.source="https://github.com/Glutexo/kastan" \
      org.opencontainers.image.licenses="CC0-1.0"

RUN export DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        libcurl4 \
        libxml2 \
        tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /home/kastan/.config \
    && chown -R 65532:65532 /home/kastan

ENV HOME=/home/kastan \
    XDG_CONFIG_HOME=/home/kastan/.config \
    LANG=C.UTF-8

COPY LICENSE /usr/share/doc/kastan/LICENSE

ARG KASTAN_VERSION
ARG KASTAN_REVISION

LABEL org.opencontainers.image.version="${KASTAN_VERSION}" \
      org.opencontainers.image.revision="${KASTAN_REVISION}"

USER 65532:65532

FROM runtime AS cli

LABEL org.opencontainers.image.title="Kaštan CLI" \
      org.opencontainers.image.description="Personal IDOS searches from a containerized command line"

COPY --from=cli-builder /artifacts/ /usr/local/bin/

ENTRYPOINT ["/usr/local/bin/kastan"]
CMD ["--help"]

FROM runtime AS mcp

LABEL org.opencontainers.image.title="Kaštan MCP server" \
      org.opencontainers.image.description="Read-only IDOS search tools over MCP stdio or Streamable HTTP"

COPY --from=mcp-builder /artifacts/kastan-mcp /usr/local/bin/kastan-mcp

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/kastan-mcp"]
