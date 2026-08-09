/*
  サービス設定モジュール

  このモジュールは以下のサービスを設定します：
  - OpenSSHサーバー（セキュリティ強化設定付き）
    → SSH の強化設定本体は ./sshd-baseline.nix に分離し、ここでは import する。
      複数ホストで共有する SSH ベースラインを一元管理するため。
  - Fail2ban（SSH保護）
    → 強化 jail 本体は ./fail2ban-baseline.nix に分離し、ここでは import する。
      ホスト間で検出強度が食い違わないよう一元管理するため。
  - ファイアウォール（SSHポートの開放）
  - Dockerコンテナランタイム

  config.nixの値を参照して設定を行います。
*/
{
  config,
  pkgs,
  lib,
  sharedConfig,
  ...
}:
let
  cfg = sharedConfig;
in
{
  imports = [
    # SSH の強化設定 (services.openssh + banner) を提供するベースライン
    ./sshd-baseline.nix

    # fail2ban の強化 jail を提供するベースライン。
    # sshd-baseline とは別ファイルにしてあるのは、Docker やファイアウォールまでは
    # 要らず SSH 強化と fail2ban だけを取り込みたいホストがあるため。
    ./fail2ban-baseline.nix
  ];

  # ファイアウォール設定 - SSHポートを許可
  networking.firewall.allowedTCPPorts = [ cfg.ssh.port ];

  # Docker
  virtualisation.docker.enable = true;
}
