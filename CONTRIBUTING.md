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

## Questions?

Feel free to open an issue or reach out to support@spendowl.io.

Thank you for contributing!
