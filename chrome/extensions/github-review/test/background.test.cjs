const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

function setup(create = async () => ({})) {
  let receive;
  const tabs = [];
  const chrome = {
    runtime: {
      id: "test-extension",
      getURL: file => `chrome-extension://test-extension/${file}`,
      onMessage: { addListener: callback => { receive = callback; } }
    },
    tabs: { create: options => { tabs.push(options); return create(options); } }
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "../background.js"), "utf8"), {
    chrome, URL, GitHubReviewRules: require("../rules.js"), importScripts: () => {}
  });
  return { receive, tabs };
}
const message = { type: "open-settings", repository: "owner/repo" };
const sender = { id: "test-extension", url: "https://github.com/owner/repo/pull/1/changes" };

test("worker opens repository settings from the extension context and responds after tab creation", async () => {
  const { receive, tabs } = setup();
  const response = await new Promise(resolve => assert.equal(receive(message, sender, resolve), true));
  assert.equal(response.ok, true);
  assert.equal(tabs.length, 1);
  assert.equal(tabs[0].url, "chrome-extension://test-extension/options.html?repository=owner%2Frepo");
});
test("worker ignores requests outside this extension's matching GitHub PR", () => {
  const { receive, tabs } = setup();
  for (const invalid of [
    { ...sender, id: "another-extension" },
    { ...sender, url: "https://example.com/owner/repo/pull/1/changes" },
    { ...sender, url: "https://github.com/owner/repo/issues/1" },
    { ...sender, url: "https://github.com/other/repo/pull/1/changes" },
    { ...sender, url: "invalid" }
  ]) assert.equal(receive(message, invalid, () => assert.fail("Unexpected response")), undefined);
  assert.equal(receive({ type: "other" }, sender, () => {}), undefined);
  assert.equal(tabs.length, 0);
});
test("worker reports tab creation failure", async () => {
  const { receive } = setup(async () => { throw new Error("Tab creation failed"); });
  const response = await new Promise(resolve => receive(message, sender, resolve));
  assert.equal(response.ok, false);
});
