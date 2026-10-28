#!/bin/bash

# Updates the artifact bundle URL and checksum in Package.swift, the
# InstallSafeDITool plugin's hardcoded SafeDI version in
# Plugins/Shared.swift, the Bazel module version in MODULE.bazel, and,
# for a stable release, the install snippets in the documentation that
# state a SafeDI version.
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

# The documentation files whose install snippets state a SafeDI version.
# The publish workflow commits each of them, and the CI check fails when
# a Markdown file outside this list states one. The examples' own
# dependency pins (Examples/ExampleTuistIntegration/Tuist/Package.swift
# and Examples/ExampleBazelIntegration/MODULE.bazel) are not snippets:
# they move in the example-pin pull request after a release.
DOCUMENTATION_FILES=(
    README.md
    Documentation/Manual.md
    Sources/SafeDI/SafeDI.docc/SafeDI.md
    Examples/ExampleTuistIntegration/README.md
)

# In-place sed that works with both BSD sed (macOS) and GNU sed (Linux):
# BSD requires an argument to -i and GNU treats a separate argument as
# the script, but both accept an attached suffix. The last argument is
# the file being edited.
sed_in_place() {
    sed -i.bak "$@" && rm -f "${@: -1}.bak"
}

echo "Updating Package.swift for version $VERSION with checksum $CHECKSUM..."

# Update the binary target URL.
sed_in_place "s|https://github.com/dfed/SafeDI/releases/download/[^\"]*|https://github.com/dfed/SafeDI/releases/download/${VERSION}/SafeDITool.artifactbundle.zip|" Package.swift

# Update the checksum.
sed_in_place "s|checksum: \"[^\"]*\"|checksum: \"${CHECKSUM}\"|" Package.swift

echo "  Package.swift: URL and checksum updated"

# Update the InstallSafeDITool XcodeCommandPlugin's hardcoded SafeDI
# version (Xcode plugins can't read the package manifest at runtime, so
# the version has to live in source). The declaration spans multiple
# lines, so scope the replacement to the `safeDIVersion` getter body
# via an address range — the only quoted string inside that range is
# the version literal.
sed_in_place -E "/var safeDIVersion: String \{/,/\}/ s|\"[^\"]+\"|\"${VERSION}\"|" Plugins/Shared.swift

echo "  Plugins/Shared.swift: safeDIVersion updated"

# Update the Bazel module version. Scope the replacement to the
# `module(…)` block so the top-level version line is the only match
# (bazel_dep's `version = "X"` lines elsewhere in the file stay put).
sed_in_place -E "/^module\(/,/^\)/ s|version = \"[^\"]*\"|version = \"${VERSION}\"|" MODULE.bazel

echo "  MODULE.bazel: module version updated"

# Update the install snippets. A prerelease (a version with a hyphen,
# such as 2.2.0-rc-1) leaves them on the last stable release: the
# publish commit lands on main, and readers copying a snippet should not
# pick up a release candidate. Each pattern requires the version to
# start with a digit, so a placeholder such as `version = "…"` stays put.
case "$VERSION" in
    *-*)
        echo "  Documentation install snippets: left unchanged for prerelease $VERSION"
        ;;
    *)
        for file in "${DOCUMENTATION_FILES[@]}"; do
            # `.package(url: "https://github.com/dfed/SafeDI.git", from: "X")`
            sed_in_place -E "s|(github\.com/dfed/SafeDI\.git\", from: \")[0-9][^\"]*\"|\1${VERSION}\"|g" "$file"
            # `bazel_dep(name = "safedi", version = "X")`
            sed_in_place -E "s|(bazel_dep\(name = \"safedi\", version = \")[0-9][^\"]*\"|\1${VERSION}\"|g" "$file"
            # The migration guide's "Update your SafeDI dependency to `from: "X"`".
            sed_in_place -E "s|(SafeDI dependency to .from: \")[0-9][^\"]*\"|\1${VERSION}\"|g" "$file"
            echo "  $file: install snippets updated"
        done
        ;;
esac

echo "Done."
