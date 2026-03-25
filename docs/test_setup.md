## DO NOT USE FIREFOX.

## setting up canvas

sudo chmod -R 777 .
./script/docker_dev_setup.sh
./script/docker_dev_setup.sh
sudo vim /etc/hosts
127.0.0.1 canvas.docker
docker-compose restart web
docker exec -it canvas-lms-web-1 bash

open http://canvas.docker

## config the LTI in canvas
  1. Key Configuration Settings
  In the "Admin" -> "Developer Keys" -> "+ Developer Key" -> "LTI Key" page, set the
   following:
    * Method: Choose "Manual Entry" (it's easier to debug than "Enter URL").
    * Title: My Test Tool
    * Target Link URI: http://127.0.0.1:4567/lti/launch
    * OpenID Connect Initiation Url: http://127.0.0.1:4567/oidc/init
    * JWKS Method: Choose "Public JWK"
    * Public JWK: copy the JSON from http://127.0.0.1:4567/lti/jwk

  2. Redirect URIs
  In the Redirect URIs field (usually at the top of the form), you must put the final launch
  URL:
   * http://127.0.0.1:4567/lti/launch

   3. Why this matters for NRPS
    1. Canvas will reject an HTTP `Public JWK URL` during the NRPS token exchange with an
       `InsecureUriError`.
    2. Using a pasted `Public JWK` avoids that server-to-server HTTPS requirement for local
       Docker demos.

   4. After Saving (Crucial Step)
    1. Get the Client ID: Once you save the key, you will see a number under the "Details"
       column (e.g., 1000000000001). This is your Client ID.
    2. Update your environment: set `CLIENT_ID` to this number.
    3. Turn it "ON": Make sure the state of the Developer Key is toggled to ON.
    4. The demo now reuses a local dev key from `tmp/demo-tool-private-key.pem`, so the pasted
       JWK keeps working across restarts by default.
    5. If you want to override that key, set `TOOL_PRIVATE_KEY_PATH` or `TOOL_PRIVATE_KEY_PEM`.

## better long-term fix
  1. The best production-like setup is still serving the tool over HTTPS and switching Canvas
     back to `Public JWK URL`.
  2. For local Canvas Docker work, the pasted `Public JWK` is the simpler and more reliable fix.


   5. Deploying the Tool to a Course
  Developer Keys are just "blueprints." To actually use it:
   1. Go to a specific Course -> Settings -> Apps -> View App Configurations.
   2. Click + App.
   3. Configuration Type: By Client ID.
   4. Paste the Client ID you got from the Developer Key page.
   5. Click Submit and then Install.


## how to test the redirect
  1. Fix the Sidebar (easiest way to test)
  To make your tool show up in the left-hand sidebar, you need to tell Canvas that's where it
  belongs.
   1. Go back to Admin -> Developer Keys.
   2. Edit your LTI Key.
   3. Under LTI Advantage Services, look for Placements.
   4. Add "Course Navigation" to the placements list.
   5. Save the key.
   6. Go to your Course -> Settings -> Apps -> View App Configurations.
   7. Click the "cog" icon next to your tool and click Deployment ID (or just delete and re-add
      the app using the Client ID to refresh it).
   8. Refresh the course page; "My Test Tool" should appear in the sidebar.


## viewing the roster
  1. Launch the tool from the course sidebar.
  2. If the launch includes NRPS, the embedded tool page now renders the first roster page
     directly inside Canvas.
  3. You no longer need to open `/nrps/members` separately for the basic demo flow.
