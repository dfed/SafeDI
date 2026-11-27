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
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// Acceptance cells of the mock kinds, from the frozen mock writer's value tests: two places that differ in one part of a
/// record, laid out from node records and written by the mock's walk, compiled, and compared by value
/// (`MockKindsAcceptance`).
struct SafeDIToolMockKindsNodeValueTests: ~Copyable {
	// MARK: Initialization

	init() {
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
	mutating func mock_buildsWalksValues_whenFeaturesDeclareSameSiblingsInOtherOrdersBeneathSendableInstantiators() async throws {
		// `F1` builds `x` before `screenBuilder` and `F2` after it, so the `G` beneath `F2`'s builder receives `F2`'s `x` and
		// the one beneath `F1`'s receives `nil`: the two `P`s between hold one generator and read one override alike, and
		// differ only in the records of their children.
		let fixtureFiles = [
			"Root.swift": Self.type("Root", generateMock: true, properties: ["@Instantiated let f2: F2", "@Instantiated let f1: F1"]),
			"F1.swift": Self.type("F1", properties: ["@Instantiated let x: X", "@Instantiated let screenBuilder: SendableInstantiator<Screen>"]),
			"F2.swift": Self.type("F2", properties: ["@Instantiated let screenBuilder: SendableInstantiator<Screen>", "@Instantiated let x: X"]),
			"X.swift": Self.type("X", conformances: ", Sendable", properties: ["@Received(onlyIfAvailable: true) let screenBuilder: SendableInstantiator<Screen>?"]),
			"Screen.swift": Self.type("Screen", conformances: ", Sendable", properties: ["@Instantiated let p: P"]),
			"P.swift": Self.type("P", conformances: ", Sendable", properties: ["@Instantiated let g: G"]),
			"G.swift": Self.type("G", conformances: ", Sendable", properties: ["@Received(onlyIfAvailable: true) let x: X?"]),
		]
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("{ let root = Root.mock(); return root.f2.screenBuilder.instantiate().p.g.x === root.f2.x }()"),
			DifferentialValueProbe("{ let root = Root.mock(); return root.f1.screenBuilder.instantiate().p.g.x === root.f1.x }()"),
			DifferentialValueProbe("{ let root = Root.mock(); return root.f1.screenBuilder.instantiate().p.g.x == nil }()"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenOnlyRenameTellsTwoPlacesBeneathSendableInstantiatorsApart() async throws {
		// `Model` receives `config: any ConfigA`, which `P2` builds and which beneath `P1` is `mock()`'s parameter, named
		// apart from `Other`'s `config: any ConfigB`. The places between receive nothing themselves.
		let fixtureFiles = [
			"Root.swift": Self.type("Root", generateMock: true, properties: ["@Instantiated let p2: P2", "@Instantiated let p1: P1", "@Instantiated let other: Other"]),
			"P1.swift": Self.type("P1", properties: ["@Instantiated let screenBuilder: SendableInstantiator<Screen>"]),
			"P2.swift": Self.type("P2", properties: [#"@Instantiated(fulfilledByType: "LiveConfig") let config: any ConfigA"#, "@Instantiated let screenBuilder: SendableInstantiator<Screen>"]),
			"Screen.swift": Self.type("Screen", conformances: ", Sendable", properties: ["@Instantiated let panel: Panel"]),
			"Panel.swift": Self.type("Panel", conformances: ", Sendable", properties: ["@Instantiated let model: Model"]),
			"Model.swift": Self.type("Model", conformances: ", Sendable", properties: ["@Received let config: any ConfigA"]),
			"Other.swift": Self.type("Other", properties: ["@Received let config: any ConfigB"]),
			"LiveConfig.swift": Self.type("LiveConfig", conformances: ", ConfigA", properties: []),
			"Protocols.swift": """
			public protocol ConfigA: AnyObject, Sendable {}
			public protocol ConfigB: AnyObject, Sendable {}
			public final class GivenConfigA: ConfigA {
			    public init() {}
			}
			public final class GivenConfigB: ConfigB {
			    public init() {}
			}
			""",
		]
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("{ let root = Root.mock(config_ConfigA: GivenConfigA(), config_ConfigB: GivenConfigB()); return root.p2.screenBuilder.instantiate().panel.model.config === root.p2.config }()"),
			DifferentialValueProbe("{ let given = GivenConfigA(); return Root.mock(config_ConfigA: given, config_ConfigB: GivenConfigB()).p1.screenBuilder.instantiate().panel.model.config === given }()"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenActorAndClassDeclareSameInstantiatorOfLeaf() async throws {
		// `Leaf` has no configuration, so each place takes its override closure, typed `@Sendable` only beneath the actor.
		let fixtureFiles = [
			"Root.swift": Self.type("Root", generateMock: true, properties: ["@Instantiated let a: A", "@Instantiated let b: B"]),
			"A.swift": Self.type("A", kind: "actor", properties: ["@Instantiated let leafBuilder: Instantiator<Leaf>"]),
			"B.swift": Self.type("B", properties: ["@Instantiated let leafBuilder: Instantiator<Leaf>"]),
			"Leaf.swift": Self.type("Leaf", properties: []),
		]
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("{ let leaf = Leaf(); return Root.mock(safeDIOverrides: .init(b: .init(leafBuilder: { leaf }))).b.leafBuilder.instantiate() === leaf }()"),
			DifferentialValueProbe("Root.mock().b"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenBuilderFunctionNamedApartHidesNoneACloserReads() async throws {
		// `List`'s `next` builds a `Page` inside `Detail`'s `next`, which builds the `List`: the walk names the inner function
		// apart, so `List`'s closer of `detail` reads the outer one. `X`'s `next` is an alike place under the plain name.
		let fixtureFiles = [
			"Root.swift": Self.type("Root", generateMock: true, properties: ["@Instantiated let detail: Detail", "@Instantiated let x: X"]),
			"X.swift": Self.type("X", properties: ["@Instantiated let next: Instantiator<Page>"]),
			"Detail.swift": Self.type("Detail", properties: ["@Instantiated let next: Instantiator<List>"]),
			"List.swift": Self.type("List", properties: ["@Instantiated let detail: Instantiator<Detail>", "@Instantiated let next: Instantiator<Page>"]),
			"Page.swift": """
			@Instantiable
			public final class Page: Instantiable {
			    public init(value: Int = 3) {
			        self.value = value
			    }

			    let value: Int
			}
			""",
		]
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock().detail.next.instantiate().next.instantiate().value"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(x: .init(next: .init(value: 7)))).x.next.instantiate().value"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenTwoEntriesToCycleDifferInCycleArgument() async throws {
		// `F1` builds `x` after `aBuilder` and `F2` before it, so the two entries to the cycle of `A` and `B` differ only in
		// the `x` their calls hand it.
		let fixtureFiles = [
			"Root.swift": Self.type("Root", generateMock: true, properties: ["@Instantiated let f1: F1", "@Instantiated let f2: F2"]),
			"F1.swift": Self.type("F1", properties: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let x: X"]),
			"F2.swift": Self.type("F2", properties: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"]),
			"A.swift": Self.type("A", properties: ["@Received(onlyIfAvailable: true) let x: X?", "@Instantiated let bBuilder: Instantiator<B>"]),
			"B.swift": Self.type("B", properties: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"]),
			"X.swift": Self.type("X", properties: ["@Received(onlyIfAvailable: true) let aBuilder: Instantiator<A>?"]),
		]
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("{ let root = Root.mock(); return root.f1.aBuilder.instantiate().x === root.f1.x }()"),
			DifferentialValueProbe("{ let root = Root.mock(); return root.f2.aBuilder.instantiate().x === root.f2.x }()"),
			DifferentialValueProbe("{ let root = Root.mock(); return root.f1.aBuilder.instantiate().x == nil }()"),
			DifferentialValueProbe("{ let root = Root.mock(); return root.f2.aBuilder.instantiate().x == nil }()"),
		], filesToDelete: &filesToDelete)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The source of a type that takes each of `properties` in its initializer.
	private static func type(_ name: String, kind: String = "final class", generateMock: Bool = false, conformances: String = "", properties: [String]) -> String {
		let labelsAndTypes = properties.map { property -> (label: String, type: String) in
			let declaration = property.components(separatedBy: " let ").last ?? property
			let parts = declaration.components(separatedBy: ": ")
			return (parts[0], parts.dropFirst().joined(separator: ": "))
		}
		let parameters = labelsAndTypes.map { "\($0.label): \($0.type)" }.joined(separator: ", ")
		let assignments = labelsAndTypes.map { "        self.\($0.label) = \($0.label)" }.joined(separator: "\n")
		let declarations = properties.map { "    \($0)" }.joined(separator: "\n")
		return """
		@Instantiable\(generateMock ? "(generateMock: true)" : "")
		public \(kind) \(name): Instantiable\(conformances) {
		    public init(\(parameters)) {
		\(assignments)
		    }

		\(declarations)
		}
		"""
	}
}
