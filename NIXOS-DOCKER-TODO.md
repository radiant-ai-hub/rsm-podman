# NixOS Docker/Podman Configuration Guide

## Current Setup

Your NixOS system currently has:

- ✅ Docker v29.1.2 enabled and starts on boot
- ✅ Podman enabled (dockerCompat = false)
- ✅ User in docker group (can run without sudo)
- ✅ lazydocker UI tool for container management
- ✅ VS Code Docker extension (v2.0.0)

**Location**: `~/nixos-config/hosts/s76-nixos/configuration.nix:187-194`

---

## Enhancement Options

### 1. Enable Rootless Docker (Recommended for Security)

Rootless Docker runs without root privileges, improving security isolation.

**Edit**: `~/nixos-config/hosts/s76-nixos/configuration.nix`

```nix
virtualisation.docker = {
  enable = true;
  enableOnBoot = true;
  rootless = {
    enable = true;
    setSocketVariable = true;
  };
};
```

**Benefits**:
- No privilege escalation needed
- Better isolation from host
- Safer for development environments
- Still works with docker/podman CLI normally

**Trade-offs**:
- Slightly slower than rootful Docker
- Some advanced features may have limitations
- Existing containers won't automatically be rootless

---

### 2. Enable Podman Docker Compatibility (Alternative to Docker)

Use Podman as a drop-in replacement for Docker. Podman is more security-conscious and doesn't require a daemon.

**Edit**: `~/nixos-config/hosts/s76-nixos/configuration.nix`

```nix
virtualisation.podman = {
  enable = true;
  dockerCompat = true;  # Changes from current: false
};

# Optionally disable regular docker if using podman exclusively
virtualisation.docker = {
  enable = false;  # Remove if you want both
};
```

**Benefits**:
- No daemon process
- Better systemd integration
- More aligned with OCI standards
- Rootless by default

**Trade-offs**:
- Some tools may prefer Docker daemon
- Different architecture (no central daemon)
- Less widespread than Docker

---

### 3. Docker Configuration Options

Add custom daemon settings for resource limits, logging, storage, etc.

**Edit**: `~/nixos-config/hosts/s76-nixos/configuration.nix`

```nix
virtualisation.docker = {
  enable = true;
  enableOnBoot = true;

  # Custom daemon configuration
  extraOptions = ''
    --storage-driver overlay2
    --log-driver json-file
    --log-opt max-size=10m
    --log-opt max-file=5
  '';

  # Resource limits for daemon
  daemonOptions = [
    "--dns 8.8.8.8"
    "--dns 8.8.4.4"
  ];
};
```

---

### 4. OCI Image Building with Nix

Build Docker/OCI images declaratively using Nix. No need for Dockerfile.

**Example**: `~/nixos-config/home/vnijs/containers/my-app.nix`

```nix
{ pkgs }:

pkgs.dockerTools.buildImage {
  name = "my-app";
  tag = "latest";

  fromImage = pkgs.dockerTools.pullImage {
    imageName = "nixos/nix";
    imageDigest = "sha256:...";
    sha256 = "...";
  };

  copyToRoot = pkgs.buildEnv {
    name = "image-root";
    paths = with pkgs; [ python3 postgresql curl ];
    pathsToLink = [ "/bin" "/lib" ];
  };

  config = {
    Env = [ "PATH=/bin:/usr/bin" ];
    Entrypoint = [ "${pkgs.python3}/bin/python" ];
    Cmd = [ "app.py" ];
  };
}
```

**Benefits**:
- Reproducible, declarative images
- No Dockerfile needed
- Can use any NixOS package
- Images are minimal (Nix only includes needed deps)

---

### 5. Docker as Systemd Service

Run containers via NixOS service definitions instead of manual commands.

**Example**: `~/nixos-config/hosts/s76-nixos/docker-services.nix`

```nix
systemd.services.my-container = {
  description = "My Docker Container";
  after = [ "docker.service" ];
  requires = [ "docker.service" ];
  wantedBy = [ "multi-user.target" ];

  environment.DOCKER_HOST = "unix:///run/docker.sock";

  serviceConfig = {
    Type = "simple";
    ExecStart = ''
      ${pkgs.docker}/bin/docker run \
        --name my-container \
        --rm \
        -v /home/vnijs:/root \
        my-image:latest
    '';
    Restart = "on-failure";
    RestartSec = 10;
  };
};
```

---

## Persistent Flakes/Shells with Docker + Mounted Home

### Architecture

When running a NixOS Docker container with your home directory mounted from macOS:

```
macOS System              Docker Container
  ~/                  <-->  /root (mounted)
  ├── dev/
  │   └── my-project/
  │       ├── flake.nix       (PERSISTS)
  │       ├── flake.lock      (PERSISTS)
  │       └── shell.nix       (PERSISTS)
  └── .envrc               (PERSISTS)

  /nix/store (host)       /nix/store (container)
  └── [packages]  <X>     └── [rebuilt on restart]
                          (unless mounted volume used)
```

### What Persists

✅ **Across restarts**:
- `flake.nix` files
- `flake.lock` files
- `shell.nix` files
- `.envrc` direnv configuration
- Source code
- All text-based config files

❌ **Does NOT persist** (by default):
- Built Nix store packages (rebuilt on next use)
- Container filesystem state

### What to Do for Persistent Store

If you want the **Nix store** to persist (faster rebuilds after restart):

Mount a Docker volume for `/nix/store`:

```bash
docker run \
  -v ~/:/root \
  -v nix-store:/nix/store \
  -v nix-var:/var/lib \
  -it nixos /bin/bash
```

Or with docker-compose:

```yaml
services:
  nixos-dev:
    image: nixos
    volumes:
      - ~/:/root
      - nix-store:/nix/store
      - nix-var:/var/lib

volumes:
  nix-store:
  nix-var:
```

---

## Practical Workflow Example

### Setup (One-time)

```bash
# On macOS, create a project directory
mkdir -p ~/dev/my-project
cd ~/dev/my-project

# Create a flake for your development environment
cat > flake.nix <<'EOF'
{
  description = "Python + PostgreSQL dev environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            python3
            postgresql
            nodejs
            sqlite
          ];

          shellHook = ''
            echo "Development environment loaded!"
            python3 --version
            postgres --version
          '';
        };
      }
    );
}
EOF

# Create a .envrc for auto-loading
cat > .envrc <<'EOF'
use flake
EOF

# Commit this to your repo
git add flake.nix .envrc
git commit -m "Add development environment flake"
```

### Usage (Every session)

```bash
# On macOS host
cd ~/dev/my-project

# Option 1: Run with docker
docker run -v ~/:/root -it nixos /bin/bash

# Inside container
cd /root/dev/my-project
direnv allow

# Environment is now set up!
# python3, postgres, etc. are all available

# Exit when done
exit

# Next time: Same command, flake.lock already exists
# Just re-downloads/rebuilds packages (still fast with cache)
```

### Benefits of This Approach

1. **Same environment everywhere**: macOS host, container, CI/CD
2. **Reproducible**: flake.lock ensures exact versions
3. **Declarative**: All dependencies listed in flake.nix
4. **Portable**: Move entire ~/dev directory between systems
5. **Version controlled**: Track environment changes in git
6. **Container-agnostic**: Works with Docker, Podman, NixOS directly

---

## Recommended Next Steps

### Priority 1: Add Rootless Docker
```bash
# Edit ~/nixos-config/hosts/s76-nixos/configuration.nix
# Add rootless config (see section above)
# Then: just rebuild "Add rootless Docker"
```

### Priority 2: Consider Podman Docker Compat
```bash
# If you prefer podman architecture over Docker
# Edit configuration.nix to enable dockerCompat = true
```

### Priority 3: Create Reusable Flakes
```bash
# Create ~/gh/nix-shells/ repo with flakes for different workflows:
# - ~/gh/nix-shells/python/flake.nix
# - ~/gh/nix-shells/node/flake.nix
# - ~/gh/nix-shells/rust/flake.nix
# Then symlink to ~/nix-shells and use direnv
```

### Priority 4: Docker Compose with Persistent Volumes
```bash
# For complex multi-container setups
# Create docker-compose.yml with:
# - volumes for ~/home and /nix/store
# - services that mount these
```

---

## Files to Modify

| File | Change | Impact |
|------|--------|--------|
| `~/nixos-config/hosts/s76-nixos/configuration.nix` | Add rootless Docker config | Requires rebuild, better security |
| `~/nixos-config/hosts/s76-nixos/configuration.nix` | Set podman dockerCompat = true | Requires rebuild, alternative to Docker |
| `~/gh/nix-shells/` (create) | Add reusable flakes | No rebuild needed, adds convenience |

---

## Troubleshooting

**Problem**: Flake changes not applied in container
**Solution**: Delete `flake.lock`, run `nix flake update`, then `direnv allow`

**Problem**: Packages disappear after restart
**Solution**: Mount `/nix/store` as Docker volume (see section above)

**Problem**: Permission issues with mounted home
**Solution**: Run container as same UID/GID as macOS user:
```bash
docker run --user $(id -u):$(id -g) -v ~/:/home/user -it nixos /bin/bash
```

**Problem**: Rootless Docker can't run some containers
**Solution**: Use rootful Docker for those, rootless for development

---

## Resources

- [NixOS Docker Documentation](https://nixos.org/manual/nixos/stable/#sec-docker)
- [Podman on NixOS](https://nixos.wiki/wiki/Podman)
- [Nix Flakes Documentation](https://nixos.wiki/wiki/Flakes)
- [direnv for automatic environment loading](https://direnv.net/)
- [Docker Images with Nix](https://nixos.org/manual/nixpkgs/stable/#sec-pkgs-dockerTools)

---

## Next Steps

1. Decide: Rootless Docker + Docker, or Podman with compat?
2. Update `configuration.nix` with your choice
3. Rebuild: `just rebuild "Add rootless docker config"`
4. Test: `docker run hello-world`
5. Create `~/gh/nix-shells/` repo with reusable flakes
6. Mount home directory in containers and use direnv

Questions? Check the NixOS manual or the resources above!
