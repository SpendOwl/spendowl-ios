# Contributing to SpendOwl iOS SDK

Thank you for your interest in contributing to SpendOwl! This document provides guidelines and instructions for contributing.

## Code of Conduct

Please be respectful and constructive in all interactions. We're all here to build something great together.

## How to Contribute

### Reporting Bugs

1. Check if the bug has already been reported in [Issues](https://github.com/spendowl/spendowl-ios/issues)
2. If not, create a new issue with:
   - A clear, descriptive title
   - Steps to reproduce the bug
   - Expected vs actual behavior
   - iOS version, Xcode version, and device model
   - Any relevant code snippets or logs

### Suggesting Features

1. Check existing issues for similar suggestions
2. Create a new issue with the `enhancement` label
3. Describe the feature and its use case
4. Explain why it would benefit other users

### Pull Requests

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature-name`
3. Make your changes following our coding standards
4. Add or update tests as needed
5. Run tests: `swift test`
6. Commit with a clear message
7. Push and create a Pull Request

## Coding Standards

### Swift Style

- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use meaningful variable and function names
- Keep functions focused and small
- Add documentation comments for public APIs

### Documentation

All public APIs must have documentation comments:

```swift
/// Fetches attribution data asynchronously.
///
/// - Returns: The attribution result.
/// - Throws: `SpendOwlError` if attribution fails.
public static func attribution() async throws -> AttributionResult {
    // ...
}
```

### Testing

- Add tests for new functionality
- Ensure all tests pass before submitting
- Aim for good test coverage

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/spendowl/spendowl-ios.git
   cd spendowl-ios
   ```

2. Install SwiftLint:
   ```bash
   brew install swiftlint
   ```

3. Set up pre-commit hook (recommended):
   ```bash
   ln -s "$(pwd)/scripts/lint.sh" .git/hooks/pre-commit
   chmod +x .git/hooks/pre-commit
   ```

4. Build and test:
   ```bash
   swift build
   swift test
   ```

5. Lint and format before committing:
   ```bash
   swiftlint lint --config .swiftlint.yml
   swiftformat Sources Tests --config .swiftformat
   ```

## Commit Messages

We use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` new features
- `fix:` bug fixes
- `chore:` maintenance tasks
- `docs:` documentation changes

## Releases

Version bumps are **not** part of feature or fix PRs. Several merged PRs are batched
into one release, so `Version.swift` and `CHANGELOG.md` change only in a dedicated
release PR. This keeps `main` readable — each PR describes one change — and keeps the
changelog writable, since it is assembled from the PRs a release contains.

To cut a release:

1. Open a release PR that updates `CHANGELOG.md` with a new version section and sets
   `spendOwlVersion` in `Sources/SpendOwl/Version.swift` to the same version.
2. Merge it, then tag the merge commit with a **`v`-prefixed** tag (`v1.3.1`).
   Swift Package Manager resolves both forms, but the repository is consistent on `v`.
3. CI's `Version matches tag` job runs on the tag and fails the release if
   `Version.swift` disagrees with it. That string is reported to the backend as
   `sdkVersion`, so drift silently corrupts per-version reporting.

Versioning follows [Semantic Versioning](https://semver.org). Because the public API
surface is small and widely depended on, an addition to it is a minor bump and any
change to existing public behaviour is a major one — internal fixes are patches.

## Questions?

Feel free to open an issue or reach out to support@spendowl.io.

Thank you for contributing!
