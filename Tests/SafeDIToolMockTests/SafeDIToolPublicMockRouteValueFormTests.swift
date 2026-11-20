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
/// does not provide it hands on `nil`, so its place is passed up there. Inline rejects the routes that pass the place
/// up, so no value is compared; each test compiles every module.
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
		// hands on its instance, and the root's case hands on `nil`, so that route passes the place up.
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
		                    self.model = { _ in .init(__safeDI_noScope: __safeDI_builder) }
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
		                    self.service = { _ in __safeDI_builder() }
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
		                self.desk = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.model = { _ in .init(__safeDI_noScope: __safeDI_builder) }
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
		            office: Office.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                office: office
		            )
		        }

		        var office: Office.SafeDIOverrides { __safeDI_storage.office }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                office: Office.SafeDIOverrides
		            ) {
		                self.office = office
		            }

		            let office: Office.SafeDIOverrides
		        }
		    }

		    static func mock(
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> OfficeScreen {
		        func __safeDI_office() -> Office {
		            func __safeDI_serviceBuilder_Office_Model_Scope_service(_ scope: Office.SafeDIMockScope_Service.Model_Scope.service_Values, token: Token) -> any Service {
		                let service: any Service = DefaultService(token: token)
		                return service
		            }
		            func __safeDI_serviceBuilder_Office(up: Office.SafeDIMockScope_Service.__safeDI_Builder<any Service>) -> Office.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(desk: { _ in __safeDI_serviceBuilder_Office_Desk_Scope() }, model: { values in __safeDI_serviceBuilder_Office_Model_Scope_(up: up.model(values)) })
		            }
		            func __safeDI_serviceBuilder_Office_Desk_Scope() -> Office.SafeDIMockScope_Service.Desk_Scope.__safeDI_Builder<any Service> {
		                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope(token: values.token) })
		            }
		            func __safeDI_serviceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token.instance) })
		            }
		            func __safeDI_serviceBuilder_Office_Model_Scope_(up: Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service>) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
		                .init(service: up.service)
		            }
		            _ = Office.__safeDI_Office_mock_533562D85E48F99D.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Office.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Office(up: .init(__safeDI_noScope: serviceBuilder)), safeDIOverrides: safeDIOverrides.office)
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
	mutating func generate_passesPlaceUpOnEveryRouteOfCalledMock_whenItsLevelHidesValueAndNoLevelOfCallerHoldsIt() async throws {
		// `Outer` fills `Inner`'s `service` with `DefaultService`, whose `gadget` `App` fills with `LiveGadget`, which reads
		// `id: Code`. `Outer` binds no `id` around `inner`, and `Inner`'s `Screen` forwards `id: String`, which hides any
		// farther `id` on the `screenBuilder` route: every route of `Inner`'s enum hands on `nil`, so the place inside the
		// fill is passed up there, and its case reads neither its payload nor `Inner`'s scope. `Holder` binds `id: Code`
		// before `direct`, so the same case of `DefaultService_Scope` is filled on that route.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"public protocol Service {}\npublic protocol Gadget {}",
					seamFixtureType(named: "Screen", declarations: ["@Forwarded public let id: String", "@Instantiated public let service: any Service"]),
					Self.publicMockType(named: "Inner", declarations: ["@Instantiated public let screenBuilder: Instantiator<Screen>", "@Instantiated public let service: any Service"]),
				]),
				ModuleFixture(name: "Middle", packageName: "Mid", swiftFileContent: [
					seamFixtureType(named: "Code", isFinalClass: true, declarations: []),
					Self.fulfillingType(named: "DefaultService", fulfilling: "Service", declarations: ["@Instantiated public let gadget: any Gadget"]),
					seamFixtureType(named: "Holder", declarations: ["@Instantiated public let id: Code", "@Instantiated public let direct: DefaultService"]),
					Self.publicMockType(named: "Outer", declarations: ["@Instantiated public let inner: Inner", "@Instantiated public let holder: Holder"]),
				].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
					Self.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: ["@Received public let id: Code"]),
					seamFixtureType(named: "Root", declarations: ["@Instantiated public let outer: Outer"])
						.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n"),
				].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Middle"]?.generatedFiles["Middle.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		#if DEBUG
		extension Outer {
		    nonisolated public enum SafeDIMockScope_Gadget {
		        nonisolated public struct inner_serviceBuilder_Values {}

		        nonisolated public struct holder_Values {
		            public let inner: Inner
		        }

		        nonisolated public enum DefaultService_Scope {
		            nonisolated public struct gadget_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let gadget: (gadget_Values) -> __safeDI_Built

		                public init(gadget: @escaping (gadget_Values) -> __safeDI_Built) {
		                    self.gadget = gadget
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.gadget = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        nonisolated public enum Holder_Scope {
		            nonisolated public struct direct_Values {
		                public let id: Code
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let direct: (direct_Values) -> SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>

		                public init(direct: @escaping (direct_Values) -> SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>) {
		                    self.direct = direct
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.direct = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let inner_serviceBuilder: (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>
		            public let holder: (holder_Values) -> SafeDIMockScope_Gadget.Holder_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(inner_serviceBuilder: @escaping (inner_serviceBuilder_Values) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<__safeDI_Built>>, holder: @escaping (holder_Values) -> SafeDIMockScope_Gadget.Holder_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.inner_serviceBuilder = inner_serviceBuilder
		                self.holder = holder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.inner_serviceBuilder = { _ in .init(__safeDI_noScope: { .init(__safeDI_noScope: __safeDI_builder) }) }
		                self.holder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            inner: Inner.SafeDIOverrides = .init(),
		            holder: __safeDI_Middle_Holder_MockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                inner: inner,
		                holder: holder
		            )
		        }

		        public var inner: Inner.SafeDIOverrides { __safeDI_storage.inner }
		        public var holder: __safeDI_Middle_Holder_MockConfiguration { __safeDI_storage.holder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                inner: Inner.SafeDIOverrides,
		                holder: __safeDI_Middle_Holder_MockConfiguration
		            ) {
		                self.inner = inner
		                self.holder = holder
		            }

		            let inner: Inner.SafeDIOverrides
		            let holder: __safeDI_Middle_Holder_MockConfiguration
		        }
		    }

		    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module’s SafeDI dependencies.
		    public static func mock(
		        gadgetBuilder: @escaping () -> any Gadget,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Outer {
		        Outer.__safeDI_mock(gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        gadgetBuilder __safeDI_gadgetBuilder: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Outer {
		        let __safeDI_gadgetBuilder_inner_serviceBuilder = __safeDI_gadgetBuilder.inner_serviceBuilder(SafeDIMockScope_Gadget.inner_serviceBuilder_Values())
		        func __safeDI_inner() -> Inner {
		            func __safeDI_serviceBuilder_Inner_service(_ scope: Inner.SafeDIMockScope_Service.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
		                func __safeDI_service() -> DefaultService {
		                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
		                    return DefaultService(gadget: gadget)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            func __safeDI_serviceBuilder_Inner_Screen_Scope_service(_ scope: Inner.SafeDIMockScope_Service.Screen_Scope.service_Values, __safeDI_inner_serviceBuilder: SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> any Service {
		                func __safeDI_service() -> DefaultService {
		                    let gadget: any Gadget = __safeDI_inner_serviceBuilder.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
		                    return DefaultService(gadget: gadget)
		                }
		                let service: any Service = __safeDI_service()
		                return service
		            }
		            func __safeDI_serviceBuilder_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(screenBuilder: { values in __safeDI_serviceBuilder_Inner_Screen_Scope(up: up.screenBuilder(values)) }, service: { scope in __safeDI_serviceBuilder_Inner_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
		            }
		            func __safeDI_serviceBuilder_Inner_Screen_Scope(up: Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Inner_Screen_Scope_service(scope, __safeDI_inner_serviceBuilder: up.service(scope)) })
		            }
		            _ = Inner.__safeDI_Inner_mock_718C21DDAD65EAF2.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Inner.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Inner(up: __safeDI_gadgetBuilder_inner_serviceBuilder), safeDIOverrides: safeDIOverrides.inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        let __safeDI_gadgetBuilder_holder = __safeDI_gadgetBuilder.holder(SafeDIMockScope_Gadget.holder_Values(inner: inner))
		        func __safeDI_holder() -> Holder {
		            let id = if let safeDIBuilder = safeDIOverrides.holder.id { safeDIBuilder() } else { Code() }
		            let __safeDI_gadgetBuilder_direct = __safeDI_gadgetBuilder_holder.direct(SafeDIMockScope_Gadget.Holder_Scope.direct_Values(id: id))
		            func __safeDI_direct() -> DefaultService {
		                let gadget: any Gadget = __safeDI_gadgetBuilder_direct.gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())
		                return if let safeDIBuilder = safeDIOverrides.holder.direct { safeDIBuilder(gadget) } else { DefaultService(gadget: gadget) }
		            }
		            let direct: DefaultService = __safeDI_direct()
		            return Holder.__safeDI_init(id: id, direct: direct, safeDIBuilder: safeDIOverrides.holder.safeDIBuilder)
		        }
		        let holder: Holder = __safeDI_holder()
		        return Outer(inner: inner, holder: holder)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_mock_B41DEA3313B1E564 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Holder` is constructed within the public mock trees of module `Middle`.
		nonisolated public struct __safeDI_Middle_Holder_MockConfiguration {
		    public init(
		        id: (() -> Code)? = nil,
		        direct: ((any Gadget) -> DefaultService)? = nil,
		        _ safeDIBuilder: ((Code, DefaultService) -> Holder)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            id: id,
		            direct: direct,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var id: (() -> Code)? { __safeDI_storage.id }
		    public var direct: ((any Gadget) -> DefaultService)? { __safeDI_storage.direct }
		    /// Overrides how `Holder` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((Code, DefaultService) -> Holder)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            id: (() -> Code)?,
		            direct: ((any Gadget) -> DefaultService)?,
		            safeDIBuilder: ((Code, DefaultService) -> Holder)?
		        ) {
		            self.id = id
		            self.direct = direct
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let id: (() -> Code)?
		        let direct: ((any Gadget) -> DefaultService)?
		        let safeDIBuilder: ((Code, DefaultService) -> Holder)?
		    }
		}

		extension Holder {
		    static func __safeDI_init(id: Code, direct: DefaultService, safeDIBuilder: ((Code, DefaultService) -> Holder)?) -> Holder {
		        if let safeDIBuilder { safeDIBuilder(id, direct) } else { Holder(id: id, direct: direct) }
		    }
		}
		#endif

		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
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
		            outer: Outer.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                outer: outer
		            )
		        }

		        var outer: Outer.SafeDIOverrides { __safeDI_storage.outer }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                outer: Outer.SafeDIOverrides
		            ) {
		                self.outer = outer
		            }

		            let outer: Outer.SafeDIOverrides
		        }
		    }

		    static func mock(
		        gadgetBuilder: @escaping () -> any Gadget,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_outer() -> Outer {
		            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope_gadget(_ scope: Outer.SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values, id: Code) -> any Gadget {
		                let gadget: any Gadget = LiveGadget(id: id)
		                return gadget
		            }
		            func __safeDI_gadgetBuilder_Outer(up: Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget>) -> Outer.SafeDIMockScope_Gadget.__safeDI_Builder<any Gadget> {
		                .init(inner_serviceBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner(up: up.inner_serviceBuilder(values)) }, holder: { _ in __safeDI_gadgetBuilder_Outer_Holder_Scope() })
		            }
		            func __safeDI_gadgetBuilder_Outer_Inner(up: Inner.SafeDIMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
		                .init(screenBuilder: { values in __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(up: up.screenBuilder(values)) }, service: { values in __safeDI_gadgetBuilder_Outer_DefaultService_Scope_(up: up.service(values)) })
		            }
		            func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(up: Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>>) -> Inner.SafeDIMockScope_Service.Screen_Scope.__safeDI_Builder<Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>> {
		                .init(service: { values in __safeDI_gadgetBuilder_Outer_DefaultService_Scope(up: up.service(values), id: values.id) })
		            }
		            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(up: Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>, id: String) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
		                .init(gadget: up.gadget)
		            }
		            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope_(up: Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget>) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
		                .init(gadget: up.gadget)
		            }
		            func __safeDI_gadgetBuilder_Outer_Holder_Scope() -> Outer.SafeDIMockScope_Gadget.Holder_Scope.__safeDI_Builder<any Gadget> {
		                .init(direct: { values in __safeDI_gadgetBuilder_Outer_DefaultService_Scope__(id: values.id) })
		            }
		            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope__(id: Code) -> Outer.SafeDIMockScope_Gadget.DefaultService_Scope.__safeDI_Builder<any Gadget> {
		                .init(gadget: { scope in __safeDI_gadgetBuilder_Outer_DefaultService_Scope_gadget(scope, id: id) })
		            }
		            _ = Outer.__safeDI_Outer_mock_B41DEA3313B1E564.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Outer.__safeDI_mock(gadgetBuilder: __safeDI_gadgetBuilder_Outer(up: .init(__safeDI_noScope: gadgetBuilder)), safeDIOverrides: safeDIOverrides.outer)
		        }
		        let outer: Outer = __safeDI_outer()
		        return Root(outer: outer)
		    }
		}
		#endif
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesPassUpParameterApartFromValue_whenFillReadsValueLabeledPassUp() async throws {
		// The fill `DefaultService` reads a value labeled `passUp`, which the level function of `Desk`’s level hands down
		// as its wrapper, beside the level function of `Office`’s root, which takes the caller’s struct as `up`.
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
		                    self.model = { _ in .init(__safeDI_noScope: __safeDI_builder) }
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
		                    self.service = { _ in __safeDI_builder() }
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
		                self.desk = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.model = { _ in .init(__safeDI_noScope: __safeDI_builder) }
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
		            office: Office.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                office: office
		            )
		        }

		        var office: Office.SafeDIOverrides { __safeDI_storage.office }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                office: Office.SafeDIOverrides
		            ) {
		                self.office = office
		            }

		            let office: Office.SafeDIOverrides
		        }
		    }

		    static func mock(
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> OfficeScreen {
		        func __safeDI_office() -> Office {
		            func __safeDI_serviceBuilder_Office_Model_Scope_service(_ scope: Office.SafeDIMockScope_Service.Model_Scope.service_Values, passUp: Token) -> any Service {
		                let service: any Service = DefaultService(passUp: passUp)
		                return service
		            }
		            func __safeDI_serviceBuilder_Office(up: Office.SafeDIMockScope_Service.__safeDI_Builder<any Service>) -> Office.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(desk: { _ in __safeDI_serviceBuilder_Office_Desk_Scope() }, model: { values in __safeDI_serviceBuilder_Office_Model_Scope_(up: up.model(values)) })
		            }
		            func __safeDI_serviceBuilder_Office_Desk_Scope() -> Office.SafeDIMockScope_Service.Desk_Scope.__safeDI_Builder<any Service> {
		                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope(passUp: values.passUp) })
		            }
		            func __safeDI_serviceBuilder_Office_Model_Scope(passUp: LazilyInstantiated<Token>) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, passUp: passUp.instance) })
		            }
		            func __safeDI_serviceBuilder_Office_Model_Scope_(up: Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service>) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
		                .init(service: up.service)
		            }
		            _ = Office.__safeDI_Office_mock_0BCE696681EAA0EC.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Office.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Office(up: .init(__safeDI_noScope: serviceBuilder)), safeDIOverrides: safeDIOverrides.office)
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
	mutating func generate_namesPassUpParameterApartFromValue_whenFillReadsValueLabeledUp() async throws {
		// The fill `DefaultService` reads a value labeled `up`, which the level function of `Desk`’s level hands down as its
		// wrapper, so the level function of `Office`’s root, which takes the caller’s struct, names that parameter `up_`.
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
		            office: Office.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                office: office
		            )
		        }

		        var office: Office.SafeDIOverrides { __safeDI_storage.office }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                office: Office.SafeDIOverrides
		            ) {
		                self.office = office
		            }

		            let office: Office.SafeDIOverrides
		        }
		    }

		    static func mock(
		        serviceBuilder: @escaping () -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> OfficeScreen {
		        func __safeDI_office() -> Office {
		            func __safeDI_serviceBuilder_Office_Model_Scope_service(_ scope: Office.SafeDIMockScope_Service.Model_Scope.service_Values, up: Token) -> any Service {
		                let service: any Service = DefaultService(up: up)
		                return service
		            }
		            func __safeDI_serviceBuilder_Office(up_: Office.SafeDIMockScope_Service.__safeDI_Builder<any Service>) -> Office.SafeDIMockScope_Service.__safeDI_Builder<any Service> {
		                .init(desk: { _ in __safeDI_serviceBuilder_Office_Desk_Scope() }, model: { values in __safeDI_serviceBuilder_Office_Model_Scope_(up_: up_.model(values)) })
		            }
		            func __safeDI_serviceBuilder_Office_Desk_Scope() -> Office.SafeDIMockScope_Service.Desk_Scope.__safeDI_Builder<any Service> {
		                .init(model: { values in __safeDI_serviceBuilder_Office_Model_Scope(up: values.up) })
		            }
		            func __safeDI_serviceBuilder_Office_Model_Scope(up: LazilyInstantiated<Token>) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceBuilder_Office_Model_Scope_service(scope, up: up.instance) })
		            }
		            func __safeDI_serviceBuilder_Office_Model_Scope_(up_: Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service>) -> Office.SafeDIMockScope_Service.Model_Scope.__safeDI_Builder<any Service> {
		                .init(service: up_.service)
		            }
		            _ = Office.__safeDI_Office_mock_30B1C276807B6ACB.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Office.__safeDI_mock(serviceBuilder: __safeDI_serviceBuilder_Office(up_: .init(__safeDI_noScope: serviceBuilder)), safeDIOverrides: safeDIOverrides.office)
		        }
		        let office: Office = __safeDI_office()
		        return OfficeScreen(office: office)
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
