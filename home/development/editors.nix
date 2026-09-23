/*
  nixvim ではなく素の Lua 設定を xdg.configFile で配置する。
  upstream のプラグインドキュメントがそのまま通用し、lua_ls + lazydev で
  この設定自身にも補完と型チェックが効く。

  プラグインはランタイム DL の lazy.nvim ではなく nixpkgs で pin する
  (このリポジトリの再現性の方針に合わせる)。

  LSP/linter/formatter は home.packages ではなく extraPackages に入れる。
  Neovim ラッパー内の PATH にだけ入り、シェルの環境を汚さない。
*/
{ pkgs, ... }:
let
  # 実際に扱う言語だけ選ぶ。withAllGrammars は全文法を引き込みクロージャが
  # 跳ね上がるので使わない。
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

    # vim/vi/vimdiff は Neovim を起動する。system 側に vim が残っていても
    # home プロファイルの PATH が優先されるため衝突しない
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;

    defaultEditor = true;

    # 言語プロバイダは無効化 (採用プラグインはいずれも Lua 実装で remote plugin 機構を使わない)。
    # 明示しないと旧既定の true が効き、評価のたびに移行警告が出る
    withNodeJs = false;
    withPython3 = false;
    withRuby = false;

    plugins = with pkgs.vimPlugins; [
      # 差分レビュー (このモジュールの主目的)。upstream sindrets/diffview.nvim は
      # 更新が止まっているため、追従している dlyongemallo フォークを使う
      diffview-plus-nvim
      gitsigns-nvim
      octo-nvim

      # snacks が picker/explorer/lazygit/通知/indent などを1つにまとめる
      # (telescope + fzf-lua + toggleterm ... を個別に入れるより管理対象が減る)
      snacks-nvim
      which-key-nvim
      trouble-nvim
      tokyonight-nvim
      lualine-nvim
      nvim-web-devicons

      # nvim-lspconfig の setup{} 系は非推奨。lsp/<server>.lua の定義だけ借りて
      # vim.lsp.config / vim.lsp.enable で有効化する (詳細は config/lsp.lua)
      nvim-lspconfig
      blink-cmp
      friendly-snippets
      lazydev-nvim

      nvim-lint
      conform-nvim

      treesitter

      # <C-h/j/k/l> が Neovim のウィンドウと tmux のペインを跨いで動く
      vim-tmux-navigator

      plenary-nvim # octo / gitsigns などが依存
      nvim-autopairs
      todo-comments-nvim
    ];

    extraPackages = with pkgs; [
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

      # deadnix は入れていない (nixd 内蔵の nixf と指摘が完全に重複するため)
      statix
      shellcheck
      yamllint
      actionlint
      kubeconform # :KubeCheck から使う

      # rustfmt は入れない (rustc/cargo ごと引き込みクロージャが重い)。
      # 整形は conform → rust-analyzer 経由で PATH 上の rustfmt (devshell 提供) に投げる
      # (プロジェクトのツールチェーンで整形されるのが正しい挙動)
      nixfmt
      stylua
      shfmt
      gofumpt
      hclfmt
      yamlfmt
      jq

      fd # snacks picker のファイル走査
      ripgrep # snacks picker の grep
      git
      gh # octo (GitHub PR) が使う
      lazygit # <Space>gg でフロート表示
    ];

    initLua = ''
      require("config")
    '';
  };

  # ~/.config/nvim/init.lua は home-manager が initLua から生成するので、
  # ここでは lua/ サブツリーだけを渡す
  xdg.configFile."nvim/lua".source = ./nvim/lua;

  # lazygit は Neovim の外からも使うので通常の PATH にも置く
  home.packages = [ pkgs.lazygit ];

  # ワークツリーに cd して `nvd` と打つだけでレビュー画面が開く
  programs.zsh.shellAliases = {
    nvd = "nvim -c ReviewBranch";
  };
}
