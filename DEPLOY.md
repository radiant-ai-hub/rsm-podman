# Multi-Platform Build Deployment Guide

This guide covers building and deploying multi-platform (AMD64 and ARM64) container images for both Docker Hub and GitHub Container Registry.

## Quick Reference

**Most Common Command:**

```bash
# Make sure to commit (but don't push) any local changes first
git status

# Run local integration tests against latest images
just local-integration-tests

# add a tag trigger
git add .github/workflows/rsm-podman-build.yml justfile scripts/ensure-tag-triggers.py
git commit -m "Fix podman workflow YAML and justfile guard"
git push

# Bump version and trigger all builds automatically
just bump 2.6.13
```

**Available Commands:**

```bash
just help           # Show all available commands
just version        # Show current version
just status         # Show build environment status
just bump X.Y.Z     # Bump version and create release (recommended)
just build          # Build Docker image locally
just podman-build   # Build Podman image locally
just clean          # Clean up test images and logs
```

## Image Registries

| Registry | Image | Build Method |
|----------|-------|--------------|
| Docker Hub | `vnijs/rsm-msba-k8s` | GitHub Actions or Local (justfile + Docker buildx) |
| GitHub Container Registry | `ghcr.io/radiant-ai-hub/rsm-podman` | GitHub Actions (recommended) or Local (justfile + Podman) |

**Recommended Workflow:** Use `just bump X.Y.Z` to tag the version, which automatically triggers GitHub Actions builds for both registries.

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

Use the `bump` command to automate version management:

```bash
# Bump to new version
just bump 2.5.0
```

This automatically:
1. Updates the VERSION file to `2.5.0`
2. Creates a git commit
3. Pushes to main branch
4. Creates and pushes git tag `v2.5.0`

The git tag automatically triggers a GitHub Actions build that:
- Builds multi-platform images (amd64 + arm64)
- Creates `ghcr.io/radiant-ai-hub/rsm-podman:2.5.0`
- Updates `ghcr.io/radiant-ai-hub/rsm-podman:latest`
- Runs integration tests

**Optional: Quick Test Before Full Build**

To test with a minimal image before the full production build:

```bash
# Test Docker build (5 min vs 30-60 min for full build)
just test-build-docker 2.5.0

# Test Podman build to GHCR
just test-build-podman 2.5.0
```

These trigger fast test workflows that validate the multi-architecture build and manifest creation process.

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

This section covers building Docker images locally using the justfile and Docker buildx.

> **Note:** Most users should use GitHub Actions workflows instead of local builds. GitHub Actions automatically builds and deploys on git tags. Only use local builds if you need to test or deploy without pushing to git.

## Prerequisites

1. Docker Desktop installed and running
2. Docker Hub account with push access to `vnijs/rsm-msba-k8s`
3. Docker buildx available (included in Docker Desktop)

## Quick Start

### Using Justfile

The simplest way to build and deploy is using the provided justfile:

```bash
# View all available commands
just help

# Check current version
just version

# Build and push multi-platform Docker image
just build

# Test build locally without pushing
just test

# Build Podman image
just podman-build

# Test Podman build locally
just podman-test
```

## Step-by-Step Deployment

### 1. Check Your Environment

Verify Docker is running and buildx is available:

```bash
just status
```

This will show:
- Docker installation and version
- Docker buildx availability and platform support
- Podman installation status
- Current VERSION and configuration

### 2. Login to Docker Hub

Set your Docker Hub token as an environment variable:

```bash
export DOCKER_TOKEN=your_docker_hub_access_token
```

Then login:

```bash
just login
```

The justfile will automatically use the `DOCKER_TOKEN` environment variable if available, or prompt for interactive login.

### 3. Test Authentication

Verify you have push permissions:

```bash
just test-auth
```

### 4. Setup Multi-Platform Builder

Create and configure the buildx builder:

```bash
just setup-builder
```

This creates a builder instance that can build for multiple platforms (amd64 and arm64) simultaneously.

### 5. Build and Push

Build and push the multi-platform Docker image:

```bash
# Build with default version (latest)
just build

# Build without cache
just build-no-cache
```

This will:

- Build for both `linux/amd64` and `linux/arm64`
- Tag as `vnijs/rsm-msba-k8s:latest`
- Push to Docker Hub
- Create detailed build logs in `build-logs/`

**For Podman builds to GHCR:**

```bash
# Setup Podman login first
export GHCR_TOKEN=your_github_container_token
just podman-login

# Build and push
just podman-build
```

### 6. Verify the Build

Inspect the multi-platform manifest:

```bash
# Docker manifest
just inspect

# Podman manifest
just podman-inspect
```

You should see both `linux/amd64` and `linux/arm64` platforms listed.

## Testing Locally

Before pushing to Docker Hub, test the build locally:

```bash
# Build test image for your current platform
just test

# Run the test image
./launch-rsm-podman.sh
```

For Podman:

```bash
just podman-test
```

## Build Without Cache

If you need a completely fresh build without using cached layers:

```bash
# Docker
just build-no-cache

# Podman
just podman-build-no-cache
```

## Build Logs

All builds create detailed logs in the `build-logs/` directory:

- `multiplatform-build_YYYYMMDD_HHMMSS.log` - Combined build log
- `build-amd64_YYYYMMDD_HHMMSS.log` - AMD64-specific logs
- `build-arm64_YYYYMMDD_HHMMSS.log` - ARM64-specific logs
- `test-build_YYYYMMDD_HHMMSS.log` - Test build logs

## Common Tasks

### Bump Version and Release

The easiest way to manage version bumps and trigger production builds:

```bash
# Bump to new version (automates: VERSION update, commit, push, tag, push tag)
just bump 2.5.0
```

This automatically:
1. Updates the VERSION file
2. Creates a git commit with message "Bump version to 2.5.0"
3. Pushes to main branch
4. Creates git tag v2.5.0
5. Pushes the tag to remote
6. Triggers GitHub Actions production builds automatically

Then optionally test with minimal test images:

```bash
# Trigger test Docker build via GitHub Actions
# Go to Actions > Test Build - Docker (Minimal) > Run workflow
# Or follow instructions shown by:
just test-build-docker 2.5.0

# Trigger test Podman build via GitHub Actions
just test-build-podman 2.5.0
```

### Build and Push Manually

If you prefer to build locally:

```bash
# Login if needed
just login

# Build and push
just build

# Verify
just inspect
```

### Clean Up

```bash
# Remove test images and logs
just clean

# Remove buildx builder
just clean-builder

# Remove only logs
just clean-logs

# Remove only test images
just clean-test-images

# Remove Podman test images
just podman-clean
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
   just login
   ```

3. Test authentication:
   ```bash
   just test-auth
   ```

### Build Failures

1. Check the build logs in `build-logs/`
2. Try building without cache:
   ```bash
   just build-no-cache
   ```
3. Test locally first:
   ```bash
   just test
   ```

### Justfile Command Not Found

If `just` command is not found, install it:

```bash
# macOS (using Homebrew)
brew install just

# Linux (using Cargo)
cargo install just

# Other platforms: https://github.com/casey/just#installation
```

## Performance Notes

- Multi-platform builds take 30-60 minutes
- Test builds (single platform) take 15-30 minutes
- Builds use Docker layer caching when possible
- Use `--no-cache` for completely fresh builds

## Environment Variables

- `DOCKER_TOKEN` - Docker Hub access token (used by `just login`)
- `GHCR_TOKEN` - GitHub Container Registry token (used by `just podman-login`)
- `VERSION` - Image version file location (default: ./VERSION)

**Version Management:**
The current version is always read from the `VERSION` file in the repository root. Use `just bump X.Y.Z` to safely update it with proper git operations.

## Additional Resources

### Documentation
- [Docker Buildx Documentation](https://docs.docker.com/buildx/working-with-buildx/)
- [Multi-platform Images Guide](https://docs.docker.com/build/building/multi-platform/)
- [GitHub Actions Workflows](https://docs.github.com/en/actions)

### Key Files
- `justfile` - Build automation recipes (replaces Makefile)
- `VERSION` - Semantic version file
- `docker-k8s/Dockerfile` - Docker image definition
- `rsm-podman/Containerfile` - Podman image definition
- `test-builds/docker/Dockerfile.minimal` - Minimal test image for quick iteration
- `test-builds/podman/Containerfile.minimal` - Minimal Podman test image
- `.github/workflows/rsm-docker-build.yml` - Docker GitHub Actions CI/CD
- `.github/workflows/rsm-podman-build.yml` - Podman GitHub Actions CI/CD
- `.github/workflows/test-docker-build.yml` - Test Docker build workflow
- `.github/workflows/test-podman-build.yml` - Test Podman build workflow
- `scripts-docker-mp/` - Docker build scripts (legacy)
- `scripts-podman-mp/` - Podman build scripts (legacy)


## Testing Docker Image Locally

IMAGE="vnijs/rsm-msba-k8s:latest"
IMAGE="vnijs/rsm-msba-k8s:2.6.9"

1) Clean slate

```bash
clear
docker rm -f rsm-test || true
```

2) Run container and keep logs

```bash
docker run -d --name rsm-test -p 8765:8765 -p 2222:2222 $IMAGE /usr/local/bin/start-container.sh
```

3) Check status and exit code

```bash
docker ps -a --filter name=rsm-test
```

```bash
docker inspect rsm-test --format 'State={{.State.Status}} ExitCode={{.State.ExitCode}}'
```

4) Dump full container logs

```bash
docker logs rsm-test
```

5) If it’s still running, inspect processes

```bash
docker exec rsm-test ps aux
```

```bash
docker exec rsm-test bash -lc 'ls -l /var/log/postgresql && tail -n +1 /var/log/postgresql/postgresql-*.log'
```

6) Check healthcheck manually

```bash
docker exec rsm-test pg_isready -h localhost -p 8765 -U jovyan
```

## Extra

1) Start a debug shell inside the image

```bash
docker run --rm -it --entrypoint bash $IMAGE
```

2) Check permissions that commonly break Postgres

```bash
id
stat -c '%U:%G %a %n' /var/lib/postgresql/16/main /var/run/postgresql /var/log/postgresql
ls -la /var/run/postgresql
```

3) Run the startup with tracing

```bash
bash -x /usr/local/bin/start-container.sh
echo "exit=$?"
cat /var/log/postgresql/postgresql-*.log
```

4) Immediately inspect Postgres logs

```bash
ls -la /var/log/postgresql
tail -n +1 /var/log/postgresql/postgresql-*.log
```

5) If Postgres dies, check for socket/lock errors

```bash
grep -n "FATAL\|ERROR\|permission\|lock file\|could not create" /var/log/postgresql/postgresql-*.log
```

If you want to keep the container alive for inspection instead of it exiting, use:

```bash
/usr/local/bin/start-container.sh &
sleep 3
ps aux | egrep 'postgres|sshd'
```

docker exec rsm-test bash -l -c '/opt/base-uv/.venv/bin/python -c "import pyspark; print(f\"PySpark version: {pyspark.__version__}\")"'

## Testing Podman Image Locally

IMAGE="ghcr.io/radiant-ai-hub/rsm-podman:latest"


1) Clean slate

```bash
clear
podman rm -f rsm-test || true
```

2) Run container and keep logs

```bash
podman run -d --name rsm-test -p 8765:8765 -p 2222:2222 $IMAGE /usr/local/bin/start-container.sh
```

3) Check status and exit code

```bash
podman ps -a --filter name=rsm-test
```

```bash
podman inspect rsm-test --format 'State={{.State.Status}} ExitCode={{.State.ExitCode}}'
```

4) Dump full container logs

```bash
podman logs rsm-test
```

5) If it’s still running, inspect processes

```bash
podman exec rsm-test ps aux;
```

```bash
podman exec rsm-test bash -lc 'ls -l /var/log/postgresql && tail -n +1 /var/log/postgresql/postgresql-*.log'
```

6) Check healthcheck manually

```bash
podman exec rsm-test pg_isready -h localhost -p 8765 -U jovyan
```

## Extra

1) Start a debug shell inside the image

```bash
podman run --rm -it --entrypoint bash $IMAGE
```

2) Check permissions that commonly break Postgres

```bash
id
stat -c '%U:%G %a %n' /var/lib/postgresql/16/main /var/run/postgresql /var/log/postgresql
ls -la /var/run/postgresql
```

3) Run the startup with tracing

```bash
bash -x /usr/local/bin/start-container.sh
echo "exit=$?"
cat /var/log/postgresql/postgresql-*.log
```

4) Immediately inspect Postgres logs

```bash
ls -la /var/log/postgresql
tail -n +1 /var/log/postgresql/postgresql-*.log
```

5) If Postgres dies, check for socket/lock errors

```bash
grep -n "FATAL\|ERROR\|permission\|lock file\|could not create" /var/log/postgresql/postgresql-*.log
```

If you want to keep the container alive for inspection instead of it exiting, use:

```bash
/usr/local/bin/start-container.sh &
sleep 3
ps aux | egrep 'postgres|sshd'
`



docker run --rm -it --entrypoint bash vnijs/rsm-msba-k8s:2.6.8

Inside the container:

mkdir -p /var/run/postgresql
sudo chown jovyan:users /var/run/postgresql
chmod 775 /var/run/postgresql
bash -x /usr/local/bin/start-container.sh



docker ps
docker exec -it 6d3b684d6587 pg_isready -h localhost -p 8765 -U jovyan
