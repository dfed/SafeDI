# Peer macros that declare no `names:` are expanded again in every file that needs the type's stored properties

## Description

When a file constructs a type, reads one of its stored properties, or references a class's metatype, the frontend job compiling that file expands every peer macro attached to any member of that type, even though the type is declared in another file. That includes peer macros on methods and computed properties, and peer macros whose declaration lists no `names:`. A peer macro without `names:` cannot introduce a stored property: the compiler rejects such an expansion with "declaration name … is not covered by macro". So these expansions can't change the type's stored properties, yet they run again in each job that needs them. A file that only calls a computed property on the same type expands none of them. `@attached(member)` macros without `names:` behave the same way in the same measurements. Peer macros that do nothing (`@Instantiated`, `@Received` and similar markers in dependency-injection libraries) are common on stored properties, so this repeats plugin round trips across many files.

## Environment

- Swift 6.4.2 (swift-6.4.2-RELEASE), 6.3.3 and 6.2.4, release toolchains from swift.org.
- Ubuntu 24.04.5 LTS, x86_64, 4 cores, 16 GB.
- swift-syntax 604.0.0.
- SwiftPM's default build system on each: Swift Build on 6.4.2, native on 6.3.3 and 6.2.4. 6.4.2 was also run with `--build-system native`.
- Not tested: macOS or Xcode.

## Steps to reproduce

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

## Expected result

Peer macros are expanded in the jobs that type-check the declarations they're attached to: the emit-module job and the job whose primary file is `Types.swift`. The job compiling `Use.swift` needs `Service`'s stored properties to construct it. None of the four `@NoopPeer` macros can add a stored property, since `@NoopPeer` declares no `names:`, so that job doesn't need to expand them.

## Actual result

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

## Why it matters

Each type's macros are expanded once more for every frontend job that compiles a file that constructs the type. In a dependency-injection codebase, where most types carry marker peer macros on their stored properties and many files construct them, these extra expansions are a large share of all expansions. With 1,000 types, one per file, each with one member macro and two peer macros on stored properties, and all constructed in one file (6.4.2, Swift Build, clean Debug build, 4 cores):

- 8,931 expansions. 2,931 of them came from the one job containing `Use.swift`, which expanded the macros of the 977 types not among its own primary files.
- The plugin used 15.6 s of CPU in total.
- The build took 14.9 s wall-clock, against 9.3 s for the same code with the macro attributes removed (mean of three runs each: 9.3 s and 16.7 s).

I measured identical expansion counts on 6.2.4, 6.3.3 and 6.4.2 (Swift Build and native), so the behavior isn't new. The related three-expansions-per-Debug-build report has the full scaling table.
