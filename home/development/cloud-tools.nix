{ pkgs, ... }:
{
  home.packages = [
    pkgs.google-cloud-sdk
    pkgs.cloudflared
  ];
}
