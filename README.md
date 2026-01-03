# RSM Data Science Container

A multi-platform container image for data science and analytics, designed for RSM/MSBA courses. Pre-configured with Jupyter Lab, PySpark, Hadoop, PostgreSQL, and essential data science tools.

## Quick Start

### Using Docker (Docker Hub)

```bash
# Pull the image (automatically selects correct platform)
docker pull vnijs/rsm-msba-k8s:latest

# Run the container
./launch-docker-k8s.sh
```

### Using Podman (GitHub Container Registry)

```bash
# Pull the image
podman pull ghcr.io/radiant-ai-hub/rsm-podman:latest

# Run the container
./launch-rsm-podman.sh
```

## Available Images

| Registry | Image | Platforms |
|----------|-------|-----------|
| Docker Hub | `vnijs/rsm-msba-k8s` | linux/amd64, linux/arm64 |
| GitHub Container Registry | `ghcr.io/radiant-ai-hub/rsm-podman` | linux/amd64, linux/arm64 |

Both images support **Intel/AMD (amd64)** and **Apple Silicon (arm64)** architectures.

You can inspect the images here: <https://github.com/orgs/radiant-ai-hub/packages/container/package/rsm-podman>

## Features

- **Jupyter**: Interactive notebook in VS Coe
- **PySpark**: Apache Spark with Python bindings
- **Hadoop 3.3.4**: Distributed storage and processing
- **PostgreSQL 16**: Relational database with pgweb interface
- **Quarto 1.9.13**: Scientific publishing system
- **Java 17**: OpenJDK runtime
- **SSH Access**: Remote terminal access on port 2222
- **Oh My Zsh**: Enhanced shell experience with Powerlevel10k theme
- **UV**: Fast Python package manager
- **GitHub CLI**: `gh` command-line tool

### Ports

| Port | Service |
|------|---------|
| 8888 | Jupyter Lab |
| 8765 | PostgreSQL |
| 8282 | pgweb (database UI) |
| 2222 | SSH |

## Installation Guides

Detailed installation instructions for different operating systems:

- **macOS (Apple Silicon)**: [install/rsm-msba-macos-arm.md](install/rsm-msba-macos-arm.md)
- **Windows**: [install/rsm-msba-windows.md](install/rsm-msba-windows.md)

## GPU Support

A GPU-enabled variant is available for CUDA workloads:

- **Image**: Built from `rsm-podman-gpu/Containerfile`
- **CUDA Version**: 12.8
- **Requirements**: NVIDIA GPU with compatible drivers

## Version

Current version: See [VERSION](VERSION) file

Check the version inside a running container:
```bash
echo $IMAGE_VERSION
```

## Project Structure

```
rsm-podman/
├── docker-k8s/          # Docker multi-platform build
├── rsm-podman/          # Podman container definition
├── rsm-podman-gpu/      # GPU variant
├── files/               # Configuration and setup scripts
├── install/             # Installation documentation
├── scripts/             # Build utilities
└── .github/workflows/   # CI/CD pipelines
```

## Building from Source

### Docker (local build)

```bash
make docker-build VERSION=2.4.0
```

### Podman (via GitHub Actions)

Podman images are built automatically via GitHub Actions when:
- Code is pushed to the `main` branch
- A version tag is created (e.g., `v2.4.0`)

See [rsm-podman/README.md](rsm-podman/README.md) for CI/CD details.

## License

See individual component licenses within the container.
