{
  lib,
  config,
  ...
}:
{
  config = lib.mkIf config.services.jellyfin.enable {
    # openFirewall はここでは触らない (upstream の既定 false のまま)。
    # このモジュールが担うのは HW トランスコードのためのグループ付与だけ
    users.users.jellyfin.extraGroups = [
      "render"
      "video"
    ];
  };
}
