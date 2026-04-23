#!/bin/bash

# Updates the artifact bundle URL and checksum in Package.swift, the
# InstallSafeDITool plugin's hardcoded SafeDI version in
# Plugins/Shared.swift, and the Bazel module version in MODULE.bazel.
# Used by the publish workflow after building the artifact bundle.
#
# Usage: ./Scripts/update-version.sh <version> <checksum>
# Example: ./Scripts/update-version.sh 2.0.0 abc123def456

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: $0 <version> <checksum>" >&2
    exit 1
fi

VERSION="$1"
CHECKSUM="$2"

echo "Updating Package.swift for version $VERSION with checksum $CHECKSUM..."

# Update the binary target URL.
sed -i '' "s|https://github.com/dfed/SafeDI/releases/download/[^\"]*|https://github.com/dfed/SafeDI/releases/download/${VERSION}/SafeDITool.artifactbundle.zip|" Package.swift

# Update the checksum.
sed -i '' "s|checksum: \"[^\"]*\"|checksum: \"${CHECKSUM}\"|" Package.swift

echo "  Package.swift: URL and checksum updated"

# Update the InstallSafeDITool XcodeCommandPlugin's hardcoded SafeDI
# version (Xcode plugins can't read the package manifest at runtime, so
# the version has to live in source). The declaration spans multiple
# lines, so scope the replacement to the `safeDIVersion` getter body
# via an address range — the only quoted string inside that range is
# the version literal.
sed -i '' -E "/var safeDIVersion: String \{/,/\}/ s|\"[^\"]+\"|\"${VERSION}\"|" Plugins/Shared.swift

echo "  Plugins/Shared.swift: safeDIVersion updated"

# Update the Bazel module version. Scope the replacement to the
# `module(…)` block so the top-level version line is the only match
# (bazel_dep's `version = "X"` lines elsewhere in the file stay put).
sed -i '' -E "/^module\(/,/^\)/ s|version = \"[^\"]*\"|version = \"${VERSION}\"|" MODULE.bazel

echo "  MODULE.bazel: module version updated"
echo "Done."
