# Canvas Demo

This Sinatra app demonstrates the `lti-advantage` gem against a locally hosted Canvas instance.
It covers the full browser launch flow and, when the launch includes NRPS, renders the first roster page directly in the launch response.

This guide assumes:

- You are comfortable running a local Canvas stack outside this repository.
- You can sign in to Canvas as an admin.
- Your browser can open Canvas at `http://canvas.docker`.

## 0. Start a local Canvas instance

This repository does not provision Canvas for you. Run Canvas from a separate local checkout or Docker-based setup first, then return here once the LMS is reachable.

A workable local setup usually looks like this:

- Docker Engine is installed and running.
- You have a local Canvas LMS setup in another directory.
- Canvas is started from that directory with its normal startup command, commonly `docker compose up -d`.
- Your browser can reach the LMS at `http://canvas.docker`.

If your Canvas setup depends on Dory, start Dory before opening Canvas:

```bash
dory up
```

If you are not using Dory, add this host entry instead:

```text
127.0.0.1 canvas.docker
```

Before continuing, verify these basics:

1. `http://canvas.docker` opens in your browser.
2. You can log in as an admin user.
3. You can open `Admin -> Developer Keys`.
4. You have at least one course where the tool can be installed.

How this maps to the demo's `.env`:

- `LMS_BROWSER_URL` is usually `http://canvas.docker`.
- `LMS_ISSUER` is often different from the browser URL in local Docker setups. A common value is `http://127.0.0.1:3000`.
- `LMS_JWKS_URL` defaults to `http://127.0.0.1:3000/api/lti/security/jwks` through the demo app.
- `LMS_TOKEN_ENDPOINT` defaults to `http://canvas.docker/login/oauth2/token` through the demo app.

If your local Canvas stack uses different ports or hostnames, update `.env` to match your installation before configuring the tool.

## 1. Install gem dependencies

From the repository root:

```bash
bin/setup
```

## 2. Create a local `.env`

Copy the example file:

```bash
cp .env.example .env
```

Start with these values:

```dotenv
CLIENT_ID=replace-me-after-step-4
LTI_DEPLOYMENT_ID=replace-me-after-step-5

TOOL_HOST=127.0.0.1:4567
LMS_BROWSER_URL=http://canvas.docker
LMS_ISSUER=http://127.0.0.1:3000

# Optional only when your Canvas setup needs them.
# LMS_TOKEN_ENDPOINT=http://canvas.docker/login/oauth2/token
# LMS_TOKEN_AUDIENCE=http://canvas.docker/login/oauth2/token
```

Notes:

- `TOOL_HOST` is host and port only, without `http://`.
- `TOOL_HOST` must be reachable by the browser that opens Canvas.
- `LMS_BROWSER_URL` is the URL you type into the browser.
- `LMS_ISSUER` must match the `iss` claim Canvas sends in the launch. In many local Docker setups that is `http://127.0.0.1:3000`, even when the browser uses `http://canvas.docker`.
- The demo persists its tool private key at `tmp/demo-tool-private-key.pem` so the pasted JWK remains stable across restarts.

## 3. Start the demo app

From the repository root:

```bash
ruby demo/app.rb
```

Leave that process running.

Confirm the demo is serving its public JWK:

- Open `http://<TOOL_HOST>/lti/jwk` using the value from your `.env`
- You should see a single JWK JSON object

## 4. Create a Canvas developer key

In Canvas:

1. Open `Admin -> Developer Keys`.
2. Click `+ Developer Key`.
3. Choose `LTI Key`.
4. Use `Manual Entry`.
5. Fill in these fields using the same host and port you set in `TOOL_HOST`:

   - `Title`: `LTI Advantage Demo`
   - `Target Link URI`: `http://<TOOL_HOST>/lti/launch`
   - `OpenID Connect Initiation Url`: `http://<TOOL_HOST>/oidc/init`
   - `Redirect URIs`: `http://<TOOL_HOST>/lti/launch`
   - `JWKS Method`: `Public JWK`
   - `Public JWK`: paste the JSON from `http://<TOOL_HOST>/lti/jwk`

6. Add the `Course Navigation` placement so the tool appears in the course sidebar.
7. Save the key.
8. Turn the key `ON`.

After saving, Canvas shows a numeric client ID. Copy that value into `.env`:

```dotenv
CLIENT_ID=your-canvas-client-id
```

Why use `Public JWK` instead of `Public JWK URL`?

- Local Canvas setups often reject non-HTTPS JWK URLs during service token exchange.
- Pasting the JWK avoids that problem for local development.

## 5. Install the tool into a course

Developer keys are only templates. To actually launch the tool, install it into a course:

1. Open a Canvas course.
2. Go to `Settings -> Apps -> View App Configurations`.
3. Click `+ App`.
4. Set `Configuration Type` to `By Client ID`.
5. Paste the client ID from step 4.
6. Submit and install the app.

Once the app is installed, copy the Canvas deployment ID for that course deployment:

1. In `View App Configurations`, open the tool's action menu.
2. Choose `Deployment ID`.
3. Copy the deployment ID value.

Put that value into `.env`:

```dotenv
LTI_DEPLOYMENT_ID=your-canvas-deployment-id
```

Restart the demo app after changing `.env`.

## 6. Launch the tool from Canvas

1. Refresh the Canvas course page.
2. Click the `LTI Advantage Demo` item in the course navigation sidebar.
3. Canvas should initiate login at `/oidc/init` and then post the signed launch to `/lti/launch`.

If everything is configured correctly, the demo page shows:

- launch success
- the Canvas user ID from the launch
- the deployment ID
- summarized launch roles

If the launch includes the NRPS claim, the page also renders the first roster page inside Canvas.

## 7. Expected demo behavior

The demo currently exposes these routes:

- `/oidc/init` for login initiation
- `/lti/launch` for launch validation and result rendering
- `/lti/jwk` for a single pasted public JWK
- `/lti/jwks` for a JWKS payload

The old `/nrps/members` endpoint is intentionally disabled. The demo now fetches the first NRPS roster page during `/lti/launch` and embeds the result in the launch page.

## Troubleshooting

### `canvas.docker` does not open

Check the local Canvas stack first:

- Make sure the Canvas containers are running.
- If you use Dory, make sure it is running.
- If you do not use Dory, make sure `/etc/hosts` maps `canvas.docker` to `127.0.0.1`.

Example checks:

```bash
docker ps
```

```bash
dory up
```

### Launch validation fails with client or deployment errors

Check these values in `.env`:

- `CLIENT_ID` must match the Canvas developer key client ID.
- `LTI_DEPLOYMENT_ID` must match the deployment ID of the installed course app.

Restart the Sinatra app after updating either value.

### JWT verification fails

Usually this means one of these values is wrong:

- `LMS_ISSUER`
- `LMS_JWKS_URL`

`LMS_ISSUER` must match the launch token's `iss` claim exactly.

### The launch succeeds but no roster is shown

Possible causes:

- Canvas did not include the NRPS claim in this launch.
- Token exchange failed for the NRPS request.
- Your local Canvas setup needs `LMS_TOKEN_ENDPOINT` or `LMS_TOKEN_AUDIENCE` overrides in `.env`.

When NRPS is unavailable, the launch page shows either a message that the claim was missing or the service error returned by the gem.
