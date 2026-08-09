/*
  デスクトップ環境設定モジュール

  このモジュールはデスクトップ機向けの GUI 環境を設定します：
  - X Window System設定
  - GNOME デスクトップ環境
  - オーディオ設定（PipeWire。PulseAudio は無効化）
  - OpenGL/グラフィックス設定
  - Docker仮想化
  - nix-ldダイナミックリンカー設定

  GUIアプリケーションやデスクトップ環境に必要な設定を提供します。
*/
{
  config,
  pkgs,
  lib,
  ...
}:
{
  # nix-ld（動的リンカー）は共有モジュールで enable + libraries を設定
  imports = [ ./nix-ld.nix ];

  # X Window System設定
  services.xserver = {
    enable = true;
  };

  # GNOME デスクトップ環境
  services.desktopManager.gnome = {
    enable = true;
  };

  # XDG autostart
  xdg.autostart.enable = true;

  # オーディオ設定 - PipeWireを使用（最新のLinuxではPulseAudioより推奨）
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # グラフィックス設定
  hardware.graphics.enable = true;

  # ファームウェア
  hardware.enableRedistributableFirmware = true;

  # Docker仮想化
  virtualisation.docker.enable = true;

  # Avahiサービス（mDNS）
  services.avahi = {
    enable = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  # デフォルトカーネル（linuxPackages）を使用。
  # out-of-tree カーネルモジュールとの互換のため latest には追随しない。
  boot.kernelPackages = pkgs.linuxPackages;
}
