-- 見た目と、キーを覚えなくても操作できるようにする仕掛け。
--
-- vim のキーバインドは覚える必要が無い、という状態を目指している:
--   - <Space> を押すと which-key がメニューを出す (日本語)
--   - <Space>? で基本操作のチートシート
--   - マウスは全部効く (options.lua)

-- ── 配色 ────────────────────────────────────────────────────────────────
require("tokyonight").setup({
  style = "night",
  styles = { comments = { italic = false } },
  on_highlights = function(hl, c)
    -- 差分レビューが主用途なので、追加/削除/変更の区別を既定より強くする
    hl.DiffAdd = { bg = c.diff.add }
    hl.DiffDelete = { bg = c.diff.delete }
    hl.DiffChange = { bg = c.diff.change }
    hl.DiffText = { bg = c.diff.text, bold = true }
  end,
})
vim.cmd.colorscheme("tokyonight")

-- ── snacks (picker / explorer / lazygit / 通知 など) ────────────────────
-- telescope + fzf-lua + toggleterm + nvim-notify + indent-blankline を
-- 個別に入れる代わりに 1 つで賄う。管理対象のプラグインが減る。
require("snacks").setup({
  bigfile = { enabled = true }, -- 巨大ファイルで構文解析を切って固まらないようにする
  quickfile = { enabled = true },
  input = { enabled = true },
  notifier = { enabled = true, timeout = 3000 },
  indent = { enabled = true },
  statuscolumn = { enabled = true },
  picker = {
    enabled = true,
    layout = { preset = "default" },
  },
  explorer = { enabled = true },
  lazygit = { enabled = true },
  words = { enabled = false }, -- LSP の documentHighlight を使うので不要
  dashboard = { enabled = false },
  scroll = { enabled = false }, -- SSH 越しだとスムーススクロールは重い
})

-- ── ステータスライン ────────────────────────────────────────────────────
require("lualine").setup({
  options = {
    theme = "tokyonight",
    globalstatus = true,
    section_separators = "",
    component_separators = "|",
  },
  sections = {
    lualine_b = { "branch", "diff", "diagnostics" },
    lualine_c = { { "filename", path = 1 } },
    lualine_x = { "filetype" },
  },
  -- quickfix / trouble のウィンドウでは専用の表示に切り替える
  extensions = { "quickfix", "trouble" },
})

-- ── 診断一覧 ────────────────────────────────────────────────────────────
require("trouble").setup({
  focus = true,
  warn_no_results = false,
  open_no_results = true,
})

require("todo-comments").setup({ signs = true })
require("nvim-autopairs").setup({ check_ts = true })

-- ── which-key ───────────────────────────────────────────────────────────
-- キーを押しかけたところでメニューが出る。実質これがキーバインド表。
local wk = require("which-key")
wk.setup({
  preset = "helix",
  delay = function(ctx)
    -- <Space> は即座に、それ以外は少し待ってから
    return ctx.plugin and 0 or 300
  end,
  icons = { mappings = false },
})

-- グループ名は日本語で登録する。<Space> を押したときにここが一覧になる。
wk.add({
  { "<leader>g", group = "git / 差分レビュー" },
  { "<leader>h", group = "hunk (変更のかたまり)" },
  { "<leader>c", group = "コード" },
  { "<leader>x", group = "診断・検索結果" },
  { "<leader>o", group = "GitHub (octo)" },
  { "<leader>u", group = "切り替え (トグル)" },
  { "<leader>b", group = "バッファ" },
})
