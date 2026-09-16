local new_set, expect = MiniTest.new_set, MiniTest.expect
local eq = expect.equality

local H = require("helpers")
local child = H.new_child()

local T = new_set({ hooks = H.hooks(child) })

local DEFAULTS = { "<LeftRelease>", "[x", "]x", "cB", "cb", "cc", "ci" }

T["a conflicted buffer gets the default mappings"] = function()
    child.open(H.TWO)
    eq(child.lua_get("Child.mappings()"), DEFAULTS)
end

T["a clean buffer gets no mappings"] = function()
    child.open({ "no conflicts here" })
    eq(child.lua_get("Child.mappings()"), {})
end

T["mappings are removed once the last conflict is resolved"] = function()
    child.open(H.ONE)
    child.goto_line(3)
    child.cmd("Conflict current")
    eq(child.lua_get("Child.mappings()"), {})
end

T["mappings respect false and overrides"] = function()
    child.setup_conflict({ default_mappings = { current = false, both = "gb" } })
    child.open(H.TWO)
    eq(child.lua_get("Child.mappings()"), { "<LeftRelease>", "[x", "]x", "cB", "ci", "gb" })
end

T["show_actions=false does not claim <LeftRelease>"] = function()
    child.setup_conflict({ show_actions = false })
    child.open(H.ONE)
    eq(child.lua_get("Child.mappings()"), { "[x", "]x", "cB", "cb", "cc", "ci" })
end

T["a mapping resolves the conflict under the cursor"] = function()
    child.open(H.ONE)
    child.goto_line(3)
    child.type_keys("cc")
    eq(child.body(), { "top", "mine1", "mine2", "middle" })
end

--------------------------------------------------------------------------------
-- Mouse
--------------------------------------------------------------------------------

T["mouse"] = new_set({
    hooks = {
        pre_case = function()
            child.setup_conflict()
        end,
    },
    parametrize = {
        { 1, { "top", "mine1", "mine2", "middle" } },
        { 20, { "top", "theirs1", "middle" } },
        { 38, { "top", "mine1", "mine2", "theirs1", "middle" } },
    },
})

T["mouse"]["clicking a label resolves that side"] = function(col, want)
    child.open(H.ONE)
    child.lua_get("Child.click(...)", { col })
    eq(child.body(), want)
end

T["mouse"]["clicking a separator resolves nothing"] = function()
    child.open(H.ONE)
    child.lua_get("Child.click(...)", { 16 })
    eq(child.body(), H.ONE)
end

T["mouse"]["clicking past the last label resolves nothing"] = function()
    child.open(H.ONE)
    child.lua_get("Child.click(...)", { 60 })
    eq(child.body(), H.ONE)
end

return T
