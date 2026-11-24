# GitHub Review Groups

GitHub PR の `/changes`（旧 `/files` も対応）にレビュー用の分類一覧を追加する Chrome 拡張。
ビルド不要の Manifest V3 拡張として、このディレクトリを直接読み込む。

## 導入

1. Chrome で `chrome://extensions/` を開き、「デベロッパーモード」を有効にする。
2. 「パッケージ化されていない拡張機能を読み込む」で、この `chrome/extensions/github-review/` ディレクトリを選ぶ。
3. GitHub の PR の `/changes` を開く。既に開いていたタブは再読み込みする。

ファイルを更新したら `chrome://extensions/` で拡張を再読み込みし、PR のタブも再読み込みする。
`make link` や Nix の適用、npm install は導入に不要。ディレクトリを移動すると Chrome 側で再登録が必要になる。

## 操作

- 標準ファイルツリーの上に **Review groups** を追加する。標準ツリーはそのまま利用できる。
- 標準ツリーを検出できない場合は左下に表示する。見出しをクリックすると折りたためる。
- **定義 → 実装 → テスト → その他** の順で分類し、グループ内はパス順に表示する。
- ファイル名をクリックすると標準ファイルツリーのリンクを通じて該当する差分へ移動する。
- **生成ファイルを表示** は初期 OFF。生成ファイルを分類一覧・標準ファイルツリー・差分本体から非表示にする。
  ON にすると生成ファイルのグループも表示する。非表示の解除は拡張が付けた属性だけを取り除き、GitHub 側の折りたたみやフィルタは維持する。
- **分類設定** で、そのリポジトリのパスルールを変更できる。保存すると開いている PR にも反映する。

差分本体の並べ替えは行わない。Viewed やレビューの入力値も変更しない。
生成ファイルの表示状態は PR のページを移動・再読み込みすると OFF に戻る。

## 分類ルール

判定の優先順は **生成 → 定義 → テスト → 実装 → その他**。
標準ルールは `rules.js` にあり、主に以下を判定する。

| 分類 | 例 |
| --- | --- |
| 生成 | `gen/`、`generated/`、`__generated__/` 配下、`*.pb.go`、`*_pb.ts`、`*.gen.go`、`*.gen.ts`、`*.generated.*`、`*_gen.go`、`*.sql.go`、`*.mock.go`、`*_enumer.go` |
| 定義 | `*.proto`、`*.sql`、`*.graphql`、`*.gql`、`openapi.yaml`・`swagger.yml` などの OpenAPI 定義名 |
| テスト | `*_test.go`、`*.test.*`、`*.spec.*`、`test/`・`tests/`・`__tests__/`・`testutil/`・`testdata/`・`testcase/`・`mock/`・`mocks/` 配下、Python のテスト名 |
| 実装 | Go、TypeScript、JavaScript、Python、Rust などのソース、Lua、CSS、HTML、`*.tmpl`、Shell |
| その他 | どのルールにも一致しないファイル（ドキュメント・設定など） |

パスは大文字・小文字を区別する。`*` は `/` を含まず、`**` は階層をまたぎ、`**/` はルートにも一致する。
例: `**/*.pb.go` はルートとサブディレクトリ両方の `.pb.go` に一致する。
`?` は `/` 以外の 1 文字。否定や brace 展開などは未対応で、その他の文字は文字どおりに扱う。

リポジトリ別設定は各分類の標準ルールを置き換える。空欄ならその分類のパス判定を無効にする。
GitHub の DOM に生成ファイルの明示的な属性・バッジがある場合も生成として扱う。
ファイル本文の `Code generated` コメントの解析や `.gitattributes` の取得は行わない。
SQL のクエリとマイグレーションはともに「定義」とする。
`buf.gen.yaml` は生成ツールの入力設定なので非表示にしない。`.gen` 接尾辞は出力言語の拡張子まで絞って判定する。
手書きの `mock/generate.go` や `*.mock.impl.go` は「テスト」に残し、`mock/` 配下全体を生成物として扱わない。
Terraform、通常の YAML 設定やドキュメントは「その他」、Storybook の `*.stories.tsx` は「実装」のままとする。

`api-schema.yaml` / `api-schema.yml` もパスにかかわらず「定義」とする。
`e2e/runn/`、`e2e/playwright/`、`load-test/scenario/` 配下は「テスト」とする。
`e2e/` 全体は対象にせず、同居するツールのソースは通常の拡張子判定を使う。

社内リポジトリ名・固有パスをコード、テスト、ドキュメントに含めない。
汎用パターンで識別できない生成出力などの個別パスは、「分類設定」から Chrome のローカルストレージに保存する。
保存済みの各分類は標準ルールより優先するため、既存設定を新版に揃える場合は
「分類設定」→「標準ルールを入力」→「保存」を行う（カスタム設定も標準に戻る）。

## 権限と保存

- GitHub の DOM を content script で読み取る。GitHub 内の SPA 遷移にも対応するため `https://github.com/*` を対象とするが、PR の `/changes`・`/files` でだけ UI を追加する。
- GitHub API、PAT、外部通信は使わない。設定画面は content script からのメッセージを受け、service worker が新しいタブで開く。
- `storage` 権限のみ使用。設定は `chrome.storage.local` の `rules:<owner>/<repo>` に保存する。
- ファイル本文やレビュー内容は保存・送信しない。
- GitHub Enterprise の独自ドメインは未対応。

## 検証と制限

開発用テストだけ Node.js と devDependencies を使う。

```sh
cd chrome/extensions/github-review
npm ci --ignore-scripts
npm test
```

分類・パスルールと、jsdom 上で旧 UI / React UI のファイル検出、生成ファイルの表示切り替え、
遅延追加、SPA 遷移時の解除、設定保存を検証する。

公開 PR `hiro-o918/rinkaku#264` の取得 HTML では、旧 UI の 8 ファイルと標準ツリーへのリンクを抽出できることを確認した。
React UI の DOM セレクタは、[Refined GitHub の差分コンテナ検出](https://github.com/refined-github/refined-github/blob/main/source/features/batch-mark-files-as-viewed.tsx)と
[ファイルパス取得](https://github.com/refined-github/refined-github/blob/main/source/features/actionable-pr-view-file.tsx)も参照した。
ログイン済みの実際の Chrome `/changes` 画面での見た目・レビュー操作は未確認。

一覧の件数は DOM から検出した件数であり、PR の総ファイル数とは限らない。
大きい PR や仮想化された画面では、GitHub がまだ DOM に出していないファイルを列挙できない場合がある。
後から差分やツリーが DOM に追加されると再分類する。GitHub の DOM 変更によって検出できなくなった場合は、
標準ファイルツリーを利用できる。拡張を無効化してタブを再読み込みすれば標準表示に戻る。
