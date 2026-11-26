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

/// A root's records made from its world's per-type facts, with no tree of places (`NodeRecords`): every test compares them
/// with the tree's records at every place (`NodeRecordsChecks`); these lay a root out from them.
struct SafeDIToolNodeRecordsTests: ~Copyable {
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
	mutating func generate_laysOutRootAsTheTreeDoes_whenOneNodeIsBuiltAtTwoPlaces() async throws {
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: Self.sharedLoggerFixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		// The logger's node is built in line in `a`'s and `bBuilder`'s functions, each evaluating its default argument for
		// its own instance.
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        let shared = Shared()
			        func __safeDI_a() -> A {
			            let logger = Logger()
			            return A(shared: shared, logger: logger)
			        }
			        let a: A = __safeDI_a()
			        func __safeDI_bBuilder(id: Int) -> B {
			            let logger = Logger()
			            let c = C(id: id)
			            return B(id: id, logger: logger, c: c)
			        }
			        let bBuilder = Instantiator<B> {
			            __safeDI_bBuilder(id: $0)
			        }
			        self.init(shared: shared, a: a, bBuilder: bBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTheTreesLayout_whenTheRootBuildsNothing() async throws {
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init() {}
				}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.generatedFiles == ["Root+SafeDI.swift": generatedFileHeader])
		#expect(reports.isEmpty)
	}

	@Test
	func nodeRecordsFiles_callNoScopeGeneratorAndReadNoText_whenReadAsSource() throws {
		// Soundness rule 2: a record is made from per-type facts, never from a tree's generator or text it spelled. Only
		// the static helpers of `ScopeGenerator` listed here are called, until they move: a new one is a decision. The
		// generator's hook (`DependencyTreeGenerator+NodeRecords.swift`) also calls `rootInitializer(of:)`, and plans the
		// tree beside the records for the comparison.
		let directory = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("Sources/SafeDICore/Generators/NodeRecords")
		let staticHelpers: Set = ["functionName", "standardIndent", "provides"]
		for file in ["NodeRecords.swift", "NodeBuildOrder.swift", "NodeRecordsObservation.swift"] {
			let source = try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
			let code = source.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
			for match in code.matches(of: /ScopeGenerator\.(\w+)/) {
				#expect(staticHelpers.contains(String(match.1)), "\(file) calls ScopeGenerator.\(match.1)")
			}
			for name in ["scopeGenerator", "generatePlan", ".spelled()"] {
				#expect(!code.contains(name), "\(file) names \(name)")
			}
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A root whose `Logger` is built where `A` and `B` each instantiate it, and whose `B` forwards what its child receives.
	private static let sharedLoggerFixture = [
		"""
		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
		    public init(shared: Shared, a: A, bBuilder: Instantiator<B>) {
		        self.shared = shared
		        self.a = a
		        self.bBuilder = bBuilder
		    }

		    @Instantiated let shared: Shared
		    @Instantiated let a: A
		    @Instantiated let bBuilder: Instantiator<B>
		}
		""",
		"""
		@Instantiable
		public struct Shared: Instantiable {
		    public init() {}
		}
		""",
		"""
		@Instantiable
		public struct Logger: Instantiable {
		    public init(level: Int = 1) {
		        self.level = level
		    }

		    let level: Int
		}
		""",
		"""
		@Instantiable
		public struct A: Instantiable {
		    public init(shared: Shared, logger: Logger) {
		        self.shared = shared
		        self.logger = logger
		    }

		    @Received let shared: Shared
		    @Instantiated let logger: Logger
		}
		""",
		"""
		@Instantiable
		public struct B: Instantiable {
		    public init(id: Int, logger: Logger, c: C) {
		        self.id = id
		        self.logger = logger
		        self.c = c
		    }

		    @Forwarded let id: Int
		    @Instantiated let logger: Logger
		    @Instantiated let c: C
		}
		""",
		"""
		@Instantiable
		public struct C: Instantiable {
		    public init(id: Int) {
		        self.id = id
		    }

		    @Received let id: Int
		}
		""",
	]

	/// What `body` returns with every root node records accept laid out from them, and the report of each root of the run.
	private static func layingOutRoots<Output>(
		filesToDelete: inout [URL],
		_ body: (inout [URL]) async throws -> Output,
	) async throws -> (Output, [NodeRecordsReport]) {
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		let output = try await NodeRecordsObservation.$laysOutRoots.withValue(true) {
			try await NodeRecordsObservation.$observer.withValue({ continuation.yield($0) }) {
				try await body(&filesMade)
			}
		}
		continuation.finish()
		var reports = [NodeRecordsReport]()
		for await report in stream {
			reports.append(report)
		}
		return (output, reports)
	}
}
