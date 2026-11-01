{
  options,
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

  # settings が無い nixpkgs (26.05 以前) でも評価できるよう旧オプションに切り替える
  services.avahi = {
    enable = true;
  }
  // (
    if options.services.avahi ? settings then
      {
        settings.publish = {
          disable-publishing = false;
          publish-addresses = true;
          publish-workstation = true;
        };
      }
    else
      {
        publish = {
          enable = true;
          addresses = true;
          workstation = true;
        };
      }
  );
}
