# macOS の SMB マルチチャネル実装はシングル NIC サーバーに対して
# smb2_mc_update_main_channel / smb_iod_start_reconnect エラーを起こす。
# サーバー側で無効化してもクライアントは定期的にインターフェーススキャンを試行するため、
# クライアント側 (nsmb.conf) でも無効化する
_: {
  environment.etc."nsmb.conf" = {
    text = ''
      [default]
      mc_on=no
    '';
  };
}
