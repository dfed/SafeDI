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

/// A public mock takes a value its tree receives as a `LazilyInstantiated` or `SendableLazilyInstantiated` as that
/// wrapper, as the type's initializer takes it, and hands it straight to the tree; a mock that calls it passes its own
/// wrapper, and its override closure for the call is handed that wrapper. So nothing builds the value before a type in
/// the tree reads it, and the called type holds the caller's wrapper, as in production.
struct SafeDIToolPublicMockLazyWrapperTests: ~Copyable {
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

	@Test(arguments: [MultiModuleIntegration.moduleInfo, .swiftPackagePlugin])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesLazilyReceivedValueAsWrapperAndCallersPassTheirOwn_whenMockCannotBuildIt(integration: MultiModuleIntegration) async throws {
		// `Feed` cannot build `Session`, whose `instantiate()` `App` declares, so `Screen`'s public mock takes the wrapper
		// `Screen` receives. `Mid` (public) and `MidInternal` (internal) hand the call their own wrapper, and their override
		// closures for it are handed that wrapper.
		let modules = Self.modules(wrapper: "LazilyInstantiated")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: integration, filesToDelete: &filesToDelete)
		let pluginComment = integration.seamCallComment(type: "Screen", declaringModule: "Feed")
		#expect(output.modules["Feed"]?.generatedFiles == (integration == .moduleInfo ? [
			"Feed.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    public static func mock(
			        session: LazilyInstantiated<Session>
			    ) -> Screen {
			        return Screen(session: session)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_78D96D718AF06CB7 {}
			}
			#endif
			""",
		] : [
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif


			""",
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    public static func mock(
			        session: LazilyInstantiated<Session>
			    ) -> Screen {
			        return Screen(session: session)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_78D96D718AF06CB7 {}
			}
			#endif
			""",
		]))
		#expect(output.modules["App"]?.generatedFiles == (integration == .moduleInfo ? [
			"App.swift": generatedFileHeader + """
			#if canImport(Feed)
			import Feed
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Mid {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            session: (() -> Session)? = nil,
			            screenBuilder: ((LazilyInstantiated<Session>) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screenBuilder: screenBuilder
			            )
			        }

			        public var session: (() -> Session)? { __safeDI_storage.session }
			        public var screenBuilder: ((LazilyInstantiated<Session>) -> Screen)? { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?,
			                screenBuilder: ((LazilyInstantiated<Session>) -> Screen)?
			            ) {
			                self.session = session
			                self.screenBuilder = screenBuilder
			            }

			            let session: (() -> Session)?
			            let screenBuilder: ((LazilyInstantiated<Session>) -> Screen)?
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Mid {
			        func __safeDI_session() -> Session {
			            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
			        }
			        let session = LazilyInstantiated<Session>(__safeDI_session)
			        _ = Screen.__safeDI_Screen_mock_78D96D718AF06CB7.self\(pluginComment)
			        func __safeDI_screenBuilder() -> Screen {
			            if let safeDIBuilder = safeDIOverrides.screenBuilder { safeDIBuilder(session) } else { Screen.mock(session: session) }
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        return Mid(screenBuilder: screenBuilder, session: session)
			    }
			}

			extension Mid {
			    public enum __safeDI_Mid_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			extension MidInternal {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            session: (() -> Session)? = nil,
			            screenBuilder: ((LazilyInstantiated<Session>) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screenBuilder: screenBuilder
			            )
			        }

			        var session: (() -> Session)? { __safeDI_storage.session }
			        var screenBuilder: ((LazilyInstantiated<Session>) -> Screen)? { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?,
			                screenBuilder: ((LazilyInstantiated<Session>) -> Screen)?
			            ) {
			                self.session = session
			                self.screenBuilder = screenBuilder
			            }

			            let session: (() -> Session)?
			            let screenBuilder: ((LazilyInstantiated<Session>) -> Screen)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> MidInternal {
			        func __safeDI_session() -> Session {
			            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
			        }
			        let session = LazilyInstantiated<Session>(__safeDI_session)
			        _ = Screen.__safeDI_Screen_mock_78D96D718AF06CB7.self\(pluginComment)
			        func __safeDI_screenBuilder() -> Screen {
			            if let safeDIBuilder = safeDIOverrides.screenBuilder { safeDIBuilder(session) } else { Screen.mock(session: session) }
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        return MidInternal(screenBuilder: screenBuilder, session: session)
			    }
			}
			#endif
			""",
		] : [
			"Mid+SafeDIMock.swift": generatedFileHeader + """
			#if canImport(Feed)
			import Feed
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Mid {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            session: (() -> Session)? = nil,
			            screenBuilder: ((LazilyInstantiated<Session>) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screenBuilder: screenBuilder
			            )
			        }

			        public var session: (() -> Session)? { __safeDI_storage.session }
			        public var screenBuilder: ((LazilyInstantiated<Session>) -> Screen)? { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?,
			                screenBuilder: ((LazilyInstantiated<Session>) -> Screen)?
			            ) {
			                self.session = session
			                self.screenBuilder = screenBuilder
			            }

			            let session: (() -> Session)?
			            let screenBuilder: ((LazilyInstantiated<Session>) -> Screen)?
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Mid {
			        func __safeDI_session() -> Session {
			            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
			        }
			        let session = LazilyInstantiated<Session>(__safeDI_session)
			        _ = Screen.__safeDI_Screen_mock_78D96D718AF06CB7.self\(pluginComment)
			        func __safeDI_screenBuilder() -> Screen {
			            if let safeDIBuilder = safeDIOverrides.screenBuilder { safeDIBuilder(session) } else { Screen.mock(session: session) }
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        return Mid(screenBuilder: screenBuilder, session: session)
			    }
			}

			extension Mid {
			    public enum __safeDI_Mid_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			extension MidInternal {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            session: (() -> Session)? = nil,
			            screenBuilder: ((LazilyInstantiated<Session>) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screenBuilder: screenBuilder
			            )
			        }

			        var session: (() -> Session)? { __safeDI_storage.session }
			        var screenBuilder: ((LazilyInstantiated<Session>) -> Screen)? { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?,
			                screenBuilder: ((LazilyInstantiated<Session>) -> Screen)?
			            ) {
			                self.session = session
			                self.screenBuilder = screenBuilder
			            }

			            let session: (() -> Session)?
			            let screenBuilder: ((LazilyInstantiated<Session>) -> Screen)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> MidInternal {
			        func __safeDI_session() -> Session {
			            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
			        }
			        let session = LazilyInstantiated<Session>(__safeDI_session)
			        _ = Screen.__safeDI_Screen_mock_78D96D718AF06CB7.self\(pluginComment)
			        func __safeDI_screenBuilder() -> Screen {
			            if let safeDIBuilder = safeDIOverrides.screenBuilder { safeDIBuilder(session) } else { Screen.mock(session: session) }
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        return MidInternal(screenBuilder: screenBuilder, session: session)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if canImport(Feed)
			import Feed
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif


			""",
		]))
		guard integration == .moduleInfo else { return }
		// Nothing builds the `Session` before the `Screen` reads it, and the `Screen` holds the caller's wrapper, as when the
		// `Screen` is built inline: `[built before the read, built after it, the Screen holds Mid's wrapper]`.
		try await expectValuesAgreeWithInlineMocks(
			of: modules,
			output: output,
			probes: [
				DifferentialValueProbe(Self.lifecycleProbe(of: "Mid.mock()")),
				DifferentialValueProbe(Self.lifecycleProbe(of: "MidInternal.mock()")),
				DifferentialValueProbe(
					name: "Mid.mock(safeDIOverrides:)",
					expression: Self.lifecycleProbe(of: "Mid.mock(safeDIOverrides: .init(screenBuilder: { session in Screen.mock(session: session) }))"),
					knownRightExpression: Self.lifecycleProbe(of: "Mid.mock(safeDIOverrides: .init(screenBuilder: { session in Screen(session: session) }))"),
				),
				DifferentialValueProbe(
					name: "MidInternal.mock(safeDIOverrides:)",
					expression: Self.lifecycleProbe(of: "MidInternal.mock(safeDIOverrides: .init(screenBuilder: { session in Screen.mock(session: session) }))"),
					knownRightExpression: Self.lifecycleProbe(of: "MidInternal.mock(safeDIOverrides: .init(screenBuilder: { session in Screen(session: session) }))"),
				),
			],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableLazilyReceivedValueAsSendableWrapper_whenMockCannotBuildIt() async throws {
		let modules = Self.modules(wrapper: "SendableLazilyInstantiated")
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feed"]?.generatedFiles == [
			"Feed.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    public static func mock(
			        session: SendableLazilyInstantiated<Session>
			    ) -> Screen {
			        return Screen(session: session)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_236E2EB355F72669 {}
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
			extension Mid {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            session: (@Sendable () -> Session)? = nil,
			            screenBuilder: ((SendableLazilyInstantiated<Session>) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screenBuilder: screenBuilder
			            )
			        }

			        public var session: (@Sendable () -> Session)? { __safeDI_storage.session }
			        public var screenBuilder: ((SendableLazilyInstantiated<Session>) -> Screen)? { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (@Sendable () -> Session)?,
			                screenBuilder: ((SendableLazilyInstantiated<Session>) -> Screen)?
			            ) {
			                self.session = session
			                self.screenBuilder = screenBuilder
			            }

			            let session: (@Sendable () -> Session)?
			            let screenBuilder: ((SendableLazilyInstantiated<Session>) -> Screen)?
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Mid {
			        let __safeDI_session__safeDIBuilder = safeDIOverrides.session
			        @Sendable func __safeDI_session() -> Session {
			            if let safeDIBuilder = __safeDI_session__safeDIBuilder { safeDIBuilder() } else { Session.instantiate() }
			        }
			        let session = SendableLazilyInstantiated<Session>(__safeDI_session)
			        _ = Screen.__safeDI_Screen_mock_236E2EB355F72669.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			        func __safeDI_screenBuilder() -> Screen {
			            if let safeDIBuilder = safeDIOverrides.screenBuilder { safeDIBuilder(session) } else { Screen.mock(session: session) }
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        return Mid(screenBuilder: screenBuilder, session: session)
			    }
			}

			extension Mid {
			    public enum __safeDI_Mid_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			extension MidInternal {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            session: (@Sendable () -> Session)? = nil,
			            screenBuilder: ((SendableLazilyInstantiated<Session>) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screenBuilder: screenBuilder
			            )
			        }

			        var session: (@Sendable () -> Session)? { __safeDI_storage.session }
			        var screenBuilder: ((SendableLazilyInstantiated<Session>) -> Screen)? { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (@Sendable () -> Session)?,
			                screenBuilder: ((SendableLazilyInstantiated<Session>) -> Screen)?
			            ) {
			                self.session = session
			                self.screenBuilder = screenBuilder
			            }

			            let session: (@Sendable () -> Session)?
			            let screenBuilder: ((SendableLazilyInstantiated<Session>) -> Screen)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> MidInternal {
			        let __safeDI_session__safeDIBuilder = safeDIOverrides.session
			        @Sendable func __safeDI_session() -> Session {
			            if let safeDIBuilder = __safeDI_session__safeDIBuilder { safeDIBuilder() } else { Session.instantiate() }
			        }
			        let session = SendableLazilyInstantiated<Session>(__safeDI_session)
			        _ = Screen.__safeDI_Screen_mock_236E2EB355F72669.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			        func __safeDI_screenBuilder() -> Screen {
			            if let safeDIBuilder = safeDIOverrides.screenBuilder { safeDIBuilder(session) } else { Screen.mock(session: session) }
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        return MidInternal(screenBuilder: screenBuilder, session: session)
			    }
			}
			#endif
			""",
		])
		try await expectValuesAgreeWithInlineMocks(
			of: modules,
			output: output,
			probes: [DifferentialValueProbe(Self.lifecycleProbe(of: "Mid.mock()"))],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOptionalWrapper_whenTreeReceivesLazilyInstantiatedValueOnlyIfAvailable() async throws {
		let modules = Self.modules(wrapper: "LazilyInstantiated", isReceivedOnlyIfAvailable: true)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feed"]?.generatedFiles == [
			"Feed.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    public static func mock(
			        session: LazilyInstantiated<Session>? = nil
			    ) -> Screen {
			        return Screen(session: session)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_9291F57C4C5BFEAF {}
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
			extension Mid {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            session: (() -> Session)? = nil,
			            screenBuilder: ((LazilyInstantiated<Session>?) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screenBuilder: screenBuilder
			            )
			        }

			        public var session: (() -> Session)? { __safeDI_storage.session }
			        public var screenBuilder: ((LazilyInstantiated<Session>?) -> Screen)? { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?,
			                screenBuilder: ((LazilyInstantiated<Session>?) -> Screen)?
			            ) {
			                self.session = session
			                self.screenBuilder = screenBuilder
			            }

			            let session: (() -> Session)?
			            let screenBuilder: ((LazilyInstantiated<Session>?) -> Screen)?
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Mid {
			        func __safeDI_session() -> Session {
			            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
			        }
			        let session = LazilyInstantiated<Session>(__safeDI_session)
			        _ = Screen.__safeDI_Screen_mock_9291F57C4C5BFEAF.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			        func __safeDI_screenBuilder() -> Screen {
			            if let safeDIBuilder = safeDIOverrides.screenBuilder { safeDIBuilder(session) } else { Screen.mock(session: session) }
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        return Mid(screenBuilder: screenBuilder, session: session)
			    }
			}

			extension Mid {
			    public enum __safeDI_Mid_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			extension MidInternal {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            session: (() -> Session)? = nil,
			            screenBuilder: ((LazilyInstantiated<Session>?) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screenBuilder: screenBuilder
			            )
			        }

			        var session: (() -> Session)? { __safeDI_storage.session }
			        var screenBuilder: ((LazilyInstantiated<Session>?) -> Screen)? { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?,
			                screenBuilder: ((LazilyInstantiated<Session>?) -> Screen)?
			            ) {
			                self.session = session
			                self.screenBuilder = screenBuilder
			            }

			            let session: (() -> Session)?
			            let screenBuilder: ((LazilyInstantiated<Session>?) -> Screen)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> MidInternal {
			        func __safeDI_session() -> Session {
			            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
			        }
			        let session = LazilyInstantiated<Session>(__safeDI_session)
			        _ = Screen.__safeDI_Screen_mock_9291F57C4C5BFEAF.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			        func __safeDI_screenBuilder() -> Screen {
			            if let safeDIBuilder = safeDIOverrides.screenBuilder { safeDIBuilder(session) } else { Screen.mock(session: session) }
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        return MidInternal(screenBuilder: screenBuilder, session: session)
			    }
			}
			#endif
			""",
		])
		try await expectValuesAgreeWithInlineMocks(
			of: modules,
			output: output,
			probes: [DifferentialValueProbe(Self.lifecycleProbe(of: "Mid.mock()", sessionIsOptional: true))],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsWrappersInstanceWhereTypeIsBuilt_whenTreeAlsoReceivesLazilyReceivedValueByValue() async throws {
		// `Badge`, which `Screen` builds through an `Instantiator`, receives `session` by value: it reads the instance of the
		// wrapper `Screen`'s mock takes when it is built, as production reads it.
		let modules = Self.modules(wrapper: "LazilyInstantiated", screenBuildsBadgeReadingSessionByValue: true)
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
			            badgeBuilder: ((Session) -> Badge)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                badgeBuilder: badgeBuilder
			            )
			        }

			        public var badgeBuilder: ((Session) -> Badge)? { __safeDI_storage.badgeBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                badgeBuilder: ((Session) -> Badge)?
			            ) {
			                self.badgeBuilder = badgeBuilder
			            }

			            let badgeBuilder: ((Session) -> Badge)?
			        }
			    }

			    public static func mock(
			        session: LazilyInstantiated<Session>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_badgeBuilder() -> Badge {
			            if let safeDIBuilder = safeDIOverrides.badgeBuilder { safeDIBuilder(session.instance) } else { Badge(session: session.instance) }
			        }
			        let badgeBuilder = Instantiator<Badge>(__safeDI_badgeBuilder)
			        return Screen(session: session, badgeBuilder: badgeBuilder)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_1237EAC7E69790A2 {}
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
			extension Mid {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            session: (() -> Session)? = nil,
			            screenBuilder: Screen.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screenBuilder: screenBuilder
			            )
			        }

			        public var session: (() -> Session)? { __safeDI_storage.session }
			        public var screenBuilder: Screen.SafeDIOverrides { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?,
			                screenBuilder: Screen.SafeDIOverrides
			            ) {
			                self.session = session
			                self.screenBuilder = screenBuilder
			            }

			            let session: (() -> Session)?
			            let screenBuilder: Screen.SafeDIOverrides
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Mid {
			        func __safeDI_session() -> Session {
			            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
			        }
			        let session = LazilyInstantiated<Session>(__safeDI_session)
			        _ = Screen.__safeDI_Screen_mock_1237EAC7E69790A2.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			        func __safeDI_screenBuilder() -> Screen {
			            Screen.mock(session: session, safeDIOverrides: safeDIOverrides.screenBuilder)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        return Mid(screenBuilder: screenBuilder, session: session)
			    }
			}

			extension Mid {
			    public enum __safeDI_Mid_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			extension MidInternal {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            session: (() -> Session)? = nil,
			            screenBuilder: Screen.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screenBuilder: screenBuilder
			            )
			        }

			        var session: (() -> Session)? { __safeDI_storage.session }
			        var screenBuilder: Screen.SafeDIOverrides { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?,
			                screenBuilder: Screen.SafeDIOverrides
			            ) {
			                self.session = session
			                self.screenBuilder = screenBuilder
			            }

			            let session: (() -> Session)?
			            let screenBuilder: Screen.SafeDIOverrides
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> MidInternal {
			        func __safeDI_session() -> Session {
			            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
			        }
			        let session = LazilyInstantiated<Session>(__safeDI_session)
			        _ = Screen.__safeDI_Screen_mock_1237EAC7E69790A2.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			        func __safeDI_screenBuilder() -> Screen {
			            Screen.mock(session: session, safeDIOverrides: safeDIOverrides.screenBuilder)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        return MidInternal(screenBuilder: screenBuilder, session: session)
			    }
			}
			#endif
			""",
		])
		try await expectValuesAgreeWithInlineMocks(
			of: modules,
			output: output,
			probes: [DifferentialValueProbe(Self.lifecycleProbe(of: "Mid.mock()"))],
		)
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesWrappersInstanceToMockedType_whenMockedTypeReceivesLazilyReceivedValueByValue(isReceivedOnlyIfAvailable: Bool) async throws {
		// `Screen` itself receives `session` by value – required, or only if available – and `Badge`, which it builds through an
		// `Instantiator`, receives the wrapper, so `Screen`'s mock takes the wrapper and passes `Screen` its instance, as
		// production does.
		let modules = Self.modules(wrapper: "LazilyInstantiated", isReceivedOnlyIfAvailable: isReceivedOnlyIfAvailable, screenReadsSessionByValueAndBuildsBadgeReadingWrapper: true)
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
			            badgeBuilder: ((LazilyInstantiated<Session>) -> Badge)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                badgeBuilder: badgeBuilder
			            )
			        }

			        public var badgeBuilder: ((LazilyInstantiated<Session>) -> Badge)? { __safeDI_storage.badgeBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                badgeBuilder: ((LazilyInstantiated<Session>) -> Badge)?
			            ) {
			                self.badgeBuilder = badgeBuilder
			            }

			            let badgeBuilder: ((LazilyInstantiated<Session>) -> Badge)?
			        }
			    }

			    public static func mock(
			        session: LazilyInstantiated<Session>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_badgeBuilder() -> Badge {
			            if let safeDIBuilder = safeDIOverrides.badgeBuilder { safeDIBuilder(session) } else { Badge(session: session) }
			        }
			        let badgeBuilder = Instantiator<Badge>(__safeDI_badgeBuilder)
			        return Screen(session: session.instance, badgeBuilder: badgeBuilder)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_1237EAC7E69790A2 {}
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
			extension Mid {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            session: (() -> Session)? = nil,
			            screenBuilder: Screen.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screenBuilder: screenBuilder
			            )
			        }

			        public var session: (() -> Session)? { __safeDI_storage.session }
			        public var screenBuilder: Screen.SafeDIOverrides { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?,
			                screenBuilder: Screen.SafeDIOverrides
			            ) {
			                self.session = session
			                self.screenBuilder = screenBuilder
			            }

			            let session: (() -> Session)?
			            let screenBuilder: Screen.SafeDIOverrides
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Mid {
			        func __safeDI_session() -> Session {
			            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
			        }
			        let session = LazilyInstantiated<Session>(__safeDI_session)
			        _ = Screen.__safeDI_Screen_mock_1237EAC7E69790A2.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			        func __safeDI_screenBuilder() -> Screen {
			            Screen.mock(session: session, safeDIOverrides: safeDIOverrides.screenBuilder)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        return Mid(screenBuilder: screenBuilder, session: session)
			    }
			}

			extension Mid {
			    public enum __safeDI_Mid_mock_51799E6AA5E7B634 {}
			}
			#endif

			#if DEBUG
			extension MidInternal {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            session: (() -> Session)? = nil,
			            screenBuilder: Screen.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screenBuilder: screenBuilder
			            )
			        }

			        var session: (() -> Session)? { __safeDI_storage.session }
			        var screenBuilder: Screen.SafeDIOverrides { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?,
			                screenBuilder: Screen.SafeDIOverrides
			            ) {
			                self.session = session
			                self.screenBuilder = screenBuilder
			            }

			            let session: (() -> Session)?
			            let screenBuilder: Screen.SafeDIOverrides
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> MidInternal {
			        func __safeDI_session() -> Session {
			            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
			        }
			        let session = LazilyInstantiated<Session>(__safeDI_session)
			        _ = Screen.__safeDI_Screen_mock_1237EAC7E69790A2.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			        func __safeDI_screenBuilder() -> Screen {
			            Screen.mock(session: session, safeDIOverrides: safeDIOverrides.screenBuilder)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        return MidInternal(screenBuilder: screenBuilder, session: session)
			    }
			}
			#endif
			""",
		])
		let screenSession = isReceivedOnlyIfAvailable ? "screen.session!" : "screen.session"
		try await expectValuesAgreeWithInlineMocks(
			of: modules,
			output: output,
			probes: [DifferentialValueProbe(
				"{ SessionCount.created = 0; let mid = Mid.mock(); let screen = mid.screenBuilder.instantiate(); let builtWithScreen = SessionCount.created; let badge = screen.badgeBuilder.instantiate(); return [builtWithScreen, SessionCount.created, \(screenSession) === mid.session.instance ? 1 : 0, badge.session === mid.session ? 1 : 0] }()",
			)],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsWrapperParameterNamedApartForInstance_whenMockedTypeTakesDefaultValuedParameterOfLabel() async throws {
		// `Screen`'s initializer takes a default-valued `session: Int`, so its mock takes the wrapper `Badge` receives as
		// `session_Session`, whose instance `Leaf`, beneath `Badge`, reads by value.
		let modules = [
			ModuleFixture(name: "Feed", packageName: "feedpkg", swiftFileContentByFilePath: [
				"Screen.swift": """
				import SafeDI

				public enum SessionCount {
				    nonisolated(unsafe) public static var created = 0
				}

				public final class Session: Instantiable, Sendable {
				    public init() {
				        SessionCount.created += 1
				    }
				}

				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    public init(badge: Badge, session: Int = 3) {
				        self.badge = badge
				    }

				    @Instantiated public let badge: Badge
				}

				@Instantiable
				public final class Badge: Instantiable {
				    public init(session: LazilyInstantiated<Session>, leaf: Leaf) {
				        self.session = session
				        self.leaf = leaf
				    }

				    @Received public let session: LazilyInstantiated<Session>
				    @Instantiated public let leaf: Leaf
				}

				@Instantiable
				public final class Leaf: Instantiable {
				    public init(session: Session) {
				        self.session = session
				    }

				    @Received public let session: Session
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "apppkg", swiftFileContentByFilePath: [
				"Mid.swift": """
				import Feed
				import SafeDI

				@Instantiable(conformsElsewhere: true)
				extension Session {
				    public static func instantiate() -> Session {
				        Session()
				    }
				}

				@Instantiable(generateMock: true)
				public final class Mid: Instantiable {
				    public init(screenBuilder: Instantiator<Screen>, session: LazilyInstantiated<Session>) {
				        self.screenBuilder = screenBuilder
				        self.session = session
				    }

				    @Instantiated public let screenBuilder: Instantiator<Screen>
				    @Instantiated public let session: LazilyInstantiated<Session>
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
			            badge: __safeDI_Feed_Badge_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                badge: badge
			            )
			        }

			        public var badge: __safeDI_Feed_Badge_MockConfiguration { __safeDI_storage.badge }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                badge: __safeDI_Feed_Badge_MockConfiguration
			            ) {
			                self.badge = badge
			            }

			            let badge: __safeDI_Feed_Badge_MockConfiguration
			        }
			    }

			    public static func mock(
			        session: Int? = nil,
			        session_Session: LazilyInstantiated<Session>,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let session = session ?? (3)
			        func __safeDI_badge() -> Badge {
			            let leaf = if let safeDIBuilder = safeDIOverrides.badge.leaf { safeDIBuilder(session_Session.instance) } else { Leaf(session: session_Session.instance) }
			            return Badge.__safeDI_init(session: session_Session, leaf: leaf, safeDIBuilder: safeDIOverrides.badge.safeDIBuilder)
			        }
			        let badge: Badge = __safeDI_badge()
			        return Screen(badge: badge, session: session)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_8D4E8D937DF23065 {}
			}
			#endif

			#if DEBUG
			/// Configuration for how `Badge` is constructed within the public mock trees of module `Feed`.
			nonisolated public struct __safeDI_Feed_Badge_MockConfiguration {
			    public init(
			        leaf: ((Session) -> Leaf)? = nil,
			        _ safeDIBuilder: ((LazilyInstantiated<Session>, Leaf) -> Badge)? = nil
			    ) {
			        __safeDI_storage = __safeDI_Storage(
			            leaf: leaf,
			            safeDIBuilder: safeDIBuilder
			        )
			    }

			    public var leaf: ((Session) -> Leaf)? { __safeDI_storage.leaf }
			    /// Overrides how `Badge` is constructed. Parameters match the type’s initializer or custom mock method.
			    public var safeDIBuilder: ((LazilyInstantiated<Session>, Leaf) -> Badge)? { __safeDI_storage.safeDIBuilder }

			    private let __safeDI_storage: __safeDI_Storage

			    private final class __safeDI_Storage {
			        init(
			            leaf: ((Session) -> Leaf)?,
			            safeDIBuilder: ((LazilyInstantiated<Session>, Leaf) -> Badge)?
			        ) {
			            self.leaf = leaf
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let leaf: ((Session) -> Leaf)?
			        let safeDIBuilder: ((LazilyInstantiated<Session>, Leaf) -> Badge)?
			    }
			}

			extension Badge {
			    static func __safeDI_init(session: LazilyInstantiated<Session>, leaf: Leaf, safeDIBuilder: ((LazilyInstantiated<Session>, Leaf) -> Badge)?) -> Badge {
			        if let safeDIBuilder { safeDIBuilder(session, leaf) } else { Badge(session: session, leaf: leaf) }
			    }
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
			extension Mid {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            session: (() -> Session)? = nil,
			            screenBuilder: Screen.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screenBuilder: screenBuilder
			            )
			        }

			        var session: (() -> Session)? { __safeDI_storage.session }
			        var screenBuilder: Screen.SafeDIMockConfiguration { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?,
			                screenBuilder: Screen.SafeDIMockConfiguration
			            ) {
			                self.session = session
			                self.screenBuilder = screenBuilder
			            }

			            let session: (() -> Session)?
			            let screenBuilder: Screen.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Mid {
			        func __safeDI_session() -> Session {
			            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
			        }
			        let session = LazilyInstantiated<Session>(__safeDI_session)
			        func __safeDI_screenBuilder() -> Screen {
			            func __safeDI_badge() -> Badge {
			                let leaf = if let safeDIBuilder = safeDIOverrides.screenBuilder.badge.leaf { safeDIBuilder(session.instance) } else { Leaf(session: session.instance) }
			                return if let safeDIBuilder = safeDIOverrides.screenBuilder.badge.safeDIBuilder { safeDIBuilder(session, leaf) } else { Badge(session: session, leaf: leaf) }
			            }
			            let badge: Badge = __safeDI_badge()
			            return if let safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder { safeDIBuilder(badge, safeDIOverrides.screenBuilder.session) } else { Screen(badge: badge, session: safeDIOverrides.screenBuilder.session) }
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        return Mid(screenBuilder: screenBuilder, session: session)
			    }
			}
			#endif

			#if DEBUG
			extension Badge {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            leaf: ((Session) -> Leaf)? = nil,
			            _ safeDIBuilder: ((LazilyInstantiated<Session>, Leaf) -> Badge)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                leaf: leaf,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var leaf: ((Session) -> Leaf)? { __safeDI_storage.leaf }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((LazilyInstantiated<Session>, Leaf) -> Badge)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                leaf: ((Session) -> Leaf)?,
			                safeDIBuilder: ((LazilyInstantiated<Session>, Leaf) -> Badge)?
			            ) {
			                self.leaf = leaf
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let leaf: ((Session) -> Leaf)?
			            let safeDIBuilder: ((LazilyInstantiated<Session>, Leaf) -> Badge)?
			        }
			    }
			}

			extension Screen {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            badge: Badge.SafeDIMockConfiguration = .init(),
			            session: Int = 3,
			            _ safeDIBuilder: ((Badge, Int) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                badge: badge,
			                session: session,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var badge: Badge.SafeDIMockConfiguration { __safeDI_storage.badge }
			        var session: Int { __safeDI_storage.session }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Badge, Int) -> Screen)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                badge: Badge.SafeDIMockConfiguration,
			                session: Int,
			                safeDIBuilder: ((Badge, Int) -> Screen)?
			            ) {
			                self.badge = badge
			                self.session = session
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let badge: Badge.SafeDIMockConfiguration
			            let session: Int
			            let safeDIBuilder: ((Badge, Int) -> Screen)?
			        }
			    }
			}
			#endif

			""",
		])
		try await expectValuesAgreeWithInlineMocks(
			of: modules,
			output: output,
			probes: [DifferentialValueProbe(
				"{ SessionCount.created = 0; let mid = Mid.mock(); let builtWithMid = SessionCount.created; let screen = mid.screenBuilder.instantiate(); return [builtWithMid, SessionCount.created, screen.badge.session === mid.session ? 1 : 0, screen.badge.leaf.session === mid.session.instance ? 1 : 0] }()",
			)],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorThatTreeReceivesWrapperFromOutsideIt_whenSendableFunctionReadsInstanceOfWrapperParameter() async {
		// `Screen`'s mock takes the `LazilyInstantiated` it receives, and `Badge`, built in a `@Sendable` function, receives
		// its instance by value, which that function cannot capture, as no production tree can hold this shape.
		let modules = [
			ModuleFixture(name: "Feed", packageName: "feedpkg", swiftFileContentByFilePath: [
				"Screen.swift": """
				import SafeDI

				public final class Session: Instantiable, Sendable {
				    public init() {}
				}

				@Instantiable(generateMock: .public)
				public final class Screen: Instantiable {
				    init(session: LazilyInstantiated<Session>, badgeBuilder: SendableInstantiator<Badge>) {
				        self.session = session
				        self.badgeBuilder = badgeBuilder
				    }

				    @Received public let session: LazilyInstantiated<Session>
				    @Instantiated public let badgeBuilder: SendableInstantiator<Badge>
				}

				@Instantiable
				public final class Badge: Instantiable, Sendable {
				    init(session: Session) {
				        self.session = session
				    }

				    @Received let session: Session
				}
				""",
			]),
		]
		await assertThrowsMultiModuleError(inModule: "Feed", diagnostics: { fixtures in
			"""
			\(fixtures["Feed"]!["Screen.swift"]):24:5: error: @Received property `session: Session` cannot be received inside a `@Sendable` function in chain: Screen -> Badge. SafeDI builds `badgeBuilder: SendableInstantiator<Badge>` on `Screen` in a `@Sendable` function, which cannot capture `session: LazilyInstantiated<Session>`, which the tree of `Screen` receives from outside it, because `LazilyInstantiated<Session>` is not `Sendable`. Declare `session` as `SendableLazilyInstantiated<Session>` where it is declared and where it is received as `LazilyInstantiated<Session>` to fix. A `SendableLazilyInstantiated` requires its instance type, `Session`, to be `Sendable`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOptionalWrapperAndBindsCallersOrItsOwn_whenMockBuildsLazilyReceivedValue() async throws {
		// One module declares `Session`'s `instantiate()`, so `Screen`'s mock builds the wrapper when passed `nil`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [ModuleFixture(name: "Feed", packageName: "feedpkg", swiftFileContentByFilePath: [
				"Screen.swift": Self.feed(wrapper: "LazilyInstantiated"),
				"Session.swift": Self.sessionInstantiate,
			])],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
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
			            session: (() -> Session)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session
			            )
			        }

			        public var session: (() -> Session)? { __safeDI_storage.session }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?
			            ) {
			                self.session = session
			            }

			            let session: (() -> Session)?
			        }
			    }

			    public static func mock(
			        session: LazilyInstantiated<Session>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_session() -> Session {
			            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
			        }
			        let session = if let session { session } else { LazilyInstantiated<Session>(__safeDI_session) }
			        return Screen(session: session)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_5183E61012439F1A {}
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOptionalWrapperOnPackageTierAndPackageCallerPassesItsOwn_whenInstanceTypeIsPackage() async throws {
		// `Session` is `package`, and `Feed` builds it, so only the `package` tier takes `session`; `App`, in the same package,
		// calls that tier with its wrapper.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feed", packageName: "feedpkg", swiftFileContentByFilePath: [
					"Screen.swift": Self.feed(wrapper: "LazilyInstantiated", sessionAccess: "package"),
					"Session.swift": Self.sessionInstantiate.replacingOccurrences(of: "public static", with: "package static"),
				]),
				ModuleFixture(name: "App", packageName: "feedpkg", swiftFileContentByFilePath: [
					"Mid.swift": """
					import Feed
					import SafeDI

					@Instantiable(generateMock: true)
					package final class MidInternal: Instantiable {
					    package init(screenBuilder: Instantiator<Screen>, session: LazilyInstantiated<Session>) {
					        self.screenBuilder = screenBuilder
					        self.session = session
					    }

					    @Instantiated package let screenBuilder: Instantiator<Screen>
					    @Instantiated package let session: LazilyInstantiated<Session>
					}
					""",
				], dependencies: ["Feed"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feed"]?.generatedFiles == [
			"Feed.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init() {
			            __safeDI_storage = __safeDI_Storage(
			                session: nil
			            )
			        }

			        package init(
			            session: (() -> Session)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session
			            )
			        }

			        package var session: (() -> Session)? { __safeDI_storage.session }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?
			            ) {
			                self.session = session
			            }

			            let session: (() -> Session)?
			        }
			    }

			    public static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        Screen.mock(session: nil, safeDIOverrides: safeDIOverrides)
			    }

			    package static func mock(
			        session: LazilyInstantiated<Session>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_session() -> Session {
			            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
			        }
			        let session = if let session { session } else { LazilyInstantiated<Session>(__safeDI_session) }
			        return Screen(session: session)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_212FA9D99060603B {}
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
			extension MidInternal {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            session: (() -> Session)? = nil,
			            screenBuilder: Screen.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screenBuilder: screenBuilder
			            )
			        }

			        var session: (() -> Session)? { __safeDI_storage.session }
			        var screenBuilder: Screen.SafeDIOverrides { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?,
			                screenBuilder: Screen.SafeDIOverrides
			            ) {
			                self.session = session
			                self.screenBuilder = screenBuilder
			            }

			            let session: (() -> Session)?
			            let screenBuilder: Screen.SafeDIOverrides
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> MidInternal {
			        func __safeDI_session() -> Session {
			            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
			        }
			        let session = LazilyInstantiated<Session>(__safeDI_session)
			        _ = Screen.__safeDI_Screen_mock_212FA9D99060603B.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			        func __safeDI_screenBuilder() -> Screen {
			            Screen.mock(session: session, safeDIOverrides: safeDIOverrides.screenBuilder)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        return MidInternal(screenBuilder: screenBuilder, session: session)
			    }
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesCallersWrapper_whenModuleListsTypeThatCallsPublicMockInAdditionalMocksToGenerate() async throws {
		// `App` lists `Panel`, declared in `Feed`, whose tree builds `Screen` through `Screen`'s public mock.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feed", packageName: "feedpkg", swiftFileContentByFilePath: [
					"Screen.swift": Self.feed(wrapper: "LazilyInstantiated"),
					"Panel.swift": """
					import SafeDI

					@Instantiable
					public final class Panel: Instantiable {
					    public init(screenBuilder: Instantiator<Screen>, session: LazilyInstantiated<Session>) {
					        self.screenBuilder = screenBuilder
					        self.session = session
					    }

					    @Instantiated public let screenBuilder: Instantiator<Screen>
					    @Instantiated public let session: LazilyInstantiated<Session>
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "apppkg", swiftFileContentByFilePath: [
					"Session.swift": "import Feed\n" + Self.sessionInstantiate,
					"SafeDIConfiguration.swift": """
					import SafeDI

					#SafeDIConfiguration(additionalMocksToGenerate: ["Panel"])
					""",
				], dependencies: ["Feed"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feed)
			import Feed
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Panel {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            session: (() -> Session)? = nil,
			            screenBuilder: ((LazilyInstantiated<Session>) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screenBuilder: screenBuilder
			            )
			        }

			        var session: (() -> Session)? { __safeDI_storage.session }
			        var screenBuilder: ((LazilyInstantiated<Session>) -> Screen)? { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?,
			                screenBuilder: ((LazilyInstantiated<Session>) -> Screen)?
			            ) {
			                self.session = session
			                self.screenBuilder = screenBuilder
			            }

			            let session: (() -> Session)?
			            let screenBuilder: ((LazilyInstantiated<Session>) -> Screen)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Panel {
			        func __safeDI_session() -> Session {
			            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
			        }
			        let session = LazilyInstantiated<Session>(__safeDI_session)
			        _ = Screen.__safeDI_Screen_mock_78D96D718AF06CB7.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			        func __safeDI_screenBuilder() -> Screen {
			            if let safeDIBuilder = safeDIOverrides.screenBuilder { safeDIBuilder(session) } else { Screen.mock(session: session) }
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        return Panel(screenBuilder: screenBuilder, session: session)
			    }
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_defaultsWrapperToOneAroundHandWrittenMock_whenMockCannotBuildLazilyReceivedValueItsHandWrittenMockBuilds() async throws {
		// `Session` forwards a `Token`, so the mock cannot build it, and its `mockOnly` mock takes nothing: the public mock
		// takes the wrapper as `LazilyInstantiated<Session>? = nil`, which defaults to one around that mock.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: .public)
				public struct Consumer: Instantiable {
				    public init(session: LazilyInstantiated<Session>) { self.session = session }
				    @Received let session: LazilyInstantiated<Session>
				}
				""",
				"""
				public struct Token {
				    public init() {}
				}
				@Instantiable
				public struct Session: Instantiable {
				    public init(token: Token) { self.token = token }
				    @Forwarded let token: Token
				}
				""",
				"""
				@Instantiable(mockOnly: true, customMockName: "preview")
				extension Session {
				    public static func preview(token: Token = Token()) -> Session { Session(token: token) }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles["Consumer+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Consumer {
		    public static func mock(
		        session: LazilyInstantiated<Session>? = nil
		    ) -> Consumer {
		        let session = session ?? (LazilyInstantiated<Session> { Session.preview() })
		        return Consumer(session: session)
		    }
		}

		extension Consumer {
		    public enum __safeDI_Consumer_mock_9291F57C4C5BFEAF {}
		}
		#endif
		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Session`'s `instantiate()`, declared apart from `Session`, which `Feed` declares.
	private static let sessionInstantiate = """
	import SafeDI

	@Instantiable(conformsElsewhere: true)
	extension Session {
	    public static func instantiate() -> Session {
	        Session()
	    }
	}
	"""

	/// `Feed`'s file: `Session`, which counts the instances built, and `Screen`, whose public mock receives `session` as
	/// `wrapper<Session>`.
	private static func feed(
		wrapper: String,
		isReceivedOnlyIfAvailable: Bool = false,
		screenBuildsBadgeReadingSessionByValue: Bool = false,
		screenReadsSessionByValueAndBuildsBadgeReadingWrapper: Bool = false,
		sessionAccess: String = "public",
	) -> String {
		let sessionType = isReceivedOnlyIfAvailable ? "\(wrapper)<Session>?" : "\(wrapper)<Session>"
		let receive = isReceivedOnlyIfAvailable ? "@Received(onlyIfAvailable: true)" : "@Received"
		var feed = """
		import SafeDI

		public enum SessionCount {
		    nonisolated(unsafe) public static var created = 0
		}

		\(sessionAccess) final class Session: Instantiable, Sendable {
		    \(sessionAccess) init() {
		        SessionCount.created += 1
		    }
		}

		"""
		if screenReadsSessionByValueAndBuildsBadgeReadingWrapper {
			// `Screen` receives `session` by value, as `Session` or, only if available, `Session?`, and `Badge`, which it builds,
			// as the wrapper.
			let screenSessionType = isReceivedOnlyIfAvailable ? "Session?" : "Session"
			feed += """
			@Instantiable(generateMock: .public)
			public final class Screen: Instantiable {
			    init(session: \(screenSessionType), badgeBuilder: Instantiator<Badge>) {
			        self.session = session
			        self.badgeBuilder = badgeBuilder
			    }

			    \(receive) public let session: \(screenSessionType)
			    @Instantiated public let badgeBuilder: Instantiator<Badge>
			}

			@Instantiable
			public final class Badge: Instantiable {
			    init(session: \(wrapper)<Session>) {
			        self.session = session
			    }

			    @Received public let session: \(wrapper)<Session>
			}
			"""
		} else if screenBuildsBadgeReadingSessionByValue {
			feed += """
			@Instantiable(generateMock: .public)
			public final class Screen: Instantiable {
			    init(session: \(sessionType), badgeBuilder: Instantiator<Badge>) {
			        self.session = session
			        self.badgeBuilder = badgeBuilder
			    }

			    \(receive) public let session: \(sessionType)
			    @Instantiated let badgeBuilder: Instantiator<Badge>
			}

			@Instantiable
			public final class Badge: Instantiable {
			    init(session: Session) {
			        self.session = session
			    }

			    @Received let session: Session
			}
			"""
		} else {
			feed += """
			@Instantiable(generateMock: .public)
			public final class Screen: Instantiable {
			    init(session: \(sessionType)) {
			        self.session = session
			    }

			    \(receive) \(sessionAccess) let session: \(sessionType)
			}
			"""
		}
		return feed
	}

	/// `App`'s file: `Session`'s `instantiate()`, and `Mid` and `MidInternal`, which hold `session` as `wrapper<Session>` and
	/// build `Screen` through an `Instantiator`.
	private static func app(wrapper: String) -> String {
		"""
		import Feed
		import SafeDI

		@Instantiable(conformsElsewhere: true)
		extension Session {
		    public static func instantiate() -> Session {
		        Session()
		    }
		}

		@Instantiable(generateMock: .public)
		public final class Mid: Instantiable {
		    public init(screenBuilder: Instantiator<Screen>, session: \(wrapper)<Session>) {
		        self.screenBuilder = screenBuilder
		        self.session = session
		    }

		    @Instantiated public let screenBuilder: Instantiator<Screen>
		    @Instantiated public let session: \(wrapper)<Session>
		}

		@Instantiable(generateMock: true)
		public final class MidInternal: Instantiable {
		    public init(screenBuilder: Instantiator<Screen>, session: \(wrapper)<Session>) {
		        self.screenBuilder = screenBuilder
		        self.session = session
		    }

		    @Instantiated public let screenBuilder: Instantiator<Screen>
		    @Instantiated public let session: \(wrapper)<Session>
		}
		"""
	}

	/// `Feed` (`feed(…)`) and `App` (`app(wrapper:)`), in packages of their own.
	private static func modules(
		wrapper: String,
		isReceivedOnlyIfAvailable: Bool = false,
		screenBuildsBadgeReadingSessionByValue: Bool = false,
		screenReadsSessionByValueAndBuildsBadgeReadingWrapper: Bool = false,
	) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feed", packageName: "feedpkg", swiftFileContentByFilePath: [
				"Screen.swift": feed(
					wrapper: wrapper,
					isReceivedOnlyIfAvailable: isReceivedOnlyIfAvailable,
					screenBuildsBadgeReadingSessionByValue: screenBuildsBadgeReadingSessionByValue,
					screenReadsSessionByValueAndBuildsBadgeReadingWrapper: screenReadsSessionByValueAndBuildsBadgeReadingWrapper,
				),
			]),
			ModuleFixture(name: "App", packageName: "apppkg", swiftFileContentByFilePath: [
				"Mid.swift": app(wrapper: wrapper),
			], dependencies: ["Feed"]),
		]
	}

	/// An expression that builds a `Screen` through `mid`, an expression that builds a `Mid` or a `MidInternal`, and evaluates
	/// to how many `Session`s were built before the `Screen` read its session, how many after, and whether the `Screen`
	/// holds the mock's own wrapper (`1`) or another (`0`).
	private static func lifecycleProbe(of mid: String, sessionIsOptional: Bool = false) -> String {
		let screenSession = sessionIsOptional ? "screen.session!" : "screen.session"
		return "{ SessionCount.created = 0; let mid = \(mid); let screen = mid.screenBuilder.instantiate(); let builtBeforeRead = SessionCount.created; _ = \(screenSession).instance; return [builtBeforeRead, SessionCount.created, \(screenSession) === mid.session ? 1 : 0] }()"
	}

	/// Compares the values the mocks of `modules`, as `output` generated them, build for `probes` with what internal
	/// mocks build inline when every declaration of `modules` is in one module and every public mock is internal.
	private mutating func expectValuesAgreeWithInlineMocks(
		of modules: [ModuleFixture],
		output: MultiModuleTestOutput,
		probes: [DifferentialValueProbe],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let moduleNames = Set(modules.map(\.name))
		func inline(_ source: String) -> String {
			source
				.split(separator: "\n", omittingEmptySubsequences: false)
				.filter { line in !moduleNames.contains { line == "import \($0)" } }
				.joined(separator: "\n")
				.replacingOccurrences(of: "generateMock: .public", with: "generateMock: true")
		}
		var inlineFiles = [String: String]()
		for module in modules {
			for (fileName, content) in module.swiftFileContentByFilePath {
				inlineFiles["\(module.name)_\(fileName)"] = inline(content)
			}
		}
		let inlineModules = [ModuleFixture(name: modules[0].name, packageName: modules[0].packageName, swiftFileContentByFilePath: inlineFiles)]
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		func path(of modules: [ModuleFixture], output: MultiModuleTestOutput) throws -> DifferentialValuePath {
			try DifferentialValuePath(modules: modules.map { module in
				try DifferentialValueModule(
					name: module.name,
					packageName: module.packageName,
					dependencyModuleNames: module.dependencies,
					fixtureFiles: module.swiftFileContentByFilePath,
					generatedFiles: #require(output.modules[module.name], sourceLocation: sourceLocation).generatedFiles,
				)
			})
		}
		try await expectDifferentialValuesAgree(
			feature: path(of: modules, output: output),
			knownRight: path(of: inlineModules, output: inlineOutput),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
