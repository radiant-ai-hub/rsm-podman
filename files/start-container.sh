#!/usr/bin/env bash

set -e

echo "Starting SSHD service..."
/usr/sbin/sshd -o PidFile=/tmp/sshd.pid -E /var/log/sshd/sshd.log

echo "Starting PostgreSQL service..."

# Initialize postgres if needed (e.g., fresh volume mount)
/usr/local/bin/init-postgres-db.sh

# Start PostgreSQL
/usr/lib/postgresql/${POSTGRES_VERSION}/bin/postgres \
    -c config_file=/etc/postgresql/${POSTGRES_VERSION}/main/postgresql.conf &
POSTGRES_PID=$!

echo "All services started. Tailing logs..."
tail -F /var/log/sshd/sshd.log >/dev/null 2>&1 &

# Wait briefly for PostgreSQL logs to appear before tailing
for i in {1..30}; do
  if ls /var/log/postgresql/postgresql-*.log >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

tail -F /var/log/postgresql/postgresql-*.log >/dev/null 2>&1 || true &

# Keep container alive as long as PostgreSQL is running
wait ${POSTGRES_PID}
