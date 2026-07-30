# Upstream

このスキルは外部の gist から vendoring したもの。実体をこのリポジトリにコミットして管理する
（submodule にしない。clone 時の `--recursive` 忘れでスキルが消える事故を避けるため）。

- source: https://gist.github.com/k16shikano/fd287c3133457c4fd8f5601d34aa817d
- gist-id: fd287c3133457c4fd8f5601d34aa817d
- file: SKILL.md
- revision: c7189cdc9c2520be50418209834145bdf3a46e97
- fetched-at: 2026-07-30
- license: Unlicense（gist のコメントで著者が明示）

## 取得方法

`gh api` 経由で取得する。`scripts/vendored-skill-diff` も同じ経路で取得して比較するので、
手で更新する場合もこのコマンドを使うこと（取得経路を変えると末尾改行の扱いがずれて差分が汚れる）。

```sh
gh api gists/fd287c3133457c4fd8f5601d34aa817d \
  --jq '.files["SKILL.md"].content' > .claude/skills/japanese-tech-writing/SKILL.md
```

## 更新手順

1. `scripts/vendored-skill-diff` を実行して上流との差分を確認する
2. 取り込む差分なら上記コマンドで取得し直す
3. このファイルの `revision` と `fetched-at` を更新してコミットする

## ローカル差分

なし（上流のまま）。

ローカルで手を入れる場合は、何をなぜ変えたかをここに列挙する。上流と衝突するので、
自分専用の規範を足したいだけなら別スキルに分けるほうがよい。
