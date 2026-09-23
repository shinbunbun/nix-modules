{
  config,
  pkgs,
  lib,
  sharedConfig,
  ...
}:
let
  cfg = sharedConfig;
  enable = cfg.management.cockpit.enable;
  port = cfg.management.cockpit.port;
  domain = cfg.management.cockpit.domain;
  desktopDomain = cfg.cloudflare.desktop.cockpit.domain or "";
  allowedNetworks = cfg.networking.allowedNetworks;
in
{
  config = lib.mkIf enable {
    services.cockpit = {
      enable = true;
      inherit port;
      openFirewall = false; # ファイアウォールは手動で制御

      settings = {
        WebService = {
          Origins = lib.mkForce (
            if desktopDomain != "" then
              "https://${domain} wss://${domain} https://${desktopDomain} wss://${desktopDomain}"
            else
              "https://${domain} wss://${domain}"
          );
          ProtocolHeader = "X-Forwarded-Proto"; # リバースプロキシ使用時に信頼する
          LoginTitle = "Server Management Portal";
          AllowUnencrypted = true; # Cloudflare Tunnel 経由なので HTTPS 終端は不要
        };

        Session = {
          IdleTimeout = 15; # 分
          Banner = "/etc/cockpit/issue.cockpit";
        };
      };
    };

    environment.etc."cockpit/issue.cockpit".text = ''
      Welcome to ${config.networking.hostName} Management Portal

      This system is for authorized use only.
      All activities are monitored and logged.
    '';

    # 特定のネットワークからのみ許可
    networking.firewall.extraCommands = lib.mkIf config.networking.firewall.enable ''
      ${lib.concatMapStrings (network: ''
        iptables -A nixos-fw -p tcp --dport ${toString port} -s ${network} -j ACCEPT
      '') allowedNetworks}

      # WireGuardインターフェースからのアクセスを許可
      iptables -A nixos-fw -p tcp --dport ${toString port} -i wg0 -j ACCEPT
    '';

    environment.systemPackages = with pkgs; [ ];
  };
}
