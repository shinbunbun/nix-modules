# nix-modules

NixOS / nix-darwin / home-manager 向けの再利用可能なモジュール集。

## 使い方

```nix
inputs.nix-modules.url = "github:shinbunbun/nix-modules";
```

出力は `nixosModules` / `darwinModules` / `homeModules` / `overlays` / `lib`。属性名はパスから
導出され、区切りは `-` になります (`nixos/services/argocd.nix` → `nixosModules.services-argocd`)。
一覧は `nix flake show` で確認できます。

モジュールは設定値を持たず、固有値は `specialArgs` の `sharedConfig` から受け取ります。
また sops-nix を使うモジュールは、利用者の flake に `secrets/*.yaml` が同名で存在することを
前提にしています。

## ライセンス

MIT
