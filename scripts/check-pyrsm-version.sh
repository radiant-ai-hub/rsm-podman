#!/usr/bin/env bash
# Check if pinned pyrsm version in install-uv.sh matches latest on PyPI
# Usage: ./scripts/check-pyrsm-version.sh [--fail-on-mismatch]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
INSTALL_SCRIPT="${REPO_ROOT}/files/install-uv.sh"
FAIL_ON_MISMATCH=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --fail-on-mismatch)
            FAIL_ON_MISMATCH=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--fail-on-mismatch]"
            echo ""
            echo "Options:"
            echo "  --fail-on-mismatch  Exit with code 1 if versions don't match"
            echo "  --help, -h          Show this help message"
            exit 0
            ;;
    esac
done

echo "=== pyrsm Version Check ==="
echo ""

# Extract pinned version from install-uv.sh
if [[ ! -f "$INSTALL_SCRIPT" ]]; then
    echo "ERROR: install-uv.sh not found at: $INSTALL_SCRIPT"
    exit 1
fi

PINNED_VERSION=$(grep -oP 'pyrsm==\K[0-9]+\.[0-9]+\.[0-9]+' "$INSTALL_SCRIPT" || true)
if [[ -z "$PINNED_VERSION" ]]; then
    echo "ERROR: Could not extract pyrsm version from $INSTALL_SCRIPT"
    echo "Expected format: pyrsm==X.Y.Z"
    exit 1
fi

echo "Pinned version (install-uv.sh): $PINNED_VERSION"

# Fetch latest version from PyPI
PYPI_URL="https://pypi.org/pypi/pyrsm/json"
echo "Fetching latest version from PyPI..."

PYPI_RESPONSE=$(curl -sS "$PYPI_URL" 2>&1) || {
    echo "ERROR: Failed to fetch from PyPI"
    echo "$PYPI_RESPONSE"
    exit 1
}

LATEST_VERSION=$(echo "$PYPI_RESPONSE" | grep -oP '"version":\s*"\K[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
if [[ -z "$LATEST_VERSION" ]]; then
    echo "ERROR: Could not parse latest version from PyPI response"
    exit 1
fi

echo "Latest version (PyPI):          $LATEST_VERSION"
echo ""

# Compare versions
if [[ "$PINNED_VERSION" == "$LATEST_VERSION" ]]; then
    echo "OK: pyrsm version is up to date"
    exit 0
else
    echo "MISMATCH: Pinned version ($PINNED_VERSION) differs from latest ($LATEST_VERSION)"
    echo ""
    echo "To update:"
    echo "  1. Edit files/install-uv.sh"
    echo "  2. Change 'pyrsm==$PINNED_VERSION' to 'pyrsm==$LATEST_VERSION'"
    echo "  3. Commit and push the change"
    echo ""

    if [[ "$FAIL_ON_MISMATCH" == "true" ]]; then
        echo "Exiting with error (--fail-on-mismatch specified)"
        exit 1
    else
        echo "Warning: Version mismatch (use --fail-on-mismatch to fail)"
        exit 0
    fi
fi
