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
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_refusesNodeForItsOtherKind_whenAKindClaimsIt() async throws {
		// No declaration fulfills `Analytics`, so `Root`'s property is a node that is always `nil` and that no initializer
		// builds: two kinds stage 1 does not make. A claim that discharges the first leaves the world refused for the second.
		let (_, reports) = try await NodeRecordsObservation.$claimsForTesting.withValue(["Analytics": ["unavailableOrInlineSeam"]]) {
			try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
				try await executeSafeDIToolTest(swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(analytics: Analytics?) {
					        self.analytics = analytics
					    }

					    @Instantiated(onlyIfAvailable: true) let analytics: Analytics?
					}
					""",
					"""
					public struct Analytics {}
					""",
				], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			}
		}
		#expect(reports.map(\.refusal) == ["noInitializer"])
		#expect(reports.map(\.everyRefusal) == [["noInitializer"]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutTheOrdinaryModuleFromNodeRecords_whenItHasFortyScreens() async throws {
		// The ordinary module's shape (designs/per-type-facts/ordinary.py): services the root builds, and layers of four
		// screens, each forwarding an ID to its view model, every third building an avatar, each opening screens of the
		// next layer. Every node is a constant or an `Instantiator` built by its initializer, so nothing refuses.
		let (_, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: Self.ordinaryModule(screenCount: 40), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.map(\.root) == ["Root"])
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_makesARecordPerNode_whenTheTreeReachesEachNodeOnExponentiallyManyPaths() async throws {
		// Soundness rule 5: each layer builds the next twice, so the tree has a place per path, and node records one record
		// per node.
		var counts = [[Int]]()
		for layerCount in [4, 8] {
			var types = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let layer: Layer1"])]
			for layer in 1...layerCount {
				let declarations = layer == layerCount
					? ["@Received let session: Session"]
					: ["@Received let session: Session", "@Instantiated let first: Layer\(layer + 1)", "@Instantiated let second: Layer\(layer + 1)"]
				types.append(seamFixtureType(named: "Layer\(layer)", isFinalClass: true, declarations: declarations))
			}
			types.append(seamFixtureType(named: "Session", isFinalClass: true, declarations: []))
			let (_, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { [types] filesToDelete in
				try await executeSafeDIToolTest(swiftFileContent: types, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete, skipCompileVerification: true)
			}
			counts += reports.map { [$0.recordCount, $0.treePlaceCount] }
		}
		#expect(counts == [[8, 16], [16, 256]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresOneFunctionPerBuilderOfOneLabel_whenSharedPlacesInTwoScopesDeclareIt() async throws {
		// `Detail`'s `itemBuilder` is one node, reached from `first` and `second`, while `Root` declares an `itemBuilder` of
		// its own: the allocator meets the label from three scopes, two of them parents of one shared place, and declares one
		// function for the label, which `Detail`'s function and the root both call.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let itemBuilder: Instantiator<Item>", "@Instantiated let first: First", "@Instantiated let second: Second"]),
				seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let detail: Detail"]),
				seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated let detail: Detail"]),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Instantiated let itemBuilder: Instantiator<Item>"]),
				seamFixtureType(named: "Item", isFinalClass: true, declarations: []),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_itemBuilder() -> Item {
			            Item()
			        }
			        let itemBuilder = Instantiator<Item>(__safeDI_itemBuilder)
			        func __safeDI_detail() -> Detail {
			            let itemBuilder = Instantiator<Item>(__safeDI_itemBuilder)
			            return Detail(itemBuilder: itemBuilder)
			        }
			        func __safeDI_first() -> First {
			            let detail: Detail = __safeDI_detail()
			            return First(detail: detail)
			        }
			        let first: First = __safeDI_first()
			        func __safeDI_second() -> Second {
			            let detail: Detail = __safeDI_detail()
			            return Second(detail: detail)
			        }
			        let second: Second = __safeDI_second()
			        self.init(itemBuilder: itemBuilder, first: first, second: second)
			    }
			}
			""",
		])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutASeamBuiltInlineAsTheTreeDoes_whenNoModuleGeneratesItsInitializer() async throws {
		// A seam in a directory a `#SafeDIConfiguration` adds is in no module's own files, so a tree that reaches it builds
		// it inline, ending its construction with the comment that says why: node records make it as a node built by its
		// initializer, with that comment.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					#SafeDIConfiguration(
					    additionalDirectoriesToInclude: ["$ADDITIONAL_DIRECTORY"]
					)
					""",
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(session: Session, screen: Screen) {
					        self.session = session
					        self.screen = screen
					    }

					    @Instantiated let session: Session
					    @Instantiated let screen: Screen
					}
					""",
					"""
					@Instantiable
					public struct Session: Instantiable {
					    public init() {}
					}
					""",
				],
				additionalDirectorySwiftFileContent: [
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable {
					    public init(detail: Detail) {
					        self.detail = detail
					    }

					    @Instantiated let detail: Detail
					}
					""",
					"""
					@Instantiable
					public struct Detail: Instantiable {
					    public init(session: Session) {
					        self.session = session
					    }

					    @Received let session: Session
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        let session = Session()
			        func __safeDI_screen() -> Screen {
			            let detail = Detail(session: session)
			            return Screen(detail: detail) // Built inline: SafeDI does not know which module declares `Screen`, so this tree cannot call the initializer SafeDI generates for it.
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(session: session, screen: screen)
			    }
			}
			""",
		])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutASeamCallAsTheTreeDoes_whenTheCallPassesNoBuilder() async throws {
		// `App`'s `Root` reaches `Feature`'s seam `Screen`, which it calls through the initializer SafeDI generates for it,
		// after the guard line: node records make the call's record, guard line included, and the root is laid out from them
		// as the tree writes it.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "App", swiftFileContent: [
						"""
						@Instantiable
						public struct Session: Instantiable {
						    public init() {}
						}
						""",
						"""
						@Instantiable(generateDependencyTree: true)
						public struct Screen: Instantiable {
						    public init(detail: Detail) {
						        self.detail = detail
						    }

						    @Instantiated let detail: Detail
						}
						""",
						"""
						@Instantiable
						public struct Detail: Instantiable {
						    public init(session: Session) {
						        self.session = session
						    }

						    @Received let session: Session
						}
						""",
					], dependencies: []),
					ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
						"""
						import Feature

						@Instantiable(isRoot: true)
						public struct Root: Instantiable {
						    public init(session: Session, screen: Screen) {
						        self.session = session
						        self.screen = screen
						    }

						    @Instantiated let session: Session
						    @Instantiated let screen: Screen
						}
						""",
					], dependencies: ["Feature"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        let session = Session()
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_1E2B55CC1D77755A.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen(__safeDI_session: session)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(session: session, screen: screen)
		    }
		}
		"""])
		// `Screen`'s own tree reads its deferred parameter through its memo, which node records read as its tree does; a
		// seam's own tree is compared, not laid out.
		#expect(reports.map(\.root) == ["Screen", "Root"])
		#expect(reports.map(\.refusal) == ["notLaidOut", nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [false, true])
		#expect(reports.map(\.recordCount) == [1, 2])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_makesTheRecordOfASeamCallAsTheTreeDoes_whenTheCallPassesABuilderUp() async throws {
		// `Middle`'s seam `Home` calls `Feature`'s seam `Screen`, whose hole `api` nothing `Middle` declares fulfills: the call
		// passes up the member of `Home`'s own builder struct for its case, which node records read from `Home`'s signature,
		// as the tree records it beside its text.
		let (_, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "App", swiftFileContent: [
						"""
						public protocol Api {}

						@Instantiable(generateDependencyTree: true)
						public struct Screen: Instantiable {
						    public init(api: any Api) {
						        self.api = api
						    }

						    @Instantiated let api: any Api
						}
						""",
					], dependencies: []),
					ModuleFixture(name: "Middle", packageName: "App", swiftFileContent: [
						"""
						import Feature

						@Instantiable(generateDependencyTree: true)
						public struct Home: Instantiable {
						    public init(screen: Screen) {
						        self.screen = screen
						    }

						    @Instantiated let screen: Screen
						}
						""",
					], dependencies: ["Feature"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(reports.map(\.root) == ["Screen", "Home"])
		// The records of `Screen`'s tree, which holds its hole, and of `Home`'s are made, and a seam's own tree is not laid out.
		#expect(reports.map(\.refusal) == ["notLaidOut", "notLaidOut"])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutAnUnavailableDependencyAsTheTreeDoes_whenNoDeclarationFulfillsItsType() async throws {
		// Nothing fulfills `any Analytics`, so `Screen`'s property instantiated only if available is bound to `nil`, which node
		// records write as the tree does.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let screen: Screen
					    public init(screen: Screen) { self.screen = screen }
					}
					""",
					"""
					@Instantiable public final class Screen: Instantiable {
					    @Instantiated(onlyIfAvailable: true) let analytics: (any Analytics)?
					    public init(analytics: (any Analytics)?) { self.analytics = analytics }
					}
					""",
					"""
					public protocol Analytics {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen() -> Screen {
			            let analytics: (any Analytics)? = nil
			            return Screen(analytics: analytics)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(screen: screen)
			    }
			}
			""",
		])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_refusesWorldAsReadAnsweredTwoWays_whenAMemberOfALoopOfBuildersIsOwedItsBindings() async throws {
		// `Editor` receives `editorBuilder`, the `Instantiator` being built around it: a member of a loop of builders, whose
		// bindings made again the facts still owe (`madeAgain`).
		let (_, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(editorBuilder: Instantiator<Editor>) {
				        self.editorBuilder = editorBuilder
				    }
				    @Instantiated let editorBuilder: Instantiator<Editor>
				}
				""",
				"""
				@Instantiable
				public struct Editor: Instantiable {
				    public init(editorBuilder: Instantiator<Editor>?) {
				        self.editorBuilder = editorBuilder
				    }
				    @Received(onlyIfAvailable: true) let editorBuilder: Instantiator<Editor>?
				}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.map(\.everyRefusal) == [["builderLoop", "readAnsweredTwoWays"]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_refusesWorldAsReadAnsweredTwoWays_whenADeclarationIsBuiltInsideAFillOfASeamsHole() async throws {
		// `App`'s root calls `Feature`'s seam `Screen` and fills its hole `api` with `LiveApi`: whether the hole's property
		// is still being built inside its fill the facts still owe the fill and what it builds (`fillBeingBuilt`).
		let (_, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "App", swiftFileContent: [
						"""
						public protocol Api {}

						@Instantiable(generateDependencyTree: true)
						public struct Screen: Instantiable {
						    public init(api: any Api) {
						        self.api = api
						    }

						    @Instantiated let api: any Api
						}
						""",
					], dependencies: []),
					ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
						"""
						import Feature

						@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
						public struct LiveApi: Api, Instantiable {
						    public init() {}
						}

						@Instantiable(isRoot: true)
						public struct Root: Instantiable {
						    public init(screen: Screen) {
						        self.screen = screen
						    }

						    @Instantiated let screen: Screen
						}
						""",
					], dependencies: ["Feature"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(reports.filter { $0.root == "Root" }.map { $0.everyRefusal.contains("readAnsweredTwoWays") } == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_refusesMockWorldAsReadAnsweredTwoWays_whenTheMockRootsPinsRecordsAndBindingsAreOwed() async throws {
		// The facts still owe every declaration of a mock root's world its pins, required-receive records and bindings
		// (`mockRootPin`, `mockRootRecord`, `mockRootBinding`), which are set together.
		let (_, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public struct Root: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }
				    @Instantiated let service: Service
				}
				""",
				"""
				@Instantiable
				public struct Service: Instantiable {
				    public init() {}
				}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter(\.isMockRoot).map(\.everyRefusal) == [["readAnsweredTwoWays"]])
	}

	@Test
	func nodeRecordsFiles_callNoScopeGeneratorAndReadNoText_whenReadAsSource() throws {
		// Soundness rule 2: a record is made from per-type facts, never from a tree's generator or text it spelled. Only
		// the static helpers of `ScopeGenerator` listed here are called, until they move: a new one is a decision. The
		// generator's hook (`DependencyTreeGenerator+NodeRecords.swift`) also calls `rootInitializer(of:)`, and plans the
		// tree beside the records for the comparison. A mock world's records (`NodeRecords+MockConstruction.swift`) read two
		// more, both facts of one type: its default-valued parameters, and the name of the configuration it declares.
		let directory = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("Sources/SafeDICore/Generators/NodeRecords")
		let staticHelpers: Set = ["functionName", "standardIndent", "provides", "referencingDeclaration", "aliasDeclaration", "isBuilder", "DefaultParameter", "mockConfigurationStructName"]
		let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".swift") && $0 != "DependencyTreeGenerator+NodeRecords.swift" }.sorted()
		#expect(files.count >= 4)
		for file in files {
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

	/// The ordinary module (designs/per-type-facts/ordinary.py) at `screenCount` screens, with each screen opening the
	/// next layer's screens in turn, two or three of them, in place of the script's seeded sample.
	private static func ordinaryModule(screenCount: Int) -> [String] {
		func type(_ name: String, _ properties: [(attribute: String, label: String, type: String)], attribute: String = "@Instantiable") -> String {
			let parameters = properties.map { "\($0.label): \($0.type)" }.joined(separator: ", ")
			let assignments = properties.map { "        self.\($0.label) = \($0.label)\n" }.joined()
			let declarations = properties.map { "    \($0.attribute) let \($0.label): \($0.type)\n" }.joined()
			return "\(attribute)\npublic final class \(name): Instantiable {\n    public init(\(parameters)) {\n\(assignments)    }\n\n\(declarations)}\n"
		}
		var types = ["Network", "Database", "ImageCache"].map { type($0, []) }
		types.append(type("ImageLoader", [("@Received", "imageCache", "ImageCache")]))
		types.append(type("Avatar", [("@Instantiated", "imageLoader", "ImageLoader")]))
		let layers = stride(from: 0, to: screenCount, by: 4).map { Array($0..<min($0 + 4, screenCount)) }
		types.append(type("Root", [("@Instantiated", "network", "Network"), ("@Instantiated", "database", "Database"), ("@Instantiated", "imageCache", "ImageCache")] + layers[0].map { ("@Instantiated", "screen\($0)Builder", "Instantiator<Screen\($0)>") }, attribute: "@Instantiable(isRoot: true)"))
		for (layerIndex, layer) in layers.enumerated() {
			for screen in layer {
				types.append(type("Repository\(screen)", [("@Received", "database", "Database"), ("@Received", "network", "Network")]))
				types.append(type("ViewModel\(screen)", [("@Received", "id", "Int"), ("@Instantiated", "repository", "Repository\(screen)")]))
				var properties = [("@Forwarded", "id", "Int"), ("@Instantiated", "viewModel", "ViewModel\(screen)")]
				if screen % 3 == 0 {
					properties.append(("@Instantiated", "avatar", "Avatar"))
				}
				if layerIndex + 1 < layers.count {
					let next = layers[layerIndex + 1]
					let openedCount = min(next.count, 2 + screen % 2)
					let opened = (0..<openedCount).map { next[(screen + $0) % next.count] }.sorted()
					properties += opened.map { ("@Instantiated", "screen\($0)Builder", "Instantiator<Screen\($0)>") }
				}
				types.append(type("Screen\(screen)", properties))
			}
		}
		return types
	}

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
