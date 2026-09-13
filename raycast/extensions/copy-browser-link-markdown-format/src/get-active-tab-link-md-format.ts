import { BrowserExtension, Clipboard, closeMainWindow, showHUD } from "@raycast/api";

export default async function Command() {
  const tabs = await BrowserExtension.getTabs();

  // 複数ウィンドウがある場合でも「active」な tab を拾う
  // 必要ならここで URL などを見て追加の絞り込みも可能
  const activeTab = tabs.find((tab) => tab.active);

  if (!activeTab?.url) {
    throw new Error("アクティブなタブの URL を取得できませんでした");
  }

  const title = normalizeTitle(activeTab.title?.trim() || activeTab.url, activeTab.url);
  const markdown = `[${escapeMarkdownText(title)}](${activeTab.url})`;

  await Clipboard.copy(markdown);
  await closeMainWindow();
  await showHUD("Markdown link をコピーしました");
}

function normalizeTitle(title: string, url: string): string {
  if (!isNotionUrl(url)) {
    return title;
  }

  // Notion prefixes the title with an unread notification count, e.g. "(9+) ".
  return title.replace(/^\(\d+\+?\)\s*/, "");
}

function isNotionUrl(url: string): boolean {
  try {
    const hostname = new URL(url).hostname.toLowerCase();
    return (
      hostname === "notion.so" ||
      hostname.endsWith(".notion.so") ||
      hostname === "notion.com" ||
      hostname.endsWith(".notion.com")
    );
  } catch {
    return false;
  }
}

function escapeMarkdownText(text: string): string {
  return text.replace(/[[\]\\]/g, "\\$&");
}
