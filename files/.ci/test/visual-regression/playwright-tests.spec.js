/**
 * Visual Regression Testing with Playwright
 *
 * This script takes screenshots of both reference and test environments and compares them.
 * We use a two-step approach in each test:
 * 1. First capture the reference site (DEV)
 * 2. Then capture the test site (MULTIDEV)
 * 3. Save both for side-by-side comparisons
 */
const { test, expect } = require("@playwright/test");
const fs = require("fs");
const path = require("path");

// Get environment variables
const testUrl = process.env.TESTING_URL;
// Set up environment variables with defaults
const ENV = {
  // Testing URL - try to get from environment variables or use Lando URL
  TESTING_URL: process.env.TESTING_URL || "http://localhost:3000",
  // Artifacts directory for saving screenshots
  ARTIFACTS_DIR: process.env.ARTIFACTS_DIR || path.join(process.cwd(), "test-results"),
  // CI info
  CI_BUILD_URL: process.env.CI_BUILD_URL || "local-build",
  CI_PROJECT_USERNAME: process.env.CI_PROJECT_USERNAME || "local-user",
  CI_PROJECT_REPONAME: process.env.CI_PROJECT_REPONAME || process.env.LANDO_APP_NAME || "local-project",
  // Test configuration
  PERCY_TOKEN: process.env.PERCY_TOKEN || "",
  VISUAL_REGRESSION_ENABLED: process.env.VISUAL_REGRESSION_ENABLED !== "false",
  UPDATE_SNAPSHOTS: process.env.UPDATE_SNAPSHOTS === "true",
  RETRY_WITH_HIGHER_THRESHOLD: process.env.RETRY_WITH_HIGHER_THRESHOLD === "true",
  // SSL settings for local development
  IGNORE_HTTPS_ERRORS: process.env.IGNORE_HTTPS_ERRORS === "true" || true, // Always true for now
  // Timeout settings
  PAGE_LOAD_TIMEOUT: parseInt(process.env.PAGE_LOAD_TIMEOUT) || 60000,
  NAVIGATION_TIMEOUT: parseInt(process.env.NAVIGATION_TIMEOUT) || 30000,
};

const defaultMaxDiffPixelRatio = process.env.MAX_DIFF_PIXEL_RATIO ? parseFloat(process.env.MAX_DIFF_PIXEL_RATIO) : 0.02; // Default to 2% if not set
const retryMaxDiffPixelRatio = process.env.RETRY_MAX_DIFF_PIXEL_RATIO ? parseFloat(process.env.RETRY_MAX_DIFF_PIXEL_RATIO) : 0.04; // Default to 4% for retry if not set

// Configure Playwright to ignore HTTPS errors for local domains
process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";

// Ensure artifacts directory exists
if (!fs.existsSync(ENV.ARTIFACTS_DIR)) {
  fs.mkdirSync(ENV.ARTIFACTS_DIR, { recursive: true });
  console.log(`Created artifacts directory at: ${ENV.ARTIFACTS_DIR}`);
}

// Log the configuration
console.log("Test configuration:");
console.log(`Testing URL: ${ENV.TESTING_URL}`);
console.log(`Artifacts directory: ${ENV.ARTIFACTS_DIR}`);
console.log(`CI Build: ${ENV.CI_BUILD_URL}`);
console.log(`Visual regression testing enabled: ${ENV.VISUAL_REGRESSION_ENABLED}`);

function findTestRoutesFile(startDir, maxDepth = 4) {
  let currentDir = startDir;
  let depth = 0;

  while (depth <= maxDepth) {
    const testPath = path.join(currentDir, "test_routes.json");

    if (fs.existsSync(testPath)) {
      return testPath;
    }

    const parentDir = path.dirname(currentDir);

    // Stop if we've reached the filesystem root
    if (parentDir === currentDir) {
      break;
    }

    currentDir = parentDir;
    depth++;
  }

  return null;
}

// Initialize test paths and hideSelectors array
let paths = [];
let hideSelectors = [];

// Try to find and load test routes
try {
  const testRoutesPath = findTestRoutesFile(__dirname, 4);

  if (testRoutesPath) {
    console.log(`Found test_routes.json at: ${testRoutesPath}`);
    const routesData = JSON.parse(fs.readFileSync(testRoutesPath, "utf8"));

    // Handle the new JSON structure with routes and hideSelectors
    // Using the global hideSelectors array - no let declaration here
    hideSelectors = [];
    
    if (routesData.routes && typeof routesData.routes === 'object') {
      // Use the routes object for test paths
      paths = Object.entries(routesData.routes).map(([name, url]) => {
        // Remove domain part if present, we only need the path
        const parsedUrl = new URL(url.startsWith("http") ? url : `http://example.com${url}`);
        return {
          name,
          url: parsedUrl.pathname + parsedUrl.search,
        };
      });
      console.log(`✅ Loaded ${paths.length} test routes from routes object`);
    } else {
      // Legacy format - directly use the JSON object as routes
      paths = Object.entries(routesData).map(([name, url]) => {
        // Remove domain part if present, we only need the path
        const parsedUrl = new URL(url.startsWith("http") ? url : `http://example.com${url}`);
        return {
          name,
          url: parsedUrl.pathname + parsedUrl.search,
        };
      });
      console.log(`✅ Loaded ${paths.length} test routes from legacy format`);
    }
    
    // Get hide selectors if available
    if (routesData.hideSelectors && Array.isArray(routesData.hideSelectors)) {
      hideSelectors = routesData.hideSelectors;
      console.log(`✅ Loaded ${hideSelectors.length} selectors to hide during testing`);
    }

    console.log(`✅ Loaded ${paths.length} test routes from ${testRoutesPath}`);
  } else {
    console.warn("⚠️ No test_routes.json file found, using default test paths");
    paths = [
      { name: "homepage", url: "/" },
      { name: "about", url: "/about" },
      { name: "contact", url: "/contact" },
    ];
  }
} catch (error) {
  console.error(`❌ Error reading test_routes.json: ${error.message}`);
  process.exit(1);
}

// Modules are already initialized at the top

// Create directory structure if it doesn't exist
function ensureDirectoryExists(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

// Create screenshots directory
const screenshotDir = path.join(process.cwd(), "screenshots");
ensureDirectoryExists(screenshotDir);

// Helper function to pre-warm cache by pinging URLs
async function preWarmCache(url) {
  // Using node-fetch to perform a simple GET request
  console.log(`Pre-warming cache for: ${url}`);
  try {
    // Create a simple browser context just for warming up the cache
    const browser = await require("playwright").chromium.launch();
    const warmupContext = await browser.newContext();
    const warmupPage = await warmupContext.newPage();

    // Navigate to the URL and wait for the page to load
    await warmupPage.goto(url, { waitUntil: "networkidle", timeout: 30000 });
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
      await preWarmCache(`${ENV.TESTING_URL}${url}`);
      // Add a delay to ensure caches are fully built
      await new Promise((resolve) => setTimeout(resolve, 2000));
    });

    // Test each viewport
    ["mobile", "tablet", "desktop"].forEach((viewport) => {
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
        const urlToTest = ENV.TESTING_URL;

        console.log(`Navigating to: ${urlToTest}${url}`);
        await testPage.goto(`${urlToTest}${url}`, {
          waitUntil: "networkidle",
          timeout: 30000, // Increase timeout for page load
        });
        await testPage.waitForSelector("body", { timeout: 15000 });
        await testPage.waitForTimeout(500); // Initial stability delay

        // Ensure content is loaded and visible by scrolling
        await testPage.locator("body").scrollIntoViewIfNeeded();
        await testPage.waitForTimeout(500); // Wait for scrolling to complete

        // Resize window slightly to trigger any responsive layout changes
        const originalViewport = viewportSizes[viewport];
        await testPage.setViewportSize({
          width: originalViewport.width - 5,
          height: originalViewport.height,
        });
        await testPage.waitForTimeout(500); // Let layout adjust

        // Restore original viewport size
        await testPage.setViewportSize(originalViewport);
        await testPage.waitForTimeout(500); // Final stabilization wait

        // When run with --update-snapshots, it creates reference images
        // Otherwise it compares against existing references
        // Use higher thresholds when retrying failed tests
        const isRetry = process.env.RETRY_WITH_HIGHER_THRESHOLD === "true";

        // Log whether we're doing a regular test or a retry with higher thresholds
        console.log(`${isRetry ? "RETRY with higher thresholds" : "Regular test"} for ${name} on ${viewport}`);
        
        // Hide elements based on the selectors defined in test_routes.json
        if (hideSelectors && hideSelectors.length > 0) {
          console.log(`Hiding ${hideSelectors.length} elements for visual testing`);
          
          // Create CSS to hide all specified selectors
          const hideSelectorsCSS = hideSelectors
            .map(selector => `${selector} { visibility: hidden !important; display: none !important; }`)
            .join('\n');
          
          // Apply the hiding CSS
          await testPage.addStyleTag({
            content: hideSelectorsCSS
          });
        } else {
          // Fallback to just hiding the recaptcha if no hideSelectors are defined
          await testPage.addStyleTag({
            content: `
            .captcha-type-challenge--recaptcha {
              visibility: hidden !important;
              display: none !important;
            }
          `,
          });
        }
        
        // Scroll the page up and down to trigger any scroll-based JavaScript events
        console.log(`Scrolling through page for ${name} on ${viewport} to trigger scroll events`);
        await testPage.evaluate(() => {
          return new Promise((resolve) => {
            // Get the full page height
            const pageHeight = document.body.scrollHeight;
            // Start at the top
            window.scrollTo(0, 0);
            
            // Scroll down slowly in increments
            let currentPosition = 0;
            const scrollStep = Math.min(500, pageHeight / 5); // Either 500px or 1/5 of page height
            
            function scrollDown() {
              if (currentPosition < pageHeight) {
                currentPosition += scrollStep;
                window.scrollTo(0, currentPosition);
                setTimeout(scrollDown, 100);
              } else {
                // Once at the bottom, scroll back up
                scrollUp();
              }
            }
            
            function scrollUp() {
              if (currentPosition > 0) {
                currentPosition -= scrollStep;
                window.scrollTo(0, currentPosition);
                setTimeout(scrollUp, 100);
              } else {
                // Finally scroll back to top and resolve
                window.scrollTo(0, 0);
                setTimeout(resolve, 300); // Short delay after finishing scroll
              }
            }
            
            // Start the scroll sequence
            setTimeout(scrollDown, 100);
          });
        });
        
        // Reset to top of page
        await testPage.evaluate(() => window.scrollTo(0, 0));
        
        // Add a delay to ensure all content is loaded before taking the screenshot
        await testPage.waitForTimeout(3000); // 3 second delay
        
        await expect(testPage).toHaveScreenshot(`${name.replace(/ /g, "-")}-${viewport}.png`, {
          maxDiffPixelRatio: isRetry ? retryMaxDiffPixelRatio : defaultMaxDiffPixelRatio,
          threshold: 0.2, // Consistent color sensitivity, aligns with Playwright default
          fullPage: true // Capture the full page, not just the viewport
        });

        // Close the test page
        await testPage.close();
      });
    });
  });
});
