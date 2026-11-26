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

	/// The parts the key holds are the ones `walkFieldClassification` calls keyed, plus the node's generator.
	@Test
	func subtreeKey_holdsEachKeyedPartOfWalk_whenComparingMeetings() {
		let key = MockLowering.SubtreeKey(
			generator: ObjectIdentifier(Self.self),
			children: [],
			overridePathReachable: true,
			isInsideSendableFunction: false,
			renames: [:],
			lazilyInstantiatedNames: [:],
			bindingNamesPassedByName: [:],
			scope: [],
		)
		let child = MockLowering.SubtreeKey.ChildContext(index: 0, unavailableProperties: [], propertiesGeneratedLater: [])
		#expect(Self.fieldNames(of: key) == ["generator", "children", "overridePathReachable", "isInsideSendableFunction", "renames", "lazilyInstantiatedNames", "bindingNamesPassedByName", "scope"])
		#expect(Self.fieldNames(of: child) == ["index", "unavailableProperties", "propertiesGeneratedLater"])
		#expect(Set(Self.walkFieldClassification.filter { $0.value.hasPrefix(Self.keyed) }.keys) == ["overridePathReachable", "isInsideSendableFunction", "renames", "lazilyInstantiatedNames", "enclosingBindingNamesPassedByName", "unavailableProperties", "propertiesGeneratedLater", "labels"])
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

	/// The subtree of the `ChildContext` graph: `Screen` is built beneath `P1`, where `x` is built after it, and beneath
	/// `P2`, where `y` receives it and `x` receives `y`, so `Model`'s receive of `x` differs between the two paths.
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_sharesNothing_whenPublicMocksTreeBuildsHoleBeneathTwoParents() async throws {
		// `Panel`, built beneath `First` and `Second`, holds a place of `Api`, which nothing in `Feat` fulfills.
		let meetings = try await sharedMeetings(ofModules: [
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: ["FeatTypes.swift": "import SafeDI\n\npublic protocol Api: AnyObject {}\n\n" + [
				seamFixtureType(named: "Panel", isFinalClass: true, declarations: ["@Instantiated public let api: any Api"]),
				seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated public let panel: Panel"]),
				seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated public let panel: Panel"]),
				seamFixtureType(named: "Root", isFinalClass: true, declarations: ["@Instantiated public let first: First", "@Instantiated public let second: Second"])
					.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: .public)\n"),
			].joined(separator: "\n\n")]),
		])
		#expect(meetings["Root", default: 0] == 0)
	}

	@Test
	mutating func mock_matchesWalkOfEveryPath_whenScreensReceiveOnlyIfAvailableValueBuiltInOtherOrders() async throws {
		_ = try await sharedMeetings(of: Self.childContextGraph(rootBuildsX: false))
	}

	/// The `ChildContext` graph with an `x` the root builds above both parents.
	@Test
	mutating func mock_matchesWalkOfEveryPath_whenScreensReceiveOnlyIfAvailableValueBuiltInOtherOrdersBeneathOuterValue() async throws {
		_ = try await sharedMeetings(of: Self.childContextGraph(rootBuildsX: true))
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

	/// `P1` builds `x` before `screen`, so its `Model` reads `x`. `P2` declares `x` first: `x` waits on `y`, `y` on
	/// `screen`, and `screen`'s receive of `x` would close that circle, so it is left `nil` and `P2` builds `screen`, `y`,
	/// then `x`. One generator builds both screens; only the children's contexts tell the two places apart where the root
	/// builds an `x` above both, and only the values in scope where it builds none.
	private static func childContextGraph(rootBuildsX: Bool) -> [String] {
		[
			Self.type("Root", kind: "final class", generateMock: true, properties: (rootBuildsX ? ["@Instantiated let x: X"] : []) + ["@Instantiated let p1: P1", "@Instantiated let p2: P2"]),
			Self.type("P1", kind: "final class", properties: ["@Instantiated let screen: Screen", "@Instantiated let x: X"]),
			Self.type("P2", kind: "final class", properties: ["@Instantiated let x: X", "@Instantiated let screen: Screen", "@Instantiated let y: Y"]),
			Self.type("Screen", kind: "final class", properties: ["@Instantiated let model: Model"]),
			Self.type("Model", kind: "final class", properties: ["@Received(onlyIfAvailable: true) let x: X?"]),
			Self.type("Y", kind: "final class", properties: ["@Received let screen: Screen"]),
			Self.type("X", kind: "final class", properties: ["@Received(onlyIfAvailable: true) let y: Y?"]),
		]
	}

	/// `Root` builds `First0` and `Second0`, each of which builds `Layer1`; each `Layer<n>` builds `First<n>` and
	/// `Second<n>`, each of which builds `Layer<n+1>`, up to `Layer<layers>`, which builds nothing.
	private static func layeredChain(layers: Int) -> [String] {
		var files = [Self.type("Root", kind: "final class", generateMock: true, properties: ["@Instantiated let first0: First0", "@Instantiated let second0: Second0"])]
		for layer in 0..<layers {
			files.append(Self.type("First\(layer)", kind: "final class", properties: ["@Instantiated let layer\(layer + 1): Layer\(layer + 1)"]))
			files.append(Self.type("Second\(layer)", kind: "final class", properties: ["@Instantiated let layer\(layer + 1): Layer\(layer + 1)"]))
			if layer + 1 < layers {
				files.append(Self.type("Layer\(layer + 1)", kind: "final class", properties: ["@Instantiated let first\(layer + 1): First\(layer + 1)", "@Instantiated let second\(layer + 1): Second\(layer + 1)"]))
			} else {
				files.append(Self.type("Layer\(layer + 1)", kind: "final class", properties: ["@Instantiated let leaf: Leaf"]))
			}
		}
		files.append(Self.type("Leaf", kind: "final class", properties: []))
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
		"overridePathReachable": keyed + "whether the node's override reaches its children's.",
		"overridePathsByType": relative + "configuration paths are relative to the configured ancestor, which no node beneath repeats.",
		"relativeConfigurationsByType": relative + "as overridePathsByType.",
		"pushedRelativeConfigurations": relative + "pushed and popped around each node.",
		"configurationReads": relative + "the node's configuration read is computed for each meeting; its children read theirs relative to it.",
		"builtPlaceConfigurationContexts": output + "keyed by path, filled for the first meeting's paths.",
		"rootLabels": rootConstant + "the labels `mock()` binds.",
		"rootOverrideNames": rootConstant + "the root's override names.",
		"unavailableDependencyOverrideNames": rootConstant + "set from the signature before the walk.",
		"ancestorDeclarationsByLabel": "Keyed through `scope`: the declarations the children see, restricted to the labels the subtree reads; closers read the rest, and a closed subtree has none.",
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
		"rootPropertiesNamedApartFromParameters": rootLevel + "the root's nodes named apart from a parameter.",
		"labels": keyed + "the labels bound around the node, which the children's scope (`scope`) holds.",
		"uncoveredProperties": rootConstant + "the dependencies `mock()` takes.",
		"configurationRecords": output + "a configuration is recorded from the first node that needs it, identical by key.",
		"handWrittenMockDefaultParameters": rootConstant + "set from the context before the walk.",
		"mockConstructions": relative + "recorded per type, the first meeting's identical by key.",
		"sendableConfigurationTypeNames": rootConstant + "set from the context before the walk.",
		"configuredAncestorTypes": guarded + "as ancestorTypes: no type beneath a shared node repeats one above it.",
		"isBeneathRepeatedConfiguredAncestor": guarded + "the walk shares nothing beneath one.",
		"configuredNodesEntered": output + "a count of configured nodes, which a later meeting does not enter.",
		"finishedConfiguredChildren": relative + "pushed and popped around each configured node.",
		"filledCallBuilders": guarded + "a closed subtree holds no call of another module's public mock.",
		"buildsPublicMock": guarded + "a public mock's walk has no subtree sharing.",
		"enclosingBindingNamesPassedByName": keyed + "restricted to the labels the subtree reads.",
		"promotedProperties": rootLevel + "read only for the root's own nodes.",
		"promotedParameterNames": rootLevel + "read only for the root's own nodes.",
		"sendableOverrideExtractor": guarded + "the walk shares nothing inside a `@Sendable` builder function's extraction.",
		"levelNames": guarded + "used only inside an extraction, which the walk shares nothing inside.",
		"isInsideSendableFunction": keyed + "whether the children are built inside a `@Sendable` builder function.",
		"isInsideActorArgument": guarded + "the walk shares nothing inside an actor's argument.",
		"loopMembership": guarded + "a node in a loop of builders forms no key, and a closed subtree holds none.",
		"loopMembers": guarded + "a closed subtree holds no loop of builders.",
		"loopUnit": guarded + "a closed subtree holds no loop of builders.",
		"lastLoopMemberLineCounts": guarded + "a closed subtree holds no loop of builders.",
		"loopUnitRecords": guarded + "a closed subtree holds no loop of builders.",
		"pathsCoveredByLoopUnits": guarded + "a closed subtree holds no loop of builders.",
		"pathsNamedApart": output + "a path whose root falls back walks again unshared.",
		"unavailableProperties": keyed + "per child, in `children`.",
		"propertiesGeneratedLater": keyed + "per child, in `children`.",
		"childIndexPath": output + "the path a meeting's records are keyed by; a later meeting's places take the first meeting's records.",
		"recordsPlaces": rootConstant + "whether the root records places.",
		"closerAndDefaultRecords": guarded + "a closed subtree holds no closer.",
		"builtPlaceInputs": output + "keyed by path, filled for the first meeting's paths.",
		"builtRecords": output + "keyed by path, filled for the first meeting's paths.",
		"placePathsInWalkOrder": output + "the order places are recorded in.",
		"planNodes": output + "the plan's nodes.",
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
		"sharedBuilderAttributesByType": rootConstant + "set from the context before the walk.",
		"closedSubtrees": rootConstant + "a memo of `SubtreeSharing.isClosed(atNode:)` over each generator's subtree, a fact of the generator, which the key holds.",
	]

	private static func fieldNames(of value: Any) -> Set<String> {
		Set(Mirror(reflecting: value).children.compactMap(\.label))
	}
}
