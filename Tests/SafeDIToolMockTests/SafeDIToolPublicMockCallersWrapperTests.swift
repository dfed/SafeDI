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

/// A public mock that takes a builder struct, whose tree receives a value lazily, as a `LazilyInstantiated` or
/// `SendableLazilyInstantiated`, takes the value's instance in `mock()` and the wrapper itself in the function only generated
/// code calls. A generated caller hands that function the wrapper it holds, as the inline mock hands it, so nothing reads the
/// instance at the call, and a fill of the called mock's place holds the caller's own wrapper: nothing the inline mock frees
/// stays alive while the place's builder lives.
struct SafeDIToolPublicMockCallersWrapperTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – a fill that re-enters the called mock

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsCalledMockTheCallersWrapper_whenFillReentersCalledMockOfInternalCaller() async throws {
		// `Fill` builds `Screen` again, so it reads the `session` `Screen`'s place carries. `Root`'s mock passes its own wrapper,
		// which the fill holds; no `Session` is created until something reads it, as inline.
		let modules = Self.modules(
			screen: Self.screen,
			app: [Self.sessionExtension, Self.root(mock: "true"), Self.fillBuildingScreenAgain, Self.countsWhileHoleBuilderLives],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    nonisolated public enum SafeDIMockScope_Fill_AnyHole {
		        nonisolated public struct holeBuilder_Values {
		            public let session: LazilyInstantiated<Session>
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.holeBuilder = { _ in __safeDI_builder }
		            }
		        }
		    }

		    public static func mock(
		        session: Session,
		        fill_AnyHoleBuilder: @escaping ErasedInstantiator<Int, AnyHole>.Builder
		    ) -> Screen {
		        Screen.__safeDI_mock(session: LazilyInstantiated<Session> { session }, fill_AnyHoleBuilder: .init(__safeDI_noScope: fill_AnyHoleBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        session session_lazilyInstantiated: LazilyInstantiated<Session>,
		        fill_AnyHoleBuilder __safeDI_fill_AnyHoleBuilder: Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole>
		    ) -> Screen {
		        let holeBuilder = ErasedInstantiator<Int, AnyHole>(__safeDI_fill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_Fill_AnyHole.holeBuilder_Values(session: session_lazilyInstantiated)))
		        return Screen(session: session_lazilyInstantiated, holeBuilder: holeBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_B09BE77BCEBA6E3E {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            session: (() -> Session)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                session: session
		            )
		        }

		        var session: (() -> Session)? { __safeDI_storage.session }

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

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_session() -> Session {
		            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
		        }
		        let session = LazilyInstantiated<Session>(__safeDI_session)
		        func __safeDI_screen() -> Screen {
		            func __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: LazilyInstantiated<Session>) -> ErasedInstantiator<Int, AnyHole>.Builder {
		                func __safeDI_holeBuilder(ticket: Int) -> Fill {
		                    func __safeDI_screenBuilder() -> Screen {
		                        Screen.__safeDI_mock(session: session, fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder_Screen())
		                    }
		                    let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		                    return Fill(ticket: ticket, screenBuilder: screenBuilder)
		                }
		                return { forwarded in AnyHole(__safeDI_holeBuilder(ticket: forwarded)) }
		            }
		            func __safeDI_fill_AnyHoleBuilder_Screen() -> Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole> {
		                .init(holeBuilder: { values in __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: values.session) })
		            }
		            _ = Screen.__safeDI_Screen_mock_B09BE77BCEBA6E3E.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen.__safeDI_mock(session: session, fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder_Screen())
		        }
		        let screen: Screen = __safeDI_screen()
		        return Root(screen: screen, session: session)
		    }
		}
		#endif
		"""])
		let counts = try await describedCounts(of: modules, output: output, probe: "countsWhileHoleBuilderLives()")
		if compileVerificationIsEnabled {
			#expect(counts.knownRight == "probe countsWhileHoleBuilderLives()\nString \"Session 0\"\n")
			#expect(counts.feature == counts.knownRight)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsCalledMockTheCallersWrapper_whenFillReentersCalledMockOfPublicCaller() async throws {
		let modules = Self.modules(
			screen: Self.screen,
			app: [Self.sessionExtension, Self.root(mock: ".public"), Self.fillBuildingScreenAgain, Self.countsWhileHoleBuilderLives],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feed)
		import Feed
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
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
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_session() -> Session {
		            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
		        }
		        let session = LazilyInstantiated<Session>(__safeDI_session)
		        func __safeDI_screen() -> Screen {
		            func __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: LazilyInstantiated<Session>) -> ErasedInstantiator<Int, AnyHole>.Builder {
		                func __safeDI_holeBuilder(ticket: Int) -> Fill {
		                    func __safeDI_screenBuilder() -> Screen {
		                        Screen.__safeDI_mock(session: session, fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder_Screen())
		                    }
		                    let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		                    return Fill(ticket: ticket, screenBuilder: screenBuilder)
		                }
		                return { forwarded in AnyHole(__safeDI_holeBuilder(ticket: forwarded)) }
		            }
		            func __safeDI_fill_AnyHoleBuilder_Screen() -> Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole> {
		                .init(holeBuilder: { values in __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: values.session) })
		            }
		            _ = Screen.__safeDI_Screen_mock_B09BE77BCEBA6E3E.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen.__safeDI_mock(session: session, fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder_Screen())
		        }
		        let screen: Screen = __safeDI_screen()
		        return Root(screen: screen, session: session)
		    }
		}

		extension Root {
		    public enum __safeDI_Root_mock_51799E6AA5E7B634 {}
		}
		#endif
		"""])
		let counts = try await describedCounts(of: modules, output: output, probe: "countsWhileHoleBuilderLives()")
		if compileVerificationIsEnabled {
			#expect(counts.knownRight == "probe countsWhileHoleBuilderLives()\nString \"Session 0\"\n")
			#expect(counts.feature == counts.knownRight)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsCallersWrapperInPlaceOfOneItBuilds_whenFillReentersCalledMockThatCanBuildTheValue() async throws {
		// `Feed` sees how to build `Session`, so `Screen`'s mock builds it when passed `nil`. The function only generated code
		// calls takes the wrapper, and binds the caller's in place of the one it would build.
		let modules = Self.modules(
			session: Self.buildableSession,
			screen: Self.screen,
			app: [Self.root(mock: "true"), Self.fillBuildingScreenAgain, Self.countsWhileHoleBuilderLives],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    nonisolated public enum SafeDIMockScope_Fill_AnyHole {
		        nonisolated public struct holeBuilder_Values {
		            public let session: LazilyInstantiated<Session>
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.holeBuilder = { _ in __safeDI_builder }
		            }
		        }
		    }

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
		        fill_AnyHoleBuilder: @escaping ErasedInstantiator<Int, AnyHole>.Builder,
		        session: Session? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        Screen.__safeDI_mock(fill_AnyHoleBuilder: .init(__safeDI_noScope: fill_AnyHoleBuilder), session: session.map { instance in LazilyInstantiated<Session> { instance } }, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        fill_AnyHoleBuilder __safeDI_fill_AnyHoleBuilder: Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole>,
		        session: LazilyInstantiated<Session>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_session() -> Session {
		            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
		        }
		        let session = session ?? LazilyInstantiated<Session>(__safeDI_session)
		        let holeBuilder = ErasedInstantiator<Int, AnyHole>(__safeDI_fill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_Fill_AnyHole.holeBuilder_Values(session: session)))
		        return Screen(session: session, holeBuilder: holeBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_9C2F5261CFA645DE {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		        func __safeDI_screen() -> Screen {
		            func __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: LazilyInstantiated<Session>) -> ErasedInstantiator<Int, AnyHole>.Builder {
		                func __safeDI_holeBuilder(ticket: Int) -> Fill {
		                    func __safeDI_screenBuilder() -> Screen {
		                        Screen.__safeDI_mock(fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder_Screen(), session: session)
		                    }
		                    let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		                    return Fill(ticket: ticket, screenBuilder: screenBuilder)
		                }
		                return { forwarded in AnyHole(__safeDI_holeBuilder(ticket: forwarded)) }
		            }
		            func __safeDI_fill_AnyHoleBuilder_Screen() -> Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole> {
		                .init(holeBuilder: { values in __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: values.session) })
		            }
		            _ = Screen.__safeDI_Screen_mock_9C2F5261CFA645DE.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen.__safeDI_mock(fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder_Screen(), session: session, safeDIOverrides: safeDIOverrides.screen)
		        }
		        let screen: Screen = __safeDI_screen()
		        return Root(screen: screen, session: session)
		    }
		}
		#endif
		"""])
		let counts = try await describedCounts(of: modules, output: output, probe: "countsWhileHoleBuilderLives()")
		if compileVerificationIsEnabled {
			#expect(counts.knownRight == "probe countsWhileHoleBuilderLives()\nString \"Session 0\"\n")
			#expect(counts.feature == counts.knownRight)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsCalledMockTheCallersWrapper_whenFillReentersCalledMockOfTypeOneInstantiatorBeneath() async throws {
		// `Screen`'s place is `Detail`'s, one instantiator beneath it, and only `Detail` receives `session`.
		let modules = Self.modules(
			screen: Self.screenOpeningDetail,
			app: [Self.sessionExtension, Self.root(mock: "true"), Self.fillBuildingScreenAgain, Self.countsWhileDetailHoleBuilderLives],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    nonisolated public enum SafeDIMockScope_Fill_AnyHole {
		        nonisolated public struct detailBuilder_Values {
		            public let session: LazilyInstantiated<Session>
		        }

		        nonisolated public enum Detail_Scope {
		            nonisolated public struct holeBuilder_Values {}

		            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		                public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		                public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                    self.holeBuilder = holeBuilder
		                }

		                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                    self.holeBuilder = { _ in __safeDI_builder }
		                }
		            }
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let detailBuilder: (detailBuilder_Values) -> SafeDIMockScope_Fill_AnyHole.Detail_Scope.__safeDI_Builder<__safeDI_Built>

		            public init(detailBuilder: @escaping (detailBuilder_Values) -> SafeDIMockScope_Fill_AnyHole.Detail_Scope.__safeDI_Builder<__safeDI_Built>) {
		                self.detailBuilder = detailBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.detailBuilder = { _ in .init(__safeDI_noScope: __safeDI_builder) }
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            detailBuilder: ((LazilyInstantiated<Session>, ErasedInstantiator<Int, AnyHole>) -> Detail)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                detailBuilder: detailBuilder
		            )
		        }

		        public var detailBuilder: ((LazilyInstantiated<Session>, ErasedInstantiator<Int, AnyHole>) -> Detail)? { __safeDI_storage.detailBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                detailBuilder: ((LazilyInstantiated<Session>, ErasedInstantiator<Int, AnyHole>) -> Detail)?
		            ) {
		                self.detailBuilder = detailBuilder
		            }

		            let detailBuilder: ((LazilyInstantiated<Session>, ErasedInstantiator<Int, AnyHole>) -> Detail)?
		        }
		    }

		    public static func mock(
		        session: Session,
		        fill_AnyHoleBuilder: @escaping ErasedInstantiator<Int, AnyHole>.Builder,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        Screen.__safeDI_mock(session: LazilyInstantiated<Session> { session }, fill_AnyHoleBuilder: .init(__safeDI_noScope: fill_AnyHoleBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        session session_lazilyInstantiated: LazilyInstantiated<Session>,
		        fill_AnyHoleBuilder __safeDI_fill_AnyHoleBuilder: Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_fill_AnyHoleBuilder_detailBuilder = __safeDI_fill_AnyHoleBuilder.detailBuilder(SafeDIMockScope_Fill_AnyHole.detailBuilder_Values(session: session_lazilyInstantiated))
		        func __safeDI_detailBuilder() -> Detail {
		            let holeBuilder = ErasedInstantiator<Int, AnyHole>(__safeDI_fill_AnyHoleBuilder_detailBuilder.holeBuilder(SafeDIMockScope_Fill_AnyHole.Detail_Scope.holeBuilder_Values()))
		            return if let safeDIBuilder = safeDIOverrides.detailBuilder { safeDIBuilder(session_lazilyInstantiated, holeBuilder) } else { Detail(session: session_lazilyInstantiated, holeBuilder: holeBuilder) }
		        }
		        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		        return Screen(detailBuilder: detailBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_7943AD6A5FB6D853 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
		        }
		        let session = LazilyInstantiated<Session>(__safeDI_session)
		        func __safeDI_screen() -> Screen {
		            func __safeDI_fill_AnyHoleBuilder_Screen_Detail_Scope_holeBuilder(session: LazilyInstantiated<Session>) -> ErasedInstantiator<Int, AnyHole>.Builder {
		                func __safeDI_holeBuilder(ticket: Int) -> Fill {
		                    func __safeDI_screenBuilder() -> Screen {
		                        Screen.__safeDI_mock(session: session, fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder_Screen())
		                    }
		                    let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		                    return Fill(ticket: ticket, screenBuilder: screenBuilder)
		                }
		                return { forwarded in AnyHole(__safeDI_holeBuilder(ticket: forwarded)) }
		            }
		            func __safeDI_fill_AnyHoleBuilder_Screen() -> Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole> {
		                .init(detailBuilder: { values in __safeDI_fill_AnyHoleBuilder_Screen_Detail_Scope(session: values.session) })
		            }
		            func __safeDI_fill_AnyHoleBuilder_Screen_Detail_Scope(session: LazilyInstantiated<Session>) -> Screen.SafeDIMockScope_Fill_AnyHole.Detail_Scope.__safeDI_Builder<AnyHole> {
		                .init(holeBuilder: { _ in __safeDI_fill_AnyHoleBuilder_Screen_Detail_Scope_holeBuilder(session: session) })
		            }
		            _ = Screen.__safeDI_Screen_mock_7943AD6A5FB6D853.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen.__safeDI_mock(session: session, fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder_Screen(), safeDIOverrides: safeDIOverrides.screen)
		        }
		        let screen: Screen = __safeDI_screen()
		        return Root(screen: screen, session: session)
		    }
		}
		#endif
		"""])
		let counts = try await describedCounts(of: modules, output: output, probe: "countsWhileDetailHoleBuilderLives()")
		if compileVerificationIsEnabled {
			#expect(counts.knownRight == "probe countsWhileDetailHoleBuilderLives()\nString \"Session 0\"\n")
			#expect(counts.feature == counts.knownRight)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsCalledMockTheCallersSendableWrapper_whenFillReentersCalledMock() async throws {
		let modules = Self.modules(
			screen: Self.screen.replacingOccurrences(of: "LazilyInstantiated", with: "SendableLazilyInstantiated"),
			app: [Self.sessionExtension, Self.root(mock: "true", wrapper: "SendableLazilyInstantiated"), Self.fillBuildingScreenAgain, Self.countsWhileHoleBuilderLives],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    nonisolated public enum SafeDIMockScope_Fill_AnyHole {
		        nonisolated public struct holeBuilder_Values {
		            public let session: SendableLazilyInstantiated<Session>
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.holeBuilder = { _ in __safeDI_builder }
		            }
		        }
		    }

		    public static func mock(
		        session: Session,
		        fill_AnyHoleBuilder: @escaping ErasedInstantiator<Int, AnyHole>.Builder
		    ) -> Screen {
		        Screen.__safeDI_mock(session: SendableLazilyInstantiated<Session> { session }, fill_AnyHoleBuilder: .init(__safeDI_noScope: fill_AnyHoleBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        session session_sendableLazilyInstantiated: SendableLazilyInstantiated<Session>,
		        fill_AnyHoleBuilder __safeDI_fill_AnyHoleBuilder: Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole>
		    ) -> Screen {
		        let holeBuilder = ErasedInstantiator<Int, AnyHole>(__safeDI_fill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_Fill_AnyHole.holeBuilder_Values(session: session_sendableLazilyInstantiated)))
		        return Screen(session: session_sendableLazilyInstantiated, holeBuilder: holeBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_B30F8DDD164C17F2 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            session: (@Sendable () -> Session)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                session: session
		            )
		        }

		        var session: (@Sendable () -> Session)? { __safeDI_storage.session }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage: Sendable {
		            init(
		                session: (@Sendable () -> Session)?
		            ) {
		                self.session = session
		            }

		            let session: (@Sendable () -> Session)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let __safeDI_session__safeDIBuilder = safeDIOverrides.session
		        @Sendable func __safeDI_session() -> Session {
		            if let safeDIBuilder = __safeDI_session__safeDIBuilder { safeDIBuilder() } else { Session.instantiate() }
		        }
		        let session = SendableLazilyInstantiated<Session>(__safeDI_session)
		        func __safeDI_screen() -> Screen {
		            func __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: SendableLazilyInstantiated<Session>) -> ErasedInstantiator<Int, AnyHole>.Builder {
		                func __safeDI_holeBuilder(ticket: Int) -> Fill {
		                    func __safeDI_screenBuilder() -> Screen {
		                        Screen.__safeDI_mock(session: session, fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder_Screen())
		                    }
		                    let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		                    return Fill(ticket: ticket, screenBuilder: screenBuilder)
		                }
		                return { forwarded in AnyHole(__safeDI_holeBuilder(ticket: forwarded)) }
		            }
		            func __safeDI_fill_AnyHoleBuilder_Screen() -> Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole> {
		                .init(holeBuilder: { values in __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: values.session) })
		            }
		            _ = Screen.__safeDI_Screen_mock_B30F8DDD164C17F2.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen.__safeDI_mock(session: session, fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder_Screen())
		        }
		        let screen: Screen = __safeDI_screen()
		        return Root(screen: screen, session: session)
		    }
		}
		#endif
		"""])
		let counts = try await describedCounts(of: modules, output: output, probe: "countsWhileHoleBuilderLives()")
		if compileVerificationIsEnabled {
			#expect(counts.knownRight == "probe countsWhileHoleBuilderLives()\nString \"Session 0\"\n")
			#expect(counts.feature == counts.knownRight)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsFillThatBuildsCalledTypeAgainTheCallersWrapper_whenCalledTypeReceivesValueOnlyIfAvailable() async throws {
		// `Screen` receives `session` only if available. The `Screen` the fill builds again is handed `Root`'s wrapper, as inline,
		// and so is the one `Root` holds: neither is `nil`, and neither is a wrapper of the called mock's own.
		let modules = Self.modules(
			screen: Self.screen
				.replacingOccurrences(of: "@Received public let session: LazilyInstantiated<Session>", with: "@Received(onlyIfAvailable: true) public let session: LazilyInstantiated<Session>?")
				.replacingOccurrences(of: "init(session: LazilyInstantiated<Session>,", with: "init(session: LazilyInstantiated<Session>?,"),
			app: [
				Self.sessionExtension,
				Self.root(mock: "true"),
				Self.fillBuildingScreenAgain,
				"""
				func sessionsTheScreensHold() -> String {
				    let root = Root.mock()
				    let fill = root.screen.holeBuilder.instantiate(7).value as! Fill
				    let rebuilt = fill.screenBuilder.instantiate()
				    return "Root’s screen: \\(root.screen.session === root.session), the fill’s screen: \\(rebuilt.session === root.session)"
				}
				""",
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    nonisolated public enum SafeDIMockScope_Fill_AnyHole {
		        nonisolated public struct holeBuilder_Values {
		            public let session: LazilyInstantiated<Session>?
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.holeBuilder = { _ in __safeDI_builder }
		            }
		        }
		    }

		    public static func mock(
		        fill_AnyHoleBuilder: @escaping ErasedInstantiator<Int, AnyHole>.Builder,
		        session: Session? = nil
		    ) -> Screen {
		        Screen.__safeDI_mock(fill_AnyHoleBuilder: .init(__safeDI_noScope: fill_AnyHoleBuilder), session: session.map { instance in LazilyInstantiated<Session> { instance } })
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        fill_AnyHoleBuilder __safeDI_fill_AnyHoleBuilder: Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole>,
		        session session_lazilyInstantiated: LazilyInstantiated<Session>? = nil
		    ) -> Screen {
		        let holeBuilder = ErasedInstantiator<Int, AnyHole>(__safeDI_fill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_Fill_AnyHole.holeBuilder_Values(session: session_lazilyInstantiated)))
		        return Screen(session: session_lazilyInstantiated, holeBuilder: holeBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_99E78BF29E5B8084 {}
		}
		#endif
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            session: (() -> Session)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                session: session
		            )
		        }

		        var session: (() -> Session)? { __safeDI_storage.session }

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

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_session() -> Session {
		            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
		        }
		        let session = LazilyInstantiated<Session>(__safeDI_session)
		        func __safeDI_screen() -> Screen {
		            func __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: LazilyInstantiated<Session>?) -> ErasedInstantiator<Int, AnyHole>.Builder {
		                func __safeDI_holeBuilder(ticket: Int) -> Fill {
		                    func __safeDI_screenBuilder() -> Screen {
		                        Screen.__safeDI_mock(fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder_Screen(), session: session)
		                    }
		                    let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		                    return Fill(ticket: ticket, screenBuilder: screenBuilder)
		                }
		                return { forwarded in AnyHole(__safeDI_holeBuilder(ticket: forwarded)) }
		            }
		            func __safeDI_fill_AnyHoleBuilder_Screen() -> Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole> {
		                .init(holeBuilder: { values in __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: values.session) })
		            }
		            _ = Screen.__safeDI_Screen_mock_99E78BF29E5B8084.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen.__safeDI_mock(fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder_Screen(), session: session)
		        }
		        let screen: Screen = __safeDI_screen()
		        return Root(screen: screen, session: session)
		    }
		}
		#endif
		"""])
		let counts = try await describedCounts(of: modules, output: output, probe: "sessionsTheScreensHold()")
		if compileVerificationIsEnabled {
			#expect(counts.knownRight == "probe sessionsTheScreensHold()\nString \"Root’s screen: true, the fill’s screen: true\"\n")
			#expect(counts.feature == counts.knownRight)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_forwardsCallersWrapperToNarrowerTier_whenCallerInAnotherPackageCallsPublicTier() async throws {
		// `Screen` receives a `package` `Token` only if available, so its mock has a `package` tier beside the `public` one,
		// which `App`, in another package, calls. The `public` tier's function only generated code calls hands the wrapper on
		// to the `package` tier's, and the fill holds `Root`'s own.
		let modules = Self.modules(
			screen: Self.screen
				.replacingOccurrences(of: "init(session: LazilyInstantiated<Session>, holeBuilder: ErasedInstantiator<Int, AnyHole>) {", with: "init(session: LazilyInstantiated<Session>, token: Token?, holeBuilder: ErasedInstantiator<Int, AnyHole>) {\n        self.token = token")
				.replacingOccurrences(of: "    @Instantiated(fulfilledByType", with: "    @Received(onlyIfAvailable: true) let token: Token?\n    @Instantiated(fulfilledByType")
				+ """

				package final class Token: Instantiable {
				    package init() {}
				}
				""",
			app: [Self.sessionExtension, Self.root(mock: "true"), Self.fillReadingWrapper, Self.countsWhileHoleBuilderLives],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    nonisolated public enum SafeDIMockScope_Fill_AnyHole {
		        nonisolated public struct holeBuilder_Values {
		            public let session: LazilyInstantiated<Session>
		            package let token: Token?
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.holeBuilder = { _ in __safeDI_builder }
		            }
		        }
		    }

		    public static func mock(
		        session: Session,
		        fill_AnyHoleBuilder: @escaping ErasedInstantiator<Int, AnyHole>.Builder
		    ) -> Screen {
		        Screen.__safeDI_mock(session: LazilyInstantiated<Session> { session }, fill_AnyHoleBuilder: .init(__safeDI_noScope: fill_AnyHoleBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        session session_lazilyInstantiated: LazilyInstantiated<Session>,
		        fill_AnyHoleBuilder __safeDI_fill_AnyHoleBuilder: Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole>
		    ) -> Screen {
		        Screen.__safeDI_mock(session: session_lazilyInstantiated, fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder, token: nil)
		    }

		    package static func mock(
		        session: Session,
		        fill_AnyHoleBuilder: @escaping ErasedInstantiator<Int, AnyHole>.Builder,
		        token: Token? = nil
		    ) -> Screen {
		        Screen.__safeDI_mock(session: LazilyInstantiated<Session> { session }, fill_AnyHoleBuilder: .init(__safeDI_noScope: fill_AnyHoleBuilder), token: token)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    package static func __safeDI_mock(
		        session session_lazilyInstantiated: LazilyInstantiated<Session>,
		        fill_AnyHoleBuilder __safeDI_fill_AnyHoleBuilder: Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole>,
		        token: Token? = nil
		    ) -> Screen {
		        let holeBuilder = ErasedInstantiator<Int, AnyHole>(__safeDI_fill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_Fill_AnyHole.holeBuilder_Values(session: session_lazilyInstantiated, token: token)))
		        return Screen(session: session_lazilyInstantiated, token: token, holeBuilder: holeBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_68F18278ED4649DB {}
		}
		#endif
		"""])
		let counts = try await describedCounts(of: modules, output: output, probe: "countsWhileHoleBuilderLives()")
		if compileVerificationIsEnabled {
			#expect(counts.knownRight == "probe countsWhileHoleBuilderLives()\nString \"Session 0\"\n")
			#expect(counts.feature == counts.knownRight)
		}
	}

	// MARK: Tests – a fill that reads the wrapper

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsFillTheCallersWrapper_whenFillReadsWrapperTheCalledTypeReceives() async throws {
		// `Fill` reads the wrapper and builds nothing again: it holds `Root`'s wrapper, whose `Session` nothing has read.
		let modules = Self.modules(
			screen: Self.screen,
			app: [
				Self.sessionExtension,
				Self.root(mock: "true"),
				Self.fillReadingWrapper,
				Self.countsWhileHoleBuilderLives,
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            session: (() -> Session)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                session: session
		            )
		        }

		        var session: (() -> Session)? { __safeDI_storage.session }

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

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_session() -> Session {
		            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
		        }
		        let session = LazilyInstantiated<Session>(__safeDI_session)
		        func __safeDI_screen() -> Screen {
		            func __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: LazilyInstantiated<Session>) -> ErasedInstantiator<Int, AnyHole>.Builder {
		                func __safeDI_holeBuilder(ticket: Int) -> Fill {
		                    Fill(ticket: ticket, session: session)
		                }
		                return { forwarded in AnyHole(__safeDI_holeBuilder(ticket: forwarded)) }
		            }
		            func __safeDI_fill_AnyHoleBuilder_Screen() -> Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole> {
		                .init(holeBuilder: { values in __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: values.session) })
		            }
		            _ = Screen.__safeDI_Screen_mock_B09BE77BCEBA6E3E.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Screen.__safeDI_mock(session: session, fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder_Screen())
		        }
		        let screen: Screen = __safeDI_screen()
		        return Root(screen: screen, session: session)
		    }
		}
		#endif
		"""])
		let counts = try await describedCounts(of: modules, output: output, probe: "countsWhileHoleBuilderLives()")
		if compileVerificationIsEnabled {
			#expect(counts.knownRight == "probe countsWhileHoleBuilderLives()\nString \"Session 0\"\n")
			#expect(counts.feature == counts.knownRight)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_readsInstanceOfWrapperItIsHanded_whenCalledTypesTreeAlsoReceivesValueByValue() async throws {
		// `Screen`'s `Detail` receives `session` by value. The function only generated code calls takes the wrapper, and its
		// tree reads the instance from it.
		let modules = Self.modules(
			screen: Self.screen
				.replacingOccurrences(of: "init(session: LazilyInstantiated<Session>, holeBuilder: ErasedInstantiator<Int, AnyHole>) {", with: "init(session: LazilyInstantiated<Session>, detail: Detail, holeBuilder: ErasedInstantiator<Int, AnyHole>) {\n        self.detail = detail")
				.replacingOccurrences(of: "    @Instantiated(fulfilledByType", with: "    @Instantiated public let detail: Detail\n    @Instantiated(fulfilledByType")
				+ """

				@Instantiable
				public final class Detail: Instantiable {
				    public init(session: Session) {
				        self.session = session
				    }

				    @Received public let session: Session
				}
				""",
			app: [
				Self.sessionExtension,
				Self.root(mock: "true"),
				Self.fillBuildingScreenAgain,
				"""
				func sessionsTheScreenHolds() -> String {
				    let root = Root.mock()
				    return "wrapper: \\(root.screen.session === root.session), detail’s: \\(root.screen.detail.session === root.session.instance)"
				}
				""",
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    nonisolated public enum SafeDIMockScope_Fill_AnyHole {
		        nonisolated public struct holeBuilder_Values {
		            public let session: LazilyInstantiated<Session>
		            public let detail: Detail
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.holeBuilder = { _ in __safeDI_builder }
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            detail: ((Session) -> Detail)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                detail: detail
		            )
		        }

		        public var detail: ((Session) -> Detail)? { __safeDI_storage.detail }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                detail: ((Session) -> Detail)?
		            ) {
		                self.detail = detail
		            }

		            let detail: ((Session) -> Detail)?
		        }
		    }

		    public static func mock(
		        session: Session,
		        fill_AnyHoleBuilder: @escaping ErasedInstantiator<Int, AnyHole>.Builder,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        Screen.__safeDI_mock(session: LazilyInstantiated<Session> { session }, fill_AnyHoleBuilder: .init(__safeDI_noScope: fill_AnyHoleBuilder), safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        session session_lazilyInstantiated: LazilyInstantiated<Session>,
		        fill_AnyHoleBuilder __safeDI_fill_AnyHoleBuilder: Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole>,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let session = session_lazilyInstantiated.instance
		        let detail = if let safeDIBuilder = safeDIOverrides.detail { safeDIBuilder(session) } else { Detail(session: session) }
		        let holeBuilder = ErasedInstantiator<Int, AnyHole>(__safeDI_fill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_Fill_AnyHole.holeBuilder_Values(session: session_lazilyInstantiated, detail: detail)))
		        return Screen(session: session_lazilyInstantiated, detail: detail, holeBuilder: holeBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_F0C42BDD7B61685A {}
		}
		#endif
		"""])
		let counts = try await describedCounts(of: modules, output: output, probe: "sessionsTheScreenHolds()")
		if compileVerificationIsEnabled {
			#expect(counts.knownRight == "probe sessionsTheScreenHolds()\nString \"wrapper: true, detail’s: true\"\n")
			#expect(counts.feature == counts.knownRight)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_readsInstanceOfOptionalWrapperItIsHanded_whenCalledTypesTreeAlsoReceivesValueOnlyIfAvailable() async throws {
		// `Screen` receives `session` lazily only if available, and its `Detail` by value only if available. The function only
		// generated code calls takes the optional wrapper, and its tree reads the optional instance from it.
		let modules = Self.modules(
			screen: Self.onlyIfAvailableScreen
				.replacingOccurrences(of: "init(session: LazilyInstantiated<Session>?, holeBuilder: ErasedInstantiator<Int, AnyHole>) {", with: "init(session: LazilyInstantiated<Session>?, detail: Detail, holeBuilder: ErasedInstantiator<Int, AnyHole>) {\n        self.detail = detail")
				.replacingOccurrences(of: "    @Instantiated(fulfilledByType", with: "    @Instantiated public let detail: Detail\n    @Instantiated(fulfilledByType")
				+ """

				@Instantiable
				public final class Detail: Instantiable {
				    public init(session: Session?) {
				        self.session = session
				    }

				    @Received(onlyIfAvailable: true) public let session: Session?
				}
				""",
			app: [
				Self.sessionExtension,
				Self.root(mock: "true"),
				Self.fillBuildingScreenAgain,
				"""
				func sessionsTheScreenHolds() -> String {
				    let root = Root.mock()
				    return "wrapper: \\(root.screen.session === root.session), detail’s: \\(root.screen.detail.session === root.session.instance)"
				}
				""",
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    nonisolated public enum SafeDIMockScope_Fill_AnyHole {
		        nonisolated public struct holeBuilder_Values {
		            public let session: LazilyInstantiated<Session>?
		            public let detail: Detail
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.holeBuilder = { _ in __safeDI_builder }
		            }
		        }
		    }

		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            detail: ((Session?) -> Detail)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                detail: detail
		            )
		        }

		        public var detail: ((Session?) -> Detail)? { __safeDI_storage.detail }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                detail: ((Session?) -> Detail)?
		            ) {
		                self.detail = detail
		            }

		            let detail: ((Session?) -> Detail)?
		        }
		    }

		    public static func mock(
		        fill_AnyHoleBuilder: @escaping ErasedInstantiator<Int, AnyHole>.Builder,
		        session: Session? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        Screen.__safeDI_mock(fill_AnyHoleBuilder: .init(__safeDI_noScope: fill_AnyHoleBuilder), session: session.map { instance in LazilyInstantiated<Session> { instance } }, safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        fill_AnyHoleBuilder __safeDI_fill_AnyHoleBuilder: Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole>,
		        session session_lazilyInstantiated: LazilyInstantiated<Session>? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let session = session_lazilyInstantiated?.instance
		        let detail = if let safeDIBuilder = safeDIOverrides.detail { safeDIBuilder(session) } else { Detail(session: session) }
		        let holeBuilder = ErasedInstantiator<Int, AnyHole>(__safeDI_fill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_Fill_AnyHole.holeBuilder_Values(session: session_lazilyInstantiated, detail: detail)))
		        return Screen(session: session_lazilyInstantiated, detail: detail, holeBuilder: holeBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_CBA410B308919606 {}
		}
		#endif
		"""])
		let counts = try await describedCounts(of: modules, output: output, probe: "sessionsTheScreenHolds()")
		if compileVerificationIsEnabled {
			#expect(counts.knownRight == "probe sessionsTheScreenHolds()\nString \"wrapper: true, detail’s: true\"\n")
			#expect(counts.feature == counts.knownRight)
		}
	}

	// MARK: Tests – what a person and an override closure are handed

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesInstanceAsBefore_whenPersonCallsMockOfTypeWhoseTreeReceivesValueLazily() async throws {
		// A person passes the instance to `mock()`, which wraps it for the function only generated code calls.
		let modules = Self.modules(
			screen: Self.screen,
			app: [
				"""
				final class StubHole: HoleProtocol {}

				func screenTheTestBuilds() -> String {
				    let session = Session()
				    let screen = Screen.mock(session: session, fill_AnyHoleBuilder: { _ in AnyHole(StubHole()) })
				    return "\\(screen.session.instance === session)"
				}
				""",
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    nonisolated public enum SafeDIMockScope_Fill_AnyHole {
		        nonisolated public struct holeBuilder_Values {
		            public let session: LazilyInstantiated<Session>
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.holeBuilder = holeBuilder
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.holeBuilder = { _ in __safeDI_builder }
		            }
		        }
		    }

		    public static func mock(
		        session: Session,
		        fill_AnyHoleBuilder: @escaping ErasedInstantiator<Int, AnyHole>.Builder
		    ) -> Screen {
		        Screen.__safeDI_mock(session: LazilyInstantiated<Session> { session }, fill_AnyHoleBuilder: .init(__safeDI_noScope: fill_AnyHoleBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        session session_lazilyInstantiated: LazilyInstantiated<Session>,
		        fill_AnyHoleBuilder __safeDI_fill_AnyHoleBuilder: Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole>
		    ) -> Screen {
		        let holeBuilder = ErasedInstantiator<Int, AnyHole>(__safeDI_fill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_Fill_AnyHole.holeBuilder_Values(session: session_lazilyInstantiated)))
		        return Screen(session: session_lazilyInstantiated, holeBuilder: holeBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_B09BE77BCEBA6E3E {}
		}
		#endif
		"""])
		guard compileVerificationIsEnabled else { return }
		let description = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe("screenTheTestBuilds()")], filesToDelete: &filesToDelete)
		#expect(description == "probe screenTheTestBuilds()\nString \"true\"\n")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsOverrideClosureTheInstanceOfCallersWrapper_whenFillReadsNothingOfTheValue() async throws {
		// `Fill` reads nothing of `session`, so `Root`'s override closure for `screen` is offered: it takes `session` as
		// `Screen.mock()` takes it, by value, which it is handed the instance of the wrapper the call passes.
		let modules = Self.modules(
			screen: Self.screen,
			app: [Self.sessionExtension, Self.root(mock: "true"), Self.fillReadingNothing],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            screen: ((Session, @escaping ErasedInstantiator<Int, AnyHole>.Builder) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                session: session,
		                screen: screen
		            )
		        }

		        var session: (() -> Session)? { __safeDI_storage.session }
		        var screen: ((Session, @escaping ErasedInstantiator<Int, AnyHole>.Builder) -> Screen)? { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                session: (() -> Session)?,
		                screen: ((Session, @escaping ErasedInstantiator<Int, AnyHole>.Builder) -> Screen)?
		            ) {
		                self.session = session
		                self.screen = screen
		            }

		            let session: (() -> Session)?
		            let screen: ((Session, @escaping ErasedInstantiator<Int, AnyHole>.Builder) -> Screen)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_session() -> Session {
		            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
		        }
		        let session = LazilyInstantiated<Session>(__safeDI_session)
		        func __safeDI_screen() -> Screen {
		            func __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder() -> ErasedInstantiator<Int, AnyHole>.Builder {
		                func __safeDI_holeBuilder(ticket: Int) -> Fill {
		                    Fill(ticket: ticket)
		                }
		                return { forwarded in AnyHole(__safeDI_holeBuilder(ticket: forwarded)) }
		            }
		            func __safeDI_fill_AnyHoleBuilder_Screen() -> Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole> {
		                .init(holeBuilder: { _ in __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder() })
		            }
		            _ = Screen.__safeDI_Screen_mock_B09BE77BCEBA6E3E.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return if let safeDIBuilder = safeDIOverrides.screen { safeDIBuilder(session.instance, __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder()) } else { Screen.__safeDI_mock(session: session, fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder_Screen()) }
		        }
		        let screen: Screen = __safeDI_screen()
		        return Root(screen: screen, session: session)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsOverrideClosureTheInstanceOfCallersWrapperOptionally_whenCalledTypeReceivesValueOnlyIfAvailable() async throws {
		let modules = Self.modules(
			screen: Self.onlyIfAvailableScreen,
			app: [Self.sessionExtension, Self.root(mock: "true"), Self.fillReadingNothing],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, Session?) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                session: session,
		                screen: screen
		            )
		        }

		        var session: (() -> Session)? { __safeDI_storage.session }
		        var screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, Session?) -> Screen)? { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                session: (() -> Session)?,
		                screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, Session?) -> Screen)?
		            ) {
		                self.session = session
		                self.screen = screen
		            }

		            let session: (() -> Session)?
		            let screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, Session?) -> Screen)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_session() -> Session {
		            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
		        }
		        let session = LazilyInstantiated<Session>(__safeDI_session)
		        func __safeDI_screen() -> Screen {
		            func __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder() -> ErasedInstantiator<Int, AnyHole>.Builder {
		                func __safeDI_holeBuilder(ticket: Int) -> Fill {
		                    Fill(ticket: ticket)
		                }
		                return { forwarded in AnyHole(__safeDI_holeBuilder(ticket: forwarded)) }
		            }
		            func __safeDI_fill_AnyHoleBuilder_Screen() -> Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole> {
		                .init(holeBuilder: { _ in __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder() })
		            }
		            _ = Screen.__safeDI_Screen_mock_99E78BF29E5B8084.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return if let safeDIBuilder = safeDIOverrides.screen { safeDIBuilder(__safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(), (session as LazilyInstantiated<Session>?)?.instance) } else { Screen.__safeDI_mock(fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder_Screen(), session: session) }
		        }
		        let screen: Screen = __safeDI_screen()
		        return Root(screen: screen, session: session)
		    }
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsCalledMockAndOverrideClosureNil_whenCallerHoldsNoValueCalledTypeReceivesOnlyIfAvailable() async throws {
		let modules = Self.modules(
			screen: Self.onlyIfAvailableScreen,
			app: [
				"""
				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(screen: Screen) {
				        self.screen = screen
				    }

				    @Instantiated public let screen: Screen
				}
				""",
				Self.fillReadingNothing,
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
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
		            screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, Session?) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        var screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, Session?) -> Screen)? { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, Session?) -> Screen)?
		            ) {
		                self.screen = screen
		            }

		            let screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, Session?) -> Screen)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_screen() -> Screen {
		            func __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder() -> ErasedInstantiator<Int, AnyHole>.Builder {
		                func __safeDI_holeBuilder(ticket: Int) -> Fill {
		                    Fill(ticket: ticket)
		                }
		                return { forwarded in AnyHole(__safeDI_holeBuilder(ticket: forwarded)) }
		            }
		            func __safeDI_fill_AnyHoleBuilder_Screen() -> Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole> {
		                .init(holeBuilder: { _ in __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder() })
		            }
		            _ = Screen.__safeDI_Screen_mock_99E78BF29E5B8084.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return if let safeDIBuilder = safeDIOverrides.screen { safeDIBuilder(__safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(), nil) } else { Screen.__safeDI_mock(fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder_Screen(), session: nil) }
		        }
		        let screen: Screen = __safeDI_screen()
		        return Root(screen: screen)
		    }
		}
		#endif
		"""])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The declarations of `Feed` every fixture shares: the hole type `Screen`'s place holds.
	private static let holeType = """
	public protocol HoleProtocol {}

	public struct AnyHole: HoleProtocol {
	    public init(_ value: any HoleProtocol) {
	        self.value = value
	    }

	    public let value: any HoleProtocol
	}
	"""

	/// A `Session` no declaration of `Feed` makes instantiable, which `App` declares how to build (`sessionExtension`), and
	/// which counts the instances alive.
	private static let unbuildableSession = """
	public final class Session: Instantiable, Sendable {
	    public init() {
	        Session.alive += 1
	    }

	    deinit {
	        Session.alive -= 1
	    }

	    nonisolated(unsafe) public static var alive = 0
	}
	"""

	/// A `Session` `Feed` builds.
	private static let buildableSession = """
	@Instantiable
	public final class Session: Instantiable, Sendable {
	    public init() {
	        Session.alive += 1
	    }

	    deinit {
	        Session.alive -= 1
	    }

	    nonisolated(unsafe) public static var alive = 0
	}
	"""

	/// `Screen`, a `.public` mock that receives `session` lazily and holds a place nothing `Feed` sees fulfills. Its
	/// initializer is internal, so `App` calls its mock.
	private static let screen = """
	@Instantiable(generateMock: .public)
	public final class Screen: Instantiable {
	    init(session: LazilyInstantiated<Session>, holeBuilder: ErasedInstantiator<Int, AnyHole>) {
	        self.session = session
	        self.holeBuilder = holeBuilder
	    }

	    @Received public let session: LazilyInstantiated<Session>
	    @Instantiated(fulfilledByType: "Fill", erasedToConcreteExistential: true) public let holeBuilder: ErasedInstantiator<Int, AnyHole>
	}
	"""

	/// `screen`, receiving `session` only if available.
	private static let onlyIfAvailableScreen = screen
		.replacingOccurrences(of: "@Received public let session: LazilyInstantiated<Session>", with: "@Received(onlyIfAvailable: true) public let session: LazilyInstantiated<Session>?")
		.replacingOccurrences(of: "init(session: LazilyInstantiated<Session>,", with: "init(session: LazilyInstantiated<Session>?,")

	/// `Screen`, which opens `Detail`, which receives `session` lazily and holds the place.
	private static let screenOpeningDetail = """
	@Instantiable(generateMock: .public)
	public final class Screen: Instantiable {
	    init(detailBuilder: Instantiator<Detail>) {
	        self.detailBuilder = detailBuilder
	    }

	    @Instantiated public let detailBuilder: Instantiator<Detail>
	}

	@Instantiable
	public final class Detail: Instantiable {
	    public init(session: LazilyInstantiated<Session>, holeBuilder: ErasedInstantiator<Int, AnyHole>) {
	        self.session = session
	        self.holeBuilder = holeBuilder
	    }

	    @Received public let session: LazilyInstantiated<Session>
	    @Instantiated(fulfilledByType: "Fill", erasedToConcreteExistential: true) public let holeBuilder: ErasedInstantiator<Int, AnyHole>
	}
	"""

	/// How `App` builds `Session`.
	private static let sessionExtension = """
	@Instantiable(conformsElsewhere: true)
	extension Session {
	    public static func instantiate() -> Session {
	        Session()
	    }
	}
	"""

	/// `Root`, whose mock is generated with `mock`, which holds `session` in `wrapper` and builds `Screen`.
	private static func root(mock: String, wrapper: String = "LazilyInstantiated") -> String {
		"""
		@Instantiable(generateMock: \(mock))
		public final class Root: Instantiable {
		    public init(screen: Screen, session: \(wrapper)<Session>) {
		        self.screen = screen
		        self.session = session
		    }

		    @Instantiated public let screen: Screen
		    @Instantiated public let session: \(wrapper)<Session>
		}
		"""
	}

	/// The fill of `Screen`'s place, which builds `Screen` again.
	private static let fillBuildingScreenAgain = """
	@Instantiable
	public final class Fill: Instantiable, HoleProtocol {
	    public init(ticket: Int, screenBuilder: Instantiator<Screen>) {
	        self.ticket = ticket
	        self.screenBuilder = screenBuilder
	    }

	    @Forwarded let ticket: Int
	    @Instantiated let screenBuilder: Instantiator<Screen>
	}
	"""

	/// The fill of `Screen`'s place, which reads the wrapper `Screen` receives.
	private static let fillReadingWrapper = """
	@Instantiable
	public final class Fill: Instantiable, HoleProtocol {
	    public init(ticket: Int, session: LazilyInstantiated<Session>) {
	        self.ticket = ticket
	        self.session = session
	    }

	    @Forwarded let ticket: Int
	    @Received let session: LazilyInstantiated<Session>
	}
	"""

	/// The fill of `Screen`'s place, which reads nothing.
	private static let fillReadingNothing = """
	@Instantiable
	public final class Fill: Instantiable, HoleProtocol {
	    public init(ticket: Int) {
	        self.ticket = ticket
	    }

	    @Forwarded let ticket: Int
	}
	"""

	/// Holds only `Root`'s screen's place's builder and one value it built, and reports the sessions alive.
	private static let countsWhileHoleBuilderLives = """
	func countsWhileHoleBuilderLives() -> String {
	    var held: (ErasedInstantiator<Int, AnyHole>, AnyHole)?
	    do {
	        let holeBuilder = Root.mock().screen.holeBuilder
	        held = (holeBuilder, holeBuilder.instantiate(7))
	    }
	    return withExtendedLifetime(held) { "Session \\(Session.alive)" }
	}
	"""

	/// Holds only the place's builder of a `Detail` `Root`'s screen built, and one value it built, and reports the sessions alive.
	private static let countsWhileDetailHoleBuilderLives = """
	func countsWhileDetailHoleBuilderLives() -> String {
	    var held: (ErasedInstantiator<Int, AnyHole>, AnyHole)?
	    do {
	        let holeBuilder = Root.mock().screen.detailBuilder.instantiate().holeBuilder
	        held = (holeBuilder, holeBuilder.instantiate(7))
	    }
	    return withExtendedLifetime(held) { "Session \\(Session.alive)" }
	}
	"""

	/// `Feed`, declaring `session` and `screen` beside the hole type, and `App`, of `app`'s files.
	private static func modules(session: String = unbuildableSession, screen: String, app: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feed", packageName: "Feed", swiftFileContent: [
				"import SafeDI\n\n" + [holeType, session, screen].joined(separator: "\n\n"),
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: app.map { "import Feed\nimport SafeDI\n\n" + $0 }, dependencies: ["Feed"]),
		]
	}

	/// What `probe` describes of `modules` built as `output` (the feature path) and of the same files built in one module,
	/// where each public mock is internal (the known-right path).
	private mutating func describedCounts(of modules: [ModuleFixture], output: MultiModuleTestOutput, probe: String) async throws -> (feature: String?, knownRight: String?) {
		let moduleNames = Set(modules.map(\.name))
		var inlineFiles = [String: String]()
		for module in modules {
			for (index, content) in module.swiftFileContent.enumerated() {
				inlineFiles["\(module.name)_File\(index).swift"] = content
					.split(separator: "\n", omittingEmptySubsequences: false)
					.filter { line in !moduleNames.contains { line == "import \($0)" } }
					.joined(separator: "\n")
					.replacingOccurrences(of: "generateMock: .public", with: "generateMock: true")
			}
		}
		let inlineModules = [ModuleFixture(name: "KnownRight", packageName: "KnownRight", swiftFileContentByFilePath: inlineFiles)]
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let feature = try await DifferentialValueOracle.describe(DifferentialValuePath(output: output, modules: modules), probes: [DifferentialValueProbe(probe)], filesToDelete: &filesToDelete)
		let knownRight = try await DifferentialValueOracle.describe(DifferentialValuePath(output: inlineOutput, modules: inlineModules), probes: [DifferentialValueProbe(probe)], filesToDelete: &filesToDelete)
		return (feature, knownRight)
	}
}
