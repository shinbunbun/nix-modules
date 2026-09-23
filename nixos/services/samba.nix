{
  config,
  lib,
  sharedConfig,
  ...
}:
let
  cfg = sharedConfig;
  workgroup = cfg.samba.workgroup;
  serverString = cfg.samba.serverString;
  keepalive = cfg.samba.keepalive;
  deadTime = cfg.samba.deadTime;
  serverMultiChannelSupport = cfg.samba.serverMultiChannelSupport;
  allowedNetworks = cfg.networking.allowedNetworks;

  hostsAllow = lib.concatStringsSep " " allowedNetworks;
in
{
  # openFirewall はここで決めない。enable しただけでは開かないので、
  # どのネットワークへ晒すかはホスト側で明示すること
  config = lib.mkIf config.services.samba.enable {
    services.samba = {
      settings = {
        global = {
          inherit workgroup;
          "server string" = serverString;

          "server min protocol" = "SMB3_00";
          "map to guest" = "never";

          "vfs objects" = "fruit streams_xattr";
          "fruit:metadata" = "stream";
          "fruit:model" = "MacSamba";
          "fruit:posix_rename" = "yes";
          "fruit:veto_appledouble" = "no";
          "fruit:nfs_aces" = "no";
          "fruit:wipe_intentionally_left_blank_rfork" = "yes";
          "fruit:delete_empty_adfiles" = "yes";

          "fruit:time machine" = "no"; # TM非対応の共有でカーネルエラーを防止

          logging = "systemd";

          "hosts allow" = hostsAllow;
          "hosts deny" = "0.0.0.0/0";

          "keepalive" = keepalive;
          "dead time" = deadTime;
          "server multi channel support" = if serverMultiChannelSupport then "yes" else "no";

          "use sendfile" = "yes";
        };
      };
    };

    # macOS/Windows からの自動検出用
    services.samba-wsdd = {
      enable = true;
    };
  };
}
