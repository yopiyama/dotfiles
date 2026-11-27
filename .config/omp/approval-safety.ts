import { realpathSync } from "node:fs";
import { resolve } from "node:path";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

function sameDirectory(left: string, right: string) {
  try {
    return realpathSync(left) === realpathSync(right);
  } catch {
    return false;
  }
}

export default function approvalSafety(pi: ExtensionAPI) {
  const launchDirectory = process.env.DOTFILES_OMP_PROJECT_POLICY ? process.env.DOTFILES_OMP_WORKSPACE : undefined;
  pi.on("tool_call", (event, ctx) => {
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
