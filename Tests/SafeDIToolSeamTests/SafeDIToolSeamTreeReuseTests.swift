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

/// Emission makes the tree of a seam its first signature pass settled again from that pass's tree, rather than building it
/// anew (`ScopeGenerator.reseating(treeRootedAt:of:seamRoot:)`). Every run through the test executors compares the two
/// (`ReusedSeamTreeChecks`), and `SafeDIToolSeamTreeReuseSmokeTests` keeps that check from going vacuous; these tests keep
/// every stored property of a generator classified for reseating.
struct SafeDIToolSeamTreeReuseTests: ~Copyable {
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
	mutating func generate_reusesSeamsTreeWithItsLoopsLevelsBoxed_whenSeamsBuildersReceiveEachOtherAroundPlaces() async throws {
		// `Home`, a seam, instantiates the builders of three screens, each of which forwards an `id`, holds a place of `Api`
		// and receives the next screen's builder: a loop of three, whose levels the initializer binds in one box. The box is
		// worked out from the places' payloads, which the first signature pass's tree, built before the seam had places,
		// does not hold.
		let reusedTree = try await reusedTree(ofSeam: "Home", feature: [
			"public protocol Api {}",
			seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let screenABuilder: Instantiator<ScreenA>", "@Instantiated let screenBBuilder: Instantiator<ScreenB>", "@Instantiated let screenCBuilder: Instantiator<ScreenC>"]),
			seamFixtureType(named: "ScreenA", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let api: any Api", "@Received let screenBBuilder: Instantiator<ScreenB>"]),
			seamFixtureType(named: "ScreenB", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let api: any Api", "@Received let screenCBuilder: Instantiator<ScreenC>"]),
			seamFixtureType(named: "ScreenC", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let api: any Api", "@Received let screenABuilder: Instantiator<ScreenA>"]),
		])
		let reusedTreeCode = try await reusedTree.reusedTreeCode()
		#expect(reusedTreeCode.contains("let __safeDI_screenABuilder_loopLevels = __safeDI_LoopLevels_"))
		#expect(try await reusedTree.builtTreeCode() == reusedTreeCode)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reusesSeamsTreeWithItsCarrierSites_whenPlaceIsInsideBuilder() async throws {
		// `Home`, a seam, instantiates the builder of `Screen`, which forwards an `id` and holds a place of `Api`: the place's
		// level is a carrier, whose member the site takes its values through (`SeamHoles.carrierSite(at:)`), which the first
		// signature pass's tree, built before the seam had places, does not hold.
		let reusedTree = try await reusedTree(ofSeam: "Home", feature: [
			"public protocol Api {}",
			seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let screenBuilder: Instantiator<Screen>"]),
			seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let api: any Api"]),
		])
		let reusedTreeCode = try await reusedTree.reusedTreeCode()
		#expect(reusedTreeCode.contains("let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder\n"))
		#expect(reusedTreeCode.contains("let api: any Api = __safeDI_apiBuilder_screenBuilder.api(id)\n"))
		#expect(try await reusedTree.builtTreeCode() == reusedTreeCode)
	}

	@Test
	func reseating_classifiesEveryStoredProperty_ofAGenerator() {
		let generator = ScopeGenerator(
			holeProperty: Property(label: "place", typeDescription: .simple(name: "Place")),
			erasedToConcreteExistential: false,
			site: nil,
			ownerPropertyStack: [],
			ownerConcreteTypeStack: [],
		)
		let storedProperties = Set(Mirror(reflecting: generator).children.compactMap(\.label)).subtracting(["$defaultActor"])
		#expect(storedProperties == Set(ScopeGenerator.ReseatedField.byStoredProperty.keys))
	}

	@Test
	func reseating_classifiesEveryField_ofSeamAndFillFields() {
		let fields = Set(Mirror(reflecting: ScopeGenerator.SeamAndFillFields()).children.compactMap(\.label))
		#expect(fields == Set(ScopeGenerator.ReseatedField.bySeamAndFillField.keys))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reusesSeamsTreeWithItsInlineSeamComments_whenTreeBuildsSeamOfAdditionalDirectory() async throws {
		// `Home`, a seam of this module, instantiates `Service`, a seam in a directory a `#SafeDIConfiguration` adds, which no
		// run generates the initializer of: `Home`'s tree builds it inline, with a comment that says so. The comment is the
		// scope's (`Scope.builtInlineSeamComment`), so the first signature pass's tree carries it only if that pass's scopes do.
		// Node records lay out `Home`'s own world, which calls no seam and holds no hole, without its tree, so the run draws
		// the DOT graph, which reads every tree, to reuse it.
		let (stream, continuation) = AsyncStream.makeStream(of: ReusedSeamTree.self)
		var filesToDelete = filesToDelete
		defer { self.filesToDelete = filesToDelete }
		_ = try await SeamTreeReuseObservation.$comparesBuiltTrees.withValue(TaskLocalFunction { continuation.yield($0) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					#SafeDIConfiguration(
					    additionalDirectoriesToInclude: ["$ADDITIONAL_DIRECTORY"]
					)
					""",
					"public protocol UserService {}",
					"""
					@Instantiable(fulfillingAdditionalTypes: [UserService.self])
					public final class DefaultUserService: Instantiable, UserService {
					    public init() {}
					}
					""",
					seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated let service: Service"]),
				],
				additionalDirectorySwiftFileContent: [
					seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let profile: Profile"]),
					seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
				],
				buildSwiftOutputDirectory: true,
				buildDOTFileOutput: true,
				filesToDelete: &filesToDelete,
				moduleMembershipArguments: ["--module-name", "App"],
			)
		}
		continuation.finish()
		var reusedTrees = [ReusedSeamTree]()
		for await reusedTree in stream where reusedTree.signature.seamType.asSource == "Home" {
			reusedTrees.append(reusedTree)
		}
		let reusedTree = try #require(reusedTrees.first)
		let reusedTreeCode = try await reusedTree.reusedTreeCode()
		#expect(reusedTreeCode.contains("return Service(profile: profile) // Built inline: SafeDI does not know which module declares `Service`, so this tree cannot call the initializer SafeDI generates for it.\n"))
		#expect(try await reusedTree.builtTreeCode() == reusedTreeCode)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reusesSeamsTree_whenTreeIsLarge() async throws {
		// `Home`, a seam, instantiates seventy leaves and holds a place of `Api`: a tree of many scopes, each made again
		// beneath the final seam root.
		let leafLabels = (1...70).map { "leaf\($0)" }
		let reusedTree = try await reusedTree(
			ofSeam: "Home",
			feature: ["public protocol Api {}", seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let api: any Api"] + leafLabels.map { "@Instantiated let \($0): Leaf\($0.dropFirst(4))" })]
				+ leafLabels.map { seamFixtureType(named: "Leaf\($0.dropFirst(4))", declarations: []) },
		)
		let reusedTreeCode = try await reusedTree.reusedTreeCode()
		#expect(reusedTreeCode.contains("let leaf70 = Leaf70()\n"))
		#expect(try await reusedTree.builtTreeCode() == reusedTreeCode)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The tree of `seam`, declared in a module of `feature`, that emission made again from its first signature pass's tree,
	/// with `App` filling every place of `Api`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func reusedTree(ofSeam seam: String, feature: [String], sourceLocation: SourceLocation = #_sourceLocation) async throws -> ReusedSeamTree {
		let app = [
			"""
			@Instantiable(fulfillingAdditionalTypes: [Api.self])
			public final class DefaultApi: Instantiable, Api {
			    public init() {}
			}
			""",
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let home: Home"]),
		]
		let (stream, continuation) = AsyncStream.makeStream(of: ReusedSeamTree.self)
		var filesToDelete = filesToDelete
		defer { self.filesToDelete = filesToDelete }
		_ = try await SeamTreeReuseObservation.$comparesBuiltTrees.withValue(TaskLocalFunction { continuation.yield($0) }) {
			try await executeSafeDIToolMultiModuleTest(modules: SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var reusedTrees = [ReusedSeamTree]()
		for await reusedTree in stream where reusedTree.signature.seamType.asSource == seam {
			reusedTrees.append(reusedTree)
		}
		return try #require(reusedTrees.first, sourceLocation: sourceLocation)
	}
}
