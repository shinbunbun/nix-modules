# すべてのモジュールをインポート
{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./monitoring.nix
    ./fluent-bit.nix
  ];
}
