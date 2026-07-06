# モデル料金とコスト運用リファレンス

従量課金下でのモデル選択・エージェント割り当ての判断材料。料金は変動するため、参照時に確認日が古ければ https://platform.claude.com/docs/en/about-claude/models/overview で更新すること。

## 料金表（確認日: 2026-07-06）

| モデル | エイリアス | Input $/MTok | Output $/MTok | 備考 |
|---|---|---|---|---|
| Fable 5 | `fable` | 10 | 50 | 現行 Main（サブスク提供中） |
| **Opus 4.8** | `opus` | **5** | **25** | 将来の Main。1M コンテキスト標準搭載 |
| Sonnet 5 | `sonnet` | 3 | 15 | |
| Haiku 4.5 | `haiku` | 1 | 5 | |

- **Opus 4.8 は Sonnet 5 の約 1.67 倍**。旧世代 Opus のような 5 倍差ではないため、「Main=Opus、定型作業は sonnet/haiku サーヴァントへ」という分担が価格的に自然に成立する
- プロンプトキャッシュ: cache read は base の **0.1 倍**（90% 節約）、cache write は 1.25 倍（TTL 5 分）/ 2 倍（TTL 1 時間）。会話を細切れに中断せず連続で回す方がキャッシュヒット率が上がる
- fast mode（`/fast`）: 出力が最大 2.5 倍高速になる代わりに **input/output とも 2 倍課金**。急ぎでない限り常用しない
- `effortLevel` はトークン消費に比例する。グローバル設定は `high`（既定の xhigh より 1 段安い意図的な選択）

## エージェントのモデル割り当てと根拠

| Agent | モデル | 根拠 |
|---|---|---|
| hassan-of-serenity (Explorer) | haiku | 読み取り・要約中心。判断は Main が行う |
| jeanne-alter (Verifier) | haiku | コマンド実行と PASS/FAIL 判定のみ |
| sherlock-holmes (Researcher) | sonnet | 検索結果の取捨選択に推論が必要 |
| lancelot (Implementer) | sonnet | 実装品質と価格のバランス |
| da-vinci-chan / gilgamesh (Reviewer) | sonnet | レビュー精度の劣化はバグ流出コストに直結 |

見直しは `/cost` と statusline のセッションコスト実測に基づいて行う。候補:

- sherlock-holmes の sonnet → haiku 降格: 節約幅は小さく（$2/MTok）、調査品質の劣化リスクがあるため保留中
- レビュアーの降格は非推奨（見逃しコストが節約額を上回る）

## Opus 4.8 への切替手順（Fable が利用不能になったら）

1. 並行セッションがないことを確認し、`.claude/settings.json`（リポジトリ側実体）の model 行を変更する:
   - 変更前: `"model": "claude-fable-5[1m]"`
   - 変更後: `"model": "claude-opus-4-8"`（1M コンテキスト標準搭載のため `[1m]` サフィックス不要）
2. `jq . .claude/settings.json` で JSON 妥当性を確認する
3. 新しいセッションを起動し、statusline のモデル表示が Opus になっていることを確認する
4. コミットする: `chore(claude): メインモデルを claude-opus-4-8 に切替`

エージェント定義（`.claude/agents/*.md`）とスキルはエイリアス指定・model-agnostic な記述のため、切替時の変更は不要。
