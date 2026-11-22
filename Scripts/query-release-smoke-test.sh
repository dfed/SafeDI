#!/bin/bash
# Scripts/query-release-smoke-test.sh PATH_TO_SAFEDITOOL
#
# Runs a built SafeDITool as a user runs it: `generate` once per module for a
# chain of 40 one-type modules, then `query graph` and `query needs` over all
# of them, read from `--include` directories and from `.safedi` files, three
# times each. It fails unless every command exits with status 0 and each
# query reports every module.
#
# It exists for the binaries SafeDI publishes. 2.3.1's release binaries
# (Swift 6.3 with `-Osize`) returned no modules with exit status 0, or
# crashed, when `query` read more than one module, while `generate` and every
# test were right: the tests run the tool's code in process, from a build
# with another compiler and other flags. Only running the binary built as
# `publish.yml` builds it shows such a miscompile, so "Build Release
# SafeDITool on Linux" runs this on its build and `publish.yml` runs it on
# each binary before uploading it. The failure came and went between runs,
# hence three runs of each query.
set -euo pipefail

tool=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
module_count=40
work_directory=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/query-smoke.XXXXXX")
trap 'rm -rf "$work_directory"' EXIT
cd "$work_directory"

include_arguments=()
module_info_arguments=()
dependent_module_infos=""
for index in $(seq -f %03g 0 $((module_count - 1))); do
	mkdir -p "Module$index"
	if [ "$index" = 000 ]; then
		body="    public init() {}"
	else
		previous=$(printf %03d $((10#$index - 1)))
		body="    public init(child: Type$previous) { self.child = child }
    @Instantiated let child: Type$previous"
	fi
	cat > "Module$index/Type$index.swift" <<SWIFT
import SafeDI

@Instantiable
public final class Type$index: Instantiable {
$body
}
SWIFT
	include_arguments+=(--include "Module$index")
	printf '%s' "$dependent_module_infos" > dependencies.csv
	"$tool" generate --include "Module$index" --module-name "Module$index" --module-info-output "Module$index.safedi" --dependent-module-info-file-path dependencies.csv --combined-output "Module$index.generated.swift"
	module_info_arguments+=(--module-info "$work_directory/Module$index.safedi")
	dependent_module_infos="${dependent_module_infos:+$dependent_module_infos,}$work_directory/Module$index.safedi"
done

fail() {
	echo "::error::$1"
	exit 1
}

for source in include module-info; do
	if [ "$source" = include ]; then
		arguments=("${include_arguments[@]}")
	else
		arguments=("${module_info_arguments[@]}")
	fi
	for run in 1 2 3; do
		"$tool" query graph "${arguments[@]}" --output graph.json || fail "query graph over $source failed on run $run."
		reported=$(grep -c '"id" :' graph.json || true)
		[ "$reported" = "$module_count" ] || fail "query graph over $source reported $reported of $module_count types on run $run."
		"$tool" query needs Type039 --json "${arguments[@]}" > needs.json || fail "query needs over $source failed on run $run."
		grep -q '"typeName" : "Type039"' needs.json || fail "query needs over $source did not report Type039 on run $run."
	done
done
echo "query graph and query needs reported all $module_count modules."
