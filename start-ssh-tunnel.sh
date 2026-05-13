#!/bin/sh
set -e

echo "[tunnel] Starting SSH tunnel setup..."

# 配置（使用域名）
RELAY_HOST="idx.yaoshen.de5.net"
RELAY_PORT="2222"
RELAY_USER="app"
REMOTE_PORT="${REMOTE_PORT:-2002}"
LOCAL_SSH_PORT="${LOCAL_SSH_PORT:-2222}"

# 1. Setup SSH directory and user bin
mkdir -p ~/.ssh ~/.local/bin
chmod 700 ~/.ssh

# Firebase Studio can miss hostname(1); provide a small shim so SSH commands
# like `hostname` do not trip the broken /etc/bashrc command-not-found hook.
cat > ~/.local/bin/hostname <<'HOSTNAME_SHIM'
#!/bin/sh
cat /etc/hostname 2>/dev/null || printf '%s\n' "idx-workspace"
HOSTNAME_SHIM
chmod +x ~/.local/bin/hostname

# Make the shim visible for the script, interactive shells, and SSH command sessions.
IDX_HELPER_PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
export PATH="$IDX_HELPER_PATH:$PATH"
if ! grep -q 'HOME/.local/bin' ~/.bashrc 2>/dev/null; then
    printf '
# IDX SSH tunnel helpers
export PATH="$HOME/.local/bin:$PATH"
' >> ~/.bashrc
fi

# SSH remote commands may skip ~/.bashrc. Use sshd SetEnv below to force this.
cat > ~/.ssh/idx_ssh_env <<'SSH_ENV'
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
command_not_found_handle() { printf '%s\n' "$1: command not found" >&2; return 127; }
SSH_ENV

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
SSHD_BIN="$(command -v sshd || true)"
if [ -z "$SSHD_BIN" ]; then
    echo "[tunnel] ❌ sshd not found"
    exit 1
fi

echo "[tunnel] Stopping existing local sshd/tunnel if any..."
if [ -f ~/.ssh/sshd.pid ]; then
    kill "$(cat ~/.ssh/sshd.pid)" 2>/dev/null || true
fi
if [ -f ~/.ssh/tunnel.pid ]; then
    kill "$(cat ~/.ssh/tunnel.pid)" 2>/dev/null || true
fi
pkill -f "sshd.*127.0.0.1.*$LOCAL_SSH_PORT" 2>/dev/null || true
pkill -f "127.0.0.1:$REMOTE_PORT:127.0.0.1:$LOCAL_SSH_PORT" 2>/dev/null || true
sleep 1

nohup "$SSHD_BIN" -D -p $LOCAL_SSH_PORT \
    -o ListenAddress=127.0.0.1 \
    -o HostKey=~/.ssh/sshd/ssh_host_ed25519_key \
    -o PermitRootLogin=no \
    -o PasswordAuthentication=no \
    -o PubkeyAuthentication=yes \
    -o AuthorizedKeysFile=~/.ssh/authorized_keys \
    -o PidFile=~/.ssh/sshd.pid \
    -o SetEnv="PATH=$IDX_HELPER_PATH" \
    -o SetEnv="BASH_ENV=$HOME/.ssh/idx_ssh_env" \
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
    -o ExitOnForwardFailure=yes \
    -p "$RELAY_PORT" \
    "$RELAY_USER@$RELAY_HOST" \
    > ~/.ssh/tunnel.log 2>&1 &

TUNNEL_PID=$!
echo "$TUNNEL_PID" > ~/.ssh/tunnel.pid
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
