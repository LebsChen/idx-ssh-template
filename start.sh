#!/bin/sh
set -e

SISH_HOST="${SISH_HOST:-idx.yaoshen.de5.net}"
SISH_PORT="${SISH_PORT:-2022}"
SISH_USER="${SISH_USER:-user}"
SISH_ALIAS="${SISH_ALIAS:-${GOOGLE_CLOUD_WORKSTATION_NAME:-$(cat /etc/hostname 2>/dev/null | tr -d '[:space:]' || hostname 2>/dev/null)}}"
LOCAL_SSH_PORT="${LOCAL_SSH_PORT:-2222}"

mkdir -p ~/.ssh ~/.ssh/sshd
chmod 700 ~/.ssh

# sish key (shared across all workspaces)
cat > ~/.ssh/sish << 'RELAYKEY'
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACA82EjLxpQnGWckxw+u4J6lYAcpbmHZgqdjNIO3lpardAAAAIjeuvvO3rr7
zgAAAAtzc2gtZWQyNTUxOQAAACA82EjLxpQnGWckxw+u4J6lYAcpbmHZgqdjNIO3lpardA
AAAECp1Yz7kKwyxiC4yRZPLEPihMgBIjRYgNEnSjohmMHlzTzYSMvGlCcZZyTHD67gnqVg
ByluYdmCp2M0g7eWlqt0AAAABHNpc2gB
-----END OPENSSH PRIVATE KEY-----
RELAYKEY
chmod 600 ~/.ssh/sish

# client public key -> authorized_keys
grep -qxF 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICAEHT0QGPuonqX29Dwbyz+mul3/fBO8ej/4eHaFTvFj client' \
    ~/.ssh/authorized_keys 2>/dev/null || \
    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICAEHT0QGPuonqX29Dwbyz+mul3/fBO8ej/4eHaFTvFj client' \
    >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# sshd host key
[ -f ~/.ssh/sshd/ssh_host_ed25519_key ] || \
    ssh-keygen -t ed25519 -f ~/.ssh/sshd/ssh_host_ed25519_key -N '' -q

# stop existing processes
for pid_file in ~/.ssh/sshd.pid ~/.ssh/sish.pid; do
    [ -f "$pid_file" ] && kill "$(cat "$pid_file")" 2>/dev/null || true
done
pkill -f "sshd.*127\.0\.0\.1.*$LOCAL_SSH_PORT\|$SISH_ALIAS:22:127\.0\.0\.1" 2>/dev/null || true
sleep 1

# start sshd
SSHD_BIN="$(command -v sshd)" || { echo "[tunnel] ❌ sshd not found"; exit 1; }
nohup "$SSHD_BIN" -D -p "$LOCAL_SSH_PORT" \
    -o ListenAddress=127.0.0.1 \
    -o HostKey="$HOME/.ssh/sshd/ssh_host_ed25519_key" \
    -o PermitRootLogin=no \
    -o PasswordAuthentication=no \
    -o PubkeyAuthentication=yes \
    -o AuthorizedKeysFile="$HOME/.ssh/authorized_keys" \
    -o PidFile="$HOME/.ssh/sshd.pid" \
    > ~/.ssh/sshd.log 2>&1 &
echo $! > ~/.ssh/sshd.pid
sleep 2

# start sish alias tunnel
nohup ssh -N -R "$SISH_ALIAS:22:127.0.0.1:$LOCAL_SSH_PORT" \
    -i ~/.ssh/sish \
    -p "$SISH_PORT" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    "$SISH_USER@$SISH_HOST" \
    > ~/.ssh/sish.log 2>&1 &
echo $! > ~/.ssh/sish.pid

# verify
sleep 2
ps -p "$(cat ~/.ssh/sshd.pid)" > /dev/null 2>&1 || { echo "[tunnel] ❌ sshd failed"; cat ~/.ssh/sshd.log; exit 1; }
ps -p "$(cat ~/.ssh/sish.pid)" > /dev/null 2>&1 || { echo "[tunnel] ❌ sish failed"; cat ~/.ssh/sish.log; exit 1; }

echo "[tunnel] ✅ sshd + sish running"
echo "[tunnel] connect: ssh -J $SISH_USER@$SISH_HOST:$SISH_PORT user@$SISH_ALIAS"
