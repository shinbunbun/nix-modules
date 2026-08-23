-- 基本設定。
-- 方針: VS Code から来た人がいきなり困らないこと (マウス・クリップボード・
-- 保存確認) と、差分レビュー中に画面がガタつかないことを優先する。

-- leader は Space。これだけは他より先に決める必要がある
-- (以降に定義されるキーマップの <leader> がこの値で固定されるため)
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- vim-tmux-navigator に既定のキーマップを作らせない。
-- このプラグインの plugin/ スクリプトは init.lua より後に読まれるため、
-- 放っておくと keymaps.lua で付けた日本語の desc ごと上書きされ、
-- which-key のメニューに出なくなる。
vim.g.tmux_navigator_no_mappings = 1

local o = vim.opt

-- ── 見た目 ──
o.number = true
o.relativenumber = false -- 相対行番号は慣れるまで混乱の元なので使わない
o.cursorline = true
o.signcolumn = "yes" -- 常に出す。診断や git サインの有無で行がズレない
o.wrap = false
o.scrolloff = 6
o.termguicolors = true
o.winborder = "rounded"
o.list = true
o.listchars = { tab = "» ", trail = "·", nbsp = "␣" }

-- 差分表示。linematch は変更行どうしを対応付けて、行内のどこが変わったかを
-- 見せてくれる。レビュー用途では効果が大きい
o.diffopt:append({ "linematch:60", "algorithm:histogram" })
o.fillchars:append({ diff = "╱" })

-- ── VS Code 的な操作性 ──
o.mouse = "a" -- クリック / ドラッグ選択 / ホイールスクロール
o.mousemodel = "popup_setpos" -- 右クリックでメニュー
o.clipboard = "unnamedplus" -- ヤンクが OS のクリップボードに入る
-- SSH 越しの場合は Neovim 0.10+ が $SSH_TTY を見て自動的に OSC 52 を使うので
-- 追加設定は要らない (tmux 側の set-clipboard on が前提。tmux.nix 参照)

-- ── 事故防止 ──
o.confirm = true -- 未保存のまま閉じようとしたら「保存する?」と聞く
o.undofile = true -- Neovim を閉じても undo 履歴が残る
o.swapfile = false -- Claude が同じファイルを触るのでスワップは邪魔
o.autoread = true -- 外部で書き換えられたファイルを読み直す (下の autocmd と対)

-- ── 反応速度 ──
o.updatetime = 200 -- gitsigns の差分表示と診断の更新間隔
o.timeoutlen = 400 -- which-key のメニューが出るまでの待ち時間

-- ── 編集 ──
o.splitright = true
o.splitbelow = true
o.ignorecase = true
o.smartcase = true -- 大文字を含めて検索したときだけ大文字小文字を区別
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.softtabstop = 2
o.inccommand = "split" -- :%s/../../ の結果をプレビュー

-- ── 折りたたみ (treesitter ベース。既定では開いた状態) ──
o.foldmethod = "expr"
o.foldexpr = "v:lua.vim.treesitter.foldexpr()"
o.foldlevel = 99

local aug = vim.api.nvim_create_augroup("UserOptions", { clear = true })

-- Claude がワークツリーのファイルを書き換えたのを拾う。
-- autoread だけでは Neovim が「いつ確認するか」を持たないので checktime を明示的に叩く。
-- tmux 内では tmux 側の focus-events on が無いと FocusGained が届かない (tmux.nix 参照)
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "TermClose", "TermLeave" }, {
  group = aug,
  callback = function()
    if vim.o.buftype == "" and vim.fn.getcmdwintype() == "" then
      pcall(vim.cmd.checktime)
    end
  end,
})

-- ファイルが外部で書き換わったときに黙って読み直したことを知らせる
vim.api.nvim_create_autocmd("FileChangedShellPost", {
  group = aug,
  callback = function() vim.notify("ファイルが外部で変更されたため読み直しました", vim.log.levels.INFO) end,
})

-- ヤンクした範囲を一瞬光らせる (どこをコピーしたか分かる)
vim.api.nvim_create_autocmd("TextYankPost", {
  group = aug,
  callback = function() vim.hl.on_yank({ timeout = 150 }) end,
})

-- treesitter によるハイライトとインデント。
-- nvim-treesitter は master から main へ非互換の全面書き換えが入り、
-- 旧来の setup { highlight = { enable = true } } は動かない。
-- パーサとクエリは Nix が runtimepath に置いているので、
-- Neovim ネイティブの vim.treesitter.start() を呼ぶだけでよい。
vim.api.nvim_create_autocmd("FileType", {
  group = aug,
  callback = function(ev)
    if pcall(vim.treesitter.start, ev.buf) then
      vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
  end,
})

-- 前回閉じたときのカーソル位置に戻る
vim.api.nvim_create_autocmd("BufReadPost", {
  group = aug,
  callback = function(ev)
    local mark = vim.api.nvim_buf_get_mark(ev.buf, '"')
    if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(ev.buf) then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})
