#!/bin/sh
set -e

echo "[tunnel] Starting SSH tunnel setup..."

RELAY_HOST="117.31.178.161"
RELAY_PORT="2222"
RELAY_USER="app"
REMOTE_PORT="2224"

mkdir -p ~/.ssh
chmod 700 ~/.ssh

echo "[tunnel] Creating relay key from embedded base64..."
cat > ~/.ssh/idx_relay_ed25519 <<'RELAYKEY'
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACDzYSMvGlCcZZyTHD67gnqVgBylmYdmCp2M0g7eWlqt0AAAAJDfSkDu30pA
LgAAAAtzc2gtZWQyNTUxOQAAACDzYSMvGlCcZZyTHD67gnqVgBylmYdmCp2M0g7eWlqt0A
AAAECp1Yz7kKwyxiC4yRZPLEPihMgBIjRYgNEnSjohmmMHlzTzYSMvGlCcZZyTHD67gnqVgB
ylmYdmCp2M0g7eWlqt0AAAACWlkeC1yZWxheQECAwQ=
-----END OPENSSH PRIVATE KEY-----
RELAYKEY

chmod 600 ~/.ssh/idx_relay_ed25519

echo "[tunnel] Verifying relay key..."
ssh-keygen -l -f ~/.ssh/idx_relay_ed25519 || {
    echo "[tunnel] ERROR: Invalid relay key"
    exit 1
}

echo "[tunnel] Starting SSH reverse tunnel..."
nohup ssh -N -R "127.0.0.1:$REMOTE_PORT:127.0.0.1:2222" \
    -i ~/.ssh/idx_relay_ed25519 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ServerAliveInterval=60 \
    -o ServerAliveCountMax=3 \
    -p "$RELAY_PORT" \
    "$RELAY_USER@$RELAY_HOST" \
    > ~/.ssh/tunnel.log 2>&1 &

TUNNEL_PID=$!
echo "[tunnel] SSH tunnel started, PID: $TUNNEL_PID"
echo "[tunnel] Log: ~/.ssh/tunnel.log"

# 等待几秒确保 tunnel 启动
sleep 3

# 检查 tunnel 是否还在运行
if ps -p $TUNNEL_PID > /dev/null 2>&1; then
    echo "[tunnel] ✅ SSH tunnel is running"
else
    echo "[tunnel] ❌ SSH tunnel failed to start"
    echo "[tunnel] Log content:"
    cat ~/.ssh/tunnel.log
    exit 1
fi
