#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

engine="${ENGINE:-docker}"
image="${IMAGE:-rsm-podman-nix:dev}"
container="${CONTAINER:-rsm-nix-spark-hadoop-test}"
platform="${PLATFORM:-linux/arm64}"
test_email="${RSM_USER_EMAIL:-spark123@ucsd.edu}"
test_user="${test_email%@*}"

if ! command -v "$engine" >/dev/null 2>&1; then
  echo "Container engine not found: $engine" >&2
  exit 1
fi

cleanup() {
  "$engine" rm -f "$container" >/dev/null 2>&1 || true
}

wait_for_user() {
  local attempt
  for attempt in $(seq 1 30); do
    if "$engine" exec --user root "$container" awk -F: -v name="$test_user" '$1 == name { found=1 } END { exit !found }' /etc/passwd >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "Timed out waiting for user '$test_user' in container /etc/passwd" >&2
  "$engine" logs "$container" >&2 || true
  return 1
}

trap cleanup EXIT
cleanup

platform_args=()
if [ -n "$platform" ]; then
  platform_args=(--platform "$platform")
fi

echo "Starting $image with $engine ..."
"$engine" run -d \
  "${platform_args[@]}" \
  --name "$container" \
  -e RSM_USER_EMAIL="$test_email" \
  -v "$repo_root:/workspace/rsm-podman:rw" \
  "$image" \
  sleep infinity >/dev/null

wait_for_user

echo "Checking resolved runtime user ..."
"$engine" exec --user "$test_user" "$container" bash -lc "
  set -euo pipefail
  test \"\$(id -un)\" = \"$test_user\"
  test \"\$HOME\" = \"/home/$test_user\"
"

echo "Installing optional Spark/Hadoop stack into running container ..."
"$engine" exec --user root --env RSM_USERNAME="$test_user" "$container" bash \
  /workspace/rsm-podman/rsm-podman-nix/tests/install-spark-hadoop-in-container.sh

echo "Running Spark/Hadoop command smoke checks ..."
"$engine" exec --user "$test_user" "$container" bash -lc '
  set -euo pipefail
  source /etc/profile.d/rsm-spark-hadoop.sh
  command -v spark-submit hadoop hdfs jps
  hadoop version
  spark-submit --version
  python - <<'"'"'PY'"'"'
import pyspark
from pyspark.sql import SparkSession

spark = (
    SparkSession.builder.master("local[1]")
    .appName("container-spark-hadoop-smoke")
    .config("spark.ui.enabled", "false")
    .getOrCreate()
)
print("container-pyspark-count", spark.range(3).count())
spark.stop()
PY
'

echo "Running existing scalable analytics notebooks ..."
"$engine" exec --user "$test_user" "$container" bash -lc '
  set -euo pipefail
  source /etc/profile.d/rsm-spark-hadoop.sh
  notebook_workdir=/tmp/rsm-scalable-analytics-test
  rm -rf "$notebook_workdir"
  mkdir -p "$notebook_workdir"
  cp -a /workspace/rsm-podman/files/scalable_analytics/test/. "$notebook_workdir"/
  rm -f "$notebook_workdir/ShakespeareNew.txt"
  cd "$notebook_workdir"
  /opt/base-uv/.venv/bin/python \
    /workspace/rsm-podman/rsm-podman-nix/tests/run-notebook-cells.py \
    check-pyspark.ipynb \
    check-hdfs-setup.ipynb \
    hdfs-handson-test.ipynb
'

echo "Container Spark/Hadoop notebook integration test passed."
