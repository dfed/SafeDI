---
paths:
  - "Tests/**/*"
---

<!-- Keep this file under 32,000 characters (Scripts/check-claude-instruction-files.sh): Claude truncates an on-demand file at 40,000. -->

# Designing a change's tests

Review findings cluster in the neighbors of a fix, not in the shape it was written for, so a change's tests are designed before its code.

- **Write the shape matrix first.** For each rule a change adds or fixes, list its neighbor shapes as failing tests before writing code: declaration order (before, after, inside its own tree); a type reached under two parents, only one of which provides the label; required, optional and `onlyIfAvailable` on the receive and on the owner; wrapper kind and what the caller holds (the instance, the wrapper, the other wrapper); its own property versus the tree's; each position across a module boundary (the boundary type itself, beneath it, inside a fill) under both kinds of integration (the SwiftPM plugin's scan, and `generate` per module as Bazel and Tuist run it); and how each property's type is spelled (plain, closure, `@Sendable` closure, optional closure, tuple, `any P`, nested, generic, typealias, another module's). Argue an impossible cell in a line.
- **Handwritten tests cover each rule's primary shape:** diagnostic text, location and fix-it; one full generated-output pin per rule; a failing-first regression test for every bug a review or the fuzzer finds; and configurations the fuzzer does not draw.
- **Siblings along an axis go to the fuzzer** when a draw reaches the axis with a pinned count and an oracle would fail on the defect the cell guards; a draw alone is not enough. When no draw reaches it yet, extend the fuzzer (`fuzzer-corpora.md`) rather than writing sibling unit tests, and say in the pull request why any sibling stays handwritten.
- **A new feature gets a differential oracle** that compares its output with a path whose output is known right: a seam against its inline build, a public mock against the internal mock, builder parameters against the same type built inline. A seam or public mock feature also gets a retention check against the inline build (`seam-and-mock-contract.md`, rule 3).
- **Expected output draws no warning SafeDI could foresee**, such as an unused binding: adopters build with warnings as errors and cannot edit generated code. When reviewing an expected string by hand, look for warnings as well as errors.
