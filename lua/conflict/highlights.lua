local config = require("conflict.config")

local M = {}

---@param color string|integer @Hex string, color name, or integer RGB value.
---@param percent integer @Percentage to lighten or darken.
---@return string @Hex color string.
local function shade(color, percent)
    local c = ((type(color) == "string") and vim.api.nvim_get_color_by_name(color)) or color
    if c == -1 then
        return "#000000"
    end

    local r, g, b = math.floor(c / 65536), math.floor(c / 256) % 256, c % 256
    local ratio = (100 + percent) / 100
    local alter = function(val)
        return math.max(0, math.min(255, math.floor(val * ratio)))
    end

    return string.format("#%02X%02X%02X", alter(r), alter(g), alter(b))
end

---@param name string @Highlight group name.
---@param fallback string @Hex fallback if the group has no resolved background.
---@return string|integer
local function bg_of(name, fallback)
    return vim.api.nvim_get_hl(0, { name = name, link = false }).bg or fallback
end

---Defines the conflict highlight groups from the active colorscheme.
function M.set()
    local sources = config.options.highlights
    local is_light = vim.o.background == "light"
    local shade_pct = is_light and -15 or 60
    local current_bg = bg_of(sources.current, is_light and "#C8E6C9" or "#264334")
    local incoming_bg = bg_of(sources.incoming, is_light and "#BBDEFB" or "#214566")
    local ancestor_bg = bg_of(sources.ancestor, is_light and "#E1BEE7" or "#4A2A52")

    for name, opts in pairs({
        ConflictCurrent = { bg = current_bg, bold = true },
        ConflictIncoming = { bg = incoming_bg, bold = true },
        ConflictAncestor = { bg = ancestor_bg, bold = true },
        ConflictCurrentLabel = { bg = shade(current_bg, shade_pct) },
        ConflictIncomingLabel = { bg = shade(incoming_bg, shade_pct) },
        ConflictAncestorLabel = { bg = shade(ancestor_bg, shade_pct) },
    }) do
        opts.default = true
        vim.api.nvim_set_hl(0, name, opts)
    end
end

return M
