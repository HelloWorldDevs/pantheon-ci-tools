// @ts-check
import { defineConfig } from '@playwright/test';

/**
 * @see https://playwright.dev/docs/test-configuration
 */
export default defineConfig({
  testDir: './',
  testMatch: '*tests.spec.js',
  /* Maximum time one test can run for */
  timeout: 60 * 1000,
  expect: {
    /**
     * Maximum time expect() should wait for the condition to be met
     */
    timeout: 10000,
    toHaveScreenshot: {
      maxDiffPixelRatio: 0.1, // 10% threshold for differences
      threshold: 0.2,
    },
    toMatchSnapshot: {
      maxDiffPixelRatio: 0.1, // 10% threshold for differences
      threshold: 0.2,
      // Allow for small dimension differences that don't affect functionality
      maxDiffPixels: 100,
    },
  },
  /* Run tests in files in parallel */
  fullyParallel: true,
  /* Fail the build on CI if you accidentally left test.only in the source code. */
  forbidOnly: !!process.env.CI,
  /* Retry failed tests in CI */
  retries: process.env.CI ? 1 : 0,
  /* Reporter to use */
  reporter: [
    ['html', { outputFolder: 'playwright-report' }],
    ['junit', { outputFile: 'test-results/junit.xml' }]
  ],
  /* Configure projects for major browsers */
  projects: [
    {
      name: 'chromium',
      use: {
        launchOptions: {
          args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-font-subpixel-positioning',
            '--disable-font-antialiasing',
            '--disable-lcd-text'
          ],
        },
      },
    },
  ],
});
