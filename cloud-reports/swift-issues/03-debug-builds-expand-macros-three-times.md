# Debug builds expand each attached macro about three times; the third expansion comes from each file that constructs the type

## Description

In a Debug build, each attached macro use is sent to the plugin by three frontend jobs:

1. The emit-module job.
2. The job compiling the file that declares the type.
3. Each job compiling a file that constructs the type (or otherwise needs its stored properties, see the table below).

A whole-module Release build expands each macro use once. In an incremental Debug build after touching any one file, the emit-module job expands every macro use in the module again. Expansion results don't carry over from one job to another, so the plugin runs once per job, and a codebase where most types carry attached macros (dependency injection, observation, codable helpers) pays for the macros about three times per Debug build. The count is the same on 6.2.4, 6.3.3 and 6.4.2.

## Environment

- Swift 6.4.2 (swift-6.4.2-RELEASE), 6.3.3 and 6.2.4, release toolchains from swift.org.
- Ubuntu 24.04.5 LTS, x86_64, 4 cores, 16 GB.
- swift-syntax 604.0.0.
- SwiftPM's default build system on each: Swift Build on 6.4.2, native on 6.3.3 and 6.2.4. 6.4.2 was also run with `--build-system native`, with the same counts.
- Not tested: macOS or Xcode.

## Steps to reproduce

Use the package from the related report about peer macros on stored properties. It has the macros `@NoopPeer` (`@attached(peer)`) and `@NoopMember` (`@attached(member)`), both expanding to nothing. Its plugin logs each expansion with the frontend job that requested it. The package has a `final class Service` in `Types.swift` with `@NoopMember` and four `@NoopPeer` members, and `Use.swift`:

```swift
public func use() {
	_ = Service()
}
```

1. Clean Debug build:

   ```bash
   rm -rf .build /tmp/expansions.log && swift build && awk '{print $NF}' /tmp/expansions.log | sort | uniq -c
   ```

2. Release build:

   ```bash
   rm -f /tmp/expansions.log && swift build -c release && awk '{print $NF}' /tmp/expansions.log | sort | uniq -c
   ```

3. To scale it, `generate.sh N` writes N copies of `Service` (`Service0`…) to `Types.swift` and constructs each in `Use.swift`:

   ```bash
   #!/bin/bash
   # generate.sh N: writes N copies of Service (Service0…) to Types.swift and constructs each in Use.swift.
   N=$1; cd "$(dirname "$0")/Sources/Client"
   { echo "import NoopMacros"; for i in $(seq 0 $((N-1))); do cat <<SWIFT

   @NoopMember
   public final class Service$i {
       @NoopPeer var a: Int = 0
       @NoopPeer var b: String = ""
       @NoopPeer var c: Int { a }
       @NoopPeer func d() {}
       public init() {}
       public var description: String { "" }
   }
   SWIFT
   done; } > Types.swift
   { echo "public func use() {"; for i in $(seq 0 $((N-1))); do echo "    _ = Service$i()"; done; echo "}"; } > Use.swift
   ```

## Expected result

Each macro use is expanded once per build, or at least in no more jobs than need its expansion. The job compiling `Use.swift` calls `Service.init` and needs `Service`'s stored properties. None of these macros can add a stored property, because none declares `names:` (the related report shows the compiler rejects one that tries), so that job doesn't need to expand them.

## Actual result

Clean Debug build, one type with five macro uses (6.4.2, the same on 6.3.3 and 6.2.4):

```
      5 compile[Types.swift]
      5 compile[Use.swift]
      5 emit-module
```

With `generate.sh 100`: 500 in each of the three jobs, 1,500 in all. Release build of the same 100 types: 500, all in the one whole-module compile job.

The `Use.swift` job doesn't expand the macros when `Use.swift` only calls a computed property on a `Service` it's given (10 expansions instead of 15). It does when `Use.swift` reads a stored property, references `Service.self`, or (for a struct) takes the type as a parameter. The related report has that table.

**Scaling.** One type per file (`T0.swift` … `T{N-1}.swift`), each a `final class` with `@NoopMember` and `@NoopPeer` on two stored properties, so three macro uses per type. A `Use.swift` constructs every type. Swift 6.4.2 with SwiftPM's default build system (Swift Build), 4 cores; plugin CPU is summed over its processes:

| Types | Build | Expansions | in the emit-module job | in compile jobs | Plugin CPU | Wall-clock |
|---|---|---|---|---|---|---|
| 10 | clean Debug | 87 | 30 | 57 | 0.2 s | 4.5 s |
| 10 | Debug after touching `T0.swift` | 33 | 30 | 3 | 0.08 s | 2.1 s |
| 10 | Debug after touching `Use.swift` | 60 | 30 | 30 | 0.1 s | 2.0 s |
| 10 | clean Release | 30 | — | 30 | 0.02 s | 2.5 s |
| 100 | clean Debug | 843 | 300 | 543 | 1.5 s | 3.0 s |
| 100 | Debug after touching `T0.swift` | 303 | 300 | 3 | 0.5 s | 3.1 s |
| 100 | Debug after touching `Use.swift` | 600 | 300 | 300 | 1.0 s | 3.0 s |
| 100 | clean Release | 300 | — | 300 | 0.06 s | 3.2 s |
| 1,000 | clean Debug | 8,931 | 3,000 | 5,931 | 15.6 s | 14.9 s |
| 1,000 | Debug after touching `T0.swift` | 3,003 | 3,000 | 3 | 5.3 s | 13.9 s |
| 1,000 | Debug after touching `Use.swift` | 6,000 | 3,000 | 3,000 | 10.1 s | 13.4 s |
| 1,000 | clean Release | 3,000 | — | 3,000 | 0.8 s | 25.3 s |

Release wall-clock includes optimization, and these Release builds ran with `-j 2`. How the 8,931 break down: 3,000 in the emit-module job, 3,000 in the jobs whose primary files declare the types, and 2,931 in the one batch job containing `Use.swift`. That job re-expanded the macros of the 977 types that aren't among its own primary files. The expansion counts were identical, row for row, with 6.4.2 using `--build-system native`, 6.3.3 and 6.2.4. Plugin CPU differs by version (8.6 s for the clean Debug build on 6.2.4) because of the build configuration each request carries since 6.3, which the related report covers.

## Why it matters

- **Clean Debug builds** expand each macro use about three times, against once in a whole-module build. At 1,000 types with no-op macros, the clean Debug build took 16.7 s against 9.3 s for the same code without the macro attributes (mean of three runs each, 6.4.2, 4 cores).
- **Incremental Debug builds** re-expand every macro use in the module in the emit-module job, whichever file changed. Touching one of 1,000 files cost 3,003 expansions and 5.3 s of plugin CPU, nearly all in that one job's plugin process. The incremental build took 13.4 s, against 6.6 s for the same incremental build of the same code without the macro attributes (mean of three runs each, 6.4.2). It's close to the 14.9 s of a clean build.
- **Each file that constructs a type** adds a full expansion of that type's macros in its batch job. Composition roots and factories construct many types, so they re-expand the macros of everything they build.

What I could not confirm: why the emit-module job of an incremental build expands every macro (I measured only that it does), and how Xcode's build system distributes these jobs.
