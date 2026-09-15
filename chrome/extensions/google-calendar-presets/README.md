# Google Calendar Presets

Google Calendar のサイドバーにある複数のカレンダーを、プリセット単位でまとめて表示・非表示にする Chrome 拡張です。

## できること

- 任意のカレンダーを複数選んでプリセットとして保存
- プリセットの「表示」「非表示」「切り替え」
- Google Calendar 画面右上に表示されるボタンから切り替え
- 拡張機能のポップアップから切り替え
- アクティブなプリセットを Windows/Linux は `Ctrl + Shift + 9`、macOS は `Ctrl + Shift + 9` で切り替え

## 使い方

1. Chrome で `chrome://extensions/` を開く
2. 「デベロッパーモード」を有効にする
3. 「パッケージ化されていない拡張機能を読み込む」を押し、このディレクトリを選ぶ
4. Google Calendar (`https://calendar.google.com/`) を開く
5. 拡張機能のアイコンを押し、「再読み込み」でカレンダー一覧を取得する
6. カレンダーを選び、名前を付けて保存する

Google Calendar のサイドバーが折りたたまれている場合や、一覧の読み込み前の場合は、サイドバーを展開してから「再読み込み」を押してください。

ショートカットは `chrome://extensions/shortcuts` で変更できます。ショートカット対象は、設定画面のプリセット名の左にあるラジオボタンで選びます。

## 動作の仕組みと制限

Google Calendar API や OAuth は使わず、Calendar のサイドバーにあるネイティブなチェックボックスをクリックします。設定は Chrome の同期ストレージに保存し、カレンダーの予定データやアカウント情報は保存・送信しません。

カレンダーの識別には Calendar の DOM から取得できる識別子を優先し、識別子が取得できない場合はカレンダー名を使います。同名カレンダーが複数ある場合や、Google Calendar の UI が大きく変更された場合は、プリセットの再保存が必要になることがあります。

この拡張は `chrome/extensions` 配下で unpacked として直接読み込むため、`scripts/link.sh` の symlink 対象には追加していません。
