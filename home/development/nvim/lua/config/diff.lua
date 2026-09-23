local M = {}

--- git コマンドを走らせて stdout の行リストを返す。失敗時は nil。
--- stderr を混ぜてしまう vim.fn.systemlist ではなく vim.system を使う。
---@param args string[]
---@return string[]|nil
local function git(args)
  -- 固まったときに nvim ごと止まらないよう5秒で打ち切る
  local res = vim.system(vim.list_extend({ "git" }, args), { text = true }):wait(5000)
  if res.code ~= 0 then
    return nil
  end
  return vim.split(res.stdout or "", "\n", { trimempty = true })
end

--- レビューの基準にするリビジョンを求める。
--- origin/HEAD が無ければ候補を順に試す (clone 直後は張られていないことがある)。
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

local actions = require("diffview.actions")

require("diffview").setup({
  enhanced_diff_hl = true,

  view = {
    default = { layout = "diff2_horizontal", winbar_info = true },
    merge_tool = { layout = "diff3_mixed", disable_diagnostics = false },
    file_history = { layout = "diff2_horizontal", winbar_info = true },
  },

  file_panel = {
    listing_style = "tree",
    win_config = { position = "left", width = 38 },
  },

  -- 既定だと左右とも read-only バッファになり LSP も編集も効かない。
  -- --imply-local で右ペインをワークツリーの実ファイルにする。
  default_args = {
    DiffviewOpen = { "--imply-local" },
    DiffviewFileHistory = { "--imply-local" },
  },

  hooks = {
    -- 折り返すと左右の行が揃わなくなるが、差分では「見えない」より
    -- 「ずれる」を採る。<leader>uw で左右まとめて戻せる。
    diff_buf_win_enter = function(_, winid, _)
      vim.wo[winid].wrap = true
      vim.wo[winid].linebreak = true
      vim.wo[winid].breakindent = true
    end,
  },

  keymaps = {
    view = {
      { "n", "<Tab>", actions.select_next_entry, { desc = "次のファイル" } },
      { "n", "<S-Tab>", actions.select_prev_entry, { desc = "前のファイル" } },
      { "n", "<leader>gp", actions.focus_files, { desc = "ファイル一覧へ移動" } },
      { "n", "<leader>gq", "<Cmd>DiffviewClose<CR>", { desc = "差分ビューを閉じる" } },
      -- 右ペインは編集可能な実ファイルなので q は割り当てない
      -- (マクロ記録の q と衝突し、編集中の誤爆で閉じてしまう)
      { "n", "<leader>uw", function() M.toggle_wrap() end, { desc = "折り返し (左右まとめて)" } },
      { "n", "g?", actions.help("view"), { desc = "キー一覧" } },
    },
    file_panel = {
      { "n", "<Tab>", actions.select_next_entry, { desc = "次のファイル" } },
      { "n", "<S-Tab>", actions.select_prev_entry, { desc = "前のファイル" } },
      -- <cr> は既定のまま (開くだけでカーソルは一覧に残る)
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
--- 片側だけ折り返すと左右の行が対応しなくなるため、今のタブの diff ウィンドウを揃える。
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
function M.review_branch()
  local base = M.base_ref()
  if base == "HEAD" then
    vim.notify("ベースブランチが見つからないため未コミット分のみ表示します", vim.log.levels.WARN)
    vim.cmd("DiffviewOpen")
    return
  end
  -- --imply-local は default_args から入るのでここでは重ねない
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

--- 末尾のスラッシュを落とす。git の出力と自前で組んだパスを突き合わせるとき、
--- 片方だけ / が付いていると不一致になるため。
---@param path string
---@return string
local function strip_slash(path) return (path:gsub("(.)/+$", "%1")) end

--- 探索の起点になる親リポジトリ (superproject) を求める。cwd の位置で取り方が変わる。
---@return string|nil
function M.workspace_root()
  local super = git({ "rev-parse", "--show-superproject-working-tree" })
  if super and super[1] and super[1] ~= "" then
    return super[1]
  end

  -- ワークツリー内では superproject が空を返すため、共有 gitdir のパス形
  -- (<親>/.git/modules/<name> か <親>/.git) からどのリポジトリのワークツリーか判別する
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

--- 親リポジトリと全 submodule のワークツリーを集める。
---@param root string
---@return { repo: string, branch: string, path: string }[]
function M.collect_worktrees(root)
  local items = {}

  ---@param dir string 走査する作業ツリー
  ---@param label string 一覧に出すリポジトリ名
  local function add(dir, label)
    -- 未初期化の submodule では git が上位リポジトリまで遡ってしまうため、
    -- toplevel が dir 自身と一致することを確かめてから採用する
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
      -- 報告されるため、gitdir の実値と突き合わせて実パスに読み替える
      -- (前方一致だと入れ子 submodule で誤判定する)
      if path == gitdir then
        path = top
      end
      if vim.fn.isdirectory(path) == 1 then
        items[#items + 1] = { repo = label, branch = wt.branch or "(detached)", path = path }
      end
    end
  end

  add(root, vim.fn.fnamemodify(root, ":t"))

  -- submodule ごとにプロセスを起こす git submodule foreach を避け、.gitmodules を直読みする
  local conf = git({ "-C", root, "config", "--file", root .. "/.gitmodules", "--get-regexp", "submodule\\..*\\.path" })
  for _, line in ipairs(conf or {}) do
    local sub = line:match("^%S+%s+(.+)$")
    if sub then
      local dir = root .. "/" .. sub
      add(dir, sub)
    end
  end

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
        { vim.fn.pathshorten(vim.fn.fnamemodify(item.dir, ":~")), "SnacksPickerComment" },
      }
    end,
    preview = "none",
    layout = { preset = "dropdown", preview = false },
    confirm = function(picker, item)
      picker:close()
      if not item then
        return
      end
      -- タブローカルな :tcd を使う。明示形なのは % / # をファイル名展開させないため
      -- (vim.cmd.tcd(path) だと E499/E194 で落ちる)
      vim.cmd({ cmd = "tcd", args = { item.dir }, magic = { file = false } })
      M.review_branch()
    end,
  })
end

require("gitsigns").setup({
  signcolumn = true,
  numhl = false,
  current_line_blame = false,
  preview_config = { border = "rounded" },
  update_debounce = 200,
})

--- gitsigns の比較対象を「直前のコミット」と「ベースブランチ」で切り替える。
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

require("octo").setup({
  picker = "snacks",
  suppress_missing_scope = { projects_v2 = true },
})

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
