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
@testable import SafeDIToolTestSupport

/// The graph fuzzer's readers of generated code, each over a seam that takes a builder struct, where a reader that stops
/// matching the struct's form would go silent, and over a builder that keeps its closure over its scope enum, the form a
/// public mock's hole types keep, which each reads as before. Each fixture is code the tool generated: the closure form
/// as a seam spelled it before every hole type of a seam took a builder struct.
struct GraphFuzzerBuilderStructReaderTests {
	// MARK: holeBuilderNames

	@Test
	func holeBuilderNames_readsScopeCasesAndBuilderLabel_whenSeamTakesBuilderStruct() {
		#expect(GraphFuzzerOracle.holeBuilderNames(in: ["FuzzFeature/Home+SafeDI.swift": Self.switchedHome]) == [
			"Home(apiBuilder:)",
			"Home.SafeDIScope_Api",
			"Home.SafeDIScope_Api.api",
		])
	}

	@Test
	func holeBuilderNames_readsKeptBuilderBesideSwitchedOne_whenSeamTakesBothForms() {
		#expect(GraphFuzzerOracle.holeBuilderNames(in: ["FuzzFeature/Home+SafeDI.swift": Self.switchedAndKeptHome]) == [
			"Home(apiBuilder:)",
			"Home(livePanel_PanelBuilder:)",
			"Home.SafeDIScope_Api",
			"Home.SafeDIScope_Api.api",
			"Home.SafeDIScope_LivePanel_Panel",
			"Home.SafeDIScope_LivePanel_Panel.inner",
			"Home.SafeDIScope_LivePanel_Panel.panelBuilder",
		])
	}

	@Test
	func holeBuilderNames_readsMemberReturningWrapperBuilder_whenSeamTakesBuilderStructForPlaceThatForwards() {
		#expect(GraphFuzzerOracle.holeBuilderNames(in: ["FuzzFeature/Home+SafeDI.swift": Self.switchedForwardingHome]) == [
			"Home(apiBuilder:)",
			"Home(livePanel_PanelBuilder:)",
			"Home.SafeDIScope_Api",
			"Home.SafeDIScope_Api.api",
			"Home.SafeDIScope_LivePanel_Panel",
			"Home.SafeDIScope_LivePanel_Panel.panelBuilder",
		])
	}

	// MARK: seamInitializers

	@Test
	func seamInitializers_readsPlainInitializersParameters_whenPlainInitializerPrecedesGeneratedOnlyOne() {
		let initializers = GraphFuzzerOracle.seamInitializers(inGeneratedFile: Self.switchedAndKeptHome)

		#expect(initializers.map(\.seamTypeName) == ["Home"])
		#expect(initializers.map(\.access) == ["public"])
		#expect(initializers.map(\.parameters) == [["apiBuilder: @escaping () -> any Api", "livePanel_PanelBuilder: @escaping (Home.SafeDIScope_LivePanel_Panel) -> any Panel"]])
	}

	@Test
	func seamInitializers_spellsGeneratedOnlyParametersPlainly_whenPlainInitializerTakesAnotherNumberOfParameters() {
		// A plain initializer the tier's initializer only generated code calls does not forward to is not read for it.
		let file = Self.switchedAndKeptHome.replacingOccurrences(
			of: "public init(apiBuilder: @escaping () -> any Api, livePanel_PanelBuilder: @escaping (SafeDIScope_LivePanel_Panel) -> any Panel) {",
			with: "public init(apiBuilder: @escaping () -> any Api) {",
		)

		#expect(file != Self.switchedAndKeptHome)
		#expect(GraphFuzzerOracle.seamInitializers(inGeneratedFile: file).map(\.parameters) == [["apiBuilder: Home.SafeDIScope_Api.__safeDI_Builder<any Api>", "livePanel_PanelBuilder: @escaping (Home.SafeDIScope_LivePanel_Panel) -> any Panel"]])
	}

	@Test
	func seamInitializers_spellsGeneratedOnlyParametersPlainly_whenPlainInitializerIsInAnotherExtension() {
		let file = Self.switchedAndKeptHome.replacingOccurrences(
			of: "\n\n    /// Only code SafeDI generates calls this initializer",
			with: "\n}\n\nextension Home {\n    /// Only code SafeDI generates calls this initializer",
		)

		#expect(file != Self.switchedAndKeptHome)
		#expect(GraphFuzzerOracle.seamInitializers(inGeneratedFile: file).map(\.parameters) == [["apiBuilder: Home.SafeDIScope_Api.__safeDI_Builder<any Api>", "livePanel_PanelBuilder: @escaping (Home.SafeDIScope_LivePanel_Panel) -> any Panel"]])
	}

	@Test
	func seamInitializers_readsWrapperBuilderParameter_whenPlaceForwardsValue() {
		let initializers = GraphFuzzerOracle.seamInitializers(inGeneratedFile: Self.switchedForwardingHome)

		#expect(initializers.map(\.seamTypeName) == ["Home"])
		#expect(initializers.map(\.parameters) == [["apiBuilder: @escaping () -> any Api", "livePanel_PanelBuilder: @escaping ErasedInstantiator<String, any Panel>.Builder"]])
	}

	// MARK: seamOutputFeatures

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func seamOutputFeatures_countsOnlyPassThrough_whenSeamTakesBuilderStruct() {
		// `token` is the only pass-through: the struct's builder, which the plain initializer takes as a closure that takes
		// nothing, `@escaping`, is not one.
		#expect(GraphFuzzerFeature.seamOutputFeatures(of: GraphFuzzerFixture(seed: 1, swiftFileContent: []), generatedFiles: ["FuzzFeature/Home+SafeDI.swift": Self.switchedHomeWithPassThrough]) == [.requiredPassThrough])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func seamOutputFeatures_countsNoBuilderAsPassThrough_whenSeamKeepsClosureOverEnum() {
		#expect(GraphFuzzerFeature.seamOutputFeatures(of: GraphFuzzerFixture(seed: 1, swiftFileContent: []), generatedFiles: ["FuzzFeature/Inner+SafeDI.swift": Self.keptInner]).isEmpty)
	}

	// MARK: holeOutputFeatures

	@Test
	func holeOutputFeatures_readsBuilderParameter_whenSeamTakesBuilderStruct() {
		#expect(GraphFuzzerFeature.holeOutputFeatures(generatedFiles: ["FuzzFeature/Home+SafeDI.swift": Self.switchedHome]) == [.builderParameter])
	}

	@Test
	func holeOutputFeatures_readsBuilderParameter_whenSeamKeepsClosureOverEnum() {
		#expect(GraphFuzzerFeature.holeOutputFeatures(generatedFiles: ["FuzzFeature/Inner+SafeDI.swift": Self.keptInner]) == [.builderParameter, .passedUpBuilder])
	}

	@Test
	func holeOutputFeatures_readsPassedUpBuilder_whenBuilderStructMemberBuildsInnerSeamsStruct() {
		// `HoleOuter` passes up the place of `HoleSeam`, which it calls: its struct's member builds `HoleSeam`'s struct.
		#expect(GraphFuzzerFeature.holeOutputFeatures(generatedFiles: ["FuzzFeature/HoleOuter+SafeDI.swift": Self.passingUpOuter]) == [.builderParameter, .passedUpBuilder])
	}

	@Test
	func holeOutputFeatures_readsFillPassedToSeamPassingItsSiteUp_whenFillsLevelBuildsStructOfSeamPassingThePlaceUp() {
		// `Root` fills the place of `FillCallShell`'s `FillCallUserService`, inside `TrackerImpl`, which fills
		// `FillCallInner`'s place: the fill's level builds the struct of `FillCallService`, which it calls and which passes
		// the place up, neither the place's seam nor the seam the fill is declared for.
		#expect(GraphFuzzerFeature.holeOutputFeatures(generatedFiles: ["FuzzApp/Root+SafeDI.swift": Self.fillCallingSeamPassingPlaceUp]) == [.fillPassedToSeamPassingItsSiteUp])
	}

	@Test
	func holeOutputFeatures_isEmpty_whenFillsLevelBuildsStructOfSeamTheFillIsDeclaredFor() {
		let fillCallingItsOwnSeam = Self.fillCallingSeamPassingPlaceUp.replacingOccurrences(
			of: ".init(fillCallServiceBuilder: { _ in __safeDI_fillCallUserServiceBuilder_FillCallService() })",
			with: ".init(fillCallServiceBuilder: { _ in __safeDI_fillCallUserServiceBuilder_FillCallShell_FillCallInner() })",
		)

		#expect(fillCallingItsOwnSeam != Self.fillCallingSeamPassingPlaceUp)
		#expect(GraphFuzzerFeature.holeOutputFeatures(generatedFiles: ["FuzzApp/Root+SafeDI.swift": fillCallingItsOwnSeam]) == [])
	}

	@Test
	func holeOutputFeatures_readsFillPassedToItsSeam_whenFillCallsSendableLevelFunction() {
		// The fill builds `HoleSeam` again inside a `@Sendable` function, passing the level function, `@Sendable nonisolated`,
		// that the call it fills passes.
		#expect(GraphFuzzerFeature.holeOutputFeatures(generatedFiles: ["FuzzApp/Root+SafeDI.swift": Self.fillCallingSendableLevelFunction]) == [.fill, .sendableFill, .fillPassedToItsSeam])
	}

	@Test
	func holeOutputFeatures_readsFillPassedToItsSeam_whenFillPassesStructConvertedFromDispatcherOverLines() {
		// The fill builds `HoleSeam` again and hands it a struct its call spells over several lines, whose members call the
		// dispatcher over `HoleSeam`'s enum.
		#expect(GraphFuzzerFeature.holeOutputFeatures(generatedFiles: ["FuzzApp/Root+SafeDI.swift": Self.fillPassingConvertedStruct]) == [.fill, .fillPassedToItsSeam])
	}

	// MARK: GraphFuzzerScopeDeclarations

	@Test
	func valuesStructs_readsOnlyCasesPayloads_whenSeamTakesBuilderStructs() {
		// Neither a level's `__safeDI_Builder` nor the empty struct the member of a `@Sendable` enum's case takes is a case's
		// payload.
		let declarations = GraphFuzzerScopeDeclarations(generatedFiles: ["FuzzFeature/Home+SafeDI.swift": Self.switchedSendableHome])

		#expect(declarations.valuesStructs == [
			.init(extendedType: "Home", path: ["SafeDIScope_Api", "Worker_Scope", "detail_Values"], fields: ["public logger: Logger"]),
			.init(extendedType: "Home", path: ["SafeDIScope_Api", "Detail_Scope", "api_Values"], fields: []),
		])
	}

	@Test
	func valuesStructs_readsEachCasesPayload_whenSeamKeepsClosureOverEnum() {
		let declarations = GraphFuzzerScopeDeclarations(generatedFiles: ["FuzzFeature/Home+SafeDI.swift": Self.switchedAndKeptHome])

		#expect(declarations.valuesStructs == [
			.init(extendedType: "Home", path: ["SafeDIScope_Api", "api_Values"], fields: ["public inner: Inner"]),
			.init(extendedType: "Home", path: ["SafeDIScope_LivePanel_Panel", "panelBuilder_Values"], fields: ["public inner: Inner", "public api: any Api"]),
		])
	}

	@Test
	func valuesStructs_readsCasesPayloadBesideForwardedValue_whenSeamTakesBuilderStructForPlaceThatForwards() {
		let declarations = GraphFuzzerScopeDeclarations(generatedFiles: ["FuzzFeature/Home+SafeDI.swift": Self.switchedForwardingHome])

		#expect(declarations.valuesStructs == [
			.init(extendedType: "Home", path: ["SafeDIScope_Api", "api_Values"], fields: []),
			.init(extendedType: "Home", path: ["SafeDIScope_LivePanel_Panel", "panelBuilder_Values"], fields: ["public api: any Api"]),
		])
	}

	// MARK: handWrittenRetentionProbe

	@Test(arguments: [
		("@escaping () -> any S1_RetainApi", "S1_RetainHome(s1_RetainApiBuilder: { S1_RetainLive() })"),
		("@escaping @Sendable () -> any S1_RetainApi", "S1_RetainHome(s1_RetainApiBuilder: { S1_RetainLive() })"),
		("@escaping ErasedInstantiator<Int, any S1_RetainApi>.Builder", "S1_RetainHome(s1_RetainApiBuilder: { ticket in S1_RetainLive(retainTicket: ticket) })"),
	])
	func differentialValueProbes_writesBuilderAsReadableInitializerTakesIt_whenGraphHasRetentionSeam(parameterType: String, expression: String) {
		// A builder struct's readable initializer takes a closure that takes nothing, plain or `@Sendable`, or a wrapper's
		// `Builder`, which takes the value the place forwards.
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"// module: FuzzFeature\n@Instantiable(generateDependencyTree: true)\npublic final class S1_RetainHome: Instantiable {\n    public init(api: any S1_RetainApi) {\n        self.api = api\n    }\n\n    @Instantiated let api: any S1_RetainApi\n}",
			"// module: FuzzApp\n@Instantiable(fulfillingAdditionalTypes: [S1_RetainApi.self])\npublic final class S1_RetainLive: Instantiable, S1_RetainApi {\n    public init() {}\n}",
		])
		let homeFile = """
		extension S1_RetainHome {
		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(s1_RetainApiBuilder: \(parameterType)) {
		        self.init(__safeDI_s1_RetainApiBuilder: s1_RetainApiBuilder)
		    }
		}
		"""

		let probe = fixture.differentialValueProbes(generatedFiles: ["FuzzFeature/S1_RetainHome+SafeDI.swift": homeFile]).first { $0.name.hasSuffix(GraphFuzzerFixture.handWrittenBuilderProbeNameSuffix) }

		#expect(probe?.expression == expression)
		#expect(probe?.knownRightExpression == "S1_RetainRoot().retainHome")
	}

	// MARK: seamCorpusFixture

	@Test
	func seamCorpusFixture_declaresConfigurationBesideFirstSeam_whenModuleDeclaresNone() {
		let fixture = GraphFuzzerFixture.seamCorpusFixture(seed: 1, swiftFileContent: [
			"// module: FuzzFeature\n@Instantiable(generateDependencyTree: true)\npublic struct S1_Home: Instantiable {}",
			"// module: FuzzApp\n@Instantiable(isRoot: true)\npublic struct S1_Root: Instantiable {}",
		])

		#expect(fixture.swiftFileContent == [
			"// module: FuzzFeature\n@Instantiable(generateDependencyTree: true)\npublic struct S1_Home: Instantiable {}\n\n#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n",
			"// module: FuzzApp\n@Instantiable(isRoot: true)\npublic struct S1_Root: Instantiable {}",
		])
	}

	@Test
	func seamCorpusFixture_mergesArgumentIntoConfiguration_whenModuleDeclaresOne() {
		let fixture = GraphFuzzerFixture.seamCorpusFixture(seed: 1, swiftFileContent: [
			"// module: FuzzFeature\n@Instantiable(generateDependencyTree: true)\npublic struct S1_Home: Instantiable {}",
			"// module: FuzzFeature\n// file: SafeDIConfiguration.swift\n#SafeDIConfiguration(additionalDirectoriesToInclude: [])",
		])

		#expect(fixture.swiftFileContent == [
			"// module: FuzzFeature\n@Instantiable(generateDependencyTree: true)\npublic struct S1_Home: Instantiable {}",
			"// module: FuzzFeature\n// file: SafeDIConfiguration.swift\n#SafeDIConfiguration(additionalDirectoriesToInclude: [], generatePlainDependencyTreeInitializers: true)",
		])
	}

	@Test
	func seamCorpusFixture_leavesModuleAsItIs_whenModuleSetsArgument() {
		let contents = [
			"// module: FuzzFeature\n@Instantiable(generateDependencyTree: true)\npublic struct S1_Home: Instantiable {}",
			"// module: FuzzFeature\n#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)",
		]

		#expect(GraphFuzzerFixture.seamCorpusFixture(seed: 1, swiftFileContent: contents).swiftFileContent == contents)
	}

	@Test
	func seamCorpusFixture_leavesModulesAsTheyAre_whenNoModuleDeclaresSeam() {
		let contents = [
			"// module: FuzzFeature\n@Instantiable\npublic struct S1_Home: Instantiable {}",
			"// module: FuzzApp\n@Instantiable(isRoot: true)\npublic struct S1_Root: Instantiable {}",
		]

		#expect(GraphFuzzerFixture.seamCorpusFixture(seed: 1, swiftFileContent: contents).swiftFileContent == contents)
	}

	// MARK: Fixtures

	/// `Home`, whose place `api` is at its boundary: a seam that takes a builder struct, in a module that generates
	/// readable initializers.
	private static let switchedHome = """
	extension Home {
	    @frozen nonisolated public enum SafeDIScope_Api {
	        case api(api_Values)

	        nonisolated public struct api_Values {}

	        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
	            public let api: (api_Values) -> __safeDI_Built

	            public init(api: @escaping (api_Values) -> __safeDI_Built) {
	                self.api = api
	            }

	            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
	                self.api = { _ in __safeDI_builder() }
	            }
	        }
	    }

	    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
	    public init(apiBuilder: @escaping () -> any Api) {
	        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
	    }

	    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
	    /// From code you write, call the initializer above instead.
	    public init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
	        let api: any Api = __safeDI_apiBuilder.api(SafeDIScope_Api.api_Values())
	        self.init(api: api)
	    }
	}

	extension Home {
	    public enum __safeDI_Home_74DEAFE93792C3B0 {}
	}

	"""

	/// `Home`, which takes `token` and whose place `api` is at its boundary: a seam that takes a builder struct, in a module
	/// that generates readable initializers.
	private static let switchedHomeWithPassThrough = """
	extension Home {
	    @frozen nonisolated public enum SafeDIScope_Api {
	        case api(api_Values)

	        nonisolated public struct api_Values {
	            public let token: Token
	        }

	        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
	            public let api: (api_Values) -> __safeDI_Built

	            public init(api: @escaping (api_Values) -> __safeDI_Built) {
	                self.api = api
	            }

	            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
	                self.api = { _ in __safeDI_builder() }
	            }
	        }
	    }

	    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
	    public init(token: Token, apiBuilder: @escaping () -> any Api) {
	        self.init(__safeDI_token: token, __safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
	    }

	    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
	    /// From code you write, call the initializer above instead.
	    public init(__safeDI_token token: Token, __safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
	        let api: any Api = __safeDI_apiBuilder.api(SafeDIScope_Api.api_Values(token: token))
	        self.init(token: token, api: api)
	    }
	}

	extension Home {
	    public enum __safeDI_Home_4F69E85EF363C970 {}
	}

	"""

	/// `Home`, whose place `api` takes a builder struct and whose `livePanel_PanelBuilder`, which `panelBuilder` forwards a
	/// `String` to, keeps its closure over its enum: `Inner`, a seam of another module, passes up its own place of it.
	private static let switchedAndKeptHome = """
	extension Home {
	    @frozen nonisolated public enum SafeDIScope_Api {
	        case api(api_Values)

	        nonisolated public struct api_Values {
	            public let inner: Inner
	        }

	        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
	            public let api: (api_Values) -> __safeDI_Built

	            public init(api: @escaping (api_Values) -> __safeDI_Built) {
	                self.api = api
	            }

	            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
	                self.api = { _ in __safeDI_builder() }
	            }
	        }
	    }

	    @frozen public enum SafeDIScope_LivePanel_Panel {
	        case panelBuilder(panelBuilder_Values, String)
	        case inner(Inner.SafeDIScope_LivePanel_Panel)

	        public struct panelBuilder_Values {
	            public let inner: Inner
	            public let api: any Api
	        }
	    }

	    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
	    public init(apiBuilder: @escaping () -> any Api, livePanel_PanelBuilder: @escaping (SafeDIScope_LivePanel_Panel) -> any Panel) {
	        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder), __safeDI_livePanel_PanelBuilder: livePanel_PanelBuilder)
	    }

	    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
	    /// From code you write, call the initializer above instead.
	    public init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>, __safeDI_livePanel_PanelBuilder: @escaping (SafeDIScope_LivePanel_Panel) -> any Panel) {
	        func __safeDI_inner() -> Inner {
	            _ = Inner.__safeDI_Inner_A92AD223E64EBA2D.self // If this line does not compile, compile the code SafeDI generates for module FuzzCore into FuzzCore: under Bazel, add FuzzCore’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
	            return Inner(__safeDI_livePanel_PanelBuilder: .init(panelBuilder: { __safeDI_panelBuilderValues in { forwarded in __safeDI_livePanel_PanelBuilder(.inner(.panelBuilder(__safeDI_panelBuilderValues, forwarded))) } }))
	        }
	        let inner: Inner = __safeDI_inner()
	        let api: any Api = __safeDI_apiBuilder.api(SafeDIScope_Api.api_Values(inner: inner))
	        let panelBuilder = ErasedInstantiator<String, any Panel> {
	            __safeDI_livePanel_PanelBuilder(.panelBuilder(SafeDIScope_LivePanel_Panel.panelBuilder_Values(inner: inner, api: api), $0))
	        }
	        self.init(api: api, panelBuilder: panelBuilder, inner: inner)
	    }
	}

	extension Home {
	    public enum __safeDI_Home_1290934B6D80385E {}
	}

	"""

	/// `Home`, whose place `api` and whose `panelBuilder`, which forwards a `String`, each take a builder struct, in a module
	/// that generates readable initializers: the member of `panelBuilder` returns its wrapper's `Builder`.
	private static let switchedForwardingHome = """
	extension Home {
	    @frozen nonisolated public enum SafeDIScope_Api {
	        case api(api_Values)

	        nonisolated public struct api_Values {}

	        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
	            public let api: (api_Values) -> __safeDI_Built

	            public init(api: @escaping (api_Values) -> __safeDI_Built) {
	                self.api = api
	            }

	            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
	                self.api = { _ in __safeDI_builder() }
	            }
	        }
	    }

	    @frozen nonisolated public enum SafeDIScope_LivePanel_Panel {
	        case panelBuilder(panelBuilder_Values, String)

	        nonisolated public struct panelBuilder_Values {
	            public let api: any Api
	        }

	        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
	            public let panelBuilder: (panelBuilder_Values) -> ErasedInstantiator<String, __safeDI_Built>.Builder

	            public init(panelBuilder: @escaping (panelBuilder_Values) -> ErasedInstantiator<String, __safeDI_Built>.Builder) {
	                self.panelBuilder = panelBuilder
	            }

	            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
	                self.panelBuilder = { _ in __safeDI_builder }
	            }
	        }
	    }

	    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
	    public init(apiBuilder: @escaping () -> any Api, livePanel_PanelBuilder: @escaping ErasedInstantiator<String, any Panel>.Builder) {
	        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder), __safeDI_livePanel_PanelBuilder: .init(__safeDI_noScope: livePanel_PanelBuilder))
	    }

	    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
	    /// From code you write, call the initializer above instead.
	    public init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>, __safeDI_livePanel_PanelBuilder: SafeDIScope_LivePanel_Panel.__safeDI_Builder<any Panel>) {
	        let api: any Api = __safeDI_apiBuilder.api(SafeDIScope_Api.api_Values())
	        let panelBuilder = ErasedInstantiator<String, any Panel>(__safeDI_livePanel_PanelBuilder.panelBuilder(SafeDIScope_LivePanel_Panel.panelBuilder_Values(api: api)))
	        self.init(api: api, panelBuilder: panelBuilder)
	    }
	}

	extension Home {
	    public enum __safeDI_Home_97953C757FA68306 {}
	}

	"""

	/// `Home`, whose place `api` is built inside `Worker`'s `@Sendable` function: the `@Sendable` root's struct, and the
	/// empty struct its member takes.
	private static let switchedSendableHome = """
	extension Home {
	    @frozen nonisolated public enum SafeDIScope_Api {
	        @frozen nonisolated public enum Worker_Scope {
	            case detail(detail_Values, SafeDIScope_Api.Detail_Scope)

	            nonisolated public struct detail_Values {
	                public let logger: Logger
	            }

	            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
	                public let detail: (detail_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

	                public init(detail: @escaping (detail_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
	                    self.detail = detail
	                }

	                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
	                    self.detail = { _ in .init(__safeDI_noScope: __safeDI_builder) }
	                }
	            }
	        }

	        @frozen nonisolated public enum Detail_Scope {
	            case api(api_Values)

	            nonisolated public struct api_Values {}

	            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
	                public let api: (api_Values) -> __safeDI_Built

	                public init(api: @escaping (api_Values) -> __safeDI_Built) {
	                    self.api = api
	                }

	                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
	                    self.api = { _ in __safeDI_builder() }
	                }
	            }
	        }
	    }

	    @frozen nonisolated public enum SafeDISendableScope_Api {
	        case workerBuilder(SafeDIScope_Api.Worker_Scope)

	        nonisolated public struct workerBuilder_Values: Sendable {}

	        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
	            public let workerBuilder: @Sendable (workerBuilder_Values) -> SafeDIScope_Api.Worker_Scope.__safeDI_Builder<__safeDI_Built>

	            public init(workerBuilder: @escaping @Sendable (workerBuilder_Values) -> SafeDIScope_Api.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
	                self.workerBuilder = workerBuilder
	            }

	            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
	                self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
	            }
	        }
	    }
	}

	"""

	/// `Inner`, which keeps its closure over its enum, whose case holds `Innermost`'s, in a module that generates no
	/// readable initializers.
	private static let keptInner = """
	extension Inner {
	    @frozen public enum SafeDIScope_Service {
	        case innermost(Innermost.SafeDIScope_Service)
	    }

	    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
	    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
	    public convenience init(__safeDI_serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
	        let navigator = Navigator()
	        func __safeDI_innermost() -> Innermost {
	            _ = Innermost.__safeDI_Innermost_AFB8CC1B9186E9DE.self
	            return Innermost(__safeDI_serviceBuilder: .init(
	                detailBuilder: { __safeDI_detailBuilderValues in
	                    .init(service: { __safeDI_serviceValues in __safeDI_serviceBuilder(.innermost(.detailBuilder(__safeDI_detailBuilderValues, .service(__safeDI_serviceValues)))) })
	                }
	            ))
	        }
	        let innermost: Innermost = __safeDI_innermost()
	        self.init(navigator: navigator, innermost: innermost)
	    }
	}

	extension Inner {
	    public enum __safeDI_Inner_897570648FDA2A58 {}
	}

	"""

	/// `Root`'s call of `HoleSeam`, whose fill of `holeService` builds `HoleSeam` again in a `SendableInstantiator`.
	private static let fillCallingSendableLevelFunction = """
	extension Root {
	    public init() {
	        func __safeDI_holeSeam() -> HoleSeam {
	            @Sendable nonisolated func __safeDI_holeServiceBuilder_HoleSeam_holeService(_ scope: HoleSeam.SafeDIScope_HoleService.holeService_Values) -> any HoleService {
	                func __safeDI_holeService() -> HoleImpl {
	                    @Sendable nonisolated func __safeDI_holeSeamBuilder() -> HoleSeam {
	                        return HoleSeam(__safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_HoleSeam())
	                    }
	                    let holeSeamBuilder = SendableInstantiator<HoleSeam>(__safeDI_holeSeamBuilder)
	                    return HoleImpl(holeSeamBuilder: holeSeamBuilder)
	                }
	                let holeService: any HoleService = __safeDI_holeService()
	                return holeService
	            }
	            @Sendable nonisolated func __safeDI_holeServiceBuilder_HoleSeam() -> HoleSeam.SafeDIScope_HoleService.__safeDI_Builder<any HoleService> {
	                .init(holeService: { scope in __safeDI_holeServiceBuilder_HoleSeam_holeService(scope) })
	            }
	            return HoleSeam(__safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder_HoleSeam())
	        }
	        let holeSeam: HoleSeam = __safeDI_holeSeam()
	        self.init(holeSeam: holeSeam)
	    }
	}

	"""

	/// `HoleOuter`, which calls `HoleSeam` and passes its place of `HoleService` up: its builder struct's member builds
	/// `HoleSeam`'s.
	private static let passingUpOuter = """
	extension HoleOuter {
	    nonisolated public enum SafeDIScope_HoleService {
	        nonisolated public struct holeSeam_Values: Sendable {}

	        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
	            public let holeSeam: (holeSeam_Values) -> HoleSeam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>

	            public init(holeSeam: @escaping (holeSeam_Values) -> HoleSeam.SafeDIScope_HoleService.__safeDI_Builder<__safeDI_Built>) {
	                self.holeSeam = holeSeam
	            }

	            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
	                self.holeSeam = { _ in .init(__safeDI_noScope: __safeDI_builder) }
	            }
	        }
	    }

	    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
	    public convenience init(__safeDI_holeServiceBuilder: SafeDIScope_HoleService.__safeDI_Builder<any HoleService>) {
	        func __safeDI_holeSeam() -> HoleSeam {
	            return HoleSeam(__safeDI_holeServiceBuilder: __safeDI_holeServiceBuilder.holeSeam(SafeDIScope_HoleService.holeSeam_Values()))
	        }
	        let holeSeam: HoleSeam = __safeDI_holeSeam()
	        self.init(holeSeam: holeSeam)
	    }
	}

	"""

	/// `Root`'s call of `FillCallShell`, whose place of `FillCallUserService` is inside `FillCallInner`'s fill,
	/// `FillCallTrackerImpl`, which calls `FillCallService`, which passes the place up.
	private static let fillCallingSeamPassingPlaceUp = """
	extension Root {
	    public convenience init() {
	        func __safeDI_fillCallShell() -> FillCallShell {
	            func __safeDI_fillCallUserServiceBuilder_FillCallShell() -> FillCallShell.SafeDIScope_FillCallUserService.__safeDI_Builder<any FillCallUserService> {
	                .init(fillCallInner_fillCallTrackerBuilder: { _ in __safeDI_fillCallUserServiceBuilder_FillCallShell_FillCallInner() })
	            }
	            func __safeDI_fillCallUserServiceBuilder_FillCallShell_FillCallTrackerImpl_Scope() -> FillCallShell.SafeDIScope_FillCallUserService.FillCallTrackerImpl_Scope.__safeDI_Builder<any FillCallUserService> {
	                .init(fillCallServiceBuilder: { _ in __safeDI_fillCallUserServiceBuilder_FillCallService() })
	            }
	            func __safeDI_fillCallUserServiceBuilder_FillCallService() -> FillCallService.SafeDIScope_FillCallUserService.__safeDI_Builder<any FillCallUserService> {
	                .init(fillCallProfileBuilder: { _ in __safeDI_fillCallUserServiceBuilder_FillCallService_FillCallProfile_Scope() })
	            }
	            func __safeDI_fillCallUserServiceBuilder_FillCallService_FillCallProfile_Scope() -> FillCallService.SafeDIScope_FillCallUserService.FillCallProfile_Scope.__safeDI_Builder<any FillCallUserService> {
	                .init(fillCallUserService: { _ in
	                    let fillCallUserService: any FillCallUserService = FillCallUserServiceImpl()
	                    return fillCallUserService
	                })
	            }
	            func __safeDI_fillCallUserServiceBuilder_FillCallShell_FillCallInner() -> FillCallInner.SafeDIScope_FillCallTracker.__safeDI_Builder<FillCallShell.SafeDIScope_FillCallUserService.FillCallTrackerImpl_Scope.__safeDI_Builder<any FillCallUserService>> {
	                .init(fillCallBadgeBuilder: { _ in __safeDI_fillCallUserServiceBuilder_FillCallShell_FillCallInner_FillCallBadge_Scope() })
	            }
	            func __safeDI_fillCallUserServiceBuilder_FillCallShell_FillCallInner_FillCallBadge_Scope() -> FillCallInner.SafeDIScope_FillCallTracker.FillCallBadge_Scope.__safeDI_Builder<FillCallShell.SafeDIScope_FillCallUserService.FillCallTrackerImpl_Scope.__safeDI_Builder<any FillCallUserService>> {
	                .init(fillCallTracker: { _ in __safeDI_fillCallUserServiceBuilder_FillCallShell_FillCallTrackerImpl_Scope() })
	            }
	            return FillCallShell(__safeDI_fillCallUserServiceBuilder: __safeDI_fillCallUserServiceBuilder_FillCallShell())
	        }
	        let fillCallShell: FillCallShell = __safeDI_fillCallShell()
	        self.init(fillCallShell: fillCallShell)
	    }
	}

	"""

	/// `Root`'s call of `HoleSeam`, whose dispatchers keep their switch over its enum, and whose fill of `holeService`
	/// builds `HoleSeam` again, handing it a struct converted from them. The tool generates this where the fill also
	/// builds a seam that passes `HoleSeam`'s place up; that call, which passes a dispatcher of its own, is left out, so
	/// that only the converted struct passes the fill.
	private static let fillPassingConvertedStruct = """
	extension Root {
	    public init() {
	        func __safeDI_holeSeam() -> HoleSeam {
	            func __safeDI_holeServiceBuilder_HoleSeam(_ scope: HoleSeam.SafeDIScope_HoleService) -> any HoleService {
	                switch scope {
	                case let .holeOwnerBuilder(values, scope): return __safeDI_holeServiceBuilder_HoleSeam_HoleOwner_Scope(scope, holeAnalytics: values.holeAnalytics)
	                }
	            }
	            func __safeDI_holeServiceBuilder_HoleSeam_HoleOwner_Scope(_ scope: HoleSeam.SafeDIScope_HoleService.HoleOwner_Scope, holeAnalytics: HoleAnalytics) -> any HoleService {
	                switch scope {
	                case .holeService:
	                    func __safeDI_holeService() -> HoleImpl {
	                        func __safeDI_holeSeamBuilder() -> HoleSeam {
	                            return HoleSeam(__safeDI_holeServiceBuilder: .init(
	                                holeOwnerBuilder: { __safeDI_holeOwnerBuilderValues in
	                                    .init(holeService: { __safeDI_holeServiceValues in __safeDI_holeServiceBuilder_HoleSeam(.holeOwnerBuilder(__safeDI_holeOwnerBuilderValues, .holeService(__safeDI_holeServiceValues))) })
	                                }
	                            ))
	                        }
	                        let holeSeamBuilder = Instantiator<HoleSeam>(__safeDI_holeSeamBuilder)
	                        return HoleImpl(holeAnalytics: holeAnalytics, holeSeamBuilder: holeSeamBuilder)
	                    }
	                    let holeService: any HoleService = __safeDI_holeService()
	                    return holeService
	                }
	            }
	            return HoleSeam(__safeDI_holeServiceBuilder: .init(
	                holeOwnerBuilder: { __safeDI_holeOwnerBuilderValues in
	                    .init(holeService: { __safeDI_holeServiceValues in __safeDI_holeServiceBuilder_HoleSeam(.holeOwnerBuilder(__safeDI_holeOwnerBuilderValues, .holeService(__safeDI_holeServiceValues))) })
	                }
	            ))
	        }
	        let holeSeam: HoleSeam = __safeDI_holeSeam()
	        self.init(holeSeam: holeSeam)
	    }
	}

	"""
}
