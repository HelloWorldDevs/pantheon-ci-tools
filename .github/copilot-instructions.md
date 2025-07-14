# Instructions for Copilot

This document outlines the best practices and conventions to follow when working on the `pantheon-ci-tools` project.

## Languages and Frameworks

- **PHP**: The core logic of the project is written in PHP. It uses Composer for dependency management.
- **Shell Scripts**: The project contains several shell scripts for CI/CD automation.
- **GitHub Actions**: The CI/CD pipelines are defined in YAML files for GitHub Actions.

## Code Style and Conventions

### PHP

- **PSR-12**: All PHP code should adhere to the [PSR-12](https://www.php-fig.org/psr/psr-12/) standard.
- **Namespacing**: All PHP classes should be properly namespaced under `Pantheon\Terminus\CI`.
- **Strict Types**: Use strict types (`declare(strict_types=1);`) in all PHP files.
- **Composer**: All PHP dependencies should be managed through Composer.

### Shell Scripting

- **Error Handling**: All shell scripts should use `set -e` to exit on error, `set -o pipefail` to exit on pipe failure, and `set -u` to exit on unset variables.
- **Linting**: Use `shellcheck` to lint all shell scripts.
- **Variable Naming**: Use uppercase variable names for environment variables and lowercase variable names for local variables.

### Git

- **Conventional Commits**: All commit messages should follow the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification.
- **Branching**: All changes must be made in a new branch, not directly on the `main` branch. Create a pull request to merge changes.
- **Branch Naming**: Use branch names that reflect the jira ticket or feature being worked on, e.g., `JIRA-123-add-new-feature` or `JIRA-456-fix-bug`. Do not use slashes (`/`) in branch names.
- **Never Commit Sensitive Data**: Ensure that no sensitive data (like API keys or passwords) is committed to the repository.
- **Never Commit changes to main**: All changes should be made in feature branches and merged into `main` via pull requests.
- **Always check the diff** of changes using `git diff` before making a commit to ensure accuracy and compliance with the instructions.

### GitHub Actions

- **Composite Actions**: Use composite actions to reduce duplication in the workflows.
- **Secrets**: Use secrets for all sensitive data, such as API keys and tokens.
- **Pin Actions**: Pin all actions to a specific version to ensure stability.

## Development Workflow

1. If the current branch is `main`, ask if there is a Jira ticket for the changes. If so, create a new branch named after the ticket.
2.  Create a new branch for each feature or bug fix.
2.  Write code and tests.
3.  Run `composer install` to install all dependencies.
4.  Run `composer test` to run all tests.
5.  Run `composer lint` to lint all code.
6.  Create a pull request.
7.  Once the pull request is approved, merge it into the `main` branch.

# Context
Responses should consider the following files and directories in the workspace:
- `composer.json` for project dependencies and configuration.
- `README.md` for project overview and instructions.
- `src/` for source code implementation details.
- `files/` for test routes and GitHub workflows.

# Mandatory Review
Always review this file before performing any task or generating any response. This file is the primary source of truth and overrides any assumptions or prior context.

# Error Handling
If the instructions are not followed, provide a detailed explanation of the deviation and steps to correct it.