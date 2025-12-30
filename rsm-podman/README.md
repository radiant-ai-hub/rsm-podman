# RSM Podman Container Build

This directory contains the Containerfile and build configuration for the `rsm-podman` image, which is built automatically via GitHub Actions and pushed to GitHub Container Registry (GHCR).

## Image Location

**Registry**: `ghcr.io/radiant-ai-hub/rsm-podman`

```bash
# Pull the latest image
podman pull ghcr.io/radiant-ai-hub/rsm-podman:latest

# Pull a specific version
podman pull ghcr.io/radiant-ai-hub/rsm-podman:2.4.0
```

## CI/CD Pipeline

Images are built automatically using GitHub Actions (`.github/workflows/rsm-podman-build.yml`).

### Build Triggers

| Trigger | Version Format | Tags Created |
|---------|----------------|--------------|
| Push to `main` | `2.4.0-dev.abc1234` | Version only |
| Git tag `v2.4.0` | `2.4.0` | Version + `latest` |
| Manual (workflow_dispatch) | User-specified | Configurable |

### Build Process

1. **Parallel platform builds**: amd64 and arm64 images are built separately on GitHub runners
2. **Manifest creation**: A multi-architecture manifest combines both platform images
3. **Integration tests**: Automated tests verify PostgreSQL, SSH, Java, PySpark, and Hadoop functionality
4. **Push to GHCR**: Images are pushed to GitHub Container Registry

### Triggering a Release Build

To create a new versioned release:

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

This triggers a release build that:
- Creates `ghcr.io/radiant-ai-hub/rsm-podman:2.5.0`
- Updates `ghcr.io/radiant-ai-hub/rsm-podman:latest`

### Manual Build

You can trigger a manual build from the GitHub Actions UI:

1. Go to **Actions** > **Build rsm-podman**
2. Click **Run workflow**
3. Optionally specify a custom version
4. Choose whether to tag as `latest`

## Containerfile Overview

**Base Image**: `quay.io/jupyter/pyspark-notebook:2025-12-15`

### Key Components

| Component | Version | Notes |
|-----------|---------|-------|
| PostgreSQL | 16 | Non-privileged port 8765 |
| Quarto | 1.9.13 | Scientific publishing |
| Hadoop | 3.3.4 | HDFS support |
| Java | 17 | OpenJDK |
| pgweb | latest | Database UI on port 8282 |
| SSH | OpenSSH | Port 2222 |

### Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `IMAGE_VERSION` | `latest` | Version embedded in container |
| `TARGETPLATFORM` | (auto) | Build platform |
| `TARGETARCH` | (auto) | Target architecture (amd64/arm64) |

### Rootless Design

The container is optimized for rootless Podman operation:
- All services run as user `jovyan` (UID 1000)
- Non-privileged ports (2222, 8765, 8282)
- Compatible with `--userns=keep-id`

## Files

```
rsm-podman/
├── Containerfile    # Main container definition
└── README.md        # This file
```

## Local Building (Optional)

While CI/CD handles production builds, you can build locally for testing:

```bash
# From repository root
podman build \
  --platform linux/amd64 \
  --build-arg IMAGE_VERSION=test \
  -f rsm-podman/Containerfile \
  -t rsm-podman:test \
  .
```

## Troubleshooting

### Build Fails in CI

1. Check GitHub Actions logs for specific errors
2. Verify disk space cleanup is working (builds require ~20GB)
3. Check GHCR authentication (GHCR_TOKEN secret)

### Image Won't Pull

```bash
# Authenticate to GHCR
echo $GITHUB_TOKEN | podman login ghcr.io -u USERNAME --password-stdin

# Verify image exists
podman search ghcr.io/radiant-ai-hub/rsm-podman
```

### Platform Mismatch

```bash
# Explicitly specify platform
podman pull --platform linux/arm64 ghcr.io/radiant-ai-hub/rsm-podman:latest
podman pull --platform linux/amd64 ghcr.io/radiant-ai-hub/rsm-podman:latest
```

## Related Files

- **Workflow**: `.github/workflows/rsm-podman-build.yml`
- **Version**: `VERSION` (repository root)
- **Launch script**: `launch-rsm-podman.sh`
- **GPU variant**: `rsm-podman-gpu/Containerfile`
