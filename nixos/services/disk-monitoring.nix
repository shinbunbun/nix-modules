{
  config,
  pkgs,
  lib,
  sharedConfig,
  ...
}:
let
  cfg = config.services.disk-monitoring;
  port = sharedConfig.monitoring.smartctlExporter.port;

  deviceModule = lib.types.submodule {
    options = {
      path = lib.mkOption {
        type = lib.types.str;
        example = "/dev/sda";
        description = ''
          監視対象デバイスの絶対パス。NVMe は namespace block device
          (`/dev/nvme0n1`) を推奨する。controller char device (`/dev/nvme0`) でも
          SMART は読めるが、udev での ACL 付与に依存する。
        '';
      };
      deviceType = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "sat";
        description = ''
          smartctl の `-d` 値。USB-SATA bridge は "sat"、NVMe は "nvme"。
          null の場合 smartd / smartctl の autodetect に任せる。
        '';
      };
      smartdSchedule = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "(S/../../7/02|L/../01/./03)";
        description = ''
          smartd の scheduled self-test パターン (`-s` 引数の中身、外側の括弧含む)。
          null の場合 self-test スケジュールは設定しない。
        '';
      };
      disableAPM = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          udev で `hdparm -B 254` を適用して APM を無効化する。
          USB-SATA HDD でデフォルト APM=128 によりヘッド退避が頻発し
          Load_Cycle_Count が過剰増加する問題を抑制するためのもの。
          path は `/dev/sd<letter>` 形式である必要がある (udev KERNEL match
          が kernel name を期待するため)。symlink path (例: /dev/disk/by-id/...)
          を渡すと udev rule が silent fail するので assertions で禁止している。
        '';
      };
    };
  };

  smartdOptionsFor =
    d:
    let
      typeOpt = lib.optionalString (d.deviceType != null) "-d ${d.deviceType}";
      schedOpt = lib.optionalString (d.smartdSchedule != null) "-s ${d.smartdSchedule}";
      parts = lib.filter (s: s != "") [
        typeOpt
        "-a -o on -S on"
        schedOpt
      ];
    in
    lib.concatStringsSep " " parts;

  apmDevices = lib.filter (d: d.disableAPM) cfg.devices;
in
{
  options.services.disk-monitoring = {
    enable = lib.mkEnableOption "ディスク SMART 監視 (smartd + smartctl_exporter)";

    devices = lib.mkOption {
      type = lib.types.listOf deviceModule;
      default = [ ];
      description = "監視対象 disk のリスト。";
    };

    # 既定は false。smartctl_exporter は認証を持たないので、どのネットワークへ
    # 晒すかはホスト側が決める (monitoring.openFirewall と同じ方針)。
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "smartctl_exporter のポートをファイアウォールで開放するか。";
    };
  };

  config = lib.mkIf cfg.enable {
    # disableAPM は udev KERNEL match のため path が /dev/sdX 形式であることを要求する。
    # symlink や NVMe だと udev rule が silent fail するため、ここで早期に検出する
    assertions = map (d: {
      assertion = !d.disableAPM || (builtins.match "/dev/sd[a-z]+" d.path != null);
      message =
        "services.disk-monitoring: disableAPM=true は path が /dev/sd<letter> 形式の "
        + "場合のみ有効です (got \"${d.path}\")。APM 無効化 udev rule の KERNEL match "
        + "が kernel name を要求するため、symlink path や NVMe では機能しません。";
    }) cfg.devices;

    services.smartd = {
      enable = true;
      autodetect = false;
      devices = map (d: {
        device = d.path;
        options = smartdOptionsFor d;
      }) cfg.devices;
    };

    services.prometheus.exporters.smartctl = {
      enable = true;
      inherit port;
      inherit (cfg) openFirewall;
      devices = map (d: d.path) cfg.devices;
    };

    # APM 無効化 udev rule (HDD の Load_Cycle_Count 抑制)。
    # USB 接続時 (add) と再接続時 (change) に hdparm -B 254 を適用。
    services.udev.extraRules = lib.optionalString (apmDevices != [ ]) (
      lib.concatMapStringsSep "\n" (
        d:
        let
          kernel = lib.removePrefix "/dev/" d.path;
        in
        ''
          ACTION=="add|change", KERNEL=="${kernel}", SUBSYSTEM=="block", \
            RUN+="${pkgs.hdparm}/bin/hdparm -B 254 /dev/%k"
        ''
      ) apmDevices
    );
  };
}
