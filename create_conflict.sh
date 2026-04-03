#!/bin/bash
rm -rf ./conflict-test/
mkdir conflict-test
cd conflict-test || exit
git init -b main
echo "local value = 1 + 1" > conflicted.lua
git add conflicted.lua
git commit -m 'initial'
git checkout -b new_branch
echo "local value = 1 - 1" > conflicted.lua
git commit -am 'first commit on new_branch'
git checkout main
cat > conflicted.lua << 'EOF'
local value = 5 + 7
print(value)
print(string.format("value is %d", value))
EOF
git commit -am 'second commit on main'
git merge new_branch || true
echo "Done - conflict-test/conflicted.lua should have conflict markers"
