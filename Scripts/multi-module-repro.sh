#!/bin/zsh
# Scripts/multi-module-repro.sh [--conditions DEBUG,X] ROOT MODULE...
# Reproduces a multi-module shape as Bazel and Tuist build it (the graph fuzzer's `.moduleInfo` integration): runs
# `SafeDITool generate` for each MODULE in the order given, reading the `.safedi` of each module it depends on, then
# compiles the modules in the same order with swiftc, so the reproduction ends in the compiler's verdict.
#
# Layout:  ROOT/<Module>/Sources/*.swift            the module's files
#          ROOT/<Module>/dependencies.txt            optional: one module it depends on per line
#          ROOT/package.txt                          optional: the package name (default: ROOT's basename)
# Output:  ROOT/.safedi-out/<Module>.swift (generated), <Module>.safedi, <Module>.swiftmodule, <Module>.o
# Conditions (default DEBUG) go to `generate` as --active-compilation-conditions and to swiftc as -D flags.
set -euo pipefail
# A command that fails ends the script (`set -e`), and not every command prints why, so say which step it was. A
# subshell that fails stays quiet, so that the step is named once, by the line that started it.
step="reading the arguments"
trap 'failure_status=$?; (( ZSH_SUBSHELL )) || print -ru2 -- "${0:t}: failed with status $failure_status at line $LINENO, while $step"' ZERR
conditions=DEBUG
if [[ "${1:-}" == "--conditions" ]]; then conditions=$2; shift 2; fi
(( $# >= 2 )) || { echo "usage: $0 [--conditions DEBUG,X] ROOT MODULE..." >&2; exit 2; }
root=${1:A}; shift
repository=$(git -C "${0:A:h}" rev-parse --show-toplevel)
package=$( [[ -f "$root/package.txt" ]] && head -1 "$root/package.txt" || basename "$root" )
output="$root/.safedi-out"; mkdir -p "$output"
condition_list=(${(s:,:)conditions})

step="building SafeDITool, SafeDI and the macros"
echo "Building SafeDITool, SafeDI and the macros (--traits sourceBuild)…" >&2
(cd "$repository" && swift build --traits sourceBuild >&2)
bin=$(cd "$repository" && swift build --traits sourceBuild --show-bin-path)
tool="$bin/SafeDITool"
# As SafeDIBuildArtifactLocator finds them: SwiftPM's native build names the macro executable `SafeDIMacros-tool`,
# Swift Build names it `SafeDIMacros` beside a `SafeDIMacros.swiftmodule` directory.
step="finding what the build made"
macros=""
for candidate in "$bin/SafeDIMacros-tool" "$bin/SafeDIMacros-tool.exe" "$bin/SafeDIMacros"; do
	[[ -f "$candidate" ]] && { macros=$candidate; break; }
done
[[ -n "$macros" ]] || { echo "no SafeDIMacros executable in $bin" >&2; exit 1; }
# `SafeDI.swiftmodule` is a directory on macOS and a single file on Linux, so test that it exists, not that it is a directory.
module_search_path="$bin/Modules"; [[ -e "$module_search_path/SafeDI.swiftmodule" ]] || module_search_path="$bin"
swiftc=(swiftc); command -v xcrun >/dev/null 2>&1 && swiftc=(xcrun swiftc)

for module in "$@"; do
	step="preparing to generate $module"
	sources=("$root/$module"/Sources/**/*.swift(N))
	(( ${#sources} )) || { echo "$module: no Swift files under $root/$module/Sources" >&2; exit 2; }
	print -rn -- "${(j:,:)sources}" >"$output/$module.csv"
	arguments=("$output/$module.csv"
		--combined-output "$output/$module.swift"
		--compiler-receives-input-paths-unchanged
		--module-info-output "$output/$module.safedi" --module-name "$module"
		--package-name "$package")
	(( ${#condition_list} )) && arguments+=(--active-compilation-conditions "${condition_list[@]}")
	dependencies=()
	# sed, not `grep -v`: grep's status is 1 when it selects no line, which ended the script without a word on a
	# `dependencies.txt` that is empty or holds only blank lines.
	[[ -f "$root/$module/dependencies.txt" ]] && dependencies=(${(f)"$(sed '/^[[:space:]]*$/d' "$root/$module/dependencies.txt")"})
	if (( ${#dependencies} )); then
		# One path per dependency, built element by element: a nested substitution inside double quotes joins the array
		# into one word before an outer prefix or suffix applies.
		dependency_paths=()
		for dependency in "${dependencies[@]}"; do dependency_paths+=("$output/$dependency.safedi"); done
		print -rn -- "${(j:,:)dependency_paths}" >"$output/$module-dependencies.csv"
		arguments+=(--dependent-module-info-file-path "$output/$module-dependencies.csv")
	fi
	step="generating $module"
	echo "--- generate $module" >&2
	"$tool" generate "${arguments[@]}"
done

for module in "$@"; do
	sources=("$root/$module"/Sources/**/*.swift(N))
	step="compiling $module"
	echo "--- swiftc $module" >&2
	"${swiftc[@]}" -emit-object -whole-module-optimization -parse-as-library \
		-o "$output/$module.o" -module-name "$module" -package-name "$package" \
		-emit-module -emit-module-path "$output/$module.swiftmodule" \
		-I "$module_search_path" -I "$output" \
		-load-plugin-executable "$macros#SafeDIMacros" -swift-version 6 \
		${condition_list/#/-D} \
		"${sources[@]}" "$output/$module.swift"
done
echo "--- every module compiled; outputs in $output" >&2
