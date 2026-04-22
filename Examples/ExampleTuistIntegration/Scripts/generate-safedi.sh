#!/bin/bash
#
# Invoked as a pre-compile script phase from Tuist-generated targets.
# Runs SafeDITool against one module of this example project.
#
# Usage: generate-safedi.sh <subproject|host>
#
# Behavior:
#   - `subproject`: emits a `.safedi` module-info artifact for the
#     Subproject framework into $(BUILT_PRODUCTS_DIR)/SafeDI/Subproject.safedi.
#     No Swift files are generated for this target (Subproject has no
#     @Instantiable(isRoot:) and no @Instantiable(generateMock: true)
#     declarations today, but the script doesn't hardcode that — it just
#     runs whatever SafeDITool would run for any module).
#   - `host`: reads Subproject.safedi to resolve cross-module types and
#     emits the dependency-tree + mock Swift files into
#     ExampleTuistIntegration/Generated/. Whatever @Instantiable(isRoot:)
#     / @Instantiable(generateMock: true) declarations exist in the host
#     module determine the set of generated files — see
#     Sources/SafeDICore/Utilities/OutputFileNaming.swift for the
#     filename rules.
#
# SafeDITool is resolved by `tuist install`, which invokes SPM on
# Tuist/Package.swift. SafeDI's default trait chain pulls in its
# `SafeDIToolBinary` binary target for the SafeDIGenerator plugin, so
# the .artifactbundle.zip is downloaded + unpacked as a side effect of
# resolving SafeDI itself — no separate binary-target declaration
# needed here. Bump SafeDI by editing the `.package(url:from:)`
# requirement in Tuist/Package.swift; this script picks up the
# matching binary automatically.
#
# Neither the input source list nor the output file list is hardcoded:
# `find` enumerates the target's Swift sources, `scan` discovers roots
# and mocks, and the emitted Swift filenames are whatever the manifest
# lists. The script writes a single timestamp marker as its declared
# output so Xcode's dep-analysis has something concrete to compare —
# the generated `.swift` files are picked up by the target's source
# glob, not via output-file tracking here.

set -euo pipefail

mode="${1:?expected 'subproject' or 'host'}"

: "${SRCROOT:?SRCROOT must be set (this script runs as an Xcode build phase)}"

scratch_dir="${DERIVED_FILE_DIR:-$SRCROOT/.build/tuist-safedi-$mode}"
mkdir -p "$scratch_dir"

manifest_file="$scratch_dir/SafeDIManifest.json"

# Shared module-info location so the host target can pick it up
# regardless of which target is doing the reading.
shared_safedi_dir="${BUILT_PRODUCTS_DIR:-$SRCROOT/.build/SharedProducts}/SafeDI"
mkdir -p "$shared_safedi_dir"

# ---------- Locate the tuist-resolved SafeDITool binary ----------

host_os="$(uname -s)"
host_arch="$(uname -m)"
case "$host_os:$host_arch" in
Darwin:arm64)  tool_variant="SafeDITool-macos-arm64" ;;
Darwin:x86_64) tool_variant="SafeDITool-macos-x86_64" ;;
Linux:aarch64 | Linux:arm64)  tool_variant="SafeDITool-linux-arm64" ;;
Linux:x86_64 | Linux:amd64)   tool_variant="SafeDITool-linux-x86_64" ;;
*)
	echo "error: unsupported host $host_os/$host_arch" >&2
	exit 3
	;;
esac

artifact_bundle="$SRCROOT/Tuist/.build/artifacts/safedi/SafeDIToolBinary/SafeDITool.artifactbundle"
safedi_tool="$artifact_bundle/$tool_variant/bin/SafeDITool"

if [[ ! -x "$safedi_tool" ]]; then
	echo "error: SafeDITool not found at $safedi_tool" >&2
	echo "       run \`tuist install\` to fetch it — that drives SPM" >&2
	echo "       resolution on Tuist/Package.swift, which pulls SafeDI" >&2
	echo "       and its SafeDIToolBinary.artifactbundle." >&2
	exit 5
fi

# ---------- Collect this module's Swift sources ----------

case "$mode" in
subproject)
	module_dir="Subproject"
	# Subproject has no Generated/ — nothing to exclude.
	find_cmd=(find -L "$SRCROOT/$module_dir" -type f -name '*.swift')
	;;
host)
	module_dir="ExampleTuistIntegration"
	# Exclude Generated/ from inputs; those files are this script's
	# own outputs, and including them would create an input/output
	# cycle the same way declaring them as Tuist script inputs would.
	find_cmd=(find -L "$SRCROOT/$module_dir" -type f -name '*.swift' -not -path "$SRCROOT/$module_dir/Generated/*")
	;;
*)
	echo "error: unknown mode '$mode' (expected 'subproject' or 'host')" >&2
	exit 2
	;;
esac

# Build a CSV of paths relative to $SRCROOT so `scan` and `generate`
# agree on file identity (the manifest validator rejects absolute paths
# against a relative project root).
input_csv="$scratch_dir/InputSwiftFiles.csv"
: >"$input_csv"
first=1
while IFS= read -r abs; do
	rel="${abs#"$SRCROOT/"}"
	if ((first)); then
		printf '%s' "$rel" >>"$input_csv"
		first=0
	else
		printf ',%s' "$rel" >>"$input_csv"
	fi
done < <("${find_cmd[@]}")

if ((first)); then
	echo "error: no .swift sources found under $SRCROOT/$module_dir" >&2
	exit 4
fi

# ---------- Run SafeDITool ----------

cd "$SRCROOT"

case "$mode" in
subproject)
	module_info_output="$shared_safedi_dir/Subproject.safedi"
	# Subproject has no roots/mocks today, so scan's output directory
	# receives no Swift. Keep it inside the scratch dir so the only
	# committed artifact is the .safedi file — and if someone later
	# adds a root or generateMock type to Subproject, it'll land here
	# automatically without this script needing an edit.
	subproject_output_directory="$scratch_dir/GeneratedOutputs"
	mkdir -p "$subproject_output_directory"

	"$safedi_tool" scan \
		--input-sources-file "$input_csv" \
		--project-root "$SRCROOT" \
		--output-directory "$subproject_output_directory" \
		--manifest-file "$manifest_file"

	"$safedi_tool" generate \
		"$input_csv" \
		--swift-manifest "$manifest_file" \
		--module-info-output "$module_info_output"

	echo "Wrote $module_info_output"
	;;
host)
	dependent_module_info="$shared_safedi_dir/Subproject.safedi"
	if [[ ! -f "$dependent_module_info" ]]; then
		echo "error: Subproject.safedi not found at $dependent_module_info — Subproject target must build first" >&2
		exit 1
	fi
	dependent_csv="$scratch_dir/DependentModuleInfo.csv"
	printf '%s' "$dependent_module_info" >"$dependent_csv"

	host_output_directory="$SRCROOT/$module_dir/Generated"
	mkdir -p "$host_output_directory"

	"$safedi_tool" scan \
		--input-sources-file "$input_csv" \
		--project-root "$SRCROOT" \
		--output-directory "$host_output_directory" \
		--manifest-file "$manifest_file"

	"$safedi_tool" generate \
		"$input_csv" \
		--swift-manifest "$manifest_file" \
		--dependent-module-info-file-path "$dependent_csv"

	# Single-file dep-analysis marker — the generated `.swift` files
	# are picked up by Tuist's source glob. `outputPaths` in
	# Project.swift points at this one path.
	marker="$DERIVED_FILE_DIR/safedi-generated.marker"
	date +%s >"$marker"
	echo "Wrote generated SafeDI code into $host_output_directory"
	;;
esac
