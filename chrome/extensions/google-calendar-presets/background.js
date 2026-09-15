const STORAGE_KEY = 'settings';

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

async function getActiveCalendarTab() {
  const tabs = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  const tab = tabs[0];
  if (!tab?.id || !/^https:\/\/calendar\.google\.com(?:\/|$)/i.test(tab.url || '')) {
    return null;
  }
  return tab;
}

async function sendToActiveCalendar(message) {
  const tab = await getActiveCalendarTab();
  if (!tab) return { ok: false, message: 'Google Calendar のタブを開いてください。' };

  try {
    return await chrome.tabs.sendMessage(tab.id, message);
  } catch (error) {
    // The tab may have been open before this unpacked extension was loaded.
    // Inject the same files used by content_scripts so the first popup click
    // does not require a manual page reload.
    try {
      await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ['content.js'] });
      await chrome.scripting.insertCSS({ target: { tabId: tab.id }, files: ['content.css'] });
      return await chrome.tabs.sendMessage(tab.id, message);
    } catch (injectionError) {
      console.error('Could not connect to Google Calendar:', injectionError);
      return {
        ok: false,
        message: 'Google Calendar に接続できません。ページを再読み込みしてから、もう一度試してください。'
      };
    }
  }
}

chrome.commands.onCommand.addListener(async (command) => {
  if (command !== 'toggle-active-preset') return;

  const settings = await getSettings();
  const preset = settings.presets.find(({ id }) => id === settings.activePresetId);
  if (!preset) return;

  await sendToActiveCalendar({
    type: 'applyPreset',
    presetId: preset.id,
    mode: 'toggle'
  });
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message.type === 'openOptions') {
    chrome.runtime.openOptionsPage();
    sendResponse({ ok: true });
    return false;
  }

  if (message.type === 'applyPresetFromPopup') {
    sendToActiveCalendar({
      type: 'applyPreset',
      presetId: message.presetId,
      mode: message.mode || 'toggle'
    }).then(sendResponse);
    return true;
  }

  if (message.type === 'getCalendarsFromPopup') {
    sendToActiveCalendar({ type: 'getCalendars' }).then(sendResponse);
    return true;
  }

  return false;
});
