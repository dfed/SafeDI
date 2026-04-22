#!/bin/bash
#
# Invoked as a pre-compile script phase from Tuist-generated targets.
# Runs SafeDITool against one module of this example project.
#
# Usage: generate-safedi.sh <subproject|host>
#
# Behavior:
#   - `subproject`: emits a `.safedi` module-info artifact for the Subproject
#     framework into BUILT_PRODUCTS_DIR/SafeDI/Subproject.safedi. No Swift
#     files are generated (Subproject has no @Instantiable(isRoot:) and no
#     @Instantiable(generateMock: true) types).
#   - `host`: reads Subproject.safedi to resolve cross-module types, then
#     generates the host module's dependency tree (NotesApp+SafeDI.swift)
#     and mock methods (LoggedInView+SafeDIMock.swift,
#     NameEntryView+SafeDIMock.swift, SafeDIMockConfiguration.swift) into
#     ExampleTuistIntegration/Generated/.
#
# SafeDITool is built from source on demand and cached in
# $SAFEDI_REPO_ROOT/.build/release/SafeDITool so subsequent builds reuse it.
#
# This script invokes SafeDITool's `scan` and `generate` subcommands
# separately (the same flow the SafeDIGenerator SPM plugin uses) so the
# manifest/cache files land in a scratch dir instead of polluting the
# host's Generated/ source directory. Paths in the CSV are project-root-
# relative so `scan` and `generate` agree on file identity — the manifest
# validator rejects absolute paths in this mode.

set -euo pipefail

mode="${1:?expected 'subproject' or 'host'}"

: "${SRCROOT:?SRCROOT must be set (this script runs as an Xcode build phase)}"

# SafeDITool lives in the SafeDI repo two directories up from the example.
# This relative path is fixed by the on-disk layout:
#   <repo>/Examples/ExampleTuistIntegration/  <- SRCROOT
#   <repo>/                                    <- safedi_repo_root
safedi_repo_root="$(cd "$SRCROOT/../.." && pwd)"
safedi_tool="$safedi_repo_root/.build/release/SafeDITool"

if [[ ! -x "$safedi_tool" ]]; then
	echo "Building SafeDITool from source (first run) ..."
	pushd "$safedi_repo_root" >/dev/null
	# xcrun picks up the toolchain from DEVELOPER_DIR so this works both in
	# Xcode's build-phase environment (where `swift` isn't on PATH) and from
	# a plain shell.
	xcrun swift build -c release --product SafeDITool
	popd >/dev/null
fi

scratch_dir="${DERIVED_FILE_DIR:-$SRCROOT/.build/tuist-safedi-$mode}"
mkdir -p "$scratch_dir"

manifest_file="$scratch_dir/SafeDIManifest.json"

# Shared module-info location so the host target can pick it up regardless
# of which target is doing the reading.
shared_safedi_dir="${BUILT_PRODUCTS_DIR:-$SRCROOT/.build/SharedProducts}/SafeDI"
mkdir -p "$shared_safedi_dir"

write_csv() {
	local csv_path="$1"
	shift
	(
		IFS=,
		printf '%s' "$*"
	) >"$csv_path"
}

case "$mode" in
subproject)
	module_sources=(
		"Subproject/SafeDIConfiguration.swift"
		"Subproject/User.swift"
		"Subproject/InMemoryStorage.swift"
		"Subproject/NoteStorage.swift"
		"Subproject/StringStorage.swift"
		"Subproject/UserService.swift"
	)
	input_csv="$scratch_dir/InputSwiftFiles.csv"
	write_csv "$input_csv" "${module_sources[@]}"

	module_info_output="$shared_safedi_dir/Subproject.safedi"
	# The subproject has no roots and no `generateMock: true`, so scan's
	# output directory receives no Swift. Keep it inside the scratch dir
	# so the only committed artifact is the .safedi file.
	output_directory="$scratch_dir/GeneratedOutputs"
	mkdir -p "$output_directory"

	cd "$SRCROOT"
	"$safedi_tool" scan \
		--input-sources-file "$input_csv" \
		--project-root "$SRCROOT" \
		--output-directory "$output_directory" \
		--manifest-file "$manifest_file"

	"$safedi_tool" generate \
		"$input_csv" \
		--swift-manifest "$manifest_file" \
		--module-info-output "$module_info_output"

	echo "Wrote $module_info_output"
	;;
host)
	module_sources=(
		"ExampleTuistIntegration/SafeDIConfiguration.swift"
		"ExampleTuistIntegration/Views/LoggedInView.swift"
		"ExampleTuistIntegration/Views/NameEntryView.swift"
		"ExampleTuistIntegration/Views/NotesApp.swift"
	)
	input_csv="$scratch_dir/InputSwiftFiles.csv"
	write_csv "$input_csv" "${module_sources[@]}"

	dependent_module_info="$shared_safedi_dir/Subproject.safedi"
	if [[ ! -f "$dependent_module_info" ]]; then
		echo "error: Subproject.safedi not found at $dependent_module_info — Subproject target must build first" >&2
		exit 1
	fi
	dependent_csv="$scratch_dir/DependentModuleInfo.csv"
	printf '%s' "$dependent_module_info" >"$dependent_csv"

	output_directory="$SRCROOT/ExampleTuistIntegration/Generated"
	mkdir -p "$output_directory"

	cd "$SRCROOT"
	"$safedi_tool" scan \
		--input-sources-file "$input_csv" \
		--project-root "$SRCROOT" \
		--output-directory "$output_directory" \
		--manifest-file "$manifest_file"

	"$safedi_tool" generate \
		"$input_csv" \
		--swift-manifest "$manifest_file" \
		--dependent-module-info-file-path "$dependent_csv"

	echo "Wrote generated SafeDI code into $output_directory"
	;;
*)
	echo "error: unknown mode '$mode' (expected 'subproject' or 'host')" >&2
	exit 2
	;;
esac
