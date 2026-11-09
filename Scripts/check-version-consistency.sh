#!/bin/bash

# Checks that the versions SafeDI states in more than one place agree:
#
# - Each package Package.resolved pins for SwiftPM is either the same
#   version of a module MODULE.bazel depends on for Bazel, or listed below
#   as needed by SwiftPM alone.
# - SafeDI's own version is the same in MODULE.bazel's `module(…)`, the
#   release URL of Package.swift's binary target, and Plugins/Shared.swift's
#   `safeDIVersion`: the three places Scripts/update-version.sh writes.
#
# CI runs it on every change, and after Scripts/update-version.sh.
# Works with both BSD (macOS) and GNU (Linux) tools.
#
# Usage: ./Scripts/check-version-consistency.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# The MODULE.bazel module that stands for each SwiftPM package, by the
# package's identity in Package.resolved. A package listed neither here
# nor in `swiftpm_only_package` fails the check, so each new SwiftPM
# dependency is given a Bazel counterpart, or not, deliberately.
MAPPED_PACKAGES=(swift-syntax swift-argument-parser)
bazel_module_for_package() {
    case "$1" in
        swift-syntax) echo "swift-syntax" ;;
        swift-argument-parser) echo "swift_argument_parser" ;;
        *) return 1 ;;
    esac
}

# Packages only SwiftPM needs.
swiftpm_only_package() {
    case "$1" in
        # The DocC plugin, and the symbol graph library it depends on,
        # build SafeDI's documentation. Bazel builds no documentation.
        swift-docc-plugin | swift-docc-symbolkit) return 0 ;;
        *) return 1 ;;
    esac
}

failures=0
fail() {
    echo "ERROR: $*" >&2
    failures=$((failures + 1))
}

# Prints `<identity> <version>` for each pin in Package.resolved. A pin
# without a version (a branch or revision pin) prints its identity alone.
resolved_pins() {
    awk '
        /"identity"[[:space:]]*:/ {
            if (identity != "") print identity
            line = $0
            sub(/.*"identity"[[:space:]]*:[[:space:]]*"/, "", line)
            sub(/".*/, "", line)
            identity = line
            next
        }
        /"version"[[:space:]]*:[[:space:]]*"/ && identity != "" {
            line = $0
            sub(/.*"version"[[:space:]]*:[[:space:]]*"/, "", line)
            sub(/".*/, "", line)
            print identity " " line
            identity = ""
        }
        END { if (identity != "") print identity }
    ' Package.resolved
}

# Prints the version of each MODULE.bazel `bazel_dep` on the named module
# that states its name and version on one line.
bazel_dep_versions() {
    sed -n -E "s/^[[:space:]]*bazel_dep\(name = \"$1\", version = \"([^\"]*)\".*/\1/p" MODULE.bazel
}

echo "Checking dependency versions..."

pins=$(resolved_pins)
if [ -z "$pins" ]; then
    fail "Found no pins in Package.resolved."
fi

while read -r identity version; do
    [ -n "$identity" ] || continue
    if module=$(bazel_module_for_package "$identity"); then
        bazel_version=$(bazel_dep_versions "$module")
        if [ -z "$version" ]; then
            fail "Package.resolved pins $identity to a branch or revision, not a version, so MODULE.bazel's bazel_dep on $module has no version to match. Pin $identity to a release."
        elif [ -z "$bazel_version" ]; then
            fail "MODULE.bazel has no bazel_dep(name = \"$module\", version = \"…\") on one line. It is the Bazel counterpart of $identity, which Package.resolved pins to $version. Add it, or change how Scripts/check-version-consistency.sh maps $identity."
        elif [ "$(echo "$bazel_version" | grep -c .)" -gt 1 ]; then
            fail "MODULE.bazel has more than one bazel_dep on $module: $(echo "$bazel_version" | tr '\n' ' ')"
        else
            # The Bazel Central Registry names a version it patched for
            # Bazel with a `.bcr.N` suffix on the upstream version.
            upstream_version=$(echo "$bazel_version" | sed -E 's/\.bcr\.[0-9]+$//')
            if [ "$upstream_version" != "$version" ]; then
                fail "MODULE.bazel depends on $module $bazel_version, but Package.resolved pins $identity to $version. Change MODULE.bazel's bazel_dep on $module to $version. The Bazel Central Registry must host that version, and its version may carry a .bcr.N suffix (such as $version.bcr.1). Until the registry hosts it, pin Package.resolved to $upstream_version instead."
            else
                printf '  %-24s Package.resolved %-12s MODULE.bazel %s %s\n' "$identity" "$version" "$module" "$bazel_version"
            fi
        fi
    elif swiftpm_only_package "$identity"; then
        printf '  %-24s Package.resolved %-12s SwiftPM only\n' "$identity" "${version:-(no version)}"
    else
        fail "Package.resolved pins $identity, which Scripts/check-version-consistency.sh neither maps to a MODULE.bazel module nor lists as SwiftPM only. Add a bazel_dep on its Bazel Central Registry module to MODULE.bazel and map it in MAPPED_PACKAGES and bazel_module_for_package, or list it in swiftpm_only_package with the reason Bazel does not need it."
    fi
done <<< "$pins"

for identity in "${MAPPED_PACKAGES[@]}"; do
    if ! echo "$pins" | grep -q -E "^$identity( |\$)"; then
        fail "Scripts/check-version-consistency.sh maps $identity to a MODULE.bazel module, but Package.resolved does not pin it. Remove it from MAPPED_PACKAGES and bazel_module_for_package, and remove its bazel_dep from MODULE.bazel if SafeDI no longer uses it."
    fi
done

echo "Checking SafeDI's version..."

# Prints the one version on standard input. Prints nothing, and names the
# file on standard error, when there is not exactly one.
single_version() {
    local file="$1"
    local versions
    versions=$(cat)
    local count
    count=$(echo "$versions" | grep -c . || true)
    if [ "$count" -eq 0 ]; then
        echo "ERROR: Could not find SafeDI's version in $file." >&2
    elif [ "$count" -gt 1 ]; then
        echo "ERROR: Found more than one SafeDI version in $file: $(echo "$versions" | tr '\n' ' ')" >&2
    else
        echo "$versions"
    fi
}

# A pipeline below that finds nothing fails under pipefail. Each carries
# on, since `single_version` has reported what it did not find.
#
# The `version` inside MODULE.bazel's `module(…)` block, not a bazel_dep's.
module_version=$(awk '/^module\(/,/^\)/' MODULE.bazel |
    sed -n -E 's/.*version = "([^"]*)".*/\1/p' |
    single_version MODULE.bazel) || true
# The release the binary target downloads SafeDITool from.
package_version=$(grep -o 'github\.com/dfed/SafeDI/releases/download/[^/"]*/' Package.swift |
    sed -E 's|.*/download/([^/]*)/|\1|' |
    single_version Package.swift) || true
# The quoted string in the body of the `safeDIVersion` getter.
plugin_version=$(awk '/var safeDIVersion: String \{/,/\}/' Plugins/Shared.swift |
    grep -o '"[^"]*"' | tr -d '"' |
    single_version Plugins/Shared.swift) || true

echo "  MODULE.bazel module version:   ${module_version:-(not found)}"
echo "  Package.swift release URL:     ${package_version:-(not found)}"
echo "  Plugins/Shared.swift version:  ${plugin_version:-(not found)}"

if [ -z "$module_version" ] || [ -z "$package_version" ] || [ -z "$plugin_version" ]; then
    # `single_version` reported which file.
    failures=$((failures + 1))
elif [ "$module_version" != "$package_version" ] || [ "$module_version" != "$plugin_version" ]; then
    fail "SafeDI's version differs among MODULE.bazel's module(version = …), the release URL in Package.swift's binary target, and Plugins/Shared.swift's safeDIVersion. Set all three to one version: Scripts/update-version.sh <version> <checksum> <macos-arm64-binary> <macos-x86_64-binary> writes them together."
fi

if [ "$failures" -gt 0 ]; then
    echo "Version consistency check failed with $failures error(s)." >&2
    exit 1
fi

echo "All versions are consistent."
