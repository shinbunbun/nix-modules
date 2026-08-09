/*
  AIツール設定モジュール

  このモジュールはAI関連のツールを提供します：
  - claude-code: Claudeの公式CLIツール
  - mcp-grafana: Grafana MCPサーバー（Claude CodeからGrafana/Loki/Prometheusへのクエリ実行用）
  - github-mcp-server: GitHub MCPサーバー（Claude CodeからGitHub APIへの直接アクセス用）
  - uv: Python ツールランナー（mcp-server-motherduck を uvx で起動するため）
  - duckdb: DuckDB CLI（S3 互換ストレージ上の Parquet をローカルで確認するため）
  - nodejs: Node.js ランタイム（argoproj-labs/mcp-for-argocd を npx で起動するため）
*/
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    claude-code
    mcp-grafana
    github-mcp-server
    uv
    duckdb
    nodejs_22
  ];

  programs.zsh.initExtra = ''
    if command -v gh &>/dev/null; then
      export GITHUB_PERSONAL_ACCESS_TOKEN="$(gh auth token 2>/dev/null)"
    fi
  '';

  home.file.".claude/statusline.sh" = {
    source = ./claude-statusline.sh;
    executable = true;
  };
}
