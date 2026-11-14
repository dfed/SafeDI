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

/// A seam's tree that instantiates a type no `@Instantiable` declaration the seam's module can see fulfills: the
/// generated initializer takes a builder for each place the tree builds it, a closure handed a struct of the values in
/// scope there, and a module that can see a fulfilling declaration fills the builder in the code it generates.
struct SafeDIToolSeamBuilderParameterTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: One hole, filled by a root in another package

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderForHoleThatCallerFills_whenSeamsModuleCannotSeeFulfillingDeclaration(integration: MultiModuleIntegration) async throws {
		// C1.2, C3.1: `Profile` instantiates `userService: any UserService`, which only `App` can see `DefaultUserService`
		// fulfill. `Service`'s initializer takes a builder handed `Profile`'s scope, which `App` fills.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(feature: Self.canonicalFeature, app: Self.canonicalApp),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, Self.generatedFiles(module: "Feature", integration: integration, imports: [], rootFiles: [
			"Service": Self.canonicalServiceCode,
		]))
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: integration, imports: ["Feature"], rootFiles: [
			"Root": """
			extension Root {
			    public init() {
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_6E216DA2A3D4C4DA.self\(Self.pluginComment(integration, seam: "Service"))
			            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
			                switch scope {
			                case let .profile(values, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope, analytics: values.analytics)
			                }
			            }
			            func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope, analytics: Analytics) -> any UserService {
			                switch scope {
			                case .userService:
			                    let userService: any UserService = DefaultUserService(analytics: analytics)
			                    return userService
			                }
			            }
			            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
			        }
			        let service: Service = __safeDI_service()
			        self.init(service: service)
			    }
			}
			""",
		]))
		// The Manual's seam section shows this example's generated code under the plugin, read here so it cannot drift.
		guard integration == .swiftPackagePlugin else { return }
		let manual = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Documentation/Manual.md"), encoding: .utf8)
		let section = try #require(manual.components(separatedBy: "## Generating a dependency tree per module").dropFirst().first)
			.components(separatedBy: "\n#").first ?? ""
		let codeBlocks = section.components(separatedBy: "```swift\n").dropFirst().map { $0.components(separatedBy: "\n```").first ?? "" }
		let featureFile = try #require(output.modules["Feature"]?.generatedFiles["Service+SafeDI.swift"])
		let appFile = try #require(output.modules["App"]?.generatedFiles["Root+SafeDI.swift"])
		#expect(codeBlocks.dropFirst(4).first == "// Generated in module Feature, where `Profile` instantiates `userService: any UserService`.\n" + Self.seamExtension(in: featureFile))
		#expect(codeBlocks.dropFirst(5).first == "// Generated in module App, which declares `DefaultUserService`, an implementation of `UserService`.\n" + Self.serviceBuilderFunction(in: appFile))
	}

	// MARK: The Manual's adoption example

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesEveryModule_whenBuildingManualsAdoptionExample(integration: MultiModuleIntegration) async throws {
		// The adoption guide declares `Feed`'s seam with a hole and `App`'s implementation of it, and "Calling a public mock
		// from another module" calls the seam's public mock from another package; all three are read from the Manual, so
		// none can stop compiling unnoticed. `Session` and `App`'s root are this test's.
		let manual = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Documentation/Manual.md"), encoding: .utf8)
		let adoptionBlocks = try Self.swiftCodeBlocks(ofSectionTitled: "### Adopting SafeDI in a large codebase", in: manual)
		let callBlocks = try Self.swiftCodeBlocks(ofSectionTitled: "#### Calling a public mock from another module", in: manual)
		#expect(adoptionBlocks.count == 2)
		let feed = try #require(adoptionBlocks.first)
		let app = try #require(adoptionBlocks.dropFirst().first)
		let call = try #require(callBlocks.first)
		let root = """
		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(session: Session, feedScreen: FeedScreen) {
		        self.session = session
		        self.feedScreen = feedScreen
		    }

		    @Instantiated private let session: Session
		    @Instantiated private let feedScreen: FeedScreen
		}
		"""
		_ = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: [seamFixtureType(named: "Session", isFinalClass: true, declarations: [])]),
				ModuleFixture(name: "Feed", packageName: "Shop", swiftFileContentByFilePath: ["FeedScreen.swift": "import Core\n\n" + feed], dependencies: ["Core"]),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["AppFeedService.swift": "import Core\nimport Feed\n\n" + app, "Root.swift": "import Core\nimport Feed\n\n" + root], dependencies: ["Core", "Feed"]),
				ModuleFixture(name: "FeedTests", packageName: "FeedPreviews", swiftFileContentByFilePath: ["FeedScreenTests.swift": call], dependencies: ["Core", "Feed"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
	}

	// MARK: A root that cannot fill a hole

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsNoInstantiableFoundNamingChain_whenRootsModuleSeesNoFulfillingDeclaration() async {
		// C3.7, H9: `App` sees no type that fulfills `UserService`, so its root cannot fill `Service`'s builder: reported at
		// the root's dependency that reaches the seam, with a note at the hole.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):9:5: error: No @Instantiable type or extension that module `App` can see fulfills `UserService`, which @Instantiated property `userService: any UserService` instantiates in chain: Root -> Service -> Profile. `Service` generates its dependency tree in module `Feature`, which cannot see one either, so the initializer SafeDI generated for it takes `userServiceBuilder`, whose case `Profile_Scope.userService` builds `userService`, and the root `Root` must fill it. Decorate `UserService`, or an extension of it, with @Instantiable; list `UserService` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; \(fulfillingDeclarationInAnotherModuleRemedy)
			\(fixtures["Feature"]!["Profile.swift"]):8:5: note: `Profile` instantiates `userService: any UserService` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(feature: Self.canonicalFeature, app: [Self.canonicalRoot]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsNoInstantiableFoundNamingChain_whenRootInSeamsModuleCallsSeamWithHole() async {
		// C3.8: a root in `Feature` sees what `Service`'s module sees, so it cannot fill the builder either.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Root.swift"]):7:5: error: No @Instantiable type or extension that module `Feature` can see fulfills `UserService`, which @Instantiated property `userService: any UserService` instantiates in chain: Root -> Service -> Profile. `Service` generates its dependency tree in module `Feature`, so the initializer SafeDI generated for it takes `userServiceBuilder`, whose case `Profile_Scope.userService` builds `userService`, and the root `Root` must fill it. Decorate `UserService`, or an extension of it, with @Instantiable; list `UserService` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; \(fulfillingDeclarationInAnotherModuleRemedy)
			\(fixtures["Feature"]!["Profile.swift"]):8:5: note: `Profile` instantiates `userService: any UserService` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.canonicalFeature + [Self.canonicalRoot])],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsNoInstantiableFoundWithMockOnlySentence_whenRootsModuleSeesOnlyMockOnlyFulfillingDeclaration() async {
		// C3.10: a `mockOnly` declaration is used only to generate mocks, so it fills no builder.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):9:5: error: No production @Instantiable declaration that module `App` can see fulfills `UserService`, which @Instantiated property `userService: any UserService` instantiates in chain: Root -> Service -> Profile. `Service` generates its dependency tree in module `Feature`, which cannot see one either, so the initializer SafeDI generated for it takes `userServiceBuilder`, whose case `Profile_Scope.userService` builds `userService`, and the root `Root` must fill it. A `mockOnly: true` declaration fulfills it, but is used only to generate mocks. Add a production @Instantiable declaration that fulfills `UserService`.
			\(fixtures["Feature"]!["Profile.swift"]):8:5: note: `Profile` instantiates `userService: any UserService` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(feature: Self.canonicalFeature, app: [
					"""
					@Instantiable(fulfillingAdditionalTypes: [UserService.self], mockOnly: true)
					public struct FakeUserService: UserService, Instantiable {
					    public static func mock() -> FakeUserService {
					        FakeUserService()
					    }
					}
					""",
					Self.canonicalRoot,
				]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingSeamsModuleToList_whenRootsModuleDoesNotListModuleOfSeamWhoseHolePassesUp() async {
		// `Shell` passes up `Service`'s builder, and `App` lists only `Mid`, so `Service`'s module is known only from `Mid`'s
		// view: the error names it, as the module `App` must list, and says that listing it fills nothing by itself.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):9:5: error: No @Instantiable type or extension that module `App` can see fulfills `UserService`, which @Instantiated property `userService: any UserService` instantiates in chain: Root -> Shell -> Service -> Profile. `Service` generates its dependency tree in module `Feature`, which cannot see one either, so the initializer SafeDI generated for it takes `userServiceBuilder`, whose case `Profile_Scope.userService` builds `userService`, and the root `Root` must fill it. A module that declares a root lists every module beneath it, and module `App` does not list `Feature`: \(Self.listModuleRemedy) Listing it lets SafeDI follow the chain, but `UserService` still needs a declaration that fulfills it. Decorate `UserService`, or an extension of it, with @Instantiable; list `UserService` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; \(fulfillingDeclarationInAnotherModuleRemedy)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.canonicalFeature),
					ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: ["import Feature\n\n" + seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let service: Service"])], dependencies: ["Feature"]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import Mid\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let shell: Shell"])], dependencies: ["Mid"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingModuleOfSeamHoldingHole_whenHolePassesUpThroughTwoSeamsOfUnlistedModules() async {
		// The builder passes up from `Service` through `Shell` and `Top`, and `App` lists only `Outer`: the modules named are
		// those that declare the seams on the way to the hole, facts of the hole and no choice among unlisted modules.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):9:5: error: No @Instantiable type or extension that module `App` can see fulfills `UserService`, which @Instantiated property `userService: any UserService` instantiates in chain: Root -> Top -> Shell -> Service -> Profile. `Service` generates its dependency tree in module `Feature`, which cannot see one either, so the initializer SafeDI generated for it takes `userServiceBuilder`, whose case `Profile_Scope.userService` builds `userService`, and the root `Root` must fill it. A module that declares a root lists every module beneath it, and module `App` does not list `Mid` or `Feature`: for each, \(Self.listModuleRemedy) Listing them lets SafeDI follow the chain, but `UserService` still needs a declaration that fulfills it. Decorate `UserService`, or an extension of it, with @Instantiable; list `UserService` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; \(fulfillingDeclarationInAnotherModuleRemedy)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.canonicalFeature),
					ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: ["import Feature\n\n" + seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let service: Service"])], dependencies: ["Feature"]),
					ModuleFixture(name: "Outer", packageName: "Other", swiftFileContent: ["import Mid\n\n" + seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated let shell: Shell"])], dependencies: ["Mid"]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import Outer\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let top: Top"])], dependencies: ["Outer"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingSeamsOwnModule_whenUnlistedModulesSortingBeforeAndAfterItDeclareTypesOfSeamsName() async {
		// `Aardvark` and `Zebra`, which only views carry too, each declare a `Service` of their own. The hole's module is the
		// one its signature was computed from, whichever way the other modules' names sort around it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):11:5: error: No @Instantiable type or extension that module `App` can see fulfills `UserService`, which @Instantiated property `userService: any UserService` instantiates in chain: Root -> Shell -> Service -> Profile. `Service` generates its dependency tree in module `Feature`, which cannot see one either, so the initializer SafeDI generated for it takes `userServiceBuilder`, whose case `Profile_Scope.userService` builds `userService`, and the root `Root` must fill it. A module that declares a root lists every module beneath it, and module `App` does not list `Feature`: \(Self.listModuleRemedy) Listing it lets SafeDI follow the chain, but `UserService` still needs a declaration that fulfills it. Decorate `UserService`, or an extension of it, with @Instantiable; list `UserService` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; \(fulfillingDeclarationInAnotherModuleRemedy)
			"""
		}) {
			let otherService = seamFixtureType(named: "Service", declarations: [])
			return try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Aardvark", packageName: "Shop", swiftFileContent: [otherService]),
					ModuleFixture(name: "Zebra", packageName: "Shop", swiftFileContent: [otherService]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.canonicalFeature),
					ModuleFixture(name: "AardvarkSeam", packageName: "Other", swiftFileContent: ["import Aardvark\n\n" + seamFixtureType(named: "FirstSeam", isSeam: true, declarations: ["@Instantiated let service: Service"])], dependencies: ["Aardvark"]),
					ModuleFixture(name: "ZebraSeam", packageName: "Other", swiftFileContent: ["import Zebra\n\n" + seamFixtureType(named: "LastSeam", isSeam: true, declarations: ["@Instantiated let service: Service"])], dependencies: ["Zebra"]),
					ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: ["import Feature\n\n" + seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let service: Service"])], dependencies: ["Feature"]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import AardvarkSeam\nimport Mid\nimport ZebraSeam\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let shell: Shell"])], dependencies: ["AardvarkSeam", "Mid", "ZebraSeam"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingModuleToList_whenRootsModuleFulfillsHoleButDoesNotListModuleOfSeamThatHoldsIt() async {
		// `App` declares `DefaultUserService`, but the walk from its root stops at `Service`, whose module it does not list,
		// so the declaration is never reached: the listing is the whole fix, and nothing tells it to add a declaration.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):10:5: error: `DefaultUserService` fulfills `UserService`, which @Instantiated property `userService: any UserService` instantiates in chain: Root -> Shell -> Service -> Profile, but SafeDI cannot follow that chain, because module `App` does not list `Feature`. A module that declares a root lists every module beneath it: \(Self.listModuleRemedy)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.canonicalFeature),
					ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: ["import Feature\n\n" + seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let service: Service"])], dependencies: ["Feature"]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
						"import Feature\nimport Mid\n\n" + Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let analytics: Analytics"]),
						"import Feature\nimport Mid\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let shell: Shell"]),
					], dependencies: ["Mid"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingModuleOfHolesOwner_whenRootsModuleFulfillsHoleAndListsSeamsModuleButNotOwnersModule() async {
		// `App` lists `Service`'s module, but `Profile`, which owns the hole, is in `Deep`, which it does not list.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):10:5: error: `DefaultUserService` fulfills `UserService`, which @Instantiated property `userService: any UserService` instantiates in chain: Root -> Service -> Profile, but SafeDI cannot follow that chain, because module `App` does not list `Deep`. A module that declares a root lists every module beneath it: \(Self.listModuleRemedy)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.deepOwnerModules(appFulfillers: [Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let analytics: Analytics"])]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingOwnersModule_whenNothingFulfillsHoleAndRootsModuleListsSeamsModuleButNotOwnersModule() async {
		// No declaration fulfills `UserService`, and `App` does not list `Deep` either: both are true, and listing `Deep`
		// fills nothing.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):10:5: error: No @Instantiable type or extension that module `App` can see fulfills `UserService`, which @Instantiated property `userService: any UserService` instantiates in chain: Root -> Service -> Profile. `Service` generates its dependency tree in module `Feature`, which cannot see one either, so the initializer SafeDI generated for it takes `userServiceBuilder`, whose case `Profile_Scope.userService` builds `userService`, and the root `Root` must fill it. A module that declares a root lists every module beneath it, and module `App` does not list `Deep`: \(Self.listModuleRemedy) Listing it lets SafeDI follow the chain, but `UserService` still needs a declaration that fulfills it. Decorate `UserService`, or an extension of it, with @Instantiable; list `UserService` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; \(fulfillingDeclarationInAnotherModuleRemedy)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.deepOwnerModules(appFulfillers: []),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingEveryUnlistedModuleInChainOrder_whenRootsModuleFulfillsHolePassedUpThroughSeamsOfUnlistedModules() async {
		// The walk stops at the first module `App` does not list and would stop at the next, so `App` needs both, named in
		// chain order: `Mid` comes before `Feature`, which sorts first.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):11:5: error: `DefaultUserService` fulfills `UserService`, which @Instantiated property `userService: any UserService` instantiates in chain: Root -> Top -> Shell -> Service -> Profile, but SafeDI cannot follow that chain, because module `App` does not list `Mid` or `Feature`. A module that declares a root lists every module beneath it: for each, \(Self.listModuleRemedy)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.twoSeamModules(appDependencies: ["Outer"]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsHolePassedUpThroughTwoSeams_whenRootsModuleListsEveryModuleTheErrorNamed() async throws {
		// The input of the test above with the modules it names listed, and nothing else changed.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.twoSeamModules(appDependencies: ["Feature", "Mid", "Outer"]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature", "Mid", "Outer"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_0FDDB1B7CEB7998E.self // If this line does not compile, compile the code SafeDI generates for module Outer into Outer: under Bazel, add Outer’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Top(_ scope: Top.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .shell(_, scope): return __safeDI_userServiceBuilder_Shell(scope)
		                }
		            }
		            func __safeDI_userServiceBuilder_Shell(_ scope: Shell.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .service(_, scope): return __safeDI_userServiceBuilder_Service(scope)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .profile(values, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope, analytics: values.analytics)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope, analytics: Analytics) -> any UserService {
		                switch scope {
		                case .userService:
		                    let userService: any UserService = DefaultUserService(analytics: analytics)
		                    return userService
		                }
		            }
		            return Top(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Top)
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}
		"""]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingFulfillingTypeOfUnlistedModule_whenModuleRootDoesNotListDeclaresFulfillingTypeOfPassedUpHole() async {
		// `Mid` declares `DefaultUserService`, but passes the hole up, since it need not list `Deep`, which holds `Profile`.
		// `App` does not list `Mid`, so listing it is the whole fix, and nothing tells `App` to write a declaration.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):9:5: error: `DefaultUserService` fulfills `UserService`, which @Instantiated property `userService: any UserService` instantiates in chain: Root -> Top -> Shell -> Service -> Profile, but SafeDI cannot follow that chain, because module `App` does not list `Mid`. A module that declares a root lists every module beneath it: \(Self.listModuleRemedy)
			\(fixtures["Deep"]!["Profile.swift"]):7:5: note: `Profile` instantiates `userService: any UserService` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.fulfillingTypeInMidModules(midDeclarations: [Self.defaultUserService], appDependencies: ["Deep", "Feature", "Outer"]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingFulfillingTypeOfUnlistedModule_whenRootsModuleListsOnlyOutermostSeamsModule() async {
		// `App` lists `Outer` alone, so `Mid`'s declaration reaches it in a view only, and all three modules must be listed.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):9:5: error: `DefaultUserService` fulfills `UserService`, which @Instantiated property `userService: any UserService` instantiates in chain: Root -> Top -> Shell -> Service -> Profile, but SafeDI cannot follow that chain, because module `App` does not list `Mid`, `Feature`, or `Deep`. A module that declares a root lists every module beneath it: for each, \(Self.listModuleRemedy)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.fulfillingTypeInMidModules(midDeclarations: [Self.defaultUserService], appDependencies: ["Outer"]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsHoleWithDeclarationOfModuleTheErrorNamed_whenRootsModuleListsThatModule() async throws {
		// The input of the test above that names `Mid`, with `Mid` listed, and nothing else changed.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.fulfillingTypeInMidModules(midDeclarations: [Self.defaultUserService], appDependencies: ["Deep", "Feature", "Mid", "Outer"]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Deep", "Feature", "Mid", "Outer"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_D466B779B87F29B5.self // If this line does not compile, compile the code SafeDI generates for module Outer into Outer: under Bazel, add Outer’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Top(_ scope: Top.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .shell(_, scope): return __safeDI_userServiceBuilder_Shell(scope)
		                }
		            }
		            func __safeDI_userServiceBuilder_Shell(_ scope: Shell.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .service(_, scope): return __safeDI_userServiceBuilder_Service(scope)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .profile(_, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope) -> any UserService {
		                switch scope {
		                case .userService:
		                    let userService: any UserService = DefaultUserService()
		                    return userService
		                }
		            }
		            return Top(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Top)
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}
		"""]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSayingListingFillsNothing_whenUnlistedModuleDeclaresOnlyMockOnlyFulfillingDeclaration() async {
		// A `mockOnly` declaration fills no builder, so listing `Mid` would leave the hole unfilled.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):9:5: error: No @Instantiable type or extension that module `App` can see fulfills `UserService`, which @Instantiated property `userService: any UserService` instantiates in chain: Root -> Top -> Shell -> Service -> Profile. `Service` generates its dependency tree in module `Feature`, which cannot see one either, so the initializer SafeDI generated for it takes `userServiceBuilder`, whose case `Profile_Scope.userService` builds `userService`, and the root `Root` must fill it. A module that declares a root lists every module beneath it, and module `App` does not list `Mid`: \(Self.listModuleRemedy) Listing it lets SafeDI follow the chain, but `UserService` still needs a declaration that fulfills it. Decorate `UserService`, or an extension of it, with @Instantiable; list `UserService` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; \(fulfillingDeclarationInAnotherModuleRemedy)
			\(fixtures["Deep"]!["Profile.swift"]):7:5: note: `Profile` instantiates `userService: any UserService` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.fulfillingTypeInMidModules(
					midDeclarations: [
						"""
						import Deep

						@Instantiable(fulfillingAdditionalTypes: [UserService.self], mockOnly: true)
						public struct FakeUserService: UserService, Instantiable {
						    public static func mock() -> FakeUserService {
						        FakeUserService()
						    }
						}
						""",
					],
					appDependencies: ["Deep", "Feature", "Outer"],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorSayingListingFillsNothing_whenFulfillingTypeIsInModuleOffTheChainToTheHole() async {
		// `Impl` declares the type, and a view carries it, but `Impl` declares nothing on the way to the hole: listing `Mid`,
		// the module the error names, would leave the hole unfilled.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):9:5: error: No @Instantiable type or extension that module `App` can see fulfills `UserService`, which @Instantiated property `userService: any UserService` instantiates in chain: Root -> Top -> Shell -> Service -> Profile. `Service` generates its dependency tree in module `Feature`, which cannot see one either, so the initializer SafeDI generated for it takes `userServiceBuilder`, whose case `Profile_Scope.userService` builds `userService`, and the root `Root` must fill it. A module that declares a root lists every module beneath it, and module `App` does not list `Mid`: \(Self.listModuleRemedy) Listing it lets SafeDI follow the chain, but `UserService` still needs a declaration that fulfills it. Decorate `UserService`, or an extension of it, with @Instantiable; list `UserService` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; \(fulfillingDeclarationInAnotherModuleRemedy)
			\(fixtures["Deep"]!["Profile.swift"]):7:5: note: `Profile` instantiates `userService: any UserService` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.fulfillingTypeInMidModules(midDeclarations: [], impl: [Self.defaultUserService], appDependencies: ["Deep", "Feature", "Outer"]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorWithChainThroughFill_whenSeamCalledInsideFillPassesHoleUp() async {
		// `Top`'s tree fills `Inner1`'s hole with `DefaultGadget`, which calls `Inner2`, whose hole `Top` passes up: the chain
		// goes through the fill that makes the call.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):10:5: error: No @Instantiable type or extension that module `App` can see fulfills `UserService`, which @Instantiated property `userService: any UserService` instantiates in chain: Root -> Top -> Inner1 -> Holder -> DefaultGadget -> Inner2 -> Profile. `Inner2` generates its dependency tree in module `Feature`, which cannot see one either, so the initializer SafeDI generated for it takes `userServiceBuilder`, whose case `Profile_Scope.userService` builds `userService`, and the root `Root` must fill it. Decorate `UserService`, or an extension of it, with @Instantiable; list `UserService` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; \(fulfillingDeclarationInAnotherModuleRemedy)
			\(fixtures["Feature"]!["Profile.swift"]):7:5: note: `Profile` instantiates `userService: any UserService` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.threeModules(
					feature: [
						Self.userServiceProtocol,
						"public protocol /Users/dfed/Libradget {}",
						seamFixtureType(named: "Holder", declarations: ["@Instantiated let gadget: any Gadget"]),
						seamFixtureType(named: "Inner1", isSeam: true, declarations: ["@Instantiated let holder: Holder"]),
						seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
						seamFixtureType(named: "Inner2", isSeam: true, declarations: ["@Instantiated let profile: Profile"]),
					],
					mid: [
						Self.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Instantiated let inner2: Inner2"]),
						seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated let inner1: Inner1"]),
					],
					app: [seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let top: Top"])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarry_namingSeamsModule_whenSeamHoldingHoleIsKnownOnlyThroughView() async {
		// `App` does not list `Feature`, and fills `Service`'s hole, which `Shell` passes up: the module that must read a
		// fulfilling declaration is `Service`'s, which `App` knows only from the hole.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultUserService.swift"]):10:5: error: `DefaultUserService` receives `theme: Theme`, which `Home` builds after `profile`, since `Theme` receives `profile` only if available, so the scope SafeDI hands the builder for `Profile`’s `userService: any UserService` (case `Profile_Scope.userService` of `userServiceBuilder`) does not carry it. Receive `profile` on `Theme` some other way, or declare an @Instantiable type that fulfills `UserService` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Base"]!["Home.swift"]):9:5: note: `Home` declares `theme: Theme` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Base", packageName: "Shop", swiftFileContent: [
						Self.userServiceProtocol,
						seamFixtureType(named: "Theme", declarations: ["@Received(onlyIfAvailable: true) let profile: Profile?"]),
						seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
						seamFixtureType(named: "Home", declarations: ["@Instantiated let profile: Profile", "@Instantiated let theme: Theme"]),
					]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: ["import Base\n\n" + seamFixtureType(named: "Service", isSeam: true, declarations: ["@Received let theme: Theme", "@Instantiated let home: Home"])], dependencies: ["Base"]),
					ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: ["import Base\nimport Feature\n\n" + seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Received let theme: Theme", "@Instantiated let service: Service"])], dependencies: ["Base", "Feature"]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
						"import Base\nimport Mid\n\n" + Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let theme: Theme"]),
						"import Base\nimport Mid\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let shell: Shell", "@Instantiated let userService: any UserService"]),
					], dependencies: ["Base", "Mid"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarry_namingPassingUpSeamsModule_whenThatSeamIsKnownOnlyThroughView() async {
		// `Shell` binds `theme` where it calls `Service`, and `App` lists neither: the module that could fill the builder
		// itself is `Shell`'s, which `App` knows only from the hole.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultUserService.swift"]):10:5: error: `DefaultUserService` receives `theme: Theme`, which `Shell` builds where it calls `Service`, but `Shell` passes the builder for `Profile`’s `userService: any UserService` (case `Profile_Scope.userService` of `userServiceBuilder`) on from its own caller, which cannot hand it `Shell`’s values. Declare `@Received let theme: Theme` on `Service`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `UserService` in module `Mid` or a module it lists among its SafeDI dependencies, so `Shell` fills the builder itself.
			note: `Shell` declares `theme: Theme` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Base", packageName: "Shop", swiftFileContent: [
						Self.userServiceProtocol,
						seamFixtureType(named: "Theme", declarations: []),
						seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
					]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: ["import Base\n\n" + seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let profile: Profile"])], dependencies: ["Base"]),
					ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: ["import Base\nimport Feature\n\n" + seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let service: Service"])], dependencies: ["Base", "Feature"]),
					ModuleFixture(name: "Outer", packageName: "Other", swiftFileContent: ["import Mid\n\n" + seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated let shell: Shell"])], dependencies: ["Mid"]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
						"import Base\nimport Outer\n\n" + Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let theme: Theme"]),
						"import Base\nimport Outer\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let top: Top", "@Instantiated let userService: any UserService"]),
					], dependencies: ["Base", "Outer"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarry_whenSeamHoldingHoleIsKnownOnlyThroughViewAndFieldIsInternal() async {
		// `Service`'s struct carries `token` at `internal` access, so a fill in `App` cannot read it, though `App` knows
		// `Service` only from the hole `Shell` passes up.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["TokenUserService.swift"]):10:5: error: `TokenUserService` receives `token: [3 of Int]`, which the scope SafeDI hands the builder for `Profile`’s `userService: any UserService` (case `Profile_Scope.userService` of `userServiceBuilder`) carries only at `internal` access, and module `App` is not module `Feature`. `[3 of Int]` is `internal` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Feature` or on a type that receives it is `internal` (`Screen.init(token:profile:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records, or declare an @Instantiable type that fulfills `UserService` in module `Feature` or a module it lists among its SafeDI dependencies, so `Service`’s tree builds it.
			note: `Screen` declares `token: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						Self.userServiceProtocol,
						seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
						seamFixtureType(named: "Screen", declarations: ["@Forwarded let token: [3 of Int]", "@Instantiated let profile: Profile"]).replacingOccurrences(of: "public init(", with: "init("),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let screenBuilder: Instantiator<Screen>"]),
					]),
					ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: ["import Feature\n\n" + seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let service: Service"])], dependencies: ["Feature"]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
						"import Feature\nimport Mid\n\n" + Self.fulfillingType(named: "TokenUserService", fulfilling: "UserService", declarations: ["@Received let token: [3 of Int]"]),
						"import Feature\nimport Mid\n\n" + seamFixtureType(named: "Carrier", declarations: ["@Forwarded let token: [3 of Int]", "@Instantiated let userService: any UserService"]),
						"import Feature\nimport Mid\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let shell: Shell", "@Instantiated let carrierBuilder: Instantiator<Carrier>"]),
					], dependencies: ["Mid"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Where the hole sits

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableBuilderForPlacesInSendableFunctions_whenHolesSitBeneathOrAreWrappers() async throws {
		// C1.4: beneath an `Instantiator`, the place's case carries the forwarded `name` and the owner's `cache`. C1.7:
		// beneath a `SendableInstantiator`, it is a case of the `@Sendable` enum, which carries only what the `@Sendable`
		// builder function binds. C1.10: beneath two, what the inner one binds. Each level carries the holes built before it
		// (C2.7).
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(feature: Self.wrapperFeature, app: Self.wrapperFulfillers + [Self.wrapperRoot]),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension ServiceI {
		    @frozen public enum SafeDIScope_UserService {
		        case profileBuilder(profileBuilder_Values, SafeDIScope_UserService.ProfileI_Scope)

		        public struct profileBuilder_Values {
		            public let analytics: Analytics
		            public let session: Session
		        }

		        @frozen public enum ProfileI_Scope {
		            case userService(userService_Values)

		            public struct userService_Values {
		                public let name: String
		                public let cache: Cache
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        let analytics = Analytics()
		        let session = Session()
		        let __safeDI_userServiceValues_profileBuilder = SafeDIScope_UserService.profileBuilder_Values(analytics: analytics, session: session)
		        func __safeDI_profileBuilder(name: String) -> ProfileI {
		            let cache = Cache()
		            let userService: any UserService = __safeDI_userServiceBuilder(.profileBuilder(__safeDI_userServiceValues_profileBuilder, .userService(SafeDIScope_UserService.ProfileI_Scope.userService_Values(name: name, cache: cache))))
		            return ProfileI(name: name, cache: cache, userService: userService, analytics: analytics)
		        }
		        let profileBuilder = Instantiator<ProfileI> {
		            __safeDI_profileBuilder(name: $0)
		        }
		        self.init(analytics: analytics, session: session, profileBuilder: profileBuilder)
		    }
		}

		extension ServiceI {
		    public enum __safeDI_ServiceI_66F5310FDE473DDF {}
		}

		extension ServiceN {
		    @frozen public enum SafeDIScope_UserService {
		        @frozen public enum ProfileN_Scope {
		            case userService(userService_Values)

		            public struct userService_Values {
		                public let analytics: Analytics
		            }
		        }
		    }

		    @frozen public enum SafeDISendableScope_UserService {
		        case screenBuilder_Sendable(SafeDISendableScope_UserService.Screen_Scope)

		        @frozen public enum Screen_Scope {
		            case profileBuilder(SafeDIScope_UserService.ProfileN_Scope)
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceSendableBuilder: @escaping @Sendable (SafeDISendableScope_UserService) -> any UserService) {
		        let analytics = Analytics()
		        let session = Session()
		        @Sendable func __safeDI_screenBuilder(title: String) -> Screen {
		            let cache = Cache()
		            @Sendable func __safeDI_profileBuilder() -> ProfileN {
		                let analytics = Analytics()
		                let userService: any UserService = __safeDI_userServiceSendableBuilder(.screenBuilder_Sendable(.profileBuilder(.userService(SafeDIScope_UserService.ProfileN_Scope.userService_Values(analytics: analytics)))))
		                return ProfileN(userService: userService, analytics: analytics, title: title)
		            }
		            let profileBuilder = SendableInstantiator<ProfileN>(__safeDI_profileBuilder)
		            return Screen(title: title, cache: cache, profileBuilder: profileBuilder)
		        }
		        let screenBuilder = SendableInstantiator<Screen> {
		            __safeDI_screenBuilder(title: $0)
		        }
		        self.init(analytics: analytics, session: session, screenBuilder: screenBuilder)
		    }
		}

		extension ServiceN {
		    public enum __safeDI_ServiceN_F90D6E1B71FC1E9C {}
		}

		extension ServiceS {
		    @frozen public enum SafeDIScope_UserService {
		        @frozen public enum ProfileS_Scope {
		            case userService(userService_Values)

		            public struct userService_Values {
		                public let name: String
		                public let cache: Cache
		                public let analytics: Analytics
		            }
		        }
		    }

		    @frozen public enum SafeDISendableScope_UserService {
		        case profileBuilder(SafeDIScope_UserService.ProfileS_Scope)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceSendableBuilder: @escaping @Sendable (SafeDISendableScope_UserService) -> any UserService) {
		        let analytics = Analytics()
		        let session = Session()
		        @Sendable func __safeDI_profileBuilder(name: String) -> ProfileS {
		            let cache = Cache()
		            let analytics = Analytics()
		            let userService: any UserService = __safeDI_userServiceSendableBuilder(.profileBuilder(.userService(SafeDIScope_UserService.ProfileS_Scope.userService_Values(name: name, cache: cache, analytics: analytics))))
		            return ProfileS(name: name, cache: cache, userService: userService, analytics: analytics)
		        }
		        let profileBuilder = SendableInstantiator<ProfileS> {
		            __safeDI_profileBuilder(name: $0)
		        }
		        self.init(analytics: analytics, session: session, profileBuilder: profileBuilder)
		    }
		}

		extension ServiceS {
		    public enum __safeDI_ServiceS_CF0DFD007F26CD06 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsEachBuilderInCallersTree_whenHolesSitBeneathOrAreWrappers() async throws {
		// C1.4, C1.7, C1.10 in `App`: each fill builds the property as inline builds it there, a place inside a `@Sendable`
		// function in a `@Sendable` fill; the values equal the build with every fulfilling declaration in `Feature`.
		let modules = Self.modules(feature: Self.wrapperFeature, app: Self.wrapperFulfillers + [Self.wrapperRoot])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_serviceI() -> ServiceI {
		            _ = ServiceI.__safeDI_ServiceI_66F5310FDE473DDF.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_ServiceI(_ scope: ServiceI.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .profileBuilder(values, scope): return __safeDI_userServiceBuilder_ServiceI_ProfileI_Scope(scope, analytics: values.analytics)
		                }
		            }
		            func __safeDI_userServiceBuilder_ServiceI_ProfileI_Scope(_ scope: ServiceI.SafeDIScope_UserService.ProfileI_Scope, analytics: Analytics) -> any UserService {
		                switch scope {
		                case .userService:
		                    let userService: any UserService = DefaultUserService(analytics: analytics)
		                    return userService
		                }
		            }
		            return ServiceI(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_ServiceI)
		        }
		        let serviceI: ServiceI = __safeDI_serviceI()
		        func __safeDI_serviceS() -> ServiceS {
		            _ = ServiceS.__safeDI_ServiceS_CF0DFD007F26CD06.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @Sendable func __safeDI_userServiceSendableBuilder_ServiceS(_ scope: ServiceS.SafeDISendableScope_UserService) -> any UserService {
		                switch scope {
		                case let .profileBuilder(scope): return __safeDI_userServiceBuilder_ServiceS_ProfileS_Scope(scope)
		                }
		            }
		            @Sendable func __safeDI_userServiceBuilder_ServiceS_ProfileS_Scope(_ scope: ServiceS.SafeDIScope_UserService.ProfileS_Scope) -> any UserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    let userService: any UserService = DefaultUserService(analytics: analytics)
		                    return userService
		                }
		            }
		            return ServiceS(__safeDI_userServiceSendableBuilder: __safeDI_userServiceSendableBuilder_ServiceS)
		        }
		        let serviceS: ServiceS = __safeDI_serviceS()
		        func __safeDI_serviceN() -> ServiceN {
		            _ = ServiceN.__safeDI_ServiceN_F90D6E1B71FC1E9C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @Sendable func __safeDI_userServiceSendableBuilder_ServiceN(_ scope: ServiceN.SafeDISendableScope_UserService) -> any UserService {
		                switch scope {
		                case let .screenBuilder_Sendable(scope): return __safeDI_userServiceSendableBuilder_ServiceN_Screen_Scope(scope)
		                }
		            }
		            @Sendable func __safeDI_userServiceSendableBuilder_ServiceN_Screen_Scope(_ scope: ServiceN.SafeDISendableScope_UserService.Screen_Scope) -> any UserService {
		                switch scope {
		                case let .profileBuilder(scope): return __safeDI_userServiceBuilder_ServiceN_ProfileN_Scope(scope)
		                }
		            }
		            @Sendable func __safeDI_userServiceBuilder_ServiceN_ProfileN_Scope(_ scope: ServiceN.SafeDIScope_UserService.ProfileN_Scope) -> any UserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    let userService: any UserService = DefaultUserService(analytics: analytics)
		                    return userService
		                }
		            }
		            return ServiceN(__safeDI_userServiceSendableBuilder: __safeDI_userServiceSendableBuilder_ServiceN)
		        }
		        let serviceN: ServiceN = __safeDI_serviceN()
		        self.init(serviceI: serviceI, serviceS: serviceS, serviceN: serviceN)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: Self.wrapperFeature + Self.wrapperFulfillers, app: [Self.wrapperRoot]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderPerHoleThatIsWrapper_whenSeamItselfOwnsHoles() async throws {
		// C1.1, C1.11: `ServiceW` instantiates four wrappers no declaration `Feature` sees fulfills. Each builder returns
		// the plain value and the seam builds the wrapper, its label adds `Builder` to the property's, and each struct
		// carries the holes the tree binds before it (C2.7); the fills build each value as inline builds it.
		let feature = [
			"""
			public protocol UserService: Sendable {}

			public struct AnyUserService: UserService {
			    public init(_ base: any UserService) {
			        self.base = base
			    }

			    let base: any UserService
			}
			""",
			seamFixtureType(named: "Analytics", isFinalClass: true, declarations: [], conformances: ", Sendable"),
			seamFixtureType(named: "ServiceW", isSeam: true, declarations: [
				"@Received let analytics: Analytics",
				"@Instantiated let lazyUserService: LazilyInstantiated<any UserService>",
				"@Instantiated let sendableLazyUserService: SendableLazilyInstantiated<any UserService>",
				"@Instantiated(fulfilledByType: \"NamedUserService\", erasedToConcreteExistential: true) let erasedUserServiceBuilder: ErasedInstantiator<String, AnyUserService>",
				"@Instantiated(fulfilledByType: \"NamedUserService\", erasedToConcreteExistential: true) let sendableErasedUserServiceBuilder: SendableErasedInstantiator<String, AnyUserService>",
			]),
		]
		let fulfillers = Self.wrapperFulfillers + [
			seamFixtureType(named: "NamedUserService", declarations: ["@Forwarded let name: String", "@Received let analytics: Analytics"], conformances: ", UserService"),
		]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let serviceW: ServiceW"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension ServiceW {
		    @frozen public enum SafeDIScope_NamedUserService {
		        case erasedUserServiceBuilder(erasedUserServiceBuilder_Values, String)

		        public struct erasedUserServiceBuilder_Values {
		            public let analytics: Analytics
		            public let lazyUserService: LazilyInstantiated<any UserService>
		            public let sendableLazyUserService: SendableLazilyInstantiated<any UserService>
		        }
		    }

		    @frozen public enum SafeDISendableScope_NamedUserService {
		        case sendableErasedUserServiceBuilder(String)
		    }

		    @frozen public enum SafeDIScope_UserService {
		        case lazyUserService(lazyUserService_Values)

		        public struct lazyUserService_Values {
		            public let analytics: Analytics
		        }
		    }

		    @frozen public enum SafeDISendableScope_UserService {
		        case sendableLazyUserService
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_analytics analytics: Analytics, __safeDI_namedUserServiceBuilder: @escaping (SafeDIScope_NamedUserService) -> AnyUserService, __safeDI_namedUserServiceSendableBuilder: @escaping @Sendable (SafeDISendableScope_NamedUserService) -> AnyUserService, __safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService, __safeDI_userServiceSendableBuilder: @escaping @Sendable (SafeDISendableScope_UserService) -> any UserService) {
		        func __safeDI_lazyUserService() -> any UserService {
		            __safeDI_userServiceBuilder(.lazyUserService(SafeDIScope_UserService.lazyUserService_Values(analytics: analytics)))
		        }
		        let lazyUserService = LazilyInstantiated<any UserService>(__safeDI_lazyUserService)
		        @Sendable func __safeDI_sendableLazyUserService() -> any UserService {
		            __safeDI_userServiceSendableBuilder(.sendableLazyUserService)
		        }
		        let sendableLazyUserService = SendableLazilyInstantiated<any UserService>(__safeDI_sendableLazyUserService)
		        let erasedUserServiceBuilder = ErasedInstantiator<String, AnyUserService> {
		            __safeDI_namedUserServiceBuilder(.erasedUserServiceBuilder(SafeDIScope_NamedUserService.erasedUserServiceBuilder_Values(analytics: analytics, lazyUserService: lazyUserService, sendableLazyUserService: sendableLazyUserService), $0))
		        }
		        let sendableErasedUserServiceBuilder = SendableErasedInstantiator<String, AnyUserService> {
		            __safeDI_namedUserServiceSendableBuilder(.sendableErasedUserServiceBuilder($0))
		        }
		        self.init(analytics: analytics, lazyUserService: lazyUserService, sendableLazyUserService: sendableLazyUserService, erasedUserServiceBuilder: erasedUserServiceBuilder, sendableErasedUserServiceBuilder: sendableErasedUserServiceBuilder)
		    }
		}

		extension ServiceW {
		    public enum __safeDI_ServiceW_B74D48128E34846B {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        let analytics = Analytics()
		        func __safeDI_serviceW() -> ServiceW {
		            _ = ServiceW.__safeDI_ServiceW_B74D48128E34846B.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_namedUserServiceBuilder_ServiceW(_ scope: ServiceW.SafeDIScope_NamedUserService) -> AnyUserService {
		                switch scope {
		                case let .erasedUserServiceBuilder(scope, __safeDI_forwarded):
		                    let analytics = scope.analytics
		                    func __safeDI_erasedUserServiceBuilder(name: String) -> NamedUserService {
		                        NamedUserService(name: name, analytics: analytics)
		                    }
		                    return AnyUserService(__safeDI_erasedUserServiceBuilder(name: __safeDI_forwarded))
		                }
		            }
		            @Sendable func __safeDI_namedUserServiceSendableBuilder_ServiceW(_ scope: ServiceW.SafeDISendableScope_NamedUserService) -> AnyUserService {
		                switch scope {
		                case let .sendableErasedUserServiceBuilder(__safeDI_forwarded):
		                    @Sendable func __safeDI_sendableErasedUserServiceBuilder(name: String) -> NamedUserService {
		                        NamedUserService(name: name, analytics: analytics)
		                    }
		                    return AnyUserService(__safeDI_sendableErasedUserServiceBuilder(name: __safeDI_forwarded))
		                }
		            }
		            func __safeDI_userServiceBuilder_ServiceW(_ scope: ServiceW.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .lazyUserService(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_lazyUserService() -> DefaultUserService {
		                        DefaultUserService(analytics: analytics)
		                    }
		                    return __safeDI_lazyUserService()
		                }
		            }
		            @Sendable func __safeDI_userServiceSendableBuilder_ServiceW(_ scope: ServiceW.SafeDISendableScope_UserService) -> any UserService {
		                switch scope {
		                case .sendableLazyUserService:
		                    @Sendable func __safeDI_sendableLazyUserService() -> DefaultUserService {
		                        DefaultUserService(analytics: analytics)
		                    }
		                    return __safeDI_sendableLazyUserService()
		                }
		            }
		            return ServiceW(__safeDI_analytics: analytics, __safeDI_namedUserServiceBuilder: __safeDI_namedUserServiceBuilder_ServiceW, __safeDI_namedUserServiceSendableBuilder: __safeDI_namedUserServiceSendableBuilder_ServiceW, __safeDI_userServiceBuilder: __safeDI_userServiceBuilder_ServiceW, __safeDI_userServiceSendableBuilder: __safeDI_userServiceSendableBuilder_ServiceW)
		        }
		        let serviceW: ServiceW = __safeDI_serviceW()
		        self.init(analytics: analytics, serviceW: serviceW)
		    }
		}
		"""]))
		// The comparator does not call an erased instantiator, so the probes call each one.
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature + fulfillers, app: [root]), probes: [
			DifferentialValueProbe("Root()"),
			DifferentialValueProbe(#"Root().serviceW.erasedUserServiceBuilder.instantiate("first")"#),
			DifferentialValueProbe(#"Root().serviceW.sendableErasedUserServiceBuilder.instantiate("second")"#),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresOneCaseForOwnerType_whenTreeBuildsHolesOwnerAtTwoSites() async throws {
		// C1.18, C4.8, C8.13, C2.21: `Avatar` is built under `home` and under `settings`, so its hole has two sites, which
		// share `Avatar`'s one case, filled by one function. Each case carries what its type binds before the property: the
		// root's `analytics`, and `Home`'s `session`. The fill reads `session` only if available, so it takes an optional
		// parameter, which the `home` route passes from `Home`'s case and the `settings` route from `Root`.
		let feature = [
			"public protocol UserService {}",
			seamFixtureType(named: "Analytics", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Theme", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Avatar", declarations: ["@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "Home", declarations: ["@Instantiated let session: Session", "@Instantiated let avatar: Avatar"]),
			seamFixtureType(named: "Settings", declarations: ["@Instantiated let theme: Theme", "@Instantiated let avatar: Avatar"]),
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let home: Home", "@Instantiated let settings: Settings"]),
		]
		let fulfillers = [
			Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let analytics: Analytics", "@Received(onlyIfAvailable: true) let session: Session?"]),
		]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let session: Session", "@Instantiated let service: Service"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Service {
		    @frozen public enum SafeDIScope_UserService {
		        case home(home_Values, SafeDIScope_UserService.Home_Scope)
		        case settings(settings_Values, SafeDIScope_UserService.Settings_Scope)

		        public struct home_Values {
		            public let analytics: Analytics
		        }

		        public struct settings_Values {
		            public let analytics: Analytics
		            public let home: Home
		        }

		        @frozen public enum Home_Scope {
		            case avatar(avatar_Values, SafeDIScope_UserService.Avatar_Scope)

		            public struct avatar_Values {
		                public let session: Session
		            }
		        }

		        @frozen public enum Settings_Scope {
		            case avatar(avatar_Values, SafeDIScope_UserService.Avatar_Scope)

		            public struct avatar_Values {
		                public let theme: Theme
		            }
		        }

		        @frozen public enum Avatar_Scope {
		            case userService(userService_Values)

		            public struct userService_Values {}
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        let analytics = Analytics()
		        let __safeDI_userServiceValues_home = SafeDIScope_UserService.home_Values(analytics: analytics)
		        func __safeDI_home() -> Home {
		            let session = Session()
		            let __safeDI_userServiceValues_avatar = SafeDIScope_UserService.Home_Scope.avatar_Values(session: session)
		            func __safeDI_avatar() -> Avatar {
		                let userService: any UserService = __safeDI_userServiceBuilder(.home(__safeDI_userServiceValues_home, .avatar(__safeDI_userServiceValues_avatar, .userService(SafeDIScope_UserService.Avatar_Scope.userService_Values()))))
		                return Avatar(userService: userService)
		            }
		            let avatar: Avatar = __safeDI_avatar()
		            return Home(session: session, avatar: avatar)
		        }
		        let home: Home = __safeDI_home()
		        let __safeDI_userServiceValues_settings = SafeDIScope_UserService.settings_Values(analytics: analytics, home: home)
		        func __safeDI_settings() -> Settings {
		            let theme = Theme()
		            let __safeDI_userServiceValues_avatar = SafeDIScope_UserService.Settings_Scope.avatar_Values(theme: theme)
		            func __safeDI_avatar() -> Avatar {
		                let userService: any UserService = __safeDI_userServiceBuilder(.settings(__safeDI_userServiceValues_settings, .avatar(__safeDI_userServiceValues_avatar, .userService(SafeDIScope_UserService.Avatar_Scope.userService_Values()))))
		                return Avatar(userService: userService)
		            }
		            let avatar: Avatar = __safeDI_avatar()
		            return Settings(theme: theme, avatar: avatar)
		        }
		        let settings: Settings = __safeDI_settings()
		        self.init(analytics: analytics, home: home, settings: settings)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_1A94721340032BA5 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        let session = Session()
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_1A94721340032BA5.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .home(values, scope): return __safeDI_userServiceBuilder_Service_Home_Scope(scope, analytics: values.analytics)
		                case let .settings(values, scope): return __safeDI_userServiceBuilder_Service_Settings_Scope(scope, analytics: values.analytics, session: session)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service_Home_Scope(_ scope: Service.SafeDIScope_UserService.Home_Scope, analytics: Analytics) -> any UserService {
		                switch scope {
		                case let .avatar(values, scope): return __safeDI_userServiceBuilder_Service_Avatar_Scope(scope, analytics: analytics, session: values.session)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service_Avatar_Scope(_ scope: Service.SafeDIScope_UserService.Avatar_Scope, analytics: Analytics, session: Session?) -> any UserService {
		                switch scope {
		                case .userService:
		                    let userService: any UserService = DefaultUserService(analytics: analytics, session: session)
		                    return userService
		                }
		            }
		            func __safeDI_userServiceBuilder_Service_Settings_Scope(_ scope: Service.SafeDIScope_UserService.Settings_Scope, analytics: Analytics, session: Session?) -> any UserService {
		                switch scope {
		                case let .avatar(_, scope): return __safeDI_userServiceBuilder_Service_Avatar_Scope(scope, analytics: analytics, session: session)
		                }
		            }
		            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
		        }
		        let service: Service = __safeDI_service()
		        self.init(session: session, service: service)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature + fulfillers, app: [root]))
	}

	// MARK: What is in scope at the build site

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsSiblingsThatReachNoCarrierFirst_whenSiblingIsDeclaredAfterHolesCarrier() async throws {
		// C2.9, C2.7, C8.3, C8.5: `theme`, declared after `profile`, which carries the hole, reaches no carrier, so it is
		// built first and the struct carries it; `cache`, beside the hole, too; `badge` receives the hole, so it follows
		// it. `DefaultUserService` reads `logger`, which only `Root` holds, so `Root` builds it before the seam.
		let feature = [
			"public protocol UserService {}",
			seamFixtureType(named: "Theme", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Cache", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Badge", declarations: ["@Received let userService: any UserService"]),
			seamFixtureType(named: "Profile", declarations: ["@Instantiated let badge: Badge", "@Instantiated let userService: any UserService", "@Instantiated let cache: Cache"]),
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let profile: Profile", "@Instantiated let theme: Theme"]),
		]
		let fulfillers = [
			Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let cache: Cache", "@Received let logger: Logger", "@Received let theme: Theme"]),
		]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service", "@Instantiated let logger: Logger"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Service {
		    @frozen public enum SafeDIScope_UserService {
		        case profile(profile_Values, SafeDIScope_UserService.Profile_Scope)

		        public struct profile_Values {
		            public let theme: Theme
		        }

		        @frozen public enum Profile_Scope {
		            case userService(userService_Values)

		            public struct userService_Values {
		                public let cache: Cache
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        let theme = Theme()
		        let __safeDI_userServiceValues_profile = SafeDIScope_UserService.profile_Values(theme: theme)
		        func __safeDI_profile() -> Profile {
		            let cache = Cache()
		            let userService: any UserService = __safeDI_userServiceBuilder(.profile(__safeDI_userServiceValues_profile, .userService(SafeDIScope_UserService.Profile_Scope.userService_Values(cache: cache))))
		            let badge = Badge(userService: userService)
		            return Profile(badge: badge, userService: userService, cache: cache)
		        }
		        let profile: Profile = __safeDI_profile()
		        self.init(profile: profile, theme: theme)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_66BD69946A08889B {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        let logger = Logger()
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_66BD69946A08889B.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .profile(values, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope, theme: values.theme)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope, theme: Theme) -> any UserService {
		                switch scope {
		                case let .userService(scope):
		                    let cache = scope.cache
		                    let userService: any UserService = DefaultUserService(cache: cache, logger: logger, theme: theme)
		                    return userService
		                }
		            }
		            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service, logger: logger)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature + fulfillers, app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilToReceiveInsideFill_whenRootBuildsLabelAfterSeamCall() async throws {
		// `Root` declares `filter` after `service`, and `AppFilter`, which builds `filter`, requires `service`, so the seam is
		// called first. `DefaultUserService` in the fill receives `filter` only if available, so it is passed `nil`, as it is
		// when the seam's tree is built inline: the fill is generated with the properties its caller generates later, as a
		// mock's fill of a public mock's builder is.
		let feature = Self.canonicalFeature + ["public protocol FilterProtocol {}"]
		let fulfillers = [
			Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let analytics: Analytics", "@Received(onlyIfAvailable: true) let filter: (any FilterProtocol)?"]),
			Self.fulfillingType(named: "AppFilter", fulfilling: "FilterProtocol", declarations: ["@Received let service: Service"]),
		]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service", "@Instantiated let filter: any FilterProtocol"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + Self.canonicalServiceCode])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_6E216DA2A3D4C4DA.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .profile(values, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope, analytics: values.analytics)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope, analytics: Analytics) -> any UserService {
		                switch scope {
		                case .userService:
		                    let userService: any UserService = DefaultUserService(analytics: analytics, filter: nil)
		                    return userService
		                }
		            }
		            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
		        }
		        let service: Service = __safeDI_service()
		        let filter: any FilterProtocol = AppFilter(service: service)
		        self.init(service: service, filter: filter)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature + fulfillers, app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesEnclosingFillToSeamReenteredInsideIt_whenFulfillerInstantiatesSeam() async throws {
		// C1.16b, H7 (3): `DefaultRouter`, which fills `Profile`'s `router`, instantiates `Flow` again. The call inside the
		// fill passes the fill by name, so every `Flow` calls it with its own scope, as inline builds a fresh tree for each.
		let feature = [
			"public protocol Router {}",
			seamFixtureType(named: "Analytics", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Profile", declarations: ["@Instantiated let router: any Router", "@Received let analytics: Analytics"]),
			seamFixtureType(named: "Flow", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let profileBuilder: Instantiator<Profile>"]),
		]
		let fulfillers = [Self.fulfillingType(named: "DefaultRouter", fulfilling: "Router", declarations: ["@Instantiated let flowBuilder: Instantiator<Flow>", "@Received let analytics: Analytics"])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let flow: Flow"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_flow() -> Flow {
		            _ = Flow.__safeDI_Flow_8401CCF78D832F75.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_routerBuilder_Flow(_ scope: Flow.SafeDIScope_Router) -> any Router {
		                switch scope {
		                case let .profileBuilder(values, scope): return __safeDI_routerBuilder_Flow_Profile_Scope(scope, analytics: values.analytics)
		                }
		            }
		            func __safeDI_routerBuilder_Flow_Profile_Scope(_ scope: Flow.SafeDIScope_Router.Profile_Scope, analytics: Analytics) -> any Router {
		                switch scope {
		                case .router:
		                    func __safeDI_router() -> DefaultRouter {
		                        func __safeDI_flowBuilder() -> Flow {
		                            _ = Flow.__safeDI_Flow_8401CCF78D832F75.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                            return Flow(__safeDI_routerBuilder: __safeDI_routerBuilder_Flow)
		                        }
		                        let flowBuilder = Instantiator<Flow>(__safeDI_flowBuilder)
		                        return DefaultRouter(flowBuilder: flowBuilder, analytics: analytics)
		                    }
		                    let router: any Router = __safeDI_router()
		                    return router
		                }
		            }
		            return Flow(__safeDI_routerBuilder: __safeDI_routerBuilder_Flow)
		        }
		        let flow: Flow = __safeDI_flow()
		        self.init(flow: flow)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature + fulfillers, app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesEnclosingFillToSeamReenteredInsideIt_whenFillReadsCallerValueAndNoScopeBetweenDeclaresIt() async throws {
		// C1.16b's proviso, H7 (3): `DefaultRouter` receives `Root`'s `logger` and instantiates `Flow` again. No scope from
		// the fill to that call declares `logger`, so inline hands the re-entered `Flow`'s router the same `logger`, and the
		// fill, passed to that call, reads it.
		let (modules, visibleModules) = Self.reenteredFlowModules(app: [
			Self.fulfillingType(named: "DefaultRouter", fulfilling: "Router", declarations: ["@Received let logger: Logger", "@Instantiated let flowBuilder: Instantiator<Flow>"]),
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public convenience init() {
		        let logger = Logger()
		        func __safeDI_flow() -> Flow {
		            _ = Flow.__safeDI_Flow_C7439A5FFA022AA8.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_routerBuilder_Flow(_ scope: Flow.SafeDIScope_Router) -> any Router {
		                switch scope {
		                case let .profileBuilder(_, scope): return __safeDI_routerBuilder_Flow_Profile_Scope(scope)
		                }
		            }
		            func __safeDI_routerBuilder_Flow_Profile_Scope(_ scope: Flow.SafeDIScope_Router.Profile_Scope) -> any Router {
		                switch scope {
		                case .router:
		                    func __safeDI_router() -> DefaultRouter {
		                        func __safeDI_flowBuilder() -> Flow {
		                            _ = Flow.__safeDI_Flow_C7439A5FFA022AA8.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                            return Flow(__safeDI_routerBuilder: __safeDI_routerBuilder_Flow)
		                        }
		                        let flowBuilder = Instantiator<Flow>(__safeDI_flowBuilder)
		                        return DefaultRouter(logger: logger, flowBuilder: flowBuilder)
		                    }
		                    let router: any Router = __safeDI_router()
		                    return router
		                }
		            }
		            return Flow(__safeDI_routerBuilder: __safeDI_routerBuilder_Flow)
		        }
		        let flow: Flow = __safeDI_flow()
		        self.init(logger: logger, flow: flow)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: visibleModules)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarry_whenScopeInsideFillDeclaresLabelFillReadsFromCallerAboveCallThatReentersSeam() async {
		// C1.27, H7 (2)(2): inline, the `Flow` that `Middle` instantiates hands its router `Middle`'s `logger`; the fill,
		// passed to that call, is one function, which reads `Root`'s.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultRouter.swift"]):10:5: error: `DefaultRouter` receives `logger: Logger`, which `Middle` declares on the path from the builder for `Profile`’s `router: any Router` (case `Profile_Scope.router` of `routerBuilder`) to the call by which `Middle` instantiates `Flow` again (`flowBuilder`), but that call passes the builder on as module `App` fills it, which cannot hand it `Middle`’s values. Declare `@Received let logger: Logger` on `Flow`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `Router` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["App"]!["Middle.swift"]):10:5: note: `Middle` declares `logger: Logger` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.reenteredFlowModules(app: Self.reenteredFlowShadowingApp).modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsReenteredSeamFromItsOwnScope_whenSeamReceivesLabelScopeInsideFillDeclares() async throws {
		// C1.27's remedy: `Flow` receives `logger`, so the struct carries it, and `Middle`'s call of `Flow` passes its own
		// `logger`, which the fill reads from the re-entered `Flow`'s struct, as inline would.
		let (modules, visibleModules) = Self.reenteredFlowModules(flowDeclarations: ["@Received let logger: Logger"], app: Self.reenteredFlowShadowingApp)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles["Feature.swift"].map { ["Flow": Self.seamExtension(in: $0, named: "Flow")] }, ["Flow": """
		extension Flow {
		    @frozen public enum SafeDIScope_Router {
		        case profileBuilder(profileBuilder_Values, SafeDIScope_Router.Profile_Scope)

		        public struct profileBuilder_Values {
		            public let logger: Logger
		        }

		        @frozen public enum Profile_Scope {
		            case router(router_Values)

		            public struct router_Values {}
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_logger logger: Logger, __safeDI_routerBuilder: @escaping (SafeDIScope_Router) -> any Router) {
		        let __safeDI_routerValues_profileBuilder = SafeDIScope_Router.profileBuilder_Values(logger: logger)
		        func __safeDI_profileBuilder() -> Profile {
		            let router: any Router = __safeDI_routerBuilder(.profileBuilder(__safeDI_routerValues_profileBuilder, .router(SafeDIScope_Router.Profile_Scope.router_Values())))
		            return Profile(router: router)
		        }
		        let profileBuilder = Instantiator<Profile>(__safeDI_profileBuilder)
		        self.init(logger: logger, profileBuilder: profileBuilder)
		    }
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public convenience init() {
		        let logger = Logger()
		        func __safeDI_flow() -> Flow {
		            _ = Flow.__safeDI_Flow_F8FECDA524F2B568.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_routerBuilder_Flow(_ scope: Flow.SafeDIScope_Router) -> any Router {
		                switch scope {
		                case let .profileBuilder(values, scope): return __safeDI_routerBuilder_Flow_Profile_Scope(scope, logger: values.logger)
		                }
		            }
		            func __safeDI_routerBuilder_Flow_Profile_Scope(_ scope: Flow.SafeDIScope_Router.Profile_Scope, logger: Logger) -> any Router {
		                switch scope {
		                case .router:
		                    func __safeDI_router() -> DefaultRouter {
		                        func __safeDI_middle() -> Middle {
		                            let logger = Logger()
		                            func __safeDI_flowBuilder() -> Flow {
		                                _ = Flow.__safeDI_Flow_F8FECDA524F2B568.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                                return Flow(__safeDI_logger: logger, __safeDI_routerBuilder: __safeDI_routerBuilder_Flow)
		                            }
		                            let flowBuilder = Instantiator<Flow>(__safeDI_flowBuilder)
		                            return Middle(logger: logger, flowBuilder: flowBuilder)
		                        }
		                        let middle: Middle = __safeDI_middle()
		                        return DefaultRouter(logger: logger, middle: middle)
		                    }
		                    let router: any Router = __safeDI_router()
		                    return router
		                }
		            }
		            return Flow(__safeDI_logger: logger, __safeDI_routerBuilder: __safeDI_routerBuilder_Flow)
		        }
		        let flow: Flow = __safeDI_flow()
		        self.init(logger: logger, flow: flow)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: visibleModules)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsDeclarationBoundOnPathToReenteringCall_whenCallInsideOneFillPassesSiblingFillBeneathRedeclaredLabel() async {
		// C1.26b: `Flow` has two holes, so `Root`'s call declares two fills, and `Middle`'s call of `Flow`, inside the
		// router's fill, passes both. Inline, the re-entered `Flow`'s tracker reads `Middle`'s `logger`; the tracker's fill,
		// one function, reads `Root`'s.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultTracker.swift"]):9:5: error: `DefaultTracker` receives `logger: Logger`, which `Middle` declares on the path from the builder for `Profile`’s `router: any Router` (case `Profile_Scope.router` of `routerBuilder`) to the call by which `Middle` instantiates `Flow` again (`flowBuilder`), but that call passes the builder on as module `App` fills it, which cannot hand it `Middle`’s values. Declare `@Received let logger: Logger` on `Flow`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `Tracker` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["App"]!["Middle.swift"]):10:5: note: `Middle` declares `logger: Logger` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						"public protocol Router {}\npublic protocol Tracker {}",
						seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
						seamFixtureType(named: "Profile", declarations: ["@Instantiated let router: any Router"]),
						seamFixtureType(named: "Settings", declarations: ["@Instantiated let tracker: any Tracker"]),
						seamFixtureType(named: "Flow", isSeam: true, declarations: ["@Instantiated let profileBuilder: Instantiator<Profile>", "@Instantiated let settings: Settings"]),
					],
					app: [
						Self.fulfillingType(named: "DefaultRouter", fulfilling: "Router", declarations: ["@Instantiated let middle: Middle"]),
						seamFixtureType(named: "Middle", declarations: ["@Instantiated let logger: Logger", "@Instantiated let flowBuilder: Instantiator<Flow>"]),
						Self.fulfillingType(named: "DefaultTracker", fulfilling: "Tracker", declarations: ["@Received let logger: Logger"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let logger: Logger", "@Instantiated let flow: Flow"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_closesCycleOnFillsOwnBuilderFunction_whenFulfillerInstantiatesHolesOwnProperty() async throws {
		// C1.19, H7 (3)(a): `LoopingUserService` instantiates the hole's own property, so the repeat closes on the builder
		// function the fill declares for it, as inline closes on the one `A`'s builder declares.
		let feature = [
			"""
			public protocol UserService {}

			public struct AnyUserService: UserService {
			    public init(_ base: any UserService) {
			        self.base = base
			    }

			    let base: any UserService
			}
			""",
			seamFixtureType(named: "Analytics", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Cache", isFinalClass: true, declarations: []),
			seamFixtureType(named: "A", declarations: ["@Received let analytics: Analytics", "@Instantiated let cache: Cache", #"@Instantiated(fulfilledByType: "LoopingUserService", erasedToConcreteExistential: true) let userServiceBuilder: ErasedInstantiator<(), AnyUserService>"#]),
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let aBuilder: Instantiator<A>"]),
		]
		let fulfillers = [seamFixtureType(named: "LoopingUserService", declarations: ["@Received let cache: Cache", #"@Instantiated(fulfilledByType: "LoopingUserService", erasedToConcreteExistential: true) let userServiceBuilder: ErasedInstantiator<(), AnyUserService>"#], conformances: ", UserService")]
		let modules = Self.modules(feature: feature, app: fulfillers + [Self.canonicalRoot])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_66143C2D33DCF1AF.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_loopingUserServiceBuilder_Service(_ scope: Service.SafeDIScope_LoopingUserService) -> AnyUserService {
		                switch scope {
		                case let .aBuilder(_, scope): return __safeDI_loopingUserServiceBuilder_Service_A_Scope(scope)
		                }
		            }
		            func __safeDI_loopingUserServiceBuilder_Service_A_Scope(_ scope: Service.SafeDIScope_LoopingUserService.A_Scope) -> AnyUserService {
		                switch scope {
		                case let .userServiceBuilder(scope):
		                    let cache = scope.cache
		                    func __safeDI_userServiceBuilder() -> LoopingUserService {
		                        let userServiceBuilder = ErasedInstantiator<(), AnyUserService> {
		                            AnyUserService(__safeDI_userServiceBuilder())
		                        }
		                        return LoopingUserService(cache: cache, userServiceBuilder: userServiceBuilder)
		                    }
		                    return AnyUserService(__safeDI_userServiceBuilder())
		                }
		            }
		            return Service(__safeDI_loopingUserServiceBuilder: __safeDI_loopingUserServiceBuilder_Service)
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service)
		    }
		}
		"""]))
		// The comparator does not call an erased instantiator, so the probe calls the fill's twice down.
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature + fulfillers, app: [Self.canonicalRoot]), probes: [
			DifferentialValueProbe("Root()"),
			DifferentialValueProbe("Root().service.aBuilder.instantiate().userServiceBuilder.instantiate()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresFillSendable_whenSeamReenteredInsideFillIsCalledInSendableBuilderFunction() async throws {
		// C1.22: the call of `Flow` inside the fill sits in `flowBuilder`'s `@Sendable` builder function, which captures the
		// fill it passes, so the fill is a `@Sendable` local function.
		let feature = [
			"public protocol Router: Sendable {}",
			seamFixtureType(named: "Analytics", declarations: [], conformances: ", Sendable"),
			seamFixtureType(named: "Profile", declarations: ["@Instantiated let router: any Router", "@Instantiated let analytics: Analytics"], conformances: ", Sendable"),
			seamFixtureType(named: "Flow", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let profileBuilder: SendableInstantiator<Profile>"], conformances: ", Sendable"),
		]
		let fulfillers = [Self.fulfillingType(named: "DefaultRouter", fulfilling: "Router", declarations: ["@Instantiated let flowBuilder: SendableInstantiator<Flow>", "@Received let analytics: Analytics"])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let flow: Flow"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_flow() -> Flow {
		            _ = Flow.__safeDI_Flow_15611856F0DB86CA.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @Sendable func __safeDI_routerSendableBuilder_Flow(_ scope: Flow.SafeDISendableScope_Router) -> any Router {
		                switch scope {
		                case let .profileBuilder(scope): return __safeDI_routerBuilder_Flow_Profile_Scope(scope)
		                }
		            }
		            @Sendable func __safeDI_routerBuilder_Flow_Profile_Scope(_ scope: Flow.SafeDIScope_Router.Profile_Scope) -> any Router {
		                switch scope {
		                case let .router(scope):
		                    let analytics = scope.analytics
		                    func __safeDI_router() -> DefaultRouter {
		                        @Sendable func __safeDI_flowBuilder() -> Flow {
		                            _ = Flow.__safeDI_Flow_15611856F0DB86CA.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                            return Flow(__safeDI_routerSendableBuilder: __safeDI_routerSendableBuilder_Flow)
		                        }
		                        let flowBuilder = SendableInstantiator<Flow>(__safeDI_flowBuilder)
		                        return DefaultRouter(flowBuilder: flowBuilder, analytics: analytics)
		                    }
		                    let router: any Router = __safeDI_router()
		                    return router
		                }
		            }
		            return Flow(__safeDI_routerSendableBuilder: __safeDI_routerSendableBuilder_Flow)
		        }
		        let flow: Flow = __safeDI_flow()
		        self.init(flow: flow)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature + fulfillers, app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresFillSendable_whenCallInsideItPassesItToSeamTakingItSendable() async throws {
		// `Root` calls `Inner`, whose fill builds `DefaultUserService`, which builds `Shell`; `Shell` builds `Inner` through a
		// `SendableInstantiator`, so it takes the builder it passes up `@Sendable`, and the fill the call inside it passes
		// to `Shell` is `@Sendable`.
		let feature = [
			Self.userServiceProtocol,
			seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
			// `@unchecked`, as the fuzzer's mixed-wrapper graphs mark their types: `Shell` builds `Inner` in a `SendableInstantiator`.
			seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let profileBuilder: Instantiator<Profile>"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let innerBuilder: SendableInstantiator<Inner>"]),
		]
		let fulfillers = [Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Instantiated let shellBuilder: Instantiator<Shell>"])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let inner: Inner"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_0AE08C46F5886BD0.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @Sendable func __safeDI_userServiceBuilder_Inner(_ scope: Inner.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .profileBuilder(_, scope): return __safeDI_userServiceBuilder_Inner_Profile_Scope(scope)
		                }
		            }
		            @Sendable func __safeDI_userServiceBuilder_Inner_Profile_Scope(_ scope: Inner.SafeDIScope_UserService.Profile_Scope) -> any UserService {
		                switch scope {
		                case .userService:
		                    func __safeDI_userService() -> DefaultUserService {
		                        func __safeDI_shellBuilder() -> Shell {
		                            _ = Shell.__safeDI_Shell_C0B585A7276DE086.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                            @Sendable func __safeDI_userServiceSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_UserService) -> any UserService {
		                                switch scope {
		                                case let .innerBuilder(scope): return __safeDI_userServiceBuilder_Inner(scope)
		                                }
		                            }
		                            return Shell(__safeDI_userServiceSendableBuilder: __safeDI_userServiceSendableBuilder_Shell)
		                        }
		                        let shellBuilder = Instantiator<Shell>(__safeDI_shellBuilder)
		                        return DefaultUserService(shellBuilder: shellBuilder)
		                    }
		                    let userService: any UserService = __safeDI_userService()
		                    return userService
		                }
		            }
		            return Inner(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature + fulfillers, app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_closesCycleInFillWithConstant_whenFillsTreeClosesCycleAnInstantiatorDefers() async throws {
		// C1.21, H7 (4): `Root`'s inline walk closes the cycle on its own lazy `p1Builder`, and `Service`'s walk, from its root,
		// meets `c: C` again through the fill. The cycle `c -> p1Builder -> a -> c` has an instantiator along it, so the fill
		// `App` generates closes it with the constant `c`, which calls the fill's own function for `c`.
		let feature = [
			Self.userServiceProtocol,
			seamFixtureType(named: "C", declarations: ["@Instantiated let p1Builder: Instantiator<P1>"]),
			seamFixtureType(named: "P1", declarations: ["@Instantiated let a: A"]),
			seamFixtureType(named: "A", declarations: ["@Instantiated let c: C", "@Instantiated let service: Service"]),
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let userService: any UserService"]),
		]
		let fulfillers = [Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Instantiated let c: C"])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let p1Builder: Instantiator<P1>"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		for integration in [MultiModuleIntegration.moduleInfo, .swiftPackagePlugin] {
			let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: integration, filesToDelete: &filesToDelete)
			expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: integration, imports: ["Feature"], rootFiles: ["Root": """
			extension Root {
			    public init() {
			        func __safeDI_p1Builder() -> P1 {
			            func __safeDI_a() -> A {
			                func __safeDI_c() -> C {
			                    let p1Builder = Instantiator<P1>(__safeDI_p1Builder)
			                    return C(p1Builder: p1Builder)
			                }
			                let c: C = __safeDI_c()
			                func __safeDI_service() -> Service {
			                    _ = Service.__safeDI_Service_47FCCD49F0077492.self\(Self.pluginComment(integration, seam: "Service"))
			                    func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
			                        switch scope {
			                        case .userService:
			                            func __safeDI_userService() -> DefaultUserService {
			                                func __safeDI_c() -> C {
			                                    func __safeDI_p1Builder() -> P1 {
			                                        func __safeDI_a() -> A {
			                                            let c: C = __safeDI_c()
			                                            func __safeDI_service() -> Service {
			                                                _ = Service.__safeDI_Service_47FCCD49F0077492.self\(Self.pluginComment(integration, seam: "Service"))
			                                                return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
			                                            }
			                                            let service: Service = __safeDI_service()
			                                            return A(c: c, service: service)
			                                        }
			                                        let a: A = __safeDI_a()
			                                        return P1(a: a)
			                                    }
			                                    let p1Builder = Instantiator<P1>(__safeDI_p1Builder)
			                                    return C(p1Builder: p1Builder)
			                                }
			                                let c: C = __safeDI_c()
			                                return DefaultUserService(c: c)
			                            }
			                            let userService: any UserService = __safeDI_userService()
			                            return userService
			                        }
			                    }
			                    return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
			                }
			                let service: Service = __safeDI_service()
			                return A(c: c, service: service)
			            }
			            let a: A = __safeDI_a()
			            return P1(a: a)
			        }
			        let p1Builder = Instantiator<P1>(__safeDI_p1Builder)
			        self.init(p1Builder: p1Builder)
			    }
			}
			"""]))
			try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature + fulfillers, app: [root]))
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillClosesCycleInSeamTree_whenFillOfPassedUpBuilderRepeatsPropertyOfInnerSeamsPath() async {
		// C1.24: the fill of `Shell`'s passed-up builder is built with `Service`'s stack, on which `profileBuilder` is.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LoopingUserService.swift"]):10:5: error: SafeDI cannot fill the builder for `Profile`’s `userService: any UserService` (case `Profile_Scope.userService` of `userServiceBuilder`) in `Service`’s dependency tree: `LoopingUserService`, which fills it, instantiates `profileBuilder: Instantiator<Profile>`, which `Service`’s tree is building where it builds `userService` (Service -> profileBuilder -> Profile -> userService -> LoopingUserService -> profileBuilder). Code generated outside module `Feature` cannot refer to the function `Service`’s initializer builds `Profile` with, and building it again would hand it other values than `Service`’s tree holds. Instantiate the seam where `LoopingUserService` builds `Profile` (`@Instantiated let serviceBuilder: Instantiator<Service>`), so the cycle re-enters through the initializer SafeDI generates for `Service`; declare an @Instantiable type that fulfills `UserService` in module `Feature` or a module it lists among its SafeDI dependencies; or give `profileBuilder` on `LoopingUserService` another label, so the cycle closes at `userService` itself.
			\(fixtures["Feature"]!["Service.swift"]):7:5: note: `Service` instantiates `profileBuilder: Instantiator<Profile>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						Self.userServiceProtocol,
						seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let profileBuilder: Instantiator<Profile>"]),
					]),
					ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: ["import Feature\n\n" + seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let service: Service"])], dependencies: ["Feature"]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
						Self.fulfillingType(named: "LoopingUserService", fulfilling: "UserService", declarations: ["@Instantiated let profileBuilder: Instantiator<Profile>"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let shell: Shell"]),
					].map { "import Feature\nimport Mid\n\n" + $0 }, dependencies: ["Feature", "Mid"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarry_whenFillReadsSiblingThatReceivesCarrierOnlyIfAvailable() async {
		// C2.15, H4's second residual: `Theme` receives `profile` only if available, so `Home`'s `theme` follows `profile`,
		// and the struct carries the seam's received `theme` no more, which `Home`'s hides.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultUserService.swift"]):9:5: error: `DefaultUserService` receives `theme: Theme`, which `Home` builds after `profile`, since `Theme` receives `profile` only if available, so the scope SafeDI hands the builder for `Profile`’s `userService: any UserService` (case `Profile_Scope.userService` of `userServiceBuilder`) does not carry it. Receive `profile` on `Theme` some other way, or declare an @Instantiable type that fulfills `UserService` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Home.swift"]):9:5: note: `Home` declares `theme: Theme` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						Self.userServiceProtocol,
						seamFixtureType(named: "Theme", declarations: ["@Received(onlyIfAvailable: true) let profile: Profile?"]),
						seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
						seamFixtureType(named: "Home", declarations: ["@Instantiated let profile: Profile", "@Instantiated let theme: Theme"]),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Received let theme: Theme", "@Instantiated let home: Home"]),
					],
					app: [
						Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let theme: Theme"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let service: Service"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Passing a builder up

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilderUpThroughOuterSeam_whenOuterSeamsModuleCannotSeeFulfillingDeclarationEither() async throws {
		// C3.5, H8: `Shell`, in `Mid`, calls `Service` and sees no type that fulfills `UserService` either, so it takes the
		// builder, of `Service`'s struct, and passes it on; `App` fills `Shell`'s builder.
		let modules = Self.passUpModules(appFulfillers: [Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let analytics: Analytics"])])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Mid"]?.generatedFiles, Self.generatedFiles(module: "Mid", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Shell": """
		extension Shell {
		    @frozen public enum SafeDIScope_UserService {
		        case service(service_Values, Service.SafeDIScope_UserService)

		        public struct service_Values {
		            public let theme: Theme
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        let theme = Theme()
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_6E216DA2A3D4C4DA.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service(__safeDI_userServiceBuilder: { __safeDI_userServiceBuilder(.service(SafeDIScope_UserService.service_Values(theme: theme), $0)) })
		        }
		        let service: Service = __safeDI_service()
		        self.init(theme: theme, service: service)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_22FB35359A425A0C {}
		}
		"""]))
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature", "Mid"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_22FB35359A425A0C.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Shell(_ scope: Shell.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .service(_, scope): return __safeDI_userServiceBuilder_Service(scope)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .profile(values, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope, analytics: values.analytics)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope, analytics: Analytics) -> any UserService {
		                switch scope {
		                case .userService:
		                    let userService: any UserService = DefaultUserService(analytics: analytics)
		                    return userService
		                }
		            }
		            return Shell(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(shell: shell)
		    }
		}
		"""]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPassedUpBuilderWithCallersValue_whenFillReadsPassingUpSeamsOwnForwardedProperty() async throws {
		// H8: `Shell`, which passes `Service`'s builder up, forwards `name`, which its caller holds where it calls `Shell`,
		// so a fill's read of it is no hidden label: the fill reads the caller's `name`, as inline passes it through.
		let mid = [seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Forwarded let name: String", "@Instantiated let service: Service"])]
		let fulfillers = [Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let name: String"])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let shellBuilder: Instantiator<Shell>"])
		let modules = Self.threeModules(feature: Self.canonicalFeature, mid: mid, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature", "Mid"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_shellBuilder(name: String) -> Shell {
		            _ = Shell.__safeDI_Shell_AED08CA42EA1B785.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Shell(_ scope: Shell.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .service(_, scope): return __safeDI_userServiceBuilder_Service(scope)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .profile(_, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope) -> any UserService {
		                switch scope {
		                case .userService:
		                    let userService: any UserService = DefaultUserService(name: name)
		                    return userService
		                }
		            }
		            return Shell(__safeDI_name: name, __safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Shell)
		        }
		        let shellBuilder = Instantiator<Shell> {
		            __safeDI_shellBuilder(name: $0)
		        }
		        self.init(shellBuilder: shellBuilder)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(
			output,
			modules: modules,
			visibleModules: Self.threeModules(feature: Self.canonicalFeature + fulfillers, mid: mid, app: [root]),
			probes: [DifferentialValueProbe(#"Root().shellBuilder.instantiate("name")"#)],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarry_whenFillOfPassedUpBuilderReadsValueOuterSeamBinds() async {
		// C8.10: inline, `Shell`'s `theme` would be passed through `Service` to `DefaultUserService`; the struct cannot carry
		// `Shell`'s values, and `Shell`'s caller, which fills the builder, does not hold them.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultUserService.swift"]):10:5: error: `DefaultUserService` receives `theme: Theme`, which `Shell` builds where it calls `Service`, but `Shell` passes the builder for `Profile`’s `userService: any UserService` (case `Profile_Scope.userService` of `userServiceBuilder`) on from its own caller, which cannot hand it `Shell`’s values. Declare `@Received let theme: Theme` on `Service`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `UserService` in module `Mid` or a module it lists among its SafeDI dependencies, so `Shell` fills the builder itself.
			\(fixtures["Mid"]!["Shell.swift"]):10:5: note: `Shell` declares `theme: Theme` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.passUpModules(appFulfillers: [Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let theme: Theme"])]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderForHoleInsideItsOwnFill_whenFulfillerItFillsWithInstantiatesTypeItsModuleCannotSee() async throws {
		// C3.13: `Shell`, in `Mid`, fills `Service`'s builder with `DefaultUserService`, whose `logger: any Logger` no
		// declaration `Mid` sees fulfills: a site of `Shell`'s own tree, whose struct carries `Shell`'s `theme` and the
		// field of `Service`'s struct the fill binds; `App` fills `Shell`'s builder. `Shell`'s call of `Service` carries a
		// site, so `theme` starts before it.
		let feature = [
			"public protocol UserService {}\npublic protocol Logger {}",
			seamFixtureType(named: "Analytics", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Theme", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let profile: Profile"]),
		]
		let mid = [
			Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let analytics: Analytics", "@Instantiated let logger: any Logger"]),
			seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let service: Service", "@Instantiated let theme: Theme"]),
		]
		let fulfillers = [Self.fulfillingType(named: "DefaultLogger", fulfilling: "Logger", declarations: ["@Received let analytics: Analytics", "@Received let theme: Theme"])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let shell: Shell"])
		func modules(feature: [String], mid: [String], app: [String]) -> [ModuleFixture] {
			[
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
				ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: mid.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\nimport Mid\n\n" + $0 }, dependencies: ["Feature", "Mid"]),
			]
		}
		let holeModules = modules(feature: feature, mid: mid, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: holeModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Mid"]?.generatedFiles, Self.generatedFiles(module: "Mid", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Shell": """
		extension Shell {
		    @frozen public enum SafeDIScope_Logger {
		        case service_userServiceBuilder(service_userServiceBuilder_Values, Service.SafeDIScope_UserService, SafeDIScope_Logger.DefaultUserService_Scope)

		        public struct service_userServiceBuilder_Values {
		            public let theme: Theme
		        }

		        @frozen public enum DefaultUserService_Scope {
		            case logger(logger_Values)

		            public struct logger_Values {}
		        }
		    }

		    // SafeDI counts `Logger` as `public`: no module it reads declares it narrower. If `Logger` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_loggerBuilder: @escaping (SafeDIScope_Logger) -> any Logger) {
		        let theme = Theme()
		        let __safeDI_loggerValues_service_userServiceBuilder = SafeDIScope_Logger.service_userServiceBuilder_Values(theme: theme)
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_6E216DA2A3D4C4DA.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Service(_ __safeDI_service_userServiceBuilder: Service.SafeDIScope_UserService) -> any UserService {
		                switch __safeDI_service_userServiceBuilder {
		                case let .profile(values, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope, __safeDI_service_userServiceBuilder: __safeDI_service_userServiceBuilder, analytics: values.analytics)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope, __safeDI_service_userServiceBuilder: Service.SafeDIScope_UserService, analytics: Analytics) -> any UserService {
		                switch scope {
		                case .userService:
		                    func __safeDI_userService() -> DefaultUserService {
		                        let logger: any Logger = __safeDI_loggerBuilder(.service_userServiceBuilder(__safeDI_loggerValues_service_userServiceBuilder, __safeDI_service_userServiceBuilder, .logger(SafeDIScope_Logger.DefaultUserService_Scope.logger_Values())))
		                        return DefaultUserService(analytics: analytics, logger: logger)
		                    }
		                    let userService: any UserService = __safeDI_userService()
		                    return userService
		                }
		            }
		            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service, theme: theme)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_DAF792BC2BCEC191 {}
		}
		"""]))
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature", "Mid"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_DAF792BC2BCEC191.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_loggerBuilder_Shell(_ scope: Shell.SafeDIScope_Logger) -> any Logger {
		                switch scope {
		                case let .service_userServiceBuilder(values, innerScope, scope): return __safeDI_loggerBuilder_Shell_DefaultUserService_Scope(scope, analytics: __safeDI_analytics_Service_SafeDIScope_UserService(innerScope), theme: values.theme)
		                }
		            }
		            func __safeDI_loggerBuilder_Shell_DefaultUserService_Scope(_ scope: Shell.SafeDIScope_Logger.DefaultUserService_Scope, analytics: Analytics, theme: Theme) -> any Logger {
		                switch scope {
		                case .logger:
		                    let logger: any Logger = DefaultLogger(analytics: analytics, theme: theme)
		                    return logger
		                }
		            }
		            func __safeDI_analytics_Service_SafeDIScope_UserService(_ scope: Service.SafeDIScope_UserService) -> Analytics {
		                switch scope {
		                case let .profile(values, _): return values.analytics
		                }
		            }
		            return Shell(__safeDI_loggerBuilder: __safeDI_loggerBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(shell: shell)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: holeModules, visibleModules: modules(feature: feature + mid + fulfillers, mid: [], app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesFillOfPassedUpBuilderToInnerSeamReenteredInsideIt_whenFulfillerRepeatsOuterSeamsPath() async throws {
		// C1.23, H7 (3): `App` fills `Shell`'s builder, passed up from `Service`, with `DefaultUserService`, whose `X`
		// instantiates `Service` again. A fill is keyed by the site it fills, so that call passes the fill it sits in.
		let (modules, visibleModules) = Self.reenteredServiceModules(
			app: [Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Instantiated let xBuilder: Instantiator<X>"])],
			rootDeclarations: ["@Instantiated let shell: Shell"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Mid"]?.generatedFiles, Self.generatedFiles(module: "Mid", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Shell": """
		extension Shell {
		    @frozen public enum SafeDIScope_UserService {
		        case xBuilder(xBuilder_Values, SafeDIScope_UserService.X_Scope)

		        public struct xBuilder_Values {
		            public let analytics: Analytics
		        }

		        @frozen public enum X_Scope {
		            case service(service_Values, Service.SafeDIScope_UserService)

		            public struct service_Values {}
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        let analytics = Analytics()
		        let __safeDI_userServiceValues_xBuilder = SafeDIScope_UserService.xBuilder_Values(analytics: analytics)
		        func __safeDI_xBuilder() -> X {
		            func __safeDI_service() -> Service {
		                _ = Service.__safeDI_Service_55F0113D32820144.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                return Service(__safeDI_userServiceBuilder: { __safeDI_userServiceBuilder(.xBuilder(__safeDI_userServiceValues_xBuilder, .service(SafeDIScope_UserService.X_Scope.service_Values(), $0))) })
		            }
		            let service: Service = __safeDI_service()
		            return X(analytics: analytics, service: service)
		        }
		        let xBuilder = Instantiator<X>(__safeDI_xBuilder)
		        self.init(analytics: analytics, xBuilder: xBuilder)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_E007841AF02B12FA {}
		}
		"""]))
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature", "Mid"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_E007841AF02B12FA.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Shell(_ scope: Shell.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .xBuilder(_, scope): return __safeDI_userServiceBuilder_Shell_X_Scope(scope)
		                }
		            }
		            func __safeDI_userServiceBuilder_Shell_X_Scope(_ scope: Shell.SafeDIScope_UserService.X_Scope) -> any UserService {
		                switch scope {
		                case let .service(_, scope): return __safeDI_userServiceBuilder_Service(scope)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .profileBuilder(values, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope, analytics: values.analytics)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope, analytics: Analytics) -> any UserService {
		                switch scope {
		                case .userService:
		                    func __safeDI_userService() -> DefaultUserService {
		                        func __safeDI_xBuilder() -> X {
		                            func __safeDI_service() -> Service {
		                                _ = Service.__safeDI_Service_55F0113D32820144.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                                return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
		                            }
		                            let service: Service = __safeDI_service()
		                            return X(analytics: analytics, service: service)
		                        }
		                        let xBuilder = Instantiator<X>(__safeDI_xBuilder)
		                        return DefaultUserService(xBuilder: xBuilder)
		                    }
		                    let userService: any UserService = __safeDI_userService()
		                    return userService
		                }
		            }
		            return Shell(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(shell: shell)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: visibleModules)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarry_whenScopeInsideFillOfPassedUpBuilderDeclaresLabelFillReadsFromCallerAboveCallThatReentersInnerSeam() async {
		// C1.27b, H7 (2)(2): inline, the `Service` that `X` builds beneath `Middle` hands its `DefaultUserService` `Middle`'s
		// `logger`; the one fill `App` generates reads `Root`'s, which a nested copy of the fill would read again a level down.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultUserService.swift"]):11:5: error: `DefaultUserService` receives `logger: Logger`, which `Middle` declares on the path from the builder for `Profile`’s `userService: any UserService` (case `Profile_Scope.userService` of `userServiceBuilder`) to the call by which `X` instantiates `Service` again (`service`), but that call passes the builder on as module `App` fills it, which cannot hand it `Middle`’s values. Declare `@Received let logger: Logger` on `Service`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `UserService` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["App"]!["Middle.swift"]):11:5: note: `Middle` declares `logger: Logger` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.reenteredServiceModules(
					app: [
						Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let logger: Logger", "@Instantiated let middle: Middle"]),
						seamFixtureType(named: "Middle", isFinalClass: true, declarations: ["@Instantiated let logger: Logger", "@Instantiated let xBuilder: Instantiator<X>"]),
					],
					rootDeclarations: ["@Instantiated let logger: Logger", "@Instantiated let shell: Shell"],
				).modules,
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsDeclarationBoundAfterSite_whenFillPassedToSeamThatPassesSiteUpReadsLabelThatSeamBinds() async {
		// H8 for the fill a call passes on: `Root` calls `Inner`, whose fill `DefaultUserService` reads `Root`'s `logger` and
		// builds `Shell`, whose call of `Inner` is passed that fill. Inline, the `Inner` that `Shell` builds hands its
		// `DefaultUserService` `Shell`'s `logger`, which `Shell`'s copy of the builder does not carry.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultUserService.swift"]):10:5: error: `DefaultUserService` receives `logger: Logger`, which `Shell` builds where it calls `Inner`, but `Shell` passes the builder for `Profile`’s `userService: any UserService` (case `Profile_Scope.userService` of `userServiceBuilder`) on from its own caller, which cannot hand it `Shell`’s values. Declare `@Received let logger: Logger` on `Inner`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `UserService` in module `Feature` or a module it lists among its SafeDI dependencies, so `Shell` fills the builder itself.
			\(fixtures["Feature"]!["Shell.swift"]):8:5: note: `Shell` declares `logger: Logger` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						Self.userServiceProtocol,
						seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
						seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
						seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let profileBuilder: Instantiator<Profile>"]),
						seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let logger: Logger", "@Instantiated let innerBuilder: Instantiator<Inner>"]),
					],
					app: [
						Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let logger: Logger", "@Instantiated let shellBuilder: Instantiator<Shell>"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let logger: Logger", "@Instantiated let inner: Inner"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilderUpAsSendable_whenOuterSeamCallsInnerSeamInSendableBuilderFunction() async throws {
		// H8: `Shell` calls `Service` inside `serviceBuilder`'s `@Sendable` builder function, which captures the builder it
		// passes on, so `Shell` takes it `@Sendable`, and `App`'s fill is `@Sendable` too.
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol UserService: Sendable {}",
				seamFixtureType(named: "Analytics", declarations: [], conformances: ", Sendable"),
				seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService", "@Received let analytics: Analytics"], conformances: ", Sendable"),
				seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let profile: Profile"], conformances: ", Sendable"),
			]),
			ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: ["import Feature\n\n" + seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let serviceBuilder: SendableInstantiator<Service>"])], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let analytics: Analytics"]),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let shell: Shell"]),
			].map { "import Feature\nimport Mid\n\n" + $0 }, dependencies: ["Feature", "Mid"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Mid"]?.generatedFiles, ["Mid.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Shell {
		    @frozen public enum SafeDISendableScope_UserService {
		        case serviceBuilder(Service.SafeDIScope_UserService)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceSendableBuilder: @escaping @Sendable (SafeDISendableScope_UserService) -> any UserService) {
		        @Sendable func __safeDI_serviceBuilder() -> Service {
		            _ = Service.__safeDI_Service_6E216DA2A3D4C4DA.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Service(__safeDI_userServiceBuilder: { __safeDI_userServiceSendableBuilder(.serviceBuilder($0)) })
		        }
		        let serviceBuilder = SendableInstantiator<Service>(__safeDI_serviceBuilder)
		        self.init(serviceBuilder: serviceBuilder)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_AA4E2B307BF71A6E {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Mid)
		import Mid
		#endif

		extension Root {
		    public init() {
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_AA4E2B307BF71A6E.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @Sendable func __safeDI_userServiceSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_UserService) -> any UserService {
		                switch scope {
		                case let .serviceBuilder(scope): return __safeDI_userServiceBuilder_Service(scope)
		                }
		            }
		            @Sendable func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .profile(values, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope, analytics: values.analytics)
		                }
		            }
		            @Sendable func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope, analytics: Analytics) -> any UserService {
		                switch scope {
		                case .userService:
		                    let userService: any UserService = DefaultUserService(analytics: analytics)
		                    return userService
		                }
		            }
		            return Shell(__safeDI_userServiceSendableBuilder: __safeDI_userServiceSendableBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(shell: shell)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesEveryFillOfEnclosingCall_whenTwoSiteHolesFulfillerReentersSeam() async throws {
		// C1.26: `Avatar`'s `routerBuilder` has two sites; `DefaultRouter` instantiates `Flow` again. The two fills are
		// declared consecutively, and the call inside each passes both, so every `Flow` builds both sites with its scopes.
		let feature = [
			"""
			public protocol Router {}

			public struct AnyRouter: Router {
			    public init(_ base: any Router) {
			        self.base = base
			    }

			    let base: any Router
			}
			""",
			seamFixtureType(named: "Analytics", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Avatar", declarations: [#"@Instantiated(fulfilledByType: "DefaultRouter", erasedToConcreteExistential: true) let routerBuilder: ErasedInstantiator<(), AnyRouter>"#, "@Received let analytics: Analytics"]),
			seamFixtureType(named: "Home", declarations: ["@Instantiated let avatar: Avatar"]),
			seamFixtureType(named: "Settings", declarations: ["@Instantiated let settingsAvatar: Avatar"]),
			seamFixtureType(named: "Flow", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let homeBuilder: Instantiator<Home>", "@Instantiated let settingsBuilder: Instantiator<Settings>"]),
		]
		let fulfillers = [seamFixtureType(named: "DefaultRouter", declarations: ["@Instantiated let flowBuilder: Instantiator<Flow>", "@Received let analytics: Analytics"], conformances: ", Router")]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let flow: Flow"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_flow() -> Flow {
		            _ = Flow.__safeDI_Flow_72C9288FC3C68DE5.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_defaultRouterBuilder_Flow(_ scope: Flow.SafeDIScope_DefaultRouter) -> AnyRouter {
		                switch scope {
		                case let .homeBuilder(values, scope): return __safeDI_defaultRouterBuilder_Flow_Home_Scope(scope, analytics: values.analytics)
		                case let .settingsBuilder(values, scope): return __safeDI_defaultRouterBuilder_Flow_Settings_Scope(scope, analytics: values.analytics)
		                }
		            }
		            func __safeDI_defaultRouterBuilder_Flow_Home_Scope(_ scope: Flow.SafeDIScope_DefaultRouter.Home_Scope, analytics: Analytics) -> AnyRouter {
		                switch scope {
		                case let .avatar(_, scope): return __safeDI_defaultRouterBuilder_Flow_Avatar_Scope(scope, analytics: analytics)
		                }
		            }
		            func __safeDI_defaultRouterBuilder_Flow_Avatar_Scope(_ scope: Flow.SafeDIScope_DefaultRouter.Avatar_Scope, analytics: Analytics) -> AnyRouter {
		                switch scope {
		                case .routerBuilder:
		                    func __safeDI_routerBuilder() -> DefaultRouter {
		                        func __safeDI_flowBuilder() -> Flow {
		                            _ = Flow.__safeDI_Flow_72C9288FC3C68DE5.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                            return Flow(__safeDI_defaultRouterBuilder: __safeDI_defaultRouterBuilder_Flow)
		                        }
		                        let flowBuilder = Instantiator<Flow>(__safeDI_flowBuilder)
		                        return DefaultRouter(flowBuilder: flowBuilder, analytics: analytics)
		                    }
		                    return AnyRouter(__safeDI_routerBuilder())
		                }
		            }
		            func __safeDI_defaultRouterBuilder_Flow_Settings_Scope(_ scope: Flow.SafeDIScope_DefaultRouter.Settings_Scope, analytics: Analytics) -> AnyRouter {
		                switch scope {
		                case let .settingsAvatar(_, scope): return __safeDI_defaultRouterBuilder_Flow_Avatar_Scope(scope, analytics: analytics)
		                }
		            }
		            return Flow(__safeDI_defaultRouterBuilder: __safeDI_defaultRouterBuilder_Flow)
		        }
		        let flow: Flow = __safeDI_flow()
		        self.init(flow: flow)
		    }
		}
		"""])
		// The comparator does not call an erased instantiator, so the probes call the router at each site, whose
		// `flowBuilder` the comparator calls, building a second `Flow` with its own scopes.
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature + fulfillers, app: [root]), probes: [
			DifferentialValueProbe("Root()"),
			DifferentialValueProbe("Root().flow.homeBuilder.instantiate().avatar.routerBuilder.instantiate()"),
			DifferentialValueProbe("Root().flow.settingsBuilder.instantiate().settingsAvatar.routerBuilder.instantiate()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsValuesInlineBuilds_whenFillReadsWrapperFieldsInstanceOrRepeatsPropertyOfFillersPath() async throws {
		// Two cells in one fixture, to compile the value comparator's two paths once. C2.6: the struct carries the wrapper
		// `session`, and the fill passes its instance. C1.20: `DefaultUserService`
		// instantiates `xBuilder`, which `Root` also instantiates; the fill's stack is `Service`'s, so it builds `xBuilder`
		// afresh, and `X`'s call of `Service` passes the fill. The values equal the build with the fulfiller in `Feature`.
		let feature = [
			Self.userServiceProtocol,
			seamFixtureType(named: "Analytics", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
			seamFixtureType(named: "X", declarations: ["@Received let analytics: Analytics", "@Instantiated let service: Service"]),
			seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let session: LazilyInstantiated<Session>", "@Instantiated let profileBuilder: Instantiator<Profile>"]),
		]
		let fulfillers = [Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let session: Session", "@Instantiated let xBuilder: Instantiator<X>"])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let xBuilder: Instantiator<X>"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        let analytics = Analytics()
		        func __safeDI_xBuilder() -> X {
		            func __safeDI_service() -> Service {
		                _ = Service.__safeDI_Service_EE2FDE431C17101C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                    switch scope {
		                    case let .profileBuilder(values, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope, analytics: values.analytics, session: values.session)
		                    }
		                }
		                func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope, analytics: Analytics, session: LazilyInstantiated<Session>) -> any UserService {
		                    switch scope {
		                    case .userService:
		                        func __safeDI_userService() -> DefaultUserService {
		                            func __safeDI_xBuilder() -> X {
		                                func __safeDI_service() -> Service {
		                                    _ = Service.__safeDI_Service_EE2FDE431C17101C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                                    return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
		                                }
		                                let service: Service = __safeDI_service()
		                                return X(analytics: analytics, service: service)
		                            }
		                            let xBuilder = Instantiator<X>(__safeDI_xBuilder)
		                            return DefaultUserService(session: session.instance, xBuilder: xBuilder)
		                        }
		                        let userService: any UserService = __safeDI_userService()
		                        return userService
		                    }
		                }
		                return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
		            }
		            let service: Service = __safeDI_service()
		            return X(analytics: analytics, service: service)
		        }
		        let xBuilder = Instantiator<X>(__safeDI_xBuilder)
		        self.init(analytics: analytics, xBuilder: xBuilder)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature + fulfillers, app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesNearestDeclarationAndKeepsSoftReceivesAvailability_whenSiblingsOfCarriersAreDeclaredAfterThem() async throws {
		// Two cells in one fixture, to compile the value comparator's two paths once. C2.14: `Home`'s `theme`, declared
		// after the carrier `avatar`, reaches no carrier, so it starts first and is the
		// field, hiding the seam's received `theme`, as inline hands the fulfiller `Home`'s. C2.18: at `Card`'s level,
		// `badge` receives the hole only if available and `header` requires `badge`: no edge changes, so `badge` still
		// follows the hole and gets it.
		let feature = [
			Self.userServiceProtocol,
			seamFixtureType(named: "Theme", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Avatar", declarations: ["@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "Home", declarations: ["@Instantiated let avatar: Avatar", "@Instantiated let theme: Theme"]),
			seamFixtureType(named: "Badge", declarations: ["@Received(onlyIfAvailable: true) let userService: (any UserService)?"]),
			seamFixtureType(named: "Header", declarations: ["@Received let badge: Badge"]),
			seamFixtureType(named: "Card", declarations: ["@Instantiated let header: Header", "@Instantiated let badge: Badge", "@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Received let theme: Theme", "@Instantiated let home: Home", "@Instantiated let card: Card"]),
		]
		let fulfillers = [Self.fulfillingType(named: "ThemedUserService", fulfilling: "UserService", declarations: ["@Received(onlyIfAvailable: true) let theme: Theme?"])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let service: Service"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Service {
		    @frozen public enum SafeDIScope_UserService {
		        case home(home_Values, SafeDIScope_UserService.Home_Scope)
		        case card(card_Values, SafeDIScope_UserService.Card_Scope)

		        public struct home_Values {
		            public let theme: Theme
		        }

		        public struct card_Values {
		            public let theme: Theme
		            public let home: Home
		        }

		        @frozen public enum Home_Scope {
		            case avatar(avatar_Values, SafeDIScope_UserService.Avatar_Scope)

		            public struct avatar_Values {
		                public let theme: Theme
		            }
		        }

		        @frozen public enum Card_Scope {
		            case userService(userService_Values)

		            public struct userService_Values {}
		        }

		        @frozen public enum Avatar_Scope {
		            case userService(userService_Values)

		            public struct userService_Values {}
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_theme theme: Theme, __safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        let __safeDI_userServiceValues_home = SafeDIScope_UserService.home_Values(theme: theme)
		        func __safeDI_home() -> Home {
		            let theme = Theme()
		            let __safeDI_userServiceValues_avatar = SafeDIScope_UserService.Home_Scope.avatar_Values(theme: theme)
		            func __safeDI_avatar() -> Avatar {
		                let userService: any UserService = __safeDI_userServiceBuilder(.home(__safeDI_userServiceValues_home, .avatar(__safeDI_userServiceValues_avatar, .userService(SafeDIScope_UserService.Avatar_Scope.userService_Values()))))
		                return Avatar(userService: userService)
		            }
		            let avatar: Avatar = __safeDI_avatar()
		            return Home(avatar: avatar, theme: theme)
		        }
		        let home: Home = __safeDI_home()
		        let __safeDI_userServiceValues_card = SafeDIScope_UserService.card_Values(theme: theme, home: home)
		        func __safeDI_card() -> Card {
		            let userService: any UserService = __safeDI_userServiceBuilder(.card(__safeDI_userServiceValues_card, .userService(SafeDIScope_UserService.Card_Scope.userService_Values())))
		            let badge = Badge(userService: userService)
		            let header = Header(badge: badge)
		            return Card(header: header, badge: badge, userService: userService)
		        }
		        let card: Card = __safeDI_card()
		        self.init(theme: theme, home: home, card: card)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_E602172AC7C676F4 {}
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature + fulfillers, app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesEveryFieldOfInnerStructAtSiteInsideSeamsOwnFill_whenFulfillerDoesNotReadIt() async throws {
		// G1, H7: a site inside the fill `Shell` generates for `Service` counts as reading every field of `Service`'s struct,
		// so `Shell`'s struct for `logger` carries `cache`, which `DefaultUserService` does not read, and `DefaultLogger`
		// gets `Profile`'s cache, as the build with every fulfiller in `Feature` hands it.
		let feature = [
			"public protocol UserService {}\npublic protocol Logger {}",
			seamFixtureType(named: "Analytics", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Cache", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Theme", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Profile", isFinalClass: true, declarations: ["@Instantiated let cache: Cache", "@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "Service", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let profile: Profile"]),
		]
		let mid = [
			Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let analytics: Analytics", "@Instantiated let logger: any Logger"]),
			seamFixtureType(named: "Shell", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let service: Service", "@Instantiated let theme: Theme"]),
		]
		let fulfillers = [Self.fulfillingType(named: "DefaultLogger", fulfilling: "Logger", declarations: ["@Received let cache: Cache"])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let shell: Shell"])
		let holeModules = Self.threeModules(feature: feature, mid: mid, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: holeModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Mid"]?.generatedFiles, ["Mid.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Shell {
		    @frozen public enum SafeDIScope_Logger {
		        case service_userServiceBuilder(service_userServiceBuilder_Values, Service.SafeDIScope_UserService, SafeDIScope_Logger.DefaultUserService_Scope)

		        public struct service_userServiceBuilder_Values {
		            public let theme: Theme
		        }

		        @frozen public enum DefaultUserService_Scope {
		            case logger(logger_Values)

		            public struct logger_Values {}
		        }
		    }

		    // SafeDI counts `Logger` as `public`: no module it reads declares it narrower. If `Logger` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_loggerBuilder: @escaping (SafeDIScope_Logger) -> any Logger) {
		        let theme = Theme()
		        let __safeDI_loggerValues_service_userServiceBuilder = SafeDIScope_Logger.service_userServiceBuilder_Values(theme: theme)
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_3EDB4CCD82126CB9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Service(_ __safeDI_service_userServiceBuilder: Service.SafeDIScope_UserService) -> any UserService {
		                switch __safeDI_service_userServiceBuilder {
		                case let .profile(values, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope, __safeDI_service_userServiceBuilder: __safeDI_service_userServiceBuilder, analytics: values.analytics)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope, __safeDI_service_userServiceBuilder: Service.SafeDIScope_UserService, analytics: Analytics) -> any UserService {
		                switch scope {
		                case .userService:
		                    func __safeDI_userService() -> DefaultUserService {
		                        let logger: any Logger = __safeDI_loggerBuilder(.service_userServiceBuilder(__safeDI_loggerValues_service_userServiceBuilder, __safeDI_service_userServiceBuilder, .logger(SafeDIScope_Logger.DefaultUserService_Scope.logger_Values())))
		                        return DefaultUserService(analytics: analytics, logger: logger)
		                    }
		                    let userService: any UserService = __safeDI_userService()
		                    return userService
		                }
		            }
		            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service, theme: theme)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_8D6565985412E4D4 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Mid)
		import Mid
		#endif

		extension Root {
		    public init() {
		        func __safeDI_shell() -> Shell {
		            _ = Shell.__safeDI_Shell_8D6565985412E4D4.self // If this line does not compile, compile the code SafeDI generates for module Mid into Mid: under Bazel, add Mid’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_loggerBuilder_Shell(_ scope: Shell.SafeDIScope_Logger) -> any Logger {
		                switch scope {
		                case let .service_userServiceBuilder(_, innerScope, scope): return __safeDI_loggerBuilder_Shell_DefaultUserService_Scope(scope, cache: __safeDI_cache_Service_SafeDIScope_UserService(innerScope))
		                }
		            }
		            func __safeDI_loggerBuilder_Shell_DefaultUserService_Scope(_ scope: Shell.SafeDIScope_Logger.DefaultUserService_Scope, cache: Cache) -> any Logger {
		                switch scope {
		                case .logger:
		                    let logger: any Logger = DefaultLogger(cache: cache)
		                    return logger
		                }
		            }
		            func __safeDI_cache_Service_SafeDIScope_UserService(_ scope: Service.SafeDIScope_UserService) -> Cache {
		                switch scope {
		                case let .profile(_, scope): return __safeDI_cache_Service_Profile_Scope(scope)
		                }
		            }
		            func __safeDI_cache_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope) -> Cache {
		                switch scope {
		                case let .userService(values): return values.cache
		                }
		            }
		            return Shell(__safeDI_loggerBuilder: __safeDI_loggerBuilder_Shell)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(shell: shell)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, modules: holeModules, visibleModules: Self.threeModules(feature: feature + mid + fulfillers, mid: [], app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesRebindingOfInstantiator_whenFillReceivesOnlyIfAvailableInstantiatorFillersPathIsBuilding() async throws {
		// G3, H7 (1): `DefaultUserService` receives `xBuilder` only if available, and the fill is inside the builder function
		// of `Root`'s `xBuilder`, which wraps itself again there, so the fill passes that wrapper, as the tree built inline
		// would.
		let feature = [
			Self.userServiceProtocol,
			seamFixtureType(named: "Analytics", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Profile", isFinalClass: true, declarations: ["@Instantiated let userService: any UserService", "@Received let analytics: Analytics"]),
			seamFixtureType(named: "Service", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let profile: Profile"]),
		]
		let app = [
			Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let analytics: Analytics", "@Received(onlyIfAvailable: true) let xBuilder: Instantiator<X>?"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: ["@Instantiated let service: Service"]),
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let xBuilder: Instantiator<X>"]),
		]
		let modules = Self.modules(feature: feature, app: app)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_xBuilder() -> X {
		            let xBuilder = Instantiator<X>(__safeDI_xBuilder)
		            func __safeDI_service() -> Service {
		                _ = Service.__safeDI_Service_6E216DA2A3D4C4DA.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                    switch scope {
		                    case let .profile(values, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope, analytics: values.analytics)
		                    }
		                }
		                func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope, analytics: Analytics) -> any UserService {
		                    switch scope {
		                    case .userService:
		                        let userService: any UserService = DefaultUserService(analytics: analytics, xBuilder: xBuilder)
		                        return userService
		                    }
		                }
		                return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
		            }
		            let service: Service = __safeDI_service()
		            return X(service: service)
		        }
		        let xBuilder = Instantiator<X>(__safeDI_xBuilder)
		        self.init(xBuilder: xBuilder)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature + app.dropLast(), app: [app[2]]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarry_whenFillOfPassedUpBuilderReadsValueBoundInsideCalledSeamsTree() async {
		// G2, H8: `Shell` passes up `Inner2`'s builder from inside its fill of `Service`'s; inline, `DefaultLogger`'s `cache`
		// would be `Profile`'s, bound inside `Service`'s tree on the path, which `Shell`'s caller does not hold.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultLogger.swift"]):10:5: error: `DefaultLogger` receives `cache: Cache`, which `Profile` builds on the path where `Shell` calls `Inner2`, but `Shell` passes the builder for `Inner2`’s `logger: any Logger` (case `logger` of `loggerBuilder`) on from its own caller, which cannot hand it that value. Declare `@Received let cache: Cache` on `Inner2`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `Logger` in module `Mid` or a module it lists among its SafeDI dependencies, so `Shell` fills the builder itself.
			\(fixtures["Feature"]!["Profile.swift"]):8:5: note: `Profile` declares `cache: Cache` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.threeModules(
					feature: [
						"public protocol UserService {}\npublic protocol Logger {}",
						seamFixtureType(named: "Analytics", isFinalClass: true, declarations: []),
						seamFixtureType(named: "Cache", isFinalClass: true, declarations: []),
						seamFixtureType(named: "Inner2", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let logger: any Logger"]),
						seamFixtureType(named: "Profile", isFinalClass: true, declarations: ["@Instantiated let cache: Cache", "@Instantiated let userService: any UserService"]),
						seamFixtureType(named: "Service", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let profile: Profile"]),
					],
					mid: [
						Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Instantiated let inner2: Inner2"]),
						seamFixtureType(named: "Shell", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let service: Service"]),
					],
					app: [
						Self.fulfillingType(named: "DefaultLogger", fulfilling: "Logger", declarations: ["@Received let cache: Cache"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let shell: Shell"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsHoleOfSeamCalledInsideFill_whenFulfillerInstantiatesAnotherSeamWithHole() async throws {
		// C8.12, H7: `DefaultUserService`, which fills `Service`'s builder, instantiates `Other`, a seam whose `logger` no
		// declaration `Feature` sees fulfills. The fill calls `Other`'s tier and fills its builder inside itself, and no
		// call inside either fill re-enters `Service`, so nothing is hidden from the outer fill's reads.
		let feature = [
			"public protocol UserService {}\npublic protocol Logger {}",
			seamFixtureType(named: "Analytics", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService", "@Received let analytics: Analytics"]),
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let profile: Profile"]),
			seamFixtureType(named: "Other", isSeam: true, declarations: ["@Instantiated let logger: any Logger"]),
		]
		let fulfillers = [
			Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let analytics: Analytics", "@Instantiated let other: Other"]),
			Self.fulfillingType(named: "DefaultLogger", fulfilling: "Logger", declarations: ["@Received let analytics: Analytics"]),
		]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_6E216DA2A3D4C4DA.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .profile(values, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope, analytics: values.analytics)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope, analytics: Analytics) -> any UserService {
		                switch scope {
		                case .userService:
		                    func __safeDI_userService() -> DefaultUserService {
		                        func __safeDI_other() -> Other {
		                            _ = Other.__safeDI_Other_5A82A9BAB16F52C1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                            func __safeDI_loggerBuilder_Other(_ scope: Other.SafeDIScope_Logger) -> any Logger {
		                                switch scope {
		                                case .logger:
		                                    let logger: any Logger = DefaultLogger(analytics: analytics)
		                                    return logger
		                                }
		                            }
		                            return Other(__safeDI_loggerBuilder: __safeDI_loggerBuilder_Other)
		                        }
		                        let other: Other = __safeDI_other()
		                        return DefaultUserService(analytics: analytics, other: other)
		                    }
		                    let userService: any UserService = __safeDI_userService()
		                    return userService
		                }
		            }
		            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature + fulfillers, app: [root]))
	}

	// MARK: A seam whose tree reaches the seam again

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesOwnBuilderToReenteringCall_whenSeamsOwnTreeReachesSeamThroughVisibleTypes() async throws {
		// C1.27 (G4), H8: `X`, which `Service`'s tree builds, instantiates `Service` again. A seam takes one builder per site
		// and never takes a site it already takes, so that call passes `Service`'s own builder, and `App` fills it once.
		let (modules, visibleModules) = Self.reenteringServiceModules(x: ["@Instantiated let serviceBuilder: Instantiator<Service>"])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Service {
		    @frozen public enum SafeDIScope_UserService {
		        indirect case xBuilder(xBuilder_Values, SafeDIScope_UserService.X_Scope)
		        case profile(profile_Values, SafeDIScope_UserService.Profile_Scope)

		        public struct xBuilder_Values {
		            public let analytics: Analytics
		        }

		        public struct profile_Values {
		            public let analytics: Analytics
		            public let xBuilder: Instantiator<X>
		        }

		        @frozen public enum X_Scope {
		            indirect case serviceBuilder(serviceBuilder_Values, Service.SafeDIScope_UserService)

		            public struct serviceBuilder_Values {}
		        }

		        @frozen public enum Profile_Scope {
		            case userService(userService_Values)

		            public struct userService_Values {}
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        let analytics = Analytics()
		        let __safeDI_userServiceValues_xBuilder = SafeDIScope_UserService.xBuilder_Values(analytics: analytics)
		        func __safeDI_xBuilder() -> X {
		            func __safeDI_serviceBuilder() -> Service {
		                _ = Service.__safeDI_Service_4BC95F5D2D6A5D87.self
		                return Service(__safeDI_userServiceBuilder: { __safeDI_userServiceBuilder(.xBuilder(__safeDI_userServiceValues_xBuilder, .serviceBuilder(SafeDIScope_UserService.X_Scope.serviceBuilder_Values(), $0))) })
		            }
		            let serviceBuilder = Instantiator<Service>(__safeDI_serviceBuilder)
		            return X(serviceBuilder: serviceBuilder)
		        }
		        let xBuilder = Instantiator<X>(__safeDI_xBuilder)
		        let __safeDI_userServiceValues_profile = SafeDIScope_UserService.profile_Values(analytics: analytics, xBuilder: xBuilder)
		        func __safeDI_profile() -> Profile {
		            let userService: any UserService = __safeDI_userServiceBuilder(.profile(__safeDI_userServiceValues_profile, .userService(SafeDIScope_UserService.Profile_Scope.userService_Values())))
		            return Profile(userService: userService, analytics: analytics)
		        }
		        let profile: Profile = __safeDI_profile()
		        self.init(analytics: analytics, xBuilder: xBuilder, profile: profile)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_4BC95F5D2D6A5D87 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.reenteringServiceAppFiles)
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: visibleModules)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarry_whenFillReadsLabelSeamsTreeBindsOnPathToReenteringCall() async {
		// C8.14, H8: inline, the `Service` that `X` instantiates hands its `DefaultUserService` `X`'s `logger`; the call passes
		// `Service`'s builder on unchanged, so the one fill `App` generates would read `Root`'s.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultUserService.swift"]):11:5: error: `DefaultUserService` receives `logger: Logger`, which `Service`’s tree builds where it instantiates `Service` again, but that call passes the builder `Service` takes for `Profile`’s `userService: any UserService` on unchanged, so the caller that fills it cannot hand it those values. Declare `@Received let logger: Logger` on `Service`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `UserService` in module `Feature` or a module it lists among its SafeDI dependencies, so `Service` fills the builder itself.
			\(fixtures["Feature"]!["X.swift"]):8:5: note: `X` declares `logger: Logger` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.reenteringServiceModules(x: ["@Instantiated let logger: Logger", "@Instantiated let serviceBuilder: Instantiator<Service>"]).modules,
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilderAroundSeamCycle_whenTwoSeamsOfOneModuleReachEachOtherBesideHole() async throws {
		// C1.28, H8: `Service`'s tree instantiates `Other`, a seam of its module, whose tree instantiates `Service`. `Other`
		// passes `Service`'s builder up, and `Service` passes its own to `Other`, which hands it back.
		let (modules, visibleModules) = Self.reenteringServiceModules(
			x: ["@Instantiated let otherBuilder: Instantiator<Other>"],
			other: ["@Instantiated let serviceBuilder: Instantiator<Service>"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Other {
		    @frozen public enum SafeDIScope_UserService {
		        indirect case serviceBuilder(serviceBuilder_Values, Service.SafeDIScope_UserService)

		        public struct serviceBuilder_Values {}
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        func __safeDI_serviceBuilder() -> Service {
		            _ = Service.__safeDI_Service_8F1BDC206A9EBB43.self
		            return Service(__safeDI_userServiceBuilder: { __safeDI_userServiceBuilder(.serviceBuilder(SafeDIScope_UserService.serviceBuilder_Values(), $0)) })
		        }
		        let serviceBuilder = Instantiator<Service>(__safeDI_serviceBuilder)
		        self.init(serviceBuilder: serviceBuilder)
		    }
		}

		extension Other {
		    public enum __safeDI_Other_8F1BDC206A9EBB43 {}
		}

		extension Service {
		    @frozen public enum SafeDIScope_UserService {
		        indirect case xBuilder(xBuilder_Values, SafeDIScope_UserService.X_Scope)
		        case profile(profile_Values, SafeDIScope_UserService.Profile_Scope)

		        public struct xBuilder_Values {
		            public let analytics: Analytics
		        }

		        public struct profile_Values {
		            public let analytics: Analytics
		            public let xBuilder: Instantiator<X>
		        }

		        @frozen public enum X_Scope {
		            indirect case otherBuilder(otherBuilder_Values, Other.SafeDIScope_UserService)

		            public struct otherBuilder_Values {}
		        }

		        @frozen public enum Profile_Scope {
		            case userService(userService_Values)

		            public struct userService_Values {}
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        let analytics = Analytics()
		        let __safeDI_userServiceValues_xBuilder = SafeDIScope_UserService.xBuilder_Values(analytics: analytics)
		        func __safeDI_xBuilder() -> X {
		            func __safeDI_otherBuilder() -> Other {
		                _ = Other.__safeDI_Other_8F1BDC206A9EBB43.self
		                return Other(__safeDI_userServiceBuilder: { __safeDI_userServiceBuilder(.xBuilder(__safeDI_userServiceValues_xBuilder, .otherBuilder(SafeDIScope_UserService.X_Scope.otherBuilder_Values(), $0))) })
		            }
		            let otherBuilder = Instantiator<Other>(__safeDI_otherBuilder)
		            return X(otherBuilder: otherBuilder)
		        }
		        let xBuilder = Instantiator<X>(__safeDI_xBuilder)
		        let __safeDI_userServiceValues_profile = SafeDIScope_UserService.profile_Values(analytics: analytics, xBuilder: xBuilder)
		        func __safeDI_profile() -> Profile {
		            let userService: any UserService = __safeDI_userServiceBuilder(.profile(__safeDI_userServiceValues_profile, .userService(SafeDIScope_UserService.Profile_Scope.userService_Values())))
		            return Profile(userService: userService, analytics: analytics)
		        }
		        let profile: Profile = __safeDI_profile()
		        self.init(analytics: analytics, xBuilder: xBuilder, profile: profile)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_8F1BDC206A9EBB43 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        let logger = Logger()
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_8F1BDC206A9EBB43.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .xBuilder(_, scope): return __safeDI_userServiceBuilder_Service_X_Scope(scope)
		                case let .profile(values, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope, analytics: values.analytics)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service_X_Scope(_ scope: Service.SafeDIScope_UserService.X_Scope) -> any UserService {
		                switch scope {
		                case let .otherBuilder(_, scope): return __safeDI_userServiceBuilder_Other(scope)
		                }
		            }
		            func __safeDI_userServiceBuilder_Other(_ scope: Other.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .serviceBuilder(_, scope): return __safeDI_userServiceBuilder_Service(scope)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope, analytics: Analytics) -> any UserService {
		                switch scope {
		                case .userService:
		                    let userService: any UserService = DefaultUserService(analytics: analytics, logger: logger)
		                    return userService
		                }
		            }
		            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
		        }
		        let service: Service = __safeDI_service()
		        self.init(logger: logger, service: service)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: visibleModules)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarry_whenFillReadsLabelSeamOnCycleBindsOnPathToCallBack() async {
		// C8.15, H8: inline, the `Service` that `Other` instantiates hands its `DefaultUserService` `Other`'s `logger`. The
		// label reaches `Service`'s own builder through the builder `Other` passes up, which `Service` presents to `Other`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultUserService.swift"]):11:5: error: `DefaultUserService` receives `logger: Logger`, which `Other` builds where it calls `Service`, but `Other` passes the builder for `Profile`’s `userService: any UserService` (case `Profile_Scope.userService` of `userServiceBuilder`) on from its own caller, which cannot hand it `Other`’s values. Declare `@Received let logger: Logger` on `Service`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `UserService` in module `Feature` or a module it lists among its SafeDI dependencies, so `Other` fills the builder itself.
			\(fixtures["Feature"]!["Other.swift"]):8:5: note: `Other` declares `logger: Logger` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.reenteringServiceModules(
					x: ["@Instantiated let otherBuilder: Instantiator<Other>"],
					other: ["@Instantiated let logger: Logger", "@Instantiated let serviceBuilder: Instantiator<Service>"],
				).modules,
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOwnBuilderSendable_whenSeamOfItsModuleReachingItInSendableBuilderPassesItBack() async throws {
		// C1.28's `Sendable` twin: `Shell` builds `Inner` in a `SendableInstantiator`, so it takes the builder of `Inner`'s
		// site `@Sendable`, and `Inner`, which passes its own builder to `Shell`, takes it `@Sendable` too.
		let feature = [
			Self.userServiceProtocol,
			seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
			// `@unchecked`, as the fuzzer's mixed-wrapper graphs mark their types: `Shell` builds `Inner` in a `SendableInstantiator`.
			seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let profileBuilder: Instantiator<Profile>", "@Instantiated let shellBuilder: Instantiator<Shell>"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let innerBuilder: SendableInstantiator<Inner>"]),
		]
		let fulfillers = [Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: [])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let inner: Inner"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Inner {
		    @frozen public enum SafeDIScope_UserService {
		        case profileBuilder(profileBuilder_Values, SafeDIScope_UserService.Profile_Scope)

		        public struct profileBuilder_Values {
		            public let shellBuilder: Instantiator<Shell>
		        }

		        @frozen public enum Profile_Scope {
		            case userService(userService_Values)

		            public struct userService_Values {}
		        }
		    }

		    @frozen public enum SafeDISendableScope_UserService {
		        indirect case shellBuilder_Sendable(Shell.SafeDISendableScope_UserService)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService, __safeDI_userServiceSendableBuilder: @escaping @Sendable (SafeDISendableScope_UserService) -> any UserService) {
		        func __safeDI_shellBuilder() -> Shell {
		            _ = Shell.__safeDI_Shell_AFA12F37A4E5E519.self
		            return Shell(__safeDI_userServiceSendableBuilder: { __safeDI_userServiceSendableBuilder(.shellBuilder_Sendable($0)) })
		        }
		        let shellBuilder = Instantiator<Shell>(__safeDI_shellBuilder)
		        let __safeDI_userServiceValues_profileBuilder = SafeDIScope_UserService.profileBuilder_Values(shellBuilder: shellBuilder)
		        func __safeDI_profileBuilder() -> Profile {
		            let userService: any UserService = __safeDI_userServiceBuilder(.profileBuilder(__safeDI_userServiceValues_profileBuilder, .userService(SafeDIScope_UserService.Profile_Scope.userService_Values())))
		            return Profile(userService: userService)
		        }
		        let profileBuilder = Instantiator<Profile>(__safeDI_profileBuilder)
		        self.init(profileBuilder: profileBuilder, shellBuilder: shellBuilder)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_A9DD45571D3945CB {}
		}

		extension Shell {
		    @frozen public enum SafeDISendableScope_UserService {
		        case innerBuilder(Inner.SafeDIScope_UserService)
		        indirect case innerBuilder_Sendable(Inner.SafeDISendableScope_UserService)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceSendableBuilder: @escaping @Sendable (SafeDISendableScope_UserService) -> any UserService) {
		        @Sendable func __safeDI_innerBuilder() -> Inner {
		            _ = Inner.__safeDI_Inner_A9DD45571D3945CB.self
		            return Inner(__safeDI_userServiceBuilder: { __safeDI_userServiceSendableBuilder(.innerBuilder($0)) }, __safeDI_userServiceSendableBuilder: { __safeDI_userServiceSendableBuilder(.innerBuilder_Sendable($0)) })
		        }
		        let innerBuilder = SendableInstantiator<Inner>(__safeDI_innerBuilder)
		        self.init(innerBuilder: innerBuilder)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_AFA12F37A4E5E519 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_A9DD45571D3945CB.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @Sendable func __safeDI_userServiceBuilder_Inner(_ scope: Inner.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .profileBuilder(_, scope): return __safeDI_userServiceBuilder_Inner_Profile_Scope(scope)
		                }
		            }
		            @Sendable func __safeDI_userServiceBuilder_Inner_Profile_Scope(_ scope: Inner.SafeDIScope_UserService.Profile_Scope) -> any UserService {
		                switch scope {
		                case .userService:
		                    let userService: any UserService = DefaultUserService()
		                    return userService
		                }
		            }
		            @Sendable func __safeDI_userServiceSendableBuilder_Inner(_ scope: Inner.SafeDISendableScope_UserService) -> any UserService {
		                switch scope {
		                case let .shellBuilder_Sendable(scope): return __safeDI_userServiceSendableBuilder_Shell(scope)
		                }
		            }
		            @Sendable func __safeDI_userServiceSendableBuilder_Shell(_ scope: Shell.SafeDISendableScope_UserService) -> any UserService {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_userServiceBuilder_Inner(scope)
		                case let .innerBuilder_Sendable(scope): return __safeDI_userServiceSendableBuilder_Inner(scope)
		                }
		            }
		            return Inner(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Inner, __safeDI_userServiceSendableBuilder: __safeDI_userServiceSendableBuilder_Inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature + fulfillers, app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesOwnBuilderAsSendable_whenReenteringCallSitsInSeamsOwnSendableBuilderFunction() async throws {
		// C1.29, H8: `Service` calls itself inside `xBuilder`'s `@Sendable` builder function, which captures the builder it
		// passes, so `Service` takes it `@Sendable`, and `App`'s fill is `@Sendable` too.
		let (modules, visibleModules) = Self.reenteringServiceModules(
			xBuilderType: "SendableInstantiator<X>",
			x: ["@Instantiated let serviceBuilder: Instantiator<Service>"],
			fulfillerDeclarations: ["@Received let analytics: Analytics"],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Service {
		    @frozen public enum SafeDIScope_UserService {
		        case profile(profile_Values, SafeDIScope_UserService.Profile_Scope)

		        public struct profile_Values {
		            public let analytics: Analytics
		            public let xBuilder: SendableInstantiator<X>
		        }

		        @frozen public enum Profile_Scope {
		            case userService(userService_Values)

		            public struct userService_Values {}
		        }

		        @frozen public enum X_Scope {
		            case serviceBuilder(serviceBuilder_Values, Service.SafeDIScope_UserService)

		            public struct serviceBuilder_Values {}
		        }
		    }

		    @frozen public enum SafeDISendableScope_UserService {
		        case xBuilder(SafeDIScope_UserService.X_Scope)
		        indirect case xBuilder_Sendable(SafeDISendableScope_UserService.X_Scope)

		        @frozen public enum X_Scope {
		            indirect case serviceBuilder_Sendable(Service.SafeDISendableScope_UserService)
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService, __safeDI_userServiceSendableBuilder: @escaping @Sendable (SafeDISendableScope_UserService) -> any UserService) {
		        let analytics = Analytics()
		        @Sendable func __safeDI_xBuilder() -> X {
		            func __safeDI_serviceBuilder() -> Service {
		                _ = Service.__safeDI_Service_F66C3867675EF36F.self
		                return Service(__safeDI_userServiceBuilder: { __safeDI_userServiceSendableBuilder(.xBuilder(.serviceBuilder(SafeDIScope_UserService.X_Scope.serviceBuilder_Values(), $0))) }, __safeDI_userServiceSendableBuilder: { __safeDI_userServiceSendableBuilder(.xBuilder_Sendable(.serviceBuilder_Sendable($0))) })
		            }
		            let serviceBuilder = Instantiator<Service>(__safeDI_serviceBuilder)
		            return X(serviceBuilder: serviceBuilder)
		        }
		        let xBuilder = SendableInstantiator<X>(__safeDI_xBuilder)
		        let __safeDI_userServiceValues_profile = SafeDIScope_UserService.profile_Values(analytics: analytics, xBuilder: xBuilder)
		        func __safeDI_profile() -> Profile {
		            let userService: any UserService = __safeDI_userServiceBuilder(.profile(__safeDI_userServiceValues_profile, .userService(SafeDIScope_UserService.Profile_Scope.userService_Values())))
		            return Profile(userService: userService, analytics: analytics)
		        }
		        let profile: Profile = __safeDI_profile()
		        self.init(analytics: analytics, xBuilder: xBuilder, profile: profile)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_F66C3867675EF36F {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        let logger = Logger()
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_F66C3867675EF36F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @Sendable func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .profile(values, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope, analytics: values.analytics)
		                }
		            }
		            @Sendable func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope, analytics: Analytics) -> any UserService {
		                switch scope {
		                case .userService:
		                    let userService: any UserService = DefaultUserService(analytics: analytics)
		                    return userService
		                }
		            }
		            @Sendable func __safeDI_userServiceSendableBuilder_Service(_ scope: Service.SafeDISendableScope_UserService) -> any UserService {
		                switch scope {
		                case let .xBuilder(scope): return __safeDI_userServiceBuilder_Service_X_Scope(scope)
		                case let .xBuilder_Sendable(scope): return __safeDI_userServiceSendableBuilder_Service_X_Scope(scope)
		                }
		            }
		            @Sendable func __safeDI_userServiceBuilder_Service_X_Scope(_ scope: Service.SafeDIScope_UserService.X_Scope) -> any UserService {
		                switch scope {
		                case let .serviceBuilder(_, scope): return __safeDI_userServiceBuilder_Service(scope)
		                }
		            }
		            @Sendable func __safeDI_userServiceSendableBuilder_Service_X_Scope(_ scope: Service.SafeDISendableScope_UserService.X_Scope) -> any UserService {
		                switch scope {
		                case let .serviceBuilder_Sendable(scope): return __safeDI_userServiceSendableBuilder_Service(scope)
		                }
		            }
		            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service, __safeDI_userServiceSendableBuilder: __safeDI_userServiceSendableBuilder_Service)
		        }
		        let service: Service = __safeDI_service()
		        self.init(logger: logger, service: service)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: visibleModules)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOneBuilderPerSite_whenTwoSeamsOfOneModulePassUpOneSite() async throws {
		// C4.13, H8: `Service` calls `A` and `B`, seams that each call `Inner`, whose tree holds the site. A seam takes one
		// builder per site, whatever route presents it, so `Service` takes one and passes it at both calls.
		let feature = [
			Self.userServiceProtocol,
			seamFixtureType(named: "Analytics", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "A", isSeam: true, declarations: ["@Instantiated let inner: Inner"]),
			seamFixtureType(named: "B", isSeam: true, declarations: ["@Instantiated let inner: Inner"]),
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"]),
		]
		let fulfillers = [Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let analytics: Analytics"])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension A {
		    @frozen public enum SafeDIScope_UserService {
		        case inner(inner_Values, Inner.SafeDIScope_UserService)

		        public struct inner_Values {}
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_F71372C0F86A5454.self
		            return Inner(__safeDI_userServiceBuilder: { __safeDI_userServiceBuilder(.inner(SafeDIScope_UserService.inner_Values(), $0)) })
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension A {
		    public enum __safeDI_A_215C47A86E4DE07B {}
		}

		extension B {
		    @frozen public enum SafeDIScope_UserService {
		        case inner(inner_Values, Inner.SafeDIScope_UserService)

		        public struct inner_Values {}
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_F71372C0F86A5454.self
		            return Inner(__safeDI_userServiceBuilder: { __safeDI_userServiceBuilder(.inner(SafeDIScope_UserService.inner_Values(), $0)) })
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension B {
		    public enum __safeDI_B_779E14BAEBFF9A3C {}
		}

		extension Inner {
		    @frozen public enum SafeDIScope_UserService {
		        case userService(userService_Values)

		        public struct userService_Values {
		            public let analytics: Analytics
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        let analytics = Analytics()
		        let userService: any UserService = __safeDI_userServiceBuilder(.userService(SafeDIScope_UserService.userService_Values(analytics: analytics)))
		        self.init(analytics: analytics, userService: userService)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_F71372C0F86A5454 {}
		}

		extension Service {
		    @frozen public enum SafeDIScope_UserService {
		        case aBuilder(aBuilder_Values, A.SafeDIScope_UserService)
		        case bBuilder(bBuilder_Values, B.SafeDIScope_UserService)

		        public struct aBuilder_Values {}

		        public struct bBuilder_Values {
		            public let aBuilder: Instantiator<A>
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        func __safeDI_aBuilder() -> A {
		            _ = A.__safeDI_A_215C47A86E4DE07B.self
		            return A(__safeDI_userServiceBuilder: { __safeDI_userServiceBuilder(.aBuilder(SafeDIScope_UserService.aBuilder_Values(), $0)) })
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        func __safeDI_bBuilder() -> B {
		            _ = B.__safeDI_B_779E14BAEBFF9A3C.self
		            return B(__safeDI_userServiceBuilder: { __safeDI_userServiceBuilder(.bBuilder(SafeDIScope_UserService.bBuilder_Values(aBuilder: aBuilder), $0)) })
		        }
		        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		        self.init(aBuilder: aBuilder, bBuilder: bBuilder)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_FB56F7CCDFC571B6 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_FB56F7CCDFC571B6.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .aBuilder(_, scope): return __safeDI_userServiceBuilder_A(scope)
		                case let .bBuilder(_, scope): return __safeDI_userServiceBuilder_B(scope)
		                }
		            }
		            func __safeDI_userServiceBuilder_A(_ scope: A.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .inner(_, scope): return __safeDI_userServiceBuilder_Inner(scope)
		                }
		            }
		            func __safeDI_userServiceBuilder_Inner(_ scope: Inner.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .userService(scope):
		                    let analytics = scope.analytics
		                    let userService: any UserService = DefaultUserService(analytics: analytics)
		                    return userService
		                }
		            }
		            func __safeDI_userServiceBuilder_B(_ scope: B.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .inner(_, scope): return __safeDI_userServiceBuilder_Inner(scope)
		                }
		            }
		            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service)
		    }
		}
		"""])
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature + fulfillers, app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOneSendableBuilderPerSite_whenOneOfTwoSeamsPassingUpOneSiteTakesItSendable() async throws {
		// G4's diamond with a `Sendable` route: `Service` reaches `Inner`'s site through `A`, which builds `Inner` by value,
		// and through `B`, which builds it in a `SendableInstantiator` and so takes the builder `@Sendable`. `Service`
		// takes one builder for the site, which it passes to both, so it takes it `@Sendable`.
		let feature = [
			"public protocol UserService: Sendable {}",
			seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"], conformances: ", Sendable"),
			seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let profile: Profile"], conformances: ", Sendable"),
			seamFixtureType(named: "A", isSeam: true, declarations: ["@Instantiated let inner: Inner"]),
			seamFixtureType(named: "B", isSeam: true, declarations: ["@Instantiated let innerBuilder: SendableInstantiator<Inner>"]),
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let a: A", "@Instantiated let b: B"]),
		]
		let fulfillers = [Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: [])]
		let modules = Self.modules(feature: feature, app: fulfillers + [Self.canonicalRoot])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension A {
		    @frozen public enum SafeDIScope_UserService {
		        case inner(inner_Values, Inner.SafeDIScope_UserService)

		        public struct inner_Values {}
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_DB9532B32B53F312.self
		            return Inner(__safeDI_userServiceBuilder: { __safeDI_userServiceBuilder(.inner(SafeDIScope_UserService.inner_Values(), $0)) })
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension A {
		    public enum __safeDI_A_626EF207D066908B {}
		}

		extension B {
		    @frozen public enum SafeDISendableScope_UserService {
		        case innerBuilder(Inner.SafeDIScope_UserService)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceSendableBuilder: @escaping @Sendable (SafeDISendableScope_UserService) -> any UserService) {
		        @Sendable func __safeDI_innerBuilder() -> Inner {
		            _ = Inner.__safeDI_Inner_DB9532B32B53F312.self
		            return Inner(__safeDI_userServiceBuilder: { __safeDI_userServiceSendableBuilder(.innerBuilder($0)) })
		        }
		        let innerBuilder = SendableInstantiator<Inner>(__safeDI_innerBuilder)
		        self.init(innerBuilder: innerBuilder)
		    }
		}

		extension B {
		    public enum __safeDI_B_CFC5AC0EC2D149AE {}
		}

		extension Inner {
		    @frozen public enum SafeDIScope_UserService {
		        case profile(profile_Values, SafeDIScope_UserService.Profile_Scope)

		        public struct profile_Values {}

		        @frozen public enum Profile_Scope {
		            case userService(userService_Values)

		            public struct userService_Values {}
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        let __safeDI_userServiceValues_profile = SafeDIScope_UserService.profile_Values()
		        func __safeDI_profile() -> Profile {
		            let userService: any UserService = __safeDI_userServiceBuilder(.profile(__safeDI_userServiceValues_profile, .userService(SafeDIScope_UserService.Profile_Scope.userService_Values())))
		            return Profile(userService: userService)
		        }
		        let profile: Profile = __safeDI_profile()
		        self.init(profile: profile)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_DB9532B32B53F312 {}
		}

		extension Service {
		    @frozen public enum SafeDIScope_UserService {
		        case a(a_Values, A.SafeDIScope_UserService)

		        public struct a_Values {}
		    }

		    @frozen public enum SafeDISendableScope_UserService {
		        case b_Sendable(B.SafeDISendableScope_UserService)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService, __safeDI_userServiceSendableBuilder: @escaping @Sendable (SafeDISendableScope_UserService) -> any UserService) {
		        func __safeDI_a() -> A {
		            _ = A.__safeDI_A_626EF207D066908B.self
		            return A(__safeDI_userServiceBuilder: { __safeDI_userServiceBuilder(.a(SafeDIScope_UserService.a_Values(), $0)) })
		        }
		        let a: A = __safeDI_a()
		        func __safeDI_b() -> B {
		            _ = B.__safeDI_B_CFC5AC0EC2D149AE.self
		            return B(__safeDI_userServiceSendableBuilder: { __safeDI_userServiceSendableBuilder(.b_Sendable($0)) })
		        }
		        let b: B = __safeDI_b()
		        self.init(a: a, b: b)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_B2C7386B1F04E60C {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_B2C7386B1F04E60C.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .a(_, scope): return __safeDI_userServiceBuilder_A(scope)
		                }
		            }
		            func __safeDI_userServiceBuilder_A(_ scope: A.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .inner(_, scope): return __safeDI_userServiceBuilder_Inner(scope)
		                }
		            }
		            @Sendable func __safeDI_userServiceBuilder_Inner(_ scope: Inner.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .profile(_, scope): return __safeDI_userServiceBuilder_Inner_Profile_Scope(scope)
		                }
		            }
		            @Sendable func __safeDI_userServiceBuilder_Inner_Profile_Scope(_ scope: Inner.SafeDIScope_UserService.Profile_Scope) -> any UserService {
		                switch scope {
		                case .userService:
		                    let userService: any UserService = DefaultUserService()
		                    return userService
		                }
		            }
		            @Sendable func __safeDI_userServiceSendableBuilder_Service(_ scope: Service.SafeDISendableScope_UserService) -> any UserService {
		                switch scope {
		                case let .b_Sendable(scope): return __safeDI_userServiceSendableBuilder_B(scope)
		                }
		            }
		            @Sendable func __safeDI_userServiceSendableBuilder_B(_ scope: B.SafeDISendableScope_UserService) -> any UserService {
		                switch scope {
		                case let .innerBuilder(scope): return __safeDI_userServiceBuilder_Inner(scope)
		                }
		            }
		            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service, __safeDI_userServiceSendableBuilder: __safeDI_userServiceSendableBuilder_Service)
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature + fulfillers, app: [Self.canonicalRoot]))
	}

	// MARK: What a fill cannot read

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarry_whenFillReadsSiblingBuiltAfterItsCarrier() async {
		// C2.20, H4's first residual: `z` requires the carrier `p1`, so it starts with the carriers, after `p2`; `p2`'s
		// fill reads `z`, which inline builds before `p2`. A deliberate gap of the start order, reported with the reorder.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["ZLedger.swift"]):9:5: error: `ZLedger` receives `z: Z`, which `Service`’s dependency tree builds after `p2`, since `Z` requires `p1`, which carries another builder, so the scope SafeDI hands the builder for `P2`’s `ledger: any Ledger` (case `P2_Scope.ledger` of `ledgerBuilder`) does not carry it. Declare `z` before `p2` in `Service`, or declare an @Instantiable type that fulfills `Ledger` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Service.swift"]):11:5: note: `Service` declares `z: Z` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						"public protocol Clock {}\npublic protocol Ledger {}",
						seamFixtureType(named: "P1", declarations: ["@Instantiated let clock: any Clock"]),
						seamFixtureType(named: "P2", declarations: ["@Instantiated let ledger: any Ledger"]),
						seamFixtureType(named: "Z", declarations: ["@Received let p1: P1"]),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let p1: P1", "@Instantiated let p2: P2", "@Instantiated let z: Z"]),
					],
					app: [
						Self.fulfillingType(named: "SystemClock", fulfilling: "Clock", declarations: []),
						Self.fulfillingType(named: "ZLedger", fulfilling: "Ledger", declarations: ["@Received let z: Z"]),
						Self.canonicalRoot,
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarry_whenFillRequiresValueSeamsTreeReceivesOnlyIfAvailable() async {
		// C8.6: `Badge` receives `theme` only if available, so the struct carries `theme: Theme?`, which a caller may pass
		// `nil` for, while `ThemedUserService` requires `theme: Theme`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["ThemedUserService.swift"]):9:5: error: `ThemedUserService` receives `theme: Theme`, which the scope SafeDI hands the builder for `Profile`’s `userService: any UserService` (case `Profile_Scope.userService` of `userServiceBuilder`) carries only as `theme: Theme?`, since `Service`’s tree receives it only if available. Declare `@Received let theme: Theme` on `Service`, or receive it on `ThemedUserService` with `@Received(onlyIfAvailable: true) let theme: Theme?`.
			\(fixtures["Feature"]!["Badge.swift"]):7:5: note: `Badge` receives `theme: Theme?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						Self.userServiceProtocol,
						seamFixtureType(named: "Theme", declarations: []),
						seamFixtureType(named: "Badge", declarations: ["@Received(onlyIfAvailable: true) let theme: Theme?"]),
						seamFixtureType(named: "Profile", declarations: ["@Instantiated let badge: Badge", "@Instantiated let userService: any UserService"]),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let profile: Profile"]),
					],
					app: [
						Self.fulfillingType(named: "ThemedUserService", fulfilling: "UserService", declarations: ["@Received let theme: Theme"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let service: Service"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUnfulfillableErrorFromRoot_whenFillRequiresValueTypeOnPathForwardsOptionally() async {
		// `Profile` forwards `theme: Theme?`, so the struct would carry `theme: Theme?` where `ThemedUserService` requires
		// `theme: Theme`. The received-property walk reports it first, as inline: `fieldHeldOnlyOptionally` never sees a
		// field that is optional because its declaration is.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["ThemedUserService.swift"]):9:5: error: @Received property `theme: Theme` is not @Instantiated or @Forwarded in chain: Root -> Service -> Instantiator<Profile> -> ThemedUserService. Did you mean `theme: Theme?`?
			\(fixtures["App"]!["ThemedUserService.swift"]):9:26-9:31: fixit: Theme?
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						Self.userServiceProtocol,
						seamFixtureType(named: "Theme", declarations: []),
						seamFixtureType(named: "Profile", declarations: ["@Forwarded let theme: Theme?", "@Instantiated let userService: any UserService"]),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let profileBuilder: Instantiator<Profile>"]),
					],
					app: [
						Self.fulfillingType(named: "ThemedUserService", fulfilling: "UserService", declarations: ["@Received let theme: Theme"]),
						Self.canonicalRoot,
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUnfulfillableErrorFromRoot_whenFillRequiresValueSeamForwardsOptionally() async {
		// The seam itself forwards `theme: Theme?`, which the received-property walk reports, as for a type on the path.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["ThemedUserService.swift"]):9:5: error: @Received property `theme: Theme` is not @Instantiated or @Forwarded in chain: Root -> Instantiator<Service> -> Profile -> ThemedUserService. Did you mean `theme: Theme?`?
			\(fixtures["App"]!["ThemedUserService.swift"]):9:26-9:31: fixit: Theme?
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						Self.userServiceProtocol,
						seamFixtureType(named: "Theme", declarations: []),
						seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Forwarded let theme: Theme?", "@Instantiated let profile: Profile"]),
					],
					app: [
						Self.fulfillingType(named: "ThemedUserService", fulfilling: "UserService", declarations: ["@Received let theme: Theme"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let serviceBuilder: Instantiator<Service>"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUnfulfillableErrorFromRoot_whenFillRequiresValueTypeOnPathRenamesOptionally() async {
		// `Profile` renames `theme` to `currentTheme: Theme?` only if available, which the received-property walk reports
		// where `ThemedUserService` requires `currentTheme: Theme`, as for a forwarded optional.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["ThemedUserService.swift"]):9:5: error: @Received property `currentTheme: Theme` is not @Instantiated or @Forwarded in chain: Root -> Service -> Profile -> ThemedUserService. Did you mean one of `currentTheme: Theme?`, `theme: Theme`?
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						Self.userServiceProtocol,
						seamFixtureType(named: "Theme", declarations: []),
						seamFixtureType(named: "Profile", declarations: [#"@Received(fulfilledByDependencyNamed: "theme", ofType: Theme.self, onlyIfAvailable: true) let currentTheme: Theme?"#, "@Instantiated let userService: any UserService"]),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let profile: Profile"]),
					],
					app: [
						Self.fulfillingType(named: "ThemedUserService", fulfilling: "UserService", declarations: ["@Received let currentTheme: Theme"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let service: Service"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Cycles through a fill

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillClosesCycleInSeamTree_whenFulfillerInstantiatesPropertyOfSeamsPath(holeIsConstant: Bool) async {
		// C1.14, C1.16: `LoopingUserService` instantiates `aBuilder: Instantiator<A>`, which `Service`'s tree is building
		// where it builds the hole. Code generated in `App` cannot refer to `Service`'s builder function for `A`, and
		// building `A` again would hold other values. Renaming helps a hole of either kind: the cycle then closes at the hole
		// inside the fill, with `aBuilder` along it.
		let hole = holeIsConstant
			? #"@Instantiated(fulfilledByType: "LoopingUserService", erasedToConcreteExistential: true) let userService: AnyUserService"#
			: #"@Instantiated(fulfilledByType: "LoopingUserService", erasedToConcreteExistential: true) let userServiceBuilder: ErasedInstantiator<(), AnyUserService>"#
		let property = holeIsConstant ? "userService: AnyUserService" : "userServiceBuilder: ErasedInstantiator<(), AnyUserService>"
		let label = String(property.prefix { $0 != ":" })
		let renameRemedy = "; or give `aBuilder` on `LoopingUserService` another label, so the cycle closes at `\(label)` itself"
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LoopingUserService.swift"]):10:5: error: SafeDI cannot fill the builder for `A`’s `\(property)` (case `A_Scope.\(label)` of `loopingUserServiceBuilder`) in `Service`’s dependency tree: `LoopingUserService`, which fills it, instantiates `aBuilder: Instantiator<A>`, which `Service`’s tree is building where it builds `\(label)` (Service -> aBuilder -> A -> \(label) -> LoopingUserService -> aBuilder). Code generated outside module `Feature` cannot refer to the function `Service`’s initializer builds `A` with, and building it again would hand it other values than `Service`’s tree holds. Instantiate the seam where `LoopingUserService` builds `A` (`@Instantiated let serviceBuilder: Instantiator<Service>`), so the cycle re-enters through the initializer SafeDI generates for `Service`; declare an @Instantiable type that fulfills `LoopingUserService` in module `Feature` or a module it lists among its SafeDI dependencies\(renameRemedy).
			\(fixtures["Feature"]!["Service.swift"]):9:5: note: `Service` instantiates `aBuilder: Instantiator<A>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						"""
						public protocol UserService {}

						public struct AnyUserService: UserService {
						    public init(_ base: any UserService) {
						        self.base = base
						    }

						    let base: any UserService
						}
						""",
						seamFixtureType(named: "Analytics", declarations: []),
						seamFixtureType(named: "A", declarations: [hole, "@Received let analytics: Analytics"]),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let aBuilder: Instantiator<A>"]),
					],
					app: [
						seamFixtureType(named: "LoopingUserService", declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Received let analytics: Analytics"], conformances: ", UserService"),
						Self.canonicalRoot,
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsCycleError_whenFillClosesCycleOnPropertyOfSeamsPathWithNoInstantiatorAlongIt() async {
		// `LoopingUserService` instantiates `b: B`, which `Service`'s tree is building where it builds the constant hole, and
		// no dependency between is an instantiator: the cycle error, not the fill's, so the fill's remedy of a rename, which
		// would close a cycle with the same dependencies along it at the hole, is offered only for a cycle with one.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LoopingUserService.swift"]):10:5: error: Dependency cycle: `B` -> `AnyUserService` -> `B`. SafeDI accepts a dependency cycle when one of the dependencies that instantiate along it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change one of `b: B`, `userService: AnyUserService` to an instantiator.
			\(fixtures["Feature"]!["B.swift"]):1:1: note: `B` is part of the cycle
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						"""
						public protocol UserService {}

						public struct AnyUserService: UserService {
						    public init(_ base: any UserService) {
						        self.base = base
						    }

						    let base: any UserService
						}
						""",
						seamFixtureType(named: "Analytics", declarations: []),
						seamFixtureType(named: "A", declarations: ["@Instantiated let b: B", "@Received let analytics: Analytics"]),
						seamFixtureType(named: "B", declarations: [#"@Instantiated(fulfilledByType: "LoopingUserService", erasedToConcreteExistential: true) let userService: AnyUserService"#, "@Received let analytics: Analytics"]),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let aBuilder: Instantiator<A>"]),
					],
					app: [
						seamFixtureType(named: "LoopingUserService", declarations: ["@Instantiated let b: B", "@Received let analytics: Analytics"], conformances: ", UserService"),
						Self.canonicalRoot,
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_closesCycleAtHoleInsideFill_whenFulfillerInstantiatesTypeOfSeamsPathUnderAnotherLabel(holeIsConstant: Bool) async throws {
		// The remedy above: `LoopingUserService` instantiates `A` under another label, so the cycle closes at the hole inside
		// the fill `App` generates, which calls the fill's own function, with `otherBuilder` along the cycle.
		let hole = holeIsConstant
			? #"@Instantiated(fulfilledByType: "LoopingUserService", erasedToConcreteExistential: true) let userService: AnyUserService"#
			: #"@Instantiated(fulfilledByType: "LoopingUserService", erasedToConcreteExistential: true) let userServiceBuilder: ErasedInstantiator<(), AnyUserService>"#
		let feature = [
			"""
			public protocol UserService {}

			public struct AnyUserService: UserService {
			    public init(_ base: any UserService) {
			        self.base = base
			    }

			    let base: any UserService
			}
			""",
			seamFixtureType(named: "Analytics", declarations: []),
			seamFixtureType(named: "A", declarations: [hole, "@Received let analytics: Analytics"]),
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let aBuilder: Instantiator<A>"]),
		]
		let fulfillers = [seamFixtureType(named: "LoopingUserService", declarations: ["@Instantiated let otherBuilder: Instantiator<A>", "@Received let analytics: Analytics"], conformances: ", UserService")]
		let modules = Self.modules(feature: feature, app: fulfillers + [Self.canonicalRoot])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": holeIsConstant ? """
		extension Root {
		    public init() {
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_6E778CBEEBA408FC.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_loopingUserServiceBuilder_Service(_ scope: Service.SafeDIScope_LoopingUserService) -> AnyUserService {
		                switch scope {
		                case let .aBuilder(values, scope): return __safeDI_loopingUserServiceBuilder_Service_A_Scope(scope, analytics: values.analytics)
		                }
		            }
		            func __safeDI_loopingUserServiceBuilder_Service_A_Scope(_ scope: Service.SafeDIScope_LoopingUserService.A_Scope, analytics: Analytics) -> AnyUserService {
		                switch scope {
		                case .userService:
		                    func __safeDI_userService() -> LoopingUserService {
		                        func __safeDI_otherBuilder() -> A {
		                            let userService = AnyUserService(__safeDI_userService())
		                            return A(userService: userService, analytics: analytics)
		                        }
		                        let otherBuilder = Instantiator<A>(__safeDI_otherBuilder)
		                        return LoopingUserService(otherBuilder: otherBuilder, analytics: analytics)
		                    }
		                    let userService = AnyUserService(__safeDI_userService())
		                    return userService
		                }
		            }
		            return Service(__safeDI_loopingUserServiceBuilder: __safeDI_loopingUserServiceBuilder_Service)
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service)
		    }
		}
		""" : """
		extension Root {
		    public init() {
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_98D4A0572EF59BB8.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_loopingUserServiceBuilder_Service(_ scope: Service.SafeDIScope_LoopingUserService) -> AnyUserService {
		                switch scope {
		                case let .aBuilder(values, scope): return __safeDI_loopingUserServiceBuilder_Service_A_Scope(scope, analytics: values.analytics)
		                }
		            }
		            func __safeDI_loopingUserServiceBuilder_Service_A_Scope(_ scope: Service.SafeDIScope_LoopingUserService.A_Scope, analytics: Analytics) -> AnyUserService {
		                switch scope {
		                case .userServiceBuilder:
		                    func __safeDI_userServiceBuilder() -> LoopingUserService {
		                        func __safeDI_otherBuilder() -> A {
		                            let userServiceBuilder = ErasedInstantiator<(), AnyUserService> {
		                                AnyUserService(__safeDI_userServiceBuilder())
		                            }
		                            return A(userServiceBuilder: userServiceBuilder, analytics: analytics)
		                        }
		                        let otherBuilder = Instantiator<A>(__safeDI_otherBuilder)
		                        return LoopingUserService(otherBuilder: otherBuilder, analytics: analytics)
		                    }
		                    return AnyUserService(__safeDI_userServiceBuilder())
		                }
		            }
		            return Service(__safeDI_loopingUserServiceBuilder: __safeDI_loopingUserServiceBuilder_Service)
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature + fulfillers, app: [Self.canonicalRoot]))
	}

	// MARK: Names

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesBuildersApart_whenLabelsAreKeywordsOrCollideWithParameterOrTreeProperty() async throws {
		// One behavior, how builders, structs and their bindings are named apart, over its triggers, in one compile.
		// C4.2: `Badge` receives `userServiceBuilder` only if available, so the parameter keeps that label and `Profile`'s
		// hole is named apart by its owner. C4.4: a keyword label spells `caseBuilder`, `SafeDIScope_Profile_case`, and the
		// field `` `default` ``. C4.3: `Gadget`'s `userServiceBuilder` would have a builder function named as `Panel`'s
		// builder is inside `Tray`'s initializer, which binds the builder with an underscore appended. C4.10: `Owner`'s two
		// sites have equal joined paths (`a_b` then `c`, `a` then `b_c`), which named one case per path once; nested by type,
		// each is a case of the type that builds it, `Left_Scope.c` and `Right_Scope.b_c`, so no name collides.
		let feature = [
			"public protocol UserService {}\npublic protocol Clock {}",
			seamFixtureType(named: "Count", declarations: []),
			seamFixtureType(named: "Impl", declarations: []),
			seamFixtureType(named: "Gadget", declarations: ["@Instantiated let userServiceBuilder: Instantiator<Impl>"]),
			seamFixtureType(named: "Badge", declarations: ["@Received(onlyIfAvailable: true) let userServiceBuilder: Instantiator<Impl>?"]),
			seamFixtureType(named: "Profile", declarations: ["@Instantiated let `case`: any Clock", "@Instantiated let userService: any UserService", "@Instantiated let badge: Badge"]),
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let `default`: Count", "@Instantiated let profile: Profile"]),
			seamFixtureType(named: "Panel", declarations: ["@Instantiated let gadget: Gadget", "@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "Tray", isSeam: true, declarations: ["@Instantiated let panel: Panel"]),
			seamFixtureType(named: "Owner", declarations: ["@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "Left", declarations: ["@Instantiated let c: Owner"]),
			seamFixtureType(named: "Right", declarations: ["@Instantiated let b_c: Owner"]),
			seamFixtureType(named: "Twin", isSeam: true, declarations: ["@Instantiated let a_b: Left", "@Instantiated let a: Right"]),
		]
		let fulfillers = [
			Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: []),
			Self.fulfillingType(named: "SystemClock", fulfilling: "Clock", declarations: ["@Received let `default`: Count"]),
		]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service", "@Instantiated let tray: Tray", "@Instantiated let twin: Twin"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Service {
		    @frozen public enum SafeDIScope_Clock {
		        case profile(profile_Values, SafeDIScope_Clock.Profile_Scope)

		        public struct profile_Values {
		            public let userServiceBuilder: Instantiator<Impl>?
		            public let `default`: Count
		        }

		        @frozen public enum Profile_Scope {
		            case `case`(case_Values)

		            public struct case_Values {
		                public let badge: Badge
		            }
		        }
		    }

		    @frozen public enum SafeDIScope_UserService_UserService {
		        case profile(profile_Values, SafeDIScope_UserService_UserService.Profile_Scope)

		        public struct profile_Values {
		            public let userServiceBuilder: Instantiator<Impl>?
		            public let `default`: Count
		        }

		        @frozen public enum Profile_Scope {
		            case userService(userService_Values)

		            public struct userService_Values {
		                public let badge: Badge
		                public let `case`: any Clock
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder userServiceBuilder: Instantiator<Impl>?, __safeDI_clockBuilder: @escaping (SafeDIScope_Clock) -> any Clock, __safeDI_userService_UserServiceBuilder: @escaping (SafeDIScope_UserService_UserService) -> any UserService) {
		        let `default` = Count()
		        let __safeDI_clockValues_profile = SafeDIScope_Clock.profile_Values(userServiceBuilder: userServiceBuilder, default: `default`)
		        let __safeDI_userService_UserServiceValues_profile = SafeDIScope_UserService_UserService.profile_Values(userServiceBuilder: userServiceBuilder, default: `default`)
		        func __safeDI_profile() -> Profile {
		            let badge = Badge(userServiceBuilder: userServiceBuilder)
		            let `case`: any Clock = __safeDI_clockBuilder(.profile(__safeDI_clockValues_profile, .`case`(SafeDIScope_Clock.Profile_Scope.case_Values(badge: badge))))
		            let userService: any UserService = __safeDI_userService_UserServiceBuilder(.profile(__safeDI_userService_UserServiceValues_profile, .userService(SafeDIScope_UserService_UserService.Profile_Scope.userService_Values(badge: badge, case: `case`))))
		            return Profile(case: `case`, userService: userService, badge: badge)
		        }
		        let profile: Profile = __safeDI_profile()
		        self.init(default: `default`, profile: profile)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_F3052A3564C37E50 {}
		}

		extension Tray {
		    @frozen public enum SafeDIScope_UserService {
		        case panel(panel_Values, SafeDIScope_UserService.Panel_Scope)

		        public struct panel_Values {}

		        @frozen public enum Panel_Scope {
		            case userService(userService_Values)

		            public struct userService_Values {
		                public let gadget: Gadget
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder __safeDI_userServiceBuilder_: @escaping (SafeDIScope_UserService) -> any UserService) {
		        let __safeDI_userServiceValues_panel = SafeDIScope_UserService.panel_Values()
		        func __safeDI_panel() -> Panel {
		            func __safeDI_gadget() -> Gadget {
		                func __safeDI_userServiceBuilder() -> Impl {
		                    Impl()
		                }
		                let userServiceBuilder = Instantiator<Impl>(__safeDI_userServiceBuilder)
		                return Gadget(userServiceBuilder: userServiceBuilder)
		            }
		            let gadget: Gadget = __safeDI_gadget()
		            let userService: any UserService = __safeDI_userServiceBuilder_(.panel(__safeDI_userServiceValues_panel, .userService(SafeDIScope_UserService.Panel_Scope.userService_Values(gadget: gadget))))
		            return Panel(gadget: gadget, userService: userService)
		        }
		        let panel: Panel = __safeDI_panel()
		        self.init(panel: panel)
		    }
		}

		extension Tray {
		    public enum __safeDI_Tray_7A89596A70FF7CA0 {}
		}

		extension Twin {
		    @frozen public enum SafeDIScope_UserService {
		        case a_b(a_b_Values, SafeDIScope_UserService.Left_Scope)
		        case a(a_Values, SafeDIScope_UserService.Right_Scope)

		        public struct a_b_Values {}

		        public struct a_Values {
		            public let a_b: Left
		        }

		        @frozen public enum Left_Scope {
		            case c(c_Values, SafeDIScope_UserService.Owner_Scope)

		            public struct c_Values {}
		        }

		        @frozen public enum Right_Scope {
		            case b_c(b_c_Values, SafeDIScope_UserService.Owner_Scope)

		            public struct b_c_Values {}
		        }

		        @frozen public enum Owner_Scope {
		            case userService(userService_Values)

		            public struct userService_Values {}
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        let __safeDI_userServiceValues_a_b = SafeDIScope_UserService.a_b_Values()
		        func __safeDI_a_b() -> Left {
		            let __safeDI_userServiceValues_c = SafeDIScope_UserService.Left_Scope.c_Values()
		            func __safeDI_c() -> Owner {
		                let userService: any UserService = __safeDI_userServiceBuilder(.a_b(__safeDI_userServiceValues_a_b, .c(__safeDI_userServiceValues_c, .userService(SafeDIScope_UserService.Owner_Scope.userService_Values()))))
		                return Owner(userService: userService)
		            }
		            let c: Owner = __safeDI_c()
		            return Left(c: c)
		        }
		        let a_b: Left = __safeDI_a_b()
		        let __safeDI_userServiceValues_a = SafeDIScope_UserService.a_Values(a_b: a_b)
		        func __safeDI_a() -> Right {
		            let __safeDI_userServiceValues_b_c = SafeDIScope_UserService.Right_Scope.b_c_Values()
		            func __safeDI_b_c() -> Owner {
		                let userService: any UserService = __safeDI_userServiceBuilder(.a(__safeDI_userServiceValues_a, .b_c(__safeDI_userServiceValues_b_c, .userService(SafeDIScope_UserService.Owner_Scope.userService_Values()))))
		                return Owner(userService: userService)
		            }
		            let b_c: Owner = __safeDI_b_c()
		            return Right(b_c: b_c)
		        }
		        let a: Right = __safeDI_a()
		        self.init(a_b: a_b, a: a)
		    }
		}

		extension Twin {
		    public enum __safeDI_Twin_E852D6790553D043 {}
		}
		"""])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_F3052A3564C37E50.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_clockBuilder_Service(_ scope: Service.SafeDIScope_Clock) -> any Clock {
		                switch scope {
		                case let .profile(values, scope): return __safeDI_clockBuilder_Service_Profile_Scope(scope, default: values.default)
		                }
		            }
		            func __safeDI_clockBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_Clock.Profile_Scope, default: Count) -> any Clock {
		                switch scope {
		                case .`case`:
		                    let `case`: any Clock = SystemClock(default: `default`)
		                    return `case`
		                }
		            }
		            func __safeDI_userService_UserServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService_UserService) -> any UserService {
		                switch scope {
		                case let .profile(_, scope): return __safeDI_userService_UserServiceBuilder_Service_Profile_Scope(scope)
		                }
		            }
		            func __safeDI_userService_UserServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService_UserService.Profile_Scope) -> any UserService {
		                switch scope {
		                case .userService:
		                    let userService: any UserService = DefaultUserService()
		                    return userService
		                }
		            }
		            return Service(__safeDI_userServiceBuilder: nil, __safeDI_clockBuilder: __safeDI_clockBuilder_Service, __safeDI_userService_UserServiceBuilder: __safeDI_userService_UserServiceBuilder_Service)
		        }
		        let service: Service = __safeDI_service()
		        func __safeDI_tray() -> Tray {
		            _ = Tray.__safeDI_Tray_7A89596A70FF7CA0.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Tray(_ scope: Tray.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .panel(_, scope): return __safeDI_userServiceBuilder_Tray_Panel_Scope(scope)
		                }
		            }
		            func __safeDI_userServiceBuilder_Tray_Panel_Scope(_ scope: Tray.SafeDIScope_UserService.Panel_Scope) -> any UserService {
		                switch scope {
		                case .userService:
		                    let userService: any UserService = DefaultUserService()
		                    return userService
		                }
		            }
		            return Tray(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Tray)
		        }
		        let tray: Tray = __safeDI_tray()
		        func __safeDI_twin() -> Twin {
		            _ = Twin.__safeDI_Twin_E852D6790553D043.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Twin(_ scope: Twin.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .a_b(_, scope): return __safeDI_userServiceBuilder_Twin_Left_Scope(scope)
		                case let .a(_, scope): return __safeDI_userServiceBuilder_Twin_Right_Scope(scope)
		                }
		            }
		            func __safeDI_userServiceBuilder_Twin_Left_Scope(_ scope: Twin.SafeDIScope_UserService.Left_Scope) -> any UserService {
		                switch scope {
		                case let .c(_, scope): return __safeDI_userServiceBuilder_Twin_Owner_Scope(scope)
		                }
		            }
		            func __safeDI_userServiceBuilder_Twin_Owner_Scope(_ scope: Twin.SafeDIScope_UserService.Owner_Scope) -> any UserService {
		                switch scope {
		                case .userService:
		                    let userService: any UserService = DefaultUserService()
		                    return userService
		                }
		            }
		            func __safeDI_userServiceBuilder_Twin_Right_Scope(_ scope: Twin.SafeDIScope_UserService.Right_Scope) -> any UserService {
		                switch scope {
		                case let .b_c(_, scope): return __safeDI_userServiceBuilder_Twin_Owner_Scope(scope)
		                }
		            }
		            return Twin(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Twin)
		        }
		        let twin: Twin = __safeDI_twin()
		        self.init(service: service, tray: tray, twin: twin)
		    }
		}
		"""])
	}

	// MARK: Tiers and field access

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsTierOmitsBuilder_whenHolesOwnerTakesItAtNarrowerAccessThanSeamsTier() async {
		// C5.2, H2: `UserService` is `package`, so the builder is `package`, and `Service`'s `public` initializer cannot take
		// it, which every tier takes.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer, which `Service`’s `public` access requires, cannot take `userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService`, the builder for `Profile`’s `userService: any UserService`, which no @Instantiable declaration that module `Feature` can see fulfills. `UserService` is declared `package`. Declare `UserService` `public`; declare `Service` `package`; declare an @Instantiable type that fulfills `UserService` in module `Feature` or a module it lists among its SafeDI dependencies, so `Service`’s tree builds it; or declare the dependency tree on a `package` type that instantiates `Service`.
			\(fixtures["Feature"]!["UserService.swift"]):1:1: note: `UserService` is declared `package` here.
			\(fixtures["Feature"]!["UserService.swift"]):1:1-1:8: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						"package protocol UserService {}",
						seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]).replacingOccurrences(of: "public init(", with: "package init("),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let profile: Profile"]),
					],
					app: [Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: []), Self.canonicalRoot],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarry_whenFillInOtherPackageReadsPackageField() async {
		// C6.3: `Session`'s own declaration is `package`, so the struct carries `session` at `package` access, which `App`,
		// in another package, cannot read.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["SessionUserService.swift"]):9:5: error: `SessionUserService` receives `session: Session`, which the scope SafeDI hands the builder for `Profile`’s `userService: any UserService` (case `Profile_Scope.userService` of `userServiceBuilder`) carries only at `package` access, and module `App` is not in package `Shop`. `Session`’s own `@Instantiable` declaration is `package`. Declare `Session` `public`, or declare an @Instantiable type that fulfills `UserService` in module `Feature` or a module it lists among its SafeDI dependencies, so `Service`’s tree builds it.
			\(fixtures["Feature"]!["Service.swift"]):8:5: note: `Service` declares `session: Session` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						Self.userServiceProtocol,
						seamFixtureType(named: "Session", isFinalClass: true, declarations: []).replacingOccurrences(of: "public ", with: "package "),
						seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let session: Session", "@Instantiated let profile: Profile"]).replacingOccurrences(of: "public init(", with: "package init("),
					],
					app: [Self.fulfillingType(named: "SessionUserService", fulfilling: "UserService", declarations: ["@Received let session: Session"]), Self.canonicalRoot],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarryOfferingPackageName_whenFillInModuleRunWithoutItsPackageReadsPackageField() async {
		// C6.3 with `App` compiled in `Service`'s package `Shop` but its run not told so: SafeDI cannot say `App` is in
		// another package, and giving it the package name lets it read the `package` field, so that remedy comes first.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["SessionUserService.swift"]):9:5: error: `SessionUserService` receives `session: Session`, which the scope SafeDI hands the builder for `Profile`’s `userService: any UserService` (case `Profile_Scope.userService` of `userServiceBuilder`) carries only at `package` access, and module `App` is not told it is in package `Shop`. `Session`’s own `@Instantiable` declaration is `package`. Give module `App` the package name of module `Feature` (`SWIFT_PACKAGE_NAME` under Tuist, `package_name` on `safedi_swift_library` under Bazel, `--package-name` in a custom build) if the two are in one package; declare `Session` `public`; or declare an @Instantiable type that fulfills `UserService` in module `Feature` or a module it lists among its SafeDI dependencies, so `Service`’s tree builds it.
			\(fixtures["Feature"]!["Service.swift"]):8:5: note: `Service` declares `session: Session` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						Self.userServiceProtocol,
						seamFixtureType(named: "Session", isFinalClass: true, declarations: []).replacingOccurrences(of: "public ", with: "package "),
						seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let session: Session", "@Instantiated let profile: Profile"]).replacingOccurrences(of: "public init(", with: "package init("),
					]),
					ModuleFixture(
						name: "App",
						packageName: "Shop",
						swiftFileContent: [
							Self.fulfillingType(named: "SessionUserService", fulfilling: "UserService", declarations: ["@Received let session: Session"]),
							Self.canonicalRoot,
						].map { "import Feature\n\n" + $0 },
						dependencies: ["Feature"],
						omitsPackageName: true,
					),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesFieldsAtProvenAccessAndCallsTierEachCallerReaches_whenCallersAreInSeamsPackageAndAnother() async throws {
		// C3.2, C3.3, C5.4, C6.2 (the matrix's `ta`): each field is as visible as its type's proof – `session` and `theme`
		// `package`, `badge` and `banner` `public` – and the `package` pass-through `theme`, which `Banner` receives only if
		// available, gives `Service` a `package` tier beside its `public` one, both taking the builder. `Same`, in
		// `Service`'s package, calls the `package` tier and reads `session`; `Other` calls the `public` tier and reads
		// `badge`.
		let feature = [
			Self.userServiceProtocol,
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []).replacingOccurrences(of: "public ", with: "package "),
			seamFixtureType(named: "Theme", isFinalClass: true, declarations: []).replacingOccurrences(of: "public ", with: "package "),
			seamFixtureType(named: "Badge", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Banner", declarations: ["@Received(onlyIfAvailable: true) let theme: Theme?"]).replacingOccurrences(of: "public init(", with: "package init("),
			seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let session: Session", "@Instantiated let badge: Badge", "@Instantiated let banner: Banner", "@Instantiated let profile: Profile"]).replacingOccurrences(of: "public init(", with: "package init("),
		]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service"])
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "Same", packageName: "Shop", swiftFileContent: [
				Self.fulfillingType(named: "SessionUserService", fulfilling: "UserService", declarations: ["@Received let session: Session"]).replacingOccurrences(of: "public init(", with: "package init("),
				root,
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "Other", packageName: "Other", swiftFileContent: [
				Self.fulfillingType(named: "BadgeUserService", fulfilling: "UserService", declarations: ["@Received let badge: Badge"]),
				root,
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Service {
		    @frozen public enum SafeDIScope_UserService {
		        case profile(profile_Values, SafeDIScope_UserService.Profile_Scope)

		        public struct profile_Values {
		            package var theme: Theme? { __safeDI_theme.instance }
		            package let session: Session
		            public let badge: Badge
		            public let banner: Banner
		            let __safeDI_theme: LazilyInstantiated<Theme?>

		            init(theme: LazilyInstantiated<Theme?>, session: Session, badge: Badge, banner: Banner) {
		                __safeDI_theme = theme
		                self.session = session
		                self.badge = badge
		                self.banner = banner
		            }
		        }

		        @frozen public enum Profile_Scope {
		            case userService(userService_Values)

		            public struct userService_Values {}
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        self.init(__safeDI_theme: nil, __safeDI_userServiceBuilder: __safeDI_userServiceBuilder)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    package init(__safeDI_theme: @autoclosure @escaping () -> Theme?, __safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        let theme = LazilyInstantiated<Theme?>(__safeDI_theme)
		        let session = Session()
		        let badge = Badge()
		        let banner = Banner(theme: theme.instance)
		        let __safeDI_userServiceValues_profile = SafeDIScope_UserService.profile_Values(theme: theme, session: session, badge: badge, banner: banner)
		        func __safeDI_profile() -> Profile {
		            let userService: any UserService = __safeDI_userServiceBuilder(.profile(__safeDI_userServiceValues_profile, .userService(SafeDIScope_UserService.Profile_Scope.userService_Values())))
		            return Profile(userService: userService)
		        }
		        let profile: Profile = __safeDI_profile()
		        self.init(session: session, badge: badge, banner: banner, profile: profile)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_85A6462AAC6D5C6F {}
		}
		"""])
		expectGeneratedFiles(output.modules["Same"]?.generatedFiles, ["Same.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_85A6462AAC6D5C6F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .profile(values, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope, session: values.session)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope, session: Session) -> any UserService {
		                switch scope {
		                case .userService:
		                    let userService: any UserService = SessionUserService(session: session)
		                    return userService
		                }
		            }
		            return Service(__safeDI_theme: nil, __safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service)
		    }
		}
		"""])
		expectGeneratedFiles(output.modules["Other"]?.generatedFiles, ["Other.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public init() {
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_85A6462AAC6D5C6F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .profile(values, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope, badge: values.badge)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope, badge: Badge) -> any UserService {
		                switch scope {
		                case .userService:
		                    let userService: any UserService = BadgeUserService(badge: badge)
		                    return userService
		                }
		            }
		            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderAndCapsFieldsAtSeamsAccess_whenSeamIsPackage() async throws {
		// C5.3, C6.4: `UserService` is `package` as far as SafeDI can tell, as is `Service`, so its one `package` tier
		// takes the builder; `Analytics` is `public`, and its field is capped at `Service`'s `package`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					Self.userServiceProtocol,
					seamFixtureType(named: "Analytics", isFinalClass: true, declarations: []),
					seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService", "@Received let analytics: Analytics"]).replacingOccurrences(of: "public init(", with: "package init("),
					seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let profile: Profile"]).replacingOccurrences(of: "public ", with: "package "),
				]),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [
					Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let analytics: Analytics"]),
					Self.canonicalRoot.replacingOccurrences(of: "public init(", with: "package init("),
				].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Service {
		    @frozen public enum SafeDIScope_UserService {
		        case profile(profile_Values, SafeDIScope_UserService.Profile_Scope)

		        public struct profile_Values {
		            package let analytics: Analytics
		        }

		        @frozen public enum Profile_Scope {
		            case userService(userService_Values)

		            public struct userService_Values {}
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    package init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        let analytics = Analytics()
		        let __safeDI_userServiceValues_profile = SafeDIScope_UserService.profile_Values(analytics: analytics)
		        func __safeDI_profile() -> Profile {
		            let userService: any UserService = __safeDI_userServiceBuilder(.profile(__safeDI_userServiceValues_profile, .userService(SafeDIScope_UserService.Profile_Scope.userService_Values())))
		            return Profile(userService: userService, analytics: analytics)
		        }
		        let profile: Profile = __safeDI_profile()
		        self.init(analytics: analytics, profile: profile)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_F28FC83B0681AF50 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsTierOmitsBuilder_whenOuterPublicSeamPassesUpBuilderOfPackageSeam() async {
		// C5.5, H8: the struct of `Service`'s builder counts at `Service`'s `package` access, so `Shell`'s `public`
		// initializer cannot take the builder it passes up.
		await assertThrowsMultiModuleError(inModule: "Mid", diagnostics: { fixtures in
			"""
			\(fixtures["Mid"]!["Shell.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Shell`: its generated `public` initializer, which `Shell`’s `public` access requires, cannot take `userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService`, the builder for `Profile`’s `userService: any UserService`, which no @Instantiable declaration that module `Mid` can see fulfills. `Service`’s own `@Instantiable` declaration is `package`. Declare `Service` `public`; declare `Shell` `package`; declare an @Instantiable type that fulfills `UserService` in module `Mid` or a module it lists among its SafeDI dependencies, so `Shell` fills the builder itself; or declare the dependency tree on a `package` type that instantiates `Shell`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						Self.userServiceProtocol,
						seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let profile: Profile"]).replacingOccurrences(of: "public ", with: "package "),
					]),
					ModuleFixture(name: "Mid", packageName: "Shop", swiftFileContent: [
						"import Feature\n\n" + seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let service: Service"]).replacingOccurrences(of: "public init(", with: "package init("),
					], dependencies: ["Feature"]),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [
						Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: []),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let shell: Shell"]),
					].map { "import Feature\nimport Mid\n\n" + $0 }, dependencies: ["Feature", "Mid"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarry_whenFillInOtherModuleReadsFieldOnlyInternalInitializerMentions() async {
		// C6.5: only `Screen`'s `internal` initializer mentions `[3 of Int]`, so the struct carries `token` at `internal`
		// access, which `App` cannot read.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["TokenUserService.swift"]):9:5: error: `TokenUserService` receives `token: [3 of Int]`, which the scope SafeDI hands the builder for `Profile`’s `userService: any UserService` (case `Profile_Scope.userService` of `userServiceBuilder`) carries only at `internal` access, and module `App` is not module `Feature`. `[3 of Int]` is `internal` as far as SafeDI can tell: SafeDI cannot read its spelling, and every initializer, `instantiate(…)` and mock method that mentions it in module `Feature` or on a type that receives it is `internal` (`Screen.init(token:profile:)`); a mention on any other declaration matches it by name alone, so it does not count. Mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records, or declare an @Instantiable type that fulfills `UserService` in module `Feature` or a module it lists among its SafeDI dependencies, so `Service`’s tree builds it.
			\(fixtures["Feature"]!["Screen.swift"]):8:5: note: `Screen` declares `token: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						Self.userServiceProtocol,
						seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
						seamFixtureType(named: "Screen", declarations: ["@Forwarded let token: [3 of Int]", "@Instantiated let profile: Profile"]).replacingOccurrences(of: "public init(", with: "init("),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let screenBuilder: Instantiator<Screen>"]),
					],
					app: [Self.fulfillingType(named: "TokenUserService", fulfilling: "UserService", declarations: ["@Received let token: [3 of Int]"]), Self.canonicalRoot],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderAndKeepsMocksFlatParameter_whenSeamThatGeneratesMockHasHole() async throws {
		// C3.12, H11: a mock builds every seam inline, so `Service`'s mock, which cannot see a fulfilling declaration, takes
		// the hole as today's parameter, beside the generated initializer that takes the builder.
		let feature = [
			Self.userServiceProtocol,
			seamFixtureType(named: "Analytics", declarations: []),
			seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService", "@Received let analytics: Analytics"]),
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let profile: Profile"])
				.replacingOccurrences(of: "@Instantiable(generateDependencyTree: true)", with: "@Instantiable(generateDependencyTree: true, generateMock: true)"),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(feature: feature, app: Self.canonicalApp), integration: .swiftPackagePlugin, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles["Service+SafeDI.swift"] == generatedFileHeader + Self.canonicalServiceCode)
		#expect(output.modules["Feature"]?.generatedFiles["Service+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Service {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            analytics: (() -> Analytics)? = nil,
		            profile: ((any UserService, Analytics) -> Profile)? = nil
		        ) {
		            self.analytics = analytics
		            self.profile = profile
		        }

		        let analytics: (() -> Analytics)?
		        let profile: ((any UserService, Analytics) -> Profile)?
		    }

		    static func mock(
		        userService: UserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
		        let profile = if let safeDIBuilder = safeDIOverrides.profile { safeDIBuilder(userService, analytics) } else { Profile(userService: userService, analytics: analytics) }
		        return Service(analytics: analytics, profile: profile)
		    }
		}
		#endif
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsInaccessibleConstruction_whenFillBuildsImplementationWithPackageInitializerOfAnotherPackage() async {
		// `App`, in package `pkgB`, fills `Service`'s builder with `DefaultUserService`, whose initializer is `package` in
		// `pkgA`. The fill is code `App` generates, so its construction is checked as the inline tree's is, with the same
		// error and fix-it.
		for isSeam in [true, false] {
			let feature = [
				"public protocol UserService: AnyObject {}",
				seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
				seamFixtureType(named: "Service", isSeam: isSeam, declarations: ["@Instantiated let profile: Profile"]),
			]
			await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
				"""
				\(fixtures["FeatureImpl"]!["DefaultUserService.swift"]):5:5: error: `DefaultUserService`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(fixtures["FeatureImpl"]!["DefaultUserService.swift"]):5:5-5:12: fixit: public
				"""
			}) {
				try await executeSafeDIToolMultiModuleTest(
					modules: [
						ModuleFixture(name: "Feature", packageName: "pkgA", swiftFileContent: feature),
						ModuleFixture(name: "FeatureImpl", packageName: "pkgA", swiftFileContent: [
							"""
							import Feature

							@Instantiable(fulfillingAdditionalTypes: [UserService.self])
							public final class DefaultUserService: UserService, Instantiable {
							    package init() {}
							}
							""",
						], dependencies: ["Feature"]),
						ModuleFixture(name: "App", packageName: "pkgB", swiftFileContent: ["import Feature\nimport FeatureImpl\n\n" + Self.canonicalRoot], dependencies: ["Feature", "FeatureImpl"]),
					],
					integration: .moduleInfo,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_offersFillsTypeAsSeam_whenFillsTreeBuildsPackageInitializerOfAnotherPackage(fillIsSeam: Bool) async throws {
		// `App`, in package `app`, fills `Service`'s builder with `DefaultUserService`, which module `Feature`, in package
		// `feat`, declares, and whose tree builds `Helper` with a `package` initializer. A fill starts a path of its own,
		// whose seam candidate is the fill's type, so the error offers declaring `DefaultUserService` a seam, besides
		// widening the initializer. Declared so, `Feature` builds the tree and the fill calls the initializer `Feature`
		// generates, which compiles.
		let core = """
		public protocol UserService {}

		public struct AnyUserService: UserService {
		    public init(_ userService: any UserService) {
		        self.userService = userService
		    }

		    public let userService: any UserService
		}

		@Instantiable
		public struct Profile: Instantiable {
		    public init(userService: AnyUserService) {
		        self.userService = userService
		    }

		    @Received let userService: AnyUserService
		}

		@Instantiable(generateDependencyTree: true)
		public final class Service: Instantiable {
		    public init(userService: AnyUserService) {
		        self.userService = userService
		    }

		    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) let userService: AnyUserService
		}
		"""
		let feature = """
		import Core

		@Instantiable\(fillIsSeam ? "(generateDependencyTree: true)" : "")
		public final class DefaultUserService: UserService, Instantiable {
		    public init(helper: Helper) {
		        self.helper = helper
		    }

		    @Instantiated let helper: Helper
		}

		@Instantiable
		public final class Helper: Instantiable {
		    package init() {}
		}
		"""
		let app = """
		import Core
		import Feature

		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(service: Service) {
		        self.service = service
		    }

		    @Instantiated let service: Service
		}
		"""
		let modules = [
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [core]),
			ModuleFixture(name: "Feature", packageName: "feat", swiftFileContent: [feature], dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContent: [app], dependencies: ["Core", "Feature"]),
		]
		guard fillIsSeam else {
			await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
				"""
				\(fixtures["Feature"]!["DefaultUserService.swift"]):14:5: error: `Helper`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix, or declare `DefaultUserService` with `generateDependencyTree: true`, so that module `Feature` generates its tree and this module calls the initializer it generates.
				\(fixtures["Feature"]!["DefaultUserService.swift"]):14:5-14:12: fixit: public
				"""
			}) {
				try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
			}
			return
		}
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, Self.generatedFiles(module: "Feature", integration: .moduleInfo, imports: ["Core"], rootFiles: ["DefaultUserService": """
		extension DefaultUserService {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public convenience init() {
		        let helper = Helper()
		        self.init(helper: helper)
		    }
		}

		extension DefaultUserService {
		    public enum __safeDI_DefaultUserService_CBF29CE484222325 {}
		}
		"""]))
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Core", "Feature"], rootFiles: ["Root": """
		extension Root {
		    public convenience init() {
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_65E53210FA860472.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_defaultUserServiceBuilder_Service(_ scope: Service.SafeDIScope_DefaultUserService) -> AnyUserService {
		                switch scope {
		                case .userService:
		                    func __safeDI_userService() -> DefaultUserService {
		                        _ = DefaultUserService.__safeDI_DefaultUserService_CBF29CE484222325.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                        return DefaultUserService()
		                    }
		                    let userService = AnyUserService(__safeDI_userService())
		                    return userService
		                }
		            }
		            return Service(__safeDI_defaultUserServiceBuilder: __safeDI_defaultUserServiceBuilder_Service)
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service)
		    }
		}
		"""]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_renamesBuilderFunctionInsideFill_whenItWouldShadowFillThatCallInsideItPasses() async throws {
		// C4.11: `Profile`'s hole `router` is filled by `__safeDI_routerBuilder`, and `DefaultRouter`, built inside the fill,
		// declares `routerBuilder`, whose builder function would be named the same and shadow the fill where the call of
		// `Flow` inside `DefaultRouter` passes it. That builder function is renamed, as a cycle-closing scope's clash is.
		let feature = [
			"public protocol Router {}",
			seamFixtureType(named: "Analytics", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Gadget", declarations: []),
			seamFixtureType(named: "Profile", declarations: ["@Instantiated let router: any Router", "@Received let analytics: Analytics"]),
			seamFixtureType(named: "Flow", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let profileBuilder: Instantiator<Profile>"]),
		]
		let fulfillers = [Self.fulfillingType(named: "DefaultRouter", fulfilling: "Router", declarations: ["@Instantiated let routerBuilder: Instantiator<Gadget>", "@Instantiated let flowBuilder: Instantiator<Flow>", "@Received let analytics: Analytics"])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let flow: Flow"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_flow() -> Flow {
		            _ = Flow.__safeDI_Flow_8401CCF78D832F75.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_routerBuilder_Flow(_ scope: Flow.SafeDIScope_Router) -> any Router {
		                switch scope {
		                case let .profileBuilder(values, scope): return __safeDI_routerBuilder_Flow_Profile_Scope(scope, analytics: values.analytics)
		                }
		            }
		            func __safeDI_routerBuilder_Flow_Profile_Scope(_ scope: Flow.SafeDIScope_Router.Profile_Scope, analytics: Analytics) -> any Router {
		                switch scope {
		                case .router:
		                    func __safeDI_router() -> DefaultRouter {
		                        func __safeDI_routerBuilder() -> Gadget {
		                            Gadget()
		                        }
		                        let routerBuilder = Instantiator<Gadget>(__safeDI_routerBuilder)
		                        func __safeDI_flowBuilder() -> Flow {
		                            _ = Flow.__safeDI_Flow_8401CCF78D832F75.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                            return Flow(__safeDI_routerBuilder: __safeDI_routerBuilder_Flow)
		                        }
		                        let flowBuilder = Instantiator<Flow>(__safeDI_flowBuilder)
		                        return DefaultRouter(routerBuilder: routerBuilder, flowBuilder: flowBuilder, analytics: analytics)
		                    }
		                    let router: any Router = __safeDI_router()
		                    return router
		                }
		            }
		            return Flow(__safeDI_routerBuilder: __safeDI_routerBuilder_Flow)
		        }
		        let flow: Flow = __safeDI_flow()
		        self.init(flow: flow)
		    }
		}
		"""]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesNestedFillApart_whenCallInsideItPassesEnclosingFillOfSameName() async throws {
		// `Service`'s and `Inner2`'s holes are both labeled `userService`, so both fills would be `__safeDI_userServiceBuilder`.
		// `Inner2`'s fill is declared inside `Service`'s, and the call of `Service` inside it passes `Service`'s fill, which
		// it would shadow, so it is named apart.
		let feature = [
			"public protocol UserService {}\npublic protocol Tracker {}",
			seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let profileBuilder: Instantiator<Profile>"]),
			seamFixtureType(named: "Badge", declarations: ["@Instantiated let userService: any Tracker"]),
			seamFixtureType(named: "Inner2", isSeam: true, declarations: ["@Instantiated let badgeBuilder: Instantiator<Badge>"]),
		]
		let fulfillers = [
			Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Instantiated let inner2: Inner2"]),
			Self.fulfillingType(named: "DefaultTracker", fulfilling: "Tracker", declarations: ["@Instantiated let serviceBuilder: Instantiator<Service>"]),
		]
		let modules = Self.modules(feature: feature, app: fulfillers + [Self.canonicalRoot])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_F88A7C8ABB77D41F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .profileBuilder(_, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope) -> any UserService {
		                switch scope {
		                case .userService:
		                    func __safeDI_userService() -> DefaultUserService {
		                        func __safeDI_inner2() -> Inner2 {
		                            _ = Inner2.__safeDI_Inner2_F8CFCBA0F7FA5766.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                            func __safeDI_trackerBuilder_Inner2(_ scope: Inner2.SafeDIScope_Tracker) -> any Tracker {
		                                switch scope {
		                                case let .badgeBuilder(_, scope): return __safeDI_trackerBuilder_Inner2_Badge_Scope(scope)
		                                }
		                            }
		                            func __safeDI_trackerBuilder_Inner2_Badge_Scope(_ scope: Inner2.SafeDIScope_Tracker.Badge_Scope) -> any Tracker {
		                                switch scope {
		                                case .userService:
		                                    func __safeDI_userService() -> DefaultTracker {
		                                        func __safeDI_serviceBuilder() -> Service {
		                                            _ = Service.__safeDI_Service_F88A7C8ABB77D41F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                                            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
		                                        }
		                                        let serviceBuilder = Instantiator<Service>(__safeDI_serviceBuilder)
		                                        return DefaultTracker(serviceBuilder: serviceBuilder)
		                                    }
		                                    let userService: any Tracker = __safeDI_userService()
		                                    return userService
		                                }
		                            }
		                            return Inner2(__safeDI_trackerBuilder: __safeDI_trackerBuilder_Inner2)
		                        }
		                        let inner2: Inner2 = __safeDI_inner2()
		                        return DefaultUserService(inner2: inner2)
		                    }
		                    let userService: any UserService = __safeDI_userService()
		                    return userService
		                }
		            }
		            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature + fulfillers, app: [Self.canonicalRoot]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesFillApart_whenSeamsOwnTreeFillsInnerSeamsHoleNamedLikeBuilderParameterItTakes() async throws {
		// `Shell`'s tree fills `Inner`'s hole `userService` with `DefaultTracker`, whose call of `Service` passes up
		// `Service`'s hole, also labeled `userService`, so `Shell` takes `__safeDI_userServiceBuilder`. The fill is declared
		// closer than that parameter and would shadow it where the call inside the fill passes it, so it is named apart.
		let feature = [
			"public protocol UserService {}\npublic protocol Tracker {}",
			seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let profileBuilder: Instantiator<Profile>"]),
			seamFixtureType(named: "Badge", declarations: ["@Instantiated let userService: any Tracker"]),
			seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let badgeBuilder: Instantiator<Badge>"]),
		]
		let tracker = Self.fulfillingType(named: "DefaultTracker", fulfilling: "Tracker", declarations: ["@Instantiated let serviceBuilder: Instantiator<Service>"])
		let shell = seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let inner: Inner"])
		let userService = Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: [])
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let shell: Shell"])
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [tracker, shell].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [userService, root].map { "import Feature\nimport Mid\n\n" + $0 }, dependencies: ["Feature", "Mid"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Mid"]?.generatedFiles, Self.generatedFiles(module: "Mid", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Shell": """
		extension Shell {
		    @frozen public enum SafeDIScope_UserService {
		        case inner_trackerBuilder(inner_trackerBuilder_Values, Inner.SafeDIScope_Tracker, SafeDIScope_UserService.DefaultTracker_Scope)

		        public struct inner_trackerBuilder_Values {}

		        @frozen public enum DefaultTracker_Scope {
		            case serviceBuilder(serviceBuilder_Values, Service.SafeDIScope_UserService)

		            public struct serviceBuilder_Values {}
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        let __safeDI_userServiceValues_inner_trackerBuilder = SafeDIScope_UserService.inner_trackerBuilder_Values()
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_E0B7229E32F61E76.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_trackerBuilder_Inner(_ __safeDI_inner_trackerBuilder: Inner.SafeDIScope_Tracker) -> any Tracker {
		                switch __safeDI_inner_trackerBuilder {
		                case let .badgeBuilder(_, scope): return __safeDI_trackerBuilder_Inner_Badge_Scope(scope, __safeDI_inner_trackerBuilder: __safeDI_inner_trackerBuilder)
		                }
		            }
		            func __safeDI_trackerBuilder_Inner_Badge_Scope(_ scope: Inner.SafeDIScope_Tracker.Badge_Scope, __safeDI_inner_trackerBuilder: Inner.SafeDIScope_Tracker) -> any Tracker {
		                switch scope {
		                case .userService:
		                    func __safeDI_userService() -> DefaultTracker {
		                        func __safeDI_serviceBuilder() -> Service {
		                            _ = Service.__safeDI_Service_F88A7C8ABB77D41F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                            return Service(__safeDI_userServiceBuilder: { __safeDI_userServiceBuilder(.inner_trackerBuilder(__safeDI_userServiceValues_inner_trackerBuilder, __safeDI_inner_trackerBuilder, .serviceBuilder(SafeDIScope_UserService.DefaultTracker_Scope.serviceBuilder_Values(), $0))) })
		                        }
		                        let serviceBuilder = Instantiator<Service>(__safeDI_serviceBuilder)
		                        return DefaultTracker(serviceBuilder: serviceBuilder)
		                    }
		                    let userService: any Tracker = __safeDI_userService()
		                    return userService
		                }
		            }
		            return Inner(__safeDI_trackerBuilder: __safeDI_trackerBuilder_Inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension Shell {
		    public enum __safeDI_Shell_D84F55E2023CCACC {}
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature + [tracker, userService]),
			ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: ["import Feature\n\n" + shell], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import Feature\nimport Mid\n\n" + root], dependencies: ["Feature", "Mid"]),
		])
	}

	// MARK: Integrations

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHoleInSeamOfUnnamedModule_whenRunNamesNoModule() async {
		// A run with no target graph and no module name – as the Xcode project plugin runs the tool for a target – gets the
		// error every run without a module name gets, never one that reads a module that depends on this one.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Profile.swift"]):8:5: error: \(Self.holeInSeamOfUnnamedModuleMessage)
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.canonicalFeature,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				moduleMembershipArguments: [],
			)
		}
	}

	@Test(arguments: [["--module-name", "App"], []])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsSeamInlineWithoutBuilder_whenSeamWithHoleIsDeclaredInAdditionalDirectory(moduleMembershipArguments: [String]) async throws {
		// C9.4b, H12 (ii): no run generates the initializer of a seam in a directory a `#SafeDIConfiguration` adds, so it
		// takes no builder and has no hole, named module or not (the Xcode project plugin names none): every tree builds it
		// inline, here with the fulfiller its module sees. With no builder and no fill, this code is the visible build.
		// Each construction of `Service` says so, in the same words whether or not the run names its module.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.seamInAdditionalDirectoryModule + [Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: [])],
			additionalDirectorySwiftFileContent: Self.seamInAdditionalDirectory,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: moduleMembershipArguments,
		)
		#expect(output.dependencyTreeFiles.keys.sorted() == ["Root+SafeDI.swift"])
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_service() -> Service {
		            func __safeDI_profile() -> Profile {
		                let userService: any UserService = DefaultUserService()
		                return Profile(userService: userService)
		            }
		            let profile: Profile = __safeDI_profile()
		            return Service(profile: profile) // Built inline: SafeDI does not know which module declares `Service`, so this tree cannot call the initializer SafeDI generates for it.
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsNoInstantiableFound_whenSeamWithHoleIsDeclaredInAdditionalDirectoryAndNothingFulfillsIt() async {
		// C9.4c, H12 (ii): a tree that builds such a seam inline and sees no fulfiller reports `noInstantiableFound` at the
		// property, as for any type.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["AdditionalDirectory/Profile.swift"]):7:5: error: No @Instantiable type or extension fulfills `UserService`, which @Instantiated property `userService: any UserService` instantiates. Decorate `UserService`, or an extension of it, with @Instantiable, or list `UserService` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it. \(fulfillingDeclarationInTargetNotReadRemedy(for: "UserService"))
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.seamInAdditionalDirectoryModule,
				additionalDirectorySwiftFileContent: Self.seamInAdditionalDirectory,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				moduleMembershipArguments: ["--module-name", "App"],
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderBehindCompileTimeAssertion_whenFulfillingDeclarationIsInInactiveClause() async throws {
		// C9.5: `DefaultUserService` is declared in `Feature` under `#if FOO`, which `Feature`'s run finds inactive, so
		// `Service` takes a builder, and the generated file asserts the clause it took, so a build with `FOO` fails to
		// compile rather than call an initializer that takes a builder it does not.
		let feature = Self.canonicalFeature + [
			"#if FOO\n" + Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let analytics: Analytics"]) + "\n#endif",
		]
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(feature: feature, app: Self.canonicalApp),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		#if FOO
		#error("SafeDI scanned this module assuming `#if FOO` was inactive, but it is active in this compilation. Report the conditions this target compiles with to SafeDITool, as the \\"Reporting active conditions\\" section of the SafeDI manual describes for your build system.")
		#endif

		extension Service {
		    @frozen public enum SafeDIScope_UserService {
		        case profile(profile_Values, SafeDIScope_UserService.Profile_Scope)

		        public struct profile_Values {
		            public let analytics: Analytics
		        }

		        @frozen public enum Profile_Scope {
		            case userService(userService_Values)

		            public struct userService_Values {}
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
		        let analytics = Analytics()
		        let __safeDI_userServiceValues_profile = SafeDIScope_UserService.profile_Values(analytics: analytics)
		        func __safeDI_profile() -> Profile {
		            let userService: any UserService = __safeDI_userServiceBuilder(.profile(__safeDI_userServiceValues_profile, .userService(SafeDIScope_UserService.Profile_Scope.userService_Values())))
		            return Profile(userService: userService, analytics: analytics)
		        }
		        let profile: Profile = __safeDI_profile()
		        self.init(analytics: analytics, profile: profile)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_6E216DA2A3D4C4DA {}
		}
		"""])
	}

	// MARK: Shapes the coverage of the rebase onto row 4b reached

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsNoInstantiableFound_whenSeamsTreeInstantiatesTypeNoNominalTypeCanBe() async {
		// C7.8, H1 (a): no nominal type can be `[Handler]`, so only hand-written code could build it: it is no hole, and the
		// seam's module reports `noInstantiableFound` as it does today.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Service.swift"]):7:5: error: No @Instantiable type or extension fulfills `[Handler]`, which @Instantiated property `handlers: [Handler]` instantiates. Decorate `[Handler]`, or an extension of it, with @Instantiable, or list `[Handler]` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						seamFixtureType(named: "Handler", declarations: []),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let handlers: [Handler]"]),
					],
					app: [Self.canonicalRoot],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsHole_whenForeignSeamsTreeReceivesLazilyInstantiatedPassThrough() async throws {
		// H7 (4): the cycle walk from `Service`'s root, which `App` runs because it fills `Service`'s builder, counts the
		// instance of `session`, a wrapper the tree receives from outside, as received from outside too.
		let feature = [
			Self.userServiceProtocol,
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService", "@Received let session: LazilyInstantiated<Session>"]),
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let profile: Profile"]),
		]
		let fulfillers = [Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let session: Session"])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let session: LazilyInstantiated<Session>", "@Instantiated let service: Service"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_session() -> Session {
		            Session()
		        }
		        let session = LazilyInstantiated<Session>(__safeDI_session)
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_48F2EB3FC4E9B04F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .profile(values, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope, session: values.session)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope, session: LazilyInstantiated<Session>) -> any UserService {
		                switch scope {
		                case .userService:
		                    let userService: any UserService = DefaultUserService(session: session.instance)
		                    return userService
		                }
		            }
		            return Service(__safeDI_session: session, __safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
		        }
		        let service: Service = __safeDI_service()
		        self.init(session: session, service: service)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature + fulfillers, app: [root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsFieldThroughAlias_whenFulfillerAliasesFieldOfScopeStruct() async throws {
		// H7 (2)(1): `DefaultUserService`'s alias of `analytics` reads the field, as inline it reads `Service`'s `analytics`.
		let fulfillers = [Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: [#"@Received(fulfilledByDependencyNamed: "analytics", ofType: Analytics.self) let renamedAnalytics: Analytics"#])]
		let modules = Self.modules(feature: Self.canonicalFeature, app: fulfillers + [Self.canonicalRoot])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let fulfillerPath = try #require(output.modules["App"]).fixtures["DefaultUserService.swift"]
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", integration: .moduleInfo, imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_6E216DA2A3D4C4DA.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
		                switch scope {
		                case let .profile(values, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope, analytics: values.analytics)
		                }
		            }
		            func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope, analytics: Analytics) -> any UserService {
		                switch scope {
		                case .userService:
		                    func __safeDI_userService() -> DefaultUserService {
		                        #sourceLocation(file: "\(fulfillerPath)", line: 9)
		                        let renamedAnalytics: Analytics = analytics
		                        #sourceLocation()
		                        return DefaultUserService(renamedAnalytics: renamedAnalytics)
		                    }
		                    let userService: any UserService = __safeDI_userService()
		                    return userService
		                }
		            }
		            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
		        }
		        let service: Service = __safeDI_service()
		        self.init(service: service)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: Self.canonicalFeature + fulfillers, app: [Self.canonicalRoot]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarry_whenFillReadsSiblingThatRequiresHolesCarrier() async {
		// H3, H7 (2)(2): `Badge` requires `profile`, which holds the hole, so `Service` builds it after `profile` and the
		// struct does not carry it; `DefaultUserService` receives it only if available.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultUserService.swift"]):9:5: error: `DefaultUserService` receives `badge: Badge?`, which `Service`’s tree builds only after it calls the builder for `Profile`’s `userService: any UserService` (case `Profile_Scope.userService` of `userServiceBuilder`), so that builder’s scope does not carry it. Declare an @Instantiable type that fulfills `UserService` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Service.swift"]):9:5: note: `Service` declares `badge: Badge` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						Self.userServiceProtocol,
						seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
						seamFixtureType(named: "Badge", declarations: ["@Received let profile: Profile"]),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let profile: Profile", "@Instantiated let badge: Badge"]),
					],
					app: [Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received(onlyIfAvailable: true) let badge: Badge?"]), Self.canonicalRoot],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarryNamingDeclaringType_whenTypeInSeamsTreeDeclaresSiblingThatRequiresHolesCarrier() async {
		// As above, one level down: `Mid`, which `Service` instantiates, builds `badge` after `profile`, so the error names
		// `Mid` as what builds it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultUserService.swift"]):9:5: error: `DefaultUserService` receives `badge: Badge?`, which `Mid` builds only after `Service`’s tree calls the builder for `Profile`’s `userService: any UserService` (case `Profile_Scope.userService` of `userServiceBuilder`), so that builder’s scope does not carry it. Declare an @Instantiable type that fulfills `UserService` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Mid.swift"]):9:5: note: `Mid` declares `badge: Badge` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						Self.userServiceProtocol,
						seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
						seamFixtureType(named: "Badge", declarations: ["@Received let profile: Profile"]),
						seamFixtureType(named: "Mid", declarations: ["@Instantiated let profile: Profile", "@Instantiated let badge: Badge"]),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let mid: Mid"]),
					],
					app: [Self.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received(onlyIfAvailable: true) let badge: Badge?"]), Self.canonicalRoot],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillClosesCycleInSeamTreeNamingEachType_whenTypeBeneathFulfillerInstantiatesPropertyOfSeamsPath() async {
		// C1.14 one level down: `LoopingUserService` instantiates `Middle`, which instantiates `aBuilder: Instantiator<A>`,
		// which `Service`'s tree is building; the chain names the type that declares each property.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Middle.swift"]):10:5: error: SafeDI cannot fill the builder for `A`’s `userService: any UserService` (case `A_Scope.userService` of `userServiceBuilder`) in `Service`’s dependency tree: `Middle`, beneath `LoopingUserService`, which fills it, instantiates `aBuilder: Instantiator<A>`, which `Service`’s tree is building where it builds `userService` (Service -> aBuilder -> A -> userService -> LoopingUserService -> middle -> Middle -> aBuilder). Code generated outside module `Feature` cannot refer to the function `Service`’s initializer builds `A` with, and building it again would hand it other values than `Service`’s tree holds. Instantiate the seam where `Middle` builds `A` (`@Instantiated let serviceBuilder: Instantiator<Service>`), so the cycle re-enters through the initializer SafeDI generates for `Service`; declare an @Instantiable type that fulfills `UserService` in module `Feature` or a module it lists among its SafeDI dependencies; or give `aBuilder` on `Middle` another label, so the cycle closes at `userService` itself.
			\(fixtures["Feature"]!["Service.swift"]):9:5: note: `Service` instantiates `aBuilder: Instantiator<A>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						Self.userServiceProtocol,
						seamFixtureType(named: "Analytics", declarations: []),
						seamFixtureType(named: "A", declarations: ["@Instantiated let userService: any UserService", "@Received let analytics: Analytics"]),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let aBuilder: Instantiator<A>"]),
					],
					app: [
						Self.fulfillingType(named: "LoopingUserService", fulfilling: "UserService", declarations: ["@Instantiated let middle: Middle"]),
						seamFixtureType(named: "Middle", declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Received let analytics: Analytics"]),
						Self.canonicalRoot,
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillClosesCycleInSeamTreeSuggestingLabelFromSeamsOwnName_whenSeamIsNestedType() async {
		// The suggested instantiator's label is the nested seam's own name, `Service`, since `Outer.Service` is no identifier.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LoopingUserService.swift"]):9:5: error: SafeDI cannot fill the builder for `A`’s `userService: any UserService` (case `A_Scope.userService` of `userServiceBuilder`) in `Outer.Service`’s dependency tree: `LoopingUserService`, which fills it, instantiates `aBuilder: Instantiator<A>`, which `Outer.Service`’s tree is building where it builds `userService` (Outer.Service -> aBuilder -> A -> userService -> LoopingUserService -> aBuilder). Code generated outside module `Feature` cannot refer to the function `Outer.Service`’s initializer builds `A` with, and building it again would hand it other values than `Outer.Service`’s tree holds. Instantiate the seam where `LoopingUserService` builds `A` (`@Instantiated let serviceBuilder: Instantiator<Outer.Service>`), so the cycle re-enters through the initializer SafeDI generates for `Outer.Service`; declare an @Instantiable type that fulfills `UserService` in module `Feature` or a module it lists among its SafeDI dependencies; or give `aBuilder` on `LoopingUserService` another label, so the cycle closes at `userService` itself.
			\(fixtures["Feature"]!["Service.swift"]):8:9: note: `Outer.Service` instantiates `aBuilder: Instantiator<A>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						Self.userServiceProtocol,
						seamFixtureType(named: "A", declarations: ["@Instantiated let userService: any UserService"]),
						"""
						public enum Outer {
						    @Instantiable(generateDependencyTree: true)
						    public struct Service: Instantiable {
						        public init(aBuilder: Instantiator<A>) {
						            self.aBuilder = aBuilder
						        }

						        @Instantiated let aBuilder: Instantiator<A>
						    }
						}
						""",
					],
					app: [
						Self.fulfillingType(named: "LoopingUserService", fulfilling: "UserService", declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Outer.Service"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillClosesCycleInSeamTreeNamingDeclaredProperties_whenSiteIsInsideFillOfPassedUpHole() async {
		// `Shell` passes up the builder of `Inner`'s hole, and `Host` fills it with `DefaultWidget`, whose own hole is the
		// site: the chain walks `Shell`'s `inner` to `Inner`, the call that presented the hole.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultGadget.swift"]):11:5: error: SafeDI cannot fill the builder for `DefaultWidget`’s `gadget: any Gadget` (case `DefaultWidget_Scope.gadget` of `gadgetBuilder`) in `Host`’s dependency tree: `DefaultGadget`, which fills it, instantiates `panelMaker: Instantiator<Panel>`, which `Host`’s tree is building where it builds `gadget` (Host -> shell -> Shell -> inner -> Inner -> panelMaker -> Panel -> widget -> DefaultWidget -> gadget -> DefaultGadget -> panelMaker). Code generated outside module `Upper` cannot refer to the function `Host`’s initializer builds `Panel` with, and building it again would hand it other values than `Host`’s tree holds. Instantiate the seam where `DefaultGadget` builds `Panel` (`@Instantiated let hostBuilder: Instantiator<Host>`), so the cycle re-enters through the initializer SafeDI generates for `Host`, or declare an @Instantiable type that fulfills `Gadget` in module `Upper` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Inner.swift"]):7:5: note: `Inner` instantiates `panelMaker: Instantiator<Panel>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.gadgetCycleModules(
					feature: [
						seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let inner: Inner"]),
					],
					middle: [],
					hostDeclaration: "@Instantiated let shell: Shell",
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillClosesCycleInSeamTreeNamingEveryHop_whenHoleIsPassedUpThroughTwoSeamsAndScope() async {
		// `Shell` reaches `Inner` through `Carrier`, and `Outer` passes `Shell`'s copy on: every call on the way is a hop.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultGadget.swift"]):11:5: error: SafeDI cannot fill the builder for `DefaultWidget`’s `gadget: any Gadget` (case `DefaultWidget_Scope.gadget` of `gadgetBuilder`) in `Host`’s dependency tree: `DefaultGadget`, which fills it, instantiates `panelMaker: Instantiator<Panel>`, which `Host`’s tree is building where it builds `gadget` (Host -> outer -> Outer -> shell -> Shell -> carrier -> Carrier -> inner -> Inner -> panelMaker -> Panel -> widget -> DefaultWidget -> gadget -> DefaultGadget -> panelMaker). Code generated outside module `Upper` cannot refer to the function `Host`’s initializer builds `Panel` with, and building it again would hand it other values than `Host`’s tree holds. Instantiate the seam where `DefaultGadget` builds `Panel` (`@Instantiated let hostBuilder: Instantiator<Host>`), so the cycle re-enters through the initializer SafeDI generates for `Host`, or declare an @Instantiable type that fulfills `Gadget` in module `Upper` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Inner.swift"]):7:5: note: `Inner` instantiates `panelMaker: Instantiator<Panel>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.gadgetCycleModules(
					feature: [
						seamFixtureType(named: "Carrier", declarations: ["@Instantiated let inner: Inner"]),
						seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let carrier: Carrier"]),
						seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated let shell: Shell"]),
					],
					middle: [],
					hostDeclaration: "@Instantiated let outer: Outer",
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillClosesCycleInSeamTreeNamingEveryHop_whenCallThatPassesHoleUpIsInsideFill() async {
		// `Shell` fills `Holder`'s `slot` with `DefaultSlot`, whose call of `Inner` presents the hole `Shell` passes up: the
		// route goes through that fill.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultGadget.swift"]):11:5: error: SafeDI cannot fill the builder for `DefaultWidget`’s `gadget: any Gadget` (case `DefaultWidget_Scope.gadget` of `gadgetBuilder`) in `Host`’s dependency tree: `DefaultGadget`, which fills it, instantiates `panelMaker: Instantiator<Panel>`, which `Host`’s tree is building where it builds `gadget` (Host -> shell -> Shell -> holder -> Holder -> slot -> DefaultSlot -> inner -> Inner -> panelMaker -> Panel -> widget -> DefaultWidget -> gadget -> DefaultGadget -> panelMaker). Code generated outside module `Upper` cannot refer to the function `Host`’s initializer builds `Panel` with, and building it again would hand it other values than `Host`’s tree holds. Instantiate the seam where `DefaultGadget` builds `Panel` (`@Instantiated let hostBuilder: Instantiator<Host>`), so the cycle re-enters through the initializer SafeDI generates for `Host`, or declare an @Instantiable type that fulfills `Gadget` in module `Upper` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Inner.swift"]):7:5: note: `Inner` instantiates `panelMaker: Instantiator<Panel>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.gadgetCycleModules(
					feature: [
						"public protocol Slot {}",
						seamFixtureType(named: "Holder", isSeam: true, declarations: ["@Instantiated let slot: any Slot"]),
					],
					middle: [
						Self.fulfillingType(named: "DefaultSlot", fulfilling: "Slot", declarations: ["@Instantiated let inner: Inner"]),
						seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let holder: Holder"]),
					],
					hostDeclaration: "@Instantiated let shell: Shell",
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillClosesCycleInSeamTreeNotingPathsSpelling_whenPathHoldsLazySpellingOfClosingProperty() async {
		// `DefaultGadget` closes the cycle with `panel: Panel` on `Inner`'s `panel: LazilyInstantiated<Panel>`: the note is at
		// `Inner`'s declaration, in its own spelling.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultGadget.swift"]):10:5: error: SafeDI cannot fill the builder for `DefaultWidget`’s `gadget: any Gadget` (case `DefaultWidget_Scope.gadget` of `gadgetBuilder`) in `Host`’s dependency tree: `DefaultGadget`, which fills it, instantiates `panel: Panel`, which `Host`’s tree is building where it builds `gadget` (Host -> shell -> Shell -> inner -> Inner -> panel -> Panel -> rowMaker -> Row -> widget -> DefaultWidget -> gadget -> DefaultGadget -> panel). Code generated outside module `Upper` cannot refer to the function `Host`’s initializer builds `Panel` with, and building it again would hand it other values than `Host`’s tree holds. Instantiate the seam where `DefaultGadget` builds `Panel` (`@Instantiated let hostBuilder: Instantiator<Host>`), so the cycle re-enters through the initializer SafeDI generates for `Host`, or declare an @Instantiable type that fulfills `Gadget` in module `Upper` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Inner.swift"]):7:5: note: `Inner` instantiates `panel: LazilyInstantiated<Panel>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.fillCycleModules(
					feature: [
						seamFixtureType(named: "Row", declarations: ["@Instantiated let widget: any Widget"]),
						seamFixtureType(named: "Panel", declarations: ["@Instantiated let rowMaker: Instantiator<Row>"]),
						seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let panel: LazilyInstantiated<Panel>"]),
						Self.shellOfInner,
					],
					upper: [Self.widgetWithGadget, Self.hostOfShell],
					app: [Self.gadget(declarations: ["@Instantiated let panel: Panel"]), Self.rootOfHost],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillClosesCycleInSeamTreeNotingNearestDeclaration_whenPathDeclaresClosingPropertyTwice() async {
		// `Inner` and `Row` each declare `pane: any Pane`, built for different types, and the fill closes on the nearest, as
		// generation finds a closer: the note is at `Row`'s.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultGadget.swift"]):10:5: error: SafeDI cannot fill the builder for `DefaultWidget`’s `gadget: any Gadget` (case `DefaultWidget_Scope.gadget` of `gadgetBuilder`) in `Host`’s dependency tree: `DefaultGadget`, which fills it, instantiates `pane: any Pane`, which `Host`’s tree is building where it builds `gadget` (Host -> shell -> Shell -> inner -> Inner -> pane -> OuterPane -> rowMaker -> Row -> pane -> InnerPane -> widgetMaker -> DefaultWidget -> gadget -> DefaultGadget -> pane). Code generated outside module `Upper` cannot refer to the function `Host`’s initializer builds `Pane` with, and building it again would hand it other values than `Host`’s tree holds. Instantiate the seam where `DefaultGadget` builds `Pane` (`@Instantiated let hostBuilder: Instantiator<Host>`), so the cycle re-enters through the initializer SafeDI generates for `Host`, or declare an @Instantiable type that fulfills `Gadget` in module `Upper` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Row.swift"]):7:5: note: `Row` instantiates `pane: any Pane` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.fillCycleModules(
					feature: [
						"public protocol Pane {}",
						seamFixtureType(named: "InnerPane", declarations: ["@Instantiated let widgetMaker: Instantiator<Widget>"], conformances: ", Pane"),
						seamFixtureType(named: "Row", declarations: [#"@Instantiated(fulfilledByType: "InnerPane") let pane: any Pane"#]),
						seamFixtureType(named: "OuterPane", declarations: ["@Instantiated let rowMaker: Instantiator<Row>"], conformances: ", Pane"),
						seamFixtureType(named: "Inner", isSeam: true, declarations: [#"@Instantiated(fulfilledByType: "OuterPane") let pane: any Pane"#]),
						Self.shellOfInner,
					],
					upper: [Self.widgetWithGadget, Self.hostOfShell],
					app: [Self.gadget(declarations: [#"@Instantiated(fulfilledByType: "InnerPane") let pane: any Pane"#]), Self.rootOfHost],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillClosesCycleInSeamTreeNotingHolesDeclaration_whenClosingPropertyIsHoleWhoseFillHoldsSite() async {
		// `DefaultGadget` closes the cycle on `widgetMaker`, the hole `DefaultWidget` fills: `Panel` declares it, and the note
		// has its place.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultGadget.swift"]):10:5: error: SafeDI cannot fill the builder for `DefaultWidget`’s `gadget: any Gadget` (case `DefaultWidget_Scope.gadget` of `gadgetBuilder`) in `Host`’s dependency tree: `DefaultGadget`, which fills it, instantiates `widgetMaker: Instantiator<Widget>`, which `Host`’s tree is building where it builds `gadget` (Host -> shell -> Shell -> inner -> Inner -> panelMaker -> Panel -> widgetMaker -> DefaultWidget -> gadget -> DefaultGadget -> widgetMaker). Code generated outside module `Upper` cannot refer to the function `Host`’s initializer builds `Widget` with, and building it again would hand it other values than `Host`’s tree holds. Instantiate the seam where `DefaultGadget` builds `Widget` (`@Instantiated let hostBuilder: Instantiator<Host>`), so the cycle re-enters through the initializer SafeDI generates for `Host`; declare an @Instantiable type that fulfills `Gadget` in module `Upper` or a module it lists among its SafeDI dependencies; or give `widgetMaker` on `DefaultGadget` another label, so the cycle closes at `gadget` itself.
			\(fixtures["Feature"]!["Panel.swift"]):7:5: note: `Panel` instantiates `widgetMaker: Instantiator<Widget>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.fillCycleModules(
					feature: [
						seamFixtureType(named: "Panel", declarations: ["@Instantiated let widgetMaker: Instantiator<Widget>"]),
						seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let panelMaker: Instantiator<Panel>"]),
						Self.shellOfInner,
					],
					upper: [Self.widgetWithGadget, Self.hostOfShell],
					app: [Self.gadget(declarations: ["@Instantiated let widgetMaker: Instantiator<Widget>"]), Self.rootOfHost],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillClosesCycleInSeamTreeNamingFulfiller_whenFulfillerOfProtocolHoleDeclaresNextHop() async {
		// `DefaultWidget` fills `any Widget` and declares `midMaker`: the chain and the note name it, not the protocol.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultGadget.swift"]):10:5: error: SafeDI cannot fill the builder for `Mid`’s `gadget: any Gadget` (case `Mid_Scope.gadget` of `gadgetBuilder`) in `Host`’s dependency tree: `DefaultGadget`, which fills it, instantiates `midMaker: Instantiator<Mid>`, which `Host`’s tree is building where it builds `gadget` (Host -> shell -> Shell -> inner -> Inner -> panelMaker -> Panel -> widget -> DefaultWidget -> midMaker -> Mid -> gadget -> DefaultGadget -> midMaker). Code generated outside module `Upper` cannot refer to the function `Host`’s initializer builds `Mid` with, and building it again would hand it other values than `Host`’s tree holds. Instantiate the seam where `DefaultGadget` builds `Mid` (`@Instantiated let hostBuilder: Instantiator<Host>`), so the cycle re-enters through the initializer SafeDI generates for `Host`; declare an @Instantiable type that fulfills `Gadget` in module `Upper` or a module it lists among its SafeDI dependencies; or give `midMaker` on `DefaultGadget` another label, so the cycle closes at `gadget` itself.
			\(fixtures["Upper"]!["DefaultWidget.swift"]):9:5: note: `DefaultWidget` instantiates `midMaker: Instantiator<Mid>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.fillCycleModules(
					feature: [
						seamFixtureType(named: "Panel", declarations: ["@Instantiated let widget: any Widget"]),
						seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let panelMaker: Instantiator<Panel>"]),
						Self.shellOfInner,
					],
					upper: [
						Self.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Instantiated let midMaker: Instantiator<Mid>"]),
						seamFixtureType(named: "Mid", declarations: ["@Instantiated let gadget: any Gadget"]),
						Self.hostOfShell,
					],
					app: [Self.gadget(declarations: ["@Instantiated let midMaker: Instantiator<Mid>"]), Self.rootOfHost],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: FillCycleSpelling.allCases, FillCycleHop.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillClosesCycleInSeamTree_whenClosingPropertyIsAnySpellingOfPathsProperty(spelling: FillCycleSpelling, hop: FillCycleHop) async {
		// A lazily instantiated property is validated as the constant it stands for, so a closer in any spelling closes on a
		// declaration in any spelling, wherever the cycle's instantiator is.
		let closerName = hop == .onSeamPath ? "DefaultGadget" : "Helper"
		let closerDeclaration = "@Instantiated let panel: \(spelling.closer)"
		let rowDeclaration = hop == .onSeamPath ? "@Instantiated let rowMaker: Instantiator<Row>" : "@Instantiated let row: Row"
		let rowHop = hop == .onSeamPath ? "rowMaker" : "row"
		let fillHops = hop == .onSeamPath ? "DefaultGadget" : "DefaultGadget -> helperMaker -> Helper"
		let chain = "Host -> shell -> Shell -> inner -> Inner -> panel -> Panel -> \(rowHop) -> Row -> widget -> DefaultWidget -> gadget -> \(fillHops) -> panel"
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["\(closerName).swift"]):10:5: error: \(Self.gadgetCycleMessage(chain: chain, closingProperty: "panel: \(spelling.closer)", closer: hop == .onSeamPath ? nil : "Helper", caseName: "DefaultWidget_Scope.gadget", builderLabel: spelling.path.hasPrefix("Sendable") ? "gadgetSendableBuilder" : "gadgetBuilder"))
			\(fixtures["Feature"]!["Inner.swift"]):7:5: note: `Inner` instantiates `panel: \(spelling.path)` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.fillCycleModules(
					feature: [
						seamFixtureType(named: "Row", declarations: ["@Instantiated let widget: any Widget"]),
						seamFixtureType(named: "Panel", declarations: [rowDeclaration], conformances: ", Sendable"),
						seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let panel: \(spelling.path)"]),
						Self.shellOfInner,
					],
					upper: [Self.widgetWithGadget, Self.hostOfShell],
					app: (hop == .onSeamPath
						? [Self.gadget(declarations: [closerDeclaration])]
						: [Self.gadget(declarations: ["@Instantiated let helperMaker: Instantiator<Helper>"]), seamFixtureType(named: "Helper", declarations: [closerDeclaration])])
						+ [Self.rootOfHost],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsNoInstantiableFoundNamingEveryHop_whenRootCallsSeamThatPassesHoleUpThroughTwoSeamsAndScope() async {
		// `Outer` passes up the builder `Shell` passes up from `Inner`, reached through `Carrier`: the chain has every call.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):9:5: error: No @Instantiable type or extension that module `App` can see fulfills `Widget`, which @Instantiated property `widget: any Widget` instantiates in chain: Root -> Outer -> Shell -> Carrier -> Inner -> Panel. `Inner` generates its dependency tree in module `Feature`, which cannot see one either, so the initializer SafeDI generated for it takes `widgetBuilder`, whose case `Panel_Scope.widget` builds `widget`, and the root `Root` must fill it. Decorate `Widget`, or an extension of it, with @Instantiable; list `Widget` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; \(fulfillingDeclarationInAnotherModuleRemedy)
			\(fixtures["Feature"]!["Panel.swift"]):7:5: note: `Panel` instantiates `widget: any Widget` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: ["public protocol Widget {}"] + Self.typesPassingWidgetUpThroughTwoSeams,
					app: [seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let outer: Outer"])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsNoInstantiableFoundNamingEveryHopAndFulfiller_whenHoleIsInsideFillOfPassedUpHole() async {
		// `Host` fills the passed-up `widget` with `DefaultWidget`, whose hole `gadget` no module fulfills: the chain has
		// every call on the way to the fill, and the type that declares `gadget`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Root.swift"]):10:5: error: No @Instantiable type or extension that module `App` can see fulfills `Gadget`, which @Instantiated property `gadget: any Gadget` instantiates in chain: Root -> Host -> Outer -> Shell -> Carrier -> Inner -> Panel -> DefaultWidget. `Host` generates its dependency tree in module `Upper`, which cannot see one either, so the initializer SafeDI generated for it takes `gadgetBuilder`, whose case `DefaultWidget_Scope.gadget` builds `gadget`, and the root `Root` must fill it. Decorate `Gadget`, or an extension of it, with @Instantiable; list `Gadget` in the `fulfillingAdditionalTypes` of an @Instantiable type that conforms to it; \(fulfillingDeclarationInAnotherModuleRemedy)
			\(fixtures["Upper"]!["DefaultWidget.swift"]):9:5: note: `DefaultWidget` instantiates `gadget: any Gadget` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.fillCycleModules(
					feature: Self.typesPassingWidgetUpThroughTwoSeams,
					upper: [Self.widgetWithGadget, seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let outer: Outer"])],
					app: [Self.rootOfHost],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_drawsFillAsHolesPropertyInDOTTree_whenRootFillsSeamsBuilder() async throws {
		// The DOT tree draws a fill as the hole's property beneath the seam call, and the fulfiller's tree beneath it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(feature: Self.canonicalFeature, app: Self.canonicalApp),
			integration: .moduleInfo,
			writesDOTTrees: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.dotTree == """
		graph SafeDI {
		    ranksep=2
		    Root -- "service: Service"
		    "service: Service" -- "userService: any UserService"
		}
		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Feature` (package `Shop`), with `featureConfiguration`'s files, and `App` (package `Other`), which depends on it.
	static func modules(feature: [String], app: [String], featureConfiguration: [String: String] = [:]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature, swiftFileContentByFilePath: featureConfiguration),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// `Inner`'s hole `widget`, which the seams of `feature` and `middle` pass up to `Host` in `Upper`, which fills it with
	/// `DefaultWidget`, whose own hole `gadget` `App` fills with a type that instantiates `Inner`'s `panelMaker`.
	static func gadgetCycleModules(feature: [String], middle: [String], hostDeclaration: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Widget {}",
				"public protocol Gadget {}",
				seamFixtureType(named: "Panel", declarations: ["@Instantiated let widget: any Widget"]),
				seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let panelMaker: Instantiator<Panel>"]),
			] + feature),
			ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: middle.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(
				name: "Upper",
				packageName: "Other",
				swiftFileContent: [
					fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Instantiated let gadget: any Gadget"]),
					seamFixtureType(named: "Host", isSeam: true, declarations: [hostDeclaration]),
				].map { "import Feature\nimport Middle\n\n" + $0 },
				dependencies: ["Feature", "Middle"],
			),
			ModuleFixture(
				name: "App",
				packageName: "Other",
				swiftFileContent: [
					fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Instantiated let panelMaker: Instantiator<Panel>"]),
					seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let host: Host"]),
				].map { "import Feature\nimport Middle\nimport Upper\n\n" + $0 },
				dependencies: ["Feature", "Middle", "Upper"],
			),
		]
	}

	/// The error of a fill of `ownerOfHole`'s `gadget` in `Host`'s tree, by `DefaultGadget`, that closes a cycle on
	/// `closingProperty`, which builds `builtType`, printing `chain`. `closer`, beneath `DefaultGadget`, declares the property
	/// when it is given, and `DefaultGadget` does otherwise.
	static func gadgetCycleMessage(
		chain: String,
		ownerOfHole: String = "DefaultWidget",
		closingProperty: String = "panelMaker: Instantiator<Panel>",
		builtType: String = "Panel",
		closer: String? = nil,
		closesOnOwnerOfHole: Bool = false,
		caseName: String? = nil,
		builderLabel: String = "gadgetBuilder",
	) -> String {
		let closingLabel = String(closingProperty.prefix { $0 != ":" })
		let closingType = closer ?? "DefaultGadget"
		let closerDescription = closer.map { "`\($0)`, beneath `DefaultGadget`, which fills it," } ?? "`DefaultGadget`, which fills it,"
		return "SafeDI cannot fill the builder for `\(ownerOfHole)`’s `gadget: any Gadget`\(caseName.map { " (case `\($0)` of `\(builderLabel)`)" } ?? "") in `Host`’s dependency tree: \(closerDescription) instantiates `\(closingProperty)`, which `Host`’s tree is building where it builds `gadget` (\(chain)). Code generated outside module `Upper` cannot refer to the function `Host`’s initializer builds `\(builtType)` with, and building it again would hand it other values than `Host`’s tree holds. Instantiate the seam where `\(closingType)` builds `\(builtType)` (`@Instantiated let hostBuilder: Instantiator<Host>`), so the cycle re-enters through the initializer SafeDI generates for `Host`\(closesOnOwnerOfHole ? ";" : ", or") declare an @Instantiable type that fulfills `Gadget` in module `Upper` or a module it lists among its SafeDI dependencies\(closesOnOwnerOfHole ? "; or give `\(closingLabel)` on `\(closingType)` another label, so the cycle closes at `gadget` itself" : "")."
	}

	/// A spelling of the property on a seam's path and a spelling of the property of a fill that closes a cycle on it.
	enum FillCycleSpelling: CaseIterable, Sendable {
		case instanceOnPathLazyCloser
		case instanceOnPathSendableLazyCloser
		case lazyOnPathInstanceCloser
		case sendableLazyOnPathInstanceCloser
		case lazyOnPathSendableLazyCloser
		case instanceOnPathInstanceCloser

		var path: String {
			switch self {
			case .instanceOnPathLazyCloser, .instanceOnPathSendableLazyCloser, .instanceOnPathInstanceCloser:
				"Panel"
			case .lazyOnPathInstanceCloser, .lazyOnPathSendableLazyCloser:
				"LazilyInstantiated<Panel>"
			case .sendableLazyOnPathInstanceCloser:
				"SendableLazilyInstantiated<Panel>"
			}
		}

		var closer: String {
			switch self {
			case .lazyOnPathInstanceCloser, .sendableLazyOnPathInstanceCloser, .instanceOnPathInstanceCloser:
				"Panel"
			case .instanceOnPathLazyCloser:
				"LazilyInstantiated<Panel>"
			case .instanceOnPathSendableLazyCloser, .lazyOnPathSendableLazyCloser:
				"SendableLazilyInstantiated<Panel>"
			}
		}
	}

	/// Where the instantiator of a cycle a fill closes is: between the path's property and the hole, or inside the fill.
	enum FillCycleHop: CaseIterable, Sendable {
		case onSeamPath
		case insideFill
	}

	/// `Feature`, declaring `Widget`, `Gadget` and `feature`; `Upper`, declaring `upper`; and `App`, declaring `app`, each
	/// depending on those before it.
	static func fillCycleModules(feature: [String], upper: [String], app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: ["public protocol Widget {}", "public protocol Gadget {}"] + feature),
			ModuleFixture(name: "Upper", packageName: "Other", swiftFileContent: upper.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\nimport Upper\n\n" + $0 }, dependencies: ["Feature", "Upper"]),
		]
	}

	/// `Panel`'s hole `widget`, of `Inner`, which `Shell` reaches through `Carrier` and passes up, and `Outer` passes up too.
	static let typesPassingWidgetUpThroughTwoSeams = [
		seamFixtureType(named: "Panel", declarations: ["@Instantiated let widget: any Widget"]),
		seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let panelMaker: Instantiator<Panel>"]),
		seamFixtureType(named: "Carrier", declarations: ["@Instantiated let inner: Inner"]),
		seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let carrier: Carrier"]),
		seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated let shell: Shell"]),
	]

	static let shellOfInner = seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let inner: Inner"])
	static let hostOfShell = seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let shell: Shell"])
	static let rootOfHost = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let host: Host"])
	static let widgetWithGadget = fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Instantiated let gadget: any Gadget"])

	static func gadget(declarations: [String]) -> String {
		fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: declarations)
	}

	/// The Swift code blocks of the Manual's section headed `heading`, up to its next heading of any level: the next line
	/// outside a code block that begins with `#`, since a block may hold `#if DEBUG`.
	private static func swiftCodeBlocks(ofSectionTitled heading: String, in manual: String) throws -> [String] {
		let lines = manual.components(separatedBy: "\n")
		let start = try #require(lines.firstIndex(of: heading))
		var blocks = [String]()
		var block: [String]?
		for line in lines[(start + 1)...] {
			if var blockLines = block {
				if line == "```" {
					blocks.append(blockLines.joined(separator: "\n"))
					block = nil
				} else {
					blockLines.append(line)
					block = blockLines
				}
			} else if line == "```swift" {
				block = []
			} else if line.hasPrefix("#") {
				break
			}
		}
		return blocks
	}

	/// The first extension of `seam` in `file`, which holds its scope struct and initializer.
	private static func seamExtension(in file: String, named seam: String = "Service") -> String {
		let start = file.components(separatedBy: "extension \(seam) {\n").dropFirst().first ?? ""
		return "extension \(seam) {\n" + (start.components(separatedBy: "\n}\n").first ?? "") + "\n}"
	}

	/// The builder function of `service` in `file`, unindented to the left margin.
	private static func serviceBuilderFunction(in file: String) -> String {
		let lines = file.components(separatedBy: "\n")
		guard let start = lines.firstIndex(where: { $0.hasSuffix("func __safeDI_service() -> Service {") }) else { return "" }
		let indent = String(lines[start].prefix { $0 == " " })
		guard let end = lines[start...].firstIndex(of: indent + "}") else { return "" }
		return lines[start...end].map { String($0.dropFirst(indent.count)) }.joined(separator: "\n")
	}

	/// C1.16b's graph with a root that instantiates `logger`: `Feature`'s seam `Flow` instantiates `flowDeclarations` and
	/// `profileBuilder`, whose `Profile` instantiates `router: any Router`, which only `App`'s `app` fulfills; `App`'s
	/// `Root` instantiates `logger` and `flow`. The visible modules hold `app` in `Feature`, which builds every value inline.
	private static func reenteredFlowModules(flowDeclarations: [String] = [], app: [String]) -> (modules: [ModuleFixture], visibleModules: [ModuleFixture]) {
		let feature = [
			platformConditionedDeclaration("public protocol Router {}"),
			seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Profile", isFinalClass: true, declarations: ["@Instantiated let router: any Router"]),
			seamFixtureType(named: "Flow", isSeam: true, isFinalClass: true, declarations: flowDeclarations + ["@Instantiated let profileBuilder: Instantiator<Profile>"]),
		]
		let root = seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let logger: Logger", "@Instantiated let flow: Flow"])
		return (modules(feature: feature, app: app + [root]), modules(feature: feature + app, app: [root]))
	}

	/// C1.27's `App`: `DefaultRouter` receives `logger` and instantiates `Middle`, which instantiates `logger` and `Flow` again.
	private static let reenteredFlowShadowingApp = [
		fulfillingType(named: "DefaultRouter", fulfilling: "Router", declarations: ["@Received let logger: Logger", "@Instantiated let middle: Middle"]),
		seamFixtureType(named: "Middle", isFinalClass: true, declarations: ["@Instantiated let logger: Logger", "@Instantiated let flowBuilder: Instantiator<Flow>"]),
	]

	/// C1.23's graph: `Feature`'s seam `Service` instantiates `analytics` and `profileBuilder`, whose `Profile` instantiates
	/// `userService: any UserService`, and `X` receives `analytics` and instantiates `service`; `Mid`'s seam `Shell`
	/// instantiates `analytics` and `xBuilder`, and passes `Service`'s builder up; `App` holds `app` and `Root`, which
	/// declares `rootDeclarations`. The visible modules hold `app` in `Feature`, which builds every value inline.
	private static func reenteredServiceModules(app: [String], rootDeclarations: [String]) -> (modules: [ModuleFixture], visibleModules: [ModuleFixture]) {
		let feature = [
			userServiceProtocol,
			seamFixtureType(named: "Analytics", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let profileBuilder: Instantiator<Profile>"]),
			seamFixtureType(named: "X", declarations: ["@Received let analytics: Analytics", "@Instantiated let service: Service"]),
		]
		let mid = [seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let xBuilder: Instantiator<X>"])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: rootDeclarations)
		return (threeModules(feature: feature, mid: mid, app: app + [root]), threeModules(feature: feature + app, mid: mid, app: [root]))
	}

	/// G4's graph: `Feature`'s seam `Service` instantiates `analytics`, `xBuilder` (an `xBuilderType`), and `profile`, whose
	/// `Profile` instantiates `userService: any UserService`, which only `App`'s `DefaultUserService` (with
	/// `fulfillerDeclarations`) fulfills; `X` declares `x`, and `Other`, a seam, `other` when given; `App`'s `Root`
	/// instantiates `logger` and `service`. The visible modules hold `DefaultUserService` in `Feature`.
	private static func reenteringServiceModules(
		xBuilderType: String = "Instantiator<X>",
		x: [String],
		other: [String]? = nil,
		fulfillerDeclarations: [String] = ["@Received let analytics: Analytics", "@Received let logger: Logger"],
	) -> (modules: [ModuleFixture], visibleModules: [ModuleFixture]) {
		let feature = [
			userServiceProtocol,
			seamFixtureType(named: "Analytics", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService", "@Received let analytics: Analytics"]),
			seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let xBuilder: \(xBuilderType)", "@Instantiated let profile: Profile"]),
			seamFixtureType(named: "X", declarations: x),
		] + (other.map { [seamFixtureType(named: "Other", isSeam: true, declarations: $0)] } ?? [])
		let fulfillers = [fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: fulfillerDeclarations)]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let logger: Logger", "@Instantiated let service: Service"])
		return (modules(feature: feature, app: fulfillers + [root]), modules(feature: feature + fulfillers, app: [root]))
	}

	/// What `App` generates for G4's root when `Service`'s builder reads `analytics` from its struct and `logger` from
	/// `Root`, however `Service`'s tree reaches `Service` again.
	private static let reenteringServiceAppFiles = ["App.swift": generatedFileHeader + """
	#if canImport(Feature)
	import Feature
	#endif

	extension Root {
	    public init() {
	        let logger = Logger()
	        func __safeDI_service() -> Service {
	            _ = Service.__safeDI_Service_4BC95F5D2D6A5D87.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
	            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
	                switch scope {
	                case let .xBuilder(_, scope): return __safeDI_userServiceBuilder_Service_X_Scope(scope)
	                case let .profile(values, scope): return __safeDI_userServiceBuilder_Service_Profile_Scope(scope, analytics: values.analytics)
	                }
	            }
	            func __safeDI_userServiceBuilder_Service_X_Scope(_ scope: Service.SafeDIScope_UserService.X_Scope) -> any UserService {
	                switch scope {
	                case let .serviceBuilder(_, scope): return __safeDI_userServiceBuilder_Service(scope)
	                }
	            }
	            func __safeDI_userServiceBuilder_Service_Profile_Scope(_ scope: Service.SafeDIScope_UserService.Profile_Scope, analytics: Analytics) -> any UserService {
	                switch scope {
	                case .userService:
	                    let userService: any UserService = DefaultUserService(analytics: analytics, logger: logger)
	                    return userService
	                }
	            }
	            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
	        }
	        let service: Service = __safeDI_service()
	        self.init(logger: logger, service: service)
	    }
	}
	"""]

	/// C9.4b's module: a `#SafeDIConfiguration` that adds a directory, `UserService`, and `Root`, which instantiates
	/// `service`.
	private static let seamInAdditionalDirectoryModule = [
		"""
		#SafeDIConfiguration(
		    additionalDirectoriesToInclude: ["$ADDITIONAL_DIRECTORY"]
		)
		""",
		userServiceProtocol,
		seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service"]),
	]

	/// C9.4b's added directory: `Service`, a seam, instantiates `profile`, whose `Profile` instantiates `userService`.
	private static let seamInAdditionalDirectory = [
		seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let profile: Profile"]),
		seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"]),
	]

	/// `Feature` (package `Shop`), `Mid` (package `Other`, importing `Feature`), and `App` (package `Other`, importing both).
	private static func threeModules(feature: [String], mid: [String], app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: mid.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\nimport Mid\n\n" + $0 }, dependencies: ["Feature", "Mid"]),
		]
	}

	/// `Deep`, which declares the canonical hole's owner, `Feature`, which depends on it and declares the seam, and `App`,
	/// which lists only `Feature`, with `appFulfillers`.
	private static func deepOwnerModules(appFulfillers: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Deep", packageName: "Shop", swiftFileContent: [
				seamFixtureType(named: "Analytics", declarations: []),
				seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService", "@Received let analytics: Analytics"]),
				userServiceProtocol,
			]),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: ["import Deep\n\n" + seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let profile: Profile"])], dependencies: ["Deep"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: (appFulfillers + [canonicalRoot]).map { "import Deep\nimport Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// The canonical hole's `Feature`, `Mid`, whose seam `Shell` calls `Service`, `Outer`, whose seam `Top` calls `Shell`, and
	/// `App`, which declares `DefaultUserService` and a root that instantiates `top`, listing `appDependencies`.
	private static func twoSeamModules(appDependencies: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: canonicalFeature),
			ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: ["import Feature\n\n" + seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let service: Service"])], dependencies: ["Feature"]),
			ModuleFixture(name: "Outer", packageName: "Other", swiftFileContent: ["import Feature\nimport Mid\n\n" + seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated let shell: Shell"])], dependencies: ["Feature", "Mid"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"import Feature\nimport Mid\nimport Outer\n\n" + fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let analytics: Analytics"]),
				"import Feature\nimport Mid\nimport Outer\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let top: Top"]),
			], dependencies: appDependencies),
		]
	}

	/// `Deep`, which holds the hole's owner; `Feature`, whose seam `Service` holds the hole; `Mid`, whose seam `Shell` calls
	/// `Service`, and which holds `midDeclarations` but does not list `Deep`; `Impl`, holding `impl`, when `impl` is not
	/// empty; `Outer`, whose seam `Top` calls `Shell`, and which lists `Impl`; and `App`, whose root calls `Top`.
	private static func fulfillingTypeInMidModules(midDeclarations: [String], impl: [String] = [], appDependencies: [String]) -> [ModuleFixture] {
		let implModuleNames = impl.isEmpty ? [] : ["Impl"]
		return [
			ModuleFixture(name: "Deep", packageName: "Shop", swiftFileContent: [userServiceProtocol, seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService"])]),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: ["import Deep\n\n" + seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let profile: Profile"])], dependencies: ["Deep"]),
			ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: midDeclarations + ["import Feature\n\n" + seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let service: Service"])], dependencies: ["Feature"]),
		] + implModuleNames.map { ModuleFixture(name: $0, packageName: "Other", swiftFileContent: impl, dependencies: ["Deep"]) } + [
			ModuleFixture(name: "Outer", packageName: "Other", swiftFileContent: ["import Mid\n\n" + seamFixtureType(named: "Top", isSeam: true, declarations: ["@Instantiated let shell: Shell"])], dependencies: ["Mid"] + implModuleNames),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import Outer\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let top: Top"])], dependencies: appDependencies),
		]
	}

	/// A declaration, for a module whose compile can import `Deep`, that fulfills the hole of `fulfillingTypeInMidModules`.
	private static let defaultUserService = "import Deep\n\n" + fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: [])

	/// How the error at a root's module tells it to list a module, under each build system that lists modules by hand.
	private static let listModuleRemedy = "list its `<name>_safedi` target in this target’s `safedi_deps` under Bazel, list its module in the `dependencies:` of this target’s `SafeDI.preCompileScript` under Tuist, or list its `.safedi` file in the file you pass to `--dependent-module-info-file-path` in a custom build."

	/// The source of `UserService`, a public protocol.
	private static let userServiceProtocol = "public protocol UserService {}"

	/// The error at the canonical hole when the run that generates `Service` names no module: one wording for every such
	/// run, the Xcode project plugin's included.
	private static let holeInSeamOfUnnamedModuleMessage = "`Service` generates its dependency tree, and `Profile`’s @Instantiated property `userService: any UserService` in it instantiates `UserService`, which no @Instantiable declaration this module reads fulfills. SafeDI does not know which module declares `Service`, so it cannot know what that module’s callers see, and the initializer it generates cannot take a builder for `userService`. Declare an @Instantiable type that fulfills `UserService` in this module or in a module it depends on, or declare `Service` without `generateDependencyTree: true`. For the initializer to take a builder instead, SafeDI must know `Service`’s module. Under the Xcode project plugin, which cannot name modules, move the modules and the root into a local Swift package that the app target depends on. A SafeDITool run by hand names this module with `--module-name`."

	/// The canonical hole (`h01`): `Service`, the seam, instantiates `analytics` then `profile`; `Profile` instantiates
	/// `userService: any UserService` and receives `analytics`.
	private static let canonicalFeature = [
		seamFixtureType(named: "Analytics", declarations: []),
		seamFixtureType(named: "Profile", declarations: ["@Instantiated let userService: any UserService", "@Received let analytics: Analytics"]),
		seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let profile: Profile"]),
		userServiceProtocol,
	]

	/// `App`'s root, which instantiates `service`, and `DefaultUserService`, which fulfills `UserService` and receives
	/// `analytics`.
	private static let canonicalApp = [
		fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let analytics: Analytics"]),
		seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service"]),
	]

	/// What `Feature` generates for `Service`, the canonical hole's seam.
	private static let canonicalServiceCode = """
	extension Service {
	    @frozen public enum SafeDIScope_UserService {
	        case profile(profile_Values, SafeDIScope_UserService.Profile_Scope)

	        public struct profile_Values {
	            public let analytics: Analytics
	        }

	        @frozen public enum Profile_Scope {
	            case userService(userService_Values)

	            public struct userService_Values {}
	        }
	    }

	    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
	    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
	    public init(__safeDI_userServiceBuilder: @escaping (SafeDIScope_UserService) -> any UserService) {
	        let analytics = Analytics()
	        let __safeDI_userServiceValues_profile = SafeDIScope_UserService.profile_Values(analytics: analytics)
	        func __safeDI_profile() -> Profile {
	            let userService: any UserService = __safeDI_userServiceBuilder(.profile(__safeDI_userServiceValues_profile, .userService(SafeDIScope_UserService.Profile_Scope.userService_Values())))
	            return Profile(userService: userService, analytics: analytics)
	        }
	        let profile: Profile = __safeDI_profile()
	        self.init(analytics: analytics, profile: profile)
	    }
	}

	extension Service {
	    public enum __safeDI_Service_6E216DA2A3D4C4DA {}
	}
	"""

	/// `App`'s root of the canonical hole, which instantiates `service`.
	private static let canonicalRoot = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service"])

	/// Holes beneath an `Instantiator` (`ServiceI`), a `SendableInstantiator` (`ServiceS`), and two nested ones
	/// (`ServiceN`), each instantiating `analytics` and a non-`Sendable` `session`, the owner instantiating a
	/// non-`Sendable` `cache` before its hole.
	private static let wrapperFeature = [
		"""
		public protocol UserService: Sendable {}
		""",
		seamFixtureType(named: "Analytics", isFinalClass: true, declarations: [], conformances: ", Sendable"),
		seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
		seamFixtureType(named: "Cache", isFinalClass: true, declarations: []),
		seamFixtureType(named: "ProfileI", declarations: ["@Forwarded let name: String", "@Instantiated let cache: Cache", "@Instantiated let userService: any UserService", "@Received let analytics: Analytics"]),
		seamFixtureType(named: "ServiceI", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let session: Session", "@Instantiated let profileBuilder: Instantiator<ProfileI>"]),
		seamFixtureType(named: "ProfileS", declarations: ["@Forwarded let name: String", "@Instantiated let cache: Cache", "@Instantiated let userService: any UserService", "@Instantiated let analytics: Analytics"]),
		seamFixtureType(named: "ServiceS", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let session: Session", "@Instantiated let profileBuilder: SendableInstantiator<ProfileS>"]),
		seamFixtureType(named: "ProfileN", declarations: ["@Instantiated let userService: any UserService", "@Instantiated let analytics: Analytics", "@Received let title: String"]),
		seamFixtureType(named: "Screen", declarations: ["@Forwarded let title: String", "@Instantiated let cache: Cache", "@Instantiated let profileBuilder: SendableInstantiator<ProfileN>"]),
		seamFixtureType(named: "ServiceN", isSeam: true, declarations: ["@Instantiated let analytics: Analytics", "@Instantiated let session: Session", "@Instantiated let screenBuilder: SendableInstantiator<Screen>"]),
	]

	/// `DefaultUserService`, which fulfills `UserService` and receives `analytics`.
	private static let wrapperFulfillers = [
		fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let analytics: Analytics"]),
	]

	private static let wrapperRoot = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let serviceI: ServiceI", "@Instantiated let serviceS: ServiceS", "@Instantiated let serviceN: ServiceN"])

	/// The canonical hole's `Feature`, `Mid` (package `Other`), whose seam `Shell` instantiates `theme` and `service`, and
	/// `App`, whose root instantiates `shell`, with `appFulfillers`.
	private static func passUpModules(appFulfillers: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: canonicalFeature),
			ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [
				"import Feature\n\n" + seamFixtureType(named: "Theme", declarations: []),
				"import Feature\n\n" + seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let service: Service"]),
			], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: (appFulfillers + [seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let shell: Shell"])]).map { "import Feature\nimport Mid\n\n" + $0 }, dependencies: ["Feature", "Mid"]),
		]
	}

	/// A public `@Instantiable` struct named `name` that fulfills `fulfilledType`, with `declarations`.
	static func fulfillingType(named name: String, fulfilling fulfilledType: String, declarations: [String]) -> String {
		seamFixtureType(named: name, declarations: declarations, conformances: ", \(fulfilledType)")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [\(fulfilledType).self])\n")
	}

	/// The comment a call to `seam`, a seam of `Feature`, carries under `integration`.
	static func pluginComment(_ integration: MultiModuleIntegration, seam: String) -> String {
		integration.seamCallComment(type: seam, declaringModule: "Feature")
	}

	/// The files `integration` generates for `module`, whose roots and seams generate `rootFiles`' code, by type, each
	/// file importing `imports`: one combined file under `.moduleInfo`, one file per type under `.swiftPackagePlugin`.
	static func generatedFiles(module: String, integration: MultiModuleIntegration, imports: [String], rootFiles: [String: String]) -> [String: String] {
		let importLines = imports.isEmpty ? "" : imports.map { "#if canImport(\($0))\nimport \($0)\n#endif\n" }.joined() + "\n"
		switch integration {
		case .moduleInfo:
			return ["\(module).swift": generatedFileHeader + importLines + rootFiles.sorted { $0.key < $1.key }.map(\.value).joined(separator: "\n\n")]
		case .swiftPackagePlugin:
			return Dictionary(uniqueKeysWithValues: rootFiles.map { ("\($0.key)+SafeDI.swift", generatedFileHeader + importLines + $0.value) })
		}
	}

	/// Expects the values `output`, the run of `modules`, builds for each root of `App` to equal those the run of
	/// `visibleModules` builds, the same graph with every fulfilling declaration in the seam's module.
	private mutating func expectValuesEqualVisibleBuild(
		_ output: MultiModuleTestOutput,
		modules: [ModuleFixture],
		visibleModules: [ModuleFixture],
		probes: [DifferentialValueProbe] = [DifferentialValueProbe("Root()")],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		guard compileVerificationIsEnabled else { return }
		let visibleOutput = try await executeSafeDIToolMultiModuleTest(modules: visibleModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: Self.differentialValuePath(of: output, modules: modules),
			knownRight: Self.differentialValuePath(of: visibleOutput, modules: visibleModules),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	/// The path the comparator builds from `output`, the run of `modules`: each module's files as the harness wrote
	/// them, and the files the tool generated for it.
	static func differentialValuePath(of output: MultiModuleTestOutput, modules: [ModuleFixture]) throws -> DifferentialValuePath {
		try DifferentialValuePath(output: output, modules: modules)
	}

	/// Expects `generatedFiles` to equal `expected`, recording the files generated when they do not, so a failure shows
	/// the output in full.
	private func expectGeneratedFiles(_ generatedFiles: [String: String]?, _ expected: [String: String], sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(generatedFiles == expected, sourceLocation: sourceLocation)
		if let generatedFiles, generatedFiles != expected {
			Issue.record(Comment(rawValue: generatedFiles.sorted { $0.key < $1.key }.map { "=== \($0.key)\n\($0.value)" }.joined(separator: "\n")), sourceLocation: sourceLocation)
		}
	}
}
