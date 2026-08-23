-- LSP と補完。
--
-- Neovim 0.11 で vim.lsp.config() / vim.lsp.enable() が入り、
-- nvim-lspconfig の「フレームワーク部分」(require('lspconfig').xxx.setup{}) は非推奨になった。
-- ただしサーバ定義 (lsp/<name>.lua) は現役で、これは nvim-lspconfig が
-- runtimepath に置いてくれる。つまり定義だけ借りて、有効化はネイティブ API で行う。
-- ネット上の記事の多くはまだ古い setup{} 形式なので、真似すると動かない。

-- ── 補完 (blink.cmp) ────────────────────────────────────────────────────
require("blink.cmp").setup({
  keymap = {
    -- 補完中は Tab / S-Tab で選択、Enter で確定。
    -- VS Code に一番近い挙動にしてある。
    preset = "enter",
    ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
    ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
  },
  appearance = { nerd_font_variant = "mono" },
  completion = {
    documentation = { auto_show = true, auto_show_delay_ms = 200 },
    ghost_text = { enabled = false }, -- 差分レビュー中に幻の文字が出ると紛らわしい
  },
  signature = { enabled = true },
  sources = { default = { "lsp", "path", "snippets", "buffer" } },
})

-- ── 診断の見え方 ────────────────────────────────────────────────────────
vim.diagnostic.config({
  severity_sort = true,
  virtual_text = {
    spacing = 2,
    prefix = "●",
    -- 情報レベルまで行末に出すと差分が読めなくなるので警告以上に絞る
    severity = { min = vim.diagnostic.severity.WARN },
  },
  float = { border = "rounded", source = true },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "󰅚 ",
      [vim.diagnostic.severity.WARN] = "󰀪 ",
      [vim.diagnostic.severity.INFO] = "󰋽 ",
      [vim.diagnostic.severity.HINT] = "󰌶 ",
    },
  },
})

-- ── 全サーバ共通の設定 ──────────────────────────────────────────────────
vim.lsp.config("*", {
  capabilities = require("blink.cmp").get_lsp_capabilities(),
})

-- ── サーバごとの設定 ────────────────────────────────────────────────────
vim.lsp.config("nixd", {
  settings = {
    nixd = {
      -- nixpkgs の属性を補完させるための評価式。
      -- NIX_PATH が無い環境では黙って縮退し、基本的な補完だけが残る
      nixpkgs = { expr = "import <nixpkgs> { }" },
      formatting = { command = { "nixfmt" } },
    },
  },
})

vim.lsp.config("lua_ls", {
  settings = {
    Lua = {
      workspace = { checkThirdParty = false },
      -- lazydev が vim.* の定義を読み込めない場面 (この設定ツリーの外にある
      -- 素の Lua ファイルなど) で undefined-global の誤検知を出さないための保険
      diagnostics = { globals = { "vim" } },
      format = { enable = false }, -- 整形は conform (stylua) に一本化
    },
  },
})

vim.lsp.config("yamlls", {
  settings = {
    yaml = {
      -- SchemaStore からスキーマを引く (GitHub Actions / kustomization / ArgoCD など)
      schemaStore = { enable = true, url = "https://www.schemastore.org/api/json/catalog.json" },
      -- これを切らないと「キーの順序が違う」という指摘が大量に出る。
      -- k8s マニフェストでは実害が無いノイズなので落とす
      keyOrdering = false,
      validate = true,
      -- yamlls 自身には整形させない。k8s マニフェストの整形は
      -- conform (yamlfmt) を <Space>cf で明示的に呼んだときだけ行う
      format = { enable = false },
    },
    redhat = { telemetry = { enabled = false } },
  },
})

vim.lsp.config("basedpyright", {
  settings = {
    basedpyright = {
      analysis = {
        -- 既定の recommended は既存コードに対して指摘が多すぎる
        typeCheckingMode = "standard",
        diagnosticMode = "openFilesOnly",
      },
    },
  },
})

vim.lsp.config("ruff", {
  on_attach = function(client)
    -- ホバーは basedpyright に任せる (両方出ると二重表示になる)
    client.server_capabilities.hoverProvider = false
  end,
})

vim.lsp.config("rust_analyzer", {
  -- root_dir を自前で持つ。nvim-lspconfig の既定実装は Rust ツールチェーンが
  -- PATH に居ることを前提にしていて、居ないと .rs を開いた時点で ENOENT が
  -- uncaught で飛び、:edit そのものが失敗する（通知では済まない）:
  --   1. is_library() が `rustc --print sysroot` を起動 (rust_analyzer.lua:46)
  --   2. settings の cargo.sysroot を与えて 1 を迂回しても、今度は root_dir 本体が
  --      `cargo metadata` を起動する (同 :117) ので結局同じところに落ちる
  -- ツールチェーンは常設しない方針（rustfmt を外した理由と同じくクロージャが
  -- 重い）なので、外部コマンドを使わずにルートを決める。
  --
  -- 決め方: Cargo.toml を上へ辿り、[workspace] を宣言している最も近いものを
  -- ワークスペースルートとする。無ければ一番近い Cargo.toml。どちらも無ければ
  -- on_dir を呼ばない = サーバを起動しない。
  -- 「最も近い」であって「最も外側」ではない。入れ子のワークスペース
  -- (外側から exclude された内側のワークスペース) では cargo も内側を採る。
  -- Cargo.lock を目印にしないのは、ライブラリ系では gitignore されるのが慣例で
  -- 未ビルドのクローンには存在せず、メンバごとに別インスタンスが立つため。
  --
  -- 既知の限界 (cargo と食い違うが、いずれも実運用では稀):
  --   - workspace = { members = [...] } / workspace.members = [...] のような
  --     インラインテーブル・ドット記法は取りこぼす
  --   - [ workspace ] のように括弧内に空白があると取りこぼす
  --   - 複数行文字列の中に [workspace] と書かれていると誤検出する
  --   - members / exclude を解釈しないので、exclude されたクレートを
  --     ワークスペースの一部とみなす
  root_dir = function(bufnr, on_dir)
    local name = vim.api.nvim_buf_get_name(bufnr)
    -- vim.fs.dirname("") は "" ではなく "." を返す。無名バッファのまま
    -- カレントディレクトリを探し始めるのを防ぐため、名前の有無で弾く
    if name == "" then
      return
    end

    -- 依存クレート・toolchain・標準ライブラリのソースを開いたときは、既に
    -- 動いている rust_analyzer の root を再利用する。ここで独自に root を
    -- 決めてしまうと、定義ジャンプ (gd) で外部の実装に飛ぶたびにインスタンスが
    -- 増え、それぞれが自分のクレートグラフを索引し直す。
    -- (nvim-lspconfig の is_library 相当。ただし標準ライブラリの場所は
    --  rustc を起動せず、設定値か RUST_SRC_PATH から得る。Nix の devshell は
    --  rustPlatform.rustLibSrc を RUST_SRC_PATH に流すのが定石で、その配下には
    --  [workspace] を持つ Cargo.toml が実在するため、拾わないと下の探索が
    --  std のソースツリーを root にしてしまう)
    local home = vim.fs.normalize(vim.env.HOME or "")
    local cargo_home = vim.env.CARGO_HOME or (home .. "/.cargo")
    local rustup_home = vim.env.RUSTUP_HOME or (home .. "/.rustup")
    local sysroot_src = vim.tbl_get(vim.lsp.config["rust_analyzer"] or {}, "settings", "rust-analyzer", "cargo", "sysrootSrc") or vim.env.RUST_SRC_PATH
    for _, lib in ipairs({
      rustup_home .. "/toolchains",
      cargo_home .. "/registry/src",
      cargo_home .. "/git/checkouts",
      sysroot_src,
    }) do
      -- 空文字列を弾くのが必須。vim.fs.relpath("", name) は "" をカレント
      -- ディレクトリに解決するため、環境変数が「設定済みだが空」だと
      -- cwd 配下の全ファイルがライブラリ扱いになる
      if lib and lib ~= "" and vim.fs.relpath(lib, name) then
        local clients = vim.lsp.get_clients({ name = "rust_analyzer" })
        local root = clients[#clients] and clients[#clients].config.root_dir
        if root then
          on_dir(root)
        end
        -- 既存クライアントが無ければ何もしない。この場合、後からワークスペースを
        -- 開いてもこのバッファには attach されない (再試行は FileType 契機のみ)。
        -- 開き直せば付く。
        return
      end
    end

    local dir = vim.fs.dirname(name)
    local nearest, workspace
    -- upward 検索は近い順に返るので、最初に見つかった [workspace] が最も近い
    for _, toml in ipairs(vim.fs.find("Cargo.toml", { upward = true, path = dir, limit = math.huge })) do
      nearest = nearest or toml
      local ok, lines = pcall(vim.fn.readfile, toml)
      if ok then
        for _, line in ipairs(lines) do
          if line:match("^%s*%[workspace%]") then
            workspace = toml
            break
          end
        end
      end
      if workspace then
        break
      end
    end

    local marker = workspace or nearest
    if marker then
      on_dir(vim.fs.dirname(marker))
      return
    end

    -- Cargo を使わないプロジェクト (buck / bazel 等) 向けのフォールバック。
    -- upstream はこの後さらに .git まで遡るが、そちらは追随しない。
    -- Cargo も rust-project.json も無い場所で rust_analyzer を起動しても
    -- 何も解析できず、警告だけが出るため。
    local project = vim.fs.find("rust-project.json", { upward = true, path = dir })[1]
    if project then
      on_dir(vim.fs.dirname(project))
    end
  end,
  settings = {
    ["rust-analyzer"] = {
      check = { command = "clippy" },
      cargo = { allFeatures = true },
    },
  },
})

vim.lsp.config("gopls", {
  settings = {
    gopls = {
      analyses = { unusedparams = true, shadow = true },
      staticcheck = true,
    },
  },
})

-- ── 有効化 ──────────────────────────────────────────────────────────────
-- 名前は nvim-lspconfig の lsp/<name>.lua に対応する。
-- 該当ファイルタイプを開いたときに初めて起動するので、全部並べても起動は重くならない。
vim.lsp.enable({
  "nixd",
  "lua_ls",
  "rust_analyzer",
  "gopls",
  "basedpyright",
  "ruff",
  "terraformls",
  "tflint",
  "yamlls",
  "jsonls",
  "bashls",
  "taplo",
})

-- ── Lua 設定ファイル自身の開発支援 ──────────────────────────────────────
-- この設定ディレクトリを開いたときに vim.* API の補完と型が効く
require("lazydev").setup({
  library = {
    { path = "${3rd}/luv/library", words = { "vim%.uv" } },
  },
})

-- ── LSP がバッファに付いたときの追加設定 ────────────────────────────────
-- 移動系のキー (grn / gra / grr / gri / K / gO) は Neovim 0.11+ が標準で
-- 用意しているので、ここでは重複定義しない。keymaps.lua に読みやすい別名だけ置く。
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserLspAttach", { clear = true }),
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if not client then
      return
    end

    -- カーソル下のシンボルと同じものを薄く強調する
    if client:supports_method("textDocument/documentHighlight") then
      local hl_group = vim.api.nvim_create_augroup("UserLspHighlight" .. ev.buf, { clear = true })
      vim.api.nvim_create_autocmd({ "CursorHold" }, {
        group = hl_group,
        buffer = ev.buf,
        callback = vim.lsp.buf.document_highlight,
      })
      vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter" }, {
        group = hl_group,
        buffer = ev.buf,
        callback = vim.lsp.buf.clear_references,
      })
    end
  end,
})
