#!/bin/bash
# Usage: report-build-setting-arguments.sh BUILD_LOG
#
# Finds the SafeDIGenerator plugin's generate command in a verbose build log, prints it, and
# prints on its last line how it carried the build-setting arguments:
#   expanded   – the build system replaced `${SWIFT_ACTIVE_COMPILATION_CONDITIONS}` with its value
#   unexpanded – the reference reached SafeDITool literally, so SafeDITool falls back
# Also reports which SafeDITool the command ran. Swift 6.2 sometimes hands the plugin the prebuilt
# binary from the artifact bundle even when the package asks for a source build with the
# `sourceBuild` trait, and such a build exercises that release rather than this checkout's tool.
# Exits non-zero when the log does not show the command, or when the command does not carry the
# arguments, which the plugin always passes. A step must not mistake either for a result.
set -eu

log=$1
# The generate command reads the plugin's InputSwiftFiles.csv; scan runs while the plugin plans and is not logged.
command_line=$(grep -E 'InputSwiftFiles\.csv.*(--swift-manifest|--output-directory)' "$log" | grep -v 'SPMCustomBuildCommand' | tail -n 1 || true)
if [ -z "$command_line" ]; then
	echo "::error::The build log $log does not show the SafeDIGenerator plugin's generate command." >&2
	exit 1
fi
echo "Generate command: $command_line" >&2
if echo "$command_line" | grep -Eq '\.artifactbundle/[^ ]*/SafeDITool [^ ]*InputSwiftFiles\.csv'; then
	echo "::notice::The generate command ran the prebuilt SafeDITool from the artifact bundle, not one built from this checkout." >&2
elif echo "$command_line" | grep -Eq '/\.safedi/[^ ]*/safeditool [^ ]*InputSwiftFiles\.csv'; then
	echo "::notice::The generate command ran the SafeDITool downloaded into .safedi/, not one built from this checkout." >&2
else
	echo "The generate command ran a SafeDITool built from this checkout." >&2
fi
case "$command_line" in
	*build-setting-active-compilation-conditions*SWIFT_ACTIVE_COMPILATION_CONDITIONS*) echo unexpanded ;;
	*build-setting-active-compilation-conditions*) echo expanded ;;
	*)
		echo "::error::The SafeDIGenerator plugin's generate command does not carry the build-setting arguments." >&2
		exit 1
		;;
esac
