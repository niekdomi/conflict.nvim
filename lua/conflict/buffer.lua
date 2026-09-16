local config = require("conflict.config")
local git = require("conflict.git")
local parser = require("conflict.parser")
local ui = require("conflict.ui")

local M = {}

---@alias ConflictSide 'current'|'incoming'|'both'|'base'|'none'

---Sections to concatenate for each resolution, in the order they are kept.
local RESOLUTIONS = {
    current = { "current" },
    incoming = { "incoming" },
    both = { "current", "incoming" },
    base = { "ancestor" },
    none = {},
}

---@type table<integer, { positions: ConflictPosition[], tick: integer, active: boolean }>
local state = {}

---@param bufnr integer
---@return ConflictPosition[]? @Known conflicts, or nil if the buffer was never scanned.
function M.positions(bufnr)
    local data = state[bufnr]
    return data and data.positions
end

---@param bufnr integer
---@return boolean @Whether the buffer needs re-parsing.
function M.is_stale(bufnr)
    local data = state[bufnr]
    return not data or data.tick ~= vim.api.nvim_buf_get_changedtick(bufnr)
end

---@param bufnr integer @Buffer to drop cached state for.
function M.forget(bufnr)
    state[bufnr] = nil
end

---Discards all cached state, so every buffer re-parses under a new config.
function M.reset()
    state = {}
end

---Resolves a conflict when its action label is clicked.
local function handle_click()
    local mouse = vim.fn.getmousepos()
    if not mouse.winid or mouse.winid == 0 then
        return
    end

    local positions = M.positions(vim.api.nvim_win_get_buf(mouse.winid))
    if not positions then
        return
    end

    for _, pos in ipairs(positions) do
        local row = ui.anchor(pos)
        local anchor = vim.fn.screenpos(mouse.winid, row + 1, 1)
        if anchor.row > 0 and mouse.screenrow == anchor.row - 1 then
            local actions = ui.actions(pos.ancestor_row ~= nil)
            local side = ui.action_at_col(mouse.screencol - anchor.col + 1, actions)
            if side then
                vim.api.nvim_win_set_cursor(mouse.winid, { row + 1, 0 })
                vim.api.nvim_win_call(mouse.winid, function()
                    M.choose(side)
                end)
            end
            return
        end
    end
end

---@param bufnr integer @Buffer handle to clear conflict mappings from.
local function clear_mappings(bufnr)
    for _, km in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
        if km.lhs and km.desc and km.desc:find("^Conflict: ") then
            pcall(vim.keymap.del, "n", km.lhs, { buffer = bufnr })
        end
    end
end

---@param bufnr integer @Buffer handle to set conflict mappings on.
local function set_mappings(bufnr)
    clear_mappings(bufnr)

    for action, key in pairs(config.options.default_mappings) do
        local handler = M.commands[action]
        if type(key) == "string" and key ~= "" and handler then
            vim.keymap.set("n", key, handler, {
                desc = "Conflict: " .. action,
                buffer = bufnr,
                silent = true,
            })
        end
    end

    if config.options.show_actions then
        vim.keymap.set("n", "<LeftRelease>", handle_click, {
            desc = "Conflict: click action",
            buffer = bufnr,
            silent = true,
        })
    end
end

---Re-scans a buffer and refreshes its decorations and mappings.
---@param bufnr integer @Buffer handle to scan for conflicts.
function M.parse(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local positions = parser.detect(lines)
    local has_conflict = #positions > 0
    local was_active = state[bufnr] ~= nil and state[bufnr].active or false

    ui.clear(bufnr)
    state[bufnr] = {
        positions = positions,
        tick = vim.api.nvim_buf_get_changedtick(bufnr),
        active = has_conflict,
    }

    if config.options.disable_diagnostics then
        vim.diagnostic.enable(not has_conflict, { bufnr = bufnr })
    end

    if has_conflict then
        ui.draw(bufnr, positions, lines)
    end

    -- Mappings only change when the buffer crosses the conflict/no-conflict line.
    if has_conflict ~= was_active then
        if has_conflict then
            set_mappings(bufnr)
        else
            clear_mappings(bufnr)
        end
    end
end

---Replaces the conflict under the cursor with the chosen side.
---@param side ConflictSide @Which side of the conflict to keep.
function M.choose(side)
    local sections = RESOLUTIONS[side]
    local bufnr = vim.api.nvim_get_current_buf()
    local positions = M.positions(bufnr)
    if not sections or not positions then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(0)[1] - 1
    local pos = vim.iter(positions):find(function(p)
        return cursor >= p.start_row and cursor <= p.end_row
    end)
    if not pos then
        return
    end

    local replacement = {}
    for _, name in ipairs(sections) do
        local range = pos[name]
        -- `base` is only resolvable on a diff3 conflict.
        if not range then
            return
        end
        vim.list_extend(
            replacement,
            vim.api.nvim_buf_get_lines(bufnr, range.content_start, range.content_end + 1, false)
        )
    end

    vim.api.nvim_buf_set_lines(bufnr, pos.start_row, pos.end_row + 1, false, replacement)
    M.parse(bufnr)
end

---Moves the cursor to the next or previous conflict, wrapping at either end.
---@param direction "next"|"prev" @Jump direction.
function M.navigate(direction)
    local positions = M.positions(vim.api.nvim_get_current_buf())
    if not positions or #positions == 0 then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(0)[1] - 1
    local it = vim.iter(positions)
    if direction == "prev" then
        it:rev()
    end

    local target = it:find(function(p)
        if direction == "next" then
            return p.start_row > cursor
        end
        return p.start_row < cursor
    end) or (direction == "next" and positions[1] or positions[#positions])

    vim.api.nvim_win_set_cursor(0, { target.start_row + 1, 0 })
end

---Every action reachable from `:Conflict` and from the default mappings.
---@type table<string, fun()>
M.commands = {
    current = function()
        M.choose("current")
    end,
    incoming = function()
        M.choose("incoming")
    end,
    both = function()
        M.choose("both")
    end,
    base = function()
        M.choose("base")
    end,
    none = function()
        M.choose("none")
    end,
    next = function()
        M.navigate("next")
    end,
    prev = function()
        M.navigate("prev")
    end,
    list = function()
        git.list()
    end,
    qflist = function()
        git.qflist()
    end,
    refresh = function()
        M.parse(vim.api.nvim_get_current_buf())
    end,
}

return M
