{
  pkgs,
  ...
}:
{
  environment.systemPackages = [
    pkgs.polkit
    pkgs.wireguard-tools
    pkgs.jq
    pkgs.openssl
    pkgs.python3
    pkgs.gnumake
  ];
}
