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

/// Acceptance cells of the lazy and cycle kinds, from the frozen mock writer's value tests: roots that enter a mocked
/// lazy cycle, laid out from node records and written by the mock's walk, compiled, and compared by value
/// (`MockKindsAcceptance`). Which edge of the cycle the walk leaves out (`computeCycleEdges`) follows the order of the
/// types' names, so a cell either fixes the naming that picks one edge or names the cycle's types in every order. Labels
/// never change with the names: every cycle link is `nextBuilder`, so only the order of type names moves.
struct SafeDIToolMockKindsLazyCycleValueTests: ~Copyable {
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
	mutating func mock_buildsWalksValues_whenRootEntersCycleAndLeftOutEdgeLeavesTypeThatBuildsBadge() async throws {
		// `Alpha` sorts first, so the depth-first walk starts there and leaves out `Bravo` → `Alpha`: the edge out of
		// the type that builds `Badge`.
		let fixture = Self.twoTypeCycle(entry: "Alpha", badgeHolder: "Bravo")
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: fixture, probes: Self.twoTypeCycleProbes(entry: "Alpha", badgeHolder: "Bravo"), filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenRootEntersCycleAndLeftOutEdgeEntersTypeThatBuildsBadge() async throws {
		// `Alpha` builds `Badge` and sorts first, so the depth-first walk leaves out `Bravo` → `Alpha`: the edge into
		// the type that builds `Badge`.
		let fixture = Self.twoTypeCycle(entry: "Bravo", badgeHolder: "Alpha")
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: fixture, probes: Self.twoTypeCycleProbes(entry: "Bravo", badgeHolder: "Alpha"), filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenThreeTypeCycleIsNamedInEveryOrder() async throws {
		for names in Self.permutations(of: ["Alpha", "Bravo", "Charlie"]) {
			let fixture = Self.threeTypeCycle(names: names)
			try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: fixture, probes: Self.threeTypeCycleProbes(names: names), filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenRootsTreeAndPromotedTreeCloseLazyCycleAroundRedeclaration() async throws {
		// `Feature` promotes `t1Builder` twice, as the `Instantiator<T1>` its promoted `t3Builder`'s tree receives and as the
		// `T1` it receives itself, so the mock binds both apart (`t1Builder_Instantiator__T1`, `t1Builder_T1`). The laid-out
		// mock binds each under its name, or keeps the walk's body: a binding under the bare label redeclares the one the
		// cycle's function rebinds.
		let fixture = [
			"Root.swift": seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let t1Builder: Instantiator<T1>", "@Instantiated let t3Builder: Instantiator<T3>"])
				.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: true)"),
			"Feature.swift": seamFixtureType(named: "Feature", isFinalClass: true, declarations: ["@Received let t3Builder: Instantiator<T3>", "@Received let t1Builder: T1"])
				.replacingOccurrences(of: "@Instantiable", with: "@Instantiable(generateMock: true)"),
			"T3.swift": seamFixtureType(named: "T3", isFinalClass: true, declarations: ["@Instantiated let t0Builder: Instantiator<T0>", "@Received let t1Builder: Instantiator<T1>"]),
			"T0.swift": seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let t1Builder: Instantiator<T1>", "@Instantiated let t3Builder: Instantiator<T3>"]),
			"T1.swift": seamFixtureType(named: "T1", isFinalClass: true, declarations: []),
		]
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: fixture, probes: [
			DifferentialValueProbe("{ let t1 = T1(); return Feature.mock(safeDIOverrides: .init(t1Builder_T1: { t1 })).t1Builder === t1 }()"),
			DifferentialValueProbe("{ let t1 = T1(); return Feature.mock(safeDIOverrides: .init(t1Builder_Instantiator__T1: { t1 })).t3Builder.instantiate().t1Builder.instantiate() === t1 }()"),
			DifferentialValueProbe("{ let t1 = T1(); return Feature.mock(safeDIOverrides: .init(t1Builder_Instantiator__T1: { t1 })).t3Builder.instantiate().t0Builder.instantiate().t3Builder.instantiate().t1Builder.instantiate() === t1 }()"),
			DifferentialValueProbe("{ let t1 = T1(); return Root.mock(safeDIOverrides: .init(t1Builder: { t1 })).t3Builder.instantiate().t1Builder.instantiate() === t1 }()"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenReceiverIsReachedOnlyThroughSecondCycleClosedInsideFirst() async throws {
		// `W` and `U` build each other lazily, and `U` and `P` do too, so `P` closes the second cycle inside the first.
		// Each builder function of the laid-out mock takes the nearest configuration of `W` and `U`; every place reads
		// the override the walk's place reads, and `V` beneath `P` is handed `P`'s `l`.
		let fixture = [
			"Root.swift": seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let l: L", "@Instantiated let wBuilder: Instantiator<W>"])
				.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: true)"),
			"W.swift": seamFixtureType(named: "W", isFinalClass: true, declarations: ["@Instantiated let uBuilder: Instantiator<U>", "@Instantiated let vBuilder: Instantiator<V>"]),
			"U.swift": seamFixtureType(named: "U", isFinalClass: true, declarations: ["@Instantiated let pBuilder: Instantiator<P>", "@Instantiated let wBuilder: Instantiator<W>"]),
			"P.swift": seamFixtureType(named: "P", isFinalClass: true, declarations: ["@Instantiated let l: L", "@Instantiated let uBuilder: Instantiator<U>"]),
			"V.swift": seamFixtureType(named: "V", isFinalClass: true, declarations: ["@Received let l: L"]),
			"L.swift": seamFixtureType(named: "L", isFinalClass: true, declarations: []),
		]
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: fixture, probes: [
			DifferentialValueProbe("{ let l = L(); return Root.mock(safeDIOverrides: .init(l: { l })).wBuilder.instantiate().vBuilder.instantiate().l === l }()"),
			DifferentialValueProbe("{ let v = V(l: L()); return Root.mock(safeDIOverrides: .init(wBuilder: .init(vBuilder: { _ in v }))).wBuilder.instantiate().vBuilder.instantiate() === v }()"),
			DifferentialValueProbe("{ let v = V(l: L()); return Root.mock(safeDIOverrides: .init(wBuilder: .init(vBuilder: { _ in v }))).wBuilder.instantiate().uBuilder.instantiate().wBuilder.instantiate().vBuilder.instantiate() === v }()"),
			DifferentialValueProbe("{ let v = V(l: L()); return Root.mock(safeDIOverrides: .init(wBuilder: .init(vBuilder: { _ in v }))).wBuilder.instantiate().uBuilder.instantiate().pBuilder.instantiate().uBuilder.instantiate().wBuilder.instantiate().vBuilder.instantiate() === v }()"),
			DifferentialValueProbe("{ let p = Root.mock().wBuilder.instantiate().uBuilder.instantiate().pBuilder.instantiate(); return p.uBuilder.instantiate().wBuilder.instantiate().vBuilder.instantiate().l === p.l }()"),
			DifferentialValueProbe("{ let l = L(); return Root.mock(safeDIOverrides: .init(l: { l })).wBuilder.instantiate().uBuilder.instantiate().wBuilder.instantiate().vBuilder.instantiate().l === l }()"),
		], filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWalksValues_whenCycleClosingCallPassesValueMockTakesUnderNameApartFromItsLabel() async throws {
		// No type builds `Mark`, so `Hub.mock()` takes it, and `Hub`, between `screenBuilder` and the `screenBuilder` that
		// closes the cycle on it, declares `mark` again, so the cycle's function takes `mark`. The mock names its own parameter
		// apart from the function's (`mark_Mark`), which the call that closes the cycle reads inside that function.
		let fixture = [
			"Hub.swift": seamFixtureType(named: "Hub", isFinalClass: true, declarations: ["@Instantiated let screenBuilder: Instantiator<Screen>", "@Instantiated let mark: Mark"])
				.replacingOccurrences(of: "@Instantiable", with: "@Instantiable(generateMock: true)"),
			"Screen.swift": seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Instantiated let hubBuilder: Instantiator<Hub>", "@Received let mark: Mark"]),
			"Mark.swift": """
			public final class Mark {
			    public init() {}
			}
			""",
		]
		try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: fixture, probes: [
			DifferentialValueProbe("{ let mark = Mark(); return Hub.mock(mark_Mark: mark).screenBuilder.instantiate().mark === mark }()"),
			DifferentialValueProbe("{ let mark = Mark(); return Hub.mock(mark_Mark: mark).screenBuilder.instantiate().hubBuilder.instantiate().mark === mark }()"),
			DifferentialValueProbe("{ let mark = Mark(); return Hub.mock(mark_Mark: mark).screenBuilder.instantiate().hubBuilder.instantiate().screenBuilder.instantiate().mark === mark }()"),
		], filesToDelete: &filesToDelete)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Every order of `elements`, in a fixed order.
	private static func permutations(of elements: [String]) -> [[String]] {
		guard elements.count > 1 else { return [elements] }
		var result = [[String]]()
		for (index, element) in elements.enumerated() {
			var rest = elements
			rest.remove(at: index)
			for tail in permutations(of: rest) {
				result.append([element] + tail)
			}
		}
		return result
	}

	private static let badge = """
	@Instantiable
	public final class Badge: Instantiable {
	    public init(title: String = "default") {
	        self.title = title
	    }

	    public let title: String
	}
	"""

	private static func root(entry: String) -> String {
		"""
		@Instantiable(generateMock: true)
		public final class Root: Instantiable {
		    public init(entryBuilder: Instantiator<\(entry)>) {
		        self.entryBuilder = entryBuilder
		    }

		    @Instantiated public let entryBuilder: Instantiator<\(entry)>
		}
		"""
	}

	/// A cycle link: `name` builds `next` lazily, and `Badge` too when `buildsBadge`.
	private static func link(_ name: String, next: String, buildsBadge: Bool) -> String {
		if buildsBadge {
			"""
			@Instantiable(generateMock: true)
			public final class \(name): Instantiable {
			    public init(nextBuilder: Instantiator<\(next)>, badge: Badge) {
			        self.nextBuilder = nextBuilder
			        self.badge = badge
			    }

			    @Instantiated public let nextBuilder: Instantiator<\(next)>
			    @Instantiated public let badge: Badge
			}
			"""
		} else {
			"""
			@Instantiable(generateMock: true)
			public final class \(name): Instantiable {
			    public init(nextBuilder: Instantiator<\(next)>) {
			        self.nextBuilder = nextBuilder
			    }

			    @Instantiated public let nextBuilder: Instantiator<\(next)>
			}
			"""
		}
	}

	/// `Root` → `entry` ↔ `badgeHolder` through `Instantiator`s, with `badgeHolder` building `Badge`.
	private static func twoTypeCycle(entry: String, badgeHolder: String) -> [String: String] {
		[
			"Badge.swift": badge,
			"Root.swift": root(entry: entry),
			"\(entry).swift": link(entry, next: badgeHolder, buildsBadge: false),
			"\(badgeHolder).swift": link(badgeHolder, next: entry, buildsBadge: true),
		]
	}

	private static func twoTypeCycleProbes(entry: String, badgeHolder: String) -> [DifferentialValueProbe] {
		[
			DifferentialValueProbe("Root.mock().entryBuilder.instantiate().nextBuilder.instantiate().badge.title"),
			DifferentialValueProbe("Root.mock().entryBuilder.instantiate().nextBuilder.instantiate().nextBuilder.instantiate().nextBuilder.instantiate().badge.title"),
			DifferentialValueProbe("\(badgeHolder).mock(safeDIOverrides: .init(badge: .init(title: \"holder\"))).nextBuilder.instantiate().nextBuilder.instantiate().badge.title"),
			DifferentialValueProbe("\(entry).mock(safeDIOverrides: .init(nextBuilder: .init(badge: .init(title: \"entry\")))).nextBuilder.instantiate().nextBuilder.instantiate().nextBuilder.instantiate().badge.title"),
		]
	}

	/// `Root` → `names[0]` → `names[1]` → `names[2]` → `names[0]` through `Instantiator`s, with `names[1]` building
	/// `Badge`. The roles never move: only which name each role has.
	private static func threeTypeCycle(names: [String]) -> [String: String] {
		[
			"Badge.swift": badge,
			"Root.swift": root(entry: names[0]),
			"\(names[0]).swift": link(names[0], next: names[1], buildsBadge: false),
			"\(names[1]).swift": link(names[1], next: names[2], buildsBadge: true),
			"\(names[2]).swift": link(names[2], next: names[0], buildsBadge: false),
		]
	}

	private static func threeTypeCycleProbes(names: [String]) -> [DifferentialValueProbe] {
		[
			DifferentialValueProbe("Root.mock().entryBuilder.instantiate().nextBuilder.instantiate().badge.title"),
			DifferentialValueProbe("Root.mock().entryBuilder.instantiate().nextBuilder.instantiate().nextBuilder.instantiate().nextBuilder.instantiate().nextBuilder.instantiate().badge.title"),
			DifferentialValueProbe("\(names[1]).mock(safeDIOverrides: .init(badge: .init(title: \"holder\"))).nextBuilder.instantiate().nextBuilder.instantiate().nextBuilder.instantiate().badge.title"),
			DifferentialValueProbe("\(names[0]).mock(safeDIOverrides: .init(nextBuilder: .init(badge: .init(title: \"entry\")))).nextBuilder.instantiate().nextBuilder.instantiate().nextBuilder.instantiate().nextBuilder.instantiate().badge.title"),
		]
	}
}
