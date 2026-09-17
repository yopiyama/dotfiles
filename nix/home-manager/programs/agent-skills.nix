{ ... }:

{
  # Home Manager が個々のスキルだけを ~/.codex/skills/ に symlink するため、
  # Codex 同梱の .system や既存のユーザースキルは置き換えない。
  programs.agent-skills = {
    enable = true;

    sources.mattpocock = {
      input = "mattpocock-skills";
      # Codex の global skills 直下に配置するため、productivity を source root にする。
      subdir = "skills/productivity";
    };

    sources.kepano-obsidian = {
      input = "kepano-obsidian-skills";
      # 配布リポジトリの skills/ 直下に各スキルがある。
      subdir = "skills";
    };

    skills.enable = [
      "grill-me"
      # grill-me は grilling を呼び出す入口なので、単体では機能しない。
      "grilling"

      # Obsidian のデータ形式・記法を扱う宣言的なスキルだけを採用する。
      # 直接 CLI を実行させる obsidian-cli は、既存の安全な obs.sh wrapper と
      # 競合するため有効化しない。
      "obsidian-markdown"
      "obsidian-bases"
      "json-canvas"
    ];

    targets.codex = {
      enable = true;
      # 既存の ~/.codex/skills 全体を同期・置換せず、選択したスキルだけをリンクする。
      structure = "link";
    };
  };
}
