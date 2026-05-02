"""Custom Starlark rule for integrating SafeDI into a Bazel build.

`safedi_compile(srcs, deps)` runs `SafeDITool generate
--combined-output --module-info-output` once per module and produces
two artifacts:

  - `<rule>.swift` — every dependency-tree, mock, and mock
    configuration body SafeDITool would emit, concatenated into a
    single declared output. Bazel requires rule outputs to be known
    at analysis time, and the combined-output mode lets SafeDITool's
    output set (which depends on source contents) resolve to a
    single statically-known file. Add `[":<rule>"]` to a downstream
    `swift_library.srcs` to compile the generated code.

  - `<rule>.safedi` — the module-info artifact. Cross-module
    consumers list this rule's label in their own `safedi_compile`'s
    `deps` to reach `@Instantiable` types declared in this module
    without re-parsing the sources.

The rule shells out to `@safedi//Sources/SafeDITool:SafeDITool` (built
from source by Bazel, cached across runs).

This rule mirrors the Tuist plugin's `SafeDI.preCompileScript`
helper, which writes the same two artifacts in one invocation. Doing
both in one action is more efficient than splitting them across two
rules — every leaf-with-mocks or producer-with-mocks would otherwise
invoke SafeDITool twice on the same sources.

## Unsupported SafeDI features

- `#SafeDIConfiguration(additionalDirectoriesToInclude:)` is **not
  supported**. SafeDITool reads those paths at runtime to scan for
  additional source files, but Bazel's hermetic sandbox only exposes
  files declared as action inputs. List every Swift source you want
  SafeDITool to see directly in `srcs`.
"""

SafeDIInfo = provider(
    doc = "Module info artifact (`.safedi`) emitted by `safedi_compile`.",
    fields = {
        "module_info": "The `.safedi` file describing this module's @Instantiable surface.",
    },
)

def _write_csv(ctx, name, files):
    """Write a CSV of execution-root-relative paths the tool can consume."""
    csv = ctx.actions.declare_file(name)
    ctx.actions.write(
        output = csv,
        content = ",".join([f.path for f in files]),
    )
    return csv

def _safedi_compile_impl(ctx):
    module_info = ctx.actions.declare_file(ctx.label.name + ".safedi")
    combined = ctx.actions.declare_file(ctx.label.name + ".swift")
    input_csv = _write_csv(ctx, ctx.label.name + "_sources.csv", ctx.files.srcs)

    dep_module_info_files = [
        dep[SafeDIInfo].module_info
        for dep in ctx.attr.deps
    ]

    arguments = [
        input_csv.path,
        "--combined-output",
        combined.path,
        "--module-info-output",
        module_info.path,
    ]
    extra_inputs = []
    if dep_module_info_files:
        dep_csv = _write_csv(
            ctx,
            ctx.label.name + "_dep_module_infos.csv",
            dep_module_info_files,
        )
        arguments += ["--dependent-module-info-file-path", dep_csv.path]
        extra_inputs = [dep_csv] + dep_module_info_files

    ctx.actions.run(
        executable = ctx.executable._safeditool,
        inputs = ctx.files.srcs + [input_csv] + extra_inputs,
        outputs = [combined, module_info],
        arguments = arguments,
        mnemonic = "SafeDI",
        progress_message = "SafeDI compile for %{label}",
    )

    return [
        # `.swift` is the rule's default output — `[":<rule>"]` in a
        # downstream `swift_library.srcs` resolves to the generated
        # source. The `.safedi` rides through `SafeDIInfo` so other
        # `safedi_compile` rules can list this label in `deps`.
        DefaultInfo(files = depset([combined])),
        SafeDIInfo(module_info = module_info),
    ]

safedi_compile = rule(
    implementation = _safedi_compile_impl,
    doc = """Run SafeDITool against a module and emit both the
combined dependency-tree / mock Swift source and the `.safedi`
module-info artifact in a single action.""",
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".swift"],
            mandatory = True,
            doc = "Swift sources in this module.",
        ),
        "deps": attr.label_list(
            providers = [SafeDIInfo],
            default = [],
            doc = """Other `safedi_compile` labels whose `.safedi`
module-info artifacts this rule consumes for cross-module
`@Instantiable` type resolution.""",
        ),
        "_safeditool": attr.label(
            default = Label("//Sources/SafeDITool:SafeDITool"),
            executable = True,
            cfg = "exec",
        ),
    },
)
