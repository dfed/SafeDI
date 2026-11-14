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
		    @frozen public enum SafeDIMockScope_Service {
		        case desk(desk_Values, SafeDIMockScope_Service.Desk_Scope)
		        case model(model_Values, SafeDIMockScope_Service.Model_Scope)

		        public struct desk_Values {}

		        public struct model_Values {
		            public let desk: Desk
		        }

		        @frozen public enum Desk_Scope {
		            case model(model_Values, SafeDIMockScope_Service.Model_Scope)

		            public struct model_Values {
		                public let token: LazilyInstantiated<Token>
		            }
		        }

		        @frozen public enum Model_Scope {
		            case service(service_Values)

		            public struct service_Values {}
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            desk: __safeDI_Core_Desk_MockConfiguration = .init(),
		            model: ((any Service) -> Model)? = nil
		        ) {
		            self.desk = desk
		            self.model = model
		        }

		        public let desk: __safeDI_Core_Desk_MockConfiguration
		        public let model: ((any Service) -> Model)?
		    }

		    public static func mock(
		        serviceBuilder: @escaping (Office.SafeDIMockScope_Service) -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Office {
		        let __safeDI_serviceBuilder = serviceBuilder
		        let __safeDI_serviceValues_desk = SafeDIMockScope_Service.desk_Values()
		        func __safeDI_desk() -> Desk {
		            func __safeDI_token() -> Token {
		                if let safeDIBuilder = safeDIOverrides.desk.token { safeDIBuilder() } else { Token() }
		            }
		            let token = LazilyInstantiated<Token>(__safeDI_token)
		            let __safeDI_serviceValues_model = SafeDIMockScope_Service.Desk_Scope.model_Values(token: token)
		            func __safeDI_model() -> Model {
		                let service: any Service = __safeDI_serviceBuilder(.desk(__safeDI_serviceValues_desk, .model(__safeDI_serviceValues_model, .service(SafeDIMockScope_Service.Model_Scope.service_Values()))))
		                return if let safeDIBuilder = safeDIOverrides.desk.model { safeDIBuilder(service) } else { Model(service: service) }
		            }
		            let model: Model = __safeDI_model()
		            return Desk.__safeDI_init(token: token, model: model, safeDIBuilder: safeDIOverrides.desk.safeDIBuilder)
		        }
		        let desk: Desk = __safeDI_desk()
		        let __safeDI_serviceValues_model = SafeDIMockScope_Service.model_Values(desk: desk)
		        func __safeDI_model() -> Model {
		            let service: any Service = __safeDI_serviceBuilder(.model(__safeDI_serviceValues_model, .service(SafeDIMockScope_Service.Model_Scope.service_Values())))
		            return if let safeDIBuilder = safeDIOverrides.model { safeDIBuilder(service) } else { Model(service: service) }
		        }
		        let model: Model = __safeDI_model()
		        return Office(desk: desk, model: model)
		    }
		}

		extension Office {
		    public enum __safeDI_Office_mock_793294F7A3D3804D {}
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
		        self.token = token
		        self.model = model
		        self.safeDIBuilder = safeDIBuilder
		    }

		    public let token: (() -> Token)?
		    public let model: ((any Service) -> Model)?
		    /// Overrides how `Desk` is constructed. Parameters match the type’s initializer or custom mock method.
		    public let safeDIBuilder: ((LazilyInstantiated<Token>, Model) -> Desk)?
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
		            self.office = office
		        }

		        let office: Office.SafeDIOverrides
		    }

		    static func mock(
		        serviceBuilder: @escaping (Office.SafeDIMockScope_Service) -> any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> OfficeScreen {
		        func __safeDI_office() -> Office {
		            func __safeDI_serviceBuilder_Office_Model_Scope_service(_ scope: Office.SafeDIMockScope_Service.Model_Scope.service_Values, token: Token) -> any Service {
		                let service: any Service = DefaultService(token: token)
		                return service
		            }
		            func __safeDI_serviceBuilder_Office(_ scope: Office.SafeDIMockScope_Service, passUp: () -> any Service) -> any Service {
		                switch scope {
		                case let .desk(_, scope): return __safeDI_serviceBuilder_Office_Desk_Scope(scope, passUp: passUp)
		                case let .model(_, scope): return __safeDI_serviceBuilder_Office_Model_Scope(scope, token: nil, passUp: passUp)
		                }
		            }
		            func __safeDI_serviceBuilder_Office_Desk_Scope(_ scope: Office.SafeDIMockScope_Service.Desk_Scope, passUp: () -> any Service) -> any Service {
		                switch scope {
		                case let .model(values, scope): return __safeDI_serviceBuilder_Office_Model_Scope(scope, token: values.token.instance, passUp: passUp)
		                }
		            }
		            func __safeDI_serviceBuilder_Office_Model_Scope(_ scope: Office.SafeDIMockScope_Service.Model_Scope, token: Token?, passUp: () -> any Service) -> any Service {
		                switch scope {
		                case let .service(scope): if let token { return __safeDI_serviceBuilder_Office_Model_Scope_service(scope, token: token) } else { return passUp() }
		                }
		            }
		            _ = Office.__safeDI_Office_mock_793294F7A3D3804D.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Office.mock(serviceBuilder: { scope in __safeDI_serviceBuilder_Office(scope, passUp: { serviceBuilder(scope) }) }, safeDIOverrides: safeDIOverrides.office)
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
		    @frozen public enum SafeDIMockScope_Gadget {
		        case inner_serviceBuilder(inner_serviceBuilder_Values, Inner.SafeDIMockScope_Service, SafeDIMockScope_Gadget.DefaultService_Scope)
		        case holder(holder_Values, SafeDIMockScope_Gadget.Holder_Scope)

		        public struct inner_serviceBuilder_Values {}

		        public struct holder_Values {
		            public let inner: Inner
		        }

		        @frozen public enum DefaultService_Scope {
		            case gadget(gadget_Values)

		            public struct gadget_Values {}
		        }

		        @frozen public enum Holder_Scope {
		            case direct(direct_Values, SafeDIMockScope_Gadget.DefaultService_Scope)

		            public struct direct_Values {
		                public let id: Code
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            inner: Inner.SafeDIOverrides = .init(),
		            holder: __safeDI_Middle_Holder_MockConfiguration = .init()
		        ) {
		            self.inner = inner
		            self.holder = holder
		        }

		        public let inner: Inner.SafeDIOverrides
		        public let holder: __safeDI_Middle_Holder_MockConfiguration
		    }

		    // SafeDI counts `Gadget` as `public`: no module it reads declares it narrower. If `Gadget` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.
		    public static func mock(
		        gadgetBuilder: @escaping (Outer.SafeDIMockScope_Gadget) -> any Gadget,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Outer {
		        let __safeDI_gadgetBuilder = gadgetBuilder
		        let __safeDI_gadgetValues_inner_serviceBuilder = SafeDIMockScope_Gadget.inner_serviceBuilder_Values()
		        func __safeDI_inner() -> Inner {
		            func __safeDI_serviceBuilder_Inner(_ __safeDI_inner_serviceBuilder: Inner.SafeDIMockScope_Service) -> any Service {
		                switch __safeDI_inner_serviceBuilder {
		                case let .screenBuilder(_, scope): return __safeDI_serviceBuilder_Inner_Screen_Scope(scope, __safeDI_inner_serviceBuilder: __safeDI_inner_serviceBuilder)
		                case .service:
		                    func __safeDI_service() -> DefaultService {
		                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_serviceBuilder(__safeDI_gadgetValues_inner_serviceBuilder, __safeDI_inner_serviceBuilder, .gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())))
		                        return DefaultService(gadget: gadget)
		                    }
		                    let service: any Service = __safeDI_service()
		                    return service
		                }
		            }
		            func __safeDI_serviceBuilder_Inner_Screen_Scope(_ scope: Inner.SafeDIMockScope_Service.Screen_Scope, __safeDI_inner_serviceBuilder: Inner.SafeDIMockScope_Service) -> any Service {
		                switch scope {
		                case .service:
		                    func __safeDI_service() -> DefaultService {
		                        let gadget: any Gadget = __safeDI_gadgetBuilder(.inner_serviceBuilder(__safeDI_gadgetValues_inner_serviceBuilder, __safeDI_inner_serviceBuilder, .gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values())))
		                        return DefaultService(gadget: gadget)
		                    }
		                    let service: any Service = __safeDI_service()
		                    return service
		                }
		            }
		            _ = Inner.__safeDI_Inner_mock_2EFBE0AFAF545FB2.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Inner.mock(serviceBuilder: __safeDI_serviceBuilder_Inner, safeDIOverrides: safeDIOverrides.inner)
		        }
		        let inner: Inner = __safeDI_inner()
		        let __safeDI_gadgetValues_holder = SafeDIMockScope_Gadget.holder_Values(inner: inner)
		        func __safeDI_holder() -> Holder {
		            let id = if let safeDIBuilder = safeDIOverrides.holder.id { safeDIBuilder() } else { Code() }
		            let __safeDI_gadgetValues_direct = SafeDIMockScope_Gadget.Holder_Scope.direct_Values(id: id)
		            func __safeDI_direct() -> DefaultService {
		                let gadget: any Gadget = __safeDI_gadgetBuilder(.holder(__safeDI_gadgetValues_holder, .direct(__safeDI_gadgetValues_direct, .gadget(SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values()))))
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
		    public enum __safeDI_Outer_mock_0701A52A9DE584D8 {}
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
		        self.id = id
		        self.direct = direct
		        self.safeDIBuilder = safeDIBuilder
		    }

		    public let id: (() -> Code)?
		    public let direct: ((any Gadget) -> DefaultService)?
		    /// Overrides how `Holder` is constructed. Parameters match the type’s initializer or custom mock method.
		    public let safeDIBuilder: ((Code, DefaultService) -> Holder)?
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
		            self.outer = outer
		        }

		        let outer: Outer.SafeDIOverrides
		    }

		    static func mock(
		        gadgetBuilder: @escaping (Outer.SafeDIMockScope_Gadget) -> any Gadget,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_outer() -> Outer {
		            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope_gadget(_ scope: Outer.SafeDIMockScope_Gadget.DefaultService_Scope.gadget_Values, id: Code) -> any Gadget {
		                let gadget: any Gadget = LiveGadget(id: id)
		                return gadget
		            }
		            func __safeDI_gadgetBuilder_Outer(_ scope: Outer.SafeDIMockScope_Gadget, passUp: () -> any Gadget) -> any Gadget {
		                switch scope {
		                case let .inner_serviceBuilder(_, _, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, id: nil, passUp: passUp)
		                case let .holder(_, scope): return __safeDI_gadgetBuilder_Outer_Holder_Scope(scope, passUp: passUp)
		                }
		            }
		            func __safeDI_gadgetBuilder_Outer_DefaultService_Scope(_ scope: Outer.SafeDIMockScope_Gadget.DefaultService_Scope, id: Code?, passUp: () -> any Gadget) -> any Gadget {
		                switch scope {
		                case let .gadget(scope): if let id { return __safeDI_gadgetBuilder_Outer_DefaultService_Scope_gadget(scope, id: id) } else { return passUp() }
		                }
		            }
		            func __safeDI_gadgetBuilder_Outer_Holder_Scope(_ scope: Outer.SafeDIMockScope_Gadget.Holder_Scope, passUp: () -> any Gadget) -> any Gadget {
		                switch scope {
		                case let .direct(values, scope): return __safeDI_gadgetBuilder_Outer_DefaultService_Scope(scope, id: values.id, passUp: passUp)
		                }
		            }
		            func __safeDI_id_Inner_SafeDIMockScope_Service(_ scope: Inner.SafeDIMockScope_Service) -> String? {
		                switch scope {
		                case let .screenBuilder(_, scope): return __safeDI_id_Inner_Screen_Scope(scope)
		                case .service: return nil
		                }
		            }
		            func __safeDI_id_Inner_Screen_Scope(_ scope: Inner.SafeDIMockScope_Service.Screen_Scope) -> String {
		                switch scope {
		                case let .service(values): return values.id
		                }
		            }
		            _ = Outer.__safeDI_Outer_mock_0701A52A9DE584D8.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Outer.mock(gadgetBuilder: { scope in __safeDI_gadgetBuilder_Outer(scope, passUp: { gadgetBuilder(scope) }) }, safeDIOverrides: safeDIOverrides.outer)
		        }
		        let outer: Outer = __safeDI_outer()
		        return Root(outer: outer)
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
