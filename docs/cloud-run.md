# Deploy Kaštan MCP to Cloud Run

[← Documentation](README.md)

This guide deploys Kaštan's stateless Streamable HTTP transport as a private personal MCP endpoint backed by a
publicly invokable Google Cloud Run service. Cloud Run terminates HTTPS, while Kaštan requires a pre-shared
Bearer token on every `/mcp` request. The unauthenticated `/health` endpoint exists only for service health
checks. OAuth discovery and user authorization are not part of this deployment.

Kaštan reads public IDOS endpoints and is intended for occasional personal use. The configuration therefore
limits the service to one instance, four concurrent requests, and 60 authenticated MCP requests per minute.

## Prerequisites

- A Google Cloud project with billing enabled.
- The `gcloud` CLI authenticated as a principal allowed to enable APIs, create a service account and secret, and
  deploy Cloud Run services.
- `openssl` for generating a 256-bit token.
- A Kaštan MCP image that includes HTTP mode; the commands below use the fixed `0.2.0` release.

Choose the project, region, and resource names once for the current shell:

```sh
export PROJECT_ID="your-google-cloud-project"
export REGION="europe-west3"
export SERVICE="kastan-mcp"
export SECRET="kastan-mcp-bearer-token"
export SERVICE_ACCOUNT="kastan-mcp-runtime"
export IMAGE="ghcr.io/glutexo/kastan-mcp:0.2.0"

gcloud config set project "$PROJECT_ID"
gcloud services enable \
  iam.googleapis.com \
  run.googleapis.com \
  secretmanager.googleapis.com
```

Select a different Cloud Run region when organizational policy or latency measurements require it.

## Create the Runtime Identity and Token

Create a dedicated service account if it does not exist:

```sh
SERVICE_ACCOUNT_EMAIL="$SERVICE_ACCOUNT@$PROJECT_ID.iam.gserviceaccount.com"

gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" >/dev/null 2>&1 || \
  gcloud iam service-accounts create "$SERVICE_ACCOUNT" \
    --display-name="Kaštan MCP Cloud Run runtime"
```

Create the Secret Manager secret if needed, generate a new token without placing it in shell history, and add it
as a secret version:

```sh
gcloud secrets describe "$SECRET" >/dev/null 2>&1 || \
  gcloud secrets create "$SECRET" --replication-policy=automatic

TOKEN="$(openssl rand -hex 32)"
printf '%s' "$TOKEN" | gcloud secrets versions add "$SECRET" --data-file=-
```

Store `TOKEN` in the MCP client's password manager or protected environment now. It cannot be recovered from
Secret Manager in environments where the operator lacks secret-access permission, and it must never be committed
to the repository.

Permit only the runtime service account to read the secret:

```sh
gcloud secrets add-iam-policy-binding "$SECRET" \
  --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
  --role="roles/secretmanager.secretAccessor"
```

## Deploy the Service

Deploy the container with platform IAM invocation left public because generic MCP clients do not acquire Google
identity tokens. Kaštan's Bearer validator remains the access-control boundary for `/mcp`.

```sh
gcloud run deploy "$SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --image="$IMAGE" \
  --service-account="$SERVICE_ACCOUNT_EMAIL" \
  --allow-unauthenticated \
  --port=8080 \
  --set-env-vars="KASTAN_MCP_TRANSPORT=http,KASTAN_MCP_HOST=0.0.0.0,KASTAN_MCP_REQUESTS_PER_MINUTE=60" \
  --set-secrets="KASTAN_MCP_BEARER_TOKEN=$SECRET:latest" \
  --cpu=1 \
  --memory=512Mi \
  --concurrency=4 \
  --min=0 \
  --max=1 \
  --timeout=120s
```

Cloud Run resolves an image tag to an immutable digest for the new revision. Repeat the deployment command to
roll out another image or a rotated secret version. Change `IMAGE` explicitly when adopting a newer release.

Read the assigned base URL:

```sh
SERVICE_URL="$(gcloud run services describe "$SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --format='value(status.url)')"
printf '%s\n' "$SERVICE_URL"
```

## Verify Authentication and MCP

The health check must succeed without credentials, while the MCP endpoint must reject an unauthenticated request:

```sh
curl --fail --silent --show-error "$SERVICE_URL/health"

test "$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --header 'Accept: application/json, text/event-stream' \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"cloud-run-check","version":"1.0"}}}' \
  "$SERVICE_URL/mcp")" = 401
```

Then initialize MCP with the token kept in the current shell:

```sh
curl --fail --silent --show-error \
  --header "Authorization: Bearer $TOKEN" \
  --header 'Content-Type: application/json' \
  --header 'Accept: application/json, text/event-stream' \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"cloud-run-check","version":"1.0"}}}' \
  "$SERVICE_URL/mcp"
```

Configure the remote MCP client with `$SERVICE_URL/mcp` and the same Bearer token. The
[MCP guide](mcp-server.md#remote-streamable-http) shows the generic client shape.

## Operate and Rotate

Read recent logs without exposing the token:

```sh
gcloud run services logs read "$SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --limit=50
```

To rotate the credential, generate and add another secret version, store the new value in the client, and deploy
a new Cloud Run revision with the same deployment command:

```sh
TOKEN="$(openssl rand -hex 32)"
printf '%s' "$TOKEN" | gcloud secrets versions add "$SECRET" --data-file=-
```

The previous token stops working once all traffic reaches the new revision. Disable superseded secret versions
after verifying the new client configuration.

## Remove the Deployment

Delete the service to stop serving requests, then remove its secret and dedicated identity when they are no
longer needed:

```sh
gcloud run services delete "$SERVICE" --project="$PROJECT_ID" --region="$REGION"
gcloud secrets delete "$SECRET" --project="$PROJECT_ID"
gcloud iam service-accounts delete "$SERVICE_ACCOUNT_EMAIL" --project="$PROJECT_ID"
```
