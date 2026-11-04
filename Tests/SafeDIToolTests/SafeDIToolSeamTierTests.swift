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
@testable import SafeDITool

/// How a seam's tiers are formed from its parameters' access levels and what a caller that reaches none is told. A tier
/// is generated for every distinct parameter access level, and for the seam's own initializer's level when that is wider
/// than every parameter's; of two candidates that would take the same parameters, the wider is generated, so a same-package
/// caller reaches the package tier and passes the value it holds. The narrowest tier builds the tree and calls the seam's
/// own initializer, which may be narrower than it. A caller that reaches no tier is reported at the declarations whose
/// widening makes a tier reachable – the receivers that cap the tier, and the seam's own initializer when nothing caps or
/// the seam has an own parameter – never at a generated initializer, and never without a location. The omission error
/// names a seam's own only-if-available receive as what it is.
struct SafeDIToolSeamTierTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Rule F': of two tiers that would take the same parameters, the wider is generated

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsPackageTier_whenSeamsOwnInitializerIsInternalAndPackageTierTakesWhatInternalTierTakes(integration: MultiModuleIntegration) async throws {
		// `Service`'s own initializer is internal, `Header`'s public, `Badge`'s package: the candidates are public,
		// package and internal, and the package and internal tiers would take the same parameters. The wider survives:
		// `Mid`, in the same package, reaches the package tier and passes the `theme` it holds, where the internal tier
		// would have left it to pass `nil`. The guard is unchanged, since the tiers derive from the parameters' accesses.
		// The twin whose own initializer is `package` builds the same values, which the comparator checks.
		let featureFiles = [Self.badgeWithPackageInit, Self.header, Self.service(init: "init")]
		let twinFeatureFiles = [Self.badgeWithPackageInit, Self.header, Self.service(init: "package init")]
		let output = try await executeSafeDIToolMultiModuleTest(modules: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: featureFiles), ModuleFixture(name: "Mid", packageName: "Shop", swiftFileContent: [Self.midRoot, Self.midShell], dependencies: ["Feature"])], integration: integration, filesToDelete: &filesToDelete)
		let twinOutput = try await executeSafeDIToolMultiModuleTest(modules: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: twinFeatureFiles), ModuleFixture(name: "Mid", packageName: "Shop", swiftFileContent: [Self.midRoot, Self.midShell], dependencies: ["Feature"])], integration: integration, filesToDelete: &filesToDelete)
		let expectedFeatureFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Feature.swift": generatedFileHeader + """
				extension Service {
				    public convenience init(title: String) {
				        self.init(theme: nil, title: title)
				    }

				    package convenience init(theme: Theme? = nil, title: String) {
				        let badge = Badge(theme: theme)
				        let header = Header(title: title)
				        self.init(badge: badge, header: header)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_2E13D94717A41A66 {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Service+SafeDI.swift": generatedFileHeader + """
				extension Service {
				    public convenience init(title: String) {
				        self.init(theme: nil, title: title)
				    }

				    package convenience init(theme: Theme? = nil, title: String) {
				        let badge = Badge(theme: theme)
				        let header = Header(title: title)
				        self.init(badge: badge, header: header)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_2E13D94717A41A66 {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles[integration])
		let expectedMidFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Mid.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension MidRoot {
				    public convenience init() {
				        func __safeDI_shellBuilder(theme: Theme, title: String) -> MidShell {
				            func __safeDI_service() -> Service {
				                _ = Service.__safeDI_Service_2E13D94717A41A66.self
				                return Service(theme: theme, title: title)
				            }
				            let service: Service = __safeDI_service()
				            return MidShell(theme: theme, title: title, service: service)
				        }
				        let shellBuilder = Instantiator<MidShell> {
				            __safeDI_shellBuilder(theme: $0.theme, title: $0.title)
				        }
				        self.init(shellBuilder: shellBuilder)
				    }
				}
				""",
			],
			.swiftPackagePlugin: [
				"MidRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension MidRoot {
				    public convenience init() {
				        func __safeDI_shellBuilder(theme: Theme, title: String) -> MidShell {
				            func __safeDI_service() -> Service {
				                _ = Service.__safeDI_Service_2E13D94717A41A66.self // If this line does not compile, add the SafeDI plugin to the target that declares Service.
				                return Service(theme: theme, title: title)
				            }
				            let service: Service = __safeDI_service()
				            return MidShell(theme: theme, title: title, service: service)
				        }
				        let shellBuilder = Instantiator<MidShell> {
				            __safeDI_shellBuilder(theme: $0.theme, title: $0.title)
				        }
				        self.init(shellBuilder: shellBuilder)
				    }
				}
				""",
			],
		]
		#expect(try #require(output.modules["Mid"]).generatedFiles == expectedMidFiles[integration])
		// The twin, whose `package` own initializer makes the package tier by itself: the same files, byte for byte.
		#expect(try #require(twinOutput.modules["Feature"]).generatedFiles == expectedFeatureFiles[integration])
		#expect(try #require(twinOutput.modules["Mid"]).generatedFiles == expectedMidFiles[integration])
		try expectEveryModuleCompiled(output)
		try expectEveryModuleCompiled(twinOutput)
		try expectDifferentialValuesAgree(
			feature: Self.path(featureFiles: featureFiles, midFiles: [Self.midRoot, Self.midShell], output: output),
			knownRight: Self.path(featureFiles: twinFeatureFiles, midFiles: [Self.midRoot, Self.midShell], output: twinOutput),
			probes: [DifferentialValueProbe("MidRoot().shellBuilder.instantiate((theme: Theme(), title: \"title\"))")],
			filesToDelete: &filesToDelete,
		)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsPackageTier_whenStructSeamsOwnInitializerIsInternalAndPackageTierTakesWhatInternalTierTakes(integration: MultiModuleIntegration) async throws {
		// The struct seam: `public init` and `package init` tiers.
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: [
					"""
					@Instantiable
					public struct Badge: Instantiable {
					    package init(theme: Theme?) {
					        self.theme = theme
					    }

					    @Received(onlyIfAvailable: true) public let theme: Theme?
					}

					public struct Theme: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Header: Instantiable {
					    public init(title: String) {
					        self.title = title
					    }

					    @Received public let title: String
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Service: Instantiable {
					    init(badge: Badge, header: Header) {
					        self.badge = badge
					        self.header = header
					    }

					    @Instantiated public let badge: Badge
					    @Instantiated public let header: Header
					}
					""",
				],
			),
			ModuleFixture(
				name: "Mid",
				packageName: "Shop",
				swiftFileContent: [
					"""
					import Feature

					@Instantiable(isRoot: true)
					public final class MidRoot: Instantiable {
					    public init(shellBuilder: Instantiator<MidShell>) {
					        self.shellBuilder = shellBuilder
					    }

					    @Instantiated public let shellBuilder: Instantiator<MidShell>
					}
					""",
					"""
					import Feature

					@Instantiable
					public final class MidShell: Instantiable {
					    public init(theme: Theme, title: String, service: Service) {
					        self.theme = theme
					        self.title = title
					        self.service = service
					    }

					    @Forwarded public let theme: Theme
					    @Forwarded public let title: String
					    @Instantiated public let service: Service
					}
					""",
				],
				dependencies: ["Feature"],
			),
		], integration: integration, filesToDelete: &filesToDelete)
		let expectedFeatureFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Feature.swift": generatedFileHeader + """
				extension Service {
				    public init(title: String) {
				        self.init(theme: nil, title: title)
				    }

				    package init(theme: Theme? = nil, title: String) {
				        let badge = Badge(theme: theme)
				        let header = Header(title: title)
				        self.init(badge: badge, header: header)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_2E13D94717A41A66 {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Service+SafeDI.swift": generatedFileHeader + """
				extension Service {
				    public init(title: String) {
				        self.init(theme: nil, title: title)
				    }

				    package init(theme: Theme? = nil, title: String) {
				        let badge = Badge(theme: theme)
				        let header = Header(title: title)
				        self.init(badge: badge, header: header)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_2E13D94717A41A66 {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles[integration])
		let expectedMidFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Mid.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension MidRoot {
				    public convenience init() {
				        func __safeDI_shellBuilder(theme: Theme, title: String) -> MidShell {
				            func __safeDI_service() -> Service {
				                _ = Service.__safeDI_Service_2E13D94717A41A66.self
				                return Service(theme: theme, title: title)
				            }
				            let service: Service = __safeDI_service()
				            return MidShell(theme: theme, title: title, service: service)
				        }
				        let shellBuilder = Instantiator<MidShell> {
				            __safeDI_shellBuilder(theme: $0.theme, title: $0.title)
				        }
				        self.init(shellBuilder: shellBuilder)
				    }
				}
				""",
			],
			.swiftPackagePlugin: [
				"MidRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension MidRoot {
				    public convenience init() {
				        func __safeDI_shellBuilder(theme: Theme, title: String) -> MidShell {
				            func __safeDI_service() -> Service {
				                _ = Service.__safeDI_Service_2E13D94717A41A66.self // If this line does not compile, add the SafeDI plugin to the target that declares Service.
				                return Service(theme: theme, title: title)
				            }
				            let service: Service = __safeDI_service()
				            return MidShell(theme: theme, title: title, service: service)
				        }
				        let shellBuilder = Instantiator<MidShell> {
				            __safeDI_shellBuilder(theme: $0.theme, title: $0.title)
				        }
				        self.init(shellBuilder: shellBuilder)
				    }
				}
				""",
			],
		]
		#expect(try #require(output.modules["Mid"]).generatedFiles == expectedMidFiles[integration])
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsPackageTier_whenNestedSeamInSamePackageForwardsParameterPackageTierTakes(integration: MultiModuleIntegration) async throws {
		// `Mid`'s caller is itself a seam forwarding `theme`: its tier calls `Service`'s package tier with `theme`.
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: [
					"""
					@Instantiable
					public struct Badge: Instantiable {
					    package init(theme: Theme?) {
					        self.theme = theme
					    }

					    @Received(onlyIfAvailable: true) public let theme: Theme?
					}

					public struct Theme: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Header: Instantiable {
					    public init(title: String) {
					        self.title = title
					    }

					    @Received public let title: String
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Service: Instantiable {
					    init(badge: Badge, header: Header) {
					        self.badge = badge
					        self.header = header
					    }

					    @Instantiated public let badge: Badge
					    @Instantiated public let header: Header
					}
					""",
				],
			),
			ModuleFixture(
				name: "Mid",
				packageName: "Shop",
				swiftFileContent: [
					"""
					import Feature

					@Instantiable(isRoot: true)
					public final class MidRoot: Instantiable {
					    public init(screenBuilder: Instantiator<MidScreen>) {
					        self.screenBuilder = screenBuilder
					    }

					    @Instantiated public let screenBuilder: Instantiator<MidScreen>
					}
					""",
					"""
					import Feature

					@Instantiable(generateDependencyTree: true)
					public final class MidScreen: Instantiable {
					    public init(theme: Theme, title: String, service: Service) {
					        self.theme = theme
					        self.title = title
					        self.service = service
					    }

					    @Forwarded public let theme: Theme
					    @Forwarded public let title: String
					    @Instantiated public let service: Service
					}
					""",
				],
				dependencies: ["Feature"],
			),
		], integration: integration, filesToDelete: &filesToDelete)
		let expectedFeatureFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Feature.swift": generatedFileHeader + """
				extension Service {
				    public convenience init(title: String) {
				        self.init(theme: nil, title: title)
				    }

				    package convenience init(theme: Theme? = nil, title: String) {
				        let badge = Badge(theme: theme)
				        let header = Header(title: title)
				        self.init(badge: badge, header: header)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_2E13D94717A41A66 {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Service+SafeDI.swift": generatedFileHeader + """
				extension Service {
				    public convenience init(title: String) {
				        self.init(theme: nil, title: title)
				    }

				    package convenience init(theme: Theme? = nil, title: String) {
				        let badge = Badge(theme: theme)
				        let header = Header(title: title)
				        self.init(badge: badge, header: header)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_2E13D94717A41A66 {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles[integration])
		let expectedMidFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Mid.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension MidRoot {
				    public convenience init() {
				        func __safeDI_screenBuilder(theme: Theme, title: String) -> MidScreen {
				            _ = MidScreen.__safeDI_MidScreen_C63CDB91AE55533E.self
				            return MidScreen(theme: theme, title: title)
				        }
				        let screenBuilder = Instantiator<MidScreen> {
				            __safeDI_screenBuilder(theme: $0.theme, title: $0.title)
				        }
				        self.init(screenBuilder: screenBuilder)
				    }
				}

				extension MidScreen {
				    public convenience init(theme: Theme, title: String) {
				        func __safeDI_service() -> Service {
				            _ = Service.__safeDI_Service_2E13D94717A41A66.self
				            return Service(theme: theme, title: title)
				        }
				        let service: Service = __safeDI_service()
				        self.init(theme: theme, title: title, service: service)
				    }
				}

				extension MidScreen {
				    public enum __safeDI_MidScreen_C63CDB91AE55533E {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"MidRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension MidRoot {
				    public convenience init() {
				        func __safeDI_screenBuilder(theme: Theme, title: String) -> MidScreen {
				            _ = MidScreen.__safeDI_MidScreen_C63CDB91AE55533E.self
				            return MidScreen(theme: theme, title: title)
				        }
				        let screenBuilder = Instantiator<MidScreen> {
				            __safeDI_screenBuilder(theme: $0.theme, title: $0.title)
				        }
				        self.init(screenBuilder: screenBuilder)
				    }
				}
				""",
				"MidScreen+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension MidScreen {
				    public convenience init(theme: Theme, title: String) {
				        func __safeDI_service() -> Service {
				            _ = Service.__safeDI_Service_2E13D94717A41A66.self // If this line does not compile, add the SafeDI plugin to the target that declares Service.
				            return Service(theme: theme, title: title)
				        }
				        let service: Service = __safeDI_service()
				        self.init(theme: theme, title: title, service: service)
				    }
				}

				extension MidScreen {
				    public enum __safeDI_MidScreen_C63CDB91AE55533E {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Mid"]).generatedFiles == expectedMidFiles[integration])
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsPublicTier_whenSeamsOwnInitializerIsPackageAndPublicTierTakesWhatPackageTierTakes(integration: MultiModuleIntegration) async throws {
		// `Header`'s receive is public, `Service`'s own initializer package, `Badge`'s internal: the public and package tiers would
		// take the same parameters, and the public one survives, so a caller in another package calls `Service(title:)`.
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: [
					"""
					@Instantiable
					public struct Badge: Instantiable {
					    init(theme: Theme?) {
					        self.theme = theme
					    }

					    @Received(onlyIfAvailable: true) public let theme: Theme?
					}

					public struct Theme: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Header: Instantiable {
					    public init(title: String) {
					        self.title = title
					    }

					    @Received public let title: String
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Service: Instantiable {
					    package init(badge: Badge, header: Header) {
					        self.badge = badge
					        self.header = header
					    }

					    @Instantiated public let badge: Badge
					    @Instantiated public let header: Header
					}
					""",
				],
			),
			ModuleFixture(
				name: "App",
				packageName: "Other",
				swiftFileContent: [
					"""
					import Feature

					@Instantiable(isRoot: true)
					public final class AppRoot: Instantiable {
					    public init(shellBuilder: Instantiator<AppShell>) {
					        self.shellBuilder = shellBuilder
					    }

					    @Instantiated public let shellBuilder: Instantiator<AppShell>
					}
					""",
					"""
					import Feature

					@Instantiable
					public final class AppShell: Instantiable {
					    public init(title: String, service: Service) {
					        self.title = title
					        self.service = service
					    }

					    @Forwarded public let title: String
					    @Instantiated public let service: Service
					}
					""",
				],
				dependencies: ["Feature"],
			),
		], integration: integration, filesToDelete: &filesToDelete)
		let expectedFeatureFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Feature.swift": generatedFileHeader + """
				extension Service {
				    public convenience init(title: String) {
				        self.init(theme: nil, title: title)
				    }

				    internal convenience init(theme: Theme? = nil, title: String) {
				        let badge = Badge(theme: theme)
				        let header = Header(title: title)
				        self.init(badge: badge, header: header)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_B4AD90702EEDB043 {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Service+SafeDI.swift": generatedFileHeader + """
				extension Service {
				    public convenience init(title: String) {
				        self.init(theme: nil, title: title)
				    }

				    internal convenience init(theme: Theme? = nil, title: String) {
				        let badge = Badge(theme: theme)
				        let header = Header(title: title)
				        self.init(badge: badge, header: header)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_B4AD90702EEDB043 {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles[integration])
		let expectedAppFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension AppRoot {
				    public convenience init() {
				        func __safeDI_shellBuilder(title: String) -> AppShell {
				            func __safeDI_service() -> Service {
				                _ = Service.__safeDI_Service_B4AD90702EEDB043.self
				                return Service(title: title)
				            }
				            let service: Service = __safeDI_service()
				            return AppShell(title: title, service: service)
				        }
				        let shellBuilder = Instantiator<AppShell> {
				            __safeDI_shellBuilder(title: $0)
				        }
				        self.init(shellBuilder: shellBuilder)
				    }
				}
				""",
			],
			.swiftPackagePlugin: [
				"AppRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension AppRoot {
				    public convenience init() {
				        func __safeDI_shellBuilder(title: String) -> AppShell {
				            func __safeDI_service() -> Service {
				                _ = Service.__safeDI_Service_B4AD90702EEDB043.self // If this line does not compile, add the SafeDI plugin to the target that declares Service.
				                return Service(title: title)
				            }
				            let service: Service = __safeDI_service()
				            return AppShell(title: title, service: service)
				        }
				        let shellBuilder = Instantiator<AppShell> {
				            __safeDI_shellBuilder(title: $0)
				        }
				        self.init(shellBuilder: shellBuilder)
				    }
				}
				""",
			],
		]
		#expect(try #require(output.modules["App"]).generatedFiles == expectedAppFiles[integration])
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsPackageTier_whenSeamsOwnInitializerIsInternalAndOnlyParameterIsPackageOptional(integration: MultiModuleIntegration) async throws {
		// `Service`'s own initializer is internal and its one parameter package: the package tier survives, calling the own
		// initializer inside `Feature`, and a caller in the same package passes `theme`.
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: [
					"""
					@Instantiable
					public struct Badge: Instantiable {
					    package init(theme: Theme?) {
					        self.theme = theme
					    }

					    @Received(onlyIfAvailable: true) public let theme: Theme?
					}

					public struct Theme: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Service: Instantiable {
					    init(badge: Badge) {
					        self.badge = badge
					    }

					    @Instantiated public let badge: Badge
					}
					""",
				],
			),
			ModuleFixture(
				name: "App",
				packageName: "Shop",
				swiftFileContent: [
					"""
					import Feature

					@Instantiable(isRoot: true)
					public final class AppRoot: Instantiable {
					    public init(shellBuilder: Instantiator<AppShell>) {
					        self.shellBuilder = shellBuilder
					    }

					    @Instantiated public let shellBuilder: Instantiator<AppShell>
					}
					""",
					"""
					import Feature

					@Instantiable
					public final class AppShell: Instantiable {
					    public init(theme: Theme, service: Service) {
					        self.theme = theme
					        self.service = service
					    }

					    @Forwarded public let theme: Theme
					    @Instantiated public let service: Service
					}
					""",
				],
				dependencies: ["Feature"],
			),
		], integration: integration, filesToDelete: &filesToDelete)
		let expectedFeatureFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Feature.swift": generatedFileHeader + """
				extension Service {
				    package convenience init(theme: Theme? = nil) {
				        let badge = Badge(theme: theme)
				        self.init(badge: badge)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_27F6F01DC5D0EF8E {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Service+SafeDI.swift": generatedFileHeader + """
				extension Service {
				    package convenience init(theme: Theme? = nil) {
				        let badge = Badge(theme: theme)
				        self.init(badge: badge)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_27F6F01DC5D0EF8E {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles[integration])
		let expectedAppFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension AppRoot {
				    public convenience init() {
				        func __safeDI_shellBuilder(theme: Theme) -> AppShell {
				            func __safeDI_service() -> Service {
				                _ = Service.__safeDI_Service_27F6F01DC5D0EF8E.self
				                return Service(theme: theme)
				            }
				            let service: Service = __safeDI_service()
				            return AppShell(theme: theme, service: service)
				        }
				        let shellBuilder = Instantiator<AppShell> {
				            __safeDI_shellBuilder(theme: $0)
				        }
				        self.init(shellBuilder: shellBuilder)
				    }
				}
				""",
			],
			.swiftPackagePlugin: [
				"AppRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension AppRoot {
				    public convenience init() {
				        func __safeDI_shellBuilder(theme: Theme) -> AppShell {
				            func __safeDI_service() -> Service {
				                _ = Service.__safeDI_Service_27F6F01DC5D0EF8E.self // If this line does not compile, add the SafeDI plugin to the target that declares Service.
				                return Service(theme: theme)
				            }
				            let service: Service = __safeDI_service()
				            return AppShell(theme: theme, service: service)
				        }
				        let shellBuilder = Instantiator<AppShell> {
				            __safeDI_shellBuilder(theme: $0)
				        }
				        self.init(shellBuilder: shellBuilder)
				    }
				}
				""",
			],
		]
		#expect(try #require(output.modules["App"]).generatedFiles == expectedAppFiles[integration])
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPackageTier_whenRootInSeamsModuleReachesSeamWhoseNarrowestTierIsPackage(integration: MultiModuleIntegration) async throws {
		// A root in the seam's own module calls the narrowest tier, now spelled `package`, passing both values.
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: [
					"""
					@Instantiable
					public struct Badge: Instantiable {
					    package init(theme: Theme?) {
					        self.theme = theme
					    }

					    @Received(onlyIfAvailable: true) public let theme: Theme?
					}

					public struct Theme: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Header: Instantiable {
					    public init(title: String) {
					        self.title = title
					    }

					    @Received public let title: String
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Service: Instantiable {
					    init(badge: Badge, header: Header) {
					        self.badge = badge
					        self.header = header
					    }

					    @Instantiated public let badge: Badge
					    @Instantiated public let header: Header
					}
					""",
					"""
					@Instantiable(isRoot: true)
					public final class FeatureRoot: Instantiable {
					    public init(shellBuilder: Instantiator<FeatureShell>) {
					        self.shellBuilder = shellBuilder
					    }

					    @Instantiated public let shellBuilder: Instantiator<FeatureShell>
					}
					""",
					"""
					@Instantiable
					public final class FeatureShell: Instantiable {
					    public init(theme: Theme, title: String, service: Service) {
					        self.theme = theme
					        self.title = title
					        self.service = service
					    }

					    @Forwarded public let theme: Theme
					    @Forwarded public let title: String
					    @Instantiated public let service: Service
					}
					""",
				],
			),
		], integration: integration, filesToDelete: &filesToDelete)
		let expectedFeatureFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Feature.swift": generatedFileHeader + """
				extension FeatureRoot {
				    public convenience init() {
				        func __safeDI_shellBuilder(theme: Theme, title: String) -> FeatureShell {
				            func __safeDI_service() -> Service {
				                _ = Service.__safeDI_Service_2E13D94717A41A66.self
				                return Service(theme: theme, title: title)
				            }
				            let service: Service = __safeDI_service()
				            return FeatureShell(theme: theme, title: title, service: service)
				        }
				        let shellBuilder = Instantiator<FeatureShell> {
				            __safeDI_shellBuilder(theme: $0.theme, title: $0.title)
				        }
				        self.init(shellBuilder: shellBuilder)
				    }
				}

				extension Service {
				    public convenience init(title: String) {
				        self.init(theme: nil, title: title)
				    }

				    package convenience init(theme: Theme? = nil, title: String) {
				        let badge = Badge(theme: theme)
				        let header = Header(title: title)
				        self.init(badge: badge, header: header)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_2E13D94717A41A66 {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"FeatureRoot+SafeDI.swift": generatedFileHeader + """
				extension FeatureRoot {
				    public convenience init() {
				        func __safeDI_shellBuilder(theme: Theme, title: String) -> FeatureShell {
				            func __safeDI_service() -> Service {
				                _ = Service.__safeDI_Service_2E13D94717A41A66.self
				                return Service(theme: theme, title: title)
				            }
				            let service: Service = __safeDI_service()
				            return FeatureShell(theme: theme, title: title, service: service)
				        }
				        let shellBuilder = Instantiator<FeatureShell> {
				            __safeDI_shellBuilder(theme: $0.theme, title: $0.title)
				        }
				        self.init(shellBuilder: shellBuilder)
				    }
				}
				""",
				"Service+SafeDI.swift": generatedFileHeader + """
				extension Service {
				    public convenience init(title: String) {
				        self.init(theme: nil, title: title)
				    }

				    package convenience init(theme: Theme? = nil, title: String) {
				        let badge = Badge(theme: theme)
				        let header = Header(title: title)
				        self.init(badge: badge, header: header)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_2E13D94717A41A66 {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles[integration])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesGeneratedTier_whenWiderOfTwoTiersTakingTheSameParametersOmitsRequiredParameter() async {
		// `Service`'s own initializer is package, `Badge`'s receive public and `Detail`'s internal: the public and package tiers
		// would take the same parameters, and the omission error names the public one, which is generated.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Service.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Service`: its generated `public` initializer cannot take `logger: Logger`, which the initializer of `Detail` receives at a narrower access level, and cannot pass `nil` for it, since it is required. Widen the initializer of `Detail`, receive the property with `onlyIfAvailable: true` and an optional type, or narrow the initializers of every type in the tree to its level.
			\(fixtures["Detail.swift"]):7:5: note: `Detail` receives `logger: Logger` here.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				"""
				@Instantiable
				public struct Badge: Instantiable {
				    public init(theme: Theme?) {
				        self.theme = theme
				    }

				    @Received(onlyIfAvailable: true) public let theme: Theme?
				}

				public struct Theme: Sendable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public struct Detail: Instantiable {
				    init(logger: Logger) {
				        self.logger = logger
				    }

				    @Received let logger: Logger
				}

				public struct Logger: Sendable {
				    public init() {}
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public final class Service: Instantiable {
				    package init(badge: Badge, detail: Detail) {
				        self.badge = badge
				        self.detail = detail
				    }

				    @Instantiated public let badge: Badge
				    @Instantiated let detail: Detail
				}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Rule F' controls, byte-identical

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsPublicTierPassingNil_whenSeamsOwnInitializerIsPublicAndEveryParameterIsNarrowerAndOptional(integration: MultiModuleIntegration) async throws {
		// `Screen`'s own initializer is public and `Badge`'s internal: the public tier takes nothing and passes `nil`, the
		// internal tier takes `theme`.
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: [
					"""
					@Instantiable
					public struct Badge: Instantiable {
					    init(theme: Theme?) {
					        self.theme = theme
					    }

					    @Received(onlyIfAvailable: true) public let theme: Theme?
					}

					public struct Theme: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable {
					    public init(badge: Badge) {
					        self.badge = badge
					    }

					    @Instantiated let badge: Badge
					}
					""",
				],
			),
			ModuleFixture(
				name: "App",
				packageName: "Other",
				swiftFileContent: [
					"""
					import Feature

					@Instantiable(isRoot: true)
					public final class AppRoot: Instantiable {
					    public init(screenBuilder: Instantiator<Screen>) {
					        self.screenBuilder = screenBuilder
					    }

					    @Instantiated let screenBuilder: Instantiator<Screen>
					}
					""",
				],
				dependencies: ["Feature"],
			),
		], integration: integration, filesToDelete: &filesToDelete)
		let expectedFeatureFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Feature.swift": generatedFileHeader + """
				extension Screen {
				    public init() {
				        self.init(theme: nil)
				    }

				    internal init(theme: Theme? = nil) {
				        let badge = Badge(theme: theme)
				        self.init(badge: badge)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_2163FBB3C02B31CD {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public init() {
				        self.init(theme: nil)
				    }

				    internal init(theme: Theme? = nil) {
				        let badge = Badge(theme: theme)
				        self.init(badge: badge)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_2163FBB3C02B31CD {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles[integration])
		let expectedAppFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension AppRoot {
				    public convenience init() {
				        func __safeDI_screenBuilder() -> Screen {
				            _ = Screen.__safeDI_Screen_2163FBB3C02B31CD.self
				            return Screen()
				        }
				        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
				        self.init(screenBuilder: screenBuilder)
				    }
				}
				""",
			],
			.swiftPackagePlugin: [
				"AppRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension AppRoot {
				    public convenience init() {
				        func __safeDI_screenBuilder() -> Screen {
				            _ = Screen.__safeDI_Screen_2163FBB3C02B31CD.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen()
				        }
				        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
				        self.init(screenBuilder: screenBuilder)
				    }
				}
				""",
			],
		]
		#expect(try #require(output.modules["App"]).generatedFiles == expectedAppFiles[integration])
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresOnePackageTier_whenEveryParameterAndSeamsOwnInitializerArePackage(integration: MultiModuleIntegration) async throws {
		// Every parameter and the own initializer are package: one package tier, no public tier added.
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: [
					"""
					@Instantiable
					public struct Consumer: Instantiable {
					    package init(session: Session) {
					        self.session = session
					    }

					    @Received let session: Session
					}

					@Instantiable
					package struct Session: Instantiable {
					    package init() {}
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable {
					    package init(consumer: Consumer) {
					        self.consumer = consumer
					    }

					    @Instantiated let consumer: Consumer
					}
					""",
				],
			),
			ModuleFixture(
				name: "App",
				packageName: "Shop",
				swiftFileContent: [
					"""
					import Feature

					@Instantiable(isRoot: true)
					public final class AppRoot: Instantiable {
					    package init(session: Session, screen: Screen) {
					        self.session = session
					        self.screen = screen
					    }

					    @Instantiated let session: Session
					    @Instantiated let screen: Screen
					}
					""",
				],
				dependencies: ["Feature"],
			),
		], integration: integration, filesToDelete: &filesToDelete)
		let expectedFeatureFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Feature.swift": generatedFileHeader + """
				extension Screen {
				    package init(session: Session) {
				        let consumer = Consumer(session: session)
				        self.init(consumer: consumer)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_ADEC5AA5E64046ED {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    package init(session: Session) {
				        let consumer = Consumer(session: session)
				        self.init(consumer: consumer)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_ADEC5AA5E64046ED {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles[integration])
		let expectedAppFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension AppRoot {
				    public convenience init() {
				        let session = Session()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_ADEC5AA5E64046ED.self
				            return Screen(session: session)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(session: session, screen: screen)
				    }
				}
				""",
			],
			.swiftPackagePlugin: [
				"AppRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension AppRoot {
				    public convenience init() {
				        let session = Session()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_ADEC5AA5E64046ED.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen(session: session)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(session: session, screen: screen)
				    }
				}
				""",
			],
		]
		#expect(try #require(output.modules["App"]).generatedFiles == expectedAppFiles[integration])
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsPublicTierAndPackageTier_whenSeamsOwnInitializerIsPublicBesideRequiredPublicAndOptionalPackageParameters(integration: MultiModuleIntegration) async throws {
		// The Manual's example shape: a public own initializer beside a required public and an optional package parameter
		// gives public and package tiers, as before.
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: [
					"""
					@Instantiable
					public struct Badge: Instantiable {
					    package init(theme: Theme?) {
					        self.theme = theme
					    }

					    @Received(onlyIfAvailable: true) public let theme: Theme?
					}

					public struct Theme: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Header: Instantiable {
					    public init(title: String) {
					        self.title = title
					    }

					    @Received public let title: String
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Service: Instantiable {
					    public init(badge: Badge, header: Header) {
					        self.badge = badge
					        self.header = header
					    }

					    @Instantiated public let badge: Badge
					    @Instantiated public let header: Header
					}
					""",
				],
			),
			ModuleFixture(
				name: "Mid",
				packageName: "Shop",
				swiftFileContent: [
					"""
					import Feature

					@Instantiable(isRoot: true)
					public final class MidRoot: Instantiable {
					    public init(shellBuilder: Instantiator<MidShell>) {
					        self.shellBuilder = shellBuilder
					    }

					    @Instantiated public let shellBuilder: Instantiator<MidShell>
					}
					""",
					"""
					import Feature

					@Instantiable
					public final class MidShell: Instantiable {
					    public init(theme: Theme, title: String, service: Service) {
					        self.theme = theme
					        self.title = title
					        self.service = service
					    }

					    @Forwarded public let theme: Theme
					    @Forwarded public let title: String
					    @Instantiated public let service: Service
					}
					""",
				],
				dependencies: ["Feature"],
			),
		], integration: integration, filesToDelete: &filesToDelete)
		let expectedFeatureFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Feature.swift": generatedFileHeader + """
				extension Service {
				    public convenience init(title: String) {
				        self.init(theme: nil, title: title)
				    }

				    package convenience init(theme: Theme? = nil, title: String) {
				        let badge = Badge(theme: theme)
				        let header = Header(title: title)
				        self.init(badge: badge, header: header)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_2E13D94717A41A66 {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Service+SafeDI.swift": generatedFileHeader + """
				extension Service {
				    public convenience init(title: String) {
				        self.init(theme: nil, title: title)
				    }

				    package convenience init(theme: Theme? = nil, title: String) {
				        let badge = Badge(theme: theme)
				        let header = Header(title: title)
				        self.init(badge: badge, header: header)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_2E13D94717A41A66 {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles[integration])
		let expectedMidFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Mid.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension MidRoot {
				    public convenience init() {
				        func __safeDI_shellBuilder(theme: Theme, title: String) -> MidShell {
				            func __safeDI_service() -> Service {
				                _ = Service.__safeDI_Service_2E13D94717A41A66.self
				                return Service(theme: theme, title: title)
				            }
				            let service: Service = __safeDI_service()
				            return MidShell(theme: theme, title: title, service: service)
				        }
				        let shellBuilder = Instantiator<MidShell> {
				            __safeDI_shellBuilder(theme: $0.theme, title: $0.title)
				        }
				        self.init(shellBuilder: shellBuilder)
				    }
				}
				""",
			],
			.swiftPackagePlugin: [
				"MidRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension MidRoot {
				    public convenience init() {
				        func __safeDI_shellBuilder(theme: Theme, title: String) -> MidShell {
				            func __safeDI_service() -> Service {
				                _ = Service.__safeDI_Service_2E13D94717A41A66.self // If this line does not compile, add the SafeDI plugin to the target that declares Service.
				                return Service(theme: theme, title: title)
				            }
				            let service: Service = __safeDI_service()
				            return MidShell(theme: theme, title: title, service: service)
				        }
				        let shellBuilder = Instantiator<MidShell> {
				            __safeDI_shellBuilder(theme: $0.theme, title: $0.title)
				        }
				        self.init(shellBuilder: shellBuilder)
				    }
				}
				""",
			],
		]
		#expect(try #require(output.modules["Mid"]).generatedFiles == expectedMidFiles[integration])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assumesPackageAccessWithComment_whenCallerOfUnknownPackageReachesPackageTierThatSurvivedAsWider() async throws {
		// A caller whose package is unknown reaches the package tier, now generated, with the comment that `package`
		// access is assumed.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [Self.badgeWithPackageInit, Self.serviceWithBadgeOnly]),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: Self.appRootAndShell(forwarding: ["theme: Theme"]), dependencies: ["Feature"], omitsPackageName: true),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(try #require(output.modules["Feature"]).generatedFiles == [
			"Feature.swift": generatedFileHeader + """
			extension Service {
			    package convenience init(theme: Theme? = nil) {
			        let badge = Badge(theme: theme)
			        self.init(badge: badge)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_27F6F01DC5D0EF8E {}
			}
			""",
		])
		#expect(try #require(output.modules["App"]).generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension AppRoot {
			    public convenience init() {
			        func __safeDI_shellBuilder(theme: Theme) -> AppShell {
			            func __safeDI_service() -> Service {
			                _ = Service.__safeDI_Service_27F6F01DC5D0EF8E.self
			                return Service(theme: theme) // SafeDI could not verify that Service is in this package; `package` access is assumed.
			            }
			            let service: Service = __safeDI_service()
			            return AppShell(theme: theme, service: service)
			        }
			        let shellBuilder = Instantiator<AppShell> {
			            __safeDI_shellBuilder(theme: $0)
			        }
			        self.init(shellBuilder: shellBuilder)
			    }
			}
			""",
		])
	}

	// MARK: Rule L: a caller that reaches no tier is reported at the declarations whose widening makes a tier reachable

	@Test(arguments: MultiModuleIntegration.allCases, [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtCappingReceiverAlone_whenCallerReachesNoTierOfTwoSeamsWhoseReceiverRequiresParameter(integration: MultiModuleIntegration, seam: Bool) async {
		// `Detail`'s package initializer requires `logger`, so neither seam has a tier `App`, in another package, reaches:
		// `Detail` alone is reported, with its fix-it, once for both seams; widening it makes a public tier reachable, which
		// calls each seam's internal initializer inside `Feature`. Nothing is reported at the callers or at a generated
		// initializer, and the two seams' reports never merge into a location-less one. Inline reports `Detail` too.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let expected: [String: String] = [
				"moduleInfo-true": """
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5: error: `Detail`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				""",
				"moduleInfo-false": """
				\(Self.path(of: "Badge.swift", in: "Feature", fixtures, integration)):3:5: error: `Badge`’s initializer is `internal`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Badge.swift", in: "Feature", fixtures, integration)):3:5-3:5: fixit: public 
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5: error: `Detail`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				\(Self.path(of: "Panel.swift", in: "Feature", fixtures, integration)):3:5: error: `Panel`’s initializer is `internal`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Panel.swift", in: "Feature", fixtures, integration)):3:5-3:5: fixit: public 
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:5: error: `Screen`’s initializer is `internal`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:5-3:5: fixit: public 
				""",
				"swiftPackagePlugin-true": """
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5: error: `Detail`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				""",
				"swiftPackagePlugin-false": """
				\(Self.path(of: "Badge.swift", in: "Feature", fixtures, integration)):3:5: error: `Badge`’s initializer is `internal`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Badge.swift", in: "Feature", fixtures, integration)):3:5-3:5: fixit: public 
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5: error: `Detail`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				\(Self.path(of: "Panel.swift", in: "Feature", fixtures, integration)):3:5: error: `Panel`’s initializer is `internal`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Panel.swift", in: "Feature", fixtures, integration)):3:5-3:5: fixit: public 
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:5: error: `Screen`’s initializer is `internal`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:5-3:5: fixit: public 
				""",
			]
			return expected["\(integration)-\(seam)"] ?? ""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [Self.detailWithPackageInit, Self.badgeWithInternalInit] + Self.twoSeams(seam: seam)),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: Self.shellForwardingLogger, dependencies: ["Feature"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicTierOfEachSeam_whenCappingReceiverIsWidened(integration: MultiModuleIntegration) async throws {
		// The remedy: `Detail` public gives each seam a public tier taking `logger`, which `App` calls.
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: [
					"""
					@Instantiable
					public struct Detail: Instantiable {
					    public init(logger: Logger) {
					        self.logger = logger
					    }

					    @Received let logger: Logger
					}

					public struct Logger: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Badge: Instantiable {
					    init(theme: Theme?) {
					        self.theme = theme
					    }

					    @Received(onlyIfAvailable: true) public let theme: Theme?
					}

					public struct Theme: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    init(detail: Detail, badge: Badge) {
					        self.detail = detail
					        self.badge = badge
					    }

					    @Instantiated let detail: Detail
					    @Instantiated let badge: Badge
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Panel: Instantiable {
					    init(detail: Detail, badge: Badge) {
					        self.detail = detail
					        self.badge = badge
					    }

					    @Instantiated let detail: Detail
					    @Instantiated let badge: Badge
					}
					""",
				],
			),
			ModuleFixture(
				name: "App",
				packageName: "Other",
				swiftFileContent: [
					"""
					import Feature

					@Instantiable(isRoot: true)
					public final class AppRoot: Instantiable {
					    public init(shellBuilder: Instantiator<Shell>) {
					        self.shellBuilder = shellBuilder
					    }

					    @Instantiated let shellBuilder: Instantiator<Shell>
					}
					""",
					"""
					import Feature

					@Instantiable
					public final class Shell: Instantiable {
					    public init(logger: Logger, screen: Screen, panel: Panel) {
					        self.logger = logger
					        self.screen = screen
					        self.panel = panel
					    }

					    @Forwarded let logger: Logger
					    @Instantiated let screen: Screen
					    @Instantiated let panel: Panel
					}
					""",
				],
				dependencies: ["Feature"],
			),
		], integration: integration, filesToDelete: &filesToDelete)
		let expectedFeatureFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Feature.swift": generatedFileHeader + """
				extension Panel {
				    public convenience init(logger: Logger) {
				        self.init(logger: logger, theme: nil)
				    }

				    internal convenience init(logger: Logger, theme: Theme? = nil) {
				        let detail = Detail(logger: logger)
				        let badge = Badge(theme: theme)
				        self.init(detail: detail, badge: badge)
				    }
				}

				extension Panel {
				    public enum __safeDI_Panel_0239F7DB303C2FB8 {}
				}

				extension Screen {
				    public convenience init(logger: Logger) {
				        self.init(logger: logger, theme: nil)
				    }

				    internal convenience init(logger: Logger, theme: Theme? = nil) {
				        let detail = Detail(logger: logger)
				        let badge = Badge(theme: theme)
				        self.init(detail: detail, badge: badge)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_0239F7DB303C2FB8 {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Panel+SafeDI.swift": generatedFileHeader + """
				extension Panel {
				    public convenience init(logger: Logger) {
				        self.init(logger: logger, theme: nil)
				    }

				    internal convenience init(logger: Logger, theme: Theme? = nil) {
				        let detail = Detail(logger: logger)
				        let badge = Badge(theme: theme)
				        self.init(detail: detail, badge: badge)
				    }
				}

				extension Panel {
				    public enum __safeDI_Panel_0239F7DB303C2FB8 {}
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(logger: Logger) {
				        self.init(logger: logger, theme: nil)
				    }

				    internal convenience init(logger: Logger, theme: Theme? = nil) {
				        let detail = Detail(logger: logger)
				        let badge = Badge(theme: theme)
				        self.init(detail: detail, badge: badge)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_0239F7DB303C2FB8 {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles[integration])
		let expectedAppFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension AppRoot {
				    public convenience init() {
				        func __safeDI_shellBuilder(logger: Logger) -> Shell {
				            func __safeDI_screen() -> Screen {
				                _ = Screen.__safeDI_Screen_0239F7DB303C2FB8.self
				                return Screen(logger: logger)
				            }
				            let screen: Screen = __safeDI_screen()
				            func __safeDI_panel() -> Panel {
				                _ = Panel.__safeDI_Panel_0239F7DB303C2FB8.self
				                return Panel(logger: logger)
				            }
				            let panel: Panel = __safeDI_panel()
				            return Shell(logger: logger, screen: screen, panel: panel)
				        }
				        let shellBuilder = Instantiator<Shell> {
				            __safeDI_shellBuilder(logger: $0)
				        }
				        self.init(shellBuilder: shellBuilder)
				    }
				}
				""",
			],
			.swiftPackagePlugin: [
				"AppRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension AppRoot {
				    public convenience init() {
				        func __safeDI_shellBuilder(logger: Logger) -> Shell {
				            func __safeDI_screen() -> Screen {
				                _ = Screen.__safeDI_Screen_0239F7DB303C2FB8.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				                return Screen(logger: logger)
				            }
				            let screen: Screen = __safeDI_screen()
				            func __safeDI_panel() -> Panel {
				                _ = Panel.__safeDI_Panel_0239F7DB303C2FB8.self // If this line does not compile, add the SafeDI plugin to the target that declares Panel.
				                return Panel(logger: logger)
				            }
				            let panel: Panel = __safeDI_panel()
				            return Shell(logger: logger, screen: screen, panel: panel)
				        }
				        let shellBuilder = Instantiator<Shell> {
				            __safeDI_shellBuilder(logger: $0)
				        }
				        self.init(shellBuilder: shellBuilder)
				    }
				}
				""",
			],
		]
		#expect(try #require(output.modules["App"]).generatedFiles == expectedAppFiles[integration])
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtEachSeamsOwnInitializer_whenCallerReachesNoTierAndOnlyOptionalParametersAreWider(integration: MultiModuleIntegration) async {
		// Every parameter is optional and nothing caps a tier but the seams' own internal initializers: each is reported, located,
		// with its fix-it, in source order; widening it makes its level the widest tier, taking the parameters at that level and
		// passing `nil` for the rest.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let expected: [String: String] = [
				"moduleInfo": """
				\(Self.path(of: "Panel.swift", in: "Feature", fixtures, integration)):3:5: error: `Panel`’s initializer is `internal`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Panel.swift", in: "Feature", fixtures, integration)):3:5-3:5: fixit: public 
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:5: error: `Screen`’s initializer is `internal`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:5-3:5: fixit: public 
				""",
				"swiftPackagePlugin": """
				\(Self.path(of: "Panel.swift", in: "Feature", fixtures, integration)):3:5: error: `Panel`’s initializer is `internal`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Panel.swift", in: "Feature", fixtures, integration)):3:5-3:5: fixit: public 
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:5: error: `Screen`’s initializer is `internal`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:5-3:5: fixit: public 
				""",
			]
			return expected["\(integration)"] ?? ""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [
						"""
						@Instantiable
						public struct Badge: Instantiable {
						    package init(theme: Theme?) {
						        self.theme = theme
						    }

						    @Received(onlyIfAvailable: true) public let theme: Theme?
						}

						public struct Theme: Sendable {
						    public init() {}
						}
						""",
						"""
						@Instantiable
						public struct Tint: Instantiable {
						    init(color: Color?) {
						        self.color = color
						    }

						    @Received(onlyIfAvailable: true) let color: Color?
						}

						public struct Color: Sendable {
						    public init() {}
						}
						""",
						"""
						@Instantiable(generateDependencyTree: true)
						public final class Screen: Instantiable {
						    init(badge: Badge, tint: Tint) {
						        self.badge = badge
						        self.tint = tint
						    }

						    @Instantiated let badge: Badge
						    @Instantiated let tint: Tint
						}
						""",
						"""
						@Instantiable(generateDependencyTree: true)
						public final class Panel: Instantiable {
						    init(badge: Badge, tint: Tint) {
						        self.badge = badge
						        self.tint = tint
						    }

						    @Instantiated let badge: Badge
						    @Instantiated let tint: Tint
						}
						""",
					],
				),
				ModuleFixture(
					name: "App",
					packageName: "Other",
					swiftFileContent: [
						"""
						import Feature

						@Instantiable(isRoot: true)
						public final class AppRoot: Instantiable {
						    public init(screen: Screen, panel: Panel) {
						        self.screen = screen
						        self.panel = panel
						    }

						    @Instantiated let screen: Screen
						    @Instantiated let panel: Panel
						}
						""",
					],
					dependencies: ["Feature"],
				),
			], integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicTierOfEachSeam_whenBothSeamsOwnInitializersAreWidened(integration: MultiModuleIntegration) async throws {
		// The remedy applied to both seams: each gets a public tier passing `nil`, a package tier taking `theme`, and an internal
		// tier taking both.
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: [
					"""
					@Instantiable
					public struct Badge: Instantiable {
					    package init(theme: Theme?) {
					        self.theme = theme
					    }

					    @Received(onlyIfAvailable: true) public let theme: Theme?
					}

					public struct Theme: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Tint: Instantiable {
					    init(color: Color?) {
					        self.color = color
					    }

					    @Received(onlyIfAvailable: true) let color: Color?
					}

					public struct Color: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    public init(badge: Badge, tint: Tint) {
					        self.badge = badge
					        self.tint = tint
					    }

					    @Instantiated let badge: Badge
					    @Instantiated let tint: Tint
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Panel: Instantiable {
					    public init(badge: Badge, tint: Tint) {
					        self.badge = badge
					        self.tint = tint
					    }

					    @Instantiated let badge: Badge
					    @Instantiated let tint: Tint
					}
					""",
				],
			),
			ModuleFixture(
				name: "App",
				packageName: "Other",
				swiftFileContent: [
					"""
					import Feature

					@Instantiable(isRoot: true)
					public final class AppRoot: Instantiable {
					    public init(screen: Screen, panel: Panel) {
					        self.screen = screen
					        self.panel = panel
					    }

					    @Instantiated let screen: Screen
					    @Instantiated let panel: Panel
					}
					""",
				],
				dependencies: ["Feature"],
			),
		], integration: integration, filesToDelete: &filesToDelete)
		let expectedFeatureFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Feature.swift": generatedFileHeader + """
				extension Panel {
				    public convenience init() {
				        self.init(theme: nil)
				    }

				    package convenience init(theme: Theme? = nil) {
				        self.init(color: nil, theme: theme)
				    }

				    internal convenience init(color: Color? = nil, theme: Theme? = nil) {
				        let badge = Badge(theme: theme)
				        let tint = Tint(color: color)
				        self.init(badge: badge, tint: tint)
				    }
				}

				extension Panel {
				    public enum __safeDI_Panel_ABE36B831DA065A6 {}
				}

				extension Screen {
				    public convenience init() {
				        self.init(theme: nil)
				    }

				    package convenience init(theme: Theme? = nil) {
				        self.init(color: nil, theme: theme)
				    }

				    internal convenience init(color: Color? = nil, theme: Theme? = nil) {
				        let badge = Badge(theme: theme)
				        let tint = Tint(color: color)
				        self.init(badge: badge, tint: tint)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_ABE36B831DA065A6 {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Panel+SafeDI.swift": generatedFileHeader + """
				extension Panel {
				    public convenience init() {
				        self.init(theme: nil)
				    }

				    package convenience init(theme: Theme? = nil) {
				        self.init(color: nil, theme: theme)
				    }

				    internal convenience init(color: Color? = nil, theme: Theme? = nil) {
				        let badge = Badge(theme: theme)
				        let tint = Tint(color: color)
				        self.init(badge: badge, tint: tint)
				    }
				}

				extension Panel {
				    public enum __safeDI_Panel_ABE36B831DA065A6 {}
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init() {
				        self.init(theme: nil)
				    }

				    package convenience init(theme: Theme? = nil) {
				        self.init(color: nil, theme: theme)
				    }

				    internal convenience init(color: Color? = nil, theme: Theme? = nil) {
				        let badge = Badge(theme: theme)
				        let tint = Tint(color: color)
				        self.init(badge: badge, tint: tint)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_ABE36B831DA065A6 {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles[integration])
		let expectedAppFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension AppRoot {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_ABE36B831DA065A6.self
				            return Screen()
				        }
				        let screen: Screen = __safeDI_screen()
				        func __safeDI_panel() -> Panel {
				            _ = Panel.__safeDI_Panel_ABE36B831DA065A6.self
				            return Panel()
				        }
				        let panel: Panel = __safeDI_panel()
				        self.init(screen: screen, panel: panel)
				    }
				}
				""",
			],
			.swiftPackagePlugin: [
				"AppRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension AppRoot {
				    public convenience init() {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_ABE36B831DA065A6.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen()
				        }
				        let screen: Screen = __safeDI_screen()
				        func __safeDI_panel() -> Panel {
				            _ = Panel.__safeDI_Panel_ABE36B831DA065A6.self // If this line does not compile, add the SafeDI plugin to the target that declares Panel.
				            return Panel()
				        }
				        let panel: Panel = __safeDI_panel()
				        self.init(screen: screen, panel: panel)
				    }
				}
				""",
			],
		]
		#expect(try #require(output.modules["App"]).generatedFiles == expectedAppFiles[integration])
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtRemainingSeamsOwnInitializer_whenOnlyOneOfTwoSeamsOwnInitializersIsWidened(integration: MultiModuleIntegration) async {
		// Only `Screen` widened: `Panel`'s own initializer alone is reported, which the merge of location-less reports hid.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let expected: [String: String] = [
				"moduleInfo": """
				\(Self.path(of: "Panel.swift", in: "Feature", fixtures, integration)):3:5: error: `Panel`’s initializer is `internal`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Panel.swift", in: "Feature", fixtures, integration)):3:5-3:5: fixit: public 
				""",
				"swiftPackagePlugin": """
				\(Self.path(of: "Panel.swift", in: "Feature", fixtures, integration)):3:5: error: `Panel`’s initializer is `internal`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Panel.swift", in: "Feature", fixtures, integration)):3:5-3:5: fixit: public 
				""",
			]
			return expected["\(integration)"] ?? ""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [
						"""
						@Instantiable
						public struct Badge: Instantiable {
						    package init(theme: Theme?) {
						        self.theme = theme
						    }

						    @Received(onlyIfAvailable: true) public let theme: Theme?
						}

						public struct Theme: Sendable {
						    public init() {}
						}
						""",
						"""
						@Instantiable
						public struct Tint: Instantiable {
						    init(color: Color?) {
						        self.color = color
						    }

						    @Received(onlyIfAvailable: true) let color: Color?
						}

						public struct Color: Sendable {
						    public init() {}
						}
						""",
						"""
						@Instantiable(generateDependencyTree: true)
						public final class Screen: Instantiable {
						    public init(badge: Badge, tint: Tint) {
						        self.badge = badge
						        self.tint = tint
						    }

						    @Instantiated let badge: Badge
						    @Instantiated let tint: Tint
						}
						""",
						"""
						@Instantiable(generateDependencyTree: true)
						public final class Panel: Instantiable {
						    init(badge: Badge, tint: Tint) {
						        self.badge = badge
						        self.tint = tint
						    }

						    @Instantiated let badge: Badge
						    @Instantiated let tint: Tint
						}
						""",
					],
				),
				ModuleFixture(
					name: "App",
					packageName: "Other",
					swiftFileContent: [
						"""
						import Feature

						@Instantiable(isRoot: true)
						public final class AppRoot: Instantiable {
						    public init(screen: Screen, panel: Panel) {
						        self.screen = screen
						        self.panel = panel
						    }

						    @Instantiated let screen: Screen
						    @Instantiated let panel: Panel
						}
						""",
					],
					dependencies: ["Feature"],
				),
			], integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtCappingReceiverAndSeamsType_whenPackageSeamTypesCallerReachesNoTier(integration: MultiModuleIntegration) async {
		// `Screen`'s type is package, as are its own initializer and `Reader`'s, which requires `token`: `Reader`'s initializer and
		// `Screen`'s type are reported, each with a fix-it; the own initializer, which the type caps, is not.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let expected: [String: String] = [
				"moduleInfo": """
				\(Self.path(of: "Reader.swift", in: "Feature", fixtures, integration)):3:5: error: `Reader`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Reader.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):2:1: error: `Screen` is `package`, so module `App`, in another package, cannot construct it in the code SafeDI generates. Make `Screen` `public` to fix.
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):2:1-2:8: fixit: public
				""",
				"swiftPackagePlugin": """
				\(Self.path(of: "Reader.swift", in: "Feature", fixtures, integration)):3:5: error: `Reader`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Reader.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):2:1: error: `Screen` is `package`, so module `App`, in another package, cannot construct it in the code SafeDI generates. Make `Screen` `public` to fix.
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):2:1-2:8: fixit: public
				""",
			]
			return expected["\(integration)"] ?? ""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [
						"""
						@Instantiable
						public struct Token: Instantiable {
						    public init() {}
						}
						""",
						"""
						@Instantiable
						public struct Reader: Instantiable {
						    package init(token: Token) {
						        self.token = token
						    }

						    @Received let token: Token
						}
						""",
						"""
						@Instantiable(generateDependencyTree: true)
						package struct Screen: Instantiable {
						    package init(reader: Reader) {
						        self.reader = reader
						    }

						    @Instantiated let reader: Reader
						}
						""",
					],
				),
				ModuleFixture(
					name: "App",
					packageName: "Other",
					swiftFileContent: [
						"""
						import Feature

						@Instantiable(isRoot: true)
						public final class AppRoot: Instantiable {
						    public init(token: Token, screen: Screen) {
						        self.token = token
						        self.screen = screen
						    }

						    @Instantiated let token: Token
						    @Instantiated let screen: Screen
						}
						""",
					],
					dependencies: ["Feature"],
				),
			], integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtCappingReceiverAlone_whenSamePackageCallerReachesNoTierOfSeamWithInternalInitializers(integration: MultiModuleIntegration) async {
		// `Detail`'s internal initializer requires `logger` and `Screen`'s own initializer is internal: a caller in the same
		// package reaches no tier, and `Detail` alone is reported, with `package` as its fix-it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let expected: [String: String] = [
				"moduleInfo": """
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5: error: `Detail`’s initializer is `internal`, so module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make the initializer `package` to fix.
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5-3:5: fixit: package 
				""",
				"swiftPackagePlugin": """
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5: error: `Detail`’s initializer is `internal`, so module `App`, another module of the same package, cannot call it in the code SafeDI generates. Make the initializer `package` to fix.
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5-3:5: fixit: package 
				""",
			]
			return expected["\(integration)"] ?? ""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [
						"""
						@Instantiable
						public struct Logger: Instantiable {
						    public init() {}
						}
						""",
						"""
						@Instantiable
						public struct Detail: Instantiable {
						    init(logger: Logger) {
						        self.logger = logger
						    }

						    @Received let logger: Logger
						}
						""",
						"""
						@Instantiable(generateDependencyTree: true)
						public struct Screen: Instantiable {
						    init(detail: Detail) {
						        self.detail = detail
						    }

						    @Instantiated let detail: Detail
						}
						""",
					],
				),
				ModuleFixture(
					name: "App",
					packageName: "Shop",
					swiftFileContent: [
						"""
						import Feature

						@Instantiable(isRoot: true)
						public final class AppRoot: Instantiable {
						    public init(logger: Logger, screen: Screen) {
						        self.logger = logger
						        self.screen = screen
						    }

						    @Instantiated let logger: Logger
						    @Instantiated let screen: Screen
						}
						""",
					],
					dependencies: ["Feature"],
				),
			], integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicTier_whenCappingReceiverIsWidenedBesidePackageOwnInitializer(integration: MultiModuleIntegration) async throws {
		// `Reader` public beside `Screen`'s package own initializer gives public and package tiers; `App` calls the public one,
		// which calls the package initializer inside `Feature`.
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: [
					"""
					@Instantiable
					public struct Token: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct Reader: Instantiable {
					    public init(token: Token) {
					        self.token = token
					    }

					    @Received let token: Token
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public struct Screen: Instantiable {
					    package init(reader: Reader) {
					        self.reader = reader
					    }

					    @Instantiated let reader: Reader
					}
					""",
				],
			),
			ModuleFixture(
				name: "App",
				packageName: "Other",
				swiftFileContent: [
					"""
					import Feature

					@Instantiable(isRoot: true)
					public final class AppRoot: Instantiable {
					    public init(token: Token, screen: Screen) {
					        self.token = token
					        self.screen = screen
					    }

					    @Instantiated let token: Token
					    @Instantiated let screen: Screen
					}
					""",
				],
				dependencies: ["Feature"],
			),
		], integration: integration, filesToDelete: &filesToDelete)
		let expectedFeatureFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Feature.swift": generatedFileHeader + """
				extension Screen {
				    public init(token: Token) {
				        let reader = Reader(token: token)
				        self.init(reader: reader)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_1EB503BFA23A82BA {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public init(token: Token) {
				        let reader = Reader(token: token)
				        self.init(reader: reader)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_1EB503BFA23A82BA {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles[integration])
		let expectedAppFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension AppRoot {
				    public convenience init() {
				        let token = Token()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_1EB503BFA23A82BA.self
				            return Screen(token: token)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(token: token, screen: screen)
				    }
				}
				""",
			],
			.swiftPackagePlugin: [
				"AppRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension AppRoot {
				    public convenience init() {
				        let token = Token()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_1EB503BFA23A82BA.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen(token: token)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(token: token, screen: screen)
				    }
				}
				""",
			],
		]
		#expect(try #require(output.modules["App"]).generatedFiles == expectedAppFiles[integration])
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases, [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtCappingReceiverAndSeamsOwnInitializer_whenSeamHasOwnParameterAndCallerReachesNoTier(integration: MultiModuleIntegration, seam: Bool) async {
		// `Screen` has an own parameter, `token`, taken on the widest tier at its own initializer's level, so that initializer
		// caps the tier too: both `Reader`'s initializer and `Screen`'s are reported, each with its fix-it, as inline
		// reports both. Widening `Reader` alone makes the seam's module report an omission instead.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let expected: [String: String] = [
				"moduleInfo-true": """
				\(Self.path(of: "Reader.swift", in: "Feature", fixtures, integration)):3:5: error: `Reader`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Reader.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:5: error: `Screen`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				""",
				"moduleInfo-false": """
				\(Self.path(of: "Reader.swift", in: "Feature", fixtures, integration)):3:5: error: `Reader`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Reader.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:5: error: `Screen`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				""",
				"swiftPackagePlugin-true": """
				\(Self.path(of: "Reader.swift", in: "Feature", fixtures, integration)):3:5: error: `Reader`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Reader.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:5: error: `Screen`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				""",
				"swiftPackagePlugin-false": """
				\(Self.path(of: "Reader.swift", in: "Feature", fixtures, integration)):3:5: error: `Reader`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Reader.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:5: error: `Screen`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				""",
			]
			return expected["\(integration)-\(seam)"] ?? ""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [Self.readerWithPackageInitReceivingSession, Self.screenWithOwnToken(seam: seam)]),
					ModuleFixture(name: "App", packageName: "Other", swiftFileContent: Self.shellForwardingTokenAndSession, dependencies: ["Feature"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicTier_whenCappingReceiverAndSeamsOwnInitializerAreBothWidened(integration: MultiModuleIntegration) async throws {
		// The remedy: both public, `App` calls `Screen(token:session:)`.
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: [
					"""
					@Instantiable
					public struct Reader: Instantiable {
					    public init(session: Session) {
					        self.session = session
					    }

					    @Received let session: Session
					}

					public final class Secret: Sendable {
					    public init() {}
					}

					public final class Session: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    public init(token: Secret, reader: Reader) {
					        self.token = token
					        self.reader = reader
					    }

					    @Received let token: Secret
					    @Instantiated let reader: Reader
					}
					""",
				],
			),
			ModuleFixture(
				name: "App",
				packageName: "Other",
				swiftFileContent: [
					"""
					import Feature

					@Instantiable(isRoot: true)
					public final class AppRoot: Instantiable {
					    public init(shellBuilder: Instantiator<Shell>) {
					        self.shellBuilder = shellBuilder
					    }

					    @Instantiated public let shellBuilder: Instantiator<Shell>
					}
					""",
					"""
					import Feature

					@Instantiable
					public final class Shell: Instantiable {
					    public init(token: Secret, session: Session, screen: Screen) {
					        self.token = token
					        self.session = session
					        self.screen = screen
					    }

					    @Forwarded let token: Secret
					    @Forwarded let session: Session
					    @Instantiated let screen: Screen
					}
					""",
				],
				dependencies: ["Feature"],
			),
		], integration: integration, filesToDelete: &filesToDelete)
		let expectedFeatureFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Feature.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: Secret, session: Session) {
				        let reader = Reader(session: session)
				        self.init(token: token, reader: reader)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_09A4EABC2C08A72C {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: Secret, session: Session) {
				        let reader = Reader(session: session)
				        self.init(token: token, reader: reader)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_09A4EABC2C08A72C {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles[integration])
		let expectedAppFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"App.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension AppRoot {
				    public convenience init() {
				        func __safeDI_shellBuilder(session: Session, token: Secret) -> Shell {
				            func __safeDI_screen() -> Screen {
				                _ = Screen.__safeDI_Screen_09A4EABC2C08A72C.self
				                return Screen(token: token, session: session)
				            }
				            let screen: Screen = __safeDI_screen()
				            return Shell(token: token, session: session, screen: screen)
				        }
				        let shellBuilder = Instantiator<Shell> {
				            __safeDI_shellBuilder(session: $0.session, token: $0.token)
				        }
				        self.init(shellBuilder: shellBuilder)
				    }
				}
				""",
			],
			.swiftPackagePlugin: [
				"AppRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension AppRoot {
				    public convenience init() {
				        func __safeDI_shellBuilder(session: Session, token: Secret) -> Shell {
				            func __safeDI_screen() -> Screen {
				                _ = Screen.__safeDI_Screen_09A4EABC2C08A72C.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				                return Screen(token: token, session: session)
				            }
				            let screen: Screen = __safeDI_screen()
				            return Shell(token: token, session: session, screen: screen)
				        }
				        let shellBuilder = Instantiator<Shell> {
				            __safeDI_shellBuilder(session: $0.session, token: $0.token)
				        }
				        self.init(shellBuilder: shellBuilder)
				    }
				}
				""",
			],
		]
		#expect(try #require(output.modules["App"]).generatedFiles == expectedAppFiles[integration])
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsOmissionErrorInSeamsModule_whenCappingReceiverIsWidenedAloneBesideSeamsOwnParameter(integration: MultiModuleIntegration) async {
		// Widening `Reader` alone: the public tier it gives cannot take `token`, the seam's own parameter, which `Feature` reports
		// as the omission at `Screen`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let expected: [String: String] = [
				"moduleInfo": """
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `token: Secret`, which `Screen`'s own initializer receives at a narrower access level, and cannot pass `nil` for it, since it is required. Widen the initializer of `Screen`, or narrow the initializers of every type in the tree to its level.
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):8:5: note: `Screen` receives `token: Secret` here.
				""",
				"swiftPackagePlugin": """
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `token: Secret`, which `Screen`'s own initializer receives at a narrower access level, and cannot pass `nil` for it, since it is required. Widen the initializer of `Screen`, or narrow the initializers of every type in the tree to its level.
				\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):8:5: note: `Screen` receives `token: Secret` here.
				""",
			]
			return expected["\(integration)"] ?? ""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [
						"""
						@Instantiable
						public struct Reader: Instantiable {
						    public init(session: Session) {
						        self.session = session
						    }

						    @Received let session: Session
						}

						public final class Secret: Sendable {
						    public init() {}
						}

						public final class Session: Sendable {
						    public init() {}
						}
						""",
						"""
						@Instantiable(generateDependencyTree: true)
						public final class Screen: Instantiable {
						    package init(token: Secret, reader: Reader) {
						        self.token = token
						        self.reader = reader
						    }

						    @Received let token: Secret
						    @Instantiated let reader: Reader
						}
						""",
					],
				),
				ModuleFixture(
					name: "App",
					packageName: "Other",
					swiftFileContent: [
						"""
						import Feature

						@Instantiable(isRoot: true)
						public final class AppRoot: Instantiable {
						    public init(shellBuilder: Instantiator<Shell>) {
						        self.shellBuilder = shellBuilder
						    }

						    @Instantiated public let shellBuilder: Instantiator<Shell>
						}
						""",
						"""
						import Feature

						@Instantiable
						public final class Shell: Instantiable {
						    public init(token: Secret, session: Session, screen: Screen) {
						        self.token = token
						        self.session = session
						        self.screen = screen
						    }

						    @Forwarded let token: Secret
						    @Forwarded let session: Session
						    @Instantiated let screen: Screen
						}
						""",
					],
					dependencies: ["Feature"],
				),
			], integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtSeamsTypeAlone_whenPackageSeamTypeHasPublicOwnInitializerAndCallerReachesNoTier(integration: MultiModuleIntegration) async {
		// `Service`'s type is package and its own initializer spelled public: the type alone is reported, with its fix-it, since
		// only the type caps.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let expected: [String: String] = [
				"moduleInfo": """
				\(Self.path(of: "Service.swift", in: "Feature", fixtures, integration)):2:1: error: `Service` is `package`, so module `App`, in another package, cannot construct it in the code SafeDI generates. Make `Service` `public` to fix.
				\(Self.path(of: "Service.swift", in: "Feature", fixtures, integration)):2:1-2:8: fixit: public
				""",
				"swiftPackagePlugin": """
				\(Self.path(of: "Service.swift", in: "Feature", fixtures, integration)):2:1: error: `Service` is `package`, so module `App`, in another package, cannot construct it in the code SafeDI generates. Make `Service` `public` to fix.
				\(Self.path(of: "Service.swift", in: "Feature", fixtures, integration)):2:1-2:8: fixit: public
				""",
			]
			return expected["\(integration)"] ?? ""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [
						"""
						@Instantiable
						public struct Badge: Instantiable {
						    public init(theme: Theme?) {
						        self.theme = theme
						    }

						    @Received(onlyIfAvailable: true) public let theme: Theme?
						}

						public struct Theme: Sendable {
						    public init() {}
						}
						""",
						"""
						@Instantiable(generateDependencyTree: true)
						package final class Service: Instantiable {
						    public init(badge: Badge) {
						        self.badge = badge
						    }

						    @Instantiated public let badge: Badge
						}
						""",
					],
				),
				ModuleFixture(
					name: "App",
					packageName: "Other",
					swiftFileContent: [
						"""
						import Feature

						@Instantiable(isRoot: true)
						public final class AppRoot: Instantiable {
						    public init(shellBuilder: Instantiator<AppShell>) {
						        self.shellBuilder = shellBuilder
						    }

						    @Instantiated public let shellBuilder: Instantiator<AppShell>
						}
						""",
						"""
						import Feature

						@Instantiable
						public final class AppShell: Instantiable {
						    public init(theme: Theme, service: Service) {
						        self.theme = theme
						        self.service = service
						    }

						    @Forwarded public let theme: Theme
						    @Instantiated public let service: Service
						}
						""",
					],
					dependencies: ["Feature"],
				),
			], integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtSeamsTypeAndOwnInitializer_whenPackageSeamTypeHasPackageOwnInitializerAndOnlyOptionalParameters(integration: MultiModuleIntegration) async {
		// A package seam type with a package own initializer and only optional pass-throughs, called from another package: the
		// type and its own initializer are each reported with a fix-it, as today.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let expected: [String: String] = [
				"moduleInfo": """
				\(Self.path(of: "Service.swift", in: "Feature", fixtures, integration)):2:1: error: `Service` is `package`, so module `App`, in another package, cannot construct it in the code SafeDI generates. Make `Service` `public` to fix.
				\(Self.path(of: "Service.swift", in: "Feature", fixtures, integration)):2:1-2:8: fixit: public
				\(Self.path(of: "Service.swift", in: "Feature", fixtures, integration)):3:5: error: `Service`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Service.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				""",
				"swiftPackagePlugin": """
				\(Self.path(of: "Service.swift", in: "Feature", fixtures, integration)):2:1: error: `Service` is `package`, so module `App`, in another package, cannot construct it in the code SafeDI generates. Make `Service` `public` to fix.
				\(Self.path(of: "Service.swift", in: "Feature", fixtures, integration)):2:1-2:8: fixit: public
				\(Self.path(of: "Service.swift", in: "Feature", fixtures, integration)):3:5: error: `Service`’s initializer is `package`, so module `App`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Service.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				""",
			]
			return expected["\(integration)"] ?? ""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [
				ModuleFixture(
					name: "Feature",
					packageName: "Shop",
					swiftFileContent: [
						"""
						@Instantiable
						public struct Badge: Instantiable {
						    package init(theme: Theme?) {
						        self.theme = theme
						    }

						    @Received(onlyIfAvailable: true) public let theme: Theme?
						}

						public struct Theme: Sendable {
						    public init() {}
						}
						""",
						"""
						@Instantiable(generateDependencyTree: true)
						package final class Service: Instantiable {
						    package init(badge: Badge) {
						        self.badge = badge
						    }

						    @Instantiated public let badge: Badge
						}
						""",
					],
				),
				ModuleFixture(
					name: "App",
					packageName: "Other",
					swiftFileContent: [
						"""
						import Feature

						@Instantiable(isRoot: true)
						public final class AppRoot: Instantiable {
						    public init(shellBuilder: Instantiator<AppShell>) {
						        self.shellBuilder = shellBuilder
						    }

						    @Instantiated public let shellBuilder: Instantiator<AppShell>
						}
						""",
						"""
						import Feature

						@Instantiable
						public final class AppShell: Instantiable {
						    public init(theme: Theme, service: Service) {
						        self.theme = theme
						        self.service = service
						    }

						    @Forwarded public let theme: Theme
						    @Instantiated public let service: Service
						}
						""",
					],
					dependencies: ["Feature"],
				),
			], integration: integration, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Rule W: the omission error names a seam's own only-if-available receive as such

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsOmissionErrorNamingOnlyIfAvailableReceive_whenWiderTierCannotTakeSeamsOwnOnlyIfAvailableReceive() async {
		// `Reader`'s public initializer gives `session` a public tier, which cannot take the seam's own `token`, received only if
		// available but taken as declared, with no default: the error says so, rather than calling the receive required.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `token: Secret?`, which `Screen`'s own initializer receives at a narrower access level, and cannot pass `nil` for it: `Screen` receives `token` only if available, but its generated initializers take each of `Screen`'s own properties as declared, with no default. Widen the initializer of `Screen`, or narrow the initializers of every type in the tree to its level.
			\(fixtures["Screen.swift"]):8:5: note: `Screen` receives `token: Secret?` here.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				"""
				@Instantiable
				public final class Secret: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Session: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Reader: Instantiable {
				    public init(session: Session?) {
				        self.session = session
				    }

				    @Received(onlyIfAvailable: true) let session: Session?
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public final class Screen: Instantiable {
				    init(token: Secret?, reader: Reader) {
				        self.token = token
				        self.reader = reader
				    }

				    @Received(onlyIfAvailable: true) let token: Secret?
				    @Instantiated let reader: Reader
				}
				""",
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(token: Secret, session: Session, screen: Screen) {
				        self.token = token
				        self.session = session
				        self.screen = screen
				    }

				    @Instantiated let token: Secret
				    @Instantiated let session: Session
				    @Instantiated let screen: Screen
				}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsOmissionErrorNamingRequiredReceive_whenWiderTierCannotTakeSeamsOwnRequiredOptionalReceive() async {
		// The seam's own required `token: Secret?`: the error says it is required, which is true. The seam's own generation
		// reports it, whatever calls the seam.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `token: Secret?`, which `Screen`'s own initializer receives at a narrower access level, and cannot pass `nil` for it, since it is required. Widen the initializer of `Screen`, or narrow the initializers of every type in the tree to its level.
			\(fixtures["Screen.swift"]):8:5: note: `Screen` receives `token: Secret?` here.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				"""
				@Instantiable
				public final class Secret: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Session: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Reader: Instantiable {
				    public init(session: Session?) {
				        self.session = session
				    }

				    @Received(onlyIfAvailable: true) let session: Session?
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public final class Screen: Instantiable {
				    init(token: Secret?, reader: Reader) {
				        self.token = token
				        self.reader = reader
				    }

				    @Received let token: Secret?
				    @Instantiated let reader: Reader
				}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsOmissionErrorNamingOwnForwardedProperty_whenWiderTierCannotTakeSeamsOwnForwardedProperty() async {
		// The seam's own forwarded `token: Secret` sits at its own initializer's level, so the public tier that `Reader`'s
		// receive makes cannot take it: the error says the seam's own initializer takes it, since it is required.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `token: Secret`, which `Screen`'s own initializer takes at a narrower access level, and cannot pass `nil` for it, since it is required. Widen the initializer of `Screen`, or narrow the initializers of every type in the tree to its level.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				"""
				@Instantiable
				public final class Secret: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Session: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Reader: Instantiable {
				    public init(session: Session?) {
				        self.session = session
				    }

				    @Received(onlyIfAvailable: true) let session: Session?
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public final class Screen: Instantiable {
				    init(token: Secret, reader: Reader) {
				        self.token = token
				        self.reader = reader
				    }

				    @Forwarded let token: Secret
				    @Instantiated let reader: Reader
				}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: W4Holder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOwnOnlyIfAvailableReceiveWithoutDefault_whenSeamsOwnInitializerIsPublic(holder: W4Holder) async throws {
		// With a public own initializer the public tier takes `token` as declared and `session` with its default: a root holding
		// only `session` passes `nil` for `token`, one holding both passes both.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			holder.root,
			"""
			@Instantiable
			public final class Secret: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Session: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Reader: Instantiable {
			    public init(session: Session?) {
			        self.session = session
			    }

			    @Received(onlyIfAvailable: true) let session: Session?
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public final class Screen: Instantiable {
			    public init(token: Secret?, reader: Reader) {
			        self.token = token
			        self.reader = reader
			    }

			    @Received(onlyIfAvailable: true) let token: Secret?
			    @Instantiated let reader: Reader
			}
			""",
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let expectedOutput: [W4Holder: [String: String]] = [
			.session: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let session = Session()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_78E34217108FDC1A.self
				            return Screen(token: nil, session: session)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(session: session, screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: Secret?, session: Session? = nil) {
				        let reader = Reader(session: session)
				        self.init(token: token, reader: reader)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_78E34217108FDC1A {}
				}
				""",
			],
			.both: [
				"Root+SafeDI.swift": generatedFileHeader + """
				extension Root {
				    public convenience init() {
				        let token = Secret()
				        let session = Session()
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_78E34217108FDC1A.self
				            return Screen(token: token, session: session)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(token: token, session: session, screen: screen)
				    }
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(token: Secret?, session: Session? = nil) {
				        let reader = Reader(session: session)
				        self.init(token: token, reader: reader)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_78E34217108FDC1A {}
				}
				""",
			],
		]
		#expect(output.dependencyTreeFiles == expectedOutput[holder])
	}

	// MARK: Rule L through a nested seam the outer seam reaches no tier of

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsRuleLReportAtCappingReceiver_whenOuterSeamsTreeCallsNestedSeamItReachesNoTierOf(integration: MultiModuleIntegration) async {
		// `Outer`, in another package, reaches no tier of `Screen`, whose only tier is `package` because `Detail`'s initializer is: the
		// pass-through `logger` reaches `Outer` only through that call, so `Outer` reports no omission for it, and the check of every
		// construction reports `Detail`'s initializer with its fix-it, as it does where `Outer` is built inline.
		await assertThrowsMultiModuleError(inModule: "Mid", diagnostics: { fixtures in
			let expected: [MultiModuleIntegration: String] = [
				.moduleInfo: """
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5: error: `Detail`’s initializer is `package`, so module `Mid`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				""",
				.swiftPackagePlugin: """
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5: error: `Detail`’s initializer is `package`, so module `Mid`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				""",
			]
			return expected[integration] ?? ""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					public final class Logger: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Detail: Instantiable {
					    package init(logger: Logger) {
					        self.logger = logger
					    }

					    @Received let logger: Logger
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    init(detail: Detail) {
					        self.detail = detail
					    }

					    @Instantiated let detail: Detail
					}
					""",
				]),
				ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [
					"""
					import Feature

					@Instantiable(generateDependencyTree: true)
					public final class Outer: Instantiable {
					    public init(screen: Screen) {
					        self.screen = screen
					    }

					    @Instantiated let screen: Screen
					}
					""",
				], dependencies: ["Feature"]),
			], integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsRuleLReportAtCappingReceiver_whenPlainTypeInMidForwardsLoggerToNestedSeamItReachesNoTierOf(integration: MultiModuleIntegration) async {
		// The inline twin: `Outer` is a plain type forwarding `logger`, built by a root in `Mid`.
		await assertThrowsMultiModuleError(inModule: "Mid", diagnostics: { fixtures in
			let expected: [MultiModuleIntegration: String] = [
				.moduleInfo: """
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5: error: `Detail`’s initializer is `package`, so module `Mid`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				""",
				.swiftPackagePlugin: """
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5: error: `Detail`’s initializer is `package`, so module `Mid`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				""",
			]
			return expected[integration] ?? ""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					public final class Logger: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Detail: Instantiable {
					    package init(logger: Logger) {
					        self.logger = logger
					    }

					    @Received let logger: Logger
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    init(detail: Detail) {
					        self.detail = detail
					    }

					    @Instantiated let detail: Detail
					}
					""",
				]),
				ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [
					"""
					import Feature

					@Instantiable
					public final class Outer: Instantiable {
					    public init(logger: Logger, screen: Screen) {
					        self.logger = logger
					        self.screen = screen
					    }

					    @Forwarded let logger: Logger
					    @Instantiated let screen: Screen
					}
					""",
					"""
					import Feature

					@Instantiable(isRoot: true)
					public final class MidRoot: Instantiable {
					    public init(outerBuilder: Instantiator<Outer>) {
					        self.outerBuilder = outerBuilder
					    }

					    @Instantiated let outerBuilder: Instantiator<Outer>
					}
					""",
				], dependencies: ["Feature"]),
			], integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsOmissionErrorAtOuterSeam_whenCappingReceiversPackageIsUnknownSoNestedSeamCallIsNotReported() async {
		// `Detail`'s module names no package, so `Mid`'s check of every construction assumes `package` access reaches
		// `Detail` and reports nothing, while `Screen`'s package tier, in package `Shop`, is out of `Mid`'s reach: the
		// nested call is not certain to be reported, so `Outer` reports the omission of `logger`, as it does for any
		// receive. Only a build that names some modules' packages and not others' produces this: the build tool plugin
		// names every package, so the cell runs under the module info integration alone.
		await assertThrowsMultiModuleError(inModule: "Mid", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Outer.swift", in: "Mid", fixtures, .moduleInfo)):3:1: error: SafeDI cannot generate the dependency tree of `Outer`: its generated `public` initializer cannot take `logger: Logger`, which the initializer of `Detail` receives at a narrower access level, and cannot pass `nil` for it, since it is required. Widen the initializer of `Detail`, receive the property with `onlyIfAvailable: true` and an optional type, or narrow the initializers of every type in the tree to its level.
			\(Self.path(of: "Detail.swift", in: "Core", fixtures, .moduleInfo)):7:5: note: `Detail` receives `logger: Logger` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: [
					"""
					public final class Logger: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Detail: Instantiable {
					    package init(logger: Logger) {
					        self.logger = logger
					    }

					    @Received let logger: Logger
					}
					""",
				], omitsPackageName: true),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					import Core

					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    init(detail: Detail) {
					        self.detail = detail
					    }

					    @Instantiated let detail: Detail
					}
					""",
				], dependencies: ["Core"]),
				ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [
					"""
					import Feature

					@Instantiable(generateDependencyTree: true)
					public final class Outer: Instantiable {
					    public init(screen: Screen) {
					        self.screen = screen
					    }

					    @Instantiated let screen: Screen
					}
					""",
				], dependencies: ["Core", "Feature"]),
			], integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsRuleLReportAtCappingReceiver_whenOuterSeamsOwnInitializerIsNarrowedToPackage(integration: MultiModuleIntegration) async {
		// Narrowing `Outer` to `package init` changes nothing: `Detail` is still what caps the tier.
		await assertThrowsMultiModuleError(inModule: "Mid", diagnostics: { fixtures in
			let expected: [MultiModuleIntegration: String] = [
				.moduleInfo: """
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5: error: `Detail`’s initializer is `package`, so module `Mid`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				""",
				.swiftPackagePlugin: """
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5: error: `Detail`’s initializer is `package`, so module `Mid`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
				""",
			]
			return expected[integration] ?? ""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					public final class Logger: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Detail: Instantiable {
					    package init(logger: Logger) {
					        self.logger = logger
					    }

					    @Received let logger: Logger
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    init(detail: Detail) {
					        self.detail = detail
					    }

					    @Instantiated let detail: Detail
					}
					""",
				]),
				ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [
					"""
					import Feature

					@Instantiable(generateDependencyTree: true)
					public final class Outer: Instantiable {
					    package init(screen: Screen) {
					        self.screen = screen
					    }

					    @Instantiated let screen: Screen
					}
					""",
				], dependencies: ["Feature"]),
			], integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsOmissionErrorNamingOwnReceiver_whenOuterSeamsOwnTreeAlsoRequiresParameterNestedSeamCannotTake(integration: MultiModuleIntegration) async {
		// `Outer`'s own tree requires `logger` too, through `Own`, so the omission is `Outer`'s own and is reported, naming `Own`.
		await assertThrowsMultiModuleError(inModule: "Mid", diagnostics: { fixtures in
			let expected: [MultiModuleIntegration: String] = [
				.moduleInfo: """
				\(Self.path(of: "Outer.swift", in: "Mid", fixtures, integration)):3:1: error: SafeDI cannot generate the dependency tree of `Outer`: its generated `public` initializer cannot take `logger: Logger`, which the initializer of `Detail` and `Own` receives at a narrower access level, and cannot pass `nil` for it, since it is required. Widen the initializer of `Detail` and the initializer of `Own`, receive the property with `onlyIfAvailable: true` and an optional type, or narrow the initializers of every type in the tree to its level.
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):7:5: note: `Detail` receives `logger: Logger` here.
				\(Self.path(of: "Own.swift", in: "Feature", fixtures, integration)):7:5: note: `Own` receives `logger: Logger` here.
				""",
				.swiftPackagePlugin: """
				\(Self.path(of: "Outer.swift", in: "Mid", fixtures, integration)):3:1: error: SafeDI cannot generate the dependency tree of `Outer`: its generated `public` initializer cannot take `logger: Logger`, which the initializer of `Detail` and `Own` receives at a narrower access level, and cannot pass `nil` for it, since it is required. Widen the initializer of `Detail` and the initializer of `Own`, receive the property with `onlyIfAvailable: true` and an optional type, or narrow the initializers of every type in the tree to its level.
				\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):7:5: note: `Detail` receives `logger: Logger` here.
				\(Self.path(of: "Own.swift", in: "Feature", fixtures, integration)):7:5: note: `Own` receives `logger: Logger` here.
				""",
			]
			return expected[integration] ?? ""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					public final class Logger: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Detail: Instantiable {
					    package init(logger: Logger) {
					        self.logger = logger
					    }

					    @Received let logger: Logger
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    init(detail: Detail) {
					        self.detail = detail
					    }

					    @Instantiated let detail: Detail
					}
					""",
					"""
					@Instantiable
					public final class Own: Instantiable {
					    package init(logger: Logger) {
					        self.logger = logger
					    }

					    @Received let logger: Logger
					}
					""",
				]),
				ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [
					"""
					import Feature

					@Instantiable(generateDependencyTree: true)
					public final class Outer: Instantiable {
					    public init(screen: Screen, own: Own) {
					        self.screen = screen
					        self.own = own
					    }

					    @Instantiated let screen: Screen
					    @Instantiated let own: Own
					}
					""",
				], dependencies: ["Feature"]),
			], integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsNestedSeamsPublicTier_whenCappingReceiverIsWidened(integration: MultiModuleIntegration) async throws {
		// Widening `Detail` alone fixes it: `Screen` gets a public tier, which `Outer`'s public tier calls.
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"""
				public final class Logger: Sendable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Detail: Instantiable {
				    public init(logger: Logger) {
				        self.logger = logger
				    }

				    @Received let logger: Logger
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public final class Screen: Instantiable {
				    init(detail: Detail) {
				        self.detail = detail
				    }

				    @Instantiated let detail: Detail
				}
				""",
			]),
			ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [
				"""
				import Feature

				@Instantiable(generateDependencyTree: true)
				public final class Outer: Instantiable {
				    public init(screen: Screen) {
				        self.screen = screen
				    }

				    @Instantiated let screen: Screen
				}
				""",
			], dependencies: ["Feature"]),
		], integration: integration, filesToDelete: &filesToDelete)
		let expectedFeatureFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Feature.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(logger: Logger) {
				        let detail = Detail(logger: logger)
				        self.init(detail: detail)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_9BE1AE7BD8027D08 {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(logger: Logger) {
				        let detail = Detail(logger: logger)
				        self.init(detail: detail)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_9BE1AE7BD8027D08 {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles[integration])
		let expectedMidFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Mid.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Outer {
				    public convenience init(logger: Logger) {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_9BE1AE7BD8027D08.self
				            return Screen(logger: logger)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_9BE1AE7BD8027D08 {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Outer+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Outer {
				    public convenience init(logger: Logger) {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_9BE1AE7BD8027D08.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen(logger: logger)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_9BE1AE7BD8027D08 {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Mid"]).generatedFiles == expectedMidFiles[integration])
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsRuleLReportAtCappingReceiver_whenCappingReceiversPackageIsKnownInThreeModules(integration: MultiModuleIntegration) async {
		// The control twin of the unknown-package cell: with `Core` naming its package, `Mid`'s check of every construction reports `Detail`'s
		// initializer with its fix-it, and `Outer` reports no omission for `logger`; only the unknown package flips the verdict.
		await assertThrowsMultiModuleError(inModule: "Mid", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Detail.swift", in: "Core", fixtures, integration)):3:5: error: `Detail`’s initializer is `package`, so module `Mid`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(Self.path(of: "Detail.swift", in: "Core", fixtures, integration)):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: [
					"""
					public final class Logger: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Detail: Instantiable {
					    package init(logger: Logger) {
					        self.logger = logger
					    }

					    @Received let logger: Logger
					}
					""",
				]),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					import Core

					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    init(detail: Detail) {
					        self.detail = detail
					    }

					    @Instantiated let detail: Detail
					}
					""",
				], dependencies: ["Core"]),
				ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [
					"""
					import Feature

					@Instantiable(generateDependencyTree: true)
					public final class Outer: Instantiable {
					    public init(screen: Screen) {
					        self.screen = screen
					    }

					    @Instantiated let screen: Screen
					}
					""",
				], dependencies: ["Core", "Feature"]),
			], integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases, [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsOmissionErrorNamingReceiverOuterSeamBuilds_whenOuterSeamAlsoReachesItThroughNestedSeamCallItReachesNoTierOf(integration: MultiModuleIntegration, detailFirst: Bool) async {
		// `Outer`'s own tree builds `Detail` directly as well as through `Screen`, whose only tier `Outer` cannot reach: the receive is from
		// a reported seam call only on the path through `Screen`, so `Outer` reports the omission, in both declaration orders.
		await assertThrowsMultiModuleError(inModule: "Mid", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Outer.swift", in: "Mid", fixtures, integration)):3:1: error: SafeDI cannot generate the dependency tree of `Outer`: its generated `public` initializer cannot take `logger: Logger`, which the initializer of `Detail` receives at a narrower access level, and cannot pass `nil` for it, since it is required. Widen the initializer of `Detail`, receive the property with `onlyIfAvailable: true` and an optional type, or narrow the initializers of every type in the tree to its level.
			\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):7:5: note: `Detail` receives `logger: Logger` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					public final class Logger: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Detail: Instantiable {
					    package init(logger: Logger) {
					        self.logger = logger
					    }

					    @Received let logger: Logger
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    init(detail: Detail) {
					        self.detail = detail
					    }

					    @Instantiated let detail: Detail
					}
					""",
				]),
				ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [
					"""
					import Feature

					\(detailFirst ? Self.outerBuildingDetailFirst : Self.outerBuildingScreenFirst)
					""",
				], dependencies: ["Feature"]),
			], integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsOmissionErrorNamingReceiverOuterSeamBuildsThroughInstantiator_whenOuterSeamAlsoReachesItThroughNestedSeamCallItReachesNoTierOf(integration: MultiModuleIntegration) async {
		// `Outer` holds an `Instantiator<Detail>` beside the unreachable call of `Screen`: the builder's receive is `Outer`'s own.
		await assertThrowsMultiModuleError(inModule: "Mid", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Outer.swift", in: "Mid", fixtures, integration)):3:1: error: SafeDI cannot generate the dependency tree of `Outer`: its generated `public` initializer cannot take `logger: Logger`, which the initializer of `Detail` receives at a narrower access level, and cannot pass `nil` for it, since it is required. Widen the initializer of `Detail`, receive the property with `onlyIfAvailable: true` and an optional type, or narrow the initializers of every type in the tree to its level.
			\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):7:5: note: `Detail` receives `logger: Logger` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					public final class Logger: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Detail: Instantiable {
					    package init(logger: Logger) {
					        self.logger = logger
					    }

					    @Received let logger: Logger
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    init(detail: Detail) {
					        self.detail = detail
					    }

					    @Instantiated let detail: Detail
					}
					""",
				]),
				ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [
					"""
					import Feature

					@Instantiable(generateDependencyTree: true)
					public final class Outer: Instantiable {
					    public init(screen: Screen, detailBuilder: Instantiator<Detail>) {
					        self.screen = screen
					        self.detailBuilder = detailBuilder
					    }

					    @Instantiated let screen: Screen
					    @Instantiated let detailBuilder: Instantiator<Detail>
					}
					""",
				], dependencies: ["Feature"]),
			], integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsOmissionErrorNamingReceiverOuterSeamBuildsBeneathPlainType_whenOuterSeamAlsoReachesItThroughNestedSeamCallItReachesNoTierOf(integration: MultiModuleIntegration) async {
		// `Outer` builds `Detail` beneath the plain `Holder` beside the unreachable call of `Screen`: the receive beneath `Holder` is `Outer`'s own.
		await assertThrowsMultiModuleError(inModule: "Mid", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Outer.swift", in: "Mid", fixtures, integration)):3:1: error: SafeDI cannot generate the dependency tree of `Outer`: its generated `public` initializer cannot take `logger: Logger`, which the initializer of `Detail` receives at a narrower access level, and cannot pass `nil` for it, since it is required. Widen the initializer of `Detail`, receive the property with `onlyIfAvailable: true` and an optional type, or narrow the initializers of every type in the tree to its level.
			\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):7:5: note: `Detail` receives `logger: Logger` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					public final class Logger: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Detail: Instantiable {
					    package init(logger: Logger) {
					        self.logger = logger
					    }

					    @Received let logger: Logger
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    init(detail: Detail) {
					        self.detail = detail
					    }

					    @Instantiated let detail: Detail
					}
					""",
				]),
				ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [
					"""
					import Feature

					@Instantiable(generateDependencyTree: true)
					public final class Outer: Instantiable {
					    public init(screen: Screen, holder: Holder) {
					        self.screen = screen
					        self.holder = holder
					    }

					    @Instantiated let screen: Screen
					    @Instantiated let holder: Holder
					}
					""",
					"""
					import Feature

					@Instantiable
					public final class Holder: Instantiable {
					    public init(detail: Detail) {
					        self.detail = detail
					    }

					    @Instantiated let detail: Detail
					}
					""",
				], dependencies: ["Feature"]),
			], integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsRuleLReportAtCappingReceiverOnce_whenOuterSeamCallsTwoNestedSeamsItReachesNoTierOf(integration: MultiModuleIntegration) async {
		// Every path to `Detail` passes through a call the check of every construction reports, so `Outer` reports no omission, and the
		// check reports `Detail`'s initializer once.
		await assertThrowsMultiModuleError(inModule: "Mid", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5: error: `Detail`’s initializer is `package`, so module `Mid`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					public final class Logger: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Detail: Instantiable {
					    package init(logger: Logger) {
					        self.logger = logger
					    }

					    @Received let logger: Logger
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    init(detail: Detail) {
					        self.detail = detail
					    }

					    @Instantiated let detail: Detail
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Panel: Instantiable {
					    init(detail: Detail) {
					        self.detail = detail
					    }

					    @Instantiated let detail: Detail
					}
					""",
				]),
				ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [
					"""
					import Feature

					@Instantiable(generateDependencyTree: true)
					public final class Outer: Instantiable {
					    public init(screen: Screen, panel: Panel) {
					        self.screen = screen
					        self.panel = panel
					    }

					    @Instantiated let screen: Screen
					    @Instantiated let panel: Panel
					}
					""",
				], dependencies: ["Feature"]),
			], integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases, [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsRuleLReportAtCappingReceiver_whenPlainTypeInMidBuildsReceiverBesideNestedSeamItReachesNoTierOf(integration: MultiModuleIntegration, detailFirst: Bool) async {
		// The inline twin: a plain `Outer` forwarding `logger` and building `Detail` beside `Screen` gets the check's report at `Detail`, in
		// both declaration orders; the omission exists only for the seam, which must name every receiver of its own tree.
		await assertThrowsMultiModuleError(inModule: "Mid", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5: error: `Detail`’s initializer is `package`, so module `Mid`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					public final class Logger: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Detail: Instantiable {
					    package init(logger: Logger) {
					        self.logger = logger
					    }

					    @Received let logger: Logger
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    init(detail: Detail) {
					        self.detail = detail
					    }

					    @Instantiated let detail: Detail
					}
					""",
				]),
				ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [
					"""
					import Feature

					\(detailFirst ? Self.plainOuterBuildingDetailFirst : Self.plainOuterBuildingScreenFirst)
					""",
					"""
					import Feature

					@Instantiable(isRoot: true)
					public final class MidRoot: Instantiable {
					    public init(outerBuilder: Instantiator<Outer>) {
					        self.outerBuilder = outerBuilder
					    }

					    @Instantiated let outerBuilder: Instantiator<Outer>
					}
					""",
				], dependencies: ["Feature"]),
			], integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsRuleLReportAtCappingReceiver_whenPlainTypeInMidWithPackageInitializerForwardsLoggerToNestedSeamItReachesNoTierOf(integration: MultiModuleIntegration) async {
		// The inline twin of the narrowed outer seam: a plain `Outer` with a `package` initializer forwarding `logger`.
		await assertThrowsMultiModuleError(inModule: "Mid", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5: error: `Detail`’s initializer is `package`, so module `Mid`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					public final class Logger: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Detail: Instantiable {
					    package init(logger: Logger) {
					        self.logger = logger
					    }

					    @Received let logger: Logger
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    init(detail: Detail) {
					        self.detail = detail
					    }

					    @Instantiated let detail: Detail
					}
					""",
				]),
				ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [
					"""
					import Feature

					@Instantiable
					public final class Outer: Instantiable {
					    package init(logger: Logger, screen: Screen) {
					        self.logger = logger
					        self.screen = screen
					    }

					    @Forwarded let logger: Logger
					    @Instantiated let screen: Screen
					}
					""",
					"""
					import Feature

					@Instantiable(isRoot: true)
					public final class MidRoot: Instantiable {
					    public init(outerBuilder: Instantiator<Outer>) {
					        self.outerBuilder = outerBuilder
					    }

					    @Instantiated let outerBuilder: Instantiator<Outer>
					}
					""",
				], dependencies: ["Feature"]),
			], integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsRuleLReportsAtBothReceivers_whenPlainTypeInMidForwardsLoggerToNestedSeamAndOwnReceiverItReachesNoTierOf(integration: MultiModuleIntegration) async {
		// The inline twin of the omission naming `Detail` and `Own`: both builds reject, and the diagnostics differ by design. Built inline,
		// the check of every construction reports `Detail`'s and `Own`'s initializers, each with its fix-it; the seam `Outer` reports
		// its own omission instead, because `Own` is a receiver of `Outer`'s own tree, which the omission names with `Detail`.
		await assertThrowsMultiModuleError(inModule: "Mid", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5: error: `Detail`’s initializer is `package`, so module `Mid`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(Self.path(of: "Detail.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
			\(Self.path(of: "Own.swift", in: "Feature", fixtures, integration)):3:5: error: `Own`’s initializer is `package`, so module `Mid`, in another package, cannot call it in the code SafeDI generates. Make the initializer `public` to fix.
			\(Self.path(of: "Own.swift", in: "Feature", fixtures, integration)):3:5-3:12: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					public final class Logger: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Detail: Instantiable {
					    package init(logger: Logger) {
					        self.logger = logger
					    }

					    @Received let logger: Logger
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    init(detail: Detail) {
					        self.detail = detail
					    }

					    @Instantiated let detail: Detail
					}
					""",
					"""
					@Instantiable
					public final class Own: Instantiable {
					    package init(logger: Logger) {
					        self.logger = logger
					    }

					    @Received let logger: Logger
					}
					""",
				]),
				ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: [
					"""
					import Feature

					@Instantiable
					public final class Outer: Instantiable {
					    public init(logger: Logger, screen: Screen, own: Own) {
					        self.logger = logger
					        self.screen = screen
					        self.own = own
					    }

					    @Forwarded let logger: Logger
					    @Instantiated let screen: Screen
					    @Instantiated let own: Own
					}
					""",
					"""
					import Feature

					@Instantiable(isRoot: true)
					public final class MidRoot: Instantiable {
					    public init(outerBuilder: Instantiator<Outer>) {
					        self.outerBuilder = outerBuilder
					    }

					    @Instantiated let outerBuilder: Instantiator<Outer>
					}
					""",
				], dependencies: ["Feature"]),
			], integration: integration, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsNestedSeamsPublicTierBeneathHolder_whenOuterIsSeamOrPlain(integration: MultiModuleIntegration) async throws {
		// The twin of the widened cell with a caller: `Holder` forwards `logger` to `Outer`, built once as a seam and once inline, and
		// the two builds construct the same values.
		let featureFiles = [
			"""
			public final class Logger: Sendable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Detail: Instantiable {
			    public init(logger: Logger) {
			        self.logger = logger
			    }

			    @Received let logger: Logger
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public final class Screen: Instantiable {
			    init(detail: Detail) {
			        self.detail = detail
			    }

			    @Instantiated let detail: Detail
			}
			""",
		]
		let midFiles = [
			"""
			import Feature

			@Instantiable(generateDependencyTree: true)
			public final class Outer: Instantiable {
			    public init(screen: Screen) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Screen
			}
			""",
			"""
			import Feature

			@Instantiable
			public final class Holder: Instantiable {
			    public init(logger: Logger, outer: Outer) {
			        self.logger = logger
			        self.outer = outer
			    }

			    @Forwarded let logger: Logger
			    @Instantiated let outer: Outer
			}
			""",
			"""
			import Feature

			@Instantiable(isRoot: true)
			public final class MidRoot: Instantiable {
			    public init(holderBuilder: Instantiator<Holder>) {
			        self.holderBuilder = holderBuilder
			    }

			    @Instantiated let holderBuilder: Instantiator<Holder>
			}
			""",
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: featureFiles),
			ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: midFiles, dependencies: ["Feature"]),
		], integration: integration, filesToDelete: &filesToDelete)
		let expectedFeatureFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Feature.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(logger: Logger) {
				        let detail = Detail(logger: logger)
				        self.init(detail: detail)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_9BE1AE7BD8027D08 {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    public convenience init(logger: Logger) {
				        let detail = Detail(logger: logger)
				        self.init(detail: detail)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_9BE1AE7BD8027D08 {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles[integration])
		let expectedMidFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Mid.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension MidRoot {
				    public convenience init() {
				        func __safeDI_holderBuilder(logger: Logger) -> Holder {
				            func __safeDI_outer() -> Outer {
				                _ = Outer.__safeDI_Outer_9BE1AE7BD8027D08.self
				                return Outer(logger: logger)
				            }
				            let outer: Outer = __safeDI_outer()
				            return Holder(logger: logger, outer: outer)
				        }
				        let holderBuilder = Instantiator<Holder> {
				            __safeDI_holderBuilder(logger: $0)
				        }
				        self.init(holderBuilder: holderBuilder)
				    }
				}

				extension Outer {
				    public convenience init(logger: Logger) {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_9BE1AE7BD8027D08.self
				            return Screen(logger: logger)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_9BE1AE7BD8027D08 {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"MidRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension MidRoot {
				    public convenience init() {
				        func __safeDI_holderBuilder(logger: Logger) -> Holder {
				            func __safeDI_outer() -> Outer {
				                _ = Outer.__safeDI_Outer_9BE1AE7BD8027D08.self
				                return Outer(logger: logger)
				            }
				            let outer: Outer = __safeDI_outer()
				            return Holder(logger: logger, outer: outer)
				        }
				        let holderBuilder = Instantiator<Holder> {
				            __safeDI_holderBuilder(logger: $0)
				        }
				        self.init(holderBuilder: holderBuilder)
				    }
				}
				""",
				"Outer+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension Outer {
				    public convenience init(logger: Logger) {
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_9BE1AE7BD8027D08.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen(logger: logger)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_9BE1AE7BD8027D08 {}
				}
				""",
			],
		]
		#expect(try #require(output.modules["Mid"]).generatedFiles == expectedMidFiles[integration])
		let inlineMidFiles = inlineFixture(midFiles)
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: featureFiles),
			ModuleFixture(name: "Mid", packageName: "Other", swiftFileContent: inlineMidFiles, dependencies: ["Feature"]),
		], integration: integration, filesToDelete: &filesToDelete)
		#expect(try #require(inlineOutput.modules["Feature"]).generatedFiles == expectedFeatureFiles[integration])
		let expectedInlineMidFiles: [MultiModuleIntegration: [String: String]] = [
			.moduleInfo: [
				"Mid.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension MidRoot {
				    public convenience init() {
				        func __safeDI_holderBuilder(logger: Logger) -> Holder {
				            func __safeDI_outer() -> Outer {
				                func __safeDI_screen() -> Screen {
				                    _ = Screen.__safeDI_Screen_9BE1AE7BD8027D08.self
				                    return Screen(logger: logger)
				                }
				                let screen: Screen = __safeDI_screen()
				                return Outer(screen: screen)
				            }
				            let outer: Outer = __safeDI_outer()
				            return Holder(logger: logger, outer: outer)
				        }
				        let holderBuilder = Instantiator<Holder> {
				            __safeDI_holderBuilder(logger: $0)
				        }
				        self.init(holderBuilder: holderBuilder)
				    }
				}
				""",
			],
			.swiftPackagePlugin: [
				"MidRoot+SafeDI.swift": generatedFileHeader + """
				#if canImport(Feature)
				import Feature
				#endif

				extension MidRoot {
				    public convenience init() {
				        func __safeDI_holderBuilder(logger: Logger) -> Holder {
				            func __safeDI_outer() -> Outer {
				                func __safeDI_screen() -> Screen {
				                    _ = Screen.__safeDI_Screen_9BE1AE7BD8027D08.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				                    return Screen(logger: logger)
				                }
				                let screen: Screen = __safeDI_screen()
				                return Outer(screen: screen)
				            }
				            let outer: Outer = __safeDI_outer()
				            return Holder(logger: logger, outer: outer)
				        }
				        let holderBuilder = Instantiator<Holder> {
				            __safeDI_holderBuilder(logger: $0)
				        }
				        self.init(holderBuilder: holderBuilder)
				    }
				}
				""",
			],
		]
		#expect(try #require(inlineOutput.modules["Mid"]).generatedFiles == expectedInlineMidFiles[integration])
		try expectEveryModuleCompiled(output)
		try expectEveryModuleCompiled(inlineOutput)
		try expectDifferentialValuesAgree(
			feature: Self.path(featureFiles: featureFiles, midFiles: midFiles, output: output),
			knownRight: Self.path(featureFiles: featureFiles, midFiles: inlineMidFiles, output: inlineOutput),
			probes: [DifferentialValueProbe("MidRoot().holderBuilder.instantiate(Logger())")],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsOmissionErrorNamingOwnInitializerAndTreeReceiver_whenTreeReceiverAlsoReceivesSeamsOwnRequiredReceive() async {
		// The seam's own `token` is also received by `Right`, whose internal initializer caps the tier: the error names the seam's own
		// initializer and `Right`'s, both of which cap `logger`'s public tier, and the remedy names both.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `token: Token`, which `Screen`'s own initializer and the initializer of `Right` receive at a narrower access level, and cannot pass `nil` for it, since it is required. Widen the initializer of `Screen` and the initializer of `Right`, or narrow the initializers of every type in the tree to its level.
			\(fixtures["Screen.swift"]):9:5: note: `Screen` receives `token: Token` here.
			\(fixtures["Right.swift"]):7:5: note: `Right` receives `token: Token` here.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				"""
				public final class Token: Sendable {
				    public init() {}
				}

				public final class Logger: Sendable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Detail: Instantiable {
				    public init(logger: Logger) {
				        self.logger = logger
				    }

				    @Received let logger: Logger
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public final class Screen: Instantiable {
				    init(token: Token, detail: Detail, right: Right) {
				        self.token = token
				        self.detail = detail
				        self.right = right
				    }

				    @Received let token: Token
				    @Instantiated let detail: Detail
				    @Instantiated let right: Right
				}
				""",
				"""
				@Instantiable
				public final class Right: Instantiable {
				    init(token: Token) {
				        self.token = token
				    }

				    @Received let token: Token
				}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsOmissionErrorNamingOwnInitializerAndTreeReceivers_whenTwoTreeReceiversAlsoReceiveSeamsOwnRequiredReceive() async {
		// Two tree receivers beside the seam's own receive are named in declaration order after the seam's own initializer.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `token: Token`, which `Screen`'s own initializer and the initializer of `Right` and `Left` receive at a narrower access level, and cannot pass `nil` for it, since it is required. Widen the initializer of `Screen` and the initializer of `Right` and the initializer of `Left`, or narrow the initializers of every type in the tree to its level.
			\(fixtures["Screen.swift"]):10:5: note: `Screen` receives `token: Token` here.
			\(fixtures["Right.swift"]):7:5: note: `Right` receives `token: Token` here.
			\(fixtures["Left.swift"]):7:5: note: `Left` receives `token: Token` here.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				"""
				public final class Token: Sendable {
				    public init() {}
				}

				public final class Logger: Sendable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Detail: Instantiable {
				    public init(logger: Logger) {
				        self.logger = logger
				    }

				    @Received let logger: Logger
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public final class Screen: Instantiable {
				    init(token: Token, detail: Detail, right: Right, left: Left) {
				        self.token = token
				        self.detail = detail
				        self.right = right
				        self.left = left
				    }

				    @Received let token: Token
				    @Instantiated let detail: Detail
				    @Instantiated let right: Right
				    @Instantiated let left: Left
				}
				""",
				"""
				@Instantiable
				public final class Right: Instantiable {
				    init(token: Token) {
				        self.token = token
				    }

				    @Received let token: Token
				}
				""",
				"""
				@Instantiable
				public final class Left: Instantiable {
				    package init(token: Token) {
				        self.token = token
				    }

				    @Received let token: Token
				}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsOmissionErrorNamingOwnInitializerAndTreeReceiver_whenTreeReceiverAlsoRequiresSeamsOwnRequiredOptionalReceive() async {
		// The seam's own required `token: Token?` and `Right`'s required receive of the same optional form.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `token: Token?`, which `Screen`'s own initializer and the initializer of `Right` receive at a narrower access level, and cannot pass `nil` for it, since it is required. Widen the initializer of `Screen` and the initializer of `Right`, or narrow the initializers of every type in the tree to its level.
			\(fixtures["Screen.swift"]):9:5: note: `Screen` receives `token: Token?` here.
			\(fixtures["Right.swift"]):7:5: note: `Right` receives `token: Token?` here.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				"""
				public final class Token: Sendable {
				    public init() {}
				}

				public final class Logger: Sendable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Detail: Instantiable {
				    public init(logger: Logger) {
				        self.logger = logger
				    }

				    @Received let logger: Logger
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public final class Screen: Instantiable {
				    init(token: Token?, detail: Detail, right: Right) {
				        self.token = token
				        self.detail = detail
				        self.right = right
				    }

				    @Received let token: Token?
				    @Instantiated let detail: Detail
				    @Instantiated let right: Right
				}
				""",
				"""
				@Instantiable
				public final class Right: Instantiable {
				    init(token: Token?) {
				        self.token = token
				    }

				    @Received let token: Token?
				}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsOmissionErrorNamingOwnInitializerAndTreeReceiver_whenTreeReceiverReceivesSeamsOwnRequiredReceiveOnlyIfAvailable() async {
		// `Right` receives the seam's own required `token` only if available, in its optional form: it is still a receiver that caps the tier.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `token: Token`, which `Screen`'s own initializer and the initializer of `Right` receive at a narrower access level, and cannot pass `nil` for it, since it is required. Widen the initializer of `Screen` and the initializer of `Right`, or narrow the initializers of every type in the tree to its level.
			\(fixtures["Screen.swift"]):9:5: note: `Screen` receives `token: Token` here.
			\(fixtures["Right.swift"]):7:5: note: `Right` receives `token: Token?` here.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				"""
				public final class Token: Sendable {
				    public init() {}
				}

				public final class Logger: Sendable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Detail: Instantiable {
				    public init(logger: Logger) {
				        self.logger = logger
				    }

				    @Received let logger: Logger
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public final class Screen: Instantiable {
				    init(token: Token, detail: Detail, right: Right) {
				        self.token = token
				        self.detail = detail
				        self.right = right
				    }

				    @Received let token: Token
				    @Instantiated let detail: Detail
				    @Instantiated let right: Right
				}
				""",
				"""
				@Instantiable
				public final class Right: Instantiable {
				    init(token: Token?) {
				        self.token = token
				    }

				    @Received(onlyIfAvailable: true) let token: Token?
				}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsOmissionErrorNamingOwnInitializerAndTreeReceiver_whenTreeReceiverReceivesSeamsOwnOnlyIfAvailableReceiveOnlyIfAvailable() async {
		// The seam's own `onlyIfAvailable` receive beside `Right`'s: the error says the own property is taken as declared, and names `Right` too.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `token: Token?`, which `Screen`'s own initializer and the initializer of `Right` receive at a narrower access level, and cannot pass `nil` for it: `Screen` receives `token` only if available, but its generated initializers take each of `Screen`'s own properties as declared, with no default. Widen the initializer of `Screen` and the initializer of `Right`, or narrow the initializers of every type in the tree to its level.
			\(fixtures["Screen.swift"]):9:5: note: `Screen` receives `token: Token?` here.
			\(fixtures["Right.swift"]):7:5: note: `Right` receives `token: Token?` here.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				"""
				public final class Token: Sendable {
				    public init() {}
				}

				public final class Logger: Sendable {
				    public init() {}
				}
				""",
				"""
				@Instantiable
				public final class Detail: Instantiable {
				    public init(logger: Logger) {
				        self.logger = logger
				    }

				    @Received let logger: Logger
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true)
				public final class Screen: Instantiable {
				    init(token: Token?, detail: Detail, right: Right) {
				        self.token = token
				        self.detail = detail
				        self.right = right
				    }

				    @Received(onlyIfAvailable: true) let token: Token?
				    @Instantiated let detail: Detail
				    @Instantiated let right: Right
				}
				""",
				"""
				@Instantiable
				public final class Right: Instantiable {
				    init(token: Token?) {
				        self.token = token
				    }

				    @Received(onlyIfAvailable: true) let token: Token?
				}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsOmissionErrorNamingOwnInitializerAndTreeReceiverCappedByItsType_whenTreeReceiverAlsoReceivesSeamsOwnRequiredReceive(integration: MultiModuleIntegration) async {
		// `Right` is internal with a public initializer, so its type caps it: the remedy names the type that caps the initializer, after the
		// seam's own initializer.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `token: Token`, which `Screen`'s own initializer and the initializer of `Right` receive at a narrower access level, and cannot pass `nil` for it, since it is required. Widen the initializer of `Screen` and `Right`, or the type enclosing it, which caps its initializer, or narrow the initializers of every type in the tree to its level.
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):9:5: note: `Screen` receives `token: Token` here.
			\(Self.path(of: "Right.swift", in: "Feature", fixtures, integration)):7:5: note: `Right` receives `token: Token` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					public final class Token: Sendable {
					    public init() {}
					}

					public final class Logger: Sendable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Detail: Instantiable {
					    public init(logger: Logger) {
					        self.logger = logger
					    }

					    @Received let logger: Logger
					}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    init(token: Token, detail: Detail, right: Right) {
					        self.token = token
					        self.detail = detail
					        self.right = right
					    }

					    @Received let token: Token
					    @Instantiated let detail: Detail
					    @Instantiated let right: Right
					}
					""",
					"""
					@Instantiable
					final class Right: Instantiable {
					    public init(token: Token) {
					        self.token = token
					    }

					    @Received let token: Token
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
					"""
					import Feature

					@Instantiable(isRoot: true)
					public final class AppRoot: Instantiable {
					    public init(shellBuilder: Instantiator<Shell>) {
					        self.shellBuilder = shellBuilder
					    }

					    @Instantiated public let shellBuilder: Instantiator<Shell>
					}
					""",
					"""
					import Feature

					@Instantiable
					public final class Shell: Instantiable {
					    public init(token: Token, logger: Logger, screen: Screen) {
					        self.token = token
					        self.logger = logger
					        self.screen = screen
					    }

					    @Forwarded let token: Token
					    @Forwarded let logger: Logger
					    @Instantiated let screen: Screen
					}
					""",
				], dependencies: ["Feature"]),
			], integration: integration, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let outerBuildingScreenFirst = """
	@Instantiable(generateDependencyTree: true)
	public final class Outer: Instantiable {
	    public init(screen: Screen, detail: Detail) {
	        self.screen = screen
	        self.detail = detail
	    }

	    @Instantiated let screen: Screen
	    @Instantiated let detail: Detail
	}
	"""
	private static let outerBuildingDetailFirst = """
	@Instantiable(generateDependencyTree: true)
	public final class Outer: Instantiable {
	    public init(detail: Detail, screen: Screen) {
	        self.detail = detail
	        self.screen = screen
	    }

	    @Instantiated let detail: Detail
	    @Instantiated let screen: Screen
	}
	"""
	private static let plainOuterBuildingScreenFirst = """
	@Instantiable
	public final class Outer: Instantiable {
	    public init(logger: Logger, screen: Screen, detail: Detail) {
	        self.logger = logger
	        self.screen = screen
	        self.detail = detail
	    }

	    @Forwarded let logger: Logger
	    @Instantiated let screen: Screen
	    @Instantiated let detail: Detail
	}
	"""
	private static let plainOuterBuildingDetailFirst = """
	@Instantiable
	public final class Outer: Instantiable {
	    public init(logger: Logger, detail: Detail, screen: Screen) {
	        self.logger = logger
	        self.detail = detail
	        self.screen = screen
	    }

	    @Forwarded let logger: Logger
	    @Instantiated let detail: Detail
	    @Instantiated let screen: Screen
	}
	"""

	private static let badgeWithPackageInit = """
	@Instantiable
	public struct Badge: Instantiable {
	    package init(theme: Theme?) {
	        self.theme = theme
	    }

	    @Received(onlyIfAvailable: true) public let theme: Theme?
	}

	public struct Theme: Sendable {
	    public init() {}
	}
	"""
	private static let badgeWithInternalInit = """
	@Instantiable
	public struct Badge: Instantiable {
	    init(theme: Theme?) {
	        self.theme = theme
	    }

	    @Received(onlyIfAvailable: true) public let theme: Theme?
	}

	public struct Theme: Sendable {
	    public init() {}
	}
	"""
	private static let header = """
	@Instantiable
	public struct Header: Instantiable {
	    public init(title: String) {
	        self.title = title
	    }

	    @Received public let title: String
	}
	"""
	private static let serviceWithBadgeOnly = """
	@Instantiable(generateDependencyTree: true)
	public final class Service: Instantiable {
	    init(badge: Badge) {
	        self.badge = badge
	    }

	    @Instantiated public let badge: Badge
	}
	"""
	private static let midRoot = """
	import Feature

	@Instantiable(isRoot: true)
	public final class MidRoot: Instantiable {
	    public init(shellBuilder: Instantiator<MidShell>) {
	        self.shellBuilder = shellBuilder
	    }

	    @Instantiated public let shellBuilder: Instantiator<MidShell>
	}
	"""
	private static let midShell = """
	import Feature

	@Instantiable
	public final class MidShell: Instantiable {
	    public init(theme: Theme, title: String, service: Service) {
	        self.theme = theme
	        self.title = title
	        self.service = service
	    }

	    @Forwarded public let theme: Theme
	    @Forwarded public let title: String
	    @Instantiated public let service: Service
	}
	"""
	private static let detailWithPackageInit = """
	@Instantiable
	public struct Detail: Instantiable {
	    package init(logger: Logger) {
	        self.logger = logger
	    }

	    @Received let logger: Logger
	}

	public struct Logger: Sendable {
	    public init() {}
	}
	"""
	private static let shellForwardingLogger = [
		"""
		import Feature

		@Instantiable(isRoot: true)
		public final class AppRoot: Instantiable {
		    public init(shellBuilder: Instantiator<Shell>) {
		        self.shellBuilder = shellBuilder
		    }

		    @Instantiated let shellBuilder: Instantiator<Shell>
		}
		""",
		"""
		import Feature

		@Instantiable
		public final class Shell: Instantiable {
		    public init(logger: Logger, screen: Screen, panel: Panel) {
		        self.logger = logger
		        self.screen = screen
		        self.panel = panel
		    }

		    @Forwarded let logger: Logger
		    @Instantiated let screen: Screen
		    @Instantiated let panel: Panel
		}
		""",
	]
	private static let readerWithPackageInitReceivingSession = """
	@Instantiable
	public struct Reader: Instantiable {
	    package init(session: Session) {
	        self.session = session
	    }

	    @Received let session: Session
	}

	public final class Secret: Sendable {
	    public init() {}
	}

	public final class Session: Sendable {
	    public init() {}
	}
	"""
	private static let shellForwardingTokenAndSession = [
		"""
		import Feature

		@Instantiable(isRoot: true)
		public final class AppRoot: Instantiable {
		    public init(shellBuilder: Instantiator<Shell>) {
		        self.shellBuilder = shellBuilder
		    }

		    @Instantiated public let shellBuilder: Instantiator<Shell>
		}
		""",
		"""
		import Feature

		@Instantiable
		public final class Shell: Instantiable {
		    public init(token: Secret, session: Session, screen: Screen) {
		        self.token = token
		        self.session = session
		        self.screen = screen
		    }

		    @Forwarded let token: Secret
		    @Forwarded let session: Session
		    @Instantiated let screen: Screen
		}
		""",
	]

	/// `Service`, the seam of the tier cells, with `init` as its own initializer's spelling.
	private static func service(init initializer: String) -> String {
		"""
		@Instantiable(generateDependencyTree: true)
		public final class Service: Instantiable {
		    \(initializer)(badge: Badge, header: Header) {
		        self.badge = badge
		        self.header = header
		    }

		    @Instantiated public let badge: Badge
		    @Instantiated public let header: Header
		}
		"""
	}

	/// `Screen` and `Panel`, two seams instantiating `detail` and `badge`, as seams or inline.
	private static func twoSeams(seam: Bool) -> [String] {
		["Screen", "Panel"].map { name in
			"""
			@Instantiable\(seam ? "(generateDependencyTree: true)" : "")
			public final class \(name): Instantiable {
			    init(detail: Detail, badge: Badge) {
			        self.detail = detail
			        self.badge = badge
			    }

			    @Instantiated let detail: Detail
			    @Instantiated let badge: Badge
			}
			"""
		}
	}

	/// `Screen`, which receives `token` itself and instantiates `reader`, as a seam or inline.
	private static func screenWithOwnToken(seam: Bool) -> String {
		"""
		@Instantiable\(seam ? "(generateDependencyTree: true)" : "")
		public final class Screen: Instantiable {
		    package init(token: Secret, reader: Reader) {
		        self.token = token
		        self.reader = reader
		    }

		    @Received let token: Secret
		    @Instantiated let reader: Reader
		}
		"""
	}

	/// `AppRoot` building `AppShell` through an instantiator; the shell forwards `forwarding` and instantiates `service`.
	private static func appRootAndShell(forwarding: [String]) -> [String] {
		let properties = forwarding.map { declaration in
			(label: String(declaration.prefix { $0 != ":" }), type: declaration.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces))
		}
		return [
			"""
			import Feature

			@Instantiable(isRoot: true)
			public final class AppRoot: Instantiable {
			    public init(shellBuilder: Instantiator<AppShell>) {
			        self.shellBuilder = shellBuilder
			    }

			    @Instantiated public let shellBuilder: Instantiator<AppShell>
			}
			""",
			"""
			import Feature

			@Instantiable
			public final class AppShell: Instantiable {
			    public init(\(properties.map { "\($0.label): \($0.type)" }.joined(separator: ", ")), service: Service) {
			\(properties.map { "        self.\($0.label) = \($0.label)" }.joined(separator: "\n"))
			        self.service = service
			    }

			\(properties.map { "    @Forwarded public let \($0.label): \($0.type)" }.joined(separator: "\n"))
			    @Instantiated public let service: Service
			}
			""",
		]
	}

	/// The path a diagnostic names `file` of `module` by under `integration`.
	private static func path(of file: String, in module: String, _ fixtures: [String: FixturePaths], _ integration: MultiModuleIntegration) -> String {
		switch integration {
		case .moduleInfo:
			fixtures[module]![file]
		case .swiftPackagePlugin:
			NormalizedFilePath(fixtures[module]!.compilerPath(of: file)).path
		}
	}

	/// A path of `Feature` and `Mid` for the differential value comparator: each module's fixture files, named as the
	/// harness names them, and the files the tool generated for it.
	private static func path(featureFiles: [String], midFiles: [String], output: MultiModuleTestOutput) throws -> DifferentialValuePath {
		func fixtureFiles(_ files: [String]) -> [String: String] {
			Dictionary(uniqueKeysWithValues: files.enumerated().map { ("File\($0.offset).swift", $0.element) })
		}
		return try DifferentialValuePath(modules: [
			DifferentialValueModule(name: "Feature", packageName: "Shop", fixtureFiles: fixtureFiles(featureFiles), generatedFiles: #require(output.modules["Feature"]).generatedFiles),
			DifferentialValueModule(name: "Mid", packageName: "Shop", dependencyModuleNames: ["Feature"], fixtureFiles: fixtureFiles(midFiles), generatedFiles: #require(output.modules["Mid"]).generatedFiles),
		])
	}

	/// What the root of the rule W control holds.
	enum W4Holder: String, CaseIterable, CustomTestStringConvertible {
		case session
		case both

		var testDescription: String {
			rawValue
		}

		var root: String {
			switch self {
			case .session:
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(session: Session, screen: Screen) {
				        self.session = session
				        self.screen = screen
				    }

				    @Instantiated let session: Session
				    @Instantiated let screen: Screen
				}
				"""
			case .both:
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(token: Secret, session: Session, screen: Screen) {
				        self.token = token
				        self.session = session
				        self.screen = screen
				    }

				    @Instantiated let token: Secret
				    @Instantiated let session: Session
				    @Instantiated let screen: Screen
				}
				"""
			}
		}
	}

	/// Expects every module to have compiled, when compile verification runs.
	private func expectEveryModuleCompiled(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.exitCode) == output.moduleNames.map { _ in 0 }, sourceLocation: sourceLocation)
	}
}
