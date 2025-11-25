.PHONY: fmt fmt-lsp lint check check-lsp clean

fmt:fmt-lsp
	stylua lua/

fmt-lsp:
	cd lsp && bunx biome format --write

lint:
	selene lua/

lint-lsp:
	cd lsp && bunx biome lint --write

check: fmt lint check-lsp

check-lsp:
	cd lsp && bunx biome check --write


clean:
	rm -rf .luacheckcache
