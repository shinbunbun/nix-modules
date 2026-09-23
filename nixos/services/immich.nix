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
