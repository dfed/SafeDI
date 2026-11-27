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

/// A calling mock whose call of another module’s public mock fills a place that the called type builds inside a
/// `@Sendable` function, with a fill that reads a value the called type receives. The called mock binds that value at its
/// root, from the optional parameter the calling mock passes its own nearest declaration to, so the fill reads the
/// caller’s, as the production twin’s fill reads the caller’s value that the seam takes as a parameter.
struct SafeDIToolCallingMockSendablePlaceTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – the fill reads the caller’s value

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsSendablePlaceWithCallersValue_whenCalledTypeReceivesValueFillReads() async throws {
		// `F` receives `db` and builds `K`, which instantiates the hole `api`, inside a `SendableInstantiator`. `Root`’s mock
		// passes its own `db` to `F`’s public mock, which binds it at its root, so the fill of `api` reads `Root`’s `db`, as
		// the twin’s fill and the same types built inline read it.
		let graph = Self.graph(caller: .internal, calledTypes: .seamAndPublicMock)
		let modules = graph.modules(.mock)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["Feat"]?.generatedFiles == ["Feat.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension F {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_K<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
		        public let k: @Sendable () -> __safeDI_ApiCarrier_K<__safeDI_Built>

		        public init(k: @escaping @Sendable () -> __safeDI_ApiCarrier_K<__safeDI_Built>) {
		            self.k = k
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(k: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_db db: Db, __safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
		        @inline(never) @Sendable nonisolated func __safeDI_k() -> K {
		            let __safeDI_apiSendableBuilder_k = __safeDI_apiSendableBuilder.k()
		            let api: any Api = __safeDI_apiSendableBuilder_k.api()
		            return K(api: api)
		        }
		        let k = SendableInstantiator<K>(__safeDI_k)
		        self.init(db: db, k: k)
		    }
		}

		extension F {
		    public enum __safeDI_F_BCA2D47B8701CAB6 {}
		}

		#if DEBUG
		extension Db {
		    public static func mock() -> Db {
		        Db.__safeDI_mock()
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock() -> Db {
		        Db()
		    }
		}

		extension Db {
		    public enum __safeDI_Db_mock_CBF29CE484222325 {}
		}
		#endif

		#if DEBUG
		extension F {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public enum K_Scope {
		            nonisolated public struct api_Values {}

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
		    }

		    nonisolated public enum SafeDISendableMockScope_Api {
		        nonisolated public struct k_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let k: @Sendable (k_Values) -> SafeDIMockScope_Api.K_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(k: @escaping @Sendable (k_Values) -> SafeDIMockScope_Api.K_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.k = k
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		                self.init(k: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            db: (() -> Db)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                k: nil,
		                db: db
		            )
		        }

		        init(
		            k: (@Sendable (any Api) -> K)? = nil,
		            db: (() -> Db)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                k: k,
		                db: db
		            )
		        }

		        var k: (@Sendable (any Api) -> K)? { __safeDI_storage.k }
		        public var db: (() -> Db)? { __safeDI_storage.db }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                k: (@Sendable (any Api) -> K)?,
		                db: (() -> Db)?
		            ) {
		                self.k = k
		                self.db = db
		            }

		            let k: (@Sendable (any Api) -> K)?
		            let db: (() -> Db)?
		        }
		    }

		    public static func mock(
		        apiSendableBuilder: @escaping @Sendable () -> any Api,
		        db: Db? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> F {
		        F.__safeDI_mock(apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder), db: db, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiSendableBuilder __safeDI_apiSendableBuilder: F.SafeDISendableMockScope_Api.__safeDI_Builder<any Api>,
		        db: Db? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> F {
		        let db = if let db { db } else if let safeDIBuilder = safeDIOverrides.db { safeDIBuilder() } else { Db() }
		        let __safeDI_k__safeDIBuilder = safeDIOverrides.k
		        @Sendable nonisolated func __safeDI_k() -> K {
		            let __safeDI_apiSendableBuilder_k = __safeDI_apiSendableBuilder.k(SafeDISendableMockScope_Api.k_Values())
		            let api: any Api = __safeDI_apiSendableBuilder_k.api(SafeDIMockScope_Api.K_Scope.api_Values())
		            return if let safeDIBuilder = __safeDI_k__safeDIBuilder { safeDIBuilder(api) } else { K(api: api) }
		        }
		        let k = SendableInstantiator<K>(__safeDI_k)
		        return F(db: db, k: k)
		    }
		}

		extension F {
		    public enum __safeDI_F_mock_FB934F1CC08C8BFE {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == Self.expectedAppFiles(caller: .internal))
		try await expectValuesEqualInline(of: graph, output: output, modules: modules)
	}

	@Test(arguments: SendablePlaceCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_fillsSendablePlaceAsTwin_whenCalledTypeReceivesValueFillReads(caller: SendablePlaceCaller, calledTypes: CalledTypeDeclaration) async throws {
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(caller: caller, calledTypes: calledTypes), seed: 0)

		Self.expectFillsAsTwin(result)
	}

	@Test(arguments: SendablePlaceCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_fillsSendablePlaceAsTwin_whenTypeInCalledTypesTreeReceivesValueFillReads(caller: SendablePlaceCaller, calledTypes: CalledTypeDeclaration) async throws {
		// `K` receives `db` and `F` does not: `F`’s public mock binds it at its root all the same, and its seam takes it as
		// a parameter that it passes through to `K`.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			caller: caller,
			calledTypes: calledTypes,
			fDeclarations: ["@Instantiated let k: SendableInstantiator<K>"],
			kDeclarations: ["@Received let db: Db", "@Instantiated let api: any Api"],
		), seed: 0)

		Self.expectFillsAsTwin(result)
	}

	@Test(arguments: SendablePlaceCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_fillsSendablePlaceAsTwin_whenFillReceivesValueOnlyIfAvailable(caller: SendablePlaceCaller, calledTypes: CalledTypeDeclaration) async throws {
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			caller: caller,
			calledTypes: calledTypes,
			liveDeclarations: ["@Received(onlyIfAvailable: true) let db: Db?"],
		), seed: 0)

		Self.expectFillsAsTwin(result)
	}

	@Test(arguments: SendablePlaceCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_fillsSendablePlaceAsTwin_whenFillReadsValueCalledTypeAliases(caller: SendablePlaceCaller, calledTypes: CalledTypeDeclaration) async throws {
		// `F` receives `db` as the caller’s `appDb`, and the fill reads `appDb`, which `F`’s mock binds at its root.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			caller: caller,
			calledTypes: calledTypes,
			fDeclarations: [#"@Received(fulfilledByDependencyNamed: "appDb", ofType: Db.self) let db: Db"#, "@Instantiated let k: SendableInstantiator<K>"],
			liveDeclarations: ["@Received let appDb: Db"],
			rootDeclarations: ["@Instantiated let appDb: Db", "@Instantiated let f: F"],
		), seed: 0)

		Self.expectFillsAsTwin(result)
	}

	@Test(arguments: SendablePlaceCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_fillsSendablePlaceAsTwin_whenCalledTypeReceivesValueLazily(caller: SendablePlaceCaller, calledTypes: CalledTypeDeclaration) async throws {
		// `F` receives `db` in a `SendableLazilyInstantiated`, and the fill reads the caller’s wrapper. A call of a public
		// mock hands it the wrapper’s instance, which it wraps again, a known difference from the twin (“A lazy value a call
		// hands over” in `public-mock-builders.md`), so the probe describes `Root`’s wrapper and what the fill builds, not
		// `F`’s own wrapper.
		let probe = "{ let root = App.Root.%@; return (root.db, root.f.k.instantiate()) }()"
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			caller: caller,
			calledTypes: calledTypes,
			fDeclarations: ["@Received let db: SendableLazilyInstantiated<Db>", "@Instantiated let k: SendableInstantiator<K>"],
			liveDeclarations: ["@Received let db: SendableLazilyInstantiated<Db>"],
			rootDeclarations: ["@Instantiated let db: SendableLazilyInstantiated<Db>", "@Instantiated let f: F"],
			valueProbes: [DifferentialValueProbe(name: "Root", expression: probe.replacingOccurrences(of: "%@", with: "mock()"), knownRightExpression: probe.replacingOccurrences(of: "App.Root.%@", with: "App.Root()"))],
		), seed: 0)

		Self.expectFillsAsTwin(result)
	}

	@Test(arguments: SendablePlaceCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesCallingMock_whenBuildLeavesMockConditionInactive(caller: SendablePlaceCaller) async throws {
		let graph = Self.graph(caller: caller, calledTypes: .seamAndPublicMock)
		let modules = graph.modules(.mock).map { module in
			guard module.name == graph.callerModule else { return module }
			return ModuleFixture(
				name: module.name,
				packageName: module.packageName,
				swiftFileContentByFilePath: module.swiftFileContentByFilePath,
				dependencies: module.dependencies,
				isReleaseConfiguration: true,
			)
		}
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == Self.expectedAppFiles(caller: caller))
	}

	// MARK: Tests – the twin’s error, reported for the calling mock

	@Test(arguments: SendablePlaceCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_reportsTwinsError_whenFillReadsValueCalledTypeInstantiates(caller: SendablePlaceCaller, calledTypes: CalledTypeDeclaration) async throws {
		// `F` instantiates `db` outside the `@Sendable` function that builds `K`: neither the twin nor the calling mock can
		// hand the fill `F`’s `db`.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			caller: caller,
			calledTypes: calledTypes,
			fDeclarations: ["@Instantiated let db: Db", "@Instantiated let k: SendableInstantiator<K>"],
			expectedTwinErrorSite: (file: "App/AppTypes.swift", declaration: "@Received let db: Db"),
		), seed: 0)

		Self.expectReportsTwinsError(result)
	}

	@Test(arguments: SendablePlaceCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_reportsTwinsError_whenFillReadsAliasCalledTypeReceives(caller: SendablePlaceCaller, calledTypes: CalledTypeDeclaration) async throws {
		// `F` receives `db` as the caller’s `appDb`, and the fill reads `db`, which the caller does not declare.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			caller: caller,
			calledTypes: calledTypes,
			fDeclarations: [#"@Received(fulfilledByDependencyNamed: "appDb", ofType: Db.self) let db: Db"#, "@Instantiated let k: SendableInstantiator<K>"],
			rootDeclarations: ["@Instantiated let appDb: Db", "@Instantiated let f: F"],
			expectedTwinErrorSite: (file: "App/AppTypes.swift", declaration: "@Received let db: Db"),
		), seed: 0)

		Self.expectReportsTwinsError(result)
	}

	// MARK: Tests – a place another called type passes up

	@Test(arguments: SendablePlaceCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_fillsPassedUpSendablePlaceAsTwin_whenPassingTypeReceivesValueFillReads(caller: SendablePlaceCaller, calledTypes: CalledTypeDeclaration) async throws {
		// `G` receives `db` and builds `K`, whose `api` is the hole, inside a `SendableInstantiator`; `F` receives `db`, calls
		// `G`’s public mock and passes the place up to `Root`. `G`’s mock binds the `db` `F`’s mock passes, which is `Root`’s.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.passedUpGraph(caller: caller, calledTypes: calledTypes, fDeclarations: ["@Received let db: Db", "@Instantiated let g: G"]), seed: 0)

		Self.expectFillsAsTwin(result)
	}

	@Test(arguments: SendablePlaceCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_reportsTwinsError_whenTypePassingSendablePlaceUpInstantiatesValueFillReads(caller: SendablePlaceCaller, calledTypes: CalledTypeDeclaration) async throws {
		// As above, with `F` instantiating the `db` it passes `G`, which `Root`’s fill cannot read.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.passedUpGraph(
			caller: caller,
			calledTypes: calledTypes,
			fDeclarations: ["@Instantiated let db: Db", "@Instantiated let g: G"],
			expectedTwinErrorSite: (file: "App/AppTypes.swift", declaration: "@Received let db: Db"),
		), seed: 0)

		Self.expectReportsTwinsError(result)
	}

	// MARK: Tests – a value the caller does not hold

	@Test(arguments: SendablePlaceCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsCallerHoldsNoValue_whenFillReadsOnlyIfAvailableValueCallerDoesNotInstantiate(caller: SendablePlaceCaller) async {
		// `Root` declares no `db`, and `Live` reads it only if available, so `Root`’s mock passes `F`’s public mock its own
		// optional override, `nil` unless set, and `F`’s mock builds a `db` of its own, which the fill could not read. The twin,
		// whose seam takes `db` as a parameter, accepts the graph: a deliberate gap (`seam-holes.md`). The remedies work:
		// `Root` instantiating `db` is `generate_fillsSendablePlaceAsTwin_whenFillReceivesValueOnlyIfAvailable`’s graph, and
		// fulfilling `Api` in `Feat` is `generate_fillsSendablePlaceAsTwin_whenCalledTypesModuleFulfillsPlace`’s.
		let graph = Self.graph(
			caller: caller,
			calledTypes: .seamAndPublicMock,
			liveDeclarations: ["@Received(onlyIfAvailable: true) let db: Db?"],
			rootDeclarations: ["@Instantiated let f: F"],
		)
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["AppTypes.swift"]):10:5: error: `Live` receives `db: Db?`, which `F`’s public mock binds from the `db` its caller passes, outside the `@Sendable` function that builds `k: SendableInstantiator<K>`, and SafeDI hands the builder for `K`’s `api: any Api` (`api` of `apiSendableBuilder`) only what that function binds. Its caller passes no `db: Db` of its own, so the mock may build its own. Instantiate `db` above the call of `F`’s public mock, so the call passes it and the builder’s caller reads it, or declare an @Instantiable type that fulfills `Api` in module `Feat` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feat"]!["FeatTypes.swift"]):17:5: note: `F` receives `db: Db` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: graph.modules(.mock), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: SendablePlaceCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_fillsSendablePlaceAsTwin_whenCalledTypesModuleFulfillsPlace(caller: SendablePlaceCaller, calledTypes: CalledTypeDeclaration) async throws {
		// The second remedy of the error above: `Feat` declares `Live`, so `F`’s mock fills the place itself, reading its own
		// `db`, and the twin’s seam takes `db` as a parameter. A `.public` mock takes `db`, which its tree receives, as a
		// parameter of its own.
		let result = try await GraphFuzzerCallingMockCheck.run(Self.graph(
			caller: caller,
			calledTypes: calledTypes,
			liveDeclarations: ["@Received(onlyIfAvailable: true) let db: Db?"],
			rootDeclarations: ["@Instantiated let f: F"],
			declaresLiveInCalledTypesModule: true,
			flatParameterLabels: caller == .public ? ["db"] : [],
			expectedTwinInitializerLabels: ["db"],
			valueProbes: [DifferentialValueProbe(name: "Root", expression: "App.Root.mock()", knownRightExpression: "App.Root(__safeDI_db: Feat.Db())")],
		), seed: 0)

		Self.expectFillsAsTwin(result)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The adopter’s graph: module `Feat` declares `F`, which receives `db` and builds `K`, which instantiates the hole
	/// `api`, inside a `SendableInstantiator`, and module `App` declares `Live`, which fills `api` reading `db`, and the
	/// caller `Root`, which instantiates `db` and `F`. `K` and `F`’s initializer are internal, so `Root`’s mock calls `F`’s
	/// public mock.
	private static func graph(
		caller: SendablePlaceCaller,
		calledTypes: CalledTypeDeclaration,
		fDeclarations: [String] = ["@Received let db: Db", "@Instantiated let k: SendableInstantiator<K>"],
		kDeclarations: [String] = ["@Instantiated let api: any Api"],
		liveDeclarations: [String] = ["@Received let db: Db"],
		rootDeclarations: [String] = ["@Instantiated let db: Db", "@Instantiated let f: F"],
		declaresLiveInCalledTypesModule: Bool = false,
		flatParameterLabels: Set<String> = [],
		expectedTwinInitializerLabels: [String] = [],
		expectedTwinErrorSite: (file: String, declaration: String)? = nil,
		valueProbes: [DifferentialValueProbe] = [DifferentialValueProbe(name: "Root", expression: "App.Root.mock()", knownRightExpression: "App.Root()")],
	) -> GraphFuzzerCallingMockGraph {
		let live = """
		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public final class Live: Api, Instantiable {
		\(typeBody(initializerAccess: "public ", declarations: liveDeclarations))
		}
		"""
		func feat(calledTypeAttribute: String) -> String {
			var content = """
			import SafeDI

			public protocol Api: AnyObject {}

			@Instantiable(generateMock: .public)
			public final class Db: Instantiable, Sendable {
			    public init() {}
			}

			\(calledTypeAttribute)
			public final class F: Instantiable {
			\(typeBody(initializerAccess: "", declarations: fDeclarations))
			}

			@Instantiable
			final class K: Instantiable {
			\(typeBody(initializerAccess: "", declarations: kDeclarations))
			}
			"""
			if declaresLiveInCalledTypesModule {
				content += "\n\n" + live
			}
			return content
		}
		func app(callerAttribute: String) -> String {
			var content = "import Feat\nimport SafeDI\n\n"
			if !declaresLiveInCalledTypesModule {
				content += live + "\n\n"
			}
			content += """
			\(callerAttribute)
			public final class Root: Instantiable {
			\(typeBody(initializerAccess: "public ", declarations: rootDeclarations))
			}
			"""
			return content
		}
		// The twin declares the called types seams, however the calling mock’s form declares them.
		return GraphFuzzerCallingMockGraph(
			name: "a fill reading, inside a `@Sendable` function of the called type, a value the called type receives",
			mockFiles: [
				GraphFuzzerCallingMockGraph.File(module: "Feat", dependencies: [], content: feat(calledTypeAttribute: calledTypes.attribute)),
				GraphFuzzerCallingMockGraph.File(module: "App", dependencies: ["Feat"], content: app(callerAttribute: caller.attribute)),
			],
			twinFiles: [
				GraphFuzzerCallingMockGraph.File(module: "Feat", dependencies: [], content: feat(calledTypeAttribute: CalledTypeDeclaration.seamAndPublicMock.attribute)),
				GraphFuzzerCallingMockGraph.File(module: "App", dependencies: ["Feat"], content: app(callerAttribute: "@Instantiable(generateDependencyTree: true)")),
			],
			callerTypeName: "Root",
			callerIsPublic: caller == .public,
			mockConfiguration: caller == .listed ? "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Root\"])\n" : nil,
			flatParameterLabels: flatParameterLabels,
			implementationIsVisible: true,
			expectedTwinInitializerLabels: expectedTwinErrorSite == nil ? expectedTwinInitializerLabels : nil,
			expectedPassUpLabels: [],
			expectedTwinErrorSite: expectedTwinErrorSite,
			valueProbes: expectedTwinErrorSite == nil ? valueProbes : nil,
		)
	}

	/// What module `App` generates for the adopter's graph with `caller`: the calling mock, which reads `Root`'s `db` in the
	/// fill of `api` and passes it to `F`'s public mock. A listed caller's mock is internal, as an internal caller's is.
	private static func expectedAppFiles(caller: SendablePlaceCaller) -> [String: String] {
		switch caller {
		case .internal, .listed:
			["App.swift": generatedFileHeader + """
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
			        apiSendableBuilder: (@Sendable () -> any Api)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let db = if let safeDIBuilder = safeDIOverrides.db { safeDIBuilder() } else { Db() }
			        func __safeDI_f() -> F {
			            @Sendable nonisolated func __safeDI_apiSendableBuilder_F() -> F.SafeDISendableMockScope_Api.__safeDI_Builder<any Api> {
			                .init(k: { _ in __safeDI_apiBuilder_F_K_Scope() })
			            }
			            @Sendable nonisolated func __safeDI_apiBuilder_F_K_Scope() -> F.SafeDIMockScope_Api.K_Scope.__safeDI_Builder<any Api> {
			                .init(api: { _ in
			                    let api: any Api = Live(db: db)
			                    return api
			                })
			            }
			            _ = F.__safeDI_F_mock_FB934F1CC08C8BFE.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "F", declaringModule: "Feat"))
			            return F.__safeDI_mock(apiSendableBuilder: apiSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiSendableBuilder_F(), db: db, safeDIOverrides: safeDIOverrides.f)
			        }
			        let f: F = __safeDI_f()
			        return Root(db: db, f: f)
			    }
			}
			#endif
			"""]
		case .public:
			["App.swift": generatedFileHeader + """
			#if canImport(Feat)
			import Feat
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

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

			    public static func mock(
			        apiSendableBuilder: (@Sendable () -> any Api)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        Root.__safeDI_mock(apiSendableBuilder: apiSendableBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        apiSendableBuilder __safeDI_apiSendableBuilder: (@Sendable () -> any Api)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let db = if let safeDIBuilder = safeDIOverrides.db { safeDIBuilder() } else { Db() }
			        func __safeDI_f() -> F {
			            @Sendable nonisolated func __safeDI_apiSendableBuilder_F() -> F.SafeDISendableMockScope_Api.__safeDI_Builder<any Api> {
			                .init(k: { _ in __safeDI_apiBuilder_F_K_Scope() })
			            }
			            @Sendable nonisolated func __safeDI_apiBuilder_F_K_Scope() -> F.SafeDIMockScope_Api.K_Scope.__safeDI_Builder<any Api> {
			                .init(api: { _ in
			                    let api: any Api = Live(db: db)
			                    return api
			                })
			            }
			            _ = F.__safeDI_F_mock_FB934F1CC08C8BFE.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "F", declaringModule: "Feat"))
			            return F.__safeDI_mock(apiSendableBuilder: __safeDI_apiSendableBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiSendableBuilder_F(), db: db, safeDIOverrides: safeDIOverrides.f)
			        }
			        let f: F = __safeDI_f()
			        return Root(db: db, f: f)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_18EB56F91E633979 {}
			}
			#endif
			"""]
		}
	}

	/// The graph of a place `F` passes up: module `Inner` declares `G`, which receives `db` and builds `K`, which instantiates
	/// the hole `api`, inside a `SendableInstantiator`; module `Feat` declares `F`, which instantiates `G`; and module `App`
	/// declares `Live`, which fills `api` reading `db`, and the caller `Root`, which instantiates `db` and `F`. `K`’s and the
	/// called types’ initializers are internal, so `Root`’s mock calls `F`’s public mock, which calls `G`’s.
	private static func passedUpGraph(
		caller: SendablePlaceCaller,
		calledTypes: CalledTypeDeclaration,
		fDeclarations: [String],
		expectedTwinErrorSite: (file: String, declaration: String)? = nil,
	) -> GraphFuzzerCallingMockGraph {
		func inner(calledTypeAttribute: String) -> String {
			"""
			import SafeDI

			public protocol Api: AnyObject {}

			@Instantiable
			public final class Db: Instantiable, Sendable {
			    public init() {}
			}

			\(calledTypeAttribute)
			public final class G: Instantiable {
			\(typeBody(initializerAccess: "", declarations: ["@Received let db: Db", "@Instantiated let k: SendableInstantiator<K>"]))
			}

			@Instantiable
			final class K: Instantiable {
			\(typeBody(initializerAccess: "", declarations: ["@Instantiated let api: any Api"]))
			}
			"""
		}
		func feat(calledTypeAttribute: String) -> String {
			"""
			import Inner
			import SafeDI

			\(calledTypeAttribute)
			public final class F: Instantiable {
			\(typeBody(initializerAccess: "", declarations: fDeclarations))
			}
			"""
		}
		func app(callerAttribute: String) -> String {
			"""
			import Feat
			import Inner
			import SafeDI

			@Instantiable(fulfillingAdditionalTypes: [Api.self])
			public final class Live: Api, Instantiable {
			\(typeBody(initializerAccess: "public ", declarations: ["@Received let db: Db"]))
			}

			\(callerAttribute)
			public final class Root: Instantiable {
			\(typeBody(initializerAccess: "public ", declarations: ["@Instantiated let db: Db", "@Instantiated let f: F"]))
			}
			"""
		}
		func files(calledTypeAttribute: String, callerAttribute: String) -> [GraphFuzzerCallingMockGraph.File] {
			[
				GraphFuzzerCallingMockGraph.File(module: "Inner", dependencies: [], content: inner(calledTypeAttribute: calledTypeAttribute)),
				GraphFuzzerCallingMockGraph.File(module: "Feat", dependencies: ["Inner"], content: feat(calledTypeAttribute: calledTypeAttribute)),
				GraphFuzzerCallingMockGraph.File(module: "App", dependencies: ["Feat", "Inner"], content: app(callerAttribute: callerAttribute)),
			]
		}
		return GraphFuzzerCallingMockGraph(
			name: "a fill reading, inside a `@Sendable` function of a called type another passes up, a value both receive",
			mockFiles: files(calledTypeAttribute: calledTypes.attribute, callerAttribute: caller.attribute),
			twinFiles: files(calledTypeAttribute: CalledTypeDeclaration.seamAndPublicMock.attribute, callerAttribute: "@Instantiable(generateDependencyTree: true)"),
			callerTypeName: "Root",
			callerIsPublic: caller == .public,
			mockConfiguration: caller == .listed ? "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Root\"])\n" : nil,
			flatParameterLabels: [],
			implementationIsVisible: true,
			expectedTwinInitializerLabels: expectedTwinErrorSite == nil ? [] : nil,
			expectedPassUpLabels: [],
			expectedTwinErrorSite: expectedTwinErrorSite,
			valueProbes: expectedTwinErrorSite == nil ? [DifferentialValueProbe(name: "Root", expression: "App.Root.mock()", knownRightExpression: "App.Root()")] : nil,
		)
	}

	/// The body of a type of the graph: an initializer of `initializerAccess` that takes each of `declarations`, then the
	/// declarations.
	private static func typeBody(initializerAccess: String, declarations: [String]) -> String {
		let properties = declarations.map { declaration in
			let property = declaration[declaration.range(of: " let ")!.upperBound...]
			return (label: String(property.prefix { $0 != ":" }), type: property.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces))
		}
		var lines = ["    \(initializerAccess)init(\(properties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {"]
		for property in properties {
			lines.append("        self.\(property.label) = \(property.label)")
		}
		lines.append("    }")
		lines.append("")
		for declaration in declarations {
			lines.append("    \(declaration)")
		}
		return lines.joined(separator: "\n")
	}

	/// Expects `result`’s twin to have its graph’s intended outcome and the calling mock to mirror it: no place passed up,
	/// no failure, and, where compile verification is on, the twin’s values.
	private static func expectFillsAsTwin(_ result: GraphFuzzerCallingMockResult, sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")", sourceLocation: sourceLocation)
		#expect(result.passUps.map(\.label) == [], sourceLocation: sourceLocation)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")", sourceLocation: sourceLocation)
		#expect(result.comparedValues == compileVerificationIsEnabled, sourceLocation: sourceLocation)
	}

	/// Expects `result`’s twin to report its graph’s error and the calling mock to report it at the same sites.
	private static func expectReportsTwinsError(_ result: GraphFuzzerCallingMockResult, sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")", sourceLocation: sourceLocation)
		#expect(result.mockSites != nil, sourceLocation: sourceLocation)
		#expect(result.failure == nil, "\(result.failure?.details ?? "")", sourceLocation: sourceLocation)
	}

	/// Expects the calling mock `output` generated for `modules` to build, for `Root.mock()`, what `Root()` builds of the
	/// same types built inline (`GraphFuzzerCallingMockGraph.inlineModules`), where compile verification is on.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectValuesEqualInline(of graph: GraphFuzzerCallingMockGraph, output: MultiModuleTestOutput, modules: [ModuleFixture], sourceLocation: SourceLocation = #_sourceLocation) async throws {
		guard compileVerificationIsEnabled else { return }
		let inlineModules = graph.inlineModules
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let comparison = try #require(try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: inlineOutput, modules: inlineModules),
			probes: [DifferentialValueProbe(name: "Root", expression: "App.Root.mock()", knownRightExpression: "App.Root()")],
			filesToDelete: &filesToDelete,
		), sourceLocation: sourceLocation)
		for difference in comparison.differences {
			Issue.record("The calling mock builds other values than inline for \(difference)\n\(comparison.report)", sourceLocation: sourceLocation)
		}
	}
}

/// The kind of caller whose generated mock calls `F`’s public mock: an internal mock, a `.public` one, or a plain
/// `@Instantiable` its module lists in `additionalMocksToGenerate`.
enum SendablePlaceCaller: CaseIterable, CustomTestStringConvertible {
	case `internal`
	case `public`
	case listed

	/// The caller’s attribute line in the calling mock’s form.
	var attribute: String {
		switch self {
		case .internal:
			"@Instantiable(generateMock: true)"
		case .public:
			"@Instantiable(generateMock: .public)"
		case .listed:
			"@Instantiable"
		}
	}

	var testDescription: String {
		switch self {
		case .internal:
			"internal caller"
		case .public:
			"public caller"
		case .listed:
			"listed caller"
		}
	}
}
