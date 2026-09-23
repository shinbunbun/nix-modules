{
  pkgs,
  ...
}:
{
  # nix-ld（動的リンカー）は共有モジュールで enable + libraries を設定
  imports = [ ./nix-ld.nix ];

  services.xserver = {
    enable = true;
  };

  services.desktopManager.gnome = {
    enable = true;
  };

  xdg.autostart.enable = true;

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  hardware.graphics.enable = true;

  hardware.enableRedistributableFirmware = true;

  virtualisation.docker.enable = true;

  services.avahi = {
    enable = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  # デフォルトカーネル (linuxPackages) を使用。
  # out-of-tree カーネルモジュールとの互換のため latest には追随しない
  boot.kernelPackages = pkgs.linuxPackages;
}
