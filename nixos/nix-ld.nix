# nix-ld: NixOS 非対応のビルド済みバイナリ (FHS 前提でリンクされた ELF) を実行可能にする。
# enable だけではライブラリ集合が空に近く、ネイティブ拡張を持つツールが
# libstdc++.so.6 等を解決できず ImportError でクラッシュするため明示する
{
  pkgs,
  ...
}:
{
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
    zlib
  ];
}
