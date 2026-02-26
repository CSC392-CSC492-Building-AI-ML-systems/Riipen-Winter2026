import { PactV3, MatchersV3 } from '@pact-foundation/pact';
import path from 'path';

const provider = new PactV3({
  consumer: 'LtiTool',
  provider: 'CanvasLMS',
  dir: path.resolve(process.cwd(), 'pacts'),
});

describe('LTI OIDC Initiation Contract', () => {
  it('receives a valid OIDC initiation request', async () => {
    provider
      .given('a valid LTI registration exists')
      .uponReceiving('a request for OIDC login initiation')
      .withRequest({
        method: 'POST',
        path: '/oidc/init',
        body: {
          iss: MatchersV3.like('https://canvas.instructure.com'),
          login_hint: MatchersV3.like('12345'),
          target_link_uri: MatchersV3.like('http://localhost:4567/lti/launch'),
        },
      })
      .willRespondWith({
        status: 200,
        body: MatchersV3.like('<html>...</html>'), // Simplified
      });

    await provider.executeTest(async (mockServer) => {
      // In a real test, you'd use a client to call mockServer.url
      console.log(`Mock server running at: ${mockServer.url}`);
    });
  });
});
