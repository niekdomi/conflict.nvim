local new_set, expect = MiniTest.new_set, MiniTest.expect
local eq = expect.equality

local H = require("helpers")
local child = H.new_child()

local T = new_set({ hooks = H.hooks(child) })

T["keeps the current side"] = function()
    child.open(H.ONE)
    child.goto_line(3)
    child.cmd("Conflict current")
    eq(child.body(), { "top", "mine1", "mine2", "middle" })
end

T["keeps the incoming side"] = function()
    child.open(H.ONE)
    child.goto_line(3)
    child.cmd("Conflict incoming")
    eq(child.body(), { "top", "theirs1", "middle" })
end

T["keeps both sides in order"] = function()
    child.open(H.ONE)
    child.goto_line(3)
    child.cmd("Conflict both")
    eq(child.body(), { "top", "mine1", "mine2", "theirs1", "middle" })
end

T["keeps neither side"] = function()
    child.open(H.ONE)
    child.goto_line(3)
    child.cmd("Conflict none")
    eq(child.body(), { "top", "middle" })
end

T["diff3"] = new_set({
    parametrize = {
        { "current", { "cur" } },
        { "incoming", { "inc" } },
        { "base", { "ancestor" } },
        { "both", { "cur", "inc" } },
    },
})

T["diff3"]["keeps the chosen side"] = function(side, want)
    child.open(H.DIFF3)
    child.goto_line(2)
    child.cmd("Conflict " .. side)
    eq(child.body(), want)
end

T["base is a no-op without an ancestor"] = function()
    child.open(H.ONE)
    child.goto_line(3)
    child.cmd("Conflict base")
    eq(child.body(), H.ONE)
end

T["is a no-op outside a conflict"] = function()
    child.open(H.TWO)
    child.goto_line(1)
    child.cmd("Conflict current")
    eq(child.body(), H.TWO)
end

T["resolving the first conflict leaves the second decorated"] = function()
    child.open(H.TWO)
    child.goto_line(3)
    child.cmd("Conflict current")
    local ns = child.api.nvim_create_namespace("conflict-actions")
    eq(#child.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}), 1)
end

T["a malformed block does not crash"] = function()
    child.open({ "x", "<<<<<<< HEAD", "orphan", ">>>>>>> branch", "y" })
    child.goto_line(3)
    eq(child.lua_get([[pcall(vim.cmd, "Conflict current")]]), true)
end

T["an unknown side is a no-op"] = function()
    child.open(H.ONE)
    child.goto_line(3)
    child.lua([[require("conflict").choose("nonsense")]])
    eq(child.body(), H.ONE)
end

T["two unnamed buffers keep independent state"] = function()
    child.cmd("enew")
    local first = child.api.nvim_get_current_buf()
    child.open(H.ONE)

    child.cmd("enew")
    child.open({ "no conflict at all" })

    child.api.nvim_set_current_buf(first)
    child.goto_line(3)
    child.cmd("Conflict current")
    eq(child.body(), { "top", "mine1", "mine2", "middle" })
end

return T
