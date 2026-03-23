#!/usr/bin/env bash
# Pre-release validation script
# Runs all checks before creating a release
# Usage: ./scripts/pre-release-checks.sh [--strict]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
STRICT_MODE=false
WARNINGS=0
ERRORS=0

# Parse arguments
for arg in "$@"; do
    case $arg in
        --strict)
            STRICT_MODE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--strict]"
            echo ""
            echo "Options:"
            echo "  --strict    Treat warnings as errors"
            echo "  --help, -h  Show this help message"
            exit 0
            ;;
    esac
done

echo "=============================================="
echo "         Pre-Release Validation Checks        "
echo "=============================================="
echo ""
echo "Repository: $REPO_ROOT"
echo "Strict mode: $STRICT_MODE"
echo ""

# Helper functions
pass() {
    echo "[PASS] $1"
}

warn() {
    echo "[WARN] $1"
    ((WARNINGS++)) || true
}

fail() {
    echo "[FAIL] $1"
    ((ERRORS++)) || true
}

# Check 1: VERSION file exists and is valid
echo "--- Check 1: VERSION file ---"
VERSION_FILE="$REPO_ROOT/VERSION"
if [[ -f "$VERSION_FILE" ]]; then
    VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
    if [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        pass "VERSION file valid: $VERSION"
    else
        fail "VERSION file format invalid: '$VERSION' (expected X.Y.Z)"
    fi
else
    fail "VERSION file not found"
fi
echo ""

# Check 2: pyrsm version
echo "--- Check 2: pyrsm version ---"
if [[ -x "$SCRIPT_DIR/check-pyrsm-version.sh" ]]; then
    if "$SCRIPT_DIR/check-pyrsm-version.sh" --fail-on-mismatch 2>&1; then
        pass "pyrsm version is current"
    else
        if [[ "$STRICT_MODE" == "true" ]]; then
            fail "pyrsm version is outdated"
        else
            warn "pyrsm version is outdated"
        fi
    fi
else
    warn "check-pyrsm-version.sh not found or not executable"
fi
echo ""

# Check 3: Git status
echo "--- Check 3: Git status ---"
cd "$REPO_ROOT"
if git diff --quiet 2>/dev/null; then
    pass "No uncommitted changes"
else
    warn "Uncommitted changes detected"
    git status --short
fi
echo ""

# Check 4: Git branch
echo "--- Check 4: Git branch ---"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
if [[ "$CURRENT_BRANCH" == "main" ]]; then
    pass "On main branch"
else
    warn "Not on main branch (currently on: $CURRENT_BRANCH)"
fi
echo ""

# Check 5: Required files exist
echo "--- Check 5: Required files ---"
REQUIRED_FILES=(
    "VERSION"
    "files/install-uv.sh"
    "rsm-podman/Containerfile"
    "docker-k8s/Dockerfile"
    ".github/workflows/rsm-podman-build.yml"
    ".github/workflows/rsm-docker-build.yml"
)
ALL_FILES_EXIST=true
for file in "${REQUIRED_FILES[@]}"; do
    if [[ -f "$REPO_ROOT/$file" ]]; then
        echo "  [OK] $file"
    else
        echo "  [MISSING] $file"
        ALL_FILES_EXIST=false
    fi
done
if [[ "$ALL_FILES_EXIST" == "true" ]]; then
    pass "All required files exist"
else
    fail "Some required files are missing"
fi
echo ""

# Check 6: Containerfile/Dockerfile syntax
echo "--- Check 6: Container file syntax ---"
CONTAINER_FILES=(
    "rsm-podman/Containerfile"
    "docker-k8s/Dockerfile"
)
for cfile in "${CONTAINER_FILES[@]}"; do
    if [[ -f "$REPO_ROOT/$cfile" ]]; then
        # Basic syntax check - look for common issues
        if grep -q "^FROM" "$REPO_ROOT/$cfile"; then
            echo "  [OK] $cfile has FROM instruction"
        else
            fail "$cfile missing FROM instruction"
        fi
    fi
done
echo ""

# Summary
echo "=============================================="
echo "                   Summary                    "
echo "=============================================="
echo ""
echo "Errors:   $ERRORS"
echo "Warnings: $WARNINGS"
echo ""

EXIT_CODE=0
if [[ $ERRORS -gt 0 ]]; then
    echo "RESULT: FAILED - $ERRORS error(s) found"
    EXIT_CODE=1
elif [[ $WARNINGS -gt 0 && "$STRICT_MODE" == "true" ]]; then
    echo "RESULT: FAILED - $WARNINGS warning(s) in strict mode"
    EXIT_CODE=1
elif [[ $WARNINGS -gt 0 ]]; then
    echo "RESULT: PASSED with warnings"
else
    echo "RESULT: PASSED - all checks successful"
fi
echo ""

if [[ $EXIT_CODE -eq 0 ]]; then
    echo "Ready for release!"
else
    echo "Please fix the issues above before releasing."
fi

exit $EXIT_CODE
