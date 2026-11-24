(() => {
  const hiddenAttribute = "data-ghrg-hidden";
  // React selectors are also used by Refined GitHub; see README for references.
  const cardSelector = '.js-file, .file[data-path], copilot-diff-entry[data-file-path], [class*="diffTargetable"], [data-testid="diff-file"], [data-testid="diff-entry"]';
  function pathOf(element) {
    const attribute = element.getAttribute("data-path") || element.getAttribute("data-file-path") ||
      element.getAttribute("data-tagsearch-path") ||
      element.querySelector("[data-path]")?.getAttribute("data-path") ||
      element.querySelector("[data-file-path]")?.getAttribute("data-file-path");
    if (attribute) return attribute;
    const code = element.querySelector('[class*="file-name"] code');
    if (!code) return null;
    const rename = code.querySelector(".sr-only")?.textContent.split(" renamed to ", 2)[1];
    return (rename || code.textContent).replace(/[\u200e\u200f]/g, "").trim();
  }
  function collect(document) {
    const entries = new Map();
    function add(path, values) {
      if (!path || typeof path !== "string") return;
      const entry = entries.get(path) || { path, cards: new Set(), links: new Set(), generated: false };
      if (values.card) entry.cards.add(values.card);
      if (values.link) entry.links.add(values.link);
      entry.generated ||= !!values.generated;
      entries.set(path, entry);
    }
    for (const card of document.querySelectorAll(cardSelector)) {
      if (card.closest("#ghrg-panel")) continue;
      // A file's nested path label is not a second diff container.
      if (card.parentElement?.closest(cardSelector)) continue;
      const path = pathOf(card);
      if (!path) continue;
      const header = card.querySelector('.file-header, [class*="diff-file-header"], [class*="diffHeaderWrapper"]');
      const generatedSelector = '[data-generated="true"], [data-is-generated="true"], [data-file-generated="true"]';
      const generated = card.matches(generatedSelector) || !!card.querySelector(generatedSelector) ||
        [...(header?.querySelectorAll('[title], [aria-label], .Label') || [])].some(el =>
          /^(generated|generated file)$/i.test(el.getAttribute("title") || el.getAttribute("aria-label") || el.textContent.trim()));
      add(path, { card, generated });
    }
    for (const link of document.querySelectorAll('a[href*="#diff-"], ul[aria-label="File Tree"] a[href*="#"]')) {
      if (link.closest("#ghrg-panel") || link.closest(cardSelector)) continue;
      let url;
      try { url = new URL(link.href, document.location.href); } catch { continue; }
      if (url.origin !== document.location.origin || url.pathname !== document.location.pathname) continue;
      let target;
      try { target = document.getElementById(decodeURIComponent(url.hash.slice(1))); } catch { continue; }
      const card = target?.matches(cardSelector) ? target : target?.closest(cardSelector);
      const row = link.closest('[role="treeitem"], li');
      const path = pathOf(link) || (card && pathOf(card)) || (target && pathOf(target)) ||
        row?.querySelector("[data-filterable-item-text]")?.textContent.trim() ||
        link.getAttribute("title") || link.getAttribute("aria-label") || link.textContent.trim();
      add(path, { link });
    }
    return [...entries.values()].sort((a, b) => a.path.localeCompare(b.path));
  }
  function filter(document, entries, classify, showGenerated) {
    // Restore first so rule changes and paths removed by SPA navigation recover.
    restore(document);
    for (const entry of entries) {
      if (showGenerated || classify(entry.path, entry.generated) !== "generated") continue;
      for (const card of entry.cards) card.setAttribute(hiddenAttribute, "");
      for (const link of entry.links) {
        // Hide only this row, never a directory containing other files.
        const row = link.closest('[role="treeitem"], li');
        const target = row && row.querySelectorAll('a[href*="#"]').length === 1 &&
          !row.querySelector('[role="group"], ul') ? row : link;
        target.setAttribute(hiddenAttribute, "");
      }
    }
  }
  function restore(document) {
    document.querySelectorAll(`[${hiddenAttribute}]`).forEach(element => element.removeAttribute(hiddenAttribute));
  }
  function navigate(document, entry) {
    const link = [...entry.links].find(element => element.isConnected);
    if (link) { link.click(); return; }
    const card = [...entry.cards].find(element => element.isConnected);
    if (!card) return;
    card.scrollIntoView({ block: "start", behavior: "smooth" });
    const anchor = card.id ? card : card.querySelector('[id^="diff-"]');
    if (anchor) document.defaultView.history.replaceState(null, "", `#${encodeURIComponent(anchor.id)}`);
  }
  globalThis.GitHubReviewDOM = { collect, filter, restore, navigate };
})();
