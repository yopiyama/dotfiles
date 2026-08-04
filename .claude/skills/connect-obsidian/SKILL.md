---
name: connect-obsidian
description: Read, write, search, manage, or open files in the user's Obsidian vault via the obs.sh wrapper around the Obsidian CLI. Use this - instead of plain Read/Grep - whenever the user mentions Obsidian, their vault, notes, or daily notes, e.g. 「Obsidian のファイルを読んで」「vault を検索して」「デイリーノートに追記して」「ノートを開いて」. Also covers executing templates and opening notes in the app. Requires the Obsidian app running and obsidian in PATH.
tools: Bash
---

# Obsidian CLI Integration

Obsidian の操作は **`~/.claude/skills/connect-obsidian/scripts/obs.sh` 経由で行う**。`obsidian` コマンドを直に組み立てるのは、obs.sh にサブコマンドが無い操作に限る。Obsidian アプリが起動している必要がある。

> **前提条件**: `obsidian` コマンドが PATH に通っていること。macOS では `/Applications/Obsidian.app/Contents/MacOS` が PATH に含まれている必要がある。

## なぜラッパー経由なのか

素の `obsidian` CLI は引数を間違えても失敗を返さないため、「成功したつもりで別のことが起きている」事故が起きる。実際に踏んだもの:

| 素の CLI の挙動 | 結果 |
| --- | --- |
| 何があっても **常に exit 0**（`Error:` は stdout に出るだけ） | `&&` も `set -e` も効かない。失敗が伝播しない |
| キー無しの位置引数は**黙って無視**される | `obsidian read Notes/a.md` はアクティブファイルを読む。`obsidian create Notes/a.md content=…` は vault ルートに `Untitled.md` を作る |
| `overwrite` 忘れ | 上書きではなく `note 1.md` という別ファイルができる |
| `content=` のリテラル `\n` `\t` | 無条件に実改行・タブへ変換され、本文が化ける |
| Obsidian が忙しいと稀に**空応答** | 成否不明のまま次へ進む |
| `obsidian` は **stdin を飲む** | `while read` のループ内で呼ぶと残りの入力が消える |
| `obsidian help`（サブコマンド無し）を `head` 等の早期 close パイプに繋ぐ | **ハングする** |

obs.sh はこれらを全部塞ぐ。`path=` のキー付けを強制し、成功時の定型出力とパスを突き合わせ、書き込み後は `read` で読み直して内容一致を検証し、空応答はリトライする。CLI の `\n` 変換で化けた場合は vault のファイルへ直接書いて再検証する。**失敗すれば必ず非 0 で落ちて stderr にメッセージを出す。**

## 使い方

```bash
OBS=~/.claude/skills/connect-obsidian/scripts/obs.sh
```

`$OBS --help` でサブコマンド一覧が出る。パスは**必ず vault ルートからの相対パス**を素の値で渡す（`path=` は付けない。付けると弾かれる）。

### 読み取り・調査

```bash
$OBS read <path>                     # ノートを読む。無ければ失敗する
$OBS read-name <name>                # ファイル名で読む（フォルダ・拡張子省略可）
$OBS exists <path>                   # あれば exit 0 / 無ければ exit 1（出力なし）
$OBS info <path>                     # path/size/更新日時などのメタデータ
$OBS ls [folder]                     # ファイル一覧
$OBS folders [folder]                # フォルダ一覧
$OBS search <query> [folder] [limit] # 全文検索（ヒットしたパスの一覧）
$OBS grep <query> [folder] [limit]   # 全文検索（マッチ行のコンテキスト付き）
$OBS frontmatter <path>              # frontmatter を YAML で出力
$OBS vault-path                      # vault のルートパス
```

### 書き込み

本文は**ファイルか stdin で渡す**。`content=` を自分で組み立てない。

```bash
$OBS write <path> <本文ファイル>      # 作成・上書き（書き込み後に検証）
cat body.md | $OBS write <path>       # stdin でも可
$OBS append <path> [src]              # 末尾追記（追記後に検証）
$OBS prepend <path> [src]             # 先頭追記（追記後に検証）
```

長い本文は scratchpad に一時ファイルを書いてそのパスを渡すのが確実。成功すると `書き込み: <path> (CLI)` または `(直接書き込み: …)` と出る。後者は本文にリテラル `\n` `\t` が含まれていて CLI では表現できなかったケースで、内容は検証済みなので問題ない。

### frontmatter のプロパティ

```bash
$OBS prop-get <path> <name>                  # 無ければ exit 1
$OBS prop-set <path> <name> <value> [type]   # 設定後に読み直して検証
$OBS prop-del <path> <name>                  # 元から無くても成功（冪等）
```

`type` は `text|list|number|checkbox|date|datetime`。

ヘッディング配下の一部だけを差し替えたい場合、CLI に patch 相当は無い。`$OBS read` で全文を取り、ローカルで編集して `$OBS write` で書き戻す。

### その他

```bash
$OBS move <path> <to>          # 移動・リネーム
$OBS open <path> [newtab]      # Obsidian で開く
$OBS daily-path                # デイリーノートのパス
$OBS daily-read                # デイリーノートを読む
$OBS daily-append [src]        # デイリーノートに追記
$OBS trash <path>              # ゴミ箱へ移動（allow に無いので確認プロンプトが出る）
$OBS cli-help [subcommand]     # 素の CLI のヘルプ（ハングしない形で出す）
```

## 基本ルール

- ノートを新規作成する場合は `Notes/` フォルダに配置する。vault ルートには置かない
- 仕様を確認したいときは `$OBS cli-help <subcommand>`。**素の `obsidian help` を `head` に繋がない**（ハングする）
- Obsidian 設定の Files and links → Excluded files に含まれるフォルダは、検索だけでなく **Bases の集計からも落ちる**（base ビューが 0 results になる）
- `obsidian delete`（永久削除も可）と `obsidian eval`（任意 JS 実行）は意図的に allow に含めていない。`$OBS trash` も含め、削除は毎回確認プロンプトで実行する
- **フォルダの削除はできない**（CLI に rmdir 相当が無い）。空フォルダが残ったらユーザーに伝えて Obsidian 側か Finder で消してもらう

## obs.sh に無い操作

以下は obs.sh のサブコマンドが無いので素の CLI を使う。その際も**キーを必ず付け、出力を目で確認する**（exit code は信用できない）。

```bash
obsidian tasks todo                    # タスク一覧（tasks / task）
obsidian task ref="<path>:<line>" done # タスクの完了
obsidian template:insert name=<名前>   # テンプレート挿入
obsidian template:read name=<名前> resolve
obsidian create path=<path> template=<名前> overwrite open  # テンプレートから作成
obsidian backlinks path=<path>         # バックリンク
obsidian outline path=<path>           # 見出し一覧
obsidian tags / obsidian bases / obsidian base:query
```

Templater テンプレートへの引数渡し（`arguments` 相当）は CLI では直接サポートされていない。セマンティック検索に相当するコマンドも無いので `$OBS search` / `$OBS grep` で代替する。
