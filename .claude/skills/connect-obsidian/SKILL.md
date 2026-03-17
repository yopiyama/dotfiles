---
name: connect-obsidian
description: Interact with Obsidian vault using the Obsidian CLI via Bash. Use when the user wants to read, write, search, manage, or open files in their Obsidian vault, or execute templates. Obsidian app must be running. Requires obsidian command available in PATH.
tools: Bash
---

# Obsidian CLI Integration

Obsidian の操作を CLI (`obsidian` コマンド) を使って行う。Obsidian アプリが起動している必要がある。

> **前提条件**: `obsidian` コマンドが PATH に通っていること。macOS では `/Applications/Obsidian.app/Contents/MacOS` が PATH に含まれている必要がある。

## 基本ルール

- `vault=<name>` を最初のパラメータに指定することで特定の vault を対象にできる
- `file=<name>` はファイル名での解決（拡張子・フルパス不要）
- `path=<path>` は vault ルートからの正確なパス（例: `folder/note.md`）
- ファイル指定なしの場合はアクティブファイルが対象になる
- 複数行コンテンツは `\n` を使う（例: `content="# Title\n\nBody text"`）
- 出力をクリップボードにコピーするには `--copy` フラグを使う

---

## ファイル操作

### ファイル一覧の取得 (list_vault_files)

```bash
# vault 全体のファイル一覧
obsidian files

# フォルダを指定してファイル一覧
obsidian files folder=<フォルダパス>

# 拡張子でフィルタ
obsidian files ext=md

# ファイル数のみ取得
obsidian files total
```

### ファイルの読み取り (get_vault_file)

```bash
# ファイル名で読み取り（拡張子省略可）
obsidian read file=<ファイル名>

# フルパスで読み取り
obsidian read path=<vault からの相対パス>
```

### ファイルの作成・上書き (create_vault_file)

```bash
# 名前を指定して作成（Obsidian の link 解決ルールでパスが決まる）
obsidian create name=<ファイル名> content=<内容> overwrite

# パスを指定して作成
obsidian create path=<vault からの相対パス> content=<内容> overwrite

# テンプレートを使って作成
obsidian create name=<ファイル名> template=<テンプレート名> overwrite

# 作成後に Obsidian で開く
obsidian create name=<ファイル名> content=<内容> overwrite open
```

> `overwrite` フラグがない場合、同名ファイルが存在するとエラーになる。

### ファイルへの追記 (append_to_vault_file)

```bash
# ファイル末尾に追記
obsidian append file=<ファイル名> content=<追記内容>

# パスを指定して追記
obsidian append path=<vault からの相対パス> content=<追記内容>

# 改行なしで追記
obsidian append file=<ファイル名> content=<内容> inline
```

### ファイルの削除 (delete_vault_file)

```bash
# ファイル名で削除（ゴミ箱に移動）
obsidian delete file=<ファイル名>

# パスを指定して削除
obsidian delete path=<vault からの相対パス>

# 完全削除（ゴミ箱に移動しない）
obsidian delete file=<ファイル名> permanent
```

### ファイルの部分編集 (patch_vault_file)

CLI にはヘッディング・ブロックを直接ターゲットにした patch コマンドはない。操作の種類によって以下のアプローチを使う。

**フロントマターのプロパティ編集:**
```bash
# プロパティを設定
obsidian property:set name=<プロパティ名> value=<値> file=<ファイル名>

# プロパティの型を指定（text|list|number|checkbox|date|datetime）
obsidian property:set name=<プロパティ名> value=<値> type=<型> file=<ファイル名>

# プロパティを削除
obsidian property:remove name=<プロパティ名> file=<ファイル名>

# プロパティを読み取り
obsidian property:read name=<プロパティ名> file=<ファイル名>
```

**ヘッディング・ブロック以下への追記:**
```bash
# ファイル末尾への追記で代替
obsidian append file=<ファイル名> content=<内容>

# または先頭に追記
obsidian prepend file=<ファイル名> content=<内容>
```

**ヘッディング配下の特定セクションを置換する場合:**
```bash
# 1. ファイルの内容を読み取り
content=$(obsidian read file=<ファイル名>)

# 2. bash/awk/python でセクションを編集してファイルに保存
# 3. 上書き保存
obsidian create path=<vault からの相対パス> content="<編集後の内容>" overwrite
```

---

## アクティブファイル操作

### アクティブファイルの読み取り (get_active_file)

```bash
# アクティブファイルの内容を読み取り
obsidian read

# アクティブファイルのメタデータ（パス・サイズ・更新日時）を確認
obsidian file
```

### アクティブファイルへの追記 (append_to_active_file)

```bash
obsidian append content=<追記内容>

# 改行なしで追記
obsidian append content=<内容> inline
```

### アクティブファイルの削除 (delete_active_file)

```bash
obsidian delete
```

### アクティブファイルの部分編集 (patch_active_file)

patch_vault_file と同じアプローチを使う。ファイルパラメータを省略するだけ。

```bash
# フロントマターのプロパティ設定
obsidian property:set name=<プロパティ名> value=<値>

# 末尾追記
obsidian append content=<内容>

# 先頭追記
obsidian prepend content=<内容>
```

### アクティブファイルの全体更新 (update_active_file)

```bash
# 1. アクティブファイルのパスを取得
path=$(obsidian file | grep '^path' | awk '{print $2}')

# 2. 内容を上書き
obsidian create path="$path" content="<新しい内容>" overwrite
```

---

## 検索

### テキスト検索 (search_vault_simple)

```bash
# シンプルな全文検索（マッチしたファイルパスを返す）
obsidian search query=<検索テキスト>

# マッチした行のコンテキスト付きで検索
obsidian search:context query=<検索テキスト>

# フォルダを限定して検索
obsidian search query=<検索テキスト> path=<フォルダパス>

# 最大件数を指定
obsidian search query=<検索テキスト> limit=<件数>

# 大文字小文字を区別
obsidian search query=<検索テキスト> case

# JSON 形式で出力
obsidian search query=<検索テキスト> format=json
```

### クエリ検索 (search_vault / Dataview)

```bash
# Dataview DQL に相当する検索は JavaScript eval で実行
obsidian eval code="const files = app.vault.getMarkdownFiles(); return files.map(f => f.path).join('\n')"

# タグでフィルタする場合の例
obsidian eval code="app.metadataCache.getCachedFiles().filter(p => { const c = app.metadataCache.getCache(p); return c?.tags?.some(t => t.tag === '#<タグ名>'); }).join('\n')"
```

> **注意**: セマンティック検索 (search_vault_smart) に相当する CLI コマンドはない。テキスト検索 (`obsidian search`) で代替する。

---

## Obsidian でファイルを開く (show_file_in_obsidian)

```bash
# ファイルを Obsidian で開く
obsidian open file=<ファイル名>

# パスを指定して開く
obsidian open path=<vault からの相対パス>

# 新しいタブで開く
obsidian open file=<ファイル名> newtab
```

---

## テンプレートの実行 (execute_template)

```bash
# テンプレートを使って新しいファイルを作成
obsidian create path=<作成先パス> template=<テンプレート名> overwrite open

# アクティブファイルにテンプレートを挿入
obsidian template:insert name=<テンプレート名>

# テンプレートの内容を読み取り（変数展開あり）
obsidian template:read name=<テンプレート名> resolve
```

> **注意**: Templater テンプレートへの引数渡し (`arguments` パラメータ相当) は CLI では直接サポートされていない。`eval` コマンドで Templater API を呼び出すか、テンプレートを事前に作成しておく必要がある。

---

## サーバー情報の確認 (get_server_info)

```bash
# Obsidian のバージョン確認
obsidian version

# vault 情報の確認
obsidian vault
```

---

## デイリーノート操作

```bash
# デイリーノートを開く
obsidian daily

# デイリーノートの内容を読み取り
obsidian daily:read

# デイリーノートに追記
obsidian daily:append content=<内容>

# デイリーノートの先頭に追記
obsidian daily:prepend content=<内容>

# デイリーノートのパスを取得
obsidian daily:path
```

---

## タスク操作

```bash
# vault 全体のタスク一覧
obsidian tasks

# 未完了タスクのみ
obsidian tasks todo

# 完了タスクのみ
obsidian tasks done

# 特定ファイルのタスク
obsidian tasks file=<ファイル名>

# デイリーノートのタスク
obsidian tasks daily

# タスクの完了をトグル（ファイルパス:行番号 で指定）
obsidian task ref="<ファイルパス>:<行番号>" toggle

# タスクを完了にする
obsidian task file=<ファイル名> line=<行番号> done
```

---

## 権限設定

このスキルを使うには `.claude/settings.json` の `permissions.allow` に以下を追加する:

```json
"Bash(obsidian:*)"
```
