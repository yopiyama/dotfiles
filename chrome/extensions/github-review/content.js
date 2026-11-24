(() => {
  const rules = globalThis.GitHubReviewRules;
  const dom = globalThis.GitHubReviewDOM;
  let currentPage = "";
  let repository = null;
  let classify = rules.classifier();
  let entries = [];
  let panel;
  let groups;
  let status;
  let checkbox;
  let signature = "";
  let scheduled = false;
  let version = 0;
  const expanded = new Map();

  function createPanel() {
    panel = document.createElement("aside");
    panel.id = "ghrg-panel";
    panel.setAttribute("aria-label", "レビュー用ファイル一覧");
    const details = document.createElement("details");
    details.open = true;
    const summary = document.createElement("summary");
    summary.textContent = "Review groups";
    details.append(summary);
    const controls = document.createElement("div");
    controls.className = "ghrg-controls";
    const label = document.createElement("label");
    checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.addEventListener("change", () => update(true));
    label.append(checkbox, " 生成ファイルを表示");
    const settings = document.createElement("button");
    settings.type = "button";
    settings.className = "ghrg-settings";
    settings.textContent = "分類設定";
    settings.addEventListener("click", async () => {
      settings.disabled = true;
      try {
        const response = await chrome.runtime.sendMessage({ type: "open-settings", repository });
        if (!response?.ok) throw new Error("Could not open settings");
      } catch {
        status.textContent = "設定を開けません。拡張機能と PR のタブを再読み込みしてください。";
      } finally { settings.disabled = false; }
    });
    controls.append(label, settings);
    status = document.createElement("p");
    status.className = "ghrg-status";
    status.setAttribute("role", "status");
    groups = document.createElement("nav");
    groups.setAttribute("aria-label", "分類した変更ファイル");
    details.append(controls, status, groups);
    panel.append(details);
    document.body.append(panel);
  }

  function update(force = false) {
    if (!panel?.isConnected) return;
    const tree = document.querySelector('ul[aria-label="File Tree"]');
    // Insert only our node. Keep GitHub's own tree and React-owned nodes intact.
    if (tree && !tree.contains(panel)) {
      if (panel.nextElementSibling !== tree) tree.before(panel);
      panel.classList.add("ghrg-docked");
    }
    entries = dom.collect(document);
    dom.filter(document, entries, classify, checkbox.checked);
    const nextSignature = JSON.stringify([checkbox.checked, entries.map(e => [e.path, classify(e.path, e.generated)])]);
    if (!force && signature === nextSignature) return;
    signature = nextSignature;
    const generated = entries.filter(e => classify(e.path, e.generated) === "generated").length;
    status.textContent = entries.length
      ? `${entries.length} ファイルを検出 / 生成 ${generated}${checkbox.checked ? "" : "（非表示）"}`
      : "変更ファイルを検出できません。GitHub 標準の一覧を利用してください。";
    groups.replaceChildren();
    for (const [key, name] of rules.groups) {
      const members = entries.filter(e => classify(e.path, e.generated) === key);
      if (!members.length || (key === "generated" && !checkbox.checked)) continue;
      const group = document.createElement("details");
      group.open = expanded.get(key) ?? key !== "generated";
      group.addEventListener("toggle", () => { if (group.isConnected) expanded.set(key, group.open); });
      const summary = document.createElement("summary");
      summary.textContent = `${name}（${members.length}）`;
      const list = document.createElement("ul");
      for (const entry of members) {
        const row = document.createElement("li");
        const button = document.createElement("button");
        button.type = "button";
        button.textContent = entry.path;
        button.title = entry.path;
        button.addEventListener("click", () => {
          const latest = entries.find(e => e.path === entry.path);
          if (latest) dom.navigate(document, latest);
        });
        row.append(button);
        list.append(row);
      }
      group.append(summary, list);
      groups.append(group);
    }
  }

  async function refresh() {
    scheduled = false;
    const page = location.pathname;
    const nextRepository = rules.repository(page);
    if (page !== currentPage || !panel?.isConnected) {
      const request = ++version;
      currentPage = page;
      repository = nextRepository;
      dom.restore(document);
      panel?.remove();
      panel = null;
      entries = [];
      signature = "";
      expanded.clear();
      if (!repository) return;
      classify = rules.classifier();
      createPanel();
      update(true);
      const key = `rules:${repository}`;
      try {
        const stored = await chrome.storage.local.get(key);
        if (request !== version) return;
        classify = rules.classifier(stored[key]);
        update(true);
      } catch (error) { console.warn("GitHub Review Groups: 設定を取得できません", error); }
      return;
    }
    if (nextRepository) update();
  }
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    setTimeout(refresh, 100);
  }
  const observer = new MutationObserver(records => {
    // Ignore our own rendering and visibility attributes to avoid feedback loops.
    if (records.some(record => !record.target.closest?.("#ghrg-panel"))) schedule();
  });
  observer.observe(document.body, { childList: true, subtree: true, attributes: true,
    attributeFilter: ["data-path", "data-file-path", "data-generated", "data-is-generated", "data-file-generated", "href"] });
  document.addEventListener("turbo:load", schedule);
  document.addEventListener("turbo:render", schedule);
  window.addEventListener("popstate", schedule);
  chrome.storage.onChanged.addListener((changes, area) => {
    const key = `rules:${repository}`;
    if (area === "local" && changes[key]) {
      classify = rules.classifier(changes[key].newValue);
      update(true);
    }
  });
  schedule();
})();
