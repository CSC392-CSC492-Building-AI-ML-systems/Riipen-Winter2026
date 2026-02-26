import { test, expect } from '@playwright/test';

test.describe('LTI 1.3 Handshake', () => {
  test('OIDC Login Initiation should show validation error when missing parameters', async ({ page }) => {
    // Navigate to the OIDC init endpoint without params
    await page.goto('/oidc/init');

    // It should show a validation error (based on my_docs/test_setup.md)
    await expect(page.locator('body')).toContainText('Validation Error');
    await expect(page.locator('body')).toContainText('iss (issuer) is missing');
  });
});
