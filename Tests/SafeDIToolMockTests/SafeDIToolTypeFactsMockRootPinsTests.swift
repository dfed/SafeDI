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

/// The mock root's pins as the per-type facts make them from the graph (`TypeFactsMockRootPins`): each variant of a mock's
/// world passes `nil` to the receives only if available a required receive of their label pins, and every place of the
/// tree passes `nil` to exactly its variant's (check 36).
struct SafeDIToolTypeFactsMockRootPinsTests: ~Copyable {
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
	mutating func mockRootPins_pinReceiveWhereverItsTypeIsBuilt_whenRequiredReceiveBeneathItsTypePinsIt() async throws {
		// `Child`'s required `token: Instantiator<Token>` pins the declaration `Leaf` reads to a form `Leaf`'s `token: Token?`
		// cannot read, wherever `Leaf` is built.
		let report = try await mockReport(of: [
			"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(leaf: Leaf) {
			        self.leaf = leaf
			    }

			    @Instantiated let leaf: Leaf
			}
			""",
			"""
			@Instantiable
			public final class Leaf: Instantiable {
			    public init(token: Token?, child: Child) {
			        self.token = token
			        self.child = child
			    }

			    @Received(onlyIfAvailable: true) let token: Token?
			    @Instantiated let child: Child
			}
			""",
			"""
			@Instantiable
			public final class Child: Instantiable {
			    public init(token: Instantiator<Token>) {
			        self.token = token
			    }

			    @Received let token: Instantiator<Token>
			}
			""",
			"""
			@Instantiable
			public final class Token: Instantiable {
			    public init() {}
			}
			""",
		])

		#expect(passedNilByPlace(in: report) == ["Leaf as leaf: Leaf": ["token: Token?"]], "\(report.world)")
		expectPlacesPassNilAsTheirVariants(in: report)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mockRootPins_pinReceiveBeneathRequiredReceive_whenMockedTypeRequiresLabelInAnotherForm() async throws {
		// `Root`'s own required `token: Instantiator<Token>` pins the places beneath it, and only those.
		let report = try await mockReport(of: [
			"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(token: Instantiator<Token>, leaf: Leaf) {
			        self.token = token
			        self.leaf = leaf
			    }

			    @Received let token: Instantiator<Token>
			    @Instantiated let leaf: Leaf
			}
			""",
			"""
			@Instantiable
			public final class Leaf: Instantiable {
			    public init(token: Token?) {
			        self.token = token
			    }

			    @Received(onlyIfAvailable: true) let token: Token?
			}
			""",
			"""
			@Instantiable
			public final class Token: Instantiable {
			    public init() {}
			}
			""",
		])

		#expect(passedNilByPlace(in: report) == ["Leaf as leaf: Leaf": ["token: Token?"]], "\(report.world)")
		expectPlacesPassNilAsTheirVariants(in: report)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mockRootPins_pinOnlyThePlaceBeneathMockedTypesRequiredReceive_whenPromotedDependencyIsAlsoBuiltBeneathMockedType() async throws {
		// `source: Source` is promoted, so production builds it above `Root`, where `Root`'s required
		// `token: Instantiator<Token>` pins nothing; `Holder` builds it again beneath `Root`, where it pins the `Leaf` there.
		// One node, two variants, as the walk tells the two places apart.
		let report = try await mockReport(of: [
			"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(token: Instantiator<Token>, source: Source, holder: Holder) {
			        self.token = token
			        self.source = source
			        self.holder = holder
			    }

			    @Received let token: Instantiator<Token>
			    @Received let source: Source
			    @Instantiated let holder: Holder
			}
			""",
			"""
			@Instantiable
			public final class Holder: Instantiable {
			    public init(source: Source) {
			        self.source = source
			    }

			    @Instantiated let source: Source
			}
			""",
			"""
			@Instantiable
			public final class Source: Instantiable {
			    public init(leaf: Leaf) {
			        self.leaf = leaf
			    }

			    @Instantiated let leaf: Leaf
			}
			""",
			"""
			@Instantiable
			public final class Leaf: Instantiable {
			    public init(token: Token?) {
			        self.token = token
			    }

			    @Received(onlyIfAvailable: true) let token: Token?
			}
			""",
			"""
			@Instantiable
			public final class Token: Instantiable {
			    public init() {}
			}
			""",
		])

		let leafPlaces = report.places.indices.filter { report.places[$0].declaration == "Leaf as leaf: Leaf" }
		#expect(leafPlaces.map { report.places[$0].receivesPassedNil }.sorted { $0.count < $1.count } == [[], ["token: Token?"]], "\(report.world)")
		let leafNode = try #require(leafPlaces.first.flatMap { report.places[$0].node })
		#expect(report.variantNodes.indices.filter { report.variantNodes[$0] == leafNode }.map { report.variantReceivesPassedNil[$0] }.sorted { $0.count < $1.count } == [[], ["token: Token?"]], "\(report.world)")
		expectPlacesPassNilAsTheirVariants(in: report)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mockRootPins_matchTheWalk_whenRequiredReceiveOnLazyCycleIsAboveTheReceiveOnlyOnTheSecondLap() async throws {
		// `B`'s required `token: Instantiator<Token>` is above `Leaf` only on the lap the closing `aBuilder` opens, where no
		// place is built: the tree builds the first lap's `Leaf`, which nothing pins.
		let report = try await mockReport(of: [
			"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(aBuilder: Instantiator<A>) {
			        self.aBuilder = aBuilder
			    }

			    @Instantiated let aBuilder: Instantiator<A>
			}
			""",
			"""
			@Instantiable
			public final class A: Instantiable {
			    public init(leaf: Leaf, b: B) {
			        self.leaf = leaf
			        self.b = b
			    }

			    @Instantiated let leaf: Leaf
			    @Instantiated let b: B
			}
			""",
			"""
			@Instantiable
			public final class B: Instantiable {
			    public init(token: Instantiator<Token>, aBuilder: Instantiator<A>) {
			        self.token = token
			        self.aBuilder = aBuilder
			    }

			    @Received let token: Instantiator<Token>
			    @Instantiated let aBuilder: Instantiator<A>
			}
			""",
			"""
			@Instantiable
			public final class Leaf: Instantiable {
			    public init(token: Token?) {
			        self.token = token
			    }

			    @Received(onlyIfAvailable: true) let token: Token?
			}
			""",
			"""
			@Instantiable
			public final class Token: Instantiable {
			    public init() {}
			}
			""",
		])

		#expect(report.places.filter { $0.declaration == "Leaf as leaf: Leaf" }.map(\.receivesPassedNil) == [[]], "\(report.world)")
		expectPlacesPassNilAsTheirVariants(in: report)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mockRootPins_leaveTheRingToTheWalk_whenRequiredReceiveOnLazyCycleIsAboveTheReceiveOnlyOnTheSecondLap() async throws {
		// The ring's `token: Token?` override is named apart from `B`'s `token: Instantiator<Token>` (`token_Token`). The node
		// records take the name apart as a parameter, but the cycle's variants partition apart, which they do not lay out yet, so
		// the mock keeps the walk's code: lap two's `Leaf` reads lap one's override, as production reads the one declaration above both.
		let fixture = Self.secondLapRingFixture
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.refusal) == ["cycleVariantsPartitionApart"])
		#expect(output.generatedFiles == walkOutput.generatedFiles)
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mockRootPins_pinEveryLabel_whenTwentyRequiredReceivesPinTwentyLabels(reversed: Bool) async throws {
		// Twenty labels, each pinned by the mocked type's own required receive, declared in one order and its reverse: the
		// pins are a set, whichever order the labels are interned in.
		let labels = (0..<20).map { "token\($0)" }
		let declaredLabels = reversed ? labels.reversed() : labels
		let root = """
		@Instantiable(generateMock: true)
		public final class Root: Instantiable {
		    public init(\(declaredLabels.map { "\($0): Instantiator<Token>" }.joined(separator: ", ")), leaf: Leaf) {
		\(declaredLabels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
		        self.leaf = leaf
		    }

		\(declaredLabels.map { "    @Received let \($0): Instantiator<Token>" }.joined(separator: "\n"))
		    @Instantiated let leaf: Leaf
		}
		"""
		let leaf = """
		@Instantiable
		public final class Leaf: Instantiable {
		    public init(\(declaredLabels.map { "\($0): Token?" }.joined(separator: ", "))) {
		\(declaredLabels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
		    }

		\(declaredLabels.map { "    @Received(onlyIfAvailable: true) let \($0): Token?" }.joined(separator: "\n"))
		}
		"""
		let token = """
		@Instantiable
		public final class Token: Instantiable {
		    public init() {}
		}
		"""
		let report = try await mockReport(of: [root, leaf, token], skipCompileVerification: true)

		#expect(passedNilByPlace(in: report) == ["Leaf as leaf: Leaf": labels.map { "\($0): Token?" }.sorted()], "\(report.world)")
		expectPlacesPassNilAsTheirVariants(in: report)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Runs `body` with mock roots laid out from their worlds' node records, and returns what it returns with the report of
	/// each root.
	private static func layingOutMockRoots<Output>(
		filesToDelete: inout [URL],
		_ body: (inout [URL]) async throws -> Output,
	) async throws -> (Output, [NodeRecordsReport]) {
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		let output = try await NodeRecordsObservation.$laysOutMockRoots.withValue(true) {
			try await NodeRecordsObservation.$observer.withValue({ continuation.yield($0) }) {
				try await body(&filesMade)
			}
		}
		continuation.finish()
		var reports = [NodeRecordsReport]()
		for await report in stream {
			reports.append(report)
		}
		return (output, reports.sorted { $0.root < $1.root })
	}

	private static let secondLapRingFixture: [String: String] = [
		"Root.swift": """
		@Instantiable(generateMock: true)
		public final class Root: Instantiable {
		    public init(aBuilder: Instantiator<A>) {
		        self.aBuilder = aBuilder
		    }

		    @Instantiated let aBuilder: Instantiator<A>
		}
		""",
		"A.swift": """
		@Instantiable
		public final class A: Instantiable {
		    public init(leaf: Leaf, b: B) {
		        self.leaf = leaf
		        self.b = b
		    }

		    @Instantiated let leaf: Leaf
		    @Instantiated let b: B
		}
		""",
		"B.swift": """
		@Instantiable
		public final class B: Instantiable {
		    public init(token: Instantiator<Token>, aBuilder: Instantiator<A>) {
		        self.token = token
		        self.aBuilder = aBuilder
		    }

		    @Received let token: Instantiator<Token>
		    @Instantiated let aBuilder: Instantiator<A>
		}
		""",
		"Leaf.swift": """
		@Instantiable
		public final class Leaf: Instantiable {
		    public init(token: Token?) {
		        self.token = token
		    }

		    @Received(onlyIfAvailable: true) let token: Token?
		}
		""",
		"Token.swift": """
		@Instantiable
		public final class Token: Instantiable {
		    public init() {}
		}
		""",
	]

	/// The report of the last mock tree of `Root`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func mockReport(of types: [String], skipCompileVerification: Bool = false) async throws -> TypeFactsReport {
		let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		_ = try await ConstructionMemoOracle.$observer.withValue({ _, _, report in continuation.yield(report) }) {
			try await executeSafeDIToolTest(swiftFileContent: types, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete, skipCompileVerification: skipCompileVerification)
		}
		continuation.finish()
		var reports = [TypeFactsReport]()
		for await report in stream where report.root == "Root" && report.forMockGeneration {
			reports.append(report)
		}
		return try #require(reports.last)
	}

	/// The receives each node's first variant pins, by the declaration of the node's first place, where it pins any.
	private func passedNilByPlace(in report: TypeFactsReport) -> [String: [String]] {
		var passedNil = [String: [String]]()
		for place in report.places where !place.closesCycle {
			guard let node = place.node, let variant = report.variantNodes.firstIndex(of: node), !report.variantReceivesPassedNil[variant].isEmpty else { continue }
			passedNil[place.declaration] = report.variantReceivesPassedNil[variant]
		}
		return passedNil
	}

	/// Check 36, as every tree runs it: each place passes `nil` to exactly what its variant pins.
	private func expectPlacesPassNilAsTheirVariants(in report: TypeFactsReport) {
		let result = TypeFactsChecks.findings(of: report)
		#expect(result.comparedByCheck[36, default: 0] > 0, "\(report.world)")
		#expect(result.findingsByCheck[36] == nil, "\(result.findingsByCheck[36] ?? []): \(report.world)")
	}
}
