const STORAGE_KEY = 'settings';
const ROOT_ID = 'gcp-root';

function emptySettings() {
  return { version: 1, presets: [], activePresetId: null };
}

async function getSettings() {
  const stored = await chrome.storage.sync.get(STORAGE_KEY);
  const settings = stored[STORAGE_KEY];
  if (!settings || !Array.isArray(settings.presets)) return emptySettings();

  return {
    version: 1,
    presets: settings.presets,
    activePresetId: settings.activePresetId || settings.presets[0]?.id || null
  };
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function normalizeName(value) {
  return String(value || '')
    .normalize('NFKC')
    .replace(/\s+/g, ' ')
    .trim()
    .toLocaleLowerCase();
}

function cleanName(value) {
  return String(value || '')
    .replace(/^\s*(?:selected|unselected|checked|unchecked)\s*[:：-]?\s*/i, '')
    .replace(/^\s*(?:calendar|カレンダー)\s*[:：]\s*/i, '')
    .replace(/\s*[,，]?\s*(?:selected|unselected|選択中|未選択)\s*$/i, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function firstAttribute(element, names) {
  for (const name of names) {
    const value = element.getAttribute(name);
    if (value) return value;
  }
  return '';
}

function calendarKeyFor(element) {
  let current = element;
  for (let depth = 0; current && depth < 8; depth += 1, current = current.parentElement) {
    const explicitId = firstAttribute(current, [
      'data-calendarid',
      'data-calendar-id',
      'data-calendaridvalue'
    ]);
    if (explicitId) return `id:${explicitId}`;

    // Some Calendar builds expose the calendar identifier as data-id on the
    // sidebar row. Avoid short/generic values which are usually UI internals.
    const dataId = current.getAttribute('data-id');
    if (dataId && (dataId.includes('@') || dataId.includes('/') || dataId.length > 12)) {
      return `id:${dataId}`;
    }
  }
  return '';
}

function calendarNameFor(checkbox) {
  const directLabel = firstAttribute(checkbox, ['aria-label', 'data-tooltip', 'title']);
  if (directLabel) return cleanName(directLabel);

  const row = calendarRowFor(checkbox);
  return cleanName(row?.innerText || row?.textContent || '');
}

function calendarRowFor(checkbox) {
  return checkbox.closest('[data-calendarid], [data-calendar-id], label, [role="listitem"]')
    || checkbox.parentElement;
}

function visibleOnScreen(element) {
  if (!element) return false;
  const style = window.getComputedStyle(element);
  if (style.display === 'none' || style.visibility === 'hidden') return false;
  const rect = element.getBoundingClientRect();
  return rect.width > 0 && rect.height > 0;
}

function visibilityFor(checkbox) {
  if (typeof checkbox.checked === 'boolean') return checkbox.checked;

  const ariaChecked = checkbox.getAttribute('aria-checked');
  if (ariaChecked != null) return ariaChecked === 'true';

  const ariaPressed = checkbox.getAttribute('aria-pressed');
  if (ariaPressed != null) return ariaPressed === 'true';

  // aria-checked is used by current Calendar versions. If a future version
  // omits it, the safest fallback is to treat the native control as visible.
  return true;
}

function likelyCalendarCheckbox(checkbox) {
  const row = calendarRowFor(checkbox);
  if (!visibleOnScreen(checkbox) && !visibleOnScreen(row)) return false;
  const name = calendarNameFor(checkbox);
  if (!name || name.length > 180) return false;

  const hasCalendarId = Boolean(calendarKeyFor(checkbox));
  const hasSidebarRow = Boolean(checkbox.closest('[role="listitem"]'));
  let hasCalendarSection = false;
  for (let current = checkbox, depth = 0; current && depth < 8; current = current.parentElement, depth += 1) {
    const label = `${current.getAttribute('aria-label') || ''} ${current.getAttribute('data-tooltip') || ''}`;
    if (/calendar|カレンダー/i.test(label)) {
      hasCalendarSection = true;
      break;
    }
  }
  return hasCalendarId || hasSidebarRow || Boolean(checkbox.getAttribute('data-tooltip'))
    || hasCalendarSection;
}

function readCalendars() {
  // Depending on the Calendar rollout, a sidebar item is either represented
  // by a custom role=checkbox or by a native input nested in a label[data-id].
  const candidates = [...document.querySelectorAll(
    '[role="checkbox"], input[type="checkbox"]'
  )]
    .filter(likelyCalendarCheckbox);
  const byKey = new Map();

  for (const checkbox of candidates) {
    const name = calendarNameFor(checkbox);
    const key = calendarKeyFor(checkbox) || `name:${normalizeName(name)}`;
    if (!name) continue;

    const sameNameKey = [...byKey.keys()].find(existingKey =>
      normalizeName(byKey.get(existingKey).name) === normalizeName(name)
    );
    if (sameNameKey && sameNameKey.startsWith('name:') && !key.startsWith('name:')) {
      byKey.delete(sameNameKey);
    } else if (byKey.has(key) || sameNameKey) {
      continue;
    }

    const row = calendarRowFor(checkbox);
    const colorNode = row?.querySelector('[style*="background-color"]');
    const color = colorNode ? getComputedStyle(colorNode).backgroundColor : '';
    byKey.set(key, {
      key,
      name,
      color,
      visible: visibilityFor(checkbox),
      checkbox
    });
  }

  return [...byKey.values()];
}

function targetMatches(calendar, target) {
  if (target.key && calendar.key === target.key) return true;
  return Boolean(target.name) && normalizeName(calendar.name) === normalizeName(target.name);
}

async function waitForCalendars(timeoutMs = 1800) {
  const startedAt = Date.now();
  let calendars = readCalendars();
  while (calendars.length === 0 && Date.now() - startedAt < timeoutMs) {
    await sleep(150);
    calendars = readCalendars();
  }
  return calendars;
}

async function applyPreset(presetId, mode) {
  const settings = await getSettings();
  const preset = settings.presets.find(({ id }) => id === presetId);
  if (!preset) return { ok: false, message: 'プリセットが見つかりません。' };

  const calendars = await waitForCalendars();
  const targets = preset.calendars || [];
  const matched = calendars.filter(calendar => targets.some(target => targetMatches(calendar, target)));
  const matchedKeys = new Set(matched.map(({ key }) => key));
  const missing = targets.filter(target => !matched.some(calendar => targetMatches(calendar, target)));

  if (matched.length === 0) {
    return {
      ok: false,
      message: '対象カレンダーが見つかりません。サイドバーで対象カレンダーを表示してから設定を更新してください。'
    };
  }

  const allVisible = matched.every(calendar => calendar.visible);
  const desired = mode === 'show' ? true : mode === 'hide' ? false : !allVisible;
  let changed = 0;

  // Re-read after every click because Calendar may replace the sidebar row.
  for (const target of targets) {
    let current = readCalendars().find(calendar =>
      targetMatches(calendar, target) && matchedKeys.has(calendar.key)
    );
    if (!current || current.visible === desired) continue;

    current.checkbox.click();
    changed += 1;
    await sleep(90);
  }

  const action = desired ? '表示' : '非表示';
  const missingSuffix = missing.length > 0 ? `（${missing.length}件は見つかりませんでした）` : '';
  return {
    ok: true,
    message: `${preset.name}：${action} ${changed}件${missingSuffix}`,
    changed,
    desired
  };
}

function ensureRoot() {
  let root = document.getElementById(ROOT_ID);
  if (root) return root;

  root = document.createElement('div');
  root.id = ROOT_ID;
  root.innerHTML = `
    <button class="gcp-trigger" type="button" aria-busy="false">
      <span class="gcp-trigger-icon" aria-hidden="true">◉</span>
      <span class="gcp-trigger-label">カレンダー</span>
    </button>
    <div class="gcp-toast" role="status" aria-live="polite" hidden></div>
  `;
  (document.body || document.documentElement).appendChild(root);

  root.querySelector('.gcp-trigger').addEventListener('click', async event => {
    const button = event.currentTarget;
    if (button.disabled) return;

    let settings;
    try {
      settings = await getSettings();
      const preset = settings.presets.find(({ id }) => id === settings.activePresetId);
      if (!preset) {
        showToast('設定画面でショートカット対象のプリセットを選択してください。');
        return;
      }

      button.disabled = true;
      button.setAttribute('aria-busy', 'true');
      button.querySelector('.gcp-trigger-label').textContent = '切替中…';
      const result = await applyPreset(preset.id, 'toggle');
      showToast(result.message);
    } catch (error) {
      console.error('Could not apply calendar preset:', error);
      showToast('切り替えに失敗しました。Calendar のサイドバーを展開してから再試行してください。');
    } finally {
      button.disabled = false;
      button.setAttribute('aria-busy', 'false');
      renderRoot();
    }
  });

  return root;
}

function showToast(message) {
  const root = document.getElementById(ROOT_ID);
  if (!root) return;
  const toast = root.querySelector('.gcp-toast');
  toast.textContent = message;
  toast.hidden = false;
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => {
    toast.hidden = true;
  }, 3600);
}

async function renderRoot() {
  const root = ensureRoot();
  const settings = await getSettings();
  const triggerLabel = root.querySelector('.gcp-trigger-label');
  const activePreset = settings.presets.find(({ id }) => id === settings.activePresetId);

  triggerLabel.textContent = activePreset ? activePreset.name : 'カレンダープリセット';
  root.querySelector('.gcp-trigger').title = activePreset
    ? `${activePreset.name} を表示・非表示`
    : '設定画面でプリセットを選択してください';
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message.type === 'getCalendars') {
    waitForCalendars().then(calendars => {
      sendResponse({ ok: true, calendars });
    });
    return true;
  }

  if (message.type === 'applyPreset') {
    applyPreset(message.presetId, message.mode || 'toggle')
      .then(result => {
        showToast(result.message);
        sendResponse(result);
      })
      .catch(error => {
        console.error('Could not apply calendar preset:', error);
        const result = {
          ok: false,
          message: '切り替えに失敗しました。Calendar のサイドバーを展開してから再試行してください。'
        };
        showToast(result.message);
        sendResponse(result);
      });
    return true;
  }

  return false;
});

chrome.storage.onChanged.addListener((changes, areaName) => {
  if (areaName === 'sync' && changes[STORAGE_KEY]) renderRoot();
});

renderRoot();
