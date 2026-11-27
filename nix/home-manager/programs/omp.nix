{ inputs, lib, pkgs, username, ... }:

let
  upstreamOmp = inputs.omp.packages.${pkgs.stdenv.hostPlatform.system}.default;
  # 同梱の dark-terminal をベースに、本文より弱い文字色だけを明るくする。
  darkTerminal = (builtins.fromJSON (builtins.readFile
    (inputs.omp + "/packages/tui/src/theme/defaults.json")))."dark-terminal";
  readableTheme = darkTerminal // {
    name = "dark-terminal-readable";
    vars = darkTerminal.vars // { dimGray = "#a6a6a6"; };
    colors = darkTerminal.colors // {
      syntaxOperator = "dimGray";
      syntaxPunctuation = "dimGray";
      statusLineSep = "dimGray";
    };
  };
  safetyExtension = ../../../.config/omp/safety.ts;
  workspaceExtension = ../../../.config/omp/workspace-safety.ts;
  approvalExtension = ../../../.config/omp/approval-safety.ts;
  commitExtension = ../../../.config/omp/commit.ts;
  herdrExtension = inputs.herdr + "/src/integration/assets/omp/herdr-agent-state.ts";
  secretsPolicy = builtins.readFile ../../../.config/omp/secrets.sb;
  sandboxProfile = pkgs.writeText "omp-workspace.sb" (
    secretsPolicy + builtins.readFile ../../../.config/omp/workspace.sb
  );
  # コミット拡張と Lefthook の変更検知にも Seatbelt と同じ機密パスの条件を使う。
  secretPathPattern = builtins.head (lib.findFirst (match: match != null)
    (throw "Missing secret filename filter in OMP sandbox policy")
    (map (builtins.match ''[[:space:]]*\(regex #"([^"]+)"\)\)'') (lib.splitString "\n" secretsPolicy)));
  changesetSignature = "func (r *Repo) Changeset() (map[string]string, error) {";
  changesetLoop = "\tfor _, status := range statuses {\n\t\tif status.Index == 'D' || status.Worktree == 'D' {";
  safeLefthook = pkgs.lefthook.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace internal/git/repo.go \
        --replace-fail ${lib.escapeShellArg changesetSignature} \
          ${lib.escapeShellArg "var ompProtectedPath = regexp.MustCompile(${builtins.toJSON secretPathPattern})\n\n${changesetSignature}"} \
        --replace-fail $'\t"fmt"\n' $'\t"fmt"\n\t"os"\n' \
        --replace-fail ${lib.escapeShellArg changesetLoop} \
          ${lib.escapeShellArg ("\tfor _, status := range statuses {\n"
            + "\t\tif ompProtectedPath.MatchString(status.Path) {\n\t\t\tcontinue\n\t\t}\n"
            + "\t\tif status.Index == 'D' || status.Worktree == 'D' {")} \
        --replace-fail $'\t\tif isDir, _ := afero.IsDir(r.Fs, filepath.Join(r.Paths.Root, status.Path)); isDir {\n\t\t\tchangeset[status.Path] = "directory"\n\t\t\tcontinue\n\t\t}' \
          ${lib.escapeShellArg ''
            filename := filepath.Join(r.Paths.Root, status.Path)
            if links, ok := r.Fs.(afero.Symlinker); ok {
              stat, _, err := links.LstatIfPossible(filename)
              if os.IsNotExist(err) {
                changeset[status.Path] = "deleted"
                continue
              }
              if err != nil {
                return nil, err
              }
              switch {
              case stat.Mode()&os.ModeSymlink != 0:
                target, err := links.ReadlinkIfPossible(filename)
                if err != nil {
                  return nil, err
                }
                changeset[status.Path] = "symlink:" + target
                continue
              case stat.IsDir():
                changeset[status.Path] = "directory"
                continue
              case !stat.Mode().IsRegular():
                changeset[status.Path] = "special:" + stat.Mode().Type().String()
                continue
              }
            } else if isDir, _ := afero.IsDir(r.Fs, filename); isDir {
              changeset[status.Path] = "directory"
              continue
            }
          ''}
      substituteInPlace internal/git/wrapper/hash_objects.go \
        --replace-fail '"hash-object", "--"' '"hash-object", "--no-filters", "--"'
    '';
  });
  ompLefthook = pkgs.writeShellScript "omp-lefthook" ''
    # 選択コミットの一時 index では、共有 stash と作業ツリーからの再ステージを使わない。
    case "$1:$2:''${GIT_INDEX_FILE##*/}:''${DOTFILES_OMP_SELECTIVE_COMMIT-}" in
      run:pre-commit:next-index-*.lock:1)
        set -- "$@" --no-auto-install --no-stage-fixed --fail-on-changes
        ;;
    esac
    exec ${lib.getExe safeLefthook} "$@"
  '';
  protectedOmp = pkgs.writeShellScriptBin "omp" ''
    set -e
    workspace="$(pwd -P)"
    home="$(cd -P -- "$HOME" && pwd -P)"
    state="$home/.omp"
    temp="$(cd -P -- "$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)" && pwd -P)"
    policies="$state/permissions.d"
    project_policy="$policies$workspace.yml"
    case "$home/" in
      "$workspace/"*) echo "omp: start in a project directory, not HOME or its ancestor" >&2; exit 1 ;;
    esac
    case "$workspace/" in
      //|"$state/"*) echo "omp: invalid workspace: $workspace" >&2; exit 1 ;;
    esac
    if [[ "$temp" != /private/var/folders/*/T || -L "$state" || -L "$policies" ]]; then
      echo "omp: unsafe temporary or state directory" >&2
      exit 1
    fi
    vault="$workspace"
    vault_config="$policies/obsidian-vault"
    if [[ -L "$vault_config" || ( -e "$vault_config" && ! -f "$vault_config" ) ]]; then
      echo "omp: $vault_config must be a regular file, not a symbolic link" >&2
      exit 1
    fi
    if [[ -f "$vault_config" ]]; then
      vault="$(<"$vault_config")"
      if [[ "$vault" != /* || "$vault" == / || "$home/" == "$vault/"* ||
            "$vault" == *$'\n'* || ! -d "$vault" ||
            "$(${pkgs.coreutils}/bin/realpath -e -- "$vault")" != "$vault" ]]; then
        echo "omp: $vault_config must contain one physical vault path, not HOME or its ancestor" >&2
        exit 1
      fi
    fi
    go_mod_cache="$state/cache/go-mod"
    if [[ "$(${pkgs.coreutils}/bin/realpath -m -- "$go_mod_cache")" != "$go_mod_cache" ]]; then
      echo "omp: Go module cache must be a physical path: $go_mod_cache" >&2
      exit 1
    fi
    # SumDB の最新ヘッドは GOMODCACHE ではなく GOPATH/pkg/sumdb に保存される。
    export XDG_CACHE_HOME="$state/cache/xdg" GOCACHE="$state/cache/go-build" GOMODCACHE="$go_mod_cache"
    export GOPATH="$state/cache/go-path"
    export GOLANGCI_LINT_CACHE="$state/cache/golangci-lint" MISE_CACHE_DIR="$state/cache/mise" DENO_DIR="$state/cache/deno"
    # 空または区切りだけの GOPROXY は有効な接続先にならない。off や明示的な社内プロキシは保持。
    if [[ "''${GOPROXY-}" =~ ^[,\|[:space:]]*$ ]]; then
      export GOPROXY=https://proxy.golang.org,direct
    fi
    # 継承した Lefthook 2.1.1 はパイプ経由でも PTY を開こうとする。
    export LEFTHOOK_BIN="${ompLefthook}"
    export DOTFILES_OMP_GIT=${lib.escapeShellArg (lib.getExe pkgs.git)}
    export DOTFILES_OMP_PROTECTED_PATH=${lib.escapeShellArg secretPathPattern}
    git_info() (
      unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_NAMESPACE
      exec ${lib.getExe pkgs.git} "$@"
    )
    regex_literal() {
      printf '%s' "$1" | /usr/bin/sed 's/[][\\.^$*+?(){}|]/\\&/g'
    }
    commit_write='^$'
    commit_parents='^$'
    enable_worktree_commit() {
      local backlink branch path admin objects ref reflog parents
      [[ -f "$workspace/.git" && ! -L "$workspace/.git" &&
        "$git_dir" == "$common_dir/worktrees/"* && "''${git_dir#"$common_dir/worktrees/"}" != */* &&
        -f "$git_dir/gitdir" && ! -L "$git_dir/gitdir" ]] || return 1
      backlink="$(<"$git_dir/gitdir")"
      [[ "$backlink" == /* ]] || backlink="$git_dir/$backlink"
      [[ "$(${pkgs.coreutils}/bin/realpath -e -- "$backlink")" == "$workspace/.git" &&
        "$(git_info rev-parse --show-ref-format)" == files ]] || return 1
      branch="$(git_info symbolic-ref --quiet --no-recurse HEAD)" || return 1
      [[ "$branch" == refs/heads/* ]] && git_info check-ref-format "$branch" || return 1
      for path in "$git_dir" "$git_dir/logs/HEAD" "$common_dir/objects" \
        "$common_dir/$branch" "$common_dir/logs/$branch"; do
        [[ "$(${pkgs.coreutils}/bin/realpath -m -- "$path")" == "$path" ]] || return 1
      done

      admin="$(regex_literal "$git_dir")"
      objects="$(regex_literal "$common_dir/objects")"
      ref="$(regex_literal "$common_dir/$branch")"
      reflog="$(regex_literal "$common_dir/logs/$branch")"
      # Seatbelt の regex には POSIX 文字クラスや {n} を使わない。
      local admin_files='index([.]lock)?|HEAD[.]lock|logs/HEAD([.]lock)?|COMMIT_EDITMSG|omp-commit-[0-9a-f-]+[.]index([.]lock)?|next-index-[0-9]+[.]lock([.]lock)?'
      local tmp_object='[.]tmp[A-Za-z0-9]+|tmp_obj_[A-Za-z0-9]+'
      local hex='[0-9a-f]' sha1 sha256_tail
      # loose object の先頭 2 桁はディレクトリ名。ファイル名は 38 桁か 62 桁。
      printf -v sha1 "%.0s$hex" {1..38}
      printf -v sha256_tail "%.0s$hex" {1..24}
      commit_write="^($admin/($admin_files)|$ref([.]lock)?|$reflog([.]lock)?|$objects/($tmp_object|$hex$hex(/($sha1($sha256_tail)?|$tmp_object))?))$"
      # packed refs や新規 reflog に必要な親ディレクトリだけ作成可能にする。
      for path in "$common_dir/$branch" "$common_dir/logs/$branch" "$git_dir/logs/HEAD"; do
        parents="''${path%/*}"
        while [[ "$parents" == "$common_dir/"* && ! -d "$parents" ]]; do
          commit_parents+="|^$(regex_literal "$parents")$"
          parents="''${parents%/*}"
        done
      done
    }
    launch_config=()
    unset DOTFILES_OMP_PROJECT_POLICY
    if [[ -f "$project_policy" ]]; then
      export DOTFILES_OMP_PROJECT_POLICY=1
      launch_config=(--config "$project_policy")
    fi
    if [[ -d "$policies" ]] && git_dirs="$(git_info rev-parse \
      --path-format=absolute --absolute-git-dir --git-common-dir 2>/dev/null)"; then
      git_dir="''${git_dirs%%$'\n'*}"
      common_dir="''${git_dirs#*$'\n'}"
      if [[ "$git_dir" != "$common_dir" && "$common_dir" == */.git ]]; then
        repo_policy="$policies''${common_dir%/.git}.yml"
        if [[ -f "$repo_policy" ]]; then
          if [[ "$(${pkgs.coreutils}/bin/realpath -e -- "$repo_policy")" != "$repo_policy" ]]; then
            echo "omp: inherited policy must be a physical path under $policies: $repo_policy" >&2
            exit 1
          fi
          # 子プロセスから変更できない permissions.d 内で、拒否だけを原子的に更新する。
          inherited_policy="''${repo_policy%.yml}.worktree-deny.json"
          policy_tmp="$(/usr/bin/mktemp "$inherited_policy.XXXXXX")"
          trap '/bin/rm -f -- "$policy_tmp"' EXIT
          ${lib.getExe pkgs.yq-go} -o=json '
            [(.bash.patterns // [])[] | select((.approval | downcase | trim) == "deny")]
            | if length > 0 then {"bash":{"patterns":.}} else {} end
          ' "$repo_policy" > "$policy_tmp"
          ${pkgs.coreutils}/bin/mv -fT -- "$policy_tmp" "$inherited_policy"
          trap - EXIT
          # OMP は後の overlay の Bash パターンを先頭に置く。
          enable_worktree_commit || :
          launch_config+=(--config "$inherited_policy")
          export DOTFILES_OMP_PROJECT_POLICY=1
        fi
      fi
    fi
    export DOTFILES_OMP_WORKSPACE="$workspace" TMPDIR="$temp"
    exec /usr/bin/sandbox-exec \
      -D "WORKSPACE=$workspace" -D "STATE=$state" -D "TEMP=$temp" \
      -D "OBSIDIAN_VAULT=$vault" \
      -D "POLICIES=$policies" -D "COMMIT_WRITE=$commit_write" -D "COMMIT_PARENTS=$commit_parents" \
      -f ${sandboxProfile} ${upstreamOmp}/bin/omp \
      --trusted-extension ${safetyExtension} --trusted-extension ${workspaceExtension} \
      --trusted-extension ${approvalExtension} --trusted-extension ${commitExtension} \
      --trusted-extension ${herdrExtension} "''${launch_config[@]}" "$@"
  '';
in
{
  programs.omp = {
    enable = true;
    package = protectedOmp;
    # 公式 module が書き込み可能な config.yml を配置する。
    # /settings 等での変更は次回 rebuild でこの宣言に戻る。
    settings = {
      # モデル提供元ではなく、既存の指示・Skills・MCP を読む discovery source。
      enabledProviders = [ "claude" "codex" ];
      defaultThinkingLevel = "high";
      session.worktreeScope = "directory";
      # 公式の /commit と eval commit は使わず、公開 API の拡張だけを有効にする。
      commit.enabled = false;

      theme.dark = readableTheme.name;
      composer.shape = "claude";
      symbolPreset = "ascii";

      # 未登録の Bash は自動承認するが、Bash の拒否ルールが及ばない eval は都度確認する。
      tools.approvalMode = "yolo";
      tools.approval = {
        edit = "allow";
        eval = "prompt";
        commit = "allow";
        task = "allow";
        mcp__awslabs_aws_documentation_mcp_server_search_documentation = "allow";
        mcp__awslabs_aws_documentation_mcp_server_read_documentation = "allow";
        mcp__awslabs_aws_documentation_mcp_server_read_sections = "allow";
        mcp__aws_mcp_aws_search_documentation = "allow";
        mcp__aws_mcp_aws_read_documentation = "allow";
      };

      bash = {
        allowCompoundCommands = true;
        patterns =
          map (match: { inherit match; approval = "deny"; }) [
            "find * -delete*"
            "gh pr merge"
            "gh pr merge *"
            "gh pr close"
            "gh pr close *"
          ]
          ++ map (match: { inherit match; approval = "prompt"; }) [
            # メッセージは可変。メッセージより後ろのオプションは自動許可しない。
            "git commit * -*"
            "git stash push * -*"
          ]
          ++ map (match: { inherit match; approval = "allow"; }) [
            "git status"
            "git status --short"
            "git status --short --branch"
            "git status -sb"
            "git log"
            "git log --oneline"
            "git log --oneline --decorate"
            "git log -8 --oneline --decorate"
            "git diff --no-ext-diff --no-textconv"
            "git diff --no-ext-diff --no-textconv --cached"
            "git show --no-ext-diff --no-textconv"
            "git show --no-ext-diff --no-textconv --stat"
            "git ls-files"
            "git rev-parse --show-toplevel"
            "git branch --list"
            "git worktree list"
            "git stash list"
            "git stash"
            "git stash push"
            "git stash push -m *"
            "git fetch"
            "git fetch origin"
            "git fetch origin main"
            "git fetch -- origin *"
            "git add ."
            "git add -A"
            "git add -- *"
            "git commit -m *"
            "pwd"
            "uname -sm"
            "which go"
            "mise ls"
            "mise which go"
            "ghq list"
          ]
          ++ builtins.concatMap (command: [
            { match = command; approval = "allow"; }
            { match = "${command} *"; approval = "allow"; }
          ]) [
            "gh pr view"
            "gh pr list"
            "gh pr diff"
            "gh pr checks"
            "gh issue view"
            "gh repo view"
            "gh release view"
            "gh run list"
            "gh run view"
            "gh workflow list"
            "gh workflow view"
          ];
      };

      task = {
        maxConcurrency = 4;
        isolation.enabled = true;
      };

      # 認証とモデル選択後に /advisor on で有効化する。
      advisor.enabled = false;
      # ツール不具合の自動報告は明示的に無効化する。
      dev.autoqa = false;
    } // lib.optionalAttrs (username == "yoshiyama") {
      # work で選択済みのモデルと完了済みの初期セットアップを保持する。
      modelRoles.default = "openai-codex/gpt-6.2-sol";
      setupVersion = 3;
      disabledExtensions = [ "context-file:project:copilot-instructions.md" ];
    };
  };

  # AGENTS.md は task subagent に渡らないため、共通の作業ルールは RULES.md に置く。
  home.file.".omp/agent/RULES.md".source = ../../../.config/omp/RULES.md;
  home.file.".omp/agent/themes/${readableTheme.name}.json".text = builtins.toJSON readableTheme;

  # 信頼する拡張はラッパーから明示的に読み込む。ロードに失敗したら起動しない。
  # Herdr の導入状態の検出と、拡張への安定したパスも従来どおり維持する。
  home.file.".omp/agent/extensions/herdr-omp-agent-state.ts".source = herdrExtension;
  home.file.".omp/agent/extensions/safety.ts".source = safetyExtension;

  # Herdr の prefix (Ctrl+P) を OMP が必要としないよう、モデル循環を F6 へ移す。
  home.file.".omp/agent/keybindings.yml".source =
    (pkgs.formats.yaml { }).generate "omp-keybindings.yml" {
      "app.model.cycleForward" = "F6";
      "app.model.cycleBackward" = "Shift+F6";
    };
}
