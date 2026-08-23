/*
  エディタ設定モジュール (Neovim)

  用途は「Claude がワークツリーで作った差分を、LSP と静的解析を効かせたまま
  レビューし、その場で直す」こと。この 1 点に構成を寄せている。固有値を
  持たないため全ホスト共通で使う。

  ■ なぜ nixvim ではなく素の Lua か
    設定を Lua ファイルとして持ち、xdg.configFile 経由で配置する。
    こうすると各プラグインの upstream ドキュメントがそのまま通用し、
    lua_ls + lazydev.nvim でこの設定自身にも補完と型チェックが効く。
    nixvim は Nix DSL への翻訳層が挟まるぶん、詰まったときに調べられなくなる。

  ■ なぜ lazy.nvim ではないか
    プラグインを実行時にダウンロードすることになり、このリポジトリの
    再現性の方針と衝突する。プラグインは nixpkgs で pin する。

  ■ LSP / linter / formatter の置き場所
    home.packages ではなく programs.neovim.extraPackages に入れる。
    Neovim のラッパー内の PATH にだけ入るので、シェルの環境を汚さない。
*/
{ pkgs, ... }:
let
  # 実際に扱う言語だけ選ぶ。withAllGrammars は約 300 文法を引き込んで
  # クロージャが跳ね上がるので使わない。
  treesitter = pkgs.vimPlugins.nvim-treesitter.withPlugins (
    p: with p; [
      bash
      c
      diff
      dockerfile
      git_config
      git_rebase
      gitattributes
      gitcommit
      gitignore
      go
      gomod
      gosum
      hcl
      json # jsonc は独立した文法を持たず json パーサが担当する
      lua
      luadoc
      make
      markdown
      markdown_inline
      nix
      python
      query
      regex
      rust
      sql
      terraform
      toml
      vim
      vimdoc
      xml
      yaml
    ]
  );
in
{
  programs.neovim = {
    enable = true;

    # vim / vi / vimdiff と打ったら Neovim が起動する。
    # 旧 programs.vim (vim 9.2 + vim-airline) のモジュールは削除済みなので衝突しない。
    # public/nixos/base.nix の systemPackages には pkgs.vim が残っているが、
    # そちらは system プロファイル側で、PATH は home プロファイルが先に来る
    # (レスキュー時に root で vim が使える状態は残しておきたいので消さない)。
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;

    # EDITOR / VISUAL を nvim にする。git の core.editor も別の設定で
    # 同じく nvim に切り替えている。
    defaultEditor = true;

    # 言語プロバイダは全て無効。ここで採用しているプラグインは
    # いずれも Lua 実装で、remote plugin 機構を使わない。
    # 明示しないと home.stateVersion < 26.05 の場合に旧既定の true が効いて
    # ruby/python の環境がクロージャに入り、評価のたびに移行警告が出る
    # (現状の全ホストが該当する)。
    withNodeJs = false;
    withPython3 = false;
    withRuby = false;

    plugins = with pkgs.vimPlugins; [
      # ── 差分レビュー (このモジュールの主目的) ──
      # 本家 sindrets/diffview.nvim は 2024-08 以降更新が止まっており、
      # nixpkgs の diffview-nvim も 2024-06 で固まっている。
      # dlyongemallo のフォークが実質の後継で、こちらは追従している。
      diffview-plus-nvim
      gitsigns-nvim
      octo-nvim

      # ── UI / 検索 ──
      # snacks は picker / explorer / lazygit / 通知 / indent などを 1 つに
      # まとめている。telescope + fzf-lua + toggleterm + ... を個別に
      # 入れるより管理対象が減る。
      snacks-nvim
      which-key-nvim
      trouble-nvim
      tokyonight-nvim
      lualine-nvim
      nvim-web-devicons

      # ── LSP / 補完 ──
      # nvim-lspconfig は Neovim 0.11 で framework 部分が非推奨になったが、
      # lsp/<server>.lua のサーバ定義は現役。定義だけ借りて
      # vim.lsp.config / vim.lsp.enable (0.11+ ネイティブ) で有効化する。
      nvim-lspconfig
      blink-cmp
      friendly-snippets
      lazydev-nvim

      # ── 静的解析 / 整形 ──
      nvim-lint
      conform-nvim

      # ── 構文 ──
      treesitter

      # ── tmux 連携 ──
      # <C-h/j/k/l> が Neovim のウィンドウと tmux のペインを跨いで動く
      vim-tmux-navigator

      # ── その他 ──
      plenary-nvim # octo / gitsigns などが依存
      nvim-autopairs
      todo-comments-nvim
    ];

    extraPackages = with pkgs; [
      # ── 言語サーバ ──
      nixd
      rust-analyzer
      gopls
      basedpyright
      ruff
      terraform-ls
      tflint
      yaml-language-server
      lua-language-server
      bash-language-server
      taplo
      vscode-langservers-extracted # jsonls など

      # ── リンタ (LSP が出さないもの) ──
      # deadnix は入れていない。nixd 内蔵の nixf と指摘が完全に重複するため
      # (詳細は nvim/lua/config/quality.lua のコメント)。
      statix
      shellcheck
      yamllint
      actionlint
      kubeconform # :KubeCheck から使う

      # ── フォーマッタ ──
      # rustfmt は入れない。pkgs.rustfmt はクロージャが 1.7 GiB あり
      # (rustc と cargo を参照する)、全ホストに載せると
      # ディスクを圧迫する。rust-analyzer 単体なら 170 MiB で済む。
      # Rust の整形は conform の lsp_format = "fallback" 経由で
      # rust-analyzer に投げる。rust-analyzer はシェルの PATH にある
      # rustfmt を呼ぶので、プロジェクトの devshell のツールチェーンが
      # 使われる (整形結果はツールチェーンのバージョンに依存するため、
      # むしろこちらが正しい)。
      nixfmt
      stylua
      shfmt
      gofumpt
      hclfmt
      yamlfmt
      jq

      # ── 補助 ──
      fd # snacks picker のファイル走査
      ripgrep # snacks picker の grep
      git
      gh # octo (GitHub PR) が使う
      lazygit # <Space>gg でフロート表示
    ];

    # 実体は xdg.configFile で配置した Lua を読むだけ
    initLua = ''
      require("config")
    '';
  };

  # Lua 設定本体。~/.config/nvim/lua -> このディレクトリ。
  # ~/.config/nvim/init.lua は home-manager が initLua から生成するので
  # ここでは lua/ サブツリーだけを渡す。
  xdg.configFile."nvim/lua".source = ./nvim/lua;

  # lazygit は Neovim の外からも使うので通常の PATH にも置く
  home.packages = [ pkgs.lazygit ];

  # ワークツリーに cd して `nvd` と打つだけでレビュー画面が開く。
  # ReviewBranch はベースブランチを自動判定する (nvim/lua/config/diff.lua)。
  programs.zsh.shellAliases = {
    nvd = "nvim -c ReviewBranch";
  };
}
