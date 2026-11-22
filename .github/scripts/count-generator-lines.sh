#!/bin/bash
# usage: count-generator-lines.sh REVISION
#
# Prints how many lines of code the Swift files under
# Sources/SafeDICore/Generators hold at REVISION, a commit of this
# repository's checkout: every line but blank lines, lines that hold only a
# `//` comment, and the lines of `/* … */` comments that hold no code before
# or after the comment. The base comparison job prints it for a pull
# request's base and head as information; it fails nothing.
set -euo pipefail
revision=$1
git ls-tree -r --name-only "$revision" -- Sources/SafeDICore/Generators \
	| { grep '\.swift$' || true; } \
	| while read -r path; do git show "$revision:$path"; echo; done \
	| awk '
		BEGIN { inBlock = 0; count = 0 }
		{
			line = $0
			gsub(/^[ \t]+|[ \t]+$/, "", line)
			if (inBlock) {
				end = index(line, "*/")
				if (end == 0) { next }
				inBlock = 0
				line = substr(line, end + 2)
				gsub(/^[ \t]+/, "", line)
			}
			if (line == "" || substr(line, 1, 2) == "//") { next }
			if (substr(line, 1, 2) == "/*") {
				end = index(substr(line, 3), "*/")
				if (end == 0) { inBlock = 1; next }
				rest = substr(line, end + 4)
				gsub(/^[ \t]+/, "", rest)
				if (rest == "" || substr(rest, 1, 2) == "//") { next }
			}
			count++
		}
		END { print count }
	'
