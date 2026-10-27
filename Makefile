SHELL := /bin/bash
SCRIPTS := scripts/create-vm.sh scripts/install.sh scripts/install-guest-additions.sh scripts/validate-presets.sh
TEST_FILES := tests/run-tests.sh tests/mock/VBoxManage

.PHONY: help test lint syntax presets catalog dry-run list

help: ## Show this help
	@printf 'EasyVbox — make targets\n\n'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

test: lint presets catalog ## Run syntax checks, ShellCheck, validations and the test suite
	./tests/run-tests.sh

lint: syntax ## ShellCheck every script (warnings are errors)
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -S style $(SCRIPTS) $(TEST_FILES) && echo "shellcheck: clean"; \
	else \
		echo "shellcheck not installed — skipping (see docs/INSTALL.md)"; \
	fi

syntax: ## bash -n on every script
	@for f in $(SCRIPTS) $(TEST_FILES); do bash -n "$$f" || exit 1; done
	@echo "syntax: ok"

presets: ## Validate all presets and their documentation
	./scripts/validate-presets.sh

catalog: ## Validate the ISO download catalog
	./scripts/validate-catalog.sh

dry-run: ## Print a plan without touching anything
	./scripts/create-vm.sh --iso none --preset minimal-testing --dry-run

isos: ## List the images available to --download
	./scripts/create-vm.sh --list-isos

list: ## List the available presets
	./scripts/create-vm.sh --list-presets
