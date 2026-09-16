local new_set, expect = MiniTest.new_set, MiniTest.expect
local eq = expect.equality

local H = require("helpers")
local child = H.new_child()

local T = new_set({ hooks = H.hooks(child) })

local function action_marks(details)
    local ns = child.api.nvim_create_namespace("conflict-actions")
    return child.api.nvim_buf_get_extmarks(0, ns, 0, -1, details and { details = true } or {})
end

T["anchors one action line per conflict"] = function()
    child.open(H.TWO)
    local rows = {}
    for _, m in ipairs(action_marks()) do
        table.insert(rows, m[2])
    end
    eq(rows, { 1, 8 })
end

T["draws the action line above the conflict"] = function()
    child.open(H.TWO)
    eq(action_marks(true)[1][4].virt_lines_above, true)
end

T["labels a two-sided conflict"] = function()
    child.open(H.TWO)
    eq(child.lua_get("Child.action_text()"), "Accept Current | Accept Incoming | Accept Both")
end

T["adds the base label on a diff3 conflict"] = function()
    child.open(H.DIFF3)
    eq(
        child.lua_get("Child.action_text()"),
        "Accept Current | Accept Incoming | Accept Both | Accept Base"
    )
end

T["show_actions=false draws no action line"] = function()
    child.setup_conflict({ show_actions = false })
    child.open(H.TWO)
    eq(#action_marks(), 0)
end

T["highlights each section over its own range"] = function()
    child.open(H.DIFF3)
    eq(child.lua_get("Child.section_rows()"), {
        ConflictCurrent = { 0, 2 },
        ConflictAncestor = { 2, 4 },
        ConflictIncoming = { 5, 7 },
    })
end

T["clears decorations when the conflict is resolved"] = function()
    child.open(H.ONE)
    child.goto_line(3)
    child.cmd("Conflict current")
    local ns = child.api.nvim_create_namespace("conflict")
    eq(#child.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}), 0)
end

--------------------------------------------------------------------------------
-- Screen
--------------------------------------------------------------------------------

local SCREENS = {
    plain = { "before", "<<<<<<< HEAD", "cur", "=======", "inc", ">>>>>>> b", "after" },
    diff3 = { "before", unpack(H.DIFF3) },
    at_row_zero = { "<<<<<<< HEAD", "cur", "=======", "inc", ">>>>>>> b", "tail" },
    empty_sides = { "a", "<<<<<<< HEAD", "=======", ">>>>>>> b", "z" },
    multi = H.TWO,
}

T["screen"] = new_set({
    parametrize = { { "plain" }, { "diff3" }, { "at_row_zero" }, { "empty_sides" }, { "multi" } },
})

T["screen"]["renders the inline UI"] = function(name)
    child.open(SCREENS[name])
    expect.reference_screenshot(child.get_screenshot())
end

return T
