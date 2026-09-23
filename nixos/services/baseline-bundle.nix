{ sharedConfig, ... }:
{
  imports = [
    ./sshd-baseline.nix
    ./fail2ban-baseline.nix
  ];

  networking.firewall.allowedTCPPorts = [ sharedConfig.ssh.port ];
}
