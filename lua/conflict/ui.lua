local config = require("conflict.config")

local M = {}

M.NAMESPACE = vim.api.nvim_create_namespace("conflict")
M.ACTIONS_NAMESPACE = vim.api.nvim_create_namespace("conflict-actions")

---Actions in render order. `base` is only offered on conflicts with an ancestor.
local ACTION_ORDER = { "current", "incoming", "both", "base" }
local ACTION_LABELS = {
    current = "Accept Current",
    incoming = "Accept Incoming",
    both = "Accept Both",
    base = "Accept Base",
}
local ACTION_SEPARATOR = " | "
local SEPARATOR_WIDTH = vim.api.nvim_strwidth(ACTION_SEPARATOR)

---Marker lines are re-rendered as virtual text, which must be padded to cover
---the rest of the line so the label highlight reaches the window edge.
local LABEL_PADDING = 200

---@param bufnr? integer @Buffer handle, 0 or nil for the current buffer.
---@return integer
local function resolve_buf(bufnr)
    return (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
end

---@param has_ancestor boolean @Whether the conflict has a base section.
---@return { text: string, side: ConflictSide }[]
function M.actions(has_ancestor)
    local actions = {}
    for _, side in ipairs(ACTION_ORDER) do
        local text = ACTION_LABELS[side]
        if text and text ~= "" and (side ~= "base" or has_ancestor) then
            table.insert(actions, { text = text, side = side })
        end
    end
    return actions
end

---@param actions { text: string, side: ConflictSide }[]
---@return table[] @Virtual line chunks.
local function render(actions)
    local chunks = {}
    for i, action in ipairs(actions) do
        if i > 1 then
            table.insert(chunks, { ACTION_SEPARATOR, "NonText" })
        end
        table.insert(chunks, { action.text, "Comment" })
    end
    return chunks
end

---`virt_lines_above` cannot draw above the first line of a buffer, so a conflict
---starting on row 0 anchors its action line on the first content row instead.
---@param pos ConflictPosition
---@return integer
function M.anchor(pos)
    return pos.start_row > 0 and pos.start_row or pos.current.content_start
end

---@param col integer @1-based display column within the rendered action line.
---@param actions { text: string, side: ConflictSide }[]
---@return ConflictSide? @The action at that column, or nil.
function M.action_at_col(col, actions)
    local cursor = 1
    for _, action in ipairs(actions) do
        local width = vim.api.nvim_strwidth(action.text)
        if col >= cursor and col < cursor + width then
            return action.side
        end
        cursor = cursor + width + SEPARATOR_WIDTH
    end
end

---@param bufnr integer @Target buffer handle.
---@param positions ConflictPosition[] @Conflicts to decorate.
---@param lines string[] @All buffer lines, for marker label text.
function M.draw(bufnr, positions, lines)
    local actions = render(M.actions(false))
    local actions_with_base = render(M.actions(true))

    ---Re-renders a marker line with a trailing label, in the label highlight.
    local function set_label(row, hl, suffix)
        local text = (lines[row + 1] or "") .. suffix .. string.rep(" ", LABEL_PADDING)
        vim.api.nvim_buf_set_extmark(bufnr, M.NAMESPACE, row, 0, {
            hl_group = hl,
            virt_text = { { text, hl } },
            virt_text_pos = "overlay",
        })
    end

    for _, pos in ipairs(positions) do
        if config.options.show_actions then
            vim.api.nvim_buf_set_extmark(bufnr, M.ACTIONS_NAMESPACE, M.anchor(pos), 0, {
                virt_lines = { pos.ancestor_row and actions_with_base or actions },
                virt_lines_above = true,
            })
        end

        vim.api.nvim_buf_set_extmark(bufnr, M.NAMESPACE, pos.middle_row, 0, {
            line_hl_group = "NonText",
        })

        set_label(pos.start_row, "ConflictCurrentLabel", " (Current)")
        vim.api.nvim_buf_set_extmark(bufnr, M.NAMESPACE, pos.start_row, 0, {
            hl_group = "ConflictCurrent",
            end_row = pos.ancestor_row or pos.middle_row,
            hl_eol = true,
        })

        if pos.ancestor_row then
            set_label(pos.ancestor_row, "ConflictAncestorLabel", " (Base)")
            vim.api.nvim_buf_set_extmark(bufnr, M.NAMESPACE, pos.ancestor_row, 0, {
                hl_group = "ConflictAncestor",
                end_row = pos.middle_row,
                hl_eol = true,
            })
        end

        set_label(pos.end_row, "ConflictIncomingLabel", " (Incoming)")
        vim.api.nvim_buf_set_extmark(bufnr, M.NAMESPACE, pos.middle_row + 1, 0, {
            hl_group = "ConflictIncoming",
            end_row = pos.end_row + 1,
            hl_eol = true,
        })
    end
end

---@param bufnr? integer @Buffer handle, 0 or nil for current.
function M.clear(bufnr)
    local b = resolve_buf(bufnr)
    if not vim.api.nvim_buf_is_valid(b) then
        return
    end
    vim.api.nvim_buf_clear_namespace(b, M.NAMESPACE, 0, -1)
    vim.api.nvim_buf_clear_namespace(b, M.ACTIONS_NAMESPACE, 0, -1)
end

return M
