-- プラグインは Nix があらかじめ runtimepath に置いているので、ここでは設定だけを行う。
-- 読み込み順に意味がある: options (leader キー定義を含むので最初) →
-- ui (which-key を先に立ち上げてキーの説明を登録できるようにする) → 他は順不同

require("config.options")
require("config.ui")
require("config.lsp")
require("config.quality")
require("config.diff")
require("config.keymaps")
require("config.cheatsheet")
