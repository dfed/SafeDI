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
	mutating func generate_laysOutRootFromNodeRecords_whenTheRootBuildsNothing() async throws {
		// A root whose tree's body holds nothing is compared at no place, so only a run that builds no tree for it reports it.
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
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootFromNodeRecords_whenTypeRenamesLazilyInstantiatedPropertyAboveItOnlyIfAvailable() async throws {
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(analytics: LazilyInstantiated<Analytics>, child: Child) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let analytics: LazilyInstantiated<Analytics>
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(tracker: LazilyInstantiated<Analytics>?) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received(fulfilledByDependencyNamed: "analytics", ofType: LazilyInstantiated<Analytics>.self, onlyIfAvailable: true) let tracker: LazilyInstantiated<Analytics>?
				}
				""",
				"""
				@Instantiable
				public final class Analytics: Instantiable {
				    public init() {}
				}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(try #require(output.generatedFiles?["Root+SafeDI.swift"]) == generatedFileHeader + """
		extension Root {
		    public convenience init() {
		        func __safeDI_analytics() -> Analytics {
		            Analytics()
		        }
		        let analytics = LazilyInstantiated<Analytics>(__safeDI_analytics)
		        func __safeDI_child() -> Child {
		            #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 7)
		            let tracker: LazilyInstantiated<Analytics>? = analytics
		            #sourceLocation()
		            return Child(tracker: tracker)
		        }
		        let child: Child = __safeDI_child()
		        self.init(analytics: analytics, child: child)
		    }
		}
		""")
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
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
		// `Screen`'s own tree reads its deferred parameter through its memo, which a record reads from its variant's key,
		// seeded from the seam's parameters, so both roots are laid out.
		#expect(reports.map(\.root) == ["Screen", "Root"])
		#expect(reports.map(\.refusal) == [nil, nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true, true])
		#expect(reports.map(\.recordCount) == [1, 2])
		#expect(reports.flatMap(\.differences) == [])
	}

	/// A seam call held in each form of SafeDI's wrappers: the declaration `Root` makes of it, and the lines the tree writes
	/// for it.
	struct WrappedSeamCall: Sendable, CustomTestStringConvertible {
		let declaration: String
		let lines: String

		var testDescription: String {
			declaration
		}

		static let all = [
			WrappedSeamCall(declaration: "@Instantiated let screen: Instantiator<Screen>", lines: """
			        func __safeDI_screen() -> Screen {
			            GUARD
			            return Screen(__safeDI_session: session)
			        }
			        let screen = Instantiator<Screen>(__safeDI_screen)
			"""),
			WrappedSeamCall(declaration: "@Instantiated let screen: SendableInstantiator<Screen>", lines: """
			        @Sendable nonisolated func __safeDI_screen() -> Screen {
			            GUARD
			            return Screen(__safeDI_session: session)
			        }
			        let screen = SendableInstantiator<Screen>(__safeDI_screen)
			"""),
			WrappedSeamCall(declaration: #"@Instantiated(fulfilledByType: "Screen", erasedToConcreteExistential: true) let screen: ErasedInstantiator<Void, AnyScreen>"#, lines: """
			        func __safeDI_screen() -> Screen {
			            GUARD
			            return Screen(__safeDI_session: session)
			        }
			        let screen = ErasedInstantiator<Void, AnyScreen> {
			            AnyScreen(__safeDI_screen())
			        }
			"""),
			WrappedSeamCall(declaration: #"@Instantiated(fulfilledByType: "Screen", erasedToConcreteExistential: true) let screen: SendableErasedInstantiator<Void, AnyScreen>"#, lines: """
			        @Sendable nonisolated func __safeDI_screen() -> Screen {
			            GUARD
			            return Screen(__safeDI_session: session)
			        }
			        let screen = SendableErasedInstantiator<Void, AnyScreen> {
			            AnyScreen(__safeDI_screen())
			        }
			"""),
			WrappedSeamCall(declaration: "@Instantiated let screen: LazilyInstantiated<Screen>", lines: """
			        func __safeDI_screen() -> Screen {
			            GUARD
			            return Screen(__safeDI_session: session)
			        }
			        let screen = LazilyInstantiated<Screen>(__safeDI_screen)
			"""),
			WrappedSeamCall(declaration: "@Instantiated let screen: SendableLazilyInstantiated<Screen>", lines: """
			        @Sendable nonisolated func __safeDI_screen() -> Screen {
			            GUARD
			            return Screen(__safeDI_session: session)
			        }
			        let screen = SendableLazilyInstantiated<Screen>(__safeDI_screen)
			"""),
		]
	}

	@Test(arguments: WrappedSeamCall.all)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutASeamCallAsTheTreeDoes_whenAWrapperHoldsTheCall(wrappedCall: WrappedSeamCall) async throws {
		// `Root` holds its call of `Feature`'s seam `Screen` in a wrapper: node records bind the wrapper of the call's
		// function, its guard line first, as the tree binds a built place of the wrapper's form.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "App", swiftFileContent: [
						"""
						@Instantiable
						public struct Session: Instantiable, Sendable {
						    public init() {}
						}
						""",
						"""
						public protocol ScreenType: Sendable {}

						public struct AnyScreen: Sendable {
						    public init(_ screen: some ScreenType) {}
						}

						@Instantiable(generateDependencyTree: true)
						public struct Screen: Instantiable, ScreenType, Sendable {
						    public init(detail: Detail) {
						        self.detail = detail
						    }

						    @Instantiated let detail: Detail
						}
						""",
						"""
						@Instantiable
						public struct Detail: Instantiable, Sendable {
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
						    public init(session: Session, screen: \(wrappedCall.declaration.components(separatedBy: ": ").last ?? "")) {
						        self.session = session
						        self.screen = screen
						    }

						    @Instantiated let session: Session
						    \(wrappedCall.declaration)
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
		\(wrappedCall.lines.replacingOccurrences(of: "GUARD", with: "_ = Screen.__safeDI_Screen_1E2B55CC1D77755A.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes."))
		        self.init(session: session, screen: screen)
		    }
		}
		"""])
		// A seam's root's keys are seeded from its parameters, so `Screen`'s world, which reads its deferred parameter's
		// instance, is laid out from node records too.
		#expect(reports.map(\.root) == ["Screen", "Root"])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true, true])
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
		// The records of `Screen`'s tree, which holds its hole, and of `Home`'s are made, and each seam's initializers are written
		// around its body laid out from them.
		#expect(reports.map(\.refusal) == [nil, nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true, true])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTheTreeOfASeamCall_whenTwoPathsToOneNodePassUpTwoCases() async throws {
		// `Home` builds `Screen` beneath `Left` and beneath `Right`, one node with one variant, and each path passes up the
		// member of `Home`'s builder struct for its own case: no one read stands for the node, so its call keeps the tree.
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
						    public init(left: Left, right: Right) {
						        self.left = left
						        self.right = right
						    }

						    @Instantiated let left: Left
						    @Instantiated let right: Right
						}

						@Instantiable
						public struct Left: Instantiable {
						    public init(screen: Screen) {
						        self.screen = screen
						    }

						    @Instantiated let screen: Screen
						}

						@Instantiable
						public struct Right: Instantiable {
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
		#expect(reports.map(\.refusal) == [nil, "fill"])
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
	mutating func generate_laysOutRootFromNodeRecords_whenOneVariantsRenameReadsAValueUnderOneParentAndAWrapperUnderTheOther() async throws {
		// `Reader` renames `x`, which `ValueParent` declares as an `X` and `LazyParent` as a `LazilyInstantiated<X>`: one
		// rename keyed by the form that answers it, so it has a variant beneath each parent, and each variant's record binds
		// it as its own key says. Whichever parent the root builds first, the root is laid out from its records.
		var everyRefusal = [[String]]()
		for parents in [["lazyParent: LazyParent", "valueParent: ValueParent"], ["valueParent: ValueParent", "lazyParent: LazyParent"]] {
			let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
				try await executeSafeDIToolTest(swiftFileContent: Self.renameOfAValueAndAWrapper(parents: parents), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			}
			// Each `Reader` reads `x` as its parent declares it: the wrapper's instance beneath `LazyParent`, the value beneath
			// `ValueParent`.
			let expectedCode = if parents.first == "lazyParent: LazyParent" {
				"""
				// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
				// Any modifications made to this file will be overwritten on subsequent builds.
				// Please refrain from editing this file directly.

				extension Root {
				    public convenience init() {
				        func __safeDI_x() -> X {
				            X()
				        }
				        func __safeDI_readerBuilder(x: LazilyInstantiated<X>) -> Reader {
				            #sourceLocation(file: "\(output.fixtures["Reader.swift"])", line: 6)
				            let renamed: X = x.instance
				            #sourceLocation()
				            return Reader(renamed: renamed)
				        }
				        func __safeDI_lazyParent() -> LazyParent {
				            let x = LazilyInstantiated<X>(__safeDI_x)
				            let readerBuilder = Instantiator<Reader> {
				                __safeDI_readerBuilder(x: x)
				            }
				            return LazyParent(readerBuilder: readerBuilder, x: x)
				        }
				        let lazyParent: LazyParent = __safeDI_lazyParent()
				        func __safeDI_holder(x: X) -> Holder {
				            let reader: Reader = __safeDI_reader(x: x)
				            return Holder(reader: reader)
				        }
				        func __safeDI_reader(x: X) -> Reader {
				            #sourceLocation(file: "\(output.fixtures["Reader.swift"])", line: 6)
				            let renamed: X = x
				            #sourceLocation()
				            return Reader(renamed: renamed)
				        }
				        func __safeDI_valueParent() -> ValueParent {
				            let x = X()
				            let holder: Holder = __safeDI_holder(x: x)
				            return ValueParent(x: x, holder: holder)
				        }
				        let valueParent: ValueParent = __safeDI_valueParent()
				        self.init(lazyParent: lazyParent, valueParent: valueParent)
				    }
				}
				"""
			} else {
				"""
				// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
				// Any modifications made to this file will be overwritten on subsequent builds.
				// Please refrain from editing this file directly.

				extension Root {
				    public convenience init() {
				        func __safeDI_holder(x: X) -> Holder {
				            let reader: Reader = __safeDI_reader(x: x)
				            return Holder(reader: reader)
				        }
				        func __safeDI_reader(x: X) -> Reader {
				            #sourceLocation(file: "\(output.fixtures["Reader.swift"])", line: 6)
				            let renamed: X = x
				            #sourceLocation()
				            return Reader(renamed: renamed)
				        }
				        func __safeDI_valueParent() -> ValueParent {
				            let x = X()
				            let holder: Holder = __safeDI_holder(x: x)
				            return ValueParent(x: x, holder: holder)
				        }
				        let valueParent: ValueParent = __safeDI_valueParent()
				        func __safeDI_x() -> X {
				            X()
				        }
				        func __safeDI_readerBuilder(x: LazilyInstantiated<X>) -> Reader {
				            #sourceLocation(file: "\(output.fixtures["Reader.swift"])", line: 6)
				            let renamed: X = x.instance
				            #sourceLocation()
				            return Reader(renamed: renamed)
				        }
				        func __safeDI_lazyParent() -> LazyParent {
				            let x = LazilyInstantiated<X>(__safeDI_x)
				            let readerBuilder = Instantiator<Reader> {
				                __safeDI_readerBuilder(x: x)
				            }
				            return LazyParent(readerBuilder: readerBuilder, x: x)
				        }
				        let lazyParent: LazyParent = __safeDI_lazyParent()
				        self.init(valueParent: valueParent, lazyParent: lazyParent)
				    }
				}
				"""
			}
			#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": expectedCode])
			#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
			#expect(reports.flatMap(\.differences) == [])
			everyRefusal += reports.map(\.everyRefusal)
		}
		#expect(everyRefusal == [[], []])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootFromNodeRecords_whenOneVariantsRenameReadsAValueDeclaredUnderEachOfTwoParents() async throws {
		// Both parents declare `x` as an `X`: two declarations answer the rename's read in one form, so its one record is
		// right under both.
		let (_, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: Self.renameOfAValueAndAWrapper(parents: ["lazyParent: LazyParent", "valueParent: ValueParent"], lazyParentsX: "X"),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.differences) == [])
	}

	/// A root that builds `LazyParent` and `ValueParent` in the order `parents` names, each of which builds a `Reader` that
	/// renames `x`: `LazyParent` declares `x` as `lazyParentsX`, and `ValueParent` as an `X`.
	private static func renameOfAValueAndAWrapper(parents: [String], lazyParentsX: String = "LazilyInstantiated<X>") -> [String] {
		[
			"""
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(\(parents.joined(separator: ", "))) {
			\(parents.map { "        self.\($0.prefix(while: { $0 != ":" })) = \($0.prefix(while: { $0 != ":" }))" }.joined(separator: "\n"))
			    }
			\(parents.map { "    @Instantiated let \($0)" }.joined(separator: "\n"))
			}
			""",
			"""
			@Instantiable
			public final class LazyParent: Instantiable {
			    public init(readerBuilder: Instantiator<Reader>, x: \(lazyParentsX)) {
			        self.readerBuilder = readerBuilder
			        self.x = x
			    }
			    @Instantiated let readerBuilder: Instantiator<Reader>
			    @Instantiated let x: \(lazyParentsX)
			}
			""",
			"""
			@Instantiable
			public final class ValueParent: Instantiable {
			    public init(x: X, holder: Holder) {
			        self.x = x
			        self.holder = holder
			    }
			    @Instantiated let x: X
			    @Instantiated let holder: Holder
			}
			""",
			"""
			@Instantiable
			public final class Holder: Instantiable {
			    public init(reader: Reader) {
			        self.reader = reader
			    }
			    @Instantiated let reader: Reader
			}
			""",
			"""
			@Instantiable
			public final class Reader: Instantiable {
			    public init(renamed: X) {
			        self.renamed = renamed
			    }
			    @Received(fulfilledByDependencyNamed: "x", ofType: X.self) let renamed: X
			}
			""",
			"""
			@Instantiable
			public final class X: Instantiable {
			    public init() {}
			}
			""",
		]
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutLoopAsTheTreeDoes_whenThreeRootBuildersReceiveOneAnotherInARing() async throws {
		// Each member's function begins by making the next member again, and is declared right before its wrapper, as the
		// tree declares it, though each calls the next member's function.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let cBuilder: Instantiator<C>"]),
				seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received let bBuilder: Instantiator<B>"]),
				seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let cBuilder: Instantiator<C>"]),
				seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Received let aBuilder: Instantiator<A>"]),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return A(bBuilder: bBuilder)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        func __safeDI_bBuilder() -> B {
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            return B(cBuilder: cBuilder)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        func __safeDI_cBuilder() -> C {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return C(aBuilder: aBuilder)
			        }
			        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			        self.init(aBuilder: aBuilder, bBuilder: bBuilder, cBuilder: cBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_refusesWorld_whenTwoParentsLoopsMakeOneMemberAgainApart() async throws {
		// The root's `A` and `B` are a loop. `Other` builds `A` as the same property without `B`, so one node would need a
		// function per parent.
		let (_, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let other: Other"]),
				seamFixtureType(named: "Other", isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
				seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received let bBuilder: Instantiator<B>"]),
				seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let aBuilder: Instantiator<A>"]),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.map(\.refusal) == ["builderLoopSharedApart"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_answersWorldsReadsOneWay_whenADeclarationIsBuiltInsideAFillOfASeamsHole() async throws {
		// `App`'s root calls `Feature`'s seam `Screen` and fills its hole `api` with `LiveApi`: the fill channel answers
		// whether the hole's property is still being built inside its fill, so no fact of the fill is owed.
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
		#expect(reports.filter { $0.root == "Root" }.map { $0.everyRefusal.contains("readAnsweredTwoWays") } == [false])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_refusesMockWorldAsReadAnsweredTwoWays_whenTheMockRootsRecordsAndBindingsAreOwed() async throws {
		// The facts still owe every declaration of a mock root's world its required-receive records and bindings
		// (`mockRootRecord`, `mockRootBinding`), which are set together.
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
		// more, both facts of one type: its default-valued parameters, and the name of the configuration it declares. A seam
		// call's fills (`NodeRecords+FillLevels.swift`) are keyed as the tree keys them (`fillKey(of:)`, `fillCaseKey(of:)`)
		// and its dispatchers made by `FillDispatcher`'s statics, as step 3's interface allows. A world with a cycle names a
		// body's functions apart as the tree does (`identifierSafeNames`), from the labels and types of the places the body holds. A
		// mock world with a cycle asks which edges its module's configurations leave out (`CycleEdge`), a fact of the module's
		// types together that the world is made with until an edge fact holds it. A mock world's configuration records
		// (`NodeRecords+MockConfigurations.swift`) read how a mock builds one type (`MockConstruction`), a fact of that type
		// alone, as the walk's records read it.
		let directory = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("Sources/SafeDICore/Generators/NodeRecords")
		let staticHelpers: Set = ["functionName", "standardIndent", "provides", "referencingDeclaration", "aliasDeclaration", "isBuilder", "DefaultParameter", "mockConfigurationStructName", "fillKey", "fillCaseKey", "FillDispatcher", "FillFieldSelection", "identifierSafeNames", "CycleEdge", "MockConstruction"]
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutASeamsOwnRootAsTheTreeDoes_whenItsTreeReadsADeferredParameter() async throws {
		// `Screen`'s tree receives `user`, which `Root` holds lazily, in `Header`, built with `Screen`, and in `Detail`, built
		// behind an instantiator: the seam binds the deferred parameter's memo, and node records read its instance where the
		// tree does, so its root is laid out from them.
		let files = [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: LazilyInstantiated<User>", "@Instantiated let screen: Screen"]),
			seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let detailBuilder: Instantiator<Detail>", "@Instantiated let header: Header"]),
			seamFixtureType(named: "Detail", declarations: ["@Received let user: User"]),
			seamFixtureType(named: "Header", declarations: ["@Received let user: User"]),
			"""
			@Instantiable
			public final class User: Instantiable, Sendable {
			    public init() {}
			}
			""",
		]
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_user: @autoclosure @escaping () -> User) {
		        let user = LazilyInstantiated<User>(__safeDI_user)
		        @inline(never) func __safeDI_detailBuilder() -> Detail {
		            Detail(user: user.instance)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        let header = Header(user: user.instance)
		        self.init(detailBuilder: detailBuilder, header: header)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_08AA1A656B91D4BA {}
		}
		""")
		// A seam's root's keys are seeded from its parameters, the deferred one as its memo, so the world, which reads the
		// memo's instance, is laid out from node records.
		let screenReports = reports.filter { $0.root == "Screen" }
		#expect(screenReports.map(\.refusal) == [nil])
		#expect(screenReports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	mutating func generate_laysOutRenamesOfAWrappersInstanceAsTheTreeDoes_whenTheyRenameAMemoOrALazilyInstantiatedValue() async throws {
		// `Screen` renames its deferred parameter `user`, and so does `Header` beneath it; `Profile`, beneath `Root`, renames the
		// instance of `Root`'s own `LazilyInstantiated`. The tree binds each rename from the wrapper's instance, and so do the
		// node records, so both roots are laid out from them.
		let files = [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: LazilyInstantiated<User>", "@Instantiated let screen: Screen", "@Instantiated let profile: Profile"]),
			seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Received(fulfilledByDependencyNamed: \"user\", ofType: User.self) let account: User", "@Instantiated let header: Header"]),
			seamFixtureType(named: "Header", declarations: ["@Received(fulfilledByDependencyNamed: \"user\", ofType: User.self) let owner: User"]),
			seamFixtureType(named: "Profile", declarations: ["@Received(fulfilledByDependencyNamed: \"user\", ofType: User.self) let owner: User"]),
			"""
			@Instantiable
			public final class User: Instantiable, Sendable {
			    public init() {}
			}
			""",
		]
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_user: @autoclosure @escaping () -> User) {
		        let user = LazilyInstantiated<User>(__safeDI_user)
		        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
		        let account: User = user.instance
		        #sourceLocation()
		        @inline(never) func __safeDI_header() -> Header {
		            #sourceLocation(file: "\(output.fixtures["Header.swift"])", line: 7)
		            let owner: User = user.instance
		            #sourceLocation()
		            return Header(owner: owner)
		        }
		        let header: Header = __safeDI_header()
		        self.init(account: account, header: header)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_08AA1A656B91D4BA {}
		}
		""")
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_user() -> User {
		            User()
		        }
		        let user = LazilyInstantiated<User>(__safeDI_user)
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_08AA1A656B91D4BA.self
		            return Screen(__safeDI_user: user.instance)
		        }
		        let screen: Screen = __safeDI_screen()
		        func __safeDI_profile() -> Profile {
		            #sourceLocation(file: "\(output.fixtures["Profile.swift"])", line: 7)
		            let owner: User = user.instance
		            #sourceLocation()
		            return Profile(owner: owner)
		        }
		        let profile: Profile = __safeDI_profile()
		        self.init(user: user, screen: screen, profile: profile)
		    }
		}
		""")
		// A seam's root's keys are seeded from its parameters, the deferred `user` as its memo, so `Screen`'s renames key and
		// read the memo's instance, as `Root`'s rename reads its own wrapper's, and both roots are laid out.
		#expect(reports.first { $0.root == "Screen" }?.refusal == nil)
		#expect(reports.first { $0.root == "Root" }?.refusal == nil)
		#expect(reports.first { $0.root == "Screen" }?.isLaidOutFromNodeRecords == true)
		#expect(reports.first { $0.root == "Root" }?.isLaidOutFromNodeRecords == true)
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	mutating func generate_laysOutASeamsOwnRootAsTheTreeDoes_whenATypeInItsTreeReceivesADeferredPassThroughByValue() async throws {
		// `Header`, in `Screen`'s own tree, receives `user` by value, with no rename. `Screen` defers the pass-through and binds
		// its memo under the label, which its root's keys are seeded with, so `Header`'s record reads the memo's instance
		// where the tree does.
		let files = [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let screen: Screen"]),
			seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let header: Header"]),
			seamFixtureType(named: "Header", declarations: ["@Received let user: User"]),
			seamFixtureType(named: "User", declarations: []),
		]
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_user: @autoclosure @escaping () -> User) {
		        let user = LazilyInstantiated<User>(__safeDI_user)
		        let header = Header(user: user.instance)
		        self.init(header: header)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_08AA1A656B91D4BA {}
		}
		""")
		#expect(reports.first { $0.root == "Screen" }?.refusal == nil)
		#expect(reports.first { $0.root == "Screen" }?.isLaidOutFromNodeRecords == true)
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	mutating func generate_laysOutASeamsOwnRootAsTheTreeDoes_whenATypeInItsTreeReceivesADeferredPassThroughOnlyIfAvailable() async throws {
		// `Header` receives `user` only if available: `Screen` defers the optional pass-through and binds its memo, whose
		// instance the tree reads, and so does `Header`'s record, from its variant's key.
		let files = [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let screen: Screen"]),
			seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let header: Header"]),
			seamFixtureType(named: "Header", declarations: ["@Received(onlyIfAvailable: true) let user: User?"]),
			seamFixtureType(named: "User", declarations: []),
		]
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_user: @autoclosure @escaping () -> User?) {
		        let user = LazilyInstantiated<User?>(__safeDI_user)
		        let header = Header(user: user.instance)
		        self.init(header: header)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_B61C3DC8DD996187 {}
		}
		""")
		#expect(reports.first { $0.root == "Screen" }?.refusal == nil)
		#expect(reports.first { $0.root == "Screen" }?.isLaidOutFromNodeRecords == true)
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	mutating func generate_laysOutASeamsOwnRootAsTheTreeDoes_whenATypeInASendableFunctionOfItsTreeReceivesADeferredPassThrough() async throws {
		// `Panel`, built in a `SendableInstantiator`'s `@Sendable` function, receives `token`, so `Screen` defers the
		// pass-through `@Sendable` and binds its memo as a `SendableLazilyInstantiated`, which its root's keys are seeded
		// with: `Panel`'s record reads the memo's instance where the tree does.
		let files = [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let token: Token", "@Instantiated let screen: Screen"]),
			seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let panelBuilder: SendableInstantiator<Panel>"]),
			seamFixtureType(named: "Panel", declarations: ["@Received let token: Token"], conformances: ", Sendable"),
			seamFixtureType(named: "Token", declarations: [], conformances: ", Sendable"),
		]
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_token: @autoclosure @escaping @Sendable () -> Token) {
		        let token = SendableLazilyInstantiated<Token>(__safeDI_token)
		        @inline(never) @Sendable nonisolated func __safeDI_panelBuilder() -> Panel {
		            Panel(token: token.instance)
		        }
		        let panelBuilder = SendableInstantiator<Panel>(__safeDI_panelBuilder)
		        self.init(panelBuilder: panelBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_03EF6477B3A206A0 {}
		}
		""")
		#expect(reports.first { $0.root == "Screen" }?.refusal == nil)
		#expect(reports.first { $0.root == "Screen" }?.isLaidOutFromNodeRecords == true)
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	mutating func generate_laysOutASeamCallAsTheTreeDoes_whenTheSeamTakesAParameterOnlyIfAvailable() async throws {
		// `Screen`'s tree receives `token` only if available, so the call passes the caller's `token` where `Root` declares
		// one and `nil` where `Other` does not.
		let files = [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let token: Token", "@Instantiated let screen: Screen"]),
			seamFixtureType(named: "Other", isRoot: true, declarations: ["@Instantiated let screen: Screen"]),
			seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let detail: Detail"]),
			seamFixtureType(named: "Detail", declarations: ["@Received(onlyIfAvailable: true) let token: Token?"]),
			seamFixtureType(named: "Token", declarations: []),
		]
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        let token = Token()
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_F046DCFB1718557F.self
		            return Screen(__safeDI_token: token)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(token: token, screen: screen)
		    }
		}
		""")
		#expect(output.dependencyTreeFiles["Other+SafeDI.swift"] == generatedFileHeader + """
		extension Other {
		    public init() {
		        func __safeDI_screen() -> Screen {
		            _ = Screen.__safeDI_Screen_F046DCFB1718557F.self
		            return Screen(__safeDI_token: nil)
		        }
		        let screen: Screen = __safeDI_screen()
		        self.init(screen: screen)
		    }
		}
		""")
		let callerReports = reports.filter { $0.root == "Root" || $0.root == "Other" }
		#expect(callerReports.map(\.refusal) == [nil, nil])
		#expect(callerReports.map(\.isLaidOutFromNodeRecords) == [true, true])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	mutating func generate_laysOutASeamCallAsTheTreeDoes_whenAnInstantiatorOfTheSeamForwardsItAValue() async throws {
		// `Screen` forwards `token`, so `Root`'s `Instantiator<Screen>` hands the call the value it is forwarded, which the
		// call's function takes as a parameter.
		let files = [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let screenBuilder: Instantiator<Screen>"]),
			seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Forwarded let token: Token", "@Instantiated let detail: Detail"]),
			seamFixtureType(named: "Detail", declarations: ["@Received let token: Token"]),
			seamFixtureType(named: "Token", declarations: []),
		]
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_screenBuilder(token: Token) -> Screen {
		            _ = Screen.__safeDI_Screen_1EB503BFA23A82BA.self
		            return Screen(__safeDI_token: token)
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(token: $0)
		        }
		        self.init(screenBuilder: screenBuilder)
		    }
		}
		""")
		let rootReports = reports.filter { $0.root == "Root" }
		#expect(rootReports.map(\.refusal) == [nil])
		#expect(rootReports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutAHolderOfAForwardingSeamCallInOneFunction_whenTwoParentsRebindWhatTheCallReads() async throws {
		// `P0` and `P1` each instantiate `x1` again and hold a `Holder`, whose `Instantiator<S1>` calls `Feature`'s seam `S1`,
		// forwarding it a token, and reads both parents' `x1`: the holder's function, declared once in the root's body,
		// takes `x1` from each caller and captures only the root's `x0` (stated difference entry 22).
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolMultiModuleTest(modules: Self.holderOfForwardingSeamCallModules(isReversed: false), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Base)
		import Base
		#endif
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        let x0 = X0()
		        let x1 = X1()
		        func __safeDI_holder(x1: X1) -> Holder {
		            func __safeDI_s1Builder(token: Token) -> S1 {
		                _ = S1.__safeDI_S1_D5164CF5F6C535C2.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                return S1(__safeDI_token: token, __safeDI_x0: x0, __safeDI_x1: x1)
		            }
		            let s1Builder = Instantiator<S1> {
		                __safeDI_s1Builder(token: $0)
		            }
		            return Holder(s1Builder: s1Builder)
		        }
		        func __safeDI_p0() -> P0 {
		            let x1 = X1()
		            let holder: Holder = __safeDI_holder(x1: x1)
		            return P0(x1: x1, holder: holder)
		        }
		        let p0: P0 = __safeDI_p0()
		        func __safeDI_p1() -> P1 {
		            let x1 = X1()
		            let holder: Holder = __safeDI_holder(x1: x1)
		            return P1(x1: x1, holder: holder)
		        }
		        let p1: P1 = __safeDI_p1()
		        self.init(x0: x0, x1: x1, p0: p0, p1: p1)
		    }
		}
		""")
		let rootReports = reports.filter { $0.root == "Root" }
		#expect(rootReports.map(\.refusal) == [nil])
		#expect(rootReports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsTheValuesInlineBuilds_whenTwoParentsHoldAHolderOfAForwardingSeamCall(isReversed: Bool) async throws {
		let modules = Self.holderOfForwardingSeamCallModules(isReversed: isReversed)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		guard compileVerificationIsEnabled else { return }
		// The inline build declares every type in one module, where `S1` is built in place.
		let inlineModules = [ModuleFixture(
			name: "App",
			packageName: "App",
			swiftFileContent: inlineFixture(modules.flatMap(\.swiftFileContent)).map {
				$0.replacingOccurrences(of: "import Base\n", with: "").replacingOccurrences(of: "import Feature\n", with: "")
			},
		)]
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: try DifferentialValuePath(output: output, modules: modules),
			knownRight: try DifferentialValuePath(output: inlineOutput, modules: inlineModules),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().p0.holder.s1Builder.instantiate(Token())"), DifferentialValueProbe("Root().p1.holder.s1Builder.instantiate(Token())")],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	mutating func generate_laysOutASeamsOwnRootAsTheTreeDoes_whenItsRenameKeepsADeferredParametersLabel() async throws {
		// `Screen` retypes its pass-through `token` under its own label, so the rename is the parameter's only reader, bound
		// from the parameter's autoclosure, with no memo beside it.
		let files = [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let token: Secret", "@Instantiated let screen: Screen"]),
			"""
			@Instantiable(generateDependencyTree: true)
			public struct Screen: Instantiable {
			    public init(token: any Auth, detailBuilder: Instantiator<Detail>) {
			        self.token = token
			        self.detailBuilder = detailBuilder
			    }

			    @Received(fulfilledByDependencyNamed: "token", ofType: Secret.self) let token: any Auth
			    @Instantiated let detailBuilder: Instantiator<Detail>
			}
			""",
			seamFixtureType(named: "Detail", declarations: ["@Received let token: any Auth"]),
			"""
			public protocol Auth: Sendable {}

			@Instantiable
			public final class Secret: Instantiable, Auth {
			    public init() {}
			}
			""",
		]
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_token __safeDI_token_: @autoclosure @escaping () -> Secret) {
		        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
		        let token: any Auth = __safeDI_token_()
		        #sourceLocation()
		        @inline(never) func __safeDI_detailBuilder() -> Detail {
		            Detail(token: token)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(token: token, detailBuilder: detailBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_55AF83B7D12DE285 {}
		}
		""")
		let screenReports = reports.filter { $0.root == "Screen" }
		#expect(screenReports.map(\.refusal) == [nil])
		#expect(screenReports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.differences) == [])
	}

	/// A wrapper `Root` builds `Reader` in, while `Reader` receives `token` only if available: the declaration `Root` makes
	/// of it, and the lines the tree writes for it.
	struct WrappedOnlyIfAvailableReader: Sendable, CustomTestStringConvertible {
		let declaration: String
		let lines: String

		var testDescription: String {
			declaration
		}

		static let all = [
			WrappedOnlyIfAvailableReader(declaration: "@Instantiated let reader: SendableInstantiator<Reader>", lines: """
			        @Sendable nonisolated func __safeDI_reader() -> Reader {
			            Reader(token: token)
			        }
			        let reader = SendableInstantiator<Reader>(__safeDI_reader)
			"""),
			WrappedOnlyIfAvailableReader(declaration: "@Instantiated let reader: LazilyInstantiated<Reader>", lines: """
			        func __safeDI_reader() -> Reader {
			            Reader(token: token)
			        }
			        let reader = LazilyInstantiated<Reader>(__safeDI_reader)
			"""),
			WrappedOnlyIfAvailableReader(declaration: #"@Instantiated(fulfilledByType: "Reader", erasedToConcreteExistential: true) let reader: ErasedInstantiator<Void, AnyReader>"#, lines: """
			        func __safeDI_reader() -> Reader {
			            Reader(token: token)
			        }
			        let reader = ErasedInstantiator<Void, AnyReader> {
			            AnyReader(__safeDI_reader())
			        }
			"""),
		]
	}

	@Test(arguments: WrappedOnlyIfAvailableReader.all)
	mutating func generate_laysOutRootAsTheTreeDoes_whenAWrapperBuildsATypeThatReceivesAValueOnlyIfAvailable(wrappedReader: WrappedOnlyIfAvailableReader) async throws {
		// `Reader` receives `token` only if available and is built in the function of the wrapper `reader`, which captures the
		// `token` `Root` declares beside it.
		let files = [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let token: Token", wrappedReader.declaration]),
			seamFixtureType(named: "Reader", declarations: ["@Received(onlyIfAvailable: true) let token: Token?"], conformances: ", ReaderType, Sendable"),
			seamFixtureType(named: "Token", declarations: [], conformances: ", Sendable"),
			"""
			public protocol ReaderType: Sendable {}

			public struct AnyReader: Sendable {
			    public init(_ reader: some ReaderType) {}
			}
			""",
		]
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        let token = Token()
		\(wrappedReader.lines)
		        self.init(token: token, reader: reader)
		    }
		}
		""")
		let rootReports = reports.filter { $0.root == "Root" }
		#expect(rootReports.map(\.refusal) == [nil])
		#expect(rootReports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutAFilledSeamCallsDispatchersAsTheTreeDoes_whenTheCallIsTwoPlacesBelowTheRoot() async throws {
		// `App`'s `Root` builds `Outer`, which builds `Inner`, which calls `Feature`'s seam `Screen`, whose hole `api` is beneath
		// the level `detailBuilder` opens: the call's dispatchers sit in a place two places below the root, where the root's
		// functions are found only if every place on the way holds its children's code. Node records lay out the whole root
		// by type, where the tree nests each function where it is built.
		let modules = Self.modulesCallingAFilledSeamTwoPlacesBelowTheRoot
		let (output, reports) = try await NodeRecordsObservation.$recordsFilledCalls.withValue(true) {
			try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
				// Under the plugin, which runs no second pass over module info files that store their positions apart: that pass
				// runs unobserved, and a root that fills a place is laid out from node records only where a test observes them.
				try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .swiftPackagePlugin, filesToDelete: &filesToDelete)
			}
		}
		// The dispatchers are declared first in the root's body, and every function the root's records lay out is beside them.
		#expect(output.modules["App"]?.generatedFiles == ["Root+SafeDI.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Screen() -> Screen.__safeDI_ApiCarrier<any Api> {
		            .init(detailBuilder: __safeDI_apiBuilder_Screen_Detail_Scope())
		        }
		        func __safeDI_apiBuilder_Screen_Detail_Scope() -> Screen.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi()
		                return api
		            })
		        }
		        func __safeDI_inner() -> Inner {
		            func __safeDI_screen() -> Screen {
		                _ = Screen.__safeDI_Screen_1715FFCF39BF335A.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
		                return Screen(__safeDI_apiBuilder: __safeDI_apiBuilder_Screen())
		            }
		            let screen: Screen = __safeDI_screen()
		            return Inner(screen: screen)
		        }
		        func __safeDI_outer() -> Outer {
		            let inner: Inner = __safeDI_inner()
		            return Outer(inner: inner)
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}
		"""])
		let rootReports = reports.filter { $0.root == "Root" }
		#expect(rootReports.map(\.refusal) == [nil])
		#expect(rootReports.map(\.isLaidOutFromNodeRecords) == [true])
		// The root's text differs from the tree's only where it declares its functions, which entry 24 approves.
		let outcomes = rootReports.map { NodeRecordsChecks.outcome(of: $0) }
		#expect(outcomes.map(\.differences) == [[]])
		#expect(outcomes.map(\.approvedEntries) == [[24]])
		#expect(reports.filter { $0.root != "Root" }.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsWhatAFillRequiresOfTheCallerBeforeTheCall_whenTheCallerDeclaresItAfterTheCallsParent() async throws {
		// `LiveApi`, which fills `Screen`'s hole, receives `logger`, which only `Root` declares, after `outer`, whose tree makes the
		// call two places down: the root builds `logger` first, as the tree does, so the fill's function can capture it.
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Api {}",
				seamFixtureType(named: "Screen", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let api: any Api"]),
				seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
			], dependencies: []),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let outer: Outer", "@Instantiated let logger: Logger"]),
				"import Feature\n\n" + seamFixtureType(named: "Outer", isFinalClass: true, declarations: ["@Instantiated let inner: Inner"]),
				"import Feature\n\n" + seamFixtureType(named: "Inner", isFinalClass: true, declarations: ["@Instantiated let screen: Screen"]),
				"""
				import Feature

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public final class LiveApi: Api, Instantiable {
				    public init(logger: Logger) {
				        self.logger = logger
				    }

				    @Received let logger: Logger
				}
				""",
			], dependencies: ["Feature"]),
		]
		let (output, reports) = try await NodeRecordsObservation.$recordsFilledCalls.withValue(true) {
			try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
				// Under the plugin, as `generate_laysOutAFilledSeamCallsDispatchersAsTheTreeDoes_whenTheCallIsTwoPlacesBelowTheRoot`.
				try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .swiftPackagePlugin, filesToDelete: &filesToDelete)
			}
		}
		#expect(output.modules["App"]?.generatedFiles == ["Root+SafeDI.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        let logger = Logger()
		        func __safeDI_inner() -> Inner {
		            func __safeDI_screen() -> Screen {
		                _ = Screen.__safeDI_Screen_AD974FF4533A0485.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
		                func __safeDI_apiBuilder_Screen() -> Screen.__safeDI_ApiCarrier<any Api> {
		                    .init(api: {
		                        let api: any Api = LiveApi(logger: logger)
		                        return api
		                    })
		                }
		                return Screen(__safeDI_apiBuilder: __safeDI_apiBuilder_Screen())
		            }
		            let screen: Screen = __safeDI_screen()
		            return Inner(screen: screen)
		        }
		        func __safeDI_outer() -> Outer {
		            let inner: Inner = __safeDI_inner()
		            return Outer(inner: inner)
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer, logger: logger)
		    }
		}
		"""])
		let rootReports = reports.filter { $0.root == "Root" }
		#expect(rootReports.map(\.refusal) == [nil])
		#expect(rootReports.map(\.isLaidOutFromNodeRecords) == [true])
		// The root's text differs from the tree's only where it declares its functions, which entry 24 approves.
		let outcomes = rootReports.map { NodeRecordsChecks.outcome(of: $0) }
		#expect(outcomes.map(\.differences) == [[]])
		#expect(outcomes.map(\.approvedEntries) == [[24]])
		#expect(reports.filter { $0.root != "Root" }.flatMap(\.differences) == [])
	}

	@Test(arguments: [
		// Outside every function: the root's argument.
		["self.init(outer: outer)", "self.init(outer: __safeDI_outer())"],
		// Inside a function, as it builds its value.
		["return Inner(screen: screen)", "return Inner(screen: __safeDI_screen())"],
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func outcome_failsRoot_whenAFilledCallsRootLaidOutByTheTypeKeyDiffersBesideWhereItDeclaresItsFunctions(replacement: [String]) async throws {
		let (_, reports) = try await NodeRecordsObservation.$recordsFilledCalls.withValue(true) {
			try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
				try await executeSafeDIToolMultiModuleTest(modules: Self.modulesCallingAFilledSeamTwoPlacesBelowTheRoot, integration: .swiftPackagePlugin, filesToDelete: &filesToDelete)
			}
		}
		var report = try #require(reports.first { $0.root == "Root" })
		let texts = try #require(report.comparedTexts)
		#expect(texts.nodeRecords.components(separatedBy: replacement[0]).count == 2)
		// A second difference, which no entry approves, beside entry 24's.
		report.comparedTexts = NodeRecordsComparedTexts(tree: texts.tree, nodeRecords: texts.nodeRecords.replacingOccurrences(of: replacement[0], with: replacement[1]))
		let outcome = NodeRecordsChecks.outcome(of: report)
		#expect(outcome.differences == report.differences)
		#expect(outcome.differences.contains("root: the code laid out from node records differs from the tree’s"))
		#expect(outcome.approvedEntries == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_marksAFilledCallsDispatchersSendable_whenTheCallIsBuiltInItsOwnSendableFunction() async throws {
		// `Root` builds `Screen` through a `SendableInstantiator`, so the call is made inside a `@Sendable` function: the
		// call's dispatchers, which the root declares, are `@Sendable`, as the tree's are.
		let modules = [Self.modulesCallingAFilledSeamTwoPlacesBelowTheRoot[0], ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
			"import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let screenBuilder: SendableInstantiator<Screen>"]),
			"""
			import Feature

			@Instantiable(fulfillingAdditionalTypes: [Api.self])
			public final class LiveApi: Api, Instantiable {
			    public init() {}
			}
			""",
		], dependencies: ["Feature"])]
		let (_, reports) = try await NodeRecordsObservation.$recordsFilledCalls.withValue(true) {
			try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
				try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .swiftPackagePlugin, filesToDelete: &filesToDelete)
			}
		}
		let rootReports = reports.filter { $0.root == "Root" }
		#expect(rootReports.map(\.isLaidOutFromNodeRecords) == [true])
		let texts = try #require(rootReports.first?.comparedTexts)
		#expect(texts.nodeRecords.components(separatedBy: "@Sendable nonisolated func __safeDI_apiBuilder_Screen").count == 3)
		#expect(rootReports.map { NodeRecordsChecks.outcome(of: $0).differences } == [[]])
	}

	@Test(arguments: ["", "@MainActor\n"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func outcome_approvesAFunctionMovedOutOfASendableFunction_whenTheTypeKeyMarksItSendable(rootAttribute: String) async throws {
		// `Root` builds `Outer` through a `SendableInstantiator`: the tree nests `Inner`'s function, plain, inside `Outer`'s
		// `@Sendable` one, where the type key declares it at the root, marked `@Sendable` as the function that calls it
		// requires. Entry 24 approves the move with the mark, whose code compiles under a root of either isolation.
		let modules = [Self.modulesCallingAFilledSeamTwoPlacesBelowTheRoot[0], ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
			"import Feature\n\n" + rootAttribute + seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let outerBuilder: SendableInstantiator<Outer>"]),
			"import Feature\n\n" + seamFixtureType(named: "Outer", isFinalClass: true, declarations: ["@Instantiated let inner: Inner"]),
			"import Feature\n\n" + seamFixtureType(named: "Inner", isFinalClass: true, declarations: ["@Instantiated let screen: Screen"]),
			"""
			import Feature

			@Instantiable(fulfillingAdditionalTypes: [Api.self])
			public final class LiveApi: Api, Instantiable {
			    public init() {}
			}
			""",
		], dependencies: ["Feature"])]
		let (_, reports) = try await NodeRecordsObservation.$recordsFilledCalls.withValue(true) {
			try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
				try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .swiftPackagePlugin, filesToDelete: &filesToDelete)
			}
		}
		let rootReports = reports.filter { $0.root == "Root" }
		let texts = try #require(rootReports.first?.comparedTexts)
		#expect(texts.nodeRecords.components(separatedBy: "@Sendable nonisolated func __safeDI_inner()").count == 2)
		#expect(texts.tree.components(separatedBy: "@Sendable nonisolated func __safeDI_inner()").count == 1)
		let outcomes = rootReports.map { NodeRecordsChecks.outcome(of: $0) }
		#expect(outcomes.map(\.differences) == [[]])
		#expect(outcomes.map(\.approvedEntries) == [[24]])
	}

	// MARK: Private

	/// `App`'s `Root` builds `Outer`, which builds `Inner`, which calls `Feature`'s seam `Screen` and fills its hole `api`.
	private static let modulesCallingAFilledSeamTwoPlacesBelowTheRoot = [
		ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
			"public protocol Api {}",
			seamFixtureType(named: "Screen", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let detailBuilder: Instantiator<Detail>"]),
			seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Instantiated public let api: any Api"]),
		], dependencies: []),
		ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
			"import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let outer: Outer"]),
			"import Feature\n\n" + seamFixtureType(named: "Outer", isFinalClass: true, declarations: ["@Instantiated let inner: Inner"]),
			"import Feature\n\n" + seamFixtureType(named: "Inner", isFinalClass: true, declarations: ["@Instantiated let screen: Screen"]),
			"""
			import Feature

			@Instantiable(fulfillingAdditionalTypes: [Api.self])
			public final class LiveApi: Api, Instantiable {
			    public init() {}
			}
			""",
		], dependencies: ["Feature"]),
	]

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

	/// `Feature`'s seam `S1`, which is forwarded a token and whose child `C0` receives it, `x0` and `x1`, and `App`'s root, whose two parents, `P0`
	/// and `P1`, each instantiate `x1` again and hold a `Holder` of an `Instantiator<S1>`, in holderp0s1's shape (the seam
	/// world switch attack's draw); `isReversed` declares every property list the other way.
	private static func holderOfForwardingSeamCallModules(isReversed: Bool) -> [ModuleFixture] {
		func ordered(_ declarations: [String]) -> [String] {
			isReversed ? declarations.reversed() : declarations
		}
		return [
			ModuleFixture(name: "Base", packageName: "App", swiftFileContent: [
				seamFixtureType(named: "Token", isFinalClass: true, declarations: []),
				seamFixtureType(named: "X0", isFinalClass: true, declarations: []),
				seamFixtureType(named: "X1", isFinalClass: true, declarations: []),
			]),
			ModuleFixture(name: "Feature", packageName: "App", swiftFileContent: [
				seamFixtureType(named: "S1", isSeam: true, isFinalClass: true, declarations: ordered(["@Forwarded let token: Token", "@Instantiated let c0: C0"])),
				seamFixtureType(named: "C0", isFinalClass: true, declarations: ordered(["@Received let token: Token", "@Received let x0: X0", "@Received let x1: X1"])),
			].map { "import Base\n\n" + $0 }, dependencies: ["Base"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ordered(["@Instantiated let x0: X0", "@Instantiated let x1: X1", "@Instantiated let p0: P0", "@Instantiated let p1: P1"])),
				seamFixtureType(named: "P0", isFinalClass: true, declarations: ordered(["@Instantiated let x1: X1", "@Instantiated let holder: Holder"])),
				seamFixtureType(named: "P1", isFinalClass: true, declarations: ordered(["@Instantiated let x1: X1", "@Instantiated let holder: Holder"])),
				seamFixtureType(named: "Holder", isFinalClass: true, declarations: ["@Instantiated let s1Builder: Instantiator<S1>"]),
			].map { "import Base\nimport Feature\n\n" + $0 }, dependencies: ["Base", "Feature"]),
		]
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
			try await NodeRecordsObservation.$observer.withValue(TaskLocalFunction { continuation.yield($0) }) {
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
