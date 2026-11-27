# DotFiles

This repository manages shell and tool configuration files.
設定は Nix (パッケージと `programs.*`) と `$HOME` へのシンボリックリンクの
二層で適用する。操作の入口は `Makefile` (`make help`)。

## 構成 (二層)

設定の管理は 2 層に分かれており、これは移行途中の暫定ではなく確定した方針。

| 層 | 管理対象 | 適用 |
| --- | --- | --- |
| Nix | パッケージ全般と `programs.*` で書ける設定 (git/lazygit/mise/herdr 等) | `make rebuild` |
| symlink | nvim の lua や zsh など、生の設定ファイルのまま持ちたいもの | `make link` |

**同じパスを両方に管理させないこと。** home-manager は `backupFileExtension = "bak"`
なので、衝突すると symlink が黙って `*.bak` にリネームされ nix store のリンクに
差し替わる。nvim については `programs.neovim.enable` を有効にしないこと
(有効にすると init.lua が home-manager 管理下に入り symlink と衝突する)。
neovim 本体は `home.packages` で入れるだけに留めている。

## Install

```sh
make setup PROFILE=work  # 初回。install-nix → link → rebuild
make apply PROFILE=work  # 通常の設定反映。rebuild → link → Codex 同期
make install-nix # nix 本体のインストール (導入済みなら何もしない)
make link        # symlink 作成 + Homebrew 本体の準備
make link-dry    # 何も変更せず、実行内容だけ表示
make codex-sync  # 共有 Codex 設定だけを ~/.codex/config.toml に反映
make codex-sync-dry # Codex 設定の反映予定だけを表示
make doctor      # 前提コマンドと symlink の状態を確認
```

`make help` で全ターゲットを表示する。

nix 本体は `make install-nix` (公式インストーラ `https://artifacts.nixos.org/nix-installer`)
が入れる。インストーラは sudo と対話確認を求めるので非対話実行はできない。完了しても
起動中のシェルには PATH が通らないため、`rebuild` / `dry-run` は実行前に
`/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh` を読む。新しいシェルでは
`/etc/zshrc` 経由で通るが、`~/.zshenv` に `setopt no_global_rcs` を書いている場合は
読まれないので `.zshenv.sample` のように `path` へ自分で足すこと。

初回は `darwin-rebuild` がまだ無いので、`make rebuild` は flake.lock で固定した
nix-darwin を build してその中の `darwin-rebuild` で activate する。2 回目以降は
PATH 上のものを使う。

symlink 作成の実体は `scripts/link.sh`。単体実行 (`scripts/link.sh`,
`scripts/link.sh --dry-run`) もできる。リンク元はスクリプト自身の場所から
解決するので、リポジトリはどこに clone してもよい。既存の実ファイルは
`*.backup-<timestamp>` にバックアップし、別の場所を指す symlink は張り替える。

リンク対象はファイル単位とディレクトリ単位が混在する (`.claude/hooks` や
`.config/nvim/lua` はディレクトリ丸ごと) ので、管理対象を増やすときは
`scripts/link.sh` の `LINKS` を編集する。
`*.sample` から untracked な実ファイルを bootstrap する仕組みもあり
(`~/.tmux/projects.json` ← `.tmux/projects.json.sample`、`~/.zshenv` ←
`.zshenv.sample`)、既存の場合は触らない — `COPIES` を参照。

Claude 用スキルの実体は `.claude/skills/` に保管しているが、`~/.claude/skills` への
リンクは現在コメントアウトしている。OMP は `~/.codex/skills/` を再利用し、選択した
モデルが Claude でも Codex でも同じスキルを使う。Codex 側が共有するスクリプトの
source はリポジトリ内の実体を直接参照しており、このリンクの有無には依存しない。

### Codex

`.codex/config.shared.toml` は、全端末で揃える Codex の**トップレベル設定**、共有 table、
共有 MCP（`[mcp_servers.<name>]` table）の source of truth である。`make link`（または
`make codex-sync`）は、このファイルにある値と table を `~/.codex/config.toml` へ強制反映する。
同期前の実ファイルは
`config.toml.backup-<timestamp>` に退避する。

Codex Desktop が管理する project trust、UI 状態、マーケットプレイス、プラグイン、MCP の
OAuth・端末内実行パス、認証・履歴・キャッシュは同期対象外であり、ローカルに保持する。
共有対象を増やすときは `.codex/config.shared.toml` にトップレベルの単一行 `key = value`、
共有する table（例: `[tui]`）または `[mcp_servers.<name>]` table を追加する。同期器はその
table と子 table を丸ごと置換し、それ以外の table は保持する。ただし Desktop が `[tui.*]` に
追加する端末固有の UI 状態は保持する。`approval_policy`、`sandbox_mode`、
`default_permissions` などの permission 設定もここで管理できる。意図しない上書きを
避けるため、このファイルに明示した値と table 以外は同期先で保持する。

共有 permission 設定は `:workspace` を継承し、`.git` は読み取り専用のままにする。
worktree の `.git` はディレクトリではなく参照ファイルなので、`.git/index` などを
workspace root 配下の書き込み先として一律に追加すると、Seatbelt の初期化に失敗する。
`git add` / `git commit` などの書き込み操作はサンドボックス外で、次のコマンドルールに従う。

`.codex/rules/default.rules` は、サンドボックス外で実行するコマンドの共有ルールであり、
`make link` が `~/.codex/rules/default.rules` へ symlink する。既存の実ファイルは link
スクリプトの通常どおりバックアップして置き換える。Codex の UI から許可ルールを追加すると
この Git 管理ファイルも更新されるため、内容を確認してコミットする。

`.codex/AGENTS.md` は全端末で共有する Codex のグローバル指示であり、`make link` が
`~/.codex/AGENTS.md` へ symlink する。グローバル指示には全リポジトリで共通する方針だけを置き、
プロジェクト固有の規約は各リポジトリの `AGENTS.md` やスキルで管理する。

Codex のローカルメモリは `[features] memories = true` で有効化する。メモリの実データは
`~/.codex/memories/` にのみ保存し、生成データや秘密情報・端末固有情報を含む可能性があるため
Git 管理・symlink 管理しない。常に守らせるルールは `.codex/AGENTS.md` に置く。

外部配布のグローバルスキルは `agent-skills-nix` で管理する。スキルの配布元・選択・Codex
target は `nix/home-manager/programs/agent-skills.nix`、固定リビジョンは
`nix/nix-darwin/flake.lock` の source of truth である。`make rebuild PROFILE=...` で
`~/.codex/skills/` にスキル単位で symlink されるため、Codex 同梱の `.system` や既存スキルと
衝突しない。追加・更新後は `cd nix/nix-darwin && nix flake update <input>` で lock を
更新する。root に `SKILL.md` だけを置く配布元は `agent-skills-nix` で列挙できないため、
同じ設定内の `home.file` からスキル名ディレクトリへ直接リンクする。

このリポジトリ固有のスキルも同じ設定ファイルから Home Manager で配置する。
`obsidian-safe-ops`、`handoff`、`resume-handoff`、`pr-comments` は Claude 側の検証済み
スクリプトを必要に応じて共有し、外部の Obsidian 形式スキルとは I/O と記法の責務を分ける。

### Oh My Pi (omp)

本体と公式 Home Manager module は `nix/nix-darwin/flake.nix` の `omp` input で
リリースを固定する。設定の source of truth は `nix/home-manager/programs/omp.nix`、
メイン・Advisor・task subagent 共通の指示は `.config/omp/RULES.md`。

```sh
# このリポジトリで実行。私用 Mac は PROFILE=personal にする。
make rebuild PROFILE=work
# 以降は作業対象のプロジェクトで実行
omp
```

起動後、`/login` から利用するプロバイダーへ認証し、`/model` のモデル hub で
default（実装担当）や advisor（レビュー担当）を割り当てる。
Advisor はモデル割り当て後に `/advisor on` で有効化する。`work` の既定モデルは
`settings.modelRoles.default` で管理する。認証情報は共有設定に含めない。

- Claude / Codex の user-level discovery を明示的に有効化し、既存の指示・Skills・MCP
  設定を利用する。各ツールの permission や hooks が同じ意味で動く保証はない。
- 対象サービスの MCP が設定されていれば、未接続でも別の手段へ自動では切り替えない。
  認証が必要なら、まず `/mcp reauth <server>` などの手順を案内する。
  これはエージェントへの作業指示であり、`eval` などの実行権限は変更しない。
- 通常の `omp` は macOS `sandbox-exec` を通す。`.env*`、`*.env`、`id_*`、`*.pem`、
  `*.key` の内容の読み取り・変更を OMP 本体と子プロセスで拒否する。
  起動時の dotenv 読み込みも対象。sandbox を開始できなければ OMP も起動しない。
  ファイル名による保護のため、既に環境変数へ読み込まれた値や別名コピーは保護対象外。
- 書き込み先は起動ディレクトリ配下、`/tmp`（`/private/tmp`）、macOS のユーザー別
  `$TMPDIR`、OMP の動作に必要な `~/.omp` に制限する。
  `~/.omp/permissions.d/obsidian-vault` を設定した場合は、指定した Vault にも書き込める。
  この許可は `obs.sh` に限らず Bash や `eval` にも適用するが、機密ファイル保護は維持する。
  起動ディレクトリと Vault のルート自体は削除・移動できない。ホームやその親からは起動しない。
  `--cwd` や `cd` は書き込み範囲を広げない。範囲外への書き込みは通常のターミナルで行う。
  コミットは公式 OMP の公開 API で登録した `commit` 拡張で行う。本体にはパッチを当てない。
  差分を確認し、依頼されたファイルを `paths` に列挙する。行単位の切り分けはせず、
  ステージ済みと未ステージの変更が混在するファイルや、保護対象は拒否する。
  選択外のステージ内容は維持する。専用ツールは自動承認し、一般の `eval` は都度確認する。
  公式の `/commit` と `eval` のコミット機能は無効化する。amend・フックのスキップ・push は対象外。
  Lefthook は、非対話のパイプ実行に対応した Nix 管理版を OMP の起動時に指定する。
  選択コミットでは Lefthook のチェックを実行するが、自動再ステージと共有 stash は使わない。
  フックが検知対象のファイルを変更した場合はコミットを止め、結果を残す。
  差分を確認し、意図した整形・生成結果だけを含めて再実行する。変更検知のために
  `.envrc` などの保護対象や、シンボリックリンクのリンク先は読み取らない。
- `tools.approvalMode = "yolo"` で、個別ポリシーのない Bash、`write`、MCP 呼び出しは自動承認する。
  通常の `git push` や MCP 経由の外部サービスへの変更も、個別ポリシーがなければツール側では確認しない。
  `git show` などの単純な Git コマンドは `bash` で直接実行する。
  `eval` と `bash.patterns` の明示的な `prompt` は、`--auto-approve` を付けても引き続き確認する。
  `rm`、force push、hard reset、PR の merge/close などは引き続き拒否する。
  ファイルごとの削除と移動には `file_change` を使う。起動ディレクトリ配下では対象パスを
  表示して都度確認する。一時領域内だけで完結する操作は承認不要。
  `mktemp` で作った一時ディレクトリも、シェルの `trap` ではなく `file_change` で後片付けする。
  移動先の上書きやシンボリックリンク経由の操作は拒否する。
- OMP のサブエージェントは、並列数の上限が 4。対話型の親セッションからの起動は
  すべて自動承認する。子・Advisor・非対話セッションでは編集・shell・eval・MCP・LSP を拒否する。
  セッション一覧は worktree 単位に分ける。
- Herdr の公式 OMP 連携拡張も Home Manager で配置する。Herdr 内で起動した OMP の
  作業中・入力待ち・待機状態と会話の復元情報を Herdr に通知する。
  `herdr integration status` で導入状態を確認できる。拡張は Herdr と同じ revision に
  固定するため、`herdr integration install omp` での個別更新は不要。
  保護と Herdr の拡張は起動時に明示的に読み込むため、ほかの拡張は自動検出しない。
- モデル切り替えは `F6`（次）／`Shift+F6`（前）に変更し、Herdr の prefix `Ctrl+P`
  との衝突を避ける。役割の割り当ては従来どおり `Alt+M` または `/model`。
  キー設定は `~/.omp/agent/keybindings.yml` へ配置し、変更後は OMP を再起動する。
- 暗色テーマは同梱の `dark-terminal` をベースに、補助テキストのグレーを明るくした
  `dark-terminal-readable`。明色テーマと端末側の配色は変更しない。入力欄は `claude`、記号は `ascii`。
- 公式 module は `~/.omp/agent/config.yml` を書き込み可能な実ファイルとして配置する。
  `/settings`・`/model`・`/advisor` 等で保存したグローバル設定は、次回 rebuild で
  宣言内容に置き換わる。継続使用するモデルの割り当ては `settings.modelRoles` に、
  Advisor の常時有効化は `settings.advisor.enabled` に反映する。
- 認証・セッション・キャッシュは `~/.omp/` のローカルデータとして保持する。
  ディレクトリ全体を Git 管理・symlink 管理しない。

ローカル権限設定は `~/.omp/permissions.d/` に置き、Git には入れない。
設定は OMP の起動時に読み込むため、通常のターミナルで編集してから OMP を起動し直す。

Vault への書き込みを許可するには、`~/.omp/permissions.d/obsidian-vault` に Vault ルートの実パスを 1 行で書く。
`~` やシンボリックリンクを含まない絶対パスを使う。
ホームとその親は指定できない。
ファイルがなければ Vault への書き込み許可は追加せず、不正な設定があれば起動を拒否する。

```text
/Users/alice/Documents/My Vault
```

プロジェクト固有の Bash ルールは、対象プロジェクトのルートで `pwd -P` を評価し、その結果を使って `~/.omp/permissions.d$(pwd -P).yml` に置く。
たとえば、プロジェクトが `/Users/alice/src/my-app` なら `~/.omp/permissions.d/Users/alice/src/my-app.yml` に次のように書く。

```yaml
bash:
  patterns:
    - match: "task package:lint"
      approval: allow
    - match: "task package:deploy"
      approval: deny
```

`match` は引数を含む完全一致で、許可と確認のルールはその実パスからの起動にのみ適用する。
リンク済み worktree では、元リポジトリの `bash.patterns` にある拒否ルールだけを継承し、
worktree の許可ルールより先に判定する。継承用の設定は起動時に `permissions.d` 内に生成し、
元の設定と同様に OMP からは書き換えられない。起動パス固有の設定または継承した拒否ルールを
使う場合、Bash の `cwd` は起動ディレクトリに固定する。
元リポジトリの設定を継承したリンク済み worktree では、起動時のブランチへの専用コミットツールも
利用できる。許可するのは、その worktree の index とコミット用一時ファイル、起動時の
ブランチの ref・reflog と loose object の書き込み。共有 Git 設定、他ブランチと他 worktree
の管理領域には書き込めない。ブランチを切り替えた場合は OMP を起動し直す。

Go のビルド・依存・チェックサム検証（`GOPATH/pkg/sumdb`）、golangci-lint、mise、Deno と XDG
のキャッシュは、OMP 起動時に `~/.omp/cache/` 配下へ向ける。`GOPROXY` が未設定、空、または
区切り文字だけの場合は `https://proxy.golang.org,direct` を使う。プロキシを指定する場合は
起動環境に設定する。
Go の依存を展開する `~/.omp/cache/go-mod` 内では、ZIP 内の名前や階層にかかわらず
作成と部分展開の回収ができる。ほかの場所への書き込み禁止や `.env` と鍵ファイルの内容の
読み取り禁止は維持する。`id_test.go` などの Go ソースは、保護対象の親ディレクトリがない
場合に限り、このキャッシュ内で読める。保護対象のファイルを読む `go mod verify` や
`go:embed` は通常のターミナルで実行する。
Docker や外部サービスの接続・認証に秘密ファイルが必要な Task は通常のターミナルで実行する。

OMP の起動や `make rebuild` ごとに検証を実行する必要はない。OMP の安全設定を変えたときや
別の Mac で初めて適用するときは、設定を反映してから通常のターミナルで `make omp-check` を実行する。
一時ファイルだけを使い、実際の秘密ファイルは読まない。
リンク済み worktree の検証では、インストール済みの OMP を起動し、一時 index の作成と
大きな index での選択コミットを試す。フックが実行されること、対象外のステージ済み変更が
残ること、共有 Git 設定に書き込めないことも確認する。

削除・移動の承認も OMP 本体で確認する場合:

```sh
# rebuild 後、既定モデルを選択済みの状態で実行。モデルにはリクエストしない。
omp --no-session --mode rpc --trusted-extension "$PWD/.config/omp/workspace-safety.test.mjs" </dev/null
```

`check-sandbox.mjs` が `Sandbox could not start` なら、その起動環境では保護付き OMP も起動できない。
既存の sandbox 内から実行すると macOS が二重 sandbox を拒否することがあるため、
通常の Herdr ペインでも検証してから適用する。`--yolo` や拡張無効化による運用はしない。

更新時は `omp` input の URL のリリース番号を変更してから
`make update-lock INPUT=omp` → `make rebuild PROFILE=...`。アプリ内の自己更新は使わない。
公式資料：[設定](https://github.com/can1357/oh-my-pi/blob/v19.0.0/docs/settings.md)、
[モデル](https://github.com/can1357/oh-my-pi/blob/v19.0.0/docs/models.md)。

## Directory Structure

全ファイルは列挙しない。迷いやすい場所と、置き場所の判断が要るものだけ書く。

```text
nix/
  nix-darwin/          system 設定と Homebrew の宣言。hosts/ が personal|work の差分
  home-manager/
    home.nix           home.packages (パッケージはここ)
    programs/<name>.nix  個別アプリ設定。上流 home-manager の modules/programs/<name>.nix に命名を揃える
scripts/
  link.sh              symlink 作成 + Homebrew 本体の準備 (make link の実体)
.config/nvim/          Neovim。init.lua + lua/ を丸ごと symlink (Nix 管理下に置かない)
.config/herdr/         Herdr の設定とプロジェクトランチャー。Home Manager の xdg.configFile で管理
.claude/               Claude Code 設定。agents/ hooks/ は symlink、skills/ は実体のみ保管
.codex/                Codex 設定。AGENTS.md・rules/ は symlink、config.shared.toml は部分同期の source
.tmux/                 tmux から呼ぶヘルパー。launch_project.sh = prefix + C-p のプロジェクトランチャー、
                       worktree_session.sh = prefix + C-w の git worktree ランチャー、lib/ は両者の共通部品、
                       worktree_sync.sh = worktree に .env 等を持ち込み direnv/mise の許可を通す
chrome/extensions/     自作 Chrome 拡張。unpacked で直接読み込むので symlink 対象外
raycast/               自作 Raycast 拡張 (extensions/) と script command (script/)
```

トップレベルには他に `.zshrc` / `.p10k.zsh` / `.tmux.conf` などの単一設定ファイルがあり、
いずれも `scripts/link.sh` の `LINKS` 経由で `$HOME` にリンクされる。
`*.sample` は untracked な実ファイルの雛形 (`.zshenv.sample`, `.tmux/projects.json.sample`)。

### Neovim のキーバインド

`<Space>d` は、レジスタやクリップボードを上書きせずに削除する。
ノーマルモードでは後ろにモーションを続ける。`<Space>d40G` なら現在行から40行目まで、`<Space>dd` なら現在行、`3<Space>dd` なら現在行から3行を削除する。
`<Space>d` のあと少し待つと、which-key に `d`（現在行）と `w`（次の単語まで）の候補が出る。
ビジュアルモードでは `<Space>d` で選択範囲を削除する。

検索欄（`/`、`?`）とコマンドライン（`:`）では、`Ctrl+A` で入力の先頭に、`Ctrl+E` で末尾に移動する。

挿入モードで `Ctrl-N` を押すと `nvim-cmp` の補完候補が開く。候補が表示済みなら次の候補へ進む。

### Karabiner の右⌘レイヤー

内蔵キーボードの右 `⌘` を押している間は、`;` が `←`、`[` が `↑`、`'` が `↓`、`Enter` が `→` になる。
`Backspace` は `Delete`（カーソルの右側を削除）になる。
右 `⌘` はレイヤー専用で、ほかの修飾キーは変換後も残る。たとえば `左Ctrl + 左Option + 右⌘ + [` は `左Ctrl + 左Option + ↑` になる。
内蔵の右 `⌘` では通常のショートカットは発動しない。左 `⌘` と外付けキーボードの `⌘` は通常どおり使える。
設定は [`karabiner.nix`](nix/home-manager/programs/karabiner.nix) で管理し、`make rebuild PROFILE=...` で反映する。

## Packages (Nix)

Packages are declared in Nix and applied with `darwin-rebuild`.

- CLI/GUI packages available via nixpkgs → `nix/home-manager/home.nix` (`home.packages`)
- macOS-only or frequently updated apps (Homebrew cask で管理するもの) →
  `nix/nix-darwin/homebrew.nix` (`homebrew.taps` / `brews` / `casks`)
- 環境ごと (personal/work) の差分 → `nix/nix-darwin/hosts/{profile}.nix`

適用:

```sh
make rebuild PROFILE=personal
make rebuild PROFILE=work
make dry-run PROFILE=work     # activate せず評価だけ確認
```

`PROFILE` にデフォルトは無く、`setup` / `rebuild` / `dry-run` では指定が必須
(取り違えると別マシン向けの設定を activate してしまうため)。指定できる値は
`nix/nix-darwin/hosts/*.nix` のファイル名から自動で拾っており、未指定・不正な値は
実行前にエラーで止まる。

または直接:

```sh
cd nix/nix-darwin
sudo darwin-rebuild switch --flake .#personal   # または #work
```

## Herdr (prefix = Ctrl-P)

Herdr は Nix の flake input `herdrdev/herdr/v0.9.3` として固定して導入する。
設定は `.config/herdr/config.toml`、自作ランチャーは `.config/herdr/scripts/` に置き、
いずれも `make rebuild PROFILE=...` で `~/.config/herdr/` へ配置される。

tmux の操作を次のように移行している。

| キー | Herdr の操作 |
| --- | --- |
| `prefix + C-o` | `projects.json` のプロファイル picker（workspace/tab/pane を生成） |
| `prefix + C-w` | 既存 Git worktree の native picker |
| `prefix + C-c` | 新しい workspace |
| `prefix + C-r` | workspace の rename |
| `prefix + s` | workspace/session navigator |
| `prefix + w` | workspace picker |
| `prefix + h/j/k/l` | pane 移動 |
| `prefix + H/J/K/L` | pane resize（`prefix + r` は Herdr の resize mode） |
| `prefix + c/n/p/1..9` | tab の作成・移動 |

`projects.json` は tmux と共用する。tmux の session/window/pane を Herdr が直接復元する
機能はないため、既存の tmux セッションはそのまま残り、Herdr 側で同じディレクトリの
workspace を新規作成する。Git worktree、`.env` の同期、コマンド自体は multiplexer に
依存しないので引き続き利用できる。`prefix + Shift-g` は native 作成ではなく `gwt new` を popup
で開くため、作成後にローカル設定も同期する。Herdr native の open/remove はそのまま使い、作成先は
`~/worktrees/<repo>/<branch-slug>` で共通化している。削除時にブランチは消さない。

tmux の `prefix=C-p` と `prefix+C-p` の組み合わせは、Herdr が prefix 二度押しを
literal `Ctrl-P` の転送用に予約しているため登録できない。プロジェクト picker だけ
`prefix+C-o` に置き換えている。

## tmux (legacy)

旧 tmux 用の設定・スクリプトも互換確認用として残しているが、通常の起動は Herdr を使う。
以下は tmux を手動で使う場合の仕様である。

どちらも fzf の popup を出し、選んだものに対応する tmux セッションへ移動する。
既に同じセッションがあれば作り直さず attach (tmux 内なら switch-client) するだけ。
ウィンドウ構成は `~/.tmux/projects.json` (`.tmux/projects.json.sample` からコピー) で定義する。

| キー | スクリプト | 一覧に出るもの |
| --- | --- | --- |
| `prefix + C-p` | `.tmux/launch_project.sh` | `projects.json` の `projects[]` |
| `prefix + C-w` | `.tmux/worktree_session.sh` | カレントペインのリポジトリの git worktree (`C-d` で削除) |

セッション生成の実処理は `.tmux/lib/tmux_session.sh` に共通化してある。

### worktree ランチャー

一覧は `git worktree list` から作る。git 自身が登録済み worktree の実パスを持っているので、
`~/worktrees/` でも任意の既存配置でも置き場所を問わず出てくる
(ディレクトリを走査しないので探索パスの設定は要らない)。

- セッション名は メイン worktree が `<repo>`、それ以外が `<repo>@<ブランチ名>`。
  `:` `.` `/` は tmux のターゲット指定と衝突するので `-` に潰す
- worktree との対応はセッションオプション `@worktree_path` で保持する。名前ではなく
  パスで突き合わせるので、セッションをリネームしても同じ worktree を開き直せる
- 一覧は `<マーク> <ブランチ名> │ <パス>` の 3 列。`*` は「そのセッションが既にある」印。
  ブランチ名は 60 文字固定で、超過分は末尾を `…` に置き換える。パス列は残りの端末幅を使う。
  パスはメイン worktree からの相対 (`./`, `../`) で見せ、メイン worktree の行だけ
  相対表示の基準として絶対パスを出す
- ウィンドウ構成は `defaults.windows` (無ければ `shell` 1 枚)。`projects[]` は同じ `path` に
  複数のプロファイルを登録できる (同じリポジトリに Local Server と Workspace がある等) ため、
  パスからプロジェクトを一意に引き当てられない。worktree 側は `defaults` だけを見る

`C-d` を押すと、その worktree を削除する (`Enter` は従来どおり open / attach)。確認したうえで
`git worktree remove` し、`@worktree_path` で紐づく tmux セッションも閉じる。未コミットの変更や
untracked ファイルがあると git が止めるので、その場合だけ強制削除するかを改めて聞く
(`worktree_sync.sh` が張った symlink は ignore 済みなので邪魔をしない)。削除後は一覧を作り直して
選択に戻るので、続けて消せる。**ブランチは消さない** (別の worktree で作業を続けることがあるため)
ので、要らなければ表示されるコマンドで消す。

シェル上では `gwt` も同じ目的の fzf picker を開く。表示はメイン worktree からの相対パスで、
`Enter` で選択先をカレントにした新しいシェルを開き、`Ctrl-d` で確認付き削除を行う。引数付きの
`gwt` は `git worktree` にそのまま委譲する。`make link` により `~/.local/bin/gwt` へリンクされ、
どの Git リポジトリからも実行できる。

`gwt` の一覧の左端には、ブランチに紐づく最新の GitHub PR を表示する。
Open と Draft は `#1234`、Closed は `Closed`、Merged は `Merged`、PR なしおよび detached HEAD は `-`。
`gh` の未導入・認証エラー・通信エラーなどで取得できない場合は `?` を表示する。
PR 情報は起動時に対象ブランチをまとめて取得する。

`Ctrl-d` で worktree の削除を確認した後、ローカルブランチも削除するかを選べる。既定ではブランチを残す。
削除前に対象ブランチの PR を再取得し、未作成、Open、Draft、または取得できない場合は、理由と削除対象（worktree のみ、またはローカルブランチも）を示して続行するか確認する。
ここで続行しなければ、worktree もブランチも残る。
ブランチを削除するのは worktree の削除に成功した後だけで、Git が通常のブランチ削除を拒否した場合は、強制削除するかを別に確認する。
リモートブランチは削除しない。

`gwt new` は fzf で既存ローカルブランチを選択する。`gwt new <branch> [dir]` は旧
`new-worktree` の後継で、指定名の既存ブランチを checkout、無ければブランチと worktree を作成する。
`dir` の既定値は `~/worktrees/<repo>/<branch>` で、作成後にローカル設定の同期を行って終了する。
実行後のカレントディレクトリは元の位置のまま変わらない。

`+ 新規 worktree を作成` を選ぶとブランチ名を聞き、`git worktree add` してからセッションを開く
(既存ブランチならそれを checkout、無ければ新規ブランチを作る)。置き場所は上から順に:

1. `git config worktree.root` (リポジトリごとに設定できる。相対指定はメイン worktree からの相対)
2. 環境変数 `WORKTREE_ROOT`
3. `~/worktrees`

いずれの場合も、その下に `<repo>/<branch>` を作る。Herdr の `[worktrees].directory` も
`~/worktrees` に合わせている。リポジトリ内への配置は検索・ファイル監視へ別 worktree が混ざるため
推奨しない。

```sh
# 例: リポジトリごとに別の共通ルートを使う
git config worktree.root ~/Developer/worktrees
```

### worktree を作った直後から動く状態にする (worktree_sync.sh)

新しい worktree は「gitignore されたファイルが付いてこない」「パスが変わるので direnv /
mise の許可が引き継がれない」の 2 点でそのままでは動かない。`worktree-sync` がその 2 つを埋める。
新規 worktree 作成時に `gwt` から呼ばれる。処理は冪等なので、後から `.env` が増えたときなどは
手で叩き直せばよい。

```sh
worktree-sync              # カレント worktree を対象にする
worktree-sync --dry-run    # 何をするか見るだけ
```

#### 1. ローカル設定のリンク

メイン worktree 側の実体へ**シンボリックリンク**を張る。コピーではないので片方で書き換えれば
全 worktree に反映され、古いコピーが残らない (逆に、worktree 側のツールが `.env` を書き換えると
メインにも波及する)。既に同名のファイル/リンクがあれば触らない。

対象は「メイン worktree にある ignore 済みファイル」のうち、下記パターンに一致したもの。
ignore 判定は `git ls-files --others --ignored` に任せるのでグローバル/ローカルの `.gitignore`
を両方見る。`node_modules/` のようにディレクトリごと ignore されているものは 1 エントリに
畳まれるため中まで走査しない。

- デフォルト: `.env` / `*.env` / `.claude/settings.local.json`
- 追加は `git config --add worktree.sync '<パターン>'` (複数指定可。グローバルにも書ける)

パターンはリポジトリルートからの相対パスに対する glob。`*` は `/` も跨ぐので `*.env` は
`apps/web/.env` にも当たる。`/` を含むパターンは `*/<パターン>` でも照合する。

#### 2. direnv allow / mise trust / mise install

- `direnv`: 許可は `.envrc` の絶対パスに紐づくので worktree ごとに取り直しになる。
  `.envrc` があればそれを、無ければ `.env` を `direnv allow` する
  (direnv は `.envrc` → `.env` の順で最初に見つけた 1 つだけを読む。`.env` しか無いリポジトリでも
  1 でリンクを張った結果 blocked になるため対象にしている)
- `mise`: trust はメイン worktree の同等パスが trust 済みなら共有されるが、paranoid モードでは
  共有されない (ブランチによって内容が違いうるため) ので、`mise.toml` などがあれば明示的に trust する
- `mise install`: ツールの実体は `~/.local/share/mise/installs` にバージョン単位で置かれて
  worktree 間で共有されるため、たいていは何もせずに終わる (実測 0.05 秒)。実際にインストールが
  走るのはブランチが `mise.toml` のバージョンを上げているときだけ

`.envrc` は読み込み時に実行されるコードなので、自分が把握していないブランチを worktree に
checkout する場合は中身を見てから使うこと (このスクリプトは無条件に allow する)。

#### 3. serena MCP の登録

`claude mcp add` の既定スコープ (local) は「そのディレクトリ」に紐づくので、worktree ごとに
登録し直す必要がある。`claude mcp get serena` で既に登録済みなら何もしない。
