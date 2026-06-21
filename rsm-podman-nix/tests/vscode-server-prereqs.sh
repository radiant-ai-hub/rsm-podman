#!/usr/bin/env bash
set -euo pipefail

engine="${ENGINE:-docker}"
image="${IMAGE:-rsm-podman-nix:dev}"
platform="${PLATFORM:-linux/arm64}"
test_email="${RSM_USER_EMAIL:-xyz123@ucsd.edu}"
test_user="${test_email%@*}"

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
  "$image" \
  bash -lc '
    set -euo pipefail

    min_version() {
      local current="$1"
      local required="$2"

      test "$(printf "%s\n%s\n" "$required" "$current" | sort -V | tail -n 1)" = "$current"
    }

    glibc_version="$(
      strings /lib/libc.so.6 |
        grep -E "^GLIBC_[0-9]+([.][0-9]+)+$" |
        sed "s/^GLIBC_//" |
        sort -V |
        tail -n 1
    )"
    glibcxx_version="$(
      strings /lib/libstdc++.so.6 |
        grep -E "^GLIBCXX_[0-9]+([.][0-9]+)+$" |
        sed "s/^GLIBCXX_//" |
        sort -V |
        tail -n 1
    )"

    test "$(id -un)" = "'"$test_user"'"
    test "$HOME" = "/home/'"$test_user"'"

    test -x /usr/bin/tar
    test -x /usr/bin/strings
    test -x /usr/bin/ldd
    test -x /usr/sbin/ldconfig
    test -x /sbin/ldconfig

    /usr/sbin/ldconfig -p | grep -q "libc[.]so[.]6"
    /usr/sbin/ldconfig -p | grep -q "libstdc++[.]so[.]6"
    min_version "$glibc_version" "2.28"
    min_version "$glibcxx_version" "3.4.25"

    echo "user=$(id -un)"
    echo "home=$HOME"
    echo "glibc=$glibc_version"
    echo "glibcxx=$glibcxx_version"
    echo "VS Code server prerequisite test passed."
  '
