{ pkgs, ... }: {
  channel = "stable-25.05";
  packages = [
    pkgs.openssh
    pkgs.git
  ];
  
  idx = {
    workspace = {
      onCreate = {
        setup-ssh = ''
          echo "[onCreate] Setting up SSH tunnel..."
          chmod +x ./start-ssh-tunnel.sh
          ./start-ssh-tunnel.sh
        '';
      };
    };
  };
}
