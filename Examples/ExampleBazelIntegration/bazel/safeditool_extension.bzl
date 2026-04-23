"""Module extension that downloads and unpacks the prebuilt
`SafeDITool.artifactbundle`. ARM-macOS only by design — a
cross-platform version would pick `os_arch` via `module_ctx` and
expose a platform-dispatching target.
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

_SAFEDI_VERSION = "2.0.0-beta-5"
_SAFEDI_CHECKSUM = "4e95a9bb1c9ac0643d41563dd8fe125cbd72f319a16ff57160d5b4f9f40605a7"

_BUILD_FILE = """
filegroup(
    name = "safeditool",
    srcs = ["SafeDITool.artifactbundle/SafeDITool-macos-arm64/bin/SafeDITool"],
    visibility = ["//visibility:public"],
)
"""

def _safeditool_impl(_ctx):
    http_archive(
        name = "safeditool_bundle",
        urls = [
            "https://github.com/dfed/SafeDI/releases/download/{v}/SafeDITool.artifactbundle.zip".format(v = _SAFEDI_VERSION),
        ],
        sha256 = _SAFEDI_CHECKSUM,
        build_file_content = _BUILD_FILE,
    )

safeditool = module_extension(
    implementation = _safeditool_impl,
    doc = "Fetches the prebuilt SafeDITool artifact bundle; exposes the arm64 binary as @safeditool_bundle//:safeditool.",
)
