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

# The script `resolved_safeditool` writes, which runs SafeDITool from the
# script's runfiles: the tree beside the script, the one `RUNFILES_DIR` names,
# or, when the script is itself a runfile of another executable that runs it,
# the tree that holds it, which `bazel run` names in no variable. `bazel run`
# starts an executable in its runfiles tree, so a relative path among the
# arguments would resolve there, and names the directory it was run from in
# `BUILD_WORKING_DIRECTORY`; the script changes to that directory, so that a
# path resolves as it was typed. Only `bazel run` sets the variable, and a
# program it starts passes it on, so the script also changes directory when
# such a program runs it; anywhere else the script runs SafeDITool in the
# directory it was started in. `%SAFEDITOOL_RUNFILES_PATH%` is replaced by the
# path of SafeDITool in the runfiles tree.
_RUN_SAFEDITOOL_SCRIPT = """#!/bin/sh
set -eu
case "$0" in
    /*) executable="$0" ;;
    *) executable="$PWD/$0" ;;
esac
if [ -d "$executable.runfiles" ]; then
    runfiles_directory="$executable.runfiles"
elif [ -n "${RUNFILES_DIR:-}" ]; then
    runfiles_directory="$RUNFILES_DIR"
else
    case "$executable" in
        *.runfiles/*) runfiles_directory="${executable%%.runfiles/*}.runfiles" ;;
        *)
            echo "error: found no runfiles beside $executable to run SafeDITool from." >&2
            exit 1
            ;;
    esac
fi
case "$runfiles_directory" in
    /*) ;;
    *) runfiles_directory="$PWD/$runfiles_directory" ;;
esac
safeditool="$runfiles_directory"/'%SAFEDITOOL_RUNFILES_PATH%'
if [ -n "${BUILD_WORKING_DIRECTORY:-}" ]; then
    cd "$BUILD_WORKING_DIRECTORY"
fi
exec "$safeditool" "$@"
"""

def _runfiles_path(ctx, file):
    """The path of `file` in a runfiles tree."""

    # A file of another repository has a short path that starts with
    # `../<repository>/`, and a file of the main repository one that does not.
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]
    return ctx.workspace_name + "/" + file.short_path

def _resolved_safeditool_impl(ctx):
    safeditool = ctx.toolchains[_SAFEDITOOL_TOOLCHAIN_TYPE].safeditool.executable
    executable = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(
        output = executable,
        content = _RUN_SAFEDITOOL_SCRIPT.replace("%SAFEDITOOL_RUNFILES_PATH%", _runfiles_path(ctx, safeditool)),
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
`safedi_compile` runs in the same build: `bazel run @safedi//:SafeDITool --
<arguments>`, through the alias at the repository root. Under `bazel run`,
SafeDITool runs in the directory `bazel run` was run from, so relative paths
among the arguments resolve from there.""",
    executable = True,
    toolchains = [_SAFEDITOOL_TOOLCHAIN_TYPE],
)
