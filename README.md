# Pantheon CI/CD Pipeline

A Composer package that sets up CI/CD pipeline for Pantheon projects with GitHub and CircleCI.

## Features

- Automated deployment to Pantheon multidev environments
- Visual regression testing
- GitHub PR integration
- Jira ticket linking
- Automated cleanup of multidev environments

## Installation

1. Add the package to your project:

```bash
composer require --dev helloworlddevs/pantheon-ci
```

2. Set up your environment variables by copying the example file:

```bash
cp vendor/helloworlddevs/pantheon-ci/files/.env.example .env
```

3. Update the `.env` file with your specific configuration.

## Required Environment Variables

Create a `.env` file in your project root with the following variables:

```env
# Required
PANTHEON_SITE=your-site-name
TERMINUS_TOKEN=your-terminus-token
GITHUB_TOKEN=your-github-token

# Optional with defaults
GITHUB_REPO=auto-detected
PANTHEON_ENV=dev
```

## Configuration

The package will automatically set up the following files in your project:

- `.circleci/config.yml` - CircleCI configuration
- `.github/workflows/` - GitHub Actions workflows
- `.ci/` - Custom CI scripts and configurations

## Updating

To update the CI configuration, simply update the package:

```bash
composer update helloworlddevs/pantheon-ci
```

## Development

1. Clone the repository
2. Run `composer install`
3. Make your changes
4. Test with a local project using `composer link`

## License

MIT
