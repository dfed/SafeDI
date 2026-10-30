"""The prebuilt SafeDITool binaries of the release this source tree is.

The repository keeps this file empty, and it must stay empty: an empty
file registers no prebuilt toolchain, so a build of any checkout (a
`local_path_override`, a `git_override`, or an `archive_override` of a
GitHub archive) runs SafeDITool built from that same checkout.

The publish workflow writes the release's values into the copy of this
file in `SafeDI-<version>.tar.gz`, the source archive the Bazel Central
Registry entry points at (`Scripts/create-bazel-source-archive.sh`), so
only a build of a published release runs that release's binaries.
"""

# The release whose binaries `SAFEDITOOL_SHA256` names, or `None`.
SAFEDITOOL_RELEASE = None

# The sha256 of each `SafeDITool-<platform>` binary the release uploads,
# keyed by `<platform>`. Empty: no prebuilt toolchain is registered.
SAFEDITOOL_SHA256 = {}
