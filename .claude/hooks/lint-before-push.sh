#!/bin/bash
# PreToolUse hook on Bash: block `git push`, `gh stack push|sync` and `gh pr create` when SwiftFormat --lint fails
# in the worktree the command runs in. Exit 2 blocks the command and shows stderr to Claude; exit 0 lets it run.
set -u
input=$(cat)
case "$input" in
	*"git push"*|*"gh stack"*|*"gh pr create"*) ;;
	*) exit 0 ;;
esac
command=$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))')
case "$command" in
	*"git push"*|*"gh stack"*|*"gh pr create"*) ;;
	*) exit 0 ;;
esac
cwd=$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("cwd",""))')
root=$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0
mkdir -p "$root/.build"
if ! (cd "$root" && ./CLI/lint.sh --check >"$root/.build/swiftformat-lint.out" 2>&1); then
	{
		echo "Lint failed in $root; the push was not run."
		echo "Run ./CLI/lint.sh, commit the formatting in its own commit, then push again. SwiftFormat said:"
		grep -v '^Building\|^Compiling\|^Build complete' "$root/.build/swiftformat-lint.out" | head -20
	} >&2
	exit 2
fi
exit 0
