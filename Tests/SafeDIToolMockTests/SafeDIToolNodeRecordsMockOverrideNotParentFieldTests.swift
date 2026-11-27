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

/// An internal mock root whose children receive one label as two types, laid out from the node records of its world
/// (`NodeRecords+MockOverrideNotParentField.swift`). `mock()` binds each value under a name that carries its type, and
/// the function of each node that receives the label binds it again under the label, from the name of its type.
struct SafeDIToolNodeRecordsMockOverrideNotParentFieldTests: ~Copyable {
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
	mutating func mock_bindsLabelAgainInEachReceiversFunction_whenRootNamesTwoTypesOfOneLabelApart() async throws {
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		// Each value named apart is bound by `mock()` under its name, and read by that name in the first line of the
		// function of each node that receives its label: in a function handed its configuration, and in the one an
		// `Instantiator` of the root calls.
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            thing_Thing: (() -> Thing)? = nil,
		            thing_Instantiator__Thing: (() -> Thing)? = nil,
		            leaf: Leaf.SafeDIMockConfiguration = .init(),
		            secondBuilder: ((Instantiator<Thing>) -> Second)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                thing_Thing: thing_Thing,
		                thing_Instantiator__Thing: thing_Instantiator__Thing,
		                leaf: leaf,
		                secondBuilder: secondBuilder
		            )
		        }

		        var thing_Thing: (() -> Thing)? { __safeDI_storage.thing_Thing }
		        var thing_Instantiator__Thing: (() -> Thing)? { __safeDI_storage.thing_Instantiator__Thing }
		        var leaf: Leaf.SafeDIMockConfiguration { __safeDI_storage.leaf }
		        var secondBuilder: ((Instantiator<Thing>) -> Second)? { __safeDI_storage.secondBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                thing_Thing: (() -> Thing)?,
		                thing_Instantiator__Thing: (() -> Thing)?,
		                leaf: Leaf.SafeDIMockConfiguration,
		                secondBuilder: ((Instantiator<Thing>) -> Second)?
		            ) {
		                self.thing_Thing = thing_Thing
		                self.thing_Instantiator__Thing = thing_Instantiator__Thing
		                self.leaf = leaf
		                self.secondBuilder = secondBuilder
		            }

		            let thing_Thing: (() -> Thing)?
		            let thing_Instantiator__Thing: (() -> Thing)?
		            let leaf: Leaf.SafeDIMockConfiguration
		            let secondBuilder: ((Instantiator<Thing>) -> Second)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let thing_Thing = if let safeDIBuilder = safeDIOverrides.thing_Thing { safeDIBuilder() } else { Thing() }
		        func __safeDI_thing_Instantiator__Thing() -> Thing {
		            if let safeDIBuilder = safeDIOverrides.thing_Instantiator__Thing { safeDIBuilder() } else { Thing() }
		        }
		        let thing_Instantiator__Thing = Instantiator<Thing>(__safeDI_thing_Instantiator__Thing)
		        func __safeDI_first(safeDIOverrides: ((Thing) -> First)?) -> First {
		            let thing: Thing = thing_Thing
		            return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(thing) } else { First(thing: thing) }
		        }
		        func __safeDI_second(safeDIOverrides: ((Instantiator<Thing>) -> Second)?) -> Second {
		            let thing: Instantiator<Thing> = thing_Instantiator__Thing
		            return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(thing) } else { Second(thing: thing) }
		        }
		        func __safeDI_leaf(safeDIOverrides: Leaf.SafeDIMockConfiguration) -> Leaf {
		            let first: First = __safeDI_first(safeDIOverrides: safeDIOverrides.first)
		            let second: Second = __safeDI_second(safeDIOverrides: safeDIOverrides.second)
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(first, second) } else { Leaf(first: first, second: second) }
		        }
		        let leaf: Leaf = __safeDI_leaf(safeDIOverrides: safeDIOverrides.leaf)
		        func __safeDI_secondBuilder() -> Second {
		            let thing: Instantiator<Thing> = thing_Instantiator__Thing
		            return if let safeDIBuilder = safeDIOverrides.secondBuilder { safeDIBuilder(thing) } else { Second(thing: thing) }
		        }
		        let secondBuilder = Instantiator<Second>(__safeDI_secondBuilder)
		        return Root(leaf: leaf, secondBuilder: secondBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenEveryPlaceOfTreeNamedApartIsOverridden() async throws {
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, _) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		// The two write other text, so the comparison is of two programs.
		#expect(output.mockFiles["Root+SafeDIMock.swift"] != walkOutput.mockFiles["Root+SafeDIMock.swift"])
		let overridden = """
		Root.mock(safeDIOverrides: .init(\
		thing_Thing: { marked(Thing(), "thing_Thing") }, \
		thing_Instantiator__Thing: { marked(Thing(), "thing_Instantiator__Thing") }, \
		leaf: .init(first: { marked(First(thing: $0), "leaf.first") }, second: { marked(Second(thing: $0), "leaf.second") }, { marked(Leaf(first: $0, second: $1), "leaf") }), \
		secondBuilder: { marked(Second(thing: $0), "secondBuilder") }))
		"""
		let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: Self.fixture, generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: Self.fixture, generatedFiles: #require(walkOutput.generatedFiles)),
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe("Root.mock().leaf.second.thing.instantiate()"),
				DifferentialValueProbe("Root.mock().secondBuilder.instantiate().thing.instantiate()"),
				DifferentialValueProbe(name: "overridden root", expression: overridden),
				DifferentialValueProbe(name: "overridden value of the constant’s instantiator", expression: "\(overridden).leaf.second.thing.instantiate()"),
				DifferentialValueProbe(name: "overridden instantiator", expression: "\(overridden).secondBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden value of the instantiator’s instantiator", expression: "\(overridden).secondBuilder.instantiate().thing.instantiate()"),
			],
			filesToDelete: &filesToDelete,
		)
		// Nothing is compared where compile verification is off.
		guard let comparison else { return }
		#expect(comparison.differences.isEmpty, "\(comparison.report)")
		// Every override was read: each marks a value its closure built.
		for marker in ["thing_Thing", "thing_Instantiator__Thing", "leaf.first", "leaf.second", "leaf", "secondBuilder"] {
			#expect(comparison.featureDescription.contains("\"\(marker)\""), "No value is marked \(marker):\n\(comparison.featureDescription)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsTheWalksStatements_whenNodeBelowRootBuildsLabelNamedApart() async throws {
		// `Inner` builds a third `thing` of its own, which its child receives. A function of the label’s name is declared
		// once for `mock()`, so the label names two values in it: the world is refused, and the walk writes it.
		let fixture = Self.fixture.merging(Self.fixtureOfLabelBuiltBelowRoot) { $1 }
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.everyRefusal) == [["mockOverrideNotParentField"]])
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [false])
		#expect(output.generatedFiles == walkOutput.generatedFiles)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsNamesInTheWalksOrderOnEveryRun_whenRootNamesTwentyValuesApart() async throws {
		// Ten labels, each received as a value and as an `Instantiator`: twenty children the root names apart, whose
		// names the records look up by label and type and never list.
		let labels = (0..<10).map { "value\($0)" }
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(leaf: Leaf) {
			        self.leaf = leaf
			    }

			    @Instantiated let leaf: Leaf
			}

			@Instantiable
			public final class Leaf: Instantiable {
			    public init(first: First, second: Second) {
			        self.first = first
			        self.second = second
			    }

			    @Instantiated let first: First
			    @Instantiated let second: Second
			}

			@Instantiable
			public final class First: Instantiable {
			    public init(\(labels.indices.map { "\(labels[$0]): Thing\($0)" }.joined(separator: ", "))) {
			\(labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
			    }

			\(labels.indices.map { "    @Received let \(labels[$0]): Thing\($0)" }.joined(separator: "\n"))
			}

			@Instantiable
			public final class Second: Instantiable {
			    public init(\(labels.indices.map { "\(labels[$0]): Instantiator<Thing\($0)>" }.joined(separator: ", "))) {
			\(labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
			    }

			\(labels.indices.map { "    @Received let \(labels[$0]): Instantiator<Thing\($0)>" }.joined(separator: "\n"))
			}

			\(labels.indices.map { "@Instantiable\npublic final class Thing\($0): Instantiable {\n    public init() {}\n}" }.joined(separator: "\n\n"))
			""",
		]
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		var runs = [String]()
		for _ in 0..<2 {
			let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
				try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			}
			#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
			try runs.append(#require(output.mockFiles["Root+SafeDIMock.swift"]))
		}
		#expect(runs[0] == runs[1])
		// The values `mock()`'s body binds, in order: each line of its own indentation that binds a name.
		func namesBound(in mock: String) -> [String] {
			mock.split(separator: "\n").compactMap { line in
				line.hasPrefix("        let ") ? line.dropFirst("        let ".count).prefix { $0 != " " && $0 != ":" }.description : nil
			}
		}
		let expectedNames = labels.indices.map { "\(labels[$0])_Thing\($0)" } + labels.indices.map { "\(labels[$0])_Instantiator__Thing\($0)" } + ["leaf"]
		#expect(namesBound(in: runs[0]) == expectedNames)
		#expect(try namesBound(in: #require(walkOutput.mockFiles["Root+SafeDIMock.swift"])) == expectedNames)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A root whose leaf builds two children that each receive `thing`, one as a value and one as an `Instantiator`, so
	/// `mock()` names the two apart. The root also builds the second child through an `Instantiator`. Each class carries
	/// a marker an override’s closure sets.
	private static let fixture: [String: String] = [
		"Marked.swift": """
		public protocol Marked: AnyObject {
		    var marker: String { get set }
		}

		public func marked<Value: Marked>(_ value: Value, _ marker: String) -> Value {
		    value.marker = marker
		    return value
		}
		""",
		"Root.swift": """
		@Instantiable(generateMock: true)
		public final class Root: Instantiable, Marked {
		    public init(leaf: Leaf, secondBuilder: Instantiator<Second>) {
		        self.leaf = leaf
		        self.secondBuilder = secondBuilder
		    }

		    @Instantiated let leaf: Leaf
		    @Instantiated let secondBuilder: Instantiator<Second>
		    public var marker = "built"
		}
		""",
		"Leaf.swift": """
		@Instantiable
		public final class Leaf: Instantiable, Marked {
		    public init(first: First, second: Second) {
		        self.first = first
		        self.second = second
		    }

		    @Instantiated let first: First
		    @Instantiated let second: Second
		    public var marker = "built"
		}
		""",
		"First.swift": """
		@Instantiable
		public final class First: Instantiable, Marked {
		    public init(thing: Thing) {
		        self.thing = thing
		    }

		    @Received let thing: Thing
		    public var marker = "built"
		}
		""",
		"Second.swift": """
		@Instantiable
		public final class Second: Instantiable, Marked {
		    public init(thing: Instantiator<Thing>) {
		        self.thing = thing
		    }

		    @Received let thing: Instantiator<Thing>
		    public var marker = "built"
		}
		""",
		"Thing.swift": """
		@Instantiable
		public final class Thing: Instantiable, Marked {
		    public init() {}

		    public var marker = "built"
		}
		""",
	]

	/// The files that make `fixture` a root that also builds `Inner`, which builds a `thing` of a third type for its child.
	private static let fixtureOfLabelBuiltBelowRoot: [String: String] = [
		"Root.swift": """
		@Instantiable(generateMock: true)
		public final class Root: Instantiable, Marked {
		    public init(leaf: Leaf, inner: Inner) {
		        self.leaf = leaf
		        self.inner = inner
		    }

		    @Instantiated let leaf: Leaf
		    @Instantiated let inner: Inner
		    public var marker = "built"
		}
		""",
		"Inner.swift": """
		@Instantiable
		public final class Inner: Instantiable, Marked {
		    public init(thing: Other, user: User) {
		        self.thing = thing
		        self.user = user
		    }

		    @Instantiated let thing: Other
		    @Instantiated let user: User
		    public var marker = "built"
		}
		""",
		"Other.swift": """
		@Instantiable
		public final class Other: Instantiable, Marked {
		    public init() {}

		    public var marker = "built"
		}
		""",
		"User.swift": """
		@Instantiable
		public final class User: Instantiable, Marked {
		    public init(thing: Other) {
		        self.thing = thing
		    }

		    @Received let thing: Other
		    public var marker = "built"
		}
		""",
	]

	/// What `body` returns with every internal mock root node records accept laid out from them, and the report of each
	/// mock root of the run, in the order of the roots' names.
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
}
