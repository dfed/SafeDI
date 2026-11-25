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

/// A calling mock whose fill of a called public mock’s place holds a builder of the called type, which receives a value
/// only if available, which the caller holds. The call inside the fill re-enters the called type, and hands it the
/// caller’s value, as the same types built inline do.
struct SafeDIToolCallingMockOnlyIfAvailableReentryTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test(arguments: GraphFuzzerCallingMockCell.Caller.allCases, SessionForm.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsReenteredCalledTypeCallersValue_whenCalledTypeReceivesValueOnlyIfAvailable(caller: GraphFuzzerCallingMockCell.Caller, session: SessionForm) async throws {
		// `Screen`, a public mock of `Feed`, receives `session` only if available, and `Fill`, which fills its place, holds an
		// `Instantiator<Screen>`. `Root` holds `session` as `session` spells it. The call of `Screen` inside the fill hands it
		// the caller’s value, as inline hands the `Screen` it builds again the caller’s `session`.
		let graph = Self.graph(caller: caller, session: session)
		let modules = graph.modules(.mock)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": Self.expectedFeed(of: session)])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": Self.expectedApp(of: session, caller: caller)])
		if compileVerificationIsEnabled {
			try await expectCompilesAndBuildsInlineValues(of: graph, output: output, modules: modules, probes: [Self.probe(of: session)])
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// How `Screen` receives `session`, and `Root` holds it.
	enum SessionForm: CaseIterable {
		/// `Root` holds `LazilyInstantiated<Session>`, which `Screen` receives as `LazilyInstantiated<Session>?`.
		case lazilyInstantiated
		/// `Root` holds `SendableLazilyInstantiated<Session>`, which `Screen` receives as
		/// `SendableLazilyInstantiated<Session>?`.
		case sendableLazilyInstantiated
		/// `Root` holds `Session`, which `Screen` receives as `Session?`.
		case value

		/// How `Root` declares `session`.
		var held: String {
			switch self {
			case .lazilyInstantiated:
				"LazilyInstantiated<Session>"
			case .sendableLazilyInstantiated:
				"SendableLazilyInstantiated<Session>"
			case .value:
				"Session"
			}
		}

		/// What reads the instance of `session` where a type holds it as `held`.
		var instance: String {
			switch self {
			case .lazilyInstantiated, .sendableLazilyInstantiated:
				".instance"
			case .value:
				""
			}
		}

		/// What reads the instance of `session` where a type holds it as the optional of `held`.
		var optionalInstance: String {
			switch self {
			case .lazilyInstantiated, .sendableLazilyInstantiated:
				"?.instance"
			case .value:
				""
			}
		}
	}

	/// The graph: module `Feed` declares `Session`, which `App` declares instantiable, and `Screen`, a public mock that
	/// receives `session` only if available and whose place of `AnyHole` no type `Feed` sees fulfills; module `App` declares
	/// `Fill`, which fills it and holds an `Instantiator<Screen>`, and the caller `Root`, which builds `Screen` and `session`.
	private static func graph(caller: GraphFuzzerCallingMockCell.Caller, session: SessionForm) -> GraphFuzzerCallingMockGraph {
		func feed(attribute: String) -> String {
			"""
			import SafeDI

			public protocol HoleProtocol {}

			public struct AnyHole: HoleProtocol {
			    public init(_ value: any HoleProtocol) { self.value = value }
			    public let value: any HoleProtocol
			}

			public final class Session: Instantiable, Sendable {
			    public init() {}
			}

			\(attribute)
			public final class Screen: Instantiable {
			    init(session: \(session.held)?, holeBuilder: ErasedInstantiator<Int, AnyHole>) {
			        self.session = session
			        self.holeBuilder = holeBuilder
			    }

			    @Received(onlyIfAvailable: true) public let session: \(session.held)?
			    @Instantiated(fulfilledByType: "Fill", erasedToConcreteExistential: true) public let holeBuilder: ErasedInstantiator<Int, AnyHole>
			}

			"""
		}
		func app(attribute: String) -> String {
			"""
			import Feed
			import SafeDI

			@Instantiable(conformsElsewhere: true)
			extension Session {
			    public static func instantiate() -> Session { Session() }
			}

			@Instantiable
			public final class Fill: Instantiable, HoleProtocol {
			    public init(ticket: Int, screenBuilder: Instantiator<Screen>) {
			        self.ticket = ticket
			        self.screenBuilder = screenBuilder
			    }

			    @Forwarded public let ticket: Int
			    @Instantiated public let screenBuilder: Instantiator<Screen>
			}

			\(attribute)
			public final class Root: Instantiable {
			    public init(screen: Screen, session: \(session.held)) {
			        self.screen = screen
			        self.session = session
			    }

			    @Instantiated public let screen: Screen
			    @Instantiated public let session: \(session.held)
			}

			"""
		}
		return GraphFuzzerCallingMockGraph(
			name: "a fill that re-enters a called type that receives the caller’s value only if available",
			mockFiles: [
				GraphFuzzerCallingMockGraph.File(module: "Feed", dependencies: [], content: feed(attribute: "@Instantiable(generateMock: .public)")),
				GraphFuzzerCallingMockGraph.File(module: "App", dependencies: ["Feed"], content: app(attribute: callerAttribute(of: caller))),
			],
			twinFiles: [
				GraphFuzzerCallingMockGraph.File(module: "Feed", dependencies: [], content: feed(attribute: "@Instantiable(generateDependencyTree: true, generateMock: .public)")),
				GraphFuzzerCallingMockGraph.File(module: "App", dependencies: ["Feed"], content: app(attribute: "@Instantiable(generateDependencyTree: true)")),
			],
			callerTypeName: "Root",
			callerIsPublic: caller == .public,
			mockConfiguration: caller == .listed ? "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Root\"])\n" : nil,
			flatParameterLabels: [],
			implementationIsVisible: true,
			expectedTwinInitializerLabels: [],
			expectedPassUpLabels: [],
			expectedTwinErrorSite: nil,
			valueProbes: nil,
		)
	}

	/// What a cell compares: whether the `Screen` the root builds, and the `Screen` the fill builds again, hold the
	/// caller’s instance of `session`. The probe compares instances, which a wrapper the mock passes through and the
	/// wrapper inline hands on share.
	private static func probe(of session: SessionForm) -> DifferentialValueProbe {
		let read = { (root: String) in
			"{ let root = \(root); let fill = root.screen.holeBuilder.instantiate(7).value as! App.Fill; let again = fill.screenBuilder.instantiate(); return (root.screen.session\(session.optionalInstance) === root.session\(session.instance), again.session\(session.optionalInstance) === root.session\(session.instance)) }()"
		}
		return DifferentialValueProbe(name: "(the root’s Screen holds the caller’s session, the Screen the fill builds again holds it)", expression: read("App.Root.mock()"), knownRightExpression: read("App.Root()"))
	}

	/// The file the tool generates for `Feed` where `Screen` receives `session` as `session` spells it, for every caller kind.
	private static func expectedFeed(of session: SessionForm) -> String {
		switch session {
		case .lazilyInstantiated:
			generatedFileHeader + """
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
			                self.init(holeBuilder: { _ in __safeDI_builder })
			            }
			        }
			    }

			    public static func mock(
			        fill_AnyHoleBuilder: @escaping ErasedInstantiator<Int, AnyHole>.Builder,
			        session: LazilyInstantiated<Session>? = nil
			    ) -> Screen {
			        Screen.__safeDI_mock(fill_AnyHoleBuilder: .init(__safeDI_noScope: fill_AnyHoleBuilder), session: session)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        fill_AnyHoleBuilder __safeDI_fill_AnyHoleBuilder: Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole>,
			        session: LazilyInstantiated<Session>? = nil
			    ) -> Screen {
			        let holeBuilder = ErasedInstantiator<Int, AnyHole>(__safeDI_fill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_Fill_AnyHole.holeBuilder_Values(session: session)))
			        return Screen(session: session, holeBuilder: holeBuilder)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_8C12403263F5CE07 {}
			}
			#endif
			"""
		case .sendableLazilyInstantiated:
			generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Fill_AnyHole {
			        nonisolated public struct holeBuilder_Values {
			            public let session: SendableLazilyInstantiated<Session>?
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

			            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
			                self.holeBuilder = holeBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
			                self.init(holeBuilder: { _ in __safeDI_builder })
			            }
			        }
			    }

			    public static func mock(
			        fill_AnyHoleBuilder: @escaping ErasedInstantiator<Int, AnyHole>.Builder,
			        session: SendableLazilyInstantiated<Session>? = nil
			    ) -> Screen {
			        Screen.__safeDI_mock(fill_AnyHoleBuilder: .init(__safeDI_noScope: fill_AnyHoleBuilder), session: session)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        fill_AnyHoleBuilder __safeDI_fill_AnyHoleBuilder: Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole>,
			        session: SendableLazilyInstantiated<Session>? = nil
			    ) -> Screen {
			        let holeBuilder = ErasedInstantiator<Int, AnyHole>(__safeDI_fill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_Fill_AnyHole.holeBuilder_Values(session: session)))
			        return Screen(session: session, holeBuilder: holeBuilder)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_995A5C40716021DB {}
			}
			#endif
			"""
		case .value:
			generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Screen {
			    nonisolated public enum SafeDIMockScope_Fill_AnyHole {
			        nonisolated public struct holeBuilder_Values {
			            public let session: Session?
			        }

			        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
			            public let holeBuilder: (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

			            public init(holeBuilder: @escaping (holeBuilder_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
			                self.holeBuilder = holeBuilder
			            }

			            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
			                self.init(holeBuilder: { _ in __safeDI_builder })
			            }
			        }
			    }

			    public static func mock(
			        fill_AnyHoleBuilder: @escaping ErasedInstantiator<Int, AnyHole>.Builder,
			        session: Session? = nil
			    ) -> Screen {
			        Screen.__safeDI_mock(fill_AnyHoleBuilder: .init(__safeDI_noScope: fill_AnyHoleBuilder), session: session)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        fill_AnyHoleBuilder __safeDI_fill_AnyHoleBuilder: Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole>,
			        session: Session? = nil
			    ) -> Screen {
			        let holeBuilder = ErasedInstantiator<Int, AnyHole>(__safeDI_fill_AnyHoleBuilder.holeBuilder(SafeDIMockScope_Fill_AnyHole.holeBuilder_Values(session: session)))
			        return Screen(session: session, holeBuilder: holeBuilder)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_mock_FD6673438122BD73 {}
			}
			#endif
			"""
		}
	}

	/// The file the tool generates for `App` where `Root` holds `session` as `session` spells it and `caller` asks for its mock.
	private static func expectedApp(of session: SessionForm, caller: GraphFuzzerCallingMockCell.Caller) -> String {
		switch (caller, session) {
		case (.internal, .lazilyInstantiated), (.listed, .lazilyInstantiated):
			generatedFileHeader + """
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
			            screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, LazilyInstantiated<Session>?) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screen: screen
			            )
			        }

			        var session: (() -> Session)? { __safeDI_storage.session }
			        var screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, LazilyInstantiated<Session>?) -> Screen)? { __safeDI_storage.screen }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?,
			                screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, LazilyInstantiated<Session>?) -> Screen)?
			            ) {
			                self.session = session
			                self.screen = screen
			            }

			            let session: (() -> Session)?
			            let screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, LazilyInstantiated<Session>?) -> Screen)?
			        }
			    }

			    static func mock(
			        fill_AnyHoleBuilder: ErasedInstantiator<Int, AnyHole>.Builder? = nil,
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
			                        Screen.__safeDI_mock(fill_AnyHoleBuilder: fill_AnyHoleBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_fill_AnyHoleBuilder_Screen(), session: session)
			                    }
			                    let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			                    return Fill(ticket: ticket, screenBuilder: screenBuilder)
			                }
			                return { forwarded in AnyHole(__safeDI_holeBuilder(ticket: forwarded)) }
			            }
			            func __safeDI_fill_AnyHoleBuilder_Screen() -> Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole> {
			                .init(holeBuilder: { values in __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: values.session) })
			            }
			            _ = Screen.__safeDI_Screen_mock_8C12403263F5CE07.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Screen", declaringModule: "Feed"))
			            return if let safeDIBuilder = safeDIOverrides.screen { safeDIBuilder(fill_AnyHoleBuilder ?? __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: session), session) } else { Screen.__safeDI_mock(fill_AnyHoleBuilder: fill_AnyHoleBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_fill_AnyHoleBuilder_Screen(), session: session) }
			        }
			        let screen: Screen = __safeDI_screen()
			        return Root(screen: screen, session: session)
			    }
			}
			#endif
			"""
		case (.public, .lazilyInstantiated):
			generatedFileHeader + """
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
			            session: (() -> Session)? = nil,
			            screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, LazilyInstantiated<Session>?) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screen: screen
			            )
			        }

			        public var session: (() -> Session)? { __safeDI_storage.session }
			        public var screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, LazilyInstantiated<Session>?) -> Screen)? { __safeDI_storage.screen }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?,
			                screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, LazilyInstantiated<Session>?) -> Screen)?
			            ) {
			                self.session = session
			                self.screen = screen
			            }

			            let session: (() -> Session)?
			            let screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, LazilyInstantiated<Session>?) -> Screen)?
			        }
			    }

			    public static func mock(
			        fill_AnyHoleBuilder: ErasedInstantiator<Int, AnyHole>.Builder? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        Root.__safeDI_mock(fill_AnyHoleBuilder: fill_AnyHoleBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        fill_AnyHoleBuilder __safeDI_fill_AnyHoleBuilder: ErasedInstantiator<Int, AnyHole>.Builder? = nil,
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
			                        Screen.__safeDI_mock(fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_fill_AnyHoleBuilder_Screen(), session: session)
			                    }
			                    let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			                    return Fill(ticket: ticket, screenBuilder: screenBuilder)
			                }
			                return { forwarded in AnyHole(__safeDI_holeBuilder(ticket: forwarded)) }
			            }
			            func __safeDI_fill_AnyHoleBuilder_Screen() -> Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole> {
			                .init(holeBuilder: { values in __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: values.session) })
			            }
			            _ = Screen.__safeDI_Screen_mock_8C12403263F5CE07.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Screen", declaringModule: "Feed"))
			            return if let safeDIBuilder = safeDIOverrides.screen { safeDIBuilder(__safeDI_fill_AnyHoleBuilder ?? __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: session), session) } else { Screen.__safeDI_mock(fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_fill_AnyHoleBuilder_Screen(), session: session) }
			        }
			        let screen: Screen = __safeDI_screen()
			        return Root(screen: screen, session: session)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_E88E2171F0BB9CD0 {}
			}
			#endif
			"""
		case (.internal, .sendableLazilyInstantiated), (.listed, .sendableLazilyInstantiated):
			generatedFileHeader + """
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
			            session: (@Sendable () -> Session)? = nil,
			            screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, SendableLazilyInstantiated<Session>?) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screen: screen
			            )
			        }

			        var session: (@Sendable () -> Session)? { __safeDI_storage.session }
			        var screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, SendableLazilyInstantiated<Session>?) -> Screen)? { __safeDI_storage.screen }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (@Sendable () -> Session)?,
			                screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, SendableLazilyInstantiated<Session>?) -> Screen)?
			            ) {
			                self.session = session
			                self.screen = screen
			            }

			            let session: (@Sendable () -> Session)?
			            let screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, SendableLazilyInstantiated<Session>?) -> Screen)?
			        }
			    }

			    static func mock(
			        fill_AnyHoleBuilder: ErasedInstantiator<Int, AnyHole>.Builder? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let __safeDI_session__safeDIBuilder = safeDIOverrides.session
			        @Sendable nonisolated func __safeDI_session() -> Session {
			            if let safeDIBuilder = __safeDI_session__safeDIBuilder { safeDIBuilder() } else { Session.instantiate() }
			        }
			        let session = SendableLazilyInstantiated<Session>(__safeDI_session)
			        func __safeDI_screen() -> Screen {
			            func __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: SendableLazilyInstantiated<Session>?) -> ErasedInstantiator<Int, AnyHole>.Builder {
			                func __safeDI_holeBuilder(ticket: Int) -> Fill {
			                    func __safeDI_screenBuilder() -> Screen {
			                        Screen.__safeDI_mock(fill_AnyHoleBuilder: fill_AnyHoleBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_fill_AnyHoleBuilder_Screen(), session: session)
			                    }
			                    let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			                    return Fill(ticket: ticket, screenBuilder: screenBuilder)
			                }
			                return { forwarded in AnyHole(__safeDI_holeBuilder(ticket: forwarded)) }
			            }
			            func __safeDI_fill_AnyHoleBuilder_Screen() -> Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole> {
			                .init(holeBuilder: { values in __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: values.session) })
			            }
			            _ = Screen.__safeDI_Screen_mock_995A5C40716021DB.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Screen", declaringModule: "Feed"))
			            return if let safeDIBuilder = safeDIOverrides.screen { safeDIBuilder(fill_AnyHoleBuilder ?? __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: session), session) } else { Screen.__safeDI_mock(fill_AnyHoleBuilder: fill_AnyHoleBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_fill_AnyHoleBuilder_Screen(), session: session) }
			        }
			        let screen: Screen = __safeDI_screen()
			        return Root(screen: screen, session: session)
			    }
			}
			#endif
			"""
		case (.public, .sendableLazilyInstantiated):
			generatedFileHeader + """
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
			            session: (@Sendable () -> Session)? = nil,
			            screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, SendableLazilyInstantiated<Session>?) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screen: screen
			            )
			        }

			        public var session: (@Sendable () -> Session)? { __safeDI_storage.session }
			        public var screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, SendableLazilyInstantiated<Session>?) -> Screen)? { __safeDI_storage.screen }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (@Sendable () -> Session)?,
			                screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, SendableLazilyInstantiated<Session>?) -> Screen)?
			            ) {
			                self.session = session
			                self.screen = screen
			            }

			            let session: (@Sendable () -> Session)?
			            let screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, SendableLazilyInstantiated<Session>?) -> Screen)?
			        }
			    }

			    public static func mock(
			        fill_AnyHoleBuilder: ErasedInstantiator<Int, AnyHole>.Builder? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        Root.__safeDI_mock(fill_AnyHoleBuilder: fill_AnyHoleBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        fill_AnyHoleBuilder __safeDI_fill_AnyHoleBuilder: ErasedInstantiator<Int, AnyHole>.Builder? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let __safeDI_session__safeDIBuilder = safeDIOverrides.session
			        @Sendable nonisolated func __safeDI_session() -> Session {
			            if let safeDIBuilder = __safeDI_session__safeDIBuilder { safeDIBuilder() } else { Session.instantiate() }
			        }
			        let session = SendableLazilyInstantiated<Session>(__safeDI_session)
			        func __safeDI_screen() -> Screen {
			            func __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: SendableLazilyInstantiated<Session>?) -> ErasedInstantiator<Int, AnyHole>.Builder {
			                func __safeDI_holeBuilder(ticket: Int) -> Fill {
			                    func __safeDI_screenBuilder() -> Screen {
			                        Screen.__safeDI_mock(fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_fill_AnyHoleBuilder_Screen(), session: session)
			                    }
			                    let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			                    return Fill(ticket: ticket, screenBuilder: screenBuilder)
			                }
			                return { forwarded in AnyHole(__safeDI_holeBuilder(ticket: forwarded)) }
			            }
			            func __safeDI_fill_AnyHoleBuilder_Screen() -> Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole> {
			                .init(holeBuilder: { values in __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: values.session) })
			            }
			            _ = Screen.__safeDI_Screen_mock_995A5C40716021DB.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Screen", declaringModule: "Feed"))
			            return if let safeDIBuilder = safeDIOverrides.screen { safeDIBuilder(__safeDI_fill_AnyHoleBuilder ?? __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: session), session) } else { Screen.__safeDI_mock(fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_fill_AnyHoleBuilder_Screen(), session: session) }
			        }
			        let screen: Screen = __safeDI_screen()
			        return Root(screen: screen, session: session)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_E88E2171F0BB9CD0 {}
			}
			#endif
			"""
		case (.internal, .value), (.listed, .value):
			generatedFileHeader + """
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
			        fill_AnyHoleBuilder: ErasedInstantiator<Int, AnyHole>.Builder? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
			        func __safeDI_screen() -> Screen {
			            func __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: Session?) -> ErasedInstantiator<Int, AnyHole>.Builder {
			                func __safeDI_holeBuilder(ticket: Int) -> Fill {
			                    func __safeDI_screenBuilder() -> Screen {
			                        Screen.__safeDI_mock(fill_AnyHoleBuilder: fill_AnyHoleBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_fill_AnyHoleBuilder_Screen(), session: session)
			                    }
			                    let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			                    return Fill(ticket: ticket, screenBuilder: screenBuilder)
			                }
			                return { forwarded in AnyHole(__safeDI_holeBuilder(ticket: forwarded)) }
			            }
			            func __safeDI_fill_AnyHoleBuilder_Screen() -> Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole> {
			                .init(holeBuilder: { values in __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: values.session) })
			            }
			            _ = Screen.__safeDI_Screen_mock_FD6673438122BD73.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Screen", declaringModule: "Feed"))
			            return if let safeDIBuilder = safeDIOverrides.screen { safeDIBuilder(fill_AnyHoleBuilder ?? __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: session), session) } else { Screen.__safeDI_mock(fill_AnyHoleBuilder: fill_AnyHoleBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_fill_AnyHoleBuilder_Screen(), session: session) }
			        }
			        let screen: Screen = __safeDI_screen()
			        return Root(screen: screen, session: session)
			    }
			}
			#endif
			"""
		case (.public, .value):
			generatedFileHeader + """
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
			            session: (() -> Session)? = nil,
			            screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, Session?) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screen: screen
			            )
			        }

			        public var session: (() -> Session)? { __safeDI_storage.session }
			        public var screen: ((@escaping ErasedInstantiator<Int, AnyHole>.Builder, Session?) -> Screen)? { __safeDI_storage.screen }

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

			    public static func mock(
			        fill_AnyHoleBuilder: ErasedInstantiator<Int, AnyHole>.Builder? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        Root.__safeDI_mock(fill_AnyHoleBuilder: fill_AnyHoleBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        fill_AnyHoleBuilder __safeDI_fill_AnyHoleBuilder: ErasedInstantiator<Int, AnyHole>.Builder? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session.instantiate() }
			        func __safeDI_screen() -> Screen {
			            func __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: Session?) -> ErasedInstantiator<Int, AnyHole>.Builder {
			                func __safeDI_holeBuilder(ticket: Int) -> Fill {
			                    func __safeDI_screenBuilder() -> Screen {
			                        Screen.__safeDI_mock(fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_fill_AnyHoleBuilder_Screen(), session: session)
			                    }
			                    let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			                    return Fill(ticket: ticket, screenBuilder: screenBuilder)
			                }
			                return { forwarded in AnyHole(__safeDI_holeBuilder(ticket: forwarded)) }
			            }
			            func __safeDI_fill_AnyHoleBuilder_Screen() -> Screen.SafeDIMockScope_Fill_AnyHole.__safeDI_Builder<AnyHole> {
			                .init(holeBuilder: { values in __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: values.session) })
			            }
			            _ = Screen.__safeDI_Screen_mock_FD6673438122BD73.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "Screen", declaringModule: "Feed"))
			            return if let safeDIBuilder = safeDIOverrides.screen { safeDIBuilder(__safeDI_fill_AnyHoleBuilder ?? __safeDI_fill_AnyHoleBuilder_Screen_holeBuilder(session: session), session) } else { Screen.__safeDI_mock(fill_AnyHoleBuilder: __safeDI_fill_AnyHoleBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_fill_AnyHoleBuilder_Screen(), session: session) }
			        }
			        let screen: Screen = __safeDI_screen()
			        return Root(screen: screen, session: session)
			    }
			}

			extension Root {
			    public enum __safeDI_Root_mock_E88E2171F0BB9CD0 {}
			}
			#endif
			"""
		}
	}

	private static func callerAttribute(of caller: GraphFuzzerCallingMockCell.Caller) -> String {
		switch caller {
		case .internal:
			"@Instantiable(generateMock: true)"
		case .public:
			"@Instantiable(generateMock: .public)"
		case .listed:
			"@Instantiable"
		}
	}

	/// Expects the calling mock `output`, generated for `modules` and compiled, to have compiled, and to build for each of
	/// `probes` what the same types built inline build (`GraphFuzzerCallingMockGraph.inlineModules`). A module that does not
	/// compile is recorded as `verifyGeneratedCodeCompiles` records it, and nothing is compared.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectCompilesAndBuildsInlineValues(of graph: GraphFuzzerCallingMockGraph, output: MultiModuleTestOutput, modules: [ModuleFixture], probes: [DifferentialValueProbe], sourceLocation: SourceLocation = #_sourceLocation) async throws {
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		if let failure = compilation.failure {
			failure.recordIssues(skippingVerificationBy: "pass `compileVerification: .skipped`", sourceLocation: sourceLocation)
		} else {
			let inlineModules = graph.inlineModules
			let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
			let comparison = try #require(try await DifferentialValueOracle.compare(
				feature: DifferentialValuePath(output: output, modules: modules),
				knownRight: DifferentialValuePath(output: inlineOutput, modules: inlineModules),
				probes: probes,
				filesToDelete: &filesToDelete,
			), sourceLocation: sourceLocation)
			for difference in comparison.differences {
				Issue.record("The calling mock builds other values than inline for \(difference)\n\(comparison.report)", sourceLocation: sourceLocation)
			}
		}
	}
}
