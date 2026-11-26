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
import Testing
@testable import SafeDICore
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// A place instantiated only if available (`@Instantiated(onlyIfAvailable: true)`) in a laid out internal mock. Where a
/// declaration fulfills the property, the place's record carries a `nil` alternative (`BuiltPlaceRecord.nilAlternative`):
/// the entry `<binding name>IsUnavailable` beside the place's own field, read where the place is bound. Where nothing
/// fulfills it, the place is written as text, bound from the override `mock()` takes of it, or to `nil`. Each graph's mock
/// is laid out, compiled, and compared by value with the one the walk writes.
///
/// The matrix, a test per cell, each over a constant built in place, one built by a function for a default, and one built
/// by a function for a child where the cell allows: the property on the mocked type; on a type beneath it; inside a
/// `@Sendable` builder function; inside an actor's argument; beneath an `Instantiator`; on a type built at two places of
/// one root; one type instantiated only if available by two types; on the types of a mocked lazy cycle; two places that differ only in the entry they read; a keyword label; a sibling labeled like the entry; an
/// entry set beside an override; and both rows on one type.
struct SafeDIToolMockTypeKeyOnlyIfAvailableTests: ~Copyable {
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
	mutating func mock_buildsWalksValues_whenMockedTypeInstantiatesFulfilledTypesOnlyIfAvailable() async throws {
		// A constant built in place, one built by a function for its default, and one built by a function for its child, each
		// bound to `nil` by its entry alone.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(plain: Plain?, leaf: Leaf?, branch: Branch?) {
			        self.plain = plain
			        self.leaf = leaf
			        self.branch = branch
			    }

			    @Instantiated(onlyIfAvailable: true) let plain: Plain?
			    @Instantiated(onlyIfAvailable: true) let leaf: Leaf?
			    @Instantiated(onlyIfAvailable: true) let branch: Branch?
			}
			""",
			"Plain.swift": Self.plain,
			"Leaf.swift": Self.leaf,
			"Branch.swift": Self.branch,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(plainIsUnavailable: true))"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(leafIsUnavailable: true))"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(branchIsUnavailable: true))"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(plainIsUnavailable: true, leafIsUnavailable: true, branchIsUnavailable: true))"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(leaf: .init(value: 7), branch: .init(plain: { Plain(tag: 5) })))"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenTypeBeneathMockedTypeInstantiatesFulfilledTypesOnlyIfAvailable() async throws {
		// The entries are fields of the configuration of the type that declares the properties, which its function is handed.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(child: Child) {
			        self.child = child
			    }

			    @Instantiated let child: Child
			}
			""",
			"Child.swift": """
			@Instantiable
			public final class Child: Instantiable {
			    public init(plain: Plain?, leaf: Leaf?, branch: Branch?) {
			        self.plain = plain
			        self.leaf = leaf
			        self.branch = branch
			    }

			    @Instantiated(onlyIfAvailable: true) let plain: Plain?
			    @Instantiated(onlyIfAvailable: true) let leaf: Leaf?
			    @Instantiated(onlyIfAvailable: true) let branch: Branch?
			}
			""",
			"Plain.swift": Self.plain,
			"Leaf.swift": Self.leaf,
			"Branch.swift": Self.branch,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(child: .init(plainIsUnavailable: true)))"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(child: .init(leafIsUnavailable: true)))"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(child: .init(branchIsUnavailable: true)))"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(child: .init(leaf: .init(value: 7), leafIsUnavailable: false, branch: .init(plain: { Plain(tag: 5) }))))"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenTypeBuiltInsideSendableFunctionInstantiatesFulfilledTypesOnlyIfAvailable() async throws {
		// The walk reads each entry from a local bound before the `@Sendable` function; the layout reads it from the configuration
		// the function is handed.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable, Sendable {
			    public init(childBuilder: SendableInstantiator<Child>) {
			        self.childBuilder = childBuilder
			    }

			    @Instantiated let childBuilder: SendableInstantiator<Child>
			}
			""",
			"Child.swift": """
			@Instantiable
			public final class Child: Instantiable, Sendable {
			    public init(plain: Plain?, leaf: Leaf?, branch: Branch?) {
			        self.plain = plain
			        self.leaf = leaf
			        self.branch = branch
			    }

			    @Instantiated(onlyIfAvailable: true) let plain: Plain?
			    @Instantiated(onlyIfAvailable: true) let leaf: Leaf?
			    @Instantiated(onlyIfAvailable: true) let branch: Branch?
			}
			""",
			"Plain.swift": Self.sendablePlain,
			"Leaf.swift": Self.sendableLeaf,
			"Branch.swift": Self.sendableBranch,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock().childBuilder.instantiate()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(childBuilder: .init(plainIsUnavailable: true))).childBuilder.instantiate()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(childBuilder: .init(leafIsUnavailable: true))).childBuilder.instantiate()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(childBuilder: .init(branchIsUnavailable: true))).childBuilder.instantiate()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(childBuilder: .init(leaf: .init(value: 7), branch: .init(plain: { Plain(tag: 5) })))).childBuilder.instantiate()"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenTypeBuiltAsActorsArgumentInstantiatesFulfilledTypesOnlyIfAvailable() async throws {
		// A type built as an actor’s argument reads its overrides as a `@Sendable` function does.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(store: Store) {
			        self.store = store
			    }

			    @Instantiated let store: Store
			}
			""",
			"Store.swift": """
			@Instantiable
			public actor Store: Instantiable {
			    public init(child: Child) {
			        self.child = child
			    }

			    @Instantiated let child: Child
			}
			""",
			"Child.swift": """
			@Instantiable
			public final class Child: Instantiable, Sendable {
			    public init(plain: Plain?, leaf: Leaf?, branch: Branch?) {
			        self.plain = plain
			        self.leaf = leaf
			        self.branch = branch
			    }

			    @Instantiated(onlyIfAvailable: true) let plain: Plain?
			    @Instantiated(onlyIfAvailable: true) let leaf: Leaf?
			    @Instantiated(onlyIfAvailable: true) let branch: Branch?
			}
			""",
			"Plain.swift": Self.sendablePlain,
			"Leaf.swift": Self.sendableLeaf,
			"Branch.swift": Self.sendableBranch,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(store: .init(child: .init(plainIsUnavailable: true))))"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(store: .init(child: .init(leafIsUnavailable: true))))"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(store: .init(child: .init(branchIsUnavailable: true))))"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenTypeBeneathInstantiatorInstantiatesFulfilledTypesOnlyIfAvailable() async throws {
		// Each call of the instantiator reads the entries again.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(childBuilder: Instantiator<Child>) {
			        self.childBuilder = childBuilder
			    }

			    @Instantiated let childBuilder: Instantiator<Child>
			}
			""",
			"Child.swift": """
			@Instantiable
			public final class Child: Instantiable {
			    public init(plain: Plain?, leaf: Leaf?, branch: Branch?) {
			        self.plain = plain
			        self.leaf = leaf
			        self.branch = branch
			    }

			    @Instantiated(onlyIfAvailable: true) let plain: Plain?
			    @Instantiated(onlyIfAvailable: true) let leaf: Leaf?
			    @Instantiated(onlyIfAvailable: true) let branch: Branch?
			}
			""",
			"Plain.swift": Self.plain,
			"Leaf.swift": Self.leaf,
			"Branch.swift": Self.branch,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock().childBuilder.instantiate()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(childBuilder: .init(plainIsUnavailable: true))).childBuilder.instantiate()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(childBuilder: .init(leafIsUnavailable: true))).childBuilder.instantiate()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(childBuilder: .init(branchIsUnavailable: true))).childBuilder.instantiate()"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenTypeInstantiatingFulfilledTypesOnlyIfAvailableIsBuiltAtTwoPlaces() async throws {
		// Both places of `Child` call one function, and each is handed its own configuration, whose entries it reads.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(first: First, second: Second) {
			        self.first = first
			        self.second = second
			    }

			    @Instantiated let first: First
			    @Instantiated let second: Second
			}
			""",
			"First.swift": """
			@Instantiable
			public final class First: Instantiable {
			    public init(child: Child) {
			        self.child = child
			    }

			    @Instantiated let child: Child
			}
			""",
			"Second.swift": """
			@Instantiable
			public final class Second: Instantiable {
			    public init(child: Child) {
			        self.child = child
			    }

			    @Instantiated let child: Child
			}
			""",
			"Child.swift": """
			@Instantiable
			public final class Child: Instantiable {
			    public init(plain: Plain?, leaf: Leaf?, branch: Branch?) {
			        self.plain = plain
			        self.leaf = leaf
			        self.branch = branch
			    }

			    @Instantiated(onlyIfAvailable: true) let plain: Plain?
			    @Instantiated(onlyIfAvailable: true) let leaf: Leaf?
			    @Instantiated(onlyIfAvailable: true) let branch: Branch?
			}
			""",
			"Plain.swift": Self.plain,
			"Leaf.swift": Self.leaf,
			"Branch.swift": Self.branch,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(first: .init(child: .init(leafIsUnavailable: true))))"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(second: .init(child: .init(branchIsUnavailable: true))))"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(first: .init(child: .init(plainIsUnavailable: true)), second: .init(child: .init(leafIsUnavailable: true))))"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenTwoTypesInstantiateOneTypeOnlyIfAvailable() async throws {
		// The walk meets `Branch`'s subtree twice and takes the first meeting's records at the second, whose own place still
		// reads the entry of its own parent's configuration.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(first: First, second: Second) {
			        self.first = first
			        self.second = second
			    }

			    @Instantiated let first: First
			    @Instantiated let second: Second
			}
			""",
			"First.swift": """
			@Instantiable
			public final class First: Instantiable {
			    public init(branch: Branch?) {
			        self.branch = branch
			    }

			    @Instantiated(onlyIfAvailable: true) let branch: Branch?
			}
			""",
			"Second.swift": """
			@Instantiable
			public final class Second: Instantiable {
			    public init(branch: Branch?) {
			        self.branch = branch
			    }

			    @Instantiated(onlyIfAvailable: true) let branch: Branch?
			}
			""",
			"Plain.swift": Self.plain,
			"Branch.swift": Self.branch,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(first: .init(branchIsUnavailable: true)))"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(second: .init(branchIsUnavailable: true)))"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(first: .init(branch: .init(plain: { Plain(tag: 5) })), second: .init(branch: .init(plain: { Plain(tag: 6) }), branchIsUnavailable: true)))"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenTypesOfMockedLazyCycleInstantiateTypesOnlyIfAvailable() async throws {
		// Which edge of the cycle is left out follows the types' names. A place beneath it that the walk always builds, reading
		// no entry, reads in the layout the entry of the configuration its parent is handed: the nearest one of its type
		// above, or one built afresh, whose entry is `false`. So each type keeps one function, on every lap.
		let fixtureFiles = [
			"Alpha.swift": """
			@Instantiable(generateMock: true)
			public final class Alpha: Instantiable {
			    public init(bravoBuilder: Instantiator<Bravo>, plain: Plain?, holder: Holder) {
			        self.bravoBuilder = bravoBuilder
			        self.plain = plain
			        self.holder = holder
			    }

			    @Instantiated public let bravoBuilder: Instantiator<Bravo>
			    @Instantiated(onlyIfAvailable: true) public let plain: Plain?
			    @Instantiated public let holder: Holder
			}
			""",
			"Holder.swift": """
			@Instantiable
			public final class Holder: Instantiable {
			    public init(leaf: Leaf?) {
			        self.leaf = leaf
			    }

			    @Instantiated(onlyIfAvailable: true) public let leaf: Leaf?
			}
			""",
			"Bravo.swift": """
			@Instantiable(generateMock: true)
			public final class Bravo: Instantiable {
			    public init(alphaBuilder: Instantiator<Alpha>, leaf: Leaf?) {
			        self.alphaBuilder = alphaBuilder
			        self.leaf = leaf
			    }

			    @Instantiated public let alphaBuilder: Instantiator<Alpha>
			    @Instantiated(onlyIfAvailable: true) public let leaf: Leaf?
			}
			""",
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(alphaBuilder: Instantiator<Alpha>) {
			        self.alphaBuilder = alphaBuilder
			    }

			    @Instantiated public let alphaBuilder: Instantiator<Alpha>
			}
			""",
			"Plain.swift": Self.plain,
			"Leaf.swift": Self.leaf,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes.sorted() == ["Alpha: laidOut", "Bravo: laidOut", "Root: laidOut"])
		// `Holder` is built where an override reaches it and where none does, by one function.
		for file in ["Alpha+SafeDIMock.swift", "Bravo+SafeDIMock.swift", "Root+SafeDIMock.swift"] {
			#expect((mocks.laidOut.mockFiles[file] ?? "").components(separatedBy: "func __safeDI_holder(").count == 2, "\(file)")
		}
		let lapTwo = ".alphaBuilder.instantiate().bravoBuilder.instantiate()"
		func laps(_ mock: String) -> String {
			"{ let alpha = \(mock); let bravo = alpha.bravoBuilder.instantiate(); let bravoAgain = bravo\(lapTwo); return [\"\\(alpha.plain?.tag ?? 0)\", \"\\(alpha.holder.leaf?.value ?? 0)\", \"\\(bravoAgain.alphaBuilder.instantiate().holder.leaf?.value ?? 0)\", \"\\(bravo.leaf?.value ?? 0)\", \"\\(bravo.alphaBuilder.instantiate().plain?.tag ?? 0)\", \"\\(bravoAgain.leaf?.value ?? 0)\", \"\\(bravoAgain\(lapTwo).leaf?.value ?? 0)\"] }()"
		}
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe(laps("Root.mock().alphaBuilder.instantiate()")),
			DifferentialValueProbe(laps("Root.mock(safeDIOverrides: .init(alphaBuilder: .init(plainIsUnavailable: true))).alphaBuilder.instantiate()")),
			DifferentialValueProbe(laps("Root.mock(safeDIOverrides: .init(alphaBuilder: .init(bravoBuilder: .init(leaf: .init(value: 7), leafIsUnavailable: true)))).alphaBuilder.instantiate()")),
			DifferentialValueProbe(laps("Root.mock(safeDIOverrides: .init(alphaBuilder: .init(bravoBuilder: .init(leaf: .init(value: 7))))).alphaBuilder.instantiate()")),
			DifferentialValueProbe(laps("Alpha.mock()")),
			DifferentialValueProbe(laps("Alpha.mock(safeDIOverrides: .init(plainIsUnavailable: true))")),
			DifferentialValueProbe(laps("Alpha.mock(safeDIOverrides: .init(holder: .init(leaf: .init(value: 7))))")),
			DifferentialValueProbe(laps("Alpha.mock(safeDIOverrides: .init(holder: .init(leafIsUnavailable: true)))")),
			DifferentialValueProbe(laps("Root.mock(safeDIOverrides: .init(alphaBuilder: .init(holder: .init(leafIsUnavailable: true)))).alphaBuilder.instantiate()")),
			DifferentialValueProbe(laps("Alpha.mock(safeDIOverrides: .init(bravoBuilder: .init(leafIsUnavailable: true)))")),
			DifferentialValueProbe(laps("Bravo.mock().alphaBuilder.instantiate()")),
			DifferentialValueProbe(laps("Bravo.mock(safeDIOverrides: .init(alphaBuilder: .init(plainIsUnavailable: true), leafIsUnavailable: true)).alphaBuilder.instantiate()")),
			DifferentialValueProbe("Bravo.mock(safeDIOverrides: .init(leafIsUnavailable: true)).leaf?.value ?? 0"),
		])
	}

	@Test
	mutating func mock_buildsTypeByOneFunction_whenItInstantiatesTypeOnlyIfAvailableWhereAnOverrideReachesItAndWhereNoneDoes() async throws {
		// `W` and `U` instantiate one another, and so do `U` and `P`, and a mock's configurations leave one edge of each
		// cycle out, so no override reaches the `P` beneath both: the walk always builds its `leaf`, reading no entry. An
		// override reaches the `P` the root instantiates, whose `leaf` reads its entry. The place beneath the edges records
		// the entry too, of the configuration built afresh its `P` is handed, so one function builds `P` at both.
		let fixtureFiles = [
			"P.swift": """
			@Instantiable
			public final class P: Instantiable {
			    public init(leaf: Leaf?, uBuilder: Instantiator<U>) {
			        self.leaf = leaf
			        self.uBuilder = uBuilder
			    }

			    @Instantiated(onlyIfAvailable: true) public let leaf: Leaf?
			    @Instantiated public let uBuilder: Instantiator<U>
			}
			""",
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(pBuilder: Instantiator<P>, wBuilder: Instantiator<W>) {
			        self.pBuilder = pBuilder
			        self.wBuilder = wBuilder
			    }

			    @Instantiated public let pBuilder: Instantiator<P>
			    @Instantiated public let wBuilder: Instantiator<W>
			}
			""",
			"U.swift": """
			@Instantiable
			public final class U: Instantiable {
			    public init(pBuilder: Instantiator<P>, wBuilder: Instantiator<W>) {
			        self.pBuilder = pBuilder
			        self.wBuilder = wBuilder
			    }

			    @Instantiated public let pBuilder: Instantiator<P>
			    @Instantiated public let wBuilder: Instantiator<W>
			}
			""",
			"W.swift": """
			@Instantiable
			public final class W: Instantiable {
			    public init(uBuilder: Instantiator<U>) {
			        self.uBuilder = uBuilder
			    }

			    @Instantiated public let uBuilder: Instantiator<U>
			}
			""",
			"Leaf.swift": Self.leaf,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)
		let laidOut = mocks.laidOut.mockFiles["Root+SafeDIMock.swift"] ?? ""

		#expect(mocks.outcomes == ["Root: laidOut"])
		#expect(laidOut.components(separatedBy: ") -> P {").count == 2, "Unexpected output \(laidOut)")
		let beneathEdges = ".wBuilder.instantiate().uBuilder.instantiate().pBuilder.instantiate().leaf?.value ?? 0"
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock().pBuilder.instantiate().leaf?.value ?? 0"),
			DifferentialValueProbe("Root.mock()\(beneathEdges)"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(pBuilder: .init(leafIsUnavailable: true))).pBuilder.instantiate().leaf?.value ?? 0"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(pBuilder: .init(leafIsUnavailable: true)))\(beneathEdges)"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(pBuilder: .init(leaf: .init(value: 7))))\(beneathEdges)"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(pBuilder: .init(leaf: .init(value: 7)))).pBuilder.instantiate().uBuilder.instantiate().wBuilder.instantiate().uBuilder.instantiate().pBuilder.instantiate().leaf?.value ?? 0"),
		])
	}

	@Test
	mutating func mock_bindsEachPlaceToNilByItsOwnEntry_whenTwoPlacesDifferOnlyInTheEntryTheyRead() async throws {
		// The two places of `leaf` record alike but for the entry each reads: the root’s reads `mock()`’s overrides, which every
		// function can read, and `Child`’s its own configuration. With the entry out of the key that makes alike places one node
		// (`MockLowering.SharedRecordKey`), one place would read the other’s entry.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(child: Child, leaf: Leaf?) {
			        self.child = child
			        self.leaf = leaf
			    }

			    @Instantiated let child: Child
			    @Instantiated(onlyIfAvailable: true) let leaf: Leaf?
			}
			""",
			"Child.swift": """
			@Instantiable
			public final class Child: Instantiable {
			    public init(leaf: Leaf?) {
			        self.leaf = leaf
			    }

			    @Instantiated(onlyIfAvailable: true) let leaf: Leaf?
			}
			""",
			"Leaf.swift": Self.leaf,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(leafIsUnavailable: true))"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(child: .init(leafIsUnavailable: true)))"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(child: .init(leafIsUnavailable: true), leafIsUnavailable: true))"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenPropertyInstantiatedOnlyIfAvailableIsLabeledWithKeyword() async throws {
		// The binding is spelled with backticks, and the entry’s name joins the label without them.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(`default`: Plain?, `for`: Leaf?) {
			        self.`default` = `default`
			        self.`for` = `for`
			    }

			    @Instantiated(onlyIfAvailable: true) let `default`: Plain?
			    @Instantiated(onlyIfAvailable: true) let `for`: Leaf?
			}
			""",
			"Plain.swift": Self.plain,
			"Leaf.swift": Self.leaf,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(defaultIsUnavailable: true))"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(forIsUnavailable: true))"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenSiblingIsLabeledAsEntry() async throws {
		// The entry is named apart from the sibling, `leafIsUnavailable_`, and the record reads it under that name.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(leaf: Leaf?, leafIsUnavailable: Plain) {
			        self.leaf = leaf
			        self.leafIsUnavailable = leafIsUnavailable
			    }

			    @Instantiated(onlyIfAvailable: true) let leaf: Leaf?
			    @Instantiated let leafIsUnavailable: Plain
			}
			""",
			"Plain.swift": Self.plain,
			"Leaf.swift": Self.leaf,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(leafIsUnavailable_: true))"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(leafIsUnavailable_: true, leafIsUnavailable: { Plain(tag: 5) }))"),
		])
	}

	@Test
	mutating func mock_buildsNothingOfPlace_whenEntryIsSetBesideAnOverride() async throws {
		// The entry is read before the override: neither the override’s closure nor anything beneath the place is built.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(child: Child, plain: Plain?, leaf: Leaf?, branch: Branch?) {
			        self.child = child
			        self.plain = plain
			        self.leaf = leaf
			        self.branch = branch
			    }

			    @Instantiated let child: Child
			    @Instantiated(onlyIfAvailable: true) let plain: Plain?
			    @Instantiated(onlyIfAvailable: true) let leaf: Leaf?
			    @Instantiated(onlyIfAvailable: true) let branch: Branch?
			}
			""",
			"Child.swift": """
			@Instantiable
			public final class Child: Instantiable {
			    public init(plain: Plain?, leaf: Leaf?, branch: Branch?) {
			        self.plain = plain
			        self.leaf = leaf
			        self.branch = branch
			    }

			    @Instantiated(onlyIfAvailable: true) let plain: Plain?
			    @Instantiated(onlyIfAvailable: true) let leaf: Leaf?
			    @Instantiated(onlyIfAvailable: true) let branch: Branch?
			}
			""",
			"Plain.swift": Self.plain,
			"Leaf.swift": Self.leaf,
			"Branch.swift": Self.branch,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("{ var calls = [String](); let root = Root.mock(safeDIOverrides: .init(child: .init(plain: { calls.append(\"child.plain\"); return Plain(tag: 5) }, plainIsUnavailable: true, branch: .init(plain: { calls.append(\"child.branch.plain\"); return Plain(tag: 6) }) { plain in calls.append(\"child.branch\"); return Branch(plain: plain) }, branchIsUnavailable: true), plain: { calls.append(\"plain\"); return Plain(tag: 7) }, plainIsUnavailable: true, branch: .init(plain: { calls.append(\"branch.plain\"); return Plain(tag: 8) }) { plain in calls.append(\"branch\"); return Branch(plain: plain) }, branchIsUnavailable: true)); return \"\\(calls) \\(root.plain == nil) \\(root.branch == nil) \\(root.child.plain == nil) \\(root.child.branch == nil)\" }()"),
			DifferentialValueProbe("{ var calls = [String](); let root = Root.mock(safeDIOverrides: .init(child: .init(plain: { calls.append(\"child.plain\"); return Plain(tag: 5) }, branch: .init(plain: { calls.append(\"child.branch.plain\"); return Plain(tag: 6) }) { plain in calls.append(\"child.branch\"); return Branch(plain: plain) }), plain: { calls.append(\"plain\"); return Plain(tag: 7) }, branch: .init(plain: { calls.append(\"branch.plain\"); return Plain(tag: 8) }) { plain in calls.append(\"branch\"); return Branch(plain: plain) })); return \"\\(calls) \\(root.plain?.tag ?? 0) \\(root.branch?.plain.tag ?? 0) \\(root.child.plain?.tag ?? 0) \\(root.child.branch?.plain.tag ?? 0)\" }()"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenMockedTypeInstantiatesTypeOnlyIfAvailableThatNothingFulfills() async throws {
		// The property is bound from the override `mock()` takes of it, a place written as text.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(missing: Missing?, branch: Branch) {
			        self.missing = missing
			        self.branch = branch
			    }

			    @Instantiated(onlyIfAvailable: true) let missing: Missing?
			    @Instantiated let branch: Branch
			}
			""",
			"Missing.swift": Self.missing,
			"Plain.swift": Self.plain,
			"Branch.swift": Self.branch,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(missing: Missing(tag: 4)))"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenTypesBeneathMockedTypeInstantiateTypeOnlyIfAvailableThatNothingFulfills() async throws {
		// Each function that binds the property reads the one override `mock()` takes of it, and a type beneath receives it.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(first: First, second: Second) {
			        self.first = first
			        self.second = second
			    }

			    @Instantiated let first: First
			    @Instantiated let second: Second
			}
			""",
			"First.swift": """
			@Instantiable
			public final class First: Instantiable {
			    public init(child: Child) {
			        self.child = child
			    }

			    @Instantiated let child: Child
			}
			""",
			"Second.swift": """
			@Instantiable
			public final class Second: Instantiable {
			    public init(child: Child) {
			        self.child = child
			    }

			    @Instantiated let child: Child
			}
			""",
			"Child.swift": """
			@Instantiable
			public final class Child: Instantiable {
			    public init(missing: Missing?, receiver: Receiver) {
			        self.missing = missing
			        self.receiver = receiver
			    }

			    @Instantiated(onlyIfAvailable: true) let missing: Missing?
			    @Instantiated let receiver: Receiver
			}
			""",
			"Receiver.swift": """
			@Instantiable
			public final class Receiver: Instantiable {
			    public init(missing: Missing?) {
			        self.missing = missing
			    }

			    @Received(onlyIfAvailable: true) let missing: Missing?
			}
			""",
			"Missing.swift": Self.missing,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(missing: Missing(tag: 4)))"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenTypeBuiltInsideSendableFunctionInstantiatesTypeOnlyIfAvailableThatNothingFulfills() async throws {
		// Inside a `@Sendable` function, which could not capture the override, the property is `nil`.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable, Sendable {
			    public init(childBuilder: SendableInstantiator<Child>) {
			        self.childBuilder = childBuilder
			    }

			    @Instantiated let childBuilder: SendableInstantiator<Child>
			}
			""",
			"Child.swift": """
			@Instantiable
			public final class Child: Instantiable, Sendable {
			    public init(missing: Missing?, leaf: Leaf) {
			        self.missing = missing
			        self.leaf = leaf
			    }

			    @Instantiated(onlyIfAvailable: true) let missing: Missing?
			    @Instantiated let leaf: Leaf
			}
			""",
			"Missing.swift": Self.missing,
			"Leaf.swift": Self.sendableLeaf,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock().childBuilder.instantiate()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(childBuilder: .init(leaf: .init(value: 7)))).childBuilder.instantiate()"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenTypeBuiltAsActorsArgumentOrBeneathInstantiatorInstantiatesTypeOnlyIfAvailableThatNothingFulfills() async throws {
		// The binding is written where the walk writes it, in the function of the type that declares the property.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(store: Store, childBuilder: Instantiator<Child>) {
			        self.store = store
			        self.childBuilder = childBuilder
			    }

			    @Instantiated let store: Store
			    @Instantiated let childBuilder: Instantiator<Child>
			}
			""",
			"Store.swift": """
			@Instantiable
			public actor Store: Instantiable {
			    public init(child: Child) {
			        self.child = child
			    }

			    @Instantiated let child: Child
			}
			""",
			"Child.swift": """
			@Instantiable
			public final class Child: Instantiable, Sendable {
			    public init(missing: Missing?, leaf: Leaf) {
			        self.missing = missing
			        self.leaf = leaf
			    }

			    @Instantiated(onlyIfAvailable: true) let missing: Missing?
			    @Instantiated let leaf: Leaf
			}
			""",
			"Missing.swift": Self.missing,
			"Leaf.swift": Self.sendableLeaf,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock()"),
			DifferentialValueProbe("Root.mock().childBuilder.instantiate()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(missing: Missing(tag: 4))).childBuilder.instantiate()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(missing: Missing(tag: 4)))"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenOneTypeInstantiatesFulfilledAndUnfulfilledTypesOnlyIfAvailable() async throws {
		// Both rows on one type, at the root and beneath it: one property bound from the override, one built unless its entry is set.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(child: Child, missing: Missing?, leaf: Leaf?) {
			        self.child = child
			        self.missing = missing
			        self.leaf = leaf
			    }

			    @Instantiated let child: Child
			    @Instantiated(onlyIfAvailable: true) let missing: Missing?
			    @Instantiated(onlyIfAvailable: true) let leaf: Leaf?
			}
			""",
			"Child.swift": """
			@Instantiable
			public final class Child: Instantiable {
			    public init(missing: Missing?, leaf: Leaf?, plain: Plain?) {
			        self.missing = missing
			        self.leaf = leaf
			        self.plain = plain
			    }

			    @Instantiated(onlyIfAvailable: true) let missing: Missing?
			    @Instantiated(onlyIfAvailable: true) let leaf: Leaf?
			    @Instantiated(onlyIfAvailable: true) let plain: Plain?
			}
			""",
			"Missing.swift": Self.missing,
			"Plain.swift": Self.plain,
			"Leaf.swift": Self.leaf,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock()"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(missing: Missing(tag: 4)))"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(leafIsUnavailable: true))"),
			DifferentialValueProbe("Root.mock(safeDIOverrides: .init(child: .init(leafIsUnavailable: true, plainIsUnavailable: true), missing: Missing(tag: 4)))"),
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Root`'s mock as the type key lays it out, with its layout outcome, and as the walk writes it.
	private mutating func generatedMocks(of fixtureFiles: [String: String]) async throws -> (laidOut: TestOutput, walk: TestOutput, outcomes: [String]) {
		let (outcomeStream, outcomeContinuation) = AsyncStream.makeStream(of: String.self)
		var filesToDelete = filesToDelete
		let laidOut = try await MockLowering.$typeKeyLayoutObserver.withValue({ mockedType, outcome in outcomeContinuation.yield("\(mockedType): \(outcome)") }) {
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		outcomeContinuation.finish()
		var outcomes = [String]()
		for await outcome in outcomeStream {
			outcomes.append(outcome)
		}
		let walk = try await MockLowering.$laysOutWithTypeKey.withValue(false) {
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		self.filesToDelete = filesToDelete
		return (laidOut, walk, outcomes)
	}

	/// Compares what the laid-out mock builds for `probes` with what the walk's builds, the walk being the known-right path.
	private mutating func expectLaidOutValuesEqualWalks(
		_ mocks: (laidOut: TestOutput, walk: TestOutput, outcomes: [String]),
		fixtureFiles: [String: String],
		probes: [DifferentialValueProbe],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(mocks.laidOut.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(mocks.walk.generatedFiles)),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	private static let plain = """
	@Instantiable
	public final class Plain: Instantiable {
	    public init() {
	        tag = 1
	    }

	    public init(tag: Int) {
	        self.tag = tag
	    }

	    let tag: Int
	}
	"""

	private static let leaf = """
	@Instantiable
	public final class Leaf: Instantiable {
	    public init(value: Int = 3) {
	        self.value = value
	    }

	    let value: Int
	}
	"""

	private static let branch = """
	@Instantiable
	public final class Branch: Instantiable {
	    public init(plain: Plain) {
	        self.plain = plain
	    }

	    @Instantiated let plain: Plain
	}
	"""

	private static let sendablePlain = """
	@Instantiable
	public struct Plain: Instantiable, Sendable {
	    public init() {
	        tag = 1
	    }

	    public init(tag: Int) {
	        self.tag = tag
	    }

	    let tag: Int
	}
	"""

	private static let sendableLeaf = """
	@Instantiable
	public struct Leaf: Instantiable, Sendable {
	    public init(value: Int = 3) {
	        self.value = value
	    }

	    let value: Int
	}
	"""

	private static let sendableBranch = """
	@Instantiable
	public struct Branch: Instantiable, Sendable {
	    public init(plain: Plain) {
	        self.plain = plain
	    }

	    @Instantiated let plain: Plain
	}
	"""

	private static let missing = """
	public struct Missing: Sendable {
	    public init(tag: Int) {
	        self.tag = tag
	    }

	    let tag: Int
	}
	"""
}
