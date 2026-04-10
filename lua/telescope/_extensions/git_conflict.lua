local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

---@param opts? table @Telescope picker options.
local function pick_conflicts(opts)
    opts = opts or {}

    local files = require("conflict").get_conflicted_files()
    if #files == 0 then
        vim.notify("No conflicted files found", vim.log.levels.INFO)
        return
    end

    pickers
        .new(opts, {
            prompt_title = "Git Conflicts",
            finder = finders.new_table({ results = files }),
            sorter = conf.generic_sorter(opts),
            previewer = conf.file_previewer(opts),
            attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                    local entry = action_state.get_selected_entry()
                    actions.close(prompt_bufnr)
                    vim.cmd.edit(entry[1])
                end)
                return true
            end,
        })
        :find()
end

return require("telescope").register_extension({
    exports = {
        git_conflict = pick_conflicts,
    },
})
