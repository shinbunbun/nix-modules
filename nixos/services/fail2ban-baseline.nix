/*
  fail2ban ベースラインモジュール

  SSH ブルートフォース保護の共通設定を提供します。全 NixOS ホストで同一の
  検出強度・ban 時間を共有するために、ホスト側で個別に定義せずこのモジュールを
  import してください。

  提供する設定:
  - services.fail2ban.enable
  - services.fail2ban.ignoreIP (shared/config.nix の fail2ban.ignoreNetworks)
  - services.fail2ban.jails.sshd.settings
    - filter = "sshd[mode=aggressive]"
      既定の sshd フィルタは公開鍵認証のみのホストで多くの試行を拾わない。
      aggressive モードは "Connection closed by authenticating user" 等の
      パターンまで拾うため、PasswordAuthentication=false の構成では必須に近い。
    - bantime = 3600 / findtime = 600 / maxretry = 3

  port について:
  nixpkgs の fail2ban モジュールは sshd jail の port に
  `mkDefault (concatMapStringsSep "," toString config.services.openssh.ports)`
  を敷いているため、明示しなくても実際の SSH ポートを監視する。
  ここで明示するのは、banaction が参照するポートを設定値と一致させ、
  意図を設定ファイル上で読み取れるようにするため。

  nftables を使うホストでの注意:
  `action` に `iptables[...]` を直書きしているため、`networking.nftables.enable`
  なホストがこのモジュールを import すると ban が効かなくなる。nixpkgs は
  `banaction` を `nftables-multiport` に自動で切り替えるが、jail 側の `action` を
  明示するとその分岐を迂回してしまうため。nftables 化する際はここも変更すること。

  ホスト側から上書きする場合:
  - `ignoreIP` は `listOf str` なので、ホスト側で追記すればマージされる
  - `jails.sshd.settings.*` は同一属性の二重定義になるため `mkForce` が必要

  値は shared/config.nix を参照して設定します。
*/
{ sharedConfig, ... }:
let
  cfg = sharedConfig;
in
{
  services.fail2ban = {
    enable = true;
    ignoreIP = cfg.fail2ban.ignoreNetworks;

    jails.sshd.settings = {
      enabled = true;
      port = cfg.ssh.port;
      filter = "sshd[mode=aggressive]";
      maxretry = 3;
      findtime = 600;
      bantime = 3600;
      action = ''iptables[name=SSH, port="${toString cfg.ssh.port}", protocol=tcp]'';
    };
  };
}
