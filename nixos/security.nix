/*
  セキュリティ関連設定モジュール

  このモジュールは以下のセキュリティ機能を提供します：
  - PAM設定（SSHエージェント認証など）
  - Polkitによる特権管理
  - sudoルールの設定
  - システムセキュリティモジュールの有効化

  セキュリティ強化のための基本的な設定を提供します。
*/
{
  config,
  pkgs,
  lib,
  inputs,
  sharedConfig,
  ...
}:
let
  cfg = sharedConfig;
in
{
  # PAM設定
  security.pam.services = {
    sudo.sshAgentAuth = true;
  };

  # Polkit
  security.polkit.enable = true;

  # SOPS設定
  sops = {
    defaultSopsFile = "${inputs.self}/secrets/ssh-keys.yaml";
    age.keyFile = cfg.sops.keyFile;

    # SOPS ファイル側のキー名・配置先・所有者は、いずれも値レイヤのユーザー名から導く。
    # 直書きするとモジュールが特定アカウント専用になる。
    secrets."ssh_keys/${cfg.users.nixos.username}" = {
      path = "/etc/ssh/authorized_keys.d/${cfg.users.nixos.username}";
      owner = cfg.users.nixos.username;
      group = "wheel";
      mode = "0444";
      neededForUsers = true;
    };

    # Atticプライベートキャッシュ用のnetrc。
    # 中身はキャッシュの認証情報なので 0400 root で閉じる。読むのは nix-daemon
    # (root) だけで、0444 だと同ホストの任意のローカルユーザーが読めてしまう。
    secrets."nix_netrc" = {
      sopsFile = "${inputs.self}/secrets/nix.yaml";
      path = "/run/secrets/nix-netrc";
      mode = "0400";
    };
  };
}
