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

/// An internal mock's walk lowers a closed subtree once per context (`MockLowering.SubtreeKey`): a later meeting of the
/// same key takes the first meeting's nodes and records. The key must hold every part of the walk state the subtree's
/// records read, or a later meeting gets records its path would not make. Every test compares each mock lowered with
/// sharing against the same mock lowered on every path (`MockSubtreeSharingChecks`), which catches a missing part on
/// the shapes the tests and the fuzzer draw; these tests keep the list of parts complete.
struct SafeDIToolMockSubtreeSharingTests: ~Copyable {
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

	/// Each stored field of the walk is listed with why a shared subtree may ignore it, so a field added to the walk
	/// fails this test until someone decides whether the key must hold it.
	@Test
	func subtreeKey_accountsForEveryFieldOfWalk_whenDecidingWhatSharedSubtreeReads() {
		let walk = MockLowering.Walk(cycleEdges: [], rootLabels: [], uncoveredProperties: [])
		#expect(Self.fieldNames(of: walk) == Set(Self.walkFieldClassification.keys))
	}

	/// The key holds the node's generator and the parts of the walk state `walkFieldClassification` calls keyed.
	@Test
	func subtreeKey_holdsEachKeyedPartOfWalk_whenComparingMeetings() {
		let key = MockLowering.SubtreeKey(
			generator: ObjectIdentifier(Self.self),
			childrenPropertiesGeneratedLater: [],
			renames: [:],
			lazilyInstantiatedNames: [:],
			scope: [],
		)
		#expect(Self.fieldNames(of: key) == ["generator", "childrenPropertiesGeneratedLater", "renames", "lazilyInstantiatedNames", "scope"])
		#expect(Set(Self.walkFieldClassification.filter { $0.value.hasPrefix(Self.keyed) }.keys) == ["renames", "lazilyInstantiatedNames", "propertiesGeneratedLater"])
	}

	/// A screen type built beneath two parents is lowered once: the observer sees one shared meeting, and the shadow that
	/// every test runs finds the mock equal to the walk of every path.
	@Test
	mutating func mock_sharesSubtree_whenTypeWithChildrenIsBuiltBeneathTwoParents() async throws {
		let meetings = try await sharedMeetings(of: Self.screenBeneathTwoParents(screenProperty: "@Instantiated let screen: Screen"))
		#expect(meetings == ["Root": 1])
	}

	/// A subtree that receives a value the mocked type builds shares: both parents see one binding of the label.
	@Test
	mutating func mock_sharesSubtree_whenSubtreeReceivesValueRootBuilds() async throws {
		let meetings = try await sharedMeetings(of: Self.screenBeneathTwoParents(
			screenProperty: "@Instantiated let screen: Screen",
			rootProperties: ["@Instantiated let token: Token"],
			modelProperties: ["@Received let token: Token"],
			extraFiles: [Self.token],
		))
		#expect(meetings == ["Root": 1])
	}

	/// A subtree held in a `LazilyInstantiated` shares.
	@Test
	mutating func mock_sharesSubtree_whenParentsHoldScreenLazily() async throws {
		let meetings = try await sharedMeetings(of: Self.screenBeneathTwoParents(screenProperty: "@Instantiated let screen: LazilyInstantiated<Screen>"))
		#expect(meetings == ["Root": 1])
	}

	/// A subtree held in an `Instantiator` shares.
	@Test
	mutating func mock_sharesSubtree_whenParentsHoldScreenInInstantiator() async throws {
		let meetings = try await sharedMeetings(of: Self.screenBeneathTwoParents(screenProperty: "@Instantiated let screen: Instantiator<Screen>"))
		#expect(meetings == ["Root": 1])
	}

	/// A subtree that reads an alias of a value `mock()` takes shares: the alias reads the root's parameter on both paths.
	@Test
	mutating func mock_sharesSubtree_whenSubtreeAliasesRootParameter() async throws {
		let meetings = try await sharedMeetings(of: Self.screenBeneathTwoParents(
			screenProperty: "@Instantiated let screen: Screen",
			rootProperties: ["@Forwarded let name: String"],
			modelProperties: [#"@Received(fulfilledByDependencyNamed: "name", ofType: String.self) let title: String"#],
		))
		#expect(meetings == ["Root": 1])
	}

	/// A subtree built for an actor's argument reads its overrides into locals, which the key does not hold, so nothing
	/// beneath an actor is shared.
	@Test
	mutating func mock_sharesNothing_whenParentsAreActors() async throws {
		let meetings = try await sharedMeetings(of: Self.screenBeneathTwoParents(
			screenProperty: "@Instantiated let screen: Screen",
			parentKind: "actor",
		))
		#expect(meetings == ["Root": 0])
	}

	/// A subtree inside a `@Sendable` builder function reads its overrides through the function's extraction, so nothing
	/// beneath a `Sendable` wrapper is shared.
	@Test
	mutating func mock_sharesNothing_whenParentsHoldScreenInSendableInstantiator() async throws {
		let meetings = try await sharedMeetings(of: Self.screenBeneathTwoParents(
			screenProperty: "@Instantiated let screen: SendableInstantiator<Screen>",
			sendableScreenAndModel: true,
		))
		#expect(meetings == ["Root": 0])
	}

	/// A root that holds a cycle-closing node shares nothing.
	@Test
	mutating func mock_sharesNothing_whenSubtreeClosesCycle() async throws {
		let meetings = try await sharedMeetings(of: Self.screenBeneathTwoParents(
			screenProperty: "@Instantiated let screen: Screen",
			modelProperties: ["@Instantiated let nextScreen: Instantiator<Screen>"],
		))
		#expect(meetings == ["Root": 0])
	}

	/// A public mock's root shares nothing, also where the type key lays public mocks out
	/// (`MockLowering.laysOutPublicMocksWithTypeKey`): its places' records read their overrides by the path from the root, so
	/// the second `Screen` would read the first's override (`MockLowering.Walk.sharesSubtrees(of:)`).
	@Test
	mutating func mock_sharesNothing_whenRootIsPublicMock() async throws {
		let fixture = Self.screenBeneathTwoParents(screenProperty: "@Instantiated let screen: Screen")
			.map { $0.replacingOccurrences(of: "@Instantiable(generateMock: true)\n", with: "@Instantiable(generateMock: .public)\n") }
		var filesToDelete = filesToDelete
		let outcomes = try await MockLowering.$laysOutPublicMocksWithTypeKey.withValue(true) {
			try await Self.outcomes(of: fixture, filesToDelete: &filesToDelete)
		}
		self.filesToDelete = filesToDelete
		#expect(outcomes.map(\.mockedType) == ["Root"])
		#expect(outcomes.map(\.sharedMeetings) == [0])
	}

	/// A root whose tree calls another module's public mock inline shares nothing: the call's fills read the caller's scope
	/// by path (`MockLowering.Walk.sharesSubtrees(of:)`).
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_sharesNothing_whenSubtreeCallsAnotherModulesPublicMock() async throws {
		// `Panel`, built beneath `First` and `Second`, calls `Feature`'s public mock, whose fill reads the caller's scope.
		let meetings = try await sharedMeetings(ofModules: [
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: ["FeatTypes.swift": """
			import SafeDI

			public protocol Api: AnyObject {}

			@Instantiable(generateMock: .public)
			public final class Feature: Instantiable {
			    init(api: any Api) {
			        self.api = api
			    }

			    @Instantiated let api: any Api
			}
			"""]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppTypes.swift": "import Feat\nimport SafeDI\n\n" + [
				seamFixtureType(named: "Live", isFinalClass: true, declarations: [], conformances: ", Api")
					.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Api.self])\n"),
				seamFixtureType(named: "Panel", isFinalClass: true, declarations: ["@Instantiated let feature: Feature"]),
				seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let panel: Panel"]),
				seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated let panel: Panel"]),
				seamFixtureType(named: "Root", isFinalClass: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"])
					.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n"),
			].joined(separator: "\n\n")], dependencies: ["Feat"]),
		])
		#expect(meetings == ["Root": 0])
	}

	/// A subtree that holds an actor is not closed (`SubtreeFacts.isClosed`): the actor's argument reads its overrides into
	/// locals before its builder function, which the key does not hold, so neither the actor nor a node above it shares.
	@Test
	mutating func mock_sharesNothing_whenSubtreeHoldsActor() async throws {
		let meetings = try await sharedMeetings(of: Self.screenBeneathTwoParents(
			screenProperty: "@Instantiated let screen: Screen",
			modelProperties: ["@Instantiated let store: Store"],
			extraFiles: [
				Self.type("Store", kind: "actor", properties: ["@Instantiated let helper: Helper"]),
				Self.type("Helper", kind: "final class", properties: []),
			],
		))
		#expect(meetings == ["Root": 0])
	}

	/// A subtree that holds a `@Sendable` builder function is not closed: the function reads its overrides through an
	/// extraction whose locals are named by path, so neither the function nor a node above it shares.
	@Test
	mutating func mock_sharesNothing_whenSubtreeHoldsSendableInstantiator() async throws {
		let meetings = try await sharedMeetings(of: Self.screenBeneathTwoParents(
			screenProperty: "@Instantiated let screen: Screen",
			modelProperties: ["@Instantiated let worker: SendableInstantiator<Worker>"],
			extraFiles: [
				Self.type("Worker", kind: "final class", conformances: ", Sendable", properties: ["@Instantiated let helper: Helper"]),
				Self.type("Helper", kind: "final class", conformances: ", Sendable", properties: []),
			],
		))
		#expect(meetings == ["Root": 0])
	}

	/// `Mid` is built beneath `Screen` on two paths: beneath `P1`, `x` is built after `screen`; beneath `P2`, `screen` is
	/// built before `y` and `x`. `Mid`'s children are built before other properties on each path, so the meetings differ
	/// only in `childrenPropertiesGeneratedLater`, and dropping that part (`childrenPropertiesGeneratedLater: []`) shares
	/// `Mid` and hands `Model` the `x` of the wrong path.
	@Test
	mutating func mock_sharesNothing_whenChildrenAreBuiltBeforeOtherSiblings() async throws {
		let meetings = try await sharedMeetings(of: Self.childContextGraph(rootBuildsX: true, screenBuildsMid: true))
		#expect(meetings == ["Root": 0])
	}

	/// `Model` receives `config` as the root's flat parameter, named apart from `Other`'s (`config_ConfigA`), beneath `P1`,
	/// and as `P2`'s own `config` beneath `P2`. Dropping the renames from the key (`renames: [:]`) shares `Screen` and hands
	/// `Model` the parameter's name beneath `P2`.
	@Test
	mutating func mock_sharesNothing_whenRepeatedSubtreeReceivesRenamedParameter() async throws {
		let meetings = try await sharedMeetings(of: [
			Self.type("Root", kind: "final class", generateMock: true, properties: ["@Instantiated let p1: P1", "@Instantiated let p2: P2", "@Instantiated let other: Other"]),
			Self.type("P1", kind: "final class", properties: ["@Instantiated let screen: Screen"]),
			Self.type("P2", kind: "final class", properties: [#"@Instantiated(fulfilledByType: "LiveConfig") let config: any ConfigA"#, "@Instantiated let screen: Screen"]),
			Self.type("Screen", kind: "final class", properties: ["@Instantiated let model: Model"]),
			Self.type("Model", kind: "final class", properties: ["@Received let config: any ConfigA"]),
			Self.type("Other", kind: "final class", properties: ["@Received let config: any ConfigB"]),
			Self.type("LiveConfig", kind: "final class", conformances: ", ConfigA", properties: []),
			Self.protocols(["ConfigA", "ConfigB"]),
		])
		#expect(meetings == ["Root": 0])
	}

	/// `Model` receives `session: LazilyInstantiated<any Session>`, which the mock cannot build, as the wrapper `mock()`
	/// binds beneath `P1` and as `P2`'s own beneath `P2`. The construction memo already builds the two screens with two
	/// generators (`P2`'s wrapper puts its instance in the memo key's `lazilyInstantiatedInstanceProperties`), so nothing
	/// is shared with the wrappers dropped from the key either: the key's `lazilyInstantiatedNames` guards meetings of one
	/// generator that differ in them, which no graph tried reaches.
	@Test
	mutating func mock_sharesNothing_whenRepeatedSubtreeReceivesWrapperBoundApart() async throws {
		let meetings = try await sharedMeetings(of: [
			Self.type("Root", kind: "final class", generateMock: true, properties: ["@Instantiated let p1: P1", "@Instantiated let p2: P2"]),
			Self.type("P1", kind: "final class", properties: ["@Instantiated let screen: Screen"]),
			Self.type("P2", kind: "final class", properties: [#"@Instantiated(fulfilledByType: "LiveSession") let session: LazilyInstantiated<any Session>"#, "@Instantiated let screen: Screen"]),
			Self.type("Screen", kind: "final class", properties: ["@Instantiated let model: Model"]),
			Self.type("Model", kind: "final class", properties: ["@Received let session: LazilyInstantiated<any Session>"]),
			Self.type("LiveSession", kind: "final class", conformances: ", Session", properties: []),
			Self.protocols(["Session"]),
		])
		#expect(meetings == ["Root": 0])
	}

	/// `Model` aliases `x` as `y`: beneath `P1`, which builds `x` lazily, the alias reads `x.instance`; beneath `P2`, the
	/// root's `x`. As above, the construction memo already builds the two screens with two generators, so nothing is
	/// shared with the declarations dropped from the key (`scope: []`) either: the key's `scope` guards meetings of one
	/// generator whose aliases read different declarations, which no graph tried reaches.
	@Test
	mutating func mock_sharesNothing_whenRepeatedSubtreeAliasesDeclarationOnePathHolds() async throws {
		let meetings = try await sharedMeetings(of: [
			Self.type("Root", kind: "final class", generateMock: true, properties: ["@Instantiated let p1: P1", "@Instantiated let p2: P2"]),
			Self.type("P1", kind: "final class", properties: ["@Instantiated let x: LazilyInstantiated<X>", "@Instantiated let screen: Screen"]),
			Self.type("P2", kind: "final class", properties: ["@Instantiated let screen: Screen"]),
			Self.type("Screen", kind: "final class", properties: ["@Instantiated let model: Model"]),
			Self.type("Model", kind: "final class", properties: [#"@Received(fulfilledByDependencyNamed: "x", ofType: X.self) let y: X"#]),
			Self.type("X", kind: "final class", properties: []),
		])
		#expect(meetings == ["Root": 0])
	}

	/// The graph of `mock_sharesNothing_whenChildrenAreBuiltBeforeOtherSiblings` without `Mid` and without the root's `x`:
	/// both screens' models are handed `nil`.
	@Test
	mutating func mock_sharesNothing_whenScreensReceiveOnlyIfAvailableValueBuiltInOtherOrders() async throws {
		let meetings = try await sharedMeetings(of: Self.childContextGraph(rootBuildsX: false, screenBuildsMid: false))
		#expect(meetings == ["Root": 0])
	}

	/// The same graph with an `x` the root builds above both parents.
	@Test
	mutating func mock_sharesNothing_whenScreensReceiveOnlyIfAvailableValueBuiltInOtherOrdersBeneathOuterValue() async throws {
		let meetings = try await sharedMeetings(of: Self.childContextGraph(rootBuildsX: true, screenBuildsMid: false))
		#expect(meetings == ["Root": 0])
	}

	/// A chain whose every layer builds the next layer's type beneath two parents lowers each layer's subtree once, and
	/// the facts the walk holds grow with the layers: one per type on several paths, `Layer1` through `Layer<n>`,
	/// `First1` and `Second1` through `First<n-1>` and `Second<n-1>`, and `Leaf`, so 3n - 1.
	@Test
	mutating func mock_holdsFactsGrowingWithLayers_whenChainOfLayersBuildsNextLayerBeneathTwoParents() async throws {
		var outcomes = [Int: MockLowering.SubtreeSharingOutcome]()
		for layers in [3, 6, 12] {
			outcomes[layers] = try await self.outcomes(of: Self.layeredChain(layers: layers)).first { $0.mockedType == "Root" }
		}
		#expect(outcomes.mapValues(\.sharedMeetings) == [3: 3, 6: 6, 12: 12])
		#expect(outcomes.mapValues(\.heldFacts.generators) == [3: 8, 6: 17, 12: 35])
	}

	/// The chain with labels that repeat at every layer (`first`, `second`, `layer`): a label declared again along the
	/// branch changes nothing the key holds, so each layer's subtree is still lowered once.
	@Test
	mutating func mock_sharesEachLayerOnce_whenChainOfLayersRepeatsLabels() async throws {
		var outcomes = [Int: MockLowering.SubtreeSharingOutcome]()
		for layers in [3, 6, 12] {
			outcomes[layers] = try await self.outcomes(of: Self.layeredChain(layers: layers, suffixesLabels: false)).first { $0.mockedType == "Root" }
		}
		#expect(outcomes.mapValues(\.sharedMeetings) == [3: 3, 6: 6, 12: 12])
		#expect(outcomes.mapValues(\.heldFacts.generators) == [3: 8, 6: 17, 12: 35])
	}

	/// Each layer builds a view model of its own beside the next layer, under one label, `viewModel`: the view models have
	/// no children, so they form no key, and each layer's subtree is still lowered once.
	@Test
	mutating func mock_sharesEachLayerOnce_whenEachLayerBuildsViewModelOfItsOwn() async throws {
		var outcomes = [Int: MockLowering.SubtreeSharingOutcome]()
		for layers in [3, 6, 12] {
			outcomes[layers] = try await self.outcomes(of: Self.layeredChain(layers: layers, suffixesLabels: false, buildsViewModels: true)).first { $0.mockedType == "Root" }
		}
		#expect(outcomes.mapValues(\.sharedMeetings) == [3: 3, 6: 6, 12: 12])
	}

	/// Every layer receives `token` as `any TokenA` while `Other` receives it as `any TokenB`, so `mock()` takes both, named
	/// apart, and each layer's builder function asks whether a receive beneath reads `token` by name
	/// (`MockLowering.receiveReadsLabelByName`). Each such scan visits a node once per context, so the visits grow with the
	/// square of the layers, never with the paths, which double with each layer.
	@Test
	mutating func mock_scansForLabelReadByNameInNodesNotPaths_whenEveryLayerReceivesValueNamedApart() async throws {
		var visits = [Int: Int]()
		for layers in [3, 6, 12] {
			let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
			_ = try await MockLowering.$labelReadScanObserver.withValue({ visitedNodes in
				continuation.yield(visitedNodes)
			}) {
				try await outcomes(of: Self.layeredChain(layers: layers, receivesTokenNamedApart: true))
			}
			continuation.finish()
			for await visitedNodes in stream {
				visits[layers, default: 0] += visitedNodes
			}
		}
		#expect(visits == [3: 24, 6: 102, 12: 420])
	}

	/// The check that every read of a laid-out body names a declaration (`MockLowering.Walk.unresolvedRead(in:declaredAtRoot:)`)
	/// reads each place of the plan once, and a shared subtree's places once for all its meetings, so the places it reads grow
	/// with the layers, never with the paths, which double with each layer. A check that walked each path read 72, 632 and
	/// 40,952 places.
	@Test
	mutating func mock_checksLaidOutReadsInPlacesNotPaths_whenScreensBuildNextLayerBeneathTwoParents() async throws {
		var reads = [Int: Int]()
		for layers in [3, 6, 12] {
			let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
			_ = try await MockLowering.$unresolvedReadObserver.withValue({ readPlaces in
				continuation.yield(readPlaces)
			}) {
				try await outcomes(of: Self.layeredChain(layers: layers))
			}
			continuation.finish()
			for await readPlaces in stream {
				reads[layers, default: 0] += readPlaces
			}
		}
		#expect(reads == [3: 26, 6: 50, 12: 98])
	}

	/// The walk that names a mock's parameters (`ScopeGenerator.treeNames(of:readsFills:)`) visits each node of the layered
	/// chain once per generator and family, and records each other meeting of it, so both grow with the layers, never with
	/// the paths, which double with each layer. Each mock's parameters are classified more than once (its signature, its
	/// lowering), so the counts are of every walk.
	@Test
	mutating func mock_walksTreeNamesInNodesNotPaths_whenScreensBuildNextLayerBeneathTwoParents() async throws {
		var visits = [Int: [Int]]()
		for layers in [3, 6, 12] {
			let (stream, continuation) = AsyncStream.makeStream(of: (visitedNodes: Int, meetings: Int).self)
			_ = try await MockLowering.$treeNamesWalkObserver.withValue({ visitedNodes, meetings in
				continuation.yield((visitedNodes: visitedNodes, meetings: meetings))
			}) {
				try await outcomes(of: Self.layeredChain(layers: layers))
			}
			continuation.finish()
			var totals = [0, 0]
			for await walk in stream {
				totals[0] += walk.visitedNodes
				totals[1] += walk.meetings
			}
			visits[layers] = totals
		}
		#expect(visits == [3: [20, 26], 6: [38, 50], 12: [74, 98]])
	}

	/// `Home`'s public mock promotes `session`, which `Settings` receives, and `Profile` instantiates a `session` of its
	/// own, so the construction memo gives the root's node and `Profile`'s one generator. The tree-names walk meets it first
	/// beneath `profile` where `profile` is declared first, and still lists the root's node, which the plan `Feat`'s
	/// `.safedi` stores reads: `App` calls `Home`'s mock with `session` and the guard `Feat` declares, in either order.
	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_callsPublicMockWithPromotedValue_whenSameGeneratorIsMetFirstBeneathAnotherChild(profileIsDeclaredFirst: Bool) async throws {
		let homeProperties = ["@Instantiated let profile: Profile", "@Instantiated let settings: Settings"]
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: ["FeatTypes.swift": """
				import SafeDI

				@Instantiable
				public final class Session: Instantiable {
				    init() {}
				}

				@Instantiable
				public final class Profile: Instantiable {
				    init(session: Session) {
				        self.session = session
				    }

				    @Instantiated let session: Session
				}

				@Instantiable
				public final class Settings: Instantiable {
				    init(session: Session) {
				        self.session = session
				    }

				    @Received let session: Session
				}

				@Instantiable(generateMock: .public)
				public final class Home: Instantiable {
				    init(profile: Profile, settings: Settings) {
				        self.profile = profile
				        self.settings = settings
				    }

				    \((profileIsDeclaredFirst ? homeProperties : homeProperties.reversed()).joined(separator: "\n    "))
				}
				"""]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppTypes.swift": """
				import Feat
				import SafeDI

				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(home: Home) {
				        self.home = home
				    }

				    @Instantiated let home: Home
				}
				"""], dependencies: ["Feat"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            home: Home.SafeDIOverrides = .init(),
		            session: Session? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                home: home
		            )
		            self.session = session
		        }

		        var home: Home.SafeDIOverrides { __safeDI_storage.home }
		        let session: Session?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                home: Home.SafeDIOverrides
		            ) {
		                self.home = home
		            }

		            let home: Home.SafeDIOverrides
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let session: Session? = safeDIOverrides.session
		        _ = Home.__safeDI_Home_mock_53B5F60DA3BBE2A1.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let home = Home.__safeDI_mock(session: session, safeDIOverrides: safeDIOverrides.home)
		        return Root(home: home)
		    }
		}
		#endif
		""")
	}

	/// The mock root's cycle walk walks a scope reached again only where the context above it reads differently, so a
	/// tree whose screens build the next layer beneath two parents costs a walk per scope, not per path: in the plain
	/// chain, and in one whose parents each declare the `session` every layer receives and build the next layer through an
	/// instantiator. Without the skip, twelve layers walk 20,477 and 28,667 scopes.
	@Test
	mutating func mock_walksCycleCheckInScopesNotPaths_whenScreensBuildNextLayerBeneathTwoParents() async throws {
		var walkedScopes = [Int: [Int]]()
		for layers in [3, 6, 12] {
			var counts = [Int]()
			for files in [Self.layeredChain(layers: layers), Self.layeredSessionChain(layers: layers)] {
				let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
				_ = try await DependencyTreeGenerator.$mockRootCycleWalkObserver.withValue({ walked in
					continuation.yield(walked)
				}) {
					try await executeSafeDIToolTest(
						swiftFileContent: files,
						buildSwiftOutputDirectory: true,
						filesToDelete: &filesToDelete,
					)
				}
				continuation.finish()
				var total = 0
				for await walked in stream {
					total += walked
				}
				counts.append(total)
			}
			walkedScopes[layers] = counts
		}
		#expect(walkedScopes == [3: [11, 12], 6: [20, 21], 12: [38, 39]])
	}

	/// `Shared` receives `service`, which `Mocked` receives and its mock promotes. The walk meets `Shared` first as `Mocked`'s
	/// own child, where nothing builds `service` around it, and then inside the promoted `Service`, which is still being
	/// built there: the second meeting reads another context and is walked, so the cycle is reported.
	@Test
	mutating func mock_throwsCycle_whenScopeWalkedCleanOnEarlierPathReceivesPropertyBeingBuiltOnLaterPath() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Shared.swift"]):7:5: error: Dependency cycle: `Service` -> `Shared` -> `Service`. `Shared` receives `service: Service`, which is still being built when `Shared` is built. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
				\(fixtures["Service.swift"]):1:1: note: `Service` is part of the cycle
				\(fixtures["Shared.swift"]):1:1: note: `Shared` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					Self.type("Mocked", kind: "final class", generateMock: true, properties: ["@Instantiated let shared: Shared", "@Received let service: Service"]),
					Self.type("Service", kind: "final class", properties: ["@Instantiated let shared: Shared"]),
					Self.type("Shared", kind: "final class", properties: ["@Received let service: Service"]),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	/// `Shared` instantiates `service` beneath the promoted `Service` twice: first through the instantiator `holderBuilder`,
	/// which defers the cycle, and then through the constant `other`, which does not. The second context holds `other`,
	/// which `Shared`'s subtree builds again through `service`, so it is walked and the cycle with no deferred hop is
	/// reported.
	@Test
	mutating func mock_throwsCycle_whenScopeWalkedCleanBeneathInstantiatorClosesCycleBeneathConstant() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Shared.swift"]):7:5: error: Dependency cycle: `Service` -> `Other` -> `Shared` -> `Service`. SafeDI accepts a dependency cycle when one of the dependencies that instantiate along it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change one of `service: Service`, `other: Other`, `shared: Shared` to an instantiator.
				\(fixtures["Service.swift"]):1:1: note: `Service` is part of the cycle
				\(fixtures["Other.swift"]):1:1: note: `Other` is part of the cycle
				\(fixtures["Shared.swift"]):1:1: note: `Shared` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					Self.type("Mocked", kind: "final class", generateMock: true, properties: ["@Received let service: Service"]),
					Self.type("Service", kind: "final class", properties: ["@Instantiated let holderBuilder: Instantiator<Holder>", "@Instantiated let other: Other"]),
					Self.type("Holder", kind: "final class", properties: ["@Instantiated let shared: Shared"]),
					Self.type("Other", kind: "final class", properties: ["@Instantiated let shared: Shared"]),
					Self.type("Shared", kind: "final class", properties: ["@Instantiated let service: Service"]),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	/// `Shared` receives `service` beneath the promoted `RealService` twice: first beneath `Holder`, which declares a
	/// `service` of its own that `FakeService` fulfills, and then directly. The two contexts differ only in that
	/// declaration, so the second is walked and the receive of the service still being built is reported.
	@Test
	mutating func mock_throwsCycle_whenScopeWalkedCleanBeneathNearerDeclarationReceivesPropertyBeingBuiltWithoutIt() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Shared.swift"]):7:5: error: Dependency cycle: `ServiceProtocol` -> `Shared` -> `ServiceProtocol`. `Shared` receives `service: ServiceProtocol`, which is still being built when `Shared` is built. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
				\(fixtures["RealService.swift"]):1:1: note: `ServiceProtocol` is part of the cycle
				\(fixtures["Shared.swift"]):1:1: note: `Shared` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public protocol ServiceProtocol {}
					""",
					Self.type("Mocked", kind: "final class", generateMock: true, properties: ["@Received let service: ServiceProtocol"]),
					"""
					@Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self])
					public final class RealService: Instantiable, ServiceProtocol {
					    public init(holder: Holder, shared: Shared) {
					        self.holder = holder
					        self.shared = shared
					    }

					    @Instantiated let holder: Holder
					    @Instantiated let shared: Shared
					}
					""",
					"""
					@Instantiable
					public final class Holder: Instantiable {
					    public init(service: ServiceProtocol, shared: Shared) {
					        self.service = service
					        self.shared = shared
					    }

					    @Instantiated(fulfilledByType: "FakeService") let service: ServiceProtocol
					    @Instantiated let shared: Shared
					}
					""",
					Self.type("FakeService", kind: "final class", conformances: ", ServiceProtocol", properties: []),
					Self.type("Shared", kind: "final class", properties: ["@Received let service: ServiceProtocol"]),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	/// `Screen` instantiates `config`, which the mock cannot build, beneath `First` and beneath `Second`, whose builder function
	/// declares a `config` of its own. The tree-names walk visits `Screen` once, from `First`, so it names `mock()`'s
	/// parameter apart from what a builder function around `Screen` declares on every path that meets it, not only the first.
	@Test
	mutating func mock_namesParameterApart_whenBuilderFunctionOnLaterPathToTypeDeclaresItsLabel() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.screenHiddenOnOnePath,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            first: First.SafeDIMockConfiguration = .init(),
		            second: Second.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                first: first,
		                second: second
		            )
		        }

		        var first: First.SafeDIMockConfiguration { __safeDI_storage.first }
		        var second: Second.SafeDIMockConfiguration { __safeDI_storage.second }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                first: First.SafeDIMockConfiguration,
		                second: Second.SafeDIMockConfiguration
		            ) {
		                self.first = first
		                self.second = second
		            }

		            let first: First.SafeDIMockConfiguration
		            let second: Second.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        config_Config: Config,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_screen(__safeDI_Screen_configuration: Screen.SafeDIMockConfiguration) -> Screen {
		            let model = if let safeDIBuilder = __safeDI_Screen_configuration.model { safeDIBuilder() } else { Model() }
		            return if let safeDIBuilder = __safeDI_Screen_configuration.safeDIBuilder { safeDIBuilder(config_Config, model) } else { Screen(config: config_Config, model: model) }
		        }
		        func __safeDI_first(__safeDI_First_configuration: First.SafeDIMockConfiguration) -> First {
		            let screen: Screen = __safeDI_screen(__safeDI_Screen_configuration: __safeDI_First_configuration.screen)
		            return if let safeDIBuilder = __safeDI_First_configuration.safeDIBuilder { safeDIBuilder(screen) } else { First(screen: screen) }
		        }
		        let first: First = __safeDI_first(__safeDI_First_configuration: safeDIOverrides.first)
		        func __safeDI_second(__safeDI_Second_configuration: Second.SafeDIMockConfiguration) -> Second {
		            let config = if let safeDIBuilder = __safeDI_Second_configuration.config { safeDIBuilder() } else { Setting() }
		            let screen: Screen = __safeDI_screen(__safeDI_Screen_configuration: __safeDI_Second_configuration.screen)
		            return if let safeDIBuilder = __safeDI_Second_configuration.safeDIBuilder { safeDIBuilder(config, screen) } else { Second(config: config, screen: screen) }
		        }
		        let second: Second = __safeDI_second(__safeDI_Second_configuration: safeDIOverrides.second)
		        return Root(first: first, second: second)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
	}

	/// `Root` builds `First`, then `Second`, each of which builds `Screen`, which instantiates a `Config` nothing builds; `Second`
	/// also declares `config`, a `Setting`.
	private static let screenHiddenOnOnePath = [
		Self.type("Root", kind: "final class", generateMock: true, properties: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
		Self.type("First", kind: "final class", properties: ["@Instantiated let screen: Screen"]),
		Self.type("Second", kind: "final class", properties: ["@Instantiated let config: Setting", "@Instantiated let screen: Screen"]),
		Self.type("Setting", kind: "final class", properties: []),
		Self.type("Screen", kind: "final class", properties: ["@Instantiated let config: Config", "@Instantiated let model: Model"]),
		Self.type("Model", kind: "final class", properties: []),
		"""
		public final class Config {}
		""",
	]

	/// A chain that builds each type on one path, as a long chain of features does, holds no facts at all, however long.
	@Test
	mutating func mock_holdsNoFacts_whenChainBuildsEachTypeOnOnePath() async throws {
		var heldFacts = [Int: MockLowering.SubtreeSharingOutcome.HeldFacts]()
		for features in [100, 200, 400] {
			heldFacts[features] = try await outcomes(of: Self.featureChain(features: features)).first { $0.mockedType == "Root" }?.heldFacts
		}
		let none = MockLowering.SubtreeSharingOutcome.HeldFacts(generators: 0, labelWords: 0)
		#expect(heldFacts == [100: none, 200: none, 400: none])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The shared meetings each mock's lowering reports, by mocked type.
	private mutating func sharedMeetings(of swiftFileContent: [String]) async throws -> [String: Int] {
		var meetings = [String: Int]()
		for outcome in try await outcomes(of: swiftFileContent) {
			meetings[outcome.mockedType, default: 0] += outcome.sharedMeetings
			// A root that shares lays its places out by type key, so the shared meetings' missing text is never read.
			#expect(outcome.sharedMeetings == 0 || outcome.layoutOutcome == "laidOut")
		}
		return meetings
	}

	/// What each mock's lowering reports of its sharing.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func sharedMeetings(ofModules modules: [ModuleFixture]) async throws -> [String: Int] {
		let (stream, continuation) = AsyncStream.makeStream(of: MockLowering.SubtreeSharingOutcome.self)
		try await MockLowering.$subtreeSharingObserver.withValue({ outcome in
			continuation.yield(outcome)
		}) {
			_ = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var meetings = [String: Int]()
		for await outcome in stream {
			meetings[outcome.mockedType, default: 0] += outcome.sharedMeetings
		}
		return meetings
	}

	private mutating func outcomes(of swiftFileContent: [String]) async throws -> [MockLowering.SubtreeSharingOutcome] {
		var filesToDelete = filesToDelete
		let outcomes = try await Self.outcomes(of: swiftFileContent, filesToDelete: &filesToDelete)
		self.filesToDelete = filesToDelete
		return outcomes
	}

	private static func outcomes(of swiftFileContent: [String], filesToDelete: inout [URL]) async throws -> [MockLowering.SubtreeSharingOutcome] {
		let (stream, continuation) = AsyncStream.makeStream(of: MockLowering.SubtreeSharingOutcome.self)
		try await MockLowering.$subtreeSharingObserver.withValue({ outcome in
			continuation.yield(outcome)
		}) {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: swiftFileContent,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var outcomes = [MockLowering.SubtreeSharingOutcome]()
		for await outcome in stream {
			outcomes.append(outcome)
		}
		return outcomes
	}

	/// `Root` builds `First` and `Second`, each of which declares `screenProperty`, a `Screen` that builds a `Model`.
	private static func screenBeneathTwoParents(
		screenProperty: String,
		parentKind: String = "final class",
		rootProperties: [String] = [],
		modelProperties: [String] = [],
		sendableScreenAndModel: Bool = false,
		extraFiles: [String] = [],
	) -> [String] {
		let sendable = sendableScreenAndModel ? ", Sendable" : ""
		return [
			Self.type("Root", kind: "final class", generateMock: true, properties: rootProperties + ["@Instantiated let first: First", "@Instantiated let second: Second"]),
			Self.type("First", kind: parentKind, properties: [screenProperty]),
			Self.type("Second", kind: parentKind, properties: [screenProperty]),
			Self.type("Screen", kind: "final class", conformances: sendable, properties: ["@Instantiated let model: Model"]),
			Self.type("Model", kind: "final class", conformances: sendable, properties: modelProperties),
		] + extraFiles
	}

	/// `P1` builds `screen` before `x`, so its `Model` is handed `nil`. `P2` declares `x` first: `x` waits on `y`, `y` on
	/// `screen`, and `screen`'s receive of `x` would close that circle, so it is left `nil` and `P2` builds `screen`, `y`,
	/// then `x`. One generator builds both screens, beneath `Mid` where `screenBuildsMid`.
	private static func childContextGraph(rootBuildsX: Bool, screenBuildsMid: Bool) -> [String] {
		var files = [
			Self.type("Root", kind: "final class", generateMock: true, properties: (rootBuildsX ? ["@Instantiated let x: X"] : []) + ["@Instantiated let p1: P1", "@Instantiated let p2: P2"]),
			Self.type("P1", kind: "final class", properties: ["@Instantiated let screen: Screen", "@Instantiated let x: X"]),
			Self.type("P2", kind: "final class", properties: ["@Instantiated let x: X", "@Instantiated let screen: Screen", "@Instantiated let y: Y"]),
			Self.type("Model", kind: "final class", properties: ["@Received(onlyIfAvailable: true) let x: X?"]),
			Self.type("Y", kind: "final class", properties: ["@Received let screen: Screen"]),
			Self.type("X", kind: "final class", properties: ["@Received(onlyIfAvailable: true) let y: Y?"]),
		]
		if screenBuildsMid {
			files.append(Self.type("Screen", kind: "final class", properties: ["@Instantiated let mid: Mid"]))
			files.append(Self.type("Mid", kind: "final class", properties: ["@Instantiated let model: Model"]))
		} else {
			files.append(Self.type("Screen", kind: "final class", properties: ["@Instantiated let model: Model"]))
		}
		return files
	}

	/// Public protocols, one file.
	private static func protocols(_ names: [String]) -> String {
		names.map { "public protocol \($0) {}" }.joined(separator: "\n")
	}

	/// `Root` builds `First0` and `Second0`, each of which builds `Layer1`; each `Layer<n>` builds `First<n>` and
	/// `Second<n>`, each of which builds `Layer<n+1>`, up to `Layer<layers>`, which builds `Leaf`. The labels carry the
	/// layer's number where `suffixesLabels`, and are `first`, `second` and `layer` at every layer otherwise. Where
	/// `buildsViewModels`, each `Layer<n>` first builds a `ViewModel<n>` under `viewModel`. Where `receivesTokenNamedApart`,
	/// each `Layer<n>` receives `token: any TokenA` and `Root` builds `Other`, which receives `token: any TokenB`.
	private static func layeredChain(layers: Int, suffixesLabels: Bool = true, buildsViewModels: Bool = false, receivesTokenNamedApart: Bool = false) -> [String] {
		func label(_ name: String, _ layer: Int) -> String {
			suffixesLabels ? "\(name)\(layer)" : name
		}
		var files = [Self.type("Root", kind: "final class", generateMock: true, properties: ["@Instantiated let \(label("first", 0)): First0", "@Instantiated let \(label("second", 0)): Second0"] + (receivesTokenNamedApart ? ["@Instantiated let other: Other"] : []))]
		if receivesTokenNamedApart {
			files.append(Self.type("Other", kind: "final class", properties: ["@Received let token: any TokenB"]))
			files.append(Self.protocols(["TokenA", "TokenB"]))
		}
		for layer in 0..<layers {
			files.append(Self.type("First\(layer)", kind: "final class", properties: ["@Instantiated let \(label("layer", layer + 1)): Layer\(layer + 1)"]))
			files.append(Self.type("Second\(layer)", kind: "final class", properties: ["@Instantiated let \(label("layer", layer + 1)): Layer\(layer + 1)"]))
			var layerProperties = receivesTokenNamedApart ? ["@Received let token: any TokenA"] : []
			if buildsViewModels {
				layerProperties.append("@Instantiated let viewModel: ViewModel\(layer + 1)")
				files.append(Self.type("ViewModel\(layer + 1)", kind: "final class", properties: []))
			}
			if layer + 1 < layers {
				layerProperties += ["@Instantiated let \(label("first", layer + 1)): First\(layer + 1)", "@Instantiated let \(label("second", layer + 1)): Second\(layer + 1)"]
			} else {
				layerProperties.append("@Instantiated let leaf: Leaf")
			}
			files.append(Self.type("Layer\(layer + 1)", kind: "final class", properties: layerProperties))
		}
		files.append(Self.type("Leaf", kind: "final class", properties: []))
		return files
	}

	/// `Root` builds `First0` and `Second0` through instantiators; each `First<n>` and `Second<n>` declares a `session`
	/// and builds `Layer<n+1>` through an instantiator, and each layer receives the session and builds the next layer's
	/// `First` and `Second` through instantiators, the last a `Leaf`.
	private static func layeredSessionChain(layers: Int) -> [String] {
		var files = [
			Self.type("Root", kind: "final class", generateMock: true, properties: ["@Instantiated let first0: Instantiator<First0>", "@Instantiated let second0: Instantiator<Second0>"]),
			Self.type("Session", kind: "final class", properties: []),
			Self.type("Leaf", kind: "final class", properties: []),
		]
		for layer in 0..<layers {
			for parent in ["First", "Second"] {
				files.append(Self.type("\(parent)\(layer)", kind: "final class", properties: ["@Instantiated let session: Session", "@Instantiated let layer\(layer + 1): Instantiator<Layer\(layer + 1)>"]))
			}
			let next = layer + 1 < layers
				? ["@Instantiated let first\(layer + 1): Instantiator<First\(layer + 1)>", "@Instantiated let second\(layer + 1): Instantiator<Second\(layer + 1)>"]
				: ["@Instantiated let leaf: Leaf"]
			files.append(Self.type("Layer\(layer + 1)", kind: "final class", properties: ["@Received let session: Session"] + next))
		}
		return files
	}

	/// `Root` takes a `service` and builds `Feature0` through an instantiator; each `Feature<n>` receives the service and
	/// builds `Feature<n+1>` the same way, as `Scripts/generate-time-check.py`'s mock chain does.
	private static func featureChain(features: Int) -> [String] {
		var files = [
			Self.type("Root", kind: "final class", generateMock: true, properties: ["@Instantiated let service: Service", "@Instantiated let feature0: Instantiator<Feature0>"]),
			Self.type("Service", kind: "final class", properties: []),
		]
		for feature in 0..<features {
			let next = feature + 1 < features ? ["@Instantiated let feature\(feature + 1): Instantiator<Feature\(feature + 1)>"] : []
			files.append(Self.type("Feature\(feature)", kind: "final class", properties: ["@Received let service: Service"] + next))
		}
		return files
	}

	/// An `@Instantiable` type whose initializer takes each property in order.
	private static func type(_ name: String, kind: String, generateMock: Bool = false, conformances: String = "", properties: [String]) -> String {
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

	private static let token = """
	@Instantiable
	public final class Token: Instantiable {
	    public init() {}
	}
	"""

	private static let keyed = "Keyed: "
	private static let guarded = "Guarded: "
	private static let rootConstant = "Constant through the root's walk: "
	private static let relative = "Read relative to the node, or computed for each meeting: "
	private static let rootLevel = "Set only at the mock root's level, which no shared subtree is: "
	private static let output = "Written by the walk, never read back into a subtree's records: "
	private static let nameScope = "A name scope the node's own builder function opens afresh: "

	/// Every stored field of `MockLowering.Walk`, with how a shared subtree stays correct without reading it at a later
	/// meeting.
	private static let walkFieldClassification: [String: String] = [
		"cycleEdges": rootConstant + "the module's back edges.",
		"ancestorTypes": guarded + "a tree builds a type beneath itself only through a closer or a loop of builders, and a root that holds either shares nothing.",
		"parentConcreteType": relative + "only the node's own construction reads it, which each meeting computes.",
		"overridePathReachable": guarded + "a key forms only where it is true.",
		"overridePathsByType": relative + "configuration paths are relative to the configured ancestor, which no node beneath repeats.",
		"relativeConfigurationsByType": relative + "as overridePathsByType.",
		"pushedRelativeConfigurations": relative + "pushed and popped around each node.",
		"configurationReads": relative + "the node's configuration read is computed for each meeting; its children read theirs relative to it.",
		"builtPlaceConfigurationContexts": output + "keyed by path, filled for the first meeting's paths.",
		"configurationParameterNames": rootConstant + "a type's name, once claimed, is the same at every meeting, and the first meeting claims each name its subtree's records hold.",
		"rootLabels": rootConstant + "the labels `mock()` binds.",
		"rootOverrideNames": rootConstant + "the root's override names.",
		"unavailableDependencyOverrideNames": rootConstant + "set from the signature before the walk.",
		"ancestorDeclarationsByLabel": guarded + "read only by closers and loops of builders, which keep a root from sharing; the declarations an alias reads are the key's `scope`, passed down beside the walk.",
		"bodyLabels": nameScope + "enclosing bodies matter only to a cycle closer's function lookup, and a closed subtree has none.",
		"bodyFunctionNames": nameScope + "as bodyLabels.",
		"pendingRenamedFunctionName": nameScope + "set by the level for its next node, inside the subtree.",
		"renames": keyed + "restricted to the labels the subtree reads.",
		"lazilyInstantiatedNames": keyed + "restricted to the labels the subtree reads.",
		"publicMockWrapperParameterNames": rootConstant + "the wrappers a public mock takes; a public mock shares nothing.",
		"rootRenames": rootLevel + "copied from renames at the root's level.",
		"uncoveredParameterNames": rootConstant + "set from the signature before the walk.",
		"sendableAutoclosureBindings": rootConstant + "set from the signature before the walk.",
		"rootPropertyNodeBindingNames": rootLevel + "the names the root's nodes are bound under.",
		"rootFlatReceivedLabels": rootConstant + "set from the signature before the walk.",
		"rootNamesDeclaredInBuilderFunctions": rootConstant + "set from the signature before the walk.",
		"rootParametersKeepingTheirLabels": rootConstant + "set from the signature before the walk.",
		"writesText": rootConstant + "off for every root that lays out by type key, the only roots that share; a fallback walks again with no sharing.",
		"rootPropertiesNamedApartFromParameters": rootLevel + "the root's nodes named apart from a parameter.",
		"uncoveredProperties": rootConstant + "the dependencies `mock()` takes.",
		"configurationRecords": output + "a configuration is recorded from the first node that needs it, identical by key.",
		"handWrittenMockDefaultParameters": rootConstant + "set from the context before the walk.",
		"mockConstructions": relative + "recorded per type, the first meeting's identical by key.",
		"sendableConfigurationTypeNames": rootConstant + "set from the context before the walk.",
		"configuredAncestorTypes": guarded + "as ancestorTypes: no type beneath a shared node repeats one above it.",
		"isBeneathRepeatedConfiguredAncestor": guarded + "the walk shares nothing beneath one.",
		"configuredNodesEntered": output + "a count of configured nodes, which a later meeting does not enter.",
		"finishedConfiguredChildren": relative + "pushed and popped around each configured node.",
		"filledCallBuilders": guarded + "the gate (`MockLowering.Walk.sharesSubtrees(of:)`) refuses a root with an inline public mock's places.",
		"buildsPublicMock": guarded + "a public mock's walk has no subtree sharing.",
		"enclosingBindingNamesPassedByName": relative + "read only where a node of the subtree renames a receive apart, which reads a flat parameter or override the key's `renames` hold.",
		"promotedProperties": rootLevel + "read only for the root's own nodes.",
		"promotedParameterNames": rootLevel + "read only for the root's own nodes.",
		"sendableOverrideExtractor": guarded + "the walk shares nothing inside a `@Sendable` builder function's extraction.",
		"levelNames": guarded + "used only inside an extraction, which the walk shares nothing inside.",
		"isInsideSendableFunction": guarded + "every `@Sendable` builder function above a node holds an override extractor, which forms no key.",
		"isInsideActorArgument": guarded + "the walk shares nothing inside an actor's argument.",
		"loopMembership": guarded + "a node in a loop of builders forms no key, and a closed subtree holds none.",
		"loopMembers": guarded + "a closed subtree holds no loop of builders.",
		"loopUnit": guarded + "a closed subtree holds no loop of builders.",
		"lastLoopMemberLineCounts": guarded + "a closed subtree holds no loop of builders.",
		"loopMemberPaths": guarded + "a closed subtree holds no loop of builders.",
		"loopRebindings": guarded + "a closed subtree holds no loop of builders.",
		"pathsNamedApart": guarded + "the gate refuses a root with a property bound apart from its label.",
		"unavailableProperties": relative + "follows from the generator and the properties generated after each child, which the key holds.",
		"propertiesGeneratedLater": keyed + "per child, in `childrenPropertiesGeneratedLater`.",
		"childIndexPath": output + "the path a meeting's records are keyed by; a later meeting's places take the first meeting's records.",
		"recordsPlaces": rootConstant + "whether the root records places.",
		"closerAndDefaultRecords": output + "keyed by path; a later meeting takes the first meeting's child records with its parent's child codes.",
		"builtPlaceInputs": output + "keyed by path, filled for the first meeting's paths.",
		"builtRecords": output + "keyed by path, filled for the first meeting's paths.",
		"placePathsInWalkOrder": output + "the order places are recorded in.",
		"builtPlaceCalls": output + "computed for each meeting's own place.",
		"firstUnrecordedPath": output + "a root that falls back walks again unshared.",
		"pathsWithUnplannedLines": output + "a root that falls back walks again unshared.",
		"unplannedLineKinds": output + "a root that falls back walks again unshared.",
		"pathsStartingExtraction": guarded + "the walk shares nothing inside an extraction.",
		"leadingBodyPlaces": output + "keyed by path, filled for the first meeting's paths.",
		"unrecordedReasons": output + "a root that falls back walks again unshared.",
		"pendingPublicMockCallReads": guarded + "a closed subtree holds no call of another module's public mock.",
		"publicMockCallPlanNodes": guarded + "a closed subtree holds no call of another module's public mock.",
		"closedOnPlacesByLabel": guarded + "a closed subtree holds no cycle-closing node beneath.",
		"closerParentFieldReads": guarded + "a closed subtree holds no closer.",
		"subtreeSharing": output + "the subtrees met so far, which the key looks up.",
	]

	private static func fieldNames(of value: Any) -> Set<String> {
		Set(Mirror(reflecting: value).children.compactMap(\.label))
	}
}
