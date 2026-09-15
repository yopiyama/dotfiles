const STORAGE_KEY = 'settings';

const state = {
  settings: { version: 1, presets: [], activePresetId: null },
  calendars: [],
  editingPresetId: null,
  selectedKeysBeforeLoad: new Set(),
  activeTab: null
};

function uid() {
  return crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`;
}

function normalizeSettings(settings) {
  const presets = Array.isArray(settings?.presets)
    ? settings.presets.map(preset => ({
        id: String(preset.id || uid()),
        name: String(preset.name || '名称未設定'),
        calendars: Array.isArray(preset.calendars)
          ? preset.calendars
              .filter(calendar => calendar && (calendar.key || calendar.name))
              .map(calendar => ({
                key: String(calendar.key || ''),
                name: String(calendar.name || calendar.key || '')
              }))
          : []
      })).filter(preset => preset.calendars.length > 0)
    : [];
  const activePresetId = presets.some(preset => preset.id === settings?.activePresetId)
    ? settings.activePresetId
    : presets[0]?.id || null;
  return { version: 1, presets, activePresetId };
}

async function loadSettings() {
  const stored = await chrome.storage.sync.get(STORAGE_KEY);
  state.settings = normalizeSettings(stored[STORAGE_KEY]);
}

async function saveSettings() {
  state.settings = normalizeSettings(state.settings);
  await chrome.storage.sync.set({ [STORAGE_KEY]: state.settings });
}

function isCalendarTab(tab) {
  return /^https:\/\/calendar\.google\.com(?:\/|$)/i.test(tab?.url || '');
}

async function findCalendarTab() {
  const tabs = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  return tabs[0] || null;
}

function setStatus(message, isError = false) {
  const status = document.getElementById('calendar-status');
  status.textContent = message;
  status.classList.toggle('error', isError);
}

function selectedKeys() {
  return new Set(
    [...document.querySelectorAll('#calendar-list input[type="checkbox"]:checked')]
      .map(input => input.dataset.key)
  );
}

function renderCalendarList() {
  const list = document.getElementById('calendar-list');
  list.innerHTML = '';

  const selected = state.selectedKeysBeforeLoad;
  for (const calendar of state.calendars) {
    const label = document.createElement('label');
    label.className = 'calendar-option';

    const input = document.createElement('input');
    input.type = 'checkbox';
    input.dataset.key = calendar.key;
    input.checked = selected.has(calendar.key);
    input.addEventListener('change', renderSelectedSummary);

    const dot = document.createElement('span');
    dot.className = 'calendar-dot';
    if (calendar.color) dot.style.backgroundColor = calendar.color;

    const name = document.createElement('span');
    name.className = 'calendar-option-name';
    name.textContent = calendar.name;
    name.title = `${calendar.name}（${calendar.visible ? '表示中' : '非表示'}）`;

    label.append(input, dot, name);
    list.appendChild(label);
  }
  renderSelectedSummary();
}

async function loadCalendars() {
  // Keep the user's current choices when the Calendar list is fetched again.
  // This is especially useful after expanding another sidebar section.
  if (document.querySelector('#calendar-list input[type="checkbox"]')) {
    state.selectedKeysBeforeLoad = selectedKeys();
  }

  setStatus('カレンダー一覧を読み込んでいます…');
  try {
    state.activeTab = await findCalendarTab();
    if (!isCalendarTab(state.activeTab)) {
      state.calendars = [];
      renderCalendarList();
      setStatus('Google Calendar のタブを開いてから「再読み込み」を押してください。', true);
      return;
    }

    // Ask the service worker so it can inject the content script when the
    // Calendar tab was already open before the extension was loaded.
    const response = await chrome.runtime.sendMessage({ type: 'getCalendarsFromPopup' });
    if (!response?.ok) throw new Error(response?.message || '取得できませんでした');
    state.calendars = response.calendars || [];
    renderCalendarList();
    setStatus(state.calendars.length
      ? `${state.calendars.length}件のカレンダーを取得しました。`
      : 'カレンダーが見つかりません。サイドバーを展開して再読み込みしてください。', !state.calendars.length);
  } catch (error) {
    console.error('Could not load calendars:', error);
    state.calendars = [];
    renderCalendarList();
    setStatus('Google Calendar を再読み込みしてから、もう一度試してください。', true);
  }
}

function renderSelectedSummary() {
  const selected = selectedKeys();
  const summary = document.getElementById('selected-summary');
  summary.textContent = selected.size
    ? `${selected.size}件のカレンダーを選択中`
    : 'カレンダーを選択してください。';
}

function beginCreate() {
  state.editingPresetId = null;
  state.selectedKeysBeforeLoad = new Set();
  document.getElementById('editor-title').textContent = '新しいプリセット';
  document.getElementById('preset-name').value = '';
  document.getElementById('save-preset').textContent = '保存';
  document.getElementById('cancel-edit').hidden = true;
  renderCalendarList();
}

function beginEdit(presetId) {
  const preset = state.settings.presets.find(({ id }) => id === presetId);
  if (!preset) return;
  state.editingPresetId = presetId;
  state.selectedKeysBeforeLoad = new Set(preset.calendars.map(calendar => calendar.key));
  document.getElementById('editor-title').textContent = 'プリセットを編集';
  document.getElementById('preset-name').value = preset.name;
  document.getElementById('save-preset').textContent = '更新';
  document.getElementById('cancel-edit').hidden = false;
  renderCalendarList();
  document.getElementById('preset-name').focus();
}

function renderPresets() {
  const list = document.getElementById('preset-list');
  list.innerHTML = '';

  for (const preset of state.settings.presets) {
    const item = document.createElement('article');
    item.className = 'preset-item';

    const main = document.createElement('div');
    main.className = 'preset-main';

    const radioLabel = document.createElement('label');
    radioLabel.className = 'preset-radio';
    const radio = document.createElement('input');
    radio.type = 'radio';
    radio.name = 'active-preset';
    radio.checked = preset.id === state.settings.activePresetId;
    radio.title = 'ショートカットで切り替えるプリセットにする';
    radio.addEventListener('change', async () => {
      state.settings.activePresetId = preset.id;
      await saveSettings();
      renderPresets();
    });
    const title = document.createElement('span');
    title.textContent = preset.name;
    radioLabel.append(radio, title);

    const count = document.createElement('span');
    count.className = 'shortcut-hint';
    count.textContent = `${preset.calendars.length}件`;
    main.append(radioLabel, count);

    const targets = document.createElement('p');
    targets.className = 'preset-targets';
    targets.textContent = preset.calendars.map(calendar => calendar.name).join('、');

    const actions = document.createElement('div');
    actions.className = 'preset-actions';
    addPresetAction(actions, '表示', 'show', preset.id);
    addPresetAction(actions, '非表示', 'hide', preset.id);
    addPresetAction(actions, '切り替え', 'toggle', preset.id);
    addPresetAction(actions, '編集', 'edit', preset.id);
    addPresetAction(actions, '削除', 'delete', preset.id, true);

    item.append(main, targets, actions);
    list.appendChild(item);
  }
}

function addPresetAction(container, label, action, presetId, danger = false) {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = `preset-action${danger ? ' danger' : ''}`;
  button.textContent = label;
  button.addEventListener('click', () => handlePresetAction(action, presetId));
  container.appendChild(button);
}

async function handlePresetAction(action, presetId) {
  if (action === 'edit') {
    beginEdit(presetId);
    return;
  }

  if (action === 'delete') {
    const preset = state.settings.presets.find(({ id }) => id === presetId);
    if (!preset || !confirm(`「${preset.name}」を削除しますか？`)) return;
    state.settings.presets = state.settings.presets.filter(({ id }) => id !== presetId);
    if (state.settings.activePresetId === presetId) {
      state.settings.activePresetId = state.settings.presets[0]?.id || null;
    }
    await saveSettings();
    if (state.editingPresetId === presetId) beginCreate();
    renderPresets();
    return;
  }

  const activeTab = await findCalendarTab();
  if (!isCalendarTab(activeTab)) {
    alert('Google Calendar のタブを開いてから実行してください。');
    return;
  }

  try {
    const result = await chrome.runtime.sendMessage({
      type: 'applyPresetFromPopup',
      presetId,
      mode: action
    });
    if (!result?.ok) alert(result?.message || '切り替えに失敗しました。');
  } catch (error) {
    alert('Google Calendar を再読み込みしてから、もう一度試してください。');
  }
}

async function savePresetFromForm() {
  const name = document.getElementById('preset-name').value.trim();
  const keys = selectedKeys();
  if (!name) {
    alert('プリセット名を入力してください。');
    return;
  }
  if (!keys.size) {
    alert('カレンダーを1件以上選択してください。');
    return;
  }

  const calendars = state.calendars
    .filter(calendar => keys.has(calendar.key))
    .map(calendar => ({ key: calendar.key, name: calendar.name }));

  if (state.editingPresetId) {
    state.settings.presets = state.settings.presets.map(preset => preset.id === state.editingPresetId
      ? { ...preset, name, calendars }
      : preset);
  } else {
    const preset = { id: uid(), name, calendars };
    state.settings.presets.push(preset);
    if (!state.settings.activePresetId) state.settings.activePresetId = preset.id;
  }

  await saveSettings();
  renderPresets();
  beginCreate();
  setStatus(`${name} を保存しました。`);
}

document.getElementById('reload-calendars').addEventListener('click', loadCalendars);
document.getElementById('select-all').addEventListener('click', () => {
  state.selectedKeysBeforeLoad = new Set(state.calendars.map(calendar => calendar.key));
  renderCalendarList();
});
document.getElementById('clear-all').addEventListener('click', () => {
  state.selectedKeysBeforeLoad = new Set();
  renderCalendarList();
});
document.getElementById('save-preset').addEventListener('click', savePresetFromForm);
document.getElementById('cancel-edit').addEventListener('click', beginCreate);
document.getElementById('open-settings')?.addEventListener('click', () => chrome.runtime.openOptionsPage());

async function init() {
  await loadSettings();
  renderPresets();
  await loadCalendars();
}

init();
