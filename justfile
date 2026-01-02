# Justfile for rsm-msba-k8s Docker and rsm-podman multi-platform builds
# Usage: just [recipe] [args...]

# =============================================================================
# Configuration
# =============================================================================
DOCKER_IMAGE := "vnijs/rsm-msba-k8s"
DOCKER_FILE := "docker-k8s/Dockerfile"
DOCKER_BUILDER := "multiplatform-builder"

PODMAN_IMAGE := "ghcr.io/radiant-ai-hub/rsm-podman"
CONTAINERFILE := "rsm-podman/Containerfile"

PLATFORMS := "linux/amd64,linux/arm64"
TEST_DOCKER_IMAGE := "vnijs/rsm-msba-k8s-test"
TEST_PODMAN_IMAGE := "ghcr.io/radiant-ai-hub/rsm-podman-test"

VERSION_FILE := "VERSION"
CURRENT_PLATFORM := `uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/'`

# Get current version from VERSION file
@_get_version:
    #!/bin/bash
    cat {{ VERSION_FILE }}

# =============================================================================
# Help and Status
# =============================================================================

@help:
    echo "🐳 rsm-msba-k8s Multi-Platform Build System"
    echo ""
    echo "📋 Usage: just [recipe] [args...]"
    echo ""
    echo "🔧 Common Commands:"
    echo "  just help                  Show this help message"
    echo "  just status                Show build environment status"
    echo ""
    echo "📦 Version Management:"
    echo "  just version               Show current VERSION"
    echo "  just bump <VERSION>        Bump version, commit, push, and tag"
    echo "  just bump 2.5.0            (example)"
    echo ""
    echo "🐳 Docker Commands:"
    echo "  just test                  Build local test image"
    echo "  just build                 Build and push multi-platform Docker image"
    echo "  just build-no-cache        Build without cache"
    echo "  just inspect               Inspect Docker manifest"
    echo "  just login                 Login to Docker Hub"
    echo "  just test-auth             Test Docker Hub authentication"
    echo ""
    echo "📦 Podman Commands:"
    echo "  just podman-test           Build local test image"
    echo "  just podman-build          Build and push multi-platform Podman image"
    echo "  just podman-build-no-cache Build without cache"
    echo "  just podman-inspect        Inspect Podman manifest"
    echo "  just podman-login          Login to GHCR"
    echo ""
    echo "🧪 Test Build Commands (minimal images):"
    echo "  just test-build-docker     Test Docker build workflow (version as arg)"
    echo "  just test-build-podman     Test Podman build workflow (version as arg)"
    echo "  just test-build-docker 2.5.0   (example)"
    echo ""
    echo "🧹 Cleanup Commands:"
    echo "  just clean                 Clean up test images and logs"
    echo "  just clean-logs            Clean build logs"
    echo "  just clean-test-images     Remove test images"
    echo "  just podman-clean          Clean Podman test images"
    echo "  just clean-builder         Remove buildx builder"
    echo ""

@status:
    echo "🔍 Build Environment Status"
    echo "=============================="
    echo ""
    echo "📊 Configuration:"
    echo "  Docker Image:    {{ DOCKER_IMAGE }}"
    echo "  Podman Image:    {{ PODMAN_IMAGE }}"
    echo "  Current Version: $(cat {{ VERSION_FILE }})"
    echo "  Platforms:       {{ PLATFORMS }}"
    echo "  Current Platform: linux/{{ CURRENT_PLATFORM }}"
    echo ""
    echo "🐳 Docker Status:"
    docker info 2>/dev/null | grep -E "Operating System|OSType|Architecture" || echo "  ℹ️  Docker not running"
    echo ""
    echo "🏗️  Buildx Status:"
    docker buildx ls 2>/dev/null || echo "  ℹ️  buildx not available"
    echo ""
    echo "📦 Podman Status:"
    podman --version 2>/dev/null || echo "  ℹ️  Podman not installed"
    echo ""

@version:
    echo "Current VERSION: $(cat {{ VERSION_FILE }})"

# =============================================================================
# Version Management
# =============================================================================

@bump new_version:
    #!/bin/bash
    set -e

    OLD_VERSION=$(cat {{ VERSION_FILE }})
    NEW_VERSION="{{ new_version }}"

    echo "🔄 Bumping version from $OLD_VERSION to $NEW_VERSION"
    echo ""

    # Validate semantic version format
    if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "❌ Invalid version format: $NEW_VERSION"
        echo "   Use semantic versioning: X.Y.Z (e.g., 2.5.0)"
        exit 1
    fi

    # Update VERSION file
    echo "📝 Updating {{ VERSION_FILE }}..."
    echo "$NEW_VERSION" > {{ VERSION_FILE }}
    echo "   ✓ {{ VERSION_FILE }} updated to $NEW_VERSION"
    echo ""

    # Stage and commit
    echo "📌 Staging changes..."
    git add {{ VERSION_FILE }}
    echo "   ✓ VERSION file staged"
    echo ""

    echo "💾 Creating commit..."
    git commit -m "Bump version to $NEW_VERSION"
    echo "   ✓ Commit created"
    echo ""

    # Push to remote
    echo "🚀 Pushing to remote..."
    git push origin main
    echo "   ✓ Pushed to main branch"
    echo ""

    # Create and push tag
    echo "🏷️  Creating version tag..."
    git tag "v$NEW_VERSION" -m "Version $NEW_VERSION"
    echo "   ✓ Tag v$NEW_VERSION created"
    echo ""

    echo "📤 Pushing tag to remote..."
    git push origin "v$NEW_VERSION"
    echo "   ✓ Tag pushed to remote"
    echo ""

    echo "✨ Version bump complete!"
    echo ""
    echo "📢 Next steps:"
    echo "  1. Production Docker builds will trigger automatically on tag"
    echo "  2. Test builds can be triggered with:"
    echo "     just test-build-docker $NEW_VERSION"
    echo "     just test-build-podman $NEW_VERSION"
    echo ""

# =============================================================================
# Docker Targets
# =============================================================================

check-docker:
    #!/bin/bash
    echo "🔍 Checking Docker setup..."
    docker info > /dev/null 2>&1 || (echo "❌ Docker is not running" && exit 1)
    docker buildx version > /dev/null 2>&1 || (echo "❌ Docker buildx is not available" && exit 1)
    echo "✓ Docker and buildx are available"

setup-builder: check-docker
    #!/bin/bash
    echo "🔧 Setting up buildx builder..."
    if ! docker buildx ls | grep -q "{{ DOCKER_BUILDER }}"; then
        echo "📦 Creating new builder: {{ DOCKER_BUILDER }}"
        docker buildx create --name {{ DOCKER_BUILDER }} --driver docker-container --use
    else
        echo "✓ Using existing builder: {{ DOCKER_BUILDER }}"
        docker buildx use {{ DOCKER_BUILDER }}
    fi
    echo "🚀 Bootstrapping builder..."
    docker buildx inspect --bootstrap

login:
    #!/bin/bash
    echo "🔐 Logging in to Docker Hub..."
    if [ -n "$DOCKER_TOKEN" ]; then
        echo "Using DOCKER_TOKEN from environment"
        echo "$DOCKER_TOKEN" | docker login --username vnijs --password-stdin
    else
        echo "Running interactive login..."
        docker login
    fi

test-auth:
    #!/bin/bash
    echo "🧪 Testing Docker Hub authentication..."
    if docker manifest inspect {{ DOCKER_IMAGE }}:latest > /dev/null 2>&1; then
        echo "✓ Authentication working - you have access to {{ DOCKER_IMAGE }}"
    else
        echo "⚠️  Cannot access repository - login may be required"
    fi

test: setup-builder
    #!/bin/bash
    set -e
    echo "🔨 Building test image for linux/{{ CURRENT_PLATFORM }}..."
    mkdir -p build-logs
    docker buildx build \
        --platform linux/{{ CURRENT_PLATFORM }} \
        --tag {{ DOCKER_IMAGE }}:latest \
        --build-arg IMAGE_VERSION=test \
        --load \
        --progress=plain \
        -f {{ DOCKER_FILE }} \
        . 2>&1 | tee build-logs/test_$(date +%Y%m%d_%H%M%S).log
    echo "✓ Test build complete: {{ DOCKER_IMAGE }}:latest"

build: setup-builder test-auth
    #!/bin/bash
    set -e
    VERSION=$(cat {{ VERSION_FILE }})
    echo "🔨 Building multi-platform image: {{ DOCKER_IMAGE }}:$VERSION"
    echo "📍 Platforms: {{ PLATFORMS }}"
    echo "⏱️  This may take 30-60 minutes..."
    mkdir -p build-logs
    docker buildx build \
        --platform {{ PLATFORMS }} \
        --tag {{ DOCKER_IMAGE }}:$VERSION \
        --tag {{ DOCKER_IMAGE }}:latest \
        --build-arg IMAGE_VERSION=$VERSION \
        --push \
        --progress=plain \
        -f {{ DOCKER_FILE }} \
        . 2>&1 | tee build-logs/multiplatform-build_$(date +%Y%m%d_%H%M%S).log
    echo "✓ Build complete and pushed to Docker Hub"
    echo "📦 Image: {{ DOCKER_IMAGE }}:$VERSION"
    docker buildx imagetools inspect {{ DOCKER_IMAGE }}:$VERSION

build-no-cache: setup-builder test-auth
    #!/bin/bash
    set -e
    VERSION=$(cat {{ VERSION_FILE }})
    echo "🔨 Building multi-platform image (no cache): {{ DOCKER_IMAGE }}:$VERSION"
    echo "📍 Platforms: {{ PLATFORMS }}"
    mkdir -p build-logs
    docker buildx build \
        --platform {{ PLATFORMS }} \
        --tag {{ DOCKER_IMAGE }}:$VERSION \
        --tag {{ DOCKER_IMAGE }}:latest \
        --build-arg IMAGE_VERSION=$VERSION \
        --no-cache \
        --push \
        --progress=plain \
        -f {{ DOCKER_FILE }} \
        . 2>&1 | tee build-logs/multiplatform-build_$(date +%Y%m%d_%H%M%S).log
    echo "✓ Build complete and pushed to Docker Hub"

inspect:
    #!/bin/bash
    VERSION=$(cat {{ VERSION_FILE }})
    echo "🔍 Inspecting {{ DOCKER_IMAGE }}:$VERSION"
    docker buildx imagetools inspect {{ DOCKER_IMAGE }}:$VERSION

# =============================================================================
# Podman Targets
# =============================================================================

check-podman:
    #!/bin/bash
    echo "🔍 Checking Podman setup..."
    podman --version > /dev/null 2>&1 || (echo "❌ Podman is not installed" && exit 1)
    echo "✓ Podman is available"

podman-login: check-podman
    #!/bin/bash
    echo "🔐 Logging in to GHCR..."
    if command -v gh >/dev/null 2>&1; then
        echo "Using gh auth token"
        unset GH_TOKEN && gh auth token | podman login ghcr.io --username vnijs --password-stdin
    else
        echo "Running interactive login..."
        podman login ghcr.io
    fi

podman-test: check-podman
    #!/bin/bash
    set -e
    echo "🔨 Building Podman test image for linux/{{ CURRENT_PLATFORM }}..."
    mkdir -p build-logs
    podman build \
        --platform linux/{{ CURRENT_PLATFORM }} \
        --tag {{ PODMAN_IMAGE }}:test \
        --build-arg IMAGE_VERSION=test \
        --format docker \
        -f {{ CONTAINERFILE }} \
        . 2>&1 | tee build-logs/podman-test_$(date +%Y%m%d_%H%M%S).log
    echo "✓ Podman test build complete: {{ PODMAN_IMAGE }}:test"

podman-build: check-podman podman-login
    #!/bin/bash
    set -e
    VERSION=$(cat {{ VERSION_FILE }})
    echo "🔨 Building multi-platform Podman image: {{ PODMAN_IMAGE }}:$VERSION"
    echo "📍 Platforms: {{ PLATFORMS }}"
    mkdir -p build-logs

    podman manifest rm {{ PODMAN_IMAGE }}:$VERSION 2>/dev/null || true
    podman rmi {{ PODMAN_IMAGE }}:$VERSION 2>/dev/null || true
    podman manifest create {{ PODMAN_IMAGE }}:$VERSION

    for platform in $(echo {{ PLATFORMS }} | tr ',' ' '); do
        echo "🔨 Building for $platform..."
        podman build \
            --platform $platform \
            --tag {{ PODMAN_IMAGE }}:${VERSION}-$(echo $platform | tr '/' '-') \
            --build-arg IMAGE_VERSION=$VERSION \
            --format docker \
            -f {{ CONTAINERFILE }} \
            . 2>&1 | tee -a build-logs/podman-build_$(date +%Y%m%d_%H%M%S).log
        podman manifest add {{ PODMAN_IMAGE }}:$VERSION {{ PODMAN_IMAGE }}:${VERSION}-$(echo $platform | tr '/' '-')
    done

    echo "📤 Pushing manifest to GHCR..."
    podman manifest push --all {{ PODMAN_IMAGE }}:$VERSION docker://{{ PODMAN_IMAGE }}:$VERSION
    podman manifest push --all {{ PODMAN_IMAGE }}:$VERSION docker://{{ PODMAN_IMAGE }}:latest
    echo "✓ Build complete and pushed to GHCR"

podman-build-no-cache: check-podman podman-login
    #!/bin/bash
    set -e
    VERSION=$(cat {{ VERSION_FILE }})
    echo "🔨 Building multi-platform Podman image (no cache): {{ PODMAN_IMAGE }}:$VERSION"
    mkdir -p build-logs

    podman manifest rm {{ PODMAN_IMAGE }}:$VERSION 2>/dev/null || true
    podman rmi {{ PODMAN_IMAGE }}:$VERSION 2>/dev/null || true
    podman manifest create {{ PODMAN_IMAGE }}:$VERSION

    for platform in $(echo {{ PLATFORMS }} | tr ',' ' '); do
        echo "🔨 Building for $platform (no cache)..."
        podman build \
            --platform $platform \
            --tag {{ PODMAN_IMAGE }}:${VERSION}-$(echo $platform | tr '/' '-') \
            --build-arg IMAGE_VERSION=$VERSION \
            --no-cache \
            --format docker \
            -f {{ CONTAINERFILE }} \
            . 2>&1 | tee -a build-logs/podman-build-nocache_$(date +%Y%m%d_%H%M%S).log
        podman manifest add {{ PODMAN_IMAGE }}:$VERSION {{ PODMAN_IMAGE }}:${VERSION}-$(echo $platform | tr '/' '-')
    done

    podman manifest push --all {{ PODMAN_IMAGE }}:$VERSION docker://{{ PODMAN_IMAGE }}:$VERSION
    podman manifest push --all {{ PODMAN_IMAGE }}:$VERSION docker://{{ PODMAN_IMAGE }}:latest
    echo "✓ Build complete and pushed to GHCR"

podman-inspect:
    #!/bin/bash
    VERSION=$(cat {{ VERSION_FILE }})
    echo "🔍 Inspecting {{ PODMAN_IMAGE }}:$VERSION"
    podman manifest inspect {{ PODMAN_IMAGE }}:$VERSION

# =============================================================================
# Test Build Workflows (Minimal Images)
# =============================================================================

test-build-docker version="":
    #!/bin/bash
    VERSION="{{ version }}"

    if [ -z "$VERSION" ]; then
        echo "🚀 Triggering Test Docker Build with auto-generated version..."
        echo ""
        echo "📖 To use a specific version (e.g., 2.5.0):"
        echo "   just test-build-docker 2.5.0"
        echo ""
    else
        echo "🚀 Triggering Test Docker Build for version: $VERSION"
    fi

    echo "📝 Instructions:"
    echo "  1. Go to: https://github.com/radiant-ai-hub/rsm-podman/actions"
    echo "  2. Select: 'Test Build - Docker (Minimal)'"
    echo "  3. Click: 'Run workflow'"
    if [ -z "$VERSION" ]; then
        echo "  4. Leave version empty (auto-generates test-SHA)"
    else
        echo "  4. Enter version: $VERSION"
    fi
    echo "  5. Leave 'Push to registry' toggled ON"
    echo "  6. Click 'Run workflow'"
    echo ""
    echo "✓ Workflow will build amd64 and arm64 images in ~5-10 minutes"
    echo ""

test-build-podman version="":
    #!/bin/bash
    VERSION="{{ version }}"

    if [ -z "$VERSION" ]; then
        echo "🚀 Triggering Test Podman Build with auto-generated version..."
        echo ""
        echo "📖 To use a specific version (e.g., 2.5.0):"
        echo "   just test-build-podman 2.5.0"
        echo ""
    else
        echo "🚀 Triggering Test Podman Build for version: $VERSION"
    fi

    echo "📝 Instructions:"
    echo "  1. Go to: https://github.com/radiant-ai-hub/rsm-podman/actions"
    echo "  2. Select: 'Test Build - Podman (Minimal)'"
    echo "  3. Click: 'Run workflow'"
    if [ -z "$VERSION" ]; then
        echo "  4. Leave version empty (auto-generates test-SHA)"
    else
        echo "  4. Enter version: $VERSION"
    fi
    echo "  5. Leave 'Push to registry' toggled ON"
    echo "  6. Click 'Run workflow'"
    echo ""
    echo "✓ Workflow will build amd64 and arm64 images in ~5-10 minutes"
    echo ""

# =============================================================================
# Cleanup Targets
# =============================================================================

clean-logs:
    #!/bin/bash
    echo "🧹 Cleaning build logs..."
    rm -rf build-logs/*
    echo "✓ Logs cleaned"

clean-test-images:
    #!/bin/bash
    echo "🧹 Removing test images..."
    docker rmi {{ DOCKER_IMAGE }}:latest 2>/dev/null || true
    echo "✓ Test images removed"

podman-clean:
    #!/bin/bash
    echo "🧹 Removing Podman test images..."
    podman rmi {{ PODMAN_IMAGE }}:test 2>/dev/null || true
    podman rmi {{ PODMAN_IMAGE }} 2>/dev/null || true
    echo "✓ Podman test images removed"

clean-builder:
    #!/bin/bash
    echo "🧹 Removing buildx builder: {{ DOCKER_BUILDER }}"
    docker buildx rm {{ DOCKER_BUILDER }} || true
    echo "✓ Builder removed"

clean: clean-test-images clean-logs podman-clean
    #!/bin/bash
    echo "✓ Cleanup complete"
