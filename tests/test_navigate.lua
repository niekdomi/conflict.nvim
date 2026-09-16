local new_set, expect = MiniTest.new_set, MiniTest.expect
local eq = expect.equality

local H = require("helpers")
local child = H.new_child()

local T = new_set({ hooks = H.hooks(child) })

---@param from integer @1-based line to start on.
---@param direction "next"|"prev"
---@return integer @1-based line the cursor lands on.
local function nav(from, direction)
    child.goto_line(from)
    child.cmd("Conflict " .. direction)
    return child.api.nvim_win_get_cursor(0)[1]
end

T["next advances through every conflict"] = function()
    child.open(H.THREE)
    eq(nav(1, "next"), 7)
    eq(nav(7, "next"), 13)
end

T["next wraps at the last conflict"] = function()
    child.open(H.THREE)
    eq(nav(13, "next"), 1)
end

T["prev walks backwards"] = function()
    child.open(H.THREE)
    eq(nav(13, "prev"), 7)
    eq(nav(7, "prev"), 1)
end

T["prev wraps at the first conflict"] = function()
    child.open(H.THREE)
    eq(nav(1, "prev"), 13)
end

T["next from before any conflict finds the first"] = function()
    child.open(H.TWO)
    eq(nav(1, "next"), 2)
end

T["prev from after every conflict finds the last"] = function()
    child.open(H.TWO)
    eq(nav(14, "prev"), 9)
end

T["is a no-op in a clean buffer"] = function()
    child.open({ "nothing", "to", "see" })
    eq(nav(2, "next"), 2)
end

return T
