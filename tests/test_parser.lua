local new_set, expect = MiniTest.new_set, MiniTest.expect
local eq = expect.equality

local parser = require("conflict.parser")

local T = new_set()

T["detects a two-sided conflict"] = function()
    local got = parser.detect({ "a", "<<<<<<< HEAD", "cur", "=======", "inc", ">>>>>>> b", "z" })

    eq(#got, 1)
    local pos = assert(got[1])
    eq(pos.start_row, 1)
    eq(pos.middle_row, 3)
    eq(pos.end_row, 5)
    eq(pos.ancestor_row, nil)
    eq(pos.ancestor, nil)
    eq(pos.current, { content_start = 2, content_end = 2 })
    eq(pos.incoming, { content_start = 4, content_end = 4 })
end

T["detects a diff3 conflict with an ancestor"] = function()
    local got = parser.detect({
        "<<<<<<< HEAD",
        "cur",
        "||||||| base",
        "ancestor",
        "=======",
        "inc",
        ">>>>>>> b",
    })

    eq(#got, 1)
    local pos = assert(got[1])
    eq(pos.start_row, 0)
    eq(pos.ancestor_row, 2)
    eq(pos.middle_row, 4)
    eq(pos.end_row, 6)
    eq(pos.current, { content_start = 1, content_end = 1 })
    eq(pos.ancestor, { content_start = 3, content_end = 3 })
    eq(pos.incoming, { content_start = 5, content_end = 5 })
end

T["detects multiple conflicts in order"] = function()
    local got = parser.detect({
        "<<<<<<< HEAD",
        "a",
        "=======",
        "b",
        ">>>>>>> x",
        "gap",
        "<<<<<<< HEAD",
        "c",
        "=======",
        "d",
        ">>>>>>> x",
    })

    eq(#got, 2)
    eq({ assert(got[1]).start_row, assert(got[2]).start_row }, { 0, 6 })
end

T["handles empty sections"] = function()
    local got = parser.detect({ "<<<<<<< HEAD", "=======", ">>>>>>> b" })

    eq(#got, 1)
    local pos = assert(got[1])
    -- An empty side is an inverted range, which yields no lines when read back.
    eq(pos.current, { content_start = 1, content_end = 0 })
    eq(pos.incoming, { content_start = 2, content_end = 1 })
end

T["ignores a block with no ======="] = function()
    eq(parser.detect({ "x", "<<<<<<< HEAD", "orphan", ">>>>>>> b", "y" }), {})
end

T["ignores an unterminated block"] = function()
    eq(parser.detect({ "<<<<<<< HEAD", "cur", "=======", "inc" }), {})
end

T["a second <<<<<<< abandons the open block"] = function()
    local got = parser.detect({
        "<<<<<<< HEAD",
        "stale",
        "<<<<<<< HEAD",
        "cur",
        "=======",
        "inc",
        ">>>>>>> b",
    })

    eq(#got, 1)
    eq(assert(got[1]).start_row, 2)
end

T["a ======= inside incoming content does not split the block"] = function()
    local got = parser.detect({
        "<<<<<<< HEAD",
        "cur",
        "=======",
        "inc",
        "=======",
        "more",
        ">>>>>>> b",
    })

    eq(#got, 1)
    local pos = assert(got[1])
    eq(pos.middle_row, 2)
    eq(pos.incoming, { content_start = 3, content_end = 5 })
end

T["a ||||||| after ======= is treated as content"] = function()
    local got = parser.detect({
        "<<<<<<< HEAD",
        "cur",
        "=======",
        "||||||| not-a-base",
        ">>>>>>> b",
    })

    eq(#got, 1)
    local pos = assert(got[1])
    eq(pos.ancestor_row, nil)
    eq(pos.incoming, { content_start = 3, content_end = 3 })
end

T["returns nothing for a clean buffer"] = function()
    eq(parser.detect({ "just", "some", "lines" }), {})
end

return T
