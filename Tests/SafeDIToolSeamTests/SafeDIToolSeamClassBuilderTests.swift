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

/// A builder struct of two or more members is a `final class`, whose every copy and capture is one reference, where a
/// struct of as many closures is copied whole; one of a single member stays a struct, which a class's metadata,
/// allocation and deinitializer would only slow. Every case of an enum whose member takes no values takes one shared
/// empty `__safeDI_Values` of that enum.
struct SafeDIToolSeamClassBuilderTests: ~Copyable {
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
	mutating func generate_declaresFinalClassBuilder_whenEnumHasTwoCasesAndStructWhenItHasOne() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["twoPlacesBesideOne"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    nonisolated public enum SafeDIScope_Api {
		        nonisolated public struct primaryApi_Values {
		            public let logger: any Logger
		        }

		        nonisolated public struct secondaryApi_Values {
		            public let logger: any Logger
		            public let primaryApi: any Api
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public final class __safeDI_Builder<__safeDI_Built> {
		            public let primaryApi: (primaryApi_Values) -> __safeDI_Built
		            public let secondaryApi: (secondaryApi_Values) -> __safeDI_Built

		            public init(primaryApi: @escaping (primaryApi_Values) -> __safeDI_Built, secondaryApi: @escaping (secondaryApi_Values) -> __safeDI_Built) {
		                self.primaryApi = primaryApi
		                self.secondaryApi = secondaryApi
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.primaryApi = { _ in __safeDI_builder() }
		                self.secondaryApi = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    nonisolated public enum SafeDIScope_Logger {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let logger: (__safeDI_Values) -> __safeDI_Built

		            public init(logger: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                self.logger = logger
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.logger = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(apiBuilder: @escaping () -> any Api, loggerBuilder: @escaping () -> any Logger) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder), __safeDI_loggerBuilder: .init(__safeDI_noScope: loggerBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>, __safeDI_loggerBuilder: SafeDIScope_Logger.__safeDI_Builder<any Logger>) {
		        let logger: any Logger = __safeDI_loggerBuilder.logger(SafeDIScope_Logger.__safeDI_Values())
		        let primaryApi: any Api = __safeDI_apiBuilder.primaryApi(SafeDIScope_Api.primaryApi_Values(logger: logger))
		        let secondaryApi: any Api = __safeDI_apiBuilder.secondaryApi(SafeDIScope_Api.secondaryApi_Values(logger: logger, primaryApi: primaryApi))
		        self.init(logger: logger, primaryApi: primaryApi, secondaryApi: secondaryApi)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_A301D2DF4C6DED85 {}
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresSendableFinalClassWhoseCasesShareOneValuesType_whenSendableEnumHasTwoCases() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["sendableTwoPlaces"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    nonisolated public enum SafeDIScope_Api {
		        nonisolated public enum Worker_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (__safeDI_Values) -> __safeDI_Built

		                public init(api: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }

		        nonisolated public enum Helper_Scope {
		            nonisolated public struct __safeDI_Values: Sendable {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let api: (__safeDI_Values) -> __safeDI_Built

		                public init(api: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                    self.api = api
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                    self.api = { _ in __safeDI_builder() }
		                }
		            }
		        }
		    }

		    nonisolated public enum SafeDISendableScope_Api {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public final class __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let workerBuilder: @Sendable (__safeDI_Values) -> SafeDIScope_Api.Worker_Scope.__safeDI_Builder<__safeDI_Built>
		            public let helperBuilder: @Sendable (__safeDI_Values) -> SafeDIScope_Api.Helper_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(workerBuilder: @escaping @Sendable (__safeDI_Values) -> SafeDIScope_Api.Worker_Scope.__safeDI_Builder<__safeDI_Built>, helperBuilder: @escaping @Sendable (__safeDI_Values) -> SafeDIScope_Api.Helper_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.workerBuilder = workerBuilder
		                self.helperBuilder = helperBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		                self.workerBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.helperBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(apiSendableBuilder: @escaping @Sendable () -> any Api) {
		        self.init(__safeDI_apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any Api>) {
		        @Sendable nonisolated func __safeDI_workerBuilder() -> Worker {
		            let __safeDI_apiSendableBuilder_workerBuilder = __safeDI_apiSendableBuilder.workerBuilder(SafeDISendableScope_Api.__safeDI_Values())
		            let api: any Api = __safeDI_apiSendableBuilder_workerBuilder.api(SafeDIScope_Api.Worker_Scope.__safeDI_Values())
		            return Worker(api: api)
		        }
		        let workerBuilder = SendableInstantiator<Worker>(__safeDI_workerBuilder)
		        @Sendable nonisolated func __safeDI_helperBuilder() -> Helper {
		            let __safeDI_apiSendableBuilder_helperBuilder = __safeDI_apiSendableBuilder.helperBuilder(SafeDISendableScope_Api.__safeDI_Values())
		            let api: any Api = __safeDI_apiSendableBuilder_helperBuilder.api(SafeDIScope_Api.Helper_Scope.__safeDI_Values())
		            return Helper(api: api)
		        }
		        let helperBuilder = SendableInstantiator<Helper>(__safeDI_helperBuilder)
		        self.init(workerBuilder: workerBuilder, helperBuilder: helperBuilder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_8DB5C43D454C4BB7 {}
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresOneSharedValuesTypeBesideCasesPayloadStruct_whenEnumHasEmptyAndNonEmptyCase() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.fixtures["emptyBesideNonEmpty"] ?? [], integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Home {
		    nonisolated public enum SafeDIScope_Api {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        nonisolated public struct secondaryApi_Values {
		            public let primaryApi: any Api
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public final class __safeDI_Builder<__safeDI_Built> {
		            public let primaryApi: (__safeDI_Values) -> __safeDI_Built
		            public let secondaryApi: (secondaryApi_Values) -> __safeDI_Built

		            public init(primaryApi: @escaping (__safeDI_Values) -> __safeDI_Built, secondaryApi: @escaping (secondaryApi_Values) -> __safeDI_Built) {
		                self.primaryApi = primaryApi
		                self.secondaryApi = secondaryApi
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.primaryApi = { _ in __safeDI_builder() }
		                self.secondaryApi = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(apiBuilder: @escaping () -> any Api) {
		        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
		        let primaryApi: any Api = __safeDI_apiBuilder.primaryApi(SafeDIScope_Api.__safeDI_Values())
		        let secondaryApi: any Api = __safeDI_apiBuilder.secondaryApi(SafeDIScope_Api.secondaryApi_Values(primaryApi: primaryApi))
		        self.init(primaryApi: primaryApi, secondaryApi: secondaryApi)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_3D0ADF25667200FE {}
		}
		"""])
		try Self.expectCompiles(output)
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_compilesClassBuildersOfBothFamilies_whenModulesDefaultToMainActor(callingModuleIsMainActorByDefault: Bool) async throws {
		// The builders of both families are `nonisolated final class`es, which a module whose declarations default to the
		// main actor would otherwise isolate, and the `@Sendable` one is called inside the nonisolated `@Sendable` builder
		// function of the `SendableInstantiator` that holds its places.
		let mainActor = VerificationCompilerSettings(defaultIsolation: "MainActor")
		let calling = callingModuleIsMainActorByDefault ? mainActor : VerificationCompilerSettings()
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.bothFamiliesFeature, swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration, compilerSettings: mainActor),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: Self.bothFamiliesApp.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"], compilerSettings: calling),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"]?.contains("nonisolated public final class __safeDI_Builder<__safeDI_Built>: Sendable {") == true)
		try Self.expectCompiles(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsOneMemberStructThroughTwoMemberClass_whenSeamPassesUpPlacesOfSeamsInAnotherModule() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.screensFeatApp, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		#expect(output.modules["Screens"]?.generatedFiles == ["Screens.swift": generatedFileHeader + """
		extension Screen0 {
		    nonisolated public enum SafeDIScope_Hole0 {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let hole0: (__safeDI_Values) -> __safeDI_Built

		            public init(hole0: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                self.hole0 = hole0
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.hole0 = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_hole0Builder: SafeDIScope_Hole0.__safeDI_Builder<any Hole0>) {
		        let hole0: any Hole0 = __safeDI_hole0Builder.hole0(SafeDIScope_Hole0.__safeDI_Values())
		        self.init(hole0: hole0)
		    }
		}

		extension Screen0 {
		    public enum __safeDI_Screen0_53CCDEDDC5EE0F65 {}
		}

		extension Screen1 {
		    nonisolated public enum SafeDIScope_Hole0 {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let hole0: (__safeDI_Values) -> __safeDI_Built

		            public init(hole0: @escaping (__safeDI_Values) -> __safeDI_Built) {
		                self.hole0 = hole0
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.hole0 = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_hole0Builder: SafeDIScope_Hole0.__safeDI_Builder<any Hole0>) {
		        let hole0: any Hole0 = __safeDI_hole0Builder.hole0(SafeDIScope_Hole0.__safeDI_Values())
		        self.init(hole0: hole0)
		    }
		}

		extension Screen1 {
		    public enum __safeDI_Screen1_CA663954A0A7FB60 {}
		}
		"""])
		#expect(output.modules["Feat"]?.generatedFiles == ["Feat.swift": generatedFileHeader + """
		#if canImport(Screens)
		import Screens
		#endif

		extension Home {
		    nonisolated public enum SafeDIScope_Hole0 {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public final class __safeDI_Builder<__safeDI_Built> {
		            public let screen0Builder: (__safeDI_Values) -> Screen0.SafeDIScope_Hole0.__safeDI_Builder<__safeDI_Built>
		            public let screen1Builder: (__safeDI_Values) -> Screen1.SafeDIScope_Hole0.__safeDI_Builder<__safeDI_Built>

		            public init(screen0Builder: @escaping (__safeDI_Values) -> Screen0.SafeDIScope_Hole0.__safeDI_Builder<__safeDI_Built>, screen1Builder: @escaping (__safeDI_Values) -> Screen1.SafeDIScope_Hole0.__safeDI_Builder<__safeDI_Built>) {
		                self.screen0Builder = screen0Builder
		                self.screen1Builder = screen1Builder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.screen0Builder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		                self.screen1Builder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_hole0Builder: SafeDIScope_Hole0.__safeDI_Builder<any Hole0>) {
		        func __safeDI_screen0Builder() -> Screen0 {
		            _ = Screen0.__safeDI_Screen0_53CCDEDDC5EE0F65.self // If this line does not compile, compile the code SafeDI generates for module Screens into Screens: under Bazel, add Screens’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen0(__safeDI_hole0Builder: __safeDI_hole0Builder.screen0Builder(SafeDIScope_Hole0.__safeDI_Values()))
		        }
		        let screen0Builder = Instantiator<Screen0>(__safeDI_screen0Builder)
		        func __safeDI_screen1Builder() -> Screen1 {
		            _ = Screen1.__safeDI_Screen1_CA663954A0A7FB60.self // If this line does not compile, compile the code SafeDI generates for module Screens into Screens: under Bazel, add Screens’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen1(__safeDI_hole0Builder: __safeDI_hole0Builder.screen1Builder(SafeDIScope_Hole0.__safeDI_Values()))
		        }
		        let screen1Builder = Instantiator<Screen1>(__safeDI_screen1Builder)
		        self.init(screen0Builder: screen0Builder, screen1Builder: screen1Builder)
		    }
		}

		extension Home {
		    public enum __safeDI_Home_4FDF73D52AC2E7B8 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(Screens)
		import Screens
		#endif

		extension Root {
		    public init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_4FDF73D52AC2E7B8.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_hole0Builder_Home() -> Home.SafeDIScope_Hole0.__safeDI_Builder<any Hole0> {
		                .init(screen0Builder: { _ in __safeDI_hole0Builder_Screen0() }, screen1Builder: { _ in __safeDI_hole0Builder_Screen1() })
		            }
		            func __safeDI_hole0Builder_Screen0() -> Screen0.SafeDIScope_Hole0.__safeDI_Builder<any Hole0> {
		                .init(hole0: { _ in
		                    let hole0: any Hole0 = LiveHole0()
		                    return hole0
		                })
		            }
		            func __safeDI_hole0Builder_Screen1() -> Screen1.SafeDIScope_Hole0.__safeDI_Builder<any Hole0> {
		                .init(hole0: { _ in
		                    let hole0: any Hole0 = LiveHole0()
		                    return hole0
		                })
		            }
		            return Home(__safeDI_hole0Builder: __safeDI_hole0Builder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
		try Self.expectCompiles(output)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static func expectCompiles(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		for module in compilation.modules {
			#expect(module.result.exitCode == 0, "\(module.moduleName): \(module.result.stderr)", sourceLocation: sourceLocation)
			#expect(module.generatedCodeWarnings.isEmpty, "\(module.moduleName): \(module.generatedCodeWarnings)", sourceLocation: sourceLocation)
		}
	}

	private static let fixtures: [String: [ModuleFixture]] = [
		"twoPlacesBesideOne": featureAndApp(
			feature: [
				"public protocol Api {}\npublic protocol Logger {}",
				seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated public let logger: any Logger", "@Instantiated public let primaryApi: any Api", "@Instantiated public let secondaryApi: any Api"]),
			],
			app: [
				fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: []),
				fulfillingType(named: "LiveLogger", fulfilling: "Logger", declarations: []),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let home: Home"]),
			],
		),
		"sendableTwoPlaces": featureAndApp(
			feature: [
				"public protocol Api {}",
				seamFixtureType(named: "Helper", isFinalClass: true, declarations: ["@Instantiated public let api: any Api"]),
				seamFixtureType(named: "Worker", isFinalClass: true, declarations: ["@Instantiated public let api: any Api"]),
				seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let workerBuilder: SendableInstantiator<Worker>", "@Instantiated public let helperBuilder: SendableInstantiator<Helper>"]),
			],
			app: [fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: []), seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"])],
		),
		"emptyBesideNonEmpty": featureAndApp(
			feature: [
				"public protocol Api {}",
				seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated public let primaryApi: any Api", "@Instantiated public let secondaryApi: any Api"]),
			],
			app: [fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: []), seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let home: Home"])],
		),
	]

	/// `Home`'s plain places, `primaryApi` and `secondaryApi`, and those of `Worker` and `Helper`, each built in the
	/// `@Sendable` builder function of the `SendableInstantiator` that holds it: two members in each family's builder.
	private static let bothFamiliesFeature = [
		"public protocol Api: Sendable {}",
		seamFixtureType(named: "Helper", isFinalClass: true, declarations: ["@Instantiated public let api: any Api"]),
		seamFixtureType(named: "Worker", isFinalClass: true, declarations: ["@Instantiated public let api: any Api"]),
		seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: ["@Instantiated public let primaryApi: any Api", "@Instantiated public let secondaryApi: any Api", "@Instantiated public let workerBuilder: SendableInstantiator<Worker>", "@Instantiated public let helperBuilder: SendableInstantiator<Helper>"]),
	]

	private static let bothFamiliesApp = [
		fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: []),
		seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let home: Home"]),
	]

	/// P1's shape: seams `Screen0` and `Screen1` in `Screens`, each with one place of `Hole0`, a struct of one member;
	/// `Home` in `Feat`, which builds both and passes their places up, a class of two members; `App` fills them.
	private static let screensFeatApp = [
		ModuleFixture(name: "Screens", packageName: "Screens", swiftFileContent: [
			"public protocol Hole0 {}",
			seamFixtureType(named: "Screen0", isSeam: true, declarations: ["@Instantiated public let hole0: any Hole0"]),
			seamFixtureType(named: "Screen1", isSeam: true, declarations: ["@Instantiated public let hole0: any Hole0"]),
		]),
		ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContent: [
			"import Screens\n\n" + seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated public let screen0Builder: Instantiator<Screen0>", "@Instantiated public let screen1Builder: Instantiator<Screen1>"]),
		], dependencies: ["Screens"]),
		ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
			"import Screens\n\n" + fulfillingType(named: "LiveHole0", fulfilling: "Hole0", declarations: []),
			"import Feat\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let home: Home"]),
		], dependencies: ["Screens", "Feat"]),
	]

	private static func featureAndApp(feature: [String], app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: feature, swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: app.map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	private static func fulfillingType(named name: String, fulfilling fulfilledType: String, declarations: [String]) -> String {
		seamFixtureType(named: name, isFinalClass: true, declarations: declarations, conformances: ", \(fulfilledType)")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [\(fulfilledType).self])\n")
	}
}
