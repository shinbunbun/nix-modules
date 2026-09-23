{ sharedConfig, ... }:
let
  cfg = sharedConfig;
in
{
  services.fail2ban = {
    enable = true;
    # listOf str なのでホスト側で追記すればマージされる
    ignoreIP = cfg.fail2ban.ignoreNetworks;

    # ホスト側で上書きする場合は同一属性の二重定義になるため mkForce が必要
    jails.sshd.settings = {
      enabled = true;
      port = cfg.ssh.port;
      # 既定の sshd フィルタは公開鍵認証のみのホストで多くの試行を拾わない。
      # aggressive は接続拒否パターンも拾うため PasswordAuthentication=false 構成でほぼ必須
      filter = "sshd[mode=aggressive]";
      maxretry = 3;
      findtime = 600;
      bantime = 3600;
      # nftables を使うホストでこの action (iptables 直書き) を import すると、
      # nixpkgs の banaction 自動切替 (nftables-multiport) が迂回され ban が効かなくなる。
      # nftables 化する際はここも変更すること
      action = ''iptables[name=SSH, port="${toString cfg.ssh.port}", protocol=tcp]'';
    };
  };
}
