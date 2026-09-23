{ pkgs, ... }:
{
  programs.tmux = {
    enable = true;
    mouse = true;
    keyMode = "emacs"; # コピーモードで矢印キーベースの操作
    clock24 = true;
    historyLimit = 50000;
    baseIndex = 1; # キーボード配置に合わせて1始まりに
    escapeTime = 10;
    terminal = "tmux-256color";

    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank

      # Ctrl-h/j/k/l でエディタとペインを跨いで移動 (Neovim 側も vim-tmux-navigator が要る)。
      # 副作用で root テーブルの Ctrl-l を奪うため画面クリアは prefix+Ctrl-l に移る。
      # プロセス名で判定するため SSH 先のエディタには効かない。
      {
        plugin = vim-tmux-navigator;
        # Ctrl-j は LF (0x0a) そのもので、端末は Shift+Enter も LF で送るため tmux では
        # 区別できず、奪うと Shift+Enter の改行が効かなくなる
        extraConfig = ''
          unbind -n C-j
          set -g @vim_navigator_mapping_down ""
        '';
      }

      # セッション永続化: 手動保存/復元 (prefix + Ctrl-s / prefix + Ctrl-r)
      {
        plugin = resurrect;
        extraConfig = ''
          set -g @resurrect-capture-pane-contents 'on'
          # vim/nvim はセッションファイル併用で開いていたバッファも復元
          set -g @resurrect-strategy-vim 'session'
          set -g @resurrect-strategy-nvim 'session'
        '';
      }

      # 自動保存 + tmux起動時の自動復元 (resurrect の後に読み込むこと)
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '5'
        '';
      }
    ];

    extraConfig = ''
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"

      bind r source-file ~/.config/tmux/tmux.conf \; display-message "設定をリロードしました"

      setw -g pane-base-index 1

      # 拡張キー対応 (Shift+Enter 等の修飾キー付きシーケンスをアプリケーションに転送)
      set -s extended-keys on
      set -as terminal-features 'xterm*:extkeys'

      # 以下は無いと静かに機能が落ちる類の設定

      # フォーカスイベント転送。無いとペイン切り替えを中のアプリが検知できず、
      # 非フォーカス中の外部変更 (Neovim の autoread/git 差分の自動更新) に気づけない
      set -g focus-events on

      # 24bit カラー。端末名パターンで絞ると alacritty 等の独自 TERM が漏れるため全適用
      set -as terminal-features ',*:RGB'

      # 波線・下線色 (LSP の赤い波線表示に必要)。terminal-features 未対応の terminfo 向け
      set -as terminal-overrides ',*:Smulx=\E[4::%p1%dm'
      set -as terminal-overrides ',*:Setulc=\E[58::2::%p1%{65536}%/%d::%p1%{256}%/%{255}%&%d::%p1%{255}%&%d%;m'

      # OSC52 でアプリ側のコピーを tmux が端末 (手元) へ中継する。SSH 先の Neovim での
      # ヤンクが手元のクリップボードに入るのはこれのおかげ
      set -g set-clipboard on
    '';
  };
}
