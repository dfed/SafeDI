#!/bin/bash
# Scripts/type-key-shadow-summary.sh FILE
# MEASUREMENT ONLY, never merged. Summarizes the lines a run wrote under SAFEDI_TYPE_KEY_SHADOW=FILE: per result
# (laidOut, or the step of TypeKeyBody.statements that gave up), how many roots, split by whether the root holds a
# cycle and whether declarations are in scope before its body (a seam root), and how many root statements were kept as text.
set -euo pipefail
awk '$1 == "TYPE_KEY_SHADOW" {
	key = $2 " " $3 " " $4
	count[key] += 1
	split($7, text, "="); split($8, all, "=")
	kept[key] += text[2]; statements[key] += all[2]
}
END {
	for (key in count) {
		printf "%8d roots  %-60s rootTextStatements=%d of %d\n", count[key], key, kept[key], statements[key]
	}
}' "$1" | sort -k3
