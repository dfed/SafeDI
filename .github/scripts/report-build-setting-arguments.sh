#!/bin/bash
# Usage: report-build-setting-arguments.sh BUILD_LOG
#
# Finds the SafeDIGenerator plugin's generate command in a verbose build log, prints it, and
# prints on its last line how it carried the build-setting arguments:
#   expanded   – the build system replaced `${SWIFT_ACTIVE_COMPILATION_CONDITIONS}` with its value
#   unexpanded – the reference reached SafeDITool literally, so SafeDITool falls back
#   withheld   – the plugin did not pass the arguments
# Exits non-zero when the log does not show the command, which a step must not mistake for any of these.
set -eu

log=$1
# The generate command reads the plugin's InputSwiftFiles.csv; scan runs while the plugin plans and is not logged.
command_line=$(grep -E 'InputSwiftFiles\.csv.*(--swift-manifest|--output-directory)' "$log" | grep -v 'SPMCustomBuildCommand' | tail -n 1 || true)
if [ -z "$command_line" ]; then
	echo "::error::The build log $log does not show the SafeDIGenerator plugin's generate command." >&2
	exit 1
fi
echo "Generate command: $command_line" >&2
case "$command_line" in
	*build-setting-active-compilation-conditions*SWIFT_ACTIVE_COMPILATION_CONDITIONS*) echo unexpanded ;;
	*build-setting-active-compilation-conditions*) echo expanded ;;
	*) echo withheld ;;
esac
