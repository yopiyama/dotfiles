const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { JSDOM } = require("jsdom");
const rules = require("../rules.js");
const source = name => fs.readFileSync(path.join(__dirname, "..", name), "utf8");
const pause = () => new Promise(resolve => setTimeout(resolve, 180));
const fixture = `
  <ul aria-label="File Tree"><li role="treeitem" id="folder"><span>api</span><ul role="group">
    <li role="treeitem" id="generated-row"><span data-filterable-item-text hidden>api/user.pb.go</span><a href="#diff-gen">user.pb.go</a></li>
    <li role="treeitem"><a href="#diff-proto">user.proto</a></li>
  </ul></li><li role="treeitem"><a href="#diff-code">usecase.go</a></li></ul>
  <copilot-diff-entry data-file-path="api/user.pb.go"><div class="js-file" id="diff-gen"><div class="file-header" data-path="api/user.pb.go"></div><textarea>review in progress</textarea></div></copilot-diff-entry>
  <div class="js-file" id="diff-proto"><div class="file-header" data-path="api/user.proto"></div></div>
  <div class="Diff_diffTargetable__abc" id="diff-code"><div class="Diff_diff-file-header__abc"><a href="#diff-code" class="Diff_file-name__abc"><code>user/usecase.go</code></a></div><button aria-label="Not Viewed">Viewed</button></div>
  <div class="Diff_diffTargetable__abc" id="diff-test"><div class="Diff_diff-file-header__abc"><a class="Diff_file-name__abc"><code>user/usecase_test.go</code></a></div></div>`;

function setup(html = fixture, pathname = "/owner/repo/pull/1/changes") {
  const dom = new JSDOM(html, { url: `https://github.com${pathname}`, runScripts: "outside-only" });
  const listeners = [];
  const saved = {};
  const messages = [];
  dom.window.chrome = {
    runtime: {
      getURL: file => `chrome-extension://test/${file}`,
      sendMessage: async message => { messages.push(message); return { ok: true }; }
    },
    storage: {
      local: { get: async key => ({ [key]: saved[key] }), set: async value => Object.assign(saved, value) },
      onChanged: { addListener: callback => listeners.push(callback) }
    }
  };
  dom.window.eval(source("rules.js"));
  dom.window.eval(source("github-dom.js"));
  return { dom, window: dom.window, document: dom.window.document, api: dom.window.GitHubReviewDOM, listeners, saved, messages };
}

test("legacy wrapper and React header yield one entry per path and native tree links", t => {
  const { dom, document, api } = setup();
  t.after(() => dom.window.close());
  const entries = api.collect(document);
  assert.equal(entries.length, 4);
  const generated = entries.find(entry => entry.path === "api/user.pb.go");
  assert.equal(generated.cards.size, 1);
  assert.equal(generated.links.size, 1);
  assert.equal([...generated.cards][0].tagName, "COPILOT-DIFF-ENTRY");
  assert.ok(entries.some(entry => entry.path === "user/usecase.go"));
});
test("hiding and restoring preserve review inputs, native viewed state and directory siblings", t => {
  const { dom, document, api } = setup();
  t.after(() => dom.window.close());
  const entries = api.collect(document);
  const textarea = document.querySelector("textarea");
  api.filter(document, entries, rules.classifier(), false);
  assert.ok(document.querySelector("copilot-diff-entry").hasAttribute("data-ghrg-hidden"));
  assert.ok(document.querySelector("#generated-row").hasAttribute("data-ghrg-hidden"));
  assert.ok(!document.querySelector("#folder").hasAttribute("data-ghrg-hidden"));
  assert.ok(!document.querySelector("#diff-proto").hasAttribute("data-ghrg-hidden"));
  api.filter(document, entries, rules.classifier(), true);
  assert.equal(document.querySelectorAll("[data-ghrg-hidden]").length, 0);
  assert.equal(document.querySelector("textarea"), textarea);
  assert.equal(textarea.value, "review in progress");
  assert.equal(document.querySelector('[aria-label="Not Viewed"]').textContent, "Viewed");
});
test("renamed React file uses its destination path", t => {
  const { dom, document, api } = setup(`<div class="Diff_diffTargetable__abc"><div class="Diff_file-name__abc"><code>old.go → new_test.go<span class="sr-only">old.go renamed to new_test.go</span></code></div></div>`);
  t.after(() => dom.window.close());
  assert.equal(api.collect(document)[0].path, "new_test.go");
});
test("GitHub generated markers hide nonstandard paths without changing native hidden state", t => {
  const { dom, document, api } = setup(`<div class="js-file" data-path="unusual.go" hidden data-file-generated="true"></div>
    <div class="js-file" data-path="also-unusual.go"><div class="file-header"><span class="Label">Generated</span></div></div>`);
  t.after(() => dom.window.close());
  const entries = api.collect(document);
  assert.ok(entries.every(entry => entry.generated));
  api.filter(document, entries, rules.classifier(), false);
  assert.equal(document.querySelectorAll("[data-ghrg-hidden]").length, 2);
  api.restore(document);
  assert.ok(document.querySelector('[data-path="unusual.go"]').hidden);
});
test("tree path metadata supports a diff not yet loaded", t => {
  const { dom, document, api } = setup(`<ul aria-label="File Tree"><li role="treeitem"><span data-filterable-item-text hidden>api/user.pb.go</span><a href="#diff-lazy">user.pb.go</a></li></ul>`);
  t.after(() => dom.window.close());
  const [entry] = api.collect(document);
  assert.equal(entry.path, "api/user.pb.go");
  assert.equal(entry.cards.size, 0);
  api.filter(document, [entry], rules.classifier(), false);
  assert.ok(document.querySelector("li").hasAttribute("data-ghrg-hidden"));
});
test("navigation delegates to the original link", t => {
  const { dom, document, api } = setup();
  t.after(() => dom.window.close());
  let clicked = false;
  const link = document.querySelector('a[href="#diff-code"]');
  link.addEventListener("click", event => { event.preventDefault(); clicked = true; });
  api.navigate(document, api.collect(document).find(entry => entry.path === "user/usecase.go"));
  assert.ok(clicked);
});
test("panel groups files, updates on lazy loading, toggles generated files and cleans up on SPA exit", async t => {
  const { dom, window, document } = setup();
  t.after(() => window.close());
  window.eval(source("content.js"));
  await pause();
  assert.ok(document.querySelector("#ghrg-panel.ghrg-docked"));
  assert.deepEqual([...document.querySelectorAll("#ghrg-panel nav summary")].map(el => el.textContent), ["定義（1）", "実装（1）", "テスト（1）"]);
  assert.ok(document.querySelector("copilot-diff-entry").hasAttribute("data-ghrg-hidden"));
  const checkbox = document.querySelector("#ghrg-panel input");
  checkbox.click();
  assert.equal(document.querySelectorAll("[data-ghrg-hidden]").length, 0);
  assert.ok(document.querySelector("#ghrg-panel nav").textContent.includes("生成ファイル（1）"));
  checkbox.click();
  const lazy = document.createElement("div");
  lazy.className = "js-file";
  lazy.setAttribute("data-path", "gen/late.go");
  document.body.append(lazy);
  await pause();
  assert.ok(lazy.hasAttribute("data-ghrg-hidden"));
  assert.match(document.querySelector(".ghrg-status").textContent, /5 ファイル/);
  window.history.pushState({}, "", "/owner/repo/issues/1");
  window.dispatchEvent(new window.PopStateEvent("popstate"));
  await pause();
  assert.equal(document.querySelector("#ghrg-panel"), null);
  assert.equal(document.querySelectorAll("[data-ghrg-hidden]").length, 0);
});
test("stored repository rules apply live without affecting another repository", async t => {
  const { window, document, listeners } = setup();
  t.after(() => window.close());
  window.eval(source("content.js"));
  await pause();
  listeners[0]({ "rules:other/repo": { newValue: { generated: [] } } }, "local");
  assert.ok(document.querySelector("[data-ghrg-hidden]"));
  listeners[0]({ "rules:owner/repo": { newValue: { generated: [] } } }, "local");
  assert.equal(document.querySelectorAll("[data-ghrg-hidden]").length, 0);
});
test("slow settings from a previous repository cannot overwrite the current repository", async t => {
  const { window, document, messages } = setup();
  t.after(() => window.close());
  let resolveOld;
  window.chrome.storage.local.get = key => key === "rules:owner/repo"
    ? new Promise(resolve => { resolveOld = resolve; }) : Promise.resolve({});
  window.eval(source("content.js"));
  await pause();
  window.history.pushState({}, "", "/other/repo/pull/2/changes");
  document.body.append(document.createElement("div"));
  await pause();
  resolveOld({ "rules:owner/repo": { generated: [] } });
  await pause();
  assert.ok(document.querySelector("[data-ghrg-hidden]"));
  document.querySelector(".ghrg-settings").click();
  assert.equal(messages[0].repository, "other/repo");
});
test("settings button requests an extension-owned tab instead of linking from the website", async t => {
  const { window, document, messages } = setup();
  t.after(() => window.close());
  window.eval(source("content.js"));
  await pause();
  assert.equal(document.querySelector('#ghrg-panel a[href^="chrome-extension:"]'), null);
  document.querySelector(".ghrg-settings").click();
  assert.equal(messages.length, 1);
  assert.equal(messages[0].type, "open-settings");
  assert.equal(messages[0].repository, "owner/repo");
});
test("settings button reports a failure to open and allows retrying", async t => {
  const { window, document } = setup();
  t.after(() => window.close());
  window.chrome.runtime.sendMessage = async () => { throw new Error("Extension context invalidated"); };
  window.eval(source("content.js"));
  await pause();
  const button = document.querySelector(".ghrg-settings");
  button.click();
  await new Promise(setImmediate);
  assert.equal(button.disabled, false);
  assert.match(document.querySelector(".ghrg-status").textContent, /設定を開けません/);
});
test("SPA entry from a conversation activates the extension and a new PR resets visibility", async t => {
  const { window, document } = setup(fixture, "/owner/repo/pull/1");
  t.after(() => window.close());
  window.eval(source("content.js"));
  await pause();
  assert.equal(document.querySelector("#ghrg-panel"), null);
  window.history.pushState({}, "", "/owner/repo/pull/1/changes");
  document.body.append(document.createElement("div"));
  await pause();
  document.querySelector("#ghrg-panel input").click();
  window.history.pushState({}, "", "/owner/repo/pull/2/changes");
  document.body.append(document.createElement("div"));
  await pause();
  assert.equal(document.querySelector("#ghrg-panel input").checked, false);
  assert.ok(document.querySelector("[data-ghrg-hidden]"));
});
test("settings load and save repository-specific patterns", async t => {
  const { window, document, saved } = setup(source("options.html"), "/options.html?repository=owner%2Frepo");
  t.after(() => window.close());
  window.eval(source("options.js"));
  await pause();
  const form = document.querySelector("form");
  form.elements.generated.value = "custom/**\n\n**/*.pb.go";
  form.dispatchEvent(new window.Event("submit", { bubbles: true, cancelable: true }));
  await pause();
  assert.deepEqual([...saved["rules:owner/repo"].generated], ["custom/**", "**/*.pb.go"]);
  assert.match(document.querySelector("#status").textContent, /保存しました/);
});
test("repository-specific output paths are read from local storage and removed with the setting", async t => {
  const { window, document, saved, listeners } = setup(
    '<div class="js-file" data-path="backend/mock/client.go"></div>',
    "/owner/repo/pull/1/changes"
  );
  t.after(() => window.close());
  const key = "rules:owner/repo";
  saved[key] = { generated: ["backend/mock/client.go"] };
  window.eval(source("content.js"));
  await pause();
  assert.ok(document.querySelector("[data-ghrg-hidden]"));
  listeners[0]({ [key]: { newValue: undefined } }, "local");
  assert.equal(document.querySelector("[data-ghrg-hidden]"), null);
});
test("settings show and reset to shared defaults rather than local output paths", async t => {
  const { window, document, saved } = setup(source("options.html"), "/options.html?repository=owner%2Frepo");
  t.after(() => window.close());
  saved["rules:owner/repo"] = { generated: ["backend/mock/client.go"] };
  window.eval(source("options.js"));
  await pause();
  const field = document.querySelector("form").elements.generated;
  assert.equal(field.value, "backend/mock/client.go");
  document.getElementById("reset").click();
  assert.ok(!field.value.split("\n").includes("backend/mock/client.go"));
  assert.ok(field.value.split("\n").includes("**/*.mock.go"));
  assert.ok(!field.value.split("\n").includes("**/*.gen.*"));
});
