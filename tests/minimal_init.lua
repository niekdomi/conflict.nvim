-- Minimal init used by `make test`. Adds the plugin, the test helpers and
-- mini.test to the runtime, then leaves the runner to `MiniTest.run()`.
local root = vim.fn.getcwd()

vim.opt.rtp:prepend(root)
vim.opt.rtp:prepend(root .. "/deps/mini.test")
package.path = table.concat({ root .. "/tests/?.lua", package.path }, ";")

require("mini.test").setup()
