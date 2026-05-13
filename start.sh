#!/bin/sh
set -e

echo "[tunnel] Starting SSH tunnel setup (sish alias mode)..."

# sish TCP alias config. This creates an internal alias, not a public TCP port.
# Client example:
# ssh -J user@117.31.178.161:2022 user@default-13412936
SISH_HOST="${SISH_HOST:-117.31.178.161}"
SISH_PORT="${SISH_PORT:-2022}"
SISH_USER="${SISH_USER:-user}"
SISH_ALIAS="${SISH_ALIAS:-default-13412936}"
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
    printf '\n# IDX SSH tunnel helpers\nexport PATH="$HOME/.local/bin:$PATH"\n' >> ~/.bashrc
fi

# SSH remote commands may skip ~/.bashrc. Use sshd SetEnv below to force this.
cat > ~/.ssh/workspace_ssh_env <<'SSH_ENV'
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
command_not_found_handle() { printf '%s\n' "$1: command not found" >&2; return 127; }
SSH_ENV

# 2. Create shared sish key
echo "[tunnel] Creating shared sish key..."
cat > ~/.ssh/sish << 'RELAYKEY'
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACA82EjLxpQnGWckxw+u4J6lYAcpbmHZgqdjNIO3lpardAAAAJDfSkC730pA
uwAAAAtzc2gtZWQyNTUxOQAAACA82EjLxpQnGWckxw+u4J6lYAcpbmHZgqdjNIO3lpardA
AAAECp1Yz7kKwyxiC4yRZPLEPihMgBIjRYgNEnSjohmMHlzTzYSMvGlCcZZyTHD67gnqVg
ByluYdmCp2M0g7eWlqt0AAAACWlkeC1yZWxheQECAwQ=
-----END OPENSSH PRIVATE KEY-----
RELAYKEY
chmod 600 ~/.ssh/sish

# 3. Add client public key to authorized_keys
echo "[tunnel] Setting up authorized_keys..."
grep -qxF 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICAEHT0QGPuonqX29Dwbyz+mul3/fBO8ej/4eHaFTvFj client' ~/.ssh/authorized_keys 2>/dev/null || cat >> ~/.ssh/authorized_keys << 'CLIENTKEY'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICAEHT0QGPuonqX29Dwbyz+mul3/fBO8ej/4eHaFTvFj client
CLIENTKEY
chmod 600 ~/.ssh/authorized_keys

# 4. Generate sshd host key
echo "[tunnel] Generating sshd host key..."
mkdir -p ~/.ssh/sshd
if [ ! -f ~/.ssh/sshd/ssh_host_ed25519_key ]; then
    ssh-keygen -t ed25519 -f ~/.ssh/sshd/ssh_host_ed25519_key -N '' -C "idx-workspace-host-key"
fi

# 5. Start local sshd
echo "[tunnel] Starting local sshd on 127.0.0.1:$LOCAL_SSH_PORT..."
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
if [ -f ~/.ssh/sish.pid ]; then
    kill "$(cat ~/.ssh/sish.pid)" 2>/dev/null || true
fi
pkill -f "sshd.*127.0.0.1.*$LOCAL_SSH_PORT" 2>/dev/null || true
pkill -f "127.0.0.1:.*:127.0.0.1:$LOCAL_SSH_PORT" 2>/dev/null || true
pkill -f "$SISH_ALIAS:22:127.0.0.1:$LOCAL_SSH_PORT" 2>/dev/null || true
sleep 1

nohup "$SSHD_BIN" -D -p "$LOCAL_SSH_PORT" \
    -o ListenAddress=127.0.0.1 \
    -o HostKey="$HOME/.ssh/sshd/ssh_host_ed25519_key" \
    -o PermitRootLogin=no \
    -o PasswordAuthentication=no \
    -o PubkeyAuthentication=yes \
    -o AuthorizedKeysFile="$HOME/.ssh/authorized_keys" \
    -o PidFile="$HOME/.ssh/sshd.pid" \
    -o SetEnv="PATH=$IDX_HELPER_PATH" \
    -o SetEnv="BASH_ENV=$HOME/.ssh/workspace_ssh_env" \
    > ~/.ssh/sshd.log 2>&1 &

SSHD_PID=$!
echo "$SSHD_PID" > ~/.ssh/sshd.pid
echo "[tunnel] sshd started, PID: $SSHD_PID"
sleep 2

# 6. Start sish TCP alias reverse tunnel
echo "[tunnel] Starting sish alias $SISH_ALIAS:22 -> 127.0.0.1:$LOCAL_SSH_PORT via $SISH_HOST:$SISH_PORT..."
nohup ssh -N -R "$SISH_ALIAS:22:127.0.0.1:$LOCAL_SSH_PORT" \
    -i ~/.ssh/sish \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    -p "$SISH_PORT" \
    "$SISH_USER@$SISH_HOST" \
    > ~/.ssh/sish.log 2>&1 &

SISH_PID=$!
echo "$SISH_PID" > ~/.ssh/sish.pid
echo "[tunnel] sish tunnel started, PID: $SISH_PID"
sleep 3

# 7. Verify local processes
if ps -p "$SSHD_PID" > /dev/null 2>&1; then
    echo "[tunnel] ✅ sshd is running"
else
    echo "[tunnel] ❌ sshd failed to start"
    cat ~/.ssh/sshd.log
    exit 1
fi

if ps -p "$SISH_PID" > /dev/null 2>&1; then
    echo "[tunnel] ✅ sish alias tunnel is running"
else
    echo "[tunnel] ❌ sish alias tunnel failed to start"
    cat ~/.ssh/sish.log
    exit 1
fi

echo "[tunnel] Setup complete!"
echo "[tunnel] sish: $SISH_USER@$SISH_HOST:$SISH_PORT -> alias $SISH_ALIAS:22 -> 127.0.0.1:$LOCAL_SSH_PORT"
printf '%s\n' "[tunnel] client explicit: ssh -J $SISH_USER@$SISH_HOST:$SISH_PORT user@$SISH_ALIAS"
printf '%s\n' "[tunnel] client with ssh config: ssh -J idx.yaoshen.de5.net:$SISH_PORT $SISH_ALIAS"
