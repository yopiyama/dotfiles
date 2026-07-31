DOTFILES_DIR := $(shell cd "$(dir $(lastword $(MAKEFILE_LIST)))" && pwd)
NIX_DARWIN_DIR := $(DOTFILES_DIR)/nix/nix-darwin
LINK_SH := $(DOTFILES_DIR)/scripts/link.sh

# personal | work
PROFILE ?= personal

.DEFAULT_GOAL := help
.PHONY: help setup link link-dry rebuild dry-run doctor

# setup は link → rebuild の順序に意味がある (link が Homebrew 本体を用意し、
# rebuild がその上に cask/brew を宣言的に入れる) ため並列実行させない。
.NOTPARALLEL:

help:
	@echo "========================================="
	@echo "  dotfiles"
	@echo "========================================="
	@echo ""
	@echo "  make setup      - 初回セットアップ (前提チェック → link → rebuild)"
	@echo "  make link       - symlink 作成 + Homebrew 準備 (scripts/link.sh)"
	@echo "  make link-dry   - link の内容を表示するだけ (何も変更しない)"
	@echo "  make rebuild    - darwin-rebuild switch (PROFILE=personal|work, default: personal)"
	@echo "  make dry-run    - darwin-rebuild の評価だけ確認 (activate しない)"
	@echo "  make doctor     - 前提コマンドと symlink の状態を確認"
	@echo ""
	@echo "  例: make rebuild PROFILE=work"
	@echo ""

# nix 本体だけは自動インストールしない (sudo と再ログインが必要なため案内に留める)。
setup:
	@command -v nix >/dev/null 2>&1 || { \
		echo "nix が見つかりません。先に Determinate Systems のインストーラを実行してください:"; \
		echo "  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install"; \
		echo "インストール後、シェルを開き直してから make setup を再実行してください。"; \
		exit 1; \
	}
	@$(MAKE) link
	@$(MAKE) rebuild PROFILE=$(PROFILE)

link:
	@$(LINK_SH)

link-dry:
	@$(LINK_SH) --dry-run

rebuild:
	@sudo darwin-rebuild switch --flake $(NIX_DARWIN_DIR)#$(PROFILE)

dry-run:
	@nix build $(NIX_DARWIN_DIR)#darwinConfigurations.$(PROFILE).system --dry-run

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
