{
  config,
  lib,
  inputs,
  sharedConfig,
  ...
}:
let
  cfg = sharedConfig;
  deployUser = cfg.deploy.user;
in
{
  sops.secrets."deploy_ssh_public_key" = {
    sopsFile = "${inputs.self}/${cfg.sops.files.deploy}";
    mode = "0444";
  };

  # nix-darwin の keyFiles はビルド時にファイルを読むため、SOPS ランタイムパスが使えず
  # activation script で配置する
  system.activationScripts.postActivation.text = lib.mkAfter ''
    if [ -d /Users/${deployUser} ]; then
      mkdir -p /Users/${deployUser}/.ssh
      cp ${config.sops.secrets."deploy_ssh_public_key".path} /Users/${deployUser}/.ssh/authorized_keys
      chown -R ${deployUser}:staff /Users/${deployUser}/.ssh
      chmod 700 /Users/${deployUser}/.ssh
      chmod 600 /Users/${deployUser}/.ssh/authorized_keys

      # ssh-ng:// プロトコルでの nix-daemon 実行時に /etc/zshenv が読まれ、
      # Nix の PATH (/run/current-system/sw/bin 等) が設定されるために必要
      currentShell=$(dscl . -read /Users/${deployUser} UserShell 2>/dev/null | awk '{print $2}')
      if [ "$currentShell" != "/bin/zsh" ]; then
        echo "Setting deploy user shell to /bin/zsh (was: $currentShell)"
        dscl . -create /Users/${deployUser} UserShell /bin/zsh
      fi
    fi
  '';

  nix.settings.trusted-users = [ deployUser ];

  environment.etc."sudoers.d/deploy" = {
    text = "${deployUser} ALL=(ALL) NOPASSWD: ALL";
  };
}
