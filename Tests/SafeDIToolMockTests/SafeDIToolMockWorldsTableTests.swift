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

/// The mock worlds' table (`MockWorldsTable`): one entry per distinct declaration of a module's mock worlds, and which
/// of them a world may take from the table, read through `MockWorldsTableObservation`.
struct SafeDIToolMockWorldsTableTests: ~Copyable {
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
	mutating func generate_countsEachSharedDeclarationOnce_whenMockRootsShareSubtree() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct AlphaScreen: Instantiable {
					    public init(store: SessionStore) {
					        self.store = store
					    }

					    @Instantiated let store: SessionStore
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct BetaScreen: Instantiable {
					    public init(store: SessionStore) {
					        self.store = store
					    }

					    @Instantiated let store: SessionStore
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct GammaScreen: Instantiable {
					    public init(store: SessionStore) {
					        self.store = store
					    }

					    @Instantiated let store: SessionStore
					}
					""",
					"""
					@Instantiable
					public struct SessionStore: Instantiable {
					    public init(clock: Clock) {
					        self.clock = clock
					    }

					    @Instantiated let clock: Clock
					}
					""",
					"""
					@Instantiable
					public struct Clock: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// Each world holds its root, `store` and `clock`: nine declarations, of which `store` and `clock` are the same two
		// in every world.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 5,
				shareableDeclarationCount: 2,
				worlds: [
					.init(mockedType: "AlphaScreen", rootDeclaration: 0, declarationCount: 3, shareableDeclarationCount: 2),
					.init(mockedType: "BetaScreen", rootDeclaration: 3, declarationCount: 3, shareableDeclarationCount: 2),
					.init(mockedType: "GammaScreen", rootDeclaration: 4, declarationCount: 3, shareableDeclarationCount: 2),
				],
			),
		])
		#expect(reports.map { $0.worlds.map(\.declarationCount).reduce(0, +) } == [9])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_makesExactlyDeclarationsReachingCycleUnshareable_whenSubtreeHoldsCycle() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Dashboard: Instantiable {
					    public init(holder: Holder, banner: Banner) {
					        self.holder = holder
					        self.banner = banner
					    }

					    @Instantiated let holder: Holder
					    @Instantiated let banner: Banner
					}
					""",
					"""
					@Instantiable
					public struct Holder: Instantiable {
					    public init(editor: Editor) {
					        self.editor = editor
					    }

					    @Instantiated let editor: Editor
					}
					""",
					"""
					@Instantiable
					public struct Editor: Instantiable {
					    public init(previewBuilder: Instantiator<Preview>) {
					        self.previewBuilder = previewBuilder
					    }

					    @Instantiated let previewBuilder: Instantiator<Preview>
					}
					""",
					"""
					@Instantiable
					public struct Preview: Instantiable {
					    public init(editor: Editor) {
					        self.editor = editor
					    }

					    @Instantiated let editor: Editor
					}
					""",
					"""
					@Instantiable
					public struct Banner: Instantiable {
					    public init(icon: Icon) {
					        self.icon = icon
					    }

					    @Instantiated let icon: Icon
					}
					""",
					"""
					@Instantiable
					public struct Icon: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// `editor` and `previewBuilder` form the cycle, which `holder` reaches; `banner` and `icon` reach none, and the root
		// is its world's own.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 6,
				shareableDeclarationCount: 2,
				worlds: [
					.init(mockedType: "Dashboard", rootDeclaration: 0, declarationCount: 6, shareableDeclarationCount: 2),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_makesDeclarationsReachingHoleUnshareable_whenPublicMockHoldsHole() async throws {
		let reports = try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: .public)
					public struct Screen: Instantiable {
					    public init(panel: Panel, badge: Badge) {
					        self.panel = panel
					        self.badge = badge
					    }

					    @Instantiated let panel: Panel
					    @Instantiated let badge: Badge
					}
					""",
					"""
					@Instantiable
					public struct Panel: Instantiable {
					    public init(gadget: Gadget) {
					        self.gadget = gadget
					    }

					    @Instantiated let gadget: Gadget
					}
					""",
					"""
					public struct Gadget {}
					""",
					"""
					@Instantiable
					public struct Badge: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// Nothing the module sees fulfills `gadget`, so the public mock's world holds it as a hole, a place its mock's
		// builder fills: `panel` reaches it, and only `badge` is shareable.
		#expect(reports == [
			MockWorldsTableReport(
				declarationCount: 4,
				shareableDeclarationCount: 1,
				worlds: [
					.init(mockedType: "Screen", rootDeclaration: 0, declarationCount: 4, shareableDeclarationCount: 1),
				],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_givesSameCountsAndIDsInMockRootOrder_whenTypesSourceOrderIsReversed() async throws {
		// Twenty-two mock roots: the even ones build `store`, the odd ones `feed`, and both build `clock`.
		var declarations = (0..<22).map { index in
			let name = "Screen" + (index < 10 ? "0" : "") + String(index)
			let (label, type) = index.isMultiple(of: 2) ? ("store", "Store") : ("feed", "Feed")
			return """
			@Instantiable(generateMock: true)
			public struct \(name): Instantiable {
			    public init(\(label): \(type)) {
			        self.\(label) = \(label)
			    }

			    @Instantiated let \(label): \(type)
			}
			"""
		}
		for type in ["Store", "Feed"] {
			declarations.append("""
			@Instantiable
			public struct \(type): Instantiable {
			    public init(clock: Clock) {
			        self.clock = clock
			    }

			    @Instantiated let clock: Clock
			}
			""")
		}
		declarations.append("""
		@Instantiable
		public struct Clock: Instantiable {
		    public init() {}
		}
		""")
		var reports = [[MockWorldsTableReport]]()
		for orderedDeclarations in [declarations, declarations.reversed()] {
			let source = orderedDeclarations.joined(separator: "\n\n")
			await reports.append(try Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
				try await executeSafeDIToolTest(
					swiftFileContent: [],
					swiftFileContentByFilePath: ["Screens.swift": source],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			})
		}
		// The first world meets its root, `store` and `clock`, the second its root and `feed`, and every later world only
		// its root, in the order the mock roots are lowered.
		var worlds = [MockWorldsTableReport.World]()
		for index in 0..<22 {
			let rootDeclaration = switch index {
			case 0: 0
			case 1: 3
			default: index + 3
			}
			worlds.append(.init(mockedType: "Screen" + (index < 10 ? "0" : "") + String(index), rootDeclaration: rootDeclaration, declarationCount: 3, shareableDeclarationCount: 2))
		}
		let expected = [MockWorldsTableReport(declarationCount: 25, shareableDeclarationCount: 3, worlds: worlds)]
		#expect(reports == [expected, expected])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsNoMockWorldsTable_whenNoTestObservesNodeRecords() async throws {
		let reports = try await NodeRecordsChecks.$observesNodeRecords.withValue(false) {
			try await Self.tableReports(filesToDelete: &filesToDelete) { filesToDelete in
				try await executeSafeDIToolTest(
					swiftFileContent: [
						"""
						@Instantiable(generateMock: true)
						public struct AlphaScreen: Instantiable {
						    public init(clock: Clock) {
						        self.clock = clock
						    }

						    @Instantiated let clock: Clock
						}
						""",
						"""
						@Instantiable
						public struct Clock: Instantiable {
						    public init() {}
						}
						""",
					],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
		}
		#expect(reports.isEmpty)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The reports of the mock worlds' table `body`'s runs hand the observer.
	private static func tableReports(
		filesToDelete: inout [URL],
		_ body: (inout [URL]) async throws -> TestOutput,
	) async throws -> [MockWorldsTableReport] {
		let (stream, continuation) = AsyncStream.makeStream(of: MockWorldsTableReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		_ = try await MockWorldsTableObservation.$observer.withValue({ continuation.yield($0) }) {
			try await body(&filesMade)
		}
		continuation.finish()
		var reports = [MockWorldsTableReport]()
		for await report in stream {
			reports.append(report)
		}
		return reports
	}
}
