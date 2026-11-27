import { execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import { closeSync, createReadStream, createWriteStream, lstatSync, openSync, realpathSync, renameSync, rmSync, statSync } from "node:fs";
import { dirname, isAbsolute, join } from "node:path";
import { pipeline } from "node:stream/promises";
import { promisify } from "node:util";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

const exec = promisify(execFile);

export default function commitExtension(pi: ExtensionAPI) {
  const { DOTFILES_OMP_WORKSPACE: workspace, DOTFILES_OMP_GIT: git, DOTFILES_OMP_PROTECTED_PATH: pattern } = process.env;
  if (!workspace || !git || !pattern) throw new Error("The commit extension requires the protected OMP launcher.");
  const protectedPath = new RegExp(pattern);

  pi.registerTool({
    name: "commit",
    label: "Commit Files",
    description: "When the user requests a commit, inspect the diff first, then commit only the listed repository-relative files, including untracked files and deletions. Commits whole files, not hunks. Other staged changes stay staged; paths with both staged and unstaged changes are rejected. Hooks run normally. Do not use eval. No amend, push, directories, or globs.",
    parameters: pi.arktype({ paths: "string[]", subject: "string > 0", "body?": "string", "+": "reject" }),
    approval: "exec",
    loadMode: "essential",
    async execute(_id, { paths, subject, body }, signal, _update, ctx) {
      if (realpathSync(ctx.cwd) !== workspace) throw new Error("Start OMP at the root of this checkout before committing.");
      if (!subject.trim() || /[\r\n\0]/.test(subject) || body?.includes("\0")) {
        throw new Error("Provide a nonempty, single-line subject and an optional separate body.");
      }
      const wanted = new Set(paths);
      if (!wanted.size || wanted.size !== paths.length) throw new Error("List distinct files to commit.");
      for (const path of paths) {
        if (isAbsolute(path) || /[\r\n\0]/.test(path) ||
            path.split("/").some(part => !part || part === "." || part === ".." || part.toLowerCase() === ".git")) {
          throw new Error("Use literal repository-relative file paths.");
        }
        if (protectedPath.test(path)) throw new Error("Protected paths cannot be committed with this tool.");
        const stat = lstatSync(join(workspace, path), { throwIfNoEntry: false });
        if (stat && !stat.isFile() && !stat.isSymbolicLink()) throw new Error(`Not a regular file or symlink: ${path}`);
      }

      const env: NodeJS.ProcessEnv = { ...process.env, GIT_OPTIONAL_LOCKS: "0" };
      for (const key of Object.keys(env)) {
        if (key.startsWith("GIT_") && !/^GIT_(AUTHOR_|COMMITTER_|OPTIONAL_LOCKS$)/.test(key)) delete env[key];
      }
      const runGit = async (args: string[], gitEnv = env) => {
        try {
          return (await exec(git, ["--literal-pathspecs", "-c", "core.splitIndex=false", "-c", "maintenance.auto=false", ...args], {
            cwd: workspace, env: gitEnv, maxBuffer: 16 * 1024 * 1024,
          })).stdout;
        } catch (error) {
          const failure = error as Error & { stdout?: string; stderr?: string };
          throw new Error([failure.stdout, failure.stderr].filter(Boolean).join("\n").trim() || failure.message);
        }
      };
      const top = (await runGit(["rev-parse", "--show-toplevel"])).replace(/\n$/, "");
      if (realpathSync(top) !== workspace) throw new Error("Start OMP at the root of this checkout before committing.");
      const index = (await runGit(["rev-parse", "--path-format=absolute", "--git-path", "index"])).replace(/\n$/, "");
      const lock = `${index}.lock`;
      const temporary = join(dirname(index), `omp-commit-${randomUUID()}.index`);
      signal?.throwIfAborted();
      // Hold Git's real index lock until the private index is ready to publish.
      closeSync(openSync(lock, "wx"));
      let committed: string;
      let indexWarning = "";
      try {
        const privateEnv = { ...env, GIT_INDEX_FILE: temporary, DOTFILES_OMP_SELECTIVE_COMMIT: "1" };
        const indexStat = statSync(index, { throwIfNoEntry: false });
        if (indexStat) {
          // Bun's large-file copy on macOS attempts cloning/ACL writes that Seatbelt can deny.
          await pipeline(createReadStream(index), createWriteStream(temporary, { flags: "wx", mode: indexStat.mode & 0o777 }));
        } else {
          await runGit(["read-tree", "--empty"], privateEnv);
        }

        const status = await runGit(["status", "--porcelain=v1", "-z", "--untracked-files=all", "--no-renames", "--", ...paths], privateEnv);
        const changed = status.split("\0").filter(Boolean);
        const added: string[] = [];
        for (const entry of changed) {
          const path = entry.slice(3);
          if (!wanted.has(path)) throw new Error("Only exact file paths may be committed.");
          const code = entry.slice(0, 2);
          if (code === "??") added.push(path);
          else if (!code.includes(" ")) throw new Error(`Resolve staged and unstaged changes before committing: ${path}`);
        }
        if (changed.length !== paths.length) throw new Error("Each selected file must have a change and not be ignored.");
        if (added.length) await runGit(["add", "--intent-to-add", "--", ...added], privateEnv);

        // Do not interrupt Git between advancing HEAD and publishing the index.
        signal?.throwIfAborted();
        committed = await runGit(["commit", "--only", "-m", subject, ...(body ? ["-m", body] : []), "--", ...paths], privateEnv);
        try {
          renameSync(temporary, index);
        } catch (error) {
          indexWarning = `\nCommit succeeded, but the shared index was not updated: ${error instanceof Error ? error.message : String(error)}`;
        }
      } finally {
        try {
          rmSync(temporary, { force: true });
        } finally {
          rmSync(lock, { force: true });
        }
      }
      return { content: [{ type: "text", text: committed.trimEnd() + indexWarning }], details: { paths } };
    },
  });
}
