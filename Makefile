MINI_TEST_URL := https://github.com/nvim-mini/mini.test
NVIM := nvim --headless --noplugin -u tests/minimal_init.lua

.PHONY: test file deps clean

## Run the test suite.
test: deps
	$(NVIM) -c "lua MiniTest.run()"

## Run a single file, e.g. `make file FILE=tests/test_parser.lua`.
file: deps
	$(NVIM) -c "lua MiniTest.run_file('$(FILE)')"

## Fetch the test-only dependency.
deps:
	@test -d deps/mini.test || git clone --filter=blob:none --depth 1 $(MINI_TEST_URL) deps/mini.test

clean:
	rm -rf deps
