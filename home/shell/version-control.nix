{ sharedConfig, ... }:
let
  cfg = sharedConfig;
in
{
  programs.git = {
    enable = true;

    settings = {
      user = {
        name = cfg.git.userName;
        email = cfg.git.userEmail;
      };
      core.editor = cfg.git.coreEditor;
    };
  };
}
