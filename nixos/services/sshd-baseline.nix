/*
  SSH ベースライン強化モジュール (sshd-baseline)

  このモジュールは OpenSSH サーバーのセキュリティ強化設定のみを提供します。
  複数ホストで共通の SSH 強化
  ベースラインを共有し、KbdInteractiveAuthentication 経由の PAM パスワード
  プロンプト経路を確実に閉じることを目的とします。

  提供する設定:
  - services.openssh
    - enable / ports (shared/config.nix の ssh.port)
    - settings:
      - X11Forwarding = true（X11 転送は有効のまま）
      - PermitRootLogin = "no" / PasswordAuthentication = false
      - KbdInteractiveAuthentication = false（キーボード対話認証を無効化）
      - UsePAM = true
      - 接続制限 (MaxAuthTries / MaxSessions / ClientAlive*)
      - ログ設定 (LogLevel = VERBOSE)
      - その他の堅牢化 (StrictModes / IgnoreRhosts / HostbasedAuthentication /
        PermitEmptyPasswords / PermitUserEnvironment)
    - extraConfig:
      - AuthorizedKeysFile (shared/config.nix の ssh.authorizedKeysPath)
      - AllowGroups wheel（wheel グループのみ SSH アクセス許可）
      - Banner /etc/ssh/banner
      - 強力な暗号スイートのみ (KexAlgorithms / Ciphers / MACs / HostKeyAlgorithms)
  - environment.etc."ssh/banner"（警告バナー）

  含まないもの（意図的に分離）:
  - services.fail2ban
    → ./fail2ban-baseline.nix に分離。SSH 強化と対で使うことを想定しているので、
      本モジュールを import するホストは fail2ban-baseline も併せて import すること。
      （かつては「ホスト独自定義との衝突を避ける」として各ホスト任せにしていたが、
        その独自定義が jail 強度のホスト間差を生んだため方針を反転した）
  - networking.firewall.allowedTCPPorts / Docker
    → これらはホスト固有の要件があるため各ホスト側で定義する

  使用方法:
  ホスト設定の imports に本モジュールを追加するか、flake の nixosModules 経由で利用します。

  値は shared/config.nix を参照して設定します。
*/
{ sharedConfig, ... }:
let
  cfg = sharedConfig;
in
{
  # SSH service with enhanced security
  services.openssh = {
    enable = true;
    ports = [ cfg.ssh.port ];
    settings = {
      # 基本的なセキュリティ設定
      X11Forwarding = true; # X11転送は有効のまま
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false; # キーボード対話認証を無効化
      UsePAM = true;

      # 接続制限
      MaxAuthTries = 3; # 認証試行回数の制限
      MaxSessions = 10; # 最大セッション数
      ClientAliveInterval = 1800; # 30分ごとにクライアントの生存確認
      ClientAliveCountMax = 3; # 3回応答がない場合は切断（合計90分）

      # ログ設定
      LogLevel = "VERBOSE"; # 詳細なログを記録

      # その他のセキュリティ設定
      StrictModes = true; # ファイル権限の厳格なチェック
      IgnoreRhosts = true; # .rhostsファイルを無視
      HostbasedAuthentication = false; # ホストベース認証を無効化
      PermitEmptyPasswords = false; # 空パスワードを禁止
      PermitUserEnvironment = false; # ユーザー環境変数の設定を禁止
    };

    extraConfig = ''
      AuthorizedKeysFile ${cfg.ssh.authorizedKeysPath}

      # 特定のユーザーグループのみSSHアクセスを許可
      AllowGroups wheel

      # バナーメッセージ（オプション）
      Banner /etc/ssh/banner

      # 暗号化アルゴリズムの設定（強力なもののみを使用）
      # 鍵交換アルゴリズム
      KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256

      # 暗号化アルゴリズム
      Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr

      # MACアルゴリズム
      MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com

      # ホスト鍵アルゴリズム
      HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
    '';
  };

  # SSHバナーファイルの作成
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
