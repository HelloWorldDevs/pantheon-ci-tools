// @ts-check
const { defineConfig } = require("@playwright/test");

/**
 * @see https://playwright.dev/docs/test-configuration
 */
module.exports = defineConfig({
  testDir: "./",
  testMatch: "*tests.spec.js",
  /* Maximum time one test can run for */
  timeout: 60 * 1000,
  expect: {
    /**
     * Default expect() timeout. toHaveScreenshot needs its own larger
     * budget (see below) — fullPage screenshots have to converge a
     * stability loop (take screenshot, wait 100ms, take again, diff,
     * repeat until two consecutive captures match). 10s isn't enough
     * for content-rich Drupal pages with lazy-loaded images, especially
     * when we're not pre-warming the cache.
     */
    timeout: 10000,
    toHaveScreenshot: {
      maxDiffPixelRatio: 0.02, // 2% threshold for differences
      // Per-assertion timeout for the stability loop. 30s is the
      // Playwright-recommended floor for fullPage screenshots in CI.
      timeout: 30000,
      // Defense against false-positive stability churn:
      //  - animations: 'disabled' prevents CSS transitions from
      //    advancing between the two stability captures.
      //  - caret: 'hide' prevents the text-input blinking caret from
      //    flipping state between captures on forms.
      animations: "disabled",
      caret: "hide",
    },
    toMatchSnapshot: {
      maxDiffPixelRatio: 0.02, // 2% threshold for differences
      maxDiffPixels: 100,
    },
  },
  /* Run tests in files in parallel */
  fullyParallel: true,
  /* Worker count. Default CircleCI runner (medium) is 2 vCPU/4GB RAM —
   * 2 workers halves wall time without OOM on full-page screenshots.
   * If you bump the resource_class to large+ you can safely raise this. */
  workers: process.env.PLAYWRIGHT_WORKERS
    ? parseInt(process.env.PLAYWRIGHT_WORKERS, 10)
    : process.env.CI
    ? 2
    : undefined,
  /* Fail the build on CI if you accidentally left test.only in the source code. */
  forbidOnly: !!process.env.CI,
  /* Retry failed tests in CI */
  retries: process.env.CI ? 1 : 0,
  /* Reporters.
   *
   * `list` MUST be included or Playwright runs silent on stdout between
   * worker startup and test completion. When you set `reporter` in
   * config you replace ALL defaults — without an explicit stdout
   * reporter here you get no progress markers, no pass/fail lines,
   * nothing to tell you the suite is alive. `list` prints one line per
   * test result with a status icon + duration, which is what the old
   * `×F·` markers in the CI log were doing for us implicitly. */
  reporter: [
    ["list"],
    ["html", { outputFolder: "playwright-report" }],
    ["junit", { outputFile: "test-results/junit.xml" }],
  ],
  /* Configure projects for major browsers */
  projects: [
    {
      name: "chromium",
      use: {
        launchOptions: {
          args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-font-subpixel-positioning", "--disable-font-antialiasing", "--disable-lcd-text"],
        },
      },
    },
  ],
});
