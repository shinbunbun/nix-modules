{
  sharedConfig,
  ...
}:

let
  cfg = sharedConfig;
in
{
  networking.enableIPv6 = true;

  networking.firewall.allowedTCPPorts = [
    cfg.networking.firewall.generalPort
  ];

  services.avahi = {
    enable = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };
}
