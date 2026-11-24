// OMP の実際のネイティブ edit parser を使う。 --trusted-extension でのみ起動する検証用。
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import workspaceSafety from "./workspace-safety.ts";

export default async function verify(pi) {
  let tool, guard;
  workspaceSafety({ zod: pi.zod, registerTool(value) { tool = value; }, on(_event, handler) { guard = handler; } });
  const root = process.env.DOTFILES_OMP_WORKSPACE;
  const project = mkdtempSync(join(root, "omp-approval-probe-"));
  const temp = mkdtempSync("/private/tmp/omp-approval-probe-");
  try {
    const original = join(project, "file.txt");
    const moved = join(project, "moved.txt");
    const temporary = join(temp, "file.txt");
    const alias = join(project, "alias");
    writeFileSync(original, "original");
    writeFileSync(temporary, "temporary");
    symlinkSync(temp, alias);

    const expects = (policy, args) => assert.equal(tool.approval(args).policy, policy, JSON.stringify(args));
    const remove = path => ({ operation: "delete", path });
    expects("deny", remove(root));
    expects("deny", remove(join(root, "..")));
    for (const path of ["/tmp", "/private/tmp", process.env.TMPDIR, join(alias, "file.txt"), alias]) {
      expects("deny", remove(path));
    }
    const move = { operation: "move", path: original, destination: moved };
    expects("prompt", move);
    expects("deny", { ...move, destination: temporary });
    assert.match(tool.formatApprovalDetails(move), /file\.txt.*moved\.txt/);
    await tool.execute("test", move);
    assert.equal(existsSync(original), false);
    assert.equal(existsSync(moved), true);
    expects("prompt", remove(moved));
    await tool.execute("test", remove(moved));
    assert.equal(existsSync(moved), false);

    const tempCleanup = { ...remove(temp.replace("/private/tmp/", "/tmp/")), recursive: true };
    expects("allow", tempCleanup);
    expects("allow", remove(temporary));
    await tool.execute("test", tempCleanup);
    assert.equal(existsSync(temp), false);

    const edit = input => guard({ toolName: "edit", input });
    assert.equal(edit({ input: "[file.txt#ABCD]\nPUT >1:\n+REM\n+MV example" }), undefined);
    for (const input of [
      { input: "[file.txt#ABCD]\nREM" },
      { input: '[file.txt#ABCD]\nMV "other file.txt"' },
      { input: "*** Begin Patch\n*** Delete File: file.txt\n*** End Patch" },
      { path: "file.txt", edits: [{ op: "delete" }] },
      { path: "file.txt", edits: [{ op: "update", rename: "moved.txt" }] },
    ]) {
      assert.equal(edit(input)?.block, true, JSON.stringify(input));
    }
    console.log("OMP workspace approvals verified: ordinary edit, destructive edit routes, explicit-path removal/move, and temporary cleanup.");
  } finally {
    rmSync(project, { recursive: true, force: true });
    rmSync(temp, { recursive: true, force: true });
  }
}
