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
  # openFirewall と nginx のリッスンアドレスはここで決めない。enable しただけで
  # 平文 HTTP が全インターフェースに出る状態にはせず、ホスト側で明示する
  config = lib.mkIf config.services.nextcloud.enable {
    services.nextcloud = {
      package = pkgs.nextcloud33;
      hostName = domain;

      config.dbtype = "sqlite";

      settings.log_type = "systemd"; # Fluent Bit 経由で Loki へ収集される

      settings.default_phone_region = cfg.system.phoneRegion;

      maxUploadSize = "10G";
    };
  };
}
