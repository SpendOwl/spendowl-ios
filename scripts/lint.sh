#!/bin/bash
#
# lint.sh
# SpendOwl
#
# Runs SwiftLint on the codebase.
# Install SwiftLint: brew install swiftlint
#
# Usage:
#   ./scripts/lint.sh         # Lint all files
#   ./scripts/lint.sh --fix   # Auto-fix violations
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"

# Check if SwiftLint is installed
if ! command -v swiftlint &> /dev/null; then
    echo "Error: SwiftLint is not installed."
    echo "Install with: brew install swiftlint"
    exit 1
fi

echo "Running SwiftLint..."

if [[ "$1" == "--fix" ]]; then
    swiftlint --fix --config .swiftlint.yml
    echo "Auto-fix complete. Please review changes."
else
    swiftlint lint --config .swiftlint.yml
fi

echo "Lint complete!"
