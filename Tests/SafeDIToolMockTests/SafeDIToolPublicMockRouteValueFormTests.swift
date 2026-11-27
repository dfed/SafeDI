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

/// The form a public mock's caller hands a value on in, route by route: a route whose nearest type binds the value in a
/// form that provides the one the fill reads hands it on converted, and a route whose nearest level holds a form that
/// does not provide it hides the value, which the twin reports and so the calling mock reports too. Each test compiles
/// every module.
struct SafeDIToolPublicMockRouteValueFormTests: ~Copyable {
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
	mutating func generate_handsOnInstanceOfLazilyInstantiatedValue_whenRouteBindsValueLazilyAndFillReadsItByValue() async throws {
		// `Office` builds `Model` inside `Desk`, which binds `token` lazily before it, and beside `Desk`, where nothing binds
		// one. `DefaultService` reads `token: Token`, which `Desk`'s `LazilyInstantiated<Token>` provides: `Desk`'s dispatcher
		// hands on its instance, and the root's case hands on the `token` the calling mock builds, as inline does.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
					"""
					import SafeDI

					public protocol Service: Sendable {}

					@Instantiable
					public final class Token: Instantiable, Sendable {
					    public init() {}
					}

					@Instantiable
					public struct Model: Instantiable, Sendable {
					    public init(service: any Service) {
					        self.service = service
					    }

					    @Instantiated let service: any Service
					}

					@Instantiable
					public struct Desk: Instantiable {
					    public init(token: LazilyInstantiated<Token>, model: Model) {
					        self.token = token
					        self.model = model
					    }

					    @Instantiated let token: LazilyInstantiated<Token>
					    @Instantiated let model: Model
					}

					@Instantiable(generateMock: .public)
					public struct Office: Instantiable {
					    package init(desk: Desk, model: Model) {
					        self.desk = desk
					        self.model = model
					    }

					    @Instantiated let desk: Desk
					    @Instantiated let model: Model
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
					"""
					import Core
					import SafeDI

					@Instantiable(fulfillingAdditionalTypes: [Service.self])
					public struct DefaultService: Service, Instantiable {
					    public init(token: Token) {
					        self.token = token
					    }

					    @Received let token: Token
					}

					@Instantiable(generateMock: true)
					public struct OfficeScreen: Instantiable {
					    public init(office: Office) {
					        self.office = office
					    }

					    @Instantiated let office: Office
					}
					""",
				], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles["Core.swift"] == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Office {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct desk_Values {}

		        nonisolated public struct model_Values {
		            public let desk: Desk
		        }

		        nonisolated public enum Desk_Scope {
		            nonisolated public struct model_Values {
		                public let token: LazilyInstantiated<Token>
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let model: (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(model: @escaping (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.model = model
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(model: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Model_Scope {
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let desk: (desk_Values) -> SafeDIMockScope_Service.Desk_Scope.__safeDI_Builder<__safeDI_Built>
		            public let model: (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(desk: @escaping (desk_Values) -> SafeDIMockScope_Service.Desk_Scope.__safeDI_Builder<__safeDI_Built>, model: @escaping (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.desk = desk
		                self.model = model
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(desk: { _ in .init(__safeDI_noScope: __safeDI_builder) }, model: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            desk: __safeDI_Core_Desk_MockConfiguration = .init(),
		            model: ((any Service) -> Model)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                desk: desk,
		                model: model
		            )
		        }

		        public var desk: __safeDI_Core_Desk_MockConfiguration { __safeDI_storage.desk }
		        public var model: ((any Service) -> Model)? { __safeDI_storage.model }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                desk: __safeDI_Core_Desk_MockConfiguration,
		                model: ((any Service) -> Model)?
		            ) {
		                self.desk = desk
		                self.model = model
		            }

		            let desk: __safeDI_Core_Desk_MockConfiguration
		            let model: ((any Service) -> Model)?
		        }
		    }

		    public static func mock(
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Office {
		        Office.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        serviceBuilder __safeDI_serviceBuilder: Office.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Office {
		        let __safeDI_serviceBuilder_desk = __safeDI_serviceBuilder.desk(SafeDIMockScope_Service.desk_Values())
		        func __safeDI_desk() -> Desk {
		            func __safeDI_token() -> Token {
		                if let safeDIBuilder = safeDIOverrides.desk.token { safeDIBuilder() } else { Token() }
		            }
		            let token = LazilyInstantiated<Token>(__safeDI_token)
		            let __safeDI_serviceBuilder_model = __safeDI_serviceBuilder_desk.model(SafeDIMockScope_Service.Desk_Scope.model_Values(token: token))
		            func __safeDI_model() -> Model {
		                let service: any Service = __safeDI_serviceBuilder_model.service(SafeDIMockScope_Service.Model_Scope.service_Values())
		                return if let safeDIBuilder = safeDIOverrides.desk.model { safeDIBuilder(service) } else { Model(service: service) }
		            }
		            let model: Model = __safeDI_model()
		            return Desk.__safeDI_init(token: token, model: model, safeDIBuilder: safeDIOverrides.desk.safeDIBuilder)
		        }
		        let desk: Desk = __safeDI_desk()
		        let __safeDI_serviceBuilder_model = __safeDI_serviceBuilder.model(SafeDIMockScope_Service.model_Values(desk: desk))
		        func __safeDI_model() -> Model {
		            let service: any Service = __safeDI_serviceBuilder_model.service(SafeDIMockScope_Service.Model_Scope.service_Values())
		            return if let safeDIBuilder = safeDIOverrides.model { safeDIBuilder(service) } else { Model(service: service) }
		        }
		        let model: Model = __safeDI_model()
		        return Office(desk: desk, model: model)
		    }
		}

		extension Office {
		    public enum __safeDI_Office_mock_533562D85E48F99D {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Desk` is constructed within the public mock trees of module `Core`.
		nonisolated public struct __safeDI_Core_Desk_MockConfiguration {
		    public init(
		        token: (() -> Token)? = nil,
		        model: ((any Service) -> Model)? = nil,
		        _ safeDIBuilder: ((LazilyInstantiated<Token>, Model) -> Desk)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            token: token,
		            model: model,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var token: (() -> Token)? { __safeDI_storage.token }
		    public var model: ((any Service) -> Model)? { __safeDI_storage.model }
		    /// Overrides how `Desk` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((LazilyInstantiated<Token>, Model) -> Desk)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            token: (() -> Token)?,
		            model: ((any Service) -> Model)?,
		            safeDIBuilder: ((LazilyInstantiated<Token>, Model) -> Desk)?
		        ) {
		            self.token = token
		            self.model = model
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let token: (() -> Token)?
		        let model: ((any Service) -> Model)?
		        let safeDIBuilder: ((LazilyInstantiated<Token>, Model) -> Desk)?
		    }
		}

		extension Desk {
		    static func __safeDI_init(token: LazilyInstantiated<Token>, model: Model, safeDIBuilder: ((LazilyInstantiated<Token>, Model) -> Desk)?) -> Desk {
		        if let safeDIBuilder { safeDIBuilder(token, model) } else { Desk(token: token, model: model) }
		    }
		}
		#endif

		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension OfficeScreen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            token: (() -> Token)? = nil,
		            office: Office.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token,
		                office: office
		            )
		        }

		        var token: (() -> Token)? { __safeDI_storage.token }
		        var office: Office.SafeDIOverrides { __safeDI_storage.office }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Token)?,
		                office: Office.SafeDIOverrides
		            ) {
		                self.token = token
		                self.office = office
		            }

		            let token: (() -> Token)?
		            let office: Office.SafeDIOverrides
		        }
		    }

		    static func mock(
		        serviceBuilder: (() -> any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> OfficeScreen {
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Token() }
		        func __safeDI_office() -> Office {
		            func __safeDI_serviceBuilder_Office_Model_Scope_service(_ scope: Office.SafeDIMockScope_Service.Model_Scope.service_Values, token: Token) -> any Service {
		                let service: any Service = DefaultService(token: token)
		                return service
		            }
		            func __safeDI_serviceBuilder_Office(token: Token) -> Office.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(desk: { _ in __safeDI_serviceBuilder_Office_Desk_Scope() }, model: { _ in __safeDI_serviceBuilder_Office_Model_Scope_(token: token) })
		            }
		            func __safeDI_serviceBuilder_Office_Desk_Scope() -> Office.SafeDIMockScope_Service.Desk_Scope.__safeDI_Builder<any Service> {
		                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope(token: values.token) })
		            }
		            func __safeDI_serviceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token.instance) })
		            }
		            func __safeDI_serviceBuilder_Office_Model_Scope_(token: Token) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token) })
		            }
		            _ = Office.__safeDI_Office_mock_533562D85E48F99D.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Office.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Office(token: token), safeDIOverrides: safeDIOverrides.office)
		        }
		        let office: Office = __safeDI_office()
		        return OfficeScreen(office: office)
		    }
		}
		#endif
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTwinsHiddenReceiveError_whenCalledMocksLevelHidesValueNoLevelOfCallerHolds() async {
		// `Outer` fills `Inner`'s `service` with `DefaultService`, whose `gadget` `App` fills with `LiveGadget`, which reads
		// `id: Code`. `Outer` binds no `id` around `inner`, and `Inner`'s `Screen` forwards `id: String`, which hides any
		// farther `id` on the `screenBuilder` route. `Holder` binds `id: Code` before `direct`, so the same case of
		// `DefaultService_Scope` is reached on a route that holds it too. The twin reports the receive hidden, so the calling
		// mock reports the same.
		let modules = { (form: (String) -> String) in
			[
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"public protocol Service {}\npublic protocol Gadget {}",
					seamFixtureType(named: "Screen", declarations: ["@Forwarded public let id: String", "@Instantiated public let service: any Service"]),
					Self.publicMockType(named: "Inner", declarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>", "@Instantiated public let service: any Service"]),
				].map(form)),
				ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: [
					seamFixtureType(named: "Code", isFinalClass: true, declarations: []),
					Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
					seamFixtureType(named: "Holder", declarations: ["@Instantiated public let id: Code", "@Instantiated public let direct: DefaultService"]),
					Self.publicMockType(named: "Outer", declarations: ["@Instantiated public let inner: Inner", "@Instantiated public let holder: Holder"]),
				].map { form("import Feature\n\n" + $0) }, dependencies: ["Feature"]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
					Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let id: Code"]),
					seamFixtureType(named: "Root", declarations: ["@Instantiated public let outer: Outer"])
						.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n"),
				].map { form("import Feature\nimport Middle\n\n" + $0) }, dependencies: ["Feature", "Middle"]),
			]
		}
		let diagnostics = { (fixtures: [String: FixturePaths]) in
			"""
			\(fixtures["App"]!["LiveGadget.swift"]):10:5: error: @Received property `id: Code` is hidden in chain: Root -> Outer -> Inner -> Instantiator<Screen> -> any Service -> LiveGadget. `Screen` declares `id: String` with the same label, so the types below `Screen` receive `id: String` instead. Give `id: String` on `Screen` a different label to fix.
			\(fixtures["Feature"]!["Screen.swift"]):8:5: note: `id: String` is declared here
			"""
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: modules { $0 }, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: modules(callingMockProductionTwin(of:)), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsValueUnderItsLabel_whenFillReadsValueLabeledPassUp() async throws {
		// The fill `DefaultService` reads a value labeled `passUp`, the name a dispatcher takes its pass-up closure under,
		// which the level function of `Desk`’s level hands down as its wrapper, and `Office`’s root level function takes from
		// the caller. Every route fills the place, so no closure takes the name.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
					"""
					import SafeDI

					public protocol Service: Sendable {}

					@Instantiable
					public final class Token: Instantiable, Sendable {
					    public init() {}
					}

					@Instantiable
					public struct Model: Instantiable, Sendable {
					    public init(service: any Service) {
					        self.service = service
					    }

					    @Instantiated let service: any Service
					}

					@Instantiable
					public struct Desk: Instantiable {
					    public init(passUp: LazilyInstantiated<Token>, model: Model) {
					        self.passUp = passUp
					        self.model = model
					    }

					    @Instantiated let passUp: LazilyInstantiated<Token>
					    @Instantiated let model: Model
					}

					@Instantiable(generateMock: .public)
					public struct Office: Instantiable {
					    package init(desk: Desk, model: Model) {
					        self.desk = desk
					        self.model = model
					    }

					    @Instantiated let desk: Desk
					    @Instantiated let model: Model
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
					"""
					import Core
					import SafeDI

					@Instantiable(fulfillingAdditionalTypes: [Service.self])
					public struct DefaultService: Service, Instantiable {
					    public init(passUp: Token) {
					        self.passUp = passUp
					    }

					    @Received let passUp: Token
					}

					@Instantiable(generateMock: true)
					public struct OfficeScreen: Instantiable {
					    public init(office: Office) {
					        self.office = office
					    }

					    @Instantiated let office: Office
					}
					""",
				], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Core"]?.generatedFiles["Core.swift"] == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Office {
		    nonisolated public enum SafeDIMockScope_Service {
		        nonisolated public struct desk_Values {}

		        nonisolated public struct model_Values {
		            public let desk: Desk
		        }

		        nonisolated public enum Desk_Scope {
		            nonisolated public struct model_Values {
		                public let passUp: LazilyInstantiated<Token>
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let model: (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(model: @escaping (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.model = model
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.init(model: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		                }
		            }
		        }

		        nonisolated public enum Model_Scope {
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let desk: (desk_Values) -> SafeDIMockScope_Service.Desk_Scope.__safeDI_Builder<__safeDI_Built>
		            public let model: (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(desk: @escaping (desk_Values) -> SafeDIMockScope_Service.Desk_Scope.__safeDI_Builder<__safeDI_Built>, model: @escaping (model_Values) -> SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.desk = desk
		                self.model = model
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(desk: { _ in .init(__safeDI_noScope: __safeDI_builder) }, model: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            desk: __safeDI_Core_Desk_MockConfiguration = .init(),
		            model: ((any Service) -> Model)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                desk: desk,
		                model: model
		            )
		        }

		        public var desk: __safeDI_Core_Desk_MockConfiguration { __safeDI_storage.desk }
		        public var model: ((any Service) -> Model)? { __safeDI_storage.model }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                desk: __safeDI_Core_Desk_MockConfiguration,
		                model: ((any Service) -> Model)?
		            ) {
		                self.desk = desk
		                self.model = model
		            }

		            let desk: __safeDI_Core_Desk_MockConfiguration
		            let model: ((any Service) -> Model)?
		        }
		    }

		    public static func mock(
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Office {
		        Office.__safeDI_mock(serviceBuilder: .init(__safeDI_noScope: serviceBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        serviceBuilder __safeDI_serviceBuilder: Office.SafeDIMockScope_Service.__safeDI_Builder<any Service>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Office {
		        let __safeDI_serviceBuilder_desk = __safeDI_serviceBuilder.desk(SafeDIMockScope_Service.desk_Values())
		        func __safeDI_desk() -> Desk {
		            func __safeDI_passUp() -> Token {
		                if let safeDIBuilder = safeDIOverrides.desk.passUp { safeDIBuilder() } else { Token() }
		            }
		            let passUp = LazilyInstantiated<Token>(__safeDI_passUp)
		            let __safeDI_serviceBuilder_model = __safeDI_serviceBuilder_desk.model(SafeDIMockScope_Service.Desk_Scope.model_Values(passUp: passUp))
		            func __safeDI_model() -> Model {
		                let service: any Service = __safeDI_serviceBuilder_model.service(SafeDIMockScope_Service.Model_Scope.service_Values())
		                return if let safeDIBuilder = safeDIOverrides.desk.model { safeDIBuilder(service) } else { Model(service: service) }
		            }
		            let model: Model = __safeDI_model()
		            return Desk.__safeDI_init(passUp: passUp, model: model, safeDIBuilder: safeDIOverrides.desk.safeDIBuilder)
		        }
		        let desk: Desk = __safeDI_desk()
		        let __safeDI_serviceBuilder_model = __safeDI_serviceBuilder.model(SafeDIMockScope_Service.model_Values(desk: desk))
		        func __safeDI_model() -> Model {
		            let service: any Service = __safeDI_serviceBuilder_model.service(SafeDIMockScope_Service.Model_Scope.service_Values())
		            return if let safeDIBuilder = safeDIOverrides.model { safeDIBuilder(service) } else { Model(service: service) }
		        }
		        let model: Model = __safeDI_model()
		        return Office(desk: desk, model: model)
		    }
		}

		extension Office {
		    public enum __safeDI_Office_mock_0BCE696681EAA0EC {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Desk` is constructed within the public mock trees of module `Core`.
		nonisolated public struct __safeDI_Core_Desk_MockConfiguration {
		    public init(
		        passUp: (() -> Token)? = nil,
		        model: ((any Service) -> Model)? = nil,
		        _ safeDIBuilder: ((LazilyInstantiated<Token>, Model) -> Desk)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            passUp: passUp,
		            model: model,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var passUp: (() -> Token)? { __safeDI_storage.passUp }
		    public var model: ((any Service) -> Model)? { __safeDI_storage.model }
		    /// Overrides how `Desk` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((LazilyInstantiated<Token>, Model) -> Desk)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            passUp: (() -> Token)?,
		            model: ((any Service) -> Model)?,
		            safeDIBuilder: ((LazilyInstantiated<Token>, Model) -> Desk)?
		        ) {
		            self.passUp = passUp
		            self.model = model
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let passUp: (() -> Token)?
		        let model: ((any Service) -> Model)?
		        let safeDIBuilder: ((LazilyInstantiated<Token>, Model) -> Desk)?
		    }
		}

		extension Desk {
		    static func __safeDI_init(passUp: LazilyInstantiated<Token>, model: Model, safeDIBuilder: ((LazilyInstantiated<Token>, Model) -> Desk)?) -> Desk {
		        if let safeDIBuilder { safeDIBuilder(passUp, model) } else { Desk(passUp: passUp, model: model) }
		    }
		}
		#endif

		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension OfficeScreen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            passUp: (() -> Token)? = nil,
		            office: Office.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                passUp: passUp,
		                office: office
		            )
		        }

		        var passUp: (() -> Token)? { __safeDI_storage.passUp }
		        var office: Office.SafeDIOverrides { __safeDI_storage.office }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                passUp: (() -> Token)?,
		                office: Office.SafeDIOverrides
		            ) {
		                self.passUp = passUp
		                self.office = office
		            }

		            let passUp: (() -> Token)?
		            let office: Office.SafeDIOverrides
		        }
		    }

		    static func mock(
		        serviceBuilder: (() -> any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> OfficeScreen {
		        let passUp = if let safeDIBuilder = safeDIOverrides.passUp { safeDIBuilder() } else { Token() }
		        func __safeDI_office() -> Office {
		            func __safeDI_serviceBuilder_Office_Model_Scope_service(_ scope: Office.SafeDIMockScope_Service.Model_Scope.service_Values, passUp: Token) -> any Service {
		                let service: any Service = DefaultService(passUp: passUp)
		                return service
		            }
		            func __safeDI_serviceBuilder_Office(passUp: Token) -> Office.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(desk: { _ in __safeDI_serviceBuilder_Office_Desk_Scope() }, model: { _ in __safeDI_serviceBuilder_Office_Model_Scope_(passUp: passUp) })
		            }
		            func __safeDI_serviceBuilder_Office_Desk_Scope() -> Office.SafeDIMockScope_Service.Desk_Scope.__safeDI_Builder<any Service> {
		                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope(passUp: values.passUp) })
		            }
		            func __safeDI_serviceBuilder_Office_Model_Scope(passUp: LazilyInstantiated<Token>) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, passUp: passUp.instance) })
		            }
		            func __safeDI_serviceBuilder_Office_Model_Scope_(passUp: Token) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, passUp: passUp) })
		            }
		            _ = Office.__safeDI_Office_mock_0BCE696681EAA0EC.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Office.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Office(passUp: passUp), safeDIOverrides: safeDIOverrides.office)
		        }
		        let office: Office = __safeDI_office()
		        return OfficeScreen(office: office)
		    }
		}
		#endif
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsValueUnderItsLabel_whenFillReadsValueLabeledUp() async throws {
		// The fill `DefaultService` reads a value labeled `up`, the name a level function takes the caller’s struct under,
		// which the level function of `Desk`’s level hands down as its wrapper, and `Office`’s root level function takes from
		// the caller. Every route fills the place, so no level function takes the caller’s struct.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
					"""
					import SafeDI

					public protocol Service: Sendable {}

					@Instantiable
					public final class Token: Instantiable, Sendable {
					    public init() {}
					}

					@Instantiable
					public struct Model: Instantiable, Sendable {
					    public init(service: any Service) {
					        self.service = service
					    }

					    @Instantiated let service: any Service
					}

					@Instantiable
					public struct Desk: Instantiable {
					    public init(up: LazilyInstantiated<Token>, model: Model) {
					        self.up = up
					        self.model = model
					    }

					    @Instantiated let up: LazilyInstantiated<Token>
					    @Instantiated let model: Model
					}

					@Instantiable(generateMock: .public)
					public struct Office: Instantiable {
					    package init(desk: Desk, model: Model) {
					        self.desk = desk
					        self.model = model
					    }

					    @Instantiated let desk: Desk
					    @Instantiated let model: Model
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
					"""
					import Core
					import SafeDI

					@Instantiable(fulfillingAdditionalTypes: [Service.self])
					public struct DefaultService: Service, Instantiable {
					    public init(up: Token) {
					        self.up = up
					    }

					    @Received let up: Token
					}

					@Instantiable(generateMock: true)
					public struct OfficeScreen: Instantiable {
					    public init(office: Office) {
					        self.office = office
					    }

					    @Instantiated let office: Office
					}
					""",
				], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension OfficeScreen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            up: (() -> Token)? = nil,
		            office: Office.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                up: up,
		                office: office
		            )
		        }

		        var up: (() -> Token)? { __safeDI_storage.up }
		        var office: Office.SafeDIOverrides { __safeDI_storage.office }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                up: (() -> Token)?,
		                office: Office.SafeDIOverrides
		            ) {
		                self.up = up
		                self.office = office
		            }

		            let up: (() -> Token)?
		            let office: Office.SafeDIOverrides
		        }
		    }

		    static func mock(
		        serviceBuilder: (() -> any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> OfficeScreen {
		        let up = if let safeDIBuilder = safeDIOverrides.up { safeDIBuilder() } else { Token() }
		        func __safeDI_office() -> Office {
		            func __safeDI_serviceBuilder_Office_Model_Scope_service(_ scope: Office.SafeDIMockScope_Service.Model_Scope.service_Values, up: Token) -> any Service {
		                let service: any Service = DefaultService(up: up)
		                return service
		            }
		            func __safeDI_serviceBuilder_Office(up: Token) -> Office.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(desk: { _ in __safeDI_serviceBuilder_Office_Desk_Scope() }, model: { _ in __safeDI_serviceBuilder_Office_Model_Scope_(up: up) })
		            }
		            func __safeDI_serviceBuilder_Office_Desk_Scope() -> Office.SafeDIMockScope_Service.Desk_Scope.__safeDI_Builder<any Service> {
		                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope(up: values.up) })
		            }
		            func __safeDI_serviceBuilder_Office_Model_Scope(up: LazilyInstantiated<Token>) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, up: up.instance) })
		            }
		            func __safeDI_serviceBuilder_Office_Model_Scope_(up: Token) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, up: up) })
		            }
		            _ = Office.__safeDI_Office_mock_30B1C276807B6ACB.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Office.__safeDI_mock(serviceBuilder: serviceBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_serviceBuilder_Office(up: up), safeDIOverrides: safeDIOverrides.office)
		        }
		        let office: Office = __safeDI_office()
		        return OfficeScreen(office: office)
		    }
		}
		#endif
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceWithCallersLazyValue_whenCalledMockBindsValueByValueBelowItsRoot() async throws {
		// `F`’s mock binds `log` by value, from the `log.instance` the calling mock hands it, and its place `api` is a level
		// below its root, beneath `A`. `Live` fills that place and reads `log: LazilyInstantiated<Log>`, which the caller
		// holds. `F`’s copy is the caller’s own value, so the fill reads the caller’s wrapper, as the twin’s fill does, no
		// level function takes it, and the calling mock passes no builder up.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feat", packageName: "feat", swiftFileContent: [
					"""
					import SafeDI

					public protocol Api {}

					@Instantiable
					public final class Log: Instantiable {
					    public init() {}
					}

					@Instantiable
					public final class A: Instantiable {
					    init(api: any Api) {
					        self.api = api
					    }

					    @Instantiated public let api: any Api
					}

					@Instantiable
					public final class Z: Instantiable {
					    init(log: Log) {
					        self.log = log
					    }

					    @Received public let log: Log
					}

					@Instantiable(generateDependencyTree: true, generateMock: .public)
					public final class F: Instantiable {
					    public init(a: A, z: Z) {
					        self.a = a
					        self.z = z
					    }

					    @Instantiated public let a: A
					    @Instantiated public let z: Z
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
					"""
					import Feat
					import SafeDI

					@Instantiable(fulfillingAdditionalTypes: [Api.self])
					public final class Live: Api, Instantiable {
					    public init(log: LazilyInstantiated<Log>) {
					        self.log = log
					    }

					    @Received public let log: LazilyInstantiated<Log>
					}

					@Instantiable(isRoot: true, generateMock: true)
					public final class Root: Instantiable {
					    public init(log: LazilyInstantiated<Log>, f: F) {
					        self.log = log
					        self.f = f
					    }

					    @Instantiated let log: LazilyInstantiated<Log>
					    @Instantiated let f: F
					}
					""",
				], dependencies: ["Feat"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feat"]?.generatedFiles["Feat.swift"] == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension F {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let a: (LazilyInstantiated<Log>, Z) -> __safeDI_ApiCarrier_A<__safeDI_Built>

		        public init(a: @escaping (LazilyInstantiated<Log>, Z) -> __safeDI_ApiCarrier_A<__safeDI_Built>) {
		            self.a = a
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_A<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_log: @autoclosure @escaping () -> Log, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let log = LazilyInstantiated<Log>(__safeDI_log)
		        let z = Z(log: log.instance)
		        let __safeDI_apiBuilder_a = __safeDI_apiBuilder.a(log, z)
		        @inline(never) func __safeDI_a() -> A {
		            let api: any Api = __safeDI_apiBuilder_a.api()
		            return A(api: api)
		        }
		        let a: A = __safeDI_a()
		        self.init(a: a, z: z)
		    }
		}

		extension F {
		    public enum __safeDI_F_3674AAE4F944CA7B {}
		}

		#if DEBUG
		extension F {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct a_Values {
		            public let log: Log
		            public let z: Z
		        }

		        nonisolated public enum A_Scope {
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let a: (a_Values) -> SafeDIMockScope_Api.A_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(a: @escaping (a_Values) -> SafeDIMockScope_Api.A_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.a = a
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(a: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            a: ((any Api) -> A)? = nil,
		            log: (() -> Log)? = nil,
		            z: ((Log) -> Z)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                a: a,
		                log: log,
		                z: z
		            )
		        }

		        public var a: ((any Api) -> A)? { __safeDI_storage.a }
		        public var log: (() -> Log)? { __safeDI_storage.log }
		        public var z: ((Log) -> Z)? { __safeDI_storage.z }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                a: ((any Api) -> A)?,
		                log: (() -> Log)?,
		                z: ((Log) -> Z)?
		            ) {
		                self.a = a
		                self.log = log
		                self.z = z
		            }

		            let a: ((any Api) -> A)?
		            let log: (() -> Log)?
		            let z: ((Log) -> Z)?
		        }
		    }

		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        log: Log? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> F {
		        F.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), log: log, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: F.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        log: Log? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> F {
		        let log = if let log { log } else if let safeDIBuilder = safeDIOverrides.log { safeDIBuilder() } else { Log() }
		        let z = if let safeDIBuilder = safeDIOverrides.z { safeDIBuilder(log) } else { Z(log: log) }
		        let __safeDI_apiBuilder_a = __safeDI_apiBuilder.a(SafeDIMockScope_Api.a_Values(log: log, z: z))
		        func __safeDI_a() -> A {
		            let api: any Api = __safeDI_apiBuilder_a.api(SafeDIMockScope_Api.A_Scope.api_Values())
		            return if let safeDIBuilder = safeDIOverrides.a { safeDIBuilder(api) } else { A(api: api) }
		        }
		        let a: A = __safeDI_a()
		        return F(a: a, z: z)
		    }
		}

		extension F {
		    public enum __safeDI_F_mock_96D996AD6269EFC2 {}
		}
		#endif
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_log() -> Log {
		            Log()
		        }
		        let log = LazilyInstantiated<Log>(__safeDI_log)
		        func __safeDI_f() -> F {
		            _ = F.__safeDI_F_3674AAE4F944CA7B.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_F() -> F.__safeDI_ApiCarrier<any Api> {
		                .init(a: { values_log, values_z in __safeDI_apiBuilder_F_A_Scope() })
		            }
		            func __safeDI_apiBuilder_F_A_Scope() -> F.__safeDI_ApiCarrier_A<any Api> {
		                .init(api: {
		                    let api: any Api = Live(log: log)
		                    return api
		                })
		            }
		            return F(__safeDI_log: log.instance, __safeDI_apiBuilder: __safeDI_apiBuilder_F())
		        }
		        let f: F = __safeDI_f()
		        self.init(log: log, f: f)
		    }
		}

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            log: (() -> Log)? = nil,
		            f: F.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                log: log,
		                f: f
		            )
		        }

		        var log: (() -> Log)? { __safeDI_storage.log }
		        var f: F.SafeDIOverrides { __safeDI_storage.f }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                log: (() -> Log)?,
		                f: F.SafeDIOverrides
		            ) {
		                self.log = log
		                self.f = f
		            }

		            let log: (() -> Log)?
		            let f: F.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_log() -> Log {
		            if let safeDIBuilder = safeDIOverrides.log { safeDIBuilder() } else { Log() }
		        }
		        let log = LazilyInstantiated<Log>(__safeDI_log)
		        func __safeDI_f() -> F {
		            func __safeDI_apiBuilder_F() -> F.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(a: { _ in __safeDI_apiBuilder_F_A_Scope() })
		            }
		            func __safeDI_apiBuilder_F_A_Scope() -> F.SafeDIMockScope_Api.A_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = Live(log: log)
		                    return api
		                })
		            }
		            _ = F.__safeDI_F_mock_96D996AD6269EFC2.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_F(), log: log.instance, safeDIOverrides: safeDIOverrides.f)
		        }
		        let f: F = __safeDI_f()
		        return Root(log: log, f: f)
		    }
		}
		#endif
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillsPlaceWithCallersValue_whenFillReadsValueByValueCalledMockBindsBelowItsRoot() async throws {
		// As above, with `Root` and `Live` holding `log` by value: the fill reads the caller’s `log`, as the twin’s fill
		// does, and no level function takes it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feat", packageName: "feat", swiftFileContent: [
					"""
					import SafeDI

					public protocol Api {}

					@Instantiable
					public final class Log: Instantiable {
					    public init() {}
					}

					@Instantiable
					public final class A: Instantiable {
					    init(api: any Api) {
					        self.api = api
					    }

					    @Instantiated public let api: any Api
					}

					@Instantiable
					public final class Z: Instantiable {
					    init(log: Log) {
					        self.log = log
					    }

					    @Received public let log: Log
					}

					@Instantiable(generateDependencyTree: true, generateMock: .public)
					public final class F: Instantiable {
					    public init(a: A, z: Z) {
					        self.a = a
					        self.z = z
					    }

					    @Instantiated public let a: A
					    @Instantiated public let z: Z
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
					"""
					import Feat
					import SafeDI

					@Instantiable(fulfillingAdditionalTypes: [Api.self])
					public final class Live: Api, Instantiable {
					    public init(log: Log) {
					        self.log = log
					    }

					    @Received public let log: Log
					}

					@Instantiable(isRoot: true, generateMock: true)
					public final class Root: Instantiable {
					    public init(log: Log, f: F) {
					        self.log = log
					        self.f = f
					    }

					    @Instantiated let log: Log
					    @Instantiated let f: F
					}
					""",
				], dependencies: ["Feat"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feat"]?.generatedFiles["Feat.swift"] == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension F {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let a: (LazilyInstantiated<Log>, Z) -> __safeDI_ApiCarrier_A<__safeDI_Built>

		        public init(a: @escaping (LazilyInstantiated<Log>, Z) -> __safeDI_ApiCarrier_A<__safeDI_Built>) {
		            self.a = a
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_A<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_log: @autoclosure @escaping () -> Log, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let log = LazilyInstantiated<Log>(__safeDI_log)
		        let z = Z(log: log.instance)
		        let __safeDI_apiBuilder_a = __safeDI_apiBuilder.a(log, z)
		        @inline(never) func __safeDI_a() -> A {
		            let api: any Api = __safeDI_apiBuilder_a.api()
		            return A(api: api)
		        }
		        let a: A = __safeDI_a()
		        self.init(a: a, z: z)
		    }
		}

		extension F {
		    public enum __safeDI_F_3674AAE4F944CA7B {}
		}

		#if DEBUG
		extension F {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct a_Values {
		            public let log: Log
		            public let z: Z
		        }

		        nonisolated public enum A_Scope {
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let a: (a_Values) -> SafeDIMockScope_Api.A_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(a: @escaping (a_Values) -> SafeDIMockScope_Api.A_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.a = a
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(a: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            a: ((any Api) -> A)? = nil,
		            log: (() -> Log)? = nil,
		            z: ((Log) -> Z)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                a: a,
		                log: log,
		                z: z
		            )
		        }

		        public var a: ((any Api) -> A)? { __safeDI_storage.a }
		        public var log: (() -> Log)? { __safeDI_storage.log }
		        public var z: ((Log) -> Z)? { __safeDI_storage.z }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                a: ((any Api) -> A)?,
		                log: (() -> Log)?,
		                z: ((Log) -> Z)?
		            ) {
		                self.a = a
		                self.log = log
		                self.z = z
		            }

		            let a: ((any Api) -> A)?
		            let log: (() -> Log)?
		            let z: ((Log) -> Z)?
		        }
		    }

		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        log: Log? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> F {
		        F.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), log: log, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: F.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        log: Log? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> F {
		        let log = if let log { log } else if let safeDIBuilder = safeDIOverrides.log { safeDIBuilder() } else { Log() }
		        let z = if let safeDIBuilder = safeDIOverrides.z { safeDIBuilder(log) } else { Z(log: log) }
		        let __safeDI_apiBuilder_a = __safeDI_apiBuilder.a(SafeDIMockScope_Api.a_Values(log: log, z: z))
		        func __safeDI_a() -> A {
		            let api: any Api = __safeDI_apiBuilder_a.api(SafeDIMockScope_Api.A_Scope.api_Values())
		            return if let safeDIBuilder = safeDIOverrides.a { safeDIBuilder(api) } else { A(api: api) }
		        }
		        let a: A = __safeDI_a()
		        return F(a: a, z: z)
		    }
		}

		extension F {
		    public enum __safeDI_F_mock_96D996AD6269EFC2 {}
		}
		#endif
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Root {
		    public convenience init() {
		        let log = Log()
		        func __safeDI_f() -> F {
		            _ = F.__safeDI_F_3674AAE4F944CA7B.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_F() -> F.__safeDI_ApiCarrier<any Api> {
		                .init(a: { values_log, values_z in __safeDI_apiBuilder_F_A_Scope() })
		            }
		            func __safeDI_apiBuilder_F_A_Scope() -> F.__safeDI_ApiCarrier_A<any Api> {
		                .init(api: {
		                    let api: any Api = Live(log: log)
		                    return api
		                })
		            }
		            return F(__safeDI_log: log, __safeDI_apiBuilder: __safeDI_apiBuilder_F())
		        }
		        let f: F = __safeDI_f()
		        self.init(log: log, f: f)
		    }
		}

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            log: (() -> Log)? = nil,
		            f: F.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                log: log,
		                f: f
		            )
		        }

		        var log: (() -> Log)? { __safeDI_storage.log }
		        var f: F.SafeDIOverrides { __safeDI_storage.f }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                log: (() -> Log)?,
		                f: F.SafeDIOverrides
		            ) {
		                self.log = log
		                self.f = f
		            }

		            let log: (() -> Log)?
		            let f: F.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let log = if let safeDIBuilder = safeDIOverrides.log { safeDIBuilder() } else { Log() }
		        func __safeDI_f() -> F {
		            func __safeDI_apiBuilder_F() -> F.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(a: { _ in __safeDI_apiBuilder_F_A_Scope() })
		            }
		            func __safeDI_apiBuilder_F_A_Scope() -> F.SafeDIMockScope_Api.A_Scope.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = Live(log: log)
		                    return api
		                })
		            }
		            _ = F.__safeDI_F_mock_96D996AD6269EFC2.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_F(), log: log, safeDIOverrides: safeDIOverrides.f)
		        }
		        let f: F = __safeDI_f()
		        return Root(log: log, f: f)
		    }
		}
		#endif
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesPlaceUpWhole_whenFillReadingCallersLazyValueBuildsCalledMockAgainBelowItsRoot() async throws {
		// `generate_fillsPlaceWithCallersLazyValue_whenCalledMockBindsValueByValueBelowItsRoot`, with `Live` also building
		// `F` again, so `F` is re-entered, and `Live` reads `Root`’s `LazilyInstantiated` beside its place’s fields, which `F`’s
		// mock binds by value: the calling mock passes the place up whole, and `mock()` takes its builder, where the twin
		// fills it (`DependencyTreeGenerator.holeTypesTheFillGatesPassUp(of:in:lazilyHeldValues:)`).
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feat", packageName: "feat", swiftFileContent: [
					"""
					import SafeDI

					public protocol Api {}

					@Instantiable
					public final class Log: Instantiable {
					    public init() {}
					}

					@Instantiable
					public final class A: Instantiable {
					    init(api: any Api) {
					        self.api = api
					    }

					    @Instantiated public let api: any Api
					}

					@Instantiable
					public final class Z: Instantiable {
					    init(log: Log) {
					        self.log = log
					    }

					    @Received public let log: Log
					}

					@Instantiable(generateDependencyTree: true, generateMock: .public)
					public final class F: Instantiable {
					    public init(a: A, z: Z) {
					        self.a = a
					        self.z = z
					    }

					    @Instantiated public let a: A
					    @Instantiated public let z: Z
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
					"""
					import Feat
					import SafeDI

					@Instantiable(fulfillingAdditionalTypes: [Api.self])
					public final class Live: Api, Instantiable {
					    public init(log: LazilyInstantiated<Log>, fBuilder: Instantiator<F>) {
					        self.log = log
					        self.fBuilder = fBuilder
					    }

					    @Received public let log: LazilyInstantiated<Log>
					    @Instantiated public let fBuilder: Instantiator<F>
					}

					@Instantiable(isRoot: true, generateMock: true)
					public final class Root: Instantiable {
					    public init(log: LazilyInstantiated<Log>, f: F) {
					        self.log = log
					        self.f = f
					    }

					    @Instantiated let log: LazilyInstantiated<Log>
					    @Instantiated let f: F
					}
					""",
				], dependencies: ["Feat"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feat"]?.generatedFiles["Feat.swift"] == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension F {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let a: (LazilyInstantiated<Log>, Z) -> __safeDI_ApiCarrier_A<__safeDI_Built>

		        public init(a: @escaping (LazilyInstantiated<Log>, Z) -> __safeDI_ApiCarrier_A<__safeDI_Built>) {
		            self.a = a
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_A<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_log: @autoclosure @escaping () -> Log, __safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let log = LazilyInstantiated<Log>(__safeDI_log)
		        let z = Z(log: log.instance)
		        let __safeDI_apiBuilder_a = __safeDI_apiBuilder.a(log, z)
		        @inline(never) func __safeDI_a() -> A {
		            let api: any Api = __safeDI_apiBuilder_a.api()
		            return A(api: api)
		        }
		        let a: A = __safeDI_a()
		        self.init(a: a, z: z)
		    }
		}

		extension F {
		    public enum __safeDI_F_3674AAE4F944CA7B {}
		}

		#if DEBUG
		extension F {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct a_Values {
		            public let log: Log
		            public let z: Z
		        }

		        nonisolated public enum A_Scope {
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

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let a: (a_Values) -> SafeDIMockScope_Api.A_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(a: @escaping (a_Values) -> SafeDIMockScope_Api.A_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.a = a
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.init(a: { _ in .init(__safeDI_noScope: __safeDI_builder) })
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            a: ((any Api) -> A)? = nil,
		            log: (() -> Log)? = nil,
		            z: ((Log) -> Z)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                a: a,
		                log: log,
		                z: z
		            )
		        }

		        public var a: ((any Api) -> A)? { __safeDI_storage.a }
		        public var log: (() -> Log)? { __safeDI_storage.log }
		        public var z: ((Log) -> Z)? { __safeDI_storage.z }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                a: ((any Api) -> A)?,
		                log: (() -> Log)?,
		                z: ((Log) -> Z)?
		            ) {
		                self.a = a
		                self.log = log
		                self.z = z
		            }

		            let a: ((any Api) -> A)?
		            let log: (() -> Log)?
		            let z: ((Log) -> Z)?
		        }
		    }

		    public static func mock(
		        apiBuilder: @escaping () -> any Api,
		        log: Log? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> F {
		        F.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), log: log, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: F.SafeDIMockScope_Api.__safeDI_Builder<any Api>,
		        log: Log? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> F {
		        let log = if let log { log } else if let safeDIBuilder = safeDIOverrides.log { safeDIBuilder() } else { Log() }
		        let z = if let safeDIBuilder = safeDIOverrides.z { safeDIBuilder(log) } else { Z(log: log) }
		        let __safeDI_apiBuilder_a = __safeDI_apiBuilder.a(SafeDIMockScope_Api.a_Values(log: log, z: z))
		        func __safeDI_a() -> A {
		            let api: any Api = __safeDI_apiBuilder_a.api(SafeDIMockScope_Api.A_Scope.api_Values())
		            return if let safeDIBuilder = safeDIOverrides.a { safeDIBuilder(api) } else { A(api: api) }
		        }
		        let a: A = __safeDI_a()
		        return F(a: a, z: z)
		    }
		}

		extension F {
		    public enum __safeDI_F_mock_96D996AD6269EFC2 {}
		}
		#endif
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_log() -> Log {
		            Log()
		        }
		        let log = LazilyInstantiated<Log>(__safeDI_log)
		        func __safeDI_f() -> F {
		            _ = F.__safeDI_F_3674AAE4F944CA7B.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_F_A_Scope_api() -> any Api {
		                func __safeDI_api() -> Live {
		                    func __safeDI_fBuilder() -> F {
		                        _ = F.__safeDI_F_3674AAE4F944CA7B.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                        return F(__safeDI_log: log.instance, __safeDI_apiBuilder: __safeDI_apiBuilder_F())
		                    }
		                    let fBuilder = Instantiator<F>(__safeDI_fBuilder)
		                    return Live(log: log, fBuilder: fBuilder)
		                }
		                let api: any Api = __safeDI_api()
		                return api
		            }
		            func __safeDI_apiBuilder_F() -> F.__safeDI_ApiCarrier<any Api> {
		                .init(a: { values_log, values_z in __safeDI_apiBuilder_F_A_Scope() })
		            }
		            func __safeDI_apiBuilder_F_A_Scope() -> F.__safeDI_ApiCarrier_A<any Api> {
		                .init(api: { __safeDI_apiBuilder_F_A_Scope_api() })
		            }
		            return F(__safeDI_log: log.instance, __safeDI_apiBuilder: __safeDI_apiBuilder_F())
		        }
		        let f: F = __safeDI_f()
		        self.init(log: log, f: f)
		    }
		}

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            log: (() -> Log)? = nil,
		            f: F.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                log: log,
		                f: f
		            )
		        }

		        var log: (() -> Log)? { __safeDI_storage.log }
		        var f: F.SafeDIOverrides { __safeDI_storage.f }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                log: (() -> Log)?,
		                f: F.SafeDIOverrides
		            ) {
		                self.log = log
		                self.f = f
		            }

		            let log: (() -> Log)?
		            let f: F.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_apiBuilder = apiBuilder
		        func __safeDI_log() -> Log {
		            if let safeDIBuilder = safeDIOverrides.log { safeDIBuilder() } else { Log() }
		        }
		        let log = LazilyInstantiated<Log>(__safeDI_log)
		        _ = F.__safeDI_F_mock_96D996AD6269EFC2.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        func __safeDI_f() -> F {
		            let apiBuilder: () -> any Api = __safeDI_apiBuilder
		            return F.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), log: log.instance, safeDIOverrides: safeDIOverrides.f)
		        }
		        let f: F = __safeDI_f()
		        return Root(log: log, f: f)
		    }
		}
		#endif
		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A public struct named `name` that generates a public mock, whose initializer is `package`: no module of another
	/// package can build it inline, so each calls its mock.
	private static func publicMockType(named name: String, declarations: [String]) -> String {
		seamFixtureType(named: name, declarations: declarations)
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: .public)\n")
			.replacingOccurrences(of: "    public init(", with: "    package init(")
	}

	private static func fulfillingType(named name: String, fulfilling fulfilledType: String, declarations: [String]) -> String {
		seamFixtureType(named: name, declarations: declarations, conformances: ", \(fulfilledType)")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [\(fulfilledType).self])\n")
	}
}
