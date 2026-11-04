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
@testable import SafeDITool

/// A type built again through a lazy cycle receives each label from the nearest declaration above it, as every other
/// `@Received` property does: a scope between the cycle-closing scope and the scope it closes on that declares a label
/// the cycle's tree receives from above hands its own value. The builder function the cycle closes on takes such labels
/// as parameters, the scope that declares it passes its own bindings, and each cycle-closing scope passes its nearest
/// declarations. Each generated tree is compared by value with a tree built by hand to the same rule.
struct SafeDIToolLazyCycleNearestDeclarationTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – The nearest declaration's value

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearestConstant_whenScopeBetweenCycleClosingScopeAndClosedOnScopeDeclaresIt() async throws {
		// A flow instantiates a per-step session: the screen a step builds again receives the step's session, not the app's,
		// and so does the screen's alias of it.
		let fixture = [
			seamFixtureType(named: "App", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"]),
			seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Received let session: Session", #"@Received(fulfilledByDependencyNamed: "session", ofType: Session.self) let currentSession: Session"#, "@Instantiated let stepBuilder: Instantiator<Step>"]),
			seamFixtureType(named: "Step", isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"]),
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
		]
		try await expectGeneratedTree(of: fixture, root: "App", equals: { fixtures in """
		extension App {
		    public convenience init() {
		        let session = Session()
		        func __safeDI_screenBuilder(session: Session) -> Screen {
		            #sourceLocation(file: "\(fixtures["Screen.swift"])", line: 10)
		            let currentSession: Session = session
		            #sourceLocation()
		            func __safeDI_stepBuilder() -> Step {
		                let session = Session()
		                let screenBuilder = Instantiator<Screen> {
		                    __safeDI_screenBuilder(session: session)
		                }
		                return Step(session: session, screenBuilder: screenBuilder)
		            }
		            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
		            return Screen(session: session, currentSession: currentSession, stepBuilder: stepBuilder)
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(session: session)
		        }
		        self.init(session: session, screenBuilder: screenBuilder)
		    }
		}
		""" }, buildsTheSameValuesAs: """
		extension App {
		    public convenience init() {
		        func screen(session: Session) -> Screen {
		            Screen(session: session, currentSession: session, stepBuilder: Instantiator<Step> {
		                let stepSession = Session()
		                return Step(session: stepSession, screenBuilder: Instantiator<Screen> { screen(session: stepSession) })
		            })
		        }
		        let session = Session()
		        self.init(session: session, screenBuilder: Instantiator<Screen> { screen(session: session) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearestInstantiator_whenScopeBetweenCycleClosingScopeAndClosedOnScopeDeclaresIt() async throws {
		try await expectGeneratedTree(of: Self.instantiatorCycleFixture(t0Declares: "@Instantiated let t1Builder: Instantiator<T1>"), root: "Root", equals: """
		extension Root {
		    public convenience init() {
		        func __safeDI_t1Builder() -> T1 {
		            T1()
		        }
		        let t1Builder = Instantiator<T1>(__safeDI_t1Builder)
		        func __safeDI_t3Builder(t1Builder: Instantiator<T1>) -> T3 {
		            func __safeDI_t0Builder() -> T0 {
		                func __safeDI_t1Builder() -> T1 {
		                    T1()
		                }
		                let t1Builder = Instantiator<T1>(__safeDI_t1Builder)
		                let t3Builder = Instantiator<T3> {
		                    __safeDI_t3Builder(t1Builder: t1Builder)
		                }
		                return T0(t1Builder: t1Builder, t3Builder: t3Builder)
		            }
		            let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
		            return T3(t0Builder: t0Builder, t1Builder: t1Builder)
		        }
		        let t3Builder = Instantiator<T3> {
		            __safeDI_t3Builder(t1Builder: t1Builder)
		        }
		        self.init(t1Builder: t1Builder, t3Builder: t3Builder)
		    }
		}
		""", buildsTheSameValuesAs: Self.handBuiltInstantiatorCycle(name: "Root", returning: "self.init"))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearestLazilyInstantiatedInstance_whenScopeBetweenDeclaresWrapperOfLabelReceivedByValue() async throws {
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let session: LazilyInstantiated<Session>", "@Instantiated let t3Builder: Instantiator<T3>"])
				.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: true)"),
			seamFixtureType(named: "T3", isFinalClass: true, declarations: ["@Received let session: Session", "@Instantiated let t0Builder: Instantiator<T0>"]),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let session: LazilyInstantiated<Session>", "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
		]
		try await expectGeneratedTree(of: fixture, root: "Root", equals: """
		extension Root {
		    public convenience init() {
		        func __safeDI_session() -> Session {
		            Session()
		        }
		        let session = LazilyInstantiated<Session>(__safeDI_session)
		        func __safeDI_t3Builder(session: Session) -> T3 {
		            func __safeDI_t0Builder() -> T0 {
		                func __safeDI_session() -> Session {
		                    Session()
		                }
		                let session = LazilyInstantiated<Session>(__safeDI_session)
		                let t3Builder = Instantiator<T3> {
		                    __safeDI_t3Builder(session: session.instance)
		                }
		                return T0(session: session, t3Builder: t3Builder)
		            }
		            let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
		            return T3(session: session, t0Builder: t0Builder)
		        }
		        let t3Builder = Instantiator<T3> {
		            __safeDI_t3Builder(session: session.instance)
		        }
		        self.init(session: session, t3Builder: t3Builder)
		    }
		}
		""", mock: """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            session: (() -> Session)? = nil,
		            t3Builder: T3.SafeDIMockConfiguration = .init()
		        ) {
		            self.session = session
		            self.t3Builder = t3Builder
		        }

		        let session: (() -> Session)?
		        let t3Builder: T3.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_session() -> Session {
		            if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
		        }
		        let session = LazilyInstantiated<Session>(__safeDI_session)
		        func __safeDI_t3Builder(session: Session) -> T3 {
		            func __safeDI_t0Builder() -> T0 {
		                func __safeDI_session() -> Session {
		                    if let safeDIBuilder = safeDIOverrides.t3Builder.t0Builder.session { safeDIBuilder() } else { Session() }
		                }
		                let session = LazilyInstantiated<Session>(__safeDI_session)
		                let t3Builder = Instantiator<T3> {
		                    __safeDI_t3Builder(session: session.instance)
		                }
		                return if let safeDIBuilder = safeDIOverrides.t3Builder.t0Builder.safeDIBuilder { safeDIBuilder(session, t3Builder) } else { T0(session: session, t3Builder: t3Builder) }
		            }
		            let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
		            return if let safeDIBuilder = safeDIOverrides.t3Builder.safeDIBuilder { safeDIBuilder(session, t0Builder) } else { T3(session: session, t0Builder: t0Builder) }
		        }
		        let t3Builder = Instantiator<T3> {
		            __safeDI_t3Builder(session: session.instance)
		        }
		        return Root(session: session, t3Builder: t3Builder)
		    }
		}
		#endif
		""", buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func t3(session: Session) -> T3 {
		            T3(session: session, t0Builder: Instantiator<T0> {
		                let stepSession = LazilyInstantiated<Session> { Session() }
		                return T0(session: stepSession, t3Builder: Instantiator<T3> { t3(session: stepSession.instance) })
		            })
		        }
		        let session = LazilyInstantiated<Session> { Session() }
		        self.init(session: session, t3Builder: Instantiator<T3> { t3(session: session.instance) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesWrapperParameterWhoseInstanceTheTreeReads_whenTreeReceivesLazilyInstantiatedPropertyAndItsInstance() async throws {
		// `T3` receives the wrapper and `Reader` beneath it its instance: the parameter is the wrapper, which provides both.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let session: LazilyInstantiated<Session>", "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T3", isFinalClass: true, declarations: ["@Received let session: LazilyInstantiated<Session>", "@Instantiated let reader: Reader", "@Instantiated let t0Builder: Instantiator<T0>"]),
			seamFixtureType(named: "Reader", isFinalClass: true, declarations: ["@Received let session: Session"]),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let session: LazilyInstantiated<Session>", "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
		]
		try await expectGeneratedTree(of: fixture, root: "Root", equals: """
		extension Root {
		    public convenience init() {
		        func __safeDI_session() -> Session {
		            Session()
		        }
		        let session = LazilyInstantiated<Session>(__safeDI_session)
		        func __safeDI_t3Builder(session: LazilyInstantiated<Session>) -> T3 {
		            let reader = Reader(session: session.instance)
		            func __safeDI_t0Builder() -> T0 {
		                func __safeDI_session() -> Session {
		                    Session()
		                }
		                let session = LazilyInstantiated<Session>(__safeDI_session)
		                let t3Builder = Instantiator<T3> {
		                    __safeDI_t3Builder(session: session)
		                }
		                return T0(session: session, t3Builder: t3Builder)
		            }
		            let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
		            return T3(session: session, reader: reader, t0Builder: t0Builder)
		        }
		        let t3Builder = Instantiator<T3> {
		            __safeDI_t3Builder(session: session)
		        }
		        self.init(session: session, t3Builder: t3Builder)
		    }
		}
		""", buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func t3(session: LazilyInstantiated<Session>) -> T3 {
		            T3(session: session, reader: Reader(session: session.instance), t0Builder: Instantiator<T0> {
		                let stepSession = LazilyInstantiated<Session> { Session() }
		                return T0(session: stepSession, t3Builder: Instantiator<T3> { t3(session: stepSession) })
		            })
		        }
		        let session = LazilyInstantiated<Session> { Session() }
		        self.init(session: session, t3Builder: Instantiator<T3> { t3(session: session) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesForwardedProperty_whenScopeBetweenIsForwardedLabel() async throws {
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T3", isFinalClass: true, declarations: ["@Received let session: Session", "@Instantiated let t0Builder: Instantiator<T0>"]),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Forwarded let session: Session", "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
		]
		try await expectGeneratedTree(of: fixture, root: "Root", equals: """
		extension Root {
		    public convenience init() {
		        let session = Session()
		        func __safeDI_t3Builder(session: Session) -> T3 {
		            func __safeDI_t0Builder(session: Session) -> T0 {
		                let t3Builder = Instantiator<T3> {
		                    __safeDI_t3Builder(session: session)
		                }
		                return T0(session: session, t3Builder: t3Builder)
		            }
		            let t0Builder = Instantiator<T0> {
		                __safeDI_t0Builder(session: $0)
		            }
		            return T3(session: session, t0Builder: t0Builder)
		        }
		        let t3Builder = Instantiator<T3> {
		            __safeDI_t3Builder(session: session)
		        }
		        self.init(session: session, t3Builder: t3Builder)
		    }
		}
		""", buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func t3(session: Session) -> T3 {
		            T3(session: session, t0Builder: Instantiator<T0> { forwardedSession in
		                T0(session: forwardedSession, t3Builder: Instantiator<T3> { t3(session: forwardedSession) })
		            })
		        }
		        let session = Session()
		        self.init(session: session, t3Builder: Instantiator<T3> { t3(session: session) })
		    }
		}
		""", probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("Root().t3Builder.instantiate().t0Builder.instantiate(Session())")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesAlias_whenScopeBetweenAliasesLabelExactlyAndInUnwrappedForm() async throws {
		// `T0`'s aliases provide `session: Session` exactly and `optionalSession: Session?` in its unwrapped form; the app's
		// tree has no `optionalSession`, so the first `T3` is passed `nil` for it.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T3", isFinalClass: true, declarations: ["@Received let session: Session", "@Received(onlyIfAvailable: true) let optionalSession: Session?", "@Instantiated let t0Builder: Instantiator<T0>"]),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: [
				"@Instantiated let stepSession: Session",
				#"@Received(fulfilledByDependencyNamed: "stepSession", ofType: Session.self) let session: Session"#,
				#"@Received(fulfilledByDependencyNamed: "stepSession", ofType: Session.self) let optionalSession: Session"#,
				"@Instantiated let t3Builder: Instantiator<T3>",
			]),
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
		]
		try await expectGeneratedTree(of: fixture, root: "Root", equals: { fixtures in """
		extension Root {
		    public convenience init() {
		        let session = Session()
		        func __safeDI_t3Builder(session: Session, optionalSession: Session?) -> T3 {
		            func __safeDI_t0Builder() -> T0 {
		                let stepSession = Session()
		                #sourceLocation(file: "\(fixtures["T0.swift"])", line: 11)
		                let session: Session = stepSession
		                #sourceLocation()
		                #sourceLocation(file: "\(fixtures["T0.swift"])", line: 12)
		                let optionalSession: Session = stepSession
		                #sourceLocation()
		                let t3Builder = Instantiator<T3> {
		                    __safeDI_t3Builder(session: session, optionalSession: optionalSession)
		                }
		                return T0(stepSession: stepSession, session: session, optionalSession: optionalSession, t3Builder: t3Builder)
		            }
		            let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
		            return T3(session: session, optionalSession: optionalSession, t0Builder: t0Builder)
		        }
		        let t3Builder = Instantiator<T3> {
		            __safeDI_t3Builder(session: session, optionalSession: nil)
		        }
		        self.init(session: session, t3Builder: t3Builder)
		    }
		}
		""" }, buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func t3(optionalSession: Session?, session: Session) -> T3 {
		            T3(session: session, optionalSession: optionalSession, t0Builder: Instantiator<T0> {
		                let stepSession = Session()
		                return T0(stepSession: stepSession, session: stepSession, optionalSession: stepSession, t3Builder: Instantiator<T3> { t3(optionalSession: stepSession, session: stepSession) })
		            })
		        }
		        let session = Session()
		        self.init(session: session, t3Builder: Instantiator<T3> { t3(optionalSession: nil, session: session) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilOnlyWhereNearestDeclarationIsGeneratedAfterCycleClosingScope_whenLabelIsReceivedOnlyIfAvailable() async throws {
		// A logger's tree receives `t3Builder` only if available, which `Root` and `T0` each honor before `T3`'s receive of the
		// logger, so each builds its logger after its `t3Builder` and passes it `nil`; `T0` passes its session, built before.
		// `T4`, between `T3` and another cycle-closing scope, declares neither label, so that scope passes `T3`'s parameters on.
		// `T3` also aliases `session` only if available, so the parameter is optional and the alias is bound from it as such.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let logger: Logger", "@Instantiated let t3Builder: Instantiator<T3>"])
				.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: true)"),
			seamFixtureType(named: "T3", isFinalClass: true, declarations: [
				"@Received(onlyIfAvailable: true) let session: Session?",
				#"@Received(fulfilledByDependencyNamed: "session", ofType: Session.self, onlyIfAvailable: true) let aliasedSession: Session?"#,
				"@Received(onlyIfAvailable: true) let logger: Logger?",
				"@Instantiated let t0Builder: Instantiator<T0>",
				"@Instantiated let t4Builder: Instantiator<T4>",
			]),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let logger: Logger", "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T4", isFinalClass: true, declarations: ["@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Logger", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let t3Builder: Instantiator<T3>?"]),
		]
		try await expectGeneratedTree(of: fixture, root: "Root", equals: { fixtures in """
		extension Root {
		    public convenience init() {
		        let session = Session()
		        func __safeDI_t3Builder(session: Session?, logger: Logger?) -> T3 {
		            #sourceLocation(file: "\(fixtures["T3.swift"])", line: 12)
		            let aliasedSession: Session? = session
		            #sourceLocation()
		            func __safeDI_t0Builder() -> T0 {
		                let session = Session()
		                let t3Builder = Instantiator<T3> {
		                    __safeDI_t3Builder(session: session, logger: nil)
		                }
		                let logger = Logger(t3Builder: t3Builder)
		                return T0(session: session, logger: logger, t3Builder: t3Builder)
		            }
		            let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
		            func __safeDI_t4Builder() -> T4 {
		                let t3Builder = Instantiator<T3> {
		                    __safeDI_t3Builder(session: session, logger: logger)
		                }
		                return T4(t3Builder: t3Builder)
		            }
		            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
		            return T3(session: session, aliasedSession: aliasedSession, logger: logger, t0Builder: t0Builder, t4Builder: t4Builder)
		        }
		        let t3Builder = Instantiator<T3> {
		            __safeDI_t3Builder(session: session, logger: nil)
		        }
		        let logger = Logger(t3Builder: t3Builder)
		        self.init(session: session, logger: logger, t3Builder: t3Builder)
		    }
		}
		""" }, mock: { fixtures in """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            session: (() -> Session)? = nil,
		            t3Builder: T3.SafeDIMockConfiguration = .init(),
		            logger: ((Instantiator<T3>?) -> Logger)? = nil
		        ) {
		            self.session = session
		            self.t3Builder = t3Builder
		            self.logger = logger
		        }

		        let session: (() -> Session)?
		        let t3Builder: T3.SafeDIMockConfiguration
		        let logger: ((Instantiator<T3>?) -> Logger)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
		        func __safeDI_t3Builder(session: Session?, logger: Logger?) -> T3 {
		            #sourceLocation(file: "\(fixtures["T3.swift"])", line: 12)
		            let aliasedSession: Session? = session
		            #sourceLocation()
		            func __safeDI_t0Builder() -> T0 {
		                let session = if let safeDIBuilder = safeDIOverrides.t3Builder.t0Builder.session { safeDIBuilder() } else { Session() }
		                let t3Builder = Instantiator<T3> {
		                    __safeDI_t3Builder(session: session, logger: nil)
		                }
		                let logger = if let safeDIBuilder = safeDIOverrides.t3Builder.t0Builder.logger { safeDIBuilder(t3Builder) } else { Logger(t3Builder: t3Builder) }
		                return if let safeDIBuilder = safeDIOverrides.t3Builder.t0Builder.safeDIBuilder { safeDIBuilder(session, logger, t3Builder) } else { T0(session: session, logger: logger, t3Builder: t3Builder) }
		            }
		            let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
		            func __safeDI_t4Builder() -> T4 {
		                let t3Builder = Instantiator<T3> {
		                    __safeDI_t3Builder(session: session, logger: logger)
		                }
		                return if let safeDIBuilder = safeDIOverrides.t3Builder.t4Builder.safeDIBuilder { safeDIBuilder(t3Builder) } else { T4(t3Builder: t3Builder) }
		            }
		            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
		            return if let safeDIBuilder = safeDIOverrides.t3Builder.safeDIBuilder { safeDIBuilder(session, aliasedSession, logger, t0Builder, t4Builder) } else { T3(session: session, aliasedSession: aliasedSession, logger: logger, t0Builder: t0Builder, t4Builder: t4Builder) }
		        }
		        let t3Builder = Instantiator<T3> {
		            __safeDI_t3Builder(session: session, logger: nil)
		        }
		        let logger = if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder(t3Builder) } else { Logger(t3Builder: t3Builder) }
		        return Root(session: session, logger: logger, t3Builder: t3Builder)
		    }
		}
		#endif
		""" }, buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func t3(session: Session?, logger: Logger?) -> T3 {
		            T3(
		                session: session,
		                aliasedSession: session,
		                logger: logger,
		                t0Builder: Instantiator<T0> {
		                    let stepSession = Session()
		                    let t3Builder = Instantiator<T3> { t3(session: stepSession, logger: nil) }
		                    return T0(session: stepSession, logger: Logger(t3Builder: t3Builder), t3Builder: t3Builder)
		                },
		                t4Builder: Instantiator<T4> { T4(t3Builder: Instantiator<T3> { t3(session: session, logger: logger) }) },
		            )
		        }
		        let session = Session()
		        let t3Builder = Instantiator<T3> { t3(session: session, logger: nil) }
		        self.init(session: session, logger: Logger(t3Builder: t3Builder), t3Builder: t3Builder)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesEachLabelsNearestDeclaration_whenTwoScopesBetweenDeclareLabels() async throws {
		// `T0` declares `a` and `c`, and `T2`, nearer, declares `b` and `c`.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let a: A", "@Instantiated let b: B", "@Instantiated let c: C", "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T3", isFinalClass: true, declarations: ["@Received let a: A", "@Received let b: B", "@Received let c: C", "@Instantiated let t0Builder: Instantiator<T0>"]),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let a: A", "@Instantiated let c: C", "@Instantiated let t2Builder: Instantiator<T2>"]),
			seamFixtureType(named: "T2", isFinalClass: true, declarations: ["@Instantiated let b: B", "@Instantiated let c: C", "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: []),
			seamFixtureType(named: "B", isFinalClass: true, declarations: []),
			seamFixtureType(named: "C", isFinalClass: true, declarations: []),
		]
		try await expectGeneratedTree(of: fixture, root: "Root", equals: """
		extension Root {
		    public convenience init() {
		        let a = A()
		        let b = B()
		        let c = C()
		        func __safeDI_t3Builder(a: A, b: B, c: C) -> T3 {
		            func __safeDI_t0Builder() -> T0 {
		                let a = A()
		                let c = C()
		                func __safeDI_t2Builder() -> T2 {
		                    let b = B()
		                    let c = C()
		                    let t3Builder = Instantiator<T3> {
		                        __safeDI_t3Builder(a: a, b: b, c: c)
		                    }
		                    return T2(b: b, c: c, t3Builder: t3Builder)
		                }
		                let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
		                return T0(a: a, c: c, t2Builder: t2Builder)
		            }
		            let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
		            return T3(a: a, b: b, c: c, t0Builder: t0Builder)
		        }
		        let t3Builder = Instantiator<T3> {
		            __safeDI_t3Builder(a: a, b: b, c: c)
		        }
		        self.init(a: a, b: b, c: c, t3Builder: t3Builder)
		    }
		}
		""", buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func t3(a: A, b: B, c: C) -> T3 {
		            T3(a: a, b: b, c: c, t0Builder: Instantiator<T0> {
		                let t0A = A()
		                let t0C = C()
		                return T0(a: t0A, c: t0C, t2Builder: Instantiator<T2> {
		                    let t2B = B()
		                    let t2C = C()
		                    return T2(b: t2B, c: t2C, t3Builder: Instantiator<T3> { t3(a: t0A, b: t2B, c: t2C) })
		                })
		            })
		        }
		        let a = A()
		        let b = B()
		        let c = C()
		        self.init(a: a, b: b, c: c, t3Builder: Instantiator<T3> { t3(a: a, b: b, c: c) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesParameterOfFunctionNestedInsideCycle_whenThatFunctionsOwnCycleRedeclaresLabel() async throws {
		// `A`'s builder function holds `B`'s, and both are closed on: `C` redeclares `x` inside `B`'s cycle, so `B` takes `x`, and
		// `B` builds `A` again with its own parameter, which differs from `A`'s once `C` has built `B` again. Nothing but `B`'s
		// parameter declares `x` between `A`'s function and the scope that closes `A`'s cycle, so `A` takes `x` only once `B`
		// does: the tree is created a second time.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received let x: X", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let x: X", "@Instantiated let cBuilder: Instantiator<C>", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		]
		try await expectGeneratedTree(of: fixture, root: "Root", equals: """
		extension Root {
		    public convenience init() {
		        let x = X()
		        func __safeDI_aBuilder(x: X) -> A {
		            func __safeDI_bBuilder(x: X) -> B {
		                func __safeDI_cBuilder() -> C {
		                    let x = X()
		                    let bBuilder = Instantiator<B> {
		                        __safeDI_bBuilder(x: x)
		                    }
		                    return C(x: x, bBuilder: bBuilder)
		                }
		                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(x: x)
		                }
		                return B(x: x, cBuilder: cBuilder, aBuilder: aBuilder)
		            }
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(x: x)
		            }
		            return A(x: x, bBuilder: bBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(x: x)
		        }
		        self.init(x: x, aBuilder: aBuilder)
		    }
		}
		""", buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func a(x: X) -> A {
		            A(x: x, bBuilder: Instantiator<B> { b(x: x) })
		        }
		        func b(x: X) -> B {
		            B(x: x, cBuilder: Instantiator<C> {
		                let cX = X()
		                return C(x: cX, bBuilder: Instantiator<B> { b(x: cX) })
		            }, aBuilder: Instantiator<A> { a(x: x) })
		        }
		        let x = X()
		        self.init(x: x, aBuilder: Instantiator<A> { a(x: x) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesLabelOuterCycleClosingScopePassesThroughFunction_whenScopeBetweenFunctionAndItsOwnCycleClosingScopeDeclaresIt() async throws {
		// `Q`'s tree receives `w` beneath `Q` itself, and `G` declares it again, so `Q`'s function takes `w`. The scope inside `S`'s
		// function that closes `Q`'s cycle passes the nearest `w`, which reaches `S` from above it, so `S`'s function, which `D`
		// closes on with its own `w`, takes `w` too, after `z`, which `S` receives itself: the walk of `S`'s tree meets `w` only at
		// the scope that closes `Q`'s cycle.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let w: W", "@Instantiated let qBuilder: Instantiator<Q>"]),
			seamFixtureType(named: "Q", isFinalClass: true, declarations: ["@Instantiated let e: E", "@Instantiated let gBuilder: Instantiator<G>"]),
			seamFixtureType(named: "E", isFinalClass: true, declarations: ["@Received let w: W"]),
			seamFixtureType(named: "G", isFinalClass: true, declarations: ["@Instantiated let w: W", "@Instantiated let z: Z", "@Instantiated let sBuilder: Instantiator<S>"]),
			seamFixtureType(named: "S", isFinalClass: true, declarations: ["@Received let z: Z", "@Instantiated let cBuilder: Instantiator<C>", "@Instantiated let dBuilder: Instantiator<D>"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let qBuilder: Instantiator<Q>"]),
			seamFixtureType(named: "D", isFinalClass: true, declarations: ["@Instantiated let w: W", "@Instantiated let z: Z", "@Instantiated let sBuilder: Instantiator<S>"]),
			seamFixtureType(named: "W", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Z", isFinalClass: true, declarations: []),
		]
		try await expectGeneratedTree(of: fixture, root: "Root", equals: """
		extension Root {
		    public convenience init() {
		        let w = W()
		        func __safeDI_qBuilder(w: W) -> Q {
		            let e = E(w: w)
		            func __safeDI_gBuilder() -> G {
		                let w = W()
		                let z = Z()
		                func __safeDI_sBuilder(z: Z, w: W) -> S {
		                    func __safeDI_cBuilder() -> C {
		                        let qBuilder = Instantiator<Q> {
		                            __safeDI_qBuilder(w: w)
		                        }
		                        return C(qBuilder: qBuilder)
		                    }
		                    let cBuilder = Instantiator<C>(__safeDI_cBuilder)
		                    func __safeDI_dBuilder() -> D {
		                        let w = W()
		                        let z = Z()
		                        let sBuilder = Instantiator<S> {
		                            __safeDI_sBuilder(z: z, w: w)
		                        }
		                        return D(w: w, z: z, sBuilder: sBuilder)
		                    }
		                    let dBuilder = Instantiator<D>(__safeDI_dBuilder)
		                    return S(z: z, cBuilder: cBuilder, dBuilder: dBuilder)
		                }
		                let sBuilder = Instantiator<S> {
		                    __safeDI_sBuilder(z: z, w: w)
		                }
		                return G(w: w, z: z, sBuilder: sBuilder)
		            }
		            let gBuilder = Instantiator<G>(__safeDI_gBuilder)
		            return Q(e: e, gBuilder: gBuilder)
		        }
		        let qBuilder = Instantiator<Q> {
		            __safeDI_qBuilder(w: w)
		        }
		        self.init(w: w, qBuilder: qBuilder)
		    }
		}
		""", buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func q(w: W) -> Q {
		            Q(e: E(w: w), gBuilder: Instantiator<G> {
		                let gW = W()
		                let gZ = Z()
		                return G(w: gW, z: gZ, sBuilder: Instantiator<S> { s(z: gZ, w: gW) })
		            })
		        }
		        func s(z: Z, w: W) -> S {
		            S(z: z, cBuilder: Instantiator<C> { C(qBuilder: Instantiator<Q> { q(w: w) }) }, dBuilder: Instantiator<D> {
		                let dW = W()
		                let dZ = Z()
		                return D(w: dW, z: dZ, sBuilder: Instantiator<S> { s(z: dZ, w: dW) })
		            })
		        }
		        let w = W()
		        self.init(w: w, qBuilder: Instantiator<Q> { q(w: w) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenScopeBetweenDeclaresLabelOfAnotherTypeThanOnlyIfAvailableReceiveAndScopeAboveProvidesIt() async {
		// As on any other path: `Root` provides `t1Builder: Instantiator<T1>`, which `T0`'s declaration of another type hides
		// from the `T3` it builds again.
		var fixture = Self.instantiatorCycleFixture(t0Declares: "@Instantiated let t1Builder: Instantiator<Other>")
		fixture[1] = seamFixtureType(named: "T3", isFinalClass: true, declarations: ["@Instantiated let t0Builder: Instantiator<T0>", "@Received(onlyIfAvailable: true) let t1Builder: Instantiator<T1>?"])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["T3.swift"]):9:5: error: @Received property `t1Builder: Instantiator<T1>?` is hidden in chain: Root -> Instantiator<T3> -> Instantiator<T0> -> T3. `T0` declares `t1Builder: Instantiator<Other>` with the same label, so the types below `T0` receive `t1Builder: Instantiator<Other>` instead. Give `t1Builder: Instantiator<Other>` on `T0` a different label to fix.
			\(fixtures["T0.swift"]):8:5: note: `t1Builder: Instantiator<Other>` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNil_whenScopeBetweenDeclaresLabelOfAnotherTypeThanOnlyIfAvailableReceiveAndNothingAboveProvidesIt() async throws {
		// As on any other path: nothing provides `t1Builder: Instantiator<T1>`, so the `T3` built again under `T0`'s declaration
		// of another type is passed `nil`, as the first `T3` is.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T3", isFinalClass: true, declarations: ["@Instantiated let t0Builder: Instantiator<T0>", "@Received(onlyIfAvailable: true) let t1Builder: Instantiator<T1>?"]),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let t1Builder: Instantiator<Other>", "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T1", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Other", isFinalClass: true, declarations: []),
		]
		try await expectGeneratedTree(of: fixture, root: "Root", equals: """
		extension Root {
		    public convenience init() {
		        func __safeDI_t3Builder(t1Builder: Instantiator<T1>?) -> T3 {
		            func __safeDI_t0Builder() -> T0 {
		                func __safeDI_t1Builder() -> Other {
		                    Other()
		                }
		                let t1Builder = Instantiator<Other>(__safeDI_t1Builder)
		                let t3Builder = Instantiator<T3> {
		                    __safeDI_t3Builder(t1Builder: nil)
		                }
		                return T0(t1Builder: t1Builder, t3Builder: t3Builder)
		            }
		            let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
		            return T3(t0Builder: t0Builder, t1Builder: t1Builder)
		        }
		        let t3Builder = Instantiator<T3> {
		            __safeDI_t3Builder(t1Builder: nil)
		        }
		        self.init(t3Builder: t3Builder)
		    }
		}
		""", buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func t3() -> T3 {
		            T3(t0Builder: Instantiator<T0> {
		                T0(t1Builder: Instantiator<Other> { Other() }, t3Builder: Instantiator<T3> { t3() })
		            }, t1Builder: nil)
		        }
		        self.init(t3Builder: Instantiator<T3> { t3() })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilBeneathScopeDeclaringParameterLabelWithAnotherType_whenTypeThereReceivesLabelOnlyIfAvailable() async throws {
		// `T0` declares `session` as `Other`, so `T3` takes `session` as a parameter; `Reader`, beneath `T0`, receives the
		// nearest `session`, `T0`'s, which is no `Session`, and is passed `nil`, as nothing above `Reader` provides a `Session`.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T3", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let session: Session?", "@Instantiated let t0Builder: Instantiator<T0>"]),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let session: Other", "@Instantiated let reader: Reader", "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "Reader", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let session: Session?"]),
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Other", isFinalClass: true, declarations: []),
		]
		try await expectGeneratedTree(of: fixture, root: "Root", equals: """
		extension Root {
		    public convenience init() {
		        func __safeDI_t3Builder(session: Session?) -> T3 {
		            func __safeDI_t0Builder() -> T0 {
		                let session = Other()
		                let reader = Reader(session: nil)
		                let t3Builder = Instantiator<T3> {
		                    __safeDI_t3Builder(session: nil)
		                }
		                return T0(session: session, reader: reader, t3Builder: t3Builder)
		            }
		            let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
		            return T3(session: session, t0Builder: t0Builder)
		        }
		        let t3Builder = Instantiator<T3> {
		            __safeDI_t3Builder(session: nil)
		        }
		        self.init(t3Builder: t3Builder)
		    }
		}
		""", buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func t3() -> T3 {
		            T3(session: nil, t0Builder: Instantiator<T0> {
		                T0(session: Other(), reader: Reader(session: nil), t3Builder: Instantiator<T3> { t3() })
		            })
		        }
		        self.init(t3Builder: Instantiator<T3> { t3() })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesNoParameterOfClosedOnPropertysOwnLabel_whenTypeBuiltAgainReceivesBuilderThatBuildsIt() async throws {
		// `T1` receives `t1Builder` only if available, and `T2` declares it again by closing the cycle: every `T1` is built
		// inside a `t1Builder` and is passed `nil`, so `Root`'s builder function takes no parameter, as before.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let t1Builder: Instantiator<T1>"]),
			seamFixtureType(named: "T1", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let t1Builder: Instantiator<T1>?", "@Instantiated let t2Builder: Instantiator<T2>"]),
			seamFixtureType(named: "T2", isFinalClass: true, declarations: ["@Instantiated let t1Builder: Instantiator<T1>"]),
		]
		try await expectGeneratedTree(of: fixture, root: "Root", equals: """
		extension Root {
		    public convenience init() {
		        func __safeDI_t1Builder() -> T1 {
		            func __safeDI_t2Builder() -> T2 {
		                let t1Builder = Instantiator<T1>(__safeDI_t1Builder)
		                return T2(t1Builder: t1Builder)
		            }
		            let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
		            return T1(t1Builder: nil, t2Builder: t2Builder)
		        }
		        let t1Builder = Instantiator<T1>(__safeDI_t1Builder)
		        self.init(t1Builder: t1Builder)
		    }
		}
		""", buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func t1() -> T1 {
		            T1(t1Builder: nil, t2Builder: Instantiator<T2> { T2(t1Builder: Instantiator<T1> { t1() }) })
		        }
		        self.init(t1Builder: Instantiator<T1> { t1() })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesNoParameterOfLabelClosedOnTypeForwards_whenScopeBetweenDeclaresLabelOfAnotherType() async throws {
		// Inside `T3`'s builder function `T3`'s own `session` is the nearest declaration of the label, so the function takes
		// only the forwarded `session`, and `Child`, whose form nothing provides, is passed `nil` on every build, as before.
		let fixture = Self.closedOnTypesOwnLabelFixture(t3Declares: "@Forwarded let session: Session", t0Declares: "@Instantiated let session: Other")
		try await expectGeneratedTree(of: fixture, root: "Root", equals: """
		extension Root {
		    public convenience init() {
		        func __safeDI_t3Builder(session: Session) -> T3 {
		            let child = Child(session: nil)
		            func __safeDI_t0Builder() -> T0 {
		                let session = Other()
		                let t3Builder = Instantiator<T3> {
		                    __safeDI_t3Builder(session: $0)
		                }
		                return T0(session: session, t3Builder: t3Builder)
		            }
		            let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
		            return T3(session: session, child: child, t0Builder: t0Builder)
		        }
		        let t3Builder = Instantiator<T3> {
		            __safeDI_t3Builder(session: $0)
		        }
		        self.init(t3Builder: t3Builder)
		    }
		}
		""", buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func t3(session: Session) -> T3 {
		            T3(session: session, child: Child(session: nil), t0Builder: Instantiator<T0> {
		                T0(session: Other(), t3Builder: Instantiator<T3> { t3(session: $0) })
		            })
		        }
		        self.init(t3Builder: Instantiator<T3> { t3(session: $0) })
		    }
		}
		""", probes: [
			DifferentialValueProbe("Root().t3Builder.instantiate(Session())"),
			DifferentialValueProbe("Root().t3Builder.instantiate(Session()).t0Builder.instantiate().t3Builder.instantiate(Session())"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearestDeclaration_whenCycleClosingScopeIsBuiltBeforeTheReceiverOfItsParameter() async throws {
		// A walk of `Screen`'s builder function meets the cycle-closing scope in `Step`, which passes `session`, before
		// `Reader`, which receives it: the function's parameters settle, and `Reader` is passed the step's session.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"])
				.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: true)"),
			seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Instantiated let stepBuilder: Instantiator<Step>", "@Instantiated let reader: Reader"]),
			seamFixtureType(named: "Step", isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"]),
			seamFixtureType(named: "Reader", isFinalClass: true, declarations: ["@Received let session: Session"]),
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
		]
		try await expectGeneratedTree(of: fixture, root: "Root", equals: """
		extension Root {
		    public convenience init() {
		        let session = Session()
		        func __safeDI_screenBuilder(session: Session) -> Screen {
		            func __safeDI_stepBuilder() -> Step {
		                let session = Session()
		                let screenBuilder = Instantiator<Screen> {
		                    __safeDI_screenBuilder(session: session)
		                }
		                return Step(session: session, screenBuilder: screenBuilder)
		            }
		            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
		            let reader = Reader(session: session)
		            return Screen(stepBuilder: stepBuilder, reader: reader)
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(session: session)
		        }
		        self.init(session: session, screenBuilder: screenBuilder)
		    }
		}
		""", mock: """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            session: (() -> Session)? = nil,
		            screenBuilder: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            self.session = session
		            self.screenBuilder = screenBuilder
		        }

		        let session: (() -> Session)?
		        let screenBuilder: Screen.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
		        func __safeDI_screenBuilder(session: Session) -> Screen {
		            func __safeDI_stepBuilder() -> Step {
		                let session = if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.session { safeDIBuilder() } else { Session() }
		                let screenBuilder = Instantiator<Screen> {
		                    __safeDI_screenBuilder(session: session)
		                }
		                return if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.safeDIBuilder { safeDIBuilder(session, screenBuilder) } else { Step(session: session, screenBuilder: screenBuilder) }
		            }
		            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
		            let reader = if let safeDIBuilder = safeDIOverrides.screenBuilder.reader { safeDIBuilder(session) } else { Reader(session: session) }
		            return if let safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder { safeDIBuilder(stepBuilder, reader) } else { Screen(stepBuilder: stepBuilder, reader: reader) }
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(session: session)
		        }
		        return Root(session: session, screenBuilder: screenBuilder)
		    }
		}
		#endif
		""", buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func screen(session: Session) -> Screen {
		            Screen(stepBuilder: Instantiator<Step> {
		                let stepSession = Session()
		                return Step(session: stepSession, screenBuilder: Instantiator<Screen> { screen(session: stepSession) })
		            }, reader: Reader(session: session))
		        }
		        let session = Session()
		        self.init(session: session, screenBuilder: Instantiator<Screen> { screen(session: session) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearestDeclarationToSendableFunction_whenCycleClosesThroughSendableInstantiator() async throws {
		// M1's flow built through `SendableInstantiator`s: the function the cycle closes on is `@Sendable`, and each scope that
		// calls it does so from a `@Sendable` closure.
		let fixture = [
			seamFixtureType(named: "App", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let screenBuilder: SendableInstantiator<Screen>"], conformances: ", @unchecked Sendable")
				.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: true)"),
			seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Received let session: Session", "@Instantiated let stepBuilder: SendableInstantiator<Step>"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "Step", isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let screenBuilder: SendableInstantiator<Screen>"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "Session", isFinalClass: true, declarations: [], conformances: ", @unchecked Sendable"),
		]
		try await expectGeneratedTree(of: fixture, root: "App", equals: """
		extension App {
		    public convenience init() {
		        let session = Session()
		        @Sendable func __safeDI_screenBuilder(session: Session) -> Screen {
		            @Sendable func __safeDI_stepBuilder() -> Step {
		                let session = Session()
		                let screenBuilder = SendableInstantiator<Screen> {
		                    __safeDI_screenBuilder(session: session)
		                }
		                return Step(session: session, screenBuilder: screenBuilder)
		            }
		            let stepBuilder = SendableInstantiator<Step>(__safeDI_stepBuilder)
		            return Screen(session: session, stepBuilder: stepBuilder)
		        }
		        let screenBuilder = SendableInstantiator<Screen> {
		            __safeDI_screenBuilder(session: session)
		        }
		        self.init(session: session, screenBuilder: screenBuilder)
		    }
		}
		""", mock: """
		#if DEBUG
		extension App {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            session: (() -> Session)? = nil,
		            screenBuilder: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            self.session = session
		            self.screenBuilder = screenBuilder
		        }

		        let session: (() -> Session)?
		        let screenBuilder: Screen.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> App {
		        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
		        let __safeDI_screenBuilder__screenBuilder_stepBuilder_safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.safeDIBuilder
		        let __safeDI_screenBuilder__screenBuilder_stepBuilder_session_safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.session
		        let __safeDI_screenBuilder__safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder
		        @Sendable func __safeDI_screenBuilder(session: Session) -> Screen {
		            @Sendable func __safeDI_stepBuilder() -> Step {
		                let session = if let safeDIBuilder = __safeDI_screenBuilder__screenBuilder_stepBuilder_session_safeDIBuilder { safeDIBuilder() } else { Session() }
		                let screenBuilder = SendableInstantiator<Screen> {
		                    __safeDI_screenBuilder(session: session)
		                }
		                return if let safeDIBuilder = __safeDI_screenBuilder__screenBuilder_stepBuilder_safeDIBuilder { safeDIBuilder(session, screenBuilder) } else { Step(session: session, screenBuilder: screenBuilder) }
		            }
		            let stepBuilder = SendableInstantiator<Step>(__safeDI_stepBuilder)
		            return if let safeDIBuilder = __safeDI_screenBuilder__safeDIBuilder { safeDIBuilder(session, stepBuilder) } else { Screen(session: session, stepBuilder: stepBuilder) }
		        }
		        let screenBuilder = SendableInstantiator<Screen> {
		            __safeDI_screenBuilder(session: session)
		        }
		        return App(session: session, screenBuilder: screenBuilder)
		    }
		}
		#endif
		""", buildsTheSameValuesAs: """
		extension App {
		    public convenience init() {
		        @Sendable func screen(session: Session) -> Screen {
		            Screen(session: session, stepBuilder: SendableInstantiator<Step> {
		                let stepSession = Session()
		                return Step(session: stepSession, screenBuilder: SendableInstantiator<Screen> { screen(session: stepSession) })
		            })
		        }
		        let session = Session()
		        self.init(session: session, screenBuilder: SendableInstantiator<Screen> { screen(session: session) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilThenNearestDeclarationToParameterOfSendableFunction_whenOnlyCycleClosingScopeInSendableBuilderMakesItSendable() async throws {
		// The function's body reads its parameter, which captures nothing: `Root` passes `nil`, and `Z` passes its own `yBuilder`
		// from inside its function, where it is declared.
		try await expectSendableOnlyThroughCycleTree(rootDeclaresYBuilder: false)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesDeclaringScopesInstantiatorToParameterOfSendableFunction_whenOnlyCycleClosingScopeInSendableBuilderMakesItSendable() async throws {
		// `Root` passes its `yBuilder` from a closure that is not `@Sendable`, and the function's body reads the parameter, so
		// nothing captures `Root`'s `yBuilder`, which 2.2.0's function body read from above it, inside the `@Sendable` function.
		try await expectSendableOnlyThroughCycleTree(rootDeclaresYBuilder: true)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesForwardedPropertiesThenNearestDeclaration_whenCycleClosesThroughErasedInstantiatorOfTypeWithForwardedProperties() async throws {
		// The type built again forwards `name` and `count`, which each `ErasedInstantiator` passes before `session`.
		let fixture = [
			"""
			public protocol ScreenProtocol: AnyObject {}
			public final class AnyScreen {
			    public init(_ screen: some ScreenProtocol) {
			        self.screen = screen
			    }

			    public let screen: any ScreenProtocol
			}
			extension Screen: ScreenProtocol {}
			""",
			seamFixtureType(named: "App", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let session: Session", #"@Instantiated(fulfilledByType: "Screen", erasedToConcreteExistential: true) let screenBuilder: ErasedInstantiator<Screen.ForwardedProperties, AnyScreen>"#])
				.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: true)"),
			seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Forwarded let name: String", "@Forwarded let count: Int", "@Received let session: Session", "@Instantiated let stepBuilder: Instantiator<Step>"]),
			seamFixtureType(named: "Step", isFinalClass: true, declarations: ["@Instantiated let session: Session", #"@Instantiated(fulfilledByType: "Screen", erasedToConcreteExistential: true) let screenBuilder: ErasedInstantiator<Screen.ForwardedProperties, AnyScreen>"#]),
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
		]
		// An `ErasedInstantiator` is not traversed, so each probe holds a step and the screen it builds again.
		let stepAndScreenBuiltAgain = { (app: String) in
			DifferentialValueProbe(#"{ () -> (Step, AnyScreen) in let step = (\#(app).screenBuilder.instantiate((count: 1, name: "a")).screen as! Screen).stepBuilder.instantiate(); return (step, step.screenBuilder.instantiate((count: 2, name: "b"))) }()"#)
		}
		try await expectGeneratedTree(of: fixture, root: "App", equals: """
		extension App {
		    public convenience init() {
		        let session = Session()
		        func __safeDI_screenBuilder(count: Int, name: String, session: Session) -> Screen {
		            func __safeDI_stepBuilder() -> Step {
		                let session = Session()
		                let screenBuilder = ErasedInstantiator<Screen.ForwardedProperties, AnyScreen> {
		                    AnyScreen(__safeDI_screenBuilder(count: $0.count, name: $0.name, session: session))
		                }
		                return Step(session: session, screenBuilder: screenBuilder)
		            }
		            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
		            return Screen(name: name, count: count, session: session, stepBuilder: stepBuilder)
		        }
		        let screenBuilder = ErasedInstantiator<Screen.ForwardedProperties, AnyScreen> {
		            AnyScreen(__safeDI_screenBuilder(count: $0.count, name: $0.name, session: session))
		        }
		        self.init(session: session, screenBuilder: screenBuilder)
		    }
		}
		""", mock: """
		#if DEBUG
		extension App {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            session: (() -> Session)? = nil,
		            screenBuilder: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            self.session = session
		            self.screenBuilder = screenBuilder
		        }

		        let session: (() -> Session)?
		        let screenBuilder: Screen.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> App {
		        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
		        func __safeDI_screenBuilder(count: Int, name: String, session: Session) -> AnyScreen {
		            func __safeDI_stepBuilder() -> Step {
		                let session = if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.session { safeDIBuilder() } else { Session() }
		                let screenBuilder = ErasedInstantiator<Screen.ForwardedProperties, AnyScreen> {
		                    __safeDI_screenBuilder(count: $0.count, name: $0.name, session: session)
		                }
		                return if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.safeDIBuilder { safeDIBuilder(session, screenBuilder) } else { Step(session: session, screenBuilder: screenBuilder) }
		            }
		            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
		            return if let safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder { AnyScreen(safeDIBuilder(name, count, session, stepBuilder)) } else { AnyScreen(Screen(name: name, count: count, session: session, stepBuilder: stepBuilder)) }
		        }
		        let screenBuilder = ErasedInstantiator<Screen.ForwardedProperties, AnyScreen> {
		            __safeDI_screenBuilder(count: $0.count, name: $0.name, session: session)
		        }
		        return App(session: session, screenBuilder: screenBuilder)
		    }
		}
		#endif
		""", buildsTheSameValuesAs: """
		extension App {
		    public convenience init() {
		        func screen(count: Int, name: String, session: Session) -> Screen {
		            Screen(name: name, count: count, session: session, stepBuilder: Instantiator<Step> {
		                let stepSession = Session()
		                return Step(session: stepSession, screenBuilder: ErasedInstantiator<Screen.ForwardedProperties, AnyScreen> {
		                    AnyScreen(screen(count: $0.count, name: $0.name, session: stepSession))
		                })
		            })
		        }
		        let session = Session()
		        self.init(session: session, screenBuilder: ErasedInstantiator<Screen.ForwardedProperties, AnyScreen> {
		            AnyScreen(screen(count: $0.count, name: $0.name, session: session))
		        })
		    }
		}
		""", probes: [stepAndScreenBuiltAgain("App()"), stepAndScreenBuiltAgain("App.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesEachCycleClosingScopesNearestDeclaration_whenScopesAtThreeDepthsCloseOneCycle() async throws {
		// `Step`'s cycle-closing scope passes its own session; `Other`'s, with nothing between, passes `Screen`'s parameter; and
		// `Inner`'s, beneath `Other`, passes the session forwarded into `Inner`.
		let fixture = [
			seamFixtureType(named: "App", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"])
				.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: true)"),
			seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Received let session: Session", "@Instantiated let stepBuilder: Instantiator<Step>", "@Instantiated let otherBuilder: Instantiator<Other>"]),
			seamFixtureType(named: "Step", isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"]),
			seamFixtureType(named: "Other", isFinalClass: true, declarations: ["@Instantiated let innerBuilder: Instantiator<Inner>", "@Instantiated let screenBuilder: Instantiator<Screen>"]),
			seamFixtureType(named: "Inner", isFinalClass: true, declarations: ["@Forwarded let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"]),
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
		]
		// An instantiator with forwarded properties is not traversed, so a probe builds `Inner` with a session of its own.
		let inner = { (app: String) in DifferentialValueProbe("\(app).screenBuilder.instantiate().otherBuilder.instantiate().innerBuilder.instantiate(Session())") }
		try await expectGeneratedTree(of: fixture, root: "App", equals: """
		extension App {
		    public convenience init() {
		        let session = Session()
		        func __safeDI_screenBuilder(session: Session) -> Screen {
		            func __safeDI_stepBuilder() -> Step {
		                let session = Session()
		                let screenBuilder = Instantiator<Screen> {
		                    __safeDI_screenBuilder(session: session)
		                }
		                return Step(session: session, screenBuilder: screenBuilder)
		            }
		            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
		            func __safeDI_otherBuilder() -> Other {
		                func __safeDI_innerBuilder(session: Session) -> Inner {
		                    let screenBuilder = Instantiator<Screen> {
		                        __safeDI_screenBuilder(session: session)
		                    }
		                    return Inner(session: session, screenBuilder: screenBuilder)
		                }
		                let innerBuilder = Instantiator<Inner> {
		                    __safeDI_innerBuilder(session: $0)
		                }
		                let screenBuilder = Instantiator<Screen> {
		                    __safeDI_screenBuilder(session: session)
		                }
		                return Other(innerBuilder: innerBuilder, screenBuilder: screenBuilder)
		            }
		            let otherBuilder = Instantiator<Other>(__safeDI_otherBuilder)
		            return Screen(session: session, stepBuilder: stepBuilder, otherBuilder: otherBuilder)
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(session: session)
		        }
		        self.init(session: session, screenBuilder: screenBuilder)
		    }
		}
		""", mock: """
		#if DEBUG
		extension App {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            session: (() -> Session)? = nil,
		            screenBuilder: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            self.session = session
		            self.screenBuilder = screenBuilder
		        }

		        let session: (() -> Session)?
		        let screenBuilder: Screen.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> App {
		        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
		        func __safeDI_screenBuilder(session: Session) -> Screen {
		            func __safeDI_stepBuilder() -> Step {
		                let session = if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.session { safeDIBuilder() } else { Session() }
		                let screenBuilder = Instantiator<Screen> {
		                    __safeDI_screenBuilder(session: session)
		                }
		                return if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.safeDIBuilder { safeDIBuilder(session, screenBuilder) } else { Step(session: session, screenBuilder: screenBuilder) }
		            }
		            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
		            func __safeDI_otherBuilder() -> Other {
		                func __safeDI_innerBuilder(session: Session) -> Inner {
		                    let screenBuilder = Instantiator<Screen> {
		                        __safeDI_screenBuilder(session: session)
		                    }
		                    return if let safeDIBuilder = safeDIOverrides.screenBuilder.otherBuilder.innerBuilder.safeDIBuilder { safeDIBuilder(session, screenBuilder) } else { Inner(session: session, screenBuilder: screenBuilder) }
		                }
		                let innerBuilder = Instantiator<Inner> {
		                    __safeDI_innerBuilder(session: $0)
		                }
		                let screenBuilder = Instantiator<Screen> {
		                    __safeDI_screenBuilder(session: session)
		                }
		                return if let safeDIBuilder = safeDIOverrides.screenBuilder.otherBuilder.safeDIBuilder { safeDIBuilder(innerBuilder, screenBuilder) } else { Other(innerBuilder: innerBuilder, screenBuilder: screenBuilder) }
		            }
		            let otherBuilder = Instantiator<Other>(__safeDI_otherBuilder)
		            return if let safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder { safeDIBuilder(session, stepBuilder, otherBuilder) } else { Screen(session: session, stepBuilder: stepBuilder, otherBuilder: otherBuilder) }
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(session: session)
		        }
		        return App(session: session, screenBuilder: screenBuilder)
		    }
		}
		#endif
		""", buildsTheSameValuesAs: """
		extension App {
		    public convenience init() {
		        func screen(session: Session) -> Screen {
		            Screen(session: session, stepBuilder: Instantiator<Step> {
		                let stepSession = Session()
		                return Step(session: stepSession, screenBuilder: Instantiator<Screen> { screen(session: stepSession) })
		            }, otherBuilder: Instantiator<Other> {
		                Other(innerBuilder: Instantiator<Inner> { innerSession in
		                    Inner(session: innerSession, screenBuilder: Instantiator<Screen> { screen(session: innerSession) })
		                }, screenBuilder: Instantiator<Screen> { screen(session: session) })
		            })
		        }
		        let session = Session()
		        self.init(session: session, screenBuilder: Instantiator<Screen> { screen(session: session) })
		    }
		}
		""", probes: [DifferentialValueProbe("App()"), inner("App()"), inner("App.mock()")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsEachParameterType_whenScopesBetweenForwardClosureExistentialNestedGenericAndTypealiasValues() async throws {
		let support = """
		public protocol Service: AnyObject {}
		public final class DefaultService: Service {
		    public init() {}
		}
		public enum Feature {
		    public final class Config {
		        public init() {}
		    }
		}
		public final class Box<Value> {
		    public init(_ value: Value) {
		        self.value = value
		    }

		    public let value: Value
		}
		public typealias Name = String
		"""
		let values = ["@Forwarded let onTap: () -> Void", "@Forwarded let service: any Service", "@Forwarded let config: Feature.Config", "@Forwarded let box: Box<Int>", "@Forwarded let name: Name"]
		let fixture = [
			support,
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let hostBuilder: Instantiator<Host>"]),
			seamFixtureType(named: "Host", isFinalClass: true, declarations: values + ["@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T3", isFinalClass: true, declarations: values.map { $0.replacingOccurrences(of: "@Forwarded", with: "@Received") } + ["@Instantiated let t0Builder: Instantiator<T0>"]),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: values + ["@Instantiated let t3Builder: Instantiator<T3>"]),
		]
		try await expectGeneratedTree(of: fixture, root: "Root", equals: """
		extension Root {
		    public convenience init() {
		        func __safeDI_hostBuilder(box: Box<Int>, config: Feature.Config, name: Name, onTap: @escaping () -> Void, service: any Service) -> Host {
		            func __safeDI_t3Builder(onTap: @escaping () -> Void, service: any Service, config: Feature.Config, box: Box<Int>, name: Name) -> T3 {
		                func __safeDI_t0Builder(box: Box<Int>, config: Feature.Config, name: Name, onTap: @escaping () -> Void, service: any Service) -> T0 {
		                    let t3Builder = Instantiator<T3> {
		                        __safeDI_t3Builder(onTap: onTap, service: service, config: config, box: box, name: name)
		                    }
		                    return T0(onTap: onTap, service: service, config: config, box: box, name: name, t3Builder: t3Builder)
		                }
		                let t0Builder = Instantiator<T0> {
		                    __safeDI_t0Builder(box: $0.box, config: $0.config, name: $0.name, onTap: $0.onTap, service: $0.service)
		                }
		                return T3(onTap: onTap, service: service, config: config, box: box, name: name, t0Builder: t0Builder)
		            }
		            let t3Builder = Instantiator<T3> {
		                __safeDI_t3Builder(onTap: onTap, service: service, config: config, box: box, name: name)
		            }
		            return Host(onTap: onTap, service: service, config: config, box: box, name: name, t3Builder: t3Builder)
		        }
		        let hostBuilder = Instantiator<Host> {
		            __safeDI_hostBuilder(box: $0.box, config: $0.config, name: $0.name, onTap: $0.onTap, service: $0.service)
		        }
		        self.init(hostBuilder: hostBuilder)
		    }
		}
		""", buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func t3(box: Box<Int>, config: Feature.Config, name: Name, onTap: @escaping () -> Void, service: any Service) -> T3 {
		            T3(onTap: onTap, service: service, config: config, box: box, name: name, t0Builder: Instantiator<T0> { values in
		                T0(onTap: values.onTap, service: values.service, config: values.config, box: values.box, name: values.name, t3Builder: Instantiator<T3> {
		                    t3(box: values.box, config: values.config, name: values.name, onTap: values.onTap, service: values.service)
		                })
		            })
		        }
		        self.init(hostBuilder: Instantiator<Host> { values in
		            Host(onTap: values.onTap, service: values.service, config: values.config, box: values.box, name: values.name, t3Builder: Instantiator<T3> {
		                t3(box: values.box, config: values.config, name: values.name, onTap: values.onTap, service: values.service)
		            })
		        })
		    }
		}
		""", probes: [
			DifferentialValueProbe(#"Root().hostBuilder.instantiate((box: Box(1), config: Feature.Config(), name: "host", onTap: {}, service: DefaultService())).t3Builder.instantiate().t0Builder.instantiate((box: Box(2), config: Feature.Config(), name: "step", onTap: {}, service: DefaultService()))"#),
		])
	}

	// MARK: Tests – Mocks

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesNearestDeclaration_whenMockRootsTreeAndPromotedTreeCloseLazyCycleAroundRedeclaration() async throws {
		// `Root`'s mock builds the cycle in its own tree. `Feature`'s builds it in the `t3Builder` it promotes for its receive,
		// beside a `t1Builder` it promotes under another name, since `Feature` receives `t1Builder` as `T1` too.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let t1Builder: Instantiator<T1>", "@Instantiated let t3Builder: Instantiator<T3>"])
				.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: true)"),
			seamFixtureType(named: "Feature", isFinalClass: true, declarations: ["@Received let t3Builder: Instantiator<T3>", "@Received let t1Builder: T1"])
				.replacingOccurrences(of: "@Instantiable", with: "@Instantiable(generateMock: true)"),
			seamFixtureType(named: "T3", isFinalClass: true, declarations: ["@Instantiated let t0Builder: Instantiator<T0>", "@Received let t1Builder: Instantiator<T1>"]),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let t1Builder: Instantiator<T1>", "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T1", isFinalClass: true, declarations: []),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Feature+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Feature {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            t1Builder_Instantiator__T1: (() -> T1)? = nil,
			            t3Builder: T3.SafeDIMockConfiguration = .init(),
			            t1Builder_T1: (() -> T1)? = nil
			        ) {
			            self.t1Builder_Instantiator__T1 = t1Builder_Instantiator__T1
			            self.t3Builder = t3Builder
			            self.t1Builder_T1 = t1Builder_T1
			        }

			        let t1Builder_Instantiator__T1: (() -> T1)?
			        let t3Builder: T3.SafeDIMockConfiguration
			        let t1Builder_T1: (() -> T1)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Feature {
			        func __safeDI_t1Builder_Instantiator__T1() -> T1 {
			            if let safeDIBuilder = safeDIOverrides.t1Builder_Instantiator__T1 { safeDIBuilder() } else { T1() }
			        }
			        let t1Builder_Instantiator__T1 = Instantiator<T1>(__safeDI_t1Builder_Instantiator__T1)
			        func __safeDI_t3Builder(t1Builder: Instantiator<T1>) -> T3 {
			            func __safeDI_t0Builder() -> T0 {
			                func __safeDI_t1Builder() -> T1 {
			                    if let safeDIBuilder = safeDIOverrides.t3Builder.t0Builder.t1Builder { safeDIBuilder() } else { T1() }
			                }
			                let t1Builder = Instantiator<T1>(__safeDI_t1Builder)
			                let t3Builder = Instantiator<T3> {
			                    __safeDI_t3Builder(t1Builder: t1Builder)
			                }
			                return if let safeDIBuilder = safeDIOverrides.t3Builder.t0Builder.safeDIBuilder { safeDIBuilder(t1Builder, t3Builder) } else { T0(t1Builder: t1Builder, t3Builder: t3Builder) }
			            }
			            let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
			            return if let safeDIBuilder = safeDIOverrides.t3Builder.safeDIBuilder { safeDIBuilder(t0Builder, t1Builder) } else { T3(t0Builder: t0Builder, t1Builder: t1Builder) }
			        }
			        let t3Builder = Instantiator<T3> {
			            __safeDI_t3Builder(t1Builder: t1Builder_Instantiator__T1)
			        }
			        let t1Builder_T1 = if let safeDIBuilder = safeDIOverrides.t1Builder_T1 { safeDIBuilder() } else { T1() }
			        return Feature(t3Builder: t3Builder, t1Builder: t1Builder_T1)
			    }
			}
			#endif
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            t1Builder: (() -> T1)? = nil,
			            t3Builder: T3.SafeDIMockConfiguration = .init()
			        ) {
			            self.t1Builder = t1Builder
			            self.t3Builder = t3Builder
			        }

			        let t1Builder: (() -> T1)?
			        let t3Builder: T3.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_t1Builder() -> T1 {
			            if let safeDIBuilder = safeDIOverrides.t1Builder { safeDIBuilder() } else { T1() }
			        }
			        let t1Builder = Instantiator<T1>(__safeDI_t1Builder)
			        func __safeDI_t3Builder(t1Builder: Instantiator<T1>) -> T3 {
			            func __safeDI_t0Builder() -> T0 {
			                func __safeDI_t1Builder() -> T1 {
			                    if let safeDIBuilder = safeDIOverrides.t3Builder.t0Builder.t1Builder { safeDIBuilder() } else { T1() }
			                }
			                let t1Builder = Instantiator<T1>(__safeDI_t1Builder)
			                let t3Builder = Instantiator<T3> {
			                    __safeDI_t3Builder(t1Builder: t1Builder)
			                }
			                return if let safeDIBuilder = safeDIOverrides.t3Builder.t0Builder.safeDIBuilder { safeDIBuilder(t1Builder, t3Builder) } else { T0(t1Builder: t1Builder, t3Builder: t3Builder) }
			            }
			            let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
			            return if let safeDIBuilder = safeDIOverrides.t3Builder.safeDIBuilder { safeDIBuilder(t0Builder, t1Builder) } else { T3(t0Builder: t0Builder, t1Builder: t1Builder) }
			        }
			        let t3Builder = Instantiator<T3> {
			            __safeDI_t3Builder(t1Builder: t1Builder)
			        }
			        return Root(t1Builder: t1Builder, t3Builder: t3Builder)
			    }
			}
			#endif
			""",
		])
		try expectDifferentialValuesAgree(
			feature: DifferentialValuePath(fixtureFiles: Self.fixtureFiles(fixture), generatedFiles: output.generatedFiles ?? [:]),
			knownRight: DifferentialValuePath(fixtureFiles: Self.fixtureFiles(fixture), generatedFiles: ["Mocks.swift": """
			extension Root {
			    static func mock() -> Root {
			\(Self.handBuiltInstantiatorCycle(name: "Root", returning: "return Root"))
			    }
			}

			extension Feature {
			    static func mock() -> Feature {
			\(Self.handBuiltInstantiatorCycle(name: "Feature", returning: "return Feature"))
			    }
			}
			"""]),
			probes: [DifferentialValueProbe("Root.mock()"), DifferentialValueProbe("Feature.mock()")],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_readsEachOverrideOnce_whenClosedOnFunctionTakesParametersInsideEnclosingSendableBuilder() async throws {
		// `T3`'s builder function, which takes `session`, is inside `Host`'s `@Sendable` one, so the mock reads `T3`'s overrides,
		// `flag` among them, into locals before `Host`'s function, each once.
		let fixture = [
			seamFixtureType(named: "App", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let hostBuilder: SendableInstantiator<Host>"], conformances: ", @unchecked Sendable")
				.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: true)"),
			seamFixtureType(named: "Host", isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let t3Builder: SendableInstantiator<T3>"], conformances: ", @unchecked Sendable"),
			"""
			@Instantiable
			public final class T3: Instantiable, @unchecked Sendable {
			    public init(session: Session, t0Builder: SendableInstantiator<T0>, flag: Int = 7) {
			        self.session = session
			        self.t0Builder = t0Builder
			        self.flag = flag
			    }

			    @Received let session: Session
			    @Instantiated let t0Builder: SendableInstantiator<T0>
			    let flag: Int
			}
			""",
			seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let t3Builder: SendableInstantiator<T3>"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "Session", isFinalClass: true, declarations: [], conformances: ", @unchecked Sendable"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == ["App+SafeDIMock.swift": generatedFileHeader + """
		#if DEBUG
		extension App {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            hostBuilder: Host.SafeDIMockConfiguration = .init()
		        ) {
		            self.hostBuilder = hostBuilder
		        }

		        let hostBuilder: Host.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> App {
		        let __safeDI_hostBuilder__hostBuilder_session_safeDIBuilder = safeDIOverrides.hostBuilder.session
		        let __safeDI_hostBuilder__hostBuilder_t3Builder_safeDIBuilder = safeDIOverrides.hostBuilder.t3Builder.safeDIBuilder
		        let __safeDI_hostBuilder__hostBuilder_t3Builder_flag = safeDIOverrides.hostBuilder.t3Builder.flag
		        let __safeDI_hostBuilder__hostBuilder_t3Builder_t0Builder_safeDIBuilder = safeDIOverrides.hostBuilder.t3Builder.t0Builder.safeDIBuilder
		        let __safeDI_hostBuilder__hostBuilder_t3Builder_t0Builder_session_safeDIBuilder = safeDIOverrides.hostBuilder.t3Builder.t0Builder.session
		        let __safeDI_hostBuilder__safeDIBuilder = safeDIOverrides.hostBuilder.safeDIBuilder
		        @Sendable func __safeDI_hostBuilder() -> Host {
		            let session = if let safeDIBuilder = __safeDI_hostBuilder__hostBuilder_session_safeDIBuilder { safeDIBuilder() } else { Session() }
		            @Sendable func __safeDI_t3Builder(session: Session) -> T3 {
		                @Sendable func __safeDI_t0Builder() -> T0 {
		                    let session = if let safeDIBuilder = __safeDI_hostBuilder__hostBuilder_t3Builder_t0Builder_session_safeDIBuilder { safeDIBuilder() } else { Session() }
		                    let t3Builder = SendableInstantiator<T3> {
		                        __safeDI_t3Builder(session: session)
		                    }
		                    return if let safeDIBuilder = __safeDI_hostBuilder__hostBuilder_t3Builder_t0Builder_safeDIBuilder { safeDIBuilder(session, t3Builder) } else { T0(session: session, t3Builder: t3Builder) }
		                }
		                let t0Builder = SendableInstantiator<T0>(__safeDI_t0Builder)
		                return if let safeDIBuilder = __safeDI_hostBuilder__hostBuilder_t3Builder_safeDIBuilder { safeDIBuilder(session, t0Builder, __safeDI_hostBuilder__hostBuilder_t3Builder_flag()) } else { T3(session: session, t0Builder: t0Builder, flag: __safeDI_hostBuilder__hostBuilder_t3Builder_flag()) }
		            }
		            let t3Builder = SendableInstantiator<T3> {
		                __safeDI_t3Builder(session: session)
		            }
		            return if let safeDIBuilder = __safeDI_hostBuilder__safeDIBuilder { safeDIBuilder(session, t3Builder) } else { Host(session: session, t3Builder: t3Builder) }
		        }
		        let hostBuilder = SendableInstantiator<Host>(__safeDI_hostBuilder)
		        return App(hostBuilder: hostBuilder)
		    }
		}
		#endif
		"""])
		// The `T3` a step builds again receives the step's session, and every `T3` the mock builds reads `flag` from its
		// overrides.
		try expectDifferentialValuesAgree(
			feature: DifferentialValuePath(fixtureFiles: Self.fixtureFiles(fixture), generatedFiles: output.generatedFiles ?? [:]),
			knownRight: DifferentialValuePath(fixtureFiles: Self.fixtureFiles(fixture), generatedFiles: ["App+SafeDI.swift": """
			extension App {
			    public convenience init() {
			        self.init(hostBuilder: Self.hostBuilder(flag: 7))
			    }

			    struct SafeDIOverrides {
			        init(hostBuilder: HostOverrides = .init()) {
			            self.hostBuilder = hostBuilder
			        }

			        let hostBuilder: HostOverrides
			    }

			    struct HostOverrides {
			        init(t3Builder: T3Overrides = .init()) {
			            self.t3Builder = t3Builder
			        }

			        let t3Builder: T3Overrides
			    }

			    struct T3Overrides {
			        init(flag: Int = 7) {
			            self.flag = flag
			        }

			        let flag: Int
			    }

			    static func mock(safeDIOverrides: SafeDIOverrides = .init()) -> App {
			        App(hostBuilder: hostBuilder(flag: safeDIOverrides.hostBuilder.t3Builder.flag))
			    }

			    private static func hostBuilder(flag: Int) -> SendableInstantiator<Host> {
			        @Sendable func t3(session: Session) -> T3 {
			            T3(session: session, t0Builder: SendableInstantiator<T0> {
			                let stepSession = Session()
			                return T0(session: stepSession, t3Builder: SendableInstantiator<T3> { t3(session: stepSession) })
			            }, flag: flag)
			        }
			        return SendableInstantiator<Host> {
			            let session = Session()
			            return Host(session: session, t3Builder: SendableInstantiator<T3> { t3(session: session) })
			        }
			    }
			}
			"""]),
			probes: [
				DifferentialValueProbe("App()"),
				DifferentialValueProbe("App.mock()"),
				DifferentialValueProbe("App.mock(safeDIOverrides: .init(hostBuilder: .init(t3Builder: .init(flag: 9))))"),
			],
			filesToDelete: &filesToDelete,
		)
	}

	// MARK: Tests – Declarations that cannot be passed

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenScopeBetweenDeclaresLabelOfAnotherTypeThanRequiredReceive() async {
		let fixture = Self.instantiatorCycleFixture(t0Declares: "@Instantiated let t1Builder: Instantiator<Other>")
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["T3.swift"]):9:5: error: @Received property `t1Builder: Instantiator<T1>` is hidden in chain: Root -> Instantiator<T3> -> Instantiator<T0> -> T3. `T0` declares `t1Builder: Instantiator<Other>` with the same label, so the types below `T0` receive `t1Builder: Instantiator<Other>` instead. Give `t1Builder: Instantiator<Other>` on `T0` a different label to fix.
			\(fixtures["T0.swift"]):8:5: note: `t1Builder: Instantiator<Other>` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenScopeBetweenDeclaresConstantOfLabelReceivedAsInstantiator() async {
		let fixture = Self.instantiatorCycleFixture(t0Declares: "@Instantiated let t1Builder: T1")
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["T3.swift"]):9:5: error: @Received property `t1Builder: Instantiator<T1>` is hidden in chain: Root -> Instantiator<T3> -> Instantiator<T0> -> T3. `T0` declares `t1Builder: T1` with the same label, so the types below `T0` receive `t1Builder: T1` instead. Give `t1Builder: T1` on `T0` a different label to fix.
			\(fixtures["T0.swift"]):8:5: note: `t1Builder: T1` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenScopeInsideNestedCycleDeclaresLabelOfAnotherTypeThanRequiredReceive() async {
		await assertThrowsHiddenErrorOfNestedCycle(aReceives: "@Received let x: X", receivedProperty: "x: X")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenScopeInsideNestedCycleDeclaresLabelOfAnotherTypeThanOnlyIfAvailableReceiveAndScopeAboveProvidesIt() async {
		await assertThrowsHiddenErrorOfNestedCycle(aReceives: "@Received(onlyIfAvailable: true) let x: X?", receivedProperty: "x: X?")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenClosedOnTypeForwardsLabelThatOnlyScopeBetweenProvidesInFormItsTreeReceivesOnlyIfAvailable() async {
		await assertThrowsHiddenErrorOfClosedOnTypesOwnLabel(t3Declares: "@Forwarded let session: Session")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenClosedOnTypeInstantiatesLabelThatOnlyScopeBetweenProvidesInFormItsTreeReceivesOnlyIfAvailable() async {
		await assertThrowsHiddenErrorOfClosedOnTypesOwnLabel(t3Declares: "@Instantiated let session: Session")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenTypeBuiltAgainRedeclaresLabelThatOnlyScopeBetweenMakesAvailableToOnlyIfAvailableReceiveAboveIt() async {
		// Nothing above the first `A` provides `x`, so its receive, and `C`'s beneath `B`'s `x: Y`, are passed `nil`. `T0`
		// provides `x: X` above the `A` built again, whose receive then provides `x: X?` to `C`, which `B` hides, as it would
		// outside a cycle.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?", "@Instantiated let b: B", "@Instantiated let t0Builder: Instantiator<T0>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let c: C"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["C.swift"]):7:5: error: @Received property `x: X?` is hidden in chain: Root -> Instantiator<A> -> Instantiator<T0> -> Instantiator<A> -> B -> C. `B` declares `x: Y` with the same label, so the types below `B` receive `x: Y` instead. Give `x: Y` on `B` a different label to fix.
			\(fixtures["B.swift"]):8:5: note: `x: Y` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsCaptureError_whenCycleClosingScopeInSendableWrapperPassesInstantiatorDeclaredOutsideItToOnlyIfAvailableReceive() async {
		// Nothing above `T3` provides `yBuilder`, so the first `T3` is passed `nil`, and no receive in the closed-on function's
		// tree captures anything; the cycle-closing scope's own `SendableInstantiator` closure passes `T0`'s `yBuilder`.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let t3Builder: SendableInstantiator<T3>"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "T3", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let yBuilder: Instantiator<Y>?", "@Instantiated let t0Builder: Instantiator<T0>"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let yBuilder: Instantiator<Y>", "@Instantiated let t3Builder: SendableInstantiator<T3>"]),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["T3.swift"]):8:5: error: @Received property `yBuilder: Instantiator<Y>?` cannot be received inside a `@Sendable` function in chain: Root -> T3 -> T0 -> T3. SafeDI builds `t3Builder: SendableInstantiator<T3>` on `T0` in a `@Sendable` function, which cannot capture `yBuilder: Instantiator<Y>` on `T0`, because `Instantiator<Y>` is not `Sendable`. Declare `yBuilder` on `T0`, and this property, as `SendableInstantiator<Y>` to fix. `SendableInstantiator<Y>` builds `Y` in a `@Sendable` function, so what the tree of `Y` receives from outside that function must be `Sendable` too.
			\(fixtures["T0.swift"]):8:5: note: `yBuilder: Instantiator<Y>` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsCaptureError_whenCycleClosingScopeInsideSendableBuilderPassesInstantiatorDeclaredOutsideItToOnlyIfAvailableReceive() async {
		// Nothing above `T3` provides `yBuilder`, so the first `T3` is passed `nil`; the cycle-closing scope in `Z`'s `@Sendable`
		// builder function passes `T0`'s `yBuilder`, declared outside it.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T3", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let yBuilder: Instantiator<Y>?", "@Instantiated let t0Builder: Instantiator<T0>"]),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let yBuilder: Instantiator<Y>", "@Instantiated let zBuilder: SendableInstantiator<Z>"]),
			seamFixtureType(named: "Z", isFinalClass: true, declarations: ["@Instantiated let t3Builder: Instantiator<T3>"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["T3.swift"]):8:5: error: @Received property `yBuilder: Instantiator<Y>?` cannot be received inside a `@Sendable` function in chain: Root -> T3 -> T0 -> Z -> T3. SafeDI builds `zBuilder: SendableInstantiator<Z>` on `T0` in a `@Sendable` function, which cannot capture `yBuilder: Instantiator<Y>` on `T0`, because `Instantiator<Y>` is not `Sendable`. Declare `yBuilder` on `T0`, and this property, as `SendableInstantiator<Y>` to fix. `SendableInstantiator<Y>` builds `Y` in a `@Sendable` function, so what the tree of `Y` receives from outside that function must be `Sendable` too.
			\(fixtures["T0.swift"]):8:5: note: `yBuilder: Instantiator<Y>` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsCycleError_whenNearestDeclarationIsStillBeingBuiltAroundCycleClosingScope() async {
		// `T1` is built by `T0`'s `t1Builder` and builds `T3` again, which requires `t1Builder`: the nearest is the one being
		// built. `Host` is handed its `t1Builder`, so nothing else builds `T1` where `T3` receives it.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let hostBuilder: Instantiator<Host>"]),
			seamFixtureType(named: "Host", isFinalClass: true, declarations: ["@Forwarded let t1Builder: Instantiator<T1>", "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T3", isFinalClass: true, declarations: ["@Instantiated let t0Builder: Instantiator<T0>", "@Received let t1Builder: Instantiator<T1>"]),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let t1Builder: Instantiator<T1>"]),
			seamFixtureType(named: "T1", isFinalClass: true, declarations: ["@Instantiated let t3Builder: Instantiator<T3>"]),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["T3.swift"]):9:5: error: Dependency cycle: `Instantiator<T1>` -> `Instantiator<T3>` -> `Instantiator<T1>`. `T3` receives `t1Builder: Instantiator<T1>` inside the tree that `t1Builder` builds. Declare `t1Builder: Instantiator<T1>` on `T3` as @Instantiated instead of @Received.
			\(fixtures["T1.swift"]):1:1: note: `T1` is part of the cycle
			\(fixtures["T3.swift"]):1:1: note: `T3` is part of the cycle
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsCaptureError_whenCycleClosingScopeInsideSendableBuilderPassesInstantiatorDeclaredOutsideIt() async {
		// The cycle-closing scope in `Z`'s `@Sendable` builder function makes the function it closes on `@Sendable` too, and
		// passes `T0`'s `yBuilder`, declared outside `Z`'s function: the capture error, reported where the closed-on function's
		// tree first receives `yBuilder`. The function's body reads its parameter, and `Root` passes its `yBuilder` from a
		// closure that is not `@Sendable`, so neither captures `Root`'s.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let yBuilder: Instantiator<Y>", "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T3", isFinalClass: true, declarations: ["@Received let yBuilder: Instantiator<Y>", "@Instantiated let t0Builder: Instantiator<T0>"]),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let yBuilder: Instantiator<Y>", "@Instantiated let zBuilder: SendableInstantiator<Z>"]),
			seamFixtureType(named: "Z", isFinalClass: true, declarations: ["@Instantiated let t3Builder: Instantiator<T3>"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["T3.swift"]):8:5: error: @Received property `yBuilder: Instantiator<Y>` cannot be received inside a `@Sendable` function in chain: Root -> T3 -> T0 -> Z -> T3. SafeDI builds `zBuilder: SendableInstantiator<Z>` on `T0` in a `@Sendable` function, which cannot capture `yBuilder: Instantiator<Y>` on `T0`, because `Instantiator<Y>` is not `Sendable`. Declare `yBuilder` on `T0`, and this property, as `SendableInstantiator<Y>` to fix. `SendableInstantiator<Y>` builds `Y` in a `@Sendable` function, so what the tree of `Y` receives from outside that function must be `Sendable` too.
			\(fixtures["T0.swift"]):8:5: note: `yBuilder: Instantiator<Y>` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsCaptureError_whenSendableBuilderInClosedOnFunctionsBodyReceivesInstantiatorParameter() async {
		// `S`'s `@Sendable` builder function, inside the body of the function the cycle closes on, captures the function's
		// `yBuilder` parameter, which `Root` passes its own `yBuilder`: the capture error 2.2.0 reported for `Root`'s.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let yBuilder: Instantiator<Y>", "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T3", isFinalClass: true, declarations: ["@Instantiated let sBuilder: SendableInstantiator<S>", "@Instantiated let t0Builder: Instantiator<T0>"]),
			seamFixtureType(named: "S", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let yBuilder: Instantiator<Y>?"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let yBuilder: Instantiator<Y>", "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["S.swift"]):7:5: error: @Received property `yBuilder: Instantiator<Y>?` cannot be received inside a `@Sendable` function in chain: Root -> T3 -> S. SafeDI builds `sBuilder: SendableInstantiator<S>` on `T3` in a `@Sendable` function, which cannot capture `yBuilder: Instantiator<Y>` on `Root`, because `Instantiator<Y>` is not `Sendable`. Declare `yBuilder` on `Root`, and this property, as `SendableInstantiator<Y>` to fix. `SendableInstantiator<Y>` builds `Y` in a `@Sendable` function, so what the tree of `Y` receives from outside that function must be `Sendable` too.
			\(fixtures["Root.swift"]):8:5: note: `yBuilder: Instantiator<Y>` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsCaptureError_whenSendableBuilderInClosedOnFunctionsBodyReceivesParameterDeclaringScopeBuildsAfterCallingFunction() async {
		// `Root` builds its `yBuilder` after `aBuilder`, since `Y` receives `aBuilder`, so it passes the function the cycle
		// closes on `nil`, and `Mid`'s cycle-closing scope passes its own `yBuilder`: `Z`'s `@Sendable` builder function, inside
		// the function's body, captures the parameter whichever scope declares a `yBuilder` later.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let yBuilder: Instantiator<Y>"]),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: ["@Received let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let zBuilder: SendableInstantiator<Z>", "@Instantiated let midBuilder: Instantiator<Mid>"]),
			seamFixtureType(named: "Z", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let yBuilder: Instantiator<Y>?"]),
			seamFixtureType(named: "Mid", isFinalClass: true, declarations: ["@Forwarded let yBuilder: Instantiator<Y>", "@Instantiated let aBuilder: Instantiator<A>"]),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Z.swift"]):7:5: error: @Received property `yBuilder: Instantiator<Y>?` cannot be received inside a `@Sendable` function in chain: Root -> A -> Z. SafeDI builds `zBuilder: SendableInstantiator<Z>` on `A` in a `@Sendable` function, which cannot capture `yBuilder: Instantiator<Y>?`, which the tree of `Root` receives from outside it, because `Instantiator<Y>` is not `Sendable`. Declare `yBuilder` as `SendableInstantiator<Y>` where it is declared and where it is received as `Instantiator<Y>` to fix. `SendableInstantiator<Y>` builds `Y` in a `@Sendable` function, so what the tree of `Y` receives from outside that function must be `Sendable` too.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsCaptureError_whenDeclaringScopesSendableWrapperPassesInstantiatorDeclaredOutsideItToClosedOnFunction() async {
		// `Root`'s `SendableInstantiator` closure passes `Root`'s `yBuilder` to the function the cycle closes on, as 2.2.0's
		// function body read it from there: the capture error, reported where the function's tree first receives `yBuilder`.
		// `T0`'s cycle-closing scope passes `T0`'s from its own `SendableInstantiator` closure: the capture error too.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let yBuilder: Instantiator<Y>", "@Instantiated let t3Builder: SendableInstantiator<T3>"]),
			seamFixtureType(named: "T3", isFinalClass: true, declarations: ["@Instantiated let w: W", "@Instantiated let t0Builder: Instantiator<T0>"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "W", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let yBuilder: Instantiator<Y>?"]),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let yBuilder: Instantiator<Y>", "@Instantiated let t3Builder: SendableInstantiator<T3>"]),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["W.swift"]):7:5: error: @Received property `yBuilder: Instantiator<Y>?` cannot be received inside a `@Sendable` function in chain: Root -> T3 -> T0 -> T3 -> W. SafeDI builds `t3Builder: SendableInstantiator<T3>` on `T0` in a `@Sendable` function, which cannot capture `yBuilder: Instantiator<Y>` on `T0`, because `Instantiator<Y>` is not `Sendable`. Declare `yBuilder` on `T0`, and this property, as `SendableInstantiator<Y>` to fix. `SendableInstantiator<Y>` builds `Y` in a `@Sendable` function, so what the tree of `Y` receives from outside that function must be `Sendable` too.
			\(fixtures["T0.swift"]):8:5: note: `yBuilder: Instantiator<Y>` is declared here
			\(fixtures["W.swift"]):7:5: error: @Received property `yBuilder: Instantiator<Y>?` cannot be received inside a `@Sendable` function in chain: Root -> T3 -> W. SafeDI builds `t3Builder: SendableInstantiator<T3>` on `Root` in a `@Sendable` function, which cannot capture `yBuilder: Instantiator<Y>` on `Root`, because `Instantiator<Y>` is not `Sendable`. Declare `yBuilder` on `Root`, and this property, as `SendableInstantiator<Y>` to fix. `SendableInstantiator<Y>` builds `Y` in a `@Sendable` function, so what the tree of `Y` receives from outside that function must be `Sendable` too.
			\(fixtures["Root.swift"]):8:5: note: `yBuilder: Instantiator<Y>` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Root` instantiates `t1Builder: Instantiator<T1>` and `t3Builder: Instantiator<T3>`; `T3` instantiates `t0Builder` and
	/// receives `t1Builder`; `T0` declares `t0Declares` and instantiates `T3` again.
	private static func instantiatorCycleFixture(t0Declares: String) -> [String] {
		[
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let t1Builder: Instantiator<T1>", "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T3", isFinalClass: true, declarations: ["@Instantiated let t0Builder: Instantiator<T0>", "@Received let t1Builder: Instantiator<T1>"]),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: [t0Declares, "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T1", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Other", isFinalClass: true, declarations: []),
		]
	}

	/// Expects the hidden-label error at `A`'s receive `aReceives` of `x` where nested lazy cycles build `A` again beneath `C`,
	/// which declares `x` as another type: `Root` instantiates `x: X` and `A`; `A` instantiates `B`, which instantiates `C` and
	/// `A` again; `C` instantiates `x: Y` and `B` again. The `B` built again beneath `C` builds `A` again with `C`'s `x`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func assertThrowsHiddenErrorOfNestedCycle(aReceives: String, receivedProperty: String, sourceLocation: SourceLocation = #_sourceLocation) async {
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: [aReceives, "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let cBuilder: Instantiator<C>", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["A.swift"]):8:5: error: @Received property `\(receivedProperty)` is hidden in chain: Root -> Instantiator<A> -> Instantiator<B> -> Instantiator<C> -> Instantiator<B> -> A. `C` declares `x: Y` with the same label, so the types below `C` receive `x: Y` instead. Give `x: Y` on `C` a different label to fix.
			\(fixtures["C.swift"]):8:5: note: `x: Y` is declared here
			"""
		}, sourceLocation: sourceLocation) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	/// `Root` instantiates `t3Builder: Instantiator<T3>`; `T3` declares `t3Declares`, a `session`, instantiates `Child`, which
	/// receives `session: Instantiator<Session>?` only if available, and `t0Builder`; `T0` declares `t0Declares`, a `session`,
	/// and instantiates `T3` again.
	private static func closedOnTypesOwnLabelFixture(t3Declares: String, t0Declares: String) -> [String] {
		[
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T3", isFinalClass: true, declarations: [t3Declares, "@Instantiated let child: Child", "@Instantiated let t0Builder: Instantiator<T0>"]),
			seamFixtureType(named: "Child", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let session: Instantiator<Session>?"]),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: [t0Declares, "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Other", isFinalClass: true, declarations: []),
		]
	}

	/// Expects the hidden-label error at `Child`'s receive of `closedOnTypesOwnLabelFixture` with `T0` declaring
	/// `session: Instantiator<Session>`: nothing above the first `T3` provides that form, so the first `Child` is passed
	/// `nil`, but `T0` provides it above the `T3` built again, whose own `session` hides it from `Child`, as outside a cycle.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func assertThrowsHiddenErrorOfClosedOnTypesOwnLabel(t3Declares: String, sourceLocation: SourceLocation = #_sourceLocation) async {
		let fixture = Self.closedOnTypesOwnLabelFixture(t3Declares: t3Declares, t0Declares: "@Instantiated let session: Instantiator<Session>")
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Child.swift"]):7:5: error: @Received property `session: Instantiator<Session>?` is hidden in chain: Root -> Instantiator<T3> -> Instantiator<T0> -> Instantiator<T3> -> Child. `T3` declares `session: Session` with the same label, so the types below `T3` receive `session: Session` instead. Give `session: Session` on `T3` a different label to fix.
			\(fixtures["T3.swift"]):9:5: note: `session: Session` is declared here
			"""
		}, sourceLocation: sourceLocation) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	/// Expects the tree of a graph whose function the cycle closes on is `@Sendable` only because a cycle-closing scope in a
	/// `@Sendable` builder function refers to it: `Root` instantiates `t3Builder: Instantiator<T3>`, and its own `yBuilder` when
	/// `rootDeclaresYBuilder`; `T3` instantiates `w: W`, which receives `yBuilder: Instantiator<Y>?` only if available, and
	/// `t0Builder`; `T0` instantiates `zBuilder: SendableInstantiator<Z>`; `Z` instantiates its own `yBuilder` and `T3` again.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectSendableOnlyThroughCycleTree(rootDeclaresYBuilder: Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
		let rootYBuilder = rootDeclaresYBuilder ? ["@Instantiated let yBuilder: Instantiator<Y>"] : []
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: rootYBuilder + ["@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T3", isFinalClass: true, declarations: ["@Instantiated let w: W", "@Instantiated let t0Builder: Instantiator<T0>"]),
			seamFixtureType(named: "W", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let yBuilder: Instantiator<Y>?"]),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let zBuilder: SendableInstantiator<Z>"]),
			seamFixtureType(named: "Z", isFinalClass: true, declarations: ["@Instantiated let yBuilder: Instantiator<Y>", "@Instantiated let t3Builder: Instantiator<T3>"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
		let rootYBuilderDeclaration = rootDeclaresYBuilder ? """
		        func __safeDI_yBuilder() -> Y {
		            Y()
		        }
		        let yBuilder = Instantiator<Y>(__safeDI_yBuilder)

		""" : ""
		let rootArgument = rootDeclaresYBuilder ? "yBuilder" : "nil"
		let rootInitializerArguments = rootDeclaresYBuilder ? "yBuilder: yBuilder, t3Builder: t3Builder" : "t3Builder: t3Builder"
		let handBuiltRootYBuilder = rootDeclaresYBuilder ? "        let yBuilder = Instantiator<Y> { Y() }\n" : ""
		let handBuiltRootInitializerArguments = rootDeclaresYBuilder ? "yBuilder: yBuilder, t3Builder: Instantiator<T3> { t3(yBuilder: yBuilder) }" : "t3Builder: Instantiator<T3> { t3(yBuilder: nil) }"
		try await expectGeneratedTree(of: fixture, root: "Root", equals: """
		extension Root {
		    public convenience init() {
		\(rootYBuilderDeclaration)        @Sendable func __safeDI_t3Builder(yBuilder: Instantiator<Y>?) -> T3 {
		            let w = W(yBuilder: yBuilder)
		            func __safeDI_t0Builder() -> T0 {
		                @Sendable func __safeDI_zBuilder() -> Z {
		                    func __safeDI_yBuilder() -> Y {
		                        Y()
		                    }
		                    let yBuilder = Instantiator<Y>(__safeDI_yBuilder)
		                    let t3Builder = Instantiator<T3> {
		                        __safeDI_t3Builder(yBuilder: yBuilder)
		                    }
		                    return Z(yBuilder: yBuilder, t3Builder: t3Builder)
		                }
		                let zBuilder = SendableInstantiator<Z>(__safeDI_zBuilder)
		                return T0(zBuilder: zBuilder)
		            }
		            let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
		            return T3(w: w, t0Builder: t0Builder)
		        }
		        let t3Builder = Instantiator<T3> {
		            __safeDI_t3Builder(yBuilder: \(rootArgument))
		        }
		        self.init(\(rootInitializerArguments))
		    }
		}
		""", buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        @Sendable func t3(yBuilder: Instantiator<Y>?) -> T3 {
		            T3(w: W(yBuilder: yBuilder), t0Builder: Instantiator<T0> {
		                T0(zBuilder: SendableInstantiator<Z> {
		                    let zYBuilder = Instantiator<Y> { Y() }
		                    return Z(yBuilder: zYBuilder, t3Builder: Instantiator<T3> { t3(yBuilder: zYBuilder) })
		                })
		            })
		        }
		\(handBuiltRootYBuilder)        self.init(\(handBuiltRootInitializerArguments))
		    }
		}
		""", sourceLocation: sourceLocation)
	}

	/// The body of a hand-built tree of `instantiatorCycleFixture` with `T0` declaring its own `t1Builder`, which builds the
	/// type `name` with `returning`: as `Root`'s initializer, or as a mock of `Root` or of `Feature`, which receives
	/// `t3Builder` and a `T1` of its own under the same label.
	private static func handBuiltInstantiatorCycle(name: String, returning: String) -> String {
		let body = """
		        func t3(t1Builder: Instantiator<T1>) -> T3 {
		            T3(t0Builder: Instantiator<T0> {
		                let t0T1Builder = Instantiator<T1> { T1() }
		                return T0(t1Builder: t0T1Builder, t3Builder: Instantiator<T3> { t3(t1Builder: t0T1Builder) })
		            }, t1Builder: t1Builder)
		        }
		        let t1Builder = Instantiator<T1> { T1() }
		        let t3Builder = Instantiator<T3> { t3(t1Builder: t1Builder) }
		"""
		let construction = name == "Feature"
			? "        \(returning)(t3Builder: t3Builder, t1Builder: T1())"
			: "        \(returning)(t1Builder: t1Builder, t3Builder: t3Builder)"
		guard returning == "self.init" else { return body + "\n" + construction }
		return """
		extension \(name) {
		    public convenience init() {
		\(body)
		\(construction)
		    }
		}
		"""
	}

	/// Generates `fixture`, expects `root`'s generated tree to be `expectedTree` and, when `root` generates a mock, its mock
	/// to be `expectedMock`, and compares the values each builds, through `probes`, with those `handBuiltTree` builds: the
	/// mock's, through `root.mock()`, with those of the hand-built tree, which a mock of the root builds alike.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectGeneratedTree(
		of fixture: [String],
		root: String,
		equals expectedTree: (FixturePaths) -> String,
		mock expectedMock: ((FixturePaths) -> String)? = nil,
		buildsTheSameValuesAs handBuiltTree: String,
		probes: [DifferentialValueProbe]? = nil,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == ["\(root)+SafeDI.swift": generatedFileHeader + expectedTree(output.fixtures)], sourceLocation: sourceLocation)
		#expect(output.mockFiles == (expectedMock.map { ["\(root)+SafeDIMock.swift": generatedFileHeader + $0(output.fixtures)] } ?? [:]), sourceLocation: sourceLocation)
		try expectDifferentialValuesAgree(
			feature: DifferentialValuePath(fixtureFiles: Self.fixtureFiles(fixture), generatedFiles: output.generatedFiles ?? [:]),
			knownRight: DifferentialValuePath(fixtureFiles: Self.fixtureFiles(fixture), generatedFiles: [
				"\(root)+SafeDI.swift": handBuiltTree + (expectedMock == nil ? "" : "\n\nextension \(root) {\n    static func mock() -> \(root) {\n        \(root)()\n    }\n}"),
			]),
			probes: (probes ?? [DifferentialValueProbe("\(root)()")]) + (expectedMock == nil ? [] : [DifferentialValueProbe("\(root).mock()")]),
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectGeneratedTree(
		of fixture: [String],
		root: String,
		equals expectedTree: String,
		mock expectedMock: String? = nil,
		buildsTheSameValuesAs handBuiltTree: String,
		probes: [DifferentialValueProbe]? = nil,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		try await expectGeneratedTree(
			of: fixture,
			root: root,
			equals: { _ in expectedTree },
			mock: expectedMock.map { expectedMock in { _ in expectedMock } },
			buildsTheSameValuesAs: handBuiltTree,
			probes: probes,
			sourceLocation: sourceLocation,
		)
	}

	/// `files` named as `executeSafeDIToolTest` names them, after the type each declares.
	private static func fixtureFiles(_ files: [String]) -> [String: String] {
		var fixtureFiles = [String: String]()
		for file in files {
			let name = file.split(separator: "\n").compactMap { line -> String? in
				guard let classRange = line.range(of: "final class ") else { return nil }
				return String(line[classRange.upperBound...].prefix { $0 != ":" })
			}.first ?? "File"
			fixtureFiles["\(name).swift"] = file
		}
		return fixtureFiles
	}
}
