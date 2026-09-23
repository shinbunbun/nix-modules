{
  pkgs,
  config,
  sharedConfig,
  ...
}:
let
  cfg = sharedConfig;
in
{
  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";
    enableCompletion = true;
    autosuggestion.enable = true;
    plugins = [
      {
        name = "zsh-completions";
        src = pkgs.zsh-completions.src;
      }
      {
        name = "nix-zsh-completions";
        src = pkgs.nix-zsh-completions.src;
      }
    ];
  };

  programs.lsd = {
    enable = true;
  };

  programs.starship = {
    enable = true;
    settings = {
      status = {
        disabled = false;
      };
      time = {
        disabled = false;
        utc_time_offset = cfg.system.utcOffset;
        time_format = "%Y-%m-%d %H:%M";
      };
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableBashIntegration = true;
  };
}
