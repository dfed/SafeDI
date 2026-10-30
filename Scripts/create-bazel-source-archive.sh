#!/bin/bash

# Creates SafeDI-<version>.tar.gz, the source archive the Bazel Central
# Registry entry for <version> points at: `git archive` of <ref> with
# bazel/private/prebuilt_safeditool.bzl naming <version> and the sha256 of
# each SafeDITool binary in <binary directory>, which the release uploads
# beside the archive. The repository keeps that file empty, so only a build
# of the published archive runs the prebuilt binaries; a build of any
# checkout builds SafeDITool from source.
#
# The replacement file is staged in a temporary index rather than a working
# tree, and `git archive` writes the archive from the tree that index holds.
# Every other entry is exactly the entry `git archive <ref>` writes (path,
# mode, symbolic link, modification time), and no tar implementation's
# options are involved, so the script behaves the same on macOS and Linux.
# The publish workflow runs it, and the CI checks it on every change.
#
# Usage: ./Scripts/create-bazel-source-archive.sh <version> <binary directory> [<ref>]
# <binary directory> holds SafeDITool-macos-arm64, SafeDITool-macos-x86_64,
# SafeDITool-linux-x86_64, and SafeDITool-linux-arm64. <ref> defaults to the
# tag <version>. The archive is written to SafeDI-<version>.tar.gz in the
# working directory, rooted at SafeDI-<version>/ to match `strip_prefix` in
# .bcr/source.template.json.

set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    echo "Usage: $0 <version> <binary directory> [<ref>]" >&2
    exit 1
fi

# `git archive --mtime`, which stamps the archive below, arrived in git 2.40.
if [[ "$(git archive -h 2>&1 || true)" != *--mtime* ]]; then
    echo "error: $(git --version) is older than 2.40, so its git archive has no --mtime." >&2
    exit 1
fi

VERSION="$1"
BINARY_DIRECTORY="$2"
REF="${3:-$1}"

# Keep in step with the release assets publish.yml uploads and with
# _EXECUTION_PLATFORM_CONSTRAINTS in bazel/extensions.bzl.
PLATFORMS=(
    linux-arm64
    linux-x86_64
    macos-arm64
    macos-x86_64
)
PREBUILT_SAFEDITOOL_FILE=bazel/private/prebuilt_safeditool.bzl
ARCHIVE="SafeDI-${VERSION}.tar.gz"

# The file must exist at <ref>, so an archive of a ref that predates it, or a
# renamed file, fails here rather than adding a file nothing loads.
if ! git cat-file -e "${REF}:${PREBUILT_SAFEDITOOL_FILE}" 2>/dev/null; then
    echo "error: ${REF} has no ${PREBUILT_SAFEDITOOL_FILE}." >&2
    exit 1
fi

for platform in "${PLATFORMS[@]}"; do
    if [ ! -f "${BINARY_DIRECTORY}/SafeDITool-${platform}" ]; then
        echo "error: ${BINARY_DIRECTORY}/SafeDITool-${platform} does not exist." >&2
        exit 1
    fi
done

WORK_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$WORK_DIRECTORY"' EXIT

{
    echo '"""The prebuilt SafeDITool binaries of SafeDI '"${VERSION}"'.'
    echo
    echo 'Scripts/create-bazel-source-archive.sh wrote this file into the source archive'
    echo 'of the release. The repository keeps it empty.'
    echo '"""'
    echo
    echo "SAFEDITOOL_RELEASE = \"${VERSION}\""
    echo
    echo "SAFEDITOOL_SHA256 = {"
    for platform in "${PLATFORMS[@]}"; do
        sha256=$(shasum -a 256 "${BINARY_DIRECTORY}/SafeDITool-${platform}" | cut -d ' ' -f 1)
        echo "    \"${platform}\": \"${sha256}\","
    done
    echo "}"
} > "${WORK_DIRECTORY}/prebuilt_safeditool.bzl"

export GIT_INDEX_FILE="${WORK_DIRECTORY}/index"
git read-tree "$REF"
blob=$(git hash-object -w "${WORK_DIRECTORY}/prebuilt_safeditool.bzl")
git update-index --cacheinfo "100644,${blob},${PREBUILT_SAFEDITOOL_FILE}"
tree=$(git write-tree)
unset GIT_INDEX_FILE

# `git archive` of a tree, unlike one of a commit, stamps entries with the
# current time, so stamp them with <ref>'s commit time as an archive of the
# commit would be.
git archive \
    --format=tar.gz \
    --prefix="SafeDI-${VERSION}/" \
    --mtime="@$(git log -1 --format=%ct "$REF")" \
    -o "$ARCHIVE" \
    "$tree"

echo "Wrote ${ARCHIVE} from ${REF} with ${PREBUILT_SAFEDITOOL_FILE}:"
git cat-file blob "$blob"
