DOTFILES_DIR := $(shell cd "$(dir $(lastword $(MAKEFILE_LIST)))" && pwd)
NIX_DARWIN_DIR := $(DOTFILES_DIR)/nix/nix-darwin
LINK_SH := $(DOTFILES_DIR)/scripts/link.sh

NIX_INSTALLER_URL := https://artifacts.nixos.org/nix-installer
NIX_DAEMON_SH := /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
# 初回 activate 前は /etc/nix/nix.conf に flakes が入っていないので明示的に有効化する。
NIX_FLAGS := --extra-experimental-features 'nix-command flakes'

# make のレシピは (継続行を含む) 1 行ごとに別シェルなので、nix を使うコマンドの
# 直前で毎回これを挟む。install-nix の直後など、呼び出し元シェルの PATH に
# まだ nix が入っていない状態でも同一 make 実行内で続行できるようにするため。
LOAD_NIX = if ! command -v nix >/dev/null 2>&1 && [ -e $(NIX_DAEMON_SH) ]; then . $(NIX_DAEMON_SH); fi

# PROFILE を取り違えると別マシン向けの設定を activate してしまうので、デフォルト値は
# 持たず毎回明示させる。指定可能な値は hosts/*.nix のファイル名から拾う。
PROFILES := $(notdir $(basename $(wildcard $(NIX_DARWIN_DIR)/hosts/*.nix)))
CHECK_PROFILE = \
	if [ -z "$(PROFILE)" ]; then \
		echo "PROFILE を指定してください (指定可能: $(PROFILES))"; \
		echo "  例: make rebuild PROFILE=work"; \
		exit 1; \
	elif ! echo " $(PROFILES) " | grep -q " $(PROFILE) "; then \
		echo "不明な PROFILE: $(PROFILE) (指定可能: $(PROFILES))"; \
		exit 1; \
	fi

.DEFAULT_GOAL := help
.PHONY: help setup install-nix link link-dry rebuild dry-run update update-lock doctor

# setup は install-nix → link → rebuild の順序に意味がある (link が Homebrew 本体を
# 用意し、rebuild がその上に cask/brew を宣言的に入れる) ため並列実行させない。
.NOTPARALLEL:

help:
	@echo "========================================="
	@echo "  dotfiles"
	@echo "========================================="
	@echo ""
	@echo "  make setup       - 初回セットアップ (install-nix → link → rebuild) *PROFILE 必須"
	@echo "  make install-nix - nix 本体をインストール (導入済みなら何もしない)"
	@echo "  make link        - symlink 作成 + Homebrew 準備 (scripts/link.sh)"
	@echo "  make link-dry    - link の内容を表示するだけ (何も変更しない)"
	@echo "  make rebuild     - darwin-rebuild switch *PROFILE 必須"
	@echo "  make dry-run     - darwin-rebuild の評価だけ確認 (activate しない) *PROFILE 必須"
	@echo "  make update      - パッケージ更新 (update-lock → rebuild) *PROFILE 必須"
	@echo "  make update-lock - flake.lock だけ更新 (activate しない)"
	@echo "  make doctor      - 前提コマンドと symlink の状態を確認"
	@echo ""
	@echo "  PROFILE にデフォルトは無い。指定可能: $(PROFILES)"
	@echo "  例: make rebuild PROFILE=work"
	@echo ""
	@echo "  update は INPUT で対象の flake input を絞れる (未指定なら全部)"
	@echo "  例: make update PROFILE=work INPUT=nixpkgs"
	@echo ""

setup:
	@$(CHECK_PROFILE)
	@$(MAKE) install-nix
	@$(MAKE) link
	@$(MAKE) rebuild PROFILE=$(PROFILE)

# インストーラは途中で sudo と対話確認を求めるので、非対話実行には向かない。
# 完了後もこの make を起動したシェルには PATH が通らないため、後続ターゲットは
# $(LOAD_NIX) で nix-daemon.sh を読む。新しいシェルでは /etc/zshrc 経由で通る
# (~/.zshenv に no_global_rcs を書いている場合は自分で path に足すこと)。
install-nix:
	@if command -v nix >/dev/null 2>&1; then \
		echo "  [OK]   nix ($$(command -v nix))"; \
	elif [ -e $(NIX_DAEMON_SH) ]; then \
		echo "  [OK]   nix (インストール済み。このシェルには未反映)"; \
	else \
		echo "nix をインストールします ($(NIX_INSTALLER_URL))"; \
		curl -sSfL $(NIX_INSTALLER_URL) | sh -s -- install; \
		echo ""; \
		echo "今のシェルで nix を使うには: . $(NIX_DAEMON_SH)"; \
	fi

link:
	@$(LINK_SH)

link-dry:
	@$(LINK_SH) --dry-run

# 初回は darwin-rebuild がまだ存在しないので、flake.lock で固定している nix-darwin を
# build して、その中の darwin-rebuild で activate する (2 回目以降は PATH のものを使う)。
rebuild:
	@$(CHECK_PROFILE)
	@$(LOAD_NIX); \
	if command -v darwin-rebuild >/dev/null 2>&1; then \
		sudo darwin-rebuild switch --flake $(NIX_DARWIN_DIR)#$(PROFILE); \
	else \
		echo "darwin-rebuild が無いので初回ブートストラップします (PROFILE=$(PROFILE))"; \
		out="$$(nix $(NIX_FLAGS) build --no-link --print-out-paths $(NIX_DARWIN_DIR)#darwinConfigurations.$(PROFILE).system)" && \
		sudo "$$out/sw/bin/darwin-rebuild" switch --flake $(NIX_DARWIN_DIR)#$(PROFILE); \
	fi

dry-run:
	@$(CHECK_PROFILE)
	@$(LOAD_NIX); \
	nix $(NIX_FLAGS) build $(NIX_DARWIN_DIR)#darwinConfigurations.$(PROFILE).system --dry-run

# パッケージのバージョンは flake.lock に固定されているので、rebuild だけでは何も
# 新しくならない (設定変更が反映されるだけ)。lock を進めてから activate する。
# Homebrew 側は homebrew.nix の onActivation.upgrade で rebuild に含まれる。
update:
	@$(CHECK_PROFILE)
	@$(MAKE) update-lock
	@$(MAKE) rebuild PROFILE=$(PROFILE)
	@if git -C $(DOTFILES_DIR) diff --quiet -- $(NIX_DARWIN_DIR)/flake.lock; then \
		echo "flake.lock に変更はありません (既に最新)"; \
	else \
		echo ""; \
		echo "flake.lock が更新されています。動作を確認したらコミットしてください:"; \
		echo "  git add nix/nix-darwin/flake.lock"; \
		echo "戻したいときは git checkout nix/nix-darwin/flake.lock してから make rebuild。"; \
	fi

# INPUT で対象を絞れる (例: INPUT=nixpkgs)。未指定なら全 input を更新する。
# PROFILE には依存しない (lock は profile 共通) ので単体で叩ける。
update-lock:
	@$(LOAD_NIX); \
	nix $(NIX_FLAGS) flake update $(INPUT) --flake $(NIX_DARWIN_DIR)

doctor:
	@echo "--- 前提コマンド ---"
	@for c in nix darwin-rebuild brew; do \
		if command -v $$c >/dev/null 2>&1; then \
			echo "  [OK]   $$c ($$(command -v $$c))"; \
		else \
			echo "  [NG]   $$c が見つかりません"; \
		fi; \
	done
	@echo "--- symlink (未反映のものがあれば下に出ます) ---"
	@$(LINK_SH) --dry-run | grep -v '^  \[OK\]' || true
