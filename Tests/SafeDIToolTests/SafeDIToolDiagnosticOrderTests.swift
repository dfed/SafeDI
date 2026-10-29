// Distributed under the MIT License
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import SafeDICore
import Testing
@testable import SafeDITool

/// Which diagnostics `generate` reports, and where, depends on where the user declares things, never on the names
/// that sort the types, properties, or files. Each test generates two inputs that differ only in names that sort the
/// other way, from one file so every declaration keeps its location, and expects the same diagnostics, renamed.
struct SafeDIToolDiagnosticOrderTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_reportsTheSameCyclesEveryRun_whenAHandWrittenMockLeavesOutADependencyOfATypeThatGeneratesAMock() async {
		// `T` has two mock scopes, the full one and the one its hand-written mock builds, which leaves out `x`.
		// Each is validated, and the cycle each reaches first differs.
		for _ in 0..<10 {
			await assertThrowsError(
				diagnostics: { fixtures in
					"""
					\(fixtures["Module.swift"]):34:5: error: Dependency cycle: `X` -> `X2` -> `X`. SafeDI accepts a dependency cycle only if the dependency that closes it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change `x: X` to an instantiator; SafeDI then reports any other dependency in the cycle that must change too.
					\(fixtures["Module.swift"]):25:1: note: `X` is part of the cycle
					\(fixtures["Module.swift"]):31:1: note: `X2` is part of the cycle
					\(fixtures["Module.swift"]):46:5: error: Dependency cycle: `Y` -> `Y2` -> `Y`. SafeDI accepts a dependency cycle only if the dependency that closes it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change `y: Y` to an instantiator; SafeDI then reports any other dependency in the cycle that must change too.
					\(fixtures["Module.swift"]):37:1: note: `Y` is part of the cycle
					\(fixtures["Module.swift"]):43:1: note: `Y2` is part of the cycle
					"""
				},
			) {
				try await executeSafeDIToolTest(
					swiftFileContent: [],
					swiftFileContentByFilePath: [
						"Module.swift": """
						import SafeDI

						public protocol P {}

						@Instantiable(fulfillingAdditionalTypes: [P.self], generateMock: true)
						public final class T: P, Instantiable {
						    public init(x: X, y: Y, token: String) {
						        fatalError("SafeDI doesn't inspect the initializer body")
						    }

						    @Instantiated let x: X
						    @Instantiated let y: Y
						    @Received let token: String
						}

						#if DEBUG
						@Instantiable(fulfillingAdditionalTypes: [P.self], mockOnly: true, customMockName: "fake")
						extension T {
						    public static func fake(y: Y, token: String) -> P {
						        fatalError("SafeDI doesn't inspect the mock body")
						    }
						}
						#endif

						@Instantiable
						public final class X: Instantiable {
						    public init(x2: X2, token: String) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let x2: X2
						    @Received let token: String
						}
						@Instantiable
						public final class X2: Instantiable {
						    public init(x: X, token: String) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let x: X
						    @Received let token: String
						}
						@Instantiable
						public final class Y: Instantiable {
						    public init(y2: Y2, token: String) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let y2: Y2
						    @Received let token: String
						}
						@Instantiable
						public final class Y2: Instantiable {
						    public init(y: Y, token: String) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let y: Y
						    @Received let token: String
						}
						""",
					],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_reportsTheCycleOfEachRoot_whenRootNamesSortEitherWay() async {
		for firstRootName in ["AlphaRoot", "ZetaRoot"] {
			await assertThrowsError(
				diagnostics: { fixtures in
					"""
					\(fixtures["Module.swift"]):18:5: error: Dependency cycle: `One` -> `Two` -> `One`. SafeDI accepts a dependency cycle only if the dependency that closes it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change `one: One` to an instantiator; SafeDI then reports any other dependency in the cycle that must change too.
					\(fixtures["Module.swift"]):9:1: note: `One` is part of the cycle
					\(fixtures["Module.swift"]):15:1: note: `Two` is part of the cycle
					\(fixtures["Module.swift"]):36:5: error: Dependency cycle: `Three` -> `Four` -> `Three`. SafeDI accepts a dependency cycle only if the dependency that closes it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change `three: Three` to an instantiator; SafeDI then reports any other dependency in the cycle that must change too.
					\(fixtures["Module.swift"]):27:1: note: `Three` is part of the cycle
					\(fixtures["Module.swift"]):33:1: note: `Four` is part of the cycle
					"""
				},
			) {
				try await executeSafeDIToolTest(
					swiftFileContent: [],
					swiftFileContentByFilePath: [
						"Module.swift": """
						import SafeDI

						@Instantiable(isRoot: true)
						public final class \(firstRootName): Instantiable {
						    public init(one: One) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let one: One
						}

						@Instantiable
						public final class One: Instantiable {
						    public init(two: Two) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let two: Two
						}

						@Instantiable
						public final class Two: Instantiable {
						    public init(one: One) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let one: One
						}

						@Instantiable(isRoot: true)
						public final class BetaRoot: Instantiable {
						    public init(three: Three) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let three: Three
						}

						@Instantiable
						public final class Three: Instantiable {
						    public init(four: Four) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let four: Four
						}

						@Instantiable
						public final class Four: Instantiable {
						    public init(three: Three) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let three: Three
						}
						""",
					],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_reportsChildrenRequiringEachOtherInEachRoot_whenRootNamesSortEitherWay() async {
		for firstRootName in ["AlphaRoot", "ZetaRoot"] {
			await assertThrowsError(
				diagnostics: { fixtures in
					"""
					\(fixtures["Module.swift"]):19:5: error: Dependency cycle: @Instantiated `p: Instantiator<P>` -> @Received `q: Instantiator<Q>` -> @Received `p: Instantiator<P>`. `p: Instantiator<P>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
					\(fixtures["Module.swift"]):38:5: error: Dependency cycle: @Instantiated `r: Instantiator<R>` -> @Received `s: Instantiator<S>` -> @Received `r: Instantiator<R>`. `r: Instantiator<R>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
					"""
				},
			) {
				try await executeSafeDIToolTest(
					swiftFileContent: [],
					swiftFileContentByFilePath: [
						"Module.swift": """
						import SafeDI

						@Instantiable(isRoot: true)
						public final class \(firstRootName): Instantiable {
						    public init(p: Instantiator<P>, q: Instantiator<Q>) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let p: Instantiator<P>
						    @Instantiated let q: Instantiator<Q>
						}

						@Instantiable
						public final class P: Instantiable {
						    public init(q: Instantiator<Q>) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received let q: Instantiator<Q>
						}

						@Instantiable
						public final class Q: Instantiable {
						    public init(p: Instantiator<P>) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received let p: Instantiator<P>
						}

						@Instantiable(isRoot: true)
						public final class BetaRoot: Instantiable {
						    public init(r: Instantiator<R>, s: Instantiator<S>) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let r: Instantiator<R>
						    @Instantiated let s: Instantiator<S>
						}

						@Instantiable
						public final class R: Instantiable {
						    public init(s: Instantiator<S>) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received let s: Instantiator<S>
						}

						@Instantiable
						public final class S: Instantiable {
						    public init(r: Instantiator<R>) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received let r: Instantiator<R>
						}
						""",
					],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_reportsTheSameChildrenRequiringEachOther_whenRootsThatShareTheirScopeSortEitherWay() async {
		// Both roots reach `Shared`, whose children require one another. A root that reaches it after another root's
		// validation failed there still reports it, so neither root's later trees are validated for one name order only.
		for firstRootName in ["AlphaRoot", "ZetaRoot"] {
			await assertThrowsError(
				diagnostics: { fixtures in
					"""
					\(fixtures["Module.swift"]):30:5: error: Dependency cycle: @Instantiated `p: Instantiator<P>` -> @Received `q: Instantiator<Q>` -> @Received `p: Instantiator<P>`. `p: Instantiator<P>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
					"""
				},
			) {
				try await executeSafeDIToolTest(
					swiftFileContent: [],
					swiftFileContentByFilePath: [
						"Module.swift": """
						import SafeDI

						@Instantiable(isRoot: true)
						public final class \(firstRootName): Instantiable {
						    public init(shared: Shared) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let shared: Shared
						}

						@Instantiable(isRoot: true)
						public final class BetaRoot: Instantiable {
						    public init(shared: Shared, other: Other) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let shared: Shared
						    @Instantiated let other: Other
						}

						@Instantiable
						public final class Shared: Instantiable {
						    public init(p: Instantiator<P>, q: Instantiator<Q>) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let p: Instantiator<P>
						    @Instantiated let q: Instantiator<Q>
						}
						@Instantiable
						public final class P: Instantiable {
						    public init(q: Instantiator<Q>) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received let q: Instantiator<Q>
						}
						@Instantiable
						public final class Q: Instantiable {
						    public init(p: Instantiator<P>) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received let p: Instantiator<P>
						}

						@Instantiable
						public final class Other: Instantiable {
						    public init(r: Instantiator<R>, s: Instantiator<S>) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let r: Instantiator<R>
						    @Instantiated let s: Instantiator<S>
						}
						@Instantiable
						public final class R: Instantiable {
						    public init(s: Instantiator<S>) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received let s: Instantiator<S>
						}
						@Instantiable
						public final class S: Instantiable {
						    public init(r: Instantiator<R>) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received let r: Instantiator<R>
						}
						""",
					],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_reportsTheSameReceivedCycle_whenRootsThatWalkTheSameAliasSortEitherWay() async {
		// Both roots reach `C`'s receive of `D`'s `onlyIfAvailable` alias, whose fulfilling property `x` receives `d`.
		// A root that reaches the alias after another root's walk of it failed still reports it, so the cycle under
		// `BetaRoot`'s `one` is reported for neither name order.
		for firstRootName in ["AlphaRoot", "ZetaRoot"] {
			await assertThrowsError(
				diagnostics: { fixtures in
					"""
					\(fixtures["Module.swift"]):21:5: error: Dependency cycle: @Instantiated `d: D` -> @Received `renamedX: X?` -> @Received `x: X` -> @Received `d: D`. `d: D` is received while it is still being instantiated. `renamedX: X?` renames `x: X` only if available, so a type that receives `renamedX` without `onlyIfAvailable` must be built after `x: X`. Receive `renamedX` with `@Received(onlyIfAvailable: true)` to be passed `nil` where `x: X` cannot be built first.
					"""
				},
			) {
				try await executeSafeDIToolTest(
					swiftFileContent: [],
					swiftFileContentByFilePath: [
						"Module.swift": """
						import SafeDI

						@Instantiable(isRoot: true)
						public final class \(firstRootName): Instantiable {
						    public init(x: X, d: D) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let x: X
						    @Instantiated let d: D
						}

						@Instantiable(isRoot: true)
						public final class BetaRoot: Instantiable {
						    public init(x: X, d: D, one: One) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let x: X
						    @Instantiated let d: D
						    @Instantiated let one: One
						}

						@Instantiable
						public final class X: Instantiable {
						    public init(d: D) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received let d: D
						}

						@Instantiable
						public final class D: Instantiable {
						    public init(renamedX: X?, c: C) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received(fulfilledByDependencyNamed: "x", ofType: X.self, onlyIfAvailable: true) let renamedX: X?
						    @Instantiated let c: C
						}

						@Instantiable
						public final class C: Instantiable {
						    public init(renamedX: X?) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received let renamedX: X?
						}

						@Instantiable
						public final class One: Instantiable {
						    public init(two: Two) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let two: Two
						}

						@Instantiable
						public final class Two: Instantiable {
						    public init(one: One) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let one: One
						}
						""",
					],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_reportsEveryPropertyWhoseTypeHasForwardedProperties_whenParentNamesSortEitherWay() async {
		for firstParentName in ["Alpha", "Gamma"] {
			await assertThrowsError(
				diagnostics: { fixtures in
					"""
					\(fixtures["Module.swift"]):6:5: error: `leaf: Leaf` on `\(firstParentName)` cannot build `Leaf`, which has @Forwarded properties that only an instantiator is passed. Declare it as `Instantiator<Leaf>`.
					\(fixtures["Module.swift"]):18:5: note: @Forwarded property `value: Int` is declared here
					\(fixtures["Module.swift"]):12:5: error: `widget: Widget` on `Beta` cannot build `Widget`, which has @Forwarded properties that only an instantiator is passed. Declare it as `Instantiator<Widget>`.
					\(fixtures["Module.swift"]):24:5: note: @Forwarded property `name: String` is declared here
					"""
				},
			) {
				try await executeSafeDIToolTest(
					swiftFileContent: [],
					swiftFileContentByFilePath: [
						"Module.swift": Self.parentsOfTypesWithForwardedProperties(firstParentName: firstParentName, attribute: "@Instantiable(isRoot: true)"),
					],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_reportsTheErrorOfEachMockRoot_whenTypeNamesSortEitherWay() async {
		for firstParentName in ["Alpha", "Gamma"] {
			await assertThrowsError(
				diagnostics: { fixtures in
					"""
					\(fixtures["Module.swift"]):6:5: error: `leaf: Leaf` on `\(firstParentName)` cannot build `Leaf`, which has @Forwarded properties that only an instantiator is passed. Declare it as `Instantiator<Leaf>`.
					\(fixtures["Module.swift"]):18:5: note: @Forwarded property `value: Int` is declared here
					\(fixtures["Module.swift"]):12:5: error: `widget: Widget` on `Beta` cannot build `Widget`, which has @Forwarded properties that only an instantiator is passed. Declare it as `Instantiator<Widget>`.
					\(fixtures["Module.swift"]):24:5: note: @Forwarded property `name: String` is declared here
					"""
				},
			) {
				try await executeSafeDIToolTest(
					swiftFileContent: [],
					swiftFileContentByFilePath: [
						"Module.swift": Self.parentsOfTypesWithForwardedProperties(firstParentName: firstParentName, attribute: "@Instantiable(generateMock: true)"),
					],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_reportsTheCycleThroughThePromotedChildReceivedFirst_whenTheLabelsOfPromotedChildrenSortEitherWay() async {
		// The mock root promotes `a`, `b`, `c`, and `d`. One cycle runs through `a`, another through `c`, and the mock's
		// tree receives `a` first: `B`, which Root receives before `D`, receives it, and `D` receives `c`.
		for (cycleType, otherType) in [("A", "B"), ("Y", "Z")] {
			let cycleLabel = cycleType.lowercased()
			let otherLabel = otherType.lowercased()
			await assertThrowsError(
				diagnostics: { fixtures in
					"""
					\(fixtures["Module.swift"]):19:5: error: Dependency cycle: `Instantiator<\(cycleType)>` -> `\(otherType)` -> `Instantiator<\(cycleType)>`. `\(otherType)` receives `\(cycleLabel): Instantiator<\(cycleType)>` inside the tree that `\(cycleLabel)` builds. Declare `\(cycleLabel): Instantiator<\(cycleType)>` on `\(otherType)` as @Instantiated instead of @Received.
					\(fixtures["Module.swift"]):10:1: note: `\(cycleType)` is part of the cycle
					\(fixtures["Module.swift"]):16:1: note: `\(otherType)` is part of the cycle
					"""
				},
			) {
				try await executeSafeDIToolTest(
					swiftFileContent: [],
					swiftFileContentByFilePath: [
						"Module.swift": """
						import SafeDI

						@Instantiable(generateMock: true)
						public final class Root: Instantiable {
						    public init(\(otherLabel): \(otherType), d: D) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received let \(otherLabel): \(otherType)
						    @Received let d: D
						}

						@Instantiable
						public final class \(cycleType): Instantiable {
						    public init(\(otherLabel): \(otherType)) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let \(otherLabel): \(otherType)
						}

						@Instantiable
						public final class \(otherType): Instantiable {
						    public init(\(cycleLabel): Instantiator<\(cycleType)>) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received let \(cycleLabel): Instantiator<\(cycleType)>
						}

						@Instantiable
						public final class C: Instantiable {
						    public init(d: D) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let d: D
						}

						@Instantiable
						public final class D: Instantiable {
						    public init(c: Instantiator<C>) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received let c: Instantiator<C>
						}
						""",
					],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_reportsPromotedChildrenRequiringEachOtherFromTheChildReceivedFirst_whenTheirTypeNamesSortEitherWay() async {
		// The mock root promotes `service: Instantiator<ServiceA>` and `service: Instantiator<ServiceB>`, which share a
		// label, so only their type names could order them by name. The mock's tree receives the first one first.
		for firstServiceName in ["ServiceA", "ServiceZ"] {
			await assertThrowsError(
				diagnostics: { fixtures in
					"""
					\(fixtures["Module.swift"]):18:5: error: Dependency cycle: @Instantiated `service: Instantiator<\(firstServiceName)>` -> @Received `service: Instantiator<ServiceB>` -> @Received `service: Instantiator<\(firstServiceName)>`. `service: Instantiator<\(firstServiceName)>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
					"""
				},
			) {
				try await executeSafeDIToolTest(
					swiftFileContent: [],
					swiftFileContentByFilePath: [
						"Module.swift": """
						import SafeDI

						@Instantiable(generateMock: true)
						public final class Root: Instantiable {
						    public init(service: Instantiator<\(firstServiceName)>) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received let service: Instantiator<\(firstServiceName)>
						}

						@Instantiable
						public final class \(firstServiceName): Instantiable {
						    public init(service: Instantiator<ServiceB>) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received let service: Instantiator<ServiceB>
						}

						@Instantiable
						public final class ServiceB: Instantiable {
						    public init(service: Instantiator<\(firstServiceName)>) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received let service: Instantiator<\(firstServiceName)>
						}
						""",
					],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_reportsPromotedChildrenReceivingEachOtherFromTheChildReceivedFirst_whenTheirLabelsSortEitherWay() async {
		// `Host` receives `gamma` first, so the chain starts there, although the other child's type is declared first.
		for (secondType, secondLabel) in [("Beta", "beta"), ("Zeta", "zeta")] {
			await assertThrowsError(
				diagnostics: { fixtures in
					"""
					\(fixtures["Module.swift"]):13:5: error: Dependency cycle: @Instantiated `gamma: Gamma` -> @Received `\(secondLabel): \(secondType)` -> @Received `gamma: Gamma`. `gamma: Gamma` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
					"""
				},
			) {
				try await executeSafeDIToolTest(
					swiftFileContent: [],
					swiftFileContentByFilePath: [
						"Module.swift": """
						import SafeDI

						@Instantiable(generateMock: true)
						public final class Host: Instantiable {
						    public init(gamma: Gamma, \(secondLabel): \(secondType)) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received let gamma: Gamma
						    @Received let \(secondLabel): \(secondType)
						}

						@Instantiable
						public final class \(secondType): Instantiable {
						    public init(gamma: Gamma) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received let gamma: Gamma
						}

						@Instantiable
						public final class Gamma: Instantiable {
						    public init(\(secondLabel): \(secondType)) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received let \(secondLabel): \(secondType)
						}
						""",
					],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_namesTheChildsOwnPropertyInChildrenRequiringEachOther_whenAnAliasOfItsLabelSortsEitherWay() async {
		// `Beta` receives `Root`'s `alpha` both by its label and through `Root`'s alias `renamedAlpha`.
		for alphaLabel in ["alpha", "zAlpha"] {
			await assertThrowsError(
				diagnostics: { fixtures in
					"""
					\(fixtures["Module.swift"]):14:5: error: Dependency cycle: @Instantiated `\(alphaLabel): Instantiator<Alpha>` -> @Received `beta: Instantiator<Beta>` -> @Received `\(alphaLabel): Instantiator<Alpha>`. `\(alphaLabel): Instantiator<Alpha>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
					"""
				},
			) {
				try await executeSafeDIToolTest(
					swiftFileContent: [],
					swiftFileContentByFilePath: [
						"Module.swift": """
						import SafeDI

						@Instantiable(isRoot: true)
						public final class Root: Instantiable {
						    public init(\(alphaLabel): Instantiator<Alpha>, beta: Instantiator<Beta>, renamedAlpha: Instantiator<Alpha>) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let \(alphaLabel): Instantiator<Alpha>
						    @Instantiated let beta: Instantiator<Beta>
						    @Received(fulfilledByDependencyNamed: "\(alphaLabel)", ofType: Instantiator<Alpha>.self) let renamedAlpha: Instantiator<Alpha>
						}

						@Instantiable
						public final class Beta: Instantiable {
						    public init(\(alphaLabel): Instantiator<Alpha>, renamedAlpha: Instantiator<Alpha>) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received let \(alphaLabel): Instantiator<Alpha>
						    @Received let renamedAlpha: Instantiator<Alpha>
						}

						@Instantiable
						public final class Alpha: Instantiable {
						    public init(beta: Instantiator<Beta>) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Received let beta: Instantiator<Beta>
						}
						""",
					],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_reportsEveryTypeThatNoInstantiableFulfills_whenTypeNamesSortEitherWay() async {
		for (firstType, secondType) in [("Alpha", "Zeta"), ("Zeta", "Alpha")] {
			await assertThrowsError(
				diagnostics: { fixtures in
					"""
					\(fixtures["Module.swift"]):6:5: error: No @Instantiable type or extension fulfills `\(firstType)`, which @Instantiated property `first: \(firstType)` instantiates. Decorate `\(firstType)`, or an extension of it, with @Instantiable; list `\(firstType)` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; or, if such a declaration is in another module, make that module one SafeDI reads for this target.
					\(fixtures["Module.swift"]):7:5: error: No @Instantiable type or extension fulfills `\(secondType)`, which @Instantiated property `second: \(secondType)` instantiates. Decorate `\(secondType)`, or an extension of it, with @Instantiable; list `\(secondType)` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; or, if such a declaration is in another module, make that module one SafeDI reads for this target.
					"""
				},
			) {
				try await executeSafeDIToolTest(
					swiftFileContent: [],
					swiftFileContentByFilePath: [
						"Module.swift": """
						import SafeDI

						@Instantiable(isRoot: true)
						public final class Root: Instantiable {
						    public init(first: \(firstType), second: \(secondType)) { fatalError("SafeDI doesn't inspect the initializer body") }
						    @Instantiated let first: \(firstType)
						    @Instantiated let second: \(secondType)
						}

						public final class \(firstType) {}

						public final class \(secondType) {}
						""",
					],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_reportsEveryTypeThatSeveralDeclarationsFulfill_whenFileNamesSortEitherWay() async {
		// The fixtures are named after their types, so renaming `Beta` to `Zeta` moves its file after the others.
		for secondServiceOneType in ["Beta", "Zeta"] {
			await assertThrowsError(
				diagnostics: { fixtures in
					"""
					\(fixtures["Alpha.swift"]):3:1: error: Found multiple @Instantiable types or extensions that fulfill `ServiceOne`. Each type can be fulfilled by only one @Instantiable declaration, across all modules. Keep one, and remove `ServiceOne` from the others’ `fulfillingAdditionalTypes` or remove their @Instantiable.
					\(fixtures["\(secondServiceOneType).swift"]):3:1: error: Found multiple @Instantiable types or extensions that fulfill `ServiceOne`. Each type can be fulfilled by only one @Instantiable declaration, across all modules. Keep one, and remove `ServiceOne` from the others’ `fulfillingAdditionalTypes` or remove their @Instantiable.
					\(fixtures["Delta.swift"]):3:1: error: Found multiple @Instantiable types or extensions that fulfill `ServiceTwo`. Each type can be fulfilled by only one @Instantiable declaration, across all modules. Keep one, and remove `ServiceTwo` from the others’ `fulfillingAdditionalTypes` or remove their @Instantiable.
					\(fixtures["Gamma.swift"]):3:1: error: Found multiple @Instantiable types or extensions that fulfill `ServiceTwo`. Each type can be fulfilled by only one @Instantiable declaration, across all modules. Keep one, and remove `ServiceTwo` from the others’ `fulfillingAdditionalTypes` or remove their @Instantiable.
					"""
				},
			) {
				try await executeSafeDIToolTest(
					swiftFileContent: [
						"""
						public protocol ServiceOne {}
						public protocol ServiceTwo {}
						""",
						"""
						import SafeDI

						@Instantiable(fulfillingAdditionalTypes: [ServiceOne.self])
						public struct Alpha: ServiceOne, Instantiable {
						    public init() {}
						}
						""",
						"""
						import SafeDI

						@Instantiable(fulfillingAdditionalTypes: [ServiceOne.self])
						public struct \(secondServiceOneType): ServiceOne, Instantiable {
						    public init() {}
						}
						""",
						"""
						import SafeDI

						@Instantiable(fulfillingAdditionalTypes: [ServiceTwo.self])
						public struct Delta: ServiceTwo, Instantiable {
						    public init() {}
						}
						""",
						"""
						import SafeDI

						@Instantiable(fulfillingAdditionalTypes: [ServiceTwo.self])
						public struct Gamma: ServiceTwo, Instantiable {
						    public init() {}
						}
						""",
					],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_warnsNamingTheFirstDeclaredReader_whenAliasesOfALazilyInstantiatedPropertySortEitherWay() async throws {
		// `Owner` renames `Top`'s `foo` twice, and `Child` reads the instance through both names.
		for firstAliasLabel in ["bar", "qux"] {
			let output = try await executeSafeDIToolTest(
				swiftFileContent: [],
				swiftFileContentByFilePath: [
					"Module.swift": """
					import SafeDI

					@Instantiable(isRoot: true)
					public struct Top: Instantiable {
					    public init(foo: LazilyInstantiated<Foo>, owner: Owner) { self.foo = foo; self.owner = owner }
					    @Instantiated let foo: LazilyInstantiated<Foo>
					    @Instantiated let owner: Owner
					}

					@Instantiable
					public struct Owner: Instantiable {
					    public init(\(firstAliasLabel): LazilyInstantiated<Foo>, baz: LazilyInstantiated<Foo>, child: Child) { self.\(firstAliasLabel) = \(firstAliasLabel); self.baz = baz; self.child = child }
					    @Received(fulfilledByDependencyNamed: "foo", ofType: LazilyInstantiated<Foo>.self) let \(firstAliasLabel): LazilyInstantiated<Foo>
					    @Received(fulfilledByDependencyNamed: "foo", ofType: LazilyInstantiated<Foo>.self) let baz: LazilyInstantiated<Foo>
					    @Instantiated let child: Child
					}

					@Instantiable
					public struct Child: Instantiable {
					    public init(\(firstAliasLabel): Foo, baz: Foo) { self.\(firstAliasLabel) = \(firstAliasLabel); self.baz = baz }
					    @Received let \(firstAliasLabel): Foo
					    @Received let baz: Foo
					}

					@Instantiable
					public struct Foo: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)

			#expect(output.warnings.map(\.formatted) == [
				"\(output.fixtures["Module.swift"]):6:5: warning: @Instantiated property `foo: LazilyInstantiated<Foo>` is instantiated whenever `Top` is created: `Child` is created with `Top` and receives the instance as `\(firstAliasLabel): Foo`. To instantiate it lazily, receive `\(firstAliasLabel): LazilyInstantiated<Foo>` on `Child`.",
			])
		}
	}

	// MARK: Private

	private var filesToDelete = [URL]()

	/// Two types decorated with `attribute`, each with a constant `@Instantiated` property whose type has a
	/// `@Forwarded` property. The first is named `firstParentName`, and the second `Beta`.
	private static func parentsOfTypesWithForwardedProperties(firstParentName: String, attribute: String) -> String {
		"""
		import SafeDI

		\(attribute)
		public final class \(firstParentName): Instantiable {
		    public init(leaf: Leaf) { fatalError("SafeDI doesn't inspect the initializer body") }
		    @Instantiated let leaf: Leaf
		}

		\(attribute)
		public final class Beta: Instantiable {
		    public init(widget: Widget) { fatalError("SafeDI doesn't inspect the initializer body") }
		    @Instantiated let widget: Widget
		}

		@Instantiable
		public final class Leaf: Instantiable {
		    public init(value: Int) { fatalError("SafeDI doesn't inspect the initializer body") }
		    @Forwarded let value: Int
		}

		@Instantiable
		public final class Widget: Instantiable {
		    public init(name: String) { fatalError("SafeDI doesn't inspect the initializer body") }
		    @Forwarded let name: String
		}
		"""
	}
}
