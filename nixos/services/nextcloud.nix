/*
  Nextcloud - ファイル管理・共有プラットフォーム

  機能:
  - ファイルの同期・共有（WebDAV対応）
  - nginxによるWebサーバー自動設定

  設定:
  - shared/config.nix の nextcloud セクションで有効化
  - hostName は nextcloud.domain から取得
  - adminpassFile 等のシークレットはホスト固有設定で注入

  ここで決めないこと:
  - nginx のリッスンアドレスとポート
  - ファイアウォールの開放
    どのネットワークへ晒すかは利用側の判断。enable しただけで平文 HTTP が
    全インターフェースに出る状態にはしない。ホスト側で
    services.nginx.virtualHosts.<domain>.listen と
    networking.firewall.allowedTCPPorts を指定する。
*/
{
  lib,
  pkgs,
  config,
  sharedConfig,
  ...
}:
let
  cfg = sharedConfig;
  domain = cfg.nextcloud.domain;
in
{
  config = lib.mkIf config.services.nextcloud.enable {
    services.nextcloud = {
      package = pkgs.nextcloud32;
      hostName = domain;

      # SQLite（小規模利用、将来PostgreSQLに移行可能）
      config.dbtype = "sqlite";

      # ログはjournald出力（既存FluentBit経由でLoki/Grafanaに自動収集）
      settings.log_type = "systemd";

      settings.default_phone_region = cfg.system.phoneRegion;

      # 最大アップロードサイズ
      maxUploadSize = "10G";
    };
  };
}
