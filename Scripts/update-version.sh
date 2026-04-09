#!/bin/bash

# Updates version strings, artifact bundle URL, and checksum across the repository.
# Used by the publish workflow and tested in CI.
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

echo "Updating to version $VERSION with checksum $CHECKSUM..."

# Update the binary target URL in Package.swift.
sed -i '' "s|https://github.com/dfed/SafeDI/releases/download/[^\"]*|https://github.com/dfed/SafeDI/releases/download/${VERSION}/SafeDITool.artifactbundle.zip|" Package.swift

# Update the checksum in Package.swift.
sed -i '' "s|checksum: \"[^\"]*\"|checksum: \"${CHECKSUM}\"|" Package.swift

# Update SafeDITool.currentVersion.
sed -i '' "s|\"[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*[^\"]*\"|\"${VERSION}\"|" Sources/SafeDITool/SafeDITool.swift

# Update Plugins/Shared.swift Xcode version.
sed -i '' "/var safeDIVersion: String/,/}/{s|\"[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*[^\"]*\"|\"${VERSION}\"|;}" Plugins/Shared.swift

echo "  Package.swift: URL and checksum updated"
echo "  SafeDITool.swift: version updated"
echo "  Plugins/Shared.swift: version updated"
echo "Done."
