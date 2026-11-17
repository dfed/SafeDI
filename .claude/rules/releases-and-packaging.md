---
paths:
  - ".github/workflows/publish.yml"
  - "Scripts/create-bazel-source-archive.sh"
  - "Scripts/update-version.sh"
  - ".bcr/**/*"
  - "MODULE.bazel"
  - "Package.swift"
  - "Plugins/**/*"
  - "bazel/**/*"
  - "TuistPlugins/**/*"
  - "Examples/**/*"
---

<!-- Keep this file under 32,000 characters (Scripts/check-claude-instruction-files.sh): Claude truncates an on-demand file at 40,000. -->

# Breaking changes, releases and packaging

## What breaks

- **Measured from the last stable release.** A change breaks only if it breaks something the last stable release shipped, or, once the next stable ships, something that one shipped. A change to what exists only in an alpha, beta or release candidate is never breaking and needs no upgrade step, and what a prerelease adopter would have to edit is no argument either way. "New" and "old" are also judged against the last stable release.
- **Breaking means a user must edit something they wrote.** That is Swift source, macro arguments, arguments typed into `Package.swift`, `Project.swift` or `BUILD` files, flags of a hand-written invocation, and generated declarations users call: a seam's readable initializer, `mock()`, and the generated initializers of `SafeDIOverrides` and `SafeDIMockConfiguration`.
- **Never breaking:** a new warning (a project's warnings-as-errors policy is its own; release notes list it under Diagnostics); a `.safedi` file, scan cache or any other file SafeDI writes during a build, which every build regenerates, so its name, format and location never need an upgrade step such as cleaning the build folder; a declaration whose name starts with `__safeDI_`, which only generated code calls and which may change in any release; how a configuration stores its fields behind the computed properties that read them (making those fields computed was itself breaking from 2.2.0, whose fields were stored `let`s an extension initializer could assign).
- **Check a "must land before the tag" claim against the last stable release by running it**, not against the current prerelease or the design: a change that matches what the last stable already does is not a break later either.
- **Prefer one rule a user can predict** over flexible or reserved shapes. Never reserve a shape for a future with no concrete plan, never write that something "may change in a minor release" (the beta `query needs` is the exception), and never promise in documentation, diagnostics or pull requests that a shape becomes an error in a later release unless a deprecation already schedules it.
- **A fix that needs a source break waits for a major release.** Record it for that release; do not ship it in 2.x. A major release breaks only where the benefit is clear and no existing feature loses capability, and it raises the minimum Swift version to the latest release at the time; 2.x stays on Swift 6.2.
- **Retiring a released capability** first states what it lets an adopter do that nothing else does, and what it costs to carry. Propose removal only for something a better path duplicates, or a shape that adds complexity for no value; never because no project in view uses it, and never for a one-time tool such as a migration plugin. A capability only a prerelease had is not released, and may be dropped.

## Release notes

- A stable release's notes are written against the last stable tag only (`git log <last-stable>..<tag>`): no "since beta-N" sections or clauses. A prerelease's body is GitHub's generated list.
- Notes describe what shipped. No known-issue, "not yet" or regression-cost lines: a known defect is tracked as a GitHub issue with a verified minimal reproduction, and fixed. The breaking section lists only rejections of what compiled and changed output.
- No word counts, cut sizes or other editing statistics in notes or in pull requests meant for users.
- Public text (release notes, pull requests, commit messages, the Manual) never names the private apps SafeDI is measured on, nor gives their counts: say "a large production app".
- Apostrophes are ’ (U+2019), as in the Manual and diagnostics.

## Publishing

- Every real dispatch of `publish.yml` (alpha, beta, release candidate, stable) needs the maintainer's explicit go for that version. A dry run creates nothing a user can see and needs no go: run one before each real publish and after any change to the workflow.
- A stable release follows a release candidate: publish the candidate, then a pull request pinning the example projects to it (the Tuist example runs the published prebuilt binary, so its CI is the real check of it), then, after a release that changes `bazel/`, check the Bazel Central Registry presubmit; then the stable, on its own go, then a pull request moving the example pins to the stable.
- The stable GitHub release carries the hand-written notes above GitHub's generated list.
- The Tuist plugin and the package example run a released `SafeDITool`, so they exercise a new tool option only after a tag (`conditional-compilation.md`: an option the plugin passes ships in a release first).
- The registry holds a version whose `presubmit.yml` differs from the previous registered version until a registry maintainer unblocks it, so a prerelease's registry pull request should merge before the stable's. Commenting on or closing a registry pull request is a public post: the maintainer's word first.

## Packaging and integrations

- **Do what comparable projects do.** Before choosing how SafeDI integrates with a build system or registry (fetching dependencies, toolchains, release layout, presubmit, plugin shape), find two or three projects in that ecosystem that share the need behind the choice, and do what they do. Diverge only for a requirement you would defend to that ecosystem's maintainers, and write the reason where the divergence lives (as the planning-time scan does: pre-build commands run every build, which defeats per-root output files). A project without SafeDI's need that differs from SafeDI is no evidence.
