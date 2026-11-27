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

/// A call of another module's public mock, laid out from node records (`NodeRecords+PublicMockCall.swift`): each cell is an
/// internal mock in `App` that calls `Feed`'s public mock, whose bytes equal the walk's, and whose mock root node records lay
/// out. Each refusal cell names the refusal the root's world holds.
struct SafeDIToolNodeRecordsPublicMockCallTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Laid out

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutCallFromNodeRecords_whenConstantCallPassesReceivedValue() async throws {
		let (output, reports) = try await mockOfRoot(
			feed: Self.screen(),
			app: """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(session: Session, screen: Screen) {
			        self.session = session
			        self.screen = screen
			    }

			    @Instantiated let session: Session
			    @Instantiated let screen: Screen
			}
			""",
		)
		#expect(output == generatedFileHeader + """
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
		        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
		        _ = Screen.__safeDI_Screen_mock_53B5F60DA3BBE2A1.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let screen = Screen.__safeDI_mock(session: session, safeDIOverrides: safeDIOverrides.screen)
		        return Root(session: session, screen: screen)
		    }
		}
		#endif
		""")
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutCallFromNodeRecords_whenInstantiatorCallForwardsValue() async throws {
		let (output, reports) = try await mockOfRoot(
			feed: Self.screen(forwardsID: true),
			app: """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(session: Session, screenBuilder: Instantiator<Screen>) {
			        self.session = session
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated let session: Session
			    @Instantiated let screenBuilder: Instantiator<Screen>
			}
			""",
		)
		#expect(output == generatedFileHeader + """
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
		    ) -> Root {
		        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
		        _ = Screen.__safeDI_Screen_mock_B3DFA5A0540208AE.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        func __safeDI_screenBuilder(id: Int) -> Screen {
		            Screen.__safeDI_mock(id: id, session: session, safeDIOverrides: safeDIOverrides.screenBuilder)
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(id: $0)
		        }
		        return Root(session: session, screenBuilder: screenBuilder)
		    }
		}
		#endif
		""")
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	/// The bytes pinned here are the engine's, which lifts every function into the root's body, and differ from the walk's;
	/// the values equal the walk's (`mock_buildsTheWalksValues_whenEveryPlaceOfCallsBeneathRootAndAnotherNodeIsOverridden`).
	/// Only a test lays a mock root out from records (`NodeRecordsObservation.laysOutMockRoots`, with an observer set), so
	/// no run without one writes these bytes.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutCallFromNodeRecords_whenInstantiatorCallIsBuiltBeneathAnotherNode() async throws {
		let (output, reports) = try await mockOfRoot(
			feed: Self.screen(forwardsID: true),
			app: """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(session: Session, middleBuilder: Instantiator<Middle>) {
			        self.session = session
			        self.middleBuilder = middleBuilder
			    }

			    @Instantiated let session: Session
			    @Instantiated let middleBuilder: Instantiator<Middle>
			}

			@Instantiable
			public final class Middle: Instantiable {
			    public init(session: Session, screenBuilder: Instantiator<Screen>) {
			        self.session = session
			        self.screenBuilder = screenBuilder
			    }

			    @Received let session: Session
			    @Instantiated let screenBuilder: Instantiator<Screen>
			}
			""",
		)
		#expect(output == generatedFileHeader + """
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
		            middleBuilder: Middle.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                session: session,
		                middleBuilder: middleBuilder
		            )
		        }

		        var session: (() -> Session)? { __safeDI_storage.session }
		        var middleBuilder: Middle.SafeDIMockConfiguration { __safeDI_storage.middleBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                session: (() -> Session)?,
		                middleBuilder: Middle.SafeDIMockConfiguration
		            ) {
		                self.session = session
		                self.middleBuilder = middleBuilder
		            }

		            let session: (() -> Session)?
		            let middleBuilder: Middle.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
		        _ = Screen.__safeDI_Screen_mock_B3DFA5A0540208AE.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        func __safeDI_screenBuilder(id: Int, safeDIOverrides: Screen.SafeDIOverrides) -> Screen {
		            Screen.__safeDI_mock(id: id, session: session, safeDIOverrides: safeDIOverrides)
		        }
		        func __safeDI_middleBuilder(safeDIOverrides: Middle.SafeDIMockConfiguration) -> Middle {
		            let screenBuilder = Instantiator<Screen> {
		                __safeDI_screenBuilder(id: $0, safeDIOverrides: safeDIOverrides.screenBuilder)
		            }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(session, screenBuilder) } else { Middle(session: session, screenBuilder: screenBuilder) }
		        }
		        let middleBuilder = Instantiator<Middle> {
		            __safeDI_middleBuilder(safeDIOverrides: safeDIOverrides.middleBuilder)
		        }
		        return Root(session: session, middleBuilder: middleBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Middle {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            screenBuilder: Screen.SafeDIOverrides = .init(),
		            _ safeDIBuilder: ((Session, Instantiator<Screen>) -> Middle)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screenBuilder: screenBuilder,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var screenBuilder: Screen.SafeDIOverrides { __safeDI_storage.screenBuilder }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((Session, Instantiator<Screen>) -> Middle)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screenBuilder: Screen.SafeDIOverrides,
		                safeDIBuilder: ((Session, Instantiator<Screen>) -> Middle)?
		            ) {
		                self.screenBuilder = screenBuilder
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let screenBuilder: Screen.SafeDIOverrides
		            let safeDIBuilder: ((Session, Instantiator<Screen>) -> Middle)?
		        }
		    }
		}
		#endif

		""")
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutEachCallFromNodeRecords_whenTwoLabelsCallOneMock() async throws {
		let (output, reports) = try await mockOfRoot(
			feed: Self.screen(),
			app: """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(session: Session, first: Screen, second: Screen) {
			        self.session = session
			        self.first = first
			        self.second = second
			    }

			    @Instantiated let session: Session
			    @Instantiated let first: Screen
			    @Instantiated let second: Screen
			}
			""",
		)
		#expect(output == generatedFileHeader + """
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
		            first: Screen.SafeDIOverrides = .init(),
		            second: Screen.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                session: session,
		                first: first,
		                second: second
		            )
		        }

		        var session: (() -> Session)? { __safeDI_storage.session }
		        var first: Screen.SafeDIOverrides { __safeDI_storage.first }
		        var second: Screen.SafeDIOverrides { __safeDI_storage.second }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                session: (() -> Session)?,
		                first: Screen.SafeDIOverrides,
		                second: Screen.SafeDIOverrides
		            ) {
		                self.session = session
		                self.first = first
		                self.second = second
		            }

		            let session: (() -> Session)?
		            let first: Screen.SafeDIOverrides
		            let second: Screen.SafeDIOverrides
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
		        _ = Screen.__safeDI_Screen_mock_53B5F60DA3BBE2A1.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let first = Screen.__safeDI_mock(session: session, safeDIOverrides: safeDIOverrides.first)
		        _ = Screen.__safeDI_Screen_mock_53B5F60DA3BBE2A1.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let second = Screen.__safeDI_mock(session: session, safeDIOverrides: safeDIOverrides.second)
		        return Root(session: session, first: first, second: second)
		    }
		}
		#endif
		""")
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutCallFromNodeRecords_whenMockPromotesIt() async throws {
		let (output, reports) = try await mockOfRoot(
			feed: Self.screen(),
			app: """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(session: Session, screen: Screen) {
			        self.session = session
			        self.screen = screen
			    }

			    @Instantiated let session: Session
			    @Received let screen: Screen
			}
			""",
		)
		#expect(output == generatedFileHeader + """
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
		        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
		        _ = Screen.__safeDI_Screen_mock_53B5F60DA3BBE2A1.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let screen = Screen.__safeDI_mock(session: session, safeDIOverrides: safeDIOverrides.screen)
		        return Root(session: session, screen: screen)
		    }
		}
		#endif
		""")
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutCallFromNodeRecords_whenCalledMockTakesNoOverrides() async throws {
		let (output, reports) = try await mockOfRoot(
			feed: Self.screen(holdsAnalytics: false, receivesSession: false),
			app: """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(session: Session, screen: Screen) {
			        self.session = session
			        self.screen = screen
			    }

			    @Instantiated let session: Session
			    @Instantiated let screen: Screen
			}
			""",
		)
		#expect(output == generatedFileHeader + """
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
		            screen: (() -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                session: session,
		                screen: screen
		            )
		        }

		        var session: (() -> Session)? { __safeDI_storage.session }
		        var screen: (() -> Screen)? { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                session: (() -> Session)?,
		                screen: (() -> Screen)?
		            ) {
		                self.session = session
		                self.screen = screen
		            }

		            let session: (() -> Session)?
		            let screen: (() -> Screen)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
		        _ = Screen.__safeDI_Screen_mock_CBF29CE484222325.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        let screen = if let safeDIBuilder = safeDIOverrides.screen { safeDIBuilder() } else { Screen.__safeDI_mock() }
		        return Root(session: session, screen: screen)
		    }
		}
		#endif
		""")
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutCallFromNodeRecords_whenInstantiatorCallsMockThatTakesNoOverrides() async throws {
		let (output, reports) = try await mockOfRoot(
			feed: Self.screen(forwardsID: true, holdsAnalytics: false, receivesSession: false),
			app: """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(session: Session, screenBuilder: Instantiator<Screen>) {
			        self.session = session
			        self.screenBuilder = screenBuilder
			    }

			    @Instantiated let session: Session
			    @Instantiated let screenBuilder: Instantiator<Screen>
			}
			""",
		)
		#expect(output == generatedFileHeader + """
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
		            screenBuilder: ((Int) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                session: session,
		                screenBuilder: screenBuilder
		            )
		        }

		        var session: (() -> Session)? { __safeDI_storage.session }
		        var screenBuilder: ((Int) -> Screen)? { __safeDI_storage.screenBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                session: (() -> Session)?,
		                screenBuilder: ((Int) -> Screen)?
		            ) {
		                self.session = session
		                self.screenBuilder = screenBuilder
		            }

		            let session: (() -> Session)?
		            let screenBuilder: ((Int) -> Screen)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
		        _ = Screen.__safeDI_Screen_mock_F04A337DED4167F6.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        func __safeDI_screenBuilder(id: Int) -> Screen {
		            if let safeDIBuilder = safeDIOverrides.screenBuilder { safeDIBuilder(id) } else { Screen.__safeDI_mock(id: id) }
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(id: $0)
		        }
		        return Root(session: session, screenBuilder: screenBuilder)
		    }
		}
		#endif
		""")
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	// MARK: Refused

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_refusesCall_whenCallFillsBuilder() async throws {
		let (_, reports) = try await mockOfRoot(
			feed: Self.screen(holdsService: true),
			app: """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(session: Session, screen: Screen) {
			        self.session = session
			        self.screen = screen
			    }

			    @Instantiated let session: Session
			    @Instantiated let screen: Screen
			}

			@Instantiable(fulfillingAdditionalTypes: [Service.self])
			public final class DefaultService: Service, Instantiable {
			    public init() {}
			}
			""",
		)
		#expect(reports.map(\.refusal) == ["publicMockCallFills"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_refusesCall_whenCallPassesBuilderUp() async throws {
		let (_, reports) = try await mockOfRoot(
			feed: Self.screen(holdsService: true),
			app: """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(session: Session, screen: Screen) {
			        self.session = session
			        self.screen = screen
			    }

			    @Instantiated let session: Session
			    @Instantiated let screen: Screen
			}
			""",
		)
		#expect(reports.map(\.refusal) == ["publicMockCallPassesUp"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_refusesCall_whenCallReceivesValueOnlyIfAvailableMockOverrides() async throws {
		let (_, reports) = try await mockOfRoot(
			feed: Self.screen(receivesSessionOnlyIfAvailable: true),
			app: """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(screen: Screen) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Screen
			}
			""",
		)
		#expect(reports.map(\.refusal) == ["onlyIfAvailable"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_refusesCall_whenRootNamesApartLabelCalledMockReceives() async throws {
		// `Root`’s mock promotes `session` as a `Session` and as a `Token` and names the two apart, so the walk binds the
		// `Session` under its label in the call’s function before the call passes it, which no record of a call makes.
		let (_, reports) = try await mockOfRoot(
			feed: Self.screen(),
			app: """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(plain: Plain, badge: Badge, screen: Screen) {
			        self.plain = plain
			        self.badge = badge
			        self.screen = screen
			    }

			    @Instantiated let plain: Plain
			    @Instantiated let badge: Badge
			    @Instantiated let screen: Screen
			}

			@Instantiable
			public final class Plain: Instantiable {
			    public init(session: Session) {
			        self.session = session
			    }

			    @Received let session: Session
			}

			@Instantiable
			public final class Badge: Instantiable {
			    public init(session: Token) {
			        self.session = session
			    }

			    @Received let session: Token
			}

			@Instantiable
			public final class Token: Instantiable {
			    public init() {}
			}
			""",
		)
		#expect(reports.map(\.refusal) == ["mockOverrideNotParentField"])
	}

	// MARK: Values

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenEveryPlaceOfCallsBeneathRootAndAnotherNodeIsOverridden() async throws {
		let modules = [
			ModuleFixture(name: "Feed", packageName: "feedpkg", swiftFileContentByFilePath: Self.valueFeed),
			ModuleFixture(name: "App", packageName: "apppkg", swiftFileContentByFilePath: Self.valueApp, dependencies: ["Feed"]),
		]
		let walkOutput = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		var filesMade = [URL]()
		let output = try await NodeRecordsObservation.$laysOutMockRoots.withValue(true) {
			try await NodeRecordsObservation.$observer.withValue({ continuation.yield($0) }) {
				try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesMade)
			}
		}
		filesToDelete += filesMade
		continuation.finish()
		var reports = [NodeRecordsReport]()
		for await report in stream where report.isMockRoot && report.root == "Root" {
			reports.append(report)
		}
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		// The call beneath `Middle` is written apart from the walk's, so the comparison is of two programs.
		#expect(output.modules["App"]?.generatedFiles != walkOutput.modules["App"]?.generatedFiles)
		let overridden = """
		Root.mock(safeDIOverrides: .init(\
		session: { marked(Session(), "session") }, \
		panel: .init(analytics: { marked(Analytics(), "panel.analytics") }), \
		screenBuilder: .init(analytics: { marked(Analytics(), "screenBuilder.analytics") }), \
		middleBuilder: .init(screenBuilder: .init(analytics: { marked(Analytics(), "middleBuilder.screenBuilder.analytics") }))\
		))
		"""
		let overriddenMiddle = """
		Root.mock(safeDIOverrides: .init(\
		middleBuilder: .init({ marked(Middle(session: $0, screenBuilder: $1), "middleBuilder") })\
		))
		"""
		let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: walkOutput, modules: modules),
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe("Root.mock().screenBuilder.instantiate(1)"),
				DifferentialValueProbe("Root.mock().middleBuilder.instantiate().screenBuilder.instantiate(2)"),
				DifferentialValueProbe(name: "overridden root", expression: overridden),
				DifferentialValueProbe(name: "overridden screenBuilder", expression: "\(overridden).screenBuilder.instantiate(1)"),
				DifferentialValueProbe(name: "overridden middleBuilder", expression: "\(overridden).middleBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden middleBuilder's screenBuilder", expression: "\(overridden).middleBuilder.instantiate().screenBuilder.instantiate(2)"),
				DifferentialValueProbe(name: "overridden middle", expression: "\(overriddenMiddle).middleBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden middle's screenBuilder", expression: "\(overriddenMiddle).middleBuilder.instantiate().screenBuilder.instantiate(3)"),
			],
			filesToDelete: &filesToDelete,
		)
		// Nothing is compared where compile verification is off.
		guard let comparison else { return }
		#expect(comparison.differences.isEmpty, "\(comparison.report)")
		// Every override was read: each marks the value its closure built.
		for marker in ["session", "panel.analytics", "screenBuilder.analytics", "middleBuilder.screenBuilder.analytics", "middleBuilder"] {
			#expect(comparison.featureDescription.contains("\"\(marker)\""), "No value is marked \(marker):\n\(comparison.featureDescription)")
		}
	}

	// MARK: Fixtures

	/// `Feed`'s `Screen`, whose public mock `App` calls since its initializer is `internal`: it receives `session`, and
	/// instantiates `analytics`, so its mock takes `SafeDIOverrides`; with neither, its mock takes none.
	private static func screen(forwardsID: Bool = false, holdsService: Bool = false, receivesSessionOnlyIfAvailable: Bool = false, holdsAnalytics: Bool = true, receivesSession: Bool = true) -> String {
		var parameters = [String]()
		var assignments = [String]()
		var properties = [String]()
		if forwardsID {
			parameters.append("id: Int")
			assignments.append("self.id = id")
			properties.append("@Forwarded let id: Int")
		}
		if receivesSession {
			parameters.append(receivesSessionOnlyIfAvailable ? "session: Session?" : "session: Session")
			assignments.append("self.session = session")
			properties.append(receivesSessionOnlyIfAvailable ? "@Received(onlyIfAvailable: true) let session: Session?" : "@Received let session: Session")
		}
		if holdsAnalytics {
			parameters.append("analytics: Analytics")
			assignments.append("self.analytics = analytics")
			properties.append("@Instantiated let analytics: Analytics")
		}
		if holdsService {
			parameters.append("service: Service")
			assignments.append("self.service = service")
			properties.append("@Instantiated let service: Service")
		}
		return """
		import SafeDI

		@Instantiable
		public final class Session: Instantiable {
		    public init() {}
		}

		@Instantiable
		public final class Analytics: Instantiable {
		    public init() {}
		}
		\(holdsService ? "\npublic protocol Service {}\n" : "")
		@Instantiable(generateMock: .public)
		public final class Screen: Instantiable {
		    init(\(parameters.joined(separator: ", "))) {
		        \(assignments.joined(separator: "\n        "))
		    }

		    \(properties.joined(separator: "\n    "))
		}
		"""
	}

	/// `App`'s generated mock file, and the report of each mock root of `App`.
	private mutating func mockOfRoot(feed: String, app: String) async throws -> (String?, [NodeRecordsReport]) {
		let modules = [
			ModuleFixture(name: "Feed", packageName: "feedpkg", swiftFileContentByFilePath: ["Screen.swift": feed]),
			ModuleFixture(name: "App", packageName: "apppkg", swiftFileContentByFilePath: ["Root.swift": "import Feed\nimport SafeDI\n\n" + app], dependencies: ["Feed"]),
		]
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		let output = try await NodeRecordsObservation.$laysOutMockRoots.withValue(true) {
			try await NodeRecordsObservation.$laysOutRoots.withValue(true) {
				try await NodeRecordsObservation.$observer.withValue({ continuation.yield($0) }) {
					try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesMade)
				}
			}
		}
		continuation.finish()
		var reports = [NodeRecordsReport]()
		for await report in stream where report.isMockRoot && report.root == "Root" {
			reports.append(report)
		}
		return (output.modules["App"]?.generatedFiles.values.first, reports)
	}

	/// `Feed` of the value test: `Panel` and `Screen`, whose public mocks `App` calls, each receive `session` and instantiate
	/// `analytics`, and `Screen` forwards `id`. Each type carries a marker an override's closure sets.
	private static let valueFeed: [String: String] = [
		"Marked.swift": """
		public protocol Marked: AnyObject {
		    var marker: String { get set }
		}

		public func marked<Value: Marked>(_ value: Value, _ marker: String) -> Value {
		    value.marker = marker
		    return value
		}
		""",
		"Screen.swift": """
		import SafeDI

		@Instantiable
		public final class Session: Instantiable, Marked {
		    public init() {}

		    public var marker = "built"
		}

		@Instantiable
		public final class Analytics: Instantiable, Marked {
		    public init() {}

		    public var marker = "built"
		}

		@Instantiable(generateMock: .public)
		public final class Panel: Instantiable, Marked {
		    init(session: Session, analytics: Analytics) {
		        self.session = session
		        self.analytics = analytics
		    }

		    @Received let session: Session
		    @Instantiated let analytics: Analytics
		    public var marker = "built"
		}

		@Instantiable(generateMock: .public)
		public final class Screen: Instantiable, Marked {
		    init(id: Int, session: Session, analytics: Analytics) {
		        self.id = id
		        self.session = session
		        self.analytics = analytics
		    }

		    @Forwarded let id: Int
		    @Received let session: Session
		    @Instantiated let analytics: Analytics
		    public var marker = "built"
		}
		""",
	]

	/// `App` of the value test: `Root` calls `Panel`'s public mock as a constant, and `Screen`'s from an `Instantiator` and
	/// from an `Instantiator` inside `Middle`'s.
	private static let valueApp: [String: String] = [
		"Root.swift": """
		import Feed
		import SafeDI

		@Instantiable(generateMock: true)
		public final class Root: Instantiable {
		    public init(session: Session, panel: Panel, screenBuilder: Instantiator<Screen>, middleBuilder: Instantiator<Middle>) {
		        self.session = session
		        self.panel = panel
		        self.screenBuilder = screenBuilder
		        self.middleBuilder = middleBuilder
		    }

		    @Instantiated let session: Session
		    @Instantiated let panel: Panel
		    @Instantiated let screenBuilder: Instantiator<Screen>
		    @Instantiated let middleBuilder: Instantiator<Middle>
		}

		@Instantiable
		public final class Middle: Instantiable, Marked {
		    public init(session: Session, screenBuilder: Instantiator<Screen>) {
		        self.session = session
		        self.screenBuilder = screenBuilder
		    }

		    @Received let session: Session
		    @Instantiated let screenBuilder: Instantiator<Screen>
		    public var marker = "built"
		}
		""",
	]

	private var filesToDelete: [URL]
}
