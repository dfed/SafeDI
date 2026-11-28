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

/// A seam's carriers are `nonisolated` classes whose members take a level's values in run structs, and its caller's level
/// functions form them. Each holds a non-`Sendable` value (`Model`), the `@Sendable` family's carrier hands a plain carrier
/// on, and the level a `@Sendable` function reaches is formed by a `@Sendable nonisolated` function that takes the values it
/// reads. Every cell compiles, without a warning, whichever of the two modules defaults to the main actor and whether the
/// root is a struct or a class on the main actor.
struct SafeDIToolSeamCarrierIsolationTests: ~Copyable {
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

	@Test(arguments: DefaultIsolationCase.allCases, RootKind.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesCarriersAndCallersLevelFunctions_whenEitherModuleDefaultsToMainActor(isolation: DefaultIsolationCase, root: RootKind) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Seam",
					packageName: "pkg",
					swiftFileContentByFilePath: ["Types.swift": Self.seam],
					compilerSettings: isolation.seamModuleSettings,
				),
				ModuleFixture(
					name: "App",
					packageName: "pkg",
					swiftFileContentByFilePath: ["Root.swift": root.callerFixture],
					dependencies: ["Seam"],
					compilerSettings: isolation.callingModuleSettings,
				),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["Seam"]?.generatedFiles == ["Seam.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Home {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let screenBuilder: __safeDI_ApiCarrier_Screen<__safeDI_Built>

		        public init(screenBuilder: __safeDI_ApiCarrier_Screen<__safeDI_Built>) {
		            self.screenBuilder = screenBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(screenBuilder: .init(__safeDI_noScope: __safeDI_builder))
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Screen<__safeDI_Built> {
		        public let api: (Int, Model) -> __safeDI_Built
		        public let detailBuilder: (Int, Model, any Api) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(api: @escaping (Int, Model) -> __safeDI_Built, detailBuilder: @escaping (Int, Model, any Api) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.api = api
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { _, _ in __safeDI_builder() }, detailBuilder: { _, _, _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Work<__safeDI_Built> {
		        public let detailBuilder: (Int, Model) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>

		        public init(detailBuilder: @escaping (Int, Model) -> __safeDI_ApiCarrier_Detail<__safeDI_Built>) {
		            self.detailBuilder = detailBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(detailBuilder: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Detail<__safeDI_Built> {
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
		        public let workBuilder: @Sendable () -> __safeDI_ApiCarrier_Work<__safeDI_Built>

		        public init(workBuilder: @escaping @Sendable () -> __safeDI_ApiCarrier_Work<__safeDI_Built>) {
		            self.workBuilder = workBuilder
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		            self.init(workBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>, __safeDI_apiSendableBuilder: __safeDI_ApiSendableCarrier<any Api>) {
		        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder
		        @inline(never) func __safeDI_detailBuilder(__safeDI_apiBuilder_detailBuilder: __safeDI_ApiCarrier_Detail<any Api>) -> Detail {
		            let api: any Api = __safeDI_apiBuilder_detailBuilder.api()
		            return Detail(api: api)
		        }
		        @inline(never) func __safeDI_screenBuilder(id: Int) -> Screen {
		            let model = Model(id: id)
		            let api: any Api = __safeDI_apiBuilder_screenBuilder.api(id, model)
		            let __safeDI_apiBuilder_detailBuilder = __safeDI_apiBuilder_screenBuilder.detailBuilder(id, model, api)
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(__safeDI_apiBuilder_detailBuilder: __safeDI_apiBuilder_detailBuilder)
		            }
		            return Screen(id: id, model: model, api: api, detailBuilder: detailBuilder)
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(id: $0)
		        }
		        @inline(never) @Sendable nonisolated func __safeDI_detailBuilder_(__safeDI_apiSendableBuilder_detailBuilder: __safeDI_ApiCarrier_Detail<any Api>) -> Detail {
		            let api: any Api = __safeDI_apiSendableBuilder_detailBuilder.api()
		            return Detail(api: api)
		        }
		        @inline(never) @Sendable nonisolated func __safeDI_workBuilder(id: Int) -> Work {
		            let __safeDI_apiSendableBuilder_workBuilder = __safeDI_apiSendableBuilder.workBuilder()
		            let model = Model(id: id)
		            let __safeDI_apiSendableBuilder_detailBuilder = __safeDI_apiSendableBuilder_workBuilder.detailBuilder(id, model)
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder_(__safeDI_apiSendableBuilder_detailBuilder: __safeDI_apiSendableBuilder_detailBuilder)
		            }
		            return Work(id: id, model: model, detailBuilder: detailBuilder)
		        }
		        let workBuilder = SendableInstantiator<Work> {
		            __safeDI_workBuilder(id: $0)
		        }
		        self.init(screenBuilder: screenBuilder, workBuilder: workBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_4F2020B42ED8EAF2 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public \(root == .structRoot ? "" : "convenience ")init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(screenBuilder: __safeDI_apiBuilder_Home_Screen_Scope())
		        }
		        func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.__safeDI_ApiCarrier_Screen<any Api> {
		            .init(
		                api: { scope_id, scope_model in
		                    let id = scope_id
		                    let model = scope_model
		                    let api: any Api = Impl(id: id, model: model)
		                    return api
		                },
		                detailBuilder: { values_id, values_model, values_api in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) }
		            )
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Detail_Scope(id: Int, model: Model) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = Impl(id: id, model: model)
		                return api
		            })
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.__safeDI_ApiSendableCarrier<any Api> {
		            .init(workBuilder: { __safeDI_apiBuilder_Home_Work_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Work_Scope() -> Home.__safeDI_ApiCarrier_Work<any Api> {
		            .init(detailBuilder: { values_id, values_model in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_4F2020B42ED8EAF2.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
	}

	// MARK: Cases

	/// The isolation each of the two modules' declarations default to: the main actor, or none.
	struct DefaultIsolationCase: CustomTestStringConvertible, Sendable {
		static let allCases = [
			DefaultIsolationCase(seamModuleIsMainActorByDefault: true, callingModuleIsMainActorByDefault: true),
			DefaultIsolationCase(seamModuleIsMainActorByDefault: true, callingModuleIsMainActorByDefault: false),
			DefaultIsolationCase(seamModuleIsMainActorByDefault: false, callingModuleIsMainActorByDefault: true),
			DefaultIsolationCase(seamModuleIsMainActorByDefault: false, callingModuleIsMainActorByDefault: false),
		]

		let seamModuleIsMainActorByDefault: Bool
		let callingModuleIsMainActorByDefault: Bool

		var seamModuleSettings: VerificationCompilerSettings {
			VerificationCompilerSettings(defaultIsolation: seamModuleIsMainActorByDefault ? "MainActor" : nil, prependsSafeDIImport: false)
		}

		var callingModuleSettings: VerificationCompilerSettings {
			VerificationCompilerSettings(defaultIsolation: callingModuleIsMainActorByDefault ? "MainActor" : nil, prependsSafeDIImport: false)
		}

		var testDescription: String {
			"Seam \(seamModuleIsMainActorByDefault ? "on the main actor" : "nonisolated") by default, App \(callingModuleIsMainActorByDefault ? "on the main actor" : "nonisolated") by default"
		}
	}

	/// The root that builds the seam: a struct, nonisolated, or a class on the main actor.
	enum RootKind: CaseIterable, CustomTestStringConvertible, Sendable {
		case structRoot
		case mainActorClassRoot

		var callerFixture: String {
			switch self {
			case .structRoot:
				SafeDIToolSeamCarrierIsolationTests.impl + """

				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(home: Home) { self.home = home }
				    @Instantiated let home: Home
				}
				"""
			case .mainActorClassRoot:
				SafeDIToolSeamCarrierIsolationTests.impl + """

				@MainActor
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(home: Home) { self.home = home }
				    @Instantiated let home: Home
				}
				"""
			}
		}

		var testDescription: String {
			switch self {
			case .structRoot: "a struct root"
			case .mainActorClassRoot: "a @MainActor class root"
			}
		}
	}

	// MARK: Fixtures

	/// `Screen` forwards `id` and binds a non-`Sendable` `Model` before its hole and before `Detail`, whose hole is filled
	/// reading both; `Work`, under a `SendableInstantiator`, binds a `Model` before its own `Detail`.
	/// `Api` is `nonisolated`, as `SafeDIToolSeamBuilderStructMatrixTests`' main-actor fixtures declare theirs: where
	/// this module defaults to the main actor, Swift 6.4 infers main-actor isolation for the fill's `Impl` from its
	/// conformance to an isolated `Api` ("call to main actor-isolated initializer … in a synchronous nonisolated
	/// context"), which Swift 6.2 does not.
	private static let seam = """
	import SafeDI

	nonisolated public protocol Api {}

	@Instantiable
	public final class Model: Instantiable {
	    public init(id: Int) { self.id = id }
	    @Received let id: Int
	}

	@Instantiable
	public final class Detail: Instantiable {
	    public init(api: any Api) { self.api = api }
	    @Instantiated let api: any Api
	}

	@Instantiable
	public final class Screen: Instantiable {
	    public init(id: Int, model: Model, api: any Api, detailBuilder: Instantiator<Detail>) {
	        self.id = id; self.model = model; self.api = api; self.detailBuilder = detailBuilder
	    }
	    @Forwarded let id: Int
	    @Instantiated let model: Model
	    @Instantiated let api: any Api
	    @Instantiated let detailBuilder: Instantiator<Detail>
	}

	@Instantiable
	public final class Work: Instantiable {
	    public init(id: Int, model: Model, detailBuilder: Instantiator<Detail>) {
	        self.id = id; self.model = model; self.detailBuilder = detailBuilder
	    }
	    @Forwarded let id: Int
	    @Instantiated let model: Model
	    @Instantiated let detailBuilder: Instantiator<Detail>
	}

	@Instantiable(generateDependencyTree: true)
	public final class Home: Instantiable {
	    public init(screenBuilder: Instantiator<Screen>, workBuilder: SendableInstantiator<Work>) {
	        self.screenBuilder = screenBuilder; self.workBuilder = workBuilder
	    }
	    @Instantiated let screenBuilder: Instantiator<Screen>
	    @Instantiated let workBuilder: SendableInstantiator<Work>
	}
	"""

	/// The fill of `Api`, which reads the level's `id` and `Model`.
	private static let impl = """
	import Seam
	import SafeDI

	@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
	public final class Impl: Api, Instantiable {
	    public init(id: Int, model: Model) { self.id = id; self.model = model }
	    @Received let id: Int
	    @Received let model: Model
	}
	"""

	private var filesToDelete: [URL]
}
