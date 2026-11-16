#!/bin/zsh
# build.zsh VARIANT OPTIMIZATION [extra swiftc flags…]
# Builds and links one variant of a fixture. VARIANT/modules.txt lists one module per line, in build order:
#   <Module> <mode> [dependency…]
# mode `tool`: SafeDITool generate writes the module's code (as Scripts/multi-module-repro.sh runs it per module);
# mode `hand`: the module's hand-written generated code is VARIANT/<Module>/Generated/*.swift (or *.swift.txt);
# mode `plain`: no generated code. The last module is the executable, whose Sources hold main.swift.
# Sources are VARIANT/<Module>/Sources/*.swift(.txt) plus ../shared/<Module>/*.swift(.txt) when VARIANT/<Module>/shared names a folder.
# OPTIMIZATION is Onone or O. Output, outside the checkout so SwiftFormat never reads it:
# ${SPIKE_OUTPUT:-~/.cache/per-type-seam-spike}/<variant path>/out-OPTIMIZATION/, the executable `main`.
set -euo pipefail
variant=${1:A}; optimization=$2; shift 2
extra=("$@")
# macOS: swiftc defaults to an old deployment target, below the harness's `Mutex` (macOS 15), so name one.
platform=()
[[ $(uname) == Darwin ]] && platform=(-target "$(uname -m)-apple-macosx15.0")
spike=${0:A:h:h}
repository=$(git -C "$spike" rev-parse --show-toplevel)
bin=$(cd "$repository" && swift build --traits sourceBuild --show-bin-path)
tool="$bin/SafeDITool"
macros="$bin/SafeDIMacros-tool"
module_search_path="$bin/Modules"; [[ -e "$module_search_path/SafeDI.swiftmodule" ]] || module_search_path="$bin"
output_root=${SPIKE_OUTPUT:-$HOME/.cache/per-type-seam-spike}
output="$output_root/${variant#$spike/}/out-$optimization"; rm -rf "$output"; mkdir -p "$output/src"
safedi_objects=("$bin"/SafeDI.build/*.o)
if (( ${extra[(I)-enable-library-evolution]} )); then
	# Library evolution: SafeDI itself is compiled with it too, from the checkout's sources, so no warning (an error under
	# -warnings-as-errors) says it was not.
	swiftc -emit-object -whole-module-optimization -parse-as-library -$optimization -o "$output/SafeDI.o" -module-name SafeDI \
		-emit-module -emit-module-path "$output/SafeDI.swiftmodule" -load-plugin-executable "$macros#SafeDIMacros" \
		-swift-version 6 -I "$module_search_path" "${platform[@]}" "${extra[@]}" "$repository"/Sources/SafeDI/**/*.swift
	safedi_objects=("$output/SafeDI.o")
	module_search_path="$output"
fi

module_list=(); typeset -A modes deps
while read -r name mode rest; do
	[[ -z "$name" || "$name" == \#* ]] && continue
	module_list+=("$name"); modes[$name]=$mode; deps[$name]="$rest"
done <"$variant/modules.txt"

sources_of() {
	local module=$1 files=() file
	for file in "$variant/$module"/Sources/*.swift(N) "$variant/$module"/Sources/*.swift.txt(N); do files+=("$file"); done
	if [[ -f "$variant/$module/shared" ]]; then
		local shared=${variant:h}/$(head -1 "$variant/$module/shared")
		for file in "$shared"/*.swift(N) "$shared"/*.swift.txt(N); do files+=("$file"); done
	fi
	print -r -- "${files[@]}"
}

package_of() {
	# VARIANT/<Module>/package names the module's package; the default is Spike.
	if [[ -f "$variant/$1/package" ]]; then head -1 "$variant/$1/package"; else print Spike; fi
}

objects=()
for module in "${module_list[@]}"; do
	mkdir -p "$output/src/$module"
	for file in ${(z)"$(sources_of $module)"}; do cp "$file" "$output/src/$module/${${file:t}%.txt}"; done
	case ${modes[$module]} in
	tool)
		sources=("$output/src/$module"/*.swift)
		print -rn -- "${(j:,:)sources}" >"$output/$module.csv"
		arguments=("$output/$module.csv" --combined-output "$output/src/$module/__Generated.swift" --compiler-receives-input-paths-unchanged
			--module-info-output "$output/$module.safedi" --module-name "$module" --package-name "$(package_of $module)" --active-compilation-conditions DEBUG)
		dependency_paths=()
		for dependency in ${(z)deps[$module]}; do [[ -f "$output/$dependency.safedi" ]] && dependency_paths+=("$output/$dependency.safedi"); done
		if (( ${#dependency_paths} )); then
			print -rn -- "${(j:,:)dependency_paths}" >"$output/$module-dependencies.csv"
			arguments+=(--dependent-module-info-file-path "$output/$module-dependencies.csv")
		fi
			[[ -n "${SKIP_GENERATE:-}" && -f "$variant/stored/$module.swift.txt" ]] && { cp "$variant/stored/$module.swift.txt" "$output/src/$module/__Generated.swift"; } || "$tool" generate "${arguments[@]}"
		mkdir -p "$variant/stored"; cp "$output/src/$module/__Generated.swift" "$variant/stored/$module.swift.txt"
		;;
	hand)
		for file in "$variant/$module"/Generated/*.swift(N) "$variant/$module"/Generated/*.swift.txt(N); do cp "$file" "$output/src/$module/${${file:t}%.txt}"; done
		;;
	plain) ;;
	esac
	sources=("$output/src/$module"/*.swift)
	if [[ "$module" == "${module_list[-1]}" ]]; then library=(); flags=(); else library=(-parse-as-library); flags=("${extra[@]}"); fi
	# TIME_LOG names a folder: each module's compile then runs under `timeout 20m /usr/bin/time -v`, which writes
	# <TIME_LOG>/<Module>.time.
	timing=()
	[[ -n "${TIME_LOG:-}" ]] && { mkdir -p "$TIME_LOG"; timing=(timeout 20m /usr/bin/time -v -o "$TIME_LOG/$module.time"); }
	"${timing[@]}" swiftc -emit-object -whole-module-optimization "${library[@]}" -$optimization \
		-o "$output/$module.o" -module-name "$module" -package-name "$(package_of $module)" \
		-emit-module -emit-module-path "$output/$module.swiftmodule" \
		-I "$module_search_path" -I "$output" \
		-load-plugin-executable "$macros#SafeDIMacros" -swift-version 6 -warnings-as-errors -D DEBUG "${platform[@]}" \
		"${flags[@]}" "${sources[@]}"
	objects+=("$output/$module.o")
done
swiftc "${platform[@]}" -o "$output/main" "${objects[@]}" "${safedi_objects[@]}"
