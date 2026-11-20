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

/// The internal mock of a type that generates its dependency tree takes, for each hole type whose places it builds by value
/// in plain code, a closure that takes nothing, which the builder function of each type that instantiates a place calls
/// once per build, as the type's own tree calls the builder its initializer takes, in place of a value per place.
struct SafeDIToolSeamOwnMockBuilderTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – a builder per hole type

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsBuilderOncePerBuildOfHolder_whenPlaceIsBeneathInstantiator() async throws {
		// Each `Profile` the instantiator builds calls the builder, as the seam's own tree does.
		let modules = Self.serviceModule(serviceDeclarations: ["@Instantiated public let profileBuilder: Instantiator<Profile>"], probes: [
			Self.probe(named: "profiles", building: """
			var profiles: [Profile]? = [service.profileBuilder.instantiate(), service.profileBuilder.instantiate()]
			let whileHeld = LiveUserService.alive - aliveBefore
			let distinct = profiles?[0].userService !== profiles?[1].userService
			profiles = nil
			return withExtendedLifetime(service) { "while held \\(whileHeld), distinct \\(distinct), after \\(LiveUserService.alive - aliveBefore)" }
			"""),
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Service {
		    nonisolated public enum SafeDIScope_UserService {
		        nonisolated public struct profileBuilder_Values {}

		        nonisolated public enum Profile_Scope {
		            nonisolated public struct userService_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let userService: (userService_Values) -> __safeDI_Built

		                public init(userService: @escaping (userService_Values) -> __safeDI_Built) {
		                    self.userService = userService
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.userService = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let profileBuilder: (profileBuilder_Values) -> SafeDIScope_UserService.Profile_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(profileBuilder: @escaping (profileBuilder_Values) -> SafeDIScope_UserService.Profile_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.profileBuilder = profileBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.profileBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(userServiceBuilder: @escaping () -> any UserService) {
		        self.init(__safeDI_userServiceBuilder: .init(__safeDI_noScope: userServiceBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_userServiceBuilder: SafeDIScope_UserService.__safeDI_Builder<any UserService>) {
		        let __safeDI_userServiceBuilder_profileBuilder = __safeDI_userServiceBuilder.profileBuilder(SafeDIScope_UserService.profileBuilder_Values())
		        func __safeDI_profileBuilder() -> Profile {
		            let userService: any UserService = __safeDI_userServiceBuilder_profileBuilder.userService(SafeDIScope_UserService.Profile_Scope.userService_Values())
		            return Profile(userService: userService)
		        }
		        let profileBuilder = Instantiator<Profile>(__safeDI_profileBuilder)
		        self.init(profileBuilder: profileBuilder)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_DAEE219B0D380A33 {}
		}

		#if DEBUG
		extension Service {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            profileBuilder: ((any UserService) -> Profile)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                profileBuilder: profileBuilder
		            )
		        }

		        var profileBuilder: ((any UserService) -> Profile)? { __safeDI_storage.profileBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                profileBuilder: ((any UserService) -> Profile)?
		            ) {
		                self.profileBuilder = profileBuilder
		            }

		            let profileBuilder: ((any UserService) -> Profile)?
		        }
		    }

		    static func mock(
		        userServiceBuilder: @escaping () -> any UserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        func __safeDI_profileBuilder() -> Profile {
		            let userService: any UserService = userServiceBuilder()
		            return if let safeDIBuilder = safeDIOverrides.profileBuilder { safeDIBuilder(userService) } else { Profile(userService: userService) }
		        }
		        let profileBuilder = Instantiator<Profile>(__safeDI_profileBuilder)
		        return Service(profileBuilder: profileBuilder)
		    }
		}
		#endif
		"""])
		let description = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe("referenceProfiles()"), DifferentialValueProbe("mockProfiles()")], filesToDelete: &filesToDelete)
		if compileVerificationIsEnabled {
			// The seam's own tree: two values while both profiles live, none once they are gone. The base's mock shares its one
			// flat value: while held 1, distinct false, after 1.
			#expect(description == """
			probe referenceProfiles()
			String "while held 2, distinct true, after 0"
			probe mockProfiles()
			String "while held 2, distinct true, after 0"

			""")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOneBuilderForTwoPlacesOfOneHoleType_whenPlacesHaveTwoLabels() async throws {
		// `Profile`'s `userService` and `Settings`' `service` are one hole type: one builder, called once for each.
		let modules = Self.serviceModule(serviceDeclarations: ["@Instantiated public let profile: Profile", "@Instantiated public let settings: Settings"], probes: [
			Self.probe(named: "places", building: """
			let distinct = service.profile.userService !== service.settings.service
			return withExtendedLifetime(service) { "alive \\(LiveUserService.alive - aliveBefore), distinct \\(distinct)" }
			"""),
		])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Service {
		    nonisolated public enum SafeDIScope_UserService {
		        nonisolated public struct profile_Values {}

		        nonisolated public struct settings_Values {
		            public let profile: Profile
		        }

		        nonisolated public enum Profile_Scope {
		            nonisolated public struct userService_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let userService: (userService_Values) -> __safeDI_Built

		                public init(userService: @escaping (userService_Values) -> __safeDI_Built) {
		                    self.userService = userService
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.userService = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        nonisolated public enum Settings_Scope {
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
		            public let profile: (profile_Values) -> SafeDIScope_UserService.Profile_Scope.__safeDI_Builder<__safeDI_Built>
		            public let settings: (settings_Values) -> SafeDIScope_UserService.Settings_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(profile: @escaping (profile_Values) -> SafeDIScope_UserService.Profile_Scope.__safeDI_Builder<__safeDI_Built>, settings: @escaping (settings_Values) -> SafeDIScope_UserService.Settings_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.profile = profile
		                self.settings = settings
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.profile = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.settings = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(userServiceBuilder: @escaping () -> any UserService) {
		        self.init(__safeDI_userServiceBuilder: .init(__safeDI_noScope: userServiceBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_userServiceBuilder: SafeDIScope_UserService.__safeDI_Builder<any UserService>) {
		        let __safeDI_userServiceBuilder_profile = __safeDI_userServiceBuilder.profile(SafeDIScope_UserService.profile_Values())
		        func __safeDI_profile() -> Profile {
		            let userService: any UserService = __safeDI_userServiceBuilder_profile.userService(SafeDIScope_UserService.Profile_Scope.userService_Values())
		            return Profile(userService: userService)
		        }
		        let profile: Profile = __safeDI_profile()
		        let __safeDI_userServiceBuilder_settings = __safeDI_userServiceBuilder.settings(SafeDIScope_UserService.settings_Values(profile: profile))
		        func __safeDI_settings() -> Settings {
		            let service: any UserService = __safeDI_userServiceBuilder_settings.service(SafeDIScope_UserService.Settings_Scope.service_Values())
		            return Settings(service: service)
		        }
		        let settings: Settings = __safeDI_settings()
		        self.init(profile: profile, settings: settings)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_C3EEAD236AD18278 {}
		}

		#if DEBUG
		extension Service {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            profile: ((any UserService) -> Profile)? = nil,
		            settings: ((any UserService) -> Settings)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                profile: profile,
		                settings: settings
		            )
		        }

		        var profile: ((any UserService) -> Profile)? { __safeDI_storage.profile }
		        var settings: ((any UserService) -> Settings)? { __safeDI_storage.settings }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                profile: ((any UserService) -> Profile)?,
		                settings: ((any UserService) -> Settings)?
		            ) {
		                self.profile = profile
		                self.settings = settings
		            }

		            let profile: ((any UserService) -> Profile)?
		            let settings: ((any UserService) -> Settings)?
		        }
		    }

		    static func mock(
		        userServiceBuilder: @escaping () -> any UserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        func __safeDI_profile() -> Profile {
		            let userService: any UserService = userServiceBuilder()
		            return if let safeDIBuilder = safeDIOverrides.profile { safeDIBuilder(userService) } else { Profile(userService: userService) }
		        }
		        let profile: Profile = __safeDI_profile()
		        func __safeDI_settings() -> Settings {
		            let service: any UserService = userServiceBuilder()
		            return if let safeDIBuilder = safeDIOverrides.settings { safeDIBuilder(service) } else { Settings(service: service) }
		        }
		        let settings: Settings = __safeDI_settings()
		        return Service(profile: profile, settings: settings)
		    }
		}
		#endif
		"""])
		let description = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe("referencePlaces()"), DifferentialValueProbe("mockPlaces()")], filesToDelete: &filesToDelete)
		if compileVerificationIsEnabled {
			#expect(description == """
			probe referencePlaces()
			String "alive 2, distinct true"
			probe mockPlaces()
			String "alive 2, distinct true"

			""")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesBuilderForPlaceOfInnerSeamItBuildsInline_whenInnerSeamIsInAnotherModule() async throws {
		// `Inner`, a seam of module `Core`, holds the place; `Service` builds it inline in its mock, which takes the builder.
		// `Service`'s own initializers take `Inner`'s enum, which the seam's tree hands up, and are unchanged.
		let modules = [
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContent: [
				"""
				import SafeDI

				public protocol UserService: AnyObject {}

				@Instantiable(generateDependencyTree: true)
				public final class Inner: Instantiable {
				    public init(userService: any UserService) {
				        self.userService = userService
				    }

				    @Instantiated public let userService: any UserService
				}
				""",
			]),
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContent: [
				"""
				import Core
				import SafeDI

				@Instantiable(generateDependencyTree: true, generateMock: true)
				public final class Service: Instantiable {
				    public init(inner: Inner) {
				        self.inner = inner
				    }

				    @Instantiated public let inner: Inner
				}
				""",
			], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Inner {
		    nonisolated public enum SafeDIScope_UserService {
		        nonisolated public struct userService_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let userService: (userService_Values) -> __safeDI_Built

		            public init(userService: @escaping (userService_Values) -> __safeDI_Built) {
		                self.userService = userService
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.userService = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_userServiceBuilder: SafeDIScope_UserService.__safeDI_Builder<any UserService>) {
		        let userService: any UserService = __safeDI_userServiceBuilder.userService(SafeDIScope_UserService.userService_Values())
		        self.init(userService: userService)
		    }
		}

		extension Inner {
		    public enum __safeDI_Inner_30B081DD2CB1DAD9 {}
		}
		"""])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Service {
		    nonisolated public enum SafeDIScope_UserService {
		        nonisolated public struct inner_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let inner: (inner_Values) -> Inner.SafeDIScope_UserService.__safeDI_Builder<__safeDI_Built>

		            public init(inner: @escaping (inner_Values) -> Inner.SafeDIScope_UserService.__safeDI_Builder<__safeDI_Built>) {
		                self.inner = inner
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.inner = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_userServiceBuilder: SafeDIScope_UserService.__safeDI_Builder<any UserService>) {
		        func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_30B081DD2CB1DAD9.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Inner(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder.inner(SafeDIScope_UserService.inner_Values()))
		        }
		        let inner: Inner = __safeDI_inner()
		        self.init(inner: inner)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_DB8E5D9D7B267A9D {}
		}

		#if DEBUG
		extension Service {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            inner: ((any UserService) -> Inner)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                inner: inner
		            )
		        }

		        var inner: ((any UserService) -> Inner)? { __safeDI_storage.inner }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                inner: ((any UserService) -> Inner)?
		            ) {
		                self.inner = inner
		            }

		            let inner: ((any UserService) -> Inner)?
		        }
		    }

		    static func mock(
		        userServiceBuilder: @escaping () -> any UserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        func __safeDI_inner() -> Inner {
		            let userService: any UserService = userServiceBuilder()
		            return if let safeDIBuilder = safeDIOverrides.inner { safeDIBuilder(userService) } else { Inner(userService: userService) }
		        }
		        let inner: Inner = __safeDI_inner()
		        return Service(inner: inner)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_labelsBuilderByFulfillingAndReturnedTypes_whenPlaceIsErasedToAnotherType() async throws {
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContent: [
				"""
				import SafeDI

				public protocol UserService: AnyObject {}

				public struct AnyUserService {
				    public init(_ userService: any UserService) {
				        self.userService = userService
				    }

				    public let userService: any UserService
				}

				@Instantiable
				public final class Profile: Instantiable {
				    public init(userService: AnyUserService) {
				        self.userService = userService
				    }

				    @Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) public let userService: AnyUserService
				}

				@Instantiable(generateDependencyTree: true, generateMock: true)
				public final class Service: Instantiable {
				    public init(profile: Profile) {
				        self.profile = profile
				    }

				    @Instantiated public let profile: Profile
				}
				""",
			]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Service {
		    nonisolated public enum SafeDIScope_DefaultUserService_AnyUserService {
		        nonisolated public struct profile_Values {}

		        nonisolated public enum Profile_Scope {
		            nonisolated public struct userService_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let userService: (userService_Values) -> __safeDI_Built

		                public init(userService: @escaping (userService_Values) -> __safeDI_Built) {
		                    self.userService = userService
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.userService = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let profile: (profile_Values) -> SafeDIScope_DefaultUserService_AnyUserService.Profile_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(profile: @escaping (profile_Values) -> SafeDIScope_DefaultUserService_AnyUserService.Profile_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.profile = profile
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.profile = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_defaultUserService_AnyUserServiceBuilder: SafeDIScope_DefaultUserService_AnyUserService.__safeDI_Builder<AnyUserService>) {
		        let __safeDI_defaultUserService_AnyUserServiceBuilder_profile = __safeDI_defaultUserService_AnyUserServiceBuilder.profile(SafeDIScope_DefaultUserService_AnyUserService.profile_Values())
		        func __safeDI_profile() -> Profile {
		            let userService: AnyUserService = __safeDI_defaultUserService_AnyUserServiceBuilder_profile.userService(SafeDIScope_DefaultUserService_AnyUserService.Profile_Scope.userService_Values())
		            return Profile(userService: userService)
		        }
		        let profile: Profile = __safeDI_profile()
		        self.init(profile: profile)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_142FC66B1EEE39D0 {}
		}

		#if DEBUG
		extension Service {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            profile: ((AnyUserService) -> Profile)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                profile: profile
		            )
		        }

		        var profile: ((AnyUserService) -> Profile)? { __safeDI_storage.profile }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                profile: ((AnyUserService) -> Profile)?
		            ) {
		                self.profile = profile
		            }

		            let profile: ((AnyUserService) -> Profile)?
		        }
		    }

		    static func mock(
		        defaultUserService_AnyUserServiceBuilder: @escaping () -> AnyUserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        func __safeDI_profile() -> Profile {
		            let userService: AnyUserService = defaultUserService_AnyUserServiceBuilder()
		            return if let safeDIBuilder = safeDIOverrides.profile { safeDIBuilder(userService) } else { Profile(userService: userService) }
		        }
		        let profile: Profile = __safeDI_profile()
		        return Service(profile: profile)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsPlaceInsideEachHoldersFunction_whenTwoSiblingsInstantiatePlaceUnderOneLabel() async throws {
		let modules = Self.serviceModule(serviceDeclarations: ["@Instantiated public let settings: Settings", "@Instantiated public let account: Account"])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Service {
		    nonisolated public enum SafeDIScope_UserService {
		        nonisolated public struct settings_Values {}

		        nonisolated public struct account_Values {
		            public let settings: Settings
		        }

		        nonisolated public enum Settings_Scope {
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

		        nonisolated public enum Account_Scope {
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
		            public let settings: (settings_Values) -> SafeDIScope_UserService.Settings_Scope.__safeDI_Builder<__safeDI_Built>
		            public let account: (account_Values) -> SafeDIScope_UserService.Account_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(settings: @escaping (settings_Values) -> SafeDIScope_UserService.Settings_Scope.__safeDI_Builder<__safeDI_Built>, account: @escaping (account_Values) -> SafeDIScope_UserService.Account_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.settings = settings
		                self.account = account
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.settings = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.account = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(userServiceBuilder: @escaping () -> any UserService) {
		        self.init(__safeDI_userServiceBuilder: .init(__safeDI_noScope: userServiceBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_userServiceBuilder: SafeDIScope_UserService.__safeDI_Builder<any UserService>) {
		        let __safeDI_userServiceBuilder_settings = __safeDI_userServiceBuilder.settings(SafeDIScope_UserService.settings_Values())
		        func __safeDI_settings() -> Settings {
		            let service: any UserService = __safeDI_userServiceBuilder_settings.service(SafeDIScope_UserService.Settings_Scope.service_Values())
		            return Settings(service: service)
		        }
		        let settings: Settings = __safeDI_settings()
		        let __safeDI_userServiceBuilder_account = __safeDI_userServiceBuilder.account(SafeDIScope_UserService.account_Values(settings: settings))
		        func __safeDI_account() -> Account {
		            let service: any UserService = __safeDI_userServiceBuilder_account.service(SafeDIScope_UserService.Account_Scope.service_Values())
		            return Account(service: service)
		        }
		        let account: Account = __safeDI_account()
		        self.init(settings: settings, account: account)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_51CFC5BE54D28FC0 {}
		}

		#if DEBUG
		extension Service {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            settings: ((any UserService) -> Settings)? = nil,
		            account: ((any UserService) -> Account)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                settings: settings,
		                account: account
		            )
		        }

		        var settings: ((any UserService) -> Settings)? { __safeDI_storage.settings }
		        var account: ((any UserService) -> Account)? { __safeDI_storage.account }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                settings: ((any UserService) -> Settings)?,
		                account: ((any UserService) -> Account)?
		            ) {
		                self.settings = settings
		                self.account = account
		            }

		            let settings: ((any UserService) -> Settings)?
		            let account: ((any UserService) -> Account)?
		        }
		    }

		    static func mock(
		        userServiceBuilder: @escaping () -> any UserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        func __safeDI_settings() -> Settings {
		            let service: any UserService = userServiceBuilder()
		            return if let safeDIBuilder = safeDIOverrides.settings { safeDIBuilder(service) } else { Settings(service: service) }
		        }
		        let settings: Settings = __safeDI_settings()
		        func __safeDI_account() -> Account {
		            let service: any UserService = userServiceBuilder()
		            return if let safeDIBuilder = safeDIOverrides.account { safeDIBuilder(service) } else { Account(service: service) }
		        }
		        let account: Account = __safeDI_account()
		        return Service(settings: settings, account: account)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsReceiverParameterAndHolderBuilderValue_whenPlaceSharesLabelWithReceiveThatStaysParameter() async throws {
		// `Settings` instantiates `service`, a place; `Reader` receives `service` of another type, which the mock takes as a
		// parameter: the receiver reads the parameter, the holder its own binding.
		let modules = Self.serviceModule(
			serviceDeclarations: ["@Instantiated public let settings: Settings", "@Instantiated public let reader: Reader"],
			extraDeclarations: [
				"""
				public final class Clock {
				    public init() {}
				}

				@Instantiable
				public final class Reader: Instantiable {
				    public init(service: Clock) {
				        self.service = service
				    }

				    @Received public let service: Clock
				}
				""",
			],
			probes: [
				"""
				func mockReceiverAndHolder() -> String {
				    let aliveBefore = LiveUserService.alive
				    let clock = Clock()
				    let service = Service.mock(service: clock, userServiceBuilder: { LiveUserService() })
				    return withExtendedLifetime(service) { "alive \\(LiveUserService.alive - aliveBefore), receiver holds argument \\(service.reader.service === clock)" }
				}
				""",
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Service {
		    nonisolated public enum SafeDIScope_UserService {
		        nonisolated public struct settings_Values {
		            public var service: Clock { __safeDI_service.instance }
		            public let reader: Reader
		            public let __safeDI_service: LazilyInstantiated<Clock>

		            init(service: LazilyInstantiated<Clock>, reader: Reader) {
		                __safeDI_service = service
		                self.reader = reader
		            }
		        }

		        nonisolated public enum Settings_Scope {
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
		            public let settings: (settings_Values) -> SafeDIScope_UserService.Settings_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(settings: @escaping (settings_Values) -> SafeDIScope_UserService.Settings_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.settings = settings
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.settings = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(service: Clock, userServiceBuilder: @escaping () -> any UserService) {
		        self.init(__safeDI_service: service, __safeDI_userServiceBuilder: .init(__safeDI_noScope: userServiceBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_service __safeDI_service_: @autoclosure @escaping () -> Clock, __safeDI_userServiceBuilder: SafeDIScope_UserService.__safeDI_Builder<any UserService>) {
		        let service = LazilyInstantiated<Clock>(__safeDI_service_)
		        let reader = Reader(service: service.instance)
		        let __safeDI_userServiceBuilder_settings = __safeDI_userServiceBuilder.settings(SafeDIScope_UserService.settings_Values(service: service, reader: reader))
		        func __safeDI_settings() -> Settings {
		            let service: any UserService = __safeDI_userServiceBuilder_settings.service(SafeDIScope_UserService.Settings_Scope.service_Values())
		            return Settings(service: service)
		        }
		        let settings: Settings = __safeDI_settings()
		        self.init(settings: settings, reader: reader)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_63925CB4A26D4D3E {}
		}

		#if DEBUG
		extension Service {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            settings: ((any UserService) -> Settings)? = nil,
		            reader: ((Clock) -> Reader)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                settings: settings,
		                reader: reader
		            )
		        }

		        var settings: ((any UserService) -> Settings)? { __safeDI_storage.settings }
		        var reader: ((Clock) -> Reader)? { __safeDI_storage.reader }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                settings: ((any UserService) -> Settings)?,
		                reader: ((Clock) -> Reader)?
		            ) {
		                self.settings = settings
		                self.reader = reader
		            }

		            let settings: ((any UserService) -> Settings)?
		            let reader: ((Clock) -> Reader)?
		        }
		    }

		    static func mock(
		        service: Clock,
		        userServiceBuilder: @escaping () -> any UserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        func __safeDI_settings() -> Settings {
		            let service: any UserService = userServiceBuilder()
		            return if let safeDIBuilder = safeDIOverrides.settings { safeDIBuilder(service) } else { Settings(service: service) }
		        }
		        let settings: Settings = __safeDI_settings()
		        let reader = if let safeDIBuilder = safeDIOverrides.reader { safeDIBuilder(service) } else { Reader(service: service) }
		        return Service(settings: settings, reader: reader)
		    }
		}
		#endif
		"""])
		let description = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe("mockReceiverAndHolder()")], filesToDelete: &filesToDelete)
		if compileVerificationIsEnabled {
			#expect(description == "probe mockReceiverAndHolder()\nString \"alive 1, receiver holds argument true\"\n")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsBuilderByNameApart_whenSeamsOwnPropertyIsLabeledLikeBuilder() async throws {
		// `Service` instantiates `userServiceBuilder`, whose binding would hide the builder `mock()` takes under that label.
		let modules = Self.serviceModule(serviceDeclarations: ["@Instantiated public let userServiceBuilder: Instantiator<Analytics>", "@Instantiated public let profile: Profile"])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Service {
		    nonisolated public enum SafeDIScope_UserService {
		        nonisolated public struct profile_Values {
		            public let userServiceBuilder: Instantiator<Analytics>
		        }

		        nonisolated public enum Profile_Scope {
		            nonisolated public struct userService_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let userService: (userService_Values) -> __safeDI_Built

		                public init(userService: @escaping (userService_Values) -> __safeDI_Built) {
		                    self.userService = userService
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.userService = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let profile: (profile_Values) -> SafeDIScope_UserService.Profile_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(profile: @escaping (profile_Values) -> SafeDIScope_UserService.Profile_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.profile = profile
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.profile = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(userServiceBuilder: @escaping () -> any UserService) {
		        self.init(__safeDI_userServiceBuilder: .init(__safeDI_noScope: userServiceBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_userServiceBuilder __safeDI_userServiceBuilder_: SafeDIScope_UserService.__safeDI_Builder<any UserService>) {
		        func __safeDI_userServiceBuilder() -> Analytics {
		            Analytics()
		        }
		        let userServiceBuilder = Instantiator<Analytics>(__safeDI_userServiceBuilder)
		        let __safeDI_userServiceBuilder_profile = __safeDI_userServiceBuilder_.profile(SafeDIScope_UserService.profile_Values(userServiceBuilder: userServiceBuilder))
		        func __safeDI_profile() -> Profile {
		            let userService: any UserService = __safeDI_userServiceBuilder_profile.userService(SafeDIScope_UserService.Profile_Scope.userService_Values())
		            return Profile(userService: userService)
		        }
		        let profile: Profile = __safeDI_profile()
		        self.init(userServiceBuilder: userServiceBuilder, profile: profile)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_F9356196B9207CE9 {}
		}

		#if DEBUG
		extension Service {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            userServiceBuilder: (() -> Analytics)? = nil,
		            profile: ((any UserService) -> Profile)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                userServiceBuilder: userServiceBuilder,
		                profile: profile
		            )
		        }

		        var userServiceBuilder: (() -> Analytics)? { __safeDI_storage.userServiceBuilder }
		        var profile: ((any UserService) -> Profile)? { __safeDI_storage.profile }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                userServiceBuilder: (() -> Analytics)?,
		                profile: ((any UserService) -> Profile)?
		            ) {
		                self.userServiceBuilder = userServiceBuilder
		                self.profile = profile
		            }

		            let userServiceBuilder: (() -> Analytics)?
		            let profile: ((any UserService) -> Profile)?
		        }
		    }

		    static func mock(
		        userServiceBuilder: @escaping () -> any UserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        let __safeDI_userServiceBuilder_ = userServiceBuilder
		        func __safeDI_userServiceBuilder() -> Analytics {
		            if let safeDIBuilder = safeDIOverrides.userServiceBuilder { safeDIBuilder() } else { Analytics() }
		        }
		        let userServiceBuilder = Instantiator<Analytics>(__safeDI_userServiceBuilder)
		        func __safeDI_profile() -> Profile {
		            let userService: any UserService = __safeDI_userServiceBuilder_()
		            return if let safeDIBuilder = safeDIOverrides.profile { safeDIBuilder(userService) } else { Profile(userService: userService) }
		        }
		        let profile: Profile = __safeDI_profile()
		        return Service(userServiceBuilder: userServiceBuilder, profile: profile)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsBuilderByNameApart_whenHolderDeclaresPropertyLabeledLikeBuilder() async throws {
		// `Badge` instantiates `userServiceBuilder` beside its place, so a call of the builder by its label inside `Badge`'s
		// function would name the local before its declaration.
		let modules = Self.serviceModule(
			serviceDeclarations: ["@Instantiated public let badge: Badge"],
			extraDeclarations: [
				"""
				@Instantiable
				public final class Badge: Instantiable {
				    public init(userService: any UserService, userServiceBuilder: Instantiator<Analytics>) {
				        self.userService = userService
				        self.userServiceBuilder = userServiceBuilder
				    }

				    @Instantiated public let userService: any UserService
				    @Instantiated public let userServiceBuilder: Instantiator<Analytics>
				}
				""",
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Service {
		    nonisolated public enum SafeDIScope_UserService {
		        nonisolated public struct badge_Values {}

		        nonisolated public enum Badge_Scope {
		            nonisolated public struct userService_Values {
		                public let userServiceBuilder: Instantiator<Analytics>
		            }

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let userService: (userService_Values) -> __safeDI_Built

		                public init(userService: @escaping (userService_Values) -> __safeDI_Built) {
		                    self.userService = userService
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.userService = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let badge: (badge_Values) -> SafeDIScope_UserService.Badge_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(badge: @escaping (badge_Values) -> SafeDIScope_UserService.Badge_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.badge = badge
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.badge = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(userServiceBuilder: @escaping () -> any UserService) {
		        self.init(__safeDI_userServiceBuilder: .init(__safeDI_noScope: userServiceBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_userServiceBuilder __safeDI_userServiceBuilder_: SafeDIScope_UserService.__safeDI_Builder<any UserService>) {
		        let __safeDI_userServiceBuilder_badge = __safeDI_userServiceBuilder_.badge(SafeDIScope_UserService.badge_Values())
		        func __safeDI_badge() -> Badge {
		            func __safeDI_userServiceBuilder() -> Analytics {
		                Analytics()
		            }
		            let userServiceBuilder = Instantiator<Analytics>(__safeDI_userServiceBuilder)
		            let userService: any UserService = __safeDI_userServiceBuilder_badge.userService(SafeDIScope_UserService.Badge_Scope.userService_Values(userServiceBuilder: userServiceBuilder))
		            return Badge(userService: userService, userServiceBuilder: userServiceBuilder)
		        }
		        let badge: Badge = __safeDI_badge()
		        self.init(badge: badge)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_207889A9A88D111F {}
		}

		#if DEBUG
		extension Service {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            badge: Badge.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                badge: badge
		            )
		        }

		        var badge: Badge.SafeDIMockConfiguration { __safeDI_storage.badge }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                badge: Badge.SafeDIMockConfiguration
		            ) {
		                self.badge = badge
		            }

		            let badge: Badge.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        userServiceBuilder: @escaping () -> any UserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        let __safeDI_userServiceBuilder_ = userServiceBuilder
		        func __safeDI_badge() -> Badge {
		            let userService: any UserService = __safeDI_userServiceBuilder_()
		            func __safeDI_userServiceBuilder() -> Analytics {
		                if let safeDIBuilder = safeDIOverrides.badge.userServiceBuilder { safeDIBuilder() } else { Analytics() }
		            }
		            let userServiceBuilder = Instantiator<Analytics>(__safeDI_userServiceBuilder)
		            return if let safeDIBuilder = safeDIOverrides.badge.safeDIBuilder { safeDIBuilder(userService, userServiceBuilder) } else { Badge(userService: userService, userServiceBuilder: userServiceBuilder) }
		        }
		        let badge: Badge = __safeDI_badge()
		        return Service(badge: badge)
		    }
		}
		#endif

		#if DEBUG
		extension Badge {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            userServiceBuilder: (() -> Analytics)? = nil,
		            _ safeDIBuilder: ((any UserService, Instantiator<Analytics>) -> Badge)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                userServiceBuilder: userServiceBuilder,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var userServiceBuilder: (() -> Analytics)? { __safeDI_storage.userServiceBuilder }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((any UserService, Instantiator<Analytics>) -> Badge)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                userServiceBuilder: (() -> Analytics)?,
		                safeDIBuilder: ((any UserService, Instantiator<Analytics>) -> Badge)?
		            ) {
		                self.userServiceBuilder = userServiceBuilder
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let userServiceBuilder: (() -> Analytics)?
		            let safeDIBuilder: ((any UserService, Instantiator<Analytics>) -> Badge)?
		        }
		    }
		}
		#endif

		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesBuilderLabelApart_whenSeamsInitializerTakesDefaultValuedParameterLabeledLikeBuilder() async throws {
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContent: [
				"""
				import SafeDI

				public protocol Analytics: AnyObject {}

				public final class AnalyticsBuilder: Sendable {
				    public static let shared = AnalyticsBuilder()
				}

				@Instantiable(generateDependencyTree: true, generateMock: true)
				public final class Service: Instantiable {
				    public init(analytics: any Analytics, analyticsBuilder: AnalyticsBuilder = .shared) {
				        self.analytics = analytics
				        self.analyticsBuilder = analyticsBuilder
				    }

				    @Instantiated public let analytics: any Analytics
				    public let analyticsBuilder: AnalyticsBuilder
				}
				""",
			]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Service {
		    nonisolated public enum SafeDIScope_Analytics {
		        nonisolated public struct analytics_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let analytics: (analytics_Values) -> __safeDI_Built

		            public init(analytics: @escaping (analytics_Values) -> __safeDI_Built) {
		                self.analytics = analytics
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.analytics = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_analyticsBuilder: SafeDIScope_Analytics.__safeDI_Builder<any Analytics>) {
		        let analytics: any Analytics = __safeDI_analyticsBuilder.analytics(SafeDIScope_Analytics.analytics_Values())
		        self.init(analytics: analytics)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_E07D8A52C6ED2A5E {}
		}

		#if DEBUG
		extension Service {
		    static func mock(
		        analyticsBuilder: AnalyticsBuilder = .shared,
		        analyticsBuilder_: @escaping () -> any Analytics
		    ) -> Service {
		        let analytics: any Analytics = analyticsBuilder_()
		        return Service(analytics: analytics, analyticsBuilder: analyticsBuilder)
		    }
		}
		#endif
		"""])
	}

	// MARK: Tests – a place the mock still takes a value for

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesValueForPlace_whenPlaceIsHeldLazily() async throws {
		let modules = Self.serviceModule(serviceDeclarations: ["@Instantiated public let userService: LazilyInstantiated<any UserService>"])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Service {
		    nonisolated public enum SafeDIScope_UserService {
		        nonisolated public struct userService_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let userService: (userService_Values) -> __safeDI_Built

		            public init(userService: @escaping (userService_Values) -> __safeDI_Built) {
		                self.userService = userService
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.userService = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(userServiceBuilder: @escaping () -> any UserService) {
		        self.init(__safeDI_userServiceBuilder: .init(__safeDI_noScope: userServiceBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_userServiceBuilder: SafeDIScope_UserService.__safeDI_Builder<any UserService>) {
		        func __safeDI_userService() -> any UserService {
		            __safeDI_userServiceBuilder.userService(SafeDIScope_UserService.userService_Values())
		        }
		        let userService = LazilyInstantiated<any UserService>(__safeDI_userService)
		        self.init(userService: userService)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_DE15AB8B7FF442DE {}
		}

		#if DEBUG
		extension Service {
		    static func mock(
		        userService: LazilyInstantiated<any UserService>
		    ) -> Service {
		        return Service(userService: userService)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesValueForPlace_whenPlaceIsBuiltInSendableFunction() async throws {
		let modules = Self.serviceModule(serviceDeclarations: ["@Instantiated public let profileBuilder: SendableInstantiator<SendableProfile>"], extraDeclarations: [Self.sendableProfile])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Service {
		    nonisolated public enum SafeDIScope_UserService {
		        nonisolated public enum SendableProfile_Scope {
		            nonisolated public struct userService_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let userService: (userService_Values) -> __safeDI_Built

		                public init(userService: @escaping (userService_Values) -> __safeDI_Built) {
		                    self.userService = userService
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.userService = { _ in __safeDI_builder() }
		                }
		            }
		        }
		    }

		    nonisolated public enum SafeDISendableScope_UserService {
		        nonisolated public struct profileBuilder_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let profileBuilder: @Sendable (profileBuilder_Values) -> SafeDIScope_UserService.SendableProfile_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(profileBuilder: @escaping @Sendable (profileBuilder_Values) -> SafeDIScope_UserService.SendableProfile_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.profileBuilder = profileBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		                self.profileBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(userServiceSendableBuilder: @escaping @Sendable () -> any UserService) {
		        self.init(__safeDI_userServiceSendableBuilder: .init(__safeDI_noScope: userServiceSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_userServiceSendableBuilder: SafeDISendableScope_UserService.__safeDI_Builder<any UserService>) {
		        @Sendable nonisolated func __safeDI_profileBuilder() -> SendableProfile {
		            let __safeDI_userServiceSendableBuilder_profileBuilder = __safeDI_userServiceSendableBuilder.profileBuilder(SafeDISendableScope_UserService.profileBuilder_Values())
		            let userService: any UserService = __safeDI_userServiceSendableBuilder_profileBuilder.userService(SafeDIScope_UserService.SendableProfile_Scope.userService_Values())
		            return SendableProfile(userService: userService)
		        }
		        let profileBuilder = SendableInstantiator<SendableProfile>(__safeDI_profileBuilder)
		        self.init(profileBuilder: profileBuilder)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_876B32F9C29D8A44 {}
		}

		#if DEBUG
		extension Service {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            profileBuilder: (@Sendable (any UserService) -> SendableProfile)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                profileBuilder: profileBuilder
		            )
		        }

		        var profileBuilder: (@Sendable (any UserService) -> SendableProfile)? { __safeDI_storage.profileBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                profileBuilder: (@Sendable (any UserService) -> SendableProfile)?
		            ) {
		                self.profileBuilder = profileBuilder
		            }

		            let profileBuilder: (@Sendable (any UserService) -> SendableProfile)?
		        }
		    }

		    static func mock(
		        userService: @autoclosure @escaping @Sendable () -> UserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        let __safeDI_userService = userService
		        let __safeDI_profileBuilder__safeDIBuilder = safeDIOverrides.profileBuilder
		        @Sendable func __safeDI_profileBuilder() -> SendableProfile {
		            let userService = __safeDI_userService()
		            return if let safeDIBuilder = __safeDI_profileBuilder__safeDIBuilder { safeDIBuilder(userService) } else { SendableProfile(userService: userService) }
		        }
		        let profileBuilder = SendableInstantiator<SendableProfile>(__safeDI_profileBuilder)
		        return Service(profileBuilder: profileBuilder)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesErasedInstantiatorsBuilderForPlace_whenPlaceIsErasedInstantiatorThatForwardsNothing() async throws {
		// An erased instantiator that forwards nothing is built from the builder, which each instantiation calls; the mock
		// takes the builder the seam's readable initializer takes, the erased instantiator's `Builder`.
		let modules = Self.serviceModule(serviceDeclarations: ["@Instantiated(fulfilledByType: \"DefaultUserService\") public let userServiceBuilder: ErasedInstantiator<(), any UserService>"])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Service {
		    nonisolated public enum SafeDIScope_DefaultUserService_UserService {
		        nonisolated public struct userServiceBuilder_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let userServiceBuilder: (userServiceBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

		            public init(userServiceBuilder: @escaping (userServiceBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.userServiceBuilder = userServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<(), __safeDI_Built>.Builder) {
		                self.userServiceBuilder = { _ in __safeDI_builder }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(defaultUserService_UserServiceBuilder: @escaping ErasedInstantiator<(), any UserService>.Builder) {
		        self.init(__safeDI_defaultUserService_UserServiceBuilder: .init(__safeDI_noScope: defaultUserService_UserServiceBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_defaultUserService_UserServiceBuilder: SafeDIScope_DefaultUserService_UserService.__safeDI_Builder<any UserService>) {
		        let userServiceBuilder = ErasedInstantiator<(), any UserService>(__safeDI_defaultUserService_UserServiceBuilder.userServiceBuilder(SafeDIScope_DefaultUserService_UserService.userServiceBuilder_Values()))
		        self.init(userServiceBuilder: userServiceBuilder)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_F31E2D27E1AA09DF {}
		}

		#if DEBUG
		extension Service {
		    static func mock(
		        defaultUserService_UserServiceBuilder: @escaping ErasedInstantiator<(), any UserService>.Builder
		    ) -> Service {
		        let userServiceBuilder = ErasedInstantiator<(), any UserService>(defaultUserService_UserServiceBuilder)
		        return Service(userServiceBuilder: userServiceBuilder)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_listsBuilderAmongReceivedParametersByLabel_whenMockTakesReceivedParametersOnEitherSideOfIt() async throws {
		// `Reader` receives `alarm` and `zone`, which the mock takes as parameters: the builder is listed between them, as an
		// internal mock lists a builder it passes up to another module's public mock among the received parameters.
		let modules = Self.serviceModule(
			serviceDeclarations: ["@Instantiated public let settings: Settings", "@Instantiated public let reader: Reader"],
			extraDeclarations: [
				"""
				public final class Clock {
				    public init() {}
				}

				@Instantiable
				public final class Reader: Instantiable {
				    public init(alarm: Clock, zone: Clock) {
				        self.alarm = alarm
				        self.zone = zone
				    }

				    @Received public let alarm: Clock
				    @Received public let zone: Clock
				}
				""",
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Service {
		    nonisolated public enum SafeDIScope_UserService {
		        nonisolated public struct settings_Values {
		            public var alarm: Clock { __safeDI_alarm.instance }
		            public var zone: Clock { __safeDI_zone.instance }
		            public let reader: Reader
		            public let __safeDI_alarm: LazilyInstantiated<Clock>
		            public let __safeDI_zone: LazilyInstantiated<Clock>

		            init(alarm: LazilyInstantiated<Clock>, zone: LazilyInstantiated<Clock>, reader: Reader) {
		                __safeDI_alarm = alarm
		                __safeDI_zone = zone
		                self.reader = reader
		            }
		        }

		        nonisolated public enum Settings_Scope {
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
		            public let settings: (settings_Values) -> SafeDIScope_UserService.Settings_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(settings: @escaping (settings_Values) -> SafeDIScope_UserService.Settings_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.settings = settings
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.settings = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(alarm: Clock, zone: Clock, userServiceBuilder: @escaping () -> any UserService) {
		        self.init(__safeDI_alarm: alarm, __safeDI_zone: zone, __safeDI_userServiceBuilder: .init(__safeDI_noScope: userServiceBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_alarm: @autoclosure @escaping () -> Clock, __safeDI_zone: @autoclosure @escaping () -> Clock, __safeDI_userServiceBuilder: SafeDIScope_UserService.__safeDI_Builder<any UserService>) {
		        let alarm = LazilyInstantiated<Clock>(__safeDI_alarm)
		        let zone = LazilyInstantiated<Clock>(__safeDI_zone)
		        let reader = Reader(alarm: alarm.instance, zone: zone.instance)
		        let __safeDI_userServiceBuilder_settings = __safeDI_userServiceBuilder.settings(SafeDIScope_UserService.settings_Values(alarm: alarm, zone: zone, reader: reader))
		        func __safeDI_settings() -> Settings {
		            let service: any UserService = __safeDI_userServiceBuilder_settings.service(SafeDIScope_UserService.Settings_Scope.service_Values())
		            return Settings(service: service)
		        }
		        let settings: Settings = __safeDI_settings()
		        self.init(settings: settings, reader: reader)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_2BCB59648D74E2A6 {}
		}

		#if DEBUG
		extension Service {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            settings: ((any UserService) -> Settings)? = nil,
		            reader: ((Clock, Clock) -> Reader)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                settings: settings,
		                reader: reader
		            )
		        }

		        var settings: ((any UserService) -> Settings)? { __safeDI_storage.settings }
		        var reader: ((Clock, Clock) -> Reader)? { __safeDI_storage.reader }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                settings: ((any UserService) -> Settings)?,
		                reader: ((Clock, Clock) -> Reader)?
		            ) {
		                self.settings = settings
		                self.reader = reader
		            }

		            let settings: ((any UserService) -> Settings)?
		            let reader: ((Clock, Clock) -> Reader)?
		        }
		    }

		    static func mock(
		        alarm: Clock,
		        userServiceBuilder: @escaping () -> any UserService,
		        zone: Clock,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        func __safeDI_settings() -> Settings {
		            let service: any UserService = userServiceBuilder()
		            return if let safeDIBuilder = safeDIOverrides.settings { safeDIBuilder(service) } else { Settings(service: service) }
		        }
		        let settings: Settings = __safeDI_settings()
		        let reader = if let safeDIBuilder = safeDIOverrides.reader { safeDIBuilder(alarm, zone) } else { Reader(alarm: alarm, zone: zone) }
		        return Service(settings: settings, reader: reader)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesValueForPlace_whenPlaceIsInstantiatorThatForwardsValue() async throws {
		let modules = Self.serviceModule(serviceDeclarations: ["@Instantiated(fulfilledByType: \"DefaultUserService\") public let userServiceBuilder: ErasedInstantiator<String, any UserService>"])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Service {
		    nonisolated public enum SafeDIScope_DefaultUserService_UserService {
		        nonisolated public struct userServiceBuilder_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let userServiceBuilder: (userServiceBuilder_Values) -> ErasedInstantiator<String, __safeDI_Built>.Builder

		            public init(userServiceBuilder: @escaping (userServiceBuilder_Values) -> ErasedInstantiator<String, __safeDI_Built>.Builder) {
		                self.userServiceBuilder = userServiceBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
		                self.userServiceBuilder = { _ in __safeDI_builder }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(defaultUserService_UserServiceBuilder: @escaping ErasedInstantiator<String, any UserService>.Builder) {
		        self.init(__safeDI_defaultUserService_UserServiceBuilder: .init(__safeDI_noScope: defaultUserService_UserServiceBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_defaultUserService_UserServiceBuilder: SafeDIScope_DefaultUserService_UserService.__safeDI_Builder<any UserService>) {
		        let userServiceBuilder = ErasedInstantiator<String, any UserService>(__safeDI_defaultUserService_UserServiceBuilder.userServiceBuilder(SafeDIScope_DefaultUserService_UserService.userServiceBuilder_Values()))
		        self.init(userServiceBuilder: userServiceBuilder)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_55A9646ABAD6EEE4 {}
		}

		#if DEBUG
		extension Service {
		    static func mock(
		        userServiceBuilder: ErasedInstantiator<String, any UserService>
		    ) -> Service {
		        return Service(userServiceBuilder: userServiceBuilder)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesCalledMocksBuilderOverItsEnum_whenPlaceIsReachedThroughCallOfAnotherModulesPublicMock() async throws {
		// `Panel`, another module's public mock, holds a place of `UserService`, which `Feature` cannot fill: `Service`'s
		// mock passes it up, taking `Panel`'s builder over its enum, as before.
		let modules = [
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContent: [
				"""
				import SafeDI

				public protocol UserService: AnyObject {}

				@Instantiable(generateDependencyTree: true, generateMock: .public)
				public final class Panel: Instantiable {
				    init(userService: any UserService) {
				        self.userService = userService
				    }

				    @Instantiated public let userService: any UserService
				}
				""",
			]),
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContent: [
				"""
				import Core
				import SafeDI

				@Instantiable(generateDependencyTree: true, generateMock: true)
				public final class Service: Instantiable {
				    public init(panel: Panel) {
				        self.panel = panel
				    }

				    @Instantiated public let panel: Panel
				}
				""",
			], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Core"]?.generatedFiles == ["Core.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Panel {
		    nonisolated public enum SafeDIScope_UserService {
		        nonisolated public struct userService_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let userService: (userService_Values) -> __safeDI_Built

		            public init(userService: @escaping (userService_Values) -> __safeDI_Built) {
		                self.userService = userService
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.userService = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_userServiceBuilder: SafeDIScope_UserService.__safeDI_Builder<any UserService>) {
		        let userService: any UserService = __safeDI_userServiceBuilder.userService(SafeDIScope_UserService.userService_Values())
		        self.init(userService: userService)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_A4A565E3243258A7 {}
		}

		#if DEBUG
		extension Panel {
		    @frozen nonisolated public enum SafeDIMockScope_UserService {
		        case userService(userService_Values)

		        nonisolated public struct userService_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let userService: (userService_Values) -> __safeDI_Built

		            public init(userService: @escaping (userService_Values) -> __safeDI_Built) {
		                self.userService = userService
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.userService = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    public static func mock(
		        userServiceBuilder: @escaping () -> any UserService
		    ) -> Panel {
		        Panel.__safeDI_mock(userServiceBuilder: .init(__safeDI_noScope: userServiceBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        userServiceBuilder __safeDI_userServiceBuilder: Panel.SafeDIMockScope_UserService.__safeDI_Builder<any UserService>
		    ) -> Panel {
		        let userService: any UserService = __safeDI_userServiceBuilder.userService(SafeDIMockScope_UserService.userService_Values())
		        return Panel(userService: userService)
		    }
		}

		extension Panel {
		    public enum __safeDI_Panel_mock_F6067D88F054320F {}
		}
		#endif
		"""])
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Service {
		    nonisolated public enum SafeDIScope_UserService {
		        nonisolated public struct panel_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let panel: (panel_Values) -> Panel.SafeDIScope_UserService.__safeDI_Builder<__safeDI_Built>

		            public init(panel: @escaping (panel_Values) -> Panel.SafeDIScope_UserService.__safeDI_Builder<__safeDI_Built>) {
		                self.panel = panel
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.panel = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_userServiceBuilder: SafeDIScope_UserService.__safeDI_Builder<any UserService>) {
		        func __safeDI_panel() -> Panel {
		            _ = Panel.__safeDI_Panel_A4A565E3243258A7.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Panel(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder.panel(SafeDIScope_UserService.panel_Values()))
		        }
		        let panel: Panel = __safeDI_panel()
		        self.init(panel: panel)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_6C51FB7539DC4297 {}
		}

		#if DEBUG
		extension Service {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            panel: ((@escaping (Panel.SafeDIMockScope_UserService) -> any UserService) -> Panel)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                panel: panel
		            )
		        }

		        var panel: ((@escaping (Panel.SafeDIMockScope_UserService) -> any UserService) -> Panel)? { __safeDI_storage.panel }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                panel: ((@escaping (Panel.SafeDIMockScope_UserService) -> any UserService) -> Panel)?
		            ) {
		                self.panel = panel
		            }

		            let panel: ((@escaping (Panel.SafeDIMockScope_UserService) -> any UserService) -> Panel)?
		        }
		    }

		    static func mock(
		        userServiceBuilder: @escaping (Panel.SafeDIMockScope_UserService) -> any UserService,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        _ = Panel.__safeDI_Panel_mock_F6067D88F054320F.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let panel = if let safeDIBuilder = safeDIOverrides.panel { safeDIBuilder(userServiceBuilder) } else { Panel.__safeDI_mock(userServiceBuilder: .init(userService: { __safeDI_userServiceValues in userServiceBuilder(.userService(__safeDI_userServiceValues)) })) }
		        return Service(panel: panel)
		    }
		}
		#endif
		"""])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Module `Feature`: `UserService`, which nothing fulfills, `LiveUserService`, which a test's builder returns, counting
	/// its live instances, the types that hold its places, `extraDeclarations`, and the seam `Service`, which declares
	/// `serviceDeclarations` and generates its internal mock; then `probes`.
	private static func serviceModule(serviceDeclarations: [String], extraDeclarations: [String] = [], probes: [String] = []) -> [ModuleFixture] {
		let parameters = serviceDeclarations.map { declaration in
			declaration.split(separator: " ").drop { !$0.hasSuffix(":") || $0.hasPrefix("@") }.joined(separator: " ")
		}
		let labels = parameters.map { $0.prefix { $0 != ":" } }
		return [
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContent: [
				"""
				import SafeDI

				public protocol UserService: AnyObject {}

				public final class LiveUserService: UserService {
				    public init() { LiveUserService.alive += 1 }
				    deinit { LiveUserService.alive -= 1 }
				    nonisolated(unsafe) public static var alive = 0
				}

				@Instantiable
				public final class Analytics: Instantiable {
				    public init() {}
				}

				@Instantiable
				public final class Profile: Instantiable {
				    public init(userService: any UserService) {
				        self.userService = userService
				    }

				    @Instantiated public let userService: any UserService
				}

				@Instantiable
				public final class Settings: Instantiable {
				    public init(service: any UserService) {
				        self.service = service
				    }

				    @Instantiated public let service: any UserService
				}

				@Instantiable
				public final class Account: Instantiable {
				    public init(service: any UserService) {
				        self.service = service
				    }

				    @Instantiated public let service: any UserService
				}
				""",
			] + extraDeclarations.map { "import SafeDI\n\n" + $0 } + [
				"""
				import SafeDI

				@Instantiable(generateDependencyTree: true, generateMock: true)
				public final class Service: Instantiable {
				    public init(\(parameters.joined(separator: ", "))) {
				\(labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
				    }

				\(serviceDeclarations.map { "    \($0)" }.joined(separator: "\n"))
				}
				""",
			] + probes, swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
		]
	}

	/// `SendableProfile`, which holds a place of `UserService` and is built in a `SendableInstantiator`.
	private static let sendableProfile = """
	@Instantiable
	public final class SendableProfile: Instantiable, @unchecked Sendable {
	    public init(userService: any UserService) {
	        self.userService = userService
	    }

	    @Instantiated public let userService: any UserService
	}
	"""

	/// Two probes named `reference<name>()` and `mock<name>()` that run `body` on a `Service` its readable initializer builds
	/// and on one its mock builds, each filling every place with `LiveUserService`, `body` reading `aliveBefore`.
	private static func probe(named name: String, building body: String) -> String {
		let capitalized = name.prefix(1).uppercased() + name.dropFirst()
		let indentedBody = body.split(separator: "\n", omittingEmptySubsequences: false).map { "    \($0)" }.joined(separator: "\n")
		return """
		func reference\(capitalized)() -> String {
		    let aliveBefore = LiveUserService.alive
		    let service = Service(userServiceBuilder: { LiveUserService() })
		\(indentedBody)
		}

		func mock\(capitalized)() -> String {
		    let aliveBefore = LiveUserService.alive
		    let service = Service.mock(userServiceBuilder: { LiveUserService() })
		\(indentedBody)
		}
		"""
	}
}
