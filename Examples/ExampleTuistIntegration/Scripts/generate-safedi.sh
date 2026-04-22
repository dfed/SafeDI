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
#     No Swift files are generated for this target unless it gains
#     @Instantiable(isRoot: true) or @Instantiable(generateMock: true)
#     declarations; if it does, those files land in $(DERIVED_FILE_DIR).
#   - `host`: reads Subproject.safedi to resolve cross-module types and
#     emits the dependency-tree + mock Swift files into
#     $(DERIVED_FILE_DIR). Project.swift's `.generated(...)` entries
#     register those paths with the host's compile phase.
#
# SafeDITool is resolved by `tuist install` via SPM (SafeDI's default
# `prebuilt` trait pulls in its `SafeDIToolBinary` artifact bundle as a
# side effect of resolving the package). Bump SafeDI by editing the
# `.package(url:from:)` requirement in Tuist/Package.swift; this script
# picks up the matching binary automatically.
#
# Neither the input source list nor the output file list is hardcoded:
# `find` enumerates each module's Swift sources, and `SafeDITool scan`
# writes a manifest that `generate` consumes to decide which Swift
# files to emit.

set -euo pipefail

mode="${1:?expected 'subproject' or 'host'}"

: "${SRCROOT:?SRCROOT must be set (this script runs as an Xcode build phase)}"
: "${DERIVED_FILE_DIR:?DERIVED_FILE_DIR must be set (this script runs as an Xcode build phase)}"

scratch_dir="$DERIVED_FILE_DIR"
mkdir -p "$scratch_dir"

manifest_file="$scratch_dir/SafeDIManifest.json"

# Shared module-info location so the host target can pick it up
# regardless of which target is doing the reading. Uses the
# configuration-scoped BUILT_PRODUCTS_DIR so both targets in a given
# build resolve to the same path.
shared_safedi_dir="$BUILT_PRODUCTS_DIR/SafeDI"
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
	;;
host)
	module_dir="ExampleTuistIntegration"
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
done < <(find -L "$SRCROOT/$module_dir" -type f -name '*.swift')

if ((first)); then
	echo "error: no .swift sources found under $SRCROOT/$module_dir" >&2
	exit 4
fi

# ---------- Run SafeDITool ----------

cd "$SRCROOT"

case "$mode" in
subproject)
	module_info_output="$shared_safedi_dir/Subproject.safedi"

	"$safedi_tool" scan \
		--input-sources-file "$input_csv" \
		--project-root "$SRCROOT" \
		--output-directory "$scratch_dir" \
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

	"$safedi_tool" scan \
		--input-sources-file "$input_csv" \
		--project-root "$SRCROOT" \
		--output-directory "$scratch_dir" \
		--manifest-file "$manifest_file"

	"$safedi_tool" generate \
		"$input_csv" \
		--swift-manifest "$manifest_file" \
		--dependent-module-info-file-path "$dependent_csv"

	echo "Wrote generated SafeDI code into $scratch_dir"
	;;
esac
