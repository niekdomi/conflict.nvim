local parser = require("conflict.parser")

local M = {}

---@param ... string @Arguments to pass to git.
---@return string? @Trimmed stdout, or nil if the command failed.
local function git(...)
    local result = vim.system({ "git", ... }, { text = true }):wait()
    -- `stdout` is nil when the stream is disabled, which `vim.trim` will not accept.
    return result.code == 0 and vim.trim(result.stdout or "") or nil
end

---@return string[] @Absolute paths of files with unmerged conflicts.
function M.get_conflicted_files()
    local root = git("rev-parse", "--show-toplevel")
    local unmerged = root and git("diff", "--name-only", "--diff-filter=U")
    if not unmerged then
        return {}
    end

    -- Git reports paths relative to the repository root, not the current directory.
    return vim.iter(vim.split(unmerged, "\n", { trimempty = true }))
        :map(function(path)
            return root .. "/" .. path
        end)
        :totable()
end

---Opens a picker to select and open a file with unmerged conflicts.
function M.list()
    local files = M.get_conflicted_files()
    if #files == 0 then
        vim.notify("No conflicted files found", vim.log.levels.INFO)
        return
    end

    vim.ui.select(files, { prompt = "Git Conflicts" }, function(choice)
        if choice then
            vim.cmd.edit(vim.fn.fnameescape(choice))
        end
    end)
end

---Populates the quickfix list with every conflict in every conflicted file.
function M.qflist()
    local files = M.get_conflicted_files()
    if #files == 0 then
        vim.notify("No conflicted files found", vim.log.levels.INFO)
        return
    end

    local items = {}
    for _, file in ipairs(files) do
        local ok, lines = pcall(vim.fn.readfile, file)
        if ok and type(lines) == "table" then
            for _, pos in ipairs(parser.detect(lines)) do
                table.insert(items, {
                    filename = file,
                    lnum = pos.start_row + 1,
                    text = lines[pos.start_row + 1],
                })
            end
        end
    end

    vim.fn.setqflist({}, " ", { title = "Git Conflicts", items = items })
    vim.cmd.copen()
end

return M
