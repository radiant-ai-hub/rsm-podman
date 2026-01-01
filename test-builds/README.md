# Test Builds - Minimal Images for Dual-Architecture Testing

This directory contains minimal test images for rapid iteration on the dual-architecture build and manifest creation infrastructure.

## Purpose

- **Fast iteration**: Test images build in ~3-5 minutes vs 30-60 minutes for full images
- **Infrastructure testing**: Validate multi-arch build, manifest creation, and registry operations
- **Core functionality**: Test UV package manager and pyrsm installation
- **Not for production**: These images are minimal and lack many production features

## Structure

- `docker/Dockerfile.minimal`: Minimal Docker test image based on python:3.13-slim
- `podman/Containerfile.minimal`: Minimal Podman test image (identical to Docker version)
- `docker/test-pyrsm.py`: Integration test script for pyrsm functionality
- `podman/test-pyrsm.py`: Symlink to docker/test-pyrsm.py

## Local Testing

Build and run locally using:

```bash
# Docker
docker buildx build \
  --platform linux/amd64 \
  -t rsm-test:local \
  -f test-builds/docker/Dockerfile.minimal \
  .
docker run --rm rsm-test:local

# Podman
podman build \
  --platform linux/amd64 \
  -t rsm-test:local \
  -f test-builds/podman/Containerfile.minimal \
  .
podman run --rm rsm-test:local
```

## GitHub Actions Workflows

### Test Docker Build
- **Workflow**: `.github/workflows/test-docker-build.yml`
- **Image**: `vnijs/rsm-msba-k8s-test:VERSION`
- **Trigger**: Manual (workflow_dispatch) or PR to test-builds/docker/
- **Features**: Builds both amd64/arm64, creates multi-arch manifest, runs tests

### Test Podman Build
- **Workflow**: `.github/workflows/test-podman-build.yml`
- **Image**: `ghcr.io/radiant-ai-hub/rsm-podman-test:VERSION`
- **Trigger**: Manual (workflow_dispatch) or PR to test-builds/podman/
- **Features**: Builds both amd64/arm64, creates multi-arch manifest, runs tests

### Running Manually

1. Go to Actions → Select "Test Build - Docker (Minimal)" or "Test Build - Podman (Minimal)"
2. Click "Run workflow"
3. Optional: Provide custom version (default: test-SHA)
4. Optional: Toggle "Push to registry" (default: true)
5. Click "Run workflow"

## What Gets Tested

### Build Process
- ✓ Multi-architecture builds (amd64 and arm64)
- ✓ UV package manager installation
- ✓ pyrsm installation with core dependencies
- ✓ Architecture-specific image creation

### Manifest Creation
- ✓ Tag-based manifest creation (same approach as production)
- ✓ Multi-arch manifest with both platforms
- ✓ `:latest` tag creation and promotion
- ✓ Registry push operations
- ✓ Manifest verification with imagetools/podman inspect

### Integration Tests
- ✓ Container startup on both architectures
- ✓ pyrsm import functionality
- ✓ Core module accessibility
- ✓ Basic pyrsm operations (compare_means)
- ✓ Architecture verification

## What's NOT Tested

These minimal images do NOT include:
- PostgreSQL
- Hadoop/Spark infrastructure
- SSH server
- Quarto
- pgweb
- oh-my-zsh
- Most production dependencies

For full integration testing, use the main workflows:
- `.github/workflows/rsm-docker-build.yml`
- `.github/workflows/rsm-podman-build.yml`

## Expected Performance

- **Base image pull**: ~30 seconds (python:3.13-slim is ~150MB)
- **Build time per arch**: ~2-3 minutes
- **Total workflow time**: ~5 minutes (both arches in parallel)
- **Image size**: ~500MB-1GB vs 8-10GB for production

## Use Cases

1. **Testing manifest creation changes**: Quickly validate workflow modifications
2. **Registry operation testing**: Test push/pull/manifest operations
3. **UV installation testing**: Validate UV package manager setup
4. **Architecture emulation**: Test QEMU arm64 emulation on amd64 runners
5. **Quick verification**: Sanity check before running full builds

## Differences from Production

| Aspect | Test Images | Production Images |
|--------|-------------|------------------|
| Base | python:3.13-slim | quay.io/jupyter/pyspark-notebook |
| Size | ~500MB-1GB | ~8-10GB |
| Build time | ~3-5 min | ~30-60 min |
| Services | None | PostgreSQL, SSH, Hadoop |
| Python deps | ~10 core packages | 50+ packages |
| Use case | Testing infrastructure | Full data science environment |

## Troubleshooting

**Build fails with UV errors:**
- Check UV installation step in Dockerfile.minimal
- Verify network connectivity to astral.sh

**Manifest creation fails:**
- Ensure both amd64 and arm64 builds completed successfully
- Check that architecture-specific tags exist in registry
- Verify registry credentials are valid

**Test script fails:**
- Check pyrsm installation in build logs
- Verify all core dependencies were installed
- Review test-pyrsm.py output for specific errors

**ARM64 build is slow:**
- This is expected - QEMU emulation is slower than native
- Minimal images help reduce emulation time vs full images
- Consider using native ARM64 runners if available
