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

/// A plain place beneath a level of the `@Sendable` family: `Home` builds `Screen` in a `SendableInstantiator`, and
/// `Screen`, which forwards `id` and binds a non-`Sendable` `Token`, builds `Detail` in a plain `Instantiator`, whose
/// place of `Api` the calling module fills reading both. The `@Sendable` family's carrier hands the plain level's carrier
/// on per build, so no `@Sendable` closure captures a non-`Sendable` value, whichever module defaults to the main actor
/// and whatever isolation the root that builds the seam has; the seam build holds the inline build's values and keeps
/// no more of them alive.
struct SafeDIToolSeamCarrierMixedTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test(arguments: CarrierCellIsolation.allCases, CarrierCellRoot.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesPlainCarrierBeneathSendableLevel_whenEitherModuleDefaultsToMainActor(isolation: CarrierCellIsolation, root: CarrierCellRoot) async throws {
		let modules = Self.modules(isolation: isolation, root: root)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		CarrierCells.expectGeneratedFiles(output.modules["Seam"]?.generatedFiles, ["Seam.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Screen<__safeDI_Built> {
		        public let detailBuilder: (Int, Token) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: @escaping (Int, Token) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
		        public let screenBuilder: @Sendable () -> __safeDI_ApiCarrier_Screen<__safeDI_Built>

		        public init(screenBuilder: @escaping @Sendable () -> __safeDI_ApiCarrier_Screen<__safeDI_Built>) {
		            self.screenBuilder = screenBuilder
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
		        @inline(never) @Sendable nonisolated func __safeDI_detailBuilder(__safeDI_apiSendableBuilder_detailBuilder: __safeDI_ApiCarrier_Detail<any Api>) -> Detail {
		            let api: any Api = __safeDI_apiSendableBuilder_detailBuilder.api()
		            return Detail(api: api)
		        }
		        @inline(never) @Sendable nonisolated func __safeDI_screenBuilder(id: Int) -> Screen {
		            let __safeDI_apiSendableBuilder_screenBuilder = __safeDI_apiSendableBuilder.screenBuilder()
		            let token = Token()
		            let __safeDI_apiSendableBuilder_detailBuilder = __safeDI_apiSendableBuilder_screenBuilder.detailBuilder(id, token)
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(__safeDI_apiSendableBuilder_detailBuilder: __safeDI_apiSendableBuilder_detailBuilder)
		            }
		            return Screen(id: id, token: token, detailBuilder: detailBuilder)
		        }
		        let screenBuilder = SendableInstantiator<Screen> {
		            __safeDI_screenBuilder(id: $0)
		        }
		        self.init(screenBuilder: screenBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_383C96112B20F131 {}
		}
		"""])
		CarrierCells.expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    \(root.generatedInitializerDeclaration) {
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.__safeDI_ApiSendableCarrier<any Api> {
		            .init(screenBuilder: { __safeDI_apiBuilder_Home_Screen_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.__safeDI_ApiCarrier_Screen<any Api> {
		            .init(detailBuilder: { values_id, values_token in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, token: values_token) })
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Detail_Scope(id: Int, token: Token) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = Impl(id: id, token: token)
		                return api
		            })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_383C96112B20F131.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func retention_plainChildUnderSendableLevelKeepsOnlyItsReads() async throws {
		let isolation = CarrierCellIsolation(seamModuleIsMainActorByDefault: false, callingModuleIsMainActorByDefault: false)
		let modules = Self.modules(isolation: isolation, root: .structRoot)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		try await CarrierCells.expectValuesAndRetentionEqualInlineBuild(
			output,
			modules: modules,
			samples: [DifferentialValueSample(type: "Screen.ForwardedProperties", expression: "7")],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readableInitializerCompiles_whenPlainPlaceIsBeneathSendableLevel() async throws {
		let modules = [
			ModuleFixture(
				name: "Seam",
				packageName: "pkg",
				swiftFileContentByFilePath: ["Types.swift": Self.seam].merging(plainDependencyTreeInitializersConfiguration) { first, _ in first },
			),
			ModuleFixture(
				name: "App",
				packageName: "other",
				swiftFileContentByFilePath: ["Caller.swift": Self.readableCaller],
				dependencies: ["Seam"],
			),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		CarrierCells.expectGeneratedFiles(output.modules["Seam"]?.generatedFiles, ["Seam.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Screen<__safeDI_Built> {
		        public let detailBuilder: (Int, Token) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: @escaping (Int, Token) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiSendableCarrier<__safeDI_Built>: Sendable {
		        public let screenBuilder: @Sendable () -> __safeDI_ApiCarrier_Screen<__safeDI_Built>

		        public init(screenBuilder: @escaping @Sendable () -> __safeDI_ApiCarrier_Screen<__safeDI_Built>) {
		            self.screenBuilder = screenBuilder
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(apiSendableBuilder: @escaping @Sendable () -> any Api) {
		        @Sendable nonisolated func __safeDI_noScope_Home_SafeDISendableCarrierScope_Api<__safeDI_Built>(_ __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) -> Home.__safeDI_ApiSendableCarrier<__safeDI_Built> {
		            .init(screenBuilder: { __safeDI_noScope_Home_SafeDICarrierScope_Api_Screen_Scope(__safeDI_builder) })
		        }
		        @Sendable nonisolated func __safeDI_noScope_Home_SafeDICarrierScope_Api_Screen_Scope<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Home.__safeDI_ApiCarrier_Screen<__safeDI_Built> {
		            .init(detailBuilder: { _, _ in __safeDI_noScope_Home_SafeDICarrierScope_Api_Detail_Scope(__safeDI_builder) })
		        }
		        @Sendable nonisolated func __safeDI_noScope_Home_SafeDICarrierScope_Api_Detail_Scope<__safeDI_Built>(_ __safeDI_builder: @escaping () -> __safeDI_Built) -> Home.__safeDI_ApiCarrier_Detail<__safeDI_Built> {
		            .init(api: { __safeDI_builder() })
		        }
		        self.init(__safeDI_apiSendableBuilder: __safeDI_noScope_Home_SafeDISendableCarrierScope_Api(apiSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
		        @inline(never) @Sendable nonisolated func __safeDI_detailBuilder(__safeDI_apiSendableBuilder_detailBuilder: __safeDI_ApiCarrier_Detail<any Api>) -> Detail {
		            let api: any Api = __safeDI_apiSendableBuilder_detailBuilder.api()
		            return Detail(api: api)
		        }
		        @inline(never) @Sendable nonisolated func __safeDI_screenBuilder(id: Int) -> Screen {
		            let __safeDI_apiSendableBuilder_screenBuilder = __safeDI_apiSendableBuilder.screenBuilder()
		            let token = Token()
		            let __safeDI_apiSendableBuilder_detailBuilder = __safeDI_apiSendableBuilder_screenBuilder.detailBuilder(id, token)
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(__safeDI_apiSendableBuilder_detailBuilder: __safeDI_apiSendableBuilder_detailBuilder)
		            }
		            return Screen(id: id, token: token, detailBuilder: detailBuilder)
		        }
		        let screenBuilder = SendableInstantiator<Screen> {
		            __safeDI_screenBuilder(id: $0)
		        }
		        self.init(screenBuilder: screenBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_383C96112B20F131 {}
		}
		"""])
	}

	// MARK: Fixtures

	private static func modules(isolation: CarrierCellIsolation, root: CarrierCellRoot) -> [ModuleFixture] {
		[
			ModuleFixture(
				name: "Seam",
				packageName: "pkg",
				swiftFileContentByFilePath: ["Types.swift": seam],
				compilerSettings: isolation.seamModuleSettings,
			),
			ModuleFixture(
				name: "App",
				packageName: "pkg",
				swiftFileContentByFilePath: ["Root.swift": impl + "\n" + root.declaration(building: "home: Home")],
				dependencies: ["Seam"],
				compilerSettings: isolation.callingModuleSettings,
			),
		]
	}

	/// `Api` is `nonisolated`, as `SafeDIToolSeamBuilderStructMatrixTests`' main-actor fixtures declare theirs: where
	/// this module defaults to the main actor, Swift 6.4 infers main-actor isolation for the fill's `Impl` from its
	/// conformance to an isolated `Api` ("call to main actor-isolated initializer … in a synchronous nonisolated
	/// context"), which Swift 6.2 does not.
	private static let seam = """
	import SafeDI

	nonisolated public protocol Api {}

	@Instantiable
	public final class Token: Instantiable {
	    public init() {}
	}

	@Instantiable
	public final class Detail: Instantiable {
	    public init(api: any Api) { self.api = api }
	    @Instantiated let api: any Api
	}

	@Instantiable
	public final class Screen: Instantiable {
	    public init(id: Int, token: Token, detailBuilder: Instantiator<Detail>) {
	        self.id = id; self.token = token; self.detailBuilder = detailBuilder
	    }
	    @Forwarded let id: Int
	    @Instantiated let token: Token
	    @Instantiated let detailBuilder: Instantiator<Detail>
	}

	@Instantiable(generateDependencyTree: true)
	public final class Home: Instantiable {
	    public init(screenBuilder: SendableInstantiator<Screen>) { self.screenBuilder = screenBuilder }
	    @Instantiated let screenBuilder: SendableInstantiator<Screen>
	}
	"""

	/// The fill of `Api`, which reads the level's `id` and `Token`.
	private static let impl = """
	import Seam
	import SafeDI

	@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
	public final class Impl: Api, Instantiable {
	    public init(id: Int, token: Token) { self.id = id; self.token = token }
	    @Received let id: Int
	    @Received let token: Token
	}
	"""

	/// A person's call of `Home`'s readable initializer, which takes the builder of `Api` as a closure that takes
	/// nothing, and a check that the builder runs once per build of `Detail`.
	private static let readableCaller = """
	import Seam
	import SafeDI

	final class Fake: Api {}

	func makeHome() -> (home: Home, count: () -> Int) {
	    final class Counter: @unchecked Sendable { var value = 0 }
	    let counter = Counter()
	    let home = Home(apiSendableBuilder: {
	        counter.value += 1
	        return Fake()
	    })
	    return (home, { counter.value })
	}
	"""

	private var filesToDelete: [URL]
}
