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

/// A public mock whose tree reaches a type only through that type's public mock in a third module, which builds a value
/// when passed `nil`, takes the value as `T? = nil`, builds it when passed `nil`, and binds the `T` it builds or is
/// passed. Its root level holds that `T`, so a fill in a calling mock that requires the value reads it, as the production
/// twin, whose seam takes the value as a required parameter, does. Each mirror test runs one fixture as the calling mock and
/// as its twin, and compares the calling mock’s values with the twin’s.
struct SafeDIToolCallingMockInnerPublicMockValueTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – the adopter’s shape

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesCallingMockThatFillsPlaceFromCallersValue_whenOnlyInnerPublicMockRequiresValue() async throws {
		let modules = Self.modules(rootAttribute: "@Instantiable(isRoot: true, generateMock: true)", calledTypeAttribute: Self.twinCalledTypes)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(output.modules["Base"]?.generatedFiles == Self.expectedBaseFiles)
		#expect(output.modules["InnerMod"]?.generatedFiles == Self.expectedInnerModFiles)
		#expect(output.modules["Feat"]?.generatedFiles == Self.expectedFeatFiles)
		#expect(output.modules["App"]?.generatedFiles == Self.expectedAppFiles)
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation)
		#expect(compilation.failure == nil, "\(compilation.failure.map { "\($0)" } ?? "")")
		guard compilation.failure == nil else { return }
		// The same types in one module, `Root` a root: what inline builds. `Live` receives `Root`’s `db`, as each of `K` and
		// `Inner` does.
		let inline = Self.inlineModules(liveReceive: "@Received let db: Db", liveInitializerParameter: "db: Db")
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inline, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let comparison = try #require(try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: inlineOutput, modules: inline),
			probes: [DifferentialValueProbe(name: "App.Root", expression: "App.Root.mock()", knownRightExpression: "App.Root()")],
			filesToDelete: &filesToDelete,
		))
		for difference in comparison.differences {
			Issue.record("The calling mock builds other values than inline for \(difference)\n\(comparison.report)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesCallingMockThatCompiles_whenOnlyInnerPublicMockRequiresValueUnderSwiftPackagePlugin() async throws {
		// The SwiftPM plugin lists every module beneath in each module’s CSV, so `Feat` builds `Db` as it does under Bazel, and
		// the calling mock compiles. Its files differ from the module-info flow’s only by the comments that name the types
		// SafeDI counts as `public` (`GraphFuzzerOracle.integrationSpecificCommentLines`), which a run that reads every module omits.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(rootAttribute: "@Instantiable(isRoot: true, generateMock: true)", calledTypeAttribute: Self.twinCalledTypes),
			integration: .swiftPackagePlugin,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)

		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation)
		#expect(compilation.failure == nil, "\(compilation.failure.map { "\($0)" } ?? "")")
	}

	// MARK: Tests – fills where the twin fills

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_fillsPlaceAsTwin_whenFillRequiresValueOnlyInnerPublicMockRequires(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async throws {
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "a fill requiring the value only an inner public mock requires",
			mock: Self.modules(rootAttribute: caller.attribute, calledTypeAttribute: calledTypes.attribute),
			twin: Self.modules(rootAttribute: Self.twinCaller, calledTypeAttribute: Self.twinCalledTypes),
			callerIsPublic: caller == .public,
		), seed: 0)

		Self.expectFillsAsTwin(result)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_fillsPlaceAsTwin_whenListedCallersFillRequiresValueOnlyInnerPublicMockRequires() async throws {
		let configuration = "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Root\"])\n"
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "a listed caller’s fill requiring the value only an inner public mock requires",
			mock: Self.modules(rootAttribute: "@Instantiable", calledTypeAttribute: Self.twinCalledTypes),
			twin: Self.modules(rootAttribute: Self.twinCaller, calledTypeAttribute: Self.twinCalledTypes),
			callerIsPublic: false,
			mockConfiguration: configuration,
		), seed: 0)

		Self.expectFillsAsTwin(result)
	}

	@Test(arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_fillsPlaceAsTwin_whenFillReceivesValueOnlyIfAvailableThatOnlyInnerPublicMockRequires(caller: CallingMockCaller) async throws {
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "a fill receiving only if available the value only an inner public mock requires",
			mock: Self.modules(rootAttribute: caller.attribute, calledTypeAttribute: Self.twinCalledTypes, liveReceive: "@Received(onlyIfAvailable: true) let db: Db?", liveInitializerParameter: "db: Db?"),
			twin: Self.modules(rootAttribute: Self.twinCaller, calledTypeAttribute: Self.twinCalledTypes, liveReceive: "@Received(onlyIfAvailable: true) let db: Db?", liveInitializerParameter: "db: Db?"),
			callerIsPublic: caller == .public,
		), seed: 0)

		Self.expectFillsAsTwin(result)
	}

	@Test(arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_fillsPlaceAsTwin_whenNoTypeInCalledTypesTreeReceivesValueOnlyIfAvailable(caller: CallingMockCaller) async throws {
		// Without `K`, only the call of `Inner`’s public mock receives `db` in `F`’s mock tree.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "a fill requiring the value only an inner public mock receives",
			mock: Self.modules(rootAttribute: caller.attribute, calledTypeAttribute: Self.twinCalledTypes, featDeclaresReader: false),
			twin: Self.modules(rootAttribute: Self.twinCaller, calledTypeAttribute: Self.twinCalledTypes, featDeclaresReader: false),
			callerIsPublic: caller == .public,
		), seed: 0)

		Self.expectFillsAsTwin(result)
	}

	@Test(arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_fillsPlaceAsTwin_whenCalledTypeDeclaresPlaceBeforeTypesThatReceiveValue(caller: CallingMockCaller) async throws {
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "a fill requiring the value only an inner public mock requires, its place declared first",
			mock: Self.modules(rootAttribute: caller.attribute, calledTypeAttribute: Self.twinCalledTypes, featDeclaresPlaceFirst: true),
			twin: Self.modules(rootAttribute: Self.twinCaller, calledTypeAttribute: Self.twinCalledTypes, featDeclaresPlaceFirst: true),
			callerIsPublic: caller == .public,
		), seed: 0)

		Self.expectFillsAsTwin(result)
	}

	@Test(arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_fillsPlaceAsTwin_whenValueOnlyInnerPublicMockRequiresIsExistential(caller: CallingMockCaller) async throws {
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			named: "a fill requiring the existential value only an inner public mock requires",
			mock: Self.modules(rootAttribute: caller.attribute, calledTypeAttribute: Self.twinCalledTypes, dbType: "any Database"),
			twin: Self.modules(rootAttribute: Self.twinCaller, calledTypeAttribute: Self.twinCalledTypes, dbType: "any Database"),
			callerIsPublic: caller == .public,
		), seed: 0)

		Self.expectFillsAsTwin(result)
	}

	// MARK: Tests – the twin’s error, reported for the calling mock

	@Test(arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsError_whenInnerTypeInstantiatesValueFillRequires(caller: CallingMockCaller) async throws {
		// `Inner` builds its own `db`, so only `K` receives one in `F`’s tree, only if available: the twin’s `F` takes
		// `db: Db?`, which `Live`’s required receive cannot read, and so does `F`’s public mock, which builds no `db`.
		let diagnostics = { (fixtures: [String: FixturePaths]) in
			"""
			\(fixtures["App"]!["AppTypes.swift"]):12:5: error: `Live` receives `db: Db`, which SafeDI hands the builder for `F`’s `api: any Api` (`api` of `apiBuilder`) only as `db: Db?`, since `F`’s tree receives it only if available. Declare `@Received let db: Db` on `F`, or receive it on `Live` with `@Received(onlyIfAvailable: true) let db: Db?`.
			\(fixtures["Feat"]!["FeatTypes.swift"]):24:5: note: `K` receives `db: Db?` here.
			"""
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.modules(rootAttribute: Self.twinCaller, calledTypeAttribute: Self.twinCalledTypes, innerInstantiatesValue: true), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		// The calling mock reports the twin’s error at the twin’s site. Its note names `F`’s declaration rather than `K`’s
		// receive, a defect of the note that the remedy wording work owns, so only the error is compared here.
		do {
			_ = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(rootAttribute: caller.attribute, calledTypeAttribute: Self.twinCalledTypes, innerInstantiatesValue: true), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
			Issue.record("Did not throw error!")
		} catch let error as SafeDIToolMultiModuleTestError {
			#expect(error.moduleName == "App")
			// Each side is bound apart: Xcode 26.0’s Swift 6.2 (swiftlang-6.2.0) gives up type-checking the comparison written
			// as one expression inside `#expect` ("unable to type-check this expression in reasonable time"); Linux’s Swift 6.2.4
			// accepts it.
			let reportedFirstLine: String? = "\(error.underlyingError)".split(separator: "\n").first.map(String.init)
			let expectedFirstLine: String? = diagnostics(error.fixtures).split(separator: "\n").first.map(String.init)
			#expect(reportedFirstLine == expectedFirstLine)
		}
	}

	// MARK: Tests – the mock condition off

	@Test(arguments: [MockConditionCaller.internal, .public, .listed])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesDebugBuildsCode_whenBuildLeavesMockConditionInactive(caller: MockConditionCaller) async throws {
		// A release build of `App` compiles no generated mock, which is under `#if DEBUG`; the tool generates the same code as a
		// debug build does, and reports nothing.
		let rootAttribute = switch caller {
		case .internal:
			"@Instantiable(isRoot: true, generateMock: true)"
		case .public:
			"@Instantiable(isRoot: true, generateMock: .public)"
		case .listed:
			"@Instantiable(isRoot: true)"
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(
				rootAttribute: rootAttribute,
				calledTypeAttribute: Self.twinCalledTypes,
				appConfiguration: caller == .listed ? "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Root\"])\n" : nil,
				appIsReleaseConfiguration: true,
			),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["App"]?.generatedFiles == (caller == .public ? Self.expectedPublicRootAppFiles : Self.expectedAppFiles))
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The caller’s attribute line in its production twin.
	private static let twinCaller = "@Instantiable(generateDependencyTree: true)"
	/// A called type’s attribute line in the production twin: a seam as well as a public mock.
	private static let twinCalledTypes = CalledTypeDeclaration.seamAndPublicMock.attribute

	/// Expects `result`’s twin to have its graph’s intended outcome and the calling mock to mirror it: no place passed up,
	/// no failure, and, where compile verification is on, the twin’s values.
	private static func expectFillsAsTwin(_ result: GraphFuzzerCallingMockResult, sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")", sourceLocation: sourceLocation)
		#expect(result.passUps.map(\.label) == [], sourceLocation: sourceLocation)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")", sourceLocation: sourceLocation)
		#expect(result.comparedValues == compileVerificationIsEnabled, sourceLocation: sourceLocation)
	}

	/// The calling-mock check’s graph of `mock` and `twin`, whose caller is `Root`, accepted by the twin, which takes no
	/// parameter, and whose probe builds `Root` through its mock and through the twin’s seam initializer.
	private static func graph(
		named name: String,
		mock: [ModuleFixture],
		twin: [ModuleFixture],
		callerIsPublic: Bool,
		mockConfiguration: String? = nil,
	) -> GraphFuzzerCallingMockGraph {
		func files(of modules: [ModuleFixture]) -> [GraphFuzzerCallingMockGraph.File] {
			modules.map { module in
				GraphFuzzerCallingMockGraph.File(module: module.name, dependencies: module.dependencies, content: module.swiftFileContentByFilePath["\(module.name)Types.swift"] ?? "")
			}
		}
		return GraphFuzzerCallingMockGraph(
			name: name,
			mockFiles: files(of: mock),
			twinFiles: files(of: twin),
			callerTypeName: "Root",
			callerIsPublic: callerIsPublic,
			mockConfiguration: mockConfiguration,
			flatParameterLabels: [],
			implementationIsVisible: true,
			expectedTwinInitializerLabels: [],
			expectedPassUpLabels: [],
			expectedTwinErrorSite: nil,
			valueProbes: [DifferentialValueProbe(name: "App.Root", expression: "App.Root.mock()", knownRightExpression: "App.Root()")],
		)
	}

	/// The adopter’s shape: `F`’s public mock reaches `Inner` only through `Inner`’s public mock, whose internal initializer
	/// `F`’s module cannot call, and `Inner`’s public mock takes `db: Db? = nil`, which `K` receives only if available too.
	/// `App` cannot call `F`’s internal initializer either, so `Root`’s mock calls `F`’s public mock, and `Live`, which fills
	/// `F`’s `api`, receives `db`.
	/// - Parameters:
	///   - dbType: How every type spells `db`’s type: `Db`, or `any Database`, which `Db` fulfills.
	///   - innerInstantiatesValue: Whether `Inner` instantiates its own `db`, rather than receiving it.
	///   - featDeclaresReader: Whether `F` instantiates `K`, which receives `db` only if available.
	///   - featDeclaresPlaceFirst: Whether `F` declares `api` before the types that receive `db`.
	private static func modules(
		rootAttribute: String,
		calledTypeAttribute: String,
		dbType: String = "Db",
		liveReceive: String? = nil,
		liveInitializerParameter: String? = nil,
		innerInstantiatesValue: Bool = false,
		featDeclaresReader: Bool = true,
		featDeclaresPlaceFirst: Bool = false,
		appConfiguration: String? = nil,
		appIsReleaseConfiguration: Bool = false,
	) -> [ModuleFixture] {
		let featProperties = featDeclaresPlaceFirst
			? [(label: "api", type: "any Api")] + (featDeclaresReader ? [(label: "k", type: "K")] : []) + [(label: "inner", type: "Inner")]
			: (featDeclaresReader ? [(label: "k", type: "K")] : []) + [(label: "api", type: "any Api"), (label: "inner", type: "Inner")]
		let optionalDbType = dbType.hasPrefix("any ") ? "(\(dbType))?" : "\(dbType)?"
		var featLines = [
			"import Base",
			"import InnerMod",
			"import SafeDI",
			"",
			calledTypeAttribute,
			"public struct F: Instantiable {",
			"    init(\(featProperties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {",
		]
		featLines += featProperties.map { "        self.\($0.label) = \($0.label)" }
		featLines.append("    }")
		featLines.append("")
		featLines += featProperties.map { "    @Instantiated let \($0.label): \($0.type)" }
		featLines.append("}")
		if featDeclaresReader {
			featLines += [
				"",
				"@Instantiable",
				"public struct K: Instantiable {",
				"    public init(db: \(optionalDbType)) {",
				"        self.db = db",
				"    }",
				"",
				"    @Received(onlyIfAvailable: true) let db: \(optionalDbType)",
				"}",
			]
		}
		let baseDeclaration = if dbType == "Db" {
			"""
			@Instantiable
			public final class Db: Instantiable {
			    public init() {}
			}
			"""
		} else {
			"""
			public protocol Database: AnyObject {}

			@Instantiable(fulfillingAdditionalTypes: [(any Database).self])
			public final class Db: Database, Instantiable {
			    public init() {}
			}
			"""
		}
		return [
			ModuleFixture(name: "Base", packageName: "Base", swiftFileContentByFilePath: [
				"BaseTypes.swift": """
				import SafeDI

				public protocol Api {}

				\(baseDeclaration)
				""",
			]),
			ModuleFixture(name: "InnerMod", packageName: "InnerMod", swiftFileContentByFilePath: [
				"InnerModTypes.swift": """
				import Base
				import SafeDI

				\(calledTypeAttribute)
				public struct Inner: Instantiable {
				    init(db: \(dbType), api: any Api) {
				        self.db = db
				        self.api = api
				    }

				    \(innerInstantiatesValue ? "@Instantiated" : "@Received") let db: \(dbType)
				    @Instantiated let api: any Api
				}
				""",
			], dependencies: ["Base"]),
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: [
				"FeatTypes.swift": featLines.joined(separator: "\n"),
			], dependencies: ["Base", "InnerMod"]),
			ModuleFixture(
				name: "App",
				packageName: "App",
				swiftFileContentByFilePath: [
					"AppTypes.swift": """
					import Base
					import Feat
					import InnerMod
					import SafeDI

					@Instantiable(fulfillingAdditionalTypes: [Api.self])
					public struct Live: Api, Instantiable {
					    public init(\(liveInitializerParameter ?? "db: \(dbType)")) {
					        self.db = db
					    }

					    \(liveReceive ?? "@Received let db: \(dbType)")
					}

					\(rootAttribute)
					public struct Root: Instantiable {
					    public init(db: \(dbType), f: F) {
					        self.db = db
					        self.f = f
					    }

					    @Instantiated let db: \(dbType)
					    @Instantiated let f: F
					}
					""",
				].merging(appConfiguration.map { ["SafeDIConfiguration.swift": $0] } ?? [:]) { first, _ in first },
				dependencies: ["Base", "InnerMod", "Feat"],
				isReleaseConfiguration: appIsReleaseConfiguration,
			),
		]
	}

	/// The adopter’s types in one module, `Root` a root and every other type a plain `@Instantiable`: what inline builds.
	private static func inlineModules(liveReceive: String, liveInitializerParameter: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI

				public protocol Api {}

				@Instantiable
				public final class Db: Instantiable {
				    public init() {}
				}

				@Instantiable
				public struct Inner: Instantiable {
				    init(db: Db, api: any Api) {
				        self.db = db
				        self.api = api
				    }

				    @Received let db: Db
				    @Instantiated let api: any Api
				}

				@Instantiable
				public struct F: Instantiable {
				    init(k: K, api: any Api, inner: Inner) {
				        self.k = k
				        self.api = api
				        self.inner = inner
				    }

				    @Instantiated let k: K
				    @Instantiated let api: any Api
				    @Instantiated let inner: Inner
				}

				@Instantiable
				public struct K: Instantiable {
				    public init(db: Db?) {
				        self.db = db
				    }

				    @Received(onlyIfAvailable: true) let db: Db?
				}

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public struct Live: Api, Instantiable {
				    public init(\(liveInitializerParameter)) {
				        self.db = db
				    }

				    \(liveReceive)
				}

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(db: Db, f: F) {
				        self.db = db
				        self.f = f
				    }

				    @Instantiated let db: Db
				    @Instantiated let f: F
				}
				""",
			]),
		]
	}

	// MARK: Expected output

	private static let expectedBaseFiles = [
		"Base.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif


		""",
	]

	private static let expectedInnerModFiles = [
		"InnerMod.swift": generatedFileHeader + """
		#if canImport(Base)
		import Base
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Inner {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let api: (Db) -> __safeDI_Built

		        public init(api: @escaping (Db) -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _ in __safeDI_builder() })
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_db db: Db, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let api: any Api = __safeDI_apiBuilder.api(db)
		        self.init(db: db, api: api)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_FCE996E4E101DCD3 {}
		}

		#if DEBUG
		extension Inner {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct api_Values {
		            public let db: Db
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let api: (api_Values) -> __safeDI_Built

		            public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                self.api = api
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(api: { _ in __safeDI_builder() })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            db: (() -> Db)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                db: db
		            )
		        }

		        public var db: (() -> Db)? { __safeDI_storage.db }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                db: (() -> Db)?
		            ) {
		                self.db = db
		            }

		            let db: (() -> Db)?
		        }
		    }

		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        db: Db? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Inner {
		        Inner.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), db: db, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Inner.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        db: Db? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Inner {
		        let db = if let db { db } else if let safeDIBuilder = safeDIOverrides.db { safeDIBuilder() } else { Db() }
		        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values(db: db))
		        return Inner(db: db, api: api)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_mock_A60A0D925D102B18 {}
		}
		#endif
		""",
	]

	/// `F`’s public mock takes `db: Db? = nil`, binds the `Db` it is passed or builds, and its root level holds that `Db`.
	private static let expectedFeatFiles = [
		"Feat.swift": generatedFileHeader + """
		#if canImport(Base)
		import Base
		#endif
		#if canImport(InnerMod)
		import InnerMod
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension F {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let api: (LazilyInstantiated<Db>, K, Inner) -> __safeDI_Built
		        public let inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>

		        public init(api: @escaping (LazilyInstantiated<Db>, K, Inner) -> __safeDI_Built, inner: Inner.__safeDI_ApiCarrier<__safeDI_Built>) {
		            self.api = api
		            self.inner = inner
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _, _, _ in __safeDI_builder() }, inner: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_db: @autoclosure @escaping () -> Db, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let db = LazilyInstantiated<Db>(__safeDI_db)
		        let k = K(db: db.instance)
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_FCE996E4E101DCD3.self // If this line does not compile, compile the code SafeDI generates for module InnerMod into InnerMod: under Bazel, add InnerMod’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Inner(__safeDI_db: db.instance, __safeDI_apiBuilder: __safeDI_apiBuilder.inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        let api: any Api = __safeDI_apiBuilder.api(db, k, inner)
		        self.init(k: k, api: api, inner: inner)
		    }
		}

		extension F {
		    public enum __safeDI_F_B6D9BD662693F0E4 {}
		}

		#if DEBUG
		extension F {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct api_Values {
		            public let db: Db
		            public let k: K
		            public let inner: Inner
		        }

		        nonisolated public struct inner_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let api: (api_Values) -> __safeDI_Built
		            public let inner: (inner_Values) -> Inner.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>

		            public init(api: @escaping (api_Values) -> __safeDI_Built, inner: @escaping (inner_Values) -> Inner.SafeDIMockScope_Api.__safeDI_Builder<__safeDI_Built>) {
		                self.api = api
		                self.inner = inner
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(api: { _ in __safeDI_builder() }, inner: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            db: (() -> Db)? = nil,
		            k: ((Db?) -> K)? = nil,
		            inner: Inner.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                db: db,
		                k: k,
		                inner: inner
		            )
		        }

		        public var db: (() -> Db)? { __safeDI_storage.db }
		        public var k: ((Db?) -> K)? { __safeDI_storage.k }
		        public var inner: Inner.SafeDIOverrides { __safeDI_storage.inner }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                db: (() -> Db)?,
		                k: ((Db?) -> K)?,
		                inner: Inner.SafeDIOverrides
		            ) {
		                self.db = db
		                self.k = k
		                self.inner = inner
		            }

		            let db: (() -> Db)?
		            let k: ((Db?) -> K)?
		            let inner: Inner.SafeDIOverrides
		        }
		    }

		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        db: Db? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> F {
		        F.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), db: db, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: F.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        db: Db? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> F {
		        let db = if let db { db } else if let safeDIBuilder = safeDIOverrides.db { safeDIBuilder() } else { Db() }
		        let k = if let safeDIBuilder = safeDIOverrides.k { safeDIBuilder(db) } else { K(db: db) }
		        _ = Inner.__safeDI_Inner_mock_A60A0D925D102B18.self // If this line does not compile, compile the code SafeDI generates for module InnerMod into InnerMod: under Bazel, add InnerMod’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let inner = Inner.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.inner(SafeDIMockScope_Api.inner_Values()), db: db, safeDIOverrides: safeDIOverrides.inner)
		        let api: any Api = __safeDI_apiBuilder.api(SafeDIMockScope_Api.api_Values(db: db, k: k, inner: inner))
		        return F(k: k, api: api, inner: inner)
		    }
		}

		extension F {
		    public enum __safeDI_F_mock_AEA8D6564306A707 {}
		}
		#endif
		""",
	]

	/// `Root`’s mock passes its own `db` to `F`’s public mock, whose root level hands it to `Live`.
	private static let expectedAppFiles = [
		"App.swift": generatedFileHeader + """
		#if canImport(Base)
		import Base
		#endif
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(InnerMod)
		import InnerMod
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
		            .init(api: { scope_db in
		                let db = scope_db
		                let api: any Api = Live(db: db)
		                return api
		            })
		        }
		        let db = Db()
		        func __safeDI_f() -> F {
		            _ = F.__safeDI_F_B6D9BD662693F0E4.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_F() -> F.__safeDI_ApiCarrier<any Api> {
		                .init(
		                    api: { scope_db, scope_k, scope_inner in
		                        let api: any Api = Live(db: db)
		                        return api
		                    },
		                    inner: __safeDI_apiBuilder_Inner()
		                )
		            }
		            return F(__safeDI_db: db, __safeDI_apiBuilder: __safeDI_apiBuilder_F())
		        }
		        let f: F = __safeDI_f()
		        self.init(db: db, f: f)
		    }
		}

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            db: (() -> Db)? = nil,
		            f: F.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                db: db,
		                f: f
		            )
		        }

		        var db: (() -> Db)? { __safeDI_storage.db }
		        var f: F.SafeDIOverrides { __safeDI_storage.f }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                db: (() -> Db)?,
		                f: F.SafeDIOverrides
		            ) {
		                self.db = db
		                self.f = f
		            }

		            let db: (() -> Db)?
		            let f: F.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let db = if let safeDIBuilder = safeDIOverrides.db { safeDIBuilder() } else { Db() }
		        func __safeDI_f() -> F {
		            func __safeDI_apiBuilder_F() -> F.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(
		                    api: { scope in
		                        let db = scope.db
		                        let api: any Api = Live(db: db)
		                        return api
		                    },
		                    inner: { _ in __safeDI_apiBuilder_Inner() }
		                )
		            }
		            func __safeDI_apiBuilder_Inner() -> Inner.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(api: { scope in
		                    let db = scope.db
		                    let api: any Api = Live(db: db)
		                    return api
		                })
		            }
		            _ = F.__safeDI_F_mock_AEA8D6564306A707.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_F(), db: db, safeDIOverrides: safeDIOverrides.f)
		        }
		        let f: F = __safeDI_f()
		        return Root(db: db, f: f)
		    }
		}
		#endif
		""",
	]

	/// `Root`’s public mock, which differs from `expectedAppFiles` only in its access and its guard.
	private static let expectedPublicRootAppFiles = [
		"App.swift": generatedFileHeader + """
		#if canImport(Base)
		import Base
		#endif
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(InnerMod)
		import InnerMod
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
		            .init(api: { scope_db in
		                let db = scope_db
		                let api: any Api = Live(db: db)
		                return api
		            })
		        }
		        let db = Db()
		        func __safeDI_f() -> F {
		            _ = F.__safeDI_F_B6D9BD662693F0E4.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_F() -> F.__safeDI_ApiCarrier<any Api> {
		                .init(
		                    api: { scope_db, scope_k, scope_inner in
		                        let api: any Api = Live(db: db)
		                        return api
		                    },
		                    inner: __safeDI_apiBuilder_Inner()
		                )
		            }
		            return F(__safeDI_db: db, __safeDI_apiBuilder: __safeDI_apiBuilder_F())
		        }
		        let f: F = __safeDI_f()
		        self.init(db: db, f: f)
		    }
		}

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            db: (() -> Db)? = nil,
		            f: F.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                db: db,
		                f: f
		            )
		        }

		        public var db: (() -> Db)? { __safeDI_storage.db }
		        public var f: F.SafeDIOverrides { __safeDI_storage.f }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                db: (() -> Db)?,
		                f: F.SafeDIOverrides
		            ) {
		                self.db = db
		                self.f = f
		            }

		            let db: (() -> Db)?
		            let f: F.SafeDIOverrides
		        }
		    }

		    // SafeDI counts `Api` as `public`: no module it reads declares it narrower. If `Api` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        Root.__safeDI_mock(apiBuilder: apiBuilder, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let db = if let safeDIBuilder = safeDIOverrides.db { safeDIBuilder() } else { Db() }
		        func __safeDI_f() -> F {
		            func __safeDI_apiBuilder_F() -> F.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(
		                    api: { scope in
		                        let db = scope.db
		                        let api: any Api = Live(db: db)
		                        return api
		                    },
		                    inner: { _ in __safeDI_apiBuilder_Inner() }
		                )
		            }
		            func __safeDI_apiBuilder_Inner() -> Inner.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(api: { scope in
		                    let db = scope.db
		                    let api: any Api = Live(db: db)
		                    return api
		                })
		            }
		            _ = F.__safeDI_F_mock_AEA8D6564306A707.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F.__safeDI_mock(apiBuilder: __safeDI_apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_F(), db: db, safeDIOverrides: safeDIOverrides.f)
		        }
		        let f: F = __safeDI_f()
		        return Root(db: db, f: f)
		    }
		}

		extension Root {
		    public enum __safeDI_Root_mock_BEDDA3C65C73F485 {}
		}
		#endif
		""",
	]
}
