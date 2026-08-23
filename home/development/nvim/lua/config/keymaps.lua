-- キーマップ。
--
-- 方針:
--   1. 覚えるのは <Space> ひとつ。あとは which-key のメニューから辿れる
--   2. VS Code の指がそのまま使えるものは残す (Ctrl-S / Ctrl-Z / Ctrl-C / Ctrl-V)
--   3. ただし vim 本来の操作を潰すマッピングは作らない。
--      たとえば <C-a> (数値インクリメント) や <C-f> (ページ送り) は上書きしない。
--      潰すと、ヘルプやネット上の説明がそのまま通用しなくなる

local map = vim.keymap.set
local diff = require("config.diff")

-- ══ VS Code の指を残す ═══════════════════════════════════════════════════
map({ "n", "i", "v" }, "<C-s>", "<Cmd>silent! write<CR><Esc>", { desc = "保存" })
-- 端末では <C-z> は「Neovim をバックグラウンドに落とす」。初心者が最も驚く挙動なので
-- undo に振り替える (戻したいときは :suspend)
map("n", "<C-z>", "u", { desc = "取り消し (undo)" })
map("i", "<C-z>", "<C-o>u", { desc = "取り消し (undo)" })
map("v", "<C-c>", '"+y', { desc = "コピー" })
map({ "i", "c" }, "<C-v>", "<C-r>+", { desc = "貼り付け" })

-- ══ 基本 ════════════════════════════════════════════════════════════════
-- diffupdate も一緒に呼ぶ。Neovim 既定では <C-l> が
-- nohlsearch + diffupdate + redraw だが、その <C-l> は
-- tmux ペイン移動に使ってしまっている。差分の再計算の手を残しておく。
map("n", "<Esc>", "<Cmd>nohlsearch<CR><Cmd>diffupdate<CR>", { desc = "検索の強調を消す / 差分を再計算" })
map("n", "<leader>w", "<Cmd>write<CR>", { desc = "保存" })
map("n", "<leader>q", "<Cmd>quit<CR>", { desc = "閉じる" })
map("n", "<leader>Q", "<Cmd>qall<CR>", { desc = "Neovim を終了" })

-- 折り返された行でも見た目どおりに上下移動する
map({ "n", "v" }, "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })
map({ "n", "v" }, "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })

-- インデント調整後も選択範囲を保つ
map("v", "<", "<gv", { desc = "インデントを浅く" })
map("v", ">", ">gv", { desc = "インデントを深く" })

-- ══ ウィンドウ / tmux ペイン移動 ═════════════════════════════════════════
-- vim-tmux-navigator により、Neovim のウィンドウの端まで来たら
-- そのまま tmux の隣のペインに移る。境目を意識しなくてよい。
map("n", "<C-h>", "<Cmd>TmuxNavigateLeft<CR>", { desc = "左のウィンドウ/ペイン" })
map("n", "<C-j>", "<Cmd>TmuxNavigateDown<CR>", { desc = "下のウィンドウ/ペイン" })
map("n", "<C-k>", "<Cmd>TmuxNavigateUp<CR>", { desc = "上のウィンドウ/ペイン" })
map("n", "<C-l>", "<Cmd>TmuxNavigateRight<CR>", { desc = "右のウィンドウ/ペイン" })
map("n", "<C-\\>", "<Cmd>TmuxNavigatePrevious<CR>", { desc = "直前のウィンドウ/ペイン" })

-- ══ 探す ════════════════════════════════════════════════════════════════
local Snacks = require("snacks")
map("n", "<leader><leader>", function() Snacks.picker.files() end, { desc = "ファイルを探す" })
map("n", "<leader>/", function() Snacks.picker.grep() end, { desc = "全文検索 (grep)" })
map("n", "<leader>e", function() Snacks.explorer() end, { desc = "ファイラを開く" })
map("n", "<leader>bb", function() Snacks.picker.buffers() end, { desc = "開いているファイル一覧" })
map("n", "<leader>bd", function() Snacks.bufdelete() end, { desc = "このファイルを閉じる" })
map("n", "<leader>bn", "<Cmd>bnext<CR>", { desc = "次のファイル" })
map("n", "<leader>bp", "<Cmd>bprevious<CR>", { desc = "前のファイル" })
-- <S-h> / <S-l> にバッファ切替を置かない。これは H / L
-- (画面の最上行 / 最下行へ移動) と同じキーで、冒頭の方針に反するため。

-- ══ git / 差分レビュー (この設定の主目的) ════════════════════════════════
-- gw が入口。どこで nvim を開いていてもワークツリーを選んでレビューに入れる。
-- 既にワークツリーの中に居るなら gd で直接始めればよい。
map("n", "<leader>gw", diff.pick_worktree, { desc = "ワークツリーを選んでレビュー" })
map("n", "<leader>gd", diff.review_branch, { desc = "ブランチ全体の差分をレビュー" })
map("n", "<leader>gD", "<Cmd>DiffviewOpen<CR>", { desc = "未コミットの差分だけ見る" })
map("n", "<leader>gH", diff.review_commits, { desc = "コミットを 1 つずつレビュー" })
map("n", "<leader>gf", "<Cmd>DiffviewFileHistory %<CR>", { desc = "このファイルの履歴" })
map("n", "<leader>gq", "<Cmd>DiffviewClose<CR>", { desc = "差分ビューを閉じる" })
map("n", "<leader>gb", diff.toggle_gitsigns_base, { desc = "差分の基準を切り替え (HEAD / ベース)" })
map("n", "<leader>gg", function() Snacks.lazygit() end, { desc = "lazygit を開く" })
map("n", "<leader>gs", function() Snacks.picker.git_status() end, { desc = "変更ファイル一覧" })
map("n", "<leader>gl", function() Snacks.picker.git_log() end, { desc = "コミット履歴" })

-- ══ hunk (変更のかたまり) ════════════════════════════════════════════════
-- 差分ビューを開かず、普通に編集しながら変更箇所を辿るときに使う
local gs = require("gitsigns")
map("n", "]h", function() gs.nav_hunk("next") end, { desc = "次の変更箇所" })
map("n", "[h", function() gs.nav_hunk("prev") end, { desc = "前の変更箇所" })
map("n", "<leader>hp", gs.preview_hunk, { desc = "変更内容をその場で見る" })
map("n", "<leader>hs", gs.stage_hunk, { desc = "この変更を stage" })
map("n", "<leader>hr", gs.reset_hunk, { desc = "この変更を捨てる" })
map("n", "<leader>hB", gs.toggle_current_line_blame, { desc = "行ごとの blame 表示" })
map("n", "<leader>hd", gs.diffthis, { desc = "このファイルを縦割りで比較" })

-- ══ コード (LSP) ═════════════════════════════════════════════════════════
-- Neovim 0.11+ には標準で K (ホバー) / grn (リネーム) / gra (コードアクション) /
-- grr (参照) / gri (実装) / gO (シンボル一覧) が入っている。
-- ここではメニューから辿れるように分かりやすい別名を置いているだけ。
map("n", "<leader>cd", vim.lsp.buf.definition, { desc = "定義へジャンプ" })
map("n", "<leader>cr", vim.lsp.buf.rename, { desc = "名前を変更 (= grn)" })
map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, { desc = "修正候補 (= gra)" })
map("n", "<leader>cR", function() Snacks.picker.lsp_references() end, { desc = "参照箇所を探す" })
map("n", "<leader>cs", function() Snacks.picker.lsp_symbols() end, { desc = "シンボル一覧" })
map("n", "<leader>cf", "<Cmd>Format<CR>", { desc = "整形する" })
-- ビジュアルモードは <Cmd> ではなく : を使う。<Cmd> だと選択範囲 ('<,'> ) が
-- コマンドラインに入らず、範囲指定のつもりがファイル全体の整形になる。
map("v", "<leader>cf", ":Format<CR>", { desc = "選択範囲を整形する" })
map("n", "<leader>ck", "<Cmd>KubeCheck<CR>", { desc = "k8s マニフェストを検証" })

-- ══ 診断 ═════════════════════════════════════════════════════════════════
-- ]d / [d (次/前の診断) は Neovim 標準
map("n", "<leader>xx", "<Cmd>Trouble diagnostics toggle filter.buf=0<CR>", { desc = "このファイルの診断" })
map("n", "<leader>xX", "<Cmd>Trouble diagnostics toggle<CR>", { desc = "プロジェクト全体の診断" })
map("n", "<leader>xt", "<Cmd>Trouble todo toggle<CR>", { desc = "TODO / FIXME 一覧" })
map("n", "<leader>xq", "<Cmd>Trouble qflist toggle<CR>", { desc = "quickfix を開く" })
map("n", "<leader>xl", function() require("lint").try_lint() end, { desc = "リンタを今すぐ走らせる" })

-- ══ GitHub (octo) ════════════════════════════════════════════════════════
-- gh CLI の認証を使う。未認証なら `gh auth login` が必要。
map("n", "<leader>op", "<Cmd>Octo pr list<CR>", { desc = "PR 一覧" })
map("n", "<leader>oo", "<Cmd>Octo pr<CR>", { desc = "このブランチの PR を開く" })
map("n", "<leader>or", "<Cmd>Octo review start<CR>", { desc = "レビューを開始" })
map("n", "<leader>os", "<Cmd>Octo review submit<CR>", { desc = "レビューを送信" })
map("n", "<leader>oi", "<Cmd>Octo issue list<CR>", { desc = "Issue 一覧" })

-- ══ トグル ═══════════════════════════════════════════════════════════════
map("n", "<leader>uf", function()
  vim.g.disable_autoformat = not vim.g.disable_autoformat
  vim.notify("保存時の自動整形: " .. (vim.g.disable_autoformat and "OFF" or "ON"))
end, { desc = "保存時の自動整形" })

map("n", "<leader>ud", function()
  local enabled = vim.diagnostic.is_enabled()
  vim.diagnostic.enable(not enabled)
  vim.notify("診断の表示: " .. (enabled and "OFF" or "ON"))
end, { desc = "診断の表示" })

map("n", "<leader>ui", function()
  local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = 0 })
  vim.lsp.inlay_hint.enable(not enabled, { bufnr = 0 })
  vim.notify("インレイヒント: " .. (enabled and "OFF" or "ON"))
end, { desc = "インレイヒント (型の注釈)" })

map("n", "<leader>uw", function() vim.opt_local.wrap = not vim.opt_local.wrap:get() end, { desc = "行の折り返し" })

-- ══ ヘルプ ═══════════════════════════════════════════════════════════════
map("n", "<leader>?", "<Cmd>Cheatsheet<CR>", { desc = "チートシート (基本操作)" })
map("n", "<leader>K", function() require("which-key").show({ global = true }) end, { desc = "キー一覧を出す" })
