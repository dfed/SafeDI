"""Custom Starlark rules for integrating SafeDI into a Bazel build.

  - `safedi_module_info(srcs)` publishes a module's `.safedi`
    module-info artifact for downstream consumers.

  - `safedi_generate(srcs, module_infos)` runs SafeDITool, reads any
    dependent `.safedi` files for cross-module types, and emits a
    single `<rule_name>.swift` that Bazel can compile without knowing
    how many roots / mocks the source code declares.

SafeDITool emits one `.swift` per `@Instantiable(isRoot: true)`, one
per `@Instantiable(generateMock: true)`, and a shared
`SafeDIMockConfiguration.swift`. Each file is a pile of top-level
extension / struct declarations, so concatenating them produces a
valid Swift source. The rule writes them into a scratch directory,
then stitches them into a single declared output. That sidesteps
Bazel's requirement that rule outputs be known statically without
reintroducing a hand-maintained filename list in `BUILD.bazel`.
"""

def _write_csv(ctx, name, files):
    """Write a CSV of execution-root-relative paths the tool can consume."""
    csv = ctx.actions.declare_file(name)
    ctx.actions.write(
        output = csv,
        content = ",".join([f.path for f in files]),
    )
    return csv

def _run_scan_and_generate(
        ctx,
        tool,
        srcs,
        combined_swift_output = None,
        module_info_output = None,
        dependent_module_infos = []):
    """Invoke `SafeDITool scan` + `SafeDITool generate` in one shell
    action, then (if `combined_swift_output` is set) concatenate every
    `.swift` SafeDITool wrote into that single output.

    Scan and generate share one action for two reasons: (1) the scan-
    produced manifest encodes sandbox-absolute output paths that only
    make sense inside this action's sandbox, so splitting across
    actions breaks them; (2) doing the concat here means we don't have
    to know SafeDITool's per-root / per-mock filenames at analysis
    time.
    """

    input_csv = _write_csv(ctx, ctx.label.name + "_sources.csv", srcs)
    manifest = ctx.actions.declare_file(ctx.label.name + "_manifest.json")
    scan_cache = ctx.actions.declare_file(
        ctx.label.name + "_manifest.safediScannedModuleInfo.json",
    )

    scratch_name = ctx.label.name + "_scratch"

    # Generate args mirror what SafeDI's SPM plugin passes at
    # plugin-setup time.
    generate_arguments = [input_csv.path, "--swift-manifest", manifest.path]
    extra_inputs = []
    if module_info_output != None:
        generate_arguments += ["--module-info-output", module_info_output.path]
    if dependent_module_infos:
        dep_csv = _write_csv(
            ctx,
            ctx.label.name + "_dependent_module_infos.csv",
            dependent_module_infos,
        )
        generate_arguments += [
            "--dependent-module-info-file-path",
            dep_csv.path,
        ]
        extra_inputs += [dep_csv] + list(dependent_module_infos)

    combine_block = ""
    if combined_swift_output != None:
        combine_block = """
# Concatenate everything SafeDITool wrote into a single known
# output. The individual .swift files from SafeDITool are all top-
# level declarations (extensions, structs) that compose cleanly.
: > "{combined}"
shopt -s nullglob
for f in "{scratch}"/*.swift; do
    cat "$f" >> "{combined}"
    printf '\\n' >> "{combined}"
done
""".format(
            combined = combined_swift_output.path,
            scratch = scratch_name,
        )

    shell_cmd = """
set -euo pipefail
mkdir -p "{scratch}"
"$1" scan \\
    --input-sources-file "{input_csv}" \\
    --project-root . \\
    --output-directory "{scratch}" \\
    --manifest-file "{manifest}"
shift
"$1" generate {generate_args}
{combine_block}
""".format(
        scratch = scratch_name,
        input_csv = input_csv.path,
        manifest = manifest.path,
        generate_args = " ".join(['"%s"' % arg for arg in generate_arguments]),
        combine_block = combine_block,
    )

    outputs = [manifest, scan_cache]
    if combined_swift_output != None:
        outputs.append(combined_swift_output)
    if module_info_output != None:
        outputs.append(module_info_output)

    ctx.actions.run_shell(
        tools = [tool],
        inputs = list(srcs) + [input_csv] + extra_inputs,
        outputs = outputs,
        command = shell_cmd,
        arguments = [tool.path, tool.path],
        mnemonic = "SafeDI",
        progress_message = "SafeDI scan+generate for %s" % ctx.label,
    )

def _safedi_module_info_impl(ctx):
    module_info = ctx.actions.declare_file(ctx.label.name + ".safedi")
    _run_scan_and_generate(
        ctx,
        tool = ctx.executable._safeditool,
        srcs = ctx.files.srcs,
        module_info_output = module_info,
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
            default = "@safeditool_bundle//:safeditool",
            executable = True,
            cfg = "exec",
        ),
    },
)

def _safedi_generate_impl(ctx):
    combined = ctx.actions.declare_file(ctx.label.name + ".swift")
    module_infos = []
    for dep in ctx.attr.module_infos:
        module_infos += dep[DefaultInfo].files.to_list()
    _run_scan_and_generate(
        ctx,
        tool = ctx.executable._safeditool,
        srcs = ctx.files.srcs,
        combined_swift_output = combined,
        dependent_module_infos = module_infos,
    )
    return [DefaultInfo(files = depset([combined]))]

safedi_generate = rule(
    implementation = _safedi_generate_impl,
    doc = """Run SafeDITool against a module and produce a single
combined `.swift` output (named after the rule's label). The
single-output shape is what makes this Bazel-friendly — SafeDI's
per-root / per-mock file splits happen in the action's scratch
directory and get stitched together for consumers, sidestepping
Bazel's requirement that rule outputs be known statically.""",
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".swift"],
            mandatory = True,
        ),
        "module_infos": attr.label_list(
            allow_files = [".safedi"],
            default = [],
            doc = "Dependent-module .safedi artifacts.",
        ),
        "_safeditool": attr.label(
            default = "@safeditool_bundle//:safeditool",
            executable = True,
            cfg = "exec",
        ),
    },
)
