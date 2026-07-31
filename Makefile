DOTFILES_DIR := $(shell cd "$(dir $(lastword $(MAKEFILE_LIST)))" && pwd)
NIX_DARWIN_DIR := $(DOTFILES_DIR)/nix/nix-darwin

# personal | work
PROFILE ?= personal

.DEFAULT_GOAL := help
.PHONY: help install install-dry-run rebuild dry-run

help:
	@echo "========================================="
	@echo "  dotfiles"
	@echo "========================================="
	@echo ""
	@echo "  make install            - install.sh を実行 (symlink 作成 + Homebrew 準備)"
	@echo "  make install-dry-run    - install.sh --dry-run (何も変更せず表示のみ)"
	@echo "  make rebuild            - darwin-rebuild switch (PROFILE=personal|work, default: personal)"
	@echo "  make dry-run            - darwin-rebuild の評価だけ確認 (activate しない)"
	@echo ""
	@echo "  例: make rebuild PROFILE=work"
	@echo ""

install:
	@$(DOTFILES_DIR)/install.sh

install-dry-run:
	@$(DOTFILES_DIR)/install.sh --dry-run

rebuild:
	@sudo darwin-rebuild switch --flake $(NIX_DARWIN_DIR)#$(PROFILE)

dry-run:
	@nix build $(NIX_DARWIN_DIR)#darwinConfigurations.$(PROFILE).system --dry-run
