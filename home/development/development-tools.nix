{ pkgs, ... }:
{
  home.packages =
    with pkgs;
    [
      pnpm
      kubectl-cnpg
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      cocoapods
    ];
}
