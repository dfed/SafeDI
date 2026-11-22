---
paths:
  - "Documentation/**/*"
  - "README.md"
  - "Contributing.md"
---

# Documentation

The Manual is how people learn what SafeDI can do and how to design with it. Each topic has one home section (`CLAUDE.md`, "Documentation"); these rules keep it readable.

- **Only what users need.** Document a capability a user would otherwise not find, with the design rule behind it and one example. Do not document the absence of a former limitation, the cases an error message already explains, a known defect or edge case (make the diagnostic say it, or put it in the pull request), or a prompt a tool explains itself, such as Xcode's trust dialogs.
- **The reader's path.** Before adding text, ask what question brings a reader to this spot, what they must learn there (the capability and its rule, not only the mechanism), and where they will look for it. Prefer a short rule and one example to an exhaustive paragraph; put edge cases last or in the section that owns them; never send a reader forward to an unrelated section for a basic step. Review documentation as a new adopter reading the integration sections and as an experienced user looking up a rule, besides checking accuracy.
- **No SafeDI version numbers** outside install pins (`from:`, `version =`) and upgrade or migration sections: write "SafeDI needs Swift 6.2", never "SafeDI 2 needs", and no "new in", "since" or "now does".
- **Steps are instructions.** Say which types to declare, what to add, and that the macro checks it, with its fix-it, in the active voice. When a step relies on a SafeDI concept (built in the tree or passed at runtime, instantiated or received), say why in a sentence.
- **An edit is a diff.** In the QuickStart, how-to, migration and release-note upgrade steps, a change to an existing file is a `diff` block with `+` and `-` lines and some context; a new file is a plain block, labeled new. Reference sections keep full listings, and tests read some of the Manual's code blocks by position, so do not convert those.
- **Commands use the reader's integration**: `bazel run` of the `@safedi//:SafeDITool` target for Bazel, the artifact bundle's binary for Tuist, and for SwiftPM and the Xcode plugin a command that works without the `sourceBuild` trait. Never `swift run SafeDITool` for a Bazel or Tuist user. Run each one before documenting it.
- **What one integration cannot do** is said once, in its limits section (as "Limits of the Xcode project plugin"), and the error leads with the remedy that works there.
- **Apostrophes are ’** (U+2019) in the Manual, the README and release notes; code, Swift syntax and quoted code keep `'`.
- **A new call form gets a written call.** When the Manual documents a new way to call a generated declaration (a parameter, a label, a builder or scope shape), add that call to `Scripts/release-checks/written-calls/` in the same change, citing the section; never change a call there that the last stable release's Manual documents (`.claude/rules/releases-and-packaging.md`, "Written calls keep compiling").

## Tests that read the Manual by position

Two tests take the Swift code blocks of "Generating a dependency tree per module" up to the section's first line that begins with `#`, its first subheading: one expects exactly seven, takes the first as its fixture, and compares the second with the code generated for that fixture and the third with the call a root in another module generates for it; the other compares the fifth and sixth with the code its own builder fixture generates. A third takes the two Swift code blocks of "Adopting SafeDI in a large codebase" and the first of "Calling a public mock from another module", each section up to its next heading, as the files of modules `Feed`, `App` and a module of another package, and compiles them.
