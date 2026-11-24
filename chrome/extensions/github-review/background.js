importScripts("rules.js");

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type !== "open-settings") return;
  let repository;
  try {
    const url = new URL(sender.url);
    if (sender.id !== chrome.runtime.id || url.origin !== "https://github.com") return;
    repository = GitHubReviewRules.repository(url.pathname);
    if (!repository || repository !== message.repository) return;
  } catch { return; }
  const url = chrome.runtime.getURL(`options.html?repository=${encodeURIComponent(repository)}`);
  chrome.tabs.create({ url }).then(
    () => sendResponse({ ok: true }),
    () => sendResponse({ ok: false })
  );
  return true;
});
