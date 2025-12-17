#!/bin/bash
# Validate that required environment variables are set in the container image
# Usage: ./scripts/validate-image.sh [image:tag] [docker|podman]

set -e

IMAGE="${1:-vnijs/docker-k8s:latest}"
ENGINE="${2:-docker}"
ERRORS=0

# Validate engine choice
if [ "$ENGINE" != "docker" ] && [ "$ENGINE" != "podman" ]; then
    echo "Error: Engine must be 'docker' or 'podman'"
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Validating environment variables in: ${IMAGE} (using $ENGINE)${NC}"
echo "=============================================="

# Function to check an environment variable
check_env() {
    local var_name=$1
    local expected_pattern=$2
    local value

    # Run container and get the value from /etc/profile.d/rsm-env.sh sourced shell
    value=$($ENGINE run --rm "$IMAGE" bash -l -c "echo \$$var_name" 2>/dev/null)

    if [ -z "$value" ]; then
        echo -e "${RED}FAIL${NC}: $var_name is not set"
        ERRORS=$((ERRORS + 1))
        return 1
    elif [ -n "$expected_pattern" ] && ! echo "$value" | grep -qE "$expected_pattern"; then
        echo -e "${YELLOW}WARN${NC}: $var_name='$value' (expected pattern: $expected_pattern)"
        return 0
    else
        echo -e "${GREEN}OK${NC}:   $var_name='$value'"
        return 0
    fi
}

# Function to check file existence
check_file() {
    local filepath=$1
    local description=$2

    if $ENGINE run --rm "$IMAGE" bash -c "[ -f '$filepath' ]" 2>/dev/null; then
        echo -e "${GREEN}OK${NC}:   $description exists ($filepath)"
        return 0
    else
        echo -e "${RED}FAIL${NC}: $description missing ($filepath)"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
}

echo ""
echo "Checking required environment variables..."
echo "-------------------------------------------"

# Check JAVA_HOME (should contain openjdk path)
check_env "JAVA_HOME" "/usr/lib/jvm/java-.*-openjdk"

# Check SPARK_HOME
check_env "SPARK_HOME" "/usr/local/spark"

# Check HADOOP_HOME
check_env "HADOOP_HOME" "/opt/hadoop"

# Check PYTHONPATH (should contain spark and py4j)
check_env "PYTHONPATH" "spark.*py4j"

# Check PATH includes hadoop and spark
check_env "PATH" "hadoop.*spark|spark.*hadoop"

echo ""
echo "Checking required files..."
echo "--------------------------"

# Check profile.d script exists
check_file "/etc/profile.d/rsm-env.sh" "RSM environment script"

# Check Java directory matches JAVA_HOME
echo ""
echo "Checking Java installation..."
echo "-----------------------------"
JAVA_HOME_VALUE=$($ENGINE run --rm "$IMAGE" bash -l -c 'echo $JAVA_HOME' 2>/dev/null)
if [ -n "$JAVA_HOME_VALUE" ]; then
    if $ENGINE run --rm "$IMAGE" bash -c "[ -d '$JAVA_HOME_VALUE' ]" 2>/dev/null; then
        echo -e "${GREEN}OK${NC}:   JAVA_HOME directory exists"
    else
        echo -e "${RED}FAIL${NC}: JAVA_HOME directory does not exist: $JAVA_HOME_VALUE"
        ERRORS=$((ERRORS + 1))
    fi

    # Check java binary works
    if $ENGINE run --rm "$IMAGE" bash -l -c 'java -version' >/dev/null 2>&1; then
        JAVA_VER=$($ENGINE run --rm "$IMAGE" bash -l -c 'java -version 2>&1 | head -1')
        echo -e "${GREEN}OK${NC}:   Java works: $JAVA_VER"
    else
        echo -e "${RED}FAIL${NC}: Java binary not working"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Check py4j file exists
echo ""
echo "Checking py4j installation..."
echo "-----------------------------"
PY4J_FILE=$($ENGINE run --rm "$IMAGE" bash -c 'ls /usr/local/spark/python/lib/py4j-*.zip 2>/dev/null | head -1')
if [ -n "$PY4J_FILE" ]; then
    echo -e "${GREEN}OK${NC}:   py4j found: $(basename $PY4J_FILE)"
else
    echo -e "${RED}FAIL${NC}: py4j zip not found in /usr/local/spark/python/lib/"
    ERRORS=$((ERRORS + 1))
fi

# Check architecture detection
echo ""
echo "Checking architecture..."
echo "------------------------"
ARCH=$($ENGINE run --rm "$IMAGE" uname -m 2>/dev/null)
echo -e "${GREEN}INFO${NC}: Container architecture: $ARCH"

if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    if echo "$JAVA_HOME_VALUE" | grep -q "arm64"; then
        echo -e "${GREEN}OK${NC}:   JAVA_HOME matches ARM64 architecture"
    else
        echo -e "${RED}FAIL${NC}: JAVA_HOME does not match ARM64 architecture"
        ERRORS=$((ERRORS + 1))
    fi
elif [ "$ARCH" = "x86_64" ]; then
    if echo "$JAVA_HOME_VALUE" | grep -q "amd64"; then
        echo -e "${GREEN}OK${NC}:   JAVA_HOME matches AMD64 architecture"
    else
        echo -e "${RED}FAIL${NC}: JAVA_HOME does not match AMD64 architecture"
        ERRORS=$((ERRORS + 1))
    fi
fi

echo ""
echo "=============================================="
if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}VALIDATION FAILED: $ERRORS error(s) found${NC}"
    echo -e "${RED}DO NOT push this image!${NC}"
    exit 1
else
    echo -e "${GREEN}VALIDATION PASSED: All checks successful${NC}"
    echo -e "${GREEN}Image is ready for push${NC}"
    exit 0
fi
