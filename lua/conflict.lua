local M = {}

--------------------------------------------------------------------------------
-- Configuration & Constants
--------------------------------------------------------------------------------

---@alias ConflictSide 'current'|'incoming'|'both'|'base'|'none'

---@class ConflictRange
---@field content_start integer @First row of the section's content.
---@field content_end integer @Last row of the section's content.

---@class ConflictPosition
---@field start_row integer @Row of the `<<<<<<<` marker.
---@field middle_row integer @Row of the `=======` marker.
---@field end_row integer @Row of the `>>>>>>>` marker.
---@field ancestor_row? integer @Row of the `|||||||` marker, in diff3 conflicts.
---@field current ConflictRange
---@field incoming ConflictRange
---@field ancestor? ConflictRange

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

---Sections to concatenate for each resolution, in the order they are kept.
local RESOLUTIONS = {
    current = { "current" },
    incoming = { "incoming" },
    both = { "current", "incoming" },
    base = { "ancestor" },
    none = {},
}

---Marker lines are re-rendered as virtual text, which must be padded to cover
---the rest of the line so the label highlight reaches the window edge.
local LABEL_PADDING = 200

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

---@type ConflictConfig
local config = vim.deepcopy(DEFAULTS)

--------------------------------------------------------------------------------
-- State Management
--------------------------------------------------------------------------------

---@type table<integer, { positions: ConflictPosition[], tick: integer, active: boolean }>
local state = {}

---@type fun(bufnr: integer)
local parse_buffer

---@param bufnr? integer @Buffer handle, 0 or nil for the current buffer.
---@return integer
local function resolve_buf(bufnr)
    return (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
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

    return string.format("#%02X%02X%02X", alter(r), alter(g), alter(b))
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
-- Action Labels
--------------------------------------------------------------------------------

---@param has_ancestor boolean @Whether the conflict has a base section.
---@return { text: string, side: ConflictSide }[]
local function build_actions(has_ancestor)
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
local function render_actions(actions)
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
local function actions_anchor(pos)
    return pos.start_row > 0 and pos.start_row or pos.current.content_start
end

---@param col integer @1-based display column within the rendered action line.
---@param actions { text: string, side: ConflictSide }[]
---@return ConflictSide? @The action at that column, or nil.
local function action_at_col(col, actions)
    local cursor = 1
    for _, action in ipairs(actions) do
        local width = vim.api.nvim_strwidth(action.text)
        if col >= cursor and col < cursor + width then
            return action.side
        end
        cursor = cursor + width + SEPARATOR_WIDTH
    end
end

--------------------------------------------------------------------------------
-- Mouse Click
--------------------------------------------------------------------------------

---Resolves a conflict when its action label is clicked.
local function handle_click()
    local mouse = vim.fn.getmousepos()
    if not mouse.winid or mouse.winid == 0 then
        return
    end

    local data = state[vim.api.nvim_win_get_buf(mouse.winid)]
    if not data then
        return
    end

    for _, pos in ipairs(data.positions) do
        local row = actions_anchor(pos)
        local anchor = vim.fn.screenpos(mouse.winid, row + 1, 1)
        if anchor.row > 0 and mouse.screenrow == anchor.row - 1 then
            local actions = build_actions(pos.ancestor_row ~= nil)
            local side = action_at_col(mouse.screencol - anchor.col + 1, actions)
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

--------------------------------------------------------------------------------
-- Commands & Mappings
--------------------------------------------------------------------------------

---@type table<string, fun()>
local commands = {
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
        M.list()
    end,
    qflist = function()
        M.qflist()
    end,
    refresh = function()
        parse_buffer(vim.api.nvim_get_current_buf())
    end,
}

local COMMAND_NAMES = vim.tbl_keys(commands)
table.sort(COMMAND_NAMES)

---@param bufnr integer @Buffer handle to clear conflict mappings from.
local function clear_buffer_mappings(bufnr)
    for _, km in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
        if km.lhs and km.desc and km.desc:find("^Conflict: ") then
            pcall(vim.keymap.del, "n", km.lhs, { buffer = bufnr })
        end
    end
end

---@param bufnr integer @Buffer handle to set conflict mappings on.
local function set_buffer_mappings(bufnr)
    clear_buffer_mappings(bufnr)

    for action, key in pairs(config.default_mappings) do
        local handler = commands[action]
        if type(key) == "string" and key ~= "" and handler then
            vim.keymap.set("n", key, handler, {
                desc = "Conflict: " .. action,
                buffer = bufnr,
                silent = true,
            })
        end
    end

    if config.show_actions then
        vim.keymap.set("n", "<LeftRelease>", handle_click, {
            desc = "Conflict: click action",
            buffer = bufnr,
            silent = true,
        })
    end
end

--------------------------------------------------------------------------------
-- Conflict Detection
--------------------------------------------------------------------------------

---@param lines string[] @List of buffer lines to analyze.
---@return ConflictPosition[]
local function detect_conflicts(lines)
    local positions = {}
    ---@type ConflictPosition?
    local open = nil

    for i, line in ipairs(lines) do
        local lnum = i - 1

        if line:match(CONFLICT_START) then
            -- A nested or unterminated conflict abandons whatever was open.
            open = { start_row = lnum, current = { content_start = lnum + 1 } }
        elseif open then
            if line:match(CONFLICT_ANCESTOR) and not open.ancestor_row and not open.middle_row then
                open.current.content_end = lnum - 1
                open.ancestor_row = lnum
                open.ancestor = { content_start = lnum + 1 }
            elseif line:match(CONFLICT_MIDDLE) and not open.middle_row then
                local side = open.ancestor or open.current
                side.content_end = lnum - 1
                open.middle_row = lnum
                open.incoming = { content_start = lnum + 1 }
            elseif line:match(CONFLICT_END) then
                -- A block without a `=======` is malformed and cannot be resolved.
                if open.middle_row then
                    open.incoming.content_end = lnum - 1
                    open.end_row = lnum
                    table.insert(positions, open)
                end
                open = nil
            end
        end
    end

    return positions
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

---@param bufnr integer @Target buffer handle.
---@param positions ConflictPosition[] @List of conflict positions.
---@param lines string[] @All buffer lines, for marker label text.
local function draw_sections(bufnr, positions, lines)
    local actions = render_actions(build_actions(false))
    local actions_with_base = render_actions(build_actions(true))

    ---Re-renders a marker line with a trailing label, in the label highlight.
    local function set_label(row, hl, suffix)
        local text = (lines[row + 1] or "") .. suffix .. string.rep(" ", LABEL_PADDING)
        vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, row, 0, {
            hl_group = hl,
            virt_text = { { text, hl } },
            virt_text_pos = "overlay",
        })
    end

    for _, pos in ipairs(positions) do
        if config.show_actions then
            vim.api.nvim_buf_set_extmark(bufnr, ACTIONS_NAMESPACE, actions_anchor(pos), 0, {
                virt_lines = { pos.ancestor_row and actions_with_base or actions },
                virt_lines_above = true,
            })
        end

        vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, pos.middle_row, 0, {
            line_hl_group = "NonText",
        })

        set_label(pos.start_row, "ConflictCurrentLabel", " (Current)")
        vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, pos.start_row, 0, {
            hl_group = "ConflictCurrent",
            end_row = pos.ancestor_row or pos.middle_row,
            hl_eol = true,
        })

        if pos.ancestor_row then
            set_label(pos.ancestor_row, "ConflictAncestorLabel", " (Base)")
            vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, pos.ancestor_row, 0, {
                hl_group = "ConflictAncestor",
                end_row = pos.middle_row,
                hl_eol = true,
            })
        end

        set_label(pos.end_row, "ConflictIncomingLabel", " (Incoming)")
        vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, pos.middle_row + 1, 0, {
            hl_group = "ConflictIncoming",
            end_row = pos.end_row + 1,
            hl_eol = true,
        })
    end
end

--------------------------------------------------------------------------------
-- Parsing
--------------------------------------------------------------------------------

---@param bufnr integer @Buffer handle to scan for conflicts.
function parse_buffer(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local positions = detect_conflicts(lines)
    local has_conflict = #positions > 0
    local was_active = state[bufnr] ~= nil and state[bufnr].active or false

    M.clear(bufnr)
    state[bufnr] = {
        positions = positions,
        tick = vim.api.nvim_buf_get_changedtick(bufnr),
        active = has_conflict,
    }

    if config.disable_diagnostics then
        vim.diagnostic.enable(not has_conflict, { bufnr = bufnr })
    end

    if has_conflict then
        draw_sections(bufnr, positions, lines)
    end

    -- Mappings only change when the buffer crosses the conflict/no-conflict line.
    if has_conflict ~= was_active then
        if has_conflict then
            set_buffer_mappings(bufnr)
        else
            clear_buffer_mappings(bufnr)
        end
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

---@param side ConflictSide @Which side of the conflict to keep.
function M.choose(side)
    local sections = RESOLUTIONS[side]
    local bufnr = vim.api.nvim_get_current_buf()
    local data = state[bufnr]
    if not sections or not data then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(0)[1] - 1
    local pos = vim.iter(data.positions):find(function(p)
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
    parse_buffer(bufnr)
end

---@param direction "next"|"prev" @Jump direction.
function M.navigate(direction)
    local data = state[vim.api.nvim_get_current_buf()]
    if not data or #data.positions == 0 then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(0)[1] - 1
    local it = vim.iter(data.positions)
    if direction == "prev" then
        it:rev()
    end

    local target = it:find(function(p)
        if direction == "next" then
            return p.start_row > cursor
        end
        return p.start_row < cursor
    end) or (direction == "next" and data.positions[1] or data.positions[#data.positions])

    vim.api.nvim_win_set_cursor(0, { target.start_row + 1, 0 })
end

---@param ... string @Arguments to pass to git.
---@return string? @Trimmed stdout, or nil if the command failed.
local function git(...)
    local result = vim.system({ "git", ... }, { text = true }):wait()
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
        if ok and type(lines) == "table" then
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
    local b = resolve_buf(bufnr)
    if not vim.api.nvim_buf_is_valid(b) then
        return
    end
    vim.api.nvim_buf_clear_namespace(b, NAMESPACE, 0, -1)
    vim.api.nvim_buf_clear_namespace(b, ACTIONS_NAMESPACE, 0, -1)
end

---@param opts? ConflictConfig @User configuration overrides.
function M.setup(opts)
    config = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), opts or {})
    state = {}
    set_highlights()

    vim.api.nvim_create_user_command("Conflict", function(args)
        local run = commands[args.args]
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

    vim.api.nvim_create_autocmd("ColorScheme", { group = AUGROUP, callback = set_highlights })

    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        group = AUGROUP,
        callback = function(args)
            state[args.buf] = nil
        end,
    })

    vim.api.nvim_set_decoration_provider(NAMESPACE, {
        on_win = function(_, _, bufnr)
            local data = state[bufnr]
            if
                (not data or data.tick ~= vim.api.nvim_buf_get_changedtick(bufnr))
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
