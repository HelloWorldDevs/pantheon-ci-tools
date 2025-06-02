# Test info

- Name: Visual regression test for ProductPage >> ProductPage should look the same on mobile
- Location: /Users/danlinn/Sites/wavemetrics/.ci/test/visual-regression/playwright-tests.spec.js:79:7

# Error details

```
Error: expect(page).toHaveScreenshot(expected)

  16358 pixels (ratio 0.11 of all image pixels) are different.

Expected: /Users/danlinn/Sites/wavemetrics/.ci/test/visual-regression/playwright-tests.spec.js-snapshots/ProductPage-mobile-chromium-darwin.png
Received: /Users/danlinn/Sites/wavemetrics/.ci/test/visual-regression/test-results/playwright-tests-Visual-re-0253f-uld-look-the-same-on-mobile-chromium/ProductPage-mobile-actual.png
    Diff: /Users/danlinn/Sites/wavemetrics/.ci/test/visual-regression/test-results/playwright-tests-Visual-re-0253f-uld-look-the-same-on-mobile-chromium/ProductPage-mobile-diff.png

Call log:
  - expect.toHaveScreenshot(ProductPage-mobile.png) with timeout 10000ms
    - verifying given screenshot expectation
  - taking page screenshot
    - disabled all CSS animations
  - waiting for fonts to load...
  - fonts loaded
  - 16358 pixels (ratio 0.11 of all image pixels) are different.
  - waiting 100ms before taking screenshot
  - taking page screenshot
    - disabled all CSS animations
  - waiting for fonts to load...
  - fonts loaded
  - captured a stable screenshot
  - 16358 pixels (ratio 0.11 of all image pixels) are different.

    at /Users/danlinn/Sites/wavemetrics/.ci/test/visual-regression/playwright-tests.spec.js:134:32
```

# Page snapshot

```yaml
- link:
  - /url: "#"
  - img
- link:
  - /url: /
- navigation "Main navigation":
  - heading "Main navigation" [level=2]
  - list:
    - listitem:
      - link "Products":
        - /url: /products
    - listitem:
      - link "News & Blog":
        - /url: /news
    - listitem:
      - link "Downloads":
        - /url: /downloads/current
    - listitem:
      - link "Samples Galleries":
        - /url: /photo-gallery
    - listitem:
      - link "Case Studies":
        - /url: /case-studies
    - listitem:
      - link "IgorExchange Forums":
        - /url: /forum
    - listitem:
      - link "Support Center":
        - /url: /support
- banner "Site header":
  - link:
    - /url: /
    - img
  - link:
    - /url: "#"
  - link:
    - /url: /search/wavemetrics?keys=
- heading "Products" [level=1]
- link:
  - /url: /products/igorpro
- heading "Igor Pro®" [level=2]:
  - link "Igor Pro®":
    - /url: /products/igorpro
- paragraph: Igor Pro® is an extraordinarily powerful and extensible graphing, data analysis, image processing and programming tool for scientists and engineers.
- link "Try or Buy":
  - /url: /products/igorpro
- link:
  - /url: /products/nidaqtools
- heading "Igor Pro® NIDAQ Tools MX" [level=2]:
  - link "Igor Pro® NIDAQ Tools MX":
    - /url: /products/nidaqtools
- paragraph: The NIDAQ Tools MX package adds support for data acquisition directly into Igor Pro. It supports most "multifunction data acquisition" boards made by National Instruments.
- link "Buy":
  - /url: /products/nidaqtools
- link:
  - /url: /products/xoptoolkit
- heading "Igor XOP Toolkit" [level=2]:
  - link "Igor XOP Toolkit":
    - /url: /products/xoptoolkit
- paragraph: The Igor XOP Toolkit allows a C programmer to extend Igor Pro®. You can add operations, functions, menus, dialogs, and windows for data analysis, data acquisition or other purposes.
- link "Buy":
  - /url: /products/xoptoolkit
- link "Forum":
  - /url: /forum
  - img
  - paragraph: Forum
- link "Support":
  - /url: /support
  - img
  - paragraph: Support
- link "Gallery":
  - /url: /photo-gallery
  - img
  - paragraph: Gallery
- link "Igor Pro 9 Learn More":
  - /url: /products/igorpro
  - heading "Igor Pro 9" [level=3]
  - paragraph: Learn More
- link "Igor XOP Toolkit Learn More":
  - /url: /products/xoptoolkit
  - heading "Igor XOP Toolkit" [level=3]
  - paragraph: Learn More
- link "Igor NIDAQ Tools MX Learn More":
  - /url: /products/nidaqtools
  - heading "Igor NIDAQ Tools MX" [level=3]
  - paragraph: Learn More
- contentinfo:
  - complementary:
    - heading "WaveMetrics - A Division of Sutter Instrument" [level=2]
    - paragraph: Scientific graphic and data analysis software for scientists and engineers
    - heading "Business Information" [level=3]
    - heading "Hours:" [level=4]
    - list:
      - listitem: Mon-Fri
      - listitem: 9:00 am - 5:00 pm
    - heading "Phone Number:" [level=4]
    - list:
      - listitem:
        - text: "Portland:"
        - link "(503) 620-3001":
          - /url: "tel:"
    - heading "Address:" [level=4]
    - list:
      - listitem: WaveMetrics, Suite G-7, 10200 SW Nimbus Ave, Portland , OR 97223
    - heading "Support Information" [level=3]
    - heading "Customer Support:" [level=4]
    - list:
      - listitem: sales@wavemetrics.com
    - heading "Technical Support:" [level=4]
    - list:
      - listitem: support@wavemetrics.com
    - heading "Mailing Address:" [level=4]
    - list:
      - listitem: WaveMetrics, P.O. Box 2088 Lake Oswego, OR 97035 USA
    - paragraph:
      - link "Privacy Policy":
        - /url: https://wavemetrics.com/privacy-accessibility
```

# Test source

```ts
   34 |   if (!fs.existsSync(dir)) {
   35 |     fs.mkdirSync(dir, { recursive: true });
   36 |   }
   37 | }
   38 |
   39 | // Create screenshots directory
   40 | const screenshotDir = path.join(process.cwd(), 'screenshots');
   41 | ensureDirectoryExists(screenshotDir);
   42 |
   43 | // Helper function to pre-warm cache by pinging URLs
   44 | async function preWarmCache(url) {
   45 |   // Using node-fetch to perform a simple GET request
   46 |   console.log(`Pre-warming cache for: ${url}`);
   47 |   try {
   48 |     // Create a simple browser context just for warming up the cache
   49 |     const browser = await require('playwright').chromium.launch();
   50 |     const warmupContext = await browser.newContext();
   51 |     const warmupPage = await warmupContext.newPage();
   52 |
   53 |     // Navigate to the URL and wait for the page to load
   54 |     await warmupPage.goto(url, { waitUntil: 'networkidle', timeout: 30000 });
   55 |     console.log(`Successfully pre-warmed cache for: ${url}`);
   56 |
   57 |     // Close everything to free resources
   58 |     await warmupPage.close();
   59 |     await warmupContext.close();
   60 |     await browser.close();
   61 |   } catch (error) {
   62 |     console.error(`Error pre-warming cache for ${url}: ${error.message}`);
   63 |   }
   64 | }
   65 |
   66 | // Define test for each path
   67 | paths.forEach(({ name, url }) => {
   68 |   test.describe(`Visual regression test for ${name}`, () => {
   69 |     // Pre-warm caches before tests run
   70 |     test.beforeAll(async () => {
   71 |       // Pre-warm both reference and test URLs
   72 |       await preWarmCache(`${testUrl}${url}`);
   73 |       // Add a delay to ensure caches are fully built
   74 |       await new Promise(resolve => setTimeout(resolve, 2000));
   75 |     });
   76 |
   77 |     // Test each viewport
   78 |     ['mobile', 'tablet', 'desktop'].forEach(viewport => {
   79 |       test(`${name} should look the same on ${viewport}`, async ({ context }) => {
   80 |         // Set viewport size based on device type
   81 |         const viewportSizes = {
   82 |           mobile: { width: 320, height: 480 },
   83 |           tablet: { width: 1024, height: 768 },
   84 |           desktop: { width: 1920, height: 1080 },
   85 |         };
   86 |
   87 |         // Create a single page for testing/snapshot comparison
   88 |         // Create a browser context with JavaScript enabled for consistent behavior
   89 |         const browserContext = await context.browser().newContext({
   90 |           javaScriptEnabled: true,
   91 |         });
   92 |
   93 |         // Create a new page for testing
   94 |         const testPage = await browserContext.newPage();
   95 |         await testPage.setViewportSize(viewportSizes[viewport]);
   96 |
   97 |         // The URL to test varies based on the execution context
   98 |         // First run with --update-snapshots will use DEV_SITE_URL (reference)
   99 |         // Second run without the flag will use MULTIDEV_SITE_URL (test)
  100 |         const urlToTest = testUrl;
  101 |
  102 |         console.log(`Navigating to: ${urlToTest}${url}`);
  103 |         await testPage.goto(`${urlToTest}${url}`, {
  104 |           waitUntil: "networkidle",
  105 |           timeout: 30000, // Increase timeout for page load
  106 |         });
  107 |         await testPage.waitForSelector("body", { timeout: 15000 });
  108 |         await testPage.waitForTimeout(2000); // Initial stability delay
  109 |
  110 |         // Ensure content is loaded and visible by scrolling
  111 |         await testPage.locator("body").scrollIntoViewIfNeeded();
  112 |         await testPage.waitForTimeout(2000); // Wait for scrolling to complete
  113 |
  114 |         // Resize window slightly to trigger any responsive layout changes
  115 |         const originalViewport = viewportSizes[viewport];
  116 |         await testPage.setViewportSize({
  117 |           width: originalViewport.width - 5,
  118 |           height: originalViewport.height
  119 |         });
  120 |         await testPage.waitForTimeout(500); // Let layout adjust
  121 |
  122 |         // Restore original viewport size
  123 |         await testPage.setViewportSize(originalViewport);
  124 |         await testPage.waitForTimeout(1000); // Final stabilization wait
  125 |
  126 |         // When run with --update-snapshots, it creates reference images
  127 |         // Otherwise it compares against existing references
  128 |         // Use higher thresholds when retrying failed tests
  129 |         const isRetry = process.env.RETRY_WITH_HIGHER_THRESHOLD === 'true';
  130 |         
  131 |         // Log whether we're doing a regular test or a retry with higher thresholds
  132 |         console.log(`${isRetry ? 'RETRY with higher thresholds' : 'Regular test'} for ${name} on ${viewport}`);
  133 |         
> 134 |         await expect(testPage).toHaveScreenshot(`${name.replace(/ /g, "-")}-${viewport}.png`, {
      |                                ^ Error: expect(page).toHaveScreenshot(expected)
  135 |           maxDiffPixelRatio: isRetry ? 0.2 : 0.1,      // Double the allowed diff ratio on retry
  136 |           threshold: isRetry ? 0.3 : 0.2,             // Higher color difference threshold on retry
  137 |           maxDiffPixels: isRetry ? 500 : 100,         // Allow more different pixels on retry
  138 |         });
  139 |
  140 |         // Close the test page
  141 |         await testPage.close();
  142 |       });
  143 |     });
  144 |   });
  145 | });
  146 |
```