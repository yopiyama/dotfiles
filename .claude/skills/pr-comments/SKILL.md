---
name: pr-comments
description: "GitHub PR のレビューコメントの洗い出しとタスク化、および対応状況の更新。固定スクリプトで reviews / review threads / issue comments をまとめて取得し、分類して Obsidian のタスクノートに書き出す。「PR コメントをリストアップして」「レビューコメントをタスク化して」「PR の指摘を洗い出して」「対応状況を更新して」「ステータスを同期して」と言われたときに起動。"
allowed-tools: Bash(~/.claude/skills/pr-comments/scripts/fetch-pr-comments.sh:*), Bash(~/.claude/skills/pr-comments/scripts/pr-task-notes.sh:*), Bash(~/.claude/skills/connect-obsidian/scripts/obs.sh:*), Bash(gh pr view:*), Bash(git rev-parse:*), Bash(date:*)
---

# PR Comments — レビューコメントの洗い出しとタスク化

GitHub PR に付いたコメントを固定スクリプトで一括取得し、分類・一覧化して Obsidian のタスクノートに書き出す。

**コマンドをその場で組み立てないこと。** 2 本の固定スクリプトを使う:

- `~/.claude/skills/pr-comments/scripts/fetch-pr-comments.sh` … PR コメント取得（以下 `fetch-pr-comments.sh` と略記）
- `~/.claude/skills/pr-comments/scripts/pr-task-notes.sh` … タスクノート操作（以下 `pr-task-notes.sh` と略記）

**実行するときは上のフルパスをそのまま書く。変数に入れて呼ばない。** `NOTES=<パス>` と代入して `$NOTES list ...` のように呼ぶと、コマンド文字列の先頭が `NOTES=` になって settings.json の allow パターン（`Bash(~/.claude/skills/pr-comments/scripts/pr-task-notes.sh:*)`）に一致せず、毎回パーミッション確認が出る。

`gh api` + インライン Python の組み立ては禁止（毎回承認が必要になる）。Obsidian への書き込みも `obsidian create` を直に叩かず `pr-task-notes.sh` 経由で行う（パス組み立て・連番採番・ファイル名維持・書き込み検証が入る）。`pr-task-notes.sh --help` でサブコマンド一覧が出る。

## 手順

### 1. コメント取得

```bash
fetch-pr-comments.sh [PR番号 | PR URL] [オプション]
```

- 引数省略時はカレントブランチの PR を自動解決する
- ユーザーが「このレビュー以降」と URL を貼った場合、`#pullrequestreview-<ID>` の ID を `--since <ID>` に渡す（その review 自身を含む）。日時指定なら ISO8601 も可
- 解決済み (resolved) スレッドはデフォルトで除外される。全件見たいと言われたら `--include-resolved`
- 出力はデフォルト JSON。`--format md` で人間向け Markdown

### 2. 分類して一覧提示

タスク化の前に、必ず一覧をユーザーに提示する。

- コメント本文の先頭ラベル（`[IMO]` `[ASK]` `[NITS]` `[WANT]` `[Tweet]` `[質問]` など）を拾って分類する。ラベルが無ければ内容から «要修正 / 要回答 / 要議論 / 対応不要» を推定する
- 各項目は「指摘者 / `path:line` / ラベル / 一行要約」で提示。「対応不要」とスレッド内で明言されているものはその旨を付記する
- スレッドに返信が付いている場合は最新の議論状態を要約に反映する

### 3. Obsidian タスクノートへ書き出し

保存先は親ノート + 子ノートの 2 層構造:

```
ClaudeCode/<プロジェクト名>/Tasks/
├── PR-<PR番号>.md        ← 親: PR 情報 + Bases ステータスビュー
└── PR-<PR番号>/          ← 子: 1 スレッド = 1 ノート
    ├── 01_<短い要約>.md
    └── 02_<短い要約>.md
```

- プロジェクト名は `--project <name>` で渡す（対象リポジトリの名前。dotfiles ではなく PR のリポジトリ）。省略するとカレントリポジトリ名になる
- 書き込みは `pr-task-notes.sh` で行う。素の Write も `obsidian create` も使わない
- ステータスは子ノートの frontmatter（`status` / `memo`）が唯一の正。親ノートは Bases がそれを自動集計するだけで、親側に手動のステータスリストは持たない

**既存の子ノートがあるスレッドは先に `pr-task-notes.sh read` で読み、手書きの追記（補足・回答案）とユーザーが変更した `status` / `memo` を保持したままマージする**（`put` は上書きなので無断で潰さない）。

書き出しの流れ:

```bash
# 親ノート（Bases ビュー入り。この定型は毎回スクリプトが生成する）
pr-task-notes.sh --project <名前> init <PR番号> --url <PR URL> --repo <owner/name> \
       --title '<PR タイトル>' [--scope '<--since を使った場合はその範囲>']

# 既存の子ノートを確認（index / path / comment_url / status / memo の TSV）
pr-task-notes.sh --project <名前> list <PR番号>

# 次に振る連番
pr-task-notes.sh --project <名前> next-index <PR番号>

# 子ノートを書く。本文は scratchpad に書いてから渡す
pr-task-notes.sh --project <名前> put <PR番号> <連番> '<短い要約>' <本文ファイル>

# ステータス更新（status / memo / updated をまとめて設定）
pr-task-notes.sh --project <名前> set-status <PR番号> <連番> <status> ['<memo>']

# 既存の子ノートを読む（マージ前に必ず）
pr-task-notes.sh --project <名前> read <PR番号> <連番>

# 親ノートを開く
pr-task-notes.sh --project <名前> open <PR番号>
```

`set-status` の `<status>` は短いキーで渡す（絵文字を手打ちしない。ブレると親の base の groupBy が崩れる）:
`ready` = 🟢 着手可能 / `waiting` = 🟡 返信待ち / `local` = 🔵 手元では対応済み / `hold` = ⏸️ 保留 / `done` = ✅ 完了

`put` は**その連番の既存ノートがあれば `<短い要約>` を無視して既存ファイル名を維持する**（リンクを壊さないため）。要約が古くなったら本文の見出しだけ直す。

親ノートのフォーマット（`init` が生成する内容。手で組み立てる必要はない）:

````markdown
---
pr: <PR URL>
repo: <owner/name>
updated: <YYYY-MM-DD>
---

# PR #<番号> レビュー対応タスク

PR: <PR URL>
タイトル: <PR タイトル>
対象: <--since を使った場合はその範囲。全件対象なら行ごと省略>

## ステータス

```base
filters:
  and:
    - file.inFolder("ClaudeCode/<プロジェクト名>/Tasks/PR-<番号>")
views:
  - type: table
    name: タスク一覧
    groupBy:
      property: status
      direction: DESC
    order:
      - file.name
      - memo
      - priority
      - author
      - location
    sort:
      - property: file.name
        direction: ASC
```
````

子ノートのフォーマット（1 スレッド = 1 ノート）:

````markdown
---
pr: <PR URL>
status: 🟢 着手可能
memo: <現在状態の短いメモ（何待ちか・どの commit で対応したか）>
label: "[IMO]"
priority: 高
author: "@login"
location: path/file.go:54
comment_url: <スレッド先頭コメントの URL>
updated: <YYYY-MM-DD>
---

# <番号>. <一行要約>

## 指摘コメント

> **@login** (YYYY-MM-DD):
> （コメント本文の全文。要約・省略・改変をしない）

> **@reply-user** (YYYY-MM-DD):
> （スレッドに返信が付いていれば時系列で全文を続ける）

## 該当コード

```diff
（スクリプト出力の diff_hunk。長い場合は指摘行の周辺のみに切り詰めて良い）
```

## 補足

- （Claude の分析・対応の経緯。追記式で日付を付ける）

## 回答案

```
（返信の下書き。投稿したら見出しを「回答案(投稿済み)」に変える）
```
````

ルール:

- 1 スレッド = 1 子ノート。ファイル名は `<ゼロ埋め 2 桁番号>_<短い要約>.md` で、番号は追加順に振る。再取得・更新時も既存の番号・ファイル名を変えない（リンクを壊さないため。要約が古くなっても本文の見出しだけ直す）
- **「指摘コメント」にはコメント本文の全文を必ず原文のまま載せる**（一行要約は見出し・ファイル名用。本文を要約で代替しない。投稿者の意図やコンテキストを欠落させないため）
- 「該当コード」は diff_hunk が取れたスレッドのみ。issue comment などコード位置が無いものは省略
- frontmatter のキー:
  - `location`: 指摘位置 `path:line`（`file` は Bases の `file.*` 名前空間と衝突するので使わない）
  - `comment_url`: スレッド先頭コメントの URL。更新時の突き合わせキーなので必ず入れる
  - `label`: 先頭ラベル。無ければ推定分類（要修正 / 要回答 / 要議論 / 対応不要）を入れる
  - `status` / `memo`: 下記のステータス定義に従う
- ステータスの定義（`status` には絵文字込みの固定文字列を入れる。親の base は groupBy DESC で 🟢 → 🟡 → 🔵 → ✅ → ⏸️ の順に並び、アクション可能なものが上に来る）:
  - `🟢 着手可能`: 未着手または作業中。他者待ちでない
  - `🟡 返信待ち`: 返信・修正を済ませて相手の反応待ち、または相手の回答待ち
  - `🔵 手元では対応済み`: 修正・返信の準備は済んだが push・投稿がまだのもの
  - `⏸️ 保留`: 判断により意図的に先送りしているもの（理由を `memo` に書く）
  - `✅ 完了`: スレッドが resolved、または「対応不要」が確定したもの（対応不要はその旨を `memo` に注記）
- `memo` には現在状態の短いメモ（何待ちか・どの commit で対応したか）を入れ、状態が動くたびに更新する
- 初回作成時は原則 `🟢 着手可能` に置く。「対応不要」とスレッド内で明言されているものは `✅ 完了`、他者への確認依頼など最初から相手待ちのものは `🟡 返信待ち` に置く
- 書き出し後、親ノートのパスをユーザーに伝える（必要なら `pr-task-notes.sh open` で開く）

### 4. 対応状況の更新（再実行時）

「対応状況を更新して」「ステータスを同期して」と言われた場合、または既存タスクノートがある PR に対して再度洗い出しを行う場合はこちら。

1. 旧形式の検出: `pr-task-notes.sh --project <名前> list <PR番号>` が空なのに親ノート（`pr-task-notes.sh parent-path` のパス）がある場合は旧形式（単一ノート）なので、先に下記「旧形式ノートの移行」を行ってから同期に進む
2. `pr-task-notes.sh --project <名前> list <PR番号>` で子ノートを列挙する。index / path / comment_url / status / memo が TSV で出るので、これが突き合わせ表になる
3. `fetch-pr-comments.sh` を `--include-resolved` 付きで再取得し、GitHub 側の最新状態を得る
4. 既存の子ノートは必ず `comment_url` をキーにスレッドと突き合わせる（`path:line` だけでは同じ行に複数スレッドが立つケースを区別できない）
5. 突き合わせたスレッドに新しいコメントが付いていれば、`pr-task-notes.sh read <PR番号> <連番>` で現状を取り、「指摘コメント」末尾に全文を時系列で追記して `pr-task-notes.sh put` で書き戻す。`memo` の更新は `pr-task-notes.sh set-status`（例: `@xxx から返信あり(YYYY-MM-DD)`）。`🟡 返信待ち` の子ノートに相手の返信が付いたら `ready` に戻す
6. 突き合わせたスレッドが resolved になっていれば `pr-task-notes.sh set-status <PR番号> <連番> done` にする
7. GitHub 側がまだ resolved でなくても、ユーザーが手動で `✅ 完了` / `⏸️ 保留` にした子ノートはそのまま維持する（自動で押し戻さない。ユーザーの判断を優先する）
8. 手書きの「補足」「回答案」は消さない。追記のみ行う
9. 新規スレッド・新規コメントは手順 2 の分類基準に従い、次番号の子ノートとして追加する（親ノートの base が自動で拾うので、親の編集は不要）
10. `pr-task-notes.sh init` を再実行して親ノートの `updated` を更新し、変更点（✅ 完了になった件数・新規追加件数・返信が付いた件数）をユーザーに要約して報告する

#### 旧形式ノートの移行

単一ノート時代の `PR-<番号>.md` を検出したら、同期の前に新構造へ分割する。

- 「ステータス概要」+ 番号付きセクション形式の場合:
  - 各 `## <n>. <見出し>` セクションを、同じ番号の子ノート `<ゼロ埋め 2 桁 n>_<短い要約>.md` に移す。「指摘コメント」「該当コード」「補足」「回答案」は見出しレベルを 1 つ上げて（`###` → `##`）そのまま持っていく
  - セクション冒頭の「ファイル / 指摘者 / ラベル / 優先度 / リンク」箇条書きは frontmatter（`location` / `author` / `label` / `priority` / `comment_url`）に変換する
  - ステータス概要での所属グループ → `status`、リンク表示テキストの状態メモ → `memo` に変換する
  - 最後に `pr-task-notes.sh init` で親ノートを新フォーマット（base ビュー入り）に上書きする
- チェックボックス一覧のみのさらに古い形式の場合: `--include-resolved` で全件再取得し、コメント全文から手順 3 のとおり子ノートを組み立てる（チェック済みの項目は `✅ 完了`、行末の commit 等のメモは `memo` へ）
- 移行が終わったら通常の同期（上記手順 2 以降）を続ける

## 注意

- `fetch-pr-comments.sh` は gh CLI の認証を前提とする。失敗したら stderr をそのまま提示する
- ノート本文は scratchpad に一時ファイルとして書いてから `pr-task-notes.sh put <PR番号> <連番> '<要約>' <ファイル>` に渡す。`content=` を自分で組み立てない。書き込み検証（リテラル `\n` を含む本文の直接書き込みフォールバックまで）は `pr-task-notes.sh` の内側で済んでいる
- `pr-task-notes.sh` / `obs.sh` が非 0 で落ちたら**そこで止めて stderr を提示する**。素の `obsidian` は失敗しても exit 0 なので、代わりに直叩きへ迂回すると失敗が見えなくなる
- 親ノートの base ビューが「0 results」になる場合、Obsidian 設定の Files and links → Excluded files に `ClaudeCode` 配下が含まれていないか確認する（除外されたファイルは Bases の集計からも落ちる）
- タスク管理先の変更（TaskCreate / Notion 等）をユーザーが明示した場合のみ、そちらに切り替える
