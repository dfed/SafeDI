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

/// A flat `mock()` parameter – a `@Forwarded` property of the mocked type, or a received dependency the mock cannot
/// build – defaults to the hand-written mock the mock's tree would build a property of its type with, when that mock
/// takes no required argument and the module generating the mock can call it.
struct SafeDIToolFlatMockParameterDefaultTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Forwarded parameters

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_defaultsForwardedProtocolToMockOnlyFake_whenFakeIsItsOnlyProvider() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.serviceProtocol,
				Self.fakeService,
				Self.screenForwarding("Service"),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    static func mock(
		        service: Service = FakeService.mock()
		    ) -> Screen {
		        return Screen(service: service)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test(.enabled(if: compileVerificationIsEnabled))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsMockOnlyFakeForForwardedProtocol_whenCallerPassesNothing() async throws {
		// `Screen.mock()` holds the fake its default builds, as a caller passing the fake by hand does.
		let fixtureFiles = [
			"Service.swift": Self.serviceProtocol,
			"FakeService.swift": Self.fakeService,
			"Screen.swift": Self.screenForwarding("Service"),
		]
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: fixtureFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		let path = try DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles))
		try expectDifferentialValuesAgree(
			feature: path,
			knownRight: path,
			probes: [DifferentialValueProbe(name: "Screen.mock()", expression: "Screen.mock()", knownRightExpression: "Screen(service: FakeService.mock())")],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_defaultsForwardedProtocolToConformersMock_whenConformersMockReturnsItsOwnType() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.serviceProtocol,
				Self.defaultService(mock: "public static func mock() -> DefaultService { DefaultService() }"),
				Self.screenForwarding("Service"),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    static func mock(
		        service: Service = DefaultService.mock()
		    ) -> Screen {
		        return Screen(service: service)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesForwardedProtocolWithoutDefault_whenConformersMockTakesRequiredArgument() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.serviceProtocol,
				"""
				public struct Client {
				    public init() {}
				}
				""",
				"""
				@Instantiable(fulfillingAdditionalTypes: [Service.self])
				public final class DefaultService: Service, Instantiable {
				    public init(client: Client) {
				        self.client = client
				    }
				    @Received let client: Client

				    public static func mock(client: Client) -> DefaultService { DefaultService(client: client) }
				}
				""",
				Self.screenForwarding("Service"),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    static func mock(
		        service: Service
		    ) -> Screen {
		        return Screen(service: service)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test(.enabled(if: compileVerificationIsEnabled))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_defaultsForwardedProtocolToConformersOwnMock_whenMockOnlyFakeAlsoFulfillsProtocol() async throws {
		// The conformer's own mock holds the slot, so the mock tree builds `Service` with it, and so does the default.
		let fixtureFiles = [
			"Service.swift": Self.serviceProtocol,
			"DefaultService.swift": Self.defaultService(mock: "public static func mock() -> DefaultService { DefaultService() }"),
			"FakeService.swift": Self.fakeService,
			"Screen.swift": Self.screenForwarding("Service"),
		]
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: fixtureFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    static func mock(
		        service: Service = DefaultService.mock()
		    ) -> Screen {
		        return Screen(service: service)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
		let path = try DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles))
		try expectDifferentialValuesAgree(
			feature: path,
			knownRight: path,
			probes: [DifferentialValueProbe(name: "Screen.mock()", expression: "Screen.mock()", knownRightExpression: "Screen(service: DefaultService.mock())")],
			filesToDelete: &filesToDelete,
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_defaultsForwardedProtocolToMockOnlyFake_whenConformerHasNoMock() async throws {
		// The fake takes the slot from a conformer without a mock of its own, so the mock tree builds `Service` with the
		// fake, and so does the default.
		let fixtureFiles = [
			"Service.swift": Self.serviceProtocol,
			"DefaultService.swift": Self.defaultService(mock: nil),
			"FakeService.swift": Self.fakeService,
			"Screen.swift": Self.screenForwarding("Service"),
		]
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [],
			swiftFileContentByFilePath: fixtureFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    static func mock(
		        service: Service = FakeService.mock()
		    ) -> Screen {
		        return Screen(service: service)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
		let path = try DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles))
		try expectDifferentialValuesAgree(
			feature: path,
			knownRight: path,
			probes: [DifferentialValueProbe(name: "Screen.mock()", expression: "Screen.mock()", knownRightExpression: "Screen(service: FakeService.mock())")],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_defaultsForwardedProtocolToExtensionMock_whenExtensionMockReturnsTheProtocol() async throws {
		// The mock returns `Service`, which the forwarded property declares, so it builds the property.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public protocol Service {}
				public struct DefaultService: Service {}
				""",
				"""
				@Instantiable(fulfillingAdditionalTypes: [Service.self])
				extension DefaultService: Instantiable {
				    public static func instantiate() -> DefaultService { DefaultService() }
				    public static func mock() -> Service { DefaultService() }
				}
				""",
				Self.screenForwarding("Service"),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    static func mock(
		        service: Service = DefaultService.mock()
		    ) -> Screen {
		        return Screen(service: service)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_defaultsForwardedExistentialToMockOnlyFake_whenPropertySpellsAny() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.serviceProtocol,
				Self.fakeService,
				Self.screenForwarding("any Service"),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    static func mock(
		        service: any Service = FakeService.mock()
		    ) -> Screen {
		        return Screen(service: service)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_defaultsForwardedNestedProtocolToNestedFake_whenBothAreNestedInOneType() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public enum Feature {
				    public protocol Service {}

				    @Instantiable(fulfillingAdditionalTypes: [Feature.Service.self], mockOnly: true)
				    public final class FakeService: Feature.Service {
				        public static func mock() -> FakeService { FakeService() }
				    }
				}
				""",
				Self.screenForwarding("Feature.Service"),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    static func mock(
		        service: Feature.Service = Feature.FakeService.mock()
		    ) -> Screen {
		        return Screen(service: service)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesForwardedTypealiasWithoutDefault_whenOnlyTheProtocolItNamesHasAFake() async throws {
		// SafeDI matches types by name, and no declaration fulfills `AnyService`, so nothing says which mock builds it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.serviceProtocol + "\npublic typealias AnyService = Service",
				Self.fakeService,
				Self.screenForwarding("AnyService"),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    static func mock(
		        service: AnyService
		    ) -> Screen {
		        return Screen(service: service)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsConstructionDefault_whenForwardedProtocolAlsoHasMockOnlyFake() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.serviceProtocol + "\npublic struct StubService: Service {\n    public init() {}\n}",
				Self.fakeService,
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(service: Service = StubService()) {
				        self.service = service
				    }
				    @Forwarded let service: Service
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Screen+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    static func mock(
		        service: Service = StubService()
		    ) -> Screen {
		        return Screen(service: service)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Screen+SafeDIMock.swift"] ?? "")")
	}

	// MARK: Tests – Received parameters

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesReceivedTypeWithForwardedPropertiesWithoutDefault_whenItsMockTakesRequiredArgument() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.consumerReceiving("Session"),
				"""
				public struct Token {
				    public init() {}
				}
				@Instantiable
				public struct Session: Instantiable {
				    public init(token: Token) { self.token = token }
				    @Forwarded let token: Token

				    public static func mock(token: Token) -> Session { Session(token: token) }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Consumer+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Consumer {
		    static func mock(
		        session: Session
		    ) -> Consumer {
		        return Consumer(session: session)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Consumer+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_defaultsInstanceOfReceivedLazilyInstantiated_whenItsTypeHasForwardedPropertiesAndArgumentlessMock() async throws {
		// A mock never takes a `LazilyInstantiated`: it takes the instance, which now defaults, and wraps it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				Self.consumerReceiving("LazilyInstantiated<Session>"),
				Self.sessionWithForwardedToken,
				Self.sessionPreview,
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Consumer+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Consumer {
		    static func mock(
		        session: Session = Session.preview()
		    ) -> Consumer {
		        let session_lazilyInstantiated = LazilyInstantiated<Session> { session }
		        return Consumer(session: session_lazilyInstantiated)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Consumer+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsOverrideForOnlyIfAvailableReceive_whenItsTypeHasForwardedPropertiesAndArgumentlessMock() async throws {
		// An `onlyIfAvailable` receive is an override that defaults to `nil`, not a flat parameter.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Consumer: Instantiable {
				    public init(session: Session?) { self.session = session }
				    @Received(onlyIfAvailable: true) let session: Session?
				}
				""",
				Self.sessionWithForwardedToken,
				Self.sessionPreview,
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Consumer+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Consumer {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            session: Session? = nil
		        ) {
		            self.session = session
		        }

		        let session: Session?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Consumer {
		        let session: Session? = safeDIOverrides.session
		        return Consumer(session: session)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Consumer+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsReceivedInstantiator_whenItsTypeHasForwardedPropertiesAndArgumentlessMock() async throws {
		// The mock builds an `Instantiator`, which is handed the forwarded values, so it is no flat parameter.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Consumer: Instantiable {
				    public init(sessionBuilder: Instantiator<Session>) { self.sessionBuilder = sessionBuilder }
				    @Received let sessionBuilder: Instantiator<Session>
				}
				""",
				Self.sessionWithForwardedToken,
				Self.sessionPreview,
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Consumer+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Consumer {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            sessionBuilder: ((Token) -> Session)? = nil
		        ) {
		            self.sessionBuilder = sessionBuilder
		        }

		        let sessionBuilder: ((Token) -> Session)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Consumer {
		        func __safeDI_sessionBuilder(token: Token) -> Session {
		            if let safeDIBuilder = safeDIOverrides.sessionBuilder { safeDIBuilder(token) } else { Session.preview(token: token) }
		        }
		        let sessionBuilder = Instantiator<Session> {
		            __safeDI_sessionBuilder(token: $0)
		        }
		        return Consumer(sessionBuilder: sessionBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Consumer+SafeDIMock.swift"] ?? "")")
	}

	// MARK: Tests – Access between modules

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_defaultsForwardedProtocolToFake_whenFakesMockIsPublicInAnotherModule(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modulesForwardingServiceFakedInTestSupport(fakeMockAccess: "public"),
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let generatedFiles = try #require(output.modules["App"]).generatedFiles
		#expect(generatedFiles == Self.appMockFiles(under: integration, imports: ["Feature", "TestSupport"], code: """
		#if DEBUG
		extension Screen {
		    static func mock(
		        service: Service = FakeService.mock()
		    ) -> Screen {
		        return Screen(service: service)
		    }
		}
		#endif
		"""), "Unexpected output \(generatedFiles)")
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_defaultsForwardedProtocolToFake_whenFakesMockIsPackageInAnotherModuleOfThePackage(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modulesForwardingServiceFakedInTestSupport(fakeMockAccess: "package"),
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let generatedFiles = try #require(output.modules["App"]).generatedFiles
		#expect(generatedFiles == Self.appMockFiles(under: integration, imports: ["Feature", "TestSupport"], code: """
		#if DEBUG
		extension Screen {
		    static func mock(
		        service: Service = FakeService.mock()
		    ) -> Screen {
		        return Screen(service: service)
		    }
		}
		#endif
		"""), "Unexpected output \(generatedFiles)")
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesForwardedProtocolWithoutDefault_whenFakesMockIsInternalToAnotherModule(integration: MultiModuleIntegration) async throws {
		// `App` cannot call the fake's mock, so it does not default to it, and nothing is reported.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modulesForwardingServiceFakedInTestSupport(fakeMockAccess: ""),
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let generatedFiles = try #require(output.modules["App"]).generatedFiles
		#expect(generatedFiles == Self.appMockFiles(under: integration, imports: ["Feature", "TestSupport"], code: """
		#if DEBUG
		extension Screen {
		    static func mock(
		        service: Service
		    ) -> Screen {
		        return Screen(service: service)
		    }
		}
		#endif
		"""), "Unexpected output \(generatedFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_assumesPackageAccessWithoutComment_whenReceivedParameterDefaultCallsHandWrittenMockOfUnknownModule() async throws {
		// `mock()` defaults `session` to `Session.preview()`, which constructs `Session` as any line of a mock's tree does:
		// SafeDI knows no name of `App`'s module, so it assumes `package` access, with no comment, as on every such line.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Models", packageName: "Shop", swiftFileContent: [
					Self.sessionWithForwardedToken,
					"""
					@Instantiable(mockOnly: true, customMockName: "preview")
					extension Session {
					    package static func preview(token: Token = Token()) -> Session { Session(token: token) }
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: ["import Models\n\n" + Self.consumerReceiving("Session")], dependencies: ["Models"]),
			],
			integration: .swiftPackagePlugin,
			writesTargetGraph: false,
			filesToDelete: &filesToDelete,
		)

		let generatedFiles = try #require(output.modules["App"]).generatedFiles
		#expect(generatedFiles == Self.appMockFiles(under: .swiftPackagePlugin, imports: ["Models"], mockedTypeName: "Consumer", code: """
		#if DEBUG
		extension Consumer {
		    static func mock(
		        session: Session = Session.preview()
		    ) -> Consumer {
		        return Consumer(session: session)
		    }
		}
		#endif
		"""), "Unexpected output \(generatedFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesForwardedTypeWithoutDefault_whenTreeCallsAnotherModulesPublicMockOfTheType() async throws {
		// `App` cannot build `Widget` and calls its public mock where its tree builds one; that mock is no hand-written
		// mock, so a forwarded `Widget` does not default to it.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "core", swiftFileContent: [
					"""
					@Instantiable(generateMock: .public)
					public final class Widget: Instantiable {
					    init() {}
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
					"""
					import Core

					@Instantiable(generateMock: true)
					final class Screen: Instantiable {
					    init(widget: Widget) {
					        self.widget = widget
					    }
					    @Forwarded let widget: Widget
					}
					""",
				], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		let generatedFiles = try #require(output.modules["App"]).generatedFiles
		#expect(generatedFiles == Self.appMockFiles(under: .moduleInfo, imports: ["Core"], code: """
		#if DEBUG
		extension Screen {
		    static func mock(
		        widget: Widget
		    ) -> Screen {
		        return Screen(widget: widget)
		    }
		}
		#endif
		"""), "Unexpected output \(generatedFiles)")
	}

	// MARK: Tests – Public mocks

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesForwardedProtocolAsOptionalParameter_whenFakeInAnotherModuleDefaultsIt(integration: MultiModuleIntegration) async throws {
		// A public mock takes a value it defaults as `T? = nil` and resolves the default in its own module.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modulesForwardingServiceFakedInTestSupport(fakeMockAccess: "public", screenIsPublicMock: true),
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		// A run without the plugin's target graph may not read every first-party module, so it says how it proves
		// `Service` `public`, as it does for any type a public mock names.
		let unreadTypeComment = switch integration {
		case .moduleInfo:
			"\n    // SafeDI counts `Service` as `public`: no module it reads declares it narrower. If `Service` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies."
		case .swiftPackagePlugin:
			""
		}
		let generatedFiles = try #require(output.modules["App"]).generatedFiles
		#expect(generatedFiles == Self.appMockFiles(under: integration, imports: ["Feature", "TestSupport"], code: """
		#if DEBUG
		extension Screen {\(unreadTypeComment)
		    public static func mock(
		        service: Service? = nil
		    ) -> Screen {
		        let service = service ?? (FakeService.mock())
		        return Screen(service: service)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_01EE4AB7CC54DCE0 {}
		}
		#endif
		"""), "Unexpected output \(generatedFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicMockForwardsPackageProtocolWhoseFakesMockIsInternalToAnotherModule() async {
		// The mock cannot call the fake's mock, so `service` stays required, and the `public` tier cannot take it.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Screen.swift"]):3:29: error: SafeDI cannot generate the public mock of `Screen`: its `public` tier, which `generateMock: .public` requires, cannot take `service: Service`, which `Screen` forwards, and cannot pass `nil` for it, since it is required. `Service` is declared `package` in module `Feature`. Declare `Service` `public` in module `Feature`; give `Service` a `mockOnly` mock; or use `generateMock: .internal`.
			\(fixtures["Feature"]!["Service.swift"]):1:1: note: `Service` is declared `package` here.
			\(fixtures["Feature"]!["Service.swift"]):1:1-1:8: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesForwardingServiceFakedInTestSupport(fakeMockAccess: "", screenIsPublicMock: true, serviceAccess: "package"),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesReceivedTypeWithForwardedPropertiesAsOptionalParameter_whenItsPublicMockInAnotherModuleDefaultsIt(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modulesReceivingSessionMockedInTestSupport(sessionAccess: "public", previewAccess: "public"),
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let generatedFiles = try #require(output.modules["App"]).generatedFiles
		#expect(generatedFiles == Self.appMockFiles(under: integration, imports: ["Models", "TestSupport"], mockedTypeName: "Consumer", code: """
		#if DEBUG
		extension Consumer {
		    public static func mock(
		        session: Session? = nil
		    ) -> Consumer {
		        let session = session ?? (Session.preview())
		        return Consumer(session: session)
		    }
		}

		extension Consumer {
		    public enum __safeDI_Consumer_mock_D4A974D59A93702C {}
		}
		#endif
		"""), "Unexpected output \(generatedFiles)")
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsPublicMockWithoutDefaultedReceivedParameter_whenCallerOfAnotherPackageProvidesNothingForIt(integration: MultiModuleIntegration) async throws {
		// A caller in another package cannot build `Consumer`, so its mock calls the public mock, passing `nil` for `session`,
		// which nothing in its tree provides, as for any dependency the called mock builds: the called mock builds it with
		// its default, as the inline mock would, and the caller's mock takes no `session` of its own.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modulesReceivingSessionMockedInTestSupport(sessionAccess: "public", previewAccess: "public") + [
				ModuleFixture(name: "Caller", packageName: "Other", swiftFileContentByFilePath: ["Screen.swift": """
				import App

				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(consumer: Consumer) { self.consumer = consumer }
				    @Received let consumer: Consumer
				}

				"""], dependencies: ["App", "Models", "TestSupport"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let generatedFiles = try #require(output.modules["Caller"]).generatedFiles
		let header = generatedFileHeader + ["App", "Models", "TestSupport"].map { "#if canImport(\($0))\nimport \($0)\n#endif" }.joined(separator: "\n") + "\n\n"
		// The plugin's flow cannot tell whether the declaring module applies the plugin, so its call says to; the module
		// info flow's call says how each integration that writes module info compiles App's generated code into App.
		let seamCallComment = switch integration {
		case .moduleInfo:
			" // If this line does not compile, compile the code SafeDI generates for module App into App: under Bazel, add App's safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes."
		case .swiftPackagePlugin:
			" // If this line does not compile, add the SafeDI plugin to the target that declares Consumer."
		}
		let code = """
		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            consumer: ((Session?) -> Consumer)? = nil
		        ) {
		            self.consumer = consumer
		        }

		        let consumer: ((Session?) -> Consumer)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        _ = Consumer.__safeDI_Consumer_mock_D4A974D59A93702C.self\(seamCallComment)
		        let consumer = if let safeDIBuilder = safeDIOverrides.consumer { safeDIBuilder(nil) } else { Consumer.mock(session: nil) }
		        return Screen(consumer: consumer)
		    }
		}
		#endif
		"""
		let expectedFiles: [String: String] = switch integration {
		case .moduleInfo:
			["Caller.swift": header + code]
		case .swiftPackagePlugin:
			["Screen+SafeDIMock.swift": header + code, "SafeDIMockConfiguration.swift": header]
		}
		#expect(generatedFiles == expectedFiles, "Unexpected output \(generatedFiles)")
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesPackageReceivedTypeOnPackageTier_whenItsPackageMockInAnotherModuleOfThePackageDefaultsIt(integration: MultiModuleIntegration) async throws {
		// The default lets the `public` tier pass `nil` for the `package` `Session`, which it cannot take.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modulesReceivingSessionMockedInTestSupport(sessionAccess: "package", previewAccess: "package"),
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let generatedFiles = try #require(output.modules["App"]).generatedFiles
		#expect(generatedFiles == Self.appMockFiles(under: integration, imports: ["Models", "TestSupport"], mockedTypeName: "Consumer", code: """
		#if DEBUG
		extension Consumer {
		    public static func mock() -> Consumer {
		        Consumer.mock(session: nil)
		    }

		    package static func mock(
		        session: Session? = nil
		    ) -> Consumer {
		        let session = session ?? (Session.preview())
		        return Consumer(session: session)
		    }
		}

		extension Consumer {
		    public enum __safeDI_Consumer_mock_E091DB4BE7BC7703 {}
		}
		#endif
		"""), "Unexpected output \(generatedFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenPublicMockReceivesPackageTypeWhoseMockIsInternalToAnotherModule() async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Consumer.swift"]):3:29: error: SafeDI cannot generate the public mock of `Consumer`: its `public` tier, which `generateMock: .public` requires, cannot take `session: Session`, which the initializer of `Consumer` receives, and cannot pass `nil` for it, since it is required. `Session`'s own `@Instantiable` declaration is `package`. Declare `Session` `public`; receive it with `onlyIfAvailable: true` and an optional type; or use `generateMock: .internal`.
			\(fixtures["App"]!["Consumer.swift"]):6:5: note: `Consumer` receives `session: Session` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modulesReceivingSessionMockedInTestSupport(sessionAccess: "package", previewAccess: ""),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Tests – Query

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func query_reportsForwardedProtocolAsDefaulted_whenMockOnlyFakeDefaultsIt() async throws {
		let output = try await executeSafeDIToolQuery(
			typeName: "Screen",
			modules: [
				QueryTestModule("FeatureModule", [Self.serviceProtocol, Self.screenForwarding("Service")]),
				QueryTestModule("TestSupport", [Self.fakeService]),
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.result.forwardedParameters == [
			TypeReport.ForwardedParameter(label: "service", type: "Service", defaultExpression: nil),
		])
		#expect(output.result.mock?.forwardedParameters == [
			TypeReport.ForwardedParameter(label: "service", type: "Service", defaultExpression: "FakeService.mock()"),
		])
		#expect(output.result.mock?.modules == [
			output.module("FeatureModule", [
				output.instantiable("Screen", in: "FeatureModule", file: 1),
			]),
			output.module("TestSupport", [
				output.handWrittenMock("FakeService", "mock", in: "TestSupport"),
			]),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func query_reportsForwardedProtocolAsRequired_whenFakesMockIsInternalToAnotherModule() async throws {
		// `FeatureModule` generates the mock and cannot call the fake's `internal` mock, so, as `generate` emits it, the
		// mock takes `service` without a default and calls nothing `TestSupport` declares.
		let output = try await executeSafeDIToolQuery(
			typeName: "Screen",
			modules: [
				QueryTestModule("FeatureModule", [Self.serviceProtocol, Self.screenForwarding("Service")]),
				QueryTestModule("TestSupport", [Self.fakeService(mockModifier: "")]),
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.result.mock?.generatedIn == ["FeatureModule"])
		#expect(output.result.mock?.forwardedParameters == [
			TypeReport.ForwardedParameter(label: "service", type: "Service", defaultExpression: nil),
		])
		#expect(output.result.mock?.modules == [
			output.module("FeatureModule", [
				output.instantiable("Screen", in: "FeatureModule", file: 1),
			]),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func query_reportsForwardedProtocolAsDefaulted_whenInternalFakeIsInModuleThatListsTheType() async throws {
		// `AppModule` generates the mock, because its configuration lists `Screen`, and declares the fake, so it can call
		// the fake's `internal` mock.
		let output = try await executeSafeDIToolQuery(
			typeName: "Screen",
			modules: [
				QueryTestModule("AppModule", [Self.fakeService(mockModifier: "")], swiftFileContentByFilePath: [
					"SafeDIConfiguration.swift": #"#SafeDIConfiguration(additionalMocksToGenerate: ["Screen"])"#,
				]),
				QueryTestModule("FeatureModule", [Self.serviceProtocol, Self.screenForwarding("Service", generateMock: false)]),
			],
			filesToDelete: &filesToDelete,
		)

		#expect(output.result.mock?.generatedIn == ["AppModule"])
		#expect(output.result.mock?.forwardedParameters == [
			TypeReport.ForwardedParameter(label: "service", type: "Service", defaultExpression: "FakeService.mock()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func query_reportsReceivedTypeWithForwardedPropertiesAsDefaulted_whenItsHandWrittenMockDefaultsIt() async throws {
		let output = try await executeSafeDIToolQuery(
			typeName: "Consumer",
			modules: [
				QueryTestModule("FeatureModule", [Self.consumerReceiving("Session")]),
				QueryTestModule("Models", [Self.sessionWithForwardedToken]),
				QueryTestModule("TestSupport", [Self.sessionPreview]),
			],
			filesToDelete: &filesToDelete,
		)

		// Production has no hand-written mock to default to; the mock defaults `session` to the one `TestSupport` declares.
		let featureModule = try #require(output.moduleDirectories["FeatureModule"]?.path)
		let testSupport = try #require(output.moduleDirectories["TestSupport"]?.path)
		let reason = "`Session` declares @Forwarded properties (`token: Token`), so only an `Instantiator` handed their values can build it."
		#expect(output.json == """
		{
		  "formatVersion" : 0,
		  "types" : [
		    {
		      "forwardedParameters" : [

		      ],
		      "mock" : {
		        "forwardedParameters" : [

		        ],
		        "generatedIn" : [
		          "FeatureModule"
		        ],
		        "kind" : "generated",
		        "methodName" : "mock",
		        "modules" : [
		          {
		            "declarations" : [
		              {
		                "filePath" : "\(featureModule)/Consumer.swift",
		                "kind" : "instantiable",
		                "typeName" : "Consumer"
		              }
		            ],
		            "name" : "FeatureModule",
		            "paths" : [
		              "\(featureModule)"
		            ]
		          },
		          {
		            "declarations" : [
		              {
		                "filePath" : "\(testSupport)/File.swift",
		                "kind" : "handWrittenMock",
		                "methodName" : "preview",
		                "typeName" : "Session"
		              }
		            ],
		            "name" : "TestSupport",
		            "paths" : [
		              "\(testSupport)"
		            ]
		          }
		        ],
		        "unfulfilledDependencies" : [
		          {
		            "defaultExpression" : "Session.preview()",
		            "label" : "session",
		            "reason" : "\(reason)",
		            "reasonKind" : "typeHasForwardedProperties",
		            "type" : "Session"
		          }
		        ]
		      },
		      "modules" : [
		        {
		          "declarations" : [
		            {
		              "filePath" : "\(featureModule)/Consumer.swift",
		              "kind" : "instantiable",
		              "typeName" : "Consumer"
		            }
		          ],
		          "name" : "FeatureModule",
		          "paths" : [
		            "\(featureModule)"
		          ]
		        }
		      ],
		      "typeName" : "Consumer",
		      "unfulfilledDependencies" : [
		        {
		          "label" : "session",
		          "reason" : "\(reason)",
		          "reasonKind" : "typeHasForwardedProperties",
		          "type" : "Session"
		        }
		      ]
		    }
		  ]
		}
		""", "Unexpected output \(output.json)")
		#expect(output.formatted.hasSuffix("""
		Required parameters of `Consumer.mock()` that no @Instantiable declaration removes:
		  (none)

		Defaulted parameters of `Consumer.mock()` that no @Instantiable declaration removes:
		  session: Session = Session.preview()
		    `Session` declares @Forwarded properties (`token: Token`), so only an `Instantiator` handed their values can build it.
		"""), "Unexpected output \(output.formatted)")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let serviceProtocol = "public protocol Service {}"

	/// A `mockOnly` fake that fulfills `Service`, whose mock takes nothing.
	private static let fakeService = fakeService(mockModifier: "public ")

	/// A `mockOnly` fake that fulfills `Service`, whose mock takes nothing and spells `mockModifier` (an empty string
	/// for `internal`).
	private static func fakeService(mockModifier: String) -> String {
		"""
		@Instantiable(fulfillingAdditionalTypes: [Service.self], mockOnly: true)
		public final class FakeService: Service {
		    \(mockModifier)static func mock() -> FakeService { FakeService() }
		}
		"""
	}

	/// A production conformer of `Service`, with `mock` in its body when given one.
	private static func defaultService(mock: String?) -> String {
		"""
		@Instantiable(fulfillingAdditionalTypes: [Service.self])
		public final class DefaultService: Service, Instantiable {
		    public init() {}
		\(mock.map { "\n    \($0)\n" } ?? "")}
		"""
	}

	/// A type that forwards `service` of `type` and stores it, with a generated mock unless `generateMock` is `false`.
	private static func screenForwarding(_ type: String, generateMock: Bool = true) -> String {
		"""
		@Instantiable\(generateMock ? "(generateMock: true)" : "")
		public final class Screen: Instantiable {
		    public init(service: \(type)) {
		        self.service = service
		    }
		    @Forwarded let service: \(type)
		}
		"""
	}

	/// A type with a generated mock that receives `session` of `type`.
	private static func consumerReceiving(_ type: String) -> String {
		"""
		@Instantiable(generateMock: true)
		public struct Consumer: Instantiable {
		    public init(session: \(type)) { self.session = session }
		    @Received let session: \(type)
		}
		"""
	}

	/// A `Session` that only an `Instantiator` handed its forwarded `token` can build.
	private static let sessionWithForwardedToken = """
	public struct Token {
	    public init() {}
	}
	@Instantiable
	public struct Session: Instantiable {
	    public init(token: Token) { self.token = token }
	    @Forwarded let token: Token
	}
	"""

	/// A `mockOnly` extension giving `Session` a mock, `preview`, that takes nothing.
	private static let sessionPreview = """
	@Instantiable(mockOnly: true, customMockName: "preview")
	extension Session {
	    public static func preview(token: Token = Token()) -> Session { Session(token: token) }
	}
	"""

	/// `Feature` declaring `Service` of `serviceAccess`, `TestSupport` declaring its fake with a mock of `fakeMockAccess`
	/// (an empty string for `internal`), and `App` declaring `Screen`, which forwards `Service`: every module in
	/// package `Shop`.
	private static func modulesForwardingServiceFakedInTestSupport(fakeMockAccess: String, screenIsPublicMock: Bool = false, serviceAccess: String = "public") -> [ModuleFixture] {
		let fakeMockModifier = fakeMockAccess.isEmpty ? "" : "\(fakeMockAccess) "
		return [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Service.swift": "\(serviceAccess) protocol Service {}\n"]),
			ModuleFixture(name: "TestSupport", packageName: "Shop", swiftFileContentByFilePath: ["FakeService.swift": """
			import Feature

			@Instantiable(fulfillingAdditionalTypes: [Service.self], mockOnly: true)
			public final class FakeService: Service {
			    \(fakeMockModifier)static func mock() -> FakeService { FakeService() }
			}

			"""], dependencies: ["Feature"]),
			ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Screen.swift": """
			import Feature
			import TestSupport
			@Instantiable(generateMock: \(screenIsPublicMock ? ".public" : "true"))
			public final class Screen: Instantiable {
			    \(screenIsPublicMock ? "package" : "public") init(service: Service) {
			        self.service = service
			    }
			    @Forwarded let service: Service
			}

			"""], dependencies: ["Feature", "TestSupport"]),
		]
	}

	/// `Models` declaring `Session` of `sessionAccess`, `TestSupport` declaring its mock, `preview`, of
	/// `previewAccess` (an empty string for `internal`), and `App` declaring `Consumer`, whose public mock receives
	/// `Session`: every module in package `Shop`.
	private static func modulesReceivingSessionMockedInTestSupport(sessionAccess: String, previewAccess: String) -> [ModuleFixture] {
		let previewModifier = previewAccess.isEmpty ? "" : "\(previewAccess) "
		return [
			ModuleFixture(name: "Models", packageName: "Shop", swiftFileContentByFilePath: ["Session.swift": """
			public struct Token {
			    public init() {}
			}
			@Instantiable
			\(sessionAccess) struct Session: Instantiable {
			    \(sessionAccess) init(token: Token) { self.token = token }
			    @Forwarded let token: Token
			}

			"""]),
			ModuleFixture(name: "TestSupport", packageName: "Shop", swiftFileContentByFilePath: ["SessionPreview.swift": """
			import Models

			@Instantiable(mockOnly: true, customMockName: "preview")
			extension Session {
			    \(previewModifier)static func preview(token: Token = Token()) -> Session { Session(token: token) }
			}

			"""], dependencies: ["Models"]),
			ModuleFixture(name: "App", packageName: "Shop", swiftFileContentByFilePath: ["Consumer.swift": """
			import Models
			import TestSupport
			@Instantiable(generateMock: .public)
			public struct Consumer: Instantiable {
			    package init(session: Session) { self.session = session }
			    @Received let session: Session
			}

			"""], dependencies: ["Models", "TestSupport"]),
		]
	}

	/// The files `App` generates under `integration` when it imports `imports` and generates `code` for the mock of
	/// `mockedTypeName`.
	private static func appMockFiles(under integration: MultiModuleIntegration, imports: [String], mockedTypeName: String = "Screen", code: String) -> [String: String] {
		let header = generatedFileHeader + imports.map { "#if canImport(\($0))\nimport \($0)\n#endif" }.joined(separator: "\n") + "\n\n"
		return switch integration {
		case .moduleInfo:
			["App.swift": header + code]
		case .swiftPackagePlugin:
			["\(mockedTypeName)+SafeDIMock.swift": header + code, "SafeDIMockConfiguration.swift": header]
		}
	}
}
