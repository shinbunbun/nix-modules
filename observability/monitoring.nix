{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.services.observability.monitoring;
in
{
  options.services.observability.monitoring = {
    enable = mkEnableOption "Node Exporter and Process Exporter for system and per-process metrics";

    nodeExporter = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Node Exporter for system metrics";
      };

      port = mkOption {
        type = types.port;
        default = 9100;
        description = "Port for Node Exporter metrics endpoint";
      };

      enabledCollectors = mkOption {
        type = types.listOf types.str;
        default = [
          "cpu"
          "diskstats"
          "filesystem"
          "loadavg"
          "meminfo"
          "netdev"
          "stat"
          "time"
          "vmstat"
          "systemd"
          "processes"
          "hwmon"
          "thermal_zone"
          "interrupts"
          "powersupplyclass"
          "tcpstat"
        ];
        description = "List of collectors to enable";
      };

      extraFlags = mkOption {
        type = types.listOf types.str;
        default = [
          "--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|run/user/.+)($|/)"
          "--collector.netdev.device-exclude=^(veth.*|br.*|docker.*|virbr.*|lo|wlp[0-9]s0)$"
        ];
        description = "Extra command-line flags for Node Exporter";
      };

      # enabledCollectors / extraFlags を直接いじるとホスト側で既定の一覧を
      # 再列挙する羽目になるので、専用オプションとして切り出す
      ethtool = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Enable the ethtool collector, which exposes NIC driver-level counters
            (rx_missed_errors, rx_no_buffer_count, ...) that are not visible in
            /proc/net/dev. Disabled by default in node_exporter itself.
          '';
        };

        devices = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "eno1" ];
          description = ''
            Interfaces to collect ethtool statistics for, passed as
            --collector.ethtool.device-include.

            Leaving this empty collects every interface. On hosts running a CNI
            (cilium/flannel) that means every veth/lxc virtual interface as well,
            multiplying the number of interfaces by the number of driver counters.
            Listing the physical NICs explicitly is strongly recommended.
          '';
        };
      };
    };

    processExporter = {
      enable = mkOption {
        type = types.bool;
        default = false; # nodeExporter と異なり opt-in。既存ホストの挙動を変えないため
        description = "Enable Process Exporter (ncabatoff/process-exporter) for per-process metrics";
      };

      port = mkOption {
        type = types.port;
        default = 9256;
        description = "Port for Process Exporter metrics endpoint";
      };

      processNames = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              name = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = ''
                  groupname テンプレート (例 "{{.Comm}}", "{{.ExeBase}}")。
                  マッチしたプロセスをどの groupname ラベルに集約するか。
                '';
              };
              comm = mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
                description = "実行ファイル名 (comm) のリストでマッチ。";
              };
              exe = mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
                description = "実行ファイルパス (exe) のリストでマッチ。";
              };
              cmdline = mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
                description = "コマンドライン全体に対する正規表現リストでマッチ。";
              };
            };
          }
        );
        default = [
          # comm ごとに集約 (top の COMMAND 列相当)。/nix/store パスは exe ではなく
          # comm を使うことで剥がれる。cmdline=[".+"] でカーネルスレッドを除外する
          {
            name = "{{.Comm}}";
            cmdline = [ ".+" ];
          }
        ];
        description = ''
          process-exporter の process_names 設定 (groupname への集約ルール)。
          namedprocess_namegroup_* メトリクスの groupname ラベルを決める。
          設定構文は https://github.com/ncabatoff/process-exporter を参照。
          .Comm の代わりに .ExeBase を使うと 15 文字切り詰めを回避できる。
        '';
      };
    };

    # 既定は false。exporter は認証を持たないので、どのネットワークへ
    # 晒すかはホスト側が決める (monitoring.openFirewall と同じ方針)。
    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall ports for enabled exporters (Node Exporter and/or Process Exporter)";
    };
  };

  config = mkIf cfg.enable {
    services.prometheus.exporters.node = mkIf cfg.nodeExporter.enable {
      enable = true;
      port = cfg.nodeExporter.port;

      enabledCollectors =
        cfg.nodeExporter.enabledCollectors ++ optional cfg.nodeExporter.ethtool.enable "ethtool";

      # device-include は devices を指定したときだけ付ける。
      # 空のまま付けると "^()$" になって全インタフェースが除外されてしまう
      extraFlags =
        cfg.nodeExporter.extraFlags
        ++ optional (
          cfg.nodeExporter.ethtool.enable && cfg.nodeExporter.ethtool.devices != [ ]
        ) "--collector.ethtool.device-include=^(${concatStringsSep "|" cfg.nodeExporter.ethtool.devices})$";
    };

    services.prometheus.exporters.process = mkIf cfg.processExporter.enable {
      enable = true;
      port = cfg.processExporter.port;
      # submodule 化で未設定フィールドが null になるため、null を除いてから渡す
      settings.process_names = map (
        entry: filterAttrs (_: v: v != null) entry
      ) cfg.processExporter.processNames;
    };

    networking.firewall.allowedTCPPorts =
      (optional (cfg.openFirewall && cfg.nodeExporter.enable) cfg.nodeExporter.port)
      ++ (optional (cfg.openFirewall && cfg.processExporter.enable) cfg.processExporter.port);

    # nixpkgs の exporters モジュールはバイナリを environment.systemPackages へ
    # 追加しないため、`node_exporter --help` 等の手元診断用に明示的に載せる
    environment.systemPackages =
      (optional cfg.nodeExporter.enable pkgs.prometheus-node-exporter)
      ++ (optional cfg.processExporter.enable pkgs.prometheus-process-exporter);
  };
}
