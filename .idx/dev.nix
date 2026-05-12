{ pkgs, ... }: {
  channel = "stable-25.05";
  packages = [
    pkgs.openssh
    pkgs.curl
  ];
  env = {};
  idx = {
    workspace = {
      onCreate = {
        setup-ssh-tunnel = "chmod +x ./start-ssh-tunnel.sh && ./start-ssh-tunnel.sh";
        default.openFiles = [ "README.md" "index.html" ];
      };
    };
  };
}
