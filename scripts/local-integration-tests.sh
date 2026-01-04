#!/usr/bin/env bash
set -euo pipefail

DOCKER_IMAGE="${DOCKER_IMAGE:-vnijs/rsm-msba-k8s:latest}"
PODMAN_IMAGE="${PODMAN_IMAGE:-ghcr.io/radiant-ai-hub/rsm-podman:latest}"

DOCKER_CONTAINER="${DOCKER_CONTAINER:-rsm-test-docker}"
PODMAN_CONTAINER="${PODMAN_CONTAINER:-rsm-test-podman}"

wait_for_postgres() {
  local engine="$1"
  local container="$2"

  for i in {1..30}; do
    if "$engine" exec "$container" pg_isready -h localhost -p 8765 -U jovyan >/dev/null 2>&1; then
      echo "PostgreSQL is ready"
      return 0
    fi
    echo "Waiting for PostgreSQL... (${i}/30)"
    sleep 2
  done

  echo "PostgreSQL did not become ready"
  return 1
}

run_tests() {
  local engine="$1"
  local container="$2"
  local user_flag="-u root"
  if [[ "$engine" == "podman" ]]; then
    user_flag="--user root"
  fi

  "$engine" exec "$container" psql -h localhost -p 8765 -U jovyan -c 'SELECT 1 as test;'
  "$engine" exec "$container" psql -h localhost -p 8765 -U jovyan -c '
    CREATE TABLE test_table (id SERIAL PRIMARY KEY, name TEXT);
    INSERT INTO test_table (name) VALUES ('"'"'test_value'"'"');
    SELECT * FROM test_table;
    DROP TABLE test_table;
  '
  "$engine" exec "$container" bash -l -c 'java -version'
  "$engine" exec "$container" bash -l -c '
    echo "JAVA_HOME=$JAVA_HOME"
    echo "SPARK_HOME=$SPARK_HOME"
    echo "HADOOP_HOME=$HADOOP_HOME"
    test -n "$JAVA_HOME" || exit 1
    test -n "$SPARK_HOME" || exit 1
    test -n "$HADOOP_HOME" || exit 1
  '
  "$engine" exec "$container" /usr/local/bin/pgweb_binary --version
  "$engine" exec "$container" sshd -T | grep -E "port|permitrootlogin"
  "$engine" exec "$container" bash -l -c '
    /opt/base-uv/.venv/bin/python -c "import pyspark; print(f\"PySpark version: {pyspark.__version__}\")"
  '

  ssh-keygen -t ed25519 -f /tmp/test_key -N "" >/dev/null
  "$engine" exec "$container" bash -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
  "$engine" cp /tmp/test_key.pub "${container}:/home/jovyan/.ssh/authorized_keys"
  "$engine" exec $user_flag "$container" bash -c "chown jovyan:users /home/jovyan/.ssh/authorized_keys"
  "$engine" exec $user_flag "$container" bash -c "chmod 600 /home/jovyan/.ssh/authorized_keys"
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i /tmp/test_key -p 2222 jovyan@localhost echo "SSH connection successful"

  "$engine" exec "$container" bash -l -c '
    cd $HADOOP_HOME
    ./init-dfs.sh
    hadoop version
  '

  "$engine" exec "$container" bash -l -c \
    " /opt/base-uv/.venv/bin/python -c 'from pyspark.sql import SparkSession; spark = SparkSession.builder.master(\"local\").getOrCreate(); print(\"PySpark works\"); spark.stop()' "
}

cleanup() {
  docker stop "$DOCKER_CONTAINER" >/dev/null 2>&1 || true
  docker rm "$DOCKER_CONTAINER" >/dev/null 2>&1 || true
  podman stop "$PODMAN_CONTAINER" >/dev/null 2>&1 || true
  podman rm "$PODMAN_CONTAINER" >/dev/null 2>&1 || true
  rm -f /tmp/test_key /tmp/test_key.pub
}

trap cleanup EXIT

echo "=== Docker tests (${DOCKER_IMAGE}) ==="
docker run -d --name "$DOCKER_CONTAINER" \
  -p 8765:8765 \
  -p 2222:2222 \
  "$DOCKER_IMAGE" \
  /usr/local/bin/start-container.sh

sleep 30
if ! docker ps | grep -q "$DOCKER_CONTAINER"; then
  echo "Docker container failed to start"
  docker logs "$DOCKER_CONTAINER"
  exit 1
fi

wait_for_postgres docker "$DOCKER_CONTAINER"
run_tests docker "$DOCKER_CONTAINER"
docker stop "$DOCKER_CONTAINER" >/dev/null
docker rm "$DOCKER_CONTAINER" >/dev/null

echo "=== Podman tests (${PODMAN_IMAGE}) ==="
podman run -d --name "$PODMAN_CONTAINER" \
  -p 8765:8765 \
  -p 2222:2222 \
  "$PODMAN_IMAGE" \
  /usr/local/bin/start-container.sh

sleep 30
if ! podman ps | grep -q "$PODMAN_CONTAINER"; then
  echo "Podman container failed to start"
  podman logs "$PODMAN_CONTAINER"
  exit 1
fi

wait_for_postgres podman "$PODMAN_CONTAINER"
run_tests podman "$PODMAN_CONTAINER"
podman stop "$PODMAN_CONTAINER" >/dev/null
podman rm "$PODMAN_CONTAINER" >/dev/null

echo "✅ Local integration tests passed for Docker and Podman images."
