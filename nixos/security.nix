/*
  セキュリティ関連設定モジュール

  このモジュールは以下のセキュリティ機能を提供します：
  - Polkitによる特権管理
  - SOPS (sops-nix) の既定ファイルと ssh authorized_keys の配置

  sudo のルールは public/nixos/services/deploy-user.nix にある。

  security.pam.services.sudo.sshAgentAuth = true は撤去した (#597)。撤去しても
  nixpkgs の security/sudo.nix が同じ既定値を立てるため属性値自体は変わらず
  (実測)、実際に有効かは別のマスタースイッチ security.pam.sshAgentAuth.enable
  (現状 false) が決める。つまり元から nixpkgs 既定と重複した冗長行だった。
  マスタースイッチを立てると他サービスのためでも sudo まで巻き込まれる点に注意。
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
  # Polkit
  security.polkit.enable = true;

  # SOPS設定
  sops = {
    defaultSopsFile = "${inputs.self}/${cfg.sops.files.sshKeys}";
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
      sopsFile = "${inputs.self}/${cfg.sops.files.nix}";
      path = "/run/secrets/nix-netrc";
      mode = "0400";
    };
  };
}
