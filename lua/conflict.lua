local M = {}

--------------------------------------------------------------------------------
-- Configuration & Constants
--------------------------------------------------------------------------------

---@alias ConflictSide 'current'|'incoming'|'both'|'base'|'none'

---@class ConflictConfig
---@field default_mappings table<string, string|false>
---@field show_actions boolean
---@field disable_diagnostics boolean
---@field highlights { current: string, incoming: string, ancestor: string }

local NAMESPACE = vim.api.nvim_create_namespace("conflict")
local ACTIONS_NAMESPACE = vim.api.nvim_create_namespace("conflict-actions")
local AUGROUP = vim.api.nvim_create_augroup("ConflictCommands", { clear = true })

local CONFLICT_START = "^<<<<<<<"
local CONFLICT_MIDDLE = "^======="
local CONFLICT_END = "^>>>>>>>"
local CONFLICT_ANCESTOR = "^|||||||"

local ACTION_LABELS = {
    { text = "Accept Current", side = "current" },
    { text = "Accept Incoming", side = "incoming" },
    { text = "Accept Both", side = "both" },
}

local ACTION_LABELS_WITH_BASE = {
    { text = "Accept Current", side = "current" },
    { text = "Accept Incoming", side = "incoming" },
    { text = "Accept Both", side = "both" },
    { text = "Accept Base", side = "base" },
}

---@type ConflictConfig
local config = {
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

--------------------------------------------------------------------------------
-- State Management
--------------------------------------------------------------------------------

---@type table<string, { bufnr: integer, positions: table, tick: integer }>
local visited_buffers = {}

---@type table<string, function>
local cmds

---@param bufnr integer @Buffer handle to clear conflict mappings from.
local function clear_buffer_mappings(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    for _, km in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
        if km.lhs and km.desc and km.desc:find("^Conflict: ") then
            pcall(vim.keymap.del, "n", km.lhs, { buffer = bufnr })
        end
    end
end

---@param bufnr integer @Buffer handle to set conflict mappings on.
local function set_buffer_mappings(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end
    clear_buffer_mappings(bufnr)

    for action, key in pairs(config.default_mappings) do
        local handler = cmds[action]
        if type(key) == "string" and key ~= "" and handler then
            vim.keymap.set("n", key, function()
                handler(action)
            end, {
                desc = "Conflict: " .. action,
                buffer = bufnr,
                silent = true,
            })
        end
    end
end

--------------------------------------------------------------------------------
-- UI & Highlights
--------------------------------------------------------------------------------

---@param color string|integer @Hex string, color name, or integer RGB value.
---@param percent integer @Percentage to lighten or darken.
---@return string @Hex color string.
local function shade_color(color, percent)
    local c = type(color) == "string" and vim.api.nvim_get_color_by_name(color) or color
    if c == -1 then
        return "#000000"
    end

    local r, g, b = math.floor(c / 65536), math.floor(c / 256) % 256, c % 256
    local ratio = (100 + percent) / 100
    local alter = function(val)
        return math.max(0, math.min(255, math.floor(val * ratio)))
    end

    return string.format("#%02x%02x%02x", alter(r), alter(g), alter(b))
end

---@param name string @Highlight group name.
---@param fallback string @Hex fallback if the HL group has no resolved bg.
---@return string|integer
local function hl_bg(name, fallback)
    return vim.api.nvim_get_hl(0, { name = name, link = false }).bg or fallback
end

---Sets highlight groups for conflict sections based on the configured colorscheme.
local function set_highlights()
    local h = config.highlights
    local is_light = vim.o.background == "light"
    local shade_pct = is_light and -15 or 60
    local current_bg = hl_bg(h.current, is_light and "#C8E6C9" or "#264334")
    local incoming_bg = hl_bg(h.incoming, is_light and "#BBDEFB" or "#214566")
    local ancestor_bg = hl_bg(h.ancestor, is_light and "#E1BEE7" or "#4A2A52")

    for name, opts in pairs({
        ConflictCurrent = { bg = current_bg, bold = true },
        ConflictIncoming = { bg = incoming_bg, bold = true },
        ConflictAncestor = { bg = ancestor_bg, bold = true },
        ConflictCurrentLabel = { bg = shade_color(current_bg, shade_pct) },
        ConflictIncomingLabel = { bg = shade_color(incoming_bg, shade_pct) },
        ConflictAncestorLabel = { bg = shade_color(ancestor_bg, shade_pct) },
    }) do
        opts.default = true
        vim.api.nvim_set_hl(0, name, opts)
    end
end

--------------------------------------------------------------------------------
-- Mouse Click
--------------------------------------------------------------------------------

---@param col integer @1-based column within the actions virtual text.
---@param labels table @Action labels list matching what was rendered.
---@return ConflictSide? @The action side at that column, or nil.
local function get_action_at_col(col, labels)
    local cursor = 1
    for _, action in ipairs(labels) do
        local width = #action.text
        if col >= cursor and col < (cursor + width) then
            return action.side
        end
        cursor = cursor + width + 3 -- 3 for " | "
    end
end

---Handles mouse click on action labels to resolve conflicts.
local function handle_click()
    local mouse = vim.fn.getmousepos()
    if not mouse.winid or mouse.winid == 0 then
        return
    end

    local buf = vim.api.nvim_win_get_buf(mouse.winid)
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    local data = visited_buffers[vim.api.nvim_buf_get_name(buf)]
    if not data then
        return
    end

    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ACTIONS_NAMESPACE, 0, -1, {})) do
        local row = mark[2]
        local anchor = vim.fn.screenpos(mouse.winid, row + 1, 1)
        if anchor.row > 0 and mouse.screenrow == anchor.row - 1 then
            local pos = vim.iter(data.positions):find(function(p)
                local p_anchor = p.current.range_start > 0 and p.current.range_start
                    or p.current.content_start
                return p_anchor == row
            end)
            local labels = (pos and pos.ancestor) and ACTION_LABELS_WITH_BASE or ACTION_LABELS
            local side = get_action_at_col(mouse.screencol - anchor.col + 1, labels)
            if side then
                vim.api.nvim_win_set_cursor(mouse.winid, { row + 1, 0 })
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
    local function build_actions_line(labels)
        local result = {}
        for i, act in ipairs(labels) do
            if i > 1 then
                table.insert(result, { " | ", "NonText" })
            end
            table.insert(result, { act.text, "Comment" })
        end
        return result
    end

    local actions_line = build_actions_line(ACTION_LABELS)
    local actions_line_with_base = build_actions_line(ACTION_LABELS_WITH_BASE)

    for _, pos in ipairs(positions) do
        local range_start = pos.current.range_start
        local middle_start = pos.middle.range_start
        local incoming_end = pos.incoming.range_end
        local ancestor_start = pos.ancestor and pos.ancestor.range_start

        if config.show_actions then
            local anchor = range_start > 0 and range_start or pos.current.content_start
            vim.api.nvim_buf_set_extmark(bufnr, ACTIONS_NAMESPACE, anchor, 0, {
                virt_lines = { ancestor_start and actions_line_with_base or actions_line },
                virt_lines_above = true,
            })
        end

        -- Overlay marker lines with labels
        local function set_label(row, hl, suffix)
            vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, row, 0, {
                hl_group = hl,
                virt_text = { { (lines[row + 1] or "") .. suffix .. string.rep(" ", 200), hl } },
                virt_text_pos = "overlay",
            })
        end

        if middle_start then
            vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, middle_start, 0, {
                line_hl_group = "NonText",
            })
        end

        set_label(range_start, "ConflictCurrentLabel", " (Current)")
        vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, range_start, 0, {
            hl_group = "ConflictCurrent",
            end_row = ancestor_start or middle_start or incoming_end,
            hl_eol = true,
        })

        if ancestor_start then
            set_label(ancestor_start, "ConflictAncestorLabel", " (Base)")
            vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, ancestor_start, 0, {
                hl_group = "ConflictAncestor",
                end_row = middle_start or incoming_end,
                hl_eol = true,
            })
        end

        set_label(incoming_end, "ConflictIncomingLabel", " (Incoming)")
        vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, (middle_start or range_start) + 1, 0, {
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
    ---@type table?
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
            if line:match(CONFLICT_ANCESTOR) then
                if not current.current.content_end then
                    current.current.content_end = lnum - 1
                    current.current.range_end = lnum - 1
                end
                current.ancestor = { range_start = lnum, content_start = lnum + 1 }
            elseif line:match(CONFLICT_MIDDLE) then
                if not current.current.content_end then
                    current.current.content_end = lnum - 1
                    current.current.range_end = lnum - 1
                end
                if current.ancestor then
                    current.ancestor.content_end = lnum - 1
                    current.ancestor.range_end = lnum - 1
                end
                current.middle = { range_start = lnum, range_end = lnum + 1 }
                current.incoming = { range_start = lnum + 1, content_start = lnum + 1 }
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
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local has_conflict, positions = detect_conflicts(lines)

    M.clear(bufnr)
    visited_buffers[vim.api.nvim_buf_get_name(bufnr)] = {
        bufnr = bufnr,
        positions = positions,
        tick = vim.api.nvim_buf_get_changedtick(bufnr),
    }

    if config.disable_diagnostics then
        vim.diagnostic.enable(not has_conflict, { bufnr = bufnr })
    end

    if has_conflict then
        draw_sections(bufnr, positions, lines)
        vim.keymap.set("n", "<LeftRelease>", handle_click, { buffer = bufnr, silent = true })
        set_buffer_mappings(bufnr)
    else
        pcall(vim.api.nvim_buf_del_keymap, bufnr, "n", "<LeftRelease>")
        clear_buffer_mappings(bufnr)
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

---@param side ConflictSide @Which side of the conflict to keep.
function M.choose(side)
    local bufnr = vim.api.nvim_get_current_buf()
    local data = visited_buffers[vim.api.nvim_buf_get_name(bufnr)]
    if not data or #data.positions == 0 then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(0)[1] - 1
    local pos = vim.iter(data.positions):find(function(p)
        return cursor >= p.current.range_start and cursor <= p.incoming.range_end
    end)

    if not pos then
        return
    end

    if side == "base" and not pos.ancestor then
        return
    end

    local replacement = {}
    if side == "current" or side == "both" then
        vim.list_extend(
            replacement,
            vim.api.nvim_buf_get_lines(
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
            vim.api.nvim_buf_get_lines(
                bufnr,
                pos.incoming.content_start,
                pos.incoming.content_end + 1,
                false
            )
        )
    end
    if side == "base" then
        vim.list_extend(
            replacement,
            vim.api.nvim_buf_get_lines(
                bufnr,
                pos.ancestor.content_start,
                pos.ancestor.content_end + 1,
                false
            )
        )
    end
    vim.api.nvim_buf_set_lines(
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
    local bufnr = vim.api.nvim_get_current_buf()
    local data = visited_buffers[vim.api.nvim_buf_get_name(bufnr)]
    if not data or #data.positions == 0 then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(0)[1] - 1
    local it = vim.iter(data.positions)
    if direction == "prev" then
        it:rev()
    end

    local target = it:find(function(p)
        local start = p.current.range_start
        return direction == "next" and start > cursor or start < cursor
    end) or (direction == "next" and data.positions[1] or data.positions[#data.positions])

    vim.api.nvim_win_set_cursor(0, { target.current.range_start + 1, 0 })
end

---@return string[] @List of file paths with unmerged conflicts.
function M.get_conflicted_files()
    local files = vim.fn.systemlist("git diff --name-only --diff-filter=U")
    if vim.v.shell_error ~= 0 then
        return {}
    end
    return files
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
            vim.cmd.edit(choice)
        end
    end)
end

---Populates the quickfix list with all conflict markers from conflicted files.
function M.qflist()
    local files = M.get_conflicted_files()
    if #files == 0 then
        vim.notify("No conflicted files found", vim.log.levels.INFO)
        return
    end

    local items = {}
    for _, file in ipairs(files) do
        local ok, lines = pcall(vim.fn.readfile, file)
        if ok then
            for i, line in ipairs(lines) do
                if line:match(CONFLICT_START) then
                    table.insert(items, { filename = file, lnum = i, text = line })
                end
            end
        end
    end

    vim.fn.setqflist({}, " ", { title = "Git Conflicts", items = items })
    vim.cmd.copen()
end

---@param bufnr? integer @Buffer handle, 0 or nil for current.
function M.clear(bufnr)
    local b = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(b) then
        return
    end
    vim.api.nvim_buf_clear_namespace(b, NAMESPACE, 0, -1)
    vim.api.nvim_buf_clear_namespace(b, ACTIONS_NAMESPACE, 0, -1)
end

---@param opts? table @User configuration overrides.
function M.setup(opts)
    config = vim.tbl_deep_extend("force", config, opts or {})
    set_highlights()

    cmds = {
        next = M.navigate,
        prev = M.navigate,
        refresh = parse_buffer,
        current = M.choose,
        incoming = M.choose,
        both = M.choose,
        base = M.choose,
        none = M.choose,
        list = M.list,
        qflist = M.qflist,
    }

    vim.api.nvim_create_user_command("Conflict", function(args)
        local cmd = args.fargs[1]
        if cmds[cmd] then
            cmds[cmd](cmd == "refresh" and 0 or cmd)
        else
            vim.api.nvim_echo(
                { { "Conflict: Invalid command " .. (cmd or ""), "ErrorMsg" } },
                true,
                { err = true }
            )
        end
    end, {
        nargs = 1,
        complete = function()
            return vim.tbl_keys(cmds)
        end,
    })

    vim.api.nvim_create_autocmd("ColorScheme", { group = AUGROUP, callback = set_highlights })

    vim.api.nvim_set_decoration_provider(NAMESPACE, {
        on_win = function(_, _, bufnr)
            local b = visited_buffers[vim.api.nvim_buf_get_name(bufnr)]
            if
                (not b or b.tick ~= vim.api.nvim_buf_get_changedtick(bufnr))
                and vim.bo[bufnr].buftype == ""
                and vim.bo[bufnr].modifiable
            then
                parse_buffer(bufnr)
            end
        end,
    })

    local bufnr = vim.api.nvim_get_current_buf()
    if vim.bo[bufnr].buftype == "" and vim.bo[bufnr].modifiable then
        parse_buffer(bufnr)
    end
end

return M
