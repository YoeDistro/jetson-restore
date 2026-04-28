.PHONY: lint test clean help

SHELL := bash
.SHELLFLAGS := -euo pipefail -c

SHELL_FILES := $(shell find bin lib share -type f \
                  \( -name '*.sh' -o -name 'jetson-restore' \) 2>/dev/null)

help:
	@echo "Targets:"
	@echo "  lint       run shellcheck + shfmt"
	@echo "  test       run bats unit tests"
	@echo "  clean      remove ./work/"

lint:
	$(if $(SHELL_FILES),shellcheck -S warning $(SHELL_FILES),@echo "No shell files found; skipping shellcheck")
	$(if $(SHELL_FILES),shfmt -d -i 4 -ci $(SHELL_FILES),@echo "No shell files found; skipping shfmt")

test:
	./test/helpers/bats-core/bin/bats -r test/unit

clean:
	rm -rf work/
