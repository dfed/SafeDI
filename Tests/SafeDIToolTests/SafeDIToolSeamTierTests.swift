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

	// MARK: R6(1): tiers at the type's level and at each narrower parameter access, never at the own initializer's

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_formsNoTierAtOwnInitializersLevel_whenClassSeamsOwnInitializerIsNarrowerThanEveryParameter(integration: MultiModuleIntegration) async throws {
		// `Service`'s type is public, `title` is proven `public` and `theme` `package`: the tiers are `public` and
		// `package`, and the own initializer's `internal` level is no tier, so `Mid`, in the same package, reaches the
		// `package` tier and passes the `theme` it holds. The twin whose own initializer is `package` generates the same
		// files and builds the same values, which the comparator checks.
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
	mutating func generate_formsNoTierAtOwnInitializersLevel_whenStructSeamsOwnInitializerIsNarrowerThanEveryParameter(integration: MultiModuleIntegration) async throws {
		// The struct seam: `public init` and `package init` tiers, none at the own initializer's `internal` level.
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
	mutating func generate_callsPublicTierFromAnotherPackage_whenSeamsOwnInitializerIsPackageAndOneParameterIsInternal(integration: MultiModuleIntegration) async throws {
		// `title` is proven `public` and `theme` `internal`: the tiers are `public` and `internal`, and the own initializer's
		// `package` level is no tier, so a caller in another package calls `Service(title:)`.
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

	// MARK: R6(1): tiers an own initializer as wide as the type leaves as they are

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesPublicAndPackageTiers_whenRequiredPublicParameterIsBesideOptionalPackageOne(integration: MultiModuleIntegration) async throws {
		// The Manual's example shape: a required parameter proven `public` beside an optional one proven `package` gives
		// `public` and `package` tiers.
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

	// MARK: R6: a caller in another package calls each seam's public tier

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicTierOfEachSeam_whenEachSeamHasTiersAtThreeLevels(integration: MultiModuleIntegration) async throws {
		// `theme` is proven `package` and `color` `internal`: each seam gets a public tier passing `nil`, a package tier taking
		// `theme`, and an internal tier taking both.
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
	mutating func generate_throwsErrorAtSeamsTypeAlone_whenPackageSeamTypeHasPublicOwnInitializerAndCallerReachesNoTier(integration: MultiModuleIntegration) async {
		// R6(6): `Service`'s type is package and its own initializer spelled public: the type alone is reported, with its
		// fix-it, since a call of a seam's tier needs only the seam's type to be visible.
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
	mutating func generate_callsNestedSeamsPublicTierBeneathHolder_whenOuterIsSeamOrPlain(integration: MultiModuleIntegration) async throws {
		// The previous cell's shape with a caller: `Holder` forwards `logger` to `Outer`, built once as a seam and once inline,
		// and the two builds construct the same values.
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

	// MARK: Private

	private var filesToDelete: [URL]

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
	private static let header = """
	@Instantiable
	public struct Header: Instantiable {
	    public init(title: String) {
	        self.title = title
	    }

	    @Received public let title: String
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

	/// The path a diagnostic names `file` of `module` by under `integration`.
	private static func path(of file: String, in module: String, _ fixtures: [String: FixturePaths], _ integration: MultiModuleIntegration) -> String {
		// A module the tool did not run for is named, so a test that expects the error elsewhere fails rather than traps.
		guard let moduleFixtures = fixtures[module] else { return "<\(module) did not run>/\(file)" }
		return switch integration {
		case .moduleInfo:
			moduleFixtures[file]
		case .swiftPackagePlugin:
			NormalizedFilePath(moduleFixtures.compilerPath(of: file)).path
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

	/// Expects every module to have compiled, when compile verification runs.
	private func expectEveryModuleCompiled(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.exitCode) == output.moduleNames.map { _ in 0 }, sourceLocation: sourceLocation)
	}
}
