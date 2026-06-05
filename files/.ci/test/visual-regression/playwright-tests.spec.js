/**
 * Visual Regression Testing with Playwright
 *
 * This script takes screenshots of both reference and test environments and compares them.
 * We use a two-step approach in each test:
 * 1. First capture the reference site (DEV)
 * 2. Then capture the test site (MULTIDEV)
 * 3. Save both for side-by-side comparisons
 *
 * AUTHENTICATED ROUTES
 * --------------------
 * Routes that require a logged-in user are supported via an optional `auth`
 * block in test_routes.json plus an `auth` flag on the routes that need it.
 * Anonymous routes are unaffected — if you don't add an `auth` block, nothing
 * about the existing behavior changes.
 *
 *   {
 *     "auth": {
 *       "loginUrl": "/user/login",            // default: /user/login
 *       "preFormSelector": ".show-login",     // optional: click to reveal the
 *                                             //   fields (some themes hide the
 *                                             //   login form behind a button)
 *       "usernameSelector": "input[name=name]", // Drupal core defaults
 *       "passwordSelector": "input[name=pass]",
 *       "submitSelector": "#edit-submit",
 *       "successSelector": "body.user-logged-in" // optional post-login wait
 *     },
 *     "routes": {
 *       "HomePage": "/",                        // string  → anonymous
 *       "Dashboard": { "url": "/dashboard", "auth": true } // object → logged in
 *     }
 *   }
 *
 * IMPORTANT: credentials are NEVER stored in test_routes.json (it is committed
 * to the repo). The username and password are read only from environment
 * variables — VRT_USERNAME and VRT_PASSWORD by default. Set these in the
 * CircleCI project/context settings. To use different env var names, add
 * "usernameEnv"/"passwordEnv" to the auth block (the *names*, not the values).
 *
 * The login is performed once per environment (DEV and MULTIDEV are separate
 * domains, so each gets its own session) and the resulting cookies are reused
 * across every authenticated route/viewport.
 */
const { test, expect } = require("@playwright/test");
const fs = require("fs");
const path = require("path");

// Set up environment variables with defaults
const ENV = {
  // Testing URL - try to get from environment variables or use Lando URL
  TESTING_URL: process.env.DEV_SITE_URL || "http://localhost:3000",
  // Artifacts directory for saving screenshots
  ARTIFACTS_DIR: process.env.ARTIFACTS_DIR || path.join(process.cwd(), "test-results"),
  // CI info
  CI_BUILD_URL: process.env.CI_BUILD_URL || "local-build",
  CI_PROJECT_USERNAME: process.env.CI_PROJECT_USERNAME || "local-user",
  CI_PROJECT_REPONAME:
    process.env.CI_PROJECT_REPONAME ||
    process.env.LANDO_APP_NAME ||
    "local-project",
  // Test configuration
  PERCY_TOKEN: process.env.PERCY_TOKEN || "",
  VISUAL_REGRESSION_ENABLED: process.env.VISUAL_REGRESSION_ENABLED !== "false",
  UPDATE_SNAPSHOTS: process.env.UPDATE_SNAPSHOTS === "true",
  RETRY_WITH_HIGHER_THRESHOLD:
    process.env.RETRY_WITH_HIGHER_THRESHOLD === "true",
  // SSL settings for local development
  IGNORE_HTTPS_ERRORS: process.env.IGNORE_HTTPS_ERRORS === "true" || true, // Always true for now
  // Timeout settings
  PAGE_LOAD_TIMEOUT: parseInt(process.env.PAGE_LOAD_TIMEOUT) || 60000,
  NAVIGATION_TIMEOUT: parseInt(process.env.NAVIGATION_TIMEOUT) || 30000,
};

const defaultMaxDiffPixelRatio = process.env.MAX_DIFF_PIXEL_RATIO
  ? parseFloat(process.env.MAX_DIFF_PIXEL_RATIO)
  : 0.02; // Default to 2% if not set
const retryMaxDiffPixelRatio = process.env.RETRY_MAX_DIFF_PIXEL_RATIO
  ? parseFloat(process.env.RETRY_MAX_DIFF_PIXEL_RATIO)
  : 0.04; // Default to 4% for retry if not set

// Configure Playwright to ignore HTTPS errors for local domains
process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";

// Ensure artifacts directory exists
if (!fs.existsSync(ENV.ARTIFACTS_DIR)) {
  fs.mkdirSync(ENV.ARTIFACTS_DIR, { recursive: true });
  console.log(`Created artifacts directory at: ${ENV.ARTIFACTS_DIR}`);
}

// Log the configuration ONCE per CI run, not once per worker × retry.
// Playwright spawns a fresh node process per worker (and on retry), so
// any unguarded top-level console.log fires N×retries times, flooding
// the CI log with duplicate "Test configuration / Loaded N routes"
// blocks between every test. We gate on a tmp marker file so only the
// first process in the CI run emits the diagnostics.
const STARTUP_LOG_MARKER = path.join(
  process.env.RUNNER_TEMP || process.env.TMPDIR || "/tmp",
  `pw-vr-startup-${process.env.CIRCLE_BUILD_NUM || process.ppid || "local"}.lock`
);
const SHOULD_LOG_STARTUP = (() => {
  try {
    fs.writeFileSync(STARTUP_LOG_MARKER, String(process.pid), { flag: "wx" });
    return true;
  } catch (_) {
    return false;
  }
})();

if (SHOULD_LOG_STARTUP) {
  console.log("Test configuration:");
  console.log(`Testing URL: ${ENV.TESTING_URL}`);
  console.log(`Artifacts directory: ${ENV.ARTIFACTS_DIR}`);
  console.log(`CI Build: ${ENV.CI_BUILD_URL}`);
  console.log(
    `Visual regression testing enabled: ${ENV.VISUAL_REGRESSION_ENABLED}`
  );
}

function resolveTestRoutesPath() {
  const candidateRoots = [
    process.env.TEST_ROUTES_PATH,
    process.env.CI_PROJECT_DIR,
    process.env.CIRCLE_WORKING_DIRECTORY,
    path.resolve(__dirname),
    process.cwd(),
  ].filter(Boolean);

  const normalizedRoots = Array.from(
    new Set(candidateRoots.map((candidate) => path.resolve(candidate)))
  );

  for (const root of normalizedRoots) {
    const projectTestRoutes = path.join(root, "test_routes.json");
    if (fs.existsSync(projectTestRoutes)) {
      return projectTestRoutes;
    }
  }

  // Try ascending from the current directory as a fallback.
  let currentDir = path.resolve(__dirname);
  for (let depth = 0; depth <= 6; depth++) {
    const testPath = path.join(currentDir, "test_routes.json");
    if (fs.existsSync(testPath)) {
      return testPath;
    }

    const parentDir = path.dirname(currentDir);
    if (parentDir === currentDir) {
      break;
    }
    currentDir = parentDir;
  }

  // Finally, look for the vendor fallback using any known root.
  for (const root of normalizedRoots) {
    const vendorTestRoutes = path.join(
      root,
      "vendor",
      "helloworlddevs",
      "pantheon-ci-tools",
      "files",
      "test_routes.json"
    );

    if (fs.existsSync(vendorTestRoutes)) {
      console.log(
        `Project test_routes.json not found. Falling back to vendor defaults at: ${vendorTestRoutes}`
      );
      return vendorTestRoutes;
    }
  }

  return null;
}

// Normalize a route entry into { name, url, auth }. A route value may be:
//   - a string path/URL                      → anonymous
//   - an object { url|path, auth }            → auth defaults to false
function normalizeRoute(name, value) {
  let raw;
  let auth = false;
  if (typeof value === "string") {
    raw = value;
  } else if (value && typeof value === "object") {
    raw = value.url || value.path || "/";
    auth = Boolean(value.auth);
  } else {
    return null;
  }
  const parsedUrl = new URL(
    raw.startsWith("http") ? raw : `http://example.com${raw}`
  );
  return { name, url: parsedUrl.pathname + parsedUrl.search, auth };
}

// Initialize test paths, hideSelectors, and auth config
let paths = [];
let hideSelectors = [];
let authConfig = null;

// Try to find and load test routes
try {
  const testRoutesPath = resolveTestRoutesPath();

  if (testRoutesPath) {
    if (SHOULD_LOG_STARTUP) {
      console.log(`Found test_routes.json at: ${testRoutesPath}`);
    }
    const routesData = JSON.parse(fs.readFileSync(testRoutesPath, "utf8"));

    hideSelectors = [];

    // The routes live under `routes` in the current schema; the legacy
    // format used the top-level object directly as the route map. `auth`
    // and `hideSelectors` are reserved keys and never treated as routes.
    const routeMap =
      routesData.routes && typeof routesData.routes === "object"
        ? routesData.routes
        : routesData;
    paths = Object.entries(routeMap)
      .filter(([key]) => key !== "hideSelectors" && key !== "auth")
      .map(([name, value]) => normalizeRoute(name, value))
      .filter(Boolean);

    if (routesData.auth && typeof routesData.auth === "object") {
      authConfig = routesData.auth;
    }

    if (routesData.hideSelectors && Array.isArray(routesData.hideSelectors)) {
      hideSelectors = routesData.hideSelectors;
    }

    if (SHOULD_LOG_STARTUP) {
      const authCount = paths.filter((p) => p.auth).length;
      console.log(
        `✅ Loaded ${paths.length} test routes (${authCount} authenticated, ${hideSelectors.length} hide selectors)`
      );
      if (authCount > 0 && !authConfig) {
        console.warn(
          "⚠️ Routes are marked auth:true but no top-level `auth` block was found in test_routes.json — those routes will be captured ANONYMOUSLY."
        );
      }
    }
  } else {
    if (SHOULD_LOG_STARTUP) {
      console.warn(
        "⚠️ No test_routes.json file found, using default test paths"
      );
    }
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

// NOTE: We used to have a preWarmCache(url) helper here that launched
// a separate chromium instance per route in beforeAll, navigated with
// `networkidle`, then tore it down — only for the real test to immediately
// `goto` the same URL with `networkidle` again. That paid the slow
// page-load cost twice per route (5–30s each on cold Pantheon multidevs),
// adding ~10–20 min to every run.
//
// Cache pre-warming is now handled at the bash level in `run-playwright`
// BEFORE any Playwright worker spins up: parallel curl against every
// route in test_routes.json across both DEV and MULTIDEV environments
// (8-way concurrency). That wakes Pantheon's appserver (the 30–60s
// cold-start tax) and pre-fills Varnish once, instead of paying it
// twice per route inside the test.

// Cache of logged-in storageState keyed by base URL. DEV and MULTIDEV are
// different domains/origins, so each environment gets its own session. We log
// in at most once per environment per worker and reuse the cookies for every
// authenticated route × viewport, instead of re-submitting the login form
// dozens of times.
const authStateCache = new Map();

// Perform a form login against `baseUrl` and return a Playwright storageState
// object (cookies + localStorage) that can be handed to newContext(). Result
// is memoized per baseUrl. Throws if credentials are missing so failures are
// loud rather than silently producing anonymous screenshots.
async function getAuthState(browser, baseUrl, auth) {
  if (authStateCache.has(baseUrl)) {
    return authStateCache.get(baseUrl);
  }

  const loginUrl = auth.loginUrl || "/user/login";
  const usernameSelector = auth.usernameSelector || "input[name=name]";
  const passwordSelector = auth.passwordSelector || "input[name=pass]";
  const submitSelector = auth.submitSelector || "#edit-submit";

  // Credentials are read ONLY from environment variables — never from the
  // committed test_routes.json. The config may rename which env vars to read
  // via `usernameEnv` / `passwordEnv`; defaults are VRT_USERNAME / VRT_PASSWORD.
  const usernameEnv = auth.usernameEnv || "VRT_USERNAME";
  const passwordEnv = auth.passwordEnv || "VRT_PASSWORD";
  const username = process.env[usernameEnv];
  const password = process.env[passwordEnv];

  if (!username || !password) {
    throw new Error(
      `Auth is required for one or more routes but credentials are missing. ` +
        `Set ${usernameEnv} and ${passwordEnv} as environment variables ` +
        `(e.g. in CircleCI project/context settings). ` +
        `Credentials are never read from test_routes.json.`
    );
  }

  process.stdout.write(`  → logging in at ${baseUrl}${loginUrl}\n`);
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
  try {
    const page = await ctx.newPage();
    // Use "load" (NOT "networkidle"): Drupal login pages routinely carry chat,
    // analytics or reCAPTCHA widgets that keep the network busy indefinitely,
    // so "networkidle" would burn the whole timeout for no benefit. "load"
    // still guarantees scripts ran — which matters because the credential
    // fields can be revealed by theme JS (see the toggle handling below).
    await page.goto(`${baseUrl}${loginUrl}`, {
      waitUntil: "load",
      timeout: 30000,
    });

    // Reveal the credential fields before filling. Some themes hide the form
    // behind a toggle (`preFormSelector`) — BUT also auto-expand it when
    // navigator.webdriver is true, which Playwright sets. In that case the
    // form is ALREADY open, and clicking the toggle would flip it CLOSED again
    // (the original timeout bug). So: only click the toggle when the username
    // field isn't already visible, and confirm visibility afterward.
    const usernameField = page.locator(usernameSelector).first();
    let fieldVisible = await usernameField.isVisible().catch(() => false);
    if (!fieldVisible && auth.preFormSelector) {
      await page
        .locator(auth.preFormSelector)
        .first()
        .click({ timeout: 15000 })
        .catch(() => {});
      fieldVisible = await usernameField
        .waitFor({ state: "visible", timeout: 15000 })
        .then(() => true)
        .catch(() => false);
    }
    if (!fieldVisible) {
      // Behaviors may have attached late; give the field one final chance to
      // appear (throws loudly if the selectors are genuinely wrong).
      await usernameField.waitFor({ state: "visible", timeout: 15000 });
    }

    await usernameField.fill(username);
    await page.locator(passwordSelector).first().fill(password);
    await Promise.all([
      page.waitForLoadState("load", { timeout: 30000 }).catch(() => {}),
      page.locator(submitSelector).first().click(),
    ]);
    if (auth.successSelector) {
      await page.waitForSelector(auth.successSelector, { timeout: 15000 });
    }
    const state = await ctx.storageState();
    authStateCache.set(baseUrl, state);
    return state;
  } finally {
    // Swallow close errors: if the surrounding test already timed out, the
    // context may be torn down out from under us, and a throw here would mask
    // the real failure.
    await ctx.close().catch(() => {});
  }
}

// Define test for each path
paths.forEach(({ name, url, auth: routeRequiresAuth }) => {
  test.describe(`Visual regression test for ${name}`, () => {
    // Test each viewport
    ["mobile", "tablet", "desktop"].forEach((viewport) => {
      test(`${name} should look the same on ${viewport}`, async ({
        context,
      }) => {
        // One concise in-flight progress line per test. Fires the moment
        // the test starts (not after completion) so the CI log shows
        // forward motion even while a 30s+ test is mid-screenshot.
        // `process.stdout.write` (not console.log) avoids the implicit
        // newline buffering that can hide output on some CI captures.
        // The "list" reporter adds the post-test result line separately.
        process.stdout.write(
          `  → ${name} on ${viewport}${routeRequiresAuth ? " [auth]" : ""}\n`
        );

        const viewportSizes = {
          mobile: { width: 320, height: 480 },
          tablet: { width: 1024, height: 768 },
          desktop: { width: 1920, height: 1080 },
        };

        // The URL to test varies based on the execution context
        // First run with --update-snapshots will use DEV_SITE_URL (reference)
        // Second run without the flag will use MULTIDEV_SITE_URL (test)
        const urlToTest = ENV.TESTING_URL;

        // For authenticated routes, establish (or reuse) a logged-in session
        // for THIS environment and seed the context with it. Anonymous routes
        // skip this entirely.
        const contextOptions = {
          javaScriptEnabled: true,
          ignoreHTTPSErrors: true,
        };
        if (routeRequiresAuth && authConfig) {
          contextOptions.storageState = await getAuthState(
            context.browser(),
            urlToTest,
            authConfig
          );
        }

        // Create a single page for testing/snapshot comparison
        const browserContext = await context
          .browser()
          .newContext(contextOptions);

        // Create a new page for testing
        const testPage = await browserContext.newPage();
        await testPage.setViewportSize(viewportSizes[viewport]);

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

        // Hide elements based on the selectors defined in test_routes.json
        if (hideSelectors && hideSelectors.length > 0) {
          const hideSelectorsCSS = hideSelectors
            .map(
              (selector) =>
                `${selector} { visibility: hidden !important; display: none !important; }`
            )
            .join("\n");

          await testPage.addStyleTag({
            content: hideSelectorsCSS,
          });
        } else {
          await testPage.addStyleTag({
            content: `
            .captcha-type-challenge--recaptcha {
              visibility: hidden !important;
              display: none !important;
            }
          `,
          });
        }

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

        // Wait for the network to actually settle after our scroll-up-down
        // pass. The scroll triggers IntersectionObserver-driven lazy image
        // loads, and goto()'s `networkidle` from earlier doesn't cover the
        // requests we just kicked off. Without this, the screenshot
        // stability loop fights against images still decoding/painting.
        try {
          await testPage.waitForLoadState("networkidle", { timeout: 10000 });
        } catch (_) {
          // Some pages keep a long-poll or analytics socket open and never
          // hit networkidle — that's fine, fall through to the stability
          // check which will tolerate it.
        }

        // Final stability delay (covers fonts swap, layout shift, etc.)
        await testPage.waitForTimeout(3000);

        await expect(testPage).toHaveScreenshot(
          `${name.replace(/ /g, "-")}-${viewport}.png`,
          {
            maxDiffPixelRatio: isRetry
              ? retryMaxDiffPixelRatio
              : defaultMaxDiffPixelRatio,
            threshold: 0.2, // Consistent color sensitivity, aligns with Playwright default
            fullPage: true, // Capture the full page, not just the viewport
            // Explicit per-call copies of the config-level defaults so a
            // future tweak to expect.toHaveScreenshot can't silently
            // un-stabilize captures. See playwright.config.js for the
            // rationale on each.
            animations: "disabled",
            caret: "hide",
          }
        );

        await testPage.close();
      });
    });
  });
});
