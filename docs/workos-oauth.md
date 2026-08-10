# Protect Kaštan MCP with WorkOS AuthKit

[← Documentation](README.md)

WorkOS AuthKit can act as the OAuth 2.1 authorization server for an internet-facing Kaštan MCP resource server.
The MCP client discovers AuthKit from Kaštan's RFC 9728 metadata, signs the user in through a browser, and obtains
an access token addressed specifically to the public Kaštan `/mcp` URL. Kaštan verifies that token locally from
WorkOS public keys; no WorkOS API key or OAuth client secret is stored in the container.

This guide uses AuthKit's default domain, Magic Auth, and invite-only registration for a small private deployment.
WorkOS documents the provider-side MCP controls in its
[AuthKit MCP guide](https://workos.com/docs/authkit/mcp) and the closed-registration controls in its
[invite-only signup guide](https://workos.com/docs/authkit/invite-only-signup).

## Choose the WorkOS Environment

Use a WorkOS staging environment while testing an unpublished endpoint. Use a production environment before
relying on OAuth for the live service. WorkOS separates users, invitations, keys, AuthKit configuration, and
Connect settings between environments, so repeat the configuration in production rather than reusing staging
values. WorkOS requires billing information before production can be unlocked even when usage remains within its
free allowance.

Record these two public values; they are not secrets:

```sh
export AUTHKIT_ISSUER="https://your-subdomain.authkit.app"
export MCP_RESOURCE="https://your-service.run.app/mcp"
```

The resource must be the externally reachable MCP URL, including the exact `/mcp` path and without a trailing
slash. The issuer must match the `issuer` value returned by AuthKit's metadata exactly.

## Restrict Sign-in to Invited Users

In the selected WorkOS environment:

1. Keep the default AuthKit application and default AuthKit domain unless a separate branded application is
   required.
2. Enable Magic Auth as the authentication method used by the invited account.
3. Disable **Sign up** in the environment's Authentication settings.
4. Create an application-wide invitation for each permitted email address from **Users → Invites**. Do not attach
   an organization unless organization membership is part of the intended access model.
5. Accept the invitation before testing an MCP client. Disabling signup prevents uninvited accounts from creating
   a user, while a valid invitation temporarily opens registration for its recipient.

For a personal server, invite-only registration is the primary user allowlist. Kaštan additionally requires a
nonempty token subject but deliberately does not encode an email address or WorkOS user ID in deployment
configuration.

## Enable MCP Client Registration

Open **Connect → Configuration** in the same environment and:

1. Enable **Client ID Metadata Document (CIMD)** for current MCP clients.
2. Enable **Dynamic Client Registration (DCR)** for clients that implement the earlier MCP registration flow.
3. Add the exact value of `MCP_RESOURCE` as a valid **Resource Indicator**.

The resource indicator is security-critical. WorkOS places the requested resource in the access token's `aud`
claim, and Kaštan rejects a token unless that claim contains the exact configured MCP URL. Without a configured
resource indicator, WorkOS uses an environment-specific default audience that Kaštan will correctly reject.

AuthKit currently advertises the standard `openid`, `profile`, `email`, and `offline_access` scopes. Kaštan needs
only `openid`; advertising and requiring it ensures an MCP client requests a scope WorkOS supports while keeping
the grant minimal.

## Configure Kaštan

Start directly in OAuth-only mode for a new service:

```sh
export KASTAN_MCP_AUTH_MODE="oauth"
export KASTAN_MCP_OAUTH_ISSUER="$AUTHKIT_ISSUER"
export KASTAN_MCP_OAUTH_RESOURCE="$MCP_RESOURCE"
export KASTAN_MCP_OAUTH_REQUIRED_SCOPES="openid"

swift run --package-path MCPServer kastan-mcp \
  --transport http \
  --host 0.0.0.0 \
  --port 8080
```

Kaštan derives the WorkOS JWKS URL as `$AUTHKIT_ISSUER/oauth2/jwks`. Set
`KASTAN_MCP_OAUTH_JWKS_URL` only when an authorization server publishes its keys elsewhere.

For an existing static-token deployment, first use `hybrid` with both OAuth variables and the existing
`KASTAN_MCP_BEARER_TOKEN`. Verify one interactive OAuth client before switching to `oauth` and removing the static
secret from the runtime. The [Cloud Run guide](cloud-run.md) gives exact commands for this two-revision migration.

## Verify Discovery

The public health and protected-resource metadata must succeed without a token:

```sh
curl --fail --silent --show-error "${MCP_RESOURCE%/mcp}/health"
curl --fail --silent --show-error \
  "${MCP_RESOURCE%/mcp}/.well-known/oauth-protected-resource" | jq
```

The metadata must contain the exact resource and WorkOS issuer:

```json
{
  "resource": "https://your-service.run.app/mcp",
  "authorization_servers": ["https://your-subdomain.authkit.app"],
  "bearer_methods_supported": ["header"],
  "scopes_supported": ["openid"]
}
```

An unauthenticated MCP request must return 401. Its `WWW-Authenticate` header points back to the metadata URL and
includes the `openid` scope:

```sh
curl --include --silent \
  --header 'Content-Type: application/json' \
  --header 'Accept: application/json, text/event-stream' \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"oauth-check","version":"1.0"}}}' \
  "$MCP_RESOURCE"
```

Finally, add only `MCP_RESOURCE` to an OAuth-capable remote MCP client. A browser should open for AuthKit sign-in
and consent. After the invited user completes it, `initialize`, `tools/list`, and a read-only tool call must work
without a manually configured Authorization header.

## Runtime Validation and Rotation

Kaštan accepts only RS256 JWT access tokens. It requires the configured issuer, exact resource audience, expiry,
nonempty subject, and requested scopes; it also honors optional not-before and issued-at times with 60 seconds of
clock tolerance. Public keys are cached according to the upstream cache lifetime, refreshed when they expire or a
new key ID appears, and restricted to signing RSA keys. Unknown key IDs are refresh-throttled to avoid turning
unauthenticated traffic into an upstream request flood.

WorkOS key rotation therefore needs no Kaštan secret update or redeployment. Changing the AuthKit domain, WorkOS
environment, public MCP URL, or required scopes does require a new Kaštan revision and matching WorkOS Resource
Indicator configuration.
