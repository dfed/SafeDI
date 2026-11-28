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

/// A loop of builders inside a seam's tree whose members hold places: the seam's initializer binds each member's level
/// before the loop's first function, and each member's function names the functions of the members its tree receives, so
/// that, a local function capturing what the functions it names capture, every member's function would capture every
/// member's level and the compiled code would grow with the square of the loop. The levels are held in one box instead,
/// which each member's function captures and unboxes its own level from.
struct SafeDIToolSeamLoopLevelsTests: ~Copyable {
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
	mutating func generate_holdsLoopsLevelsInOneBox_whenSeamsBuildersReceiveEachOtherAroundPlaces() async throws {
		// `Home`, a seam, instantiates the builders of three screens, each of which forwards an `id`, holds a place of `Api`
		// and receives the next screen's builder: a loop of three, whose levels the initializer binds in one box.
		let modules = Self.modules(feature: Self.ringFeature, app: [Self.defaultApi, Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			"Feature.swift": generatedFileHeader + """
			extension Home {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
			        public let screenABuilder: __safeDI_ApiCarrier_ScreenA<__safeDI_Built>
			        public let screenBBuilder: __safeDI_ApiCarrier_ScreenB<__safeDI_Built>
			        public let screenCBuilder: __safeDI_ApiCarrier_ScreenC<__safeDI_Built>

			        public init(screenABuilder: __safeDI_ApiCarrier_ScreenA<__safeDI_Built>, screenBBuilder: __safeDI_ApiCarrier_ScreenB<__safeDI_Built>, screenCBuilder: __safeDI_ApiCarrier_ScreenC<__safeDI_Built>) {
			            self.screenABuilder = screenABuilder
			            self.screenBBuilder = screenBBuilder
			            self.screenCBuilder = screenCBuilder
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_ScreenA<__safeDI_Built> {
			        public let api: (Int, Instantiator<ScreenB>) -> __safeDI_Built

			        public init(api: @escaping (Int, Instantiator<ScreenB>) -> __safeDI_Built) {
			            self.api = api
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_ScreenB<__safeDI_Built> {
			        public let api: (Int, Instantiator<ScreenC>) -> __safeDI_Built

			        public init(api: @escaping (Int, Instantiator<ScreenC>) -> __safeDI_Built) {
			            self.api = api
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_ScreenC<__safeDI_Built> {
			        public let api: (Int, Instantiator<ScreenA>) -> __safeDI_Built

			        public init(api: @escaping (Int, Instantiator<ScreenA>) -> __safeDI_Built) {
			            self.api = api
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
			        let __safeDI_screenABuilder_loopLevels = __safeDI_LoopLevels_6810F24E4F3FBD4D(
			            __safeDI_apiBuilder_screenABuilder: __safeDI_apiBuilder.screenABuilder,
			            __safeDI_apiBuilder_screenBBuilder: __safeDI_apiBuilder.screenBBuilder,
			            __safeDI_apiBuilder_screenCBuilder: __safeDI_apiBuilder.screenCBuilder
			        )
			        @inline(never) func __safeDI_screenABuilder(id: Int) -> ScreenA {
			            let __safeDI_apiBuilder_screenABuilder = __safeDI_screenABuilder_loopLevels.__safeDI_apiBuilder_screenABuilder
			            let screenBBuilder = Instantiator<ScreenB> {
			                __safeDI_screenBBuilder(id: $0)
			            }
			            let api: any Api = __safeDI_apiBuilder_screenABuilder.api(id, screenBBuilder)
			            return ScreenA(id: id, api: api, screenBBuilder: screenBBuilder)
			        }
			        let screenABuilder = Instantiator<ScreenA> {
			            __safeDI_screenABuilder(id: $0)
			        }
			        @inline(never) func __safeDI_screenBBuilder(id: Int) -> ScreenB {
			            let __safeDI_apiBuilder_screenBBuilder = __safeDI_screenABuilder_loopLevels.__safeDI_apiBuilder_screenBBuilder
			            let screenCBuilder = Instantiator<ScreenC> {
			                __safeDI_screenCBuilder(id: $0)
			            }
			            let api: any Api = __safeDI_apiBuilder_screenBBuilder.api(id, screenCBuilder)
			            return ScreenB(id: id, api: api, screenCBuilder: screenCBuilder)
			        }
			        let screenBBuilder = Instantiator<ScreenB> {
			            __safeDI_screenBBuilder(id: $0)
			        }
			        @inline(never) func __safeDI_screenCBuilder(id: Int) -> ScreenC {
			            let __safeDI_apiBuilder_screenCBuilder = __safeDI_screenABuilder_loopLevels.__safeDI_apiBuilder_screenCBuilder
			            let screenABuilder = Instantiator<ScreenA> {
			                __safeDI_screenABuilder(id: $0)
			            }
			            let api: any Api = __safeDI_apiBuilder_screenCBuilder.api(id, screenABuilder)
			            return ScreenC(id: id, api: api, screenABuilder: screenABuilder)
			        }
			        let screenCBuilder = Instantiator<ScreenC> {
			            __safeDI_screenCBuilder(id: $0)
			        }
			        self.init(screenABuilder: screenABuilder, screenBBuilder: screenBBuilder, screenCBuilder: screenCBuilder)
			    }

			    /// Holds the payloads of a loop of builders, so that each builder function of the loop captures one reference.
			    nonisolated private final class __safeDI_LoopLevels_6810F24E4F3FBD4D {
			        init(
			            __safeDI_apiBuilder_screenABuilder: __safeDI_ApiCarrier_ScreenA<any Api>,
			            __safeDI_apiBuilder_screenBBuilder: __safeDI_ApiCarrier_ScreenB<any Api>,
			            __safeDI_apiBuilder_screenCBuilder: __safeDI_ApiCarrier_ScreenC<any Api>
			        ) {
			            self.__safeDI_apiBuilder_screenABuilder = __safeDI_apiBuilder_screenABuilder
			            self.__safeDI_apiBuilder_screenBBuilder = __safeDI_apiBuilder_screenBBuilder
			            self.__safeDI_apiBuilder_screenCBuilder = __safeDI_apiBuilder_screenCBuilder
			        }

			        let __safeDI_apiBuilder_screenABuilder: __safeDI_ApiCarrier_ScreenA<any Api>
			        let __safeDI_apiBuilder_screenBBuilder: __safeDI_ApiCarrier_ScreenB<any Api>
			        let __safeDI_apiBuilder_screenCBuilder: __safeDI_ApiCarrier_ScreenC<any Api>
			    }
			}

			extension Home {
			    public enum __safeDI_Home_6D4E0593FD00DAB3 {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
			            .init(screenABuilder: __safeDI_apiBuilder_Home_ScreenA_Scope(), screenBBuilder: __safeDI_apiBuilder_Home_ScreenB_Scope(), screenCBuilder: __safeDI_apiBuilder_Home_ScreenC_Scope())
			        }
			        func __safeDI_apiBuilder_Home_ScreenA_Scope() -> Home.__safeDI_ApiCarrier_ScreenA<any Api> {
			            .init(api: { scope_id, scope_screenBBuilder in
			                let api: any Api = DefaultApi()
			                return api
			            })
			        }
			        func __safeDI_apiBuilder_Home_ScreenB_Scope() -> Home.__safeDI_ApiCarrier_ScreenB<any Api> {
			            .init(api: { scope_id, scope_screenCBuilder in
			                let api: any Api = DefaultApi()
			                return api
			            })
			        }
			        func __safeDI_apiBuilder_Home_ScreenC_Scope() -> Home.__safeDI_ApiCarrier_ScreenC<any Api> {
			            .init(api: { scope_id, scope_screenABuilder in
			                let api: any Api = DefaultApi()
			                return api
			            })
			        }
			        func __safeDI_home() -> Home {
			            _ = Home.__safeDI_Home_6D4E0593FD00DAB3.self\(Self.callComment(module: "Feature"))
			            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
			        }
			        let home: Home = __safeDI_home()
			        self.init(home: home)
			    }
			}
			""",
		])
		try await expectValuesAndRetentionEqualInlineBuild(output, modules: modules, inlineModules: Self.modules(feature: inlineFixture(Self.ringFeature) + [Self.defaultApi], app: [Self.root]), samples: Self.ringSamples)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsNoLevels_whenLoopAroundPlacesIsBuiltInline() async throws {
		// The same graph with `Home` built inline in `App`'s tree: `DefaultApi` fills each place where it is built, so the
		// loop binds no level and its functions capture nothing but one another.
		let modules = Self.modules(feature: inlineFixture(Self.ringFeature) + [Self.defaultApi], app: [Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_home() -> Home {
			            func __safeDI_screenABuilder(id: Int) -> ScreenA {
			                let screenBBuilder = Instantiator<ScreenB> {
			                    __safeDI_screenBBuilder(id: $0)
			                }
			                let api: any Api = DefaultApi()
			                return ScreenA(id: id, api: api, screenBBuilder: screenBBuilder)
			            }
			            let screenABuilder = Instantiator<ScreenA> {
			                __safeDI_screenABuilder(id: $0)
			            }
			            func __safeDI_screenBBuilder(id: Int) -> ScreenB {
			                let screenCBuilder = Instantiator<ScreenC> {
			                    __safeDI_screenCBuilder(id: $0)
			                }
			                let api: any Api = DefaultApi()
			                return ScreenB(id: id, api: api, screenCBuilder: screenCBuilder)
			            }
			            let screenBBuilder = Instantiator<ScreenB> {
			                __safeDI_screenBBuilder(id: $0)
			            }
			            func __safeDI_screenCBuilder(id: Int) -> ScreenC {
			                let screenABuilder = Instantiator<ScreenA> {
			                    __safeDI_screenABuilder(id: $0)
			                }
			                let api: any Api = DefaultApi()
			                return ScreenC(id: id, api: api, screenABuilder: screenABuilder)
			            }
			            let screenCBuilder = Instantiator<ScreenC> {
			                __safeDI_screenCBuilder(id: $0)
			            }
			            return Home(screenABuilder: screenABuilder, screenBBuilder: screenBBuilder, screenCBuilder: screenCBuilder)
			        }
			        let home: Home = __safeDI_home()
			        self.init(home: home)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsEachLoopsLevelsInABoxOfItsOwn_whenLoopMembersTypeDeclaresAnotherLoop() async throws {
		// `ScreenA` and `ScreenB` are a loop of `Home`'s, and `ScreenA` instantiates the builders of `TabX` and `TabY`,
		// which receive each other: a loop inside `ScreenA`'s builder function, whose levels are member calls on the level
		// `ScreenA`'s function unboxed. Each loop holds its own levels in a box of its own; the class is declared once.
		let feature = [
			"public protocol Api {}",
			seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let screenABuilder: Instantiator<ScreenA>", "@Instantiated let screenBBuilder: Instantiator<ScreenB>"]),
			seamFixtureType(named: "ScreenA", isFinalClass: true, declarations: ["@Instantiated let api: any Api", "@Received let screenBBuilder: Instantiator<ScreenB>", "@Instantiated let tabXBuilder: Instantiator<TabX>", "@Instantiated let tabYBuilder: Instantiator<TabY>"]),
			seamFixtureType(named: "ScreenB", isFinalClass: true, declarations: ["@Instantiated let api: any Api", "@Received let screenABuilder: Instantiator<ScreenA>"]),
			seamFixtureType(named: "TabX", isFinalClass: true, declarations: ["@Instantiated let api: any Api", "@Received let tabYBuilder: Instantiator<TabY>"]),
			seamFixtureType(named: "TabY", isFinalClass: true, declarations: ["@Instantiated let api: any Api", "@Received let tabXBuilder: Instantiator<TabX>"]),
		]
		let modules = Self.modules(feature: feature, app: [Self.defaultApi, Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			"Feature.swift": generatedFileHeader + """
			extension Home {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
			        public let screenABuilder: __safeDI_ApiCarrier_ScreenA<__safeDI_Built>
			        public let screenBBuilder: __safeDI_ApiCarrier_ScreenB<__safeDI_Built>

			        public init(screenABuilder: __safeDI_ApiCarrier_ScreenA<__safeDI_Built>, screenBBuilder: __safeDI_ApiCarrier_ScreenB<__safeDI_Built>) {
			            self.screenABuilder = screenABuilder
			            self.screenBBuilder = screenBBuilder
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_ScreenA<__safeDI_Built> {
			        public let api: (Instantiator<ScreenB>) -> __safeDI_Built
			        public let tabXBuilder: (Instantiator<ScreenB>, any Api) -> __safeDI_ApiCarrier_TabX<__safeDI_Built>
			        public let tabYBuilder: (Instantiator<ScreenB>, any Api) -> __safeDI_ApiCarrier_TabY<__safeDI_Built>

			        public init(api: @escaping (Instantiator<ScreenB>) -> __safeDI_Built, tabXBuilder: @escaping (Instantiator<ScreenB>, any Api) -> __safeDI_ApiCarrier_TabX<__safeDI_Built>, tabYBuilder: @escaping (Instantiator<ScreenB>, any Api) -> __safeDI_ApiCarrier_TabY<__safeDI_Built>) {
			            self.api = api
			            self.tabXBuilder = tabXBuilder
			            self.tabYBuilder = tabYBuilder
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_ScreenB<__safeDI_Built> {
			        public let api: (Instantiator<ScreenA>) -> __safeDI_Built

			        public init(api: @escaping (Instantiator<ScreenA>) -> __safeDI_Built) {
			            self.api = api
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_TabX<__safeDI_Built> {
			        public let api: (Instantiator<TabY>) -> __safeDI_Built

			        public init(api: @escaping (Instantiator<TabY>) -> __safeDI_Built) {
			            self.api = api
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_TabY<__safeDI_Built> {
			        public let api: (Instantiator<TabX>) -> __safeDI_Built

			        public init(api: @escaping (Instantiator<TabX>) -> __safeDI_Built) {
			            self.api = api
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
			        let __safeDI_screenABuilder_loopLevels = __safeDI_LoopLevels_0B2EF1D82F50807F(
			            __safeDI_apiBuilder_screenABuilder: __safeDI_apiBuilder.screenABuilder,
			            __safeDI_apiBuilder_screenBBuilder: __safeDI_apiBuilder.screenBBuilder
			        )
			        @inline(never) func __safeDI_screenABuilder() -> ScreenA {
			            let __safeDI_apiBuilder_screenABuilder = __safeDI_screenABuilder_loopLevels.__safeDI_apiBuilder_screenABuilder
			            let screenBBuilder = Instantiator<ScreenB>(__safeDI_screenBBuilder)
			            let api: any Api = __safeDI_apiBuilder_screenABuilder.api(screenBBuilder)
			            let __safeDI_tabXBuilder_loopLevels = __safeDI_LoopLevels_D40DAB636B814745(
			                __safeDI_apiBuilder_tabXBuilder: __safeDI_apiBuilder_screenABuilder.tabXBuilder(screenBBuilder, api),
			                __safeDI_apiBuilder_tabYBuilder: __safeDI_apiBuilder_screenABuilder.tabYBuilder(screenBBuilder, api)
			            )
			            @inline(never) func __safeDI_tabXBuilder() -> TabX {
			                let __safeDI_apiBuilder_tabXBuilder = __safeDI_tabXBuilder_loopLevels.__safeDI_apiBuilder_tabXBuilder
			                let tabYBuilder = Instantiator<TabY>(__safeDI_tabYBuilder)
			                let api: any Api = __safeDI_apiBuilder_tabXBuilder.api(tabYBuilder)
			                return TabX(api: api, tabYBuilder: tabYBuilder)
			            }
			            let tabXBuilder = Instantiator<TabX>(__safeDI_tabXBuilder)
			            @inline(never) func __safeDI_tabYBuilder() -> TabY {
			                let __safeDI_apiBuilder_tabYBuilder = __safeDI_tabXBuilder_loopLevels.__safeDI_apiBuilder_tabYBuilder
			                let tabXBuilder = Instantiator<TabX>(__safeDI_tabXBuilder)
			                let api: any Api = __safeDI_apiBuilder_tabYBuilder.api(tabXBuilder)
			                return TabY(api: api, tabXBuilder: tabXBuilder)
			            }
			            let tabYBuilder = Instantiator<TabY>(__safeDI_tabYBuilder)
			            return ScreenA(api: api, screenBBuilder: screenBBuilder, tabXBuilder: tabXBuilder, tabYBuilder: tabYBuilder)
			        }
			        let screenABuilder = Instantiator<ScreenA>(__safeDI_screenABuilder)
			        @inline(never) func __safeDI_screenBBuilder() -> ScreenB {
			            let __safeDI_apiBuilder_screenBBuilder = __safeDI_screenABuilder_loopLevels.__safeDI_apiBuilder_screenBBuilder
			            let screenABuilder = Instantiator<ScreenA>(__safeDI_screenABuilder)
			            let api: any Api = __safeDI_apiBuilder_screenBBuilder.api(screenABuilder)
			            return ScreenB(api: api, screenABuilder: screenABuilder)
			        }
			        let screenBBuilder = Instantiator<ScreenB>(__safeDI_screenBBuilder)
			        self.init(screenABuilder: screenABuilder, screenBBuilder: screenBBuilder)
			    }

			    /// Holds the payloads of a loop of builders, so that each builder function of the loop captures one reference.
			    nonisolated private final class __safeDI_LoopLevels_0B2EF1D82F50807F {
			        init(
			            __safeDI_apiBuilder_screenABuilder: __safeDI_ApiCarrier_ScreenA<any Api>,
			            __safeDI_apiBuilder_screenBBuilder: __safeDI_ApiCarrier_ScreenB<any Api>
			        ) {
			            self.__safeDI_apiBuilder_screenABuilder = __safeDI_apiBuilder_screenABuilder
			            self.__safeDI_apiBuilder_screenBBuilder = __safeDI_apiBuilder_screenBBuilder
			        }

			        let __safeDI_apiBuilder_screenABuilder: __safeDI_ApiCarrier_ScreenA<any Api>
			        let __safeDI_apiBuilder_screenBBuilder: __safeDI_ApiCarrier_ScreenB<any Api>
			    }

			    /// Holds the payloads of a loop of builders, so that each builder function of the loop captures one reference.
			    nonisolated private final class __safeDI_LoopLevels_D40DAB636B814745 {
			        init(
			            __safeDI_apiBuilder_tabXBuilder: __safeDI_ApiCarrier_TabX<any Api>,
			            __safeDI_apiBuilder_tabYBuilder: __safeDI_ApiCarrier_TabY<any Api>
			        ) {
			            self.__safeDI_apiBuilder_tabXBuilder = __safeDI_apiBuilder_tabXBuilder
			            self.__safeDI_apiBuilder_tabYBuilder = __safeDI_apiBuilder_tabYBuilder
			        }

			        let __safeDI_apiBuilder_tabXBuilder: __safeDI_ApiCarrier_TabX<any Api>
			        let __safeDI_apiBuilder_tabYBuilder: __safeDI_ApiCarrier_TabY<any Api>
			    }
			}

			extension Home {
			    public enum __safeDI_Home_31621E585D1B9CBB {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
			            .init(screenABuilder: __safeDI_apiBuilder_Home_ScreenA_Scope(), screenBBuilder: __safeDI_apiBuilder_Home_ScreenB_Scope())
			        }
			        func __safeDI_apiBuilder_Home_ScreenA_Scope() -> Home.__safeDI_ApiCarrier_ScreenA<any Api> {
			            .init(
			                api: { scope_screenBBuilder in
			                    let api: any Api = DefaultApi()
			                    return api
			                },
			                tabXBuilder: { values_screenBBuilder, values_api in __safeDI_apiBuilder_Home_TabX_Scope() },
			                tabYBuilder: { values_screenBBuilder, values_api in __safeDI_apiBuilder_Home_TabY_Scope() }
			            )
			        }
			        func __safeDI_apiBuilder_Home_TabX_Scope() -> Home.__safeDI_ApiCarrier_TabX<any Api> {
			            .init(api: { scope_tabYBuilder in
			                let api: any Api = DefaultApi()
			                return api
			            })
			        }
			        func __safeDI_apiBuilder_Home_TabY_Scope() -> Home.__safeDI_ApiCarrier_TabY<any Api> {
			            .init(api: { scope_tabXBuilder in
			                let api: any Api = DefaultApi()
			                return api
			            })
			        }
			        func __safeDI_apiBuilder_Home_ScreenB_Scope() -> Home.__safeDI_ApiCarrier_ScreenB<any Api> {
			            .init(api: { scope_screenABuilder in
			                let api: any Api = DefaultApi()
			                return api
			            })
			        }
			        func __safeDI_home() -> Home {
			            _ = Home.__safeDI_Home_31621E585D1B9CBB.self\(Self.callComment(module: "Feature"))
			            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
			        }
			        let home: Home = __safeDI_home()
			        self.init(home: home)
			    }
			}
			""",
		])
		try await expectValuesAndRetentionEqualInlineBuild(output, modules: modules, inlineModules: Self.modules(feature: inlineFixture(feature) + [Self.defaultApi], app: [Self.root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_capturesOneValueInEachLoopMembersFunction_whenSeamsLoopGrows() async throws {
		// Loops of 8, 16 and 32 screens, each holding a place and receiving the next screen's builder: each member's
		// builder function captures the box alone, however long the loop, where it captured every member's level.
		var captureCountsByLoopLength = [Int: Set<Int>]()
		for loopLength in [8, 16, 32] {
			let feature = ["public protocol Api {}"] + (0..<loopLength).map { index in
				seamFixtureType(named: "Screen\(index)", declarations: ["@Forwarded let id: Int", "@Instantiated let api: any Api", "@Received let screen\((index + 1) % loopLength)Builder: Instantiator<Screen\((index + 1) % loopLength)>"])
			} + [seamFixtureType(named: "Home", isSeam: true, declarations: (0..<loopLength).map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" })]
			let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(feature: feature, app: [Self.defaultApi, Self.root]), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
			let captures = try LocalFunctionCaptures.captures(inInitializerTaking: "__safeDI_apiBuilder", of: #require(output.modules["Feature"]?.generatedFiles["Feature.swift"]))
			captureCountsByLoopLength[loopLength] = Set((0..<loopLength).map { captures["__safeDI_screen\($0)Builder", default: []].count })
		}
		#expect(captureCountsByLoopLength == [8: [1], 16: [1], 32: [1]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsLoopsLevelsInABoxForEachCall_whenLoopIsInsideFunctionALazyCycleClosesOn() async throws {
		// `Flow`, which `Home` builds through an instantiator, declares the loop of `aBuilder` and `bBuilder`, and `A` builds
		// `Flow` again, closing a lazy cycle on `flowBuilder`'s function: the loop's box is bound inside that function, so
		// each call, the first and each one the cycle makes, binds a box of its own, as it bound the levels before.
		let feature = [
			"public protocol Api {}",
			seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let flowBuilder: Instantiator<Flow>"]),
			seamFixtureType(named: "Flow", isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let api: any Api", "@Received let bBuilder: Instantiator<B>", "@Instantiated let flowBuilder: Instantiator<Flow>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let api: any Api", "@Received let aBuilder: Instantiator<A>"]),
		]
		let modules = Self.modules(feature: feature, app: [Self.defaultApi, Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			"Feature.swift": generatedFileHeader + """
			extension Home {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
			        public let flowBuilder: __safeDI_ApiCarrier_Flow<__safeDI_Built>

			        public init(flowBuilder: __safeDI_ApiCarrier_Flow<__safeDI_Built>) {
			            self.flowBuilder = flowBuilder
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_Flow<__safeDI_Built> {
			        public let aBuilder: __safeDI_ApiCarrier_A<__safeDI_Built>
			        public let bBuilder: __safeDI_ApiCarrier_B<__safeDI_Built>

			        public init(aBuilder: __safeDI_ApiCarrier_A<__safeDI_Built>, bBuilder: __safeDI_ApiCarrier_B<__safeDI_Built>) {
			            self.aBuilder = aBuilder
			            self.bBuilder = bBuilder
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_A<__safeDI_Built> {
			        public let api: (Instantiator<B>, Instantiator<Flow>) -> __safeDI_Built

			        public init(api: @escaping (Instantiator<B>, Instantiator<Flow>) -> __safeDI_Built) {
			            self.api = api
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_B<__safeDI_Built> {
			        public let api: (Instantiator<A>) -> __safeDI_Built

			        public init(api: @escaping (Instantiator<A>) -> __safeDI_Built) {
			            self.api = api
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
			        let __safeDI_apiBuilder_flowBuilder = __safeDI_apiBuilder.flowBuilder
			        @inline(never) func __safeDI_flowBuilder() -> Flow {
			            let __safeDI_aBuilder_loopLevels = __safeDI_LoopLevels_9EAC39336BC1DA07(
			                __safeDI_apiBuilder_aBuilder: __safeDI_apiBuilder_flowBuilder.aBuilder,
			                __safeDI_apiBuilder_bBuilder: __safeDI_apiBuilder_flowBuilder.bBuilder
			            )
			            @inline(never) func __safeDI_aBuilder() -> A {
			                let __safeDI_apiBuilder_aBuilder = __safeDI_aBuilder_loopLevels.__safeDI_apiBuilder_aBuilder
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                let flowBuilder = Instantiator<Flow>(__safeDI_flowBuilder)
			                let api: any Api = __safeDI_apiBuilder_aBuilder.api(bBuilder, flowBuilder)
			                return A(api: api, bBuilder: bBuilder, flowBuilder: flowBuilder)
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            @inline(never) func __safeDI_bBuilder() -> B {
			                let __safeDI_apiBuilder_bBuilder = __safeDI_aBuilder_loopLevels.__safeDI_apiBuilder_bBuilder
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                let api: any Api = __safeDI_apiBuilder_bBuilder.api(aBuilder)
			                return B(api: api, aBuilder: aBuilder)
			            }
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return Flow(aBuilder: aBuilder, bBuilder: bBuilder)
			        }
			        let flowBuilder = Instantiator<Flow>(__safeDI_flowBuilder)
			        self.init(flowBuilder: flowBuilder)
			    }

			    /// Holds the payloads of a loop of builders, so that each builder function of the loop captures one reference.
			    nonisolated private final class __safeDI_LoopLevels_9EAC39336BC1DA07 {
			        init(
			            __safeDI_apiBuilder_aBuilder: __safeDI_ApiCarrier_A<any Api>,
			            __safeDI_apiBuilder_bBuilder: __safeDI_ApiCarrier_B<any Api>
			        ) {
			            self.__safeDI_apiBuilder_aBuilder = __safeDI_apiBuilder_aBuilder
			            self.__safeDI_apiBuilder_bBuilder = __safeDI_apiBuilder_bBuilder
			        }

			        let __safeDI_apiBuilder_aBuilder: __safeDI_ApiCarrier_A<any Api>
			        let __safeDI_apiBuilder_bBuilder: __safeDI_ApiCarrier_B<any Api>
			    }
			}

			extension Home {
			    public enum __safeDI_Home_363879E6EA1BD3C0 {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
			            .init(flowBuilder: __safeDI_apiBuilder_Home_Flow_Scope())
			        }
			        func __safeDI_apiBuilder_Home_Flow_Scope() -> Home.__safeDI_ApiCarrier_Flow<any Api> {
			            .init(aBuilder: __safeDI_apiBuilder_Home_A_Scope(), bBuilder: __safeDI_apiBuilder_Home_B_Scope())
			        }
			        func __safeDI_apiBuilder_Home_A_Scope() -> Home.__safeDI_ApiCarrier_A<any Api> {
			            .init(api: { scope_bBuilder, scope_flowBuilder in
			                let api: any Api = DefaultApi()
			                return api
			            })
			        }
			        func __safeDI_apiBuilder_Home_B_Scope() -> Home.__safeDI_ApiCarrier_B<any Api> {
			            .init(api: { scope_aBuilder in
			                let api: any Api = DefaultApi()
			                return api
			            })
			        }
			        func __safeDI_home() -> Home {
			            _ = Home.__safeDI_Home_363879E6EA1BD3C0.self\(Self.callComment(module: "Feature"))
			            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
			        }
			        let home: Home = __safeDI_home()
			        self.init(home: home)
			    }
			}
			""",
		])
		try await expectValuesAndRetentionEqualInlineBuild(output, modules: modules, inlineModules: Self.modules(feature: inlineFixture(feature) + [Self.defaultApi], app: [Self.root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresLoopLevelsClassInSeamsExtension_whenSeamIsDeclaredInGenericType() async throws {
		// `Home` is declared inside the generic `Box`, so its initializer is in a generic context, where Swift declares no
		// local type: the box's class is a member of `Home`'s extension, which compiles there.
		let feature = [
			"public protocol Api {}",
			"""
			public struct Box<Key> {
			    @Instantiable(generateDependencyTree: true)
			    public struct Home: Instantiable {
			        public init(screenABuilder: Instantiator<ScreenA>, screenBBuilder: Instantiator<ScreenB>) {
			            self.screenABuilder = screenABuilder
			            self.screenBBuilder = screenBBuilder
			        }

			        @Instantiated let screenABuilder: Instantiator<ScreenA>
			        @Instantiated let screenBBuilder: Instantiator<ScreenB>
			    }
			}
			""",
			seamFixtureType(named: "ScreenA", declarations: ["@Instantiated let api: any Api", "@Received let screenBBuilder: Instantiator<ScreenB>"]),
			seamFixtureType(named: "ScreenB", declarations: ["@Instantiated let api: any Api", "@Received let screenABuilder: Instantiator<ScreenA>"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(feature: feature, app: [Self.defaultApi]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif


			""",
		])
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			"Feature.swift": generatedFileHeader + """
			extension Box.Home {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
			        public let screenABuilder: __safeDI_ApiCarrier_ScreenA<__safeDI_Built>
			        public let screenBBuilder: __safeDI_ApiCarrier_ScreenB<__safeDI_Built>

			        public init(screenABuilder: __safeDI_ApiCarrier_ScreenA<__safeDI_Built>, screenBBuilder: __safeDI_ApiCarrier_ScreenB<__safeDI_Built>) {
			            self.screenABuilder = screenABuilder
			            self.screenBBuilder = screenBBuilder
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_ScreenA<__safeDI_Built> {
			        public let api: (Instantiator<ScreenB>) -> __safeDI_Built

			        public init(api: @escaping (Instantiator<ScreenB>) -> __safeDI_Built) {
			            self.api = api
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_ScreenB<__safeDI_Built> {
			        public let api: (Instantiator<ScreenA>) -> __safeDI_Built

			        public init(api: @escaping (Instantiator<ScreenA>) -> __safeDI_Built) {
			            self.api = api
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
			        let __safeDI_screenABuilder_loopLevels = __safeDI_LoopLevels_0B2EF1D82F50807F(
			            __safeDI_apiBuilder_screenABuilder: __safeDI_apiBuilder.screenABuilder,
			            __safeDI_apiBuilder_screenBBuilder: __safeDI_apiBuilder.screenBBuilder
			        )
			        @inline(never) func __safeDI_screenABuilder() -> ScreenA {
			            let __safeDI_apiBuilder_screenABuilder = __safeDI_screenABuilder_loopLevels.__safeDI_apiBuilder_screenABuilder
			            let screenBBuilder = Instantiator<ScreenB>(__safeDI_screenBBuilder)
			            let api: any Api = __safeDI_apiBuilder_screenABuilder.api(screenBBuilder)
			            return ScreenA(api: api, screenBBuilder: screenBBuilder)
			        }
			        let screenABuilder = Instantiator<ScreenA>(__safeDI_screenABuilder)
			        @inline(never) func __safeDI_screenBBuilder() -> ScreenB {
			            let __safeDI_apiBuilder_screenBBuilder = __safeDI_screenABuilder_loopLevels.__safeDI_apiBuilder_screenBBuilder
			            let screenABuilder = Instantiator<ScreenA>(__safeDI_screenABuilder)
			            let api: any Api = __safeDI_apiBuilder_screenBBuilder.api(screenABuilder)
			            return ScreenB(api: api, screenABuilder: screenABuilder)
			        }
			        let screenBBuilder = Instantiator<ScreenB>(__safeDI_screenBBuilder)
			        self.init(screenABuilder: screenABuilder, screenBBuilder: screenBBuilder)
			    }

			    /// Holds the payloads of a loop of builders, so that each builder function of the loop captures one reference.
			    nonisolated private final class __safeDI_LoopLevels_0B2EF1D82F50807F {
			        init(
			            __safeDI_apiBuilder_screenABuilder: __safeDI_ApiCarrier_ScreenA<any Api>,
			            __safeDI_apiBuilder_screenBBuilder: __safeDI_ApiCarrier_ScreenB<any Api>
			        ) {
			            self.__safeDI_apiBuilder_screenABuilder = __safeDI_apiBuilder_screenABuilder
			            self.__safeDI_apiBuilder_screenBBuilder = __safeDI_apiBuilder_screenBBuilder
			        }

			        let __safeDI_apiBuilder_screenABuilder: __safeDI_ApiCarrier_ScreenA<any Api>
			        let __safeDI_apiBuilder_screenBBuilder: __safeDI_ApiCarrier_ScreenB<any Api>
			    }
			}

			extension Box.Home {
			    public enum __safeDI_Box_Home_A55A411C911C1DEB {}
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresOneClassForBothBoxes_whenTwoLoopsBindTheSameLevels() async throws {
		// `Home` builds `Flow` twice, as `flowA` and `flowB`, and `Flow` declares the loop of `aBuilder` and `bBuilder`: each
		// build binds the loop's levels in a box of its own, under the same names and of the same types, so both boxes are
		// one class, declared once.
		let feature = [
			"public protocol Api {}",
			seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let flowA: Flow", "@Instantiated let flowB: Flow"]),
			seamFixtureType(named: "Flow", isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let api: any Api", "@Received let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let api: any Api", "@Received let aBuilder: Instantiator<A>"]),
		]
		let modules = Self.modules(feature: feature, app: [Self.defaultApi, Self.root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			"Feature.swift": generatedFileHeader + """
			extension Home {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
			        public let flowA: __safeDI_ApiCarrier_Flow<__safeDI_Built>
			        public let flowB: (Flow) -> __safeDI_ApiCarrier_Flow<__safeDI_Built>

			        public init(flowA: __safeDI_ApiCarrier_Flow<__safeDI_Built>, flowB: @escaping (Flow) -> __safeDI_ApiCarrier_Flow<__safeDI_Built>) {
			            self.flowA = flowA
			            self.flowB = flowB
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_Flow<__safeDI_Built> {
			        public let aBuilder: __safeDI_ApiCarrier_A<__safeDI_Built>
			        public let bBuilder: __safeDI_ApiCarrier_B<__safeDI_Built>

			        public init(aBuilder: __safeDI_ApiCarrier_A<__safeDI_Built>, bBuilder: __safeDI_ApiCarrier_B<__safeDI_Built>) {
			            self.aBuilder = aBuilder
			            self.bBuilder = bBuilder
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_A<__safeDI_Built> {
			        public let api: (Instantiator<B>) -> __safeDI_Built

			        public init(api: @escaping (Instantiator<B>) -> __safeDI_Built) {
			            self.api = api
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ApiCarrier_B<__safeDI_Built> {
			        public let api: (Instantiator<A>) -> __safeDI_Built

			        public init(api: @escaping (Instantiator<A>) -> __safeDI_Built) {
			            self.api = api
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
			        let __safeDI_apiBuilder_flowA = __safeDI_apiBuilder.flowA
			        @inline(never) func __safeDI_flowA() -> Flow {
			            let __safeDI_aBuilder_loopLevels = __safeDI_LoopLevels_9EAC39336BC1DA07(
			                __safeDI_apiBuilder_aBuilder: __safeDI_apiBuilder_flowA.aBuilder,
			                __safeDI_apiBuilder_bBuilder: __safeDI_apiBuilder_flowA.bBuilder
			            )
			            @inline(never) func __safeDI_aBuilder() -> A {
			                let __safeDI_apiBuilder_aBuilder = __safeDI_aBuilder_loopLevels.__safeDI_apiBuilder_aBuilder
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                let api: any Api = __safeDI_apiBuilder_aBuilder.api(bBuilder)
			                return A(api: api, bBuilder: bBuilder)
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            @inline(never) func __safeDI_bBuilder() -> B {
			                let __safeDI_apiBuilder_bBuilder = __safeDI_aBuilder_loopLevels.__safeDI_apiBuilder_bBuilder
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                let api: any Api = __safeDI_apiBuilder_bBuilder.api(aBuilder)
			                return B(api: api, aBuilder: aBuilder)
			            }
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return Flow(aBuilder: aBuilder, bBuilder: bBuilder)
			        }
			        let flowA: Flow = __safeDI_flowA()
			        let __safeDI_apiBuilder_flowB = __safeDI_apiBuilder.flowB(flowA)
			        @inline(never) func __safeDI_flowB() -> Flow {
			            let __safeDI_aBuilder_loopLevels = __safeDI_LoopLevels_9EAC39336BC1DA07(
			                __safeDI_apiBuilder_aBuilder: __safeDI_apiBuilder_flowB.aBuilder,
			                __safeDI_apiBuilder_bBuilder: __safeDI_apiBuilder_flowB.bBuilder
			            )
			            @inline(never) func __safeDI_aBuilder() -> A {
			                let __safeDI_apiBuilder_aBuilder = __safeDI_aBuilder_loopLevels.__safeDI_apiBuilder_aBuilder
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                let api: any Api = __safeDI_apiBuilder_aBuilder.api(bBuilder)
			                return A(api: api, bBuilder: bBuilder)
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            @inline(never) func __safeDI_bBuilder() -> B {
			                let __safeDI_apiBuilder_bBuilder = __safeDI_aBuilder_loopLevels.__safeDI_apiBuilder_bBuilder
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                let api: any Api = __safeDI_apiBuilder_bBuilder.api(aBuilder)
			                return B(api: api, aBuilder: aBuilder)
			            }
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return Flow(aBuilder: aBuilder, bBuilder: bBuilder)
			        }
			        let flowB: Flow = __safeDI_flowB()
			        self.init(flowA: flowA, flowB: flowB)
			    }

			    /// Holds the payloads of a loop of builders, so that each builder function of the loop captures one reference.
			    nonisolated private final class __safeDI_LoopLevels_9EAC39336BC1DA07 {
			        init(
			            __safeDI_apiBuilder_aBuilder: __safeDI_ApiCarrier_A<any Api>,
			            __safeDI_apiBuilder_bBuilder: __safeDI_ApiCarrier_B<any Api>
			        ) {
			            self.__safeDI_apiBuilder_aBuilder = __safeDI_apiBuilder_aBuilder
			            self.__safeDI_apiBuilder_bBuilder = __safeDI_apiBuilder_bBuilder
			        }

			        let __safeDI_apiBuilder_aBuilder: __safeDI_ApiCarrier_A<any Api>
			        let __safeDI_apiBuilder_bBuilder: __safeDI_ApiCarrier_B<any Api>
			    }
			}

			extension Home {
			    public enum __safeDI_Home_6F8ACC2B52D54906 {}
			}
			""",
		])
		try await expectValuesAndRetentionEqualInlineBuild(output, modules: modules, inlineModules: Self.modules(feature: inlineFixture(feature) + [Self.defaultApi], app: [Self.root]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_boxesOnlyTheSeamsOwnTree_whenSeamWithPublicMockFillsCalledHoleWithLoopOfBuilders() async throws {
		// `Outer`, a seam with a public mock, builds `Inner`, a seam with a public mock of another package, and fills its
		// `service` with `DefaultService`, whose loop of `LoopA` and `LoopB` holds `Outer`'s places of `Gadget`. The seam's
		// initializer boxes the loop's levels and declares the class beside it; the public mock, which the SwiftPM plugin
		// writes to a file of its own, binds the loop's payloads in a `let` each and names no class.
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Service {}\npublic protocol Gadget {}",
				Self.seamWithPublicMock(named: "Inner", declarations: ["@Instantiated public let service: any Service"]),
			]),
			ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: [
				Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let aBuilder: Instantiator<LoopA>", "@Instantiated public let bBuilder: Instantiator<LoopB>"]),
				seamFixtureType(named: "LoopA", isFinalClass: true, declarations: ["@Instantiated public let gadget: any Gadget", "@Received public let bBuilder: Instantiator<LoopB>"]),
				seamFixtureType(named: "LoopB", isFinalClass: true, declarations: ["@Instantiated public let gadget: any Gadget", "@Received public let aBuilder: Instantiator<LoopA>"]),
				Self.seamWithPublicMock(named: "Outer", declarations: ["@Instantiated public let inner: Inner"], initializerAccess: "public"),
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: []),
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let outer: Outer"])
					.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: true)"),
			].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .swiftPackagePlugin, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			"Inner+SafeDI.swift": generatedFileHeader + """
			extension Inner {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
			        public let service: () -> __safeDI_Built

			        public init(service: @escaping () -> __safeDI_Built) {
			            self.service = service
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
			        let service: any Service = __safeDI_serviceBuilder.service()
			        self.init(service: service)
			    }
			}

			extension Inner {
			    public enum __safeDI_Inner_99BD917DA5EDFC3D {}
			}
			""",
			"Inner+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Inner {
			    nonisolated public enum SafeDIMockScope_Service {
			        nonisolated public struct service_Values {}

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let service: (service_Values) -> __safeDI_Built

			            public init(service: @escaping (service_Values) -> __safeDI_Built) {
			                self.service = service
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(service: { _ in __safeDI_builder() })
			            }
			        }
			    }

			    public static func mock(
			        serviceBuilder: @escaping () -> any Service
			    ) -> Inner {
			        Inner.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder))
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        serviceBuilder __safeDI_serviceBuilder: Inner.SafeDIMockScope_Service.__safeDI_Builder<any Service>
			    ) -> Inner {
			        let service: any Service = __safeDI_serviceBuilder.service(SafeDIMockScope_Service.service_Values())
			        return Inner(service: service)
			    }
			}

			extension Inner {
			    public enum __safeDI_Inner_mock_E789692848368FB8 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """

			""",
		])
		expectGeneratedFiles(output.modules["Middle"]?.generatedFiles, [
			"Outer+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Outer {
			    nonisolated public enum SafeDIScope_Gadget {
			        nonisolated public struct inner_serviceBuilder_Values {}

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct aBuilder_Values {}

			            nonisolated public struct bBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let aBuilder: (aBuilder_Values) -> SafeDIScope_Gadget.LoopA_Scope.__safeDI_Builder<__safeDI_Built>
			                public let bBuilder: (bBuilder_Values) -> SafeDIScope_Gadget.LoopB_Scope.__safeDI_Builder<__safeDI_Built>

			                public init(aBuilder: @escaping (aBuilder_Values) -> SafeDIScope_Gadget.LoopA_Scope.__safeDI_Builder<__safeDI_Built>, bBuilder: @escaping (bBuilder_Values) -> SafeDIScope_Gadget.LoopB_Scope.__safeDI_Builder<__safeDI_Built>) {
			                    self.aBuilder = aBuilder
			                    self.bBuilder = bBuilder
			                }
			            }
			        }

			        nonisolated public enum LoopA_Scope {
			            nonisolated public struct gadget_Values {
			                public let bBuilder: Instantiator<LoopB>
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }
			            }
			        }

			        nonisolated public enum LoopB_Scope {
			            nonisolated public struct gadget_Values {
			                public let aBuilder: Instantiator<LoopA>
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public convenience init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIScope_Gadget.inner_serviceBuilder_Values())
			        @inline(never) func __safeDI_inner() -> Inner {
			            _ = Inner.__safeDI_Inner_99BD917DA5EDFC3D.self // If this line does not compile, add the SafeDI plugin to the target that declares Inner.
			            @inline(never) func __safeDI_serviceBuilder_Inner_service(__safeDI_inner_serviceBuilder: SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                @inline(never) func __safeDI_service() -> DefaultService {
			                    let __safeDI_aBuilder_loopLevels = __safeDI_LoopLevels_A5B9BE4983B4B4E1(
			                        __safeDI_gadgetBuilder_aBuilder: __safeDI_inner_serviceBuilder.aBuilder(SafeDIScope_Gadget.DefaultService_Scope.aBuilder_Values()),
			                        __safeDI_gadgetBuilder_bBuilder: __safeDI_inner_serviceBuilder.bBuilder(SafeDIScope_Gadget.DefaultService_Scope.bBuilder_Values())
			                    )
			                    @inline(never) func __safeDI_aBuilder() -> LoopA {
			                        let __safeDI_gadgetBuilder_aBuilder = __safeDI_aBuilder_loopLevels.__safeDI_gadgetBuilder_aBuilder
			                        let bBuilder = Instantiator<LoopB>(__safeDI_bBuilder)
			                        let gadget: any Gadget = __safeDI_gadgetBuilder_aBuilder.gadget(SafeDIScope_Gadget.LoopA_Scope.gadget_Values(bBuilder: bBuilder))
			                        return LoopA(gadget: gadget, bBuilder: bBuilder)
			                    }
			                    let aBuilder = Instantiator<LoopA>(__safeDI_aBuilder)
			                    @inline(never) func __safeDI_bBuilder() -> LoopB {
			                        let __safeDI_gadgetBuilder_bBuilder = __safeDI_aBuilder_loopLevels.__safeDI_gadgetBuilder_bBuilder
			                        let aBuilder = Instantiator<LoopA>(__safeDI_aBuilder)
			                        let gadget: any Gadget = __safeDI_gadgetBuilder_bBuilder.gadget(SafeDIScope_Gadget.LoopB_Scope.gadget_Values(aBuilder: aBuilder))
			                        return LoopB(gadget: gadget, aBuilder: aBuilder)
			                    }
			                    let bBuilder = Instantiator<LoopB>(__safeDI_bBuilder)
			                    return DefaultService(aBuilder: aBuilder, bBuilder: bBuilder)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            @inline(never) func __safeDI_serviceBuilder_Inner(up: Inner.__safeDI_ServiceCarrier<SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.__safeDI_ServiceCarrier<any Service> {
			                .init(service: { __safeDI_serviceBuilder_Inner_service(__safeDI_inner_serviceBuilder: up.service()) })
			            }
			            return Inner(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder))
			        }
			        let inner: Inner = __safeDI_inner()
			        self.init(inner: inner)
			    }

			    /// Holds the payloads of a loop of builders, so that each builder function of the loop captures one reference.
			    nonisolated private final class __safeDI_LoopLevels_A5B9BE4983B4B4E1 {
			        init(
			            __safeDI_gadgetBuilder_aBuilder: SafeDIScope_Gadget.LoopA_Scope.__safeDI_Builder<any Gadget>,
			            __safeDI_gadgetBuilder_bBuilder: SafeDIScope_Gadget.LoopB_Scope.__safeDI_Builder<any Gadget>
			        ) {
			            self.__safeDI_gadgetBuilder_aBuilder = __safeDI_gadgetBuilder_aBuilder
			            self.__safeDI_gadgetBuilder_bBuilder = __safeDI_gadgetBuilder_bBuilder
			        }

			        let __safeDI_gadgetBuilder_aBuilder: SafeDIScope_Gadget.LoopA_Scope.__safeDI_Builder<any Gadget>
			        let __safeDI_gadgetBuilder_bBuilder: SafeDIScope_Gadget.LoopB_Scope.__safeDI_Builder<any Gadget>
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_757BD5316E5FE50B {}
			}
			""",
			"Outer+SafeDIMock.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			#if DEBUG
			extension Outer {
			    nonisolated public enum SafeDIMockScope_Gadget {
			        nonisolated public struct inner_serviceBuilder_Values {}

			        nonisolated public enum DefaultService_Scope {
			            nonisolated public struct aBuilder_Values {}

			            nonisolated public struct bBuilder_Values {}

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let aBuilder: (aBuilder_Values) -> SafeDIMockScope_Gadget.LoopA_Scope.__safeDI_Builder<__safeDI_Built>
			                public let bBuilder: (bBuilder_Values) -> SafeDIMockScope_Gadget.LoopB_Scope.__safeDI_Builder<__safeDI_Built>

			                public init(aBuilder: @escaping (aBuilder_Values) -> SafeDIMockScope_Gadget.LoopA_Scope.__safeDI_Builder<__safeDI_Built>, bBuilder: @escaping (bBuilder_Values) -> SafeDIMockScope_Gadget.LoopB_Scope.__safeDI_Builder<__safeDI_Built>) {
			                    self.aBuilder = aBuilder
			                    self.bBuilder = bBuilder
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(aBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) }, bBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			                }
			            }
			        }

			        nonisolated public enum LoopA_Scope {
			            nonisolated public struct gadget_Values {
			                public let bBuilder: Instantiator<LoopB>
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gadget: { _ in __safeDI_builder() })
			                }
			            }
			        }

			        nonisolated public enum LoopB_Scope {
			            nonisolated public struct gadget_Values {
			                public let aBuilder: Instantiator<LoopA>
			            }

			            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			                public let gadget: (gadget_Values) -> __safeDI_Built

			                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
			                    self.gadget = gadget
			                }

			                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                    self.init(gadget: { _ in __safeDI_builder() })
			                }
			            }
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>

			            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>) {
			                self.inner_serviceBuilder = inner_serviceBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			                self.init(inner_serviceBuilder: { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) })
			            }
			        }
			    }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {}
			    }

			    public static func mock(
			        gadgetBuilder: @escaping () -> any Gadget,
			        serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        Outer.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), serviceBuilder: serviceBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        gadgetBuilder __safeDI_gadgetBuilder: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>,
			        serviceBuilder __safeDI_serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Outer {
			        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIMockScope_Gadget.inner_serviceBuilder_Values())
			        func __safeDI_inner() -> Inner {
			            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIMockScope_Service.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
			                func __safeDI_service() -> DefaultService {
			                    let __safeDI_gadgetBuilder_aBuilder = __safeDI_inner_serviceBuilder.aBuilder(SafeDIMockScope_Gadget.DefaultService_Scope.aBuilder_Values())
			                    let __safeDI_gadgetBuilder_bBuilder = __safeDI_inner_serviceBuilder.bBuilder(SafeDIMockScope_Gadget.DefaultService_Scope.bBuilder_Values())
			                    func __safeDI_aBuilder() -> LoopA {
			                        let bBuilder = Instantiator<LoopB>(__safeDI_bBuilder)
			                        let gadget: any Gadget = __safeDI_gadgetBuilder_aBuilder.gadget(SafeDIMockScope_Gadget.LoopA_Scope.gadget_Values(bBuilder: bBuilder))
			                        return LoopA(gadget: gadget, bBuilder: bBuilder)
			                    }
			                    let aBuilder = Instantiator<LoopA>(__safeDI_aBuilder)
			                    func __safeDI_bBuilder() -> LoopB {
			                        let aBuilder = Instantiator<LoopA>(__safeDI_aBuilder)
			                        let gadget: any Gadget = __safeDI_gadgetBuilder_bBuilder.gadget(SafeDIMockScope_Gadget.LoopB_Scope.gadget_Values(aBuilder: aBuilder))
			                        return LoopB(gadget: gadget, aBuilder: aBuilder)
			                    }
			                    let bBuilder = Instantiator<LoopB>(__safeDI_bBuilder)
			                    return DefaultService(aBuilder: aBuilder, bBuilder: bBuilder)
			                }
			                let service: any Service = __safeDI_service()
			                return service
			            }
			            func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                .init(service: { scope in __safeDI_serviceBuilder_Inner_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
			            }
			            _ = Inner.__safeDI_Inner_mock_E789692848368FB8.self // If this line does not compile, add the SafeDI plugin to the target that declares Inner.
			            return Inner.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder))
			        }
			        let inner: Inner = __safeDI_inner()
			        return Outer(inner: inner)
			    }
			}

			extension Outer {
			    public enum __safeDI_Outer_mock_BBEADFB7A541D124 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif


			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
			            .init(inner_serviceBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner() })
			        }
			        func __safeDI_gadgetBuilder_Outer_DefaultService_Scope() -> Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
			            .init(aBuilder: { _ in __safeDI_gadgetBuilder_Outer_LoopA_Scope() }, bBuilder: { _ in __safeDI_gadgetBuilder_Outer_LoopB_Scope() })
			        }
			        func __safeDI_gadgetBuilder_Outer_LoopA_Scope() -> Outer.SafeDIScope_Gadget.LoopA_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { _ in
			                let gadget: any Gadget = LiveGadget()
			                return gadget
			            })
			        }
			        func __safeDI_gadgetBuilder_Outer_LoopB_Scope() -> Outer.SafeDIScope_Gadget.LoopB_Scope.__safeDI_Builder<any Gadget> {
			            .init(gadget: { _ in
			                let gadget: any Gadget = LiveGadget()
			                return gadget
			            })
			        }
			        func __safeDI_gadgetBuilder_Outer_Inner() -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
			            .init(service: { __safeDI_gadgetBuilder_Outer_DefaultService_Scope() })
			        }
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_757BD5316E5FE50B.self // If this line does not compile, add the SafeDI plugin to the target that declares Outer.
			            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(outer: outer)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            outer: Outer.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                outer: outer
			            )
			        }

			        var outer: Outer.SafeDIMockConfiguration { __safeDI_storage.outer }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                outer: Outer.SafeDIMockConfiguration
			            ) {
			                self.outer = outer
			            }

			            let outer: Outer.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        serviceBuilder: (() -> any Service)? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_outer() -> Outer {
			            func __safeDI_inner() -> Inner {
			                func __safeDI_serviceBuilder_Inner_service() -> any Service {
			                    func __safeDI_service() -> DefaultService {
			                        func __safeDI_aBuilder() -> LoopA {
			                            let bBuilder = Instantiator<LoopB>(__safeDI_bBuilder)
			                            let gadget: any Gadget = LiveGadget()
			                            return LoopA(gadget: gadget, bBuilder: bBuilder)
			                        }
			                        let aBuilder = Instantiator<LoopA>(__safeDI_aBuilder)
			                        func __safeDI_bBuilder() -> LoopB {
			                            let aBuilder = Instantiator<LoopA>(__safeDI_aBuilder)
			                            let gadget: any Gadget = LiveGadget()
			                            return LoopB(gadget: gadget, aBuilder: aBuilder)
			                        }
			                        let bBuilder = Instantiator<LoopB>(__safeDI_bBuilder)
			                        return DefaultService(aBuilder: aBuilder, bBuilder: bBuilder)
			                    }
			                    let service: any Service = __safeDI_service()
			                    return service
			                }
			                func __safeDI_serviceBuilder_Inner() -> Inner.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
			                    .init(service: { _ in __safeDI_serviceBuilder_Inner_service() })
			                }
			                _ = Inner.__safeDI_Inner_mock_E789692848368FB8.self // If this line does not compile, add the SafeDI plugin to the target that declares Inner.
			                return if let safeDIBuilder = safeDIOverrides.outer.inner { safeDIBuilder({ if let serviceBuilder { serviceBuilder() } else { __safeDI_serviceBuilder_Inner_service() } }) } else { Inner.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Inner()) }
			            }
			            let inner: Inner = __safeDI_inner()
			            return if let safeDIBuilder = safeDIOverrides.outer.safeDIBuilder { safeDIBuilder(inner) } else { Outer(inner: inner) }
			        }
			        let outer: Outer = __safeDI_outer()
			        return Root(outer: outer)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Middle)
			import Middle
			#endif

			#if DEBUG
			extension Outer {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            inner: ((@escaping () -> any Service) -> Inner)? = nil,
			            _ safeDIBuilder: ((Inner) -> Outer)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                inner: inner,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var inner: ((@escaping () -> any Service) -> Inner)? { __safeDI_storage.inner }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Inner) -> Outer)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                inner: ((@escaping () -> any Service) -> Inner)?,
			                safeDIBuilder: ((Inner) -> Outer)?
			            ) {
			                self.inner = inner
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let inner: ((@escaping () -> any Service) -> Inner)?
			            let safeDIBuilder: ((Inner) -> Outer)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A public final class named `name`, a seam with a public mock, whose initializer has `initializerAccess`: `package`
	/// keeps every module of another package from building it inline.
	private static func seamWithPublicMock(named name: String, declarations: [String], initializerAccess: String = "package") -> String {
		seamFixtureType(named: name, isSeam: true, isFinalClass: true, declarations: declarations)
			.replacingOccurrences(of: "@Instantiable(generateDependencyTree: true)", with: "@Instantiable(generateDependencyTree: true, generateMock: .public)")
			.replacingOccurrences(of: "    public init(", with: "    \(initializerAccess) init(")
	}

	private static func fulfillingType(named name: String, fulfilling fulfilledType: String, declarations: [String]) -> String {
		seamFixtureType(named: name, isFinalClass: true, declarations: declarations, conformances: ", \(fulfilledType)")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [\(fulfilledType).self])\n")
	}

	/// `Home`, a seam, and the three screens of its loop, each forwarding an `id`, holding a place of `Api` and receiving
	/// the next screen's builder.
	private static let ringFeature = [
		"public protocol Api {}",
		seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let screenABuilder: Instantiator<ScreenA>", "@Instantiated let screenBBuilder: Instantiator<ScreenB>", "@Instantiated let screenCBuilder: Instantiator<ScreenC>"]),
		seamFixtureType(named: "ScreenA", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let api: any Api", "@Received let screenBBuilder: Instantiator<ScreenB>"]),
		seamFixtureType(named: "ScreenB", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let api: any Api", "@Received let screenCBuilder: Instantiator<ScreenC>"]),
		seamFixtureType(named: "ScreenC", isFinalClass: true, declarations: ["@Forwarded let id: Int", "@Instantiated let api: any Api", "@Received let screenABuilder: Instantiator<ScreenA>"]),
	]

	/// What the comparator calls each screen's instantiator with: its forwarded `id`.
	private static let ringSamples = ["ScreenA", "ScreenB", "ScreenC"].map { DifferentialValueSample(type: "\($0).ForwardedProperties", expression: "7") }

	/// The type that fills each place of `Api`.
	private static let defaultApi = """
	@Instantiable(fulfillingAdditionalTypes: [Api.self])
	public final class DefaultApi: Instantiable, Api {
	    public init() {}
	}
	"""

	/// The root, which builds `Home`.
	private static let root = seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let home: Home"])

	private static func modules(feature: [String], app: [String]) -> [ModuleFixture] {
		SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app)
	}

	private static func callComment(module: String) -> String {
		MultiModuleIntegration.moduleInfo.seamCallComment(type: "", declaringModule: module)
	}

	/// Expects `output`, the run of `modules`, to build the values the run of `inlineModules`, the same graph built inline,
	/// builds for `Root()`, and to keep alive no more of them than the inline build keeps once the root is released, holding
	/// each wrapper the root's value holds and what one call of it builds, calling an instantiator that forwards a value with
	/// the sample of its type `samples` holds.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectValuesAndRetentionEqualInlineBuild(
		_ output: MultiModuleTestOutput,
		modules: [ModuleFixture],
		inlineModules: [ModuleFixture],
		samples: [DifferentialValueSample] = [],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		guard compileVerificationIsEnabled else { return }
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let graph = try DifferentialValueGraph(
			name: "loop levels",
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: inlineOutput, modules: inlineModules),
			probes: [DifferentialValueProbe("Root()")],
			samples: samples,
			judgesRetention: true,
		)
		let comparison = try #require(try await DifferentialValueOracle.compare(graphs: [graph], filesToDelete: &filesToDelete)?.first?.result.get(), sourceLocation: sourceLocation)
		#expect(comparison.differences == [], sourceLocation: sourceLocation)
		#expect(comparison.retentionDifferences == [], sourceLocation: sourceLocation)
		#expect(comparison.retentionJudgedProbes == ["Root()"], sourceLocation: sourceLocation)
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
