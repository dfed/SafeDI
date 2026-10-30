"""The rule that declares a toolchain of `@safedi//bazel:safeditool_toolchain_type`."""

def _safeditool_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            safeditool = ctx.attr.safeditool[DefaultInfo].files_to_run,
        ),
    ]

safeditool_toolchain = rule(
    implementation = _safeditool_toolchain_impl,
    doc = """Declares the SafeDITool a `safeditool_toolchain_type` toolchain
hands `safedi_compile`. SafeDI declares every such toolchain itself:
`//bazel:safeditool_from_source` and, in a release's source archive, one
per prebuilt binary (`//bazel:extensions.bzl`).""",
    attrs = {
        "safeditool": attr.label(
            mandatory = True,
            executable = True,
            cfg = "exec",
            doc = "The SafeDITool executable.",
        ),
    },
    provides = [platform_common.ToolchainInfo],
)
