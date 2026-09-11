// @ts-check
const { defineConfig } = require("@playwright/test");

/**
 * @see https://playwright.dev/docs/test-configuration
 */
module.exports = defineConfig({
  testDir: "./",
  testMatch: "*tests.spec.js",
  /* Maximum time one test can run for. Caps a runaway/hanging test
   * so a single broken page can't burn the entire CI budget. With
   * cache pre-warming and 15s screenshot stability, well-behaved
   * tests complete in 5–15s; 45s leaves headroom for the slowest
   * legitimate ones while terminating stuck pages fast. */
  timeout: 45 * 1000,
  expect: {
    /**
     * Default expect() timeout for non-screenshot assertions.
     */
    timeout: 10000,
    toHaveScreenshot: {
      maxDiffPixelRatio: 0.02,
      /**
       * STABILITY-LOOP TIMEOUT — read this if tests are timing out.
       *
       * `toHaveScreenshot` works by taking two screenshots 100ms apart
       * and waiting for them to be pixel-identical (the "stability
       * check") before locking in the result. This timeout is the
       * budget for that loop to converge.
       *
       * If a test fails here with "Timed out 15000ms waiting for
       * expect(page).toHaveScreenshot", the page has something that
       * keeps changing between the two captures — almost always one of:
       *
       *   - A JS-driven carousel / image slider auto-advancing
       *   - An auto-playing video (banner, hero, product reel)
       *   - A typewriter / fade-in effect on hero text
       *   - A "live" widget (countdown, view counter, chat icon)
       *   - Lazy images still decoding from the scroll trigger
       *   - A captcha / reCAPTCHA challenge frame
       *
       * `animations: 'disabled'` below disables CSS animations only —
       * NOT setInterval/setTimeout/requestAnimationFrame loops in
       * application JS. To fix a perma-failing page, add the offending
       * selector to `hideSelectors` in your project's test_routes.json.
       *
       * 15s is intentional: stable pages converge in <5s, so 15s is
       * generous; pages that won't stabilize at 15s won't at 30s
       * either, and raising the ceiling just makes each failure 2x
       * more expensive. Fail-fast > fail-slow.
       */
      timeout: 15000,
      animations: "disabled",
      caret: "hide",
    },
    toMatchSnapshot: {
      maxDiffPixelRatio: 0.02,
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
    // JSON report is what run-playwright parses to name the failing tests in
    // the Slack failure notification (see write_failure_summary there).
    ["json", { outputFile: "test-results/results.json" }],
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
