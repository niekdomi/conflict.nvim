local M = {}

local api = vim.api
local map = vim.keymap.set

--------------------------------------------------------------------------------
-- Configuration & Constants
--------------------------------------------------------------------------------

---@alias ConflictSide 'current'|'incoming'|'both'

local NAMESPACE = api.nvim_create_namespace("conflict")
local ACTIONS_NAMESPACE = api.nvim_create_namespace("conflict-actions")
local AUGROUP = api.nvim_create_augroup("ConflictCommands", { clear = true })

local CONFLICT_START = "^<<<<<<<"
local CONFLICT_MIDDLE = "^======="
local CONFLICT_END = "^>>>>>>>"
local CONFLICT_ANCESTOR = "^|||||||"

local config = {
    default_mappings = {
        current = "<leader>cc",
        incoming = "<leader>ci",
        both = "<leader>cb",
        next = "]x",
        prev = "[x",
    },
    show_actions = true,
    disable_diagnostics = true,
    highlights = {
        current = "DiffText",
        incoming = "DiffAdd",
    },
}

local ACTION_LABELS = {
    { text = "Accept Current", side = "current" },
    { text = "Accept Incoming", side = "incoming" },
    { text = "Accept Both", side = "both" },
}

--------------------------------------------------------------------------------
-- State Management
--------------------------------------------------------------------------------

---@type table<string, { bufnr: integer, positions: table[], tick: integer }>
local visited_buffers = {}

--------------------------------------------------------------------------------
-- UI & Highlights
--------------------------------------------------------------------------------

---@param color string|integer @Hex string, color name, or integer RGB value.
---@param percent integer @Percentage to lighten or darken.
---@return string @Hex color string.
local function shade_color(color, percent)
    local c = type(color) == "string" and api.nvim_get_color_by_name(color) or color
    if c == -1 then return "#000000" end

    local r, g, b = math.floor(c / 65536), math.floor(c / 256) % 256, c % 256
    local ratio = (100 + percent) / 100
    local alter = function(val) return math.min(255, math.floor(val * ratio)) end

    return string.format("#%02x%02x%02x", alter(r), alter(g), alter(b))
end

local function set_highlights()
    local h = config.highlights
    local current_bg = (api.nvim_get_hl(0, { name = h.current })).bg or "#264334"
    local incoming_bg = (api.nvim_get_hl(0, { name = h.incoming })).bg or "#214566"

    for name, opts in pairs({
        ConflictCurrent = { bg = current_bg, bold = true },
        ConflictIncoming = { bg = incoming_bg, bold = true },
        ConflictCurrentLabel = { bg = shade_color(current_bg, 60) },
        ConflictIncomingLabel = { bg = shade_color(incoming_bg, 60) },
    }) do
        opts.default = true
        api.nvim_set_hl(0, name, opts)
    end
end

--------------------------------------------------------------------------------
-- Mouse Click
--------------------------------------------------------------------------------

---@param col integer @1-based column within the actions virtual text.
---@return ConflictSide? @The action side at that column, or nil.
local function get_action_at_col(col)
    local cursor = 1
    for _, action in ipairs(ACTION_LABELS) do
        local width = #action.text
        if col >= cursor and col < (cursor + width) then return action.side end
        cursor = cursor + width + 3 -- 3 for " | "
    end
end

local function handle_click()
    local mouse = vim.fn.getmousepos()
    if not mouse.winid or mouse.winid == 0 then return end

    local buf = api.nvim_win_get_buf(mouse.winid)
    if not api.nvim_buf_is_valid(buf) then return end

    for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, ACTIONS_NAMESPACE, 0, -1, {})) do
        local row = mark[2]
        local anchor = vim.fn.screenpos(mouse.winid, row + 1, 1)
        if anchor.row > 0 and mouse.screenrow == anchor.row - 1 then
            local side = get_action_at_col(mouse.screencol - anchor.col + 1)
            if side then
                api.nvim_win_set_cursor(mouse.winid, { row + 1, 0 })
                M.choose(side)
                return
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

---@param bufnr integer @Target buffer handle.
---@param positions table[] @List of conflict position objects.
---@param lines string[] @All buffer lines for label text extraction.
local function draw_sections(bufnr, positions, lines)
    local actions_line = {}
    for i, act in ipairs(ACTION_LABELS) do
        if i > 1 then table.insert(actions_line, { " | ", "NonText" }) end
        table.insert(actions_line, { act.text, "Comment" })
    end

    for _, pos in ipairs(positions) do
        local range_start = pos.current.range_start
        local middle_start = pos.middle.range_start
        local incoming_end = pos.incoming.range_end

        if config.show_actions then
            local anchor = range_start > 0 and range_start or pos.current.content_start
            api.nvim_buf_set_extmark(bufnr, ACTIONS_NAMESPACE, anchor, 0, {
                virt_lines = { actions_line },
                virt_lines_above = true,
            })
        end

        -- Overlay marker lines with labels
        local function set_label(row, hl, suffix)
            api.nvim_buf_set_extmark(bufnr, NAMESPACE, row, 0, {
                hl_group = hl,
                virt_text = { { (lines[row + 1] or "") .. suffix .. string.rep(" ", 200), hl } },
                virt_text_pos = "overlay",
            })
        end

        if middle_start then
            api.nvim_buf_set_extmark(bufnr, NAMESPACE, middle_start, 0, {
                line_hl_group = "NonText",
            })
        end

        set_label(range_start, "ConflictCurrentLabel", " (Current)")
        api.nvim_buf_set_extmark(bufnr, NAMESPACE, range_start, 0, {
            hl_group = "ConflictCurrent",
            end_row = middle_start or incoming_end,
            hl_eol = true,
        })

        set_label(incoming_end, "ConflictIncomingLabel", " (Incoming)")
        api.nvim_buf_set_extmark(bufnr, NAMESPACE, (middle_start or range_start) + 1, 0, {
            hl_group = "ConflictIncoming",
            end_row = incoming_end + 1,
            hl_eol = true,
        })
    end
end

--------------------------------------------------------------------------------
-- Conflict Detection
--------------------------------------------------------------------------------

---@param lines string[] @List of buffer lines to analyze.
---@return boolean, table[] @True if conflicts found, and the list of conflict position objects.
local function detect_conflicts(lines)
    local positions = {}
    local current = nil

    for i, line in ipairs(lines) do
        local lnum = i - 1

        if line:match(CONFLICT_START) then
            current = {
                current = { range_start = lnum, content_start = lnum + 1 },
                middle = {},
                incoming = {},
            }
        elseif current then
            if line:match(CONFLICT_ANCESTOR) or line:match(CONFLICT_MIDDLE) then
                if not current.current.content_end then
                    current.current.content_end = lnum - 1
                    current.current.range_end = lnum - 1
                end
                if line:match(CONFLICT_MIDDLE) then
                    current.middle = { range_start = lnum, range_end = lnum + 1 }
                    current.incoming = { range_start = lnum + 1, content_start = lnum + 1 }
                end
            elseif line:match(CONFLICT_END) then
                current.incoming.range_end = lnum
                current.incoming.content_end = lnum - 1
                table.insert(positions, current)
                current = nil
            end
        end
    end

    return #positions > 0, positions
end

---@param bufnr integer @Buffer handle to scan for conflicts.
local function parse_buffer(bufnr)
    if not bufnr or not api.nvim_buf_is_valid(bufnr) then return end

    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local has_conflict, positions = detect_conflicts(lines)

    M.clear(bufnr)
    visited_buffers[api.nvim_buf_get_name(bufnr)] = {
        bufnr = bufnr,
        positions = positions,
        tick = api.nvim_buf_get_changedtick(bufnr),
    }

    if config.disable_diagnostics then
        vim.diagnostic.enable(not has_conflict, { bufnr = bufnr })
    end

    if has_conflict then
        draw_sections(bufnr, positions, lines)
        map("n", "<LeftRelease>", handle_click, { buffer = bufnr, silent = true })
    else
        pcall(api.nvim_buf_del_keymap, bufnr, "n", "<LeftRelease>")
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

---@param side ConflictSide @Which side of the conflict to keep.
function M.choose(side)
    local bufnr = api.nvim_get_current_buf()
    local data = visited_buffers[api.nvim_buf_get_name(bufnr)]
    if not data or #data.positions == 0 then return end

    local cursor = api.nvim_win_get_cursor(0)[1] - 1
    local pos = vim.iter(data.positions):find(
        function(p) return cursor >= p.current.range_start and cursor <= p.incoming.range_end end
    )
    if not pos then return end

    local replacement = {}
    if side == "current" or side == "both" then
        vim.list_extend(
            replacement,
            api.nvim_buf_get_lines(
                bufnr,
                pos.current.content_start,
                pos.current.content_end + 1,
                false
            )
        )
    end
    if side == "incoming" or side == "both" then
        vim.list_extend(
            replacement,
            api.nvim_buf_get_lines(
                bufnr,
                pos.incoming.content_start,
                pos.incoming.content_end + 1,
                false
            )
        )
    end

    api.nvim_buf_set_lines(
        bufnr,
        pos.current.range_start,
        pos.incoming.range_end + 1,
        false,
        replacement
    )
    parse_buffer(bufnr)
end

---@param direction "next"|"prev" @Jump direction.
function M.navigate(direction)
    local bufnr = api.nvim_get_current_buf()
    local data = visited_buffers[api.nvim_buf_get_name(bufnr)]
    if not data or #data.positions == 0 then return end

    local cursor = api.nvim_win_get_cursor(0)[1] - 1
    local it = vim.iter(data.positions)
    if direction == "prev" then it:rev() end

    local target = it:find(function(p)
        local start = p.current.range_start
        return direction == "next" and start > cursor or start < cursor
    end) or (direction == "next" and data.positions[1] or data.positions[#data.positions])

    api.nvim_win_set_cursor(0, { target.current.range_start + 1, 0 })
end

---@param bufnr? integer @Buffer handle, 0 or nil for current.
function M.clear(bufnr)
    local b = (bufnr and bufnr ~= 0) and bufnr or api.nvim_get_current_buf()
    if not api.nvim_buf_is_valid(b) then return end
    api.nvim_buf_clear_namespace(b, NAMESPACE, 0, -1)
    api.nvim_buf_clear_namespace(b, ACTIONS_NAMESPACE, 0, -1)
end

---@param opts? table @User configuration overrides.
function M.setup(opts)
    config = vim.tbl_deep_extend("force", config, opts or {})
    set_highlights()

    local cmds = {
        next = M.navigate,
        prev = M.navigate,
        refresh = parse_buffer,
        current = M.choose,
        incoming = M.choose,
        both = M.choose,
    }

    api.nvim_create_user_command("Conflict", function(args)
        local cmd = args.fargs[1]
        if cmds[cmd] then
            cmds[cmd](cmd == "refresh" and 0 or cmd)
        else
            api.nvim_echo(
                { { "Conflict: Invalid command " .. (cmd or ""), "ErrorMsg" } },
                true,
                { err = true }
            )
        end
    end, { nargs = 1, complete = function() return vim.tbl_keys(cmds) end })

    api.nvim_create_autocmd("ColorScheme", { group = AUGROUP, callback = set_highlights })

    api.nvim_set_decoration_provider(NAMESPACE, {
        on_win = function(_, _, bufnr)
            local b = visited_buffers[api.nvim_buf_get_name(bufnr)]
            if
                (not b or b.tick ~= api.nvim_buf_get_changedtick(bufnr))
                and vim.bo[bufnr].buftype == ""
                and vim.bo[bufnr].modifiable
            then
                parse_buffer(bufnr)
            end
        end,
    })

    for action, key in pairs(config.default_mappings) do
        local handler = cmds[action]
        if key and key ~= "" and handler then
            map("n", key, function() handler(action) end, {
                desc = "Conflict: " .. action,
                buffer = false,
            })
        end
    end

    local bufnr = api.nvim_get_current_buf()
    if vim.bo[bufnr].buftype == "" and vim.bo[bufnr].modifiable then parse_buffer(bufnr) end
end

return M
