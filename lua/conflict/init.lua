local buffer = require("conflict.buffer")
local config = require("conflict.config")
local git = require("conflict.git")
local highlights = require("conflict.highlights")
local ui = require("conflict.ui")

local M = {}

M.choose = buffer.choose
M.navigate = buffer.navigate
M.clear = ui.clear
M.get_conflicted_files = git.get_conflicted_files
M.list = git.list
M.qflist = git.qflist

local COMMAND_NAMES = vim.tbl_keys(buffer.commands)
table.sort(COMMAND_NAMES)

---@param opts? ConflictConfig @User configuration overrides.
function M.setup(opts)
    config.apply(opts)
    buffer.reset()
    highlights.set()

    -- Recreated on every setup() so repeated calls do not stack duplicate handlers.
    local augroup = vim.api.nvim_create_augroup("ConflictCommands", { clear = true })

    vim.api.nvim_create_user_command("Conflict", function(args)
        local run = buffer.commands[args.args]
        if not run then
            vim.api.nvim_echo(
                { { "Conflict: Invalid command " .. args.args, "ErrorMsg" } },
                true,
                { err = true }
            )
            return
        end
        run()
    end, {
        nargs = 1,
        desc = "Resolve or navigate git conflicts",
        complete = function(arg_lead)
            return vim.tbl_filter(function(name)
                return vim.startswith(name, arg_lead)
            end, COMMAND_NAMES)
        end,
    })

    vim.api.nvim_create_autocmd("ColorScheme", { group = augroup, callback = highlights.set })

    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        group = augroup,
        callback = function(args)
            buffer.forget(args.buf)
        end,
    })

    vim.api.nvim_set_decoration_provider(ui.NAMESPACE, {
        on_win = function(_, _, bufnr)
            if
                buffer.is_stale(bufnr)
                and vim.bo[bufnr].buftype == ""
                and vim.bo[bufnr].modifiable
            then
                buffer.parse(bufnr)
            end
        end,
    })

    local bufnr = vim.api.nvim_get_current_buf()
    if vim.bo[bufnr].buftype == "" and vim.bo[bufnr].modifiable then
        buffer.parse(bufnr)
    end
end

return M
