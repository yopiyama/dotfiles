// content.js - オーバーレイの表示と操作制御

(function () {
    const OVERLAY_ID = '__url_time_blocker_overlay__';
    const BADGE_ID   = '__url_time_blocker_badge__';
    let pollTimer = null;
    let countdownTimer = null;
    let badgeCountdownTimer = null;

    // ─── バッジ ──────────────────────────────────────────────

    function badgeColorClass(remainingSec, graceSec) {
        const pct = graceSec > 0 ? remainingSec / graceSec : 0;
        if (pct > 0.5) return 'utb-ok';
        if (pct > 0.2) return 'utb-warn';
        return 'utb-danger';
    }

    function fmt(sec) {
        const s = Math.max(0, sec);
        return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
    }

    function createOrUpdateBadge(remainingGraceSec, graceSec) {
        let el = document.getElementById(BADGE_ID);
        if (!el) {
            el = document.createElement('div');
            el.id = BADGE_ID;
            el.innerHTML = '<span class="utb-dot"></span><span class="utb-time"></span>';
            document.documentElement.appendChild(el);
            makeBadgeDraggable(el);
        }

        const refresh = (sec) => {
            el.querySelector('.utb-time').textContent = `残 ${fmt(sec)}`;
            el.className = badgeColorClass(sec, graceSec);
        };

        refresh(remainingGraceSec);

        if (badgeCountdownTimer) clearInterval(badgeCountdownTimer);
        let left = remainingGraceSec;
        badgeCountdownTimer = setInterval(() => {
            left--;
            if (left <= 0) {
                clearInterval(badgeCountdownTimer);
                badgeCountdownTimer = null;
                requestStatus();
                return;
            }
            refresh(left);
        }, 1000);
    }

    function removeBadge() {
        const el = document.getElementById(BADGE_ID);
        if (el) el.remove();
        if (badgeCountdownTimer) {
            clearInterval(badgeCountdownTimer);
            badgeCountdownTimer = null;
        }
    }

    function makeBadgeDraggable(el) {
        el.addEventListener('mousedown', (e) => {
            if (e.button !== 0) return;
            e.preventDefault();
            e.stopPropagation();

            const rect = el.getBoundingClientRect();
            const startX = e.clientX;
            const startY = e.clientY;
            const origRight  = window.innerWidth  - rect.right;
            const origBottom = window.innerHeight - rect.bottom;
            el.style.cursor = 'grabbing !important';

            const onMove = (e) => {
                const r = Math.max(4, origRight  - (e.clientX - startX));
                const b = Math.max(4, origBottom - (e.clientY - startY));
                el.style.setProperty('right',  r + 'px', 'important');
                el.style.setProperty('bottom', b + 'px', 'important');
            };
            const onUp = () => {
                el.style.cursor = '';
                document.removeEventListener('mousemove', onMove, true);
                document.removeEventListener('mouseup',   onUp,   true);
            };

            document.addEventListener('mousemove', onMove, { capture: true });
            document.addEventListener('mouseup',   onUp,   { capture: true });
        });
    }

    // ─── オーバーレイ ─────────────────────────────────────────

    function createOverlay(remainingSec) {
        if (document.getElementById(OVERLAY_ID))
            return updateRemaining(remainingSec);

        const root = document.createElement('div');
        root.id = OVERLAY_ID;
        root.innerHTML = `
      <div class="utb-card">
        <div class="utb-title">⏰ 閲覧時間の上限に達しました</div>
        <div class="utb-msg">
          このページの本日の閲覧時間が設定値を超えたため、表示を制限しています。
        </div>
        <div class="utb-remaining">
          解除まで <span id="utb-remaining">--:--</span>
        </div>
        <div class="utb-actions">
          <button id="utb-back" class="utb-btn utb-primary">← 戻る</button>
          <button id="utb-close" class="utb-btn">タブを閉じる</button>
        </div>
        <div class="utb-foot">URL Time Blocker</div>
      </div>
    `;
        document.documentElement.appendChild(root);

        document.getElementById('utb-back').addEventListener('click', () => {
            if (history.length > 1) history.back();
            else location.href = 'about:blank';
            unblockInteractions();
            unmuteAllSounds();
            document.getElementById(OVERLAY_ID).remove();
        });
        document.getElementById('utb-close').addEventListener('click', () => {
            chrome.runtime.sendMessage({ type: 'closeTab' });
        });

        blockInteractions();
        muteAllSounds();
        updateRemaining(remainingSec);
    }

    function removeOverlay() {
        const el = document.getElementById(OVERLAY_ID);
        if (el) el.remove();
        unblockInteractions();
        unmuteAllSounds();
        if (countdownTimer) {
            clearInterval(countdownTimer);
            countdownTimer = null;
        }
    }

    function updateRemaining(remainingSec) {
        const span = document.getElementById('utb-remaining');
        if (!span) return;
        const render = (sec) => {
            const m = Math.floor(sec / 60);
            const s = sec % 60;
            span.textContent = `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
        };
        render(remainingSec);
        if (countdownTimer) clearInterval(countdownTimer);
        let left = remainingSec;
        countdownTimer = setInterval(() => {
            left--;
            if (left <= 0) {
                clearInterval(countdownTimer);
                countdownTimer = null;
                requestStatus();
                return;
            }
            render(left);
        }, 1000);
    }

    // ─── インタラクション抑制 ─────────────────────────────────

    function preventEvent(e) {
        const overlay = document.getElementById(OVERLAY_ID);
        if (overlay && overlay.contains(e.target)) return;
        e.stopPropagation();
        e.preventDefault();
    }

    const blockedEvents = [
        'wheel', 'touchmove', 'scroll', 'keydown', 'keyup', 'keypress',
        'click', 'mousedown', 'mouseup', 'contextmenu',
    ];

    function blockInteractions() {
        blockedEvents.forEach((ev) =>
            window.addEventListener(ev, preventEvent, { capture: true, passive: false }),
        );
        document.documentElement.style.overflow = 'hidden';
    }

    function unblockInteractions() {
        blockedEvents.forEach((ev) =>
            window.removeEventListener(ev, preventEvent, { capture: true }),
        );
        document.documentElement.style.overflow = '';
    }

    async function muteAllSounds() {
        chrome.runtime.sendMessage({ action: 'MUTE_MY_TAB' });
    }

    async function unmuteAllSounds() {
        chrome.runtime.sendMessage({ action: 'UNMUTE_MY_TAB' });
    }

    // ─── background との通信 ──────────────────────────────────

    let earlyCheckTimer = null;

    function scheduleEarlyCheck(secUntilGrace) {
        if (earlyCheckTimer) clearTimeout(earlyCheckTimer);
        earlyCheckTimer = setTimeout(
            () => {
                earlyCheckTimer = null;
                requestStatus();
            },
            (secUntilGrace + 1) * 1000,
        );
    }

    function requestStatus() {
        try {
            chrome.runtime.sendMessage({ type: 'getStatus' }, (res) => {
                if (chrome.runtime.lastError || !res) return;
                if (!res.matched) {
                    removeOverlay();
                    removeBadge();
                    return;
                }
                if (res.shouldOverlay) {
                    createOverlay(Math.max(1, res.remainingSec));
                    removeBadge();
                } else {
                    removeOverlay();
                    const graceSec = res.rule.graceSec;
                    // remainingGraceSec は background が cycleBase を加味して計算済み
                    const remaining = res.remainingGraceSec ?? Math.max(0, graceSec - res.accumulatedSec);
                    if (remaining > 0 && remaining < 30) {
                        scheduleEarlyCheck(remaining);
                    }
                    createOrUpdateBadge(remaining, graceSec);
                }
            });
        } catch (e) {
            /* ignore */
        }
    }

    chrome.runtime.onMessage.addListener((msg) => {
        if (msg.type !== 'overlay') return;
        const { action, remainingSec } = msg.payload;
        if (action === 'show') {
            createOverlay(remainingSec);
            removeBadge();
        } else if (action === 'hide') {
            removeOverlay();
            requestStatus(); // バッジ再表示のため再確認
        }
    });

    // 初回確認 + 定期確認（30秒）
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => {
            requestStatus();
            pollTimer = setInterval(requestStatus, 30000);
        });
    } else {
        requestStatus();
        pollTimer = setInterval(requestStatus, 30000);
    }
})();
