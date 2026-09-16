local M = {}

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

local START = "^<<<<<<<"
local MIDDLE = "^======="
local ENDING = "^>>>>>>>"
local ANCESTOR = "^|||||||"

---Finds every well-formed conflict block in a list of lines.
---
---Only the three marker rows are tracked while scanning; every content boundary
---is derived from them once the block is known to be complete. Markers are only
---matched in the order git writes them, so a `=======` or `|||||||` appearing
---inside a section's content cannot corrupt the block.
---@param lines string[] @Buffer lines to analyze.
---@return ConflictPosition[]
function M.detect(lines)
    local positions = {}
    ---@type integer?, integer?, integer?
    local start_row, ancestor_row, middle_row

    for i, line in ipairs(lines) do
        local lnum = i - 1

        if line:match(START) then
            -- A nested or unterminated conflict abandons whatever was open.
            start_row, ancestor_row, middle_row = lnum, nil, nil
        elseif start_row then
            if line:match(ANCESTOR) and not ancestor_row and not middle_row then
                ancestor_row = lnum
            elseif line:match(MIDDLE) and not middle_row then
                middle_row = lnum
            elseif line:match(ENDING) then
                -- A block without a `=======` is malformed and cannot be resolved.
                if middle_row then
                    ---@type ConflictRange?
                    local ancestor = nil
                    if ancestor_row then
                        ancestor = {
                            content_start = ancestor_row + 1,
                            content_end = middle_row - 1,
                        }
                    end

                    table.insert(positions, {
                        start_row = start_row,
                        ancestor_row = ancestor_row,
                        middle_row = middle_row,
                        end_row = lnum,
                        current = {
                            content_start = start_row + 1,
                            content_end = (ancestor_row or middle_row) - 1,
                        },
                        ancestor = ancestor,
                        incoming = {
                            content_start = middle_row + 1,
                            content_end = lnum - 1,
                        },
                    })
                end
                start_row, ancestor_row, middle_row = nil, nil, nil
            end
        end
    end

    return positions
end

return M
