import { lstatSync, realpathSync, renameSync, rmSync } from "node:fs";
import { basename, dirname, isAbsolute, join, relative, resolve } from "node:path";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { editInspect } from "@oh-my-pi/pi-natives";

function below(root: string, target: string) {
  const part = relative(root, target);
  return part !== "" && part !== ".." && !part.startsWith("../") && !isAbsolute(part);
}

type FileChange = { operation: "delete" | "move"; path: string; destination?: string; recursive?: boolean };

export default function workspaceSafety(pi: ExtensionAPI) {
  const root = process.env.DOTFILES_OMP_WORKSPACE;
  const userTemp = process.env.TMPDIR;
  if (!root || !userTemp) throw new Error("Start OMP using the protected dotfiles launcher.");
  const workspace = root;
  const tempRoots = [realpathSync("/tmp"), realpathSync(userTemp)];

  function target(input: string) {
    if (!input) throw new Error("A literal filesystem path is required.");
    const path = resolve(workspace, input);
    // /tmp と /var は macOS の標準エイリアス。それ以外の symlink 経由は許可しない。
    const literal = path.startsWith("/tmp/") || path.startsWith("/var/") ? `/private${path}` : path;
    const actual = join(realpathSync(dirname(literal)), basename(literal));
    const temp = tempRoots.some(root => below(root, actual));
    if (actual !== literal || actual === workspace || below(actual, workspace) ||
        tempRoots.includes(actual) || (!temp && !below(workspace, actual))) {
      throw new Error(`Path is outside the allowed scope or is a protected root: ${JSON.stringify(input)}`);
    }
    const entry = lstatSync(actual, { throwIfNoEntry: false });
    if (entry?.isSymbolicLink()) throw new Error(`Symbolic links are not accepted: ${JSON.stringify(input)}`);
    return { path: actual, temp, entry };
  }

  function plan(args: FileChange) {
    const source = target(args.path);
    if (!source.entry) throw new Error(`Path does not exist: ${JSON.stringify(source.path)}`);
    const destination = args.operation === "move" ? target(args.destination ?? "") : undefined;
    if (destination?.entry) throw new Error(`Move would overwrite ${JSON.stringify(destination.path)}`);
    return { source, destination, temp: source.temp && (!destination || destination.temp) };
  }

  pi.registerTool({
    name: "file_change",
    label: "Delete or move a path",
    description: "Delete one path or move it to a new path without overwriting. Paths are literal and relative to the launch directory. Set recursive only for directory deletion. Temporary paths under /tmp or $TMPDIR require no approval; workspace paths require confirmation.",
    parameters: pi.zod.object({
      operation: pi.zod.enum(["delete", "move"]),
      path: pi.zod.string(),
      destination: pi.zod.string().optional(),
      recursive: pi.zod.boolean().optional(),
    }),
    concurrency: "exclusive",
    approval(args) {
      try {
        return { tier: "write", policy: plan(args as FileChange).temp ? "allow" : "prompt" };
      } catch (error) {
        return { tier: "write", policy: "deny", reason: String(error) };
      }
    },
    formatApprovalDetails(args) {
      const { source, destination } = plan(args as FileChange);
      if (destination) return `Move: ${JSON.stringify(source.path)} → ${JSON.stringify(destination.path)}`;
      return `Delete${(args as FileChange).recursive ? " recursively" : ""}: ${JSON.stringify(source.path)}`;
    },
    async execute(_id, args, signal) {
      signal?.throwIfAborted();
      const { source, destination } = plan(args);
      if (destination) renameSync(source.path, destination.path);
      else rmSync(source.path, { recursive: args.recursive === true });
      const text = destination
        ? `Moved ${JSON.stringify(source.path)} to ${JSON.stringify(destination.path)}`
        : `Deleted ${JSON.stringify(source.path)}`;
      return { content: [{ type: "text", text }], details: {} };
    },
  });

  pi.on("tool_call", event => {
    if (event.toolName !== "edit" && event.toolName !== "apply_patch") return;
    const input = event.input;
    const modes = typeof input.input === "string" ? ["hashline", "apply_patch", "sloppy"]
      : Array.isArray(input.edits) ? ["patch"] : [];
    if (modes.length === 0) return;
    const json = JSON.stringify(input);
    if (modes.some(mode => editInspect(mode, json).fileOps.length > 0)) {
      return { block: true, reason: "Safety: use file_change for whole-file deletion or moves; edit is for content changes." };
    }
  });
}
