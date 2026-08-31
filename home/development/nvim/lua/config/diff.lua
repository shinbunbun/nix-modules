-- 差分レビュー。この設定の主目的。
--
-- 想定する流れ:
--   1. どこで nvim を開いていても <Space>gw でワークツリーを選ぶ
--      (Claude のワークツリーは scratchpad 配下の深いパスにあり cd が現実的でないため。
--       既にワークツリーの中に居るなら <Space>gd で直接始めてよい)
--   2. 左 = ベースブランチ / 右 = 実ファイル で差分を眺める
--   3. 気になる所はその場で直す (右ペインは実ファイルなので LSP も編集も効く)
--
-- ■ --imply-local が要
--   `:DiffviewOpen main...HEAD` は既定だと左右とも git のオブジェクトを読み出した
--   read-only バッファになり、LSP が刺さらず編集もできない。--imply-local を付けると
--   右ペインがワークツリーの実ファイルになり、診断・定義ジャンプ・保存が全部通る。
--   要件の「LSP や静的解析も効いてほしい」「自分で編集もできるように」は
--   まるごとこのフラグに乗っている。default_args で常に付ける。

local M = {}

--- git コマンドを走らせて stdout の行リストを返す。失敗時は nil。
--- vim.fn.systemlist ではなく vim.system を使うのは、前者が stderr を
--- stdout に混ぜてしまうため。exit 0 で警告だけ吐く git (壊れた ref など) に
--- 当たると警告文が結果として返り、判定を誤る。
---@param args string[]
---@return string[]|nil
local function git(args)
  -- 発行するのは rev-parse / worktree list / config だけでネットワークも
  -- 対話プロンプトも無いが、万一固まったときに nvim ごと止まらないよう時間を切る。
  local res = vim.system(vim.list_extend({ "git" }, args), { text = true }):wait(5000)
  if res.code ~= 0 then
    return nil
  end
  return vim.split(res.stdout or "", "\n", { trimempty = true })
end

--- レビューの基準にするリビジョンを求める。
--- origin/HEAD が張られていればそれを使い、無ければ順に候補を試す。
--- (git clone 直後や CI の checkout では origin/HEAD が無いことが珍しくない)
---@return string
function M.base_ref()
  local head = git({ "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD" })
  if head and head[1] and head[1] ~= "" then
    return head[1]
  end
  for _, candidate in ipairs({ "origin/main", "origin/master", "main", "master" }) do
    if git({ "rev-parse", "--verify", "--quiet", candidate }) then
      return candidate
    end
  end
  return "HEAD"
end

-- ── diffview ────────────────────────────────────────────────────────────
local actions = require("diffview.actions")

require("diffview").setup({
  -- 変更行の中の「実際に変わった部分」だけを強調する。
  -- これが無いと行まるごとが同じ色になり、1 文字の変更を見落とす
  enhanced_diff_hl = true,

  view = {
    default = { layout = "diff2_horizontal", winbar_info = true },
    -- コンフリクト解決時は 3 ペイン (自分の変更 / ベース / 相手の変更)
    merge_tool = { layout = "diff3_mixed", disable_diagnostics = false },
    file_history = { layout = "diff2_horizontal", winbar_info = true },
  },

  file_panel = {
    listing_style = "tree",
    win_config = { position = "left", width = 38 },
  },

  -- 右ペインを実ファイルにする。詳細はこのファイル冒頭のコメント
  default_args = {
    DiffviewOpen = { "--imply-local" },
    DiffviewFileHistory = { "--imply-local" },
  },

  hooks = {
    -- 折り返すと左右の行が縦に揃わなくなるが、差分では「見えない」より
    -- 「ずれる」を採る。<leader>uw で左右まとめて戻せる。
    diff_buf_win_enter = function(_, winid, _)
      vim.wo[winid].wrap = true
      vim.wo[winid].linebreak = true
      vim.wo[winid].breakindent = true
    end,
  },

  keymaps = {
    -- view は差分の左右ペインそのもの。右ペインは編集可能な実ファイルなので、
    -- ここに q を割り当てない。マクロ記録 (q) が使えなくなるうえ、
    -- 編集中の誤爆でレビューごと閉じてしまう。閉じるのは <leader>gq に統一する。
    view = {
      { "n", "<Tab>", actions.select_next_entry, { desc = "次のファイル" } },
      { "n", "<S-Tab>", actions.select_prev_entry, { desc = "前のファイル" } },
      { "n", "<leader>gp", actions.focus_files, { desc = "ファイル一覧へ移動" } },
      { "n", "<leader>gq", "<Cmd>DiffviewClose<CR>", { desc = "差分ビューを閉じる" } },
      -- 既定の <leader>uw は今のウィンドウしか変えない。差分は左右揃っていないと
      -- 読めないので、差分ビューの中では両ペインまとめて切り替える方を優先する
      { "n", "<leader>uw", function() M.toggle_wrap() end, { desc = "折り返し (左右まとめて)" } },
      { "n", "g?", actions.help("view"), { desc = "キー一覧" } },
    },
    file_panel = {
      { "n", "<Tab>", actions.select_next_entry, { desc = "次のファイル" } },
      { "n", "<S-Tab>", actions.select_prev_entry, { desc = "前のファイル" } },
      -- <cr> は既定のまま (開くだけでカーソルは一覧に残る)。
      -- 一覧を上から順に見ていく間にカーソルが飛ぶと戻ってくるのが面倒なので、
      -- ペインへ移るのは <C-l> か下の <leader>gp と、明示的に叩いたときだけにする
      { "n", "<leader>gp", actions.focus_entry, { desc = "差分ペインへ移動" } },
      { "n", "q", "<Cmd>DiffviewClose<CR>", { desc = "差分ビューを閉じる" } },
      { "n", "<leader>gq", "<Cmd>DiffviewClose<CR>", { desc = "差分ビューを閉じる" } },
      { "n", "g?", actions.help("file_panel"), { desc = "キー一覧" } },
    },
    file_history_panel = {
      { "n", "<leader>gp", actions.focus_entry, { desc = "差分ペインへ移動" } },
      { "n", "q", "<Cmd>DiffviewClose<CR>", { desc = "差分ビューを閉じる" } },
      { "n", "g?", actions.help("file_history_panel"), { desc = "キー一覧" } },
    },
  },
})

--- 差分ペインの折り返しをまとめて切り替える。
--- 片側だけ折り返すと左右の行がまったく対応しなくなるので、
--- 今のタブの diff ウィンドウを全部同じ状態にする。
function M.toggle_wrap()
  local wins = vim.tbl_filter(function(win) return vim.wo[win].diff end, vim.api.nvim_tabpage_list_wins(0))
  if #wins == 0 then
    wins = { vim.api.nvim_get_current_win() }
  end
  local enable = not vim.wo[wins[1]].wrap
  for _, win in ipairs(wins) do
    vim.wo[win].wrap = enable
  end
  vim.notify("行の折り返し: " .. (enable and "ON" or "OFF"))
end

--- ブランチ全体 (ベースとの共通祖先から現在のワークツリーまで) をレビューする。
--- コミット済みの変更と未コミットの変更の両方が 1 画面に出る。
function M.review_branch()
  local base = M.base_ref()
  if base == "HEAD" then
    vim.notify("ベースブランチが見つからないため未コミット分のみ表示します", vim.log.levels.WARN)
    vim.cmd("DiffviewOpen")
    return
  end
  -- --imply-local は default_args から入る。ここで重ねて渡さないのは、
  -- 主経路が default_args の設定を実際に通ることを保証するため。
  vim.cmd(("DiffviewOpen %s...HEAD"):format(base))
end

--- ブランチのコミットを 1 つずつ辿ってレビューする。
--- --right-only でベース側のコミットを除き、--no-merges でマージコミットを畳む。
function M.review_commits()
  local base = M.base_ref()
  if base == "HEAD" then
    vim.notify("ベースブランチが見つかりません", vim.log.levels.WARN)
    return
  end
  vim.cmd(("DiffviewFileHistory --range=%s...HEAD --right-only --no-merges"):format(base))
end

-- ── ワークツリー選択 ────────────────────────────────────────────────────
-- Claude が切るワークツリーは scratchpad 配下の深いパスにあるため、
-- レビューのたびに cd するのは現実的でない。親リポジトリと全 submodule の
-- ワークツリーを一覧して、選んだら移動 + レビュー開始まで一気に行う。

--- 末尾のスラッシュを落とす。git の出力と自前で組んだパスを突き合わせるとき、
--- 片方だけに / が付いていると不一致になるため。
--- vim.fs.normalize は使わない (既定で $VAR を展開するので、パスに $ を含む
--- リポジトリを壊す)。--path-format=absolute の出力は既に正規形。
---@param path string
---@return string
local function strip_slash(path) return (path:gsub("(.)/+$", "%1")) end

--- 探索の起点になる親リポジトリ (superproject) を求める。
--- cwd がどこにあるかで取り方が変わる。公開しているのは検証しやすくするため。
---@return string|nil
function M.workspace_root()
  -- ① submodule の *チェックアウト* 内 (親リポジトリ配下に submodule を持つ構成)
  local super = git({ "rev-parse", "--show-superproject-working-tree" })
  if super and super[1] and super[1] ~= "" then
    return super[1]
  end

  -- ② ワークツリーの中にいる場合。そこは元の作業ツリーの外にあるので ① は空を返す。
  --    共有 gitdir の形から、どのリポジトリのワークツリーかを判別する。
  --      submodule のワークツリー  : <親>/.git/modules/<name>
  --      親リポジトリのワークツリー: <親>/.git
  --    後者を拾わないと、ワークツリー自身が起点になって submodule が
  --    1 つも出てこない (この機能の主目的が消える)。
  local common = git({ "rev-parse", "--path-format=absolute", "--git-common-dir" })
  if common and common[1] and common[1] ~= "" then
    local dir = strip_slash(common[1])
    local root = dir:match("^(.*)/%.git/modules/")
    if root then
      return root
    end
    if vim.fn.fnamemodify(dir, ":t") == ".git" then
      return vim.fn.fnamemodify(dir, ":h")
    end
  end

  -- ③ 素のリポジトリ (親リポジトリ自身など)
  local top = git({ "rev-parse", "--show-toplevel" })
  if top and top[1] and top[1] ~= "" then
    return top[1]
  end
  return nil
end

--- `git worktree list --porcelain` の出力を解析する。
---@param lines string[]
---@return { path: string, branch: string|nil }[]
local function parse_worktrees(lines)
  local out, cur = {}, nil
  for _, line in ipairs(lines) do
    local path = line:match("^worktree (.+)$")
    if path then
      cur = { path = path }
      out[#out + 1] = cur
    elseif cur then
      local branch = line:match("^branch refs/heads/(.+)$")
      if branch then
        cur.branch = branch
      end
    end
  end
  return out
end

--- 親リポジトリと全 submodule のワークツリーを集める。公開しているのは検証しやすくするため。
---@param root string
---@return { repo: string, branch: string, path: string }[]
function M.collect_worktrees(root)
  local items = {}

  ---@param dir string 走査する作業ツリー
  ---@param label string 一覧に出すリポジトリ名
  local function add(dir, label)
    -- toplevel と共有 gitdir を 1 プロセスで取る。
    -- 未初期化の submodule ディレクトリでは git が上位リポジトリまで遡るため、
    -- `worktree list` が「親リポジトリのワークツリー一覧」を返してしまう。
    -- そのまま採ると submodule 名のラベルで別リポジトリへ連れて行かれるので、
    -- toplevel が自分自身であることを確かめてから採用する。
    local info = git({ "-C", dir, "rev-parse", "--path-format=absolute", "--show-toplevel", "--git-common-dir" })
    if not info or #info < 2 then
      return
    end
    local top, gitdir = strip_slash(info[1]), strip_slash(info[2])
    if top ~= strip_slash(dir) then
      return
    end

    local lines = git({ "-C", dir, "worktree", "list", "--porcelain" })
    if not lines then
      return
    end

    for _, wt in ipairs(parse_worktrees(lines)) do
      local path = wt.path
      -- submodule の主ワークツリーは実チェックアウトではなく共有 gitdir として
      -- 報告される。そのまま開くと中身の無いディレクトリに移動してしまうので
      -- 読み替える。前方一致ではなく gitdir の実値と突き合わせるのは、
      -- 入れ子 submodule だと <親>/.git/modules/<外>/modules/<内> になり
      -- 前方一致では判定を誤るため。
      -- (通常のリポジトリでは gitdir は <top>/.git なので一致せず素通りする)
      if path == gitdir then
        path = top
      end
      if vim.fn.isdirectory(path) == 1 then
        items[#items + 1] = { repo = label, branch = wt.branch or "(detached)", path = path }
      end
    end
  end

  add(root, vim.fn.fnamemodify(root, ":t"))

  -- submodule のパスは .gitmodules から 1 プロセスで取る
  -- (git submodule foreach は submodule ごとにプロセスを起こすので遅い)
  local conf = git({ "-C", root, "config", "--file", root .. "/.gitmodules", "--get-regexp", "submodule\\..*\\.path" })
  for _, line in ipairs(conf or {}) do
    local sub = line:match("^%S+%s+(.+)$")
    if sub then
      local dir = root .. "/" .. sub
      add(dir, sub)
    end
  end

  -- Claude が切ったブランチを上に出す。main / master は下。
  local function rank(it) return (it.branch == "main" or it.branch == "master") and 1 or 0 end
  table.sort(items, function(a, b)
    if rank(a) ~= rank(b) then
      return rank(a) < rank(b)
    end
    if a.repo ~= b.repo then
      return a.repo < b.repo
    end
    return a.branch < b.branch
  end)
  return items
end

--- ワークツリーを選んで移動し、そのままレビューを開始する。
function M.pick_worktree()
  local root = M.workspace_root()
  if not root then
    vim.notify(
      "git リポジトリの外にいるためワークツリーを列挙できません。\n"
        .. "リポジトリに cd してから開き直すか :tcd <リポジトリ> してください",
      vim.log.levels.WARN
    )
    return
  end

  local items = M.collect_worktrees(root)
  if #items == 0 then
    vim.notify("ワークツリーが見つかりません: " .. root, vim.log.levels.WARN)
    return
  end

  -- 列を揃える。ブランチ名は長くなりうるので上限を設けて
  -- パスが右へ押し出されすぎないようにする。
  local repo_w, branch_w = 0, 0
  for _, it in ipairs(items) do
    repo_w = math.max(repo_w, vim.fn.strdisplaywidth(it.repo))
    branch_w = math.max(branch_w, vim.fn.strdisplaywidth(it.branch))
  end
  branch_w = math.min(branch_w, 30)

  --- 表示幅を want に合わせる。溢れる場合は切り詰めて列崩れを防ぐ。
  ---@param text string
  ---@param want integer
  ---@return string
  local function fit(text, want)
    local w = vim.fn.strdisplaywidth(text)
    if w > want then
      -- … の 1 桁と、隣の列との間隔 1 桁を確保する
      while w > want - 2 and #text > 0 do
        text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text) - 1)
        w = vim.fn.strdisplaywidth(text)
      end
      return text .. "…" .. string.rep(" ", math.max(1, want - w - 1))
    end
    return text .. string.rep(" ", want - w)
  end

  require("snacks").picker.pick({
    title = "ワークツリー",
    finder = function()
      local finder_items = {}
      for _, it in ipairs(items) do
        finder_items[#finder_items + 1] = {
          -- text は絞り込みの対象。リポジトリ名・ブランチ名に加えて
          -- ワークツリーのディレクトリ名でも引けるようにする
          -- (Claude はディレクトリ名を機能名で付けるので手掛かりになる)
          text = table.concat({ it.repo, it.branch, vim.fn.fnamemodify(it.path, ":t") }, " "),
          repo = it.repo,
          branch = it.branch,
          dir = it.path,
        }
      end
      return finder_items
    end,
    format = function(item)
      return {
        { fit(item.repo, repo_w + 1), "SnacksPickerDirectory" },
        { fit(item.branch, branch_w + 1), "SnacksPickerGitBranch" },
        -- パスは補助情報なので pathshorten で圧縮して 1 行に収める
        -- (末尾のワークツリー名だけは残るので判別できる)
        { vim.fn.pathshorten(vim.fn.fnamemodify(item.dir, ":~")), "SnacksPickerComment" },
      }
    end,
    -- ワークツリーはパスとブランチが分かれば十分でプレビューする中身が無い。
    -- preview = "none" だけでは枠が残るので layout 側で窓ごと落とす。
    preview = "none",
    layout = { preset = "dropdown", preview = false },
    confirm = function(picker, item)
      picker:close()
      if not item then
        return
      end
      -- tcd (タブローカル) を使う。グローバル cd と違い他のタブを巻き込まず、
      -- DiffviewOpen が開く新しいタブには継承される (実測で確認)。
      -- 元のディレクトリに戻したくなったら :tcd - でよい。
      --
      -- vim.cmd.tcd(path) ではなく明示形なのは、:tcd が EX_XFILE で
      -- パス中の % / # をファイル名として展開してしまい E499/E194 で
      -- 落ちるため。magic を切ると % / # と空白は実パスのまま通る。
      --
      -- 既知の制約: パスに $ が含まれると :tcd が環境変数として展開し E344 になる。
      -- magic も fnameescape もこれは止められない (vim.fn.chdir でも同じ)。
      -- 止められるのは vim.uv.chdir だけだが、あちらはプロセス全体の cwd を
      -- 変えるのでタブローカルでなくなる。ディレクトリ名に $ を含む
      -- リポジトリは実運用に無いと判断して受容する。
      vim.cmd({ cmd = "tcd", args = { item.dir }, magic = { file = false } })
      M.review_branch()
    end,
  })
end

-- ── gitsigns ────────────────────────────────────────────────────────────
-- diffview が「差分を見る」モードなのに対し、gitsigns は
-- 「普通に編集しながら、どこが変わったかを常に横目で見る」モード。
require("gitsigns").setup({
  signcolumn = true,
  numhl = false,
  current_line_blame = false, -- <Space>hB でトグル
  preview_config = { border = "rounded" },
  -- 差分の再計算間隔。options.lua の updatetime と揃えている
  update_debounce = 200,
})

--- gitsigns の比較対象を「直前のコミット」と「ベースブランチ」で切り替える。
--- ベースブランチにすると、編集画面のサインがそのままブランチ全体の差分になる。
local base_mode = false
function M.toggle_gitsigns_base()
  local gs = require("gitsigns")
  if base_mode then
    gs.change_base(nil, true)
    base_mode = false
    vim.notify("差分の基準: 直前のコミット (HEAD)")
  else
    local base = M.base_ref()
    gs.change_base(base, true)
    base_mode = true
    vim.notify("差分の基準: " .. base)
  end
end

-- ── octo (GitHub の PR を Neovim から扱う) ──────────────────────────────
-- gh CLI の認証を使う。未認証だとコマンド実行時にエラーになるだけで、
-- 起動そのものには影響しない。
require("octo").setup({
  picker = "snacks",
  suppress_missing_scope = { projects_v2 = true },
})

-- ── ユーザーコマンド ────────────────────────────────────────────────────
vim.api.nvim_create_user_command("ReviewBranch", M.review_branch, {
  desc = "ベースブランチとの差分をレビューする",
})
vim.api.nvim_create_user_command("ReviewCommits", M.review_commits, {
  desc = "ブランチのコミットを 1 つずつレビューする",
})
vim.api.nvim_create_user_command("ReviewWorktree", M.pick_worktree, {
  desc = "ワークツリーを選んで移動しレビューする",
})

return M
