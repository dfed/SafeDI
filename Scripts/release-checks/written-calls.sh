#!/bin/zsh
# Scripts/release-checks/written-calls.sh --tool SAFEDITOOL [--macros MACROS] [--modules DIRECTORY] [--output DIRECTORY]
#                                         [--compile-only] [--configuration debug|release]
#
# A release check: code written against a release still compiles against a later SafeDITool. The fixture modules in
# `written-calls/` hold hand-written calls of every generated declaration the release’s manual tells a person to call:
# a root’s `init()`, the wrappers a tree builds, `mock()` with its flat parameters and `safeDIOverrides`,
# `SafeDIOverrides` and `SafeDIMockConfiguration` values, a seam’s initializers with readable labels and their hole
# builders, and public mocks called from a module of another package. Each call names the manual section it comes from.
#
# For each configuration (`debug`: `DEBUG` active, so the mocks compile; `release`: no condition), the script runs the
# given `SafeDITool generate` once per module, in dependency order, as Bazel and Tuist run it (one combined output and
# one `.safedi` per module), then compiles each module’s fixture sources with its generated code, against the `SafeDI`
# library and macros built beside the tool. A failing compile is a break of a documented call form: a removed
# parameter, a newly required one, a renamed label or a changed type.
#
# The fixtures at a release’s tag are the calls that release documents. To check a later head against release R, build
# the head’s `SafeDITool` and `SafeDI` library (which builds the macros) in the head’s checkout, and run R’s copy of
# this script, from a checkout of R, with the head’s tool; the macros and `SafeDI.swiftmodule` are found beside it:
#     swift build --traits sourceBuild -c release --product SafeDITool
#     swift build --traits sourceBuild -c release --product SafeDI
#     <checkout of R>/Scripts/release-checks/written-calls.sh --tool <head’s checkout>/.build/release/SafeDITool
# When a release documents a new call form, add a call of it here before its tag. Change no call a released manual
# documents: that call is what a later release must keep compiling.
#
# Layout:  written-calls/<Module>/Sources/*.swift     the module’s files: declarations and hand-written calls
#          written-calls/<Module>/dependencies.txt     the modules it depends on, one per line
#          written-calls/<Module>/package.txt          optional: its package name (default `Shop`)
#          written-calls/modules.txt                   the modules, in the order they generate and compile
# Output:  <output>/<configuration>/<Module>+SafeDI.swift (generated), <Module>.safedi, .swiftmodule, .o; default
#          `.build/release-checks/written-calls` in this checkout. Temporary files go to <output>/tmp.
# `--compile-only` skips generation and compiles the generated files already in <output>, so that a test of the check
# can edit a generated file and see the compile fail.
set -euo pipefail
step="reading the arguments"
trap 'failure_status=$?; (( ZSH_SUBSHELL )) || print -ru2 -- "${0:t}: failed with status $failure_status at line $LINENO, while $step"' ZERR

usage="usage: $0 --tool SAFEDITOOL [--macros MACROS] [--modules DIRECTORY] [--output DIRECTORY] [--compile-only] [--configuration debug|release]"
tool="" macros="" module_search_path="" output="" compile_only=0
configurations=(debug release)
while (( $# )); do
	case $1 in
	--tool) tool=${2:A}; shift 2 ;;
	--macros) macros=${2:A}; shift 2 ;;
	--modules) module_search_path=${2:A}; shift 2 ;;
	--output) output=${2:A}; shift 2 ;;
	--compile-only) compile_only=1; shift ;;
	--configuration) configurations=($2); shift 2 ;;
	*) print -ru2 -- "$usage"; exit 2 ;;
	esac
done
[[ -n "$tool" ]] || { print -ru2 -- "$usage"; exit 2; }
[[ -x "$tool" ]] || { print -ru2 -- "no executable SafeDITool at $tool"; exit 2; }
for configuration in "${configurations[@]}"; do
	[[ "$configuration" == (debug|release) ]] || { print -ru2 -- "$usage"; exit 2; }
done

fixtures=${0:A:h}/written-calls
repository=$(git -C "${0:A:h}" rev-parse --show-toplevel)
[[ -n "$output" ]] || output="$repository/.build/release-checks/written-calls"
bin=${tool:h}
# As `Scripts/multi-module-repro.sh` finds them: SwiftPM’s native build names the macro executable
# `SafeDIMacros-tool`, Swift Build names it `SafeDIMacros`.
if [[ -z "$macros" ]]; then
	for candidate in "$bin/SafeDIMacros-tool" "$bin/SafeDIMacros-tool.exe" "$bin/SafeDIMacros"; do
		[[ -f "$candidate" ]] && { macros=$candidate; break; }
	done
fi
[[ -n "$macros" && -f "$macros" ]] || { print -ru2 -- "no SafeDIMacros executable beside $tool: build the SafeDI product too, or pass --macros"; exit 2; }
# `SafeDI.swiftmodule` is a directory on macOS and a single file on Linux, so test that it exists.
if [[ -z "$module_search_path" ]]; then
	module_search_path="$bin/Modules"; [[ -e "$module_search_path/SafeDI.swiftmodule" ]] || module_search_path="$bin"
fi
[[ -e "$module_search_path/SafeDI.swiftmodule" ]] || { print -ru2 -- "no SafeDI.swiftmodule in $module_search_path: build the SafeDI product too, or pass --modules"; exit 2; }
swiftc=(swiftc); command -v xcrun >/dev/null 2>&1 && swiftc=(xcrun swiftc)
module_order=(${(f)"$(sed '/^[[:space:]]*$/d' "$fixtures/modules.txt")"})

# The tool and the compiler write temporary files; keep them out of the system temporary directory.
mkdir -p "$output/tmp"
export TMPDIR="$output/tmp/"

package_of() {
	[[ -f "$fixtures/$1/package.txt" ]] && head -1 "$fixtures/$1/package.txt" || print -r -- Shop
}

print -ru2 -- "SafeDITool: $tool ($("$tool" --version))"
for configuration in "${configurations[@]}"; do
	directory="$output/$configuration"
	condition_list=()
	[[ "$configuration" == debug ]] && condition_list=(DEBUG)
	if (( ! compile_only )); then
		rm -rf "$directory"; mkdir -p "$directory"
		for module in "${module_order[@]}"; do
			step="preparing to generate $module ($configuration)"
			sources=("$fixtures/$module"/Sources/**/*.swift(N))
			(( ${#sources} )) || { print -ru2 -- "$module: no Swift files under $fixtures/$module/Sources"; exit 2; }
			print -rn -- "${(j:,:)sources}" >"$directory/$module.csv"
			arguments=("$directory/$module.csv"
				--combined-output "$directory/$module+SafeDI.swift"
				--compiler-receives-input-paths-unchanged
				--module-info-output "$directory/$module.safedi" --module-name "$module"
				--package-name "$(package_of "$module")")
			(( ${#condition_list} )) && arguments+=(--active-compilation-conditions "${condition_list[@]}")
			dependencies=()
			[[ -f "$fixtures/$module/dependencies.txt" ]] && dependencies=(${(f)"$(sed '/^[[:space:]]*$/d' "$fixtures/$module/dependencies.txt")"})
			if (( ${#dependencies} )); then
				dependency_paths=()
				for dependency in "${dependencies[@]}"; do dependency_paths+=("$directory/$dependency.safedi"); done
				print -rn -- "${(j:,:)dependency_paths}" >"$directory/$module-dependencies.csv"
				arguments+=(--dependent-module-info-file-path "$directory/$module-dependencies.csv")
			fi
			step="generating $module ($configuration)"
			print -ru2 -- "--- $configuration: generate $module"
			"$tool" generate "${arguments[@]}"
		done
	fi
	for module in "${module_order[@]}"; do
		sources=("$fixtures/$module"/Sources/**/*.swift(N))
		step="compiling $module ($configuration)"
		[[ -f "$directory/$module+SafeDI.swift" ]] || { print -ru2 -- "no generated $directory/$module+SafeDI.swift: run without --compile-only first"; exit 2; }
		print -ru2 -- "--- $configuration: swiftc $module"
		"${swiftc[@]}" -emit-object -whole-module-optimization -parse-as-library \
			-o "$directory/$module.o" -module-name "$module" -package-name "$(package_of "$module")" \
			-emit-module -emit-module-path "$directory/$module.swiftmodule" \
			-I "$module_search_path" -I "$directory" \
			-load-plugin-executable "$macros#SafeDIMacros" -swift-version 6 \
			${condition_list/#/-D} \
			"${sources[@]}" "$directory/$module+SafeDI.swift"
	done
done
print -ru2 -- "--- every written call compiled (${(j:, :)configurations}); outputs in $output"
