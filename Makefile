.PHONY: lint test container clean help

SHELL := bash
.SHELLFLAGS := -euo pipefail -c

SHELL_FILES := $(shell find bin lib container share -type f \
                  \( -name '*.sh' -o -name 'jetson-restore' -o -name 'entrypoint.sh' \) 2>/dev/null)

help:
	@echo "Targets:"
	@echo "  lint       run shellcheck + shfmt"
	@echo "  test       run bats unit tests"
	@echo "  container  build the flash container locally"
	@echo "  clean      remove ./work/"

lint:
	$(if $(SHELL_FILES),shellcheck -S warning $(SHELL_FILES),@echo "No shell files found; skipping shellcheck")
	$(if $(SHELL_FILES),shfmt -d -i 4 -ci $(SHELL_FILES),@echo "No shell files found; skipping shfmt")

test:
	./test/helpers/bats-core/bin/bats -r test/unit

container:
	docker build -t jetson-restore:dev -f container/Containerfile container/

clean:
	rm -rf work/
