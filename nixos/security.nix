{
  inputs,
  sharedConfig,
  ...
}:
let
  cfg = sharedConfig;
in
{
  security.polkit.enable = true;

  sops = {
    defaultSopsFile = "${inputs.self}/${cfg.sops.files.sshKeys}";
    age.keyFile = cfg.sops.keyFile;

    # SOPS ファイル側のキー名・配置先・所有者は、いずれも値レイヤのユーザー名から導く。
    # 直書きするとモジュールが特定アカウント専用になる
    secrets."ssh_keys/${cfg.users.nixos.username}" = {
      path = "/etc/ssh/authorized_keys.d/${cfg.users.nixos.username}";
      owner = cfg.users.nixos.username;
      group = "wheel";
      mode = "0444";
      neededForUsers = true;
    };

    # 中身はキャッシュの認証情報なので 0400 root で閉じる。読むのは nix-daemon
    # (root) だけで、0444 だと同ホストの任意のローカルユーザーが読めてしまう
    secrets."nix_netrc" = {
      sopsFile = "${inputs.self}/${cfg.sops.files.nix}";
      path = "/run/secrets/nix-netrc";
      mode = "0400";
    };
  };
}
