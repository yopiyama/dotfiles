// 通常のターミナルから実行する。実在の秘密情報は使用せず、一時ファイルだけで検証する。
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const source = name => fs.readFileSync(fileURLToPath(new URL(name, import.meta.url)), "utf8");
const profile = source("./secrets.sb") + source("./workspace.sb");
const root = fs.realpathSync(process.cwd());
const temp = fs.realpathSync(os.tmpdir());
const sandbox = (command, args, workspace = root, state = path.join(root, "omp-probe-state"), vault = workspace, commit = {}) =>
  spawnSync("/usr/bin/sandbox-exec", [
    "-D", `WORKSPACE=${workspace}`, "-D", `STATE=${state}`, "-D", `TEMP=${temp}`,
    "-D", `OBSIDIAN_VAULT=${vault}`,
    "-D", `POLICIES=${path.join(state, "permissions.d")}`,
    "-D", `COMMIT_WRITE=${commit.write ?? "^$"}`, "-D", `COMMIT_PARENTS=${commit.parents ?? "^$"}`,
    "-p", profile, command, ...args,
  ], { encoding: "utf8" });
const probe = sandbox("/usr/bin/true", []);
if (probe.status !== 0) {
  console.error("Sandbox could not start. OMP's protected launcher will also refuse to start.");
  console.error(probe.error?.message ?? probe.stderr.trim());
  process.exit(77);
}

const directory = fs.mkdtempSync(path.join(root, "omp-sandbox-probe-"));
const temporary = fs.mkdtempSync("/private/tmp/omp-sandbox-probe-");
try {
  const workspace = path.join(directory, "project");
  const outside = path.join(directory, "project-other");
  const state = path.join(directory, "state");
  const vault = path.join(directory, "vault");
  for (const dir of [workspace, outside, state, vault]) fs.mkdirSync(dir);
  const run = (command, args) => sandbox(command, args, workspace, state, vault);
  const childFs = (script, ...args) => run(process.execPath, ["-e", script, ...args]);
  const touch = file => childFs('require("node:fs").appendFileSync(process.argv[1], "fixture")', file);
  const remove = file => childFs('require("node:fs").unlinkSync(process.argv[1])', file);
  const allowed = result => assert.equal(result.status, 0, result.stderr);
  const denied = result => {
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /EPERM|EACCES|[Oo]peration not permitted|[Pp]ermission denied/);
  };
  const outsideFile = path.join(outside, "outside.txt");
  fs.writeFileSync(outsideFile, "unchanged");
  const link = path.join(workspace, "other");
  fs.symlinkSync(outside, link);
  allowed(run("/usr/bin/head", ["-c", "1", outsideFile]));
  denied(touch(outsideFile));
  denied(remove(outsideFile));
  denied(touch(path.join(link, "outside.txt")));
  assert.equal(fs.readFileSync(outsideFile, "utf8"), "unchanged");
  denied(childFs('require("node:fs").renameSync(process.argv[1], process.argv[2])', workspace, path.join(temporary, "moved")));
  // obs.sh と同じく、Vault 内の一時ファイルから rename でノートを保存できる。
  const note = path.join(vault, "Notes", "note.md");
  allowed(childFs(`
    const fs = require("node:fs");
    const note = process.argv[1];
    fs.mkdirSync(require("node:path").dirname(note));
    fs.writeFileSync(note + ".obs-tmp", "fixture");
    fs.renameSync(note + ".obs-tmp", note);
  `, note));
  assert.equal(fs.readFileSync(note, "utf8"), "fixture");
  denied(childFs('require("node:fs").renameSync(process.argv[1], process.argv[2])', vault, path.join(temporary, "moved-vault")));
  denied(touch(path.join(vault, "fixture.key")));
  const vaultLink = path.join(vault, "other");
  fs.symlinkSync(outside, vaultLink);
  denied(touch(path.join(vaultLink, "outside.txt")));
  const tempFile = path.join(temporary, "tmp-file.txt");
  allowed(touch(tempFile.replace("/private/tmp/", "/tmp/")));
  allowed(remove(tempFile));
  allowed(touch(path.join(state, "session.txt")));
  const policies = path.join(state, "permissions.d");
  fs.mkdirSync(policies);
  denied(touch(path.join(policies, "local.yml")));
  const ordinary = path.join(workspace, "ordinary.txt");
  allowed(touch(ordinary));
  allowed(run("/usr/bin/head", ["-c", "1", ordinary]));
  const fixtures = [".env", ".env.local", ".envrc", "settings.env", "id_fixture", "fixture.pem", "fixture.key"];
  for (const name of fixtures) {
    const file = path.join(workspace, name);
    fs.writeFileSync(file, "synthetic test data; no credentials");
    denied(run("/usr/bin/head", ["-c", "1", file]));
  }
  const alias = path.join(workspace, "ordinary-alias.txt");
  fs.symlinkSync(path.join(workspace, "fixture.key"), alias);
  denied(run("/usr/bin/head", ["-c", "1", alias]));
  denied(run("/bin/sh", ["-c", 'exec /usr/bin/head -c 1 "$1"', "sh", path.join(workspace, "fixture.key")]));

  const goModule = path.join(state, "cache/go-mod/example.org/module@v1.0.0");
  const goSource = path.join(goModule, "id_test.go");
  fs.mkdirSync(goModule, { recursive: true });
  allowed(touch(goSource));
  allowed(run("/usr/bin/head", ["-c", "1", goSource]));
  denied(touch(path.join(workspace, "id_test.go")));
  // Go の ZIP 展開と失敗時の回収と同じく、名前や階層にかかわらず書けるが読めない。
  for (const member of ["example/server/sample.pem", "test/sample.key", "fixtures/sample.env",
    ".env.sample", "id_fixture", ".env.fixtures/id_nested.go"]) {
    const file = path.join(goModule, member);
    const extract = childFs(`
      const fs = require("node:fs");
      const file = process.argv[1];
      fs.mkdirSync(require("node:path").dirname(file), { recursive: true });
      fs.writeFileSync(file, "synthetic archive data", { flag: "wx", mode: 0o444 });
    `, file);
    allowed(extract);
    denied(run("/usr/bin/head", ["-c", "1", file]));
    allowed(remove(file));
  }
  const partial = path.join(goModule, ".env.fixtures");
  allowed(touch(path.join(partial, "partial-marker.txt")));
  allowed(childFs('require("node:fs").rmSync(process.argv[1], { recursive: true })', partial));
  assert.ok(!fs.existsSync(partial));
  const keyAlias = path.join(goModule, "outside.key");
  fs.symlinkSync(path.join(workspace, "fixture.key"), keyAlias);
  denied(touch(keyAlias));
  const cacheAlias = path.join(goModule, "linked-outside");
  fs.symlinkSync(outside, cacheAlias);
  denied(touch(path.join(cacheAlias, "outside.txt")));
  const otherCache = path.join(state, "cache/go-mod-other");
  fs.mkdirSync(otherCache);
  denied(touch(path.join(otherCache, "fixture.key")));

  const refs = path.join(outside, "refs");
  const branch = path.join(refs, "feature");
  const literalRegex = name => `^${name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}$`;
  const commit = { write: literalRegex(branch), parents: literalRegex(refs) };
  const gitWrite = (script, file) => sandbox(process.execPath, ["-e", script, file], workspace, state, vault, commit);
  allowed(gitWrite('require("node:fs").mkdirSync(process.argv[1])', refs));
  denied(gitWrite('require("node:fs").rmdirSync(process.argv[1])', refs));
  const updateRef = 'require("node:fs").writeFileSync(process.argv[1], "fixture")';
  allowed(gitWrite(updateRef, branch));
  denied(gitWrite(updateRef, path.join(refs, "main")));

  allowed(remove(ordinary));
  console.log("Sandbox verified: workspace, Obsidian vault, state, and temporary writes allowed; outside writes/deletions, protected root removal, and secret reads denied.");
} finally {
  fs.rmSync(directory, { recursive: true, force: true });
  fs.rmSync(temporary, { recursive: true, force: true });
}
