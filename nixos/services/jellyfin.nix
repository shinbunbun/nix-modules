/*
  Jellyfin - メディアサーバー

  機能:
  - メディアファイルのストリーミング再生
  - VAAPI によるハードウェアトランスコード

  設定:
  - デフォルトポート8096でリッスン
  - jellyfinユーザーにrender/videoグループ付与（GPU利用）
*/
{
  lib,
  config,
  ...
}:
{
  config = lib.mkIf config.services.jellyfin.enable {
    # openFirewall はここでは触らない。upstream の既定 (false) のまま、
    # 開けるかどうかはホスト側で services.jellyfin.openFirewall を指定する。
    # このモジュールが担うのは HW トランスコードのためのグループ付与だけ。

    # ハードウェアトランスコード用グループ
    users.users.jellyfin.extraGroups = [
      "render"
      "video"
    ];
  };
}
