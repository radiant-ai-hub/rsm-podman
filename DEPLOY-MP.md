# Multi-Platform Build Deployment Guide

This guide covers building and deploying multi-platform (AMD64 and ARM64) container images for both Docker Hub and GitHub Container Registry.

## Image Registries

| Registry | Image | Build Method |
|----------|-------|--------------|
| Docker Hub | `vnijs/rsm-msba-k8s` | Local (Make/Docker buildx) |
| GitHub Container Registry | `ghcr.io/radiant-ai-hub/rsm-podman` | GitHub Actions CI/CD |

---

## Part 1: Podman Images (GitHub Actions)

The `rsm-podman` images are built automatically via GitHub Actions and pushed to GHCR.

### Versioning

Version is controlled by the `VERSION` file in the repository root.

| Trigger | Version Format | Tags Created |
|---------|----------------|--------------|
| Push to `main` | `2.4.0-dev.abc1234` | Version only |
| Git tag `v2.4.0` | `2.4.0` | Version + `latest` |
| Manual (workflow_dispatch) | User-specified | Configurable |

### Releasing a New Version

```bash
# 1. Update the VERSION file
echo "2.5.0" > VERSION
git add VERSION
git commit -m "Bump version to 2.5.0"
git push origin main

# 2. Create and push the release tag
git tag v2.5.0
git push origin v2.5.0
```

This triggers a GitHub Actions build that:
- Builds multi-platform images (amd64 + arm64)
- Creates `ghcr.io/radiant-ai-hub/rsm-podman:2.5.0`
- Updates `ghcr.io/radiant-ai-hub/rsm-podman:latest`
- Runs integration tests

### Manual Workflow Trigger

You can also trigger a build manually from the GitHub Actions UI:

1. Go to **Actions** > **Build rsm-podman**
2. Click **Run workflow**
3. Optionally specify a custom version
4. Choose whether to tag as `latest`

### Checking Build Status

- View builds: https://github.com/radiant-ai-hub/rsm-podman/actions
- View packages: https://github.com/orgs/radiant-ai-hub/packages

---

## Part 2: Docker Images (Local Build)

This section covers building Docker images locally using Make and Docker buildx.

## Prerequisites

1. Docker Desktop installed and running
2. Docker Hub account with push access to `vnijs/rsm-msba-k8s`
3. Docker buildx available (included in Docker Desktop)

## Quick Start

### Using Make

The simplest way to build and deploy is using the provided Makefile:

```bash
# use for MS macos building
# security -v unlock-keychain ~/Library/Keychains/login.keychain-db
```

```bash
# View all available commands
IMAGE_VERSION="2.4.0"
make help

# Build and push multi-platform image (version: latest)
#make build

# Build and push with a specific version
make build VERSION=$IMAGE_VERSION

# Test build locally without pushing
make test
```

## Step-by-Step Deployment

### 1. Check Your Environment

Verify Docker is running and buildx is available:

```bash
make status
```

Or manually:

```bash
docker info
docker buildx version
```

### 2. Login to Docker Hub

Set your Docker Hub token as an environment variable:

```bash
export DOCKER_TOKEN=your_docker_hub_access_token
```

Then login:

```bash
make login
```

Or login manually:

```bash
docker login
```

### 3. Test Authentication

Verify you have push permissions:

```bash
make test-auth
```

### 4. Setup Multi-Platform Builder

Create and configure the buildx builder:

```bash
make setup-builder
```

This creates a builder instance that can build for multiple platforms simultaneously.

### 5. Build and Push

Build and push the multi-platform image:

```bash
# With default version (latest)
# make build

# With specific version
make build VERSION=$IMAGE_VERSION
```

This will:

- Build for both `linux/amd64` and `linux/arm64`
- Tag as both `vnijs/rsm-podman:$IMAGE_VERSION` and `vnijs/rsm-podman:latest`
- Push to Docker Hub
- Create detailed build logs in `build-logs/`

### 6. Verify the Build

Inspect the multi-platform manifest:

```bash
make inspect VERSION=$IMAGE_VERSION
```

You should see both `linux/amd64` and `linux/arm64` platforms listed.

## Testing Locally

Before pushing to Docker Hub, test the build locally:

```bash
# Build test image for your current platform
make test

# Run the test image
./launch-rsm-podman.sh
```

## Build Without Cache

If you need a completely fresh build:

```bash
make build-no-cache VERSION=$IMAGE_VERSION
```

## Build Logs

All builds create detailed logs in the `build-logs/` directory:

- `multiplatform-build_YYYYMMDD_HHMMSS.log` - Combined build log
- `build-amd64_YYYYMMDD_HHMMSS.log` - AMD64-specific logs
- `build-arm64_YYYYMMDD_HHMMSS.log` - ARM64-specific logs
- `test-build_YYYYMMDD_HHMMSS.log` - Test build logs

## Common Tasks

### Build a New Release

```bash
# Login if needed
make login

# Build and push
make build VERSION=$IMAGE_VERSION

# Verify
make inspect VERSION=$IMAGE_VERSION
```

### Clean Up

```bash
# Remove test images and logs
make clean

# Remove buildx builder
make clean-builder

# Remove only logs
make clean-logs
```

## Troubleshooting

### Authentication Issues

If you see authentication errors:

1. Verify your Docker Hub token:

   ```bash
   echo $DOCKER_TOKEN
   ```

2. Login again:

   ```bash
   make login
   ```

3. Test authentication:
   ```bash
   make test-auth
   ```

### Build Failures

1. Check the build logs in `build-logs/`
2. Try building without cache:
   ```bash
   make build-no-cache
   ```
3. Test locally first:
   ```bash
   make test
   ```

## Performance Notes

- Multi-platform builds take 30-60 minutes
- Test builds (single platform) take 15-30 minutes
- Builds use Docker layer caching when possible
- Use `--no-cache` for completely fresh builds

## Environment Variables

- `DOCKER_TOKEN` - Docker Hub access token (recommended)
- `DOCKER_USERNAME` - Docker Hub username
- `DOCKER_PASSWORD` - Docker Hub password (alternative to token)
- `VERSION` - Image version tag (default: latest)

## Additional Resources

### Documentation
- [Docker Buildx Documentation](https://docs.docker.com/buildx/working-with-buildx/)
- [Multi-platform Images Guide](https://docs.docker.com/build/building/multi-platform/)
- [GitHub Actions Workflows](https://docs.github.com/en/actions)

### Key Files
- `VERSION` - Semantic version for Podman builds
- `docker-k8s/Dockerfile` - Docker image definition
- `rsm-podman/Containerfile` - Podman image definition
- `.github/workflows/rsm-podman-build.yml` - GitHub Actions CI/CD
- `scripts-docker-mp/` - Docker build scripts
- `scripts-podman-mp/` - Podman build scripts
