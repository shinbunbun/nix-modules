{
  pkgs,
  inputs,
  sharedConfig,
  ...
}:
let
  cfg = sharedConfig;
in
{
  sops.secrets."deploy_ssh_public_key" = {
    sopsFile = "${inputs.self}/${cfg.sops.files.deploy}";
    # /etc/ssh/authorized_keys.d/%u に配置 (SSHd の AuthorizedKeysFile が自動的に読み取る)
    path = "/etc/ssh/authorized_keys.d/${cfg.deploy.user}";
    owner = cfg.deploy.user;
    mode = "0444";
    neededForUsers = true;
  };

  users.users.${cfg.deploy.user} = {
    isNormalUser = true;
    description = "Automated deployment user for CI/CD";
    shell = pkgs.bash;
    extraGroups = [ "wheel" ]; # SSH AllowGroups制限を通過するため
  };

  nix.settings.trusted-users = [ cfg.deploy.user ]; # クロージャ転送のため必要

  security.sudo.extraRules = [
    {
      users = [ cfg.deploy.user ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
