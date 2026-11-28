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
		        Lone.__safeDI_mock(shared: shared, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
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
			        Lone.__safeDI_mock(shared: shared, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
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
			        let other: \(spellings.mockedType) = shared // Declared as Lone.other
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
			        Lone.__safeDI_mock(shared: shared, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
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
			        @Sendable nonisolated func __safeDI_shared() -> \(spellings.mockedType) {
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
			        let other: \(spellings.mockedType) = shared // Declared as Lone.other
			        return Lone(grand: grand, other: other)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	// MARK: Tests – An alias whose `ofType:` names the protocol without `any`

	// `ofType: Service.self` is an expression, which the `ExistentialAny` upcoming feature does not flag, so it never decides
	// how the mock spells the dependency: the alias's own property does, and a direct receive of the dependency decides over
	// an alias, in whichever order the mocked type declares them.

	@Test(arguments: ["Service", "any Service"], InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsFlatReceivedParameterAsAliasPropertyDeclaresIt_whenAliasDeclaredAfterChildNamesProtocolWithoutAnyInOfType(receiverInTree: String, caller: InternalMockCaller) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				Self.protocolFixture,
				grandChild: Self.grandChildFixture(sharedType: receiverInTree),
				lone: Self.aliasingLoneFixture(otherType: "any Service", ofType: "Service", instantiableAttribute: caller.attribute),
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
			            grand: ((\(receiverInTree)) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                grand: grand
			            )
			        }

			        var grand: ((\(receiverInTree)) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                grand: ((\(receiverInTree)) -> GrandChild)?
			            ) {
			                self.grand = grand
			            }

			            let grand: ((\(receiverInTree)) -> GrandChild)?
			        }
			    }

			    static func mock(
			        shared: any Service,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        let other: any Service = shared // Declared as Lone.other
			        return Lone(grand: grand, other: other)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: ["Service", "any Service"], InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsPromotedReceiveAsAliasPropertyDeclaresIt_whenAliasDeclaredAfterChildNamesProtocolWithoutAnyInOfType(receiverInTree: String, caller: InternalMockCaller) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				Self.serviceFixture,
				grandChild: Self.grandChildFixture(sharedType: receiverInTree),
				lone: Self.aliasingLoneFixture(otherType: "any Service", ofType: "Service", instantiableAttribute: caller.attribute),
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
			            shared: (() -> any Service)? = nil,
			            grand: ((\(receiverInTree)) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                shared: shared,
			                grand: grand
			            )
			        }

			        var shared: (() -> any Service)? { __safeDI_storage.shared }
			        var grand: ((\(receiverInTree)) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                shared: (() -> any Service)?,
			                grand: ((\(receiverInTree)) -> GrandChild)?
			            ) {
			                self.shared = shared
			                self.grand = grand
			            }

			            let shared: (() -> any Service)?
			            let grand: ((\(receiverInTree)) -> GrandChild)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let shared: any Service = if let safeDIBuilder = safeDIOverrides.shared { safeDIBuilder() } else { DefaultService() }
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        let other: any Service = shared // Declared as Lone.other
			        return Lone(grand: grand, other: other)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: AliasedDependencyDeclarations.allCases, InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsFlatReceivedParameterAsMockedTypeDeclaresIt_whenAliasDeclaredBeforeChildNamesProtocolWithoutAnyInOfType(declarations: AliasedDependencyDeclarations, caller: InternalMockCaller) async throws {
		let (directReceive, aliasType) = (declarations.directReceive, declarations.aliasType)
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				Self.protocolFixture,
				grandChild: Self.grandChildFixture(sharedType: "any Service"),
				lone: directReceive.loneFixture(aliasType: aliasType, instantiableAttribute: caller.attribute),
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
			            grand: ((any Service) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                grand: grand
			            )
			        }

			        var grand: ((any Service) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                grand: ((any Service) -> GrandChild)?
			            ) {
			                self.grand = grand
			            }

			            let grand: ((any Service) -> GrandChild)?
			        }
			    }

			    static func mock(
			        shared: \(directReceive.spelling(aliasType: aliasType)),
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let other: \(aliasType) = shared // Declared as Lone.other
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        return Lone(\(directReceive.returnArguments))
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: AliasedDependencyDeclarations.allCases, InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsPromotedReceiveAsMockedTypeDeclaresIt_whenAliasDeclaredBeforeChildNamesProtocolWithoutAnyInOfType(declarations: AliasedDependencyDeclarations, caller: InternalMockCaller) async throws {
		let (directReceive, aliasType) = (declarations.directReceive, declarations.aliasType)
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				Self.serviceFixture,
				grandChild: Self.grandChildFixture(sharedType: "any Service"),
				lone: directReceive.loneFixture(aliasType: aliasType, instantiableAttribute: caller.attribute),
			),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		let spelling = directReceive.spelling(aliasType: aliasType)
		#expect(output.generatedFiles == [
			"Lone+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Lone {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            shared: (() -> \(spelling))? = nil,
			            grand: ((any Service) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                shared: shared,
			                grand: grand
			            )
			        }

			        var shared: (() -> \(spelling))? { __safeDI_storage.shared }
			        var grand: ((any Service) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                shared: (() -> \(spelling))?,
			                grand: ((any Service) -> GrandChild)?
			            ) {
			                self.shared = shared
			                self.grand = grand
			            }

			            let shared: (() -> \(spelling))?
			            let grand: ((any Service) -> GrandChild)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let shared: \(spelling) = if let safeDIBuilder = safeDIOverrides.shared { safeDIBuilder() } else { DefaultService() }
			        let other: \(aliasType) = shared // Declared as Lone.other
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        return Lone(\(directReceive.returnArguments))
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: AliasedDependencyDeclarations.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsPublicMockFlatReceivedParameterAsMockedTypeDeclaresIt_whenAliasDeclaredBeforeChildNamesProtocolWithoutAnyInOfType(declarations: AliasedDependencyDeclarations) async throws {
		let (directReceive, aliasType) = (declarations.directReceive, declarations.aliasType)
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: [
				"Service.swift": Self.protocolFixture,
				"GrandChild.swift": Self.grandChildFixture(sharedType: "any Service"),
				"Lone.swift": directReceive.loneFixture(aliasType: aliasType, instantiableAttribute: "@Instantiable(generateMock: .public)"),
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
			            grand: ((any Service) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                grand: grand
			            )
			        }

			        public var grand: ((any Service) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                grand: ((any Service) -> GrandChild)?
			            ) {
			                self.grand = grand
			            }

			            let grand: ((any Service) -> GrandChild)?
			        }
			    }

			    public static func mock(
			        shared: \(directReceive.spelling(aliasType: aliasType)),
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        Lone.__safeDI_mock(shared: shared, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        shared: \(directReceive.spelling(aliasType: aliasType)),
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let other: \(aliasType) = shared // Declared as Lone.other
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        return Lone(\(directReceive.returnArguments))
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

	@Test(arguments: AliasedDependencyDeclarations.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsPublicMockPromotedReceiveAsMockedTypeDeclaresIt_whenAliasDeclaredBeforeChildNamesProtocolWithoutAnyInOfType(declarations: AliasedDependencyDeclarations) async throws {
		let (directReceive, aliasType) = (declarations.directReceive, declarations.aliasType)
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: [
				"Service.swift": Self.serviceFixture,
				"GrandChild.swift": Self.grandChildFixture(sharedType: "any Service"),
				"Lone.swift": directReceive.loneFixture(aliasType: aliasType, instantiableAttribute: "@Instantiable(generateMock: .public)"),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		let spelling = directReceive.spelling(aliasType: aliasType)
		#expect(output.generatedFiles == [
			"Lone+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Lone {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            shared: (() -> \(spelling))? = nil,
			            grand: ((any Service) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                shared: shared,
			                grand: grand
			            )
			        }

			        public var shared: (() -> \(spelling))? { __safeDI_storage.shared }
			        public var grand: ((any Service) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                shared: (() -> \(spelling))?,
			                grand: ((any Service) -> GrandChild)?
			            ) {
			                self.shared = shared
			                self.grand = grand
			            }

			            let shared: (() -> \(spelling))?
			            let grand: ((any Service) -> GrandChild)?
			        }
			    }

			    public static func mock(
			        shared: \(spelling.hasPrefix("any ") ? "(\(spelling))?" : "\(spelling)?") = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        Lone.__safeDI_mock(shared: shared, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        shared: \(spelling.hasPrefix("any ") ? "(\(spelling))?" : "\(spelling)?") = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let shared: \(spelling) = if let shared { shared } else if let safeDIBuilder = safeDIOverrides.shared { safeDIBuilder() } else { DefaultService() }
			        let other: \(aliasType) = shared // Declared as Lone.other
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        return Lone(\(directReceive.returnArguments))
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

	@Test(arguments: InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsPromotedReceiveAsAliasPropertyDeclaresIt_whenOnlyIfAvailableAliasNamesProtocolWithoutAnyInOfType(caller: InternalMockCaller) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				Self.serviceFixture,
				grandChild: Self.grandChildFixture(sharedType: "any Service"),
				lone: """
				\(caller.attribute)
				public final class Lone: Instantiable {
				    public init(other: (any Service)?, grand: GrandChild) {
				        self.other = other
				        self.grand = grand
				    }
				    @Received(fulfilledByDependencyNamed: "shared", ofType: Service.self, onlyIfAvailable: true) let other: (any Service)?
				    @Instantiated let grand: GrandChild
				}
				""",
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
			            shared: (() -> any Service)? = nil,
			            grand: ((any Service) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                shared: shared,
			                grand: grand
			            )
			        }

			        var shared: (() -> any Service)? { __safeDI_storage.shared }
			        var grand: ((any Service) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                shared: (() -> any Service)?,
			                grand: ((any Service) -> GrandChild)?
			            ) {
			                self.shared = shared
			                self.grand = grand
			            }

			            let shared: (() -> any Service)?
			            let grand: ((any Service) -> GrandChild)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let shared: any Service = if let safeDIBuilder = safeDIOverrides.shared { safeDIBuilder() } else { DefaultService() }
			        let other: (any Service)? = shared // Declared as Lone.other
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        return Lone(other: other, grand: grand)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsPromotedReceiveAsAliasPropertyDeclaresIt_whenLazilyInstantiatedAliasNamesProtocolWithoutAnyInOfType(caller: InternalMockCaller) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				Self.serviceFixture,
				grandChild: Self.grandChildFixture(sharedType: "LazilyInstantiated<any Service>"),
				lone: """
				\(caller.attribute)
				public final class Lone: Instantiable {
				    public init(other: LazilyInstantiated<any Service>, grand: GrandChild) {
				        self.other = other
				        self.grand = grand
				    }
				    @Received(fulfilledByDependencyNamed: "shared", ofType: LazilyInstantiated<Service>.self) let other: LazilyInstantiated<any Service>
				    @Instantiated let grand: GrandChild
				}
				""",
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
			            shared: (() -> any Service)? = nil,
			            grand: ((LazilyInstantiated<any Service>) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                shared: shared,
			                grand: grand
			            )
			        }

			        var shared: (() -> any Service)? { __safeDI_storage.shared }
			        var grand: ((LazilyInstantiated<any Service>) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                shared: (() -> any Service)?,
			                grand: ((LazilyInstantiated<any Service>) -> GrandChild)?
			            ) {
			                self.shared = shared
			                self.grand = grand
			            }

			            let shared: (() -> any Service)?
			            let grand: ((LazilyInstantiated<any Service>) -> GrandChild)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        func __safeDI_shared() -> any Service {
			            if let safeDIBuilder = safeDIOverrides.shared { safeDIBuilder() } else { DefaultService() }
			        }
			        let shared = LazilyInstantiated<any Service>(__safeDI_shared)
			        let other: LazilyInstantiated<any Service> = shared // Declared as Lone.other
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        return Lone(other: other, grand: grand)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsPromotedReceiveAsAliasPropertyDeclaresIt_whenSendableLazilyInstantiatedAliasNamesProtocolWithoutAnyInOfType(caller: InternalMockCaller) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				Self.serviceFixture,
				grandChild: Self.grandChildFixture(sharedType: "SendableLazilyInstantiated<any Service>"),
				lone: """
				\(caller.attribute)
				public final class Lone: Instantiable {
				    public init(other: SendableLazilyInstantiated<any Service>, grand: GrandChild) {
				        self.other = other
				        self.grand = grand
				    }
				    @Received(fulfilledByDependencyNamed: "shared", ofType: SendableLazilyInstantiated<Service>.self) let other: SendableLazilyInstantiated<any Service>
				    @Instantiated let grand: GrandChild
				}
				""",
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
			            shared: (@Sendable () -> any Service)? = nil,
			            grand: ((SendableLazilyInstantiated<any Service>) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                shared: shared,
			                grand: grand
			            )
			        }

			        var shared: (@Sendable () -> any Service)? { __safeDI_storage.shared }
			        var grand: ((SendableLazilyInstantiated<any Service>) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                shared: (@Sendable () -> any Service)?,
			                grand: ((SendableLazilyInstantiated<any Service>) -> GrandChild)?
			            ) {
			                self.shared = shared
			                self.grand = grand
			            }

			            let shared: (@Sendable () -> any Service)?
			            let grand: ((SendableLazilyInstantiated<any Service>) -> GrandChild)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let __safeDI_shared__safeDIBuilder = safeDIOverrides.shared
			        @Sendable nonisolated func __safeDI_shared() -> any Service {
			            if let safeDIBuilder = __safeDI_shared__safeDIBuilder { safeDIBuilder() } else { DefaultService() }
			        }
			        let shared = SendableLazilyInstantiated<any Service>(__safeDI_shared)
			        let other: SendableLazilyInstantiated<any Service> = shared // Declared as Lone.other
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        return Lone(other: other, grand: grand)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsFlatReceivedParameterAsAliasPropertyDeclaresIt_whenErasedInstantiatorAliasNamesProtocolWithoutAnyInOfType(caller: InternalMockCaller) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				Self.protocolFixture,
				grandChild: Self.grandChildFixture(sharedType: "ErasedInstantiator<(), any Service>"),
				lone: """
				\(caller.attribute)
				public final class Lone: Instantiable {
				    public init(other: ErasedInstantiator<(), any Service>, grand: GrandChild) {
				        self.other = other
				        self.grand = grand
				    }
				    @Received(fulfilledByDependencyNamed: "shared", ofType: ErasedInstantiator<(), Service>.self) let other: ErasedInstantiator<(), any Service>
				    @Instantiated let grand: GrandChild
				}
				""",
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
			            grand: ((ErasedInstantiator<(), any Service>) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                grand: grand
			            )
			        }

			        var grand: ((ErasedInstantiator<(), any Service>) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                grand: ((ErasedInstantiator<(), any Service>) -> GrandChild)?
			            ) {
			                self.grand = grand
			            }

			            let grand: ((ErasedInstantiator<(), any Service>) -> GrandChild)?
			        }
			    }

			    static func mock(
			        shared: ErasedInstantiator<(), any Service>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let other: ErasedInstantiator<(), any Service> = shared // Declared as Lone.other
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        return Lone(other: other, grand: grand)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsPromotedReceiveAsFulfillingTypeDeclaresIt_whenAliasPropertyIsProtocolTheFulfillingTypeConformsTo(caller: InternalMockCaller) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				"""
				public protocol Service: Sendable {}

				@Instantiable
				public final class DefaultService: Service, Instantiable {
				    public init() {}
				}
				""",
				grandChild: Self.grandChildFixture(sharedType: "DefaultService"),
				lone: """
				\(caller.attribute)
				public final class Lone: Instantiable {
				    public init(other: any Service, grand: GrandChild) {
				        self.other = other
				        self.grand = grand
				    }
				    @Received(fulfilledByDependencyNamed: "shared", ofType: DefaultService.self) let other: any Service
				    @Instantiated let grand: GrandChild
				}
				""",
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
			            shared: (() -> DefaultService)? = nil,
			            grand: ((DefaultService) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                shared: shared,
			                grand: grand
			            )
			        }

			        var shared: (() -> DefaultService)? { __safeDI_storage.shared }
			        var grand: ((DefaultService) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                shared: (() -> DefaultService)?,
			                grand: ((DefaultService) -> GrandChild)?
			            ) {
			                self.shared = shared
			                self.grand = grand
			            }

			            let shared: (() -> DefaultService)?
			            let grand: ((DefaultService) -> GrandChild)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let shared = if let safeDIBuilder = safeDIOverrides.shared { safeDIBuilder() } else { DefaultService() }
			        let other: any Service = shared // Declared as Lone.other
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(shared) } else { GrandChild(shared: shared) }
			        return Lone(other: other, grand: grand)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsPromotedReceiveAsAliasPropertyDeclaresIt_whenTreeReceivesOnlyTheAliasAndOfTypeNamesProtocolWithoutAny() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: [
				"Service.swift": Self.serviceFixture,
				"GrandChild.swift": """
				@Instantiable
				public final class GrandChild: Instantiable {
				    public init(other: any Service) {
				        self.other = other
				    }
				    @Received let other: any Service
				}
				""",
				"Lone.swift": DirectReceiveOfAliasedDependency.absent.loneFixture(aliasType: "any Service", instantiableAttribute: "@Instantiable(generateMock: true)"),
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
			            grand: ((any Service) -> GrandChild)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                shared: shared,
			                grand: grand
			            )
			        }

			        var shared: (() -> any Service)? { __safeDI_storage.shared }
			        var grand: ((any Service) -> GrandChild)? { __safeDI_storage.grand }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                shared: (() -> any Service)?,
			                grand: ((any Service) -> GrandChild)?
			            ) {
			                self.shared = shared
			                self.grand = grand
			            }

			            let shared: (() -> any Service)?
			            let grand: ((any Service) -> GrandChild)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let shared: any Service = if let safeDIBuilder = safeDIOverrides.shared { safeDIBuilder() } else { DefaultService() }
			        let other: any Service = shared // Declared as Lone.other
			        let grand = if let safeDIBuilder = safeDIOverrides.grand { safeDIBuilder(other) } else { GrandChild(other: other) }
			        return Lone(other: other, grand: grand)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	/// How `Lone` declares the dependency it aliases (`DirectReceiveOfAliasedDependency.loneFixture(aliasType:instantiableAttribute:)`):
	/// whether and where it also receives it directly, and the type of the alias's property.
	struct AliasedDependencyDeclarations: CustomTestStringConvertible, Sendable {
		static let allCases = DirectReceiveOfAliasedDependency.allCases.flatMap { directReceive in
			["any Service", "Service"].map { aliasType in
				AliasedDependencyDeclarations(directReceive: directReceive, aliasType: aliasType)
			}
		}

		let directReceive: DirectReceiveOfAliasedDependency
		/// The type of the alias's property.
		let aliasType: String

		var testDescription: String {
			"\(directReceive.testDescription), alias of type \(aliasType)"
		}
	}

	/// Whether and where `Lone`, which receives `shared` as `other` through an alias whose `ofType:` is `Service.self` before
	/// it instantiates `GrandChild`, also receives `shared` directly, as `any Service`.
	enum DirectReceiveOfAliasedDependency: CaseIterable, CustomTestStringConvertible, Sendable {
		case absent
		case afterAlias
		case beforeAlias

		/// How the mock spells `shared` where the alias's property spells it `aliasType`: as the direct receive does, when
		/// there is one.
		func spelling(aliasType: String) -> String {
			switch self {
			case .absent:
				aliasType
			case .afterAlias, .beforeAlias:
				"any Service"
			}
		}

		/// The line of `loneFixture(aliasType:instantiableAttribute:)` that declares the alias.
		var aliasLine: Int {
			switch self {
			case .absent:
				7
			case .afterAlias:
				8
			case .beforeAlias:
				9
			}
		}

		/// The arguments the mock passes to `Lone`'s initializer.
		var returnArguments: String {
			switch self {
			case .absent:
				"other: other, grand: grand"
			case .afterAlias, .beforeAlias:
				"other: other, grand: grand, shared: shared"
			}
		}

		var testDescription: String {
			switch self {
			case .absent:
				"no direct receive"
			case .afterAlias:
				"direct receive after the alias"
			case .beforeAlias:
				"direct receive before the alias"
			}
		}

		/// `Lone`, whose alias's property spells `shared` as `aliasType`.
		func loneFixture(aliasType: String, instantiableAttribute: String) -> String {
			switch self {
			case .absent:
				"""
				\(instantiableAttribute)
				public final class Lone: Instantiable {
				    public init(other: \(aliasType), grand: GrandChild) {
				        self.other = other
				        self.grand = grand
				    }
				    @Received(fulfilledByDependencyNamed: "shared", ofType: Service.self) let other: \(aliasType)
				    @Instantiated let grand: GrandChild
				}
				"""
			case .afterAlias:
				"""
				\(instantiableAttribute)
				public final class Lone: Instantiable {
				    public init(other: \(aliasType), grand: GrandChild, shared: any Service) {
				        self.shared = shared
				        self.other = other
				        self.grand = grand
				    }
				    @Received(fulfilledByDependencyNamed: "shared", ofType: Service.self) let other: \(aliasType)
				    @Instantiated let grand: GrandChild
				    @Received let shared: any Service
				}
				"""
			case .beforeAlias:
				"""
				\(instantiableAttribute)
				public final class Lone: Instantiable {
				    public init(other: \(aliasType), grand: GrandChild, shared: any Service) {
				        self.shared = shared
				        self.other = other
				        self.grand = grand
				    }
				    @Received let shared: any Service
				    @Received(fulfilledByDependencyNamed: "shared", ofType: Service.self) let other: \(aliasType)
				    @Instantiated let grand: GrandChild
				}
				"""
			}
		}
	}

	@Test(arguments: ByValueAndLazilyInstantiatedSpellings.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsFlatReceivedParameterAndWrapperWithAny_whenAnotherReceiverInTreeReceivesLazilyInstantiatedProtocolSpelledApart(spellings: ByValueAndLazilyInstantiatedSpellings) async throws {
		// Twenty labels, each received by value and as a `LazilyInstantiated` spelled apart, so that a spelling chosen by
		// the order of a set, which Swift seeds per process, gives this output on almost no run. Two digits each, so that the
		// mock's label order is the order of declaration. The by-value receive and the wrapper's instance are one value,
		// which the mock spells one way, the more explicit; each receiver's override keeps its own spelling.
		let labels = (10..<30).map { "service\($0)" }
		var lazyReceiver = """
		@Instantiable
		public final class LazyReceiver: Instantiable {
		    public init(\(labels.map { "\($0): LazilyInstantiated<\(spellings.lazilyInstantiatedReceiver)>" }.joined(separator: ", "))) {
		        fatalError("SafeDI doesn't inspect the initializer body")
		    }

		"""
		var plainReceiver = """
		@Instantiable
		public final class PlainReceiver: Instantiable {
		    public init(\(labels.map { "\($0): \(spellings.byValueReceiver)" }.joined(separator: ", "))) {
		        fatalError("SafeDI doesn't inspect the initializer body")
		    }

		"""
		for label in labels {
			lazyReceiver.append("    @Received let \(label): LazilyInstantiated<\(spellings.lazilyInstantiatedReceiver)>\n")
			plainReceiver.append("    @Received let \(label): \(spellings.byValueReceiver)\n")
		}
		lazyReceiver.append("}")
		plainReceiver.append("}")
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.protocolFixture,
				lazyReceiver,
				plainReceiver,
				"""
				@Instantiable(generateMock: true)
				public final class Lone: Instantiable {
				    public init(lazyReceiver: LazyReceiver, plainReceiver: PlainReceiver) {
				        self.lazyReceiver = lazyReceiver
				        self.plainReceiver = plainReceiver
				    }

				    @Instantiated let lazyReceiver: LazyReceiver
				    @Instantiated let plainReceiver: PlainReceiver
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		let lazyReceiverClosure = "((\(labels.map { _ in "LazilyInstantiated<\(spellings.lazilyInstantiatedReceiver)>" }.joined(separator: ", "))) -> LazyReceiver)?"
		let plainReceiverClosure = "((\(labels.map { _ in spellings.byValueReceiver }.joined(separator: ", "))) -> PlainReceiver)?"
		var mockParameters = ""
		var wrapperBindings = ""
		for label in labels {
			mockParameters.append("        \(label): any Service,\n")
			wrapperBindings.append("        let \(label)_lazilyInstantiated = LazilyInstantiated<any Service> { \(label) }\n")
		}
		let wrapperArguments = labels.map { "\($0)_lazilyInstantiated" }.joined(separator: ", ")
		let lazyReceiverArguments = labels.map { "\($0): \($0)_lazilyInstantiated" }.joined(separator: ", ")
		let plainReceiverArguments = labels.map { "\($0): \($0)" }.joined(separator: ", ")
		let expectedMockFile: String = generatedFileHeader + """
		#if DEBUG
		extension Lone {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            lazyReceiver: \(lazyReceiverClosure) = nil,
		            plainReceiver: \(plainReceiverClosure) = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                lazyReceiver: lazyReceiver,
		                plainReceiver: plainReceiver
		            )
		        }

		        var lazyReceiver: \(lazyReceiverClosure) { __safeDI_storage.lazyReceiver }
		        var plainReceiver: \(plainReceiverClosure) { __safeDI_storage.plainReceiver }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                lazyReceiver: \(lazyReceiverClosure),
		                plainReceiver: \(plainReceiverClosure)
		            ) {
		                self.lazyReceiver = lazyReceiver
		                self.plainReceiver = plainReceiver
		            }

		            let lazyReceiver: \(lazyReceiverClosure)
		            let plainReceiver: \(plainReceiverClosure)
		        }
		    }

		    static func mock(
		\(mockParameters)        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Lone {
		\(wrapperBindings)        let lazyReceiver = if let safeDIBuilder = safeDIOverrides.lazyReceiver { safeDIBuilder(\(wrapperArguments)) } else { LazyReceiver(\(lazyReceiverArguments)) }
		        let plainReceiver = if let safeDIBuilder = safeDIOverrides.plainReceiver { safeDIBuilder(\(labels.joined(separator: ", "))) } else { PlainReceiver(\(plainReceiverArguments)) }
		        return Lone(lazyReceiver: lazyReceiver, plainReceiver: plainReceiver)
		    }
		}
		#endif
		"""
		#expect(output.generatedFiles == [
			"Lone+SafeDIMock.swift": expectedMockFile,
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	// MARK: Tests – Receivers in the tree spell the protocol apart

	@Test(arguments: TreeReceiverSpellings.allCases, InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsPromotedReceiveWithAny_whenTwoReceiversInItsTreeSpellItApart(spellings: TreeReceiverSpellings, caller: InternalMockCaller) async throws {
		// `Lone` receives `shared` in no form, so no spelling of its own decides: of its receivers' two, the more explicit.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				Self.serviceFixture,
				first: Self.receiverFixture(named: "First", sharedType: spellings.first),
				second: Self.receiverFixture(named: "Second", sharedType: spellings.second),
				lone: Self.twoReceiverLoneFixture(instantiableAttribute: caller.attribute),
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
			            shared: (() -> any Service)? = nil,
			            first: ((\(spellings.first)) -> First)? = nil,
			            second: ((\(spellings.second)) -> Second)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                shared: shared,
			                first: first,
			                second: second
			            )
			        }

			        var shared: (() -> any Service)? { __safeDI_storage.shared }
			        var first: ((\(spellings.first)) -> First)? { __safeDI_storage.first }
			        var second: ((\(spellings.second)) -> Second)? { __safeDI_storage.second }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                shared: (() -> any Service)?,
			                first: ((\(spellings.first)) -> First)?,
			                second: ((\(spellings.second)) -> Second)?
			            ) {
			                self.shared = shared
			                self.first = first
			                self.second = second
			            }

			            let shared: (() -> any Service)?
			            let first: ((\(spellings.first)) -> First)?
			            let second: ((\(spellings.second)) -> Second)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let shared: any Service = if let safeDIBuilder = safeDIOverrides.shared { safeDIBuilder() } else { DefaultService() }
			        let first = if let safeDIBuilder = safeDIOverrides.first { safeDIBuilder(shared) } else { First(shared: shared) }
			        let second = if let safeDIBuilder = safeDIOverrides.second { safeDIBuilder(shared) } else { Second(shared: shared) }
			        return Lone(first: first, second: second)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: TreeReceiverSpellings.allCases, InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsFlatReceivedParameterWithAny_whenTwoReceiversInItsTreeSpellItApart(spellings: TreeReceiverSpellings, caller: InternalMockCaller) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				Self.protocolFixture,
				first: Self.receiverFixture(named: "First", sharedType: spellings.first),
				second: Self.receiverFixture(named: "Second", sharedType: spellings.second),
				lone: Self.twoReceiverLoneFixture(instantiableAttribute: caller.attribute),
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
			            first: ((\(spellings.first)) -> First)? = nil,
			            second: ((\(spellings.second)) -> Second)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                first: first,
			                second: second
			            )
			        }

			        var first: ((\(spellings.first)) -> First)? { __safeDI_storage.first }
			        var second: ((\(spellings.second)) -> Second)? { __safeDI_storage.second }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                first: ((\(spellings.first)) -> First)?,
			                second: ((\(spellings.second)) -> Second)?
			            ) {
			                self.first = first
			                self.second = second
			            }

			            let first: ((\(spellings.first)) -> First)?
			            let second: ((\(spellings.second)) -> Second)?
			        }
			    }

			    static func mock(
			        shared: any Service,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let first = if let safeDIBuilder = safeDIOverrides.first { safeDIBuilder(shared) } else { First(shared: shared) }
			        let second = if let safeDIBuilder = safeDIOverrides.second { safeDIBuilder(shared) } else { Second(shared: shared) }
			        return Lone(first: first, second: second)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: TreeReceiverSpellings.allCases, InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsOnlyIfAvailableOverrideWithAny_whenTwoReceiversInItsTreeSpellItApart(spellings: TreeReceiverSpellings, caller: InternalMockCaller) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				Self.protocolFixture,
				first: Self.receiverFixture(named: "First", sharedType: spellings.firstOptional, receivedAttribute: "@Received(onlyIfAvailable: true)"),
				second: Self.receiverFixture(named: "Second", sharedType: spellings.secondOptional, receivedAttribute: "@Received(onlyIfAvailable: true)"),
				lone: Self.twoReceiverLoneFixture(instantiableAttribute: caller.attribute),
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
			            first: ((\(spellings.firstOptional)) -> First)? = nil,
			            second: ((\(spellings.secondOptional)) -> Second)? = nil,
			            shared: (any Service)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                first: first,
			                second: second
			            )
			            self.shared = shared
			        }

			        var first: ((\(spellings.firstOptional)) -> First)? { __safeDI_storage.first }
			        var second: ((\(spellings.secondOptional)) -> Second)? { __safeDI_storage.second }
			        let shared: (any Service)?

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                first: ((\(spellings.firstOptional)) -> First)?,
			                second: ((\(spellings.secondOptional)) -> Second)?
			            ) {
			                self.first = first
			                self.second = second
			            }

			            let first: ((\(spellings.firstOptional)) -> First)?
			            let second: ((\(spellings.secondOptional)) -> Second)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let shared: (any Service)? = safeDIOverrides.shared
			        let first = if let safeDIBuilder = safeDIOverrides.first { safeDIBuilder(shared) } else { First(shared: shared) }
			        let second = if let safeDIBuilder = safeDIOverrides.second { safeDIBuilder(shared) } else { Second(shared: shared) }
			        return Lone(first: first, second: second)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: TreeReceiverSpellings.allCases, InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsFlatReceivedParameterWithAny_whenOneReceiverInItsTreeRequiresItAndAnotherReceivesItsOptionalFormOnlyIfAvailable(spellings: TreeReceiverSpellings, caller: InternalMockCaller) async throws {
		// `First` requires `shared` and `Second` receives `shared: Service?` only if available: two forms of one value, which
		// the mock spells one way.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				Self.protocolFixture,
				first: Self.receiverFixture(named: "First", sharedType: spellings.first),
				second: Self.receiverFixture(named: "Second", sharedType: spellings.secondOptional, receivedAttribute: "@Received(onlyIfAvailable: true)"),
				lone: Self.twoReceiverLoneFixture(instantiableAttribute: caller.attribute),
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
			            first: ((\(spellings.first)) -> First)? = nil,
			            second: ((\(spellings.secondOptional)) -> Second)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                first: first,
			                second: second
			            )
			        }

			        var first: ((\(spellings.first)) -> First)? { __safeDI_storage.first }
			        var second: ((\(spellings.secondOptional)) -> Second)? { __safeDI_storage.second }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                first: ((\(spellings.first)) -> First)?,
			                second: ((\(spellings.secondOptional)) -> Second)?
			            ) {
			                self.first = first
			                self.second = second
			            }

			            let first: ((\(spellings.first)) -> First)?
			            let second: ((\(spellings.secondOptional)) -> Second)?
			        }
			    }

			    static func mock(
			        shared: any Service,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let first = if let safeDIBuilder = safeDIOverrides.first { safeDIBuilder(shared) } else { First(shared: shared) }
			        let second = if let safeDIBuilder = safeDIOverrides.second { safeDIBuilder(shared) } else { Second(shared: shared) }
			        return Lone(first: first, second: second)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: InternalMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsFlatReceivedParameterAsAliasesInItsTreeDeclareIt_whenEveryReceiverInItsTreeReceivesItThroughAliasOfBareOfType(caller: InternalMockCaller) async throws {
		// Every declaration spells `any Service`: `Service.self` is an expression, which the `ExistentialAny` upcoming
		// feature does not flag, so a `mock()` parameter spelled from it would be the only bare spelling in the module.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: caller.fixtureFiles(
				Self.protocolFixture,
				first: Self.aliasingReceiverFixture(named: "First"),
				second: Self.aliasingReceiverFixture(named: "Second"),
				lone: Self.twoReceiverLoneFixture(instantiableAttribute: caller.attribute),
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
			            first: ((any Service) -> First)? = nil,
			            second: ((any Service) -> Second)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                first: first,
			                second: second
			            )
			        }

			        var first: ((any Service) -> First)? { __safeDI_storage.first }
			        var second: ((any Service) -> Second)? { __safeDI_storage.second }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                first: ((any Service) -> First)?,
			                second: ((any Service) -> Second)?
			            ) {
			                self.first = first
			                self.second = second
			            }

			            let first: ((any Service) -> First)?
			            let second: ((any Service) -> Second)?
			        }
			    }

			    static func mock(
			        shared: any Service,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        func __safeDI_first() -> First {
			            let other: any Service = shared // Declared as First.other
			            return if let safeDIBuilder = safeDIOverrides.first { safeDIBuilder(other) } else { First(other: other) }
			        }
			        let first: First = __safeDI_first()
			        func __safeDI_second() -> Second {
			            let other: any Service = shared // Declared as Second.other
			            return if let safeDIBuilder = safeDIOverrides.second { safeDIBuilder(other) } else { Second(other: other) }
			        }
			        let second: Second = __safeDI_second()
			        return Lone(first: first, second: second)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		], "Unexpected output \(output.generatedFiles ?? [:])")
	}

	@Test(arguments: TreeReceiverSpellings.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsFlatReceivedParameterWithAny_whenMockIsPublicAndTwoReceiversInItsTreeSpellItApart(spellings: TreeReceiverSpellings) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.protocolFixture,
				Self.receiverFixture(named: "First", sharedType: spellings.first),
				Self.receiverFixture(named: "Second", sharedType: spellings.second),
				Self.twoReceiverLoneFixture(instantiableAttribute: "@Instantiable(generateMock: .public)"),
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
			            first: ((\(spellings.first)) -> First)? = nil,
			            second: ((\(spellings.second)) -> Second)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                first: first,
			                second: second
			            )
			        }

			        public var first: ((\(spellings.first)) -> First)? { __safeDI_storage.first }
			        public var second: ((\(spellings.second)) -> Second)? { __safeDI_storage.second }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                first: ((\(spellings.first)) -> First)?,
			                second: ((\(spellings.second)) -> Second)?
			            ) {
			                self.first = first
			                self.second = second
			            }

			            let first: ((\(spellings.first)) -> First)?
			            let second: ((\(spellings.second)) -> Second)?
			        }
			    }

			    public static func mock(
			        shared: any Service,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        Lone.__safeDI_mock(shared: shared, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        shared: any Service,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Lone {
			        let first = if let safeDIBuilder = safeDIOverrides.first { safeDIBuilder(shared) } else { First(shared: shared) }
			        let second = if let safeDIBuilder = safeDIOverrides.second { safeDIBuilder(shared) } else { Second(shared: shared) }
			        return Lone(first: first, second: second)
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

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsFlatReceivedParameterWithAny_whenReceiverInModuleItImportsSpellsItBare(integration: MultiModuleIntegration) async throws {
		// `Core` spells `Service` without `any`, as a module that has not enabled `ExistentialAny` may, and `Feature`, which
		// has, spells it with `any`: the mock, which `Feature` compiles, spells it with `any`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Core", swiftFileContentByFilePath: [
					"Service.swift": "import SafeDI\n\n" + Self.protocolFixture,
					"First.swift": "import SafeDI\n\n" + Self.receiverFixture(named: "First", sharedType: "Service"),
				]),
				ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContentByFilePath: [
					"Second.swift": "import Core\nimport SafeDI\n\n" + Self.receiverFixture(named: "Second", sharedType: "any Service"),
					"Lone.swift": "import Core\nimport SafeDI\n\n" + Self.twoReceiverLoneFixture(),
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
		    struct SafeDIOverrides {
		        init(
		            first: ((Service) -> First)? = nil,
		            second: ((any Service) -> Second)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                first: first,
		                second: second
		            )
		        }

		        var first: ((Service) -> First)? { __safeDI_storage.first }
		        var second: ((any Service) -> Second)? { __safeDI_storage.second }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                first: ((Service) -> First)?,
		                second: ((any Service) -> Second)?
		            ) {
		                self.first = first
		                self.second = second
		            }

		            let first: ((Service) -> First)?
		            let second: ((any Service) -> Second)?
		        }
		    }

		    static func mock(
		        shared: any Service,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Lone {
		        let first = if let safeDIBuilder = safeDIOverrides.first { safeDIBuilder(shared) } else { First(shared: shared) }
		        let second = if let safeDIBuilder = safeDIOverrides.second { safeDIBuilder(shared) } else { Second(shared: shared) }
		        return Lone(first: first, second: second)
		    }
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

	/// How one type in a mocked type's tree spells a protocol it receives by value, and another a `LazilyInstantiated` of
	/// it under the same label: one with `any`, the other without.
	enum ByValueAndLazilyInstantiatedSpellings: CaseIterable, CustomTestStringConvertible {
		case byValueReceiverSpellsAny
		case lazilyInstantiatedReceiverSpellsAny

		/// How the type that receives the protocol by value spells it.
		var byValueReceiver: String {
			switch self {
			case .byValueReceiverSpellsAny:
				"any Service"
			case .lazilyInstantiatedReceiverSpellsAny:
				"Service"
			}
		}

		/// How the type that receives a `LazilyInstantiated` of the protocol spells it.
		var lazilyInstantiatedReceiver: String {
			switch self {
			case .byValueReceiverSpellsAny:
				"Service"
			case .lazilyInstantiatedReceiverSpellsAny:
				"any Service"
			}
		}

		var testDescription: String {
			switch self {
			case .byValueReceiverSpellsAny:
				"by-value receiver spells any"
			case .lazilyInstantiatedReceiverSpellsAny:
				"lazily instantiated receiver spells any"
			}
		}
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

		fileprivate static func optional(_ type: String) -> String {
			type.hasPrefix("any ") ? "(\(type))?" : "\(type)?"
		}
	}

	/// How two types in the mocked type's tree, `First` and `Second`, spell one protocol they receive and the mocked type
	/// does not: one with `any`, the other without.
	enum TreeReceiverSpellings: CaseIterable, CustomTestStringConvertible {
		case firstSpellsAny
		case secondSpellsAny

		/// How `First` spells the protocol.
		var first: String {
			switch self {
			case .firstSpellsAny:
				"any Service"
			case .secondSpellsAny:
				"Service"
			}
		}

		/// How `Second` spells the protocol.
		var second: String {
			switch self {
			case .firstSpellsAny:
				"Service"
			case .secondSpellsAny:
				"any Service"
			}
		}

		/// How `First` spells the optional protocol.
		var firstOptional: String {
			ReceivedProtocolSpellings.optional(first)
		}

		/// How `Second` spells the optional protocol.
		var secondOptional: String {
			ReceivedProtocolSpellings.optional(second)
		}

		var testDescription: String {
			switch self {
			case .firstSpellsAny:
				"first receiver spells any"
			case .secondSpellsAny:
				"second receiver spells any"
			}
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

		/// The fixture's files for `Lone` with two receivers in its tree, named for the types they declare, with the
		/// configuration that lists `Lone` where it is.
		func fixtureFiles(_ service: String, first: String, second: String, lone: String) -> [String: String] {
			var files = [
				"Service.swift": service,
				"First.swift": first,
				"Second.swift": second,
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
	/// alias whose type `otherType` spells, and whose `ofType:` names `ofType`, or `otherType` when that is `nil`.
	private static func aliasingLoneFixture(otherType: String, ofType: String? = nil, instantiableAttribute: String = "@Instantiable(generateMock: true)") -> String {
		let ofType = ofType ?? otherType
		return """
		\(instantiableAttribute)
		public final class Lone: Instantiable {
		    public init(grand: GrandChild, other: \(otherType)) {
		        self.grand = grand
		        self.other = other
		    }

		    @Instantiated let grand: GrandChild
		    @Received(fulfilledByDependencyNamed: "shared", ofType: \(ofType.hasPrefix("any ") ? "(\(ofType))" : ofType).self) let other: \(otherType)
		}
		"""
	}

	/// A type named `name` that receives `shared` as `sharedType` spells it.
	private static func receiverFixture(named name: String, sharedType: String, receivedAttribute: String = "@Received") -> String {
		"""
		@Instantiable
		public final class \(name): Instantiable {
		    public init(shared: \(sharedType)) {
		        self.shared = shared
		    }

		    \(receivedAttribute) let shared: \(sharedType)
		}
		"""
	}

	/// A type named `name` that receives `shared` as `other`, through an alias whose `ofType:` names `Service` without
	/// `any` and whose type spells it with `any`.
	private static func aliasingReceiverFixture(named name: String) -> String {
		"""
		@Instantiable
		public final class \(name): Instantiable {
		    public init(other: any Service) {
		        self.other = other
		    }

		    @Received(fulfilledByDependencyNamed: "shared", ofType: Service.self) let other: any Service
		}
		"""
	}

	/// `Lone`, which instantiates `First` and then `Second`, and receives nothing itself.
	private static func twoReceiverLoneFixture(instantiableAttribute: String = "@Instantiable(generateMock: true)") -> String {
		"""
		\(instantiableAttribute)
		public final class Lone: Instantiable {
		    public init(first: First, second: Second) {
		        self.first = first
		        self.second = second
		    }

		    @Instantiated let first: First
		    @Instantiated let second: Second
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
