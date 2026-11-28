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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let detailBuilder: (detailBuilder_Values) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: @escaping (detailBuilder_Values) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let leafBuilder: __safeDI_ApiCarrier_Leaf<__safeDI_Built>

		        public init(leafBuilder: __safeDI_ApiCarrier_Leaf<__safeDI_Built>) {
		            self.leafBuilder = leafBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Leaf<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let detailValues = detailBuilder_Values()
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder(detailValues)
		        @inline(never) func __safeDI_leafBuilder(__safeDI_apiBuilder_leafBuilder: __safeDI_ApiCarrier_Leaf<any Api>) -> Leaf {
		            let api: any Api = __safeDI_apiBuilder_leafBuilder.api()
		            return Leaf(api: api)
		        }
		        @inline(never) func __safeDI_detailBuilder() -> Detail {
		            let __safeDI_apiBuilder_leafBuilder = __safeDI_apiBuilder_detailBuilder.leafBuilder
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(__safeDI_apiBuilder_leafBuilder: __safeDI_apiBuilder_leafBuilder)
		            }
		            return Detail(leafBuilder: leafBuilder)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(detailValues: detailValues, detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_CF7F566E9AD09F37 {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(detailBuilder: { values_detailValues in __safeDI_apiBuilder_Home_Detail_Scope(detailValues: values_detailValues) })
		        }
		        func __safeDI_apiBuilder_Home_Detail_Scope(detailValues: detailBuilder_Values) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(leafBuilder: __safeDI_apiBuilder_Home_Leaf_Scope(detailValues: detailValues))
		        }
		        func __safeDI_apiBuilder_Home_Leaf_Scope(detailValues: detailBuilder_Values) -> Home.__safeDI_ApiCarrier_Leaf<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi(detailValues: detailValues)
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_CF7F566E9AD09F37.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let detailBuilder: __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let scopeBuilder: __safeDI_ApiCarrier_Detail_Scope<__safeDI_Built>

		        public init(scopeBuilder: __safeDI_ApiCarrier_Detail_Scope<__safeDI_Built>) {
		            self.scopeBuilder = scopeBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail_Scope<__safeDI_Built> {
		        public let leafBuilder: __safeDI_ApiCarrier_Leaf<__safeDI_Built>

		        public init(leafBuilder: __safeDI_ApiCarrier_Leaf<__safeDI_Built>) {
		            self.leafBuilder = leafBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Leaf<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder
		        @inline(never) func __safeDI_scopeBuilder(__safeDI_apiBuilder_scopeBuilder: __safeDI_ApiCarrier_Detail_Scope<any Api>) -> Detail_Scope {
		            let __safeDI_apiBuilder_leafBuilder = __safeDI_apiBuilder_scopeBuilder.leafBuilder
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(__safeDI_apiBuilder_leafBuilder: __safeDI_apiBuilder_leafBuilder)
		            }
		            return Detail_Scope(leafBuilder: leafBuilder)
		        }
		        @inline(never) func __safeDI_leafBuilder(__safeDI_apiBuilder_leafBuilder: __safeDI_ApiCarrier_Leaf<any Api>) -> Leaf {
		            let api: any Api = __safeDI_apiBuilder_leafBuilder.api()
		            return Leaf(api: api)
		        }
		        @inline(never) func __safeDI_detailBuilder() -> Detail {
		            let __safeDI_apiBuilder_scopeBuilder = __safeDI_apiBuilder_detailBuilder.scopeBuilder
		            let scopeBuilder = Instantiator<Detail_Scope> {
		                __safeDI_scopeBuilder(__safeDI_apiBuilder_scopeBuilder: __safeDI_apiBuilder_scopeBuilder)
		            }
		            return Detail(scopeBuilder: scopeBuilder)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_5E00940DB1757F7F {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(detailBuilder: __safeDI_apiBuilder_Home_Detail_Scope())
		        }
		        func __safeDI_apiBuilder_Home_Detail_Scope() -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(scopeBuilder: __safeDI_apiBuilder_Home_Detail_Scope_Scope())
		        }
		        func __safeDI_apiBuilder_Home_Detail_Scope_Scope() -> Home.__safeDI_ApiCarrier_Detail_Scope<any Api> {
		            .init(leafBuilder: __safeDI_apiBuilder_Home_Leaf_Scope())
		        }
		        func __safeDI_apiBuilder_Home_Leaf_Scope() -> Home.__safeDI_ApiCarrier_Leaf<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi()
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_5E00940DB1757F7F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let detailBuilder: __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let leafBuilder: __safeDI_ApiCarrier_Leaf<__safeDI_Built>

		        public init(leafBuilder: __safeDI_ApiCarrier_Leaf<__safeDI_Built>) {
		            self.leafBuilder = leafBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Leaf<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder.detailBuilder
		        @inline(never) func __safeDI_leafBuilder(__safeDI_apiBuilder_leafBuilder: __safeDI_ApiCarrier_Leaf<any Api>) -> Leaf {
		            let api: any Api = __safeDI_apiBuilder_leafBuilder.api()
		            return Leaf(api: api)
		        }
		        @inline(never) func __safeDI_detailBuilder() -> Detail {
		            let __safeDI_apiBuilder_leafBuilder = __safeDI_apiBuilder_detailBuilder.leafBuilder
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(__safeDI_apiBuilder_leafBuilder: __safeDI_apiBuilder_leafBuilder)
		            }
		            return Detail(leafBuilder: leafBuilder)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_3768984570F7981B {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(detailBuilder: __safeDI_apiBuilder_Home_Detail_Scope())
		        }
		        func __safeDI_apiBuilder_Home_Detail_Scope() -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(leafBuilder: __safeDI_apiBuilder_Home_Leaf_Scope())
		        }
		        func __safeDI_apiBuilder_Home_Leaf_Scope() -> Home.__safeDI_ApiCarrier_Leaf<any Api> {
		            .init(api: {
		                let api: any Api = LiveApi()
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_3768984570F7981B.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
	mutating func generate_spellsUsersTypeNamedBuilt_whenPlaceForwardsIt() async throws {
		// `Leaf`'s place `apiBuilder` forwards `Feature`'s own type `Built`, which each builder struct's member and no-scope
		// initializer spell beside the struct's generic parameter, named `__safeDI_Built` so that `Built` names the person's
		// type inside the struct.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(featureTypes: [Self.built], leafDeclarations: [#"@Instantiated(fulfilledByType: "LiveApi") public let apiBuilder: ErasedInstantiator<Built, any Api>"#], liveApiDeclarations: ["@Forwarded public let built: Built"]), integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_LiveApi_ApiCarrier<__safeDI_Built> {
		        public let detailBuilder: __safeDI_LiveApi_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: __safeDI_LiveApi_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_LiveApi_ApiCarrier_Detail<__safeDI_Built> {
		        public let leafBuilder: __safeDI_LiveApi_ApiCarrier_Leaf<__safeDI_Built>

		        public init(leafBuilder: __safeDI_LiveApi_ApiCarrier_Leaf<__safeDI_Built>) {
		            self.leafBuilder = leafBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_LiveApi_ApiCarrier_Leaf<__safeDI_Built> {
		        public let apiBuilder: () -> ErasedInstantiator<Built, __safeDI_Built>.Builder

		        public init(apiBuilder: @escaping () -> ErasedInstantiator<Built, __safeDI_Built>.Builder) {
		            self.apiBuilder = apiBuilder
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_liveApi_ApiBuilder: __safeDI_LiveApi_ApiCarrier<any Api>) {
		        let __safeDI_liveApi_ApiBuilder_detailBuilder = __safeDI_liveApi_ApiBuilder.detailBuilder
		        @inline(never) func __safeDI_leafBuilder(__safeDI_liveApi_ApiBuilder_leafBuilder: __safeDI_LiveApi_ApiCarrier_Leaf<any Api>) -> Leaf {
		            let apiBuilder = ErasedInstantiator<Built, any Api>(__safeDI_liveApi_ApiBuilder_leafBuilder.apiBuilder())
		            return Leaf(apiBuilder: apiBuilder)
		        }
		        @inline(never) func __safeDI_detailBuilder() -> Detail {
		            let __safeDI_liveApi_ApiBuilder_leafBuilder = __safeDI_liveApi_ApiBuilder_detailBuilder.leafBuilder
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(__safeDI_liveApi_ApiBuilder_leafBuilder: __safeDI_liveApi_ApiBuilder_leafBuilder)
		            }
		            return Detail(leafBuilder: leafBuilder)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_9134C880C0249592 {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_liveApi_ApiBuilder_Home_Leaf_Scope_apiBuilder() -> ErasedInstantiator<Built, any Api>.Builder {
		            return __safeDI_fillBody_AE6C668D9EABCAE6()
		        }
		        func __safeDI_fillBody_AE6C668D9EABCAE6() -> ErasedInstantiator<Built, any Api>.Builder {
		            func __safeDI_apiBuilder(built: Built) -> LiveApi {
		                LiveApi(built: built)
		            }
		            return { forwarded in __safeDI_apiBuilder(built: forwarded) }
		        }
		        func __safeDI_liveApi_ApiBuilder_Home() -> Home.__safeDI_LiveApi_ApiCarrier<any Api> {
		            .init(detailBuilder: __safeDI_liveApi_ApiBuilder_Home_Detail_Scope())
		        }
		        func __safeDI_liveApi_ApiBuilder_Home_Detail_Scope() -> Home.__safeDI_LiveApi_ApiCarrier_Detail<any Api> {
		            .init(leafBuilder: __safeDI_liveApi_ApiBuilder_Home_Leaf_Scope())
		        }
		        func __safeDI_liveApi_ApiBuilder_Home_Leaf_Scope() -> Home.__safeDI_LiveApi_ApiCarrier_Leaf<any Api> {
		            .init(apiBuilder: { __safeDI_liveApi_ApiBuilder_Home_Leaf_Scope_apiBuilder() })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_9134C880C0249592.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_liveApi_ApiBuilder: __safeDI_liveApi_ApiBuilder_Home())
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
	mutating func generate_spellsUsersTypeNamedBuilt_whenPlaceForwardsItInTuple() async throws {
		// As `generate_spellsUsersTypeNamedBuilt_whenPlaceForwardsIt`, with `Built` an element of the tuple `apiBuilder`
		// forwards.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(featureTypes: [Self.built], leafDeclarations: [#"@Instantiated(fulfilledByType: "LiveApi") public let apiBuilder: ErasedInstantiator<(built: Built, id: Int), any Api>"#], liveApiDeclarations: ["@Forwarded public let built: Built", "@Forwarded public let id: Int"]), integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + """
		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_LiveApi_ApiCarrier<__safeDI_Built> {
		        public let detailBuilder: __safeDI_LiveApi_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: __safeDI_LiveApi_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_LiveApi_ApiCarrier_Detail<__safeDI_Built> {
		        public let leafBuilder: __safeDI_LiveApi_ApiCarrier_Leaf<__safeDI_Built>

		        public init(leafBuilder: __safeDI_LiveApi_ApiCarrier_Leaf<__safeDI_Built>) {
		            self.leafBuilder = leafBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_LiveApi_ApiCarrier_Leaf<__safeDI_Built> {
		        public let apiBuilder: () -> ErasedInstantiator<(built: Built, id: Int), __safeDI_Built>.Builder

		        public init(apiBuilder: @escaping () -> ErasedInstantiator<(built: Built, id: Int), __safeDI_Built>.Builder) {
		            self.apiBuilder = apiBuilder
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_liveApi_ApiBuilder: __safeDI_LiveApi_ApiCarrier<any Api>) {
		        let __safeDI_liveApi_ApiBuilder_detailBuilder = __safeDI_liveApi_ApiBuilder.detailBuilder
		        @inline(never) func __safeDI_leafBuilder(__safeDI_liveApi_ApiBuilder_leafBuilder: __safeDI_LiveApi_ApiCarrier_Leaf<any Api>) -> Leaf {
		            let apiBuilder = ErasedInstantiator<(built: Built, id: Int), any Api>(__safeDI_liveApi_ApiBuilder_leafBuilder.apiBuilder())
		            return Leaf(apiBuilder: apiBuilder)
		        }
		        @inline(never) func __safeDI_detailBuilder() -> Detail {
		            let __safeDI_liveApi_ApiBuilder_leafBuilder = __safeDI_liveApi_ApiBuilder_detailBuilder.leafBuilder
		            let leafBuilder = Instantiator<Leaf> {
		                __safeDI_leafBuilder(__safeDI_liveApi_ApiBuilder_leafBuilder: __safeDI_liveApi_ApiBuilder_leafBuilder)
		            }
		            return Detail(leafBuilder: leafBuilder)
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        self.init(detailBuilder: detailBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_98BA726F198227ED {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_liveApi_ApiBuilder_Home_Leaf_Scope_apiBuilder() -> ErasedInstantiator<(built: Built, id: Int), any Api>.Builder {
		            return __safeDI_fillBody_6BB989D8FE1BA293()
		        }
		        func __safeDI_fillBody_6BB989D8FE1BA293() -> ErasedInstantiator<(built: Built, id: Int), any Api>.Builder {
		            func __safeDI_apiBuilder(built: Built, id: Int) -> LiveApi {
		                LiveApi(built: built, id: id)
		            }
		            return { forwarded in __safeDI_apiBuilder(built: forwarded.built, id: forwarded.id) }
		        }
		        func __safeDI_liveApi_ApiBuilder_Home() -> Home.__safeDI_LiveApi_ApiCarrier<any Api> {
		            .init(detailBuilder: __safeDI_liveApi_ApiBuilder_Home_Detail_Scope())
		        }
		        func __safeDI_liveApi_ApiBuilder_Home_Detail_Scope() -> Home.__safeDI_LiveApi_ApiCarrier_Detail<any Api> {
		            .init(leafBuilder: __safeDI_liveApi_ApiBuilder_Home_Leaf_Scope())
		        }
		        func __safeDI_liveApi_ApiBuilder_Home_Leaf_Scope() -> Home.__safeDI_LiveApi_ApiCarrier_Leaf<any Api> {
		            .init(apiBuilder: { __safeDI_liveApi_ApiBuilder_Home_Leaf_Scope_apiBuilder() })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_98BA726F198227ED.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_liveApi_ApiBuilder: __safeDI_liveApi_ApiBuilder_Home())
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
		let message = "error: `Home` is declared in modules `App` and `Feature`. SafeDI tells apart by name the @Instantiable types a module can name, and every type declared with `generateDependencyTree: true` or `generateMock: .public` that a run reads. Rename one."
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

	/// `Built`, a type of `Feature`'s named like the builder struct's generic parameter without its prefix.
	private static let built = "public final class Built {\n    public init() {}\n}"

	/// `Feature`, declaring `Home` with `homeDeclarations`, `Detail` with `detailDeclarations`, `Leaf` with
	/// `leafDeclarations`, `Api` and `featureTypes`, and `App`, declaring `LiveApi` with `liveApiDeclarations`, `Root` and
	/// `appTypes`.
	private static func modules(
		homeDeclarations: [String] = [detailBuilder],
		featureTypes: [String] = [],
		detailDeclarations: [String] = ["@Instantiated public let leafBuilder: Instantiator<Leaf>"],
		leafDeclarations: [String] = ["@Instantiated public let api: any Api"],
		liveApiDeclarations: [String] = [],
		appTypes: [String] = [],
	) -> [ModuleFixture] {
		let feature = [
			"public protocol Api: AnyObject {}",
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: leafDeclarations),
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
