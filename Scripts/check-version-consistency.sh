#!/bin/bash

# This script checks that the version string is consistent across all files
# that contain it. Run this in CI to catch version mismatches.

set -e

# Helper function to extract and validate a version
extract_version() {
    local file="$1"
    local pattern="$2"
    local context_lines="$3"
    local quote_char="$4"

    local version
    version=$(grep -A"$context_lines" "$pattern" "$file" | grep -o "${quote_char}[0-9]*\.[0-9]*\.[0-9]*${quote_char}" | tr -d "$quote_char")

    local count
    count=$(echo "$version" | grep -c . || true)

    if [ -z "$version" ]; then
        echo "ERROR: Could not find version in $file" >&2
        return 1
    elif [ "$count" -gt 1 ]; then
        echo "ERROR: Found multiple versions in $file: $version" >&2
        return 1
    fi

    echo "$version"
}

echo "Checking version consistency..."

# Extract version from SafeDITool.swift (looks for the line after "static var currentVersion")
TOOL_VERSION=$(extract_version "Sources/SafeDITool/SafeDITool.swift" "static var currentVersion" 1 '"')
echo "  SafeDITool.swift:     $TOOL_VERSION"

# Extract version from Plugins/Shared.swift (the safeDIVersion property in XcodePluginContext)
PLUGIN_VERSION=$(extract_version "Plugins/Shared.swift" "var safeDIVersion: String" 4 '"')
echo "  Plugins/Shared.swift: $PLUGIN_VERSION"

# Extract version from SafeDI.podspec
PODSPEC_VERSION=$(extract_version "SafeDI.podspec" "s.version" 0 "'")
echo "  SafeDI.podspec:       $PODSPEC_VERSION"

if [ "$TOOL_VERSION" != "$PLUGIN_VERSION" ] || [ "$TOOL_VERSION" != "$PODSPEC_VERSION" ]; then
    echo "ERROR: Version mismatch detected!"
    exit 1
fi

echo "All versions match: $TOOL_VERSION"
