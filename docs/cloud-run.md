# Deploy Kaštan MCP to Cloud Run

[← Documentation](README.md)

This guide deploys Kaštan's stateless Streamable HTTP transport as an OAuth-protected remote MCP endpoint.
Google Cloud Run terminates HTTPS and permits public platform invocation; Kaštan remains the OAuth resource
server and WorkOS AuthKit is the authorization server. `/health` and OAuth discovery are public, while every
`/mcp` request requires a valid access token.

Kaštan reads public IDOS endpoints and is intended for occasional personal use. The deployment therefore limits
the service to one instance, four concurrent requests, and 60 authenticated MCP requests per minute.

## Prerequisites

- A Google Cloud project with billing enabled.
- The `gcloud` CLI authenticated as a principal allowed to enable APIs, create a service account and secret, and
  deploy Cloud Run services.
- A WorkOS environment with an AuthKit domain. Production WorkOS environments must be unlocked with billing
  information.
- `openssl` for the temporary migration credential.
- A Kaštan MCP image that includes OAuth mode; the commands below use the fixed `0.5.0` release.

Choose the deployment values once for the current shell:

```sh
export PROJECT_ID="your-google-cloud-project"
export REGION="europe-west3"
export SERVICE="kastan-mcp"
export SECRET="kastan-mcp-bearer-token"
export SERVICE_ACCOUNT="kastan-mcp-runtime"
export IMAGE="ghcr.io/glutexo/kastan-mcp:0.5.0"
export AUTHKIT_ISSUER="https://your-subdomain.authkit.app"

gcloud config set project "$PROJECT_ID"
gcloud services enable \
  iam.googleapis.com \
  run.googleapis.com \
  secretmanager.googleapis.com
```

Select a different Cloud Run region when organizational policy or latency measurements require it.

## Create the Runtime Identity and Migration Token

Create a dedicated service account if it does not exist:

```sh
SERVICE_ACCOUNT_EMAIL="$SERVICE_ACCOUNT@$PROJECT_ID.iam.gserviceaccount.com"

gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" >/dev/null 2>&1 || \
  gcloud iam service-accounts create "$SERVICE_ACCOUNT" \
    --display-name="Kaštan MCP Cloud Run runtime"
```

The first revision uses a static token to establish the permanent Cloud Run URL. It also provides a controlled
fallback while the first OAuth client is tested. Create a secret and add a 256-bit token without placing the
value in shell history:

```sh
gcloud secrets describe "$SECRET" >/dev/null 2>&1 || \
  gcloud secrets create "$SECRET" --replication-policy=automatic

TOKEN="$(openssl rand -hex 32)"
printf '%s' "$TOKEN" | gcloud secrets versions add "$SECRET" --data-file=-

gcloud secrets add-iam-policy-binding "$SECRET" \
  --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
  --role="roles/secretmanager.secretAccessor"
```

Keep `TOKEN` only in a protected password manager or shell long enough to verify the migration. Never commit it.

## Bootstrap the Stable Service URL

Deploy static authorization for a new service. For an existing Kaštan service, retain its current revision and
skip directly to reading `SERVICE_URL`.

```sh
gcloud run deploy "$SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --image="$IMAGE" \
  --service-account="$SERVICE_ACCOUNT_EMAIL" \
  --allow-unauthenticated \
  --port=8080 \
  --set-env-vars="KASTAN_MCP_TRANSPORT=http,KASTAN_MCP_HOST=0.0.0.0,KASTAN_MCP_AUTH_MODE=static,KASTAN_MCP_REQUESTS_PER_MINUTE=60" \
  --set-secrets="KASTAN_MCP_BEARER_TOKEN=$SECRET:latest" \
  --cpu=1 \
  --memory=512Mi \
  --concurrency=4 \
  --min=0 \
  --max=1 \
  --timeout=120s
```

Read the assigned URL and form the exact OAuth resource indicator:

```sh
SERVICE_URL="$(gcloud run services describe "$SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --format='value(status.url)')"
MCP_RESOURCE="$SERVICE_URL/mcp"
printf '%s\n' "$MCP_RESOURCE"
```

Cloud Run resolves the image tag to an immutable digest for each revision. Use the fixed release tag and inspect
the deployed digest when reproducibility matters.

## Configure WorkOS

Follow the [WorkOS OAuth guide](workos-oauth.md) in the same WorkOS environment identified by `AUTHKIT_ISSUER`:

1. Disable public signup, enable Magic Auth, and invite the permitted account.
2. Enable Client ID Metadata Document and Dynamic Client Registration under **Connect → Configuration**.
3. Add the exact value printed in `MCP_RESOURCE` as a Resource Indicator.

Do not create or mount a WorkOS API key for Kaštan. The runtime needs only the public issuer, resource, and JWKS.

## Deploy Hybrid Authorization

Deploy a second revision that accepts either the temporary static token or a WorkOS access token:

```sh
gcloud run deploy "$SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --image="$IMAGE" \
  --service-account="$SERVICE_ACCOUNT_EMAIL" \
  --allow-unauthenticated \
  --port=8080 \
  --set-env-vars="KASTAN_MCP_TRANSPORT=http,KASTAN_MCP_HOST=0.0.0.0,KASTAN_MCP_AUTH_MODE=hybrid,KASTAN_MCP_OAUTH_ISSUER=$AUTHKIT_ISSUER,KASTAN_MCP_OAUTH_RESOURCE=$MCP_RESOURCE,KASTAN_MCP_OAUTH_REQUIRED_SCOPES=openid,KASTAN_MCP_REQUESTS_PER_MINUTE=60" \
  --set-secrets="KASTAN_MCP_BEARER_TOKEN=$SECRET:latest" \
  --cpu=1 \
  --memory=512Mi \
  --concurrency=4 \
  --min=0 \
  --max=1 \
  --timeout=120s
```

## Verify Discovery and Both Credentials

The health check and OAuth metadata must succeed without credentials:

```sh
curl --fail --silent --show-error "$SERVICE_URL/health"
curl --fail --silent --show-error \
  "$SERVICE_URL/.well-known/oauth-protected-resource" | jq
curl --fail --silent --show-error \
  "$SERVICE_URL/.well-known/oauth-authorization-server" | jq
```

The protected-resource document must name `MCP_RESOURCE` exactly and list `AUTHKIT_ISSUER`. The authorization
server document must come from the same issuer and advertise Authorization Code, PKCE S256, and a token endpoint.

An unauthenticated MCP request must return 401 with a `resource_metadata` challenge:

```sh
curl --include --silent \
  --header 'Content-Type: application/json' \
  --header 'Accept: application/json, text/event-stream' \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"cloud-run-check","version":"1.0"}}}' \
  "$MCP_RESOURCE"
```

The temporary token must still initialize MCP during the hybrid revision:

```sh
curl --fail --silent --show-error \
  --header "Authorization: Bearer $TOKEN" \
  --header 'Content-Type: application/json' \
  --header 'Accept: application/json, text/event-stream' \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"cloud-run-check","version":"1.0"}}}' \
  "$MCP_RESOURCE"
```

Finally configure an OAuth-capable MCP client with only `MCP_RESOURCE`, complete AuthKit sign-in as an invited
user, and verify `initialize`, `tools/list`, and one read-only tool call. Do not remove the static credential until
this interactive flow succeeds end to end.

## Switch to OAuth Only

After the OAuth client works, create an OAuth-only revision and remove the Secret Manager mapping atomically:

```sh
gcloud run deploy "$SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --image="$IMAGE" \
  --update-env-vars="KASTAN_MCP_AUTH_MODE=oauth" \
  --remove-secrets="KASTAN_MCP_BEARER_TOKEN"
```

Verify that the old static token now receives 401 and the OAuth client still completes a tool call. Then remove
the runtime identity's secret access:

```sh
gcloud secrets remove-iam-policy-binding "$SECRET" \
  --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
  --role="roles/secretmanager.secretAccessor"
```

Retain the secret version only for a deliberately short rollback window. After that window, disable or destroy
the version and delete the secret if no other revision uses it. Rolling back to a hybrid revision also requires
temporarily restoring the service account's secret access.

## Operate and Remove

Read recent logs without exposing tokens:

```sh
gcloud run services logs read "$SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --limit=50
```

WorkOS rotates its signing keys through the public JWKS, so routine key rotation requires no Cloud Run secret or
deployment change. A different AuthKit environment, issuer domain, MCP URL, or required scope does require a new
revision and matching WorkOS Resource Indicator.

Delete the service and its dedicated identity when no longer needed. Delete the migration secret too if it was
retained:

```sh
gcloud run services delete "$SERVICE" --project="$PROJECT_ID" --region="$REGION"
gcloud secrets delete "$SECRET" --project="$PROJECT_ID"
gcloud iam service-accounts delete "$SERVICE_ACCOUNT_EMAIL" --project="$PROJECT_ID"
```
