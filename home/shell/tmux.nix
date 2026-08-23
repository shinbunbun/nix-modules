/*
  tmux設定モジュール

  ターミナルマルチプレクサtmuxの設定を提供します：
  - マウス操作対応（ペイン選択・リサイズ・スクロール）
  - 直感的なキーバインド（| で縦分割、- で横分割）
  - システムクリップボード連携（tmux-yank）
  - 基本設定の改善（tmux-sensible）
  - 拡張キー対応（Shift+Enter等の修飾キー付きシーケンスをアプリケーションに転送）
  - 端末アプリ連携（focus-events / 24bitカラー / 波線 / OSC52 クリップボード）
    ※ いずれも欠けていても tmux は動くが、中で動かすエディタの機能が静かに落ちる
  - ペイン移動の統合（vim-tmux-navigator: Ctrl-h/k/l がエディタのウィンドウも跨ぐ）
  - セッションの永続化（tmux-resurrect + tmux-continuum）
    - マシン再起動をまたいでセッション（ペイン構成・作業ディレクトリ・実行プロセス）を復元
    - continuumが5分ごとに自動保存し、tmux起動時に自動復元する
    - 保存データは ~/.local/share/tmux/resurrect/ に保持される

  使い方:
    tmux           - 新しいセッションを開始
    tmux attach    - 既存セッションに接続
    prefix + |     - 縦分割
    prefix + -     - 横分割
    prefix + r     - 設定リロード
    prefix + Ctrl-s - セッションを手動保存（resurrect）
    prefix + Ctrl-r - セッションを手動復元（resurrect）
*/
{ pkgs, ... }:
{
  programs.tmux = {
    enable = true;

    # マウスでペイン選択・リサイズ・スクロール可能
    mouse = true;

    # コピーモードで矢印キーベースの操作
    keyMode = "emacs";

    # 24時間表示
    clock24 = true;

    # スクロールバック行数
    historyLimit = 50000;

    # ウィンドウ/ペイン番号を1始まりに（キーボード配置に合わせる）
    baseIndex = 1;

    # Escキーの遅延を短縮（ms）
    escapeTime = 10;

    # 256色対応
    terminal = "tmux-256color";

    # プラグイン
    plugins = with pkgs.tmuxPlugins; [
      sensible # 基本的なデフォルト設定の改善
      yank # システムクリップボードへのコピー対応

      # Ctrl-h/k/l でエディタ（Neovim側もvim-tmux-navigator要）とペインを跨いで移動。
      # 副作用でrootテーブルのCtrl-lを奪うため画面クリアはprefix+Ctrl-lに移る。
      # プロセス名で判定するため、SSH先のエディタには効かない（tmuxからはsshにしか見えず、
      # その場合ペイン移動はtmux側で処理されキーがエディタに届かない）。
      {
        plugin = vim-tmux-navigator;
        # Ctrl-jはLF(0x0a)そのもので、端末はShift+EnterもLFで送るためtmuxでは区別できず、
        # 奪うとShift+Enterの改行が効かなくなる。unbindも既存バインドを消すために必要。
        extraConfig = ''
          unbind -n C-j
          set -g @vim_navigator_mapping_down ""
        '';
      }

      # セッション永続化: 手動保存/復元（prefix + Ctrl-s / prefix + Ctrl-r）
      {
        plugin = resurrect;
        extraConfig = ''
          # ペインの表示内容も保存/復元する
          set -g @resurrect-capture-pane-contents 'on'
          # vim/nvimはセッションファイル併用で開いていたバッファも復元
          set -g @resurrect-strategy-vim 'session'
          set -g @resurrect-strategy-nvim 'session'
        '';
      }

      # 自動保存 + tmux起動時の自動復元（resurrectの後に読み込むこと）
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on' # tmux起動時に前回のセッションを自動復元
          set -g @continuum-save-interval '5' # 5分ごとに自動保存
        '';
      }
    ];

    # 追加キーバインド
    extraConfig = ''
      # 直感的なペイン分割
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"

      # 設定リロード
      bind r source-file ~/.config/tmux/tmux.conf \; display-message "設定をリロードしました"

      # ペイン番号も1始まりに
      setw -g pane-base-index 1

      # 拡張キー対応（Shift+Enter等の修飾キー付きシーケンスをアプリケーションに転送）
      set -s extended-keys on
      set -as terminal-features 'xterm*:extkeys'

      # Neovim等を tmux 内でも素で動かすための設定。無いと静かに機能が落ちる類のもの。

      # フォーカスイベント転送。無いとペイン切り替えを中のアプリが検知できず、
      # 非フォーカス中の外部変更（Neovimのautoread/git差分の自動更新）に気づけない。
      set -g focus-events on

      # 24bitカラー。端末名パターンで絞るとalacritty等の独自TERMが漏れるため全適用
      # （linux/dumbのような非対応端末にも宣言することになるが実害は出ていない）。
      set -as terminal-features ',*:RGB'

      # 波線・下線色（LSPの赤い波線表示に必要）。terminal-features未対応のterminfo向け。
      set -as terminal-overrides ',*:Smulx=\E[4::%p1%dm'
      set -as terminal-overrides ',*:Setulc=\E[58::2::%p1%{65536}%/%d::%p1%{256}%/%{255}%&%d::%p1%{255}%&%d%;m'

      # OSC52でアプリ側のコピーをtmuxが端末（手元）へ中継する。SSH先のNeovimでの
      # ヤンクが手元のクリップボードに入るのはこれのおかげ。
      set -g set-clipboard on
    '';
  };
}
