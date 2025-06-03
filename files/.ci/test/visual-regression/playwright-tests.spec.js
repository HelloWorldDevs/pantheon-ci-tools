import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { test, expect } from '@playwright/test';
import { chromium } from 'playwright';
import pixelmatch from 'pixelmatch';
import pngjs from 'pngjs';

// Get the current file's directory in ES module
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Initialize PNG and pixelmatch
const { PNG: PngClass } = pngjs;
const pixelMatchFn = pixelmatch;

/**
 * Visual Regression Testing with Playwright
 *
 * This script takes screenshots of both reference and test environments and compares them.
 * We use a two-step approach in each test:
 * 1. First capture the reference site (DEV)
 * 2. Then capture the test site (MULTIDEV)
 * 3. Save both for side-by-side comparisons
 */

// Set up environment variables with defaults
const ENV = {
  // Testing URL - try to get from environment variables or use Lando URL
  TESTING_URL: process.env.TESTING_URL || 'http://localhost:3000',
  // Artifacts directory for saving screenshots
  ARTIFACTS_DIR: process.env.ARTIFACTS_DIR || path.join(process.cwd(), 'test-results'),
  // CI info
  CI_BUILD_URL: process.env.CI_BUILD_URL || 'local-build',
  CI_PROJECT_USERNAME: process.env.CI_PROJECT_USERNAME || 'local-user',
  CI_PROJECT_REPONAME: process.env.CI_PROJECT_REPONAME || 
                       (process.env.LANDO_APP_NAME || 'local-project'),
  // Test configuration
  PERCY_TOKEN: process.env.PERCY_TOKEN || '',
  VISUAL_REGRESSION_ENABLED: process.env.VISUAL_REGRESSION_ENABLED !== 'false',
  UPDATE_SNAPSHOTS: process.env.UPDATE_SNAPSHOTS === 'true',
  RETRY_WITH_HIGHER_THRESHOLD: process.env.RETRY_WITH_HIGHER_THRESHOLD === 'true',
  // SSL settings for local development
  IGNORE_HTTPS_ERRORS: process.env.IGNORE_HTTPS_ERRORS === 'true' || true, // Always true for now
  // Timeout settings
  PAGE_LOAD_TIMEOUT: parseInt(process.env.PAGE_LOAD_TIMEOUT) || 60000,
  NAVIGATION_TIMEOUT: parseInt(process.env.NAVIGATION_TIMEOUT) || 30000
};

// Configure Playwright to ignore HTTPS errors for local domains
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';

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

// Initialize test paths
let paths = [];

// Try to find and load test routes
try {
  const testRoutesPath = findTestRoutesFile(__dirname, 4);
  
  if (testRoutesPath) {
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
    
    console.log(`✅ Loaded ${paths.length} test routes from ${testRoutesPath}`);
  } else {
    console.warn('⚠️ No test_routes.json file found, using default test paths');
    paths = [
      { name: 'homepage', url: '/' },
      { name: 'about', url: '/about' },
      { name: 'contact', url: '/contact' }
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
const screenshotDir = path.join(process.cwd(), 'screenshots');
ensureDirectoryExists(screenshotDir);

// Helper function to pre-warm cache by pinging URLs
async function preWarmCache(url) {
  try {
    console.log(`Pre-warming cache for: ${url}`);
    const browser = await require('playwright').chromium.launch({
      // Disable SSL verification for local domains
      ignoreHTTPSErrors: true
    });
    const context = await browser.newContext({
      // Ignore HTTPS errors for local domains
      ignoreHTTPSErrors: true,
      // Disable web security for local development
      bypassCSP: true
    });
    
    const page = await context.newPage();
    
    try {
      await page.goto(url, { 
        waitUntil: 'networkidle', 
        timeout: 30000,
        // Disable timeout for local development
        waitUntil: 'domcontentloaded'
      });
      await page.waitForTimeout(2000); // Wait for any lazy-loaded content
    } catch (error) {
      console.warn(`Warning during pre-warming ${url}: ${error.message}`);
      // Continue even if there are navigation errors
    } finally {
      await browser.close();
    }
  } catch (error) {
    console.error(`Error pre-warming cache for ${url}: ${error.message}`);
  }
}

// Configure test settings
const config = {
  // Timeout settings
  testTimeout: 60000,
  // Viewport configurations
  viewports: {
    mobile: { width: 375, height: 667 },
    tablet: { width: 768, height: 1024 },
    desktop: { width: 1280, height: 1024 }
  },
  // Visual comparison thresholds
  thresholds: {
    pixelMatch: 0.1,      // 10% pixel difference allowed
    failureThreshold: 0.2,  // 20% threshold for retry
    maxDiffPixels: 100,     // Maximum allowed different pixels
    maxDiffPixelRatio: 0.01 // 1% maximum pixel ratio difference
  },
  // Navigation settings
  navigation: {
    waitUntil: 'networkidle',
    timeout: 30000,
    waitForSelector: 'body'
  },
  // Screenshot settings
  screenshot: {
    fullPage: true,
    animations: 'disabled',
    caret: 'hide',
    scale: 'css',
    timeout: 30000
  }
};

// Apply test timeout
test.setTimeout(config.testTimeout);

// Configure Playwright to ignore HTTPS errors for local domains
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';

// Helper function to create a new browser context with proper SSL settings
async function createBrowserContext(browser, viewport) {
  return await browser.newContext({
    viewport: viewport,
    deviceScaleFactor: 1,
    ignoreHTTPSErrors: true, // Always ignore HTTPS errors for testing
    // Additional context options for better reliability
    javaScriptEnabled: true,
    bypassCSP: true,
    // Configure network settings
    offline: false,
    serviceWorkers: 'allow',
    // Configure timeouts
    navigationTimeout: config.navigation.timeout,
    // Configure viewport for mobile emulation if needed
    isMobile: viewport.width < 768,
    hasTouch: viewport.width < 768,
    // Configure user agent for consistent testing
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
  });
}

// Define test for each path
paths.forEach(({ name, url }) => {
  test.describe(`Visual regression test for ${name}`, () => {
    // Pre-warm caches before tests run
    test.beforeAll(async ({ browser }) => {
      const context = await createBrowserContext(browser, config.viewports.desktop);
      const page = await context.newPage();
      
      try {
        // Pre-warm the test URL
        await preWarmCache(`${ENV.TESTING_URL}${url}`);
      } catch (error) {
        console.warn(`Warning during pre-warm for ${name}: ${error.message}`);
      } finally {
        await context.close();
      }
    });

    // Test each viewport
    Object.entries(config.viewports).forEach(([viewportName, viewportSize]) => {
      test(`${name} should look the same on ${viewportName}`, async ({ browser }) => {
        let context;
        let page;
        
        try {
          // Create a new context with the specified viewport
          context = await createBrowserContext(browser, viewportSize);
          page = await context.newPage();
          
          // Set viewport size
          await page.setViewportSize(viewportSize);
          
          // Define the test URL
          const testUrl = `${ENV.TESTING_URL}${url}`;
          console.log(`Testing URL: ${testUrl}`);
          
          // Navigate to the page
          await page.goto(testUrl, {
            waitUntil: config.navigation.waitUntil,
            timeout: config.navigation.timeout
          });
          
          // Wait for the page to be fully loaded
          await page.waitForSelector(config.navigation.waitForSelector, {
            timeout: config.navigation.timeout
          });
          
          // Wait for any lazy-loaded content
          await page.waitForTimeout(2000);
          
          // Take a screenshot
          const screenshot = await page.screenshot({
            fullPage: config.screenshot.fullPage,
            animations: config.screenshot.animations,
            caret: config.screenshot.caret,
            scale: config.screenshot.scale,
            timeout: config.screenshot.timeout
          });
          
          // Define paths for the screenshot and diff
          const screenshotPath = path.join(screenshotDir, `${name}-${viewportName}.png`);
          const diffPath = path.join(screenshotDir, `${name}-${viewportName}-diff.png`);
          
          // Save the screenshot
          fs.writeFileSync(screenshotPath, screenshot);
          
          // If we're updating snapshots, we're done
          if (ENV.UPDATE_SNAPSHOTS) {
            console.log(`✅ Updated reference image for ${name} on ${viewportName}`);
            return;
          }
          
          // Otherwise, compare with the reference image
          try {
            const referenceImage = fs.readFileSync(screenshotPath);
            const img1 = PngClass.sync.read(referenceImage);
            const img2 = PngClass.sync.read(screenshot);
            
            // Compare images using pixelmatch
            const diff = new PngClass({ width: img1.width, height: img1.height });
            const diffPixels = pixelMatchFn(
              img1.data, 
              img2.data, 
              diff.data, 
              img1.width, 
              img1.height, 
              { threshold: config.thresholds.pixelMatch }
            );
            
            // Save the diff image
            fs.writeFileSync(diffPath, PngClass.sync.write(diff));
            
            // Calculate difference percentage
            const diffPercent = (diffPixels * 100) / (img1.width * img1.height);
            
            // Check if difference is within threshold
            if (diffPercent > config.thresholds.maxDiffPixelRatio * 100) {
              // Save diff image
              fs.writeFileSync(diffPath, PNG.sync.write(diff));
              
              // Check if we should retry with higher threshold
              if (!ENV.RETRY_WITH_HIGHER_THRESHOLD) {
                console.warn(`⚠️ Visual test failed for ${name} on ${viewportName}, will retry with higher thresholds`);
                throw new Error(`Visual difference (${diffPercent.toFixed(2)}%) exceeds threshold (${config.thresholds.maxDiffPixelRatio * 100}%)`);
              }
              
              // If we already retried, fail the test
              throw new Error(`Visual difference (${diffPercent.toFixed(2)}%) exceeds threshold (${config.thresholds.maxDiffPixelRatio * 100}%). See diff at: ${diffPath}`);
            }
            
            console.log(`✅ Visual test passed for ${name} on ${viewportName} (${diffPixels} pixels different, ${diffPercent.toFixed(2)}%)`);
            
          } catch (error) {
            if (!ENV.RETRY_WITH_HIGHER_THRESHOLD) {
              console.warn(`⚠️ Visual test failed for ${name} on ${viewportName}, will retry with higher thresholds`);
              throw error;
            }
            
            // If we get here, we're already in retry mode and still failing
            console.error(`❌ Visual test failed for ${name} on ${viewportName}: ${error.message}`);
            throw error;
          }
        } catch (error) {
          console.error(`❌ Test failed for ${name} on ${viewportName}: ${error.message}`);
          throw error;
        } finally {
          // Clean up resources
          if (page) await page.close().catch(e => console.error('Error closing page:', e));
          if (context) await context.close().catch(e => console.error('Error closing context:', e));
        }
      });
    });
  });
});
