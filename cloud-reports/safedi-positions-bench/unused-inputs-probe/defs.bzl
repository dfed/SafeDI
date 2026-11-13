def _impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".out")
    unused = ctx.actions.declare_file(ctx.label.name + ".unused")
    ctx.actions.run(
        executable = ctx.executable._probe,
        inputs = [ctx.file.used, ctx.file.unused_input],
        outputs = [out, unused],
        arguments = [ctx.file.used.path, ctx.file.unused_input.path, out.path, unused.path],
        unused_inputs_list = unused,
        mnemonic = "Probe",
    )
    return [DefaultInfo(files = depset([out]))]

probe = rule(implementation = _impl, attrs = {
    "used": attr.label(allow_single_file = True),
    "unused_input": attr.label(allow_single_file = True),
    "_probe": attr.label(default = ":probe.sh", executable = True, cfg = "exec", allow_single_file = True),
})
