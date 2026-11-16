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

/// A generated `mock()` takes the global actor that the member it builds the type with spells – the hand-written mock it
/// calls through to (the method `customMockName` names), or, for a type without one, its `init` or `instantiate()` –
/// unless `mockAttributes` spells one or the type's own declaration already binds `mock()` to it, since a synchronous
/// `mock()` can call a method isolated to a global actor only from that actor.
struct SafeDIToolMockConstructionIsolationTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Internal mocks

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_isIsolatedToGlobalActorOfHandWrittenMock_whenExtensionBasedTypeSpellsNoIsolation() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol Clock: Sendable {}
				public final class SystemClock: Clock, Sendable {
				    public init() {}
				}
				""",
				"""
				@Instantiable(fulfillingAdditionalTypes: [Clock.self], generateMock: true, customMockName: "customMock")
				extension SystemClock: Instantiable {
				    public static func instantiate() -> SystemClock {
				        SystemClock()
				    }

				    @MainActor public static func customMock(zone: String = "UTC") -> Clock {
				        SystemClock()
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"File+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension SystemClock {
			    @MainActor static func mock(
			        zone: String = "UTC"
			    ) -> Clock {
			        return SystemClock.customMock(zone: zone)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_isIsolatedToGlobalActorOfHandWrittenMock_whenTypeDeclarationSpellsNoIsolation() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public final class Service: Instantiable {
				    public init() {}

				    @MainActor public static func customMock() -> Service {
				        Service()
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    @MainActor static func mock() -> Service {
			        Service.customMock()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_staysNonisolated_whenOnlyInstantiateSpellsGlobalActor() async throws {
		// `mock()` calls `customMock()`, which spells no isolation, so the `@MainActor` of `instantiate()`, which only
		// production calls, does not reach it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public final class SystemClock: Sendable {
				    public init() {}
				}
				""",
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				extension SystemClock: Instantiable {
				    @MainActor public static func instantiate() -> SystemClock {
				        SystemClock()
				    }

				    public static func customMock() -> SystemClock {
				        SystemClock()
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"File+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension SystemClock {
			    static func mock() -> SystemClock {
			        SystemClock.customMock()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsMockAttributesAlone_whenMockAttributesSpellGlobalActor() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(mockAttributes: "@MainActor", generateMock: true, customMockName: "customMock")
				public final class Service: Instantiable {
				    public init() {}

				    @MainActor public static func customMock() -> Service {
				        Service()
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    @MainActor static func mock() -> Service {
			        Service.customMock()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsGlobalActorOfHandWrittenMockAfterMockAttributes_whenMockAttributesSpellNoGlobalActor() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(mockAttributes: "@discardableResult", generateMock: true, customMockName: "customMock")
				public final class Service: Instantiable {
				    public init() {}

				    @MainActor public static func customMock() -> Service {
				        Service()
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    @discardableResult @MainActor static func mock() -> Service {
			        Service.customMock()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsNoGlobalActor_whenTypeDeclarationSpellsHandWrittenMocksGlobalActor() async throws {
		// `mock()` is declared in an extension of `Service`, so it is on the main actor already.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				@Instantiable(generateMock: true, customMockName: "customMock")
				public final class Service: Instantiable {
				    public init() {}

				    @MainActor public static func customMock() -> Service {
				        Service()
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    static func mock() -> Service {
			        Service.customMock()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsTypesGlobalActor_whenHandWrittenMockIsNonisolated() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				@Instantiable(generateMock: true, customMockName: "customMock")
				public final class Service: Instantiable {
				    nonisolated public init() {}

				    nonisolated public static func customMock() -> Service {
				        Service()
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    static func mock() -> Service {
			        Service.customMock()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_isIsolatedToGlobalActorOfHandWrittenMock_whenTypeDeclarationSpellsAnotherGlobalActor() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@globalActor
				public actor PreviewActor {
				    public static let shared = PreviewActor()
				}

				@MainActor
				@Instantiable(generateMock: true, customMockName: "customMock")
				public final class Service: Instantiable {
				    nonisolated public init() {}

				    @PreviewActor public static func customMock() -> Service {
				        Service()
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    @PreviewActor static func mock() -> Service {
			        Service.customMock()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_isIsolatedToGlobalActorOfMockOnlyDeclarationsMock_whenProductionDeclarationGeneratesMock() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Service: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable(mockOnly: true, customMockName: "preview")
				extension Service {
				    @MainActor public static func preview() -> Service {
				        Service()
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    @MainActor static func mock() -> Service {
			        Service.preview()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_isIsolatedToGlobalActorOfHandWrittenMock_whenMockBuildsTree() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public final class Service: Instantiable {
				    public init(child: Child) {
				        self.child = child
				    }

				    @Instantiated let child: Child

				    @MainActor public static func customMock(child: Child, name: String? = nil) -> Service {
				        Service(child: child)
				    }
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            child: (() -> Child)? = nil
			        ) {
			            self.child = child
			        }

			        let child: (() -> Child)?
			    }

			    @MainActor static func mock(
			        name: String? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let child = if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder() } else { Child() }
			        return Service.customMock(child: child, name: name)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_compiles_whenParentsMockAttributesSpellGlobalActorOfChildsHandWrittenMock() async throws {
		// `Parent`'s mock builds `Service` with `customMock()`, which is on the main actor, so `Parent` opts its `mock()`
		// in through `mockAttributes`, as for a type whose tree builds a `@MainActor` initializer: SafeDI binds no mock to
		// the actor of a type its tree builds.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(mockAttributes: "@MainActor", generateMock: true)
				public final class Parent: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				""",
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public final class Service: Instantiable {
				    public init() {}

				    @MainActor public static func customMock() -> Service {
				        Service()
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Parent+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Parent {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: (() -> Service)? = nil
			        ) {
			            self.service = service
			        }

			        let service: (() -> Service)?
			    }

			    @MainActor static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Parent {
			        let service = if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { Service.customMock() }
			        return Parent(service: service)
			    }
			}
			#endif
			""",
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    @MainActor static func mock() -> Service {
			        Service.customMock()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	// MARK: Tests – Initializers

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_isIsolatedToGlobalActorOfInitializer_whenTypeHasNoHandWrittenMock() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Service: Instantiable {
				    @MainActor public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    @MainActor static func mock() -> Service {
			        Service()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_isIsolatedToGlobalActorOfInstantiate_whenExtensionBasedTypeHasNoHandWrittenMock() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public final class SystemClock: Sendable {
				    public init() {}
				}
				""",
				"""
				@Instantiable(generateMock: true)
				extension SystemClock: Instantiable {
				    @MainActor public static func instantiate() -> SystemClock {
				        SystemClock()
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"File+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension SystemClock {
			    @MainActor static func mock() -> SystemClock {
			        SystemClock.instantiate()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_isIsolatedToGlobalActorOfInitializer_whenMockBuildsTree() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Service: Instantiable {
				    @MainActor public init(child: Child, name: String? = nil) {
				        self.child = child
				    }

				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            child: (() -> Child)? = nil
			        ) {
			            self.child = child
			        }

			        let child: (() -> Child)?
			    }

			    @MainActor static func mock(
			        name: String? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let child = if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder() } else { Child() }
			        return Service(child: child, name: name)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsMockAttributesAlone_whenMockAttributesSpellInitializersGlobalActor() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(mockAttributes: "@MainActor", generateMock: true)
				public final class Service: Instantiable {
				    @MainActor public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    @MainActor static func mock() -> Service {
			        Service()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsNoGlobalActor_whenTypeDeclarationSpellsInitializersGlobalActor() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				@Instantiable(generateMock: true)
				public final class Service: Instantiable {
				    @MainActor public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    static func mock() -> Service {
			        Service()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsTypesGlobalActor_whenInitializerIsNonisolated() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				@Instantiable(generateMock: true)
				public final class Service: Instantiable {
				    nonisolated public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    static func mock() -> Service {
			        Service()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_isIsolatedToGlobalActorOfInitializer_whenTypeDeclarationSpellsAnotherGlobalActor() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@globalActor
				public actor PreviewActor {
				    public static let shared = PreviewActor()
				}

				@MainActor
				@Instantiable(generateMock: true)
				public final class Service: Instantiable {
				    @PreviewActor public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    @PreviewActor static func mock() -> Service {
			        Service()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_isolatesPublicMockAndProviderOfOwnOptionalDefault_toGlobalActorOfInitializer() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				enum Defaults {
				    static var name: String? = "name"
				}

				@Instantiable(generateMock: .public)
				public final class NoTree: Instantiable {
				    @MainActor init(name: String? = Defaults.name) {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"NoTree+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension NoTree {
			    @usableFromInline @MainActor static func __safeDI_publicMockDefault_name() -> String? { Defaults.name }

			    @MainActor public static func mock(
			        name: String? = NoTree.__safeDI_publicMockDefault_name()
			    ) -> NoTree {
			        return NoTree(name: name)
			    }
			}

			extension NoTree {
			    public enum __safeDI_NoTree_mock_9B791E5044AD415C {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	// MARK: Tests – `@preconcurrency` and extensions

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsPreconcurrencyBesideGlobalActorOfInitializer_whenInitializerIsPreconcurrency() async throws {
		// `mock()` keeps the `@preconcurrency` of the initializer it calls, so code on no actor can still call it, as it can
		// call the initializer, and `mock()` calls the initializer without the warning a nonisolated caller gets.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Service: Instantiable {
				    @preconcurrency @MainActor public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    @preconcurrency @MainActor static func mock() -> Service {
			        Service()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsPreconcurrencyBesideGlobalActorOfHandWrittenMock_whenHandWrittenMockIsPreconcurrency() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public final class Service: Instantiable {
				    public init() {}

				    @preconcurrency @MainActor public static func customMock() -> Service {
				        Service()
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    @preconcurrency @MainActor static func mock() -> Service {
			        Service.customMock()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_isIsolatedToGlobalActorOfExtension_whenInstantiateSpellsNoIsolation() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public final class SystemClock: Sendable {
				    public init() {}
				}
				""",
				"""
				@Instantiable(generateMock: true)
				@MainActor extension SystemClock: Instantiable {
				    public static func instantiate() -> SystemClock {
				        SystemClock()
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"File+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension SystemClock {
			    @MainActor static func mock() -> SystemClock {
			        SystemClock.instantiate()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_isIsolatedToGlobalActorOfMockOnlyExtension_whenHandWrittenMockSpellsNoIsolation() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Service: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable(mockOnly: true, customMockName: "preview")
				@MainActor extension Service {
				    public static func preview() -> Service {
				        Service()
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Service {
			    @MainActor static func mock() -> Service {
			        Service.preview()
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	// MARK: Tests – Generated initializers

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func rootInit_isIsolatedToGlobalActorOfOwnInitializer_whenRootSpellsNoIsolation() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    @MainActor public init(child: Child) {
				        self.child = child
				    }

				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    @MainActor public convenience init() {
			        let child = Child()
			        self.init(child: child)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func rootInit_spellsGeneratedInitializerAttributesAlone_whenTheyNameOwnInitializersGlobalActor() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generatedInitializerAttributes: "@MainActor")
				public final class Root: Instantiable {
				    @MainActor public init(child: Child) {
				        self.child = child
				    }

				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    @MainActor public convenience init() {
			        let child = Child()
			        self.init(child: child)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func seamInitializers_areIsolatedToGlobalActorOfOwnInitializer_whenSeamSpellsNoIsolation() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateDependencyTree: true)
				public final class Feature: Instantiable {
				    @MainActor public init(child: Child) {
				        self.child = child
				    }

				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.dependencyTreeFiles == [
			"Feature+SafeDI.swift": generatedFileHeader + """
			extension Feature {
			    /// Code you write and code SafeDI generates can both call this initializer.
			    @MainActor public convenience init() {
			        let child = Child()
			        self.init(child: child)
			    }
			}

			extension Feature {
			    public enum __safeDI_Feature_CBF29CE484222325 {}
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_constructionFunctionSpellsPreconcurrencyBesideGlobalActor_whenConfiguredTypesInitializerIsPreconcurrency() async throws {
		// A public mock's construction function mirrors the isolation of the initializer it calls, its `@preconcurrency`
		// included. `Parent`'s mock builds `Service` in its own body, so it opts in through `mockAttributes`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(mockAttributes: "@MainActor", generateMock: .public)
				public final class Parent: Instantiable {
				    public init(service: Service) {
				        self.service = service
				    }

				    @Instantiated let service: Service
				}
				""",
				"""
				@Instantiable
				public final class Service: Instantiable {
				    @preconcurrency @MainActor public init(retries: Int = 3) {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Parent+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Parent {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            service: __safeDI_Service_MockConfiguration = .init()
			        ) {
			            self.service = service
			        }

			        public let service: __safeDI_Service_MockConfiguration
			    }

			    @MainActor public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Parent {
			        func __safeDI_service() -> Service {
			            return Service.__safeDI_init(retries: safeDIOverrides.service.retries, safeDIBuilder: safeDIOverrides.service.safeDIBuilder)
			        }
			        let service: Service = __safeDI_service()
			        return Parent(service: service)
			    }
			}

			extension Parent {
			    public enum __safeDI_Parent_mock_51799E6AA5E7B634 {}
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			/// Configuration for how `Service` is constructed within the public mock trees of this module.
			nonisolated public struct __safeDI_Service_MockConfiguration {
			    public init(
			        retries: Int? = nil,
			        _ safeDIBuilder: ((Int) -> Service)? = nil
			    ) {
			        self.retries = retries
			        self.safeDIBuilder = safeDIBuilder
			    }

			    /// `nil` keeps the default of `Service`’s `retries`.
			    public let retries: Int?
			    /// Overrides how `Service` is constructed. Parameters match the type’s initializer or custom mock method.
			    public let safeDIBuilder: ((Int) -> Service)?
			}

			extension Service {
			    @preconcurrency @MainActor static func __safeDI_init(retries: Int?, safeDIBuilder: ((Int) -> Service)?) -> Service {
			        let retries = retries ?? (3)
			        return if let safeDIBuilder { safeDIBuilder(retries) } else { Service(retries: retries) }
			    }
			}
			#endif

			""",
		])
	}

	// MARK: Tests – Public mocks

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_isolatesPublicMockAndProviderOfOwnOptionalDefault_toGlobalActorOfHandWrittenMock() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@MainActor
				public enum Defaults {
				    public static var name: String? = "name"
				}
				""",
				"""
				@Instantiable(generateMock: .public, customMockName: "customMock")
				public final class Service: Instantiable {
				    public init(child: Child) {
				        self.child = child
				    }

				    @Instantiated let child: Child

				    @MainActor public static func customMock(child: Child, name: String? = Defaults.name) -> Service {
				        Service(child: child)
				    }
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Service+SafeDIMock.swift": Self.serviceMockFile(construction: "Service.customMock(child: child, name: name)"),
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_publicMockOfTypeWithGlobalActorHandWrittenMockCompilesForCallerInAnotherModule(integration: MultiModuleIntegration) async throws {
		// `Child`'s initializer is internal, so `Screen`'s mock in another module cannot build `Service` inline and calls
		// `Service`'s public mock, whose signature it computes as `Core` does: the provider of `name`'s default is on the
		// main actor, so `name` is a parameter of `mock()`, not a field of `SafeDIOverrides`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Core",
					packageName: "core",
					swiftFileContentByFilePath: ["Service.swift": """
					@MainActor
					public enum Defaults {
					    public static var name: String? = "name"
					}

					@Instantiable(generateMock: .public, customMockName: "customMock")
					public final class Service: Instantiable {
					    public init(child: Child) {
					        self.child = child
					    }

					    @Instantiated let child: Child

					    @MainActor public static func customMock(child: Child, name: String? = Defaults.name) -> Service {
					        Service(child: child)
					    }
					}

					@Instantiable
					public final class Child: Instantiable {
					    init() {}
					}
					"""],
				),
				ModuleFixture(
					name: "App",
					packageName: "app",
					swiftFileContentByFilePath: ["Screen.swift": """
					import Core

					@Instantiable(mockAttributes: "@MainActor", generateMock: true)
					public final class Screen: Instantiable {
					    public init(service: Service) {
					        self.service = service
					    }

					    @Instantiated let service: Service
					}
					"""],
					dependencies: ["Core"],
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["Core"]?.generatedFiles == Self.serviceFiles(integration: integration, construction: "Service.customMock(child: child, name: name)"))
		#expect(output.modules["App"]?.generatedFiles == Self.screenFiles(integration: integration))
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_publicMockOfTypeWithGlobalActorInitializerCompilesForCallerInAnotherModule(integration: MultiModuleIntegration) async throws {
		// `Child`'s initializer is internal, so `Screen`'s mock in another module calls `Service`'s public mock, whose
		// signature it computes as `Core` does from `Service`'s `@MainActor` initializer: the provider of `name`'s default
		// is on the main actor, so `name` is a parameter of `mock()`, not a field of `SafeDIOverrides`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Core",
					packageName: "core",
					swiftFileContentByFilePath: ["Service.swift": """
					@MainActor
					public enum Defaults {
					    public static var name: String? = "name"
					}

					@Instantiable(generateMock: .public)
					public final class Service: Instantiable {
					    @MainActor public init(child: Child, name: String? = Defaults.name) {
					        self.child = child
					    }

					    @Instantiated let child: Child
					}

					@Instantiable
					public final class Child: Instantiable {
					    init() {}
					}
					"""],
				),
				ModuleFixture(
					name: "App",
					packageName: "app",
					swiftFileContentByFilePath: ["Screen.swift": """
					import Core

					@Instantiable(mockAttributes: "@MainActor", generateMock: true)
					public final class Screen: Instantiable {
					    public init(service: Service) {
					        self.service = service
					    }

					    @Instantiated let service: Service
					}
					"""],
					dependencies: ["Core"],
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		#expect(output.modules["Core"]?.generatedFiles == Self.serviceFiles(integration: integration, construction: "Service(child: child, name: name)"))
		#expect(output.modules["App"]?.generatedFiles == Self.screenFiles(integration: integration))
	}

	// MARK: Private

	/// The public mock of `Service`, whose `construction` is on the main actor, as its module generates it.
	private static func serviceMockFile(construction: String) -> String {
		generatedFileHeader + """
		#if DEBUG
		extension Service {
		    @usableFromInline @MainActor static func __safeDI_publicMockDefault_name() -> String? { Defaults.name }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            child: (() -> Child)? = nil
		        ) {
		            self.child = child
		        }

		        public let child: (() -> Child)?
		    }

		    @MainActor public static func mock(
		        name: String? = Service.__safeDI_publicMockDefault_name(),
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Service {
		        let child = if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder() } else { Child() }
		        return \(construction)
		    }
		}

		extension Service {
		    public enum __safeDI_Service_mock_ECE674C8C1745A31 {}
		}
		#endif
		"""
	}

	private static func serviceFiles(integration: MultiModuleIntegration, construction: String) -> [String: String] {
		switch integration {
		case .moduleInfo:
			["Core.swift": serviceMockFile(construction: construction)]
		case .swiftPackagePlugin:
			["Service+SafeDIMock.swift": serviceMockFile(construction: construction), "SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput]
		}
	}

	private static func screenFiles(integration: MultiModuleIntegration) -> [String: String] {
		switch integration {
		case .moduleInfo:
			[
				"App.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif

				#if DEBUG
				extension Screen {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            service: Service.SafeDIOverrides = .init()
				        ) {
				            self.service = service
				        }

				        let service: Service.SafeDIOverrides
				    }

				    @MainActor static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        _ = Service.__safeDI_Service_mock_ECE674C8C1745A31.self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
				        let service = Service.mock(safeDIOverrides: safeDIOverrides.service)
				        return Screen(service: service)
				    }
				}
				#endif
				""",
			]
		case .swiftPackagePlugin:
			[
				"Screen+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif

				#if DEBUG
				extension Screen {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            service: Service.SafeDIOverrides = .init()
				        ) {
				            self.service = service
				        }

				        let service: Service.SafeDIOverrides
				    }

				    @MainActor static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Screen {
				        _ = Service.__safeDI_Service_mock_ECE674C8C1745A31.self // If this line does not compile, add the SafeDI plugin to the target that declares Service.
				        let service = Service.mock(safeDIOverrides: safeDIOverrides.service)
				        return Screen(service: service)
				    }
				}
				#endif
				""",
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(Core)
				import Core
				#endif


				""",
			]
		}
	}

	private var filesToDelete: [URL]
}
