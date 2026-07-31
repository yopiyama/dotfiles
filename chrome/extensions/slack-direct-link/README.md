# Slack Direct Link (Chrome 拡張)

Slack のパーマリンクを Chrome で開いたときに出る
「アプリへリダイレクトしています / ＜Workspace name＞を立ち上げています」の中間ページをスキップし、
ブラウザ版 Slack を直接開く。

```
https://<team>.slack.com/archives/C02HL39C6H0/p1784279363071809?thread_ts=...
  ↓
https://<team>.slack.com/messages/C02HL39C6H0/p1784279363071809?thread_ts=...&skip_today=1
```

`declarativeNetRequest` の静的ルール (`rules.json`) だけで実現しているので、
background script も content script も無い。ページが読み込まれる前にリクエスト URL 自体を
書き換えるため、中間ページが一瞬表示されることもない。

## インストール

Chrome Web Store には出していないので、unpacked で読み込む。

1. `chrome://extensions` を開く
2. 右上の「デベロッパーモード」を ON
3. 「パッケージ化されていない拡張機能を読み込む」→ このディレクトリを選択

リポジトリのパスを直接参照するので symlink は不要 (`scripts/link.sh` の管理対象外)。
デベロッパーモードで読み込んだ拡張は Chrome 起動時に警告バルーンが出ることがあるが、
バルーンを閉じれば拡張は有効なまま動く。

ルール (`rules.json`) を編集したら `chrome://extensions` で拡張の再読み込みが必要。

## ルールの構成

| id | 対象 | 変換 |
| --- | --- | --- |
| 1 | `skip_today=` を既に含む URL | `allow` (書き換えない) |
| 2 | `/archives/<ch>/<pTs>?<query>` | `/messages/<ch>/<pTs>?<query>&skip_today=1` |
| 3 | `/archives/<ch>/<pTs>` | `/messages/<ch>/<pTs>?skip_today=1` |
| 4 | `/archives/<ch>?<query>` | `/messages/<ch>?<query>&skip_today=1` |
| 5 | `/archives/<ch>` | `/messages/<ch>?skip_today=1` |

- id 1 は最優先 (`priority: 10`) の `allow` ルール。書き換え後の URL が Slack 側で
  再び `/archives/` に転送された場合のリダイレクトループを止めるガード。
- `resourceTypes` は `main_frame` のみ。ブラウザ版 Slack が内部で投げる API リクエストには触らない。
- `main_frame` のナビゲーションに対する redirect はリクエスト先のホスト権限だけで足りる
  (initiator 側の権限は不要) ので、`host_permissions` は `*://*.slack.com/*` のみ。
  Gmail や Slack デスクトップアプリから開いたリンクにも効く。
- `app.slack.com/client/...` 形式のアプリ用ディープリンクは対象外 (`/archives/` を含まないため一致しない)。

## デバッグ

想定どおりに書き換わらないときは、`chrome://extensions` の当該拡張から
「Service Worker」ではなく以下を確認する。

- `chrome://net-export` でリダイレクトの有無を見る
- ルールが登録されているかは DevTools のコンソール (拡張のページ) で
  `chrome.declarativeNetRequest.getEnabledRulesets()` / `getDynamicRules()` を叩く
- どのルールが一致したかを見たい場合は `manifest.json` の `permissions` に
  `declarativeNetRequestFeedback` を追加し、`chrome.declarativeNetRequest.onRuleMatchedDebug` を監視する
  (デベロッパーモードのみ有効)

## 参考

- [chrome.declarativeNetRequest](https://developer.chrome.com/docs/extensions/reference/api/declarativeNetRequest)
- [declarativeNetRequest — MDN (ホスト権限の要件)](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/declarativeNetRequest)
