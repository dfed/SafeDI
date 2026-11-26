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

/// A loop of builders in a mock is recorded as production records it: each member is a built place, whose function begins
/// with a closer on each sibling's function it rebinds, handing that sibling the configuration its level hands it. Each
/// graph here is laid out, and its mock is compiled and compared by value, with an override at every place, with the one
/// the walk writes.
struct SafeDIToolMockTypeKeyLoopValueTests: ~Copyable {
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
	mutating func mock_buildsWalksValuesOnEveryTurn_whenLoopOfBuildersSitsBeneathTwoParents() async throws {
		// `Flow`'s `aBuilder` and `bBuilder` receive each other, and `P1` and `P2` each build a `Flow`: each turn of either
		// loop reads the overrides of its own `Flow`'s members.
		let fixtureFiles = Self.loopBeneathTwoParents(wrapper: "Instantiator", conformances: "")
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("\(Self.overridingLeaves).p1.flow.aBuilder.instantiate().leaf.value"),
			DifferentialValueProbe("\(Self.overridingLeaves).p2.flow.aBuilder.instantiate().leaf.value"),
			DifferentialValueProbe("\(Self.overridingLeaves).p1.flow.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().leaf.value"),
			DifferentialValueProbe("\(Self.overridingLeaves).p2.flow.bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().leaf.value"),
			// An override closure at a member is called on the first turn and on the second.
			DifferentialValueProbe("""
			{
			    var calls = [String]()
			    let root = Root.mock(safeDIOverrides: .init(
			        p1: .init(flow: .init(bBuilder: { aBuilder in calls.append("p1"); return B(aBuilder: aBuilder) })),
			        p2: .init(flow: .init(bBuilder: { aBuilder in calls.append("p2"); return B(aBuilder: aBuilder) })),
			    ))
			    _ = root.p1.flow.bBuilder.instantiate()
			    _ = root.p1.flow.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()
			    _ = root.p2.flow.aBuilder.instantiate().bBuilder.instantiate()
			    return calls
			}()
			"""),
		])
	}

	@Test
	mutating func mock_buildsWalksValuesOnEveryTurn_whenLoopOfSendableBuildersSitsBeneathTwoParents() async throws {
		// The same loop of `SendableInstantiator`s: each member's function is `@Sendable`, so what it is handed crosses into it.
		let fixtureFiles = Self.loopBeneathTwoParents(wrapper: "SendableInstantiator", conformances: ", Sendable")
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("\(Self.overridingLeaves).p1.flow.aBuilder.instantiate().leaf.value"),
			DifferentialValueProbe("\(Self.overridingLeaves).p2.flow.aBuilder.instantiate().leaf.value"),
			DifferentialValueProbe("\(Self.overridingLeaves).p1.flow.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().leaf.value"),
			DifferentialValueProbe("\(Self.overridingLeaves).p2.flow.bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().leaf.value"),
			DifferentialValueProbe("""
			{
			    let given = B(aBuilder: SendableInstantiator<A> { A(bBuilder: SendableInstantiator<B> { fatalError() }, leaf: Leaf(value: 0)) })
			    let root = Root.mock(safeDIOverrides: .init(p2: .init(flow: .init(bBuilder: { _ in given }))))
			    return [
			        root.p2.flow.aBuilder.instantiate().bBuilder.instantiate() === given,
			        root.p2.flow.bBuilder.instantiate() === given,
			        root.p1.flow.aBuilder.instantiate().bBuilder.instantiate() === given,
			    ]
			}()
			"""),
		])
	}

	@Test(arguments: ["`default`", "`in`", "`class`", "any", "async", "🎨"])
	mutating func mock_buildsWalksValues_whenLoopMemberReceivesKeywordLabel(label: String) async throws {
		// `A`, a member of `X`'s loop, receives the `Theme` its `P` declares under `label`, which the loop's function reads.
		let fixtureFiles = [
			"Root.swift": Self.type("Root", generateMock: true, properties: ["@Instantiated let p1: P1", "@Instantiated let p2: P2"]),
			"P1.swift": Self.type("P1", properties: ["@Instantiated let \(label): Theme", "@Instantiated let x: X"]),
			"P2.swift": Self.type("P2", properties: ["@Instantiated let \(label): Theme", "@Instantiated let x: X"]),
			"X.swift": Self.type("X", properties: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"]),
			"A.swift": Self.type("A", properties: ["@Received let bBuilder: Instantiator<B>", "@Received let \(label): Theme"]),
			"B.swift": Self.type("B", properties: ["@Received let aBuilder: Instantiator<A>"]),
			"Theme.swift": Self.theme,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("{ let root = Root.mock(); return root.p1.x.aBuilder.instantiate().\(label) === root.p1.\(label) }()"),
			DifferentialValueProbe("{ let root = Root.mock(); return root.p2.x.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().\(label) === root.p2.\(label) }()"),
		])
	}

	@Test(arguments: ["`default`", "`in`", "`class`", "any", "async", "🎨"])
	mutating func mock_readsNearestDeclarationOfKeywordLabel_whenLoopMemberReceivesLabelRootAlsoDeclares(label: String) async throws {
		// `Root` and `P1` both declare `label`: the `A` beneath `P1` receives `P1`'s, and the one beneath `P2` receives `Root`'s.
		let fixtureFiles = [
			"Root.swift": Self.type("Root", generateMock: true, properties: ["@Instantiated let \(label): Theme", "@Instantiated let p1: P1", "@Instantiated let p2: P2"]),
			"P1.swift": Self.type("P1", properties: ["@Instantiated let \(label): Theme", "@Instantiated let x: X"]),
			"P2.swift": Self.type("P2", properties: ["@Instantiated let x: X"]),
			"X.swift": Self.type("X", properties: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"]),
			"A.swift": Self.type("A", properties: ["@Received let bBuilder: Instantiator<B>", "@Received let \(label): Theme"]),
			"B.swift": Self.type("B", properties: ["@Received let aBuilder: Instantiator<A>"]),
			"Theme.swift": Self.theme,
		]
		let mocks = try await generatedMocks(of: fixtureFiles)
		let overriding = "Root.mock(safeDIOverrides: .init(\(label.filter { $0 != "`" }): .init(value: 1), p1: .init(\(label.filter { $0 != "`" }): .init(value: 7))))"

		#expect(mocks.outcomes == ["Root: laidOut"])
		try await expectLaidOutValuesEqualWalks(mocks, fixtureFiles: fixtureFiles, probes: [
			DifferentialValueProbe("{ let root = Root.mock(); return root.p1.x.aBuilder.instantiate().\(label) === root.p1.\(label) }()"),
			DifferentialValueProbe("{ let root = Root.mock(); return root.p2.x.aBuilder.instantiate().\(label) === root.\(label) }()"),
			DifferentialValueProbe("\(overriding).p1.x.aBuilder.instantiate().\(label).value"),
			DifferentialValueProbe("\(overriding).p2.x.bBuilder.instantiate().aBuilder.instantiate().\(label).value"),
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Root.mock()` with an override of the `Leaf` beneath each `Flow`'s `aBuilder`, other at each parent.
	private static let overridingLeaves = "Root.mock(safeDIOverrides: .init(p1: .init(flow: .init(aBuilder: .init(leaf: .init(value: 7)))), p2: .init(flow: .init(aBuilder: .init(leaf: .init(value: 9))))))"

	/// A `Theme` whose `value` defaults to 3, a field of its configuration.
	private static let theme = """
	@Instantiable
	public final class Theme: Instantiable {
	    public init(value: Int = 3) {
	        self.value = value
	    }

	    let value: Int
	}
	"""

	/// `Root` builds `P1` and `P2`, each of which builds a `Flow`, whose `aBuilder` and `bBuilder`, of `wrapper`, receive
	/// each other. `A` also builds a `Leaf`, whose `value` defaults to 3.
	private static func loopBeneathTwoParents(wrapper: String, conformances: String) -> [String: String] {
		[
			"Root.swift": type("Root", generateMock: true, properties: ["@Instantiated let p1: P1", "@Instantiated let p2: P2"]),
			"P1.swift": type("P1", properties: ["@Instantiated let flow: Flow"]),
			"P2.swift": type("P2", properties: ["@Instantiated let flow: Flow"]),
			"Flow.swift": type("Flow", properties: ["@Instantiated let aBuilder: \(wrapper)<A>", "@Instantiated let bBuilder: \(wrapper)<B>"]),
			"A.swift": type("A", conformances: conformances, properties: ["@Received let bBuilder: \(wrapper)<B>", "@Instantiated let leaf: Leaf"]),
			"B.swift": type("B", conformances: conformances, properties: ["@Received let aBuilder: \(wrapper)<A>"]),
			"Leaf.swift": """
			@Instantiable
			public final class Leaf: Instantiable\(conformances) {
			    public init(value: Int = 3) {
			        self.value = value
			    }

			    let value: Int
			}
			""",
		]
	}

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
