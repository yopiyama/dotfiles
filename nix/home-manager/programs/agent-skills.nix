{ inputs, ... }:

{
  home.file = {
    # 自作スキルの本文は Codex 用に置き、検証済みの操作スクリプトは Claude 側と共有する。
    # 同じ obs.sh を複製しないため、修正後は一度の rebuild で両方へ反映される。
    ".codex/skills/obsidian-safe-ops/SKILL.md".source =
      ../../../.codex/skills/obsidian-safe-ops/SKILL.md;
    ".codex/skills/obsidian-safe-ops/scripts/obs.sh" = {
      source = ../../../.claude/skills/connect-obsidian/scripts/obs.sh;
      executable = true;
    };

    ".codex/skills/handoff/SKILL.md".source =
      ../../../.codex/skills/handoff/SKILL.md;
    ".codex/skills/resume-handoff/SKILL.md".source =
      ../../../.codex/skills/resume-handoff/SKILL.md;
    ".codex/skills/pr-comments/SKILL.md".source =
      ../../../.codex/skills/pr-comments/SKILL.md;
    ".codex/skills/pr-comments/scripts/fetch-pr-comments.sh" = {
      source = ../../../.claude/skills/pr-comments/scripts/fetch-pr-comments.sh;
      executable = true;
    };
    ".codex/skills/pr-comments/scripts/pr-task-notes.sh" = {
      source = ../../../.claude/skills/pr-comments/scripts/pr-task-notes.sh;
      executable = true;
    };
    # 指定 gist は root に SKILL.md だけを置くため、agent-skills-nix の
    # ディレクトリ列挙ではなくスキルの配置先へ直接リンクする。
    ".codex/skills/japanese-tech-writing/SKILL.md".source =
      inputs."k16shikano-japanese-tech-writing" + "/SKILL.md";
  };

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
