-- Loaded inside the child Neovim with `dofile`, so the tests can drive it
-- without embedding Lua in strings. Everything here runs in the child.

local Child = {}

---@return string[] @Sorted left-hand sides of every mapping the plugin owns.
function Child.mappings()
    local lhs = {}
    for _, km in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
        if km.desc and km.desc:find("^Conflict: ") then
            table.insert(lhs, km.lhs)
        end
    end
    table.sort(lhs)
    return lhs
end

---@return string @The rendered action line, chunks concatenated.
function Child.action_text()
    local ns = vim.api.nvim_create_namespace("conflict-actions")
    local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
    local details = marks[1] and marks[1][4]
    local chunks = details and details.virt_lines and details.virt_lines[1]
    if chunks == nil then
        return ""
    end

    local out = {}
    for _, chunk in ipairs(chunks) do
        table.insert(out, chunk[1])
    end
    return table.concat(out)
end

---@return table<string, integer[]> @Highlight group to its `{ first, last }` row.
function Child.section_rows()
    local ns = vim.api.nvim_create_namespace("conflict")
    local seen = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
        local details = mark[4]
        if details and details.hl_group and details.end_row and not details.virt_text then
            seen[details.hl_group] = { mark[2], details.end_row }
        end
    end
    return seen
end

---Clicks the action line above the first conflict.
---@param column integer @1-based display column within the action line.
---@return boolean|string @True if the click handler ran, or a reason it could not.
function Child.click(column)
    local callback
    for _, km in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
        if km.lhs == "<LeftRelease>" then
            callback = km.callback
        end
    end
    if type(callback) ~= "function" then
        return "no mapping"
    end

    local win = vim.api.nvim_get_current_win()
    local anchor = vim.fn.screenpos(win, 2, 1)
    local real = vim.fn.getmousepos

    -- The action line is a virtual line drawn directly above the marker row.
    vim.fn.getmousepos = function()
        return {
            winid = win,
            screenrow = anchor.row - 1,
            screencol = anchor.col + column - 1,
        }
    end
    local ok = pcall(callback)
    vim.fn.getmousepos = real

    return ok
end

---Builds a throwaway repository whose merge leaves `sub/deep/f.txt` conflicted.
---@return string @Absolute path of the repository root.
function Child.make_repo()
    local repo = vim.fn.tempname()
    vim.fn.mkdir(repo .. "/sub/deep", "p")

    local function git(...)
        return vim.system({ "git", "-C", repo, ... }, { text = true }):wait()
    end

    git("init", "-q", "-b", "main", ".")
    git("config", "user.email", "test@example.com")
    git("config", "user.name", "test")

    local file = repo .. "/sub/deep/f.txt"
    vim.fn.writefile({ "base" }, file)
    git("add", "-A")
    git("commit", "-qm", "init")

    git("checkout", "-qb", "other")
    vim.fn.writefile({ "other" }, file)
    git("commit", "-q", "-a", "-m", "other")

    git("checkout", "-q", "main")
    vim.fn.writefile({ "main" }, file)
    git("commit", "-q", "-a", "-m", "main")
    git("merge", "other")

    return repo
end

---Creates an empty directory and makes it the working directory.
---@param as_repo boolean @Whether to initialize a repository inside it.
function Child.chdir_empty(as_repo)
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    if as_repo then
        vim.system({ "git", "-C", dir, "init", "-q", "-b", "main", "." }):wait()
    end
    vim.uv.chdir(dir)
end

---@return { lnum: integer, name: string }[] @A summary of the quickfix list.
function Child.quickfix()
    return vim.tbl_map(function(entry)
        return { lnum = entry.lnum, name = vim.fn.bufname(entry.bufnr) }
    end, vim.fn.getqflist())
end

_G.Child = Child
return Child
