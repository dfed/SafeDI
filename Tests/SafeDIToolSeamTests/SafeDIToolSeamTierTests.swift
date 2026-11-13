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

/// How a seam's tiers are formed from its parameters' access levels and what a caller that reaches none is told. A tier
/// is generated at the seam's type's level and at each narrower level the proof gives a parameter, never at the seam's
/// own initializer's level, so a same-package caller reaches the package tier and passes the value it holds. The
/// narrowest tier builds the tree and calls the seam's own initializer, which may be narrower than it. A caller that
/// reaches no tier cannot construct the seam's type, and is reported at that type and the types enclosing it, never at a
/// generated or own initializer, and never without a location. The omission error names a seam's own only-if-available
/// receive as what it is.
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
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_title: @autoclosure @escaping () -> String) {
				        self.init(__safeDI_theme: nil, __safeDI_title: __safeDI_title())
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    package convenience init(__safeDI_theme: @autoclosure @escaping () -> Theme?, __safeDI_title: @autoclosure @escaping () -> String) {
				        let theme = LazilyInstantiated<Theme?>(__safeDI_theme)
				        let title = LazilyInstantiated<String>(__safeDI_title)
				        let badge = Badge(theme: theme.instance)
				        let header = Header(title: title.instance)
				        self.init(badge: badge, header: header)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_29874EE5B00C89A6 {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Service+SafeDI.swift": generatedFileHeader + """
				extension Service {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_title: @autoclosure @escaping () -> String) {
				        self.init(__safeDI_theme: nil, __safeDI_title: __safeDI_title())
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    package convenience init(__safeDI_theme: @autoclosure @escaping () -> Theme?, __safeDI_title: @autoclosure @escaping () -> String) {
				        let theme = LazilyInstantiated<Theme?>(__safeDI_theme)
				        let title = LazilyInstantiated<String>(__safeDI_title)
				        let badge = Badge(theme: theme.instance)
				        let header = Header(title: title.instance)
				        self.init(badge: badge, header: header)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_29874EE5B00C89A6 {}
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
				                _ = Service.__safeDI_Service_29874EE5B00C89A6.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				                return Service(__safeDI_theme: theme, __safeDI_title: title)
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
				                _ = Service.__safeDI_Service_29874EE5B00C89A6.self // If this line does not compile, add the SafeDI plugin to the target that declares Service.
				                return Service(__safeDI_theme: theme, __safeDI_title: title)
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

					    @Received(onlyIfAvailable: true) package let theme: Theme?
					}

					package struct Theme: Sendable {
					    package init() {}
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
					    package init(shellBuilder: Instantiator<MidShell>) {
					        self.shellBuilder = shellBuilder
					    }

					    @Instantiated package let shellBuilder: Instantiator<MidShell>
					}
					""",
					"""
					import Feature

					@Instantiable
					package final class MidShell: Instantiable {
					    package init(theme: Theme, title: String, service: Service) {
					        self.theme = theme
					        self.title = title
					        self.service = service
					    }

					    @Forwarded package let theme: Theme
					    @Forwarded package let title: String
					    @Instantiated package let service: Service
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
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public init(__safeDI_title: @autoclosure @escaping () -> String) {
				        self.init(__safeDI_theme: nil, __safeDI_title: __safeDI_title())
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    package init(__safeDI_theme: @autoclosure @escaping () -> Theme?, __safeDI_title: @autoclosure @escaping () -> String) {
				        let theme = LazilyInstantiated<Theme?>(__safeDI_theme)
				        let title = LazilyInstantiated<String>(__safeDI_title)
				        let badge = Badge(theme: theme.instance)
				        let header = Header(title: title.instance)
				        self.init(badge: badge, header: header)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_29874EE5B00C89A6 {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Service+SafeDI.swift": generatedFileHeader + """
				extension Service {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public init(__safeDI_title: @autoclosure @escaping () -> String) {
				        self.init(__safeDI_theme: nil, __safeDI_title: __safeDI_title())
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    package init(__safeDI_theme: @autoclosure @escaping () -> Theme?, __safeDI_title: @autoclosure @escaping () -> String) {
				        let theme = LazilyInstantiated<Theme?>(__safeDI_theme)
				        let title = LazilyInstantiated<String>(__safeDI_title)
				        let badge = Badge(theme: theme.instance)
				        let header = Header(title: title.instance)
				        self.init(badge: badge, header: header)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_29874EE5B00C89A6 {}
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
				                _ = Service.__safeDI_Service_29874EE5B00C89A6.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				                return Service(__safeDI_theme: theme, __safeDI_title: title)
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
				                _ = Service.__safeDI_Service_29874EE5B00C89A6.self // If this line does not compile, add the SafeDI plugin to the target that declares Service.
				                return Service(__safeDI_theme: theme, __safeDI_title: title)
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

					    @Received(onlyIfAvailable: true) let theme: Theme?
					}

					struct Theme: Sendable {
					    init() {}
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

					    @Forwarded package let title: String
					    @Instantiated package let service: Service
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
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_title: @autoclosure @escaping () -> String) {
				        self.init(__safeDI_theme: nil, __safeDI_title: __safeDI_title())
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    internal convenience init(__safeDI_theme: @autoclosure @escaping () -> Theme?, __safeDI_title: @autoclosure @escaping () -> String) {
				        let theme = LazilyInstantiated<Theme?>(__safeDI_theme)
				        let title = LazilyInstantiated<String>(__safeDI_title)
				        let badge = Badge(theme: theme.instance)
				        let header = Header(title: title.instance)
				        self.init(badge: badge, header: header)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_2BA66E1683389903 {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Service+SafeDI.swift": generatedFileHeader + """
				extension Service {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_title: @autoclosure @escaping () -> String) {
				        self.init(__safeDI_theme: nil, __safeDI_title: __safeDI_title())
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    internal convenience init(__safeDI_theme: @autoclosure @escaping () -> Theme?, __safeDI_title: @autoclosure @escaping () -> String) {
				        let theme = LazilyInstantiated<Theme?>(__safeDI_theme)
				        let title = LazilyInstantiated<String>(__safeDI_title)
				        let badge = Badge(theme: theme.instance)
				        let header = Header(title: title.instance)
				        self.init(badge: badge, header: header)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_2BA66E1683389903 {}
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
				                _ = Service.__safeDI_Service_2BA66E1683389903.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				                return Service(__safeDI_title: title)
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
				                _ = Service.__safeDI_Service_2BA66E1683389903.self // If this line does not compile, add the SafeDI plugin to the target that declares Service.
				                return Service(__safeDI_title: title)
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

					    @Received(onlyIfAvailable: true) package let theme: Theme?
					}

					package struct Theme: Sendable {
					    package init() {}
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
					    package init(shellBuilder: Instantiator<MidShell>) {
					        self.shellBuilder = shellBuilder
					    }

					    @Instantiated package let shellBuilder: Instantiator<MidShell>
					}
					""",
					"""
					import Feature

					@Instantiable
					package final class MidShell: Instantiable {
					    package init(theme: Theme, title: String, service: Service) {
					        self.theme = theme
					        self.title = title
					        self.service = service
					    }

					    @Forwarded package let theme: Theme
					    @Forwarded package let title: String
					    @Instantiated package let service: Service
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
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_title: @autoclosure @escaping () -> String) {
				        self.init(__safeDI_theme: nil, __safeDI_title: __safeDI_title())
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    package convenience init(__safeDI_theme: @autoclosure @escaping () -> Theme?, __safeDI_title: @autoclosure @escaping () -> String) {
				        let theme = LazilyInstantiated<Theme?>(__safeDI_theme)
				        let title = LazilyInstantiated<String>(__safeDI_title)
				        let badge = Badge(theme: theme.instance)
				        let header = Header(title: title.instance)
				        self.init(badge: badge, header: header)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_29874EE5B00C89A6 {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Service+SafeDI.swift": generatedFileHeader + """
				extension Service {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_title: @autoclosure @escaping () -> String) {
				        self.init(__safeDI_theme: nil, __safeDI_title: __safeDI_title())
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    package convenience init(__safeDI_theme: @autoclosure @escaping () -> Theme?, __safeDI_title: @autoclosure @escaping () -> String) {
				        let theme = LazilyInstantiated<Theme?>(__safeDI_theme)
				        let title = LazilyInstantiated<String>(__safeDI_title)
				        let badge = Badge(theme: theme.instance)
				        let header = Header(title: title.instance)
				        self.init(badge: badge, header: header)
				    }
				}

				extension Service {
				    public enum __safeDI_Service_29874EE5B00C89A6 {}
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
				                _ = Service.__safeDI_Service_29874EE5B00C89A6.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				                return Service(__safeDI_theme: theme, __safeDI_title: title)
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
				                _ = Service.__safeDI_Service_29874EE5B00C89A6.self // If this line does not compile, add the SafeDI plugin to the target that declares Service.
				                return Service(__safeDI_theme: theme, __safeDI_title: title)
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

					    @Received(onlyIfAvailable: true) package let theme: Theme?
					}

					package struct Theme: Sendable {
					    package init() {}
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

					struct Color: Sendable {
					    init() {}
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
				    /// Code you write and code SafeDI generates can both call this initializer.
				    public convenience init() {
				        self.init(__safeDI_theme: nil)
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    package convenience init(__safeDI_theme: @autoclosure @escaping () -> Theme?) {
				        self.init(__safeDI_color: nil, __safeDI_theme: __safeDI_theme())
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    internal convenience init(__safeDI_color: @autoclosure @escaping () -> Color?, __safeDI_theme: @autoclosure @escaping () -> Theme?) {
				        let color = LazilyInstantiated<Color?>(__safeDI_color)
				        let theme = LazilyInstantiated<Theme?>(__safeDI_theme)
				        let badge = Badge(theme: theme.instance)
				        let tint = Tint(color: color.instance)
				        self.init(badge: badge, tint: tint)
				    }
				}

				extension Panel {
				    public enum __safeDI_Panel_6E041BAAAB16BF74 {}
				}

				extension Screen {
				    /// Code you write and code SafeDI generates can both call this initializer.
				    public convenience init() {
				        self.init(__safeDI_theme: nil)
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    package convenience init(__safeDI_theme: @autoclosure @escaping () -> Theme?) {
				        self.init(__safeDI_color: nil, __safeDI_theme: __safeDI_theme())
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    internal convenience init(__safeDI_color: @autoclosure @escaping () -> Color?, __safeDI_theme: @autoclosure @escaping () -> Theme?) {
				        let color = LazilyInstantiated<Color?>(__safeDI_color)
				        let theme = LazilyInstantiated<Theme?>(__safeDI_theme)
				        let badge = Badge(theme: theme.instance)
				        let tint = Tint(color: color.instance)
				        self.init(badge: badge, tint: tint)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_6E041BAAAB16BF74 {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Panel+SafeDI.swift": generatedFileHeader + """
				extension Panel {
				    /// Code you write and code SafeDI generates can both call this initializer.
				    public convenience init() {
				        self.init(__safeDI_theme: nil)
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    package convenience init(__safeDI_theme: @autoclosure @escaping () -> Theme?) {
				        self.init(__safeDI_color: nil, __safeDI_theme: __safeDI_theme())
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    internal convenience init(__safeDI_color: @autoclosure @escaping () -> Color?, __safeDI_theme: @autoclosure @escaping () -> Theme?) {
				        let color = LazilyInstantiated<Color?>(__safeDI_color)
				        let theme = LazilyInstantiated<Theme?>(__safeDI_theme)
				        let badge = Badge(theme: theme.instance)
				        let tint = Tint(color: color.instance)
				        self.init(badge: badge, tint: tint)
				    }
				}

				extension Panel {
				    public enum __safeDI_Panel_6E041BAAAB16BF74 {}
				}
				""",
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Code you write and code SafeDI generates can both call this initializer.
				    public convenience init() {
				        self.init(__safeDI_theme: nil)
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    package convenience init(__safeDI_theme: @autoclosure @escaping () -> Theme?) {
				        self.init(__safeDI_color: nil, __safeDI_theme: __safeDI_theme())
				    }

				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    internal convenience init(__safeDI_color: @autoclosure @escaping () -> Color?, __safeDI_theme: @autoclosure @escaping () -> Theme?) {
				        let color = LazilyInstantiated<Color?>(__safeDI_color)
				        let theme = LazilyInstantiated<Theme?>(__safeDI_theme)
				        let badge = Badge(theme: theme.instance)
				        let tint = Tint(color: color.instance)
				        self.init(badge: badge, tint: tint)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_6E041BAAAB16BF74 {}
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
				            _ = Screen.__safeDI_Screen_6E041BAAAB16BF74.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Screen()
				        }
				        let screen: Screen = __safeDI_screen()
				        func __safeDI_panel() -> Panel {
				            _ = Panel.__safeDI_Panel_6E041BAAAB16BF74.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
				            _ = Screen.__safeDI_Screen_6E041BAAAB16BF74.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen()
				        }
				        let screen: Screen = __safeDI_screen()
				        func __safeDI_panel() -> Panel {
				            _ = Panel.__safeDI_Panel_6E041BAAAB16BF74.self // If this line does not compile, add the SafeDI plugin to the target that declares Panel.
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
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_logger: @autoclosure @escaping () -> Logger) {
				        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
				        let detail = Detail(logger: logger.instance)
				        self.init(detail: detail)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_4FF58FD9C96A28C4 {}
				}
				""",
			],
			.swiftPackagePlugin: [
				"Screen+SafeDI.swift": generatedFileHeader + """
				extension Screen {
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_logger: @autoclosure @escaping () -> Logger) {
				        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
				        let detail = Detail(logger: logger.instance)
				        self.init(detail: detail)
				    }
				}

				extension Screen {
				    public enum __safeDI_Screen_4FF58FD9C96A28C4 {}
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
				                _ = Outer.__safeDI_Outer_4FF58FD9C96A28C4.self
				                return Outer(__safeDI_logger: logger)
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
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_logger: @autoclosure @escaping () -> Logger) {
				        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_4FF58FD9C96A28C4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				            return Screen(__safeDI_logger: logger.instance)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_4FF58FD9C96A28C4 {}
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
				                _ = Outer.__safeDI_Outer_4FF58FD9C96A28C4.self
				                return Outer(__safeDI_logger: logger)
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
				    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
				    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
				    public convenience init(__safeDI_logger: @autoclosure @escaping () -> Logger) {
				        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
				        func __safeDI_screen() -> Screen {
				            _ = Screen.__safeDI_Screen_4FF58FD9C96A28C4.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				            return Screen(__safeDI_logger: logger.instance)
				        }
				        let screen: Screen = __safeDI_screen()
				        self.init(screen: screen)
				    }
				}

				extension Outer {
				    public enum __safeDI_Outer_4FF58FD9C96A28C4 {}
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
				                    _ = Screen.__safeDI_Screen_4FF58FD9C96A28C4.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				                    return Screen(__safeDI_logger: logger)
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
				                    _ = Screen.__safeDI_Screen_4FF58FD9C96A28C4.self // If this line does not compile, add the SafeDI plugin to the target that declares Screen.
				                    return Screen(__safeDI_logger: logger)
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
		try expectDifferentialValuesAgree(
			feature: Self.path(featureFiles: featureFiles, midFiles: midFiles, output: output),
			knownRight: Self.path(featureFiles: featureFiles, midFiles: inlineMidFiles, output: inlineOutput),
			probes: [DifferentialValueProbe("MidRoot().holderBuilder.instantiate(Logger())")],
			filesToDelete: &filesToDelete,
		)
	}

	// MARK: Each tier names its builders apart from its own parameters and wider ones only

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsPublicTiersBuilderLabelAndEnum_whenPackageParameterTakesBuildersLabel() async throws {
		// `Badge`, a `package` type in `Host`'s tree, receives `serviceBuilder` only if available, so only `Host`'s `package`
		// tier takes it. The `public` tier names its builder `serviceBuilder` over `SafeDIScope_Service`, as it would without
		// `Badge`; the `package` tier names the same builder apart from its parameter. `Mid`, in `Host`'s package, calls the
		// `package` tier, and `App`, in another package, the `public` one.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.hostWithBadgeReceivingServiceBuilder, swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
				ModuleFixture(name: "Mid", packageName: "Shop", swiftFileContent: [Self.rootFillingServiceOfHost(named: "MidRoot")], dependencies: ["Feature"]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [Self.rootFillingServiceOfHost(named: "AppRoot")], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(try #require(output.modules["Feature"]).generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    @frozen public enum SafeDIScope_Service {
		        case service(service_Values)

		        public struct service_Values {
		            package var serviceBuilder: Thing? { __safeDI_serviceBuilder.instance }
		            package let badge: Badge
		            let __safeDI_serviceBuilder: LazilyInstantiated<Thing?>

		            init(serviceBuilder: LazilyInstantiated<Thing?>, badge: Badge) {
		                __safeDI_serviceBuilder = serviceBuilder
		                self.badge = badge
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(serviceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		        self.init(__safeDI_serviceBuilder: serviceBuilder)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_serviceBuilder __safeDI_serviceBuilder_: @escaping (SafeDIScope_Service) -> any Service) {
		        self.init(__safeDI_serviceBuilder: nil, __safeDI_service_ServiceBuilder: __safeDI_serviceBuilder_)
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    package init(serviceBuilder: Thing?, service_ServiceBuilder: @escaping (SafeDIScope_Service) -> any Service) {
		        self.init(__safeDI_serviceBuilder: serviceBuilder, __safeDI_service_ServiceBuilder: service_ServiceBuilder)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    package init(__safeDI_serviceBuilder: @autoclosure @escaping () -> Thing?, __safeDI_service_ServiceBuilder __safeDI_serviceBuilder_: @escaping (SafeDIScope_Service) -> any Service) {
		        let serviceBuilder = LazilyInstantiated<Thing?>(__safeDI_serviceBuilder)
		        let badge = Badge(serviceBuilder: serviceBuilder.instance)
		        let service: any Service = __safeDI_serviceBuilder_(.service(SafeDIScope_Service.service_Values(serviceBuilder: serviceBuilder, badge: badge)))
		        self.init(service: service, badge: badge)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_C6E7807A1A8B8684 {}
		}
		"""])
		#expect(try #require(output.modules["Mid"]).generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension MidRoot {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_C6E7807A1A8B8684.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_serviceBuilder_Host(_ scope: Host.SafeDIScope_Service) -> any Service {
		                switch scope {
		                case .service:
		                    let service: any Service = ServiceImpl()
		                    return service
		                }
		            }
		            return Host(__safeDI_serviceBuilder: nil, __safeDI_service_ServiceBuilder: __safeDI_serviceBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		#expect(try #require(output.modules["App"]).generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension AppRoot {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_C6E7807A1A8B8684.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_serviceBuilder_Host(_ scope: Host.SafeDIScope_Service) -> any Service {
		                switch scope {
		                case .service:
		                    let service: any Service = ServiceImpl()
		                    return service
		                }
		            }
		            return Host(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Host)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsPublicTiersStagedBuilderLabel_whenPackageParameterTakesBuildersLabel() async throws {
		// As above, but `Host` holds `service` in a `SendableLazilyInstantiated`, so the place is staged and has a builder of
		// its own. The `public` tier names it `serviceBuilder_service`, as it would without `Badge`; the `package` tier, whose
		// `serviceBuilder` parameter renames the hole type's stem, names it `service_ServiceBuilder_service`. `Mid`, in
		// `Host`'s package, passes its fill under the `package` tier's label, and `App`, in another package, under the
		// `public` one's.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.hostWithBadgeReceivingServiceBuilderAndSendableService, swiftFileContentByFilePath: plainDependencyTreeInitializersConfiguration),
				ModuleFixture(name: "Mid", packageName: "Shop", swiftFileContent: [Self.rootFillingServiceOfHost(named: "MidRoot")], dependencies: ["Feature"]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [Self.rootFillingServiceOfHost(named: "AppRoot")], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(try #require(output.modules["Feature"]).generatedFiles == ["Feature.swift": generatedFileHeader + """
		extension Host {
		    public enum SafeDIStagedScope_Service_service {
		        public struct Stage1 {
		            package var serviceBuilder: Thing? { __safeDI_serviceBuilder.instance }
		            package let badge: Badge
		            let __safeDI_serviceBuilder: LazilyInstantiated<Thing?>

		            init(serviceBuilder: LazilyInstantiated<Thing?>, badge: Badge) {
		                __safeDI_serviceBuilder = serviceBuilder
		                self.badge = badge
		            }
		        }

		        public struct Stage2 {}
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public init(serviceBuilder_service: @escaping (SafeDIStagedScope_Service_service.Stage1) -> @Sendable (SafeDIStagedScope_Service_service.Stage2) -> any Service) {
		        self.init(__safeDI_serviceBuilder_service: serviceBuilder_service)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public init(__safeDI_serviceBuilder_service: @escaping (SafeDIStagedScope_Service_service.Stage1) -> @Sendable (SafeDIStagedScope_Service_service.Stage2) -> any Service) {
		        self.init(__safeDI_serviceBuilder: nil, __safeDI_service_ServiceBuilder_service: __safeDI_serviceBuilder_service)
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    package init(serviceBuilder: Thing?, service_ServiceBuilder_service: @escaping (SafeDIStagedScope_Service_service.Stage1) -> @Sendable (SafeDIStagedScope_Service_service.Stage2) -> any Service) {
		        self.init(__safeDI_serviceBuilder: serviceBuilder, __safeDI_service_ServiceBuilder_service: service_ServiceBuilder_service)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    package init(__safeDI_serviceBuilder: @autoclosure @escaping () -> Thing?, __safeDI_service_ServiceBuilder_service __safeDI_serviceBuilder_service: @escaping (SafeDIStagedScope_Service_service.Stage1) -> @Sendable (SafeDIStagedScope_Service_service.Stage2) -> any Service) {
		        let serviceBuilder = LazilyInstantiated<Thing?>(__safeDI_serviceBuilder)
		        let badge = Badge(serviceBuilder: serviceBuilder.instance)
		        let __safeDI_serviceBuilder_service_Stage2 = __safeDI_serviceBuilder_service(SafeDIStagedScope_Service_service.Stage1(serviceBuilder: serviceBuilder, badge: badge))
		        @Sendable func __safeDI_service() -> any Service {
		            __safeDI_serviceBuilder_service_Stage2(SafeDIStagedScope_Service_service.Stage2())
		        }
		        let service = SendableLazilyInstantiated<any Service>(__safeDI_service)
		        self.init(service: service, badge: badge)
		    }
		}

		extension Host {
		    public enum __safeDI_Host_B6CC9A154A8FE04A {}
		}
		"""])
		#expect(try #require(output.modules["Mid"]).generatedFiles == ["Mid.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension MidRoot {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_B6CC9A154A8FE04A.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_service_ServiceBuilder_service(_ scope: Host.SafeDIStagedScope_Service_service.Stage1) -> @Sendable (Host.SafeDIStagedScope_Service_service.Stage2) -> any Service {
		                @Sendable func __safeDI_service_ServiceBuilder_service_Stage2(_ scope: Host.SafeDIStagedScope_Service_service.Stage2) -> any Service {
		                    @Sendable func __safeDI_service() -> ServiceImpl {
		                        ServiceImpl()
		                    }
		                    return __safeDI_service()
		                }
		                return __safeDI_service_ServiceBuilder_service_Stage2
		            }
		            return Host(__safeDI_serviceBuilder: nil, __safeDI_service_ServiceBuilder_service: __safeDI_service_ServiceBuilder_service)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
		#expect(try #require(output.modules["App"]).generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension AppRoot {
		    public init() {
		        func __safeDI_host() -> Host {
		            _ = Host.__safeDI_Host_B6CC9A154A8FE04A.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_serviceBuilder_service(_ scope: Host.SafeDIStagedScope_Service_service.Stage1) -> @Sendable (Host.SafeDIStagedScope_Service_service.Stage2) -> any Service {
		                @Sendable func __safeDI_serviceBuilder_service_Stage2(_ scope: Host.SafeDIStagedScope_Service_service.Stage2) -> any Service {
		                    @Sendable func __safeDI_service() -> ServiceImpl {
		                        ServiceImpl()
		                    }
		                    return __safeDI_service()
		                }
		                return __safeDI_serviceBuilder_service_Stage2
		            }
		            return Host(__safeDI_serviceBuilder_service: __safeDI_serviceBuilder_service)
		        }
		        let host: Host = __safeDI_host()
		        self.init(host: host)
		    }
		}
		"""])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Host`, a `public` seam holding the hole `service` and `badge`, whose `package` type receives `serviceBuilder: Thing?`
	/// only if available.
	private static let hostWithBadgeReceivingServiceBuilder = [
		"public protocol Service {}",
		"package struct Thing {}",
		"""
		@Instantiable
		package struct Badge: Instantiable {
		    package init(serviceBuilder: Thing?) {
		        self.serviceBuilder = serviceBuilder
		    }

		    @Received(onlyIfAvailable: true) let serviceBuilder: Thing?
		}
		""",
		"""
		@Instantiable(generateDependencyTree: true)
		public struct Host: Instantiable {
		    init(service: any Service, badge: Badge) {
		        self.service = service
		        self.badge = badge
		    }

		    @Instantiated let service: any Service
		    @Instantiated let badge: Badge
		}
		""",
	]

	/// `Host`, as `hostWithBadgeReceivingServiceBuilder` but holding the hole `service` in a `SendableLazilyInstantiated`,
	/// which makes the place staged.
	private static let hostWithBadgeReceivingServiceBuilderAndSendableService = [
		"public protocol Service: Sendable {}",
		"package struct Thing {}",
		"""
		@Instantiable
		package struct Badge: Instantiable {
		    package init(serviceBuilder: Thing?) {
		        self.serviceBuilder = serviceBuilder
		    }

		    @Received(onlyIfAvailable: true) let serviceBuilder: Thing?
		}
		""",
		"""
		@Instantiable(generateDependencyTree: true)
		public struct Host: Instantiable {
		    init(service: SendableLazilyInstantiated<any Service>, badge: Badge) {
		        self.service = service
		        self.badge = badge
		    }

		    @Instantiated let service: SendableLazilyInstantiated<any Service>
		    @Instantiated let badge: Badge
		}
		""",
	]

	/// A root named `name` that instantiates `Host` and declares `ServiceImpl`, which fills `Host`'s hole.
	private static func rootFillingServiceOfHost(named name: String) -> String {
		"""
		import Feature

		@Instantiable(fulfillingAdditionalTypes: [(any Service).self])
		public struct ServiceImpl: Instantiable, Service {
		    public init() {}
		}

		@Instantiable(isRoot: true)
		public struct \(name): Instantiable {
		    public init(host: Host) {
		        self.host = host
		    }

		    @Instantiated let host: Host
		}
		"""
	}

	private static let badgeWithPackageInit = """
	@Instantiable
	public struct Badge: Instantiable {
	    package init(theme: Theme?) {
	        self.theme = theme
	    }

	    @Received(onlyIfAvailable: true) package let theme: Theme?
	}

	package struct Theme: Sendable {
	    package init() {}
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
	    package init(shellBuilder: Instantiator<MidShell>) {
	        self.shellBuilder = shellBuilder
	    }

	    @Instantiated package let shellBuilder: Instantiator<MidShell>
	}
	"""
	private static let midShell = """
	import Feature

	@Instantiable
	package final class MidShell: Instantiable {
	    package init(theme: Theme, title: String, service: Service) {
	        self.theme = theme
	        self.title = title
	        self.service = service
	    }

	    @Forwarded package let theme: Theme
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
}
