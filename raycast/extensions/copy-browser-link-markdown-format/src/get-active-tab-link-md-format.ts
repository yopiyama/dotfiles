import { BrowserExtension, Clipboard, closeMainWindow, showHUD } from "@raycast/api";

export default async function Command() {
  const tabs = await BrowserExtension.getTabs();

  // 複数ウィンドウがある場合でも「active」な tab を拾う
  // 必要ならここで URL などを見て追加の絞り込みも可能
  const activeTab = tabs.find((tab) => tab.active);

  if (!activeTab?.url) {
    throw new Error("アクティブなタブの URL を取得できませんでした");
  }

  let title = activeTab.title?.trim() || activeTab.url;

  // Notion のタブタイトルから通知数プレフィックス "(2) " などを除去
  if (activeTab.url.includes("notion.so")) {
      title = title.replace(/^\(\d+\)\s+/,"");
  }
  const title = activeTab.title?.trim() || activeTab.url;
  const markdown = `[${escapeMarkdownText(title)}](${activeTab.url})`;

  await Clipboard.copy(markdown);
  await closeMainWindow();
  await showHUD("Markdown link をコピーしました");
}

function escapeMarkdownText(text: string): string {
  return text.replace(/[[\]\\]/g, "\\$&");
}
