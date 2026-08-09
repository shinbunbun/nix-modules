{
  description = "Reusable NixOS / nix-darwin / home-manager modules";

  # 意図的に input を持たない。
  # ここが公開するのはモジュールのパスと関数だけで、nixpkgs のバージョンは
  # 利用者が決める。input を持つと利用者の nixpkgs と二重になる。
  inputs = { };

  outputs =
    { self }:
    let
      inherit (builtins)
        readDir
        attrNames
        concatMap
        listToAttrs
        stringLength
        substring
        pathExists
        ;

      # nixpkgs.lib は input が無いので使えない。必要な述語だけ builtins で書く。
      hasNixSuffix = s: stringLength s > 4 && substring (stringLength s - 4) 4 s == ".nix";
      dropNixSuffix = s: substring 0 (stringLength s - 4) s;

      # ディレクトリ以下の .nix を再帰的に集め、パスから属性名を作る。
      #
      #   nixos/base.nix            -> base
      #   nixos/services/argocd.nix -> services-argocd
      #   observability/            -> observability      (default.nix があるので束ねる)
      #
      # 一覧は手書きせず機械的に導出する。モジュールが増減しても編集不要。
      collect =
        dir: prefix:
        let
          entries = readDir dir;
          join = name: if prefix == "" then name else "${prefix}-${name}";
        in
        concatMap (
          name:
          let
            path = dir + "/${name}";
            kind = entries.${name};
          in
          if kind == "directory" then
            if pathExists (path + "/default.nix") then
              [
                {
                  name = join name;
                  value = path;
                }
              ]
            else
              collect path (join name)
          else if kind == "regular" && hasNixSuffix name then
            [
              {
                name = join (dropNixSuffix name);
                value = path;
              }
            ]
          else
            [ ]
        ) (attrNames entries);

      modulesIn = dir: listToAttrs (collect dir "");

      # overlay は module と違って値そのものを渡す必要があるので import して返す。
      overlaysIn =
        dir:
        builtins.mapAttrs (_: path: import path) (modulesIn dir);
    in
    {
      # NixOS モジュール。observability/ は default.nix を持つのでディレクトリごと束ねる。
      nixosModules = modulesIn ./nixos // {
        observability = ./observability;
      };

      # nix-darwin モジュール。
      darwinModules = modulesIn ./darwin;

      # home-manager モジュール。
      homeModules = modulesIn ./home;

      # nixpkgs オーバーレイ (final: prev: 形式)。
      overlays = overlaysIn ./overlays;

      # モジュールではない補助関数。
      # sops-wireguard は { inputs } を取るファクトリなので、import した関数のまま渡す。
      lib = {
        sopsWireguard = import ./lib/sops-wireguard.nix;
      };
    };
}
