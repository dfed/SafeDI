# Bazel

**`bazel/private/prebuilt_safeditool.bzl` stays empty in the repository.** `safedi_compile` takes SafeDITool from a toolchain. An empty file makes the `safeditool` module extension (`bazel/extensions.bzl`) declare no prebuilt toolchain, so a Bazel build of any checkout (the example's `local_path_override`, a consumer's `git_override`) runs SafeDITool built from that checkout, and a rule change that passes `generate` a new option never meets an older release's binary. Only `Scripts/create-bazel-source-archive.sh`, which `publish.yml` runs, fills the file in, inside the source archive the BCR entry points at, where the rule and the binaries are the same release. The Bazel job fails when the example's generate step runs anything but `//Sources/SafeDITool:SafeDITool`, which a filled-in file would cause, and the `Bazel Source Archive Check` job checks the file directly.

`SafeDIInfo.transitive_module_infos` is a depset never flattened at analysis (the CSV is written from an `Args` object); only a module with a root or seam reads it, and only for what its dependency trees need (`ModulesBeneathSelection`).

Every build of the tool names its modules `SafeDIToolLibrary` and `SafeDICore` (`module_name` on their `swift_library` rules); `.claude/rules/serialization.md` says why. Rules: `.claude/rules/serialization.md` and `.claude/rules/file-paths.md`.
