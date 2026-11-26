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

/// A builder function of a laid out mock takes its type's configuration under a name made from the type
/// (`MockLowering.ConfigurationParameterNames`). Each graph here holds a type whose name does not spell an identifier as
/// it stands, or two declarations whose generated names would meet, and its mock is compiled and compared by value with
/// the one the walk writes.
struct SafeDIToolMockTypeKeyConfigurationNameTests: ~Copyable {
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
	mutating func mock_buildsWalksValues_whenConfiguredTypeIsNamedWithKeyword() async throws {
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(a: A, b: `default`) {
			        self.a = a
			        self.b = b
			    }

			    @Instantiated let a: A
			    @Instantiated let b: `default`
			}
			""",
			"A.swift": """
			@Instantiable
			public final class A: Instantiable {
			    public init(b: `default`) {
			        self.b = b
			    }

			    @Instantiated let b: `default`
			}
			""",
			"Default.swift": """
			@Instantiable
			public final class `default`: Instantiable {
			    public init(leaf: Leaf) {
			        self.leaf = leaf
			    }

			    @Instantiated let leaf: Leaf
			}
			""",
			"Leaf.swift": Self.leaf,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock().b.leaf.value"),
			DifferentialValueProbe("{ let root = Root.mock(safeDIOverrides: .init(a: .init(b: .init(leaf: .init(value: 7))))); return [root.a.b.leaf.value, root.b.leaf.value] }()"),
			DifferentialValueProbe("{ let root = Root.mock(safeDIOverrides: .init(b: .init(leaf: .init(value: 5)))); return [root.a.b.leaf.value, root.b.leaf.value] }()"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenConfiguredTypeIsNamedWithRawIdentifier() async throws {
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(a: A, screen: `my screen`) {
			        self.a = a
			        self.screen = screen
			    }

			    @Instantiated let a: A
			    @Instantiated let screen: `my screen`
			}
			""",
			"A.swift": """
			@Instantiable
			public final class A: Instantiable {
			    public init(screen: `my screen`) {
			        self.screen = screen
			    }

			    @Instantiated let screen: `my screen`
			}
			""",
			"MyScreen.swift": """
			@Instantiable
			public final class `my screen`: Instantiable {
			    public init(leaf: Leaf) {
			        self.leaf = leaf
			    }

			    @Instantiated let leaf: Leaf
			}
			""",
			"Leaf.swift": Self.leaf,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock().screen.leaf.value"),
			DifferentialValueProbe("{ let root = Root.mock(safeDIOverrides: .init(a: .init(screen: .init(leaf: .init(value: 7))))); return [root.a.screen.leaf.value, root.screen.leaf.value] }()"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenConfiguredTypeIsNestedAndNamedWithKeyword() async throws {
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(a: A, b: Networking.`default`) {
			        self.a = a
			        self.b = b
			    }

			    @Instantiated let a: A
			    @Instantiated let b: Networking.`default`
			}
			""",
			"A.swift": """
			@Instantiable
			public final class A: Instantiable {
			    public init(b: Networking.`default`) {
			        self.b = b
			    }

			    @Instantiated let b: Networking.`default`
			}
			""",
			"Networking.swift": """
			public enum Networking {
			    @Instantiable
			    public final class `default`: Instantiable {
			        public init(leaf: Leaf) {
			            self.leaf = leaf
			        }

			        @Instantiated let leaf: Leaf
			    }
			}
			""",
			"Leaf.swift": Self.leaf,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock().b.leaf.value"),
			DifferentialValueProbe("{ let root = Root.mock(safeDIOverrides: .init(a: .init(b: .init(leaf: .init(value: 7))))); return [root.a.b.leaf.value, root.b.leaf.value] }()"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenConfiguredTypesGenericArgumentIsNamedWithKeyword() async throws {
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(a: A, box: Box<`default`>) {
			        self.a = a
			        self.box = box
			    }

			    @Instantiated let a: A
			    @Instantiated let box: Box<`default`>
			}
			""",
			"A.swift": """
			@Instantiable
			public final class A: Instantiable {
			    public init(box: Box<`default`>) {
			        self.box = box
			    }

			    @Instantiated let box: Box<`default`>
			}
			""",
			"Box.swift": """
			public struct `default` {}

			public final class Box<Element> {
			    init(count: Int) {
			        self.count = count
			    }

			    let count: Int
			}

			@Instantiable
			extension Box: Instantiable {
			    public static func instantiate(count: Int = 3) -> Box<`default`> {
			        .init(count: count)
			    }
			}
			""",
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock().box.count"),
			DifferentialValueProbe("{ let root = Root.mock(safeDIOverrides: .init(a: .init(box: .init(count: 7)))); return [root.a.box.count, root.box.count] }()"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenTypeNamedWithKeywordInstantiatesItselfLazily() async throws {
		// The builder function of `default` takes the nearest configuration of its own type beside its own.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(b: B) {
			        self.b = b
			    }

			    @Instantiated let b: B
			}
			""",
			"B.swift": """
			@Instantiable
			public final class B: Instantiable {
			    public init(nextBuilder: Instantiator<`default`>) {
			        self.nextBuilder = nextBuilder
			    }

			    @Instantiated let nextBuilder: Instantiator<`default`>
			}
			""",
			"Default.swift": """
			@Instantiable
			public final class `default`: Instantiable {
			    public init(leaf: Leaf, bBuilder: Instantiator<B>) {
			        self.leaf = leaf
			        self.bBuilder = bBuilder
			    }

			    @Instantiated let leaf: Leaf
			    @Instantiated let bBuilder: Instantiator<B>
			}
			""",
			"Leaf.swift": Self.leaf,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock().b.nextBuilder.instantiate().bBuilder.instantiate().nextBuilder.instantiate().leaf.value"),
			DifferentialValueProbe("{ let first = Root.mock(safeDIOverrides: .init(b: .init(nextBuilder: .init(leaf: .init(value: 7))))).b.nextBuilder.instantiate(); return [first.leaf.value, first.bBuilder.instantiate().nextBuilder.instantiate().leaf.value] }()"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenTypeNamedWithRawIdentifierIsBuiltAgainByTypeItInstantiatesLazily() async throws {
		// `b screen` instantiates `a screen` again lazily, so its builder function takes `a screen`'s nearest configuration,
		// under a name joined from the name `a screen`'s own function takes its configuration under, which has backticks.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(a: `a screen`) {
			        self.a = a
			    }

			    @Instantiated let a: `a screen`
			}
			""",
			"AScreen.swift": """
			@Instantiable
			public final class `a screen`: Instantiable {
			    public init(bBuilder: Instantiator<`b screen`>) {
			        self.bBuilder = bBuilder
			    }

			    @Instantiated let bBuilder: Instantiator<`b screen`>
			}
			""",
			"BScreen.swift": """
			@Instantiable
			public final class `b screen`: Instantiable {
			    public init(leaf: Leaf, aBuilder: Instantiator<`a screen`>) {
			        self.leaf = leaf
			        self.aBuilder = aBuilder
			    }

			    @Instantiated let leaf: Leaf
			    @Instantiated let aBuilder: Instantiator<`a screen`>
			}
			""",
			"Leaf.swift": Self.leaf,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock().a.bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().leaf.value"),
			DifferentialValueProbe("{ let first = Root.mock(safeDIOverrides: .init(a: .init(bBuilder: .init(leaf: .init(value: 7))))).a.bBuilder.instantiate(); return [first.leaf.value, first.aBuilder.instantiate().bBuilder.instantiate().leaf.value] }()"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenNestedTypeAndTopLevelTypeSpellOneIdentifier() async throws {
		// `Outer.Inner` and `Outer_Inner` open each other through an instantiator, so each one's builder function takes the
		// nearest configuration of the other beside its own.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(a: Instantiator<A>, b: Instantiator<Outer.Inner>, c: Instantiator<Outer_Inner>) {
			        self.a = a
			        self.b = b
			        self.c = c
			    }

			    @Instantiated let a: Instantiator<A>
			    @Instantiated let b: Instantiator<Outer.Inner>
			    @Instantiated let c: Instantiator<Outer_Inner>
			}
			""",
			"A.swift": """
			@Instantiable
			public final class A: Instantiable {
			    public init(b: Instantiator<Outer.Inner>) {
			        self.b = b
			    }

			    @Instantiated let b: Instantiator<Outer.Inner>
			}
			""",
			"Outer.swift": """
			public enum Outer {
			    @Instantiable
			    public final class Inner: Instantiable {
			        public init(c: Instantiator<Outer_Inner>, x: X) {
			            self.c = c
			            self.x = x
			        }

			        @Instantiated let c: Instantiator<Outer_Inner>
			        @Instantiated let x: X
			    }
			}
			""",
			"Outer_Inner.swift": """
			@Instantiable
			public final class Outer_Inner: Instantiable {
			    public init(b: Instantiator<Outer.Inner>, y: Leaf) {
			        self.b = b
			        self.y = y
			    }

			    @Instantiated let b: Instantiator<Outer.Inner>
			    @Instantiated let y: Leaf
			}
			""",
			"X.swift": """
			@Instantiable
			public final class X: Instantiable {
			    public init(leaf: Leaf) {
			        self.leaf = leaf
			    }

			    @Instantiated let leaf: Leaf
			}
			""",
			"Leaf.swift": Self.leaf,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock().b.instantiate().c.instantiate().b.instantiate().x.leaf.value"),
			DifferentialValueProbe("{ let inner = Root.mock(safeDIOverrides: .init(b: .init(x: .init(leaf: .init(value: 7))))).b.instantiate(); return [inner.x.leaf.value, inner.c.instantiate().y.value, inner.c.instantiate().b.instantiate().x.leaf.value] }()"),
			DifferentialValueProbe("{ let outer = Root.mock(safeDIOverrides: .init(c: .init(y: .init(value: 5)))).c.instantiate(); return [outer.y.value, outer.b.instantiate().x.leaf.value, outer.b.instantiate().c.instantiate().y.value] }()"),
			DifferentialValueProbe("{ let inner = Root.mock(safeDIOverrides: .init(a: .init(b: .init(x: .init(leaf: .init(value: 9)))))).a.instantiate().b.instantiate(); return [inner.x.leaf.value, inner.c.instantiate().b.instantiate().x.leaf.value] }()"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenLabelSpellsConfigurationParameterOfSiblingsType() async throws {
		// The builder function of the property `Aa_configuration` would be named as the parameter through which `Aa`'s
		// builder function, which calls it, takes `Aa`'s configuration.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(aa: Aa, Aa_configuration: B) {
			        self.aa = aa
			        self.Aa_configuration = Aa_configuration
			    }

			    @Instantiated let aa: Aa
			    @Instantiated let Aa_configuration: B
			}
			""",
			"Aa.swift": """
			@Instantiable
			public final class Aa: Instantiable {
			    public init(Aa_configuration: B) {
			        self.Aa_configuration = Aa_configuration
			    }

			    @Instantiated let Aa_configuration: B
			}
			""",
			"B.swift": """
			@Instantiable
			public final class B: Instantiable {
			    public init(leaf: Leaf) {
			        self.leaf = leaf
			    }

			    @Instantiated let leaf: Leaf
			}
			""",
			"Leaf.swift": Self.leaf,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock().aa.Aa_configuration.leaf.value"),
			DifferentialValueProbe("{ let root = Root.mock(safeDIOverrides: .init(aa: .init(Aa_configuration: .init(leaf: .init(value: 7))))); return [root.aa.Aa_configuration.leaf.value, root.Aa_configuration.leaf.value] }()"),
			DifferentialValueProbe("{ let root = Root.mock(safeDIOverrides: .init(Aa_configuration: .init(leaf: .init(value: 5)))); return [root.aa.Aa_configuration.leaf.value, root.Aa_configuration.leaf.value] }()"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenLabelSpellsNearestConfigurationParameterOfTypeInCycle() async throws {
		// `Aa` instantiates `A` again lazily, so its builder function takes `A`'s nearest configuration, under the name the
		// builder function of its property `A_configuration_nearest` would take.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(a: A) {
			        self.a = a
			    }

			    @Instantiated let a: A
			}
			""",
			"A.swift": """
			@Instantiable
			public final class A: Instantiable {
			    public init(aaBuilder: Instantiator<Aa>) {
			        self.aaBuilder = aaBuilder
			    }

			    @Instantiated let aaBuilder: Instantiator<Aa>
			}
			""",
			"Aa.swift": """
			@Instantiable
			public final class Aa: Instantiable {
			    public init(A_configuration_nearest: X, aBuilder: Instantiator<A>) {
			        self.A_configuration_nearest = A_configuration_nearest
			        self.aBuilder = aBuilder
			    }

			    @Instantiated let A_configuration_nearest: X
			    @Instantiated let aBuilder: Instantiator<A>
			}
			""",
			"X.swift": """
			@Instantiable
			public final class X: Instantiable {
			    public init(leaf: Leaf) {
			        self.leaf = leaf
			    }

			    @Instantiated let leaf: Leaf
			}
			""",
			"Leaf.swift": Self.leaf,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("Root.mock().a.aaBuilder.instantiate().aBuilder.instantiate().aaBuilder.instantiate().A_configuration_nearest.leaf.value"),
			DifferentialValueProbe("{ let first = Root.mock(safeDIOverrides: .init(a: .init(aaBuilder: .init(A_configuration_nearest: .init(leaf: .init(value: 7)))))).a.aaBuilder.instantiate(); return [first.A_configuration_nearest.leaf.value, first.aBuilder.instantiate().aaBuilder.instantiate().A_configuration_nearest.leaf.value] }()"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenValueMockIsPassedForSendableBuilderSpellsConfigurationParameter() async throws {
		// `mock()` reads its parameter `Panel_configuration`, which nothing builds, into a local before any builder function,
		// under the name `Panel`'s builder function, which calls that local, would take `Panel`'s configuration under.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public struct Root: Instantiable {
			    public init(panelBuilder: SendableInstantiator<Panel>) {
			        self.panelBuilder = panelBuilder
			    }

			    @Instantiated let panelBuilder: SendableInstantiator<Panel>
			}
			""",
			"Panel.swift": """
			@Instantiable
			public struct Panel: Instantiable, Sendable {
			    public init(leaf: SendableLeaf, Panel_configuration: Missing) {
			        self.leaf = leaf
			        self.Panel_configuration = Panel_configuration
			    }

			    @Instantiated let leaf: SendableLeaf
			    @Instantiated let Panel_configuration: Missing
			}
			""",
			"SendableLeaf.swift": Self.sendableLeaf,
			"Missing.swift": Self.missing,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("{ let panel = Root.mock(Panel_configuration: Missing(tag: 1)).panelBuilder.instantiate(); return [panel.leaf.value, panel.Panel_configuration.tag] }()"),
			DifferentialValueProbe("{ let panel = Root.mock(Panel_configuration: Missing(tag: 2), safeDIOverrides: .init(panelBuilder: .init(leaf: .init(value: 7)))).panelBuilder.instantiate(); return [panel.leaf.value, panel.Panel_configuration.tag] }()"),
		])
	}

	@Test
	mutating func mock_buildsWalksValues_whenValueMockIsPassedForSendableBuilderSpellsNearestConfigurationParameter() async throws {
		// `Aa` instantiates `A` again lazily, so its builder function takes `A`'s nearest configuration, under the name of
		// the local `mock()` reads its parameter `A_configuration_nearest` into, which that function calls.
		let fixtureFiles = [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(a: A) {
			        self.a = a
			    }

			    @Instantiated let a: A
			}
			""",
			"A.swift": """
			@Instantiable
			public final class A: Instantiable, Sendable {
			    public init(aaBuilder: SendableInstantiator<Aa>) {
			        self.aaBuilder = aaBuilder
			    }

			    @Instantiated let aaBuilder: SendableInstantiator<Aa>
			}
			""",
			"Aa.swift": """
			@Instantiable
			public final class Aa: Instantiable, Sendable {
			    public init(A_configuration_nearest: Missing, aBuilder: SendableInstantiator<A>) {
			        self.A_configuration_nearest = A_configuration_nearest
			        self.aBuilder = aBuilder
			    }

			    @Instantiated let A_configuration_nearest: Missing
			    @Instantiated let aBuilder: SendableInstantiator<A>
			}
			""",
			"Missing.swift": Self.missing,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("{ let first = Root.mock(A_configuration_nearest: Missing(tag: 1)).a.aaBuilder.instantiate(); return [first.A_configuration_nearest.tag, first.aBuilder.instantiate().aaBuilder.instantiate().A_configuration_nearest.tag] }()"),
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

	private static let leaf = """
	@Instantiable
	public final class Leaf: Instantiable {
	    public init(value: Int = 3) {
	        self.value = value
	    }

	    let value: Int
	}
	"""

	private static let sendableLeaf = """
	@Instantiable
	public struct SendableLeaf: Instantiable, Sendable {
	    public init(value: Int = 3) {
	        self.value = value
	    }

	    let value: Int
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
