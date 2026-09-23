{
  config,
  lib,
  ...
}:
{
  options.nixpkgs.unfreeAllowlist.packages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "nvidia-x11" ];
    description = ''
      unfree として許可する `lib.getName` の値。定義は複数モジュールから連結される。
      ここに無い unfree 派生が closure に入ると eval が失敗する。
    '';
  };

  config.nixpkgs.config.allowUnfreePredicate =
    pkg: builtins.elem (lib.getName pkg) config.nixpkgs.unfreeAllowlist.packages;
}
