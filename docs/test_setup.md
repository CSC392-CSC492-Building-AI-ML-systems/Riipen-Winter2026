# End-to-End Manual Testing Guide

This guide explains how to run the local Canvas LMS, start the Riipen LTI demo app, configure the LTI 1.3 tool in Canvas, and verify the working demo end to end.

- **Canvas LMS browser URL:** `http://canvas.docker`
- **Riipen demo tool URL:** `http://127.0.0.1:4567`
- **LTI launch path:** `http://127.0.0.1:4567/lti/launch`
- **OIDC initiation path:** `http://127.0.0.1:4567/oidc/init`
- **Tool JWK source:** `http://127.0.0.1:4567/lti/jwk`

## Browser note

Do **not** use Firefox for this local demo. Use Chrome, Edge, or another Chromium-based browser.

## What this test verifies

When the setup is working, launching the tool from Canvas should display:

1. **Successful LTI 1.3 launch**
2. **AGS capability** with an AGS read-only display
3. **NRPS roster data** for the course context

The working demo page should show:

- a successful launch message
- the Canvas deployment ID and launch roles
- AGS scopes and the Canvas `lineitems` endpoint
- either line item data or a message that no line items were returned
- an NRPS roster table with course members

## Prerequisites

Before starting, make sure you have:

- this repository available at `Riipen-Winter2026/`
- the Canvas LMS repository available locally at `canvas-lms/`
- Docker installed and working
- Ruby / Bundler installed to run `bundle install` and `bundle exec ruby demo/app.rb`

For Canvas installation details, use the local Canvas repo and the official Quick Start guide:

- local repo: `@canvas-lms/`
- upstream guide: <https://github.com/instructure/canvas-lms/wiki/Quick-Start>

## 1. Start local Canvas

From the `canvas-lms/` repository, follow the Canvas quick-start flow if your local instance is not already installed.

If you already have Canvas working locally, the most important thing for this demo is that the browser can open: http://canvas.docker


### 1.1 Ensure the hostname works

Make sure your hosts file includes: 127.0.0.1 canvas.docker


### 1.2 Confirm the Canvas issuer configuration

In `canvas-lms/config/security.yml`, the local issuer should be:

```yml
lti_iss: 'http://canvas.docker'
```

If you change this file, restart the Canvas web service before testing again.

### 1.3 Quick Canvas health check

Open `http://canvas.docker` in the browser.

If it does not load:

- verify the Canvas containers are running
- verify `canvas.docker` still resolves locally
- if you use Dory or another local proxy, make sure it is running

## 2. Start the Riipen demo app

From the `Riipen-Winter2026/` repository:

```bash
bundle install
pkill -f "ruby demo/app.rb" || true
CLIENT_ID="REPLACE_AFTER_CREATING_KEY" \
TOOL_HOST="127.0.0.1:4567" \
LMS_BROWSER_URL="http://canvas.docker" \
LMS_ISSUER="http://canvas.docker" \
LMS_TOKEN_ENDPOINT="http://canvas.docker/login/oauth2/token" \
LTI_DEPLOYMENT_ID="temporary-deployment-id" \
bundle exec ruby demo/app.rb
```

Notes:

- `TOOL_HOST` is host and port only, without `http://`.
- `LMS_BROWSER_URL` is the Canvas URL you open in the browser.
- `LMS_ISSUER` must match the `iss` claim Canvas sends in the launch token exactly.
- `CLIENT_ID` and `LTI_DEPLOYMENT_ID` will be replaced with the real Canvas values after the LTI key and course app are created.
- The demo app persists a reusable dev private key at: tmp/demo-tool-private-key.pem

This keeps the pasted JWK stable across restarts unless you delete that key file.

### 2.1 Verify the demo app is reachable

Open these in the browser:

http://127.0.0.1:4567/lti/jwk
http://127.0.0.1:4567/oidc/init

Expected behavior:

- `/lti/jwk` returns a JSON JWK object
- `/oidc/init` returns a validation-style error when opened directly, because Canvas normally supplies the launch parameters

### 2.2 Demo routes exposed by the app

The local demo app exposes these routes:

- `/oidc/init` for login initiation
- `/lti/launch` for launch validation and result rendering
- `/lti/jwk` for a single pasted public JWK
- `/lti/jwks` for a JWKS payload

## 3. Create a fresh Canvas LTI 1.3 developer key

In Canvas:

Admin -> Developer Keys -> + Developer Key -> LTI Key

Use a **fresh key** for testing. Do not reuse an older key that may still contain stale hostname values.

### 3.1 Recommended LTI key values

Use these exact values:

- **Title:** `Riipen Demo Tool`
- **Redirect URIs:** `http://127.0.0.1:4567/lti/launch`
- **Target Link URI:** `http://127.0.0.1:4567/lti/launch`
- **OpenID Connect Initiation URL:** `http://127.0.0.1:4567/oidc/init`
- **Domain (Under Additional Settings):** `127.0.0.1`

### 3.2 JWK configuration

Use a pasted **Public JWK**, not an HTTP JWK URL.

Copy the JSON from:

http://127.0.0.1:4567/lti/jwk

Then paste it into the Canvas key configuration JWK Method* -> Public JWK (not Public JWK URL).

Why this matters:

- for local Docker demos, Canvas may reject an HTTP `public_jwk_url` during token exchange
- using the pasted JWK avoids that issue and was the working configuration for the demo

### 3.3 Required scopes

Enable these scopes:

- `https://purl.imsglobal.org/spec/lti-ags/scope/lineitem`
- `https://purl.imsglobal.org/spec/lti-ags/scope/lineitem.readonly`
- `https://purl.imsglobal.org/spec/lti-ags/scope/score`
- `https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly`
- `https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly`

In Canvas, these may appear as permission checkboxes instead of raw IMS scope URLs. Make sure the following permissions are enabled:

- **Can create and view assignment data in the gradebook associated with the tool.**
  - maps to `https://purl.imsglobal.org/spec/lti-ags/scope/lineitem`
- **Can view assignment data in the gradebook associated with the tool.**
  - maps to `https://purl.imsglobal.org/spec/lti-ags/scope/lineitem.readonly`
- **Can create and update submission results for assignments associated with the tool.**
  - maps to `https://purl.imsglobal.org/spec/lti-ags/scope/score`
- **Can view submission data for assignments associated with the tool.**
  - maps to `https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly`
- **Can retrieve user data associated with the context the tool is installed in.**
  - maps to `https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly`

If Canvas shows both the JSON scopes and the checkbox labels, enable both consistently.

### 3.4 Placement

For the simplest working demo, make sure the tool supports **Course Navigation** placement.

### 3.5 Save and enable the key

After saving:

1. turn the key **On**
2. copy the generated **Client ID**

## 4. Install the tool in a course

In a created course:

Course -> Settings -> Apps

Then:

1. remove any old Riipen tool installs if they exist
2. click **+ App**
3. choose **Configuration Type: By Client ID**
4. paste the Client ID from the developer key
5. install the app

## 5. Get the Canvas deployment ID

Still in:

Course -> Settings -> Apps

Find the installed tool, click the gear icon, and copy the **Deployment ID**.

## 6. Restart the Riipen demo app with the real Canvas values

Now restart the tool using the real Client ID and Deployment ID:

```bash
pkill -f "ruby demo/app.rb" || true
CLIENT_ID="YOUR_CLIENT_ID" \
TOOL_HOST="127.0.0.1:4567" \
LMS_BROWSER_URL="http://canvas.docker" \
LMS_ISSUER="http://canvas.docker" \
LMS_TOKEN_ENDPOINT="http://canvas.docker/login/oauth2/token" \
LTI_DEPLOYMENT_ID="YOUR_DEPLOYMENT_ID" \
bundle exec ruby demo/app.rb
```

## 7. Launch and test the demo

In Canvas, open the course and click the tool from the left course navigation.

This is the easiest and most reliable launch path for the local demo.

## 8. Expected successful output

When everything is configured correctly, the embedded tool page should display:

### 8.1 Launch section

- `Launch successful`
- the launching user ID
- the Canvas deployment ID
- launch roles such as Instructor / Administrator

### 8.2 AGS section

- `Canvas granted AGS capability for this launch`
- a `Lineitems URL` pointing at Canvas
- granted AGS scopes

The AGS area may show either:

- one or more line items, or
- `No line items were returned for this launch context.`

Both outcomes still indicate a successful AGS read. The second case means Canvas returned an empty line item collection for that launch context.

### 8.3 NRPS section

- `NRPS roster`
- the Canvas course title
- a table of course members with user ID, name, email, roles, and status

## 9. Ways to test the project

The simplest working demo is the course-navigation launch. If you want to test the features more thoroughly, use the scenarios below.

### 9.1 Basic launch test

This is the minimum successful test.

Steps:

1. Start Canvas.
2. Start the Riipen demo app.
3. Create and enable the LTI key.
4. Install the tool in a course.
5. Launch the tool from the course navigation sidebar.

Expected result:

- the page shows `Launch successful`
- the page shows the deployment ID and launch roles
- the AGS section appears
- the NRPS section appears

### 9.2 NRPS roster demo

This is the clearest way to show the roster feature.

Steps:

1. In Canvas, go to the test course.
2. Open `People`.
3. Add at least one more user to the course if possible, or use an existing second user if your Canvas seed data already includes one.
4. Launch the tool again from course navigation.

Expected result:

- the `NRPS roster` section shows the course title
- the roster table lists one or more users
- each row includes user ID, name, email, roles, and status

### 9.3 AGS capability demo

This proves Canvas granted AGS access to the tool.

Steps:

1. Launch the tool from course navigation.
2. Look at the `AGS grade services` section.

Expected result:

- the page says `Canvas granted AGS capability for this launch`
- it shows a `Lineitems URL`
- it shows the granted AGS scopes

This proves the launch included AGS capability and that Canvas told the tool where AGS operations live.

### 9.4 AGS read demo with existing assignments

This is a standard setup but feel free to make any adjustments for testing.

Steps:

1. In Canvas, create one or more assignments in the test course.
2. Change the submission Type to use External Tool and set the External Tool URL to: http://127.0.0.1:4567/lti/launch, and optionally check the "Load This Tool In A New Tab"
3. Select a grading system, assign it to everyone, and save the assignments.
4. [Optionally] View the system as a student through the "View as Student" button on the top right of the screen to submit the assignment or launch the external tool as a student.
4. Relaunch the assignments page and the demo should either immediately show or click the "Load Test Assignment in a new window" to see the demo page.

Expected result:

- the description of the launch should match the role of the person opening the tool
- the AGS section still shows the scopes and `Lineitems URL`
- if Canvas returns matching line items for the launch context, they appear in the `Line items` table
- if Canvas returns none, the page may still show `No line items were returned for this launch context.`

Even an empty result is still a successful AGS read if the section renders without an AGS error.

## 10. Common issues and fixes

### `Invalid redirect_uri`

Cause: the Canvas key does not exactly match the tool host the app is using.

Fix: use these exact values everywhere for the tool:

- `http://127.0.0.1:4567/oidc/init`
- `http://127.0.0.1:4567/lti/launch`

### `Unknown platform issuer: http://canvas.docker`

Cause: the running Riipen app is not using the same issuer Canvas sends.

Fix:

- ensure `canvas-lms/config/security.yml` uses `lti_iss: 'http://canvas.docker'`
- restart the Riipen app with `LMS_ISSUER="http://canvas.docker"`

### `Host not permitted`

Cause: the local tool was launched with a custom hostname that Sinatra/Rack host authorization did not accept.

Fix: use `127.0.0.1:4567` for the demo tool URLs.

### `JWK Error: riipen.docker cannot be resolved to any address`

Cause: Canvas is still using a stale older developer key or course app install.

Fix:

- create a fresh LTI key using only `127.0.0.1`
- delete the old course app install
- reinstall by Client ID
- use the new deployment ID

### `canvas.docker` does not open

Cause: Canvas Docker services or local proxy/hosts configuration is not available.

Fix:

- confirm the Canvas containers are running
- confirm `127.0.0.1 canvas.docker` exists in your hosts file
- if you use Dory, make sure it is running

## 11. Stopping the services

To stop the Riipen demo app:

```bash
pkill -f "ruby demo/app.rb"
```

Canvas can be stopped using the normal Docker workflow from the `canvas-lms/` repository.
