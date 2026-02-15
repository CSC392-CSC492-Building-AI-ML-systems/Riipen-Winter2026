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
   * JWKS Method: Choose "Public JWK URL"
   * Public JWK URL: http://127.0.0.1:4567/lti/jwks

  2. Redirect URIs
  In the Redirect URIs field (usually at the top of the form), you must put the final launch
  URL:
   * http://127.0.0.1:4567/lti/launch


