---
paths:
  - ".github/scripts/compile-check-identity.sh"
  - ".github/workflows/share-compile-checks.yml"
  - ".github/workflows/ci.yml"
  - ".github/workflows/verify.yml"
  - ".github/actions/*compile-checks*/**"
  - "Tests/SafeDIToolTestSupport/PassedCompileCheckCache.swift"
  - "Tests/**/PassedCompileCheckCacheTests.swift"
---

# CI's cache of passed compile checks

"Build and Test on Xcode 26" and "Build and Test on Linux" skip each compile check that passed in an earlier run: `SAFEDI_COMPILE_CHECK_PASSED_CACHE` names a file of passed checks' keys (`PassedCompileCheckCache.swift`), cached under `.github/scripts/compile-check-identity.sh`'s hash of what compiles them, which covers SafeDICore only as the macro target compiles it (`Package.swift`'s `exclude`), so a generator change compiles again only the checks whose generated code it changes; a new input to whether a check compiles goes into that script or the key. Each key also carries what compiles the check, as the test process itself finds it (`CompileCheckBuild`): the compiler and SDK, the bytes of the SafeDI module it loads, and the dependency versions the build recorded (`workspace-state.json`, which a job that tests another job's build carries in its bundle). The macro plugin's bytes are not hashed, since two builds of the same sources differ; its sources are in the script's hash. So no workflow file is hashed: a workflow edit keeps every passed check unless it changes one of those, and nobody has to know which workflow lines matter. `share-compile-checks.yml` adds each finished CI or Verify run's passed checks to a per-identity list saved as main's cache, which every run on every branch also restores; a run uploads only the checks its own test processes passed (`passed-in-run-<run>.txt`), never what its job restored; as a `workflow_run` workflow it runs from main's copy only. The list trusts every branch of this repository, so the identity also hashes the two actions that restore and upload the checks, and the script. A cache restores only where the compression matches, so the Linux list is saved from the test jobs' container (gzip) and the macOS list from a Linux runner without one (zstd, as the macOS job): change a test job's container or runner and that workflow together.
