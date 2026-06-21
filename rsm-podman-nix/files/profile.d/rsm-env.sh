#!/usr/bin/env bash

export PATH="/opt/base-uv/.venv/bin:/opt/rsm-nix-profile/bin:/usr/local/bin:$PATH"
export UV_LINK_MODE="${UV_LINK_MODE:-copy}"
export PIP_REQUIRE_VIRTUALENV="${PIP_REQUIRE_VIRTUALENV:-true}"
export QUARTO_PYTHON="${QUARTO_PYTHON:-/opt/base-uv/.venv/bin/python}"
export RETICULATE_PYTHON="${RETICULATE_PYTHON:-/opt/base-uv/.venv/bin/python}"
export PYSPARK_PYTHON="${PYSPARK_PYTHON:-/opt/base-uv/.venv/bin/python}"
export PYSPARK_DRIVER_PYTHON="${PYSPARK_DRIVER_PYTHON:-/opt/base-uv/.venv/bin/python}"

if [ -n "${HOME:-}" ]; then
  case "${RSMBASE:-}" in
    "$HOME"/*) ;;
    *) export RSMBASE="$HOME/.rsm-msba" ;;
  esac
  export RSM_ZSH_USER_CONFIG="${RSM_ZSH_USER_CONFIG:-$RSMBASE/zsh}"
  export RSM_ZSH_STATE="${RSM_ZSH_STATE:-$RSMBASE/zsh}"
  export RSM_ZSH_CACHE="${RSM_ZSH_CACHE:-$RSMBASE/zsh/.cache}"
  export UV_CACHE_DIR="${UV_CACHE_DIR:-$RSMBASE/uv-cache}"
fi

export ZDOTDIR="${ZDOTDIR:-/etc/rsm/zsh}"
