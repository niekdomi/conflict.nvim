local Helpers = {}

Helpers.root = vim.fn.getcwd()

--------------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------------

---Two conflicts separated by plain text.
Helpers.TWO = {
    "top",
    "<<<<<<< HEAD",
    "mine1",
    "mine2",
    "=======",
    "theirs1",
    ">>>>>>> branch",
    "middle",
    "<<<<<<< HEAD",
    "a-cur",
    "=======",
    "a-inc",
    ">>>>>>> branch",
    "bottom",
}

---The first conflict of |Helpers.TWO| on its own.
Helpers.ONE = vim.list_slice(Helpers.TWO, 1, 8)

---A conflict carrying an ancestor section, as produced by `diff3`.
Helpers.DIFF3 = {
    "<<<<<<< HEAD",
    "cur",
    "||||||| base",
    "ancestor",
    "=======",
    "inc",
    ">>>>>>> branch",
}

---Three conflicts, to catch navigation that restarts instead of advancing.
Helpers.THREE = {}
for _ = 1, 3 do
    vim.list_extend(Helpers.THREE, {
        "<<<<<<< HEAD",
        "cur",
        "=======",
        "inc",
        ">>>>>>> b",
        "gap",
    })
end

--------------------------------------------------------------------------------
-- Child Neovim
--------------------------------------------------------------------------------

---Creates a child Neovim with plugin-aware conveniences attached.
---@return table
function Helpers.new_child()
    local child = MiniTest.new_child_neovim()

    ---Restarts the child and loads the plugin with `config`.
    ---@param config? table
    function child.setup_conflict(config)
        child.restart({ "-u", "NONE" })
        child.lua("vim.opt.rtp:prepend(...)", { Helpers.root })
        child.lua("dofile(...)", { Helpers.root .. "/tests/child_helpers.lua" })
        child.lua("require('conflict').setup(...)", { config or {} })
        child.o.lines, child.o.columns = 20, 60
        child.o.laststatus, child.o.ruler, child.o.number = 0, false, false
    end

    ---Fills the current buffer and forces a parse.
    ---@param lines string[]
    function child.open(lines)
        child.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        child.cmd("Conflict refresh")
    end

    ---@return string[] @Current buffer contents.
    function child.body()
        return child.api.nvim_buf_get_lines(0, 0, -1, false)
    end

    ---@param row integer @1-based line to place the cursor on.
    function child.goto_line(row)
        child.api.nvim_win_set_cursor(0, { row, 0 })
    end

    return child
end

---Standard hooks: a fresh child per case, stopped once the set finishes.
---@param child table
---@param config? table @Passed to `require("conflict").setup()`.
---@return table
function Helpers.hooks(child, config)
    return {
        pre_case = function()
            child.setup_conflict(config)
        end,
        post_once = child.stop,
    }
end

return Helpers
