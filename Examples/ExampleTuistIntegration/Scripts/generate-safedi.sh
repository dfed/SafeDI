#!/bin/bash
#
# Invoked as a pre-compile script phase from Tuist-generated targets.
# Runs SafeDITool against one module of this example project.
#
# Usage: generate-safedi.sh <module-name> [<dependent-module-name>...]
#
#   <module-name>            Directory under $SRCROOT holding this
#                            module's .swift sources, and basename of
#                            the emitted <module-name>.safedi artifact.
#   <dependent-module-name>  Optional. Names of modules whose .safedi
#                            artifacts this module consumes — fed to
#                            `SafeDITool generate` as
#                            --dependent-module-info-file-path. Each
#                            resolves to
#                            $BUILT_PRODUCTS_DIR/SafeDI/<name>.safedi;
#                            missing files are an error (the Tuist
#                            target dependency graph guarantees they
#                            exist before this script runs).
#
# Every invocation writes $BUILT_PRODUCTS_DIR/SafeDI/<module-name>.safedi.
# Modules without downstream consumers can ignore that artifact;
# downstream modules pass the upstream's name on the command line.
# Generated Swift code (dependency tree, mocks, mock configuration)
# lands in $DERIVED_FILE_DIR; Project.swift's `.generated(...)` entries
# register those paths with the consuming target's compile phase.
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

module_name="${1:?expected <module-name> as first argument}"
shift
dependent_module_names=("$@")

: "${SRCROOT:?SRCROOT must be set (this script runs as an Xcode build phase)}"
: "${DERIVED_FILE_DIR:?DERIVED_FILE_DIR must be set (this script runs as an Xcode build phase)}"
: "${BUILT_PRODUCTS_DIR:?BUILT_PRODUCTS_DIR must be set (this script runs as an Xcode build phase)}"

scratch_dir="$DERIVED_FILE_DIR"
mkdir -p "$scratch_dir"

manifest_file="$scratch_dir/SafeDIManifest.json"

# Shared module-info location so any consuming target picks the file
# up from a configuration-scoped path that both producer and consumer
# resolve to identically.
shared_safedi_dir="$BUILT_PRODUCTS_DIR/SafeDI"
mkdir -p "$shared_safedi_dir"

module_info_output="$shared_safedi_dir/$module_name.safedi"

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

module_dir="$SRCROOT/$module_name"
if [[ ! -d "$module_dir" ]]; then
	echo "error: module directory not found at $module_dir" >&2
	exit 4
fi

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
done < <(find -L "$module_dir" -type f -name '*.swift')

if ((first)); then
	echo "error: no .swift sources found under $module_dir" >&2
	exit 4
fi

# ---------- Resolve dependent .safedi artifacts ----------

dependent_csv=""
if ((${#dependent_module_names[@]} > 0)); then
	dependent_csv="$scratch_dir/DependentModuleInfo.csv"
	: >"$dependent_csv"
	first=1
	for dependent_name in "${dependent_module_names[@]}"; do
		dependent_path="$shared_safedi_dir/$dependent_name.safedi"
		if [[ ! -f "$dependent_path" ]]; then
			echo "error: $dependent_name.safedi not found at $dependent_path — the $dependent_name target must build first" >&2
			exit 1
		fi
		if ((first)); then
			printf '%s' "$dependent_path" >>"$dependent_csv"
			first=0
		else
			printf ',%s' "$dependent_path" >>"$dependent_csv"
		fi
	done
fi

# ---------- Run SafeDITool ----------

cd "$SRCROOT"

"$safedi_tool" scan \
	--input-sources-file "$input_csv" \
	--project-root "$SRCROOT" \
	--output-directory "$scratch_dir" \
	--manifest-file "$manifest_file"

generate_args=(
	"$input_csv"
	--swift-manifest "$manifest_file"
	--module-info-output "$module_info_output"
)
if [[ -n "$dependent_csv" ]]; then
	generate_args+=(--dependent-module-info-file-path "$dependent_csv")
fi

"$safedi_tool" generate "${generate_args[@]}"

echo "Wrote $module_info_output"
echo "Wrote generated SafeDI code into $scratch_dir"
