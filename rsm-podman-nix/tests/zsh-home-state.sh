#!/usr/bin/env bash
set -euo pipefail

engine="${ENGINE:-docker}"
image="${IMAGE:-rsm-podman-nix:dev}"
platform="${PLATFORM:-linux/arm64}"
test_email="${RSM_USER_EMAIL:-xyz123@ucsd.edu}"
test_user="${test_email%@*}"
tmp_home="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_home"
}
trap cleanup EXIT

if ! command -v "$engine" >/dev/null 2>&1; then
  echo "Container engine not found: $engine" >&2
  exit 1
fi

platform_args=()
if [ -n "$platform" ]; then
  platform_args=(--platform "$platform")
fi

"$engine" run --rm \
  "${platform_args[@]}" \
  -e RSM_USER_EMAIL="$test_email" \
  -v "$tmp_home:/home/$test_user:rw" \
  "$image" \
  zsh -lic '
    set -e

    setup

    test "$(id -un)" = "'"$test_user"'"
    test "$HOME" = "/home/'"$test_user"'"
    test "$ZDOTDIR" = "/etc/rsm/zsh"
    test "$RSMBASE" = "$HOME/.rsm-msba"
    test "$RSM_ZSH_USER_CONFIG" = "$HOME/.rsm-msba/zsh"
    test "$RSM_ZSH_STATE" = "$HOME/.rsm-msba/zsh"
    test "$RSM_ZSH_CACHE" = "$HOME/.rsm-msba/zsh/.cache"
    test "$UV_CACHE_DIR" = "$HOME/.rsm-msba/uv-cache"
    test -f "$RSM_ZSH_USER_CONFIG/local.zsh"
    test -f "$RSM_ZSH_USER_CONFIG/.p10k.zsh"
    test -f "$RSM_ZSH_STATE/.zsh_history"
    test ! -e "$HOME/.zshrc"
    test ! -e "$HOME/.lintr"
    test ! -d "$HOME/.config/rsm-podman"
    test ! -d "$HOME/.local/state/rsm-podman"

    alias sbase >/dev/null
    alias pgweb >/dev/null
    test -n "${functions[_zsh_autosuggest_start]-}"
    test -n "${functions[history-substring-search-up]-}"

    print -sr -- "rsm-zsh-history-smoke"
    fc -W
  '

grep -q "rsm-zsh-history-smoke" "$tmp_home/.rsm-msba/zsh/.zsh_history"

echo "Zsh mounted-home state test passed."
