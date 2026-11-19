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

/// Generated code reaches another module's public mock only through the function only generated code calls,
/// `__safeDI_mock`, which every tier of every public mock declares beside its `mock()`, never through the `mock()` people
/// call, so that function's forms can change in any release while `mock()` stays as people call it.
struct SafeDIToolPublicMockGeneratedOnlyCallTests: ~Copyable {
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
	mutating func mock_callsGeneratedOnlyMockOfAnotherModule_whenCalledMockTakesNoBuilders() async throws {
		// `App` cannot call `Screen`'s internal initializer, so `Root`'s mock calls `Screen`'s public mock, which takes no
		// builder: through `__safeDI_mock`, handing it the wrapper `Root` holds. `Screen`'s `mock()` calls the same function.
		let modules = [
			ModuleFixture(name: "Feed", packageName: "feedpkg", swiftFileContentByFilePath: [
				"Screen.swift": """
				import SafeDI

				@Instantiable
				public final class Session: Instantiable {
				    public init() {}
				}

				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    init(detailBuilder: Instantiator<Detail>) {
				        self.detailBuilder = detailBuilder
				    }

				    @Instantiated public let detailBuilder: Instantiator<Detail>
				}

				@Instantiable
				public final class Detail: Instantiable {
				    init(session: LazilyInstantiated<Session>) {
				        self.session = session
				    }

				    @Received public let session: LazilyInstantiated<Session>
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "apppkg", swiftFileContentByFilePath: [
				"Root.swift": """
				import Feed
				import SafeDI

				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(session: LazilyInstantiated<Session>, screen: Screen) {
				        self.session = session
				        self.screen = screen
				    }

				    @Instantiated let session: LazilyInstantiated<Session>
				    @Instantiated let screen: Screen
				}
				""",
			], dependencies: ["Feed"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feed"]?.generatedFiles == [
			"Feed.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            session: (() -> Session)? = nil,
			            detailBuilder: ((LazilyInstantiated<Session>) -> Detail)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                detailBuilder: detailBuilder
			            )
			        }

			        public var session: (() -> Session)? { __safeDI_storage.session }
			        public var detailBuilder: ((LazilyInstantiated<Session>) -> Detail)? { __safeDI_storage.detailBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?,
			                detailBuilder: ((LazilyInstantiated<Session>) -> Detail)?
			            ) {
			                self.session = session
			                self.detailBuilder = detailBuilder
			            }

			            let session: (() -> Session)?
			            let detailBuilder: ((LazilyInstantiated<Session>) -> Detail)?
			        }
			    }

			    public static func mock(
			        session: LazilyInstantiated<Session>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.__safeDI_mock(session: session, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        session: LazilyInstantiated<Session>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_session() -> Session {
			            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
			        }
			        let session = if let session { session } else { LazilyInstantiated<Session>(__safeDI_session) }
			        func __safeDI_detailBuilder() -> Detail {
			            if let safeDIBuilder = safeDIOverrides.detailBuilder { safeDIBuilder(session) } else { Detail(session: session) }
			        }
			        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			        return Screen(detailBuilder: detailBuilder)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_5183E61012439F1A {}
			}
			#endif
			""",
		])
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feed)
			import Feed
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            session: (() -> Session)? = nil,
			            screen: Screen.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screen: screen
			            )
			        }

			        var session: (() -> Session)? { __safeDI_storage.session }
			        var screen: Screen.SafeDIOverrides { __safeDI_storage.screen }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?,
			                screen: Screen.SafeDIOverrides
			            ) {
			                self.session = session
			                self.screen = screen
			            }

			            let session: (() -> Session)?
			            let screen: Screen.SafeDIOverrides
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_session() -> Session {
			            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
			        }
			        let session = LazilyInstantiated<Session>(__safeDI_session)
			        _ = Screen.__safeDI_Screen_mock_5183E61012439F1A.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			        let screen = Screen.__safeDI_mock(session: session, safeDIOverrides: safeDIOverrides.screen)
			        return Root(session: session, screen: screen)
			    }
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_forwardsEachTierThroughGeneratedOnlyMocks_whenMockTakesNoBuilders() async throws {
		// `Service`'s public mock has a `public` tier and a `package` tier, since `Session` is `package`, and takes no
		// builder. Each tier's `mock()` calls its own `__safeDI_mock`, the `public` one forwards to the `package` one, and a
		// mock in its package (`App`) and one in another package (`Other`) each call the `__safeDI_mock` of the tier it reaches.
		let modules = [
			ModuleFixture(name: "Feed", packageName: "feedpkg", swiftFileContentByFilePath: [
				"Service.swift": """
				import SafeDI

				@Instantiable
				public final class Analytics: Instantiable {
				    public init() {}
				}

				@Instantiable
				package final class Session: Instantiable {
				    package init() {}
				}

				@Instantiable(generateMock: .public)
				public final class Service: Instantiable {
				    init(analytics: Analytics, session: Session) {
				        self.analytics = analytics
				        self.session = session
				    }

				    @Received let analytics: Analytics
				    @Received let session: Session
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "feedpkg", swiftFileContentByFilePath: [
				"Root.swift": """
				import Feed
				import SafeDI

				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    init(analytics: Analytics, session: Session, service: Service) {
				        self.analytics = analytics
				        self.session = session
				        self.service = service
				    }

				    @Instantiated let analytics: Analytics
				    @Instantiated let session: Session
				    @Instantiated let service: Service
				}
				""",
			], dependencies: ["Feed"]),
			ModuleFixture(name: "Other", packageName: "otherpkg", swiftFileContentByFilePath: [
				"OtherRoot.swift": """
				import Feed
				import SafeDI

				@Instantiable(generateMock: true)
				public final class OtherRoot: Instantiable {
				    public init(analytics: Analytics, service: Service) {
				        self.analytics = analytics
				        self.service = service
				    }

				    @Instantiated let analytics: Analytics
				    @Instantiated let service: Service
				}
				""",
			], dependencies: ["Feed"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feed"]?.generatedFiles == [
			"Feed.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Service {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            analytics: (() -> Analytics)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                analytics: analytics,
			                session: nil
			            )
			        }

			        package init(
			            analytics: (() -> Analytics)? = nil,
			            session: (() -> Session)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                analytics: analytics,
			                session: session
			            )
			        }

			        public var analytics: (() -> Analytics)? { __safeDI_storage.analytics }
			        package var session: (() -> Session)? { __safeDI_storage.session }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                analytics: (() -> Analytics)?,
			                session: (() -> Session)?
			            ) {
			                self.analytics = analytics
			                self.session = session
			            }

			            let analytics: (() -> Analytics)?
			            let session: (() -> Session)?
			        }
			    }

			    public static func mock(
			        analytics: Analytics? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        Service.__safeDI_mock(analytics: analytics, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        analytics: Analytics? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        Service.__safeDI_mock(analytics: analytics, session: nil, safeDIOverrides: safeDIOverrides)
			    }

			    package static func mock(
			        analytics: Analytics? = nil,
			        session: Session? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        Service.__safeDI_mock(analytics: analytics, session: session, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    package static func __safeDI_mock(
			        analytics: Analytics? = nil,
			        session: Session? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Service {
			        let analytics = if let analytics { analytics } else if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
			        let session = if let session { session } else if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
			        return Service(analytics: analytics, session: session)
			    }
			}

			extension Service {
			    public enum __safeDI_Service_mock_6735768CCCA710F9 {}
			}
			#endif
			""",
		])
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feed)
			import Feed
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            analytics: (() -> Analytics)? = nil,
			            session: (() -> Session)? = nil,
			            service: Service.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                analytics: analytics,
			                session: session,
			                service: service
			            )
			        }

			        var analytics: (() -> Analytics)? { __safeDI_storage.analytics }
			        var session: (() -> Session)? { __safeDI_storage.session }
			        var service: Service.SafeDIOverrides { __safeDI_storage.service }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                analytics: (() -> Analytics)?,
			                session: (() -> Session)?,
			                service: Service.SafeDIOverrides
			            ) {
			                self.analytics = analytics
			                self.session = session
			                self.service = service
			            }

			            let analytics: (() -> Analytics)?
			            let session: (() -> Session)?
			            let service: Service.SafeDIOverrides
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
			        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
			        _ = Service.__safeDI_Service_mock_6735768CCCA710F9.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			        let service = Service.__safeDI_mock(analytics: analytics, session: session, safeDIOverrides: safeDIOverrides.service)
			        return Root(analytics: analytics, session: session, service: service)
			    }
			}
			#endif
			""",
		])
		#expect(output.modules["Other"]?.generatedFiles == [
			"Other.swift": generatedFileHeader + """
			#if canImport(Feed)
			import Feed
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension OtherRoot {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            analytics: (() -> Analytics)? = nil,
			            service: Service.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                analytics: analytics,
			                service: service
			            )
			        }

			        var analytics: (() -> Analytics)? { __safeDI_storage.analytics }
			        var service: Service.SafeDIOverrides { __safeDI_storage.service }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                analytics: (() -> Analytics)?,
			                service: Service.SafeDIOverrides
			            ) {
			                self.analytics = analytics
			                self.service = service
			            }

			            let analytics: (() -> Analytics)?
			            let service: Service.SafeDIOverrides
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> OtherRoot {
			        let analytics = if let safeDIBuilder = safeDIOverrides.analytics { safeDIBuilder() } else { Analytics() }
			        _ = Service.__safeDI_Service_mock_6735768CCCA710F9.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			        let service = Service.__safeDI_mock(analytics: analytics, safeDIOverrides: safeDIOverrides.service)
			        return OtherRoot(analytics: analytics, service: service)
			    }
			}
			#endif
			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
