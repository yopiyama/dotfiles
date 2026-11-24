import { realpathSync } from "node:fs";
import { resolve } from "node:path";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

function isScoutOnly(input: Record<string, unknown>) {
  const batch = input.tasks === undefined ? [input] : input.tasks;
  return Array.isArray(batch) && batch.length > 0 && batch.every(item =>
    item && typeof item === "object" && item.agent === "scout" &&
    !item.isolated && item.tools === undefined && item.model === undefined);
}

function sameDirectory(left: string, right: string) {
  try {
    return realpathSync(left) === realpathSync(right);
  } catch {
    return false;
  }
}

export default function approvalSafety(pi: ExtensionAPI) {
  const launchDirectory = process.env.DOTFILES_OMP_PROJECT_POLICY ? process.env.DOTFILES_OMP_WORKSPACE : undefined;
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName === "task" && !isScoutOnly(event.input)) {
      if (!ctx.hasUI || !await ctx.ui.confirm(
        "Allow subagent delegation?",
        JSON.stringify(event.input, null, 2).slice(0, 2500),
      )) {
        return { block: true, reason: "Safety: subagent delegation was not approved." };
      }
    }
    // Native Bash patterns resolve against the session, not Bash's optional cwd.
    if (launchDirectory && event.toolName === "bash") {
      const cwd = event.input.cwd;
      if (!sameDirectory(ctx.cwd, launchDirectory) ||
          (typeof cwd === "string" && !sameDirectory(resolve(ctx.cwd, cwd), launchDirectory))) {
        return {
          block: true,
          reason: "Safety: with a local project policy, use the launch directory as Bash cwd. Use an explicit cd in a reviewed command for other directories.",
        };
      }
    }
  });
}
