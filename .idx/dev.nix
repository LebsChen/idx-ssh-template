{ pkgs, ... }: {
  channel = "stable-25.05";
  packages = [
    pkgs.debianutils
    pkgs.unzip
    pkgs.openssh
    pkgs.git
    pkgs.qemu_kvm
    pkgs.qemu
    pkgs.sudo
    pkgs.cdrkit
    pkgs.cloud-utils
    pkgs.openssl
    pkgs.curl
    pkgs.ttyd
  ];
  env = {};
  services.docker.enable = true;
  idx = {
    previews = {
      previews = {
        web = {
          command = [ "ttyd" "-W" "-p" "$PORT" "bash" ];
          manager = "web";
        };
      };
    };
    workspace = {
      onCreate = {
        setup-ssh-tunnel = ''
          chmod +x ./start-ssh-tunnel.sh
          ./start-ssh-tunnel.sh
        '';
      };
      onStart = {
        auto-debian13 = ''
          chmod +x ./debian13-autostart.sh
          ./debian13-autostart.sh
        '';
      };
    };
  };
}
