local new_set, expect = MiniTest.new_set, MiniTest.expect
local eq = expect.equality

local H = require("helpers")
local child = H.new_child()

local T = new_set({
    hooks = {
        pre_case = function()
            child.setup_conflict()
        end,
        post_once = child.stop,
    },
})

T["cwd"] = new_set({ parametrize = { { "" }, { "/sub/deep" } } })

T["cwd"]["finds the conflicted file"] = function(subdir)
    child.lua("vim.uv.chdir(Child.make_repo() .. ...)", { subdir })

    local files = child.lua_get([[require("conflict").get_conflicted_files()]])
    eq(#files, 1)
    -- Paths must resolve no matter which directory Neovim was started in.
    eq(child.lua_get("vim.uv.fs_stat(...) ~= nil", { files[1] }), true)
end

T["cwd"]["populates the quickfix list"] = function(subdir)
    child.lua("vim.uv.chdir(Child.make_repo() .. ...)", { subdir })
    child.cmd("Conflict qflist")

    local qf = child.lua_get("Child.quickfix()")
    eq(#qf, 1)
    eq(qf[1].lnum, 1)
    eq(qf[1].name:find("f%.txt") ~= nil, true)
end

T["returns nothing outside a repository"] = function()
    child.lua("Child.chdir_empty(false)")
    eq(child.lua_get([[require("conflict").get_conflicted_files()]]), {})
end

T["returns nothing when the repository is clean"] = function()
    child.lua("Child.chdir_empty(true)")
    eq(child.lua_get([[require("conflict").get_conflicted_files()]]), {})
end

return T
