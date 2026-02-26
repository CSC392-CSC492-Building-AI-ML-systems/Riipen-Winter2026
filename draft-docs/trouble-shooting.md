> canvas.docker refused to connect.   
Try:                                                                                       

   Checking the connection                                                                    
   Checking the proxy and the firewall                                                        
   ERR_CONNECTION_REFUSED                                                                     
▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
✦ This usually happens because the Canvas Docker containers or the Dory proxy (which handles
  the canvas.docker name) stopped running or went to sleep.

  1. Check if Canvas is running
  In your terminal, run:


   1 docker ps
  Do you see the canvas-lms or web containers in the list? If not, you need to restart Canvas
  in your Canvas directory:
   1 # Usually something like:
   2 docker-compose up -d


  2. Check Dory (The Proxy)
  Since you are using canvas.docker, you are likely using Dory to map that name. If Dory is
  down, your browser won't know where to send the request.
  Try restarting Dory:


   1 # You might need sudo depending on your setup
   2 dory up

  3. Check your /etc/hosts
  If you aren't using Dory, check if canvas.docker is still in your hosts file:
   1 cat /etc/hosts | grep canvas.docker


  Quickest way to test:
  Can you still open http://canvas.docker in a normal browser tab?
   * If no: The problem is Canvas or its proxy (Dory) is down.
   * If yes: Then the problem is specifically with the tool's redirect.

