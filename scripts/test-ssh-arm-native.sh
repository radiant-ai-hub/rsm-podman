#!/usr/bin/env bash
# Test SSH on native ARM hardware (Mac Studio)
# Usage: ssh ms 'bash -s' < scripts/test-ssh-arm-native.sh
# Or run directly on Mac Studio: ./scripts/test-ssh-arm-native.sh
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/radiant-ai-hub/rsm-podman:latest}"
CONTAINER_NAME="rsm-ssh-test"
SSH_PORT=2222

echo "=== Native ARM SSH Test Script ==="
echo "Image: $IMAGE"
echo "Container: $CONTAINER_NAME"
echo "SSH Port: $SSH_PORT"
echo ""

cleanup() {
    echo ""
    echo "=== Cleanup ==="
    podman stop "$CONTAINER_NAME" 2>/dev/null || true
    podman rm "$CONTAINER_NAME" 2>/dev/null || true
    rm -f /tmp/test_ssh_key /tmp/test_ssh_key.pub
    echo "Cleanup complete"
}

trap cleanup EXIT

# Pull the latest image
echo "=== Pulling image ==="
podman pull "$IMAGE"

# Start container
echo ""
echo "=== Starting container ==="
podman run -d --name "$CONTAINER_NAME" \
    -p ${SSH_PORT}:2222 \
    "$IMAGE" \
    /usr/local/bin/start-container.sh

# Wait for container to be ready
echo ""
echo "=== Waiting for container to start ==="
sleep 15

if ! podman ps | grep -q "$CONTAINER_NAME"; then
    echo "ERROR: Container failed to start"
    podman logs "$CONTAINER_NAME"
    exit 1
fi

echo "Container is running"

# Check SSHD status
echo ""
echo "=== SSHD Status ==="
podman exec "$CONTAINER_NAME" pgrep -a sshd || echo "SSHD process not found"
podman exec "$CONTAINER_NAME" ss -tlnp | grep ":2222" || echo "Port 2222 not listening"

# Check SSHD configuration
echo ""
echo "=== SSHD Configuration ==="
podman exec "$CONTAINER_NAME" sshd -T 2>&1 | grep -E "^(port|usepam|passwordauthentication|pubkeyauthentication|permitrootlogin)" || true

# Check host key permissions
echo ""
echo "=== Host Key Permissions ==="
podman exec "$CONTAINER_NAME" ls -la /etc/ssh/ssh_host_*_key 2>&1 | head -5 || echo "No host keys found"

# Check PAM configuration
echo ""
echo "=== PAM Configuration ==="
podman exec "$CONTAINER_NAME" cat /etc/pam.d/sshd 2>&1 | head -10 || echo "No PAM config found"

# Generate test key
echo ""
echo "=== Setting up SSH keys ==="
rm -f /tmp/test_ssh_key /tmp/test_ssh_key.pub
ssh-keygen -t ed25519 -f /tmp/test_ssh_key -N "" -q
echo "Generated test key"

# Copy public key to container
podman exec "$CONTAINER_NAME" bash -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
podman cp /tmp/test_ssh_key.pub "${CONTAINER_NAME}:/home/jovyan/.ssh/authorized_keys"
podman exec --user root "$CONTAINER_NAME" bash -c "chown jovyan:users /home/jovyan/.ssh/authorized_keys && chmod 600 /home/jovyan/.ssh/authorized_keys"
echo "Installed authorized_keys"

# Verify key setup
echo ""
echo "=== Authorized Keys Check ==="
podman exec "$CONTAINER_NAME" cat ~/.ssh/authorized_keys
podman exec "$CONTAINER_NAME" ls -la ~/.ssh/

# Wait for SSHD to be fully ready
echo ""
echo "=== Waiting for SSHD ==="
sleep 5

# Test SSH connection with verbose output
echo ""
echo "=== Testing SSH Connection (verbose) ==="
if ssh -vvv -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o AddressFamily=inet -i /tmp/test_ssh_key -p "$SSH_PORT" jovyan@127.0.0.1 echo "SSH SUCCESS" 2>&1; then
    echo ""
    echo "SSH test PASSED on native ARM"
    exit 0
else
    echo ""
    echo "SSH test FAILED"
    echo ""
    echo "=== Container Logs (last 50 lines) ==="
    podman logs --tail=50 "$CONTAINER_NAME"
    echo ""
    echo "=== SSHD Log ==="
    podman exec "$CONTAINER_NAME" cat /var/log/sshd/sshd.log 2>/dev/null || echo "No SSHD log file"
    exit 1
fi
