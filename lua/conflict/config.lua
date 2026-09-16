local M = {}

---@class ConflictConfig
---@field default_mappings table<string, string|false>
---@field show_actions boolean
---@field disable_diagnostics boolean
---@field highlights { current: string, incoming: string, ancestor: string }

---@type ConflictConfig
local DEFAULTS = {
    default_mappings = {
        current = "cc",
        incoming = "ci",
        both = "cb",
        base = "cB",
        next = "]x",
        prev = "[x",
        none = false,
    },
    show_actions = true,
    disable_diagnostics = true,
    highlights = {
        current = "DiffText",
        incoming = "DiffAdd",
        ancestor = "DiffChange",
    },
}

---Active configuration. |M.apply| replaces this table wholesale, so read fields
---through it on demand rather than caching them at module scope.
---@type ConflictConfig
M.options = vim.deepcopy(DEFAULTS)

---@param opts? ConflictConfig @User overrides, merged over the defaults.
function M.apply(opts)
    M.options = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), opts or {})
end

return M
