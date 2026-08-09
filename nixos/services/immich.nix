/*
  Immich - 写真・動画管理サーバー

  機能:
  - 写真・動画の自動バックアップ（iOS/Android対応）
  - 顔認識・オブジェクト認識（ML）
  - Intel GPU (OpenVINO) によるML高速化

  設定:
  - shared/config.nix の immich セクションで有効化
  - ポートはデフォルト2283
  - mediaLocation はホスト固有設定で指定
*/
{
  lib,
  config,
  sharedConfig,
  ...
}:
let
  cfg = sharedConfig;
in
{
  config = lib.mkIf config.services.immich.enable {
    # openFirewall はホスト側で指定する。ここで開けると、enable した時点で
    # 写真ライブラリの API が全インターフェースに出る。
    services.immich = {
      port = cfg.immich.port;
    };
  };
}
