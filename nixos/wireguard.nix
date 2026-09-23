{
  config,
  pkgs,
  lib,
  inputs,
  sharedConfig,
  ...
}:
let
  sopsWireGuardHelper = import ../lib/sops-wireguard.nix { inherit inputs; };
  cfg = sharedConfig;
in
sopsWireGuardHelper.mkSopsWireGuardConfig { inherit config pkgs lib; } {
  sopsFile = "${inputs.self}/${cfg.sops.files.wireguard}";
  privateKeyPath = cfg.wireguard.nixos.privateKeyPath;
  publicKeyPath = cfg.wireguard.nixos.publicKeyPath;
  interfaceName = cfg.wireguard.nixos.interfaceName;
  interfaceAddress = "${cfg.wireguard.nixos.clientIp}/24";
  peerEndpoint = cfg.wireguard.nixos.serverEndpoint;
  peerAllowedIPs = [ "${cfg.wireguard.network.serverIp}/32" ];
  persistentKeepalive = cfg.wireguard.persistentKeepalive;
  isDarwin = false;
}
