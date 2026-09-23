require("blink.cmp").setup({
  keymap = {
    -- 補完中は Tab / S-Tab で選択、Enter で確定 (VS Code に近い挙動)
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

vim.diagnostic.config({
  severity_sort = true,
  virtual_text = {
    spacing = 2,
    prefix = "●",
    severity = { min = vim.diagnostic.severity.WARN }, -- INFO まで行末に出すと差分が読めない
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

vim.lsp.config("*", {
  capabilities = require("blink.cmp").get_lsp_capabilities(),
})

vim.lsp.config("nixd", {
  settings = {
    nixd = {
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
      -- lazydev が vim.* を読み込めない場面での undefined-global 誤検知を防ぐ保険
      diagnostics = { globals = { "vim" } },
      format = { enable = false }, -- 整形は conform (stylua) に一本化
    },
  },
})

vim.lsp.config("yamlls", {
  settings = {
    yaml = {
      schemaStore = { enable = true, url = "https://www.schemastore.org/api/json/catalog.json" },
      -- キー順序チェックは k8s マニフェストでは実害の無いノイズなので落とす
      keyOrdering = false,
      validate = true,
      format = { enable = false }, -- 整形は conform (yamlfmt) を明示的に呼んだときだけ
    },
    redhat = { telemetry = { enabled = false } },
  },
})

vim.lsp.config("basedpyright", {
  settings = {
    basedpyright = {
      analysis = {
        typeCheckingMode = "standard", -- 既定の recommended は既存コードへの指摘が多すぎる
        diagnosticMode = "openFilesOnly",
      },
    },
  },
})

vim.lsp.config("ruff", {
  on_attach = function(client)
    client.server_capabilities.hoverProvider = false -- basedpyright と二重表示になる
  end,
})

vim.lsp.config("rust_analyzer", {
  -- root_dir を自前で持つ: 既定実装は cargo/rustc が PATH に無いと
  -- :edit が uncaught ENOENT で失敗する。外部コマンドを使わずに求める。
  root_dir = function(bufnr, on_dir)
    local name = vim.api.nvim_buf_get_name(bufnr)
    -- vim.fs.dirname("") は "." を返すため、無名バッファのままカレント
    -- ディレクトリを探し始めるのを名前の有無で弾く
    if name == "" then
      return
    end

    -- 依存クレート・toolchain・標準ライブラリを開いたときは、既存の
    -- rust_analyzer の root を再利用する (無いと gd で飛ぶたびにインスタンスが増える)
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
      -- 空文字列を弾く (vim.fs.relpath("", name) は "" を cwd に解決してしまう)
      if lib and lib ~= "" and vim.fs.relpath(lib, name) then
        local clients = vim.lsp.get_clients({ name = "rust_analyzer" })
        local root = clients[#clients] and clients[#clients].config.root_dir
        if root then
          on_dir(root)
        end
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

    -- 既知の限界: インラインテーブルの workspace.members やドット記法、
    -- 複数行文字列内の [workspace] は正しく解釈できない
    local marker = workspace or nearest
    if marker then
      on_dir(vim.fs.dirname(marker))
      return
    end

    -- Cargo が無いプロジェクト (buck/bazel 等) 向けのフォールバック。
    -- .git まで遡る upstream の挙動は追随しない (何も解析できず警告が出るだけ)
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

-- 該当ファイルタイプを開いたときに初めて起動するので、全部並べても起動は重くならない
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

require("lazydev").setup({
  library = {
    { path = "${3rd}/luv/library", words = { "vim%.uv" } },
  },
})

-- 移動系のキーは Neovim 標準に任せ、ここでは重複定義しない (keymaps.lua に別名のみ置く)
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserLspAttach", { clear = true }),
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if not client then
      return
    end

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
