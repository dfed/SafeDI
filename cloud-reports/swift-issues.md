# Swift compiler macro-expansion costs: reproductions and issue drafts

Nothing has been filed upstream. The three drafts below are for the maintainer to file on swiftlang/swift. Each also exists as its own file under [`swift-issues/`](swift-issues/), next to the reproduction projects ([`swift-issues/repros`](swift-issues/repros)) and the measurements ([`swift-issues/results`](swift-issues/results/README.md)). None of the reproductions use SafeDI.

## Summary

| # | Behavior | Reproduced? | Since |
|---|---|---|---|
| 1 | Peer macros on a type's members, including ones that declare no `names:` and so can't add a stored property, are expanded again in each file's job that needs the type's stored properties | Yes | ≤ 6.2.4 (same on 6.2.4, 6.3.3, 6.4.2) |
| 2 | Each expansion request carries a ~4–4.5 KB static build configuration, which swift-syntax decodes per request | Yes | 6.3 (absent on 6.2.4) |
| 3 | Debug builds expand each attached macro about three times: emit-module, the declaring file, each file that constructs the type | Yes, with a fourth finding: incremental Debug builds re-expand every macro in the module | ≤ 6.2.4 |

Headline numbers, from a clean Debug build of 1,000 types, one per file, each with one member macro and two peer macros, all constructed in one file. Swift 6.4.2 with SwiftPM, Ubuntu, 4 cores:

- 8,931 expansions, against 3,000 for the Release build.
- The build took 16.7 s with the no-op macros and 9.3 s without them.
- A one-file incremental build took 13.4 s with the macros and 6.6 s without.
- The plugin used 15.6 s of CPU on 6.4.2, against 8.6 s on 6.2.4 for the same expansions.

## Setup

- **Toolchains.** Swift 6.4.2, 6.3.3 and 6.2.4 release toolchains for Ubuntu 24.04, recorded with `swift --version`. swiftly 1.x was installed, but `swiftly install` failed every time while importing swift.org's signing keys: `www.swift.org/keys/all-keys.asc` is served with `Content-Encoding: gzip`, and swiftly passes the compressed bytes to `gpg --import`. So I downloaded the official tarballs and their `.sig` files, verified each with `gpg --verify` against swift.org's keys ("Good signature from Swift 6.x Release Signing Key"), and unpacked them to `~/swift-toolchains/<version>`. I didn't install with verification turned off.
- **swift-syntax** 604.0.0 for every package.
- **SwiftPM's default build system** is Swift Build on 6.4.2 and native on 6.3.3 and 6.2.4. 6.4.2 was also measured with `--build-system native`.
- **Machine.** Ubuntu 24.04.5 LTS, x86_64, 4 cores, 16 GB. Nothing was run on macOS or with Xcode.

## How strong the evidence is

1. **Peer macros expanded for stored properties: strong for what was measured, and it reproduces on all three versions.**
   - Every expansion was counted from inside the plugin and attributed to the frontend job that asked for it, using the job's command line.
   - The job compiling a constructing file expands every peer macro of the type, including peers on a method and a computed property. A file that only calls a computed property expands none.
   - The rule that a peer or member macro without `names:` cannot add a stored property was confirmed against the compiler (`RuleCheck`).
   - Not confirmed: which compiler request triggers the expansion. The draft says only that the triggering uses are those that need the type's stored properties or layout, and gives the table of uses.
   - The draft assumes the fix direction (skip macros that declare no names) is sound. A compiler engineer may know other reasons that job needs the expansion.
2. **Build configuration in every request: strong.** Four independent measurements agree:
   - request sizes captured from the pipe on three compilers with one plugin binary;
   - a microbenchmark of swift-syntax's own decoder on captured requests, built for Release and for Debug;
   - an A/B in one plugin binary, with the field kept or removed before swift-syntax sees it, three runs each on 6.3.3 and 6.4.2;
   - cross-version plugin CPU, whose gap (~7 s at 9,000 expansions) matches the microbenchmark (~0.76 ms per request with Debug swift-syntax).

   Not measured: the compiler side of building and serializing the configuration. Also, the large per-request costs depend on the plugin being built in Debug, as SwiftPM does for a Debug build here; how Xcode builds plugins wasn't checked. Part of the fix may belong in swift-syntax, which decodes eagerly.
3. **Three expansions per Debug build: strong.**
   - Deterministic counts, identical across 6.2.4, 6.3.3 and 6.4.2 and both of SwiftPM's build systems.
   - Scaled over 10, 100 and 1,000 types, for clean Debug, two kinds of incremental Debug build, and Release.
   - Wall-clock baselines without macros for the clean build and the one-file incremental build.

   Wall-clock numbers come from a shared 4-core VM and vary by roughly ±10% between runs. Not confirmed: why the emit-module job of an incremental build re-expands everything, and how Xcode partitions jobs.

Mistakes made and fixed during the work, so the numbers can be trusted:
- The minimal package's first log writer lost lines to concurrent writes; it now uses `O_APPEND`.
- The harness first treated the host's zero-length termination message as a decode error; that is fixed.
- Under Swift Build some batch jobs pass their primary files through `-primary-filelist`, and the `/proc` command line of large jobs is not fully readable. The per-job attribution in the drafts therefore uses a two-file layout, where it's unambiguous; the one-file-per-type matrix uses totals only.

## Where things are

- **This branch:** `cloud-reports/swift-issues.md` (this report), and under `cloud-reports/swift-issues/`:
  - the three drafts: `01-peer-macros-expanded-for-stored-properties.md`, `02-build-configuration-in-every-request.md`, `03-debug-builds-expand-macros-three-times.md`;
  - the reproduction projects and scripts, in `repros/`;
  - the measurements, with captured requests, in `results/`.
- **Session machine** (ephemeral cloud container; reclaimed after inactivity), under `/tmp/claude-0/-home-user-SafeDI/27c66093-4718-5b32-9d58-8979c63c8846/scratchpad/repros`:
  - the working copies with their build directories (`Harness`, `MacroRepro`, `RuleCheck`, `verify/`);
  - all raw logs (`logs/`);
  - the toolchains, in `~/swift-toolchains`.

## Related reading

None of these is an existing report of these specific behaviors. Search the tracker for duplicates before filing.

- [RFC: Static build configuration in SwiftIfConfig and build configurations for macro expansion contexts](https://forums.swift.org/t/rfc-static-build-configuration-in-swiftifconfig-and-build-configurations-for-macro-expansion-contexts/82393), the design behind `staticBuildConfiguration`.
- [Swift Macros: Build Time Overhead Concerns](https://forums.swift.org/t/swift-macros-build-time-overhead-concerns/70443) and [Analysis of Macro expansion overhead in the Swift Compiler](https://forums.swift.org/t/analysis-of-macro-expansion-overhead-in-the-swift-compiler/80813).

## Draft 1: Peer macros that declare no `names:` are expanded again in every file that needs the type's stored properties

### Description

When a file constructs a type, reads one of its stored properties, or references a class's metatype, the frontend job compiling that file expands every peer macro attached to any member of that type, even though the type is declared in another file. That includes peer macros on methods and computed properties, and peer macros whose declaration lists no `names:`. A peer macro without `names:` cannot introduce a stored property: the compiler rejects such an expansion with "declaration name … is not covered by macro". So these expansions can't change the type's stored properties, yet they run again in each job that needs them. A file that only calls a computed property on the same type expands none of them. `@attached(member)` macros without `names:` behave the same way in the same measurements. Peer macros that do nothing (`@Instantiated`, `@Received` and similar markers in dependency-injection libraries) are common on stored properties, so this repeats plugin round trips across many files.

### Environment

- Swift 6.4.2 (swift-6.4.2-RELEASE), 6.3.3 and 6.2.4, release toolchains from swift.org.
- Ubuntu 24.04.5 LTS, x86_64, 4 cores, 16 GB.
- swift-syntax 604.0.0.
- SwiftPM's default build system on each: Swift Build on 6.4.2, native on 6.3.3 and 6.2.4. 6.4.2 was also run with `--build-system native`.
- Not tested: macOS or Xcode.

### Steps to reproduce

The package below has a macro target with two macros that expand to nothing, a client with one class, and a file that constructs it. The plugin appends one line per expansion to `/tmp/expansions.log`, naming the frontend job that asked for it. On Linux it reads the job from `/proc/<parent>/cmdline`. On macOS it logs only the frontend's process ID, and SwiftPM's macro sandbox will probably block the write unless you pass `--disable-sandbox`; I did not try macOS.

`Package.swift`:

```swift
// swift-tools-version: 6.0
import CompilerPluginSupport
import PackageDescription

let package = Package(
	name: "MacroRepro",
	platforms: [.macOS(.v13)],
	dependencies: [.package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0")],
	targets: [
		.macro(name: "NoopMacrosPlugin", dependencies: [
			.product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
			.product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
		]),
		.target(name: "NoopMacros", dependencies: ["NoopMacrosPlugin"]),
		.target(name: "Client", dependencies: ["NoopMacros"]),
	],
)
```

`Sources/NoopMacros/NoopMacros.swift`:

```swift
/// Expands to nothing. Declares no `names:`, so it cannot add a stored property.
@attached(peer)
public macro NoopPeer() = #externalMacro(module: "NoopMacrosPlugin", type: "NoopPeerMacro")

/// Expands to nothing. Declares no `names:`, so it cannot add a stored property.
@attached(member)
public macro NoopMember() = #externalMacro(module: "NoopMacrosPlugin", type: "NoopMemberMacro")
```

`Sources/NoopMacrosPlugin/Plugin.swift`:

```swift
import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

/// Appends one line per expansion to /tmp/expansions.log: role, declaration, and the
/// frontend job that asked (its mode and primary files, read from /proc on Linux).
func log(_ role: String, _ declaration: some SyntaxProtocol, _ context: some MacroExpansionContext) {
	let type = context.lexicalContext.lazy.compactMap { $0.asProtocol(NamedDeclSyntax.self)?.name.text }.first
	let name = declaration.as(VariableDeclSyntax.self)?.bindings.first?.pattern.trimmedDescription
		?? declaration.as(FunctionDeclSyntax.self)?.name.text
		?? declaration.asProtocol(NamedDeclSyntax.self)?.name.text ?? "?"
	let line = Array("\(role) \([type, name].compactMap(\.self).joined(separator: ".")) \(job)\n".utf8)
	// O_APPEND, so lines from the compiler's concurrent jobs don't overwrite each other.
	let file = open("/tmp/expansions.log", O_WRONLY | O_APPEND | O_CREAT, 0o644)
	_ = line.withUnsafeBytes { write(file, $0.baseAddress, $0.count) }
	close(file)
}

let job: String = {
	let parent = getppid()
	guard let data = FileManager.default.contents(atPath: "/proc/\(parent)/cmdline") else { return "frontend-pid=\(parent)" }
	let arguments = data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
	let mode = arguments.contains("-c") ? "compile" : arguments.contains("-emit-module") ? "emit-module" : "other"
	let primaries = arguments.indices.dropLast().filter { arguments[$0] == "-primary-file" }
		.map { URL(fileURLWithPath: arguments[$0 + 1]).lastPathComponent }
	return primaries.isEmpty ? mode : "\(mode)[\(primaries.joined(separator: ","))]"
}()

public struct NoopPeerMacro: PeerMacro {
	public static func expansion(of _: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
		log("peer", declaration, context)
		return []
	}
}

public struct NoopMemberMacro: MemberMacro {
	public static func expansion(of _: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, conformingTo _: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] {
		log("member", declaration, context)
		return []
	}
}

@main
struct Plugin: CompilerPlugin {
	let providingMacros: [Macro.Type] = [NoopPeerMacro.self, NoopMemberMacro.self]
}
```

`Sources/Client/Types.swift`:

```swift
import NoopMacros

@NoopMember
public final class Service {
	@NoopPeer var a: Int = 0
	@NoopPeer var b: String = ""
	@NoopPeer var c: Int {
		a
	}

	@NoopPeer
	func d() {}
	public init() {}
	public var description: String {
		""
	}
}
```

`Sources/Client/Use.swift`:

```swift
public func use() {
	_ = Service()
}
```

Build it and count expansions per job:

```bash
rm -f /tmp/expansions.log && swift build && sort /tmp/expansions.log | uniq -c
```

Then replace `Use.swift` with a file that calls only a computed property, do a clean build of `Client`, and count again:

```swift
public func use(_ service: Service) -> String {
	service.description
}
```

### Expected result

Peer macros are expanded in the jobs that type-check the declarations they're attached to: the emit-module job and the job whose primary file is `Types.swift`. The job compiling `Use.swift` needs `Service`'s stored properties to construct it. None of the four `@NoopPeer` macros can add a stored property, since `@NoopPeer` declares no `names:`, so that job doesn't need to expand them.

### Actual result

With `Use.swift` constructing `Service`, every peer macro, and the member macro, is expanded in all three jobs. That includes the peers on the computed property `c` and the method `d`. Output on 6.4.2 (identical on 6.3.3 and 6.2.4):

```
      1 member Service compile[Types.swift]
      1 member Service compile[Use.swift]
      1 member Service emit-module
      1 peer Service.a compile[Types.swift]
      1 peer Service.a compile[Use.swift]
      1 peer Service.a emit-module
      1 peer Service.b compile[Types.swift]
      1 peer Service.b compile[Use.swift]
      1 peer Service.b emit-module
      1 peer Service.c compile[Types.swift]
      1 peer Service.c compile[Use.swift]
      1 peer Service.c emit-module
      1 peer Service.d compile[Types.swift]
      1 peer Service.d compile[Use.swift]
      1 peer Service.d emit-module
```

With `Use.swift` only calling `service.description`, the `compile[Use.swift]` lines disappear: 10 expansions instead of 15.

What `Use.swift` does to a type decides whether its job expands that type's macros. I measured 100 types in `Types.swift`, each with one member macro and peer macros on two stored properties, so each job that expands a type's macros adds 300 expansions. These are Debug builds with 6.4.2:

| `Use.swift` does this with each type `T` | `final class` | `struct` |
|---|---|---|
| nothing | not expanded | not expanded |
| `_ = T()` | expanded | expanded |
| `[T.self]` as `[Any.Type]` | expanded | expanded |
| `func f(_ value: T) {}` | not expanded | expanded |
| `func f(_ value: T) -> String { value.description }` (computed property) | not expanded | not measured |
| `func f(_ value: T) -> Int { value.a }` (stored property) | expanded | not measured |

These cases match uses that need the type's stored properties or layout. I did not confirm which compiler request triggers the expansion. Moving the peer macros from the stored properties to a computed property and a method gave the same counts, so the expansion in `Use.swift`'s job covers peer macros on every member, not only those on stored properties.

To confirm that a peer macro without `names:` cannot add a stored property, I wrote a second package whose `@attached(peer)` macro returns `var addedByPeer: Int = 0` and whose `@attached(member)` macro returns `var addedByMember: Int = 0`. Swift 6.4.2 rejects both:

```
error: declaration name 'addedByPeer' is not covered by macro 'PeerAddsStoredProperty'
error: declaration name 'addedByMember' is not covered by macro 'MemberAddsStoredProperty'
```

### Why it matters

Each type's macros are expanded once more for every frontend job that compiles a file that constructs the type. In a dependency-injection codebase, where most types carry marker peer macros on their stored properties and many files construct them, these extra expansions are a large share of all expansions. With 1,000 types, one per file, each with one member macro and two peer macros on stored properties, and all constructed in one file (6.4.2, Swift Build, clean Debug build, 4 cores):

- 8,931 expansions. 2,931 of them came from the one job containing `Use.swift`, which expanded the macros of the 977 types not among its own primary files.
- The plugin used 15.6 s of CPU in total.
- The build took 14.9 s wall-clock, against 9.3 s for the same code with the macro attributes removed (mean of three runs each: 9.3 s and 16.7 s).

I measured identical expansion counts on 6.2.4, 6.3.3 and 6.4.2 (Swift Build and native), so the behavior isn't new. The related three-expansions-per-Debug-build report has the full scaling table.

## Draft 2: Every macro expansion request carries the full static build configuration (about 4 KB), and swift-syntax decodes it for each request

### Description

Since Swift 6.3, every `expandAttachedMacro` request the compiler sends to a macro plugin includes a `staticBuildConfiguration` field. It's a JSON string of about 4–4.5 KB that lists every feature, attribute, custom condition and target property. With swift-syntax 604, `PluginProviderMessageHandler.handleMessage` decodes that string into a `StaticBuildConfiguration` for every request. It does so before running the macro, whether or not the macro reads `context.buildConfiguration`. The configuration content is the same for every request a plugin process receives. The decode multiplies the plugin's per-request message-decoding cost about tenfold: 7.7 µs → 100 µs with swift-syntax built for Release, 87 µs → 845 µs built for Debug. In a measured Debug build of 1,000 macro-using types, the plugin's CPU time went from 8.6 s with 6.2.4 to 15.6 s with 6.4.2, for the same number of expansions.

### Environment

- Swift 6.4.2 (swift-6.4.2-RELEASE), 6.3.3 and 6.2.4, release toolchains from swift.org.
- Ubuntu 24.04.5 LTS, x86_64, 4 cores, 16 GB.
- swift-syntax 604.0.0.
- SwiftPM's default build system on each: Swift Build on 6.4.2, native on 6.3.3 and 6.2.4.
- Not tested: macOS or Xcode.

### Steps to reproduce

This records the messages the compiler sends to a plugin without changing the plugin. Use any macro plugin built with swift-syntax 604, for example `NoopMacrosPlugin` from the related report about peer macros. Its `NoopPeerMacro` returns `[]`.

1. Build the plugin and write its path next to the recording script:

   ```bash
   swift build && echo "$(swift build --show-bin-path)/NoopMacrosPlugin" > request-sizes/plugin-path
   ```

2. `request-sizes/record-plugin.sh` (`chmod +x`). The frontend doesn't pass its environment to the plugin process, so the plugin path comes from a file:

   ```bash
   #!/bin/bash
   # Stands in for the macro plugin: appends everything the compiler sends to /tmp/requests.bin, then runs the
   # real plugin, whose path is in plugin-path next to this script. (The compiler does not pass its environment on.)
   tee -a /tmp/requests.bin | "$(cat "$(dirname "$0")/plugin-path")"
   ```

3. `request-sizes/Client.swift`:

   ```swift
   @attached(peer)
   macro NoopPeer() = #externalMacro(module: "NoopMacrosPlugin", type: "NoopPeerMacro")

   struct S {
   	@NoopPeer var a: Int = 0
   }
   ```

4. `request-sizes/frames.py` reads the recorded frames (an 8-byte little-endian length, then JSON):

   ```python
   #!/usr/bin/env python3
   """frames.py FILE [--show]: prints the size of each message the compiler sent and of its staticBuildConfiguration."""
   import json, struct, sys
   data = open(sys.argv[1], "rb").read(); offset = 0; rows = []
   while offset + 8 <= len(data):
       (count,) = struct.unpack_from("<Q", data, offset); offset += 8
       if count == 0: continue
       message = json.loads(data[offset:offset + count]); offset += count
       kind = next(iter(message))
       configuration = (message[kind] or {}).get("staticBuildConfiguration") or ""
       rows.append((kind, count, len(configuration.encode())))
   expansions = [r for r in rows if r[0].startswith("expand")]
   for kind in sorted({r[0] for r in rows}):
       print(f"{kind}: {sum(1 for r in rows if r[0] == kind)} messages")
   if expansions:
       print(f"expansion requests: {len(expansions)}, bytes each: {min(r[1] for r in expansions)}-{max(r[1] for r in expansions)}, "
             f"staticBuildConfiguration bytes each: {min(r[2] for r in expansions)}-{max(r[2] for r in expansions)}, "
             f"total: {sum(r[1] for r in expansions)} bytes")
   if len(sys.argv) > 2 and sys.argv[2] == "--show":
       # Field-by-field size of the first request's staticBuildConfiguration.
       offset = 0
       while offset + 8 <= len(data):
           (count,) = struct.unpack_from("<Q", data, offset); offset += 8
           message = json.loads(data[offset:offset + count]) if count else {}; offset += count
           configuration = message.get("expandAttachedMacro", {}).get("staticBuildConfiguration")
           if configuration:
               for key, value in json.loads(configuration).items():
                   print(f"  {key}: {len(json.dumps(value))} bytes" + (f", {len(value)} entries" if isinstance(value, list) else f" = {json.dumps(value)}"))
               break
   ```

5. With each compiler, and the same plugin binary:

   ```bash
   cd request-sizes && rm -f /tmp/requests.bin && swiftc -typecheck Client.swift -load-plugin-executable ./record-plugin.sh#NoopMacrosPlugin && python3 frames.py /tmp/requests.bin --show
   ```

### Expected result

Requests stay about the size of the syntax they carry, as with 6.2. Alternatively, the build configuration is sent once per plugin process, for example with the capability exchange, or only to plugins or macros that ask for it. And swift-syntax decodes it at most once per process, or only when a macro reads `context.buildConfiguration`.

### Actual result

One request for a one-line declaration, with each compiler and the same plugin binary:

| Compiler | Request bytes | `staticBuildConfiguration` bytes |
|---|---|---|
| 6.2.4 | 670 | (absent) |
| 6.3.3 | 4,715 | 3,651 |
| 6.4.2 | 5,143 | 4,043 |

The configuration in the 6.4.2 request (`--show`):

```
  attributes: 946 bytes, 64 entries
  compilerVersion: 25 bytes = {"components": [6, 4, 2]}
  customConditions: 2 bytes, 0 entries
  endianness: 8 bytes = "little"
  features: 2849 bytes, 113 entries
  languageMode: 23 bytes = {"components": [5, 10]}
  targetArchitectures: 10 bytes, 1 entries
  targetAtomicBitWidths: 20 bytes, 5 entries
  targetEnvironments: 2 bytes, 0 entries
  targetOSs: 9 bytes, 1 entries
  targetObjectFileFormats: 7 bytes, 1 entries
  targetPointerAuthenticationSchemes: 9 bytes, 1 entries
  targetPointerBitWidth: 2 bytes = 64
  targetRuntimes: 29 bytes, 2 entries
```

In SwiftPM builds the configuration is slightly larger: 4,504 bytes in a 6.4.2 Debug build and 4,080 bytes with 6.3.3. Every expansion request in a build carries it, about 5.9 KB per request on 6.4.2 against about 900 bytes on 6.2.4. Two requests captured from the same plugin process held the same configuration, but with the elements of `features`, `attributes` and `customConditions` in a different order.

**What decoding it costs.** I timed swift-syntax 604's decoder on a captured 6.4.2 request (5,843 bytes, 4,504 of them configuration), 20,000 iterations each, or 2,000 for Debug. The two decodes `handleMessage` performs are the request itself, then `JSON.decode(StaticBuildConfiguration.self, …)` on the embedded string. The rightmost column is that request with the field removed, for comparison.

| swift-syntax built for | Decode the request | Decode the configuration string | Total per request | Request without the field |
|---|---|---|---|---|
| Release | 27.8 µs | 72.0 µs | ~100 µs | 7.7 µs |
| Debug | 502 µs | 343 µs | ~845 µs | 87 µs |

**What it costs in a build.** Here, SwiftPM's Debug build compiles the macro plugin and swift-syntax in Debug as well. I measured a clean Debug build with SwiftPM of 1,000 classes in one file, each with one member macro and two peer macros, constructed from a second file: 9,000 expansions, 3 frontend jobs. The plugin's CPU time is summed over its processes. Swift-syntax's handler only decodes the configuration when the request contains it, so I compared the same plugin binary handing the handler each request as received ("kept") with handing it the request with the field removed ("removed"). Mean of three alternating runs:

| Compiler | Plugin CPU, kept | Plugin CPU, removed | Build wall-clock, kept | Build wall-clock, removed |
|---|---|---|---|---|
| 6.4.2 | 15.3 s | 11.1 s | 15.9 s | 14.3 s |
| 6.3.3 | 14.7 s | 10.9 s | 14.5 s | 13.1 s |

Removing the field before swift-syntax sees it still leaves the cost of scanning and copying the 4.5 KB string out of each request. Across compilers, with one type per file and the same plugin source (scale table in the related report on three expansions per Debug build), the plugin used this much CPU in total for the same 8,931 Debug or 3,000 Release expansions:

| | 6.2.4 | 6.3.3 | 6.4.2 |
|---|---|---|---|
| Clean Debug build, 1,000 types | 8.6 s | 15.0 s | 15.6 s |
| Clean Release build, 1,000 types | 0.39 s | 0.76 s | 0.78 s |

The plugin reported protocol version 7 instead of 8 in its capability reply on 6.4.2, and the compiler still sent the configuration.

### Why it matters

The cost is per expansion request, so it grows with the number of macro uses multiplied by the number of frontend jobs that expand each one; Debug builds expand each attached macro about three times. In the measured 1,000-type Debug build, the requests totaled 53 MB on 6.4.2 against 8 MB on 6.2.4. Removing only swift-syntax's decode saved 4.2 s of plugin CPU and 1.6 s of wall-clock time on 4 cores. Between 6.2.4 and 6.4.2, plugin CPU for the same expansions grew by 7 s, consistent with the ~0.76 ms of extra per-request decoding measured above for Debug-built swift-syntax.

What I could not confirm: the compiler-side cost of building and serializing the configuration for each request (I measured only the plugin side), and whether Xcode builds plugins in Debug for Debug builds as SwiftPM does here. The decode happens in swift-syntax (`Sources/SwiftCompilerPluginMessageHandling/CompilerPluginMessageHandler.swift`, the `.expandFreestandingMacro` and `.expandAttachedMacro` cases of `handleMessage`), so part of a fix may belong in swift-syntax.

## Draft 3: Debug builds expand each attached macro about three times; the third expansion comes from each file that constructs the type

### Description

In a Debug build, each attached macro use is sent to the plugin by three frontend jobs:

1. The emit-module job.
2. The job compiling the file that declares the type.
3. Each job compiling a file that constructs the type (or otherwise needs its stored properties, see the table below).

A whole-module Release build expands each macro use once. In an incremental Debug build after touching any one file, the emit-module job expands every macro use in the module again. Expansion results don't carry over from one job to another, so the plugin runs once per job, and a codebase where most types carry attached macros (dependency injection, observation, codable helpers) pays for the macros about three times per Debug build. The count is the same on 6.2.4, 6.3.3 and 6.4.2.

### Environment

- Swift 6.4.2 (swift-6.4.2-RELEASE), 6.3.3 and 6.2.4, release toolchains from swift.org.
- Ubuntu 24.04.5 LTS, x86_64, 4 cores, 16 GB.
- swift-syntax 604.0.0.
- SwiftPM's default build system on each: Swift Build on 6.4.2, native on 6.3.3 and 6.2.4. 6.4.2 was also run with `--build-system native`, with the same counts.
- Not tested: macOS or Xcode.

### Steps to reproduce

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

### Expected result

Each macro use is expanded once per build, or at least in no more jobs than need its expansion. The job compiling `Use.swift` calls `Service.init` and needs `Service`'s stored properties. None of these macros can add a stored property, because none declares `names:` (the related report shows the compiler rejects one that tries), so that job doesn't need to expand them.

### Actual result

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

### Why it matters

- **Clean Debug builds** expand each macro use about three times, against once in a whole-module build. At 1,000 types with no-op macros, the clean Debug build took 16.7 s against 9.3 s for the same code without the macro attributes (mean of three runs each, 6.4.2, 4 cores).
- **Incremental Debug builds** re-expand every macro use in the module in the emit-module job, whichever file changed. Touching one of 1,000 files cost 3,003 expansions and 5.3 s of plugin CPU, nearly all in that one job's plugin process. The incremental build took 13.4 s, against 6.6 s for the same incremental build of the same code without the macro attributes (mean of three runs each, 6.4.2). It's close to the 14.9 s of a clean build.
- **Each file that constructs a type** adds a full expansion of that type's macros in its batch job. Composition roots and factories construct many types, so they re-expand the macros of everything they build.

What I could not confirm: why the emit-module job of an incremental build expands every macro (I measured only that it does), and how Xcode's build system distributes these jobs.

## Commit

This report, the drafts, the reproductions and the measurements were committed together on branch `dfed--claude/cloud-swift-issues`. The commit SHA is given in the session's final message, since a file can't contain the SHA of the commit that adds it.
