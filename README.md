# HWD CI/CD Tools

A Composer plugin that sets up CI/CD pipelines for multiple hosting platforms (Pantheon, Upsun, WP Engine) and frameworks (Drupal, WordPress, Laravel) with GitHub Actions, visual regression testing, and automated deployments.

## Features

- **Multi-Platform Support** - Pantheon, Upsun (Platform.sh), and WP Engine
- **Multi-Framework Support** - Drupal, WordPress, and Laravel
- **Auto-Detection** - Automatically detects your platform and framework
- **Visual Regression Testing** - Playwright-based VRT for all platforms
- **GitHub Integration** - PR status checks, comments, and Jira sync
- **Automated Deployments** - Push to deploy to development environments
- **Automated Cleanup** - Remove stale environments on PR merge
- **Configurable** - Override auto-detection with `ci-tools.json`

## Supported Platforms

| Platform | Environment Creation | CLI Tool | Status |
|----------|---------------------|----------|--------|
| Pantheon | Multidev (11 char limit) | `terminus` | Full |
| Upsun | Branch environments | `platform` | Planned |
| WP Engine | Fixed (dev/staging/prod) | `git` | Planned |

## Supported Frameworks

| Framework | Auto-Detection | Config Import | Status |
|-----------|---------------|---------------|--------|
| Drupal | `web/core/`, `docroot/core/` | `drush cim` | Full |
| WordPress | `wp-config.php` | N/A | Planned |
| Laravel | `artisan` | `artisan config:cache` | Planned |

## Installation

1. Allow the plugin to run:

```bash
composer config allow-plugins.helloworlddevs/pantheon-ci-tools true
```

2. Add the package to your project:

```bash
composer require --dev helloworlddevs/pantheon-ci-tools
```

The plugin will automatically detect your platform and framework and install the appropriate CI files.

## Configuration (Optional)

Configure ci-tools via `composer.json` (recommended) or a separate `ci-tools.json` file.

### Option 1: composer.json (recommended)

Add configuration to the `extra` section of your `composer.json`. This uses Composer's native plugin API (similar to how npm plugins read from `package.json`):

```json
{
  "name": "your/project",
  "extra": {
    "ci-tools": {
      "platform": "upsun",
      "framework": "laravel",
      "testingUrl": "https://dev-mysite.example.com",
      "updateUrl": "https://prod-mysite.example.com",
      "options": {
        "skipVRT": false,
        "skipJiraIntegration": false
      }
    }
  }
}
```

**Why use composer.json?**
- Standard Composer plugin pattern - config travels with dependencies
- Works in Docker/Lando containers where platform markers (`.upsun/`, `pantheon.yml`) may not be mounted
- No extra config files to maintain

### Option 2: ci-tools.json

Create a `ci-tools.json` file in your project root for project-specific overrides:

```json
{
  "platform": "pantheon",
  "framework": "drupal",
  "options": {
    "skipVRT": false,
    "skipJiraIntegration": false,
    "skipCircleCI": true
  },
  "excludeFiles": [
    ".circleci/config.yml"
  ]
}
```

### Configuration Priority

1. `ci-tools.json` (highest - allows local overrides)
2. `composer.json` `extra.ci-tools`
3. Auto-detection from platform markers (`.upsun/`, `pantheon.yml`, etc.)
4. Default values

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `platform` | string | auto | Override platform detection (`pantheon`, `upsun`, `wpengine`) |
| `framework` | string | auto | Override framework detection (`drupal`, `wordpress`, `laravel`) |
| `projectRoot` | string | null | Install files relative to this path (e.g., `..` for parent directory) |
| `options.debug` | bool | false | Show verbose output (file-by-file details) |
| `options.skipVRT` | bool | false | Skip visual regression testing files |
| `options.skipJiraIntegration` | bool | false | Skip Jira integration files |
| `options.skipCircleCI` | bool | false | Skip CircleCI configuration |
| `options.vrtMode` | string | `lfs` | VRT mode: `lfs` (Git LFS baselines), `live` (DEV vs MULTIDEV), `disabled` |
| `options.baselineBranch` | string | `main` | Branch containing VRT baselines for LFS mode |
| `testingUrl` | string | null | Default URL for running VRT tests (used if `TESTING_URL` env var not set) |
| `updateUrl` | string | null | Default URL for updating baselines (used if `TESTING_URL` env var not set) |
| `excludeFiles` | array | [] | List of files to skip during installation |

## Visual Regression Testing

The CI tools include Playwright-based visual regression testing with two modes:

- **LFS Mode** (default) - Baseline images stored in Git LFS, compared against PR environments
- **Live Mode** - Baselines generated from DEV, compared against MULTIDEV (Pantheon)

### Setup (LFS Mode - Recommended)

Git LFS is automatically set up when you install the plugin. The installer will:
- Detect if Git LFS is installed (and show installation instructions if not)
- Initialize LFS in your repository (`git lfs install`)
- Create/update `.gitattributes` with VRT baseline tracking

1. Create a `test_routes.json` file in your project root:

```json
{
  "routes": {
    "home": "/",
    "about": "/about",
    "contact": "/contact"
  },
  "hideSelectors": []
}
```

2. Generate baseline images using Docker (ensures Linux consistency with CI):

```bash
TESTING_URL=https://your-site.com .ci/test/visual-regression/update-baselines
```

3. Commit the baselines (stored in Git LFS):

```bash
git add .
git commit -m "Add VRT baselines"
```

4. Add `TESTING_URL` to your GitHub repository secrets pointing to your test environment.

### Running Tests

Run VRT tests locally against a URL:

```bash
# With explicit URL
TESTING_URL=https://your-site.com .ci/test/visual-regression/run-playwright

# Or if testingUrl is configured in composer.json, just run:
.ci/test/visual-regression/run-playwright
```

### Updating Baselines

When intentional visual changes are made:

```bash
# With explicit URL
TESTING_URL=https://your-site.com .ci/test/visual-regression/update-baselines

# Or if updateUrl is configured in composer.json, just run:
.ci/test/visual-regression/update-baselines

# Then commit
git add .ci/test/visual-regression/playwright-tests.spec.js-snapshots/
git commit -m "Update VRT baselines"
```

### Default URLs

Configure default URLs in `composer.json` to avoid specifying them each time:

```json
{
  "extra": {
    "ci-tools": {
      "testingUrl": "https://staging.mysite.com",
      "updateUrl": "https://production.mysite.com"
    }
  }
}
```

- `testingUrl`: Used by `run-playwright` when `TESTING_URL` env var is not set
- `updateUrl`: Used by `update-baselines` when `TESTING_URL` env var is not set (falls back to `testingUrl` if not specified)

### Live Mode (Pantheon)

For Pantheon projects, you can use live mode to compare DEV vs MULTIDEV without storing baselines:

```json
{
  "options": {
    "vrtMode": "live"
  }
}
```

This generates baselines from DEV and compares against the MULTIDEV environment on each PR.

### Configuration

Customize visual testing in `playwright.config.js`:

- Adjust viewport sizes
- Set thresholds for pixel differences
- Configure test timeouts

## Required Environment Variables

Set these in your CI environment (GitHub Actions secrets or CircleCI):

### Pantheon

```env
PANTHEON_SITE=your-site-name
TERMINUS_TOKEN=your-terminus-token
GITHUB_TOKEN=your-github-token
SSH_PRIVATE_KEY=your-ssh-key
```

### Upsun

```env
PLATFORMSH_CLI_TOKEN=your-platform-token
GITHUB_TOKEN=your-github-token
```

### WP Engine

```env
WPENGINE_SSH_KEY=your-ssh-key
GITHUB_TOKEN=your-github-token
```

### Optional (Jira Integration)

```env
JIRA_BASE_URL=https://your-domain.atlassian.net
JIRA_USER=your-email@example.com
JIRA_TOKEN=your-jira-api-token
```

## What Gets Installed

### File Management (Hybrid Approach)

The installer uses a **hybrid approach** - files are installed once and then preserved on future installs:

| Category | Files | Behavior |
|----------|-------|----------|
| **VRT Templates** | `playwright-tests.spec.js`, `run-playwright`, etc. | Install once, skip if exists |
| **GitHub Workflows** | `vrt.yml`, `pr-comments-to-jira.yml` | Install once, skip if exists |
| **Generated Config** | `vrt-config.sh` | Always regenerated from composer.json |
| **Baselines** | `playwright-tests.spec.js-snapshots/*.png` | Created by Playwright, tracked by Git LFS |
| **Artifacts** | `node_modules/`, `test-results/`, `playwright-report/` | Gitignored |

**Why this approach?**
- **Customizable** - Modify test scripts, workflows without losing changes on reinstall
- **Safe** - Baseline snapshots are never touched by the installer
- **Updatable** - Use `--force` to update templates when needed

**Commands:**
```bash
# Normal install (skips existing files)
composer ci-tools:install

# Force update templates (overwrites existing, preserves snapshots)
composer ci-tools:install -- --force
```

### Shared Files (All Platforms)

- `.ci/test/visual-regression/` - Playwright VRT setup
  - `run-playwright` - Test runner (supports LFS and live modes)
  - `update-baselines` - Docker-based baseline generator
  - `playwright.config.js` - Playwright configuration
  - `.gitignore` - Excludes artifacts, preserves baselines
- `.github/workflows/vrt.yml` - Visual regression testing workflow
- `.ci/scripts/notify_jira.sh` - Jira notification script
- `.github/workflows/pr-comments-to-jira.yml` - Jira comment sync
- `.gitattributes` - Git LFS tracking (created/updated for VRT baselines)

### Pantheon-Specific

- `.circleci/config.yml` - CircleCI pipeline
- `.github/workflows/pr-multidev.yml` - Create multidev on PR
- `.github/workflows/delete-multidev-on-merge.yml` - Cleanup
- `.ci/scripts/dev-multidev.sh` - Deployment script

### Framework-Specific (Drupal)

- `lando/scripts/dev-config.sh` - Config split toggle
- `lando/scripts/config-safety-check.sh` - Config validation

## Architecture

```
src/
├── Plugin.php              # Composer plugin entry point
├── Installer.php           # Main installer logic
├── Detection/
│   ├── PlatformDetector.php
│   └── FrameworkDetector.php
├── Platform/
│   ├── PantheonHandler.php
│   ├── UpsunHandler.php
│   └── WPEngineHandler.php
├── Framework/
│   ├── DrupalHandler.php
│   ├── WordPressHandler.php
│   └── LaravelHandler.php
└── Config/
    ├── CIConfig.php
    └── ConfigLoader.php
```

## Development

### Testing Locally

```bash
php test_local_installer.php
```

### Directory Structure

```
files/
├── shared/          # Platform-agnostic files
├── pantheon/        # Pantheon-specific files
├── upsun/           # Upsun-specific files
├── wpengine/        # WP Engine-specific files
└── framework/       # Framework-specific files
    ├── drupal/
    ├── wordpress/
    └── laravel/
```

## Troubleshooting

### Platform Not Detected

Create a `ci-tools.json` file to explicitly set your platform:

```json
{
  "platform": "pantheon"
}
```

### Visual Tests Failing

1. Check test artifacts for failure screenshots in GitHub Actions
2. Adjust thresholds in `playwright.config.js`
3. Update baselines using Docker for consistency:
   ```bash
   TESTING_URL=https://your-site.com .ci/test/visual-regression/update-baselines
   ```
4. Ensure baselines were generated on Linux (use Docker or CI)

### Git LFS Issues

If LFS baselines aren't being tracked:

1. Verify LFS is installed: `git lfs version`
2. Initialize in repo: `git lfs install`
3. Check `.gitattributes` contains the tracking line:
   ```
   **/playwright-tests.spec.js-snapshots/*.png filter=lfs diff=lfs merge=lfs -text
   ```
4. Re-track existing files: `git lfs migrate import --include="*.png"`

### Deployment Issues

1. Verify CLI tool authentication (Terminus, Platform CLI)
2. Check GitHub Actions logs
3. Ensure environment variables are set correctly

## License

MIT
