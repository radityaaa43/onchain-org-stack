.PHONY: test test-render test-helm prereqs

test: test-render test-helm
	@echo "All tests passed."

test-render:
	bats tests/render.bats

test-helm:
	bash tests/helm_test.sh

prereqs:
	bash scripts/check-prereqs.sh
