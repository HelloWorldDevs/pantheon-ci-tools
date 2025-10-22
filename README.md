# Pantheon CI/CD Tools

A Composer plugin that sets up CI/CD pipelines for Pantheon projects with CircleCI, including visual regression testing and automated deployments.

## Features

- 🚀 **Automated Deployments** - Push to deploy to Pantheon multidev environments
- 👁️ **Visual Regression Testing** - Catch visual bugs with Playwright
- 🔗 **GitHub Integration** - PR status checks and comments
- 🧹 **Automated Cleanup** - Remove stale multidev environments
- 🛠️ **Zero Configuration** - Works out of the box with sensible defaults

## Installation

1. Allow the plugin to run:

```bash
composer config allow-plugins.helloworlddevs/pantheon-ci-tools true
```

2. Add the package to your project:

```bash
composer require --dev helloworlddevs/pantheon-ci-tools
```

## Visual Regression Testing

### Setup

1. Create a `test_routes.json` file in your project root with the paths you want to test:

```json
{
  "home": "/",
  "about": "/about",
  "contact": "/contact"
}
```

2. The test runner will automatically find this file in your project root or any parent directory (up to 4 levels up).

### Running Tests Locally

1. Run tests:
```bash
./ci/test/visual-regression/run-playwright
```

### Configuration

Customize visual testing in `playwright.config.js`:
- Adjust viewport sizes
- Set thresholds for pixel differences
- Configure test timeouts

## CI/CD Pipeline

The plugin sets up a CircleCI pipeline that:

1. Runs on every PR
2. Deploys to a multidev environment
3. Runs visual regression tests
4. Reports results back to GitHub

### Required Environment Variables

Set these in your CI environment:

```env
# Required
PANTHEON_SITE=your-site-name
TERMINUS_TOKEN=your-terminus-token
GITHUB_TOKEN=your-github-token
```

## Troubleshooting

### Visual Tests Failing

1. Check the test artifacts for screenshots of failures
2. Adjust thresholds in `playwright.config.js` if needed
3. Update baseline images if the changes are intentional:
   ```bash
   UPDATE_SNAPSHOTS=true npx playwright test
   ```

### Deployment Issues

1. Verify your Terminus token has the correct permissions
2. Check the CircleCI logs for detailed error messages
3. Ensure your Pantheon site is properly connected to your GitHub repository

## License

MIT

## Updating

To update the CI configuration, simply update the package:

```bash
composer update helloworlddevs/pantheon-ci
```

## Development

### Setup

1. Clone the repository
2. Run `composer install` to install dependencies
3. Make your changes to the source code

### Testing Your Changes

To test your local changes without publishing to Github:

#### Option 1: Local Test Script (Recommended)

Run the built-in test that uses your local code directly:

```bash
php test_local_installer.php
```

This will:
- Create a `sampleoutput/` directory with a mock Drupal project
- Copy `lando-test.yml` as the sample `.lando.yml` file
- Run your local installer code directly (not via Composer)
- Show detailed analysis of what was added/modified
- Install all CI files, Lando scripts, and modify `.lando.yml`

Check the results in `sampleoutput/` to verify everything works correctly.

#### Option 2: Test in a Real Project

1. In your test Drupal project, add this to `composer.json`:

```json
{
  "repositories": [
    {
      "type": "path",
      "url": "/path/to/your/pantheon-ci-tools"
    }
  ],
  "require-dev": {
    "helloworlddevs/pantheon-ci-tools": "@dev"
  }
}
```

2. Allow the plugin and install:

```bash
composer config allow-plugins.helloworlddevs/pantheon-ci-tools true
composer install
```

#### What Gets Installed

The installer will:
- Copy CI configuration files (`.circleci/`, `.ci/`, `.github/`)
- Install Lando scripts (`lando/scripts/dev-config.sh`, `config-safety-check.sh`)
- Add tooling commands to `.lando.yml` (`dev-config`, `config-check`, `safe-export`)
- Add post-start and post-pull events to `.lando.yml`
- Add `drupal/config_split` to `require-dev`

#### Cleanup

```bash
rm -rf sampleoutput  # Remove test directory
```

## License

MIT
