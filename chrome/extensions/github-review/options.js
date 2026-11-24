(async () => {
  const rules = globalThis.GitHubReviewRules;
  const repository = new URLSearchParams(location.search).get("repository");
  const form = document.querySelector("form");
  const status = document.getElementById("status");
  if (!repository || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository)) {
    form.hidden = true;
    status.textContent = "PR の Review groups にある「分類設定」から開いてください。";
    return;
  }
  document.getElementById("repository").textContent = repository;
  const key = `rules:${repository}`;
  function fill(value) {
    for (const [name, patterns] of Object.entries(rules.normalize(value))) form.elements[name].value = patterns.join("\n");
  }
  form.querySelectorAll("button").forEach(button => button.disabled = true);
  try {
    const stored = await chrome.storage.local.get(key);
    fill(stored[key]);
    form.querySelectorAll("button").forEach(button => button.disabled = false);
  } catch {
    status.textContent = "設定を取得できません。ページを再読み込みしてください。";
    return;
  }
  document.getElementById("reset").addEventListener("click", () => {
    fill();
    status.textContent = "標準ルールを入力しました。保存すると適用されます。";
  });
  form.addEventListener("submit", async event => {
    event.preventDefault();
    const value = Object.fromEntries(Object.keys(rules.defaults).map(name => [name,
      form.elements[name].value.split(/\r?\n/).map(line => line.trim()).filter(Boolean)
    ]));
    try {
      await chrome.storage.local.set({ [key]: value });
      status.textContent = "保存しました。開いている PR にも反映されます。";
    } catch { status.textContent = "保存できませんでした。もう一度お試しください。"; }
  });
})();
