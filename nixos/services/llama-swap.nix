{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.llamaSwap;
  yamlFormat = pkgs.formats.yaml { };

  serverBin = "${cfg.serverPackage}/bin/llama-server";

  # cmd の "''${PORT}" (Nix ではリテラル埋め込み) は llama-swap が実行時に割り当てる
  # ポートのプレースホルダ。空白区切りでシェル的にトークン化されるため、JSON 等
  # クォートが必要な引数は args 要素として単一引用符付きで渡すこと
  modelToConfig =
    _name: m:
    let
      portArg = if m.port != null then toString m.port else "\${PORT}";
    in
    {
      cmd = lib.concatStringsSep " " (
        [ serverBin ]
        ++ m.args
        ++ [
          "--port"
          portArg
        ]
      );
      inherit (m) ttl;
    }
    // lib.optionalAttrs (m.aliases != [ ]) { inherit (m) aliases; }
    // lib.optionalAttrs (m.env != [ ]) { inherit (m) env; }
    // lib.optionalAttrs (m.port != null) {
      proxy = "http://127.0.0.1:${toString m.port}";
    };

  swapConfig = yamlFormat.generate "llama-swap.yaml" {
    inherit (cfg) healthCheckTimeout logLevel;
    models = lib.mapAttrs modelToConfig cfg.models;
  };

  nvidiaDevices = [
    "/dev/nvidia0 rwm"
    "/dev/nvidiactl rwm"
    "/dev/nvidia-uvm rwm"
    "/dev/nvidia-uvm-tools rwm"
    "/dev/nvidia-modeset rwm"
  ];
in
{
  options.services.llamaSwap = {
    enable = lib.mkEnableOption "llama-swap ベースの OpenAI 互換 model-swapping 推論プロキシ";

    swapPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.llama-swap;
      defaultText = lib.literalExpression "pkgs.llama-swap";
      description = "llama-swap バイナリを提供するパッケージ。";
    };

    serverPackage = lib.mkOption {
      type = lib.types.package;
      description = ''
        llama-server バイナリを提供するパッケージ。CPU ビルド (pkgs.llama-cpp) や
        GPU/CUDA ビルドをホスト側で指定する。
      '';
      example = lib.literalExpression "inputs.self.packages.x86_64-linux.llama-cpp-cuda";
    };

    # 既定は loopback。llama-swap は認証を持たず、モデルの実行そのものを外部に
    # 委ねる口なので、LAN へ出すかどうかはホスト側の明示的な選択にする。
    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "リッスンアドレス (LAN 公開時は 0.0.0.0)。";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8082;
      description = "HTTP API ポート。";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "ファイアウォールで port を開放する。";
    };

    healthCheckTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 300;
      description = "各モデルの起動 health check タイムアウト秒 (大きめの GPU モデルロードを想定)。";
    };

    logLevel = lib.mkOption {
      type = lib.types.str;
      default = "info";
      description = "llama-swap のログレベル。";
    };

    enableNvidiaGpu = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        NVIDIA GPU デバイスへのアクセスを許可する。true で PrivateDevices=false +
        /dev/nvidia* への DeviceAllow を付与する (false のままだと GPU を使えない)。
      '';
    };

    modelsDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/llama-cpp/models";
      description = "GGUF モデル配置ディレクトリ (tmpfiles で作成)。";
    };

    stateDirectory = lib.mkOption {
      type = lib.types.str;
      default = "llama-cpp";
      description = "systemd StateDirectory 名 (/var/lib/<name>)。";
    };

    requiredPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        ConditionPathExists に渡すファイル群。ここに列挙したファイルが全て揃うまで
        サービス起動をスキップする (モデル未配置でのデプロイを起動失敗にしない)。
      '';
    };

    models = lib.mkOption {
      description = "llama-swap が切り替えるモデル定義 (キー = model 名)。";
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            args = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = ''
                llama-server に渡す引数リスト (--model <path> を含む)。--port は
                モジュールが自動付与するため含めない。クォートが必要な値 (JSON 等) は
                単一引用符で囲んだ文字列要素として渡す。
              '';
            };
            aliases = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "この model 名に別名でルーティングするための alias。";
            };
            ttl = lib.mkOption {
              type = lib.types.ints.positive;
              default = 1800;
              description = "idle unload までの秒数。";
            };
            env = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = [ "LLAMA_DEC_SLOTS=0" ];
              description = ''
                この model の llama-server にだけ渡す環境変数 ("KEY=VALUE")。
                systemd.services.llama-swap.environment は全 model 共通なので、
                model ごとに変えたい値はこちらに置く。
              '';
            };
            port = lib.mkOption {
              type = lib.types.nullOr lib.types.port;
              default = null;
              description = ''
                固定 upstream ポート。設定すると llama-server を --port <port> で起動し、
                llama-swap は proxy: http://127.0.0.1:<port> でこのモデルへ接続する。
                llama-server の /metrics を外部 Prometheus から直接 scrape する用途
                (llama-swap 自身の /metrics は host/GPU 統計のみで推論 tps を出さないため)。
                null なら llama-swap が startPort から自動割当する (''${PORT})。
                外部 scrape するにはモデルの args に "--host" "0.0.0.0" を含め、
                openFirewall でこのポートも開放すること (openFirewall=true なら自動で開く)。
              '';
            };
          };
        }
      );
    };

    memoryHigh = lib.mkOption {
      type = lib.types.str;
      default = "20G";
      description = "systemd MemoryHigh (ソフトリミット)。";
    };

    memoryMax = lib.mkOption {
      type = lib.types.str;
      default = "28G";
      description = "systemd MemoryMax (ハードリミット)。";
    };

    nice = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "プロセスの nice 値。";
    };

    cpuWeight = lib.mkOption {
      type = lib.types.ints.positive;
      default = 50;
      description = "systemd CPUWeight (競合時に他サービスへ CPU を譲る)。";
    };
  };

  config = lib.mkIf cfg.enable {
    # DynamicUser + StateDirectory では実体が /var/lib/private/ 配下へ移され /var/lib/<name>
    # は symlink になる。親を tmpfiles で d 宣言すると resetup のたびに衝突するので、
    # 親 (modelsDir の親) は宣言せず models ディレクトリ 1 行だけにする。
    systemd.tmpfiles.rules = [
      "d ${cfg.modelsDir} 0755 root root -"
    ];

    systemd.services.llama-swap = {
      description = "llama-swap OpenAI-compatible model-swapping proxy";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      unitConfig = lib.mkIf (cfg.requiredPaths != [ ]) {
        ConditionPathExists = cfg.requiredPaths;
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.swapPackage}/bin/llama-swap -config ${swapConfig} -listen ${cfg.host}:${toString cfg.port} -watch-config";

        DynamicUser = true;
        StateDirectory = cfg.stateDirectory;

        CPUWeight = cfg.cpuWeight;
        IOWeight = 50;
        Nice = cfg.nice;
        MemoryHigh = cfg.memoryHigh;
        MemoryMax = cfg.memoryMax;

        # Hardening (モデルファイル読み取り + StateDirectory 書き込みのみ許可)
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        NoNewPrivileges = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
        ReadOnlyPaths = cfg.requiredPaths;

        Restart = "on-failure";
        RestartSec = 30;

        # GPU アクセス: PrivateDevices=true だと /dev/nvidia* が見えず GPU を使えない。
        PrivateDevices = !cfg.enableNvidiaGpu;
      }
      // lib.optionalAttrs cfg.enableNvidiaGpu {
        DeviceAllow = nvidiaDevices;
      };
    };

    # openFirewall では llama-swap の proxy port に加え、固定 upstream port
    # (models.<name>.port) も開放する (llama-server /metrics を外部 scrape するため)。
    networking.firewall.allowedTCPPorts = lib.optionals cfg.openFirewall (
      [ cfg.port ] ++ lib.filter (p: p != null) (lib.mapAttrsToList (_: m: m.port) cfg.models)
    );
  };
}
