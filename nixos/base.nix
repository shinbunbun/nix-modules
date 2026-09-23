{
  pkgs,
  sharedConfig,
  ...
}:

let
  cfg = sharedConfig;
in
{
  # system.stateVersion は各ホストの default.nix で設定する（ホストごとに異なるため）
  system.autoUpgrade.enable = false;
  system.autoUpgrade.allowReboot = false;

  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Attic バイナリキャッシュ設定（プライベート）
  nix.settings = {
    substituters = [
      "https://cache.nixos.org"
      # LAN直接アクセス（最優先）
      "http://${cfg.networking.hosts.nixos.ip}:${toString cfg.attic.port}/main"
      "https://${cfg.attic.domain}/main" # 外部フォールバック
    ];

    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      cfg.attic.trustedPublicKey
    ];

    netrc-file = "/run/secrets/nix-netrc";
  };

  boot.loader.systemd-boot.enable = true;
  # ESP の世代蓄積による枯渇を防ぐため保持世代数を制限する
  boot.loader.systemd-boot.configurationLimit = cfg.system.bootConfigurationLimit;
  boot.loader.efi.canTouchEfiVariables = true;

  time.timeZone = cfg.system.timeZone;

  services.timesyncd = {
    enable = true;
    servers = cfg.system.ntpServers;
  };

  users.users.${cfg.users.nixos.username} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "docker"
    ];
    shell = pkgs.zsh;
    # authorizedKeys.keyFilesはprofileごとに上書き
  };

  programs.zsh.enable = true;

  environment.systemPackages = [
    pkgs.vim
    pkgs.wget
  ];

  virtualisation = {
    vmVariantWithBootLoader = {
      virtualisation = {
        memorySize = 2048;
        cores = 2;
        graphics = false;
        useEFIBoot = true;
      };
    };
  };
}
