/*
  Fluent Bitログ収集エージェント設定モジュール

  このモジュールは以下の機能を提供します：
  - Fluent Bit: 軽量高速なログ収集・転送エージェント
  - 設定ファイルの柔軟な管理
  - systemd-journalやsyslogからのログ収集
  - LokiやVectorへの送信

  使用方法:
  - 設定ファイルを用意して configFile option で指定
  - または、独自の systemd service を作成
*/
{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.services.observability.fluentBit;
in
{
  options.services.observability.fluentBit = {
    enable = mkEnableOption "Fluent Bit log collection agent";

    package = mkOption {
      type = types.package;
      default = pkgs.fluent-bit;
      description = "Fluent Bit package to use";
    };

    configFile = mkOption {
      type = types.path;
      description = ''
        Path to Fluent Bit configuration file.
        The file should be in Fluent Bit's native configuration format.
      '';
      example = literalExpression "./fluent-bit.conf";
    };

    port = mkOption {
      type = types.port;
      default = 2020;
      description = ''
        Fluent Bit HTTP メトリクスポート (firewall 開放専用)。

        この値は openFirewall = true のとき firewall を開けるためだけに
        使われ、Fluent Bit 本体には渡らない。実際に listen する HTTP
        ポートは configFile 内の [SERVICE] HTTP_Port で設定すること。
        両者を一致させるのは利用者の責任。
      '';
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/fluent-bit";
      description = ''
        Fluent Bit のデータ保存ディレクトリ。

        systemd の StateDirectory として使われるため /var/lib/ の
        直下 (= /var/lib/<name> 形式) である必要がある。StateDirectory は
        /var/lib からの相対名のみを受け付け、本モジュールは baseNameOf で
        その相対名を導出するため、/var/lib/foo/bar のようなネストした
        パスを渡すと StateDirectory = "bar" となり systemd が
        /var/lib/bar を作成してしまう (意図とずれる)。これを防ぐため
        assertion で直下のみを受理する。実ディレクトリは systemd が
        作成・管理する。
      '';
    };

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Additional packages to make available to Fluent Bit";
      example = literalExpression "[ pkgs.geoip ]";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall ports for Fluent Bit";
    };

    firewallPorts = mkOption {
      type = types.listOf types.port;
      default = [ ];
      description = "Additional firewall ports to open for Fluent Bit";
      example = [ 514 ]; # syslog
    };
  };

  config = mkIf cfg.enable {
    # dataDir は systemd StateDirectory (= /var/lib 配下の相対名) として
    # 使うため /var/lib/ の直下であることを保証する。
    # StateDirectory は baseNameOf cfg.dataDir で導出するため、
    # /var/lib/foo/bar のようなネストしたパスを許すと StateDirectory = "bar"
    # となり systemd が /var/lib/bar を作成してしまい意図とずれる。
    # そのため hasPrefix ではなく「正規化後が /var/lib/<basename> と一致する」
    # ことを要求し、直下のみを受理する。
    assertions = [
      {
        assertion = cfg.dataDir == "/var/lib/" + baseNameOf cfg.dataDir;
        message = "services.observability.fluentBit.dataDir は /var/lib/ の直下 (= /var/lib/<name> 形式) である必要があります (現在値: ${cfg.dataDir})。systemd StateDirectory が /var/lib からの相対名のみを受け付け、本モジュールは baseNameOf で相対名を導出するため、ネストしたパスを渡すと systemd が意図しないディレクトリを作成します。";
      }
    ];

    # Fluent Bit systemd service
    systemd.services.fluent-bit = {
      description = "Fluent Bit Log Processor";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/fluent-bit -c ${cfg.configFile}";
        Restart = "on-failure";
        RestartSec = "10s";

        # セキュリティ設定
        DynamicUser = false;
        User = "fluent-bit";
        Group = "fluent-bit";

        # ディレクトリ設定
        # StateDirectory は /var/lib からの相対名なので dataDir の basename を使う。
        # 既定 dataDir = /var/lib/fluent-bit のとき basename = "fluent-bit"。
        StateDirectory = baseNameOf cfg.dataDir;
        StateDirectoryMode = "0750";

        # ログアクセス権限
        SupplementaryGroups = [ "systemd-journal" ];

        # 特権ポート（<1024）へのバインド許可
        # syslog input が privileged port (514/udp) を listen するため
        # CAP_NET_BIND_SERVICE を Ambient で付与する。
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];

        # systemd hardening
        # AmbientCapabilities で付与したケーパビリティに対する bounding set を
        # 同一集合に絞り、それ以外のケーパビリティ取得を禁止する (対称化)。
        # NoNewPrivileges で exec によるケーパビリティ/特権昇格を遮断する。
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
        NoNewPrivileges = true;

        # ファイルシステム保護
        # ProtectSystem = "strict" は / 全体を read-only にする (/dev /proc /sys 除く)。
        # StateDirectory (cfg.dataDir) への書き込みのみ ReadWritePaths で許可する。
        # systemd-journal の読み取り (/var/log/journal, /run/log/journal) は
        # read アクセスのため strict でも塞がれない。fluent-bit が書き込むのは
        # cfg.dataDir (= storage.path のファイルシステムバッファ、macOS では
        # storage DB も同配下) のみで、これは StateDirectory として確保される。
        # よって ReadWritePaths に dataDir を含めれば書き込みは過不足なく許可される。
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.dataDir ];
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        # ネットワーク (Loki/Vector への TCP、syslog の UDP) と
        # systemd-journal アクセス (AF_UNIX/AF_NETLINK) に必要な
        # アドレスファミリのみ許可する。
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_NETLINK"
          "AF_INET"
          "AF_INET6"
        ];

        # リソース制限
        MemoryMax = "512M";
        CPUQuota = "100%";
      };
    };

    # fluent-bit ユーザーとグループ
    users.users.fluent-bit = {
      isSystemUser = true;
      group = "fluent-bit";
      description = "Fluent Bit daemon user";
    };

    users.groups.fluent-bit = { };

    # ファイアウォール設定
    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall ([ cfg.port ] ++ cfg.firewallPorts);

    networking.firewall.allowedUDPPorts = mkIf cfg.openFirewall cfg.firewallPorts;

    # システムパッケージ
    environment.systemPackages = [ cfg.package ] ++ cfg.extraPackages;
  };
}
