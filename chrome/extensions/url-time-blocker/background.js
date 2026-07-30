// background.js - 各URLパターンの累積時間を管理する

const STORAGE_KEYS = {
  RULES: 'rules',          // [{id, pattern, graceSec, blockSec, enabled}]
  USAGE: 'usage',          // { ruleId: { date: 'YYYY-MM-DD', accumulatedSec: number } }
  BLOCK_STATE: 'blockState' // { ruleId: { date: 'YYYY-MM-DD', blockStartedAt: number(ms) } }
};

// ---------- activeTracking (chrome.storage.session で永続化) ----------
// MV3 のサービスワーカーはアイドル後に終了されるため、メモリ上の Map は失われる。
// chrome.storage.session はブラウザセッション中はサービスワーカー再起動をまたいで維持される。
// 構造: { [tabId]: { ruleId, startedAt(ms), url } }

async function getActiveTracking() {
  const result = await chrome.storage.session.get('activeTracking');
  return result.activeTracking || {};
}

async function setActiveTracking(tracking) {
  await chrome.storage.session.set({ activeTracking: tracking });
}

// ---------- ユーティリティ ----------
function todayStr() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

async function getRules() {
  const obj = await chrome.storage.local.get(STORAGE_KEYS.RULES);
  return obj[STORAGE_KEYS.RULES] || [];
}

async function getUsage() {
  const obj = await chrome.storage.local.get(STORAGE_KEYS.USAGE);
  return obj[STORAGE_KEYS.USAGE] || {};
}

async function setUsage(usage) {
  await chrome.storage.local.set({ [STORAGE_KEYS.USAGE]: usage });
}

async function getBlockState() {
  const obj = await chrome.storage.local.get(STORAGE_KEYS.BLOCK_STATE);
  return obj[STORAGE_KEYS.BLOCK_STATE] || {};
}

async function setBlockState(state) {
  await chrome.storage.local.set({ [STORAGE_KEYS.BLOCK_STATE]: state });
}

// grace期間を超えた瞬間に blockStartedAt を記録し、壁時計でブロック残り時間を返す。
// タブを閉じていても blockStartedAt からの経過時間でカウントが進む。
// ブロック解除後は cycleBase を更新し、次サイクルの猶予時間を再付与する。
async function checkBlockPeriod(rule, totalAccumulatedSec) {
  const today = todayStr();
  const blockState = await getBlockState();
  const state = blockState[rule.id];

  // cycleBase: 現サイクルの猶予判定の起点となる累積秒数。
  // 初回・日付変わり時は 0、ブロック解除時に totalAccumulatedSec に更新される。
  const cycleBase = (state?.date === today && state?.cycleBase != null) ? state.cycleBase : 0;

  if (totalAccumulatedSec < cycleBase + rule.graceSec) {
    return { blocked: false, remainingSec: 0, cycleBase };
  }

  // 猶予時間超過 → ブロック開始（または前回のブロックが解除済みで新サイクル開始）
  if (!state || state.date !== today || state.blockStartedAt == null) {
    blockState[rule.id] = { date: today, blockStartedAt: Date.now(), cycleBase };
    await setBlockState(blockState);
    return { blocked: true, remainingSec: rule.blockSec, cycleBase };
  }

  const blockElapsedSec = Math.floor((Date.now() - state.blockStartedAt) / 1000);
  if (blockElapsedSec >= rule.blockSec) {
    // ブロック期間終了 → cycleBase を現在の累積時間に更新して次サイクルへ
    blockState[rule.id] = { date: today, blockStartedAt: null, cycleBase: totalAccumulatedSec };
    await setBlockState(blockState);
    return { blocked: false, remainingSec: 0, cycleBase: totalAccumulatedSec };
  }

  return { blocked: true, remainingSec: rule.blockSec - blockElapsedSec, cycleBase };
}

function normalizeUsageEntry(entry) {
  const today = todayStr();
  if (!entry || entry.date !== today) return { date: today, accumulatedSec: 0 };
  return entry;
}

async function findMatchingRule(url) {
  if (!url || !/^https?:/i.test(url)) return null;
  const rules = await getRules();
  for (const rule of rules) {
    if (!rule.enabled) continue;
    try {
      if (new RegExp(rule.pattern).test(url)) return rule;
    } catch (e) {
      console.warn('Invalid regex:', rule.pattern, e);
    }
  }
  return null;
}

// ---------- 計測ロジック ----------
async function flushTabTime(tabId) {
  const tracking = await getActiveTracking();
  const entry = tracking[tabId];
  if (!entry) return;

  const elapsedSec = Math.floor((Date.now() - entry.startedAt) / 1000);
  if (elapsedSec > 0) {
    const usage = await getUsage();
    const usageEntry = normalizeUsageEntry(usage[entry.ruleId]);
    usageEntry.accumulatedSec += elapsedSec;
    usage[entry.ruleId] = usageEntry;
    await setUsage(usage);
  }

  delete tracking[tabId];
  await setActiveTracking(tracking);
}

async function startTracking(tabId, url) {
  // 既存のトラッキングをフラッシュしてから開始する。
  // 呼び出し元が事前に flushTabTime を呼んでいる場合は entry がないので no-op になる。
  await flushTabTime(tabId);

  const rule = await findMatchingRule(url);
  if (!rule) return;

  const tracking = await getActiveTracking();
  tracking[tabId] = { ruleId: rule.id, startedAt: Date.now(), url };
  await setActiveTracking(tracking);

  await maybeNotifyOverlay(tabId, rule);
}

async function maybeNotifyOverlay(tabId, rule) {
  const usage = await getUsage();
  const total = normalizeUsageEntry(usage[rule.id]).accumulatedSec;

  const { blocked, remainingSec } = await checkBlockPeriod(rule, total);
  if (blocked) {
    sendOverlayCommand(tabId, { action: 'show', remainingSec, ruleId: rule.id });
  } else {
    sendOverlayCommand(tabId, { action: 'hide' });
  }
}

function sendOverlayCommand(tabId, payload) {
  chrome.tabs.sendMessage(tabId, { type: 'overlay', payload }).catch(() => {});
}

// ---------- アラーム ----------
// SW 再起動のたびに chrome.alarms.create を呼ぶと既存アラームがキャンセルされ
// タイマーがリセットされる。YouTube Shorts のように頻繁に onUpdated が発火する
// サイトでは SW が連続再起動してアラームが永遠に発火しなくなる。
// → 存在しない場合だけ作成し、インストール・更新時だけ明示的に再作成する。
async function ensureAlarm() {
  const existing = await chrome.alarms.get('tick');
  if (!existing) {
    chrome.alarms.create('tick', { periodInMinutes: 0.5 });
  }
}

// ---------- イベントハンドラ ----------
chrome.tabs.onActivated.addListener(async ({ tabId }) => {
  // 他のタブの計測を停止
  const tracking = await getActiveTracking();
  for (const idStr of Object.keys(tracking)) {
    const id = Number(idStr);
    if (id !== tabId) await flushTabTime(id);
  }
  try {
    const tab = await chrome.tabs.get(tabId);
    if (tab?.url) await startTracking(tabId, tab.url);
  } catch (e) {}
});

chrome.tabs.onUpdated.addListener(async (tabId, changeInfo, tab) => {
  if (changeInfo.status === 'complete') {
    if (tab.active && tab.url) {
      await startTracking(tabId, tab.url);
    } else {
      // 非アクティブタブの場合は flush のみ
      await flushTabTime(tabId);
    }
  } else if (changeInfo.url) {
    if (tab.status === 'complete' && tab.active && tab.url) {
      // SPA (history.pushState 等): status が complete のまま URL 変化 → 即時再開
      await startTracking(tabId, tab.url);
    } else {
      // 通常ナビゲーション: status='loading' → flush のみ、complete イベントで再開
      await flushTabTime(tabId);
    }
  }
});

chrome.tabs.onRemoved.addListener(async (tabId) => {
  await flushTabTime(tabId);
});

chrome.windows.onFocusChanged.addListener(async (windowId) => {
  if (windowId === chrome.windows.WINDOW_ID_NONE) {
    // すべてのウィンドウからフォーカスが外れた → 全タブの計測停止
    const tracking = await getActiveTracking();
    for (const idStr of Object.keys(tracking)) await flushTabTime(Number(idStr));
  } else {
    // フォーカスのあるウィンドウのアクティブタブを再開（startTracking 内で flush する）
    try {
      const [tab] = await chrome.tabs.query({ active: true, windowId });
      if (tab?.url) await startTracking(tab.id, tab.url);
    } catch (e) {}
  }
});

chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name !== 'tick') return;
  const tracking = await getActiveTracking();
  for (const [tabIdStr, entry] of Object.entries(tracking)) {
    const tabId = Number(tabIdStr);
    await flushTabTime(tabId);
    await startTracking(tabId, entry.url);
  }
});

// content scriptからのリクエスト（現在のステータス取得）
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === 'getStatus') {
    (async () => {
      const url = sender.tab?.url;
      if (!url) return sendResponse({ matched: false });
      const rule = await findMatchingRule(url);
      if (!rule) return sendResponse({ matched: false });
      const usage = await getUsage();
      const entry = normalizeUsageEntry(usage[rule.id]);

      // 現在進行中のセッション時間も加算する（ストレージ未フラッシュ分）
      const tracking = await getActiveTracking();
      const tabId = sender.tab?.id;
      const currentSession = tabId != null ? tracking[tabId] : null;
      const currentElapsed = currentSession
        ? Math.floor((Date.now() - currentSession.startedAt) / 1000)
        : 0;

      const total = entry.accumulatedSec + currentElapsed;
      const { blocked, remainingSec, cycleBase } = await checkBlockPeriod(rule, total);
      const remainingGraceSec = blocked ? 0 : Math.max(0, cycleBase + rule.graceSec - total);
      sendResponse({
        matched: true,
        rule,
        accumulatedSec: total,
        shouldOverlay: blocked,
        remainingSec,
        remainingGraceSec
      });
    })();
    return true; // async
  }
  if (msg.type === 'closeTab') {
    if (sender.tab?.id != null) chrome.tabs.remove(sender.tab.id);
    sendResponse({ ok: true });
    return false;
  }
});

chrome.runtime.onStartup.addListener(async () => {
  await ensureAlarm();
  await initActiveTabs();
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.action === 'MUTE_MY_TAB') {
        chrome.tabs.update(sender.tab.id, { muted: true });
        console.log(`Tab ${sender.tab.id} muted via message.`);
    } else if (message.action === "UNMUTE_MY_TAB") {
        chrome.tabs.update(sender.tab.id, { muted: false });
        console.log(`Tab ${sender.tab.id} unmuted via message.`);
    }
});

chrome.runtime.onInstalled.addListener(async () => {
  // インストール・更新時はアラームを作り直して設定を確実に反映する
  await chrome.alarms.clear('tick');
  chrome.alarms.create('tick', { periodInMinutes: 0.5 });
  await initActiveTabs();
});

async function initActiveTabs() {
  const tabs = await chrome.tabs.query({ active: true });
  for (const tab of tabs) {
    if (tab.url) await startTracking(tab.id, tab.url);
  }
}

// モジュール初回ロード時（SW 再起動時）にアラームの存在を確認・補完
ensureAlarm();
