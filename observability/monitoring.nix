/*
  監視システム設定モジュール

  このモジュールは Node Exporter と Process Exporter を設定します。
  メトリクス収集・アラート評価・通知は k3s クラスタの VictoriaMetrics スタック
  (VMCluster, VMAgent, VMAlert, VMAlertmanager) に移管済み。
  NixOS 側では各ホストがスクレイプ対象として exporter を提供するのみ。

  提供する設定:
  - services.observability.monitoring.enable           モジュール全体の有効化
  - services.observability.monitoring.nodeExporter.*   Node Exporter (ホスト全体メトリクス)
  - services.observability.monitoring.processExporter.* Process Exporter (プロセス別メトリクス)
  - services.observability.monitoring.openFirewall      exporter ポートのファイアウォール開放

  nodeExporter と processExporter は独立して enable 可能。
  (既に services.prometheus.exporters.node を直書きしているホストは
   nodeExporter.enable = false にして processExporter だけ利用できる)
*/
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

    # Node Exporter設定
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

      # ethtool collector は node_exporter の既定では無効なため、明示的に
      # 有効化する必要がある。enabledCollectors / extraFlags を直接いじると
      # ホスト側で既定の一覧を再列挙する羽目になるので、専用オプションとして
      # 切り出して collector とフラグの両方をここで組み立てる。
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

    # Process Exporter 設定 (プロセス別 CPU/メモリ等)
    processExporter = {
      enable = mkOption {
        type = types.bool;
        # nodeExporter と異なり opt-in。既存ホストの挙動を変えないため default false。
        default = false;
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
          # 実行ファイル名 (comm) ごとに集約する。top の COMMAND 列に相当。
          # /nix/store パスは exe basename ではなく comm を使うことで剥がれる。
          # cmdline = [ ".+" ] で cmdline を持つ全プロセスにマッチ
          # (cmdline が空のカーネルスレッドは除外される)。
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

    # ファイアウォール設定
    #
    # 既定は false。exporter は認証を持たないので、どのネットワークへ晒すかは
    # モジュールではなくホスト側が決める。enable しただけで全インターフェースに
    # 開くと、公開の意思表示なしに口が開く。
    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall ports for enabled exporters (Node Exporter and/or Process Exporter)";
    };
  };

  config = mkIf cfg.enable {
    # Node Exporter設定
    services.prometheus.exporters.node = mkIf cfg.nodeExporter.enable {
      enable = true;
      port = cfg.nodeExporter.port;

      enabledCollectors =
        cfg.nodeExporter.enabledCollectors ++ optional cfg.nodeExporter.ethtool.enable "ethtool";

      # device-include は devices を指定したときだけ付ける。
      # 空のまま付けると "^()$" になって全インタフェースが除外されてしまう。
      extraFlags =
        cfg.nodeExporter.extraFlags
        ++ optional (
          cfg.nodeExporter.ethtool.enable && cfg.nodeExporter.ethtool.devices != [ ]
        ) "--collector.ethtool.device-include=^(${concatStringsSep "|" cfg.nodeExporter.ethtool.devices})$";
    };

    # Process Exporter設定
    services.prometheus.exporters.process = mkIf cfg.processExporter.enable {
      enable = true;
      port = cfg.processExporter.port;
      # submodule 化で未設定フィールドが null になるため、null を除いてから
      # process_names に渡す (従来の types.anything 時と同一の YAML を生成する)。
      settings.process_names = map (
        entry: filterAttrs (_: v: v != null) entry
      ) cfg.processExporter.processNames;
    };

    # ファイアウォール設定 (有効な exporter のポートだけ開放)
    networking.firewall.allowedTCPPorts =
      (optional (cfg.openFirewall && cfg.nodeExporter.enable) cfg.nodeExporter.port)
      ++ (optional (cfg.openFirewall && cfg.processExporter.enable) cfg.processExporter.port);

    # システムパッケージ (CLI 診断用に意図的に PATH へ載せる)
    #
    # nixpkgs の services.prometheus.exporters.{node,process} モジュールは
    # systemd service の ExecStart で store パスを直接叩くだけで、exporter
    # バイナリを environment.systemPackages へは追加しない。そのため
    # この行は重複ではなく、`node_exporter --help` 等を手元で実行して
    # collector/flag を確認するための診断用に PATH へ載せる目的。
    environment.systemPackages =
      (optional cfg.nodeExporter.enable pkgs.prometheus-node-exporter)
      ++ (optional cfg.processExporter.enable pkgs.prometheus-process-exporter);
  };
}
