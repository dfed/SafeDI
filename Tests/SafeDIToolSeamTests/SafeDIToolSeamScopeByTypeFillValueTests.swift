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

/// One fill per case of an enum nested by type serves every route to the case: a value its tree reads that the case's
/// payload does not carry is a parameter, which each dispatcher passes from the nearest type on the route that binds it,
/// and the root dispatcher from the caller's own scope. These tests hold the values such a fill builds to those of the
/// same graph built inline, route by route.
struct SafeDIToolSeamScopeByTypeFillValueTests: ~Copyable {
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
	mutating func generate_buildsCallersValueFirst_whenRouteWithoutLevelReadsValueTheCallerDeclaresAfterTheSeam() async throws {
		// `Avatar` is reached under `settings`, whose route binds no `session`, and under `home`, which binds its own. The
		// fill reads `session`, so on the `settings` route the root dispatcher passes `Root`'s, which `Root` declares after
		// `service`: the call receives it, so `Root` builds it first.
		try await expectFill(
			feature: [
				"public protocol UserService {}",
				seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Theme", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Avatar", declarations: ["@Instantiated let userService: any UserService"]),
				seamFixtureType(named: "Settings", declarations: ["@Instantiated let avatar: Avatar"]),
				seamFixtureType(named: "Home", declarations: ["@Instantiated let session: Session", "@Instantiated let theme: Theme", "@Instantiated let avatar: Avatar"]),
				seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let settings: Settings", "@Instantiated let home: Home"]),
			],
			fulfillers: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let session: Session", "@Received let theme: Theme"]),
			],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service", "@Instantiated let session: Session"]),
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        let session = Session()
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_BDD2A4CCA0E772F5.self // \(Self.moduleInfoComment)
			            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
			                switch scope {
			                case let .settings(values, scope): return __safeDI_userServiceBuilder_Service_Settings_Scope(scope, session: session, theme: values.theme)
			                case let .home(_, scope): return __safeDI_userServiceBuilder_Service_Home_Scope(scope)
			                }
			            }
			            func __safeDI_userServiceBuilder_Service_Settings_Scope(_ scope: Service.SafeDIScope_UserService.Settings_Scope, session: Session, theme: Theme) -> any UserService {
			                switch scope {
			                case let .avatar(_, scope): return __safeDI_userServiceBuilder_Service_Avatar_Scope(scope, session: session, theme: theme)
			                }
			            }
			            func __safeDI_userServiceBuilder_Service_Avatar_Scope(_ scope: Service.SafeDIScope_UserService.Avatar_Scope, session: Session, theme: Theme) -> any UserService {
			                switch scope {
			                case .userService:
			                    let userService: any UserService = DefaultUserService(session: session, theme: theme)
			                    return userService
			                }
			            }
			            func __safeDI_userServiceBuilder_Service_Home_Scope(_ scope: Service.SafeDIScope_UserService.Home_Scope) -> any UserService {
			                switch scope {
			                case let .avatar(values, scope): return __safeDI_userServiceBuilder_Service_Avatar_Scope(scope, session: values.session, theme: values.theme)
			                }
			            }
			            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
			        }
			        let service: Service = __safeDI_service()
			        self.init(service: service, session: session)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNil_whenRouteWithoutLevelReadsValueOnlyIfAvailableAndCallerDeclaresNone() async throws {
		// The `settings` route binds no `session`, which the fill reads only if available, and `Root` declares none: inline
		// passes `nil` there, so the root dispatcher does, and the parameter is optional.
		try await expectFill(
			feature: [
				"public protocol UserService {}",
				seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Avatar", declarations: ["@Instantiated let userService: any UserService"]),
				seamFixtureType(named: "Home", declarations: ["@Instantiated let session: Session", "@Instantiated let avatar: Avatar"]),
				seamFixtureType(named: "Settings", declarations: ["@Instantiated let avatar: Avatar"]),
				seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let home: Home", "@Instantiated let settings: Settings"]),
			],
			fulfillers: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received(onlyIfAvailable: true) let session: Session?"]),
			],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service"]),
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_F4129070323CDFE2.self // \(Self.moduleInfoComment)
			            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
			                switch scope {
			                case let .home(_, scope): return __safeDI_userServiceBuilder_Service_Home_Scope(scope)
			                case let .settings(_, scope): return __safeDI_userServiceBuilder_Service_Settings_Scope(scope, session: nil)
			                }
			            }
			            func __safeDI_userServiceBuilder_Service_Home_Scope(_ scope: Service.SafeDIScope_UserService.Home_Scope) -> any UserService {
			                switch scope {
			                case let .avatar(values, scope): return __safeDI_userServiceBuilder_Service_Avatar_Scope(scope, session: values.session)
			                }
			            }
			            func __safeDI_userServiceBuilder_Service_Avatar_Scope(_ scope: Service.SafeDIScope_UserService.Avatar_Scope, session: Session?) -> any UserService {
			                switch scope {
			                case .userService:
			                    let userService: any UserService = DefaultUserService(session: session)
			                    return userService
			                }
			            }
			            func __safeDI_userServiceBuilder_Service_Settings_Scope(_ scope: Service.SafeDIScope_UserService.Settings_Scope, session: Session?) -> any UserService {
			                switch scope {
			                case let .avatar(_, scope): return __safeDI_userServiceBuilder_Service_Avatar_Scope(scope, session: session)
			                }
			            }
			            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
			        }
			        let service: Service = __safeDI_service()
			        self.init(service: service)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNil_whenRouteThroughInstantiatorWithoutLevelReadsForwardedValueOnlyIfAvailable() async throws {
		// `Detail` is reached through `Home`, which forwards `tab`, and through `Settings`, which binds none. The fill reads
		// `tab` only if available, and `Root` declares none.
		try await expectFill(
			feature: [
				"public protocol Api {}",
				seamFixtureType(named: "Detail", declarations: ["@Forwarded public let id: Int", "@Instantiated public let api: any Api"]),
				seamFixtureType(named: "Home", declarations: ["@Forwarded public let tab: String", "@Instantiated public let detailBuilder: Instantiator<Detail>"]),
				seamFixtureType(named: "Settings", declarations: ["@Instantiated public let detailBuilder: Instantiator<Detail>"]),
				seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated public let homeBuilder: Instantiator<Home>", "@Instantiated public let settings: Settings"]),
			],
			fulfillers: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultApi", fulfilling: "Api", declarations: ["@Received public let id: Int", "@Received(onlyIfAvailable: true) public let tab: String?"]),
			],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let service: Service"]),
			probes: [
				DifferentialValueProbe("Root()"),
				DifferentialValueProbe(#"Root().service.homeBuilder.instantiate("t").detailBuilder.instantiate(7)"#),
				DifferentialValueProbe("Root().service.settings.detailBuilder.instantiate(9)"),
			],
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_47E9FFFFF356AFE2.self // \(Self.moduleInfoComment)
			            func __safeDI_apiBuilder_Service(_ scope: Service.SafeDIScope_Api) -> any Api {
			                switch scope {
			                case let .homeBuilder(_, scope): return __safeDI_apiBuilder_Service_Home_Scope(scope)
			                case let .settings(_, scope): return __safeDI_apiBuilder_Service_Settings_Scope(scope, tab: nil)
			                }
			            }
			            func __safeDI_apiBuilder_Service_Home_Scope(_ scope: Service.SafeDIScope_Api.Home_Scope) -> any Api {
			                switch scope {
			                case let .detailBuilder(values, scope): return __safeDI_apiBuilder_Service_Detail_Scope(scope, tab: values.tab)
			                }
			            }
			            func __safeDI_apiBuilder_Service_Detail_Scope(_ scope: Service.SafeDIScope_Api.Detail_Scope, tab: String?) -> any Api {
			                switch scope {
			                case let .api(scope):
			                    let id = scope.id
			                    let api: any Api = DefaultApi(id: id, tab: tab)
			                    return api
			                }
			            }
			            func __safeDI_apiBuilder_Service_Settings_Scope(_ scope: Service.SafeDIScope_Api.Settings_Scope, tab: String?) -> any Api {
			                switch scope {
			                case let .detailBuilder(_, scope): return __safeDI_apiBuilder_Service_Detail_Scope(scope, tab: tab)
			                }
			            }
			            return Service(__safeDI_apiBuilder: __safeDI_apiBuilder_Service)
			        }
			        let service: Service = __safeDI_service()
			        self.init(service: service)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_typesParameterOptional_whenOneRouteHoldsValueOptionallyAndTheOtherRouteIsFirst() async throws {
		// `Home` instantiates `session: Session`; `Settings` forwards `session: Session?`. The fill reads it only if
		// available, so its parameter is `Session?` whichever route the builders reach first.
		try await expectFill(
			feature: Self.optionalFormsFeature(homeFirst: true),
			fulfillers: [Self.optionalFormsFulfiller],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let service: Service"]),
			probes: Self.optionalFormsProbes,
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_E862B36C039806C6.self // \(Self.moduleInfoComment)
			            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
			                switch scope {
			                case let .home(_, scope): return __safeDI_userServiceBuilder_Service_Home_Scope(scope)
			                case let .settingsBuilder(_, scope): return __safeDI_userServiceBuilder_Service_Settings_Scope(scope)
			                }
			            }
			            func __safeDI_userServiceBuilder_Service_Home_Scope(_ scope: Service.SafeDIScope_UserService.Home_Scope) -> any UserService {
			                switch scope {
			                case let .avatar(values, scope): return __safeDI_userServiceBuilder_Service_Avatar_Scope(scope, session: values.session)
			                }
			            }
			            func __safeDI_userServiceBuilder_Service_Avatar_Scope(_ scope: Service.SafeDIScope_UserService.Avatar_Scope, session: Session?) -> any UserService {
			                switch scope {
			                case .userService:
			                    let userService: any UserService = DefaultUserService(session: session)
			                    return userService
			                }
			            }
			            func __safeDI_userServiceBuilder_Service_Settings_Scope(_ scope: Service.SafeDIScope_UserService.Settings_Scope) -> any UserService {
			                switch scope {
			                case let .avatar(values, scope): return __safeDI_userServiceBuilder_Service_Avatar_Scope(scope, session: values.session)
			                }
			            }
			            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
			        }
			        let service: Service = __safeDI_service()
			        self.init(service: service)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_typesParameterOptional_whenOneRouteHoldsValueOptionallyAndThatRouteIsFirst() async throws {
		try await expectFill(
			feature: Self.optionalFormsFeature(homeFirst: false),
			fulfillers: [Self.optionalFormsFulfiller],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let service: Service"]),
			probes: Self.optionalFormsProbes,
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_5F431683C56802AF.self // \(Self.moduleInfoComment)
			            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
			                switch scope {
			                case let .settingsBuilder(_, scope): return __safeDI_userServiceBuilder_Service_Settings_Scope(scope)
			                case let .home(_, scope): return __safeDI_userServiceBuilder_Service_Home_Scope(scope)
			                }
			            }
			            func __safeDI_userServiceBuilder_Service_Settings_Scope(_ scope: Service.SafeDIScope_UserService.Settings_Scope) -> any UserService {
			                switch scope {
			                case let .avatar(values, scope): return __safeDI_userServiceBuilder_Service_Avatar_Scope(scope, session: values.session)
			                }
			            }
			            func __safeDI_userServiceBuilder_Service_Avatar_Scope(_ scope: Service.SafeDIScope_UserService.Avatar_Scope, session: Session?) -> any UserService {
			                switch scope {
			                case .userService:
			                    let userService: any UserService = DefaultUserService(session: session)
			                    return userService
			                }
			            }
			            func __safeDI_userServiceBuilder_Service_Home_Scope(_ scope: Service.SafeDIScope_UserService.Home_Scope) -> any UserService {
			                switch scope {
			                case let .avatar(values, scope): return __safeDI_userServiceBuilder_Service_Avatar_Scope(scope, session: values.session)
			                }
			            }
			            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
			        }
			        let service: Service = __safeDI_service()
			        self.init(service: service)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsLevelsValue_whenFirstRouteReadsDeferredPassThroughAndSecondRouteBindsItsOwn() async throws {
		// `Avatar` receives `logger`, which `Service` passes through from `Root` on the `settings` route, and which `Home`
		// binds on the `home` route. The `home` route reads `Home`'s, the `settings` route `Root`'s.
		try await expectFill(
			feature: Self.deferredPassThroughFeature(settingsFirst: true),
			fulfillers: [Self.loggerFulfiller],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let logger: Logger", "@Instantiated let service: Service"]),
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        let logger = Logger()
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_A5FB911289C13CF5.self // \(Self.moduleInfoComment)
			            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
			                switch scope {
			                case let .settings(_, scope): return __safeDI_userServiceBuilder_Service_Settings_Scope(scope, logger: logger)
			                case let .home(_, scope): return __safeDI_userServiceBuilder_Service_Home_Scope(scope)
			                }
			            }
			            func __safeDI_userServiceBuilder_Service_Settings_Scope(_ scope: Service.SafeDIScope_UserService.Settings_Scope, logger: Logger) -> any UserService {
			                switch scope {
			                case let .avatar(_, scope): return __safeDI_userServiceBuilder_Service_Avatar_Scope(scope, logger: logger)
			                }
			            }
			            func __safeDI_userServiceBuilder_Service_Avatar_Scope(_ scope: Service.SafeDIScope_UserService.Avatar_Scope, logger: Logger) -> any UserService {
			                switch scope {
			                case .userService:
			                    let userService: any UserService = DefaultUserService(logger: logger)
			                    return userService
			                }
			            }
			            func __safeDI_userServiceBuilder_Service_Home_Scope(_ scope: Service.SafeDIScope_UserService.Home_Scope) -> any UserService {
			                switch scope {
			                case let .avatar(values, scope): return __safeDI_userServiceBuilder_Service_Avatar_Scope(scope, logger: values.logger)
			                }
			            }
			            return Service(__safeDI_logger: logger, __safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
			        }
			        let service: Service = __safeDI_service()
			        self.init(logger: logger, service: service)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsLevelsValue_whenFirstRouteBindsItsOwnAndSecondRouteReadsDeferredPassThrough() async throws {
		try await expectFill(
			feature: Self.deferredPassThroughFeature(settingsFirst: false),
			fulfillers: [Self.loggerFulfiller],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let logger: Logger", "@Instantiated let service: Service"]),
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        let logger = Logger()
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_56059E08F2BE9915.self // \(Self.moduleInfoComment)
			            func __safeDI_userServiceBuilder_Service(_ scope: Service.SafeDIScope_UserService) -> any UserService {
			                switch scope {
			                case let .home(_, scope): return __safeDI_userServiceBuilder_Service_Home_Scope(scope)
			                case let .settings(_, scope): return __safeDI_userServiceBuilder_Service_Settings_Scope(scope, logger: logger)
			                }
			            }
			            func __safeDI_userServiceBuilder_Service_Home_Scope(_ scope: Service.SafeDIScope_UserService.Home_Scope) -> any UserService {
			                switch scope {
			                case let .avatar(values, scope): return __safeDI_userServiceBuilder_Service_Avatar_Scope(scope, logger: values.logger)
			                }
			            }
			            func __safeDI_userServiceBuilder_Service_Avatar_Scope(_ scope: Service.SafeDIScope_UserService.Avatar_Scope, logger: Logger) -> any UserService {
			                switch scope {
			                case .userService:
			                    let userService: any UserService = DefaultUserService(logger: logger)
			                    return userService
			                }
			            }
			            func __safeDI_userServiceBuilder_Service_Settings_Scope(_ scope: Service.SafeDIScope_UserService.Settings_Scope, logger: Logger) -> any UserService {
			                switch scope {
			                case let .avatar(_, scope): return __safeDI_userServiceBuilder_Service_Avatar_Scope(scope, logger: logger)
			                }
			            }
			            return Service(__safeDI_logger: logger, __safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service)
			        }
			        let service: Service = __safeDI_service()
			        self.init(logger: logger, service: service)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNil_whenRouteWithoutLevelReadsValueOnlyIfAvailableAndForwardingRouteIsFirst() async throws {
		// `A` forwards `session` and is reached through an instantiator; `B` binds none. The fill reads `session` only if
		// available and `Root` declares none.
		try await expectFill(
			feature: [
				"public protocol Api {}",
				seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Avatar", declarations: ["@Instantiated let api: any Api"]),
				seamFixtureType(named: "A", declarations: ["@Forwarded let session: Session", "@Instantiated let avatar: Avatar"]),
				seamFixtureType(named: "B", declarations: ["@Instantiated let avatar: Avatar"]),
				seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let b: B"]),
			],
			fulfillers: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) let session: Session?"]),
			],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let home: Home"]),
			probes: [
				DifferentialValueProbe("Root()"),
				DifferentialValueProbe("Root().home.aBuilder.instantiate(Session())"),
			],
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_home() -> Home {
			            _ = Home.__safeDI_Home_B439E14552F86528.self // \(Self.moduleInfoComment)
			            func __safeDI_apiBuilder_Home(_ scope: Home.SafeDIScope_Api) -> any Api {
			                switch scope {
			                case let .aBuilder(_, scope): return __safeDI_apiBuilder_Home_A_Scope(scope)
			                case let .b(_, scope): return __safeDI_apiBuilder_Home_B_Scope(scope, session: nil)
			                }
			            }
			            func __safeDI_apiBuilder_Home_A_Scope(_ scope: Home.SafeDIScope_Api.A_Scope) -> any Api {
			                switch scope {
			                case let .avatar(values, scope): return __safeDI_apiBuilder_Home_Avatar_Scope(scope, session: values.session)
			                }
			            }
			            func __safeDI_apiBuilder_Home_Avatar_Scope(_ scope: Home.SafeDIScope_Api.Avatar_Scope, session: Session?) -> any Api {
			                switch scope {
			                case .api:
			                    let api: any Api = LiveApi(session: session)
			                    return api
			                }
			            }
			            func __safeDI_apiBuilder_Home_B_Scope(_ scope: Home.SafeDIScope_Api.B_Scope, session: Session?) -> any Api {
			                switch scope {
			                case let .avatar(_, scope): return __safeDI_apiBuilder_Home_Avatar_Scope(scope, session: session)
			                }
			            }
			            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home)
			        }
			        let home: Home = __safeDI_home()
			        self.init(home: home)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsInnerSeamsDispatcherNoValuesOfOuterSeam_whenOuterSeamPassesPlaceUpThroughWrappingCase() async throws {
		// `Outer` calls `Inner`, whose place `api` it passes up: `Outer`'s enum wraps `Inner`'s in a case that carries what
		// `Outer` binds before `inner`, for a builder a person writes. A generated fill never reads it: `Inner`'s root
		// dispatcher takes no parameters, so `theme`, which no type on the route binds, is `Root`'s, as inline.
		try await expectFill(
			feature: Self.passedUpPlaceFeature(outerBindsTheme: false),
			fulfillers: [Self.passedUpPlaceFulfiller],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let outer: Outer"]),
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        let theme = Theme()
			        func __safeDI_outer() -> Outer {
			            _ = Outer.__safeDI_Outer_ABE6117F85943AE5.self // \(Self.moduleInfoComment)
			            func __safeDI_apiBuilder_Outer(_ scope: Outer.SafeDIScope_Api) -> any Api {
			                switch scope {
			                case let .inner(_, scope): return __safeDI_apiBuilder_Inner(scope)
			                }
			            }
			            func __safeDI_apiBuilder_Inner(_ scope: Inner.SafeDIScope_Api) -> any Api {
			                switch scope {
			                case let .panel(_, scope): return __safeDI_apiBuilder_Inner_Panel_Scope(scope)
			                }
			            }
			            func __safeDI_apiBuilder_Inner_Panel_Scope(_ scope: Inner.SafeDIScope_Api.Panel_Scope) -> any Api {
			                switch scope {
			                case let .api(scope):
			                    let session = scope.session
			                    let api: any Api = DefaultApi(session: session, theme: theme)
			                    return api
			                }
			            }
			            return Outer(__safeDI_apiBuilder: __safeDI_apiBuilder_Outer)
			        }
			        let outer: Outer = __safeDI_outer()
			        self.init(theme: theme, outer: outer)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsBoundByPassingUpSeam_whenFillReadsValueOuterSeamBindsBeforeWrappingCase() async {
		// As above, but `Outer` binds `theme` before calling `Inner`. Its wrapping case carries `theme`, but no generated fill
		// reads a wrapping case's values in this release: per place, the fill could not read `Outer`'s `theme`, so it is
		// reported, never handed `Root`'s.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultApi.swift"]):11:5: error: `DefaultApi` receives `theme: Theme`, which `Outer` builds where it calls `Inner`, but `Outer` passes the builder for `Panel`'s `api: any Api` (case `Panel_Scope.api` of `apiBuilder`) on from its own caller, which cannot hand it `Outer`'s values. Declare `@Received let theme: Theme` on `Inner`, so the builder’s scope carries it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies, so `Outer` fills the builder itself.
			\(fixtures["Feature"]!["Outer.swift"]):8:5: note: `Outer` declares `theme: Theme` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(
					feature: Self.passedUpPlaceFeature(outerBindsTheme: true),
					app: [
						Self.passedUpPlaceFulfiller,
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let outer: Outer"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFieldFormsDiffer_whenRoutesToOneCaseHoldReadValueLazilyAndByValue() async {
		// `Home` holds `session` lazily and `Settings` by value, each before `avatar`. Each place alone reads its route's
		// value, but one fill fills both, and no one parameter takes a `LazilyInstantiated<Session>` and a `Session`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Home.swift"]):8:5: error: SafeDI fills every place of the builder for `Avatar`'s `userService: any UserService` (case `Avatar_Scope.userService` of `userServiceBuilder`) with one function, which reads `session`, but the types on the routes to those places declare it in forms one value cannot carry: `session: LazilyInstantiated<Session>` (`Home`) and `session: Session` (`Settings`). Declare `session: LazilyInstantiated<Session>` on each, or declare an @Instantiable type that fulfills `UserService` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Settings.swift"]):8:5: note: `Settings` declares `session: Session` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(
					feature: [
						"public protocol UserService {}",
						seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
						seamFixtureType(named: "Avatar", declarations: ["@Instantiated let userService: any UserService"]),
						seamFixtureType(named: "Home", declarations: ["@Instantiated let session: LazilyInstantiated<Session>", "@Instantiated let avatar: Avatar"]),
						seamFixtureType(named: "Settings", declarations: ["@Instantiated let session: Session", "@Instantiated let avatar: Avatar"]),
						seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let home: Home", "@Instantiated let settings: Settings"]),
					],
					app: [
						SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let session: Session"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Home` instantiates `session: Session` and `Settings` forwards `session: Session?`, each before `avatar`, whose
	/// `userService` the fill reads `session` for; `Service` instantiates `home` first when `homeFirst`.
	private static func optionalFormsFeature(homeFirst: Bool) -> [String] {
		let serviceDeclarations = ["@Instantiated public let home: Home", "@Instantiated public let settingsBuilder: Instantiator<Settings>"]
		return [
			"public protocol UserService {}",
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Avatar", declarations: ["@Instantiated public let userService: any UserService"]),
			seamFixtureType(named: "Home", declarations: ["@Instantiated public let session: Session", "@Instantiated public let avatar: Avatar"]),
			seamFixtureType(named: "Settings", declarations: ["@Forwarded public let session: Session?", "@Instantiated public let avatar: Avatar"]),
			seamFixtureType(named: "Service", isSeam: true, declarations: homeFirst ? serviceDeclarations : serviceDeclarations.reversed()),
		]
	}

	private static let optionalFormsFulfiller = SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received(onlyIfAvailable: true) public let session: Session?"])

	private static let optionalFormsProbes = [
		DifferentialValueProbe("Root()"),
		DifferentialValueProbe("Root().service.settingsBuilder.instantiate(nil)"),
		DifferentialValueProbe("Root().service.settingsBuilder.instantiate(Session())"),
	]

	/// `Avatar` receives `logger` and is reached under `settings`, where `Service` passes `logger` through, and under
	/// `home`, which instantiates its own `logger` first; `Service` instantiates `settings` first when `settingsFirst`.
	private static func deferredPassThroughFeature(settingsFirst: Bool) -> [String] {
		let serviceDeclarations = ["@Instantiated let settings: Settings", "@Instantiated let home: Home"]
		return [
			"public protocol UserService {}",
			seamFixtureType(named: "Logger", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Avatar", declarations: ["@Received let logger: Logger", "@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "Home", declarations: ["@Instantiated let logger: Logger", "@Instantiated let avatar: Avatar"]),
			seamFixtureType(named: "Settings", declarations: ["@Instantiated let avatar: Avatar"]),
			seamFixtureType(named: "Service", isSeam: true, declarations: settingsFirst ? serviceDeclarations : serviceDeclarations.reversed()),
		]
	}

	/// `Inner`'s place `api` under `Panel`, which binds `session`, and `Outer`, which calls `Inner` and passes the place
	/// up, binding `theme` before the call when `outerBindsTheme`.
	private static func passedUpPlaceFeature(outerBindsTheme: Bool) -> [String] {
		[
			"public protocol Api {}",
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Theme", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Panel", declarations: ["@Instantiated let session: Session", "@Instantiated let api: any Api"]),
			seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated let panel: Panel"]),
			seamFixtureType(named: "Outer", isSeam: true, declarations: (outerBindsTheme ? ["@Instantiated let theme: Theme"] : []) + ["@Instantiated let inner: Inner"]),
		]
	}

	private static let passedUpPlaceFulfiller = SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultApi", fulfilling: "Api", declarations: ["@Received let session: Session", "@Received let theme: Theme"])

	private static let loggerFulfiller = SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let logger: Logger"])

	/// The comment a call of `Feature`'s seam carries in a `.safedi` flow.
	private static let moduleInfoComment = "If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes."

	/// Generates `feature`, whose seam `Service` (or `Home`) holds a place `App` fills with `fulfillers`, and `App`'s
	/// `root`; expects `App`'s file to equal `expectedApp`, and the values `Root` builds to equal those of the same graph
	/// built with `fulfillers` in `Feature`, where every tree is built inline.
	private mutating func expectFill(
		feature: [String],
		fulfillers: [String],
		root: String,
		probes: [DifferentialValueProbe] = [DifferentialValueProbe("Root()")],
		expectedApp: String,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + expectedApp, sourceLocation: sourceLocation)
		guard compileVerificationIsEnabled else { return }
		let visibleModules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [root])
		let visibleOutput = try await executeSafeDIToolMultiModuleTest(modules: visibleModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: visibleOutput, modules: visibleModules),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
