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

/// A hole's site inside the builder function a lazy cycle closes on, in the tree of a seam that defers a pass-through
/// of a label that function takes as a cycle parameter: the site's struct carries the function's parameter, by value,
/// as inline's site reads it, never the seam's memo of the pass-through, which the parameter hides.
struct SafeDIToolSeamDeferredCycleParameterTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Fixtures

	/// How the cycle in `Hub`'s tree closes on the function that builds `A`.
	private enum Cycle {
		/// `Hub` and `B` each instantiate `aBuilder: Instantiator<A>`.
		case instantiator
		/// `Hub` and `B` each instantiate `a: LazilyInstantiated<A>`.
		case lazilyInstantiated
		/// `Hub` and `B` each instantiate `aBuilder: SendableInstantiator<A>`, and `A` instantiates
		/// `bBuilder: SendableInstantiator<B>`, so the function that builds `A`, and the site inside it, are `@Sendable`.
		case sendableInstantiator

		var openerAndCloser: String {
			switch self {
			case .instantiator: "@Instantiated let aBuilder: Instantiator<A>"
			case .lazilyInstantiated: "@Instantiated let a: LazilyInstantiated<A>"
			case .sendableInstantiator: "@Instantiated let aBuilder: SendableInstantiator<A>"
			}
		}

		var bBuilder: String {
			switch self {
			case .instantiator, .lazilyInstantiated: "@Instantiated let bBuilder: Instantiator<B>"
			case .sendableInstantiator: "@Instantiated let bBuilder: SendableInstantiator<B>"
			}
		}

		/// A probe that builds `B` with a `Tag` of its own, and so the `A` that `B` builds again.
		var probe: DifferentialValueProbe {
			switch self {
			case .instantiator, .sendableInstantiator: DifferentialValueProbe("Root().hub.aBuilder.instantiate().bBuilder.instantiate(Tag())")
			case .lazilyInstantiated: DifferentialValueProbe("Root().hub.a.instance.bBuilder.instantiate(Tag())")
			}
		}
	}

	/// `Feature`, where the seam `Hub` builds `A` behind `cycle`'s opener; `A` builds `TagReader`, which receives `tag` as
	/// `readerReceive` declares it, `api: any Api`, a hole only `App` can fill, and `B`, which forwards `tag` and builds `A`
	/// again behind `cycle`'s closer. `App`, in another package unless `appPackageName` says otherwise, declares `LiveApi`,
	/// which fulfills `Api` with `liveApiDeclarations`, and `Root`, which instantiates `tag` as `rootTag` and `hub`. Every
	/// type is spelled at `access`; `Tag` and `Root` are classes with creation stamps.
	private static func modules(
		cycle: Cycle = .instantiator,
		readerReceive: String = "@Received let tag: Tag",
		liveApiDeclarations: [String] = [],
		rootTag: String = "Tag",
		hubArguments: String = "generateDependencyTree: true",
		access: String = "public",
		appPackageName: String = "Other",
	) -> [ModuleFixture] {
		let stamp = DifferentialValueCreationStamp.property(counterNamed: "Counter")
		let tagConformances = cycle == .sendableInstantiator ? ", Sendable" : ""
		let tag = """
		@Instantiable
		public final class Tag: Instantiable\(tagConformances) {
		    public init() {}

		    \(stamp)
		}
		"""
		let feature = [
			DifferentialValueCreationStamp.counterDeclaration(named: "Counter"),
			"public protocol Api {}",
			tag,
			seamFixtureType(named: "TagReader", declarations: [readerReceive]),
			seamFixtureType(named: "A", declarations: ["@Instantiated let reader: TagReader", "@Instantiated let api: any Api", cycle.bBuilder]),
			seamFixtureType(named: "B", declarations: ["@Forwarded let tag: Tag", cycle.openerAndCloser]),
			seamFixtureType(named: "Hub", declarations: [cycle.openerAndCloser])
				.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(\(hubArguments))\n"),
		]
		let liveApi = seamFixtureType(named: "LiveApi", declarations: liveApiDeclarations, conformances: ", Api")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Api.self])\n")
		let root = seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let tag: \(rootTag)", "@Instantiated let hub: Hub"])
			.replacingOccurrences(of: "public final class Root: Instantiable {\n", with: "public final class Root: Instantiable {\n    \(stamp)\n\n")
		func spelled(_ files: [String]) -> [String] {
			files.map { $0.replacingOccurrences(of: "public ", with: "\(access) ") }
		}
		return [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: spelled(feature)),
			ModuleFixture(name: "App", packageName: appPackageName, swiftFileContent: spelled([liveApi, root]).map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// `modules` with `Hub` built inline, as a type that is not a seam.
	private static func inlineModules(_ modules: [ModuleFixture]) -> [ModuleFixture] {
		modules.map { module in
			ModuleFixture(
				name: module.name,
				packageName: module.packageName,
				swiftFileContent: module.swiftFileContent.map { $0.replacingOccurrences(of: "generateDependencyTree: true", with: "generateDependencyTree: false") },
				dependencies: module.dependencies,
			)
		}
	}

	/// The comment on the line of `App`'s guard of the call of `Hub`.
	private static let callComment = MultiModuleIntegration.moduleInfo.seamCallComment(type: "Hub", declaringModule: "Feature")

	/// `App`'s generated file, whose `Root` binds `tag` with `rootTagCode` and calls `Hub`'s initializer under the guard
	/// `guardName`, passing `tagArgument` and the dispatcher, whose one case, `caseName`, `fillCode` fills.
	private static func appFile(
		guardName: String,
		rootTagCode: String = "let tag = Tag()",
		tagArgument: String = "tag",
		caseName: String = "aBuilder_api",
		fillCode: String = "let api: any Api = LiveApi()",
	) -> [String: String] {
		["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        \(rootTagCode)
		        func __safeDI_hub() -> Hub {
		            _ = Hub.\(guardName).self\(callComment)
		            func __safeDI_apiBuilder_Hub(_ scope: Hub.SafeDIScope_Api) -> any Api {
		                switch scope {
		                case \(fillCode.contains("scope.") ? "let .\(caseName)(scope)" : ".\(caseName)"):
		                    \(fillCode)
		                    return api
		                }
		            }
		            return Hub(__safeDI_tag: \(tagArgument), __safeDI_apiBuilder: __safeDI_apiBuilder_Hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        self.init(tag: tag, hub: hub)
		    }
		}
		"""]
	}

	/// `Feature`'s generated file for `Hub`'s tree built behind `aBuilder: Instantiator<A>`, with `tag` typed `tagType`,
	/// the guard `guardName`, at `access`, followed by `mockCode`.
	private static func instantiatorCycleFeatureFile(guardName: String, tagType: String = "Tag", access: String = "public", mockCode: String = "") -> [String: String] {
		["Feature.swift": generatedFileHeader + """
		extension Hub {
		    @frozen public enum SafeDIScope_Api {
		        case aBuilder_api(aBuilder_api_Values)

		        public struct aBuilder_api_Values {
		            \(access) let tag: \(tagType)
		            \(access) let reader: TagReader
		            \(access) let bBuilder: Instantiator<B>
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    \(access) init(__safeDI_tag: @autoclosure @escaping () -> \(tagType), __safeDI_apiBuilder: @escaping (SafeDIScope_Api) -> any Api) {
		        let tag = LazilyInstantiated<\(tagType)>(__safeDI_tag)
		        func __safeDI_aBuilder(tag: \(tagType)) -> A {
		            let reader = TagReader(tag: tag)
		            func __safeDI_bBuilder(tag: Tag) -> B {
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(tag: tag)
		                }
		                return B(tag: tag, aBuilder: aBuilder)
		            }
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(tag: $0)
		            }
		            let api: any Api = __safeDI_apiBuilder(.aBuilder_api(SafeDIScope_Api.aBuilder_api_Values(tag: tag, reader: reader, bBuilder: bBuilder)))
		            return A(reader: reader, api: api, bBuilder: bBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(tag: tag.instance)
		        }
		        self.init(aBuilder: aBuilder)
		    }
		}

		extension Hub {
		    public enum \(guardName) {}
		}
		""" + mockCode]
	}

	/// `Feature`'s generated file for `Hub`'s tree built behind `aBuilder: SendableInstantiator<A>`.
	private static let sendableCycleFeatureFile = ["Feature.swift": generatedFileHeader + """
	extension Hub {
	    public enum SafeDIStagedScope_Api_aBuilder_api {
	        public struct Stage1 {}

	        public struct Stage2 {
	            public let tag: Tag
	            public let reader: TagReader
	            public let bBuilder: SendableInstantiator<B>
	        }
	    }

	    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
	    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
	    public init(__safeDI_tag: @autoclosure @escaping @Sendable () -> Tag, __safeDI_apiBuilder_aBuilder_api: @escaping (SafeDIStagedScope_Api_aBuilder_api.Stage1) -> @Sendable (SafeDIStagedScope_Api_aBuilder_api.Stage2) -> any Api) {
	        let tag = SendableLazilyInstantiated<Tag>(__safeDI_tag)
	        let __safeDI_apiBuilder_aBuilder_api_Stage2 = __safeDI_apiBuilder_aBuilder_api(SafeDIStagedScope_Api_aBuilder_api.Stage1())
	        @Sendable func __safeDI_aBuilder(tag: Tag) -> A {
	            let reader = TagReader(tag: tag)
	            @Sendable func __safeDI_bBuilder(tag: Tag) -> B {
	                let aBuilder = SendableInstantiator<A> {
	                    __safeDI_aBuilder(tag: tag)
	                }
	                return B(tag: tag, aBuilder: aBuilder)
	            }
	            let bBuilder = SendableInstantiator<B> {
	                __safeDI_bBuilder(tag: $0)
	            }
	            let api: any Api = __safeDI_apiBuilder_aBuilder_api_Stage2(SafeDIStagedScope_Api_aBuilder_api.Stage2(tag: tag, reader: reader, bBuilder: bBuilder))
	            return A(reader: reader, api: api, bBuilder: bBuilder)
	        }
	        let aBuilder = SendableInstantiator<A> {
	            __safeDI_aBuilder(tag: tag.instance)
	        }
	        self.init(aBuilder: aBuilder)
	    }
	}

	extension Hub {
	    public enum __safeDI_Hub_CE1237D4AE25666D {}
	}
	"""]

	/// `App`'s generated file for `Hub`'s tree built behind `aBuilder: SendableInstantiator<A>`, whose fill of the last stage
	/// is `fillCode`.
	private static func sendableCycleAppFile(fillCode: String = "let api: any Api = LiveApi()") -> [String: String] {
		["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        let tag = Tag()
		        func __safeDI_hub() -> Hub {
		            _ = Hub.__safeDI_Hub_CE1237D4AE25666D.self\(callComment)
		            func __safeDI_apiBuilder_aBuilder_api(_ scope: Hub.SafeDIStagedScope_Api_aBuilder_api.Stage1) -> @Sendable (Hub.SafeDIStagedScope_Api_aBuilder_api.Stage2) -> any Api {
		                @Sendable func __safeDI_apiBuilder_aBuilder_api_Stage2(_ scope: Hub.SafeDIStagedScope_Api_aBuilder_api.Stage2) -> any Api {
		                    \(fillCode)
		                    return api
		                }
		                return __safeDI_apiBuilder_aBuilder_api_Stage2
		            }
		            return Hub(__safeDI_tag: tag, __safeDI_apiBuilder_aBuilder_api: __safeDI_apiBuilder_aBuilder_api)
		        }
		        let hub: Hub = __safeDI_hub()
		        self.init(tag: tag, hub: hub)
		    }
		}
		"""]
	}

	// MARK: The site's struct

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesCycleParameterInScope_whenSiteIsInsideFunctionInstantiatorCycleClosesOn() async throws {
		// `Hub` defers `tag`, which `TagReader` receives, as a memo; `B` builds `A` again with the `tag` it forwards, so the
		// function that builds `A` takes `tag`, which hides the memo inside it. The site of `api` there carries the
		// function's `tag`, by value, as inline's site reads it: `Root`'s where `Hub` builds `A`, `B`'s where `B` does.
		let modules = Self.modules()
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == Self.instantiatorCycleFeatureFile(guardName: "__safeDI_Hub_B47455B435186A99"))
		#expect(output.modules["App"]?.generatedFiles == Self.appFile(guardName: "__safeDI_Hub_B47455B435186A99"))
		try await expectValuesEqualInlineBuild(output, modules: modules, probes: [DifferentialValueProbe("Root()"), Cycle.instantiator.probe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesOptionalCycleParameterInScope_whenTreeReceivesLabelOnlyIfAvailable() async throws {
		// Every receive of `tag` in the function's body is only if available, so the function takes it optionally, and the
		// site carries it as the function takes it.
		let modules = Self.modules(readerReceive: "@Received(onlyIfAvailable: true) let tag: Tag?")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == Self.instantiatorCycleFeatureFile(guardName: "__safeDI_Hub_C838B16EBCDE3D8B", tagType: "Tag?"))
		#expect(output.modules["App"]?.generatedFiles == Self.appFile(guardName: "__safeDI_Hub_C838B16EBCDE3D8B"))
		try await expectValuesEqualInlineBuild(output, modules: modules, probes: [DifferentialValueProbe("Root()"), Cycle.instantiator.probe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesCycleParameterInScope_whenLazilyInstantiatedCycleClosesOnFunction() async throws {
		// `Hub` and `B` each build `A` lazily, and `Root` holds `tag` lazily too: the memo reads `Root`'s wrapper only when
		// `Hub`'s `a` is first read, as inline reads it there.
		let modules = Self.modules(cycle: .lazilyInstantiated, rootTag: "LazilyInstantiated<Tag>")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Hub {
		    @frozen public enum SafeDIScope_Api {
		        case a_api(a_api_Values)

		        public struct a_api_Values {
		            public let tag: Tag
		            public let reader: TagReader
		            public let bBuilder: Instantiator<B>
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_tag: @autoclosure @escaping () -> Tag, __safeDI_apiBuilder: @escaping (SafeDIScope_Api) -> any Api) {
		        let tag = LazilyInstantiated<Tag>(__safeDI_tag)
		        func __safeDI_a(tag: Tag) -> A {
		            let reader = TagReader(tag: tag)
		            func __safeDI_bBuilder(tag: Tag) -> B {
		                let a = LazilyInstantiated<A> {
		                    __safeDI_a(tag: tag)
		                }
		                return B(tag: tag, a: a)
		            }
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(tag: $0)
		            }
		            let api: any Api = __safeDI_apiBuilder(.a_api(SafeDIScope_Api.a_api_Values(tag: tag, reader: reader, bBuilder: bBuilder)))
		            return A(reader: reader, api: api, bBuilder: bBuilder)
		        }
		        let a = LazilyInstantiated<A> {
		            __safeDI_a(tag: tag.instance)
		        }
		        self.init(a: a)
		    }
		}

		extension Hub {
		    public enum __safeDI_Hub_C65C21D0A2486BC2 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == Self.appFile(
			guardName: "__safeDI_Hub_C65C21D0A2486BC2",
			rootTagCode: """
			func __safeDI_tag() -> Tag {
			            Tag()
			        }
			        let tag = LazilyInstantiated<Tag>(__safeDI_tag)
			""",
			tagArgument: "tag.instance",
			caseName: "a_api",
		))
		try await expectValuesEqualInlineBuild(output, modules: modules, probes: [DifferentialValueProbe("Root()"), Cycle.lazilyInstantiated.probe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesCycleParameterInStage_whenSendableInstantiatorCycleClosesOnSendableFunction() async throws {
		// The function that builds `A` is `@Sendable`, so it starts the site's second stage, whose struct carries the
		// function's `tag`; the memo, read inside a `@Sendable` function, is a `SendableLazilyInstantiated`.
		let modules = Self.modules(cycle: .sendableInstantiator)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == Self.sendableCycleFeatureFile)
		#expect(output.modules["App"]?.generatedFiles == Self.sendableCycleAppFile())
		try await expectValuesEqualInlineBuild(output, modules: modules, probes: [DifferentialValueProbe("Root()"), Cycle.sendableInstantiator.probe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsCycleParameterFromScope_whenFillReceivesLabel() async throws {
		// `LiveApi` receives `tag`, which the fill binds from the struct, never from `Root`: where `B` builds `A` again, the
		// `tag` inline's `LiveApi` receives is `B`'s.
		let modules = Self.modules(liveApiDeclarations: ["@Received let tag: Tag"])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == Self.instantiatorCycleFeatureFile(guardName: "__safeDI_Hub_B47455B435186A99"))
		#expect(output.modules["App"]?.generatedFiles == Self.appFile(
			guardName: "__safeDI_Hub_B47455B435186A99",
			fillCode: """
			let tag = scope.tag
			                    let api: any Api = LiveApi(tag: tag)
			""",
		))
		try await expectValuesEqualInlineBuild(output, modules: modules, probes: [DifferentialValueProbe("Root()"), Cycle.instantiator.probe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsCycleParameterFromStage_whenSendableFillReceivesLabel() async throws {
		// The `@Sendable` function's `tag` is in the site's second stage, which the fill's `@Sendable` stage binds `tag` from:
		// where `B` builds `A` again, `LiveApi` receives `B`'s `tag`, as inline's does, never `Root`'s.
		let modules = Self.modules(cycle: .sendableInstantiator, liveApiDeclarations: ["@Received let tag: Tag"])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == Self.sendableCycleFeatureFile)
		#expect(output.modules["App"]?.generatedFiles == Self.sendableCycleAppFile(fillCode: """
		let tag = scope.tag
		                    let api: any Api = LiveApi(tag: tag)
		"""))
		try await expectValuesEqualInlineBuild(output, modules: modules, probes: [DifferentialValueProbe("Root()"), Cycle.sendableInstantiator.probe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarry_whenFillRequiresCycleParameterFunctionTakesOptionally() async {
		// `TagReader` receives `tag` only if available, so the function that builds `A` takes `tag: Tag?`, which hides
		// `Hub`'s pass-through, and the struct carries it as the function takes it, while `LiveApi` requires `tag: Tag`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `tag: Tag`, which the scope SafeDI hands the builder for `A`'s `api: any Api` (case `aBuilder_api` of `apiBuilder`) carries only as `tag: Tag?`, since `A`'s builder function takes it as a parameter, because a cycle inside `A`'s tree passes it, and no type `Hub`'s tree builds in that function requires `tag: Tag`. Receive it on `LiveApi` with `@Received(onlyIfAvailable: true) let tag: Tag?`, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["TagReader.swift"]):7:5: note: `TagReader` receives `tag: Tag?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(readerReceive: "@Received(onlyIfAvailable: true) let tag: Tag?", liveApiDeclarations: ["@Received let tag: Tag"]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_mocksSeamInline_whenSeamWithSiteInsideCycleFunctionGeneratesMock() async throws {
		// A mock builds `Hub`'s tree inline, as mocks build every seam, taking `api`, which it cannot build.
		let modules = Self.modules(hubArguments: "generateDependencyTree: true, generateMock: true")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == Self.instantiatorCycleFeatureFile(guardName: "__safeDI_Hub_B47455B435186A99", mockCode: """


		#if DEBUG
		extension Hub {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            tag: (() -> Tag)? = nil,
		            aBuilder: A.SafeDIMockConfiguration = .init()
		        ) {
		            self.tag = tag
		            self.aBuilder = aBuilder
		        }

		        private(set) var tag: (() -> Tag)?
		        private(set) var aBuilder: A.SafeDIMockConfiguration
		    }

		    static func mock(
		        api: Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Hub {
		        let tag = if let safeDIBuilder = safeDIOverrides.tag { safeDIBuilder() } else { Tag() }
		        func __safeDI_aBuilder(tag: Tag) -> A {
		            let reader = if let safeDIBuilder = safeDIOverrides.aBuilder.reader { safeDIBuilder(tag) } else { TagReader(tag: tag) }
		            func __safeDI_bBuilder(tag: Tag) -> B {
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(tag: tag)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.bBuilder.safeDIBuilder { safeDIBuilder(tag, aBuilder) } else { B(tag: tag, aBuilder: aBuilder) }
		            }
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(tag: $0)
		            }
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(reader, api, bBuilder) } else { A(reader: reader, api: api, bBuilder: bBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(tag: tag)
		        }
		        return Hub(aBuilder: aBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension B {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            _ safeDIBuilder: ((Tag, Instantiator<A>) -> B)? = nil
		        ) {
		            self.safeDIBuilder = safeDIBuilder
		        }

		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        private(set) var safeDIBuilder: ((Tag, Instantiator<A>) -> B)?
		    }
		}

		extension A {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            reader: ((Tag) -> TagReader)? = nil,
		            bBuilder: B.SafeDIMockConfiguration = .init(),
		            _ safeDIBuilder: ((TagReader, any Api, Instantiator<B>) -> A)? = nil
		        ) {
		            self.reader = reader
		            self.bBuilder = bBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        private(set) var reader: ((Tag) -> TagReader)?
		        private(set) var bBuilder: B.SafeDIMockConfiguration
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        private(set) var safeDIBuilder: ((TagReader, any Api, Instantiator<B>) -> A)?
		    }
		}
		#endif

		"""))
		#expect(output.modules["App"]?.generatedFiles == Self.appFile(guardName: "__safeDI_Hub_B47455B435186A99"))
		try await expectValuesEqualInlineBuild(output, modules: modules, probes: [
			DifferentialValueProbe("Root()"),
			Cycle.instantiator.probe,
			DifferentialValueProbe(name: "Hub.mock(api: LiveApi())", expression: "Hub.mock(api: LiveApi())"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesCycleParameterAtPackageAccess_whenSeamsTierIsPackage() async throws {
		// Every type is `package`, and `App` is in `Feature`'s package: `Hub`'s one tier is `package`, and so is each field.
		let modules = Self.modules(access: "package", appPackageName: "Shop")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == Self.instantiatorCycleFeatureFile(guardName: "__safeDI_Hub_23AC0F8ED5FC7306", access: "package"))
		#expect(output.modules["App"]?.generatedFiles == Self.appFile(guardName: "__safeDI_Hub_23AC0F8ED5FC7306"))
		try await expectValuesEqualInlineBuild(output, modules: modules, probes: [DifferentialValueProbe("Root()"), Cycle.instantiator.probe])
	}

	// MARK: A site passed up from inside the function

	/// `Core`, where the seam `Inner` builds `api: any Api`, a hole only `App` can fill, beside `innerDeclarations`;
	/// `Feature`, where the seam `Hub` builds `A` behind `aBuilder: Instantiator<A>`, and `A` builds `TagReader`, which
	/// receives `tag`, `Inner`, whose builder `Hub` passes up, and `B`, which forwards `tag` and builds `A` again, so the
	/// function that builds `A` takes `tag`; and `App`, which declares `LiveApi`, which fulfills `Api` with
	/// `liveApiDeclarations`, and `Root`, which instantiates `tag` and `hub`. `Tag` and `Root` are classes with creation
	/// stamps.
	private static func passedUpModules(innerDeclarations: [String] = [], liveApiDeclarations: [String] = []) -> [ModuleFixture] {
		let stamp = DifferentialValueCreationStamp.property(counterNamed: "Counter")
		let tag = """
		@Instantiable
		public final class Tag: Instantiable {
		    public init() {}

		    \(stamp)
		}
		"""
		let core = [
			DifferentialValueCreationStamp.counterDeclaration(named: "Counter"),
			"public protocol Api {}",
			tag,
			seamFixtureType(named: "Inner", isSeam: true, declarations: innerDeclarations + ["@Instantiated let api: any Api"]),
		]
		let feature = [
			seamFixtureType(named: "TagReader", declarations: ["@Received let tag: Tag"]),
			seamFixtureType(named: "A", declarations: ["@Instantiated let reader: TagReader", "@Instantiated let inner: Inner", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", declarations: ["@Forwarded let tag: Tag", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
		]
		let liveApi = seamFixtureType(named: "LiveApi", declarations: liveApiDeclarations, conformances: ", Api")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Api.self])\n")
		let root = seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let tag: Tag", "@Instantiated let hub: Hub"])
			.replacingOccurrences(of: "public final class Root: Instantiable {\n", with: "public final class Root: Instantiable {\n    \(stamp)\n\n")
		return [
			ModuleFixture(name: "Core", packageName: "Base", swiftFileContent: core),
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature.map { "import Core\n\n" + $0 }, dependencies: ["Core"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [liveApi, root].map { "import Core\nimport Feature\n\n" + $0 }, dependencies: ["Core", "Feature"]),
		]
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarry_whenSeamPassesUpSiteInsideFunctionThatTakesCycleParameter() async {
		// `Hub` passes up the builder `Inner` takes for `api`, and calls `Inner` inside the function that builds `A`, which
		// takes `tag`. Inline, the `LiveApi` that `Inner` builds where `B` builds `A` again receives `B`'s `tag`; `Root`, which
		// fills the builder, holds only its own.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):10:5: error: `LiveApi` receives `tag: Tag`, which `A`'s builder function takes as a parameter on the path where `Hub` calls `Inner`, because a cycle inside `A`'s tree passes it, but `Hub` passes the builder for `Inner`'s `api: any Api` (case `api` of `apiBuilder`) on from its own caller, which cannot hand it that value. Declare `@Received let tag: Tag` on `Inner`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies, so `Hub` fills the builder itself.
			\(fixtures["Feature"]!["TagReader.swift"]):9:5: note: `TagReader` receives `tag: Tag` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.passedUpModules(liveApiDeclarations: ["@Received let tag: Tag"]),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsCycleParameterFromInnerSeamsScope_whenInnerSeamReceivesLabel() async throws {
		// `Inner` receives `tag`, so `Hub` passes it the function's `tag` and `Inner`'s struct carries it: where `B` builds `A`
		// again, the `LiveApi` that `Inner` builds receives `B`'s `tag`, as inline's does.
		let modules = Self.passedUpModules(innerDeclarations: ["@Received let tag: Tag"], liveApiDeclarations: ["@Received let tag: Tag"])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let innerCallComment = MultiModuleIntegration.moduleInfo.seamCallComment(type: "Inner", declaringModule: "Core")
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		extension Hub {
		    @frozen public enum SafeDIScope_Api {
		        case aBuilder_inner(Inner.SafeDIScope_Api)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_tag: @autoclosure @escaping () -> Tag, __safeDI_apiBuilder: @escaping (SafeDIScope_Api) -> any Api) {
		        let tag = LazilyInstantiated<Tag>(__safeDI_tag)
		        func __safeDI_aBuilder(tag: Tag) -> A {
		            let reader = TagReader(tag: tag)
		            func __safeDI_inner() -> Inner {
		                _ = Inner.__safeDI_Inner_B28B6E75A98C7D72.self\(innerCallComment)
		                return Inner(__safeDI_tag: tag, __safeDI_apiBuilder: { __safeDI_apiBuilder(.aBuilder_inner($0)) })
		            }
		            let inner: Inner = __safeDI_inner()
		            func __safeDI_bBuilder(tag: Tag) -> B {
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(tag: tag)
		                }
		                return B(tag: tag, aBuilder: aBuilder)
		            }
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(tag: $0)
		            }
		            return A(reader: reader, inner: inner, bBuilder: bBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(tag: tag.instance)
		        }
		        self.init(aBuilder: aBuilder)
		    }
		}

		extension Hub {
		    public enum __safeDI_Hub_8C8CCA788EC6514B {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        let tag = Tag()
		        func __safeDI_hub() -> Hub {
		            _ = Hub.__safeDI_Hub_8C8CCA788EC6514B.self\(Self.callComment)
		            func __safeDI_apiBuilder_Hub(_ scope: Hub.SafeDIScope_Api) -> any Api {
		                switch scope {
		                case let .aBuilder_inner(scope): return __safeDI_apiBuilder_Inner(scope)
		                }
		            }
		            func __safeDI_apiBuilder_Inner(_ scope: Inner.SafeDIScope_Api) -> any Api {
		                switch scope {
		                case let .api(scope):
		                    let tag = scope.tag
		                    let api: any Api = LiveApi(tag: tag)
		                    return api
		                }
		            }
		            return Hub(__safeDI_tag: tag, __safeDI_apiBuilder: __safeDI_apiBuilder_Hub)
		        }
		        let hub: Hub = __safeDI_hub()
		        self.init(tag: tag, hub: hub)
		    }
		}
		"""])
		try await expectValuesEqualInlineBuild(output, modules: modules, probes: [DifferentialValueProbe("Root()"), Cycle.instantiator.probe])
	}

	// MARK: Values

	/// Expects the values `output`, the run of `modules`, builds for `probes` to equal those the run of `modules` with `Hub`
	/// built inline builds.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectValuesEqualInlineBuild(
		_ output: MultiModuleTestOutput,
		modules: [ModuleFixture],
		probes: [DifferentialValueProbe],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		guard compileVerificationIsEnabled else { return }
		let inlineModules = Self.inlineModules(modules)
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: inlineOutput, modules: inlineModules),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	private var filesToDelete: [URL]
}
