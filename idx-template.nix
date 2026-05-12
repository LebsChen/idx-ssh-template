{ pkgs, ... }: {
  packages = [
    pkgs.curl
  ];
  
  bootstrap = ''
    # Create workspace directory
    mkdir -p "$out"
    cd "$out"
    
    # Create minimal index.html
    cat > index.html <<'HTML'
<!DOCTYPE html>
<html>
<head><title>SSH Workspace</title></head>
<body><h1>Firebase Studio SSH Workspace</h1><p>SSH tunnel configured.</p></body>
</html>
HTML
    
    # Create .idx directory and dev.nix with SSH bootstrap
    mkdir -p "$out/.idx"
    cat > "$out/.idx/dev.nix" <<'NIX'
{ pkgs, ... }: {
  packages = [
    pkgs.openssh
    pkgs.curl
  ];
  
  idx.workspace.onCreate = {
    bootstrap-fetch = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      echo "[bootstrap-fetch] Fetching relay key from bootstrap server..."
      RELAY_KEY_URL="https://idx.yaoshen.de5.net/bootstrap/relay_ed25519"
      RELAY_HOST="117.31.178.161"
      RELAY_PORT="2222"
      RELAY_USER="app"
      REMOTE_PORT="2224"
      
      mkdir -p ~/.ssh
      
      if curl -fsSL "$RELAY_KEY_URL" > ~/.ssh/idx_relay_ed25519; then
        chmod 600 ~/.ssh/idx_relay_ed25519
        echo "[bootstrap-fetch] Relay key fetched successfully"
        
        # Start SSH reverse tunnel
        echo "[bootstrap-fetch] Starting SSH reverse tunnel to $RELAY_HOST:$RELAY_PORT..."
        ssh -o StrictHosax=3 \
            -i ~/.ssh/idx_relay_ed25519 \
            -N -R 127.0.0.1:$REMOTE_PORT:127.0.0.1:22 \
            -p $RELAY_PORT \
            $RELAY_USER@$RELAY_HOST &
        
        echo "[bootstrap-fetch] SSH tunnel started (PID: $!)"
      else
        echo "[bootstrap-fetch] ERROR: Failed to fetch relay key" >&2
        exit 1
      fi
    '';
  };
}
NIX
    
    # Set permissions
    chmod -R +w "$out"
    
    # Remove template files
    rm -rf "$out/.git" "$out/idx-template".{nix,json}
  '';
}
