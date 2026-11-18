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

/// A mock spells a protocol its tree builds as the property spells it, `any P`, wherever it names the type: the binding,
/// the builder function that returns it, the override closure that returns it, and a `mock()` parameter of it. So the mock
/// compiles in a module that enables the `ExistentialAny` upcoming feature, which every compile of these tests enables.
struct SafeDIToolMockExistentialAnyTests: ~Copyable {
	// MARK: Initialization

	init() throws {
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
	mutating func mock_spellsProtocolWithAnyInBindingAndOverride_whenTypeFulfillsItAsAnAdditionalType() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol Service {}
				""",
				"""
				@Instantiable(fulfillingAdditionalTypes: [Service.self])
				public final class DefaultService: Service, Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(service: any Service) {
				        self.service = service
				    }

				    @Instantiated let service: any Service
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(upcomingFeatures: [existentialAnyFeature]),
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let service: any Service = DefaultService()
			        self.init(service: service)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: (() -> any Service)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service
			            )
			        }

			        var service: (() -> any Service)? { __safeDI_storage.service }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: (() -> any Service)?
			            ) {
			                self.service = service
			            }

			            let service: (() -> any Service)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let service: any Service = if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { DefaultService() }
			        return Root(service: service)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsProtocolWithAnyInBindingAndOverride_whenModuleListsTypeInAdditionalMocksToGenerate() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#SafeDIConfiguration(additionalMocksToGenerate: ["Root"])
				""",
				"Service.swift": """
				public protocol Service {}

				@Instantiable(fulfillingAdditionalTypes: [Service.self])
				public final class DefaultService: Service, Instantiable {
				    public init() {}
				}
				""",
				"Root.swift": """
				@Instantiable
				public final class Root: Instantiable {
				    public init(service: any Service) {
				        self.service = service
				    }

				    @Instantiated let service: any Service
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(upcomingFeatures: [existentialAnyFeature]),
		)

		#expect(output.generatedFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: (() -> any Service)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service
			            )
			        }

			        var service: (() -> any Service)? { __safeDI_storage.service }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: (() -> any Service)?
			            ) {
			                self.service = service
			            }

			            let service: (() -> any Service)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let service: any Service = if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { DefaultService() }
			        return Root(service: service)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsProtocolWithAnyInBuilderFunction_whenErasedInstantiatorBuildsProtocol() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol Service {}
				""",
				"""
				@Instantiable
				public final class DefaultService: Service, Instantiable {
				    public init(name: String) {
				        self.name = name
				    }

				    @Forwarded let name: String
				}
				""",
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(serviceBuilder: ErasedInstantiator<String, any Service>) {
				        self.serviceBuilder = serviceBuilder
				    }

				    @Instantiated(fulfilledByType: "DefaultService") let serviceBuilder: ErasedInstantiator<String, any Service>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(upcomingFeatures: [existentialAnyFeature]),
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_serviceBuilder(name: String) -> DefaultService {
			            DefaultService(name: name)
			        }
			        let serviceBuilder = ErasedInstantiator<String, any Service> {
			            __safeDI_serviceBuilder(name: $0)
			        }
			        self.init(serviceBuilder: serviceBuilder)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            serviceBuilder: ((String) -> any Service)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                serviceBuilder: serviceBuilder
			            )
			        }

			        var serviceBuilder: ((String) -> any Service)? { __safeDI_storage.serviceBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                serviceBuilder: ((String) -> any Service)?
			            ) {
			                self.serviceBuilder = serviceBuilder
			            }

			            let serviceBuilder: ((String) -> any Service)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_serviceBuilder(name: String) -> any Service {
			            if let safeDIBuilder = safeDIOverrides.serviceBuilder { safeDIBuilder(name) } else { DefaultService(name: name) }
			        }
			        let serviceBuilder = ErasedInstantiator<String, any Service> {
			            __safeDI_serviceBuilder(name: $0)
			        }
			        return Root(serviceBuilder: serviceBuilder)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsProtocolWithAnyInBuilderFunction_whenLazilyInstantiatedBuildsProtocol() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol Service {}
				""",
				"""
				@Instantiable(fulfillingAdditionalTypes: [Service.self])
				public final class DefaultService: Service, Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(service: LazilyInstantiated<any Service>) {
				        self.service = service
				    }

				    @Instantiated let service: LazilyInstantiated<any Service>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(upcomingFeatures: [existentialAnyFeature]),
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_service() -> DefaultService {
			            DefaultService()
			        }
			        let service = LazilyInstantiated<any Service>(__safeDI_service)
			        self.init(service: service)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: (() -> any Service)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service
			            )
			        }

			        var service: (() -> any Service)? { __safeDI_storage.service }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: (() -> any Service)?
			            ) {
			                self.service = service
			            }

			            let service: (() -> any Service)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_service() -> any Service {
			            if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { DefaultService() }
			        }
			        let service = LazilyInstantiated<any Service>(__safeDI_service)
			        return Root(service: service)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsProtocolWithAnyInParameter_whenNoTypeFulfillsInstantiatedProtocol() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol Service {}
				""",
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(service: any Service) {
				        self.service = service
				    }

				    @Instantiated let service: any Service
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(upcomingFeatures: [existentialAnyFeature]),
		)

		#expect(output.generatedFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    static func mock(
			        service: any Service
			    ) -> Screen {
			        return Screen(service: service)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	// MARK: Tests – A received protocol spelled apart

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsPromotedReceiveAsMockedTypeDeclaresIt_whenMockedTypeSpellsAnyWhereReceiverInItsTreeSpellsBare() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.serviceFixture,
				Self.grandChildFixture(sharedType: "Service"),
				Self.loneFixture(sharedType: "any Service"),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Lone+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Lone {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            shared: (() -> any Service)? = nil,
			            grand: ((Service) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                shared: shared,
			                grand: grand
			            )
			        }

			        var shared: (() -> any Service)? { __safeDI_storage.shared }
			        var grand: ((Service) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                shared: (() -> any Service)?,
			                grand: ((Service) -> GrandChild)?
			            ) {
			                self.shared = shared
			                self.grand = grand
			            }

			            let shared: (() -> any Service)?
			            let grand: ((Service) -> GrandChild)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let shared: any Service = if let safeDIBuilder = safeDIOverrides.shared { safeDIBuilder() } else { DefaultService() }
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        return Lone(shared: shared, grand: grand)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsPromotedReceiveAsMockedTypeDeclaresIt_whenMockedTypeSpellsBareWhereReceiverInItsTreeSpellsAny() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.serviceFixture,
				Self.grandChildFixture(sharedType: "any Service"),
				Self.loneFixture(sharedType: "Service"),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Lone+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Lone {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            shared: (() -> Service)? = nil,
			            grand: ((any Service) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                shared: shared,
			                grand: grand
			            )
			        }

			        var shared: (() -> Service)? { __safeDI_storage.shared }
			        var grand: ((any Service) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                shared: (() -> Service)?,
			                grand: ((any Service) -> GrandChild)?
			            ) {
			                self.shared = shared
			                self.grand = grand
			            }

			            let shared: (() -> Service)?
			            let grand: ((any Service) -> GrandChild)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let shared: Service = if let safeDIBuilder = safeDIOverrides.shared { safeDIBuilder() } else { DefaultService() }
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        return Lone(shared: shared, grand: grand)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsPromotedReceiveAsMockedTypeDeclaresIt_whenMockedTypeReceivesOptionalProtocolOnlyIfAvailable() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.serviceFixture,
				Self.grandChildFixture(sharedType: "Service"),
				Self.loneFixture(sharedType: "(any Service)?", receivedAttribute: "@Received(onlyIfAvailable: true)"),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Lone+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Lone {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            shared: (() -> any Service)? = nil,
			            grand: ((Service) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                shared: shared,
			                grand: grand
			            )
			        }

			        var shared: (() -> any Service)? { __safeDI_storage.shared }
			        var grand: ((Service) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                shared: (() -> any Service)?,
			                grand: ((Service) -> GrandChild)?
			            ) {
			                self.shared = shared
			                self.grand = grand
			            }

			            let shared: (() -> any Service)?
			            let grand: ((Service) -> GrandChild)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let shared: any Service = if let safeDIBuilder = safeDIOverrides.shared { safeDIBuilder() } else { DefaultService() }
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        return Lone(shared: shared, grand: grand)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsPromotedReceiveAsMockedTypeDeclaresIt_whenMockedTypeReceivesLazilyInstantiatedProtocol() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.serviceFixture,
				Self.grandChildFixture(sharedType: "LazilyInstantiated<Service>"),
				Self.loneFixture(sharedType: "LazilyInstantiated<any Service>"),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Lone+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Lone {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            shared: (() -> any Service)? = nil,
			            grand: ((LazilyInstantiated<Service>) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                shared: shared,
			                grand: grand
			            )
			        }

			        var shared: (() -> any Service)? { __safeDI_storage.shared }
			        var grand: ((LazilyInstantiated<Service>) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                shared: (() -> any Service)?,
			                grand: ((LazilyInstantiated<Service>) -> GrandChild)?
			            ) {
			                self.shared = shared
			                self.grand = grand
			            }

			            let shared: (() -> any Service)?
			            let grand: ((LazilyInstantiated<Service>) -> GrandChild)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        func __safeDI_shared() -> any Service {
			            if let safeDIBuilder = safeDIOverrides.shared { safeDIBuilder() } else { DefaultService() }
			        }
			        let shared = LazilyInstantiated<any Service>(__safeDI_shared)
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        return Lone(shared: shared, grand: grand)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsPromotedReceiveAsMockedTypeDeclaresIt_whenModuleListsMockedTypeInAdditionalMocksToGenerate() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: [
				"SafeDIConfiguration.swift": """
				#SafeDIConfiguration(additionalMocksToGenerate: ["Lone"])
				""",
				"Service.swift": Self.serviceFixture,
				"GrandChild.swift": Self.grandChildFixture(sharedType: "Service"),
				"Lone.swift": Self.loneFixture(sharedType: "any Service", instantiableAttribute: "@Instantiable"),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Lone+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Lone {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            shared: (() -> any Service)? = nil,
			            grand: ((Service) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                shared: shared,
			                grand: grand
			            )
			        }

			        var shared: (() -> any Service)? { __safeDI_storage.shared }
			        var grand: ((Service) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                shared: (() -> any Service)?,
			                grand: ((Service) -> GrandChild)?
			            ) {
			                self.shared = shared
			                self.grand = grand
			            }

			            let shared: (() -> any Service)?
			            let grand: ((Service) -> GrandChild)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let shared: any Service = if let safeDIBuilder = safeDIOverrides.shared { safeDIBuilder() } else { DefaultService() }
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        return Lone(shared: shared, grand: grand)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsPromotedReceiveAsMockedTypeDeclaresIt_whenMockIsPublicAndReceiverInItsTreeIsInModuleItImports(integration: MultiModuleIntegration) async throws {
		// `Core` spells `Service` without `any`, as a module that has not enabled `ExistentialAny` may, and `Feature`, which
		// has, spells it with `any`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Core", swiftFileContentByFilePath: [
					"Service.swift": "import SafeDI\n\n" + Self.serviceFixture,
					"GrandChild.swift": "import SafeDI\n\n" + Self.grandChildFixture(sharedType: "Service"),
				]),
				ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContentByFilePath: [
					"Lone.swift": "import Core\nimport SafeDI\n\n" + Self.loneFixture(sharedType: "any Service", instantiableAttribute: "@Instantiable(generateMock: .public)"),
				], dependencies: ["Core"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let mockFile = generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Lone {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            shared: (() -> any Service)? = nil,
		            grand: ((Service) -> GrandChild)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                shared: shared,
		                grand: grand
		            )
		        }

		        public var shared: (() -> any Service)? { __safeDI_storage.shared }
		        public var grand: ((Service) -> GrandChild)? { __safeDI_storage.grand }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                shared: (() -> any Service)?,
		                grand: ((Service) -> GrandChild)?
		            ) {
		                self.shared = shared
		                self.grand = grand
		            }

		            let shared: (() -> any Service)?
		            let grand: ((Service) -> GrandChild)?
		        }
		    }

		    public static func mock(
		        shared: (any Service)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Lone {
		        let shared: any Service = if let shared { shared } else if let safeDIBuilder = safeDIOverrides.shared { safeDIBuilder() } else { DefaultService() }
		        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
		        return Lone(shared: shared, grand: grand)
		    }
		}

		extension Lone {
		    public enum __safeDI_Lone_mock_FE2EA18EBD87E595 {}
		}
		#endif
		"""
		let featureFiles: [String: String] = output.modules["Feature"]?.generatedFiles ?? [:]
		switch integration {
		case .moduleInfo:
			#expect(featureFiles == ["Feature.swift": mockFile], "Unexpected output \(featureFiles)")
		case .swiftPackagePlugin:
			let mockedFile: String? = featureFiles["Lone+SafeDIMock.swift"]
			#expect(mockedFile == mockFile, "Unexpected output \(featureFiles)")
		}
	}

	// MARK: Tests – A protocol the mock takes, spelled apart

	@Test(arguments: ReceivedProtocolSpellings.allCases, InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsFlatReceivedParameterAsMockedTypeDeclaresIt_whenNoTypeFulfillsReceivedProtocol(spellings: ReceivedProtocolSpellings, caller: InternalMockCaller) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				Self.protocolFixture,
				grandChild: Self.grandChildFixture(sharedType: spellings.receiverInTree),
				lone: Self.loneFixture(sharedType: spellings.mockedType, instantiableAttribute: caller.attribute),
			),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Lone+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Lone {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            grand: ((\(spellings.receiverInTree)) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                grand: grand
			            )
			        }

			        var grand: ((\(spellings.receiverInTree)) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                grand: ((\(spellings.receiverInTree)) -> GrandChild)?
			            ) {
			                self.grand = grand
			            }

			            let grand: ((\(spellings.receiverInTree)) -> GrandChild)?
			        }
			    }

			    static func mock(
			        shared: \(spellings.mockedType),
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        return Lone(shared: shared, grand: grand)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: ReceivedProtocolSpellings.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsFlatReceivedParameterAsMockedTypeDeclaresIt_whenMockIsPublic(spellings: ReceivedProtocolSpellings) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.protocolFixture,
				Self.grandChildFixture(sharedType: spellings.receiverInTree),
				Self.loneFixture(sharedType: spellings.mockedType, instantiableAttribute: "@Instantiable(generateMock: .public)"),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Lone+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Lone {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            grand: ((\(spellings.receiverInTree)) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                grand: grand
			            )
			        }

			        public var grand: ((\(spellings.receiverInTree)) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                grand: ((\(spellings.receiverInTree)) -> GrandChild)?
			            ) {
			                self.grand = grand
			            }

			            let grand: ((\(spellings.receiverInTree)) -> GrandChild)?
			        }
			    }

			    public static func mock(
			        shared: \(spellings.mockedType),
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        return Lone(shared: shared, grand: grand)
			    }
			}

			extension Lone {
			    public enum __safeDI_Lone_mock_5A94C95D789D83D1 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: ReceivedProtocolSpellings.allCases, InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsFlatReceivedParameterAsMockedTypeDeclaresIt_whenMockedTypeReceivesOptionalProtocolOnlyIfAvailable(spellings: ReceivedProtocolSpellings, caller: InternalMockCaller) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				Self.protocolFixture,
				grandChild: Self.grandChildFixture(sharedType: spellings.receiverInTree),
				lone: Self.loneFixture(sharedType: spellings.mockedTypeOptional, receivedAttribute: "@Received(onlyIfAvailable: true)", instantiableAttribute: caller.attribute),
			),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Lone+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Lone {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            grand: ((\(spellings.receiverInTree)) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                grand: grand
			            )
			        }

			        var grand: ((\(spellings.receiverInTree)) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                grand: ((\(spellings.receiverInTree)) -> GrandChild)?
			            ) {
			                self.grand = grand
			            }

			            let grand: ((\(spellings.receiverInTree)) -> GrandChild)?
			        }
			    }

			    static func mock(
			        shared: \(spellings.mockedType),
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        return Lone(shared: shared, grand: grand)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: ReceivedProtocolSpellings.allCases, InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsFlatReceivedParameterAsMockedTypeDeclaresIt_whenMockedTypeReceivesProtocolThroughAlias(spellings: ReceivedProtocolSpellings, caller: InternalMockCaller) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				Self.protocolFixture,
				grandChild: Self.grandChildFixture(sharedType: spellings.receiverInTree),
				lone: Self.aliasingLoneFixture(otherType: spellings.mockedType, instantiableAttribute: caller.attribute),
			),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Lone+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Lone {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            grand: ((\(spellings.receiverInTree)) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                grand: grand
			            )
			        }

			        var grand: ((\(spellings.receiverInTree)) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                grand: ((\(spellings.receiverInTree)) -> GrandChild)?
			            ) {
			                self.grand = grand
			            }

			            let grand: ((\(spellings.receiverInTree)) -> GrandChild)?
			        }
			    }

			    static func mock(
			        shared: \(spellings.mockedType),
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        #sourceLocation(file: "\(output.fixtures["Lone.swift"])", line: 9)
			        let other: \(spellings.mockedType) = shared
			        #sourceLocation()
			        return Lone(grand: grand, other: other)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: ReceivedProtocolSpellings.allCases, InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsFlatReceivedParameterAsMockedTypeDeclaresIt_whenReceiverInItsTreeReceivesLazilyInstantiatedProtocol(spellings: ReceivedProtocolSpellings, caller: InternalMockCaller) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				Self.protocolFixture,
				grandChild: Self.grandChildFixture(sharedType: "LazilyInstantiated<\(spellings.receiverInTree)>"),
				lone: Self.loneFixture(sharedType: spellings.mockedType, instantiableAttribute: caller.attribute),
			),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Lone+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Lone {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            grand: ((LazilyInstantiated<\(spellings.receiverInTree)>) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                grand: grand
			            )
			        }

			        var grand: ((LazilyInstantiated<\(spellings.receiverInTree)>) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                grand: ((LazilyInstantiated<\(spellings.receiverInTree)>) -> GrandChild)?
			            ) {
			                self.grand = grand
			            }

			            let grand: ((LazilyInstantiated<\(spellings.receiverInTree)>) -> GrandChild)?
			        }
			    }

			    static func mock(
			        shared: \(spellings.mockedType),
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let shared_lazilyInstantiated = LazilyInstantiated<\(spellings.mockedType)> { shared }
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared_lazilyInstantiated) } else { GrandChild(shared: shared_lazilyInstantiated) }
			        return Lone(shared: shared, grand: grand)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: ReceivedProtocolSpellings.allCases, InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsOnlyIfAvailableOverrideAsMockedTypeDeclaresIt_whenEveryReceiverReceivesProtocolOnlyIfAvailable(spellings: ReceivedProtocolSpellings, caller: InternalMockCaller) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				Self.serviceFixture,
				grandChild: Self.grandChildFixture(sharedType: spellings.receiverInTreeOptional, receivedAttribute: "@Received(onlyIfAvailable: true)"),
				lone: Self.loneFixture(sharedType: spellings.mockedTypeOptional, receivedAttribute: "@Received(onlyIfAvailable: true)", instantiableAttribute: caller.attribute),
			),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Lone+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Lone {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            grand: ((\(spellings.receiverInTreeOptional)) -> GrandChild)? = nil,
			            shared: \(spellings.mockedTypeOptional) = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                grand: grand
			            )
			            self.shared = shared
			        }

			        var grand: ((\(spellings.receiverInTreeOptional)) -> GrandChild)? { __safeDI_storage.grand }
			        let shared: \(spellings.mockedTypeOptional)

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                grand: ((\(spellings.receiverInTreeOptional)) -> GrandChild)?
			            ) {
			                self.grand = grand
			            }

			            let grand: ((\(spellings.receiverInTreeOptional)) -> GrandChild)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let shared: \(spellings.mockedTypeOptional) = safeDIOverrides.shared
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        return Lone(shared: shared, grand: grand)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: ReceivedProtocolSpellings.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsOnlyIfAvailableParameterAsMockedTypeDeclaresIt_whenMockIsPublic(spellings: ReceivedProtocolSpellings) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.serviceFixture,
				Self.grandChildFixture(sharedType: spellings.receiverInTreeOptional, receivedAttribute: "@Received(onlyIfAvailable: true)"),
				Self.loneFixture(sharedType: spellings.mockedTypeOptional, receivedAttribute: "@Received(onlyIfAvailable: true)", instantiableAttribute: "@Instantiable(generateMock: .public)"),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Lone+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Lone {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            grand: ((\(spellings.receiverInTreeOptional)) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                grand: grand
			            )
			        }

			        public var grand: ((\(spellings.receiverInTreeOptional)) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                grand: ((\(spellings.receiverInTreeOptional)) -> GrandChild)?
			            ) {
			                self.grand = grand
			            }

			            let grand: ((\(spellings.receiverInTreeOptional)) -> GrandChild)?
			        }
			    }

			    public static func mock(
			        shared: \(spellings.mockedTypeOptional) = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        return Lone(shared: shared, grand: grand)
			    }
			}

			extension Lone {
			    public enum __safeDI_Lone_mock_FE2EA18EBD87E595 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: ReceivedProtocolSpellings.allCases, InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsPromotedReceiveAsMockedTypeDeclaresIt_whenReceiverInItsTreeReceivesLazilyInstantiatedProtocol(spellings: ReceivedProtocolSpellings, caller: InternalMockCaller) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				Self.serviceFixture,
				grandChild: Self.grandChildFixture(sharedType: "LazilyInstantiated<\(spellings.receiverInTree)>"),
				lone: Self.loneFixture(sharedType: spellings.mockedType, instantiableAttribute: caller.attribute),
			),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Lone+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Lone {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            shared: (() -> \(spellings.mockedType))? = nil,
			            grand: ((LazilyInstantiated<\(spellings.receiverInTree)>) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                shared: shared,
			                grand: grand
			            )
			        }

			        var shared: (() -> \(spellings.mockedType))? { __safeDI_storage.shared }
			        var grand: ((LazilyInstantiated<\(spellings.receiverInTree)>) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                shared: (() -> \(spellings.mockedType))?,
			                grand: ((LazilyInstantiated<\(spellings.receiverInTree)>) -> GrandChild)?
			            ) {
			                self.shared = shared
			                self.grand = grand
			            }

			            let shared: (() -> \(spellings.mockedType))?
			            let grand: ((LazilyInstantiated<\(spellings.receiverInTree)>) -> GrandChild)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        func __safeDI_shared() -> \(spellings.mockedType) {
			            if let safeDIBuilder = safeDIOverrides.shared { safeDIBuilder() } else { DefaultService() }
			        }
			        let shared = LazilyInstantiated<\(spellings.mockedType)>(__safeDI_shared)
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        return Lone(shared: shared.instance, grand: grand)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: ReceivedProtocolSpellings.allCases, InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsPromotedReceiveAsMockedTypeDeclaresIt_whenReceiverInItsTreeReceivesSendableLazilyInstantiatedProtocol(spellings: ReceivedProtocolSpellings, caller: InternalMockCaller) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				Self.serviceFixture,
				grandChild: Self.grandChildFixture(sharedType: "SendableLazilyInstantiated<\(spellings.receiverInTree)>"),
				lone: Self.loneFixture(sharedType: spellings.mockedType, instantiableAttribute: caller.attribute),
			),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Lone+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Lone {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            shared: (@Sendable () -> \(spellings.mockedType))? = nil,
			            grand: ((SendableLazilyInstantiated<\(spellings.receiverInTree)>) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                shared: shared,
			                grand: grand
			            )
			        }

			        var shared: (@Sendable () -> \(spellings.mockedType))? { __safeDI_storage.shared }
			        var grand: ((SendableLazilyInstantiated<\(spellings.receiverInTree)>) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                shared: (@Sendable () -> \(spellings.mockedType))?,
			                grand: ((SendableLazilyInstantiated<\(spellings.receiverInTree)>) -> GrandChild)?
			            ) {
			                self.shared = shared
			                self.grand = grand
			            }

			            let shared: (@Sendable () -> \(spellings.mockedType))?
			            let grand: ((SendableLazilyInstantiated<\(spellings.receiverInTree)>) -> GrandChild)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let __safeDI_shared__safeDIBuilder = safeDIOverrides.shared
			        @Sendable func __safeDI_shared() -> \(spellings.mockedType) {
			            if let safeDIBuilder = __safeDI_shared__safeDIBuilder { safeDIBuilder() } else { DefaultService() }
			        }
			        let shared = SendableLazilyInstantiated<\(spellings.mockedType)>(__safeDI_shared)
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        return Lone(shared: shared.instance, grand: grand)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: ReceivedProtocolSpellings.allCases, InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsPromotedReceiveAsMockedTypeDeclaresIt_whenMockedTypeReceivesProtocolThroughAlias(spellings: ReceivedProtocolSpellings, caller: InternalMockCaller) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				Self.serviceFixture,
				grandChild: Self.grandChildFixture(sharedType: spellings.receiverInTree),
				lone: Self.aliasingLoneFixture(otherType: spellings.mockedType, instantiableAttribute: caller.attribute),
			),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Lone+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Lone {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            shared: (() -> \(spellings.mockedType))? = nil,
			            grand: ((\(spellings.receiverInTree)) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                shared: shared,
			                grand: grand
			            )
			        }

			        var shared: (() -> \(spellings.mockedType))? { __safeDI_storage.shared }
			        var grand: ((\(spellings.receiverInTree)) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                shared: (() -> \(spellings.mockedType))?,
			                grand: ((\(spellings.receiverInTree)) -> GrandChild)?
			            ) {
			                self.shared = shared
			                self.grand = grand
			            }

			            let shared: (() -> \(spellings.mockedType))?
			            let grand: ((\(spellings.receiverInTree)) -> GrandChild)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let shared: \(spellings.mockedType) = if let safeDIBuilder = safeDIOverrides.shared { safeDIBuilder() } else { DefaultService() }
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        #sourceLocation(file: "\(output.fixtures["Lone.swift"])", line: 9)
			        let other: \(spellings.mockedType) = shared
			        #sourceLocation()
			        return Lone(grand: grand, other: other)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	/// How the mocked type and a type in its tree spell one protocol they receive: one with `any`, the other without.
	enum ReceivedProtocolSpellings: CaseIterable, CustomTestStringConvertible {
		case mockedTypeSpellsAny
		case receiverInTreeSpellsAny

		/// How the mocked type spells the protocol.
		var mockedType: String {
			switch self {
			case .mockedTypeSpellsAny:
				"any Service"
			case .receiverInTreeSpellsAny:
				"Service"
			}
		}

		/// How the type in the mocked type's tree spells the protocol.
		var receiverInTree: String {
			switch self {
			case .mockedTypeSpellsAny:
				"Service"
			case .receiverInTreeSpellsAny:
				"any Service"
			}
		}

		/// How the mocked type spells the optional protocol.
		var mockedTypeOptional: String {
			Self.optional(mockedType)
		}

		/// How the type in the mocked type's tree spells the optional protocol.
		var receiverInTreeOptional: String {
			Self.optional(receiverInTree)
		}

		var testDescription: String {
			switch self {
			case .mockedTypeSpellsAny:
				"mocked type spells any"
			case .receiverInTreeSpellsAny:
				"receiver in its tree spells any"
			}
		}

		private static func optional(_ type: String) -> String {
			type.hasPrefix("any ") ? "(\(type))?" : "\(type)?"
		}
	}

	/// How a module asks for an internal mock of `Lone`: on its declaration, or in its `#SafeDIConfiguration`.
	enum InternalMockCaller: CaseIterable, CustomTestStringConvertible {
		case generateMock
		case additionalMocksToGenerate

		/// `Lone`'s attribute.
		var attribute: String {
			switch self {
			case .generateMock:
				"@Instantiable(generateMock: true)"
			case .additionalMocksToGenerate:
				"@Instantiable"
			}
		}

		var testDescription: String {
			switch self {
			case .generateMock:
				"generateMock"
			case .additionalMocksToGenerate:
				"additionalMocksToGenerate"
			}
		}

		/// The fixture's files, named for the types they declare, with the configuration that lists `Lone` where it is.
		func fixtureFiles(_ service: String, grandChild: String, lone: String) -> [String: String] {
			var files = [
				"Service.swift": service,
				"GrandChild.swift": grandChild,
				"Lone.swift": lone,
			]
			switch self {
			case .generateMock:
				break
			case .additionalMocksToGenerate:
				files["SafeDIConfiguration.swift"] = """
				#SafeDIConfiguration(additionalMocksToGenerate: ["Lone"])
				"""
			}
			return files
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Service`, which no type fulfills.
	private static let protocolFixture = """
	public protocol Service: Sendable {}
	"""

	/// `Service`, and `DefaultService`, which fulfills it.
	private static let serviceFixture = """
	public protocol Service: Sendable {}

	@Instantiable(fulfillingAdditionalTypes: [Service.self])
	public final class DefaultService: Service, Instantiable {
	    public init() {}
	}
	"""

	/// `GrandChild`, which receives `shared` as `sharedType` spells it.
	private static func grandChildFixture(sharedType: String, receivedAttribute: String = "@Received") -> String {
		"""
		@Instantiable
		public final class GrandChild: Instantiable {
		    public init(shared: \(sharedType)) {
		        self.shared = shared
		    }

		    \(receivedAttribute) let shared: \(sharedType)
		}
		"""
	}

	/// `Lone`, whose mock is generated, which instantiates `GrandChild` and then receives `shared` as `other`, through an
	/// alias whose type `otherType` spells.
	private static func aliasingLoneFixture(otherType: String, instantiableAttribute: String = "@Instantiable(generateMock: true)") -> String {
		"""
		\(instantiableAttribute)
		public final class Lone: Instantiable {
		    public init(grand: GrandChild, other: \(otherType)) {
		        self.grand = grand
		        self.other = other
		    }

		    @Instantiated let grand: GrandChild
		    @Received(fulfilledByDependencyNamed: "shared", ofType: \(otherType.hasPrefix("any ") ? "(\(otherType))" : otherType).self) let other: \(otherType)
		}
		"""
	}

	/// `Lone`, whose mock is generated, which receives `shared` as `sharedType` spells it, and instantiates `GrandChild`.
	private static func loneFixture(
		sharedType: String,
		receivedAttribute: String = "@Received",
		instantiableAttribute: String = "@Instantiable(generateMock: true)",
	) -> String {
		"""
		\(instantiableAttribute)
		public final class Lone: Instantiable {
		    public init(shared: \(sharedType), grand: GrandChild) {
		        self.shared = shared
		        self.grand = grand
		    }

		    \(receivedAttribute) let shared: \(sharedType)
		    @Instantiated let grand: GrandChild
		}
		"""
	}
}
