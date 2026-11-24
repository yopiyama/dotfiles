import assert from "node:assert/strict";
import test from "node:test";
import safety from "./safety.ts";
import approvalSafety from "./approval-safety.ts";

let guard;
safety({ on(event, handler) { assert.equal(event, "tool_call"); guard = handler; } });
const main = { agent: { kind: "main" }, hasUI: true };
const sub = { agent: { kind: "sub", name: "explore" }, hasUI: false };
const call = (toolName, input = {}, ctx = main) => guard({ toolName, input }, ctx);

test("main allows ordinary work to reach the configured approval gate", async () => {
  for (const command of ["git status --short", "git diff", "git push origin feature", "make test"]) {
    assert.equal(await call("bash", { command }), undefined, command);
  }
  assert.equal(await call("edit", { path: "src/main.ts" }), undefined);
});

test("known destructive commands and deletion are rejected", async () => {
  for (const command of [
    "rm -rf build", "echo ok && rm file", "git reset --hard", "git -C ../repo clean -fd",
    "git push --force-with-lease origin feature", "git push origin :main --delete",
    "git push origin :main", "git push origin +HEAD:main",
    "git branch -D feature", "git checkout -- src/a.ts", "git restore src/a.ts", "sudo sh",
  ]) {
    assert.equal((await call("bash", { command }))?.block, true, command);
  }
  assert.equal((await call("delete", { path: "src/main.ts" }))?.block, true);
});

test("subagents including depth-zero clones and advisors cannot mutate or execute", async () => {
  for (const tool of ["bash", "eval", "edit", "write", "delete", "task", "mcp__db_query", "lsp", "debug"]) {
    assert.equal((await call(tool, {}, sub))?.block, true, tool);
    assert.equal((await call(tool, {}, { ...sub, agent: { kind: "sub", id: "advisor", depth: 0 } }))?.block, true);
  }
  for (const tool of ["read", "grep", "glob", "ast_grep", "ls"]) {
    assert.equal(await call(tool, {}, sub), undefined, tool);
  }
});

test("headless or unknown contexts fail closed for mutations", async () => {
  assert.equal((await call("bash", { command: "echo ok" }, { agent: { kind: "main" }, hasUI: false }))?.block, true);
  assert.equal((await call("write", {}, { hasUI: true }))?.block, true);
});

test("scout-only batches skip confirmation, but other delegations do not", async () => {
  let approvalGuard;
  approvalSafety({ on(_event, handler) { approvalGuard = handler; } });
  let prompted = 0;
  const ctx = { ...main, ui: { confirm() { prompted++; return false; } } };
  const delegate = input => approvalGuard({ toolName: "task", input }, ctx);
  const scout = { agent: "scout", task: "Find references", solutionSpace: "read-only" };
  assert.equal(await delegate({ tasks: [scout] }), undefined);
  assert.equal(prompted, 0);
  for (const item of [{ ...scout, agent: "task" }, { ...scout, isolated: true }, { ...scout, tools: ["custom"] }]) {
    assert.equal((await delegate({ tasks: [scout, item] }))?.block, true);
  }
  assert.equal(prompted, 3);
});

test("Bash cannot carry a project-scoped approval to another cwd", async t => {
  const root = process.cwd();
  const workspace = "DOTFILES_OMP_WORKSPACE";
  const projectPolicy = "DOTFILES_OMP_PROJECT_POLICY";
  const oldWorkspace = process.env[workspace];
  const oldPolicy = process.env[projectPolicy];
  t.after(() => {
    if (oldWorkspace === undefined) delete process.env[workspace];
    else process.env[workspace] = oldWorkspace;
    if (oldPolicy === undefined) delete process.env[projectPolicy];
    else process.env[projectPolicy] = oldPolicy;
  });
  process.env[workspace] = root;
  process.env[projectPolicy] = "1";
  let approvalGuard;
  approvalSafety({ on(_event, handler) { approvalGuard = handler; } });
  const task = (sessionCwd, cwd) => approvalGuard({
    toolName: "bash",
    input: { command: "git status && task package:build", cwd },
  }, { ...main, cwd: sessionCwd });
  assert.equal(await task(root, undefined), undefined);
  assert.equal(await task(root, "."), undefined);
  assert.equal((await task(root, ".."))?.block, true);
  assert.equal((await task("/tmp", undefined))?.block, true);
});
