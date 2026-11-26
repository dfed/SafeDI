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

/// The walk of an internal mock root's tree that records places for the type key's layout writes no statement to the
/// root's body: the layout writes the body from the records (`MockLowering.Walk.writesText`). Only a root whose layout
/// falls back is walked again, for the walk's body. A tree has a statement or more per path, so a walk that wrote them
/// only for the layout to replace them held the largest text a root has until then.
struct SafeDIToolMockTypeKeyWalkTextTests: ~Copyable {
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
	mutating func mock_walksRootOnceWritingNoStatement_whenTypeKeyLaysRootOut() async throws {
		let observed = try await observingWalks { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.treeFixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(observed.outcomes == ["Parent: laidOut"])
		#expect(observed.walks == ["Parent: 0"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_walksRootOnceWritingItsStatements_whenTypeKeyLaysNoMockOut() async throws {
		let observed = try await observingWalks { filesToDelete in
			try await MockLowering.$laysOutWithTypeKey.withValue(false) {
				try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.treeFixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			}
		}

		#expect(observed.outcomes == [])
		// `__safeDI_child`'s declaration, `grandchild`'s binding, the function's `return` and brace, and `child`'s binding.
		#expect(observed.walks == ["Parent: 5"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_walksRootAgainWritingItsStatements_whenLayoutFallsBack() async throws {
		// `MyService`'s hand-written mock takes no `database`, so production's record function throws at its place
		// (`MockTypeKeyLayoutChecks.expectedRecordErrors`) and `Parent` keeps the walk's body.
		let observed = try await observingWalks { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.fallbackFixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let walk = try await MockLowering.$laysOutWithTypeKey.withValue(false) {
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.fallbackFixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(observed.outcomes == ["Parent: unrecorded:threw:unexpectedArgument:configuredConstruction"])
		// The walk that recorded places wrote nothing, and the walk after the fallback wrote `service`'s binding.
		#expect(observed.walks == ["Parent: 0", "Parent: 1"])
		#expect(observed.output.mockFiles == walk.mockFiles)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_writesNoStatementOfLoop_whenLaidOutRootHoldsLoopOfBuilders() async throws {
		// `Child`, built inside the `Node` the promoted `nodeBuilder` builds, receives `nodeBuilder` back, a loop of
		// builders, whose members are recorded as built places and whose rebinding is a closer: no member is written as
		// text. `SafeDIToolMockTypeKeyLoopValueTests` compares what such a layout builds with the walk's body.
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public final class Screen: Instantiable {
			    public init(nodeBuilder: Instantiator<Node>) { self.nodeBuilder = nodeBuilder }
			    @Received let nodeBuilder: Instantiator<Node>
			}
			""",
			"""
			@Instantiable
			public final class Node: Instantiable {
			    public init(child: Child) { self.child = child }
			    @Instantiated let child: Child
			}
			""",
			"""
			@Instantiable
			public final class Child: Instantiable {
			    public init(nodeBuilder: Instantiator<Node>) { self.nodeBuilder = nodeBuilder }
			    @Received let nodeBuilder: Instantiator<Node>
			}
			""",
		]
		let observed = try await observingWalks { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(observed.outcomes == ["Screen: laidOut"])
		#expect(observed.walks == ["Screen: 0"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_writesNoStatementOfCall_whenLaidOutRootCallsAnotherModulesPublicMock() async throws {
		// `Root`'s mock cannot build `Panel`, whose initializer is `package`, so it calls `Panel`'s public mock, a place
		// whose record copies the call's text: the call is written to lines of its own.
		let modules = [
			ModuleFixture(name: "Core", packageName: "core", swiftFileContent: [
				"""
				import SafeDI

				@Instantiable
				public final class Leaf: Instantiable {
				    public init() {}
				}

				@Instantiable(generateMock: .public)
				public final class Panel: Instantiable {
				    package init(leaf: Leaf) {
				        self.leaf = leaf
				    }

				    @Instantiated public let leaf: Leaf
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
				"""
				import Core
				import SafeDI

				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(panel: Panel) {
				        self.panel = panel
				    }

				    @Instantiated public let panel: Panel
				}
				""",
			], dependencies: ["Core"]),
		]
		let (outcomeStream, outcomeContinuation) = AsyncStream.makeStream(of: String.self)
		let (walkStream, walkContinuation) = AsyncStream.makeStream(of: String.self)
		_ = try await MockLowering.$typeKeyLayoutObserver.withValue({ mockedType, outcome in outcomeContinuation.yield("\(mockedType): \(outcome)") }) {
			try await MockLowering.$rootWalkObserver.withValue({ mockedType, statementCount in walkContinuation.yield("\(mockedType): \(statementCount)") }) {
				try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
			}
		}
		outcomeContinuation.finish()
		walkContinuation.finish()
		var outcomes = [String]()
		for await outcome in outcomeStream {
			outcomes.append(outcome)
		}
		var walks = [String]()
		for await walk in walkStream {
			walks.append(walk)
		}

		#expect(outcomes == ["Root: laidOut"])
		// `Panel`'s public mock, which the type key never lays out, is walked once for its statements.
		#expect(walks.sorted() == ["Panel: 1", "Root: 0"])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// What `generate` returns, each mocked type's layout outcome, and the statements each walk of a mock root wrote.
	private mutating func observingWalks(
		_ generate: (inout [URL]) async throws -> TestOutput,
	) async throws -> (output: TestOutput, outcomes: [String], walks: [String]) {
		let (outcomeStream, outcomeContinuation) = AsyncStream.makeStream(of: String.self)
		let (walkStream, walkContinuation) = AsyncStream.makeStream(of: String.self)
		var filesToDelete = filesToDelete
		let output = try await MockLowering.$typeKeyLayoutObserver.withValue({ mockedType, outcome in outcomeContinuation.yield("\(mockedType): \(outcome)") }) {
			try await MockLowering.$rootWalkObserver.withValue({ mockedType, statementCount in walkContinuation.yield("\(mockedType): \(statementCount)") }) {
				try await generate(&filesToDelete)
			}
		}
		self.filesToDelete = filesToDelete
		outcomeContinuation.finish()
		walkContinuation.finish()
		var outcomes = [String]()
		for await outcome in outcomeStream {
			outcomes.append(outcome)
		}
		var walks = [String]()
		for await walk in walkStream {
			walks.append(walk)
		}
		return (output, outcomes, walks)
	}

	private static let treeFixture = [
		"Parent.swift": """
		@Instantiable(generateMock: true)
		public struct Parent: Instantiable {
		    public init(child: Child) {
		        self.child = child
		    }
		    @Instantiated let child: Child
		}
		""",
		"Child.swift": """
		@Instantiable
		public struct Child: Instantiable {
		    public init(grandchild: Grandchild) {
		        self.grandchild = grandchild
		    }
		    @Instantiated let grandchild: Grandchild
		}
		""",
		"Grandchild.swift": """
		@Instantiable
		public struct Grandchild: Instantiable {
		    public init() {}
		}
		""",
	]

	private static let fallbackFixture = [
		"Parent.swift": """
		@Instantiable(generateMock: true)
		public struct Parent: Instantiable {
		    public init(service: MyService) {
		        self.service = service
		    }
		    @Instantiated let service: MyService
		}
		""",
		"Database.swift": """
		@Instantiable
		public struct Database: Instantiable {
		    public init() {}
		}
		""",
		"MyService.swift": """
		@Instantiable
		public struct MyService: Instantiable {
		    public init(database: Database) {
		        self.database = database
		    }
		    @Instantiated let database: Database
		}
		""",
		"MyServiceMock.swift": """
		@Instantiable(mockOnly: true)
		extension MyService {
		    public static func mock() -> MyService { MyService(database: Database()) }
		}
		""",
	]
}
