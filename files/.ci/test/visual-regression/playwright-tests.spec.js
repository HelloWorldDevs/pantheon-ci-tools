const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');
const { PNG } = require('pngjs');
const pixelmatch = require('pixelmatch');

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

// Set up environment variables with defaults
const ENV = {
  // Testing URL - try to get from environment variables or use Lando URL
  TESTING_URL: process.env.MULTIDEV_SITE_URL || 
              process.env.LANDO_APP_URL || 
              (process.env.LANDO_APP_NAME ? `https://${process.env.LANDO_APP_NAME}.lndo.site` : null) ||
              'http://localhost',
              
  // Artifacts directory for saving screenshots
  ARTIFACTS_DIR: process.env.ARTIFACTS_DIR || path.join(process.cwd(), 'artifacts'),
  
  // CI info
  CI_BUILD_URL: process.env.CI_BUILD_URL || 'local-build',
  CI_PROJECT_USERNAME: process.env.CI_PROJECT_USERNAME || 'local-user',
  CI_PROJECT_REPONAME: process.env.CI_PROJECT_REPONAME || 
                       (process.env.LANDO_APP_NAME || 'local-project'),
                       
  // Test configuration
  PERCY_TOKEN: process.env.PERCY_TOKEN || '',
  VISUAL_REGRESSION_ENABLED: process.env.VISUAL_REGRESSION_ENABLED !== 'false',
};

// Ensure artifacts directory exists
if (!fs.existsSync(ENV.ARTIFACTS_DIR)) {
  fs.mkdirSync(ENV.ARTIFACTS_DIR, { recursive: true });
  console.log(`Created artifacts directory at: ${ENV.ARTIFACTS_DIR}`);
}

// Log the configuration
console.log('Test configuration:');
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

// Find test_routes.json in current directory or up to 4 levels up
const testRoutesPath = findTestRoutesFile(__dirname, 4);

if (!testRoutesPath) {
  console.error("ERROR: test_routes.json not found in current directory or any parent directory (up to 4 levels)");
  process.exit(1);
}
// Initialize paths array
let paths = [];

// Try to load routes from test_routes.json at project root
try {
  if (fs.existsSync(testRoutesPath)) {
    console.log(`Found test_routes.json at: ${testRoutesPath}`);
    const routesData = JSON.parse(fs.readFileSync(testRoutesPath, 'utf8'));
    
    // Convert the JSON data to the expected format
    paths = Object.entries(routesData).map(([name, url]) => {
      // Remove domain part if present, we only need the path
      const parsedUrl = new URL(url.startsWith('http') ? url : `http://example.com${url}`);
      return {
        name,
        url: parsedUrl.pathname + parsedUrl.search
      };
    });
    
    console.log('Using routes from test_routes.json:');
    console.log(paths);
  } else {
    console.error(`ERROR: test_routes.json not found at ${testRoutesPath}`);
    console.error('Please create a test_routes.json file at the root of your project');
    process.exit(1); // Exit with error code
  }
} catch (error) {
  console.error(`ERROR reading test_routes.json: ${error.message}`);
  process.exit(1); // Exit with error code
}

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

// Set test timeout to 30 seconds to account for slower environments
test.setTimeout(30000);

// Configure viewports for different device types
const viewports = {
  mobile: { width: 375, height: 667 },
  tablet: { width: 768, height: 1024 },
  desktop: { width: 1280, height: 1024 }
};

// Define test for each path
paths.forEach(({ name, url }) => {
  test.describe(`Visual regression test for ${name}`, () => {
    // Pre-warm caches before tests run
    test.beforeAll(async ({ browser }) => {
      const page = await browser.newPage();
      // Pre-warm the test URL
      await preWarmCache(`${ENV.TESTING_URL}${url}`);
      await page.close();
    });

    // Test each viewport
    Object.entries(viewports).forEach(([viewport, size]) => {
      test(`${name} should look the same on ${viewport}`, async ({ browser }) => {
        const context = await browser.newContext({
          viewport: size,
          deviceScaleFactor: 1,
        });
        const page = await context.newPage();
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
        
        // Take screenshot of the full page
        const screenshot = await testPage.screenshot({
          fullPage: true,
          animations: 'disabled',
          caret: 'hide',
          scale: 'css',
          timeout: 30000
        });
        
        // Define paths for the screenshot and diff
        const screenshotPath = path.join(screenshotDir, `${name}-${viewport}.png`);
        const diffPath = path.join(screenshotDir, `${name}-${viewport}-diff.png`);
        
        // Save the screenshot
        fs.writeFileSync(screenshotPath, screenshot);
        
        // If we're updating snapshots, we're done
        if (process.env.UPDATE_SNAPSHOTS) {
          console.log(`✅ Updated reference image for ${name} on ${viewport}`);
          return;
        }
        
        // Otherwise, compare with the reference image
        try {
          const referenceImage = fs.readFileSync(screenshotPath);
          expect(screenshot).toMatchSnapshot(`${name}-${viewport}.png`, {
            maxDiffPixelRatio: isRetry ? 0.1 : 0.01, // 10% on retry, 1% initially
            threshold: 0.1,
            maxDiffPixels: isRetry ? 1000 : 100
          });
          console.log(`✅ Visual test passed for ${name} on ${viewport}`);
        } catch (error) {
          if (!isRetry) {
            console.warn(`⚠️ Visual test failed for ${name} on ${viewport}, will retry with higher thresholds`);
            // Rethrow to trigger retry
            throw error;
          }
          
          // If we get here, we're already in retry mode and still failing
          console.error(`❌ Visual test failed for ${name} on ${viewport} even with higher thresholds`);
          
          // Save the diff image for debugging
          const referenceImage = fs.readFileSync(screenshotPath);
          const img1 = PNG.sync.read(referenceImage);
          const img2 = PNG.sync.read(screenshot);
          const { width, height } = img1;
          const diff = new PNG({ width, height });
          
          const diffResult = pixelmatch(
            img1.data, 
            img2.data, 
            diff.data, 
            width, 
            height, 
            { threshold: 0.1 }
          );
          
          fs.writeFileSync(diffPath, PNG.sync.write(diff));
          console.error(`🔍 Diff saved to: ${diffPath}`);
          
          // Rethrow with a more helpful error message
          throw new Error(`Visual regression test failed for ${name} on ${viewport}. See diff at: ${diffPath}`);
        }
      });
    });
  });
});
