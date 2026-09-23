_final: prev:
let
  inherit (prev) lib stdenv;
in
lib.optionalAttrs stdenv.hostPlatform.isDarwin {
  # direnv のテストスイートは macOS GitHub-hosted runner 上で確定論的にハングする
  # (ローカル実機では通る)。本番動作に影響しないため checkPhase を丸ごと飛ばす
  direnv = prev.direnv.overrideAttrs (_: {
    doCheck = false;
  });
}
