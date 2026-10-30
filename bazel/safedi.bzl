"""Starlark rule and macro for integrating SafeDI into a Bazel build.

Most modules declare a `safedi_swift_library`, which takes the
attributes of a `swift_library` and declares two targets from them:

  - `<name>_safedi`, a `safedi_compile` target that runs SafeDITool.
  - `<name>`, a `swift_library` that compiles `srcs` together with the
    code SafeDITool generated.

Both targets receive the same `srcs`, `defines`, and `copts`, so the
compilation conditions SafeDITool scans with always match the ones
the compiler uses. Modules that need something the macro does not
offer can declare `safedi_compile` and `swift_library` by hand.

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
    `deps` (or `safedi_swift_library`'s `safedi_deps`) to reach
    `@Instantiable` types declared in this module without re-parsing
    the sources.

The rule shells out to `@safedi//Sources/SafeDITool:SafeDITool` (built
from source by Bazel, cached across runs).

This rule mirrors the Tuist plugin's `SafeDI.preCompileScript`
helper, which writes the same two artifacts in one invocation. Doing
both in one action is more efficient than splitting them across two
rules — every leaf-with-mocks or producer-with-mocks would otherwise
invoke SafeDITool twice on the same sources.

## Conditional compilation

SafeDITool scans only the `#if` clauses that are active for the
build. `safedi_compile` reports these conditions:

  - `DEBUG`, whenever Bazel's compilation mode is `dbg` or
    `fastbuild`, matching the `-DDEBUG` rules_swift passes to swiftc
    in those modes.
  - `NDEBUG`, whenever Bazel's compilation mode is `opt`, matching
    the `-DNDEBUG` rules_swift passes to swiftc in that mode.
  - `defines`, and every `-D` flag in `copts`, which must match the
    wrapped `swift_library`'s attributes of the same names.
    `safedi_swift_library` passes both targets the same values. The
    library cannot be read here (its `srcs` include this rule's
    output, so depending on it would be a cycle), so a hand-wired
    `safedi_compile` has to repeat them.
  - Every `-D` flag passed to rules_swift's
    `--@rules_swift//swift:copt` command-line flag, which rules_swift
    passes to every Swift compilation in the target configuration
    (`--@rules_swift//swift:exec_copt` in the exec configuration).

A bare condition none of these sources reports is inactive. That
includes `defines` propagated from a dependency, rules_swift's
`--@rules_swift//swift:per_module_swiftcopt`, and copts set on a
custom Swift toolchain. The generated code asserts every decision a
condition made, so a condition the build defines but the rule does not
report fails the build with a message naming it.

## Modules and packages

`safedi_compile` tells SafeDITool the name of the Swift module that
compiles its output (`module_name`), that module's package
(`package_name`, which the compiler receives as `-package-name`), and
the modules of its `deps`, and records them in the `.safedi`
artifact, so a consumer knows which module and package declare each
`@Instantiable` type. `safedi_swift_library` passes the module name
its `swift_library` compiles: the `module_name` attribute, or the name
rules_swift derives from the library's label. Give
`safedi_swift_library` a `package_name` to compile the library with
`-package-name`, which `package` declarations need.

## Unsupported SafeDI features

- `#SafeDIConfiguration(additionalDirectoriesToInclude:)` is **not
  supported**. SafeDITool reads those paths at runtime to scan for
  additional source files, but Bazel's hermetic sandbox only exposes
  files declared as action inputs. List every Swift source you want
  SafeDITool to see directly in `srcs`.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@build_bazel_rules_swift//swift:module_name.bzl", "derive_swift_module_name")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

SafeDIInfo = provider(
    doc = "Module info artifact (`.safedi`) emitted by `safedi_compile`.",
    fields = {
        "module_info": "The `.safedi` file describing this module's @Instantiable surface.",
        "module_name": "The name of the Swift module that compiles the rule's output, or `None` when the rule was not told it.",
    },
)

# Flags whose next argument belongs to another tool, so a `-D` there is
# not a Swift compilation condition.
_FLAGS_FORWARDING_NEXT_ARGUMENT = [
    "-Xcc",
    "-Xclang-linker",
    "-Xlinker",
    "-Xllvm",
]

def _write_csv(ctx, name, files):
    """Write a CSV of execution-root-relative paths the tool can consume."""
    csv = ctx.actions.declare_file(name)
    ctx.actions.write(
        output = csv,
        content = ",".join([f.path for f in files]),
    )
    return csv

def _compilation_conditions_from_copts(copts):
    """Returns the conditions that `-D` flags in `copts` define for swiftc."""
    conditions = []
    flag_expecting_condition = None
    for copt in copts:
        if flag_expecting_condition == "-D":
            conditions.append(copt)
            flag_expecting_condition = None
        elif flag_expecting_condition != None:
            flag_expecting_condition = None
        elif copt == "-D" or copt in _FLAGS_FORWARDING_NEXT_ARGUMENT:
            flag_expecting_condition = copt
        elif copt.startswith("-D"):
            conditions.append(copt[len("-D"):])
    return conditions

def _safedi_compile_impl(ctx):
    module_info = ctx.actions.declare_file(ctx.label.name + ".safedi")
    combined = ctx.actions.declare_file(ctx.label.name + ".swift")
    input_csv = _write_csv(ctx, ctx.label.name + "_sources.csv", ctx.files.srcs)

    dependency_module_info_files = [
        dependency[SafeDIInfo].module_info
        for dependency in ctx.attr.deps
    ]

    arguments = [
        input_csv.path,
        "--combined-output",
        combined.path,
        "--module-info-output",
        module_info.path,
        # rules_swift hands swiftc the same execution-root-relative paths
        # this rule writes to the CSV, so the generated `#sourceLocation`
        # directives can name them and stay free of machine-specific paths.
        "--compiler-receives-input-paths-unchanged",
    ]

    # rules_swift applies `copt` in the target configuration and
    # `exec_copt` in the exec configuration, telling them apart by the
    # output directory in the same way.
    if "-exec-" in ctx.bin_dir.path:
        command_line_copts = ctx.attr._swift_exec_copts[BuildSettingInfo].value
    else:
        command_line_copts = ctx.attr._swift_copts[BuildSettingInfo].value

    # `swift_library` expands Make variables in `copts`, so a `-D` flag
    # can name a value set with `--define`. Only the conditions are
    # expanded: other copts may use `$(location …)`, which needs the
    # library's `swiftc_inputs`.
    target_copt_conditions = [
        ctx.expand_make_variables("copts", condition, {})
        for condition in _compilation_conditions_from_copts(ctx.attr.copts)
    ]

    active_compilation_conditions = list(ctx.attr.defines)
    active_compilation_conditions += target_copt_conditions
    active_compilation_conditions += _compilation_conditions_from_copts(command_line_copts)
    compilation_mode = ctx.var.get("COMPILATION_MODE")
    if compilation_mode in ("dbg", "fastbuild"):
        active_compilation_conditions.append("DEBUG")
    elif compilation_mode == "opt":
        active_compilation_conditions.append("NDEBUG")
    if active_compilation_conditions:
        arguments += ["--active-compilation-conditions"] + active_compilation_conditions

    # The module and package that declare this module's `@Instantiable`
    # types, which SafeDITool records in the `.safedi` artifact.
    if ctx.attr.module_name:
        arguments += ["--module-name", ctx.attr.module_name]
    if ctx.attr.package_name:
        arguments += ["--package-name", ctx.attr.package_name]
    dependency_module_names = [
        dependency[SafeDIInfo].module_name
        for dependency in ctx.attr.deps
        if dependency[SafeDIInfo].module_name
    ]
    if dependency_module_names:
        arguments += ["--dependency-module-names"] + dependency_module_names
    extra_inputs = []
    if dependency_module_info_files:
        dependency_csv = _write_csv(
            ctx,
            ctx.label.name + "_dep_module_infos.csv",
            dependency_module_info_files,
        )
        arguments += ["--dependent-module-info-file-path", dependency_csv.path]
        extra_inputs = [dependency_csv] + dependency_module_info_files

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
        SafeDIInfo(
            module_info = module_info,
            module_name = ctx.attr.module_name or None,
        ),
    ]

safedi_compile = rule(
    implementation = _safedi_compile_impl,
    doc = """Run SafeDITool against a module and emit both the
combined dependency-tree / mock Swift source and the `.safedi`
module-info artifact in a single action.

Prefer `safedi_swift_library`, which declares this target and the
`swift_library` that compiles its output from one set of attributes.""",
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
        "defines": attr.string_list(
            default = [],
            doc = """Compilation conditions active for this module,
matching the wrapped `swift_library.defines`. `DEBUG` is added
automatically in the `dbg` and `fastbuild` compilation modes, and
`NDEBUG` in the `opt` compilation mode.""",
        ),
        "copts": attr.string_list(
            default = [],
            doc = """Swift compiler options matching the wrapped
`swift_library.copts`. Each `-D` flag among them reports a compilation
condition; other options are ignored.""",
        ),
        "module_name": attr.string(
            default = "",
            doc = """The name of the Swift module that compiles this
rule's output: the wrapped `swift_library`'s `module_name`, or the
name rules_swift derives from that library's label.
`safedi_swift_library` passes it. SafeDITool records it as the module
that declares this module's `@Instantiable` types, and consumers of
this rule as one of their dependencies.""",
        ),
        "package_name": attr.string(
            default = "",
            doc = """The `package_name` of the wrapped `swift_library`,
which the compiler receives as `-package-name`. Leave it empty when
the library has none.""",
        ),
        "_safeditool": attr.label(
            default = Label("//Sources/SafeDITool:SafeDITool"),
            executable = True,
            cfg = "exec",
        ),
        "_swift_copts": attr.label(
            default = Label("@build_bazel_rules_swift//swift:copt"),
            providers = [BuildSettingInfo],
        ),
        "_swift_exec_copts": attr.label(
            default = Label("@build_bazel_rules_swift//swift:exec_copt"),
            providers = [BuildSettingInfo],
        ),
    },
)

def safedi_swift_library(
        name,
        srcs,
        safedi_deps = [],
        defines = [],
        copts = [],
        package_name = None,
        tags = None,
        testonly = None,
        visibility = None,
        target_compatible_with = None,
        **kwargs):
    """Declares a `swift_library` that compiles the code SafeDI generates for it.

    Declares two targets:

      - `<name>_safedi`, a `safedi_compile` target that runs SafeDITool
        over `srcs`. Other modules list it in their `safedi_deps`.
      - `<name>`, a `swift_library` that compiles `srcs` together with
        `<name>_safedi`'s generated source.

    Both targets receive the same `srcs`, `defines`, and `copts`, so
    SafeDITool scans the `#if` clauses the compiler compiles.

    Args:
        name: The name of the `swift_library`.
        srcs: Swift sources in this module.
        safedi_deps: The `<name>_safedi` (or `safedi_compile`) labels of
            other modules whose `@Instantiable` types this module uses.
            List the libraries themselves in `deps`.
        defines: Passed to both targets.
        copts: Passed to both targets. `safedi_compile` reads only the
            `-D` flags.
        package_name: The package the `swift_library` belongs to, which
            the compiler receives as `-package-name` and which
            `package` declarations need. Passed to both targets.
        tags: Passed to both targets.
        testonly: Passed to both targets.
        visibility: Passed to both targets, because a module that
            depends on this library also depends on `<name>_safedi`.
        target_compatible_with: Passed to both targets.
        **kwargs: Passed to the `swift_library`. `safedi_compile` also
            reads its `module_name`.
    """
    safedi_name = name + "_safedi"
    safedi_compile(
        name = safedi_name,
        srcs = srcs,
        deps = safedi_deps,
        defines = defines,
        copts = copts,
        # The module the `swift_library` below compiles, named as
        # rules_swift names it.
        module_name = kwargs.get("module_name") or derive_swift_module_name(native.package_name(), name),
        package_name = package_name,
        tags = tags,
        testonly = testonly,
        visibility = visibility,
        target_compatible_with = target_compatible_with,
    )
    swift_library(
        name = name,
        srcs = srcs + [":" + safedi_name],
        defines = defines,
        copts = copts,
        package_name = package_name,
        tags = tags,
        testonly = testonly,
        visibility = visibility,
        target_compatible_with = target_compatible_with,
        **kwargs
    )
