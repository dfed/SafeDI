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
			        func __safeDI_userServiceBuilder_Service() -> Service.__safeDI_UserServiceCarrier<any UserService> {
			            .init(settings: { values_theme in __safeDI_userServiceBuilder_Service_Settings_Scope(session: session, theme: values_theme) }, home: { values_theme, values_settings in __safeDI_userServiceBuilder_Service_Home_Scope() })
			        }
			        func __safeDI_userServiceBuilder_Service_Settings_Scope(session: Session, theme: Theme) -> Service.__safeDI_UserServiceCarrier_Settings<any UserService> {
			            .init(avatar: __safeDI_userServiceBuilder_Service_Avatar_Scope(session: session, theme: theme))
			        }
			        func __safeDI_userServiceBuilder_Service_Avatar_Scope(session: Session, theme: Theme) -> Service.__safeDI_UserServiceCarrier_Avatar<any UserService> {
			            .init(userService: {
			                let userService: any UserService = DefaultUserService(session: session, theme: theme)
			                return userService
			            })
			        }
			        func __safeDI_userServiceBuilder_Service_Home_Scope() -> Service.__safeDI_UserServiceCarrier_Home<any UserService> {
			            .init(avatar: { values_session, values_theme in __safeDI_userServiceBuilder_Service_Avatar_Scope(session: values_session, theme: values_theme) })
			        }
			        let session = Session()
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_C25F2916AB97F229.self // \(Self.moduleInfoComment)
			            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service())
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
			        func __safeDI_userServiceBuilder_Service_Home_Scope() -> Service.__safeDI_UserServiceCarrier_Home<any UserService> {
			            .init(avatar: { values_session in __safeDI_userServiceBuilder_Service_Avatar_Scope(session: values_session) })
			        }
			        func __safeDI_userServiceBuilder_Service_Avatar_Scope(session: Session?) -> Service.__safeDI_UserServiceCarrier_Avatar<any UserService> {
			            .init(userService: {
			                let userService: any UserService = DefaultUserService(session: session)
			                return userService
			            })
			        }
			        func __safeDI_userServiceBuilder_Service_Settings_Scope(session: Session?) -> Service.__safeDI_UserServiceCarrier_Settings<any UserService> {
			            .init(avatar: __safeDI_userServiceBuilder_Service_Avatar_Scope(session: session))
			        }
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_D06DB61BED988956.self // \(Self.moduleInfoComment)
			            func __safeDI_userServiceBuilder_Service() -> Service.__safeDI_UserServiceCarrier<any UserService> {
			                .init(home: __safeDI_userServiceBuilder_Service_Home_Scope(), settings: { values_home in __safeDI_userServiceBuilder_Service_Settings_Scope(session: nil) })
			            }
			            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service())
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
			        func __safeDI_apiBuilder_Service_Home_Scope() -> Service.__safeDI_ApiCarrier_Home<any Api> {
			            .init(detailBuilder: { values_tab in __safeDI_apiBuilder_Service_Detail_Scope(tab: values_tab) })
			        }
			        func __safeDI_apiBuilder_Service_Detail_Scope(tab: String?) -> Service.__safeDI_ApiCarrier_Detail<any Api> {
			            .init(api: { scope_id in
			                let id = scope_id
			                let api: any Api = DefaultApi(id: id, tab: tab)
			                return api
			            })
			        }
			        func __safeDI_apiBuilder_Service_Settings_Scope(tab: String?) -> Service.__safeDI_ApiCarrier_Settings<any Api> {
			            .init(detailBuilder: __safeDI_apiBuilder_Service_Detail_Scope(tab: tab))
			        }
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_2CEE2E5D483A1EF6.self // \(Self.moduleInfoComment)
			            func __safeDI_apiBuilder_Service() -> Service.__safeDI_ApiCarrier<any Api> {
			                .init(homeBuilder: __safeDI_apiBuilder_Service_Home_Scope(), settings: { values_homeBuilder in __safeDI_apiBuilder_Service_Settings_Scope(tab: nil) })
			            }
			            return Service(__safeDI_apiBuilder: __safeDI_apiBuilder_Service())
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
			        func __safeDI_userServiceBuilder_Service() -> Service.__safeDI_UserServiceCarrier<any UserService> {
			            .init(home: __safeDI_userServiceBuilder_Service_Home_Scope(), settingsBuilder: { values_home in __safeDI_userServiceBuilder_Service_Settings_Scope() })
			        }
			        func __safeDI_userServiceBuilder_Service_Home_Scope() -> Service.__safeDI_UserServiceCarrier_Home<any UserService> {
			            .init(avatar: { values_session in __safeDI_userServiceBuilder_Service_Avatar_Scope(session: values_session) })
			        }
			        func __safeDI_userServiceBuilder_Service_Avatar_Scope(session: Session?) -> Service.__safeDI_UserServiceCarrier_Avatar<any UserService> {
			            .init(userService: {
			                let userService: any UserService = DefaultUserService(session: session)
			                return userService
			            })
			        }
			        func __safeDI_userServiceBuilder_Service_Settings_Scope() -> Service.__safeDI_UserServiceCarrier_Settings<any UserService> {
			            .init(avatar: { values_session in __safeDI_userServiceBuilder_Service_Avatar_Scope(session: values_session) })
			        }
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_766BBB41F728010A.self // \(Self.moduleInfoComment)
			            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service())
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
			        func __safeDI_userServiceBuilder_Service() -> Service.__safeDI_UserServiceCarrier<any UserService> {
			            .init(settingsBuilder: __safeDI_userServiceBuilder_Service_Settings_Scope(), home: { values_settingsBuilder in __safeDI_userServiceBuilder_Service_Home_Scope() })
			        }
			        func __safeDI_userServiceBuilder_Service_Settings_Scope() -> Service.__safeDI_UserServiceCarrier_Settings<any UserService> {
			            .init(avatar: { values_session in __safeDI_userServiceBuilder_Service_Avatar_Scope(session: values_session) })
			        }
			        func __safeDI_userServiceBuilder_Service_Avatar_Scope(session: Session?) -> Service.__safeDI_UserServiceCarrier_Avatar<any UserService> {
			            .init(userService: {
			                let userService: any UserService = DefaultUserService(session: session)
			                return userService
			            })
			        }
			        func __safeDI_userServiceBuilder_Service_Home_Scope() -> Service.__safeDI_UserServiceCarrier_Home<any UserService> {
			            .init(avatar: { values_session in __safeDI_userServiceBuilder_Service_Avatar_Scope(session: values_session) })
			        }
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_E393F1B8E43D7CAB.self // \(Self.moduleInfoComment)
			            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service())
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
			        func __safeDI_userServiceBuilder_Service() -> Service.__safeDI_UserServiceCarrier<any UserService> {
			            .init(settings: { values_logger in __safeDI_userServiceBuilder_Service_Settings_Scope(logger: logger) }, home: { values_logger, values_settings in __safeDI_userServiceBuilder_Service_Home_Scope() })
			        }
			        func __safeDI_userServiceBuilder_Service_Settings_Scope(logger: Logger) -> Service.__safeDI_UserServiceCarrier_Settings<any UserService> {
			            .init(avatar: __safeDI_userServiceBuilder_Service_Avatar_Scope(logger: logger))
			        }
			        func __safeDI_userServiceBuilder_Service_Avatar_Scope(logger: Logger) -> Service.__safeDI_UserServiceCarrier_Avatar<any UserService> {
			            .init(userService: {
			                let userService: any UserService = DefaultUserService(logger: logger)
			                return userService
			            })
			        }
			        func __safeDI_userServiceBuilder_Service_Home_Scope() -> Service.__safeDI_UserServiceCarrier_Home<any UserService> {
			            .init(avatar: { values_logger in __safeDI_userServiceBuilder_Service_Avatar_Scope(logger: values_logger) })
			        }
			        let logger = Logger()
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_7BB64FE7E3D2A4FF.self // \(Self.moduleInfoComment)
			            return Service(__safeDI_logger: logger, __safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service())
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
			        func __safeDI_userServiceBuilder_Service() -> Service.__safeDI_UserServiceCarrier<any UserService> {
			            .init(home: { values_logger in __safeDI_userServiceBuilder_Service_Home_Scope() }, settings: { values_logger, values_home in __safeDI_userServiceBuilder_Service_Settings_Scope(logger: logger) })
			        }
			        func __safeDI_userServiceBuilder_Service_Home_Scope() -> Service.__safeDI_UserServiceCarrier_Home<any UserService> {
			            .init(avatar: { values_logger in __safeDI_userServiceBuilder_Service_Avatar_Scope(logger: values_logger) })
			        }
			        func __safeDI_userServiceBuilder_Service_Avatar_Scope(logger: Logger) -> Service.__safeDI_UserServiceCarrier_Avatar<any UserService> {
			            .init(userService: {
			                let userService: any UserService = DefaultUserService(logger: logger)
			                return userService
			            })
			        }
			        func __safeDI_userServiceBuilder_Service_Settings_Scope(logger: Logger) -> Service.__safeDI_UserServiceCarrier_Settings<any UserService> {
			            .init(avatar: __safeDI_userServiceBuilder_Service_Avatar_Scope(logger: logger))
			        }
			        let logger = Logger()
			        func __safeDI_service() -> Service {
			            _ = Service.__safeDI_Service_DEF254FB9884D00F.self // \(Self.moduleInfoComment)
			            return Service(__safeDI_logger: logger, __safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service())
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
			        func __safeDI_apiBuilder_Home_A_Scope() -> Home.__safeDI_ApiCarrier_A<any Api> {
			            .init(avatar: { values_session in __safeDI_apiBuilder_Home_Avatar_Scope(session: values_session) })
			        }
			        func __safeDI_apiBuilder_Home_Avatar_Scope(session: Session?) -> Home.__safeDI_ApiCarrier_Avatar<any Api> {
			            .init(api: {
			                let api: any Api = LiveApi(session: session)
			                return api
			            })
			        }
			        func __safeDI_apiBuilder_Home_B_Scope(session: Session?) -> Home.__safeDI_ApiCarrier_B<any Api> {
			            .init(avatar: __safeDI_apiBuilder_Home_Avatar_Scope(session: session))
			        }
			        func __safeDI_home() -> Home {
			            _ = Home.__safeDI_Home_86483726617AD620.self // \(Self.moduleInfoComment)
			            func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
			                .init(aBuilder: __safeDI_apiBuilder_Home_A_Scope(), b: { values_aBuilder in __safeDI_apiBuilder_Home_B_Scope(session: nil) })
			            }
			            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
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
		// `Outer` calls `Inner`, whose place `api` it passes up: `Outer`'s enum wraps `Inner`'s in a case that holds `Inner`'s
		// enum alone. `Inner`'s root dispatcher takes no parameters, so `theme`, which no type on the route binds, is
		// `Root`'s, as inline.
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
			            _ = Outer.__safeDI_Outer_51580B58182D7898.self // \(Self.moduleInfoComment)
			            func __safeDI_apiBuilder_Outer() -> Outer.__safeDI_ApiCarrier<any Api> {
			                .init(inner: __safeDI_apiBuilder_Inner())
			            }
			            func __safeDI_apiBuilder_Inner() -> Inner.__safeDI_ApiCarrier<any Api> {
			                .init(panel: __safeDI_apiBuilder_Inner_Panel_Scope())
			            }
			            func __safeDI_apiBuilder_Inner_Panel_Scope() -> Inner.__safeDI_ApiCarrier_Panel<any Api> {
			                .init(api: { scope_session in
			                    let session = scope_session
			                    let api: any Api = DefaultApi(session: session, theme: theme)
			                    return api
			                })
			            }
			            return Outer(__safeDI_apiBuilder: __safeDI_apiBuilder_Outer())
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
			\(fixtures["App"]!["DefaultApi.swift"]):11:5: error: `DefaultApi` receives `theme: Theme`, which `Outer` builds where it calls `Inner`, but `Outer` passes the builder for `Panel`’s `api: any Api` (`api` of `apiBuilder`) on from its own caller, which cannot hand it `Outer`’s values. Declare `@Received let theme: Theme` on `Inner`, so SafeDI hands it to the builder, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies, so `Outer` fills the builder itself.
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
			\(fixtures["Feature"]!["Home.swift"]):8:5: error: SafeDI fills every place of the builder for `Avatar`’s `userService: any UserService` (`userService` of `userServiceBuilder`) with one function, which reads `session`, but the types on the routes to those places declare it in forms one value cannot carry: `session: LazilyInstantiated<Session>` (`Home`) and `session: Session` (`Settings`). Declare `session: LazilyInstantiated<Session>` on each, or declare an @Instantiable type that fulfills `UserService` in module `Feature` or a module it lists among its SafeDI dependencies.
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

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_wrapsCallersTokenForFill_whenLevelBindsTokenLazilyBesideCallersPlainToken(integration: MultiModuleIntegration) async throws {
		// `Desk` binds `token` lazily above one of `Model`’s places, and `Root` holds a plain `token` above the other, which
		// the root dispatcher hands the fill. The fill takes the wrapper and reads its instance where it builds `userService`:
		// `Desk`’s route hands it `Desk`’s wrapper, and the root dispatcher wraps `Root`’s own `token`, as inline reads each.
		try await expectFill(
			feature: Self.lazyRouteFeature(),
			fulfillers: [Self.lazyRouteFulfiller],
			root: Self.lazyRouteRoot,
			integration: integration,
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
			            .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
			        }
			        func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
			            .init(userService: {
			                let userService: any UserService = DefaultUserService(token: token.instance)
			                return userService
			            })
			        }
			        let token = Token()
			        func __safeDI_office() -> Office {
			            _ = Office.__safeDI_Office_B2DE8228FC9538C0.self\(SafeDIToolSeamBuilderParameterTests.pluginComment(integration, seam: "Office"))
			            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
			                .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>({ token })) })
			            }
			            return Office(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
			        }
			        let office: Office = __safeDI_office()
			        self.init(token: token, office: office)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_wrapsCallersTokenForFill_whenRouteReadingCallersPlainTokenIsFirst() async throws {
		// `Office` builds `model`, whose route binds no `token`, before `desk`, which binds it lazily: the builders reach the
		// route that reads `Root`’s plain `token` first, and the fill still takes the wrapper.
		try await expectFill(
			feature: Self.lazyRouteFeature(deskFirst: false),
			fulfillers: [Self.lazyRouteFulfiller],
			root: Self.lazyRouteRoot,
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
			            .init(userService: {
			                let userService: any UserService = DefaultUserService(token: token.instance)
			                return userService
			            })
			        }
			        func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
			            .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
			        }
			        let token = Token()
			        func __safeDI_office() -> Office {
			            _ = Office.__safeDI_Office_C89D2770CF7FEA3C.self // \(Self.moduleInfoComment)
			            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
			                .init(model: __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>({ token })), desk: { values_model in __safeDI_userServiceBuilder_Office_Desk_Scope() })
			            }
			            return Office(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
			        }
			        let office: Office = __safeDI_office()
			        self.init(token: token, office: office)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_wrapsCallersTokenForFill_whenLevelBindsTokenSendableLazilyBesideCallersPlainToken() async throws {
		try await expectFill(
			feature: Self.lazyRouteFeature(deskToken: "SendableLazilyInstantiated<Token>"),
			fulfillers: [Self.lazyRouteFulfiller],
			root: Self.lazyRouteRoot,
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
			            .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
			        }
			        func __safeDI_userServiceBuilder_Office_Model_Scope(token: SendableLazilyInstantiated<Token>) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
			            .init(userService: {
			                let userService: any UserService = DefaultUserService(token: token.instance)
			                return userService
			            })
			        }
			        let token = Token()
			        func __safeDI_office() -> Office {
			            _ = Office.__safeDI_Office_73F97802D05F021E.self // \(Self.moduleInfoComment)
			            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
			                .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: SendableLazilyInstantiated<Token>({ token })) })
			            }
			            return Office(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
			        }
			        let office: Office = __safeDI_office()
			        self.init(token: token, office: office)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsFillCallersTokenInstance_whenCallerHoldsTokenLazilyBesideLevelsPlainToken() async throws {
		// The other way round: `Desk` binds a plain `token`, which the fill takes, and `Root` holds it lazily, so the root
		// dispatcher hands the fill `Root`’s instance.
		try await expectFill(
			feature: Self.lazyRouteFeature(deskToken: "Token"),
			fulfillers: [Self.lazyRouteFulfiller],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let token: LazilyInstantiated<Token>", "@Instantiated let office: Office"]),
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
			            .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
			        }
			        func __safeDI_userServiceBuilder_Office_Model_Scope(token: Token) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
			            .init(userService: {
			                let userService: any UserService = DefaultUserService(token: token)
			                return userService
			            })
			        }
			        func __safeDI_token() -> Token {
			            Token()
			        }
			        let token = LazilyInstantiated<Token>(__safeDI_token)
			        func __safeDI_office() -> Office {
			            _ = Office.__safeDI_Office_F8D805F0A45A6EA3.self // \(Self.moduleInfoComment)
			            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
			                .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: token.instance) })
			            }
			            return Office(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
			        }
			        let office: Office = __safeDI_office()
			        self.init(token: token, office: office)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsOptionalLazyFillParametersInstance_whenFillReadsLazilyBoundTokenOnlyIfAvailable() async throws {
		// `DefaultUserService` reads `token` only if available: the fill takes the wrapper optionally and reads its instance
		// through the optional, `Desk`’s beneath `Desk` and `Root`’s wrapped `token` beside it.
		try await expectFill(
			feature: Self.lazyRouteFeature(),
			fulfillers: [Self.lazyRouteOnlyIfAvailableFulfiller],
			root: Self.lazyRouteRoot,
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
			            .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
			        }
			        func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>?) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
			            .init(userService: {
			                let userService: any UserService = DefaultUserService(token: token?.instance)
			                return userService
			            })
			        }
			        let token = Token()
			        func __safeDI_office() -> Office {
			            _ = Office.__safeDI_Office_B2DE8228FC9538C0.self // \(Self.moduleInfoComment)
			            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
			                .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>({ token })) })
			            }
			            return Office(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
			        }
			        let office: Office = __safeDI_office()
			        self.init(token: token, office: office)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_wrapsCallersTokenForFill_whenFulfillerIsDeclaredInAnotherModule() async throws {
		// `DefaultUserService` is declared in `Services`, beneath `App`, which fills the place: what the fill reads is read
		// from the fulfiller’s declaration in `Services`’ `.safedi`.
		try await expectFill(
			feature: Self.lazyRouteFeature(),
			fulfillers: [Self.lazyRouteFulfiller],
			root: Self.lazyRouteRoot,
			fulfillersModule: "Services",
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif
			#if canImport(Services)
			import Services
			#endif

			extension Root {
			    public init() {
			        func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
			            .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
			        }
			        func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
			            .init(userService: {
			                let userService: any UserService = DefaultUserService(token: token.instance)
			                return userService
			            })
			        }
			        let token = Token()
			        func __safeDI_office() -> Office {
			            _ = Office.__safeDI_Office_B2DE8228FC9538C0.self // \(Self.moduleInfoComment)
			            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
			                .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>({ token })) })
			            }
			            return Office(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
			        }
			        let office: Office = __safeDI_office()
			        self.init(token: token, office: office)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_instantiatesDesksTokenWhenModelIsBuilt_whenDeskHoldsModelInInstantiator() async throws {
		// `Desk` holds `Model` in an instantiator: inline reads `Desk`’s lazy `token` only when `modelBuilder` builds a
		// `Model`, never when `Desk` is built. `Desk`’s route hands the fill the wrapper, whose instance the fill reads where
		// it builds `userService`, so a `Root()` holds a `Desk` whose `token` is not instantiated yet, as inline’s does.
		try await expectFill(
			feature: Self.lazyRouteFeature(deskModel: "modelBuilder: Instantiator<Model>"),
			fulfillers: [Self.lazyRouteFulfiller],
			root: Self.lazyRouteRoot,
			probes: [
				DifferentialValueProbe("Root()"),
				DifferentialValueProbe("Root().office.desk.modelBuilder.instantiate()"),
			],
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
			            .init(modelBuilder: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
			        }
			        func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
			            .init(userService: {
			                let userService: any UserService = DefaultUserService(token: token.instance)
			                return userService
			            })
			        }
			        let token = Token()
			        func __safeDI_office() -> Office {
			            _ = Office.__safeDI_Office_B139FC6CC46F99FE.self // \(Self.moduleInfoComment)
			            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
			                .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>({ token })) })
			            }
			            return Office(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
			        }
			        let office: Office = __safeDI_office()
			        self.init(token: token, office: office)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilForOptionalLazyFillParameter_whenCallerDeclaresNoToken() async throws {
		// `DefaultUserService` reads `token` only if available and `Root` declares none: inline passes `nil` beside `Desk`,
		// so the root dispatcher does, and `Desk`’s route hands its wrapper, whose instance the fill reads through the optional.
		try await expectFill(
			feature: Self.lazyRouteFeature(),
			fulfillers: [Self.lazyRouteOnlyIfAvailableFulfiller],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let office: Office"]),
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
			            .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
			        }
			        func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>?) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
			            .init(userService: {
			                let userService: any UserService = DefaultUserService(token: token?.instance)
			                return userService
			            })
			        }
			        func __safeDI_office() -> Office {
			            _ = Office.__safeDI_Office_B2DE8228FC9538C0.self // \(Self.moduleInfoComment)
			            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
			                .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: nil) })
			            }
			            return Office(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
			        }
			        let office: Office = __safeDI_office()
			        self.init(office: office)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasFromOptionalLazyFillParameter_whenFillRenamesTokenOnlyIfAvailable() async throws {
		// `DefaultUserService` renames `token` only if available: the alias reads the instance through the optional wrapper
		// the fill takes, `Desk`’s beneath it and `Root`’s value beside it.
		try await expectFill(
			feature: Self.lazyRouteFeature(),
			fulfillers: [SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: [#"@Received(fulfilledByDependencyNamed: "token", ofType: Token.self, onlyIfAvailable: true) let renamed: Token?"#])],
			root: Self.lazyRouteRoot,
			expectedApp: """
				#if canImport(Feature)
				import Feature
				#endif

				extension Root {
				    public init() {
				        let token = Token()
				        func __safeDI_office() -> Office {
				            _ = Office.__safeDI_Office_B2DE8228FC9538C0.self // \(Self.moduleInfoComment)
				            func __safeDI_userServiceBuilder_Office_Model_Scope_userService(token: LazilyInstantiated<Token>?) -> any UserService {
				                func __safeDI_userService() -> DefaultUserService {
				                    let renamed: Token? = token?.instance // Declared as DefaultUserService.renamed
				                    return DefaultUserService(renamed: renamed)
				                }
				                let userService: any UserService = __safeDI_userService()
				                return userService
				            }
				            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
				                .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>({ token })) })
				            }
				            func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
				                .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
				            }
				            func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>?) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
				                .init(userService: { __safeDI_userServiceBuilder_Office_Model_Scope_userService(token: token) })
				            }
				            return Office(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
				        }
				        let office: Office = __safeDI_office()
				        self.init(token: token, office: office)
				    }
				}
				""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesOptionalLazyFillParametersInstanceToCycle_whenLoopInFillDeclaresTokenAgain() async throws {
		// `DefaultUserService` builds a loop of instantiators, `LoopA` reading `token` only if available and `LoopB`
		// declaring its own before it builds `LoopA` again: the function the loop closes on takes `token`, and its first call,
		// in the fill, hands it the instance of the wrapper the fill takes optionally.
		try await expectFill(
			feature: Self.lazyRouteFeature(),
			fulfillers: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Instantiated let loopABuilder: Instantiator<LoopA>"]),
				seamFixtureType(named: "LoopA", declarations: ["@Received(onlyIfAvailable: true) let token: Token?", "@Instantiated let loopBBuilder: Instantiator<LoopB>"]),
				seamFixtureType(named: "LoopB", declarations: ["@Instantiated let token: Token", "@Instantiated let loopABuilder: Instantiator<LoopA>"]),
			],
			root: Self.lazyRouteRoot,
			probes: [
				DifferentialValueProbe("Root()"),
				DifferentialValueProbe("(Root().office.model.userService as! DefaultUserService).loopABuilder.instantiate()"),
				DifferentialValueProbe("(Root().office.desk.model.userService as! DefaultUserService).loopABuilder.instantiate()"),
			],
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        let token = Token()
			        func __safeDI_office() -> Office {
			            _ = Office.__safeDI_Office_B2DE8228FC9538C0.self // \(Self.moduleInfoComment)
			            func __safeDI_userServiceBuilder_Office_Model_Scope_userService(token: LazilyInstantiated<Token>?) -> any UserService {
			                func __safeDI_userService() -> DefaultUserService {
			                    func __safeDI_loopABuilder(token: Token?) -> LoopA {
			                        func __safeDI_loopBBuilder() -> LoopB {
			                            let token = Token()
			                            let loopABuilder = Instantiator<LoopA> {
			                                __safeDI_loopABuilder(token: token)
			                            }
			                            return LoopB(token: token, loopABuilder: loopABuilder)
			                        }
			                        let loopBBuilder = Instantiator<LoopB>(__safeDI_loopBBuilder)
			                        return LoopA(token: token, loopBBuilder: loopBBuilder)
			                    }
			                    let loopABuilder = Instantiator<LoopA> {
			                        __safeDI_loopABuilder(token: token?.instance)
			                    }
			                    return DefaultUserService(loopABuilder: loopABuilder)
			                }
			                let userService: any UserService = __safeDI_userService()
			                return userService
			            }
			            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
			                .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>({ token })) })
			            }
			            func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
			                .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
			            }
			            func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>?) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
			                .init(userService: { __safeDI_userServiceBuilder_Office_Model_Scope_userService(token: token) })
			            }
			            return Office(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
			        }
			        let office: Office = __safeDI_office()
			        self.init(token: token, office: office)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_wrapsCallersOptionalToken_whenCallingSeamTakesTokenOnlyIfAvailable() async throws {
		// `Screen`, a seam of `App` that calls `Office`, receives `token` only if available, so its generated initializer takes
		// `token: Token?`, which the root dispatcher maps into the wrapper the fill takes.
		try await expectFill(
			feature: Self.lazyRouteFeature(),
			fulfillers: [Self.lazyRouteOnlyIfAvailableFulfiller],
			root: seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Received(onlyIfAvailable: true) let token: Token?", "@Instantiated let office: Office"])
				+ "\n\n"
				+ seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let token: Token", "@Instantiated let screen: Screen"]),
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        let token = Token()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_029593DA1BB2FBD5.self
			            return Screen(__safeDI_token: token)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(token: token, screen: screen)
			    }
			}

			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_token token: Token?) {
			        @inline(never) func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
			            .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
			        }
			        @inline(never) func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>?) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
			            .init(userService: {
			                let userService: any UserService = DefaultUserService(token: token?.instance)
			                return userService
			            })
			        }
			        @inline(never) func __safeDI_office() -> Office {
			            _ = Office.__safeDI_Office_B2DE8228FC9538C0.self // \(Self.moduleInfoComment)
			            @inline(never) func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
			                .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: token.map { value in LazilyInstantiated<Token>({ value }) }) })
			            }
			            return Office(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
			        }
			        let office: Office = __safeDI_office()
			        self.init(token: token, office: office)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_029593DA1BB2FBD5 {}
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesRequiredWrapper_whenSeamCallInsideOptionalReaderRequiresToken() async throws {
		// `DefaultUserService` reads `token` only if available, but builds `Panel`, a seam whose place `DefaultGadget` fills
		// requiring `token`, which the fill hands it from its own scope: the fill's tree requires `token`, so the fill takes
		// the wrapper required, as inline reads a value on every route.
		try await expectFill(
			feature: Self.lazyRouteFeature() + [
				"public protocol Gadget {}",
				seamFixtureType(named: "Panel", isSeam: true, declarations: ["@Instantiated let gadget: any Gadget"]),
			],
			fulfillers: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received(onlyIfAvailable: true) let token: Token?", "@Instantiated let panel: Panel"]),
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: ["@Received let token: Token"]),
			],
			root: Self.lazyRouteRoot,
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        let token = Token()
			        func __safeDI_office() -> Office {
			            _ = Office.__safeDI_Office_B2DE8228FC9538C0.self // \(Self.moduleInfoComment)
			            func __safeDI_userServiceBuilder_Office_Model_Scope_userService(token: LazilyInstantiated<Token>) -> any UserService {
			                func __safeDI_userService() -> DefaultUserService {
			                    func __safeDI_panel() -> Panel {
			                        _ = Panel.__safeDI_Panel_9CC66A47349ADC17.self // \(Self.moduleInfoComment)
			                        func __safeDI_gadgetBuilder_Panel() -> Panel.__safeDI_GadgetCarrier<any Gadget> {
			                            .init(gadget: {
			                                let gadget: any Gadget = DefaultGadget(token: token.instance)
			                                return gadget
			                            })
			                        }
			                        return Panel(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Panel())
			                    }
			                    let panel: Panel = __safeDI_panel()
			                    return DefaultUserService(token: token.instance, panel: panel)
			                }
			                let userService: any UserService = __safeDI_userService()
			                return userService
			            }
			            func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
			                .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>({ token })) })
			            }
			            func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
			                .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
			            }
			            func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
			                .init(userService: { __safeDI_userServiceBuilder_Office_Model_Scope_userService(token: token) })
			            }
			            return Office(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
			        }
			        let office: Office = __safeDI_office()
			        self.init(token: token, office: office)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_wrapsCallersOptionalToken_whenCallerForwardsTokenOptionally() async throws {
		// `Screen`, the caller, forwards `token: Token?`, which the fill reads only if available: the root dispatcher wraps
		// the value where there is one, so the fill reads the caller’s `token` beside `Desk` and `Desk`’s instance beneath it.
		try await expectFill(
			feature: Self.lazyRouteFeature(),
			fulfillers: [Self.lazyRouteOnlyIfAvailableFulfiller],
			root: seamFixtureType(named: "Screen", declarations: ["@Forwarded let token: Token?", "@Instantiated let office: Office"])
				+ "\n\n"
				+ seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let screenBuilder: Instantiator<Screen>"]),
			probes: [
				DifferentialValueProbe("Root().screenBuilder.instantiate(nil)"),
				DifferentialValueProbe("Root().screenBuilder.instantiate(Token())"),
			],
			expectedApp: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_userServiceBuilder_Office_Desk_Scope() -> Office.__safeDI_UserServiceCarrier_Desk<any UserService> {
			            .init(model: { values_token in __safeDI_userServiceBuilder_Office_Model_Scope(token: values_token) })
			        }
			        func __safeDI_userServiceBuilder_Office_Model_Scope(token: LazilyInstantiated<Token>?) -> Office.__safeDI_UserServiceCarrier_Model<any UserService> {
			            .init(userService: {
			                let userService: any UserService = DefaultUserService(token: token?.instance)
			                return userService
			            })
			        }
			        func __safeDI_screenBuilder(token: Token?) -> Screen {
			            func __safeDI_office() -> Office {
			                _ = Office.__safeDI_Office_B2DE8228FC9538C0.self // \(Self.moduleInfoComment)
			                func __safeDI_userServiceBuilder_Office() -> Office.__safeDI_UserServiceCarrier<any UserService> {
			                    .init(desk: __safeDI_userServiceBuilder_Office_Desk_Scope(), model: { values_desk in __safeDI_userServiceBuilder_Office_Model_Scope(token: token.map { value in LazilyInstantiated<Token>({ value }) }) })
			                }
			                return Office(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Office())
			            }
			            let office: Office = __safeDI_office()
			            return Screen(token: token, office: office)
			        }
			        let screenBuilder = Instantiator<Screen> {
			            __safeDI_screenBuilder(token: $0)
			        }
			        self.init(screenBuilder: screenBuilder)
			    }
			}
			""",
		)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Office`, a seam, builds `Model`, whose `userService` is a place, inside `Desk`, which binds `token` as `deskToken`,
	/// and beside it, where no type of `Office`’s tree binds `token`; `Desk` holds `Model` as `deskModel` declares it, and
	/// `Office` builds `desk` first when `deskFirst`.
	private static func lazyRouteFeature(deskToken: String = "LazilyInstantiated<Token>", deskModel: String = "model: Model", deskFirst: Bool = true) -> [String] {
		let officeDeclarations = ["@Instantiated let desk: Desk", "@Instantiated let model: Model"]
		return [
			"public protocol UserService {}",
			seamFixtureType(named: "Token", isFinalClass: true, declarations: [], conformances: ", Sendable"),
			seamFixtureType(named: "Model", declarations: ["@Instantiated let userService: any UserService"]),
			seamFixtureType(named: "Desk", declarations: ["@Instantiated let token: \(deskToken)", "@Instantiated let \(deskModel)"]),
			seamFixtureType(named: "Office", isSeam: true, declarations: deskFirst ? officeDeclarations : officeDeclarations.reversed()),
		]
	}

	/// The fill of `lazyRouteFeature`’s place, which reads `token: Token`.
	private static let lazyRouteFulfiller = SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received let token: Token"])

	/// The fill of `lazyRouteFeature`’s place, which reads `token` only if available.
	private static let lazyRouteOnlyIfAvailableFulfiller = SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultUserService", fulfilling: "UserService", declarations: ["@Received(onlyIfAvailable: true) let token: Token?"])

	/// The caller of `lazyRouteFeature`’s seam, which holds a plain `token` above the call.
	private static let lazyRouteRoot = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let token: Token", "@Instantiated let office: Office"])

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
	private static let moduleInfoComment = "If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes."

	/// Generates `feature`, whose seam `Service` (or `Home`) holds a place `App` fills with `fulfillers`, and `App`'s
	/// `root`, through `integration`; expects `App`'s file holding `Root`'s initializer to equal `expectedApp`, and the
	/// values `Root` builds to equal those of the same graph built with `fulfillers` in `Feature`, where every tree is built
	/// inline. `fulfillers` are declared in `App`, or in a module of that name between `Feature` and `App` when
	/// `fulfillersModule` names one.
	private mutating func expectFill(
		feature: [String],
		fulfillers: [String],
		root: String,
		integration: MultiModuleIntegration = .moduleInfo,
		fulfillersModule: String? = nil,
		probes: [DifferentialValueProbe] = [DifferentialValueProbe("Root()")],
		expectedApp: String,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let modules = if let fulfillersModule {
			[
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature),
				ModuleFixture(name: fulfillersModule, packageName: "Other", swiftFileContent: fulfillers.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: ["import Feature\nimport \(fulfillersModule)\n\n" + root], dependencies: ["Feature", fulfillersModule]),
			]
		} else {
			SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [root])
		}
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: integration, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles[integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift"] == generatedFileHeader + expectedApp, sourceLocation: sourceLocation)
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
