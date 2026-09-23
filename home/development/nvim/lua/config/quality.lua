-- LSP の診断はファイル単体でしか分からないため、statix / shellcheck / yamllint /
-- actionlint のような外部リンタを重ねる (extraPackages 経由で Neovim の PATH にのみ入る)
local conform = require("conform")

-- 保存時に自動整形する言語。YAML/Terraform/JSON/Markdown は含めない。
-- 既存ファイルが整形済みとは限らず、1文字の変更が全行差分になって
-- レビュー対象を埋もれさせるため (<Space>cf で手動整形する)
local FORMAT_ON_SAVE = {
  nix = true,
  lua = true,
  sh = true,
  bash = true,
  go = true,
  rust = true,
  python = true,
}

conform.setup({
  formatters_by_ft = {
    nix = { "nixfmt" },
    lua = { "stylua" },
    sh = { "shfmt" },
    bash = { "shfmt" },
    go = { "gofumpt" },
    -- rustfmt は extraPackages に無い。devshell の PATH にあれば使われ、
    -- 無ければ conform が lsp_format=fallback で rust-analyzer に整形を委ねる
    -- (rust-analyzer は範囲指定の整形に非対応、ファイル全体のみ)
    rust = { "rustfmt" },
    python = { "ruff_organize_imports", "ruff_format" },
    terraform = { "hclfmt" },
    hcl = { "hclfmt" },
    yaml = { "yamlfmt" },
    json = { "jq" },
    jsonc = { "jq" },
  },

  format_on_save = function(bufnr)
    -- <Space>uf でグローバルに止められる
    if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
      return nil
    end
    if not FORMAT_ON_SAVE[vim.bo[bufnr].filetype] then
      return nil
    end
    return { timeout_ms = 3000, lsp_format = "fallback" }
  end,
})

local lint = require("lint")

lint.linters_by_ft = {
  -- deadnix は入れない (nixd 内蔵の nixf と同じ指摘が重複する)。
  -- statix は nixd が見ない書き方の問題 (入れ子の let in、余分な括弧など) を拾う
  nix = { "statix" },
  sh = { "shellcheck" },
  bash = { "shellcheck" },
}

-- yamllint の既定ルールは k8s マニフェストではほぼ全行が警告になるため、
-- 実害のあるものだけ残す
lint.linters.yamllint.args = {
  "--format",
  "parsable",
  "-d",
  "{extends: relaxed, rules: {line-length: disable, comments-indentation: disable}}",
  "-",
}

--- このバッファに追加で流すリンタを決める。
--- ファイルタイプだけでは判別できないもの (GitHub Actions と ただの YAML など) を扱う。
---@param bufnr integer
---@return string[]
local function extra_linters(bufnr)
  local ft = vim.bo[bufnr].filetype
  if ft ~= "yaml" then
    return {}
  end

  local path = vim.api.nvim_buf_get_name(bufnr)
  if path:match("%.github/workflows/[^/]+%.ya?ml$") then
    -- actionlint はワークフロー以外に対しては意味のあることを言えない
    return { "actionlint" }
  end
  return { "yamllint" }
end

local lint_group = vim.api.nvim_create_augroup("UserLint", { clear = true })
vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
  group = lint_group,
  callback = function(ev)
    -- 巨大ファイルではリンタの起動コストが体感に出るので打ち切る
    local ok, stat = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(ev.buf))
    if ok and stat and stat.size > 512 * 1024 then
      return
    end
    lint.try_lint()
    local extra = extra_linters(ev.buf)
    if #extra > 0 then
      lint.try_lint(extra)
    end
  end,
})

-- kubeconform は nvim-lint に組み込みが無い。CRD を含むリポジトリでは
-- -ignore-missing-schemas が無いと未知の型で全部落ちるため付ける。
-- 自動実行はノイズになるので明示コマンドにしてある
vim.api.nvim_create_user_command("KubeCheck", function()
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    vim.notify("保存されていないバッファは検証できません", vim.log.levels.WARN)
    return
  end

  local out = vim.fn.systemlist({
    "kubeconform",
    "-strict",
    "-ignore-missing-schemas",
    "-output",
    "text",
    file,
  })

  if vim.v.shell_error == 0 then
    vim.notify("kubeconform: 問題なし", vim.log.levels.INFO)
    return
  end

  -- kubeconform の text 出力は行番号を持たないので、既定の errorformat では
  -- ファイルにすら飛べない。ファイル名だけ自前で埋めて quickfix から開けるようにする
  local items = {}
  for _, line in ipairs(out) do
    if line ~= "" then
      -- lnum = 1 にする (0 だと quickfix の項目が invalid になり行番号欄が空欄になる)
      items[#items + 1] = { filename = file, lnum = 1, text = (line:gsub("^" .. vim.pesc(file) .. "%s*%-%s*", "")) }
    end
  end
  vim.fn.setqflist({}, " ", { title = "kubeconform", items = items })
  vim.cmd("copen")
end, { desc = "現在のファイルを kubeconform で検証する" })

vim.api.nvim_create_user_command("Format", function(args)
  local range = nil
  if args.count ~= -1 then
    local end_line = vim.api.nvim_buf_get_lines(0, args.line2 - 1, args.line2, true)[1]
    range = {
      start = { args.line1, 0 },
      ["end"] = { args.line2, end_line:len() },
    }
  end
  conform.format({ async = true, lsp_format = "fallback", range = range })
end, { range = true, desc = "整形する (範囲指定可)" })
