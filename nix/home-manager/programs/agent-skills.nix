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

    skills.enable = [
      "grill-me"
      # grill-me は grilling を呼び出す入口なので、単体では機能しない。
      "grilling"
    ];

    targets.codex = {
      enable = true;
      # 既存の ~/.codex/skills 全体を同期・置換せず、選択したスキルだけをリンクする。
      structure = "link";
    };
  };
}
