---
name: connect-obsidian
description: Read, write, search, manage, or open files in the user's Obsidian vault via the obs.sh wrapper around the Obsidian CLI. Use this - instead of plain Read/Grep - whenever the user mentions Obsidian, their vault, notes, or daily notes, e.g. 「Obsidian のファイルを読んで」「vault を検索して」「デイリーノートに追記して」「ノートを開いて」. Also covers executing templates and opening notes in the app. Requires the Obsidian app running and obsidian in PATH.
tools: Bash
---

# Obsidian CLI Integration

Obsidian の操作は **`~/.claude/skills/connect-obsidian/scripts/obs.sh` 経由で行う**。`obsidian` コマンドを直に組み立てるのは、obs.sh にサブコマンドが無い操作に限る。

> **前提条件**: `obsidian` コマンドが PATH に通っていること（macOS では `/Applications/Obsidian.app/Contents/MacOS`）。ただし本文の読み書きと検索は vault のファイルを直接触るので **Obsidian が起動していなくても動く**。アプリの起動が必要なのは `move` / `trash` / `prop-*` / `open` / `daily-*` だけ。

## 呼び出し方（重要）

**パスを直接書く。変数に入れない。**

```bash
# ✅ これ
~/.claude/skills/connect-obsidian/scripts/obs.sh read "Notes/foo.md"

# ❌ これはダメ（毎回パーミッション確認が出る）
OBS=~/.claude/skills/connect-obsidian/scripts/obs.sh
$OBS read "Notes/foo.md"
```

`OBS=...` + `$OBS` の形はコマンド文字列の先頭が `OBS=` になるため settings.json の allow パターン（`Bash(~/.claude/skills/connect-obsidian/scripts/obs.sh read:*)` 等）に一致せず、**サブコマンドごとに毎回確認プロンプトが出る**。パスの綴りも `~/.claude/...` で固定する（`$HOME/...` や絶対パス、`~/ghq/.../dotfiles/.claude/...` は一致しない）。

同じ理由で、**出力をパイプに繋ぐと確認プロンプトになる**。件数を絞りたいときは `| head` ではなく `search` / `grep` の `limit` 引数を使う。

以下このドキュメントでは紙面のため `obs.sh` と略記するが、実行時は必ず上記のフルパスを書くこと。

## なぜラッパー経由なのか

素の `obsidian` CLI は引数を間違えても失敗を返さず、さらに**本文を渡すと壊す**。実際に踏んだもの:

| 素の CLI の挙動 | 結果 |
| --- | --- |
| `content=` は argv 経由で Chromium の process-singleton ソケットに流れる | **8KB 付近のバッファ境界でマルチバイト文字が分断され、1 文字が U+FFFD 2〜3 個に化ける**。数十 KB では Broken pipe でハングし、vault を開いていない二重起動インスタンスが残る。これで vault の 6 ノートが壊れた |
| `search` / `search:context` | **1.13.4 では全クエリで空を返す**（完全に壊れている）。しかも exit 0 なので「0 件」と区別できない。仮に動いても対象は markdown のみで `.canvas` やファイル名は引っかからない |
| 何があっても **常に exit 0**（`Error:` は stdout に出るだけ） | `&&` も `set -e` も効かない。失敗が伝播しない |
| キー無しの位置引数は**黙って無視**される | `obsidian read Notes/a.md` はアクティブファイルを読む。`obsidian create Notes/a.md content=…` は vault ルートに `Untitled.md` を作る |
| `overwrite` 忘れ | 上書きではなく `note 1.md` という別ファイルができる |
| 大きい出力を `head` 等の**早期 close パイプ**に繋ぐ | **ハングする**（`obsidian read` した大きなノートを `head` に繋ぐと固まる） |
| `obsidian` は **stdin を飲む** | `while read` のループ内で呼ぶと残りの入力が消える |

obs.sh はこれらを塞ぐ。**本文の読み・書き・検索は CLI を通さず vault のファイルへ直接アクセスする**（`cat` なのでパイプに繋いでも安全）。書き込みは同一ディレクトリ内の rename で差し替え、書いたバイト列と読み直したバイト列を突き合わせて検証する。CLI を使う操作では成功時の定型出力とパスを突き合わせ、**失敗すれば必ず非 0 で落ちて stderr にメッセージを出す**。

## 使い方

`obs.sh --help` でサブコマンド一覧が出る。パスは**必ず vault ルートからの相対パス**を素の値で渡す（`path=` は付けない。付けると弾かれる。絶対パスと `..` も弾く）。

### 読み取り・調査

```bash
obs.sh read <path>                       # ノートを読む。無ければ失敗する
obs.sh read-name <name>                  # ファイル名で読む（フォルダ・拡張子省略可）
obs.sh exists <path>                     # あれば exit 0 / 無ければ exit 1（出力なし）
obs.sh info <path>                       # path/size/更新日時
obs.sh ls [folder]                       # ファイル一覧（vault 相対パス・再帰）
obs.sh folders [folder]                  # フォルダ一覧
obs.sh frontmatter <path>                # frontmatter を YAML で出力
obs.sh vault-path                        # vault のルートパス
```

### 検索

```bash
obs.sh search [--all] <query> [folder] [limit]  # ヒットしたパスの一覧
obs.sh grep   [--all] <query> [folder] [limit]  # マッチ行（path:行番号: 行）
```

- **本文とパス名の両方**を見る。`AOBI-970` のようにファイル名にしか出てこない語も引っかかる
- query は**固定文字列・大小無視**（正規表現ではない）。`.canvas` や `.csv` も対象
- `ClaudeCode/*/Conversations/` の会話ログは自動生成されるセッション記録で件数が多いため**既定で除外**し、何件除外したかを stderr に出す。含めたいときは `--all`
- **0 件なら exit 1** で stderr にメッセージを出す（黙って 0 件にならない）
- 正規表現で引きたいときは `obs.sh vault-path` の下で `rg` を直接叩く

### 書き込み

本文は**ファイルか stdin で渡す**。`content=` を自分で組み立てない。

```bash
obs.sh write <path> <本文ファイル>       # 作成・上書き（書き込み後に検証）
cat body.md | obs.sh write <path>        # stdin でも可
obs.sh append <path> [src]               # 末尾追記（追記後に検証）
obs.sh prepend <path> [src]              # 先頭追記（追記後に検証）
```

長い本文は scratchpad に一時ファイルを書いてそのパスを渡すのが確実。成功すると `書き込み: <path> (12345 bytes)` と出る。サイズ上限は無い（数十 KB でも壊れない）。

`append` / `prepend` は既存の全文を読んでローカルで連結し、丸ごと書き直す。既存ノートが無ければ新規作成として扱う。

### frontmatter のプロパティ

```bash
obs.sh prop-get <path> <name>                  # 無ければ exit 1
obs.sh prop-set <path> <name> <value> [type]   # 設定後に読み直して検証
obs.sh prop-del <path> <name>                  # 元から無くても成功（冪等）
```

`type` は `text|list|number|checkbox|date|datetime`。YAML の型付き編集は CLI に任せている（値は短いのでソケットの問題は出ない）。Obsidian の起動が必要。

ヘッディング配下の一部だけを差し替えたい場合、CLI に patch 相当は無い。`obs.sh read` で全文を取り、ローカルで編集して `obs.sh write` で書き戻す。

### 保守

```bash
obs.sh lint [folder]           # U+FFFD（文字化けの痕跡）を含むノートを列挙
```

過去に CLI の `content=` 経由で壊れたノートを洗い出すための診断。文字化けを疑ったときに走らせる。

### その他

```bash
obs.sh move <path> <to>        # 移動・リネーム（リンクも更新される）
obs.sh open <path> [newtab]    # Obsidian で開く
obs.sh daily-path              # デイリーノートのパス
obs.sh daily-read              # デイリーノートを読む
obs.sh daily-append [src]      # デイリーノートに追記
obs.sh trash <path>            # ゴミ箱へ移動（allow に無いので確認プロンプトが出る）
obs.sh cli-help [subcommand]   # 素の CLI のヘルプ（ハングしない形で出す）
```

`daily-append` はその日のノートがまだ無い場合、テンプレート（daily-notes の `template` 設定）を効かせるために実体の作成だけ Obsidian に任せる（ノートが 1 枚開く）。本文はファイルへ直接追記する。

## 基本ルール

- ノートを新規作成する場合は `Notes/` フォルダに配置する。vault ルートには置かない
- 仕様を確認したいときは `obs.sh cli-help <subcommand>`。**素の `obsidian help` を `head` に繋がない**（ハングする）
- **`obsidian create` / `append` / `prepend` / `daily:append` を素で呼んで本文を渡さない**。ソケット境界で本文が壊れる。本文を伴う操作は必ず obs.sh 経由
- Obsidian 設定の Files and links → Excluded files に含まれるフォルダは Obsidian 側の検索と **Bases の集計から落ちる**（base ビューが 0 results になる）。obs.sh の `search` はファイルシステムを直接見るので影響を受けない
- `obsidian delete`（永久削除も可）と `obsidian eval`（任意 JS 実行）は意図的に allow に含めていない。`obs.sh trash` も含め、削除は毎回確認プロンプトで実行する
- **フォルダの削除はできない**（CLI に rmdir 相当が無い）。空フォルダが残ったらユーザーに伝えて Obsidian 側か Finder で消してもらう

## obs.sh に無い操作

以下は obs.sh のサブコマンドが無いので素の CLI を使う。その際も**キーを必ず付け、出力を目で確認する**（exit code は信用できない）。**本文を渡すもの（`content=`）は使わない**。

```bash
obsidian tasks todo                    # タスク一覧（tasks / task）
obsidian task ref="<path>:<line>" done # タスクの完了
obsidian template:insert name=<名前>   # テンプレート挿入
obsidian template:read name=<名前> resolve
obsidian create path=<path> template=<名前> overwrite open  # テンプレートから作成（本文は渡さない）
obsidian backlinks path=<path>         # バックリンク
obsidian outline path=<path>           # 見出し一覧
obsidian tags / obsidian bases / obsidian base:query
```

Templater テンプレートへの引数渡し（`arguments` 相当）は CLI では直接サポートされていない。セマンティック検索に相当するコマンドも無いので `obs.sh search` / `obs.sh grep` で代替する。
