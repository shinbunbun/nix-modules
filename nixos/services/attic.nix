{
  config,
  pkgs,
  lib,
  inputs,
  sharedConfig,
  ...
}:
let
  cfg = sharedConfig;
  port = cfg.attic.port;
  domain = cfg.attic.domain;
  storagePath = cfg.attic.storagePath;
  dbName = cfg.attic.database.name;
  dbUser = cfg.attic.database.user;
in
{
  sops.secrets = {
    "attic_jwt_secret_base64" = {
      sopsFile = "${inputs.self}/${cfg.sops.files.attic}";
      # atticdユーザーはservices.atticdで動的に作成されるため、rootが所有
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };

  sops.templates."attic/env" = {
    content = ''
      ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=${config.sops.placeholder."attic_jwt_secret_base64"}
    '';
    path = "/run/secrets/rendered/attic/env";
    # テンプレートもrootが所有、atticdサービスが読み取る
    owner = "root";
    group = "root";
    mode = "0400";
  };

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    ensureDatabases = [ dbName ];
    ensureUsers = [
      {
        name = dbUser;
        ensureDBOwnership = true;
      }
    ];

    # peer認証でatticdユーザーからatticDBユーザーへのマッピング
    identMap = ''
      attic-users atticd ${dbUser}
    '';

    authentication = lib.mkAfter ''
      local ${dbName} ${dbUser} peer map=attic-users
    '';
  };

  services.atticd = {
    enable = true;

    environmentFile = config.sops.templates."attic/env".path;

    settings = {
      listen = "[::]:${toString port}";
      allowed-hosts = [
        domain
        "${cfg.networking.hosts.nixos.ip}:${toString port}"
      ];
      database = {
        # peer認証 + Unix socket + 明示的なユーザー名指定
        url = "postgresql:///${dbName}?host=/run/postgresql&user=${dbUser}";
      };

      storage = {
        type = "local";
        path = storagePath;
      };

      chunking = {
        nar-size-threshold = cfg.attic.chunking.narSizeThreshold;
        min-size = cfg.attic.chunking.minSize;
        avg-size = cfg.attic.chunking.avgSize;
        max-size = cfg.attic.chunking.maxSize;
      };

      compression = {
        type = cfg.attic.compression.type;
        level = cfg.attic.compression.level;
      };

      garbage-collection = {
        interval = cfg.attic.garbageCollection.interval;
        default-retention-period = cfg.attic.garbageCollection.retentionPeriod;
      };
    };
  };

  # atticd は DynamicUser のため rebuild 時にユーザーが不在なことがある。
  # root 所有で作成し、ReadWritePaths で atticd に書き込みだけ許可する
  systemd.tmpfiles.rules = [
    "d ${storagePath} 0755 root root -"
  ];

  systemd.services.atticd = {
    after = [
      "postgresql.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    requires = [ "postgresql.service" ];
    serviceConfig = {
      ReadWritePaths = [ storagePath ];
    };
  };

  networking.firewall.allowedTCPPorts = [ port ];
}
