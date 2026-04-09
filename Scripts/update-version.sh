#!/bin/bash

# Updates the artifact bundle URL and checksum in Package.swift.
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
echo "Done."
