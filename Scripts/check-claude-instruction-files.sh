#!/bin/bash
# Fails when an instruction file could be truncated or would load at launch by mistake.
# Bash, not zsh, and Python for counts, so that it runs unchanged on CI's Linux runner,
# which has no zsh and whose `wc -m` counts bytes under the C locale.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
status=0
characters() { python3 -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8").read()))' "$1"; }
words() { python3 -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8").read().split()))' "$1"; }
for file in .claude/rules/*.md; do
	if ! { head -1 "$file" | grep -q '^---$' && sed -n '2,10p' "$file" | grep -q '^paths:'; }; then
		echo "$file: every rules file needs paths: frontmatter, or it loads in every session"
		status=1
	fi
	if (( $(characters "$file") > 32000 )); then
		echo "$file: over 32,000 characters; Claude truncates on-demand files at 40,000"
		status=1
	fi
done
while IFS= read -r file; do
	if (( $(characters "$file") > 1500 )); then
		echo "$file: a directory CLAUDE.md is a signpost; keep it under 1,500 characters"
		status=1
	fi
done < <(git ls-files '*/CLAUDE.md')
if (( $(words CLAUDE.md) > 5500 )); then
	echo "CLAUDE.md: over 5,500 words; move the rule to the file that owns its topic"
	status=1
fi
instruction_files=(CLAUDE.md .claude/rules/*.md)
while IFS= read -r file; do instruction_files+=("$file"); done < <(git ls-files '*/CLAUDE.md')
if grep -nE '(^|[[:space:]])@[A-Za-z0-9_.~/-]*(/|\.md)' "${instruction_files[@]}"; then
	echo "an @path import loads eagerly with the importing file; name files in backticks instead"
	status=1
fi
exit $status
