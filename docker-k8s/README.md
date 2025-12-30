# RSM Docker Container Build

This directory contains the Dockerfile and build configuration for the `rsm-msba-k8s` Docker image, which is built automatically via GitHub Actions and pushed to Docker Hub and GitHub Container Registry.

## Image Locations

| Registry | Image |
|----------|-------|
| Docker Hub | `vnijs/rsm-msba-k8s` |
| GHCR | `ghcr.io/radiant-ai-hub/rsm-msba-k8s` |

```bash
# Pull from Docker Hub
docker pull vnijs/rsm-msba-k8s:latest

# Pull from GHCR
docker pull ghcr.io/radiant-ai-hub/rsm-msba-k8s:latest

# Pull a specific version
docker pull vnijs/rsm-msba-k8s:2.4.0
```

## CI/CD Pipeline

Images are built automatically using GitHub Actions (`.github/workflows/rsm-docker-build.yml`).

### Build Triggers

| Trigger | Version Format | Tags Created |
|---------|----------------|--------------|
| Push to `main` | `2.4.0-dev.abc1234` | Version only |
| Git tag `v2.4.0` | `2.4.0` | Version + `latest` |
| Manual (workflow_dispatch) | User-specified | Configurable |

### Build Process

1. **Parallel platform builds**: amd64 and arm64 images are built separately
2. **Dual registry push**: Images are pushed to both Docker Hub and GHCR
3. **Manifest creation**: Multi-architecture manifests for both registries
4. **Integration tests**: Automated tests verify PostgreSQL, SSH, Java, PySpark, and Hadoop

### Triggering a Release Build

To create a new versioned release:

```bash
# 1. Update the VERSION file (in repository root)
echo "2.5.0" > VERSION
git add VERSION
git commit -m "Bump version to 2.5.0"
git push origin main

# 2. Create and push the release tag
git tag v2.5.0
git push origin v2.5.0
```

This triggers a build that creates:
- `vnijs/rsm-msba-k8s:2.5.0` (Docker Hub)
- `vnijs/rsm-msba-k8s:latest` (Docker Hub)
- `ghcr.io/radiant-ai-hub/rsm-msba-k8s:2.5.0` (GHCR)
- `ghcr.io/radiant-ai-hub/rsm-msba-k8s:latest` (GHCR)

### Manual Workflow Trigger

You can trigger a manual build from the GitHub Actions UI:

1. Go to **Actions** > **Build rsm-msba-k8s (Docker)**
2. Click **Run workflow**
3. Optionally specify a custom version
4. Choose whether to tag as `latest`

## Dockerfile Overview

**Base Image**: `quay.io/jupyter/pyspark-notebook:2025-12-15`

### Key Components

| Component | Version | Notes |
|-----------|---------|-------|
| PostgreSQL | 16 | Port 8765 |
| Quarto | 1.9.13 | Scientific publishing |
| Hadoop | 3.3.4 | HDFS support |
| Java | 17 | OpenJDK |
| pgweb | 0.11.11 | Database UI on port 8282 |
| SSH | OpenSSH | Port 2222 |

### Platform Support

The Dockerfile supports both architectures:
- **ARM64** (Apple Silicon, AWS Graviton)
- **AMD64** (Intel/AMD x86_64)

Platform-specific handling:
- Java paths: `/usr/lib/jvm/java-17-openjdk-arm64/` vs `/usr/lib/jvm/java-17-openjdk-amd64/`
- pgweb binary: `pgweb_linux_arm64_v7.zip` vs `pgweb_linux_amd64.zip`

## Files

```
docker-k8s/
├── Dockerfile    # Multi-platform Docker image definition
└── README.md     # This file
```

## Local Building (Optional)

While CI/CD handles production builds, you can build locally for testing:

```bash
# From repository root
docker buildx build \
  --platform linux/amd64 \
  --build-arg IMAGE_VERSION=test \
  -f docker-k8s/Dockerfile \
  -t rsm-msba-k8s:test \
  .

# For multi-platform local build (requires buildx)
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg IMAGE_VERSION=test \
  -f docker-k8s/Dockerfile \
  -t rsm-msba-k8s:test \
  .
```

## Troubleshooting

### Build Fails in CI

1. Check GitHub Actions logs for specific errors
2. Verify disk space cleanup is working (builds require ~20GB)
3. Check Docker Hub authentication (`DOCKER_USERNAME`, `DOCKER_TOKEN` secrets)
4. Check GHCR authentication (`GHCR_TOKEN` secret)

### Image Won't Pull

```bash
# Check available tags on Docker Hub
docker search vnijs/rsm-msba-k8s

# Authenticate if needed
docker login
```

### Platform Mismatch

```bash
# Explicitly specify platform
docker pull --platform linux/arm64 vnijs/rsm-msba-k8s:latest
docker pull --platform linux/amd64 vnijs/rsm-msba-k8s:latest
```

## Related Files

- **Workflow**: `.github/workflows/rsm-docker-build.yml`
- **Version**: `VERSION` (repository root)
- **Launch script**: `launch-docker-k8s.sh`
- **Podman equivalent**: `rsm-podman/Containerfile`
