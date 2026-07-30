const STORAGE = { RULES: 'rules', USAGE: 'usage', BLOCK_STATE: 'blockState' };

function uid() {
  return crypto.randomUUID();
}

function fmtSec(sec) {
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  if (m === 0) return `${s}s`;
  return `${m}m ${s}s`;
}

function todayStr() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
}

async function getRules() {
  const o = await chrome.storage.local.get(STORAGE.RULES);
  return o[STORAGE.RULES] || [];
}
async function setRules(rules) {
  await chrome.storage.local.set({ [STORAGE.RULES]: rules });
}
async function getUsage() {
  const o = await chrome.storage.local.get(STORAGE.USAGE);
  return o[STORAGE.USAGE] || {};
}
async function setUsage(usage) {
  await chrome.storage.local.set({ [STORAGE.USAGE]: usage });
}
async function getBlockState() {
  const o = await chrome.storage.local.get(STORAGE.BLOCK_STATE);
  return o[STORAGE.BLOCK_STATE] || {};
}

function getUsedSec(usage, ruleId) {
  const e = usage[ruleId];
  if (!e || e.date !== todayStr()) return 0;
  return e.accumulatedSec || 0;
}

// 現在のサイクルの使用秒数とブロック状態を返す。
// background.js の checkBlockPeriod と同じ cycleBase ロジックを使用。
function getCycleInfo(rule, usedSec, stateEntry) {
  const today = todayStr();
  if (!stateEntry || stateEntry.date !== today) {
    return { cycleUsedSec: usedSec, blocked: false, remainingBlockSec: 0 };
  }
  const cycleBase = stateEntry.cycleBase ?? 0;
  const cycleUsedSec = Math.max(0, usedSec - cycleBase);
  if (stateEntry.blockStartedAt != null) {
    const elapsed = Math.floor((Date.now() - stateEntry.blockStartedAt) / 1000);
    const remaining = rule.blockSec - elapsed;
    if (remaining > 0) return { cycleUsedSec, blocked: true, remainingBlockSec: remaining };
    // ブロック期間終了済みだがバックグラウンドがまだ cycleBase を更新していない
    return { cycleUsedSec: 0, blocked: false, remainingBlockSec: 0 };
  }
  return { cycleUsedSec, blocked: false, remainingBlockSec: 0 };
}

async function render() {
  const [rules, usage, blockState] = await Promise.all([getRules(), getUsage(), getBlockState()]);
  const list = document.getElementById('rules-list');
  list.innerHTML = '';

  if (rules.length === 0) {
    list.innerHTML = '<div class="empty">ルールが登録されていません</div>';
    return;
  }

  for (const rule of rules) {
    const used = getUsedSec(usage, rule.id);
    const cycle = getCycleInfo(rule, used, blockState[rule.id]);

    let cycleHtml;
    if (cycle.blocked) {
      cycleHtml = `
        <div class="cycle-row cycle-blocked">
          <span class="cycle-badge">ブロック中</span>
          <span class="cycle-time">残り ${fmtSec(cycle.remainingBlockSec)}</span>
        </div>`;
    } else if (rule.graceSec === 0) {
      cycleHtml = `
        <div class="cycle-row">
          <span class="cycle-time cycle-no-grace">猶予なし</span>
        </div>`;
    } else {
      const pct = Math.min(100, Math.round(cycle.cycleUsedSec / rule.graceSec * 100));
      const barColor = pct >= 100 ? '#ff8080' : pct >= 80 ? '#ffc34d' : '#4f7cff';
      cycleHtml = `
        <div class="cycle-row">
          <div class="cycle-bar-wrap">
            <div class="cycle-bar-fill" style="width:${pct}%;background:${barColor}"></div>
          </div>
          <span class="cycle-time">${fmtSec(cycle.cycleUsedSec)} / ${Math.floor(rule.graceSec / 60)}分</span>
        </div>`;
    }

    const item = document.createElement('div');
    item.className = 'rule-item';
    item.innerHTML = `
      <div class="pattern">${escapeHtml(rule.pattern)}</div>
      <div class="meta">
        <span>猶予 ${Math.floor(rule.graceSec/60)}分 / 制限 ${Math.floor(rule.blockSec/60)}分</span>
        <span class="usage">本日 ${fmtSec(used)}</span>
      </div>
      ${cycleHtml}
      <div class="actions">
        <button data-act="toggle" data-id="${rule.id}">${rule.enabled ? '無効化' : '有効化'}</button>
        <button data-act="reset" data-id="${rule.id}">リセット</button>
        <button data-act="delete" data-id="${rule.id}" class="danger">削除</button>
      </div>
    `;
    list.appendChild(item);
  }

  list.querySelectorAll('button').forEach(btn => {
    btn.addEventListener('click', () => handleRuleAction(btn.dataset.act, btn.dataset.id));
  });
}

function escapeHtml(s) {
  return s.replace(/[&<>"']/g, c => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  }[c]));
}

async function handleRuleAction(act, id) {
  const rules = await getRules();
  if (act === 'delete') {
    if (!confirm('このルールを削除しますか？')) return;
    await setRules(rules.filter(r => r.id !== id));
  } else if (act === 'toggle') {
    await setRules(rules.map(r => r.id === id ? { ...r, enabled: !r.enabled } : r));
  } else if (act === 'reset') {
    const [usage, blockState] = await Promise.all([getUsage(), getBlockState()]);
    delete usage[id];
    delete blockState[id];
    await Promise.all([
      setUsage(usage),
      chrome.storage.local.set({ [STORAGE.BLOCK_STATE]: blockState }),
    ]);
  }
  await render();
}

document.getElementById('add-btn').addEventListener('click', async () => {
  const pattern = document.getElementById('new-pattern').value.trim();
  const graceMin = parseInt(document.getElementById('new-grace').value, 10);
  const blockMin = parseInt(document.getElementById('new-block').value, 10);

  if (!pattern) {
    alert('URLパターンを入力してください');
    return;
  }
  try {
    new RegExp(pattern);
  } catch (e) {
    alert('正規表現が不正です: ' + e.message);
    return;
  }
  if (isNaN(graceMin) || graceMin < 0) {
    alert('猶予時間が不正です');
    return;
  }
  if (isNaN(blockMin) || blockMin < 1) {
    alert('制限時間は1分以上にしてください');
    return;
  }

  const rules = await getRules();
  rules.push({
    id: uid(),
    pattern,
    graceSec: graceMin * 60,
    blockSec: blockMin * 60,
    enabled: true
  });
  await setRules(rules);

  document.getElementById('new-pattern').value = '';
  await render();
});

document.getElementById('reset-today').addEventListener('click', async () => {
  if (!confirm('本日の累積時間をすべてリセットしますか？')) return;
  await Promise.all([
    setUsage({}),
    chrome.storage.local.set({ [STORAGE.BLOCK_STATE]: {} }),
  ]);
  await render();
});

render();
