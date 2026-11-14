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

/// A hole on a cycle in a seam's tree. `Hub`, a seam in `Feature`, builds `A`, which builds `B`, whose `aBuilder`
/// re-enters the function `Hub`'s tree builds `A` with. `A` instantiates `api: any Api`, which `Feature` cannot build (a
/// hole), and `App` fills it with `LiveApi`. Inline, the `A` that `B` builds again receives `B`'s declarations through the
/// function's parameters; a fill reads the scope struct or the caller's scope, which hold the same values at every level.
struct SafeDIToolSeamHoleOnCycleTests: ~Copyable {
	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Rejected

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenHoleSitsOnInstantiatorCycleAndFillReceivesLabelOnlyIfAvailable() async {
		// Inline, the `A` that `B` forwarded `2` builds again hands `LiveApi` `count` 2; the fill would read `nil` again.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):11:5: error: `LiveApi` receives `count: Int?`, which `B` declares between where `Hub` instantiates `aBuilder: Instantiator<A>` and where `B` instantiates it again. Inline, the `A` built again receives `B`'s `count`, but the scope SafeDI hands the builder for `A`'s `api: any Api` (case `A_Scope.api` of `apiBuilder`) holds the same values at every level of that cycle. Give `count` on `B` another label, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["B.swift"]):8:5: note: `B` declares `count: Int` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: Self.feature(b: ["@Forwarded public let count: Int"]),
					app: [Self.liveApi(["@Received(onlyIfAvailable: true) public let name: String?", "@Received(onlyIfAvailable: true) public let count: Int?"]), Self.root([])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenFillRequiresLabelTheCallerAlsoProvides() async {
		// Inline, the `A` that `B` builds again hands `LiveApi` `B`'s `tag`; the fill would read `Root`'s at every level.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `tag: Tag`, which `B` declares between where `Hub` instantiates `aBuilder: Instantiator<A>` and where `B` instantiates it again. Inline, the `A` built again receives `B`'s `tag`, but the scope SafeDI hands the builder for `A`'s `api: any Api` (case `A_Scope.api` of `apiBuilder`) holds the same values at every level of that cycle. Give `tag` on `B` another label, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["B.swift"]):8:5: note: `B` declares `tag: Tag` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [Self.tag] + Self.feature(b: ["@Forwarded public let tag: Tag"]),
					app: [Self.liveApi(["@Received public let tag: Tag"]), Self.root(["@Instantiated public let tag: Tag"])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenFillRequiresLabelTheSeamCarriesFromAboveTheCycle() async {
		// `Hub`'s `tag` is a field of the scope struct, bound above the function the cycle closes on, so the fill would read
		// it at every level, where inline the `A` that `B` builds again hands `LiveApi` `B`'s.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `tag: Tag`, which `B` declares between where `Hub` instantiates `aBuilder: Instantiator<A>` and where `B` instantiates it again. Inline, the `A` built again receives `B`'s `tag`, but the scope SafeDI hands the builder for `A`'s `api: any Api` (case `A_Scope.api` of `apiBuilder`) holds the same values at every level of that cycle. Give `tag` on `B` another label, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["B.swift"]):8:5: note: `B` declares `tag: Tag` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [Self.tag] + Self.feature(b: ["@Forwarded public let tag: Tag"], hub: ["@Instantiated public let tag: Tag"]),
					app: [Self.liveApi(["@Received public let tag: Tag"]), Self.root([])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenHoleSitsOnLazyCycle() async {
		// `B`'s `a` closes on `Hub`'s `a`, a lazily instantiated `A`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `count: Int?`, which `B` declares between where `Hub` instantiates `a: LazilyInstantiated<A>` and where `B` instantiates it again. Inline, the `A` built again receives `B`'s `count`, but the scope SafeDI hands the builder for `A`'s `api: any Api` (case `A_Scope.api` of `apiBuilder`) holds the same values at every level of that cycle. Give `count` on `B` another label, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["B.swift"]):8:5: note: `B` declares `count: Int` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						"public protocol Api {}",
						seamFixtureType(named: "A", declarations: ["@Instantiated public let api: any Api", "@Instantiated public let bBuilder: Instantiator<B>"]),
						seamFixtureType(named: "B", declarations: ["@Forwarded public let count: Int", "@Instantiated public let a: LazilyInstantiated<A>"]),
						seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let a: LazilyInstantiated<A>"]),
					],
					app: [Self.liveApi(["@Received(onlyIfAvailable: true) public let count: Int?"]), Self.root([])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenSeamThatCallsHubPassesBuilderUp() async {
		// `Shell`, a seam of `Feature` too, calls `Hub` and cannot fill its builder, which it passes up to `Root`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `count: Int?`, which `B` declares between where `Hub` instantiates `aBuilder: Instantiator<A>` and where `B` instantiates it again. Inline, the `A` built again receives `B`'s `count`, but the scope SafeDI hands the builder for `A`'s `api: any Api` (case `A_Scope.api` of `apiBuilder`) holds the same values at every level of that cycle. Give `count` on `B` another label, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["B.swift"]):8:5: note: `B` declares `count: Int` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: Self.feature(b: ["@Forwarded public let count: Int"]) + [
						seamFixtureType(named: "Shell", isSeam: true, declarations: ["@Instantiated public let hub: Hub"]),
					],
					app: [
						Self.liveApi(["@Received(onlyIfAvailable: true) public let count: Int?"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let shell: Shell"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenLabelIsParameterOfNestedCycleBetween() async {
		// `C` builds `B` again, so `B`'s function takes `count`, which `X` passes it first and `C` from then on. `B` receives
		// `count` from `X`, inside the function `B`'s `aBuilder` closes on, so that function takes no `count` and the scope
		// carries none. Inline, `LiveApi` makes `A`'s function take `count`, and the `A` that `B` builds again hands it the
		// `count` `B`'s function was passed; the fill would read `nil`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `count: Int?`, which `B`'s builder function takes as a parameter between where `Hub` instantiates `aBuilder: Instantiator<A>` and where `B` instantiates it again, because a cycle inside `B`'s tree passes it (`C` declares `count: Int`). Inline, the `A` built again receives the `count` that parameter is passed, but the scope SafeDI hands the builder for `A`'s `api: any Api` (case `A_Scope.api` of `apiBuilder`) holds the same values at every level of that cycle. Give `count` on `C` another label, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["C.swift"]):8:5: note: `C` declares `count: Int` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						"public protocol Api {}",
						seamFixtureType(named: "A", declarations: ["@Instantiated public let api: any Api", "@Instantiated public let xBuilder: Instantiator<X>"]),
						seamFixtureType(named: "X", declarations: ["@Forwarded public let count: Int", "@Instantiated public let bBuilder: Instantiator<B>"]),
						seamFixtureType(named: "B", declarations: ["@Received(onlyIfAvailable: true) public let count: Int?", "@Instantiated public let cBuilder: Instantiator<C>", "@Instantiated public let aBuilder: Instantiator<A>"]),
						seamFixtureType(named: "C", declarations: ["@Forwarded public let count: Int", "@Instantiated public let bBuilder: Instantiator<B>"]),
						seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let aBuilder: Instantiator<A>"]),
					],
					app: [Self.liveApi(["@Received(onlyIfAvailable: true) public let count: Int?"]), Self.root([])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenLabelIsParameterOfCycleNestedTwiceBetween() async {
		// `D` builds `C` again, so `C`'s function takes `count`, which `D` forwards, and `C` builds `B` again, so `B`'s
		// function takes `count` too, which `C`'s parameter passes it: the value `B`'s parameter carries is `D`'s. `B` receives
		// `count` from `X`, inside the function `B`'s `aBuilder` closes on, so that function takes no `count`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `count: Int?`, which `B`'s builder function takes as a parameter between where `Hub` instantiates `aBuilder: Instantiator<A>` and where `B` instantiates it again, because a cycle inside `B`'s tree passes it (`D` declares `count: Int`). Inline, the `A` built again receives the `count` that parameter is passed, but the scope SafeDI hands the builder for `A`'s `api: any Api` (case `A_Scope.api` of `apiBuilder`) holds the same values at every level of that cycle. Give `count` on `D` another label, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["D.swift"]):8:5: note: `D` declares `count: Int` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						"public protocol Api {}",
						seamFixtureType(named: "A", declarations: ["@Instantiated public let api: any Api", "@Instantiated public let xBuilder: Instantiator<X>"]),
						seamFixtureType(named: "X", declarations: ["@Forwarded public let count: Int", "@Instantiated public let bBuilder: Instantiator<B>"]),
						seamFixtureType(named: "B", declarations: ["@Received(onlyIfAvailable: true) public let count: Int?", "@Instantiated public let cBuilder: Instantiator<C>", "@Instantiated public let aBuilder: Instantiator<A>"]),
						seamFixtureType(named: "C", declarations: ["@Received(onlyIfAvailable: true) public let count: Int?", "@Instantiated public let dBuilder: Instantiator<D>", "@Instantiated public let bBuilder: Instantiator<B>"]),
						seamFixtureType(named: "D", declarations: ["@Forwarded public let count: Int", "@Instantiated public let cBuilder: Instantiator<C>"]),
						seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let aBuilder: Instantiator<A>"]),
					],
					app: [Self.liveApi(["@Received(onlyIfAvailable: true) public let count: Int?"]), Self.root([])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueACycleDeclaresAgain_whenTangleOfCyclesBuildsTypeAgainThroughFunctionThatTakesNoParameter() async {
		// The graph fuzzer's seed 605, reduced, by the ruling that a seam's tree hands a place the values inline does, never
		// the caller's: `Hub` builds `T` and `C`, each of which builds the other, a tangle no type always encloses. Inline,
		// the `T` that `C` builds again inside `Hub`'s `T` hands `LiveApi` `C`'s `mark`; nothing in `Feature` receives `mark`,
		// so the function that builds `T` takes no parameter, and the fill, handed the chain of the first build, would read
		// `Root`'s nothing.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `mark: Mark?`, which `C` declares between where `Hub` instantiates `tBuilder: Instantiator<T>` and where `C` instantiates it again. Inline, the `T` built again receives `C`'s `mark`, but the scope SafeDI hands the builder for `T`'s `api: any Api` (case `T_Scope.api` of `apiBuilder`) holds the same values at every level of that cycle. Give `mark` on `C` another label, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["C.swift"]):8:5: note: `C` declares `mark: Mark` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: Self.tangle(t: []),
					app: [Self.liveApi(["@Received(onlyIfAvailable: true) public let mark: Mark?"]), Self.root([])],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Accepted

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenOnlyOneBuildOfTypeTakesTheCycleParameterTheFillReads() async throws {
		// The graph fuzzer's seed 605, reduced, by the ruling that a seam's tree hands a place the values inline does, never
		// the caller's. `Hub` builds `T` and `C`, each of which builds the other, a tangle no type always encloses. `T`'s
		// `reader` receives `mark`, so the function that builds `Hub`'s `T` takes it as a cycle parameter, while the `T` that
		// `Hub`'s `C` builds reads `C`'s from above. `T`'s level carries `mark` in the parameter's form: bound from the
		// parameter where the function takes it, and from `C`'s `mark` where it does not, as each `T`'s tree reads it inline.
		try await expectValuesEqualInlineBuild(
			feature: Self.tangle(t: ["@Instantiated public let reader: MarkReader"]) + [
				seamFixtureType(named: "MarkReader", declarations: ["@Received(onlyIfAvailable: true) public let mark: Mark?"]),
			],
			fulfiller: Self.liveApi(["@Received(onlyIfAvailable: true) public let mark: Mark?"]),
			root: Self.root([]),
			probe: DifferentialValueProbe(
				name: "T's api at each build",
				expression: """
				{ () -> [String] in
				    let hub = Root().hub
				    let t = hub.tBuilder.instantiate()
				    return [t.api, t.cBuilder.instantiate().tBuilder.instantiate().api, hub.cBuilder.instantiate().tBuilder.instantiate().api].map { "\\($0)" }
				}()
				""",
			),
			expectedFeatureFile: (name: "Feature.swift", contents: """
			extension Hub {
			    @frozen public enum SafeDIScope_Api {
			        case tBuilder(tBuilder_Values, SafeDIScope_Api.T_Scope)
			        case cBuilder(cBuilder_Values, SafeDIScope_Api.C_Scope)

			        public struct tBuilder_Values {
			            public var mark: Mark? { __safeDI_mark.instance }
			            let __safeDI_mark: LazilyInstantiated<Mark?>

			            init(mark: LazilyInstantiated<Mark?>) {
			                __safeDI_mark = mark
			            }
			        }

			        public struct cBuilder_Values {
			            public var mark: Mark? { __safeDI_mark.instance }
			            public let tBuilder: Instantiator<T>
			            let __safeDI_mark: LazilyInstantiated<Mark?>

			            init(mark: LazilyInstantiated<Mark?>, tBuilder: Instantiator<T>) {
			                __safeDI_mark = mark
			                self.tBuilder = tBuilder
			            }
			        }

			        @frozen public enum T_Scope {
			            indirect case cBuilder(cBuilder_Values, SafeDIScope_Api.C_Scope)
			            case api(api_Values)

			            public struct cBuilder_Values {
			                public let mark: Mark?
			                public let reader: MarkReader
			            }

			            public struct api_Values {
			                public let mark: Mark?
			                public let reader: MarkReader
			                public let cBuilder: Instantiator<C>
			            }
			        }

			        @frozen public enum C_Scope {
			            indirect case tBuilder(tBuilder_Values, SafeDIScope_Api.T_Scope)

			            public struct tBuilder_Values {
			                public let mark: Mark
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_mark __safeDI_mark_: @autoclosure @escaping () -> Mark?, __safeDI_apiBuilder: @escaping (SafeDIScope_Api) -> any Api) {
			        let mark = LazilyInstantiated<Mark?>(__safeDI_mark_)
			        let __safeDI_apiValues_tBuilder = SafeDIScope_Api.tBuilder_Values(mark: mark)
			        func __safeDI_tBuilder(mark: Mark?) -> T {
			            let reader = MarkReader(mark: mark)
			            func __safeDI_cBuilder() -> C {
			                let mark = Mark()
			                let tBuilder = Instantiator<T> {
			                    __safeDI_tBuilder(mark: mark)
			                }
			                return C(mark: mark, tBuilder: tBuilder)
			            }
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            let api: any Api = __safeDI_apiBuilder(.tBuilder(__safeDI_apiValues_tBuilder, .api(SafeDIScope_Api.T_Scope.api_Values(mark: mark, reader: reader, cBuilder: cBuilder))))
			            return T(reader: reader, cBuilder: cBuilder, api: api)
			        }
			        let tBuilder = Instantiator<T> {
			            __safeDI_tBuilder(mark: mark.instance)
			        }
			        let __safeDI_apiValues_cBuilder = SafeDIScope_Api.cBuilder_Values(mark: mark, tBuilder: tBuilder)
			        func __safeDI_cBuilder() -> C {
			            let mark = Mark()
			            let __safeDI_apiValues_tBuilder = SafeDIScope_Api.C_Scope.tBuilder_Values(mark: mark)
			            func __safeDI_tBuilder() -> T {
			                let reader = MarkReader(mark: mark)
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                let api: any Api = __safeDI_apiBuilder(.cBuilder(__safeDI_apiValues_cBuilder, .tBuilder(__safeDI_apiValues_tBuilder, .api(SafeDIScope_Api.T_Scope.api_Values(mark: mark, reader: reader, cBuilder: cBuilder)))))
			                return T(reader: reader, cBuilder: cBuilder, api: api)
			            }
			            let tBuilder = Instantiator<T>(__safeDI_tBuilder)
			            return C(mark: mark, tBuilder: tBuilder)
			        }
			        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			        self.init(tBuilder: tBuilder, cBuilder: cBuilder)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_0A2311840283A6E1 {}
			}
			"""),
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_hub() -> Hub {
			            _ = Hub.__safeDI_Hub_0A2311840283A6E1.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_apiBuilder_Hub(_ scope: Hub.SafeDIScope_Api) -> any Api {
			                switch scope {
			                case let .tBuilder(_, scope): return __safeDI_apiBuilder_Hub_T_Scope(scope)
			                case let .cBuilder(_, scope): return __safeDI_apiBuilder_Hub_C_Scope(scope)
			                }
			            }
			            func __safeDI_apiBuilder_Hub_T_Scope(_ scope: Hub.SafeDIScope_Api.T_Scope) -> any Api {
			                switch scope {
			                case let .cBuilder(_, scope): return __safeDI_apiBuilder_Hub_C_Scope(scope)
			                case let .api(scope):
			                    let mark = scope.mark
			                    let api: any Api = LiveApi(mark: mark)
			                    return api
			                }
			            }
			            func __safeDI_apiBuilder_Hub_C_Scope(_ scope: Hub.SafeDIScope_Api.C_Scope) -> any Api {
			                switch scope {
			                case let .tBuilder(_, scope): return __safeDI_apiBuilder_Hub_T_Scope(scope)
			                }
			            }
			            return Hub(__safeDI_mark: nil, __safeDI_apiBuilder: __safeDI_apiBuilder_Hub)
			        }
			        let hub: Hub = __safeDI_hub()
			        self.init(hub: hub)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenBuildByValueBesideTangleReadsCycleParameterFromSeamsDeferredParameter() async throws {
		// Seed 605's tangle, where `Hub` also builds `T` by value and `Root` instantiates `mark`, which `Hub` defers. The
		// function that builds `Hub`'s `t` takes no parameter, so `T`'s level binds `mark` as `t`'s tree reads it there: the
		// instance of the deferred parameter, as `reader` reads it.
		try await expectValuesEqualInlineBuild(
			feature: Self.tangle(t: ["@Instantiated public let reader: MarkReader"], hub: ["@Instantiated public let t: T"], markIsFinalClass: true) + [
				seamFixtureType(named: "MarkReader", declarations: ["@Received public let mark: Mark"]),
			],
			fulfiller: Self.liveApi(["@Received public let mark: Mark"]),
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let mark: Mark", "@Instantiated public let hub: Hub"]),
			probe: DifferentialValueProbe(
				name: "T's api and reader at each build",
				expression: """
				{ () -> [Any] in
				    let root = Root()
				    let hub = root.hub
				    let c = hub.cBuilder.instantiate()
				    let tc = hub.t.cBuilder.instantiate()
				    return [root.mark, hub.t, tc, tc.tBuilder.instantiate(), hub.tBuilder.instantiate(), c, c.tBuilder.instantiate()]
				}()
				""",
			),
			expectedFeatureFile: (name: "Feature.swift", contents: """
			extension Hub {
			    @frozen public enum SafeDIScope_Api {
			        case tBuilder(tBuilder_Values, SafeDIScope_Api.T_Scope)
			        case cBuilder(cBuilder_Values, SafeDIScope_Api.C_Scope)
			        case t(t_Values, SafeDIScope_Api.T_Scope)

			        public struct tBuilder_Values {
			            public var mark: Mark { __safeDI_mark.instance }
			            let __safeDI_mark: LazilyInstantiated<Mark>

			            init(mark: LazilyInstantiated<Mark>) {
			                __safeDI_mark = mark
			            }
			        }

			        public struct cBuilder_Values {
			            public var mark: Mark { __safeDI_mark.instance }
			            public let tBuilder: Instantiator<T>
			            let __safeDI_mark: LazilyInstantiated<Mark>

			            init(mark: LazilyInstantiated<Mark>, tBuilder: Instantiator<T>) {
			                __safeDI_mark = mark
			                self.tBuilder = tBuilder
			            }
			        }

			        public struct t_Values {
			            public var mark: Mark { __safeDI_mark.instance }
			            public let tBuilder: Instantiator<T>
			            public let cBuilder: Instantiator<C>
			            let __safeDI_mark: LazilyInstantiated<Mark>

			            init(mark: LazilyInstantiated<Mark>, tBuilder: Instantiator<T>, cBuilder: Instantiator<C>) {
			                __safeDI_mark = mark
			                self.tBuilder = tBuilder
			                self.cBuilder = cBuilder
			            }
			        }

			        @frozen public enum T_Scope {
			            indirect case cBuilder(cBuilder_Values, SafeDIScope_Api.C_Scope)
			            case api(api_Values)

			            public struct cBuilder_Values {
			                public let mark: Mark
			                public let reader: MarkReader
			            }

			            public struct api_Values {
			                public let mark: Mark
			                public let reader: MarkReader
			                public let cBuilder: Instantiator<C>
			            }
			        }

			        @frozen public enum C_Scope {
			            indirect case tBuilder(tBuilder_Values, SafeDIScope_Api.T_Scope)

			            public struct tBuilder_Values {
			                public let mark: Mark
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_mark __safeDI_mark_: @autoclosure @escaping () -> Mark, __safeDI_apiBuilder: @escaping (SafeDIScope_Api) -> any Api) {
			        let mark = LazilyInstantiated<Mark>(__safeDI_mark_)
			        let __safeDI_apiValues_tBuilder = SafeDIScope_Api.tBuilder_Values(mark: mark)
			        func __safeDI_tBuilder(mark: Mark) -> T {
			            let reader = MarkReader(mark: mark)
			            func __safeDI_cBuilder() -> C {
			                let mark = Mark()
			                let tBuilder = Instantiator<T> {
			                    __safeDI_tBuilder(mark: mark)
			                }
			                return C(mark: mark, tBuilder: tBuilder)
			            }
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            let api: any Api = __safeDI_apiBuilder(.tBuilder(__safeDI_apiValues_tBuilder, .api(SafeDIScope_Api.T_Scope.api_Values(mark: mark, reader: reader, cBuilder: cBuilder))))
			            return T(reader: reader, cBuilder: cBuilder, api: api)
			        }
			        let tBuilder = Instantiator<T> {
			            __safeDI_tBuilder(mark: mark.instance)
			        }
			        let __safeDI_apiValues_cBuilder = SafeDIScope_Api.cBuilder_Values(mark: mark, tBuilder: tBuilder)
			        func __safeDI_cBuilder() -> C {
			            let mark = Mark()
			            let __safeDI_apiValues_tBuilder = SafeDIScope_Api.C_Scope.tBuilder_Values(mark: mark)
			            func __safeDI_tBuilder() -> T {
			                let reader = MarkReader(mark: mark)
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                let api: any Api = __safeDI_apiBuilder(.cBuilder(__safeDI_apiValues_cBuilder, .tBuilder(__safeDI_apiValues_tBuilder, .api(SafeDIScope_Api.T_Scope.api_Values(mark: mark, reader: reader, cBuilder: cBuilder)))))
			                return T(reader: reader, cBuilder: cBuilder, api: api)
			            }
			            let tBuilder = Instantiator<T>(__safeDI_tBuilder)
			            return C(mark: mark, tBuilder: tBuilder)
			        }
			        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			        let __safeDI_apiValues_t = SafeDIScope_Api.t_Values(mark: mark, tBuilder: tBuilder, cBuilder: cBuilder)
			        func __safeDI_t() -> T {
			            let reader = MarkReader(mark: mark.instance)
			            let __safeDI_apiValues_cBuilder = SafeDIScope_Api.T_Scope.cBuilder_Values(mark: mark.instance, reader: reader)
			            func __safeDI_cBuilder() -> C {
			                let mark = Mark()
			                let __safeDI_apiValues_tBuilder = SafeDIScope_Api.C_Scope.tBuilder_Values(mark: mark)
			                func __safeDI_tBuilder() -> T {
			                    let reader = MarkReader(mark: mark)
			                    let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                    let api: any Api = __safeDI_apiBuilder(.t(__safeDI_apiValues_t, .cBuilder(__safeDI_apiValues_cBuilder, .tBuilder(__safeDI_apiValues_tBuilder, .api(SafeDIScope_Api.T_Scope.api_Values(mark: mark, reader: reader, cBuilder: cBuilder))))))
			                    return T(reader: reader, cBuilder: cBuilder, api: api)
			                }
			                let tBuilder = Instantiator<T>(__safeDI_tBuilder)
			                return C(mark: mark, tBuilder: tBuilder)
			            }
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            let api: any Api = __safeDI_apiBuilder(.t(__safeDI_apiValues_t, .api(SafeDIScope_Api.T_Scope.api_Values(mark: mark.instance, reader: reader, cBuilder: cBuilder))))
			            return T(reader: reader, cBuilder: cBuilder, api: api)
			        }
			        let t: T = __safeDI_t()
			        self.init(tBuilder: tBuilder, cBuilder: cBuilder, t: t)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_D0F5785AAF1C3F7F {}
			}
			"""),
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        let mark = Mark()
			        func __safeDI_hub() -> Hub {
			            _ = Hub.__safeDI_Hub_D0F5785AAF1C3F7F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_apiBuilder_Hub(_ scope: Hub.SafeDIScope_Api) -> any Api {
			                switch scope {
			                case let .tBuilder(_, scope): return __safeDI_apiBuilder_Hub_T_Scope(scope)
			                case let .cBuilder(_, scope): return __safeDI_apiBuilder_Hub_C_Scope(scope)
			                case let .t(_, scope): return __safeDI_apiBuilder_Hub_T_Scope(scope)
			                }
			            }
			            func __safeDI_apiBuilder_Hub_T_Scope(_ scope: Hub.SafeDIScope_Api.T_Scope) -> any Api {
			                switch scope {
			                case let .cBuilder(_, scope): return __safeDI_apiBuilder_Hub_C_Scope(scope)
			                case let .api(scope):
			                    let mark = scope.mark
			                    let api: any Api = LiveApi(mark: mark)
			                    return api
			                }
			            }
			            func __safeDI_apiBuilder_Hub_C_Scope(_ scope: Hub.SafeDIScope_Api.C_Scope) -> any Api {
			                switch scope {
			                case let .tBuilder(_, scope): return __safeDI_apiBuilder_Hub_T_Scope(scope)
			                }
			            }
			            return Hub(__safeDI_mark: mark, __safeDI_apiBuilder: __safeDI_apiBuilder_Hub)
			        }
			        let hub: Hub = __safeDI_hub()
			        self.init(mark: mark, hub: hub)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenBuildByValueBesideTangleReadsCycleParameterFromLazilyInstantiatedDeclaration() async throws {
		// Seed 605's tangle, where `Hub` also builds `T` by value and declares `mark` lazily. The function that builds `Hub`'s
		// `t` takes no parameter, so `T`'s level binds `mark` as `t`'s tree reads it there: the instance of `Hub`'s
		// `LazilyInstantiated`, as `reader` reads it.
		try await expectValuesEqualInlineBuild(
			feature: Self.tangle(t: ["@Instantiated public let reader: MarkReader"], hub: ["@Instantiated public let mark: LazilyInstantiated<Mark>", "@Instantiated public let t: T"], markIsFinalClass: true) + [
				seamFixtureType(named: "MarkReader", declarations: ["@Received public let mark: Mark"]),
			],
			fulfiller: Self.liveApi(["@Received public let mark: Mark"]),
			root: Self.root([]),
			probe: DifferentialValueProbe(
				name: "T's api and reader at each build",
				expression: """
				{ () -> [Any] in
				    let hub = Root().hub
				    let c = hub.cBuilder.instantiate()
				    let tc = hub.t.cBuilder.instantiate()
				    return [hub.mark.instance, hub.t, tc, tc.tBuilder.instantiate(), hub.tBuilder.instantiate(), c, c.tBuilder.instantiate()]
				}()
				""",
			),
			expectedFeatureFile: (name: "Feature.swift", contents: """
			extension Hub {
			    @frozen public enum SafeDIScope_Api {
			        case tBuilder(tBuilder_Values, SafeDIScope_Api.T_Scope)
			        case cBuilder(cBuilder_Values, SafeDIScope_Api.C_Scope)
			        case t(t_Values, SafeDIScope_Api.T_Scope)

			        public struct tBuilder_Values {
			            public let mark: LazilyInstantiated<Mark>
			        }

			        public struct cBuilder_Values {
			            public let mark: LazilyInstantiated<Mark>
			            public let tBuilder: Instantiator<T>
			        }

			        public struct t_Values {
			            public let mark: LazilyInstantiated<Mark>
			            public let tBuilder: Instantiator<T>
			            public let cBuilder: Instantiator<C>
			        }

			        @frozen public enum T_Scope {
			            indirect case cBuilder(cBuilder_Values, SafeDIScope_Api.C_Scope)
			            case api(api_Values)

			            public struct cBuilder_Values {
			                public let mark: Mark
			                public let reader: MarkReader
			            }

			            public struct api_Values {
			                public let mark: Mark
			                public let reader: MarkReader
			                public let cBuilder: Instantiator<C>
			            }
			        }

			        @frozen public enum C_Scope {
			            indirect case tBuilder(tBuilder_Values, SafeDIScope_Api.T_Scope)

			            public struct tBuilder_Values {
			                public let mark: Mark
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_apiBuilder: @escaping (SafeDIScope_Api) -> any Api) {
			        func __safeDI_mark() -> Mark {
			            Mark()
			        }
			        let mark = LazilyInstantiated<Mark>(__safeDI_mark)
			        let __safeDI_apiValues_tBuilder = SafeDIScope_Api.tBuilder_Values(mark: mark)
			        func __safeDI_tBuilder(mark: Mark) -> T {
			            let reader = MarkReader(mark: mark)
			            func __safeDI_cBuilder() -> C {
			                let mark = Mark()
			                let tBuilder = Instantiator<T> {
			                    __safeDI_tBuilder(mark: mark)
			                }
			                return C(mark: mark, tBuilder: tBuilder)
			            }
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            let api: any Api = __safeDI_apiBuilder(.tBuilder(__safeDI_apiValues_tBuilder, .api(SafeDIScope_Api.T_Scope.api_Values(mark: mark, reader: reader, cBuilder: cBuilder))))
			            return T(reader: reader, cBuilder: cBuilder, api: api)
			        }
			        let tBuilder = Instantiator<T> {
			            __safeDI_tBuilder(mark: mark.instance)
			        }
			        let __safeDI_apiValues_cBuilder = SafeDIScope_Api.cBuilder_Values(mark: mark, tBuilder: tBuilder)
			        func __safeDI_cBuilder() -> C {
			            let mark = Mark()
			            let __safeDI_apiValues_tBuilder = SafeDIScope_Api.C_Scope.tBuilder_Values(mark: mark)
			            func __safeDI_tBuilder() -> T {
			                let reader = MarkReader(mark: mark)
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                let api: any Api = __safeDI_apiBuilder(.cBuilder(__safeDI_apiValues_cBuilder, .tBuilder(__safeDI_apiValues_tBuilder, .api(SafeDIScope_Api.T_Scope.api_Values(mark: mark, reader: reader, cBuilder: cBuilder)))))
			                return T(reader: reader, cBuilder: cBuilder, api: api)
			            }
			            let tBuilder = Instantiator<T>(__safeDI_tBuilder)
			            return C(mark: mark, tBuilder: tBuilder)
			        }
			        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			        let __safeDI_apiValues_t = SafeDIScope_Api.t_Values(mark: mark, tBuilder: tBuilder, cBuilder: cBuilder)
			        func __safeDI_t() -> T {
			            let reader = MarkReader(mark: mark.instance)
			            let __safeDI_apiValues_cBuilder = SafeDIScope_Api.T_Scope.cBuilder_Values(mark: mark.instance, reader: reader)
			            func __safeDI_cBuilder() -> C {
			                let mark = Mark()
			                let __safeDI_apiValues_tBuilder = SafeDIScope_Api.C_Scope.tBuilder_Values(mark: mark)
			                func __safeDI_tBuilder() -> T {
			                    let reader = MarkReader(mark: mark)
			                    let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                    let api: any Api = __safeDI_apiBuilder(.t(__safeDI_apiValues_t, .cBuilder(__safeDI_apiValues_cBuilder, .tBuilder(__safeDI_apiValues_tBuilder, .api(SafeDIScope_Api.T_Scope.api_Values(mark: mark, reader: reader, cBuilder: cBuilder))))))
			                    return T(reader: reader, cBuilder: cBuilder, api: api)
			                }
			                let tBuilder = Instantiator<T>(__safeDI_tBuilder)
			                return C(mark: mark, tBuilder: tBuilder)
			            }
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            let api: any Api = __safeDI_apiBuilder(.t(__safeDI_apiValues_t, .api(SafeDIScope_Api.T_Scope.api_Values(mark: mark.instance, reader: reader, cBuilder: cBuilder))))
			            return T(reader: reader, cBuilder: cBuilder, api: api)
			        }
			        let t: T = __safeDI_t()
			        self.init(tBuilder: tBuilder, cBuilder: cBuilder, mark: mark, t: t)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_4B8CEE95B37FC739 {}
			}
			"""),
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_hub() -> Hub {
			            _ = Hub.__safeDI_Hub_4B8CEE95B37FC739.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            func __safeDI_apiBuilder_Hub(_ scope: Hub.SafeDIScope_Api) -> any Api {
			                switch scope {
			                case let .tBuilder(_, scope): return __safeDI_apiBuilder_Hub_T_Scope(scope)
			                case let .cBuilder(_, scope): return __safeDI_apiBuilder_Hub_C_Scope(scope)
			                case let .t(_, scope): return __safeDI_apiBuilder_Hub_T_Scope(scope)
			                }
			            }
			            func __safeDI_apiBuilder_Hub_T_Scope(_ scope: Hub.SafeDIScope_Api.T_Scope) -> any Api {
			                switch scope {
			                case let .cBuilder(_, scope): return __safeDI_apiBuilder_Hub_C_Scope(scope)
			                case let .api(scope):
			                    let mark = scope.mark
			                    let api: any Api = LiveApi(mark: mark)
			                    return api
			                }
			            }
			            func __safeDI_apiBuilder_Hub_C_Scope(_ scope: Hub.SafeDIScope_Api.C_Scope) -> any Api {
			                switch scope {
			                case let .tBuilder(_, scope): return __safeDI_apiBuilder_Hub_T_Scope(scope)
			                }
			            }
			            return Hub(__safeDI_apiBuilder: __safeDI_apiBuilder_Hub)
			        }
			        let hub: Hub = __safeDI_hub()
			        self.init(hub: hub)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenFillReadsLabelDeclaredInsideFunctionTheCycleClosesOn() async throws {
		// The hole is `B`'s, inside the function `B`'s `aBuilder` closes on, and `B` forwards `count` at every level.
		let feature = [
			"public protocol Api {}",
			seamFixtureType(named: "A", declarations: ["@Forwarded public let name: String", "@Instantiated public let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", declarations: ["@Forwarded public let count: Int", "@Instantiated public let api: any Api", "@Instantiated public let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let aBuilder: Instantiator<A>"]),
		]
		let fulfiller = Self.liveApi(["@Received(onlyIfAvailable: true) public let name: String?", "@Received(onlyIfAvailable: true) public let count: Int?"])
		try await expectValuesEqualInlineBuild(
			feature: feature,
			fulfiller: fulfiller,
			root: Self.root([]),
			probe: DifferentialValueProbe(
				name: "B's api at each level",
				expression: """
				{ () -> [String] in
				    let a = Root().hub.aBuilder.instantiate("x")
				    let b = a.bBuilder.instantiate(2)
				    let b3 = b.aBuilder.instantiate("y").bBuilder.instantiate(3)
				    return [b.api, b3.api].map { "\\($0)" }
				}()
				""",
			),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenFieldIsBoundFromParameterOfFunctionTheCycleClosesOn() async throws {
		// `A`'s `reader` requires `tag`, which `B` declares, so the function `A` is built with takes `tag`, and the field of
		// `A`'s `api` binds it from that parameter at every level.
		let feature = [
			"public protocol Api {}",
			Self.tag,
			seamFixtureType(named: "TagReader", declarations: ["@Received public let tag: Tag"]),
			seamFixtureType(named: "A", declarations: ["@Forwarded public let name: String", "@Instantiated public let reader: TagReader", "@Instantiated public let api: any Api", "@Instantiated public let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", declarations: ["@Forwarded public let tag: Tag", "@Instantiated public let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let tag: Tag", "@Instantiated public let aBuilder: Instantiator<A>"]),
		]
		try await expectValuesEqualInlineBuild(
			feature: feature,
			fulfiller: Self.liveApi(["@Received public let tag: Tag"]),
			root: Self.root([]),
			probe: Self.aApiAtEachLevel(forwarding: "Tag(value: \"two\")"),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenFillRequiresLabelTheSeamTakesAsDeferredParameter() async throws {
		// `A`'s `reader` makes `tag` a parameter of the function the cycle closes on, which hides the `tag` `Hub` defers: the
		// field holds the parameter, `Root`'s at the first level and `B`'s where `B` builds `A` again, as inline hands it.
		let feature = [
			"public protocol Api {}",
			Self.tag,
			seamFixtureType(named: "TagReader", declarations: ["@Received public let tag: Tag"]),
			seamFixtureType(named: "A", declarations: ["@Forwarded public let name: String", "@Instantiated public let reader: TagReader", "@Instantiated public let api: any Api", "@Instantiated public let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", declarations: ["@Forwarded public let tag: Tag", "@Instantiated public let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let aBuilder: Instantiator<A>"]),
		]
		try await expectValuesEqualInlineBuild(
			feature: feature,
			fulfiller: Self.liveApi(["@Received public let tag: Tag"]),
			root: Self.root(["@Instantiated public let tag: Tag"]),
			probe: Self.aApiAtEachLevel(forwarding: "Tag(value: \"two\")"),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenLabelIsParameterOfNestedCycleBetweenAndOfFunctionTheCycleClosesOn() async throws {
		// `C` builds `B` again, so `B`'s function takes `count`, which `C` forwards. `B` receives `count` from above `A`, so the
		// function `B`'s `aBuilder` closes on takes `count` too, and the field holds it: `nil` at the first level, and the
		// `count` `B`'s function was passed where `B` builds `A` again.
		let feature = [
			"public protocol Api {}",
			seamFixtureType(named: "A", declarations: ["@Instantiated public let api: any Api", "@Instantiated public let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", declarations: ["@Received(onlyIfAvailable: true) public let count: Int?", "@Instantiated public let cBuilder: Instantiator<C>", "@Instantiated public let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "C", declarations: ["@Forwarded public let count: Int", "@Instantiated public let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let aBuilder: Instantiator<A>"]),
		]
		try await expectValuesEqualInlineBuild(
			feature: feature,
			fulfiller: Self.liveApi(["@Received(onlyIfAvailable: true) public let count: Int?"]),
			root: Self.root([]),
			probe: DifferentialValueProbe(
				name: "A's api at each level",
				expression: """
				{ () -> [String] in
				    let b = Root().hub.aBuilder.instantiate().bBuilder.instantiate()
				    let b2 = b.cBuilder.instantiate(2).bBuilder.instantiate()
				    return [b.aBuilder.instantiate().api, b2.aBuilder.instantiate().api, b2.aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate(3).bBuilder.instantiate().aBuilder.instantiate().api].map { "\\($0)" }
				}()
				""",
			),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenLabelIsParameterOfCycleNestedTwiceBetweenAndOfFunctionTheCycleClosesOn() async throws {
		// `D` builds `C` again and `C` builds `B` again, so both functions take `count`, which `D` forwards. `B` receives
		// `count` from above `A`, so the function `B`'s `aBuilder` closes on takes `count` too, and the field holds it.
		let feature = [
			"public protocol Api {}",
			seamFixtureType(named: "A", declarations: ["@Instantiated public let api: any Api", "@Instantiated public let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", declarations: ["@Received(onlyIfAvailable: true) public let count: Int?", "@Instantiated public let cBuilder: Instantiator<C>", "@Instantiated public let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "C", declarations: ["@Received(onlyIfAvailable: true) public let count: Int?", "@Instantiated public let dBuilder: Instantiator<D>", "@Instantiated public let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "D", declarations: ["@Forwarded public let count: Int", "@Instantiated public let cBuilder: Instantiator<C>"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let aBuilder: Instantiator<A>"]),
		]
		try await expectValuesEqualInlineBuild(
			feature: feature,
			fulfiller: Self.liveApi(["@Received(onlyIfAvailable: true) public let count: Int?"]),
			root: Self.root([]),
			probe: DifferentialValueProbe(
				name: "A's api at each level",
				expression: """
				{ () -> [String] in
				    let c = Root().hub.aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate()
				    let b2 = c.dBuilder.instantiate(3).cBuilder.instantiate().bBuilder.instantiate()
				    return [c.bBuilder.instantiate().aBuilder.instantiate().api, b2.aBuilder.instantiate().api].map { "\\($0)" }
				}()
				""",
			),
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillBuildsInlineValues_whenCycleInsideSendableInstantiatorClosesOnFunctionBuiltByValue() async throws {
		// `Hub` builds `A` by value, and `B`, built in `A`'s `SendableInstantiator`, builds `A` again, which calls the function
		// `Hub`'s tree builds `A` with from a `@Sendable` closure: that function is `@Sendable`, so the place of `B`'s `api` is a
		// case of the `@Sendable` family, `a_Sendable`, and the plain root enum holds only `B`'s nested enum.
		let feature = [
			"public protocol Api: Sendable {}",
			seamFixtureType(named: "A", declarations: ["@Instantiated public let bBuilder: SendableInstantiator<B>"], conformances: ", Sendable"),
			seamFixtureType(named: "B", declarations: ["@Instantiated public let api: any Api", "@Instantiated public let a: A"], conformances: ", Sendable"),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let a: A"], conformances: ", Sendable"),
		]
		try await expectValuesEqualInlineBuild(
			feature: feature,
			fulfiller: Self.liveApi([]),
			root: Self.root([]),
			probe: DifferentialValueProbe(
				name: "B's api at each level",
				expression: """
				{ () -> [String] in
				    let b = Root().hub.a.bBuilder.instantiate()
				    return [b.api, b.a.bBuilder.instantiate().api].map { "\\($0)" }
				}()
				""",
			),
			expectedFeatureFile: (name: "Feature.swift", contents: """
			extension Hub {
			    @frozen public enum SafeDIScope_Api {
			        @frozen public enum B_Scope {
			            case api(api_Values)

			            public struct api_Values {
			                public let a: A
			            }
			        }
			    }

			    @frozen public enum SafeDISendableScope_Api {
			        case a_Sendable(SafeDISendableScope_Api.A_Scope)

			        @frozen public enum A_Scope {
			            case bBuilder(SafeDIScope_Api.B_Scope)
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
			    public init(__safeDI_apiSendableBuilder: @escaping @Sendable (SafeDISendableScope_Api) -> any Api) {
			        @Sendable func __safeDI_a() -> A {
			            @Sendable func __safeDI_bBuilder() -> B {
			                let a: A = __safeDI_a()
			                let api: any Api = __safeDI_apiSendableBuilder(.a_Sendable(.bBuilder(.api(SafeDIScope_Api.B_Scope.api_Values(a: a)))))
			                return B(api: api, a: a)
			            }
			            let bBuilder = SendableInstantiator<B>(__safeDI_bBuilder)
			            return A(bBuilder: bBuilder)
			        }
			        let a: A = __safeDI_a()
			        self.init(a: a)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_168DCE00C8B4949D {}
			}
			"""),
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_hub() -> Hub {
			            _ = Hub.__safeDI_Hub_168DCE00C8B4949D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            @Sendable func __safeDI_apiSendableBuilder_Hub(_ scope: Hub.SafeDISendableScope_Api) -> any Api {
			                switch scope {
			                case let .a_Sendable(scope): return __safeDI_apiSendableBuilder_Hub_A_Scope(scope)
			                }
			            }
			            @Sendable func __safeDI_apiSendableBuilder_Hub_A_Scope(_ scope: Hub.SafeDISendableScope_Api.A_Scope) -> any Api {
			                switch scope {
			                case let .bBuilder(scope): return __safeDI_apiBuilder_Hub_B_Scope(scope)
			                }
			            }
			            @Sendable func __safeDI_apiBuilder_Hub_B_Scope(_ scope: Hub.SafeDIScope_Api.B_Scope) -> any Api {
			                switch scope {
			                case .api:
			                    let api: any Api = LiveApi()
			                    return api
			                }
			            }
			            return Hub(__safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Hub)
			        }
			        let hub: Hub = __safeDI_hub()
			        self.init(hub: hub)
			    }
			}
			""",
		)
	}

	// MARK: Fixtures

	/// `Api`, `A`, `B` and `Hub`:`B` declares `b`'s declarations before its `aBuilder`, and `Hub` declares `hub`'s before its
	/// own.
	private static func feature(b: [String], hub: [String] = []) -> [String] {
		[
			"public protocol Api {}",
			seamFixtureType(named: "A", declarations: ["@Forwarded public let name: String", "@Instantiated public let api: any Api", "@Instantiated public let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", declarations: b + ["@Instantiated public let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: hub + ["@Instantiated public let aBuilder: Instantiator<A>"]),
		]
	}

	/// `Api`, `Mark`, `T`, `C` and `Hub`, a tangle of cycles no type always encloses: `Hub` builds `T` and `C` through
	/// instantiators, then declares `hub`'s declarations, `T` declares `t`'s declarations, then builds `C` before its hole
	/// `api`, and `C` instantiates `mark` before it builds `T`. `Mark` is a final class where `markIsFinalClass`, so a probe
	/// tells its instances apart.
	private static func tangle(t: [String], hub: [String] = [], markIsFinalClass: Bool = false) -> [String] {
		[
			"public protocol Api {}",
			seamFixtureType(named: "Mark", isFinalClass: markIsFinalClass, declarations: []),
			seamFixtureType(named: "T", declarations: t + ["@Instantiated public let cBuilder: Instantiator<C>", "@Instantiated public let api: any Api"]),
			seamFixtureType(named: "C", declarations: ["@Instantiated public let mark: Mark", "@Instantiated public let tBuilder: Instantiator<T>"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated public let tBuilder: Instantiator<T>", "@Instantiated public let cBuilder: Instantiator<C>"] + hub),
		]
	}

	private static let tag = """
	@Instantiable
	public struct Tag: Instantiable, CustomStringConvertible {
	    public init() { value = "root" }
	    public init(value: String) { self.value = value }
	    public let value: String
	    public var description: String { value }
	}
	"""

	private static func liveApi(_ declarations: [String]) -> String {
		seamFixtureType(named: "LiveApi", declarations: declarations, conformances: ", Api")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Api.self])\n")
	}

	private static func root(_ declarations: [String]) -> String {
		seamFixtureType(named: "Root", isRoot: true, declarations: declarations + ["@Instantiated public let hub: Hub"])
	}

	/// The `api` of the `A` that `Hub` builds and of the one its `B`, forwarded `forwarded`, builds again.
	private static func aApiAtEachLevel(forwarding forwarded: String) -> DifferentialValueProbe {
		DifferentialValueProbe(
			name: "A's api at each level",
			expression: """
			{ () -> [String] in
			    let a = Root().hub.aBuilder.instantiate("x")
			    let again = a.bBuilder.instantiate(\(forwarded)).aBuilder.instantiate("y")
			    return [a.api, again.api].map { "\\($0)" }
			}()
			""",
		)
	}

	/// `Feature`, in package `Shop`, and `App`, in package `Other`, which imports it.
	private static func modules(feature: [String], app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// Expects the build of `feature` and `App` holding `fulfiller` and `root` to compile and to construct the values the
	/// same graph builds with `fulfiller` in `Feature`, where no hole is left and the tree is built inline, for `probe`.
	/// Where `expectedFeatureFile` or `expectedApp` is given, also expects `Feature`'s generated file of that name, or
	/// `App`'s `App.swift`, to be exactly it.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectValuesEqualInlineBuild(
		feature: [String],
		fulfiller: String,
		root: String,
		probe: DifferentialValueProbe,
		expectedFeatureFile: (name: String, contents: String)? = nil,
		expectedApp: String? = nil,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let modules = Self.modules(feature: feature, app: [fulfiller, root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		if let expectedFeatureFile {
			#expect(output.modules["Feature"]?.generatedFiles[expectedFeatureFile.name] == generatedFileHeader + expectedFeatureFile.contents, sourceLocation: sourceLocation)
		}
		if let expectedApp {
			#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + expectedApp, sourceLocation: sourceLocation)
		}
		guard compileVerificationIsEnabled else { return }
		let inlineModules = Self.modules(feature: feature + [fulfiller], app: [root])
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: inlineOutput, modules: inlineModules),
			probes: [probe],
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	private var filesToDelete: [URL]
}
