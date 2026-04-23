"""Custom Starlark rules for integrating SafeDI into a Bazel build.

  - `safedi_module_info(srcs)` publishes a module's `.safedi`
    module-info artifact for downstream consumers.

  - `safedi_generate(srcs, module_infos)` runs SafeDITool and emits a
    single combined `<rule_name>.swift` that Bazel can compile without
    knowing how many roots / mocks the source code declares.

Both rules shell out to `@safedi//Sources/SafeDITool:SafeDITool` (built
from source by Bazel, cached across runs). `safedi_generate` uses
SafeDITool's `--combined-output` mode to concatenate per-root and
per-mock output into one file — Bazel requires rule outputs to be
known at analysis time, and the combined mode lets SafeDITool's
output set (which depends on source contents) resolve to a single
statically-known file.

## Unsupported SafeDI features

- `#SafeDIConfiguration(additionalDirectoriesToInclude:)` is **not
  supported** under these rules. SafeDITool reads those paths at
  runtime to scan for additional source files, but Bazel's hermetic
  sandbox only exposes files declared as action inputs. List every
  Swift source you want SafeDITool to see directly in `srcs`.
"""

def _write_csv(ctx, name, files):
    """Write a CSV of execution-root-relative paths the tool can consume."""
    csv = ctx.actions.declare_file(name)
    ctx.actions.write(
        output = csv,
        content = ",".join([f.path for f in files]),
    )
    return csv

def _safedi_module_info_impl(ctx):
    module_info = ctx.actions.declare_file(ctx.label.name + ".safedi")
    input_csv = _write_csv(ctx, ctx.label.name + "_sources.csv", ctx.files.srcs)

    ctx.actions.run(
        executable = ctx.executable._safeditool,
        inputs = ctx.files.srcs + [input_csv],
        outputs = [module_info],
        arguments = [
            input_csv.path,
            "--module-info-output",
            module_info.path,
        ],
        mnemonic = "SafeDIModuleInfo",
        progress_message = "SafeDI module info for %{label}",
    )
    return [DefaultInfo(files = depset([module_info]))]

safedi_module_info = rule(
    implementation = _safedi_module_info_impl,
    doc = """Emit a module's `.safedi` artifact for downstream
consumers. Use on leaf modules that don't themselves need generated
Swift — the artifact is consumed by `safedi_generate.module_infos`.""",
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".swift"],
            mandatory = True,
            doc = "Swift sources in this module.",
        ),
        "_safeditool": attr.label(
            default = Label("//Sources/SafeDITool:SafeDITool"),
            executable = True,
            cfg = "exec",
        ),
    },
)

def _safedi_generate_impl(ctx):
    combined = ctx.actions.declare_file(ctx.label.name + ".swift")
    input_csv = _write_csv(ctx, ctx.label.name + "_sources.csv", ctx.files.srcs)

    module_info_files = []
    for dep in ctx.attr.module_infos:
        module_info_files += dep[DefaultInfo].files.to_list()

    arguments = [
        input_csv.path,
        "--combined-output",
        combined.path,
    ]
    extra_inputs = []
    if module_info_files:
        dep_csv = _write_csv(
            ctx,
            ctx.label.name + "_dependent_module_infos.csv",
            module_info_files,
        )
        arguments += ["--dependent-module-info-file-path", dep_csv.path]
        extra_inputs = [dep_csv] + module_info_files

    ctx.actions.run(
        executable = ctx.executable._safeditool,
        inputs = ctx.files.srcs + [input_csv] + extra_inputs,
        outputs = [combined],
        arguments = arguments,
        mnemonic = "SafeDIGenerate",
        progress_message = "SafeDI generate for %{label}",
    )
    return [DefaultInfo(files = depset([combined]))]

safedi_generate = rule(
    implementation = _safedi_generate_impl,
    doc = """Run SafeDITool against a module and produce a single
combined `.swift` output (named after the rule's label). The
single-output shape is what makes this Bazel-friendly — SafeDI's
per-root / per-mock file splits happen inside the tool's combined-
output mode and get stitched together for consumers, sidestepping
Bazel's requirement that rule outputs be known statically.""",
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".swift"],
            mandatory = True,
        ),
        "module_infos": attr.label_list(
            allow_files = [".safedi"],
            default = [],
            doc = "Dependent-module `.safedi` artifacts (produced by `safedi_module_info`).",
        ),
        "_safeditool": attr.label(
            default = Label("//Sources/SafeDITool:SafeDITool"),
            executable = True,
            cfg = "exec",
        ),
    },
)
