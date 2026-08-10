/*
  AIツール設定モジュール

  このモジュールはAI関連のツールを提供します：
  - claude-code: Claudeの公式CLIツール
  - mcp-grafana: Grafana MCPサーバー（Claude CodeからGrafana/Loki/Prometheusへのクエリ実行用）
  - github-mcp-server: GitHub MCPサーバー（Claude CodeからGitHub APIへの直接アクセス用）
  - uv: Python ツールランナー（mcp-server-motherduck を uvx で起動するため）
  - duckdb: DuckDB CLI（S3 互換ストレージ上の Parquet をローカルで確認するため）
  - nodejs: Node.js ランタイム（argoproj-labs/mcp-for-argocd を npx で起動するため）

  トークンはここで配らない:
  - github-mcp-server が要求する GITHUB_PERSONAL_ACCESS_TOKEN を対話シェルへ
    export すると、そのシェルの全子プロセスが環境変数として読める。MCP を
    起動する経路 (プロジェクトの .envrc / .mcp.json の env) でのみ渡す。
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

  home.file.".claude/statusline.sh" = {
    source = ./claude-statusline.sh;
    executable = true;
  };
}
