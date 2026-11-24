import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

// 未知のツール・MCP・LSP・eval は読み取り専用とはみなさない。
const READ_ONLY_TOOLS = new Set(["read", "grep", "glob", "ast_grep", "ls"]);

// シェル全体の解析や OS の隔離ではない。既知の破壊的操作を追加で拒否する。
// 任意コードは main の承認が必要で、ファイル名による秘密保護は secrets.sb が担当する。
const DESTRUCTIVE_COMMANDS = [
  /\b(?:rm|rmdir|unlink|shred|mkfs|newfs)\b/,
  /\bgit\b[^;&|\n]*\b(?:reset|clean)\b[^;&|\n]*(?:--hard|--merge|--force|\s-[a-zA-Z]*f)/,
  /\bgit\b[^;&|\n]*\bpush\b[^;&|\n]*(?:--force|--mirror|--delete|\s-[a-zA-Z]*[fd])(?:\b|=)/,
  /\bgit\b[^;&|\n]*\bpush\b[^;&|\n]*\s(?:\+[^\s;&|]+|:[^\s;&|]+)/,
  /\bgit\b[^;&|\n]*\b(?:restore|checkout)\b[^;&|\n]*(?:\s--\s|--force|\s-f\b)/,
  /\bgit\b[^;&|\n]*\brestore\b/,
  /\bgit\b[^;&|\n]*\bbranch\b[^;&|\n]*\s-D\b/,
  /\b(?:sudo|diskutil|dd)\b/,
];

export default function safety(pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    // task は子を yolo で起動するため、承認を表示できない実行主体には変更させない。
    // Advisor と /tan の子にも適用する。主セッションで必要な操作を承認して実行する。
    if ((ctx.agent?.kind !== "main" || !ctx.hasUI) && !READ_ONLY_TOOLS.has(event.toolName)) {
      return {
        block: true,
        reason: "Safety: subagents and non-interactive sessions are read-only; perform changes in the interactive main session.",
      };
    }
    if (event.toolName === "delete") {
      return { block: true, reason: "Safety: file deletion must be performed manually outside OMP." };
    }
    if (event.toolName === "bash") {
      const command = event.input.command;
      if (typeof command !== "string") {
        return { block: true, reason: "Safety: missing bash command." };
      }
      if (DESTRUCTIVE_COMMANDS.some(pattern => pattern.test(command))) {
        return { block: true, reason: "Safety: destructive shell command blocked; perform it manually outside OMP." };
      }
    }
    return undefined;
  });
}
