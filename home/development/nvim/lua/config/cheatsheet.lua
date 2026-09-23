-- which-key は「<Space> から始まるキー」しか教えてくれないので、
-- vim そのものの基本操作 (モード / 移動 / 編集) はここで補う。
-- プラグインに依存させず、素の API だけで作ってある。

local LINES = {
  "  Neovim チートシート                          q または <Esc> で閉じる",
  "",
  "── まずこれだけ ──────────────────────────────────────────────────────",
  "  <Space>            メニューを出す (以降はメニューを見ながらでよい)",
  "  <Space>gw          ワークツリーを選んでレビューする    ← ここから始める",
  "                     (選ぶとそのタブだけ移動する。戻すときは :tcd -)",
  "  <Space>gd          今いる場所の差分をレビューする",
  "  <Space>gg          lazygit を開く",
  "  <Space><Space>     ファイルを探す",
  "  <Space>/           全文検索",
  "  Ctrl-s             保存        Ctrl-z  取り消し",
  "",
  "── モード ────────────────────────────────────────────────────────────",
  "  i                  入力モードに入る (カーソルの手前から)",
  "  a                  入力モードに入る (カーソルの後ろから)",
  "  o                  下に空行を作って入力モード",
  "  <Esc>              入力モードを抜ける (困ったらとりあえずこれ)",
  "  v                  範囲選択      V  行単位で選択",
  "  :                  コマンド入力  (:w 保存 / :q 閉じる / :q! 保存せず閉じる)",
  "",
  "── 移動 ──────────────────────────────────────────────────────────────",
  "  h j k l            左 下 上 右   (矢印キー・マウスも使える)",
  "  w / b              次 / 前の単語へ",
  "  0 / $              行頭 / 行末へ",
  "  gg / G             ファイルの先頭 / 末尾へ",
  "  Ctrl-d / Ctrl-u    半画面 下 / 上",
  "  {数字}G            その行番号へ  (例: 120G)",
  "  Ctrl-o / Ctrl-i    直前にいた場所へ戻る / 進む",
  "",
  "── 編集 ──────────────────────────────────────────────────────────────",
  "  x                  1 文字削除     dd  1 行削除",
  "  yy                 1 行コピー     p   貼り付け",
  "  u                  取り消し       Ctrl-r  やり直し",
  "  ciw                カーソル下の単語を消して入力モード",
  "  .                  直前の変更を繰り返す",
  "",
  "── 検索 ──────────────────────────────────────────────────────────────",
  "  /文字列            前方検索  (n 次へ / N 前へ)",
  "  *                  カーソル下の単語を検索",
  "  :%s/前/後/g        ファイル全体を置換 (入力中に結果がプレビューされる)",
  "",
  "── 差分ビューの中 (<Space>gd のあと) ─────────────────────────────────",
  "  Tab / Shift-Tab    次 / 前のファイル",
  "  ]c / [c            次 / 前の変更箇所",
  "  Ctrl-h / Ctrl-l    左 / 右のウィンドウへ (一覧と差分ペインの移動もこれ)",
  "  <Space>gp          ファイル一覧と差分ペインを行き来する",
  "  右ペインは実ファイル。そのまま編集して Ctrl-s で保存できる",
  "  <Space>uw          長い行の折り返しを切り替える (左右まとめて)",
  "  <Esc>              差分を再計算する（編集後にズレたと感じたら）",
  "  g?                 差分ビュー専用のキー一覧",
  "  <Space>gq          差分ビューを閉じる",
  "",
  "── 困ったら ──────────────────────────────────────────────────────────",
  "  <Esc> を数回        たいていのモードから抜けられる",
  "  :q!                 保存せずに閉じる",
  "  :checkhealth        LSP やプラグインの状態を診断",
  "  :Trouble diagnostics  診断の一覧",
}

local function open()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, LINES)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "cheatsheet"

  local width = math.min(78, vim.o.columns - 4)
  local height = math.min(#LINES, vim.o.lines - 6)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " チートシート ",
    title_pos = "center",
  })
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = false

  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end, { buffer = buf, nowait = true })
  end
end

vim.api.nvim_create_user_command("Cheatsheet", open, { desc = "基本操作のチートシート" })
