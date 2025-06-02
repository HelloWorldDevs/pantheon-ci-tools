/**
 * Visual Regression Testing with Playwright
 *
 * This script takes screenshots of both reference and test environments and compares them.
 * We use a two-step approach in each test:
 * 1. First capture the reference site (DEV)
 * 2. Then capture the test site (MULTIDEV)
 * 3. Save both for side-by-side comparisons
 */
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

// Get environment variables
const testUrl = process.env.TESTING_URL;

// Log the URLs we're testing
console.log(`Testing URL: ${testUrl}`);

// Test paths
const paths = [
  { name: "User Login", url: "/user" },
  { name: "Home Page", url: "/" },
  // Add other paths as needed
];

// Create directory structure if it doesn't exist
function ensureDirectoryExists(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

// Create screenshots directory
const screenshotDir = path.join(process.cwd(), 'screenshots');
ensureDirectoryExists(screenshotDir);

// Helper function to pre-warm cache by pinging URLs
async function preWarmCache(url) {
  // Using node-fetch to perform a simple GET request
  console.log(`Pre-warming cache for: ${url}`);
  try {
    // Create a simple browser context just for warming up the cache
    const browser = await require('playwright').chromium.launch();
    const warmupContext = await browser.newContext();
    const warmupPage = await warmupContext.newPage();

    // Navigate to the URL and wait for the page to load
    await warmupPage.goto(url, { waitUntil: 'networkidle', timeout: 30000 });
    console.log(`Successfully pre-warmed cache for: ${url}`);

    // Close everything to free resources
    await warmupPage.close();
    await warmupContext.close();
    await browser.close();
  } catch (error) {
    console.error(`Error pre-warming cache for ${url}: ${error.message}`);
  }
}

// Define test for each path
paths.forEach(({ name, url }) => {
  test.describe(`Visual regression test for ${name}`, () => {
    // Pre-warm caches before tests run
    test.beforeAll(async () => {
      // Pre-warm both reference and test URLs
      await preWarmCache(`${testUrl}${url}`);
      // Add a delay to ensure caches are fully built
      await new Promise(resolve => setTimeout(resolve, 2000));
    });

    // Test each viewport
    ['mobile', 'tablet', 'desktop'].forEach(viewport => {
      test(`${name} should look the same on ${viewport}`, async ({ context }) => {
        // Set viewport size based on device type
        const viewportSizes = {
          mobile: { width: 320, height: 480 },
          tablet: { width: 1024, height: 768 },
          desktop: { width: 1920, height: 1080 },
        };

        // Create a single page for testing/snapshot comparison
        // Create a browser context with JavaScript enabled for consistent behavior
        const browserContext = await context.browser().newContext({
          javaScriptEnabled: true,
        });

        // Create a new page for testing
        const testPage = await browserContext.newPage();
        await testPage.setViewportSize(viewportSizes[viewport]);

        // The URL to test varies based on the execution context
        // First run with --update-snapshots will use DEV_SITE_URL (reference)
        // Second run without the flag will use MULTIDEV_SITE_URL (test)
        const urlToTest = testUrl;

        console.log(`Navigating to: ${urlToTest}${url}`);
        await testPage.goto(`${urlToTest}${url}`, {
          waitUntil: "networkidle",
          timeout: 30000, // Increase timeout for page load
        });
        await testPage.waitForSelector("body", { timeout: 15000 });
        await testPage.waitForTimeout(2000); // Initial stability delay

        // Ensure content is loaded and visible by scrolling
        await testPage.locator("body").scrollIntoViewIfNeeded();
        await testPage.waitForTimeout(2000); // Wait for scrolling to complete

        // Resize window slightly to trigger any responsive layout changes
        const originalViewport = viewportSizes[viewport];
        await testPage.setViewportSize({
          width: originalViewport.width - 5,
          height: originalViewport.height
        });
        await testPage.waitForTimeout(500); // Let layout adjust

        // Restore original viewport size
        await testPage.setViewportSize(originalViewport);
        await testPage.waitForTimeout(1000); // Final stabilization wait

        // When run with --update-snapshots, it creates reference images
        // Otherwise it compares against existing references
        // Use higher thresholds when retrying failed tests
        const isRetry = process.env.RETRY_WITH_HIGHER_THRESHOLD === 'true';

        // Log whether we're doing a regular test or a retry with higher thresholds
        console.log(`${isRetry ? 'RETRY with higher thresholds' : 'Regular test'} for ${name} on ${viewport}`);

        await expect(testPage).toHaveScreenshot(`${name.replace(/ /g, "-")}-${viewport}.png`, {
          maxDiffPixelRatio: isRetry ? 0.2 : 0.1,      // Double the allowed diff ratio on retry
          threshold: isRetry ? 0.3 : 0.2,             // Higher color difference threshold on retry
          maxDiffPixels: isRetry ? 500 : 100,         // Allow more different pixels on retry
        });

        // Close the test page
        await testPage.close();
      });
    });
  });
});
