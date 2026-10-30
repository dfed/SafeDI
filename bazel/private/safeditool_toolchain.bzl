"""The rules that declare and run a toolchain of `@safedi//bazel:safeditool_toolchain_type`."""

_SAFEDITOOL_TOOLCHAIN_TYPE = Label("//bazel:safeditool_toolchain_type")

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

def _resolved_safeditool_impl(ctx):
    safeditool = ctx.toolchains[_SAFEDITOOL_TOOLCHAIN_TYPE].safeditool.executable
    executable = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = executable,
        target_file = safeditool,
        is_executable = True,
    )
    return [DefaultInfo(
        executable = executable,
        runfiles = ctx.runfiles(files = [safeditool]),
    )]

resolved_safeditool = rule(
    implementation = _resolved_safeditool_impl,
    doc = """An executable that runs the SafeDITool the
`safeditool_toolchain_type` toolchain resolves to, which is the one
`safedi_compile` runs in the same build: `bazel run @safedi//bazel:safeditool
-- <arguments>`.""",
    executable = True,
    toolchains = [_SAFEDITOOL_TOOLCHAIN_TYPE],
)
