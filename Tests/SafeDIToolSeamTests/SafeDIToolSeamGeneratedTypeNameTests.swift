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

/// A person's type named like a type a seam's generated code declares: each test generates `Home`, a seam in `Feature`
/// that builds `Detail` through `detailBuilder`, whose `Leaf` holds the place `api: any Api` that `App` fills with
/// `LiveApi`, beside such a type, and shows that the generated code names the person's type where the person wrote it
/// and compiles, or that SafeDI reports the name.
struct SafeDIToolSeamGeneratedTypeNameTests: ~Copyable {
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
	mutating func generate_namesValuesStructApart_whenSeamBindsUserTypeNamedLikeIt() async throws {
		// `Home` binds `detailValues` of `Feature`'s own type `detailBuilder_Values` before `detailBuilder`, and `LiveApi` reads
		// it: inside `SafeDIScope_Api`, the payload struct of that name would hide the type its field spells, so the struct
		// takes `_`, and `App`'s level functions spell the person's type.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(homeDeclarations: ["@Instantiated public let detailValues: detailBuilder_Values", Self.detailBuilder], featureTypes: [seamFixtureType(named: "detailBuilder_Values", isFinalClass: true, declarations: [])], liveApiDeclarations: ["@Received public let detailValues: detailBuilder_Values"]), integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    @frozen nonisolated public enum SafeDIScope_Api {
		        case detailBuilder(detailBuilder_Values_, SafeDIScope_Api.Detail_Scope)

		        nonisolated public struct detailBuilder_Values_ {
		            public let detailValues: detailBuilder_Values
		        }

		        @frozen nonisolated public enum Detail_Scope {
		            case leafBuilder(leafBuilder_Values, SafeDIScope_Api.Leaf_Scope)

		            nonisolated public struct leafBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let leafBuilder: (leafBuilder_Values) -> SafeDIScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(leafBuilder: @escaping (leafBuilder_Values) -> SafeDIScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.leafBuilder = leafBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.leafBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        @frozen nonisolated public enum Leaf_Scope {
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values_) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values_) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.detailBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let detailValues = detailBuilder_Values()
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIScope_Api.detailBuilder_Values_(detailValues: detailValues))
		        func __safeDI_detailBuilder() -> Detail {
		            let __safeDI_apiBuilder_leafBuilder = __safeDI_apiBuilder_detailBuilder.leafBuilder(SafeDIScope_Api.Detail_Scope.leafBuilder_Values())
		            func __safeDI_leafBuilder() -> Leaf {
		                let api: any Api = __safeDI_apiBuilder_leafBuilder.api(SafeDIScope_Api.Leaf_Scope.api_Values())
		                return Leaf(api: api)
		            }
		            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
		            return Detail(leafBuilder: leafBuilder)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(detailValues: detailValues, detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_E4745F45E15AB187 {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_E4745F45E15AB187.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { values in __safeDI_apiBuilder_Home_Detail_Scope(detailValues: values.detailValues) })
		            }
		            func __safeDI_apiBuilder_Home_Detail_Scope(detailValues: detailBuilder_Values) -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(leafBuilder: { _ in __safeDI_apiBuilder_Home_Leaf_Scope(detailValues: detailValues) })
		            }
		            func __safeDI_apiBuilder_Home_Leaf_Scope(detailValues: detailBuilder_Values) -> Home.SafeDIScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi(detailValues: detailValues)
		                    return api
		                })
		            }
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesTypesEnumApart_whenTreeTypeIsNamedLikeAnotherTypesEnum() async throws {
		// `Detail` builds `Detail_Scope`, a type of the tree whose name is `Detail`'s enum's: `Detail_Scope`'s enum is
		// `Detail_Scope_Scope`, and the initializer spells the person's type outside the root enum.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(featureTypes: [seamFixtureType(named: "Detail_Scope", isFinalClass: true, declarations: ["@Instantiated public let leafBuilder: Instantiator<Leaf>"])], detailDeclarations: ["@Instantiated public let scopeBuilder: Instantiator<Detail_Scope>"]), integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    @frozen nonisolated public enum SafeDIScope_Api {
		        case detailBuilder(detailBuilder_Values, SafeDIScope_Api.Detail_Scope)

		        nonisolated public struct detailBuilder_Values {}

		        @frozen nonisolated public enum Detail_Scope {
		            case scopeBuilder(scopeBuilder_Values, SafeDIScope_Api.Detail_Scope_Scope)

		            nonisolated public struct scopeBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let scopeBuilder: (scopeBuilder_Values) -> SafeDIScope_Api.Detail_Scope_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(scopeBuilder: @escaping (scopeBuilder_Values) -> SafeDIScope_Api.Detail_Scope_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.scopeBuilder = scopeBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.scopeBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        @frozen nonisolated public enum Detail_Scope_Scope {
		            case leafBuilder(leafBuilder_Values, SafeDIScope_Api.Leaf_Scope)

		            nonisolated public struct leafBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let leafBuilder: (leafBuilder_Values) -> SafeDIScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(leafBuilder: @escaping (leafBuilder_Values) -> SafeDIScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.leafBuilder = leafBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.leafBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        @frozen nonisolated public enum Leaf_Scope {
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.detailBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIScope_Api.detailBuilder_Values())
		        func __safeDI_detailBuilder() -> Detail {
		            let __safeDI_apiBuilder_scopeBuilder = __safeDI_apiBuilder_detailBuilder.scopeBuilder(SafeDIScope_Api.Detail_Scope.scopeBuilder_Values())
		            func __safeDI_scopeBuilder() -> Detail_Scope {
		                let __safeDI_apiBuilder_leafBuilder = __safeDI_apiBuilder_scopeBuilder.leafBuilder(SafeDIScope_Api.Detail_Scope_Scope.leafBuilder_Values())
		                func __safeDI_leafBuilder() -> Leaf {
		                    let api: any Api = __safeDI_apiBuilder_leafBuilder.api(SafeDIScope_Api.Leaf_Scope.api_Values())
		                    return Leaf(api: api)
		                }
		                let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
		                return Detail_Scope(leafBuilder: leafBuilder)
		            }
		            let scopeBuilder = Instantiator<Detail_Scope>(__safeDI_scopeBuilder)
		            return Detail(scopeBuilder: scopeBuilder)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_56BB1654829ADF2F {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_56BB1654829ADF2F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { _ in __safeDI_apiBuilder_Home_Detail_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Detail_Scope() -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(scopeBuilder: { _ in __safeDI_apiBuilder_Home_Detail_Scope_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Detail_Scope_Scope() -> Home.SafeDIScope_Api.Detail_Scope_Scope.__safeDI_Builder<any Api> {
		                .init(leafBuilder: { _ in __safeDI_apiBuilder_Home_Leaf_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Leaf_Scope() -> Home.SafeDIScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi()
		                    return api
		                })
		            }
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsCallingModulesOwnType_whenItIsNamedLikeSeamsRootEnum() async throws {
		// `App` declares `SafeDIScope_Api`, which `LiveApi` instantiates: `App`'s level functions spell `Home`'s root enum
		// qualified, so the bare name in the fill is `App`'s type.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(liveApiDeclarations: ["@Instantiated public let local: SafeDIScope_Api"], appTypes: [seamFixtureType(named: "SafeDIScope_Api", isFinalClass: true, declarations: [])]), integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    @frozen nonisolated public enum SafeDIScope_Api {
		        case detailBuilder(detailBuilder_Values, SafeDIScope_Api.Detail_Scope)

		        nonisolated public struct detailBuilder_Values {}

		        @frozen nonisolated public enum Detail_Scope {
		            case leafBuilder(leafBuilder_Values, SafeDIScope_Api.Leaf_Scope)

		            nonisolated public struct leafBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let leafBuilder: (leafBuilder_Values) -> SafeDIScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(leafBuilder: @escaping (leafBuilder_Values) -> SafeDIScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.leafBuilder = leafBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.leafBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        @frozen nonisolated public enum Leaf_Scope {
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.detailBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIScope_Api.detailBuilder_Values())
		        func __safeDI_detailBuilder() -> Detail {
		            let __safeDI_apiBuilder_leafBuilder = __safeDI_apiBuilder_detailBuilder.leafBuilder(SafeDIScope_Api.Detail_Scope.leafBuilder_Values())
		            func __safeDI_leafBuilder() -> Leaf {
		                let api: any Api = __safeDI_apiBuilder_leafBuilder.api(SafeDIScope_Api.Leaf_Scope.api_Values())
		                return Leaf(api: api)
		            }
		            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
		            return Detail(leafBuilder: leafBuilder)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_0D55A4C8F1E6910B {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_0D55A4C8F1E6910B.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home_Leaf_Scope_api(_ scope: Home.SafeDIScope_Api.Leaf_Scope.api_Values) -> any Api {
		                func __safeDI_api() -> LiveApi {
		                    let local = SafeDIScope_Api()
		                    return LiveApi(local: local)
		                }
		                let api: any Api = __safeDI_api()
		                return api
		            }
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { _ in __safeDI_apiBuilder_Home_Detail_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Detail_Scope() -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(leafBuilder: { _ in __safeDI_apiBuilder_Home_Leaf_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Leaf_Scope() -> Home.SafeDIScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
		                .init(api: { scope in __safeDI_apiBuilder_Home_Leaf_Scope_api(scope) })
		            }
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSeam_whenCallingModuleRenamesItsTypeNamedLikeSeam() async throws {
		// The remedy of `generate_reportsDuplicateName_whenCallingModuleDeclaresInstantiableNamedLikeSeam`: `App`'s type,
		// renamed `AppHome`, no longer shares the seam's name, and `App` calls `Home`.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(appTypes: [seamFixtureType(named: "AppHome", isFinalClass: true, declarations: [])]), integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    @frozen nonisolated public enum SafeDIScope_Api {
		        case detailBuilder(detailBuilder_Values, SafeDIScope_Api.Detail_Scope)

		        nonisolated public struct detailBuilder_Values {}

		        @frozen nonisolated public enum Detail_Scope {
		            case leafBuilder(leafBuilder_Values, SafeDIScope_Api.Leaf_Scope)

		            nonisolated public struct leafBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let leafBuilder: (leafBuilder_Values) -> SafeDIScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(leafBuilder: @escaping (leafBuilder_Values) -> SafeDIScope_Api.Leaf_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.leafBuilder = leafBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.leafBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        @frozen nonisolated public enum Leaf_Scope {
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIScope_Api.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.detailBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(SafeDIScope_Api.detailBuilder_Values())
		        func __safeDI_detailBuilder() -> Detail {
		            let __safeDI_apiBuilder_leafBuilder = __safeDI_apiBuilder_detailBuilder.leafBuilder(SafeDIScope_Api.Detail_Scope.leafBuilder_Values())
		            func __safeDI_leafBuilder() -> Leaf {
		                let api: any Api = __safeDI_apiBuilder_leafBuilder.api(SafeDIScope_Api.Leaf_Scope.api_Values())
		                return Leaf(api: api)
		            }
		            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
		            return Detail(leafBuilder: leafBuilder)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_0D55A4C8F1E6910B {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_0D55A4C8F1E6910B.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
		                .init(detailBuilder: { _ in __safeDI_apiBuilder_Home_Detail_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Detail_Scope() -> Home.SafeDIScope_Api.Detail_Scope.__safeDI_Builder<any Api> {
		                .init(leafBuilder: { _ in __safeDI_apiBuilder_Home_Leaf_Scope() })
		            }
		            func __safeDI_apiBuilder_Home_Leaf_Scope() -> Home.SafeDIScope_Api.Leaf_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = LiveApi()
		                    return api
		                })
		            }
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""")
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicateName_whenCallingModuleDeclaresInstantiableNamedLikeSeam() async {
		// `App` declares an @Instantiable `Home` beside `Feature`'s seam `Home`, which it can name too: the duplicate-name
		// error, whose remedy is to rename one.
		let message = "error: `Home` is declared in modules `App` and `Feature`. SafeDI tells apart by name the @Instantiable types a module can name, and every seam and public mock a run reads. Rename one."
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]?["Home.swift"] ?? ""):3:1: \(message)
			\(fixtures["Feature"]?["Home.swift"] ?? ""):1:1: \(message)
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(liveApiDeclarations: [], appTypes: [seamFixtureType(named: "Home", isFinalClass: true, declarations: [])]),
				integration: .moduleInfo,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let detailBuilder = "@Instantiated public let detailBuilder: Instantiator<Detail>"

	/// `Feature`, declaring `Home` with `homeDeclarations`, `Detail` with `detailDeclarations`, `Leaf`, `Api` and
	/// `featureTypes`, and `App`, declaring `LiveApi` with `liveApiDeclarations`, `Root` and `appTypes`.
	private static func modules(
		homeDeclarations: [String] = [detailBuilder],
		featureTypes: [String] = [],
		detailDeclarations: [String] = ["@Instantiated public let leafBuilder: Instantiator<Leaf>"],
		liveApiDeclarations: [String] = [],
		appTypes: [String] = [],
	) -> [ModuleFixture] {
		let feature = [
			"public protocol Api: AnyObject {}",
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Instantiated public let api: any Api"]),
			seamFixtureType(named: "Detail", isFinalClass: true, declarations: detailDeclarations),
			seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: homeDeclarations),
		] + featureTypes
		let app = [
			seamFixtureType(named: "LiveApi", isFinalClass: true, declarations: liveApiDeclarations, conformances: ", Api")
				.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Api.self])\n"),
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"]),
		] + appTypes
		return [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// Expects every module of `output` to have compiled, where compile verification is enabled.
	private static func expectCompiles(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		for module in compilation.modules {
			#expect(module.result.exitCode == 0, "\(module.moduleName): \(module.result.stderr)", sourceLocation: sourceLocation)
		}
	}
}
