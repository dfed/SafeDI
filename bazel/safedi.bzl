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

This rule mirrors the Tuist plugin's `SafeDI.preCompileScript`
helper, which writes the same two artifacts in one invocation. Doing
both in one action is more efficient than splitting them across two
rules — every leaf-with-mocks or producer-with-mocks would otherwise
invoke SafeDITool twice on the same sources.

## Which SafeDITool the rule runs

The rule takes SafeDITool from the `@safedi//bazel:safeditool_toolchain_type`
toolchain. A SafeDI release from the Bazel Central Registry registers a
toolchain for each prebuilt SafeDITool binary the release uploads (macOS
arm64 and x86_64, Linux x86_64 and arm64), so a build runs the release's
binary for its execution platform: the binary the SwiftPM plugin and the
Tuist plugin run. Bazel downloads it from the release's GitHub assets the
first time a build needs it and checks it against the sha256 the
release's source archive records. The rule runs
`@safedi//Sources/SafeDITool:SafeDITool`, built from source, instead:

  - when `--@safedi//bazel:prefer_prebuilt_safeditool=false` is set, for
    example with `common --@safedi//bazel:prefer_prebuilt_safeditool=false`
    in `.bazelrc`;
  - on an execution platform no prebuilt binary runs on;
  - always, when SafeDI comes from a checkout of its repository rather
    than a release (`local_path_override`, `git_override`, or
    `archive_override` of a GitHub archive), so the rule never runs a
    binary older than itself. See `bazel/extensions.bzl`.

`bazel run @safedi//bazel:safeditool -- <arguments>` runs the same
SafeDITool, for `query needs` or `dump` over this rule's `.safedi` files.
Registering another toolchain of this type is not supported.

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

## Unsupported SafeDI features

- `#SafeDIConfiguration(additionalDirectoriesToInclude:)` is **not
  supported**. SafeDITool reads those paths at runtime to scan for
  additional source files, but Bazel's hermetic sandbox only exposes
  files declared as action inputs. List every Swift source you want
  SafeDITool to see directly in `srcs`.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# The toolchains that hand `safedi_compile` the SafeDITool it runs.
_SAFEDITOOL_TOOLCHAIN_TYPE = Label("//bazel:safeditool_toolchain_type")

SafeDIInfo = provider(
    doc = "Module info artifact (`.safedi`) emitted by `safedi_compile`.",
    fields = {
        "module_info": "The `.safedi` file describing this module's @Instantiable surface.",
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
        executable = ctx.toolchains[_SAFEDITOOL_TOOLCHAIN_TYPE].safeditool,
        toolchain = _SAFEDITOOL_TOOLCHAIN_TYPE,
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
        "_swift_copts": attr.label(
            default = Label("@build_bazel_rules_swift//swift:copt"),
            providers = [BuildSettingInfo],
        ),
        "_swift_exec_copts": attr.label(
            default = Label("@build_bazel_rules_swift//swift:exec_copt"),
            providers = [BuildSettingInfo],
        ),
    },
    toolchains = [_SAFEDITOOL_TOOLCHAIN_TYPE],
)

def safedi_swift_library(
        name,
        srcs,
        safedi_deps = [],
        defines = [],
        copts = [],
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
        tags: Passed to both targets.
        testonly: Passed to both targets.
        visibility: Passed to both targets, because a module that
            depends on this library also depends on `<name>_safedi`.
        target_compatible_with: Passed to both targets.
        **kwargs: Passed to the `swift_library`.
    """
    safedi_name = name + "_safedi"
    safedi_compile(
        name = safedi_name,
        srcs = srcs,
        deps = safedi_deps,
        defines = defines,
        copts = copts,
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
        tags = tags,
        testonly = testonly,
        visibility = visibility,
        target_compatible_with = target_compatible_with,
        **kwargs
    )
