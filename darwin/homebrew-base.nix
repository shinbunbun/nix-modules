_:

{
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "zap";
      # Homebrew 5.1+ では `brew bundle --cleanup` が --force/--force-cleanup/$HOMEBREW_ASK を必須とするため明示的に付与
      extraFlags = [ "--force-cleanup" ];
    };
  };
}
