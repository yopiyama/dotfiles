import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { closeSync, mkdirSync, mkdtempSync, openSync, realpathSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import commitExtension from "./commit.ts";

// 本番ランチャーと同じ Bun、Seatbelt、Git を使い、モデル呼び出し前に終了する。
export default async function checkCommit(pi) {
  const cwd = process.cwd();
  const common = join(cwd, "..", "repo", ".git");
  assert.throws(() => closeSync(openSync(join(common, "config"), "r+")), { code: "EPERM" });
  const admin = join(common, "worktrees", "worktree");
  // 同じ名前形式・作成フラグで、Seatbelt の拒否と Bun のストリーム側の失敗を切り分ける。
  for (const name of ["index.lock", `omp-commit-${randomUUID()}.index`]) {
    const file = join(admin, name);
    assert.doesNotThrow(() => closeSync(openSync(file, "wx", 0o644)), `Cannot create linked-worktree Git file: ${name}`);
    rmSync(file);
  }
  let tool;
  commitExtension({ arktype: pi.arktype, registerTool(value) { tool = value; } });
  await tool.execute("probe", { paths: ["selected.txt"], subject: "test: select one file" }, undefined, undefined, { cwd });
}

if (import.meta.main) {
  // /tmp や ~/.omp 配下では、Worktree 用の書き込み許可がなくても成功する。
  const directory = mkdtempSync(join(realpathSync(process.cwd()), "omp-worktree-probe-"));
  const repo = join(directory, "repo");
  const worktree = join(directory, "worktree");
  const home = join(directory, "home");
  const env = { HOME: home, PATH: process.env.PATH, GIT_CONFIG_NOSYSTEM: "1" };
  const git = (cwd, args, input) => execFileSync("git", args, { cwd, env, input, encoding: "utf8" }).trim();
  try {
    mkdirSync(repo);
    git(repo, ["init", "--quiet", "--initial-branch=main", "--ref-format=files"]);
    git(repo, ["config", "user.name", "OMP Test"]);
    git(repo, ["config", "user.email", "omp-test@example.invalid"]);
    git(repo, ["config", "core.hooksPath", ".git-hooks"]);
    const blob = git(repo, ["hash-object", "-w", "--stdin"], "original\n");
    const paths = Array.from({ length: 1600 }, (_, n) => `padding/file-for-a-large-linked-worktree-index-${String(n).padStart(4, "0")}.txt`);
    git(repo, ["update-index", "--index-info"], [...paths, "selected.txt", "staged.txt"].map(path => `100644 ${blob}\t${path}\n`).join(""));
    git(repo, ["commit", "--quiet", "-m", "base"]);
    git(repo, ["worktree", "add", "--quiet", "-b", "feature/omp-probe", worktree]);
    const index = git(worktree, ["rev-parse", "--path-format=absolute", "--git-path", "index"]);
    assert.ok(statSync(index).size > 128 * 1024, "fixture must exercise Bun's large-file copy path");
    writeFileSync(join(worktree, "selected.txt"), "selected\n");
    writeFileSync(join(worktree, "staged.txt"), "staged\n");
    git(worktree, ["add", "staged.txt"]);
    mkdirSync(join(worktree, ".git-hooks"));
    writeFileSync(join(worktree, ".git-hooks", "pre-commit"), '#!/bin/sh\nprintf "ran\\n" > hook-ran\n', { mode: 0o755 });
    const repoPolicy = join(home, ".omp", "permissions.d", `${repo}.yml`);
    mkdirSync(dirname(repoPolicy), { recursive: true });
    writeFileSync(repoPolicy, "{}\n");

    // RPC はプロンプトを送らなくてもモデルの選択が必要。接続せずに解決できる定義を使う。
    const agent = join(home, ".omp", "agent");
    mkdirSync(agent);
    writeFileSync(join(agent, "models.yml"), `providers:
  worktree-probe:
    baseUrl: http://127.0.0.1:1/v1
    auth: none
    api: openai-completions
    models:
      - id: local
`);

    execFileSync("omp", ["--offline", "--no-session", "--mode", "rpc", "--model", "worktree-probe/local",
      "--trusted-extension", fileURLToPath(import.meta.url)], {
      cwd: worktree, env, input: "", stdio: ["pipe", "ignore", "inherit"], timeout: 30_000,
    });
    assert.equal(git(worktree, ["show", "--format=", "--name-only", "HEAD"]), "selected.txt");
    assert.equal(git(worktree, ["diff", "--cached", "--name-only"]), "staged.txt");
    assert.ok(statSync(join(worktree, "hook-ran")).isFile());
    console.log("OMP worktree commit verified: large index, hook execution, and preservation of unrelated staged changes.");
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}
