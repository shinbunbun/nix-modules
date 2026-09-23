{ pkgs, ... }:
{
  # GITHUB_PERSONAL_ACCESS_TOKEN 等のトークンはここで export しない。対話シェルへ
  # export すると全子プロセスが読めてしまうため、MCP 起動経路 (.envrc / .mcp.json) でのみ渡す
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
