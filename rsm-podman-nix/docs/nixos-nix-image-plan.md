# Plan: Nix-Based RSM Podman Image

## Goal

Build a replacement Podman image that preserves the user-facing behavior of the current `ghcr.io/radiant-ai-hub/rsm-podman` image while using `nixos/nix` as the base image and removing Conda/Mamba completely.

The target image should:

- Start from `nixos/nix`, not `quay.io/jupyter/pyspark-notebook`.
- Use Nix for system/runtime binaries and native libraries.
- Use `uv` as the Python environment and package management tool.
- Keep `/opt/base-uv/.venv` as the primary Python environment because current scripts, aliases, tests, and docs already expect it.
- Use the user's official username as the in-container account and home directory when provided, for example `xyz123@ucsd.edu` maps to `/home/xyz123`.
- Run PySpark and Hadoop reliably on both `linux/amd64` and `linux/arm64`.
- Preserve rootless Podman behavior with the resolved user, `--userns=keep-id`, mounted home directories, and a persistent PostgreSQL volume.
- Preserve the current service surface: SSH, PostgreSQL, pgweb, Hadoop/HDFS scripts, PySpark, Jupyter tools, Quarto, GitHub CLI, zsh/oh-my-zsh tooling, and RSM helper commands.

## Current Image Facts To Preserve

Observed from the repository and lightweight image metadata:

- Current published image: `ghcr.io/radiant-ai-hub/rsm-podman:latest`
  - Manifest digest observed: `sha256:62acd2d7a11cc086d7d21ad33b62c5d9bf459c89018e2ea8a39aee9caae5b1e5`
  - Platforms: `linux/amd64`, `linux/arm64`
- Current base image: `quay.io/jupyter/pyspark-notebook:2025-12-15`
  - Manifest digest observed: `sha256:42188f36f90acd245b8217ad86ebb2b421115e9ee3645ec58482ad3236a8e81b`
  - Platforms: `linux/amd64`, `linux/arm64`
- Preferred Nix base candidate: `nixos/nix:2.31.3`
  - Manifest digest observed: `sha256:d49538facc7757890eccfa5f57869ad18c823c24903e3b8ac6ca8a301d84a9b6`
  - Platforms: `linux/amd64`, `linux/arm64`

Current container behavior to keep:

| Area | Current behavior |
| --- | --- |
| User | `jovyan`, home `/home/jovyan`, zsh default shell, passwordless sudo |
| Rootless ports | SSH `2222`, pgweb `8282`, PostgreSQL `8765` |
| Volumes | Host home mounted to `/home/jovyan`; `pg_data` mounted to `/var/lib/postgresql/16/main` |
| PostgreSQL | Version 16, rootless runtime under `jovyan`, databases `jovyan` and `rsm-msba`, default password `postgres` |
| SSH | OpenSSH on port `2222`, key auth enabled, password auth disabled |
| pgweb | Compatibility command `/usr/local/bin/pgweb_binary`, UI listens on `8282` and connects to PostgreSQL on `8765` |
| Hadoop | `HADOOP_HOME=/opt/hadoop`, current configured version `3.3.4`, scripts `init-dfs.sh`, `start-dfs.sh`, `stop-dfs.sh` |
| Spark | `SPARK_HOME=/usr/local/spark`, PySpark import and local Spark sessions must work |
| Python | Current package env at `/opt/base-uv/.venv`; current build still depends on `/opt/conda/bin/python` for the base interpreter, which must be removed |
| Quarto | Current image config uses `QUARTO_VERSION=1.9.13` |
| Shell | zsh, oh-my-zsh, powerlevel10k, autojump, uv completions, aliases including `sbase`, `pgweb`, `sp` |
| Helper CLIs | `usethis`, `iusethis`, `github`, `setup`, `menu` in `/usr/local/bin` |
| CI validation | PostgreSQL, SSH, Java, PySpark, Hadoop, pgweb, and rootless startup tests |

Nix image username behavior:

- Replace the hard-coded `jovyan` account as the primary runtime identity.
- Resolve the container username at runtime in this order:
  1. `RSM_USERNAME`, if set.
  2. Prefix of `RSM_USER_EMAIL`, if set, for example `xyz123@ucsd.edu` becomes `xyz123`.
  3. A neutral fallback such as `rsmuser` for local smoke tests and unauthenticated use.
- Set `HOME=/home/<resolved-username>`, `USER=<resolved-username>`, and `LOGNAME=<resolved-username>`.
- Create the resolved user at container startup with `RSM_UID` and `RSM_GID`, defaulting to `1000:1000`.
- Keep `NB_USER` as an optional legacy compatibility variable only where old scripts still need it during transition.
- Update launch scripts later so the host can pass `RSM_USER_EMAIL` or `RSM_USERNAME` and mount the host home at `/home/<resolved-username>`.

One discrepancy to resolve during implementation: top-level docs mention Jupyter on port `8888`, but `launch-rsm-podman.sh` currently maps only `2222`, `8282`, and `8765`. The Nix image should include Jupyter tooling for parity with the old base image. Whether the launch script should also map `8888` should be decided and documented during implementation.

## Host/Nix Characteristics Worth Reusing

This session is running on `m1-nixos`:

- `nixos-version`: `26.05.20260401.6201e20`
- `builtins.currentSystem`: `aarch64-linux`
- `nix`: `2.31.3`
- Host flake uses `nixos-unstable`.
- Host Python module uses:
  - `python313`
  - `uv`
  - `UV_LINK_MODE=copy`
  - `PIP_REQUIRE_VIRTUALENV=true`
  - ARM-specific `gfortran` support for packages such as `scikit-misc`

Do not make the container depend on the personal host config. Reuse the same ideas, especially flakes, `uv`, Python 3.13, ARM-native build tooling, and `UV_LINK_MODE=copy`.

Useful nixpkgs versions observed in the current flake/channel:

| Package | Nix attribute/version observed | Plan |
| --- | --- | --- |
| Nix base | `nixos/nix:2.31.3` | Use as `FROM`, pinned by digest |
| Python | `python313` `3.13.12` | Use with `uv`; see Python strategy below |
| uv | `uv` `0.11.2` | Install through Nix, manage Python env with uv |
| Java | `openjdk17` `17.0.18+8` | Keep Java 17 |
| Spark | `spark` `4.0.1`, `spark_3_5` `3.5.5`, `spark_3_4` `3.4.4` | Match the old image/PySpark version after audit |
| Hadoop | `hadoop` `3.4.0` | Prefer exact `3.3.4` derivation for first parity build |
| PostgreSQL | `postgresql_16` `16.13` | Use Nix package |
| Quarto | `quarto` `1.8.26` | Use custom derivation or direct package for current `1.9.13` |
| pgweb | `pgweb` `0.17.0` | Prefer exact old binary `0.11.11` initially or validate new package |
| GitHub CLI | `gh` `2.89.0` | Use Nix package |

## Current Prototype Status

As of the local `linux/arm64` prototype:

- `rsm-podman-nix:dev` builds from `nixos/nix:2.31.3`.
- The runtime username is resolved from `RSM_USERNAME` or the prefix of `RSM_USER_EMAIL`; `xyz123@ucsd.edu` becomes `/home/xyz123`.
- No Conda/Mamba binaries or `/opt/conda` are present.
- uv creates `/opt/base-uv/.venv`; VS Code notebook support is provided through `ipykernel`.
- `xgboost` is kept in the base uv environment and pinned to `2.0.3` because that removes the `nvidia-nccl-cu12` dependency from the uv lock.
- `git-lfs`, PostgreSQL, pgweb, OpenSSH, GitHub CLI, and Quarto are in the default image.
- The image includes a small FHS compatibility layer for VS Code Server:
  `/usr/bin/tar`, `/usr/bin/strings`, `/usr/bin/ldd`, `ldconfig`, `/lib/libc.so.6`,
  `/lib/libstdc++.so.6`, and the platform dynamic loader are available at
  conventional paths.
- zsh and oh-my-zsh are image-owned and installed through Nix. The mounted home
  keeps persistent container-specific user state in one removable namespace:
  - base directory: `$HOME/.rsm-msba`
  - zsh user config: `$HOME/.rsm-msba/zsh`
  - zsh history: `$HOME/.rsm-msba/zsh/.zsh_history`
  - zsh cache: `$HOME/.rsm-msba/zsh/.cache`
  - uv cache: `$HOME/.rsm-msba/uv-cache`
  The active zsh startup file remains image-owned at `/etc/rsm/zsh/.zshrc`,
  and setup does not create top-level host settings such as `$HOME/.zshrc`.
- Spark and Hadoop are intentionally not in the default image; the optional flake proof passes locally and should stay separate unless every course needs it.
- The running-container Spark/Hadoop install test passes locally on `linux/arm64` with Docker. It starts a fresh container, installs the optional stack from the flake, runs command smoke checks, and executes the existing PySpark/HDFS notebooks from `files/scalable_analytics/test`.
- The VS Code Server prerequisite test passes locally on `linux/arm64` with Docker:
  `RSM_USER_EMAIL=xyz123@ucsd.edu` resolves to user/home `xyz123`,
  `glibc=2.42`, and `glibcxx=3.4.34`.

Local ARM smoke tests passed for:

- official username mapping: `RSM_USER_EMAIL=xyz123@ucsd.edu` -> user/home `xyz123`
- explicit username mapping: `RSM_USERNAME=abc999`
- fallback username: `rsmuser`
- mounted write access
- non-root `nix eval`
- `python`, `uv`, `ipykernel`, `IPython`, `requests`, `numpy`, `scipy`, and `xgboost`
- `quarto --version`, `postgres --version`, `pgweb --version`, `git-lfs version`, and `gh --version`
- VS Code Server prerequisites: `tar`, `ldconfig`, `libc.so.6`, `libstdc++.so.6`, `GLIBC >= 2.28`, and `GLIBCXX >= 3.4.25`
- mounted-home zsh state: `setup`, oh-my-zsh, autosuggestions, history-substring search, persistent `.zsh_history`, and no top-level `$HOME/.zshrc`
- optional Spark/Hadoop flake: `hadoop version`, `spark-submit --version`, and local PySpark `SparkSession`
- running-container Spark/Hadoop notebook integration: `check-pyspark.ipynb`, `check-hdfs-setup.ipynb`, and `hdfs-handson-test.ipynb`

Measured local sizes:

| Item | Measurement |
| --- | ---: |
| Minimal ARM image before PostgreSQL/Quarto/gh/OpenSSH additions | ~500 MB |
| Current ARM image with PostgreSQL, pgweb, OpenSSH, gh, Quarto, git-lfs, XGBoost, VS Code compatibility links, and Nix-managed zsh/oh-my-zsh | ~797 MB |
| Current Nix runtime closure | ~1.3 GiB unpacked |
| Current uv environment | ~279 MB unpacked |
| Custom upstream Quarto `1.9.13` package closure | ~451 MiB unpacked |
| nixpkgs `quarto` package closure | ~2.7 GiB unpacked |
| PostgreSQL 16 dry-run closure addition | ~6 MiB fetched, ~25 MiB unpacked |
| git-lfs dry-run closure addition | ~3 MiB fetched, ~12 MiB unpacked |
| Hadoop dry-run closure | ~1.2 GiB fetched, ~2.0 GiB unpacked |
| Spark 3.4 dry-run closure | ~1.5 GiB fetched, ~2.35 GiB unpacked |
| Spark 3.5 dry-run closure | ~1.5 GiB fetched, ~2.37 GiB unpacked |
| Spark 4 dry-run closure | ~2.0 GiB fetched, ~3.1 GiB unpacked |
| Optional no-R Spark/Hadoop proof flake | ~1.9 GiB fetched, ~2.9 GiB unpacked, ~3.0 GiB final closure |
| Fresh in-container Spark/Hadoop install | ~1.6 GiB fetched, ~2.7 GiB unpacked during the test |

Decision from these measurements:

- Keep PostgreSQL and git-lfs in the default image.
- Keep Quarto in the default image, but use the upstream Quarto binary package rather than nixpkgs `quarto`.
- Keep XGBoost, pinned to avoid CUDA/NCCL dependency resolution.
- Keep VS Code notebook support through `ipykernel`; do not add full JupyterLab/notebook server packages unless a workflow requires them.
- Keep Spark/Hadoop in the separate optional flake/image layer. The local proof passes, but its ~3.0 GiB closure is too large for the default image.

VS Code can attach to a running container with the Dev Containers extension.
The base Python interpreter for notebooks is `/opt/base-uv/.venv/bin/python`,
and the installed kernelspec is `RSM base uv`. If VS Code attaches as root to a
manually started container, configure the Dev Containers attach settings to use
the resolved runtime username, or start the container with an attach metadata
label for that user. The older SSH launch workflow is not fully ported yet;
OpenSSH is present, but service startup and port mapping still need to be wired
into the Nix image launch scripts.

Current local regression commands:

```bash
ENGINE=docker IMAGE=rsm-podman-nix:dev PLATFORM=linux/arm64 \
  rsm-podman-nix/tests/vscode-server-prereqs.sh

ENGINE=docker IMAGE=rsm-podman-nix:dev PLATFORM=linux/arm64 \
  rsm-podman-nix/tests/zsh-home-state.sh

ENGINE=docker IMAGE=rsm-podman-nix:dev PLATFORM=linux/arm64 \
  rsm-podman-nix/tests/container-spark-hadoop-notebooks.sh
```

## Design Decision

Use a `Containerfile` that starts from `nixos/nix`, plus a project flake that defines the runtime closure.

Do not build the image with `dockerTools.buildImage` initially, because the explicit requirement is to use `nixos/nix` as the base image. A later optimization can move more of the image construction into Nix if it still preserves the base image requirement.

Proposed structure:

```text
rsm-podman-nix/
|-- Containerfile
|-- flake.nix
|-- flake.lock
|-- pyproject.toml
|-- uv.lock
|-- docs/
|   `-- nixos-nix-image-plan.md
|-- files/
|   |-- profile.d/rsm-env.sh
|   |-- postgres/init-postgres-db.sh
|   |-- scalable_analytics/...
|   |-- sshd/sshd_config
|   |-- start-container.sh
|   `-- zsh/...
`-- tests/
    |-- validate-nix-image.sh
    |-- integration-tests.sh
    `-- package-imports.py
```

The `rsm-podman-nix/files` directory should start as a curated copy of only the portable files from the existing top-level `files/` directory, then be adjusted for Nix paths. The existing `files/` directory remains source material for the port; do not copy it wholesale or modify the Debian-based image until the Nix image is passing parity tests.

## Runtime Architecture

### Containerfile

The image should start like this:

```Dockerfile
FROM nixos/nix:2.31.3@sha256:d49538facc7757890eccfa5f57869ad18c823c24903e3b8ac6ca8a301d84a9b6
```

Build flow:

1. Enable flakes and nix-command in the build environment.
2. Copy `rsm-podman-nix/flake.nix` and `flake.lock` first, then build the Nix runtime closure for better layer caching.
3. Link or copy the built profile to `/opt/rsm-nix-profile`.
4. Set `PATH=/opt/base-uv/.venv/bin:/opt/rsm-nix-profile/bin:/usr/local/bin:/usr/bin:/bin:$PATH`.
5. Create FHS compatibility symlinks needed by existing scripts and shebangs:
   - `/usr/bin/env`
   - `/bin/bash`
   - `/bin/zsh`
   - `/usr/bin/tar`
   - `/usr/bin/strings`
   - `/usr/bin/ldd`
   - `/usr/sbin/ldconfig`
   - `/lib/libc.so.6`
   - `/lib/libstdc++.so.6`
   - `/usr/bin/hadoop`
   - `/usr/local/bin/pgweb_binary`
   - `/usr/sbin/sshd` if `start-container.sh` keeps the current path
6. Copy the runtime entrypoint that creates the resolved user from `RSM_USERNAME` or `RSM_USER_EMAIL`.
7. Create and chown runtime directories for PostgreSQL, SSH, user homes, and `/opt/base-uv`. Create Hadoop directories only when the optional Spark/Hadoop layer is installed.
8. Run `uv sync --frozen` to create `/opt/base-uv/.venv`.
9. Install Jupyter kernels with the uv environment.
10. Copy scripts/configs and set permissions.
11. Keep the image configured as root so the entrypoint can create the runtime user, then drop to that user with `gosu`.

### Nix flake

The flake should produce at least:

- `packages.${system}.runtimeEnv`: a `pkgs.buildEnv` containing system binaries.
- Optional Spark/Hadoop flake package outputs, kept outside the default image unless every course needs them.
- `packages.${system}.quarto1913`: custom exact Quarto 1.9.13 package if nixpkgs lacks it.
- `packages.${system}.pgweb01111`: compatibility package or wrapper if exact pgweb parity is required.
- `devShells.${system}.default`: local development shell with `podman`/`docker`, `nix`, `uv`, and test tools.

Initial runtime packages:

- Shell/core: `bashInteractive`, `coreutils`, `gnused`, `gnugrep`, `gawk`, `findutils`, `which`, `shadow`, `sudo`, `gosu`, `cacert`, `glibcLocales`
- Dev/user tools: `curl`, `wget`, `git`, `git-lfs`, `rsync`, `zsh`, `autojump`, `vim`, `vifm`, `htop`, `lsof`, `rename`, `unzip`, `zip`
- Services: `openssh`, `postgresql_16`, `pgweb`
- Notebook/data-adjacent tools: keep Java/Spark/Hadoop out of the default image and install them through the optional Spark/Hadoop flake.
- Build/runtime libs for uv wheels: `gcc`, `gfortran`, `pkg-config`, `openssl`, `zlib`, `xz`, `libpq`, `postgresql_16.lib`, BLAS/LAPACK as needed
- Publishing/tools: `quarto` or exact Quarto derivation, `gh`, `pandoc` if Quarto needs it separately

Avoid `apt`, `conda`, `mamba`, and curl-piped installers.

## Python And uv Strategy

Hard requirements:

- No `/opt/conda`.
- No `conda`, `mamba`, or `micromamba` binary in the final image.
- `/opt/base-uv/.venv/bin/python` is the Python used by:
  - user shells
  - Quarto via `QUARTO_PYTHON`
  - reticulate via `RETICULATE_PYTHON`
  - PySpark via `PYSPARK_PYTHON` and `PYSPARK_DRIVER_PYTHON`
  - RSM helper scripts such as `usethis`

Recommended initial implementation:

1. Use Nix to provide the interpreter binary (`python313`) and native libraries.
2. Use uv to create and manage the environment:

   ```bash
   UV_LINK_MODE=copy uv venv --python /opt/rsm-nix-profile/bin/python3 /opt/base-uv/.venv
   UV_LINK_MODE=copy uv sync --frozen --python /opt/base-uv/.venv/bin/python
   ```

This keeps Nix responsible for system ABI stability and uv responsible for Python dependency management. If strict uv-managed Python downloads are required, add a first implementation spike to test `uv python install 3.13` inside `nixos/nix` with the required loader/nix-ld support. Do not block the main parity build on that unless the spike passes on both architectures.

Default image size policy:

- Keep the base image focused on packages used in classes and common RSM workflows.
- Do not install PyTorch in the default image.
- Do not install packages that force PyTorch as a dependency, such as `transformers[torch]` or `causalml[torch]`, in the default image.
- Put large optional stacks in separate uv environments on a mounted/shared drive, for example `/home/<user>/.rsm-msba/envs/torch` or a course shared directory.
- Prefer Nix-provided system tools and one uv environment over duplicating the same runtime through both Nix and Python wheels.

Default Python packages to carry over from `files/install-uv.sh`:

- `pyrsm==2.2.0`
- `pyarrow`
- `scipy`, `sqlalchemy`, `psycopg2`, `scikit-learn`, `scikit-misc`, `mlxtend`, `xgboost`, `lightgbm`, `statsmodels`, `linearmodels`
- `bs4`, `spacy`, `nltk`, `textblob`
- `graphviz`, `plotnine`, `folium`, `networkx`
- `IPython`, `nbclient`, `nbconvert`, `jupytext`, `isort`, `xlrd`, `openpyxl`, `xlsx2csv`, `markdown`
- `polars`, `fastexcel`, `connectorx`
- `sympy`, `simpy`, `lime`, `shap`
- `findspark`
- `dowhy`
- `python-dotenv`
- `tqdm`, `ipywidgets`
- `bash_kernel`, `awscli`

Optional Python stacks, not in the default image:

- PyTorch stack: `torch`, `torchvision`, `torchaudio`.
- Transformer/NLP deep learning stack: `transformers`, `transformers[torch]`, `huggingface_hub`, and downloaded model caches.
- Causal ML stack requiring PyTorch: `causalml[torch]`.
- Any course-specific GPU/CUDA stack.

PySpark packaging rule:

- Prefer Nix Spark plus Spark's bundled Python libraries exposed through `SPARK_HOME` and `PYTHONPATH`.
- Avoid installing PyPI `pyspark` by default if Nix Spark provides the needed Python modules, because the PyPI wheel can duplicate Spark JARs already present in the image.
- If a PyPI `pyspark` wheel is required for compatibility, pin it to the same Spark major/minor as Nix Spark and measure the size increase before accepting it.

Notebook packages for the default image:

- `ipykernel`, `jupyter-client`, and `jupyter-core` for VS Code notebooks.
- `requests`, because `usethis` imports it directly
- Full `jupyterlab`, `notebook`, and `jupyter_server` are optional unless a workflow needs an in-container browser server.
- Any packages discovered by the old-image package audit described below.

Lock this in `uv.lock` and use only frozen syncs in CI and image builds.

## Spark And Hadoop Strategy

Current decision: keep Spark and Hadoop out of the default image and provide a separate optional flake/layer. Spark/Hadoop are much larger than PostgreSQL, git-lfs, or Quarto; the verified optional no-R Spark/Hadoop proof is still about 3.0 GiB unpacked.

Spark and PySpark must match at the major/minor level when the optional stack is enabled.

The local optional flake at `rsm-podman-nix/spark-hadoop` currently proves:

- Hadoop `3.4.0` runs.
- Spark `3.5.5` runs.
- A local PySpark `SparkSession` runs and returns `pyspark-count 3`.

The optional flake patches the nixpkgs Spark wrapper so `SPARK_DIST_CLASSPATH` is respected and filters Hadoop YARN classpath entries for local mode. This is needed because nixpkgs Hadoop currently includes a Spark 4 YARN shuffle jar that introduces Scala 2.13 classes into Spark 3.5's Scala 2.12 runtime.

Implementation steps:

1. Audit current image:
   - `spark-submit --version`
   - `/opt/base-uv/.venv/bin/python -c "import pyspark; print(pyspark.__version__)"`
   - `ls /usr/local/spark/python/lib/py4j-*.zip`
2. Select matching Nix Spark package:
   - Prefer `spark_3_5` or `spark_3_4` only if that matches old behavior.
   - Use `spark`/Spark 4 if the old image is already on Spark 4.
3. Expose Spark's bundled Python modules through `SPARK_HOME` and `PYTHONPATH`; add PyPI `pyspark` only if this fails compatibility tests.
4. Create stable compatibility paths:
   - `/usr/local/spark -> <nix spark package>`
   - `/opt/hadoop -> <hadoop 3.3.4 package or unpacked derivation>`
   - `/usr/bin/hadoop -> /opt/hadoop/bin/hadoop`
5. Set:
   - `JAVA_HOME`
   - `SPARK_HOME=/usr/local/spark`
   - `HADOOP_HOME=/opt/hadoop`
   - `HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop`
   - `PYSPARK_PYTHON=/opt/base-uv/.venv/bin/python`
   - `PYSPARK_DRIVER_PYTHON=/opt/base-uv/.venv/bin/python`
   - `PYTHONPATH` including Spark Python and `py4j`
6. Copy current Hadoop configs and scripts:
   - `core-site.xml`
   - `hdfs-site.xml`
   - `init-dfs.sh`
   - `start-dfs.sh`
   - `stop-dfs.sh`
7. Keep the current HDFS behavior:
   - replication `1`
   - temporary namenode/data directories
   - `hdfs namenode -format -force` via `init-dfs.sh`

For exact initial parity, package Hadoop `3.3.4` as a Nix derivation using the same Apache archive source as the current script. Once all tests pass, evaluate whether moving to nixpkgs `hadoop` `3.4.0` is acceptable.

## Service Strategy

### PostgreSQL

Use `postgresql_16` from Nix. Replace Debian-specific paths in scripts with commands from `PATH`.

Keep:

- `POSTGRES_VERSION=16`
- `PGPASSWORD=postgres`
- `PGDATA=/var/lib/postgresql/16/main`
- Runtime initialization when a fresh `pg_data` volume is mounted
- Databases for the resolved `$RSM_USERNAME` and `rsm-msba`
- Optional legacy `jovyan` database/user only if old notebooks require it during transition
- Resolved `$RSM_USERNAME` as PostgreSQL superuser
- Port `8765`
- Healthcheck via `pg_isready -h localhost -p 8765 -U "$RSM_USERNAME"`

Update scripts:

- `rsm-podman-nix/files/postgres/init-postgres-db.sh`
- `rsm-podman-nix/files/start-container.sh`

Avoid hard-coded Debian paths such as `/usr/lib/postgresql/16/bin/postgres`.

### SSH

Use Nix `openssh`.

Keep:

- Port `2222`
- key auth enabled
- password auth disabled
- root login disabled
- log file `/var/log/sshd/sshd.log`

Update the SFTP subsystem path in `sshd_config` for Nix, or add a compatibility symlink if that is simpler. Preserve the ARM/QEMU test workaround from existing CI if PAM still causes emulated ARM SSH issues.

### pgweb

Keep `/usr/local/bin/pgweb_binary` as a compatibility command, even if it is a wrapper around Nix `pgweb`.

The shell alias should continue to work:

```bash
pgweb_binary --bind=0.0.0.0 --listen=8282 --port=8765
```

### Startup

`start-container.sh` should continue to:

1. start SSHD
2. initialize PostgreSQL if needed
3. start PostgreSQL
4. tail logs
5. keep the container alive while PostgreSQL is running

Do not introduce systemd; the current image does not use it, and rootless Podman service startup is simpler without it.

## Shell And RSM Tooling

Copy and adapt:

- `files/zsh/zshrc`
- `files/zsh/p10k.zsh`
- `files/zsh/usethis`
- `files/zsh/interactive-usethis.sh`
- `files/zsh/github.sh`
- `files/zsh/setup.sh`
- `files/zsh/menu.sh`

Changes needed:

- Ensure every shebang works on a Nix base.
- Keep `/usr/local/bin/usethis`, `/usr/local/bin/iusethis`, `/usr/local/bin/github`, `/usr/local/bin/setup`, `/usr/local/bin/menu`.
- Keep aliases:
  - `sbase="source /opt/base-uv/.venv/bin/activate"`
  - `sp="source .venv/bin/activate"`
  - `pgweb=...`
- Keep uv zsh completions.
- Install oh-my-zsh and plugins through Nix/pinned fetches rather than live curl/git installers.

## Parity Audit Before Implementation

Run these against the old image and save outputs under `rsm-podman-nix/docs/audit/`:

```bash
docker run --rm ghcr.io/radiant-ai-hub/rsm-podman:latest bash -lc 'env | sort'
docker run --rm ghcr.io/radiant-ai-hub/rsm-podman:latest bash -lc 'command -v python uv jupyter java spark-submit hadoop postgres psql sshd quarto gh zsh'
docker run --rm ghcr.io/radiant-ai-hub/rsm-podman:latest bash -lc '/opt/base-uv/.venv/bin/python -m pip freeze'
docker run --rm ghcr.io/radiant-ai-hub/rsm-podman:latest bash -lc 'spark-submit --version'
docker run --rm ghcr.io/radiant-ai-hub/rsm-podman:latest bash -lc 'hadoop version'
docker run --rm ghcr.io/radiant-ai-hub/rsm-podman:latest bash -lc 'jupyter kernelspec list'
```

The final Nix image does not need to preserve Conda internals from this audit. It must preserve user-facing commands, imports, services, environment variables, and documented workflows.

## Implementation Phases

### Phase 1: Scaffold

- Create `rsm-podman-nix/Containerfile`.
- Create `rsm-podman-nix/flake.nix` and pin `flake.lock`.
- Create `rsm-podman-nix/pyproject.toml` and `uv.lock`.
- Copy only needed portable files from `files/`.
- Add a new local image name, for example `ghcr.io/radiant-ai-hub/rsm-podman-nix`.

Exit criteria:

- `docker buildx build --platform linux/arm64 -f rsm-podman-nix/Containerfile .` reaches a shell-capable image.
- No Conda/Mamba exists in the image.

### Phase 2: uv Python Environment

- Build `/opt/base-uv/.venv` with uv.
- Install package list from the current image plus Jupyter parity packages.
- Install bash kernel and Python kernel specs.
- Add import tests for all required Python packages.

Exit criteria:

- `/opt/base-uv/.venv/bin/python -c "import pyrsm, pandas, sklearn"` passes.
- Base Python and notebook kernel tests pass without PyPI `pyspark`. PySpark import/session tests pass after installing the optional Spark/Hadoop flake.
- `uv --version` works.
- `which conda` and `which mamba` fail.

### Phase 3: Spark/Hadoop

- Add Java 17, selected Spark package, exact Hadoop 3.3.4 derivation to an optional flake/layer first.
- Add compatibility paths `/usr/local/spark`, `/opt/hadoop`, `/usr/bin/hadoop`.
- Port `rsm-env.sh` to Nix paths.
- Copy Hadoop configs and scripts.

Exit criteria:

- Optional flake proof script runs on local `aarch64-linux`.
- `java -version` works.
- `hadoop version` works.
- `spark-submit --version` works.
- `python -c 'from pyspark.sql import SparkSession; ...'` starts a local Spark session.
- `cd $HADOOP_HOME && ./init-dfs.sh` works.

### Phase 4: PostgreSQL, SSH, pgweb

- Port PostgreSQL init/start scripts to Nix paths.
- Add OpenSSH and fixed `sshd_config`.
- Add pgweb wrapper.
- Add healthcheck.

Exit criteria:

- Container starts with rootless Podman/Docker.
- `pg_isready -h localhost -p 8765 -U "$RSM_USERNAME"` passes.
- `psql` can create/drop a test table.
- `sshd -T` shows port `2222`.
- `pgweb_binary --version` works.

### Phase 5: Shell And User Workflow

- Add zsh, oh-my-zsh, plugins, p10k config, helper scripts.
- Verify launch-script compatibility with mounted home and `pg_data`.
- Decide whether to update launch script port mappings for Jupyter `8888`.

Exit criteria:

- `podman exec -it --user "$RSM_USERNAME" rsm-podman-nix /bin/zsh` opens the expected shell.
- `sbase`, `pgweb`, `menu`, `usethis`, `github`, and `setup` are available.
- Mounted home directory behavior matches the old launch flow.

### Phase 6: Multi-Architecture CI

- Add `.github/workflows/rsm-podman-nix-build.yml`.
- Reuse existing version/tag/manifest logic.
- Build amd64 and arm64 images separately.
- Create a multi-arch manifest.
- Run integration tests for both platforms.
- Keep the ARM emulation SSH fallback if needed.

Exit criteria:

- CI publishes `linux/amd64` and `linux/arm64`.
- CI runs the parity integration suite against both platforms.
- The resulting manifest can be pulled by Podman on macOS ARM, Linux ARM, and Linux amd64.

### Phase 7: Cutover

- Compare old and new image test outputs.
- Update docs and launch scripts to either:
  - use the new image explicitly, or
  - provide `USE_NIX_IMAGE=1`/image override during transition.
- Keep the old image available until at least one release of the Nix image has passed course/user validation.

Exit criteria:

- Users can launch the Nix image with the same core workflow.
- Existing notebooks/tests for PostgreSQL, PySpark, Hadoop, Quarto, and Python packages run successfully.

## Validation Suite

Create `rsm-podman-nix/tests/integration-tests.sh` from the current `scripts/local-integration-tests.sh`, adjusted for the new image name.

Required checks:

```bash
# no Conda
! command -v conda
! command -v mamba
test ! -d /opt/conda

# env
test -n "$JAVA_HOME"
test -n "$SPARK_HOME"
test -n "$HADOOP_HOME"
test "$PYSPARK_PYTHON" = "/opt/base-uv/.venv/bin/python"

# services
pg_isready -h localhost -p 8765 -U "$RSM_USERNAME"
psql -h localhost -p 8765 -U "$RSM_USERNAME" -c 'SELECT 1;'
sshd -T | grep '^port 2222'
pgweb_binary --version

# tools
java -version
hadoop version
spark-submit --version
quarto --version
gh --version
uv --version
jupyter --version

# Python
/opt/base-uv/.venv/bin/python -c 'import pyrsm, pyarrow, sklearn, psycopg2'
/opt/base-uv/.venv/bin/python -c 'import pyspark'
/opt/base-uv/.venv/bin/python -c 'from pyspark.sql import SparkSession; spark = SparkSession.builder.master("local").getOrCreate(); spark.stop()'

# Hadoop
cd "$HADOOP_HOME"
./init-dfs.sh
hadoop version
```

Also add a package import test file so failures are easier to diagnose than one long shell command.

## Risks And Mitigations

| Risk | Mitigation |
| --- | --- |
| uv-managed standalone Python may have loader issues on a Nix base | Start with Nix-provided Python plus uv-managed venv; spike strict `uv python install` separately |
| Scientific wheels may need native build tooling on ARM | Include `gfortran`, compiler wrappers, BLAS/LAPACK, `pkg-config`, and `UV_LINK_MODE=copy` |
| Spark and PySpark version mismatch | Audit old image first; pin both sides to the same major/minor |
| Hadoop 3.3.4 not in nixpkgs | Package exact version as a small custom derivation |
| Nix paths break old scripts | Port scripts to `PATH` commands and add compatibility symlinks for stable public paths |
| Quarto 1.9.13 not in current nixpkgs | Add custom exact Quarto derivation or pinned binary derivation |
| pgweb version drift | Keep `/usr/local/bin/pgweb_binary`; use exact old binary first if UI behavior matters |
| Image size grows due to Nix store plus uv wheels | Use multi-stage layering, clean Nix caches, avoid build tools in final closure if possible |
| ARM QEMU SSH tests remain flaky | Preserve existing ARM fallback that verifies SSHD config when full SSH connection fails under emulation |

## Size Control

Default image exclusions:

- PyTorch: `torch`, `torchvision`, `torchaudio`.
- PyTorch-driven extras: `transformers[torch]`, `causalml[torch]`.
- Downloaded NLP/model data: spaCy models, NLTK corpora, Hugging Face model caches.
- GPU/CUDA libraries and CUDA-enabled Python wheels.
- Duplicate Spark distributions: avoid PyPI `pyspark` if Nix Spark plus `SPARK_HOME/python` is sufficient.
- Build-only toolchains in the final runtime closure unless they are needed for students to build packages interactively.

Packages to question before adding to the default image:

- `transformers` and `huggingface_hub`: useful, but pull users toward large model downloads; better as optional unless used in class.
- `spacy`: acceptable as a library, but do not preinstall language models.
- `nltk`: acceptable as a library, but do not preinstall corpora.
- `xgboost`: keep in the base environment, pinned to `2.0.3` to avoid CUDA/NCCL lock dependencies.
- `lightgbm`: keep only if used in current coursework; otherwise move to a course/project uv environment.
- `causalml`: move out of the default image unless a class actively uses it; it can pull a broad ML dependency set.
- `awscli`: keep only if there is a current workflow that needs it in every image.
- `git-lfs`: keep in the base image.

Nix-specific size checks:

- Avoid adding `nix` again through the runtime flake if the base `nixos/nix` profile can provide it without losing single-user Nix behavior.
- Keep `nix-collect-garbage -d` after profile construction.
- Measure closure size before accepting large packages:

  ```bash
  nix path-info -Sh .#runtimeEnv
  docker image inspect rsm-podman-nix:dev --format '{{.Size}}'
  ```

Optional environment pattern:

```bash
uv venv /home/<user>/.rsm-msba/envs/torch
source /home/<user>/.rsm-msba/envs/torch/bin/activate
uv pip install torch torchvision torchaudio
```

For shared drives, use a path mounted outside the image and document the environment activation command per course.

## Open Decisions

1. Exact Spark version: decide after old-image audit.
2. Exact Hadoop version: initial plan says keep `3.3.4`; later upgrade to nixpkgs `3.4.0` only after tests.
3. Exact Quarto version: keep `1.9.13` for parity unless a newer documented requirement says otherwise.
4. pgweb version: keep compatibility command regardless of underlying version.
5. Jupyter port `8888`: resolve docs/launch mismatch during Phase 5.
6. GPU image: treat `rsm-podman-gpu` as a second milestone after CPU parity unless GPU support is required for the first release.

## Definition Of Done

The Nix-based image is ready when:

- It builds from `nixos/nix` for `linux/amd64` and `linux/arm64`.
- There is no Conda/Mamba in the final image.
- uv creates and owns the Python environment at `/opt/base-uv/.venv`.
- PySpark local sessions work.
- Hadoop/HDFS scripts work.
- PostgreSQL, SSH, and pgweb start under the resolved rootless runtime user.
- Existing launch workflow works with mounted `/home/<resolved-user>` and persistent `pg_data`.
- CI publishes a multi-arch manifest and runs parity integration tests.
- Documentation clearly states the image name, supported platforms, ports, volumes, and migration status.
