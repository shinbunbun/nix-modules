{ sharedConfig, ... }:
let
  cfg = sharedConfig;
in
{
  # fail2ban は ./fail2ban-baseline.nix に分離。SSH 強化と対で import すること
  services.openssh = {
    enable = true;
    ports = [ cfg.ssh.port ];
    settings = {
      X11Forwarding = true;
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      UsePAM = true;

      MaxAuthTries = 3;
      MaxSessions = 10;
      ClientAliveInterval = 1800;
      ClientAliveCountMax = 3;

      LogLevel = "VERBOSE";

      StrictModes = true;
      IgnoreRhosts = true;
      HostbasedAuthentication = false;
      PermitEmptyPasswords = false;
      PermitUserEnvironment = false;
    };

    extraConfig = ''
      AuthorizedKeysFile ${cfg.ssh.authorizedKeysPath}

      AllowGroups wheel

      Banner /etc/ssh/banner

      KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
      Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
      MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
      HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
    '';
  };

  environment.etc."ssh/banner" = {
    text = ''
      ********************************************************************
      *                        WARNING NOTICE                            *
      *                                                                  *
      * This system is for authorized use only. All activities are      *
      * monitored and logged. Unauthorized access is prohibited and     *
      * will be prosecuted to the fullest extent of the law.           *
      ********************************************************************
    '';
    mode = "0644";
  };
}
