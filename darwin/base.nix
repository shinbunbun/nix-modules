{
  sharedConfig,
  ...
}:

let
  cfg = sharedConfig;
in
{
  system.stateVersion = 5;
  system.primaryUser = cfg.users.darwin.username;

  nix.settings = {
    # Fixed-output derivations (npm依存関係など) をサンドボックスから除外し、
    # DNS解決とネットワークアクセスを通す (macOS 推奨設定)
    sandbox = "relaxed";
    trusted-users = [
      "@admin"
      "_github-runner"
    ];
    allowed-users = [
      "@admin"
      "_github-runner"
    ];

    # Attic バイナリキャッシュ（プライベート）
    substituters = [
      "https://cache.nixos.org"
      "https://${cfg.attic.domain}/main"
    ];

    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      cfg.attic.trustedPublicKey
    ];

    # プライベートキャッシュの認証情報は Darwin では ~/.netrc に手動で置く
  };

  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  environment.systemPath = [ "/opt/homebrew/bin" ];
}
