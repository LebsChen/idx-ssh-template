#!/bin/sh
set -e

echo "[tunnel] Starting SSH tunnel setup..."

# 配置（使用域名）
RELAY_HOST="idx.yaoshen.de5.net"
RELAY_PORT="2222"
RELAY_USER="app"
REMOTE_PORT="2224"
LOCAL_SSH_PORT="22"

# 1. Setup SSH directory
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# 2. Create relay key
echo "[tunnel] Creating relay key..."
cat > ~/.ssh/idx_relay_ed25519 << 'RELAYKEY'
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACA82EjLxpQnGWckxw+u4J6lYAcpbmHZgqdjNIO3lpardAAAAJDfSkC730pA
uwAAAAtzc2gtZWQyNTUxOQAAACA82EjLxpQnGWckxw+u4J6lYAcpbmHZgqdjNIO3lpardA
AAAECp1Yz7kKwyxiC4yRZPLEPihMgBIjRYgNEnSjohmMHlzTzYSMvGlCcZZyTHD67gnqVg
ByluYdmCp2M0g7eWlqt0AAAACWlkeC1yZWxheQECAwQ=
-----END OPENSSH PRIVATE KEY-----
RELAYKEY

chmod 600 ~/.ssh/idx_relay_ed25519

# 3. Add client public key to authorized_keys
echo "[tunnel] Setting up authorized_keys..."
cat >> ~/.ssh/authorized_keys << 'CLIENTKEY'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICAEHT0QGPuonqX29Dwbyz+mul3/fBO8ej/4eHaFTvFj openclaw-idx-client
CLIENTKEY

chmod 600 ~/.ssh/authorized_keys

# 4. Generate sshd host key
echo "[tunnel] Generating sshd host key..."
mkdir -p ~/.ssh/sshd
if [ ! -f ~/.ssh/sshd/ssh_host_ed25519_key ]; then
    ssh-keygen -t ed25519 -f ~/.ssh/sshd/ssh_host_ed25519_key -N '' -C "idx-workspace-host-key"
fi

# 5. Start sshd
echo "[tunnel] Starting sshd on port $LOCAL_SSH_PORT..."
nohup /usr/bin/sshd -D -p $LOCAL_SSH_PORT \
    -o ListenAddress=127.0.0.1 \
    -o HostKey=~/.ssh/sshd/ssh_host_ed25519_key \
    -o PermitRootLogin=no \
    -o PasswordAuthentication=no \
    -o PubkeyAuthentication=yes \
    -o AuthorizedKeysFile=~/.ssh/authorized_keys \
    -o PidFile=~/.ssh/sshd.pid \
    > ~/.ssh/sshd.log 2>&1 &

SSHD_PID=$!
echo "[tunnel] sshd started, PID: $SSHD_PID"
sleep 2

# 6. Start SSH reverse tunnel
echo "[tunnel] Starting SSH reverse tunnel to $RELAY_HOST:$RELAY_PORT..."
nohup ssh -N -R "127.0.0.1:$REMOTE_PORT:127.0.0.1:$LOCAL_SSH_PORT" \
    -i ~/.ssh/idx_relay_ed25519 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -p "$RELAY_PORT" \
    "$RELAY_USER@$RELAY_HOST" \
    > ~/.ssh/tunnel.log 2>&1 &

TUNNEL_PID=$!
echo "[tunnel] SSH tunnel started, PID: $TUNNEL_PID"
sleep 3

# 7. Verify
if ps -p $SSHD_PID > /dev/null 2>&1; then
    echo "[tunnel] ✅ sshd is running"
else
    echo "[tunnel] ❌ sshd failed to start"
    cat ~/.ssh/sshd.log
fi

if ps -p $TUNNEL_PID > /dev/null 2>&1; then
    echo "[tunnel] ✅ SSH tunnel is running"
else
    echo "[tunnel] ❌ SSH tunnel failed to start"
    cat ~/.ssh/tunnel.log
fi

echo "[tunnel] Setup complete!"
echo "[tunnel] Relay: $RELAY_HOST:$RELAY_PORT -> Remote port: $REMOTE_PORT"
