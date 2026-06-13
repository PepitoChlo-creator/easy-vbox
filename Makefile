.PHONY: test
test:
	bash -n scripts/create-vm.sh
	./scripts/create-vm.sh --list-presets || true
