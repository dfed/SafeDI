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

		        private(set) var session: (() -> Session)?
		        private(set) var t3Builder: T3.SafeDIMockConfiguration
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

		        private(set) var session: (() -> Session)?
		        private(set) var t3Builder: T3.SafeDIMockConfiguration
		        private(set) var logger: ((Instantiator<T3>?) -> Logger)?
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

		        private(set) var session: (() -> Session)?
		        private(set) var screenBuilder: Screen.SafeDIMockConfiguration
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
		        @Sendable nonisolated func __safeDI_screenBuilder(session: Session) -> Screen {
		            @Sendable nonisolated func __safeDI_stepBuilder() -> Step {
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

		        private(set) var session: (() -> Session)?
		        private(set) var screenBuilder: Screen.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> App {
		        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
		        let __safeDI_screenBuilder__screenBuilder_stepBuilder_safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.safeDIBuilder
		        let __safeDI_screenBuilder__screenBuilder_stepBuilder_session_safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.session
		        let __safeDI_screenBuilder__safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder
		        @Sendable nonisolated func __safeDI_screenBuilder(session: Session) -> Screen {
		            @Sendable nonisolated func __safeDI_stepBuilder() -> Step {
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

		        private(set) var session: (() -> Session)?
		        private(set) var screenBuilder: Screen.SafeDIMockConfiguration
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

		        private(set) var session: (() -> Session)?
		        private(set) var screenBuilder: Screen.SafeDIMockConfiguration
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

			        private(set) var t1Builder_Instantiator__T1: (() -> T1)?
			        private(set) var t3Builder: T3.SafeDIMockConfiguration
			        private(set) var t1Builder_T1: (() -> T1)?
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

			        private(set) var t1Builder: (() -> T1)?
			        private(set) var t3Builder: T3.SafeDIMockConfiguration
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

		        private(set) var hostBuilder: Host.SafeDIMockConfiguration
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
		        @Sendable nonisolated func __safeDI_hostBuilder() -> Host {
		            let session = if let safeDIBuilder = __safeDI_hostBuilder__hostBuilder_session_safeDIBuilder { safeDIBuilder() } else { Session() }
		            @Sendable nonisolated func __safeDI_t3Builder(session: Session) -> T3 {
		                @Sendable nonisolated func __safeDI_t0Builder() -> T0 {
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

			        private(set) var hostBuilder: HostOverrides
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

	// MARK: Tests – An onlyIfAvailable alias of a parameter's label

	// `A` receives `renamed` only if available, and `Mid`, between `A`'s builder function and the scope that builds `A`
	// again, declares an `onlyIfAvailable` alias `renamed` of its `x`, whose `X` receives `renamed` only if available: the
	// function takes `renamed`. Where nothing above the function provides `renamed`, the parameter does not keep the alias
	// from being created, as nothing does where the function takes no parameter: `Mid` builds `x` first, passing `X` `nil`,
	// creates the alias from it, and passes the alias to the `A` it builds again.

	@Test(arguments: CycleClosingWrapper.allCases, AliasPosition.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsAliasOfParameterLabelAfterItsFulfillingSibling_whenNothingAboveClosedOnFunctionProvidesLabel(wrapper: CycleClosingWrapper, aliasPosition: AliasPosition) async throws {
		try await expectGeneratedTree(
			of: Self.aliasOfParameterLabelFixture(wrapper: wrapper, aliasPosition: aliasPosition),
			root: "Root",
			equals: { Self.expectedAliasOfParameterLabelTree(wrapper: wrapper, aliasPosition: aliasPosition, fixtures: $0) },
			mock: { Self.expectedAliasOfParameterLabelMock(wrapper: wrapper, aliasPosition: aliasPosition, fixtures: $0) },
			buildsTheSameValuesAs: Self.handBuiltAliasOfParameterLabelTree(wrapper: wrapper, aliasPosition: aliasPosition),
			probes: wrapper.isErased ? ["Root()", "Root.mock()"].map { root in
				// An `ErasedInstantiator` is not traversed, so each probe holds the `A` built first, its `Mid`, and the `A` that
				// `Mid` builds again.
				let mid = "(\(root).aBuilder.instantiate().a as! A).midBuilder.instantiate()"
				let aBuiltAgain = aliasPosition == .aboveCycleClosingScopesType ? "mid.innerBuilder.instantiate().aBuilder" : "mid.aBuilder"
				return DifferentialValueProbe(#"{ () -> (Mid, A) in let mid = \#(mid); return (mid, \#(aBuiltAgain).instantiate().a as! A) }()"#)
			} : nil,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsAliasOfParameterLabelAfterItsFulfillingSibling_whenScopeAboveClosedOnFunctionProvidesLabelOnlyAsLazilyInstantiatedInstance() async throws {
		// The instance of `Root`'s `renamed` does not keep an alias of `renamed` from being created, as a declaration whose label
		// hides the wrapper it is read from, so `Mid` creates its alias, though `Root` passes the function `renamed.instance`.
		let fixture = Self.aliasOfParameterLabelFixture(rootDeclares: ["@Instantiated let renamed: LazilyInstantiated<X>"])
		try await expectGeneratedTree(of: fixture, root: "Root", equals: { fixtures in """
		extension Root {
		    public convenience init() {
		        func __safeDI_renamed() -> X {
		            X(renamed: nil)
		        }
		        let renamed = LazilyInstantiated<X>(__safeDI_renamed)
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                let x = X(renamed: nil)
		                #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 10)
		                let renamed: X? = x
		                #sourceLocation()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return Mid(x: x, renamed: renamed, aBuilder: aBuilder)
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return A(renamed: renamed, midBuilder: midBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed.instance)
		        }
		        self.init(renamed: renamed, aBuilder: aBuilder)
		    }
		}
		""" }, mock: { fixtures in """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            renamed: ((X?) -> X)? = nil,
		            aBuilder: A.SafeDIMockConfiguration = .init()
		        ) {
		            self.renamed = renamed
		            self.aBuilder = aBuilder
		        }

		        private(set) var renamed: ((X?) -> X)?
		        private(set) var aBuilder: A.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_renamed() -> X {
		            if let safeDIBuilder = safeDIOverrides.renamed { safeDIBuilder(nil) } else { X(renamed: nil) }
		        }
		        let renamed = LazilyInstantiated<X>(__safeDI_renamed)
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                let x = if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.x { safeDIBuilder(nil) } else { X(renamed: nil) }
		                #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 10)
		                let renamed: X? = x
		                #sourceLocation()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(x, renamed, aBuilder) } else { Mid(x: x, renamed: renamed, aBuilder: aBuilder) }
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(renamed, midBuilder) } else { A(renamed: renamed, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed.instance)
		        }
		        return Root(renamed: renamed, aBuilder: aBuilder)
		    }
		}
		#endif
		""" }, buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func a(renamed: X?) -> A {
		            A(renamed: renamed, midBuilder: Instantiator<Mid> {
		                let x = X(renamed: nil)
		                return Mid(x: x, renamed: x, aBuilder: Instantiator<A> { a(renamed: x) })
		            })
		        }
		        let renamed = LazilyInstantiated<X> { X(renamed: nil) }
		        self.init(renamed: renamed, aBuilder: Instantiator<A> { a(renamed: renamed.instance) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearerAliasToFunctionBuiltAgain_whenScopeAboveClosedOnFunctionInstantiatesLabel() async throws {
		// `Root`'s `renamed` is the nearest declaration of the alias's label above the function, but `Mid`'s alias is a nearer
		// one, bound from `Mid`'s `x`, which is built first and passed `nil` for the alias it waits on. `Mid` and the `A` built
		// again are handed `Mid`'s alias.
		let fixture = Self.aliasOfParameterLabelFixture(rootDeclares: ["@Instantiated let renamed: X"])
		try await expectGeneratedTree(of: fixture, root: "Root", equals: { fixtures in """
		extension Root {
		    public convenience init() {
		        let renamed = X(renamed: nil)
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                let x = X(renamed: nil)
		                #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 10)
		                let renamed: X? = x
		                #sourceLocation()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return Mid(x: x, renamed: renamed, aBuilder: aBuilder)
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return A(renamed: renamed, midBuilder: midBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        self.init(renamed: renamed, aBuilder: aBuilder)
		    }
		}
		""" }, mock: { fixtures in """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            renamed: ((X?) -> X)? = nil,
		            aBuilder: A.SafeDIMockConfiguration = .init()
		        ) {
		            self.renamed = renamed
		            self.aBuilder = aBuilder
		        }

		        private(set) var renamed: ((X?) -> X)?
		        private(set) var aBuilder: A.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let renamed = if let safeDIBuilder = safeDIOverrides.renamed { safeDIBuilder(nil) } else { X(renamed: nil) }
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                let x = if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.x { safeDIBuilder(nil) } else { X(renamed: nil) }
		                #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 10)
		                let renamed: X? = x
		                #sourceLocation()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(x, renamed, aBuilder) } else { Mid(x: x, renamed: renamed, aBuilder: aBuilder) }
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(renamed, midBuilder) } else { A(renamed: renamed, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        return Root(renamed: renamed, aBuilder: aBuilder)
		    }
		}
		#endif
		""" }, buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        let renamed = X(renamed: nil)
		        func a(renamed: X?) -> A {
		            A(renamed: renamed, midBuilder: Instantiator<Mid> {
		                let x = X(renamed: nil)
		                return Mid(x: x, renamed: x, aBuilder: Instantiator<A> { a(renamed: x) })
		            })
		        }
		        self.init(renamed: renamed, aBuilder: Instantiator<A> { a(renamed: renamed) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearerAliasToRequiredParameter_whenScopeAboveClosedOnFunctionAliasesLabel() async throws {
		// `A` requires `renamed`, which `Root`'s alias provides above the function, so the parameter is required. `Mid`'s
		// alias is a nearer declaration of the label, bound from `Mid`'s `x`, and the `A` built again is handed it.
		let fixture = Self.aliasOfParameterLabelFixture(
			rootDeclares: ["@Instantiated let x0: X", #"@Received(fulfilledByDependencyNamed: "x0", ofType: X.self, onlyIfAvailable: true) let renamed: X?"#],
			aReceives: "@Received let renamed: X?",
		)
		try await expectGeneratedTree(of: fixture, root: "Root", equals: { fixtures in """
		extension Root {
		    public convenience init() {
		        let x0 = X(renamed: nil)
		        #sourceLocation(file: "\(fixtures["Root.swift"])", line: 10)
		        let renamed: X? = x0
		        #sourceLocation()
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                let x = X(renamed: nil)
		                #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 10)
		                let renamed: X? = x
		                #sourceLocation()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return Mid(x: x, renamed: renamed, aBuilder: aBuilder)
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return A(renamed: renamed, midBuilder: midBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        self.init(x0: x0, renamed: renamed, aBuilder: aBuilder)
		    }
		}
		""" }, mock: { fixtures in """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            x0: ((X?) -> X)? = nil,
		            aBuilder: A.SafeDIMockConfiguration = .init()
		        ) {
		            self.x0 = x0
		            self.aBuilder = aBuilder
		        }

		        private(set) var x0: ((X?) -> X)?
		        private(set) var aBuilder: A.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let x0 = if let safeDIBuilder = safeDIOverrides.x0 { safeDIBuilder(nil) } else { X(renamed: nil) }
		        #sourceLocation(file: "\(fixtures["Root.swift"])", line: 10)
		        let renamed: X? = x0
		        #sourceLocation()
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                let x = if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.x { safeDIBuilder(nil) } else { X(renamed: nil) }
		                #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 10)
		                let renamed: X? = x
		                #sourceLocation()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(x, renamed, aBuilder) } else { Mid(x: x, renamed: renamed, aBuilder: aBuilder) }
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(renamed, midBuilder) } else { A(renamed: renamed, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        return Root(x0: x0, renamed: renamed, aBuilder: aBuilder)
		    }
		}
		#endif
		""" }, buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        let x0 = X(renamed: nil)
		        func a(renamed: X?) -> A {
		            A(renamed: renamed, midBuilder: Instantiator<Mid> {
		                let x = X(renamed: nil)
		                return Mid(x: x, renamed: x, aBuilder: Instantiator<A> { a(renamed: x) })
		            })
		        }
		        self.init(x0: x0, renamed: x0, aBuilder: Instantiator<A> { a(renamed: x0) })
		    }
		}
		""")
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsCreatedAliasToSiblingBuiltAfterIt_whenNothingAboveClosedOnFunctionProvidesParameterLabel(siblingRequiresAlias: Bool) async throws {
		// `Mid`'s `y` receives the alias, required or only if available, so it is built after the alias, which it is handed.
		// A requirement of the alias does not make the parameter required: `Root` passes `nil`.
		let fixture = Self.aliasOfParameterLabelFixture(
			midDeclaresBesideAlias: ["@Instantiated let y: Y"],
			otherTypes: [seamFixtureType(named: "Y", isFinalClass: true, declarations: [siblingRequiresAlias ? "@Received let renamed: X?" : "@Received(onlyIfAvailable: true) let renamed: X?"])],
		)
		try await expectGeneratedTree(of: fixture, root: "Root", equals: { fixtures in """
		extension Root {
		    public convenience init() {
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                let x = X(renamed: nil)
		                #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 11)
		                let renamed: X? = x
		                #sourceLocation()
		                let y = Y(renamed: renamed)
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return Mid(x: x, renamed: renamed, y: y, aBuilder: aBuilder)
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return A(renamed: renamed, midBuilder: midBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: nil)
		        }
		        self.init(aBuilder: aBuilder)
		    }
		}
		""" }, mock: { fixtures in """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            aBuilder: A.SafeDIMockConfiguration = .init(),
		            renamed: X? = nil
		        ) {
		            self.aBuilder = aBuilder
		            self.renamed = renamed
		        }

		        private(set) var aBuilder: A.SafeDIMockConfiguration
		        private(set) var renamed: X?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let renamed: X? = safeDIOverrides.renamed
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                let x = if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.x { safeDIBuilder(nil) } else { X(renamed: nil) }
		                #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 11)
		                let renamed: X? = x
		                #sourceLocation()
		                let y = if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.y { safeDIBuilder(renamed) } else { Y(renamed: renamed) }
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(x, renamed, y, aBuilder) } else { Mid(x: x, renamed: renamed, y: y, aBuilder: aBuilder) }
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(renamed, midBuilder) } else { A(renamed: renamed, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        return Root(aBuilder: aBuilder)
		    }
		}
		#endif
		""" }, buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func a(renamed: X?) -> A {
		            A(renamed: renamed, midBuilder: Instantiator<Mid> {
		                let x = X(renamed: nil)
		                return Mid(x: x, renamed: x, y: Y(renamed: x), aBuilder: Instantiator<A> { a(renamed: x) })
		            })
		        }
		        self.init(aBuilder: Instantiator<A> { a(renamed: nil) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsAliasOfParameterLabelAfterItsFulfillingInstantiator_whenNothingAboveClosedOnFunctionProvidesLabel() async throws {
		let fixture = Self.aliasOfParameterLabelFixture(
			labelType: "Instantiator<X>",
			midFulfillingDeclaration: "@Instantiated let xBuilder: Instantiator<X>",
		)
		try await expectGeneratedTree(of: fixture, root: "Root", equals: { fixtures in """
		extension Root {
		    public convenience init() {
		        func __safeDI_aBuilder(renamed: Instantiator<X>?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                func __safeDI_xBuilder() -> X {
		                    X(renamed: nil)
		                }
		                let xBuilder = Instantiator<X>(__safeDI_xBuilder)
		                #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 10)
		                let renamed: Instantiator<X>? = xBuilder
		                #sourceLocation()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return Mid(xBuilder: xBuilder, renamed: renamed, aBuilder: aBuilder)
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return A(renamed: renamed, midBuilder: midBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: nil)
		        }
		        self.init(aBuilder: aBuilder)
		    }
		}
		""" }, mock: { fixtures in """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            aBuilder: A.SafeDIMockConfiguration = .init(),
		            renamed: Instantiator<X>? = nil
		        ) {
		            self.aBuilder = aBuilder
		            self.renamed = renamed
		        }

		        private(set) var aBuilder: A.SafeDIMockConfiguration
		        private(set) var renamed: Instantiator<X>?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let renamed: Instantiator<X>? = safeDIOverrides.renamed
		        func __safeDI_aBuilder(renamed: Instantiator<X>?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                func __safeDI_xBuilder() -> X {
		                    if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.xBuilder { safeDIBuilder(nil) } else { X(renamed: nil) }
		                }
		                let xBuilder = Instantiator<X>(__safeDI_xBuilder)
		                #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 10)
		                let renamed: Instantiator<X>? = xBuilder
		                #sourceLocation()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(xBuilder, renamed, aBuilder) } else { Mid(xBuilder: xBuilder, renamed: renamed, aBuilder: aBuilder) }
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(renamed, midBuilder) } else { A(renamed: renamed, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        return Root(aBuilder: aBuilder)
		    }
		}
		#endif
		""" }, buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func a(renamed: Instantiator<X>?) -> A {
		            A(renamed: renamed, midBuilder: Instantiator<Mid> {
		                let xBuilder = Instantiator<X> { X(renamed: nil) }
		                return Mid(xBuilder: xBuilder, renamed: xBuilder, aBuilder: Instantiator<A> { a(renamed: xBuilder) })
		            })
		        }
		        self.init(aBuilder: Instantiator<A> { a(renamed: nil) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsAliasOfExistentialParameterLabelAfterItsFulfillingSibling_whenNothingAboveClosedOnFunctionProvidesLabel() async throws {
		let fixture = Self.aliasOfParameterLabelFixture(
			labelType: "any XProtocol",
			midFulfillingDeclaration: #"@Instantiated(fulfilledByType: "X") let x: any XProtocol"#,
		)
		try await expectGeneratedTree(of: fixture, root: "Root", equals: { fixtures in """
		extension Root {
		    public convenience init() {
		        func __safeDI_aBuilder(renamed: (any XProtocol)?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                let x: any XProtocol = X(renamed: nil)
		                #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 10)
		                let renamed: (any XProtocol)? = x
		                #sourceLocation()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return Mid(x: x, renamed: renamed, aBuilder: aBuilder)
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return A(renamed: renamed, midBuilder: midBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: nil)
		        }
		        self.init(aBuilder: aBuilder)
		    }
		}
		""" }, mock: { fixtures in """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            aBuilder: A.SafeDIMockConfiguration = .init(),
		            renamed: (any XProtocol)? = nil
		        ) {
		            self.aBuilder = aBuilder
		            self.renamed = renamed
		        }

		        private(set) var aBuilder: A.SafeDIMockConfiguration
		        private(set) var renamed: (any XProtocol)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let renamed: (any XProtocol)? = safeDIOverrides.renamed
		        func __safeDI_aBuilder(renamed: (any XProtocol)?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                let x: XProtocol = if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.x { safeDIBuilder(nil) } else { X(renamed: nil) }
		                #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 10)
		                let renamed: (any XProtocol)? = x
		                #sourceLocation()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(x, renamed, aBuilder) } else { Mid(x: x, renamed: renamed, aBuilder: aBuilder) }
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(renamed, midBuilder) } else { A(renamed: renamed, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        return Root(aBuilder: aBuilder)
		    }
		}
		#endif
		""" }, buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func a(renamed: (any XProtocol)?) -> A {
		            A(renamed: renamed, midBuilder: Instantiator<Mid> {
		                let x: any XProtocol = X(renamed: nil)
		                return Mid(x: x, renamed: x, aBuilder: Instantiator<A> { a(renamed: x) })
		            })
		        }
		        self.init(aBuilder: Instantiator<A> { a(renamed: nil) })
		    }
		}
		""")
	}

	@Test(arguments: LabelSpelling.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsAliasOfParameterLabelAfterItsFulfillingSibling_whenNothingAboveClosedOnFunctionProvidesLabelSpelledThroughAnotherName(spelling: LabelSpelling) async throws {
		// `renamed` is a nested type, `Feature.X`, or a typealias of `X`, spelled so wherever it is declared or received.
		let fixture = Self.aliasOfParameterLabelFixture(
			labelType: spelling.labelType,
			midFulfillingDeclaration: spelling.fulfillingDeclaration,
			xEnclosingType: spelling == .nestedType ? "Feature" : nil,
			otherTypes: [spelling.declaration],
		)
		try await expectGeneratedTree(
			of: fixture,
			root: "Root",
			equals: { Self.expectedSpelledAliasOfParameterLabelTree(spelling: spelling, fixtures: $0) },
			mock: { Self.expectedSpelledAliasOfParameterLabelMock(spelling: spelling, fixtures: $0) },
			buildsTheSameValuesAs: """
			extension Root {
			    public convenience init() {
			        func a(renamed: \(spelling.labelType)?) -> A {
			            A(renamed: renamed, midBuilder: Instantiator<Mid> {
			                let x: \(spelling.labelType) = \(spelling.constructedType)(renamed: nil)
			                return Mid(x: x, renamed: x, aBuilder: Instantiator<A> { a(renamed: x) })
			            })
			        }
			        self.init(aBuilder: Instantiator<A> { a(renamed: nil) })
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsAliasOfLabelNestedClosedOnFunctionsTake_whenNothingAboveOuterFunctionProvidesLabel() async throws {
		// `B`'s builder function, inside `A`'s, takes `renamed` too, which `A`'s function passes its own parameter: that
		// parameter provides nothing above `B`'s function either, so `Mid`, beneath both, creates its alias.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"])
				.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: true)"),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let renamed: X?", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let renamed: X?", "@Instantiated let midBuilder: Instantiator<Mid>"]),
			seamFixtureType(named: "Mid", isFinalClass: true, declarations: [
				"@Instantiated let x: X",
				#"@Received(fulfilledByDependencyNamed: "x", ofType: X.self, onlyIfAvailable: true) let renamed: X?"#,
				"@Instantiated let bBuilder: Instantiator<B>",
				"@Instantiated let aBuilder: Instantiator<A>",
			]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let renamed: X?"]),
		]
		try await expectGeneratedTree(of: fixture, root: "Root", equals: { fixtures in """
		extension Root {
		    public convenience init() {
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_bBuilder(renamed: X?) -> B {
		                func __safeDI_midBuilder() -> Mid {
		                    let x = X(renamed: nil)
		                    #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 11)
		                    let renamed: X? = x
		                    #sourceLocation()
		                    let bBuilder = Instantiator<B> {
		                        __safeDI_bBuilder(renamed: renamed)
		                    }
		                    let aBuilder = Instantiator<A> {
		                        __safeDI_aBuilder(renamed: renamed)
		                    }
		                    return Mid(x: x, renamed: renamed, bBuilder: bBuilder, aBuilder: aBuilder)
		                }
		                let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		                return B(renamed: renamed, midBuilder: midBuilder)
		            }
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(renamed: renamed)
		            }
		            return A(renamed: renamed, bBuilder: bBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: nil)
		        }
		        self.init(aBuilder: aBuilder)
		    }
		}
		""" }, mock: { fixtures in """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            aBuilder: A.SafeDIMockConfiguration = .init(),
		            renamed: X? = nil
		        ) {
		            self.aBuilder = aBuilder
		            self.renamed = renamed
		        }

		        private(set) var aBuilder: A.SafeDIMockConfiguration
		        private(set) var renamed: X?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let renamed: X? = safeDIOverrides.renamed
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_bBuilder(renamed: X?) -> B {
		                func __safeDI_midBuilder() -> Mid {
		                    let x = if let safeDIBuilder = safeDIOverrides.aBuilder.bBuilder.midBuilder.x { safeDIBuilder(nil) } else { X(renamed: nil) }
		                    #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 11)
		                    let renamed: X? = x
		                    #sourceLocation()
		                    let bBuilder = Instantiator<B> {
		                        __safeDI_bBuilder(renamed: renamed)
		                    }
		                    let aBuilder = Instantiator<A> {
		                        __safeDI_aBuilder(renamed: renamed)
		                    }
		                    return if let safeDIBuilder = safeDIOverrides.aBuilder.bBuilder.midBuilder.safeDIBuilder { safeDIBuilder(x, renamed, bBuilder, aBuilder) } else { Mid(x: x, renamed: renamed, bBuilder: bBuilder, aBuilder: aBuilder) }
		                }
		                let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.bBuilder.safeDIBuilder { safeDIBuilder(renamed, midBuilder) } else { B(renamed: renamed, midBuilder: midBuilder) }
		            }
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(renamed: renamed)
		            }
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(renamed, bBuilder) } else { A(renamed: renamed, bBuilder: bBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        return Root(aBuilder: aBuilder)
		    }
		}
		#endif
		""" }, buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func a(renamed: X?) -> A {
		            func b(renamed: X?) -> B {
		                B(renamed: renamed, midBuilder: Instantiator<Mid> {
		                    let x = X(renamed: nil)
		                    return Mid(x: x, renamed: x, bBuilder: Instantiator<B> { b(renamed: x) }, aBuilder: Instantiator<A> { a(renamed: x) })
		                })
		            }
		            return A(renamed: renamed, bBuilder: Instantiator<B> { b(renamed: renamed) })
		        }
		        self.init(aBuilder: Instantiator<A> { a(renamed: nil) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsAliasOfParameterLabel_whenDeclaringScopeIsBuiltAsLabel() async throws {
		// `Root` instantiates `renamed: X`, whose `X` declares the `aBuilder` the cycle closes on, so `X` passes the function
		// `nil`: `renamed` is still being built around it. Like the declaration still being built where the function takes no
		// parameter, that `nil` keeps no alias of `renamed` from being created: `Mid` builds `x` first, whose cycle-closing
		// scope passes `nil`, since the alias is generated after it, then creates its alias and hands it to `Mid`.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let renamed: X"])
				.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: true)"),
			seamFixtureType(named: "X", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let renamed: X?", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let renamed: X?", "@Instantiated let midBuilder: Instantiator<Mid>"]),
			seamFixtureType(named: "Mid", isFinalClass: true, declarations: [
				"@Instantiated let x: X",
				#"@Received(fulfilledByDependencyNamed: "x", ofType: X.self, onlyIfAvailable: true) let renamed: X?"#,
			]),
		]
		try await expectGeneratedTree(of: fixture, root: "Root", equals: { fixtures in """
		extension Root {
		    public convenience init() {
		        func __safeDI_renamed() -> X {
		            func __safeDI_aBuilder(renamed: X?) -> A {
		                func __safeDI_midBuilder() -> Mid {
		                    func __safeDI_x() -> X {
		                        let aBuilder = Instantiator<A> {
		                            __safeDI_aBuilder(renamed: nil)
		                        }
		                        return X(renamed: nil, aBuilder: aBuilder)
		                    }
		                    let x: X = __safeDI_x()
		                    #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 9)
		                    let renamed: X? = x
		                    #sourceLocation()
		                    return Mid(x: x, renamed: renamed)
		                }
		                let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		                return A(renamed: renamed, midBuilder: midBuilder)
		            }
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(renamed: nil)
		            }
		            return X(renamed: nil, aBuilder: aBuilder)
		        }
		        let renamed: X = __safeDI_renamed()
		        self.init(renamed: renamed)
		    }
		}
		""" }, mock: { fixtures in """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            renamed: X.SafeDIMockConfiguration = .init()
		        ) {
		            self.renamed = renamed
		        }

		        private(set) var renamed: X.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_renamed() -> X {
		            func __safeDI_aBuilder(renamed: X?) -> A {
		                func __safeDI_midBuilder() -> Mid {
		                    func __safeDI_x() -> X {
		                        let aBuilder = Instantiator<A> {
		                            __safeDI_aBuilder(renamed: nil)
		                        }
		                        return X(renamed: nil, aBuilder: aBuilder)
		                    }
		                    let x: X = __safeDI_x()
		                    #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 9)
		                    let renamed: X? = x
		                    #sourceLocation()
		                    return Mid(x: x, renamed: renamed)
		                }
		                let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		                return A(renamed: renamed, midBuilder: midBuilder)
		            }
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(renamed: nil)
		            }
		            return if let safeDIBuilder = safeDIOverrides.renamed.safeDIBuilder { safeDIBuilder(nil, aBuilder) } else { X(renamed: nil, aBuilder: aBuilder) }
		        }
		        let renamed: X = __safeDI_renamed()
		        return Root(renamed: renamed)
		    }
		}
		#endif
		""" }, buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func a(renamed: X?) -> A {
		            A(renamed: renamed, midBuilder: Instantiator<Mid> {
		                let x = X(renamed: nil, aBuilder: Instantiator<A> { a(renamed: nil) })
		                return Mid(x: x, renamed: x)
		            })
		        }
		        self.init(renamed: X(renamed: nil, aBuilder: Instantiator<A> { a(renamed: nil) }))
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsDependencyCycleError_whenFulfillingTypeRequiresAliasOfParameterLabel() async {
		// `X` requires the alias, which is created only after `x`, the property `X` is built for: the parameter does not
		// stand in for the alias, as nothing above the function provides `renamed`.
		let fixture = Self.aliasOfParameterLabelFixture(xReceives: "@Received let renamed: X?")
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["X.swift"]):7:5: error: Dependency cycle: @Instantiated `x: X` -> @Received `renamed: X?` -> @Received `x: X`. `x: X` is received while it is still being instantiated. `renamed: X?` renames `x: X` only if available, so a type that receives `renamed` without `onlyIfAvailable` must be built after `x: X`. Receive `renamed` with `@Received(onlyIfAvailable: true)` to be passed `nil` where `x: X` cannot be built first.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenClosedOnTypeRequiresParameterLabelThatScopeAboveFunctionProvidesOnlyAsLazilyInstantiatedInstance() async {
		// `A` requires `renamed: X`, so the function takes it as a required parameter, which `Root` passes the instance of its
		// lazily instantiated `renamed`: a binding that keeps no alias of the label from being created. `Mid`'s alias then hides
		// the label from the `A` it builds again, as it would outside a cycle.
		let fixture = Self.aliasOfParameterLabelFixture(rootDeclares: ["@Instantiated let renamed: LazilyInstantiated<X>"], aReceives: "@Received let renamed: X")
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["A.swift"]):8:5: error: @Received property `renamed: X` is hidden in chain: Root -> Instantiator<A> -> Instantiator<Mid> -> A. `Mid` declares `renamed: X?` with the same label, so the types below `Mid` receive `renamed: X?` instead. Give `renamed: X?` on `Mid` a different label to fix.
			\(fixtures["Mid.swift"]):10:5: note: `renamed: X?` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Tests – A type built as a parameter's label

	// `A` receives `renamed` only if available, and `Mid`, between `A`'s builder function and the scope that builds `A`
	// again, instantiates `renamed: X`, whose `X` receives `renamed` only if available: the function takes `renamed`. Where
	// the function takes no parameter, `X` is passed `nil`, since `renamed` is still being built around it, though `Root`
	// declares a `renamed` above. The parameter stands for that declaration in the function's body and changes nothing: `X`
	// is passed `nil` however the function is called, and the `A` that `Mid` builds again is passed `Mid`'s `renamed`.

	@Test(arguments: CycleClosingWrapper.allCases, [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilToTypeBuiltAsParameterLabel_whenItReceivesLabelOnlyIfAvailable(wrapper: CycleClosingWrapper, closedOnTypeRequiresLabel: Bool) async throws {
		// Where `A` requires `renamed`, the function takes the required parameter `renamed: X`, which provides the optional
		// form `X` receives too.
		let parameterType = closedOnTypeRequiresLabel ? "X" : "X?"
		let aReceives = closedOnTypeRequiresLabel ? "@Received let renamed: X" : "@Received(onlyIfAvailable: true) let renamed: X?"
		try await expectGeneratedTree(
			of: Self.typeBuiltAsParameterLabelFixture(wrapper: wrapper, aReceives: aReceives),
			root: "Root",
			equals: Self.expectedTypeBuiltAsParameterLabelTree(wrapper: wrapper, parameterType: parameterType),
			mock: Self.expectedTypeBuiltAsParameterLabelMock(wrapper: wrapper, parameterType: parameterType),
			buildsTheSameValuesAs: Self.handBuiltTypeBuiltAsParameterLabelTree(wrapper: wrapper, parameterType: parameterType),
			probes: wrapper.isErased ? ["Root()", "Root.mock()"].map { root in
				// An `ErasedInstantiator` is not traversed, so each probe holds the `Mid` the `A` built first builds, and the `A`
				// that `Mid` builds again.
				let mid = "(\(root).aBuilder.instantiate().a as! A).midBuilder.instantiate()"
				return DifferentialValueProbe(#"{ () -> (Mid, A) in let mid = \#(mid); return (mid, mid.aBuilder.instantiate().a as! A) }()"#)
			} : nil,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilToTypeBuiltAsParameterLabel_whenNothingAboveClosedOnFunctionProvidesLabel() async throws {
		// Nothing above the function provides `renamed`, so `Root` passes the function `nil`. `Mid` passes the `A` it builds
		// again its `renamed`, which the parameter handed the `X` that `A`'s `Mid` builds: that `X` is passed `nil` instead, as
		// on the first build.
		try await expectGeneratedTree(of: Self.typeBuiltAsParameterLabelFixture(rootDeclares: []), root: "Root", equals: """
		extension Root {
		    public convenience init() {
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                let renamed = X(renamed: nil)
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return Mid(renamed: renamed, aBuilder: aBuilder)
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return A(renamed: renamed, midBuilder: midBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: nil)
		        }
		        self.init(aBuilder: aBuilder)
		    }
		}
		""", mock: """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            aBuilder: A.SafeDIMockConfiguration = .init(),
		            renamed: X? = nil
		        ) {
		            self.aBuilder = aBuilder
		            self.renamed = renamed
		        }

		        private(set) var aBuilder: A.SafeDIMockConfiguration
		        private(set) var renamed: X?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let renamed: X? = safeDIOverrides.renamed
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                let renamed = if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.renamed { safeDIBuilder(nil) } else { X(renamed: nil) }
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(renamed, aBuilder) } else { Mid(renamed: renamed, aBuilder: aBuilder) }
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(renamed, midBuilder) } else { A(renamed: renamed, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        return Root(aBuilder: aBuilder)
		    }
		}
		#endif
		""", buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func a(renamed: X?) -> A {
		            A(renamed: renamed, midBuilder: Instantiator<Mid> {
		                let renamed = X(renamed: nil)
		                return Mid(renamed: renamed, aBuilder: Instantiator<A> { a(renamed: renamed) })
		            })
		        }
		        self.init(aBuilder: Instantiator<A> { a(renamed: nil) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilToTypeBuiltAsLazilyInstantiatedParameterLabel_whenItReceivesLabelOnlyIfAvailable() async throws {
		// `Mid`'s `renamed` is a `LazilyInstantiated<X>`, whose `X` is built inside the wrapper's builder function. The
		// parameter does not stand in for the wrapper's instance there: `X` is passed `nil`, as it is where the function takes
		// no parameter, rather than the parameter's `.instance`, which an optional parameter does not have.
		let fixture = Self.typeBuiltAsParameterLabelFixture(midDeclares: ["@Instantiated let renamed: LazilyInstantiated<X>"])
		try await expectGeneratedTree(of: fixture, root: "Root", equals: """
		extension Root {
		    public convenience init() {
		        let renamed = X(renamed: nil)
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                func __safeDI_renamed() -> X {
		                    X(renamed: nil)
		                }
		                let renamed = LazilyInstantiated<X>(__safeDI_renamed)
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed.instance)
		                }
		                return Mid(renamed: renamed, aBuilder: aBuilder)
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return A(renamed: renamed, midBuilder: midBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        self.init(renamed: renamed, aBuilder: aBuilder)
		    }
		}
		""", mock: """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            renamed: ((X?) -> X)? = nil,
		            aBuilder: A.SafeDIMockConfiguration = .init()
		        ) {
		            self.renamed = renamed
		            self.aBuilder = aBuilder
		        }

		        private(set) var renamed: ((X?) -> X)?
		        private(set) var aBuilder: A.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let renamed = if let safeDIBuilder = safeDIOverrides.renamed { safeDIBuilder(nil) } else { X(renamed: nil) }
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                func __safeDI_renamed() -> X {
		                    if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.renamed { safeDIBuilder(nil) } else { X(renamed: nil) }
		                }
		                let renamed = LazilyInstantiated<X>(__safeDI_renamed)
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed.instance)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(renamed, aBuilder) } else { Mid(renamed: renamed, aBuilder: aBuilder) }
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(renamed, midBuilder) } else { A(renamed: renamed, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        return Root(renamed: renamed, aBuilder: aBuilder)
		    }
		}
		#endif
		""", buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func a(renamed: X?) -> A {
		            A(renamed: renamed, midBuilder: Instantiator<Mid> {
		                let renamed = LazilyInstantiated<X> { X(renamed: nil) }
		                return Mid(renamed: renamed, aBuilder: Instantiator<A> { a(renamed: renamed.instance) })
		            })
		        }
		        let renamed = X(renamed: nil)
		        self.init(renamed: renamed, aBuilder: Instantiator<A> { a(renamed: renamed) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilToTypeBuiltInsideTypeBuiltAsParameterLabel_whenItReceivesLabelOnlyIfAvailable() async throws {
		// `X` instantiates `Leaf`, which receives `renamed` only if available: `Leaf` is built inside `renamed` too.
		let fixture = Self.typeBuiltAsParameterLabelFixture(
			xDeclares: ["@Instantiated let leaf: Leaf"],
			otherTypes: [seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let renamed: X?"])],
		)
		try await expectGeneratedTree(of: fixture, root: "Root", equals: """
		extension Root {
		    public convenience init() {
		        func __safeDI_renamed() -> X {
		            let leaf = Leaf(renamed: nil)
		            return X(leaf: leaf)
		        }
		        let renamed: X = __safeDI_renamed()
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                func __safeDI_renamed() -> X {
		                    let leaf = Leaf(renamed: nil)
		                    return X(leaf: leaf)
		                }
		                let renamed: X = __safeDI_renamed()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return Mid(renamed: renamed, aBuilder: aBuilder)
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return A(renamed: renamed, midBuilder: midBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        self.init(renamed: renamed, aBuilder: aBuilder)
		    }
		}
		""", mock: """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            renamed: X.SafeDIMockConfiguration = .init(),
		            aBuilder: A.SafeDIMockConfiguration = .init()
		        ) {
		            self.renamed = renamed
		            self.aBuilder = aBuilder
		        }

		        private(set) var renamed: X.SafeDIMockConfiguration
		        private(set) var aBuilder: A.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_renamed() -> X {
		            let leaf = if let safeDIBuilder = safeDIOverrides.renamed.leaf { safeDIBuilder(nil) } else { Leaf(renamed: nil) }
		            return if let safeDIBuilder = safeDIOverrides.renamed.safeDIBuilder { safeDIBuilder(leaf) } else { X(leaf: leaf) }
		        }
		        let renamed: X = __safeDI_renamed()
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                func __safeDI_renamed() -> X {
		                    let leaf = if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.renamed.leaf { safeDIBuilder(nil) } else { Leaf(renamed: nil) }
		                    return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.renamed.safeDIBuilder { safeDIBuilder(leaf) } else { X(leaf: leaf) }
		                }
		                let renamed: X = __safeDI_renamed()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(renamed, aBuilder) } else { Mid(renamed: renamed, aBuilder: aBuilder) }
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(renamed, midBuilder) } else { A(renamed: renamed, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        return Root(renamed: renamed, aBuilder: aBuilder)
		    }
		}
		#endif
		""", buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func a(renamed: X?) -> A {
		            A(renamed: renamed, midBuilder: Instantiator<Mid> {
		                let renamed = X(leaf: Leaf(renamed: nil))
		                return Mid(renamed: renamed, aBuilder: Instantiator<A> { a(renamed: renamed) })
		            })
		        }
		        let renamed = X(leaf: Leaf(renamed: nil))
		        self.init(renamed: renamed, aBuilder: Instantiator<A> { a(renamed: renamed) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilToTypeBuiltAsParameterLabelAgain_whenTypeBesideFirstDeclarationDeclaresLabel() async throws {
		// `Mid` also instantiates `Sibling`, which instantiates its own `renamed: X`. `Mid`'s `renamed` is the nearest
		// declaration above `Sibling`, but the `X` `Sibling` builds is built as `renamed` too, so it is passed `nil`.
		let fixture = Self.typeBuiltAsParameterLabelFixture(
			midDeclares: ["@Instantiated let renamed: X", "@Instantiated let sibling: Sibling"],
			otherTypes: [seamFixtureType(named: "Sibling", isFinalClass: true, declarations: ["@Instantiated let renamed: X"])],
		)
		try await expectGeneratedTree(of: fixture, root: "Root", equals: """
		extension Root {
		    public convenience init() {
		        let renamed = X(renamed: nil)
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                let renamed = X(renamed: nil)
		                func __safeDI_sibling() -> Sibling {
		                    let renamed = X(renamed: nil)
		                    return Sibling(renamed: renamed)
		                }
		                let sibling: Sibling = __safeDI_sibling()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return Mid(renamed: renamed, sibling: sibling, aBuilder: aBuilder)
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return A(renamed: renamed, midBuilder: midBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        self.init(renamed: renamed, aBuilder: aBuilder)
		    }
		}
		""", mock: """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            renamed: ((X?) -> X)? = nil,
		            aBuilder: A.SafeDIMockConfiguration = .init()
		        ) {
		            self.renamed = renamed
		            self.aBuilder = aBuilder
		        }

		        private(set) var renamed: ((X?) -> X)?
		        private(set) var aBuilder: A.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let renamed = if let safeDIBuilder = safeDIOverrides.renamed { safeDIBuilder(nil) } else { X(renamed: nil) }
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                let renamed = if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.renamed { safeDIBuilder(nil) } else { X(renamed: nil) }
		                func __safeDI_sibling() -> Sibling {
		                    let renamed = if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.sibling.renamed { safeDIBuilder(nil) } else { X(renamed: nil) }
		                    return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.sibling.safeDIBuilder { safeDIBuilder(renamed) } else { Sibling(renamed: renamed) }
		                }
		                let sibling: Sibling = __safeDI_sibling()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(renamed, sibling, aBuilder) } else { Mid(renamed: renamed, sibling: sibling, aBuilder: aBuilder) }
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(renamed, midBuilder) } else { A(renamed: renamed, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        return Root(renamed: renamed, aBuilder: aBuilder)
		    }
		}
		#endif
		""", buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func a(renamed: X?) -> A {
		            A(renamed: renamed, midBuilder: Instantiator<Mid> {
		                let renamed = X(renamed: nil)
		                return Mid(renamed: renamed, sibling: Sibling(renamed: X(renamed: nil)), aBuilder: Instantiator<A> { a(renamed: renamed) })
		            })
		        }
		        let renamed = X(renamed: nil)
		        self.init(renamed: renamed, aBuilder: Instantiator<A> { a(renamed: renamed) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilToTypeBuiltAsParameterLabel_whenNestedClosedOnFunctionsTakeLabel() async throws {
		// `B`'s builder function, inside `A`'s, takes `renamed` too, and `Mid`, beneath both, builds `renamed` and closes both
		// cycles: `X` is passed `nil`, whichever function's parameter is nearest.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let renamed: X", "@Instantiated let aBuilder: Instantiator<A>"])
				.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: true)"),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let renamed: X?", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let renamed: X?", "@Instantiated let midBuilder: Instantiator<Mid>"]),
			seamFixtureType(named: "Mid", isFinalClass: true, declarations: ["@Instantiated let renamed: X", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let renamed: X?"]),
		]
		try await expectGeneratedTree(of: fixture, root: "Root", equals: """
		extension Root {
		    public convenience init() {
		        let renamed = X(renamed: nil)
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_bBuilder(renamed: X?) -> B {
		                func __safeDI_midBuilder() -> Mid {
		                    let renamed = X(renamed: nil)
		                    let bBuilder = Instantiator<B> {
		                        __safeDI_bBuilder(renamed: renamed)
		                    }
		                    let aBuilder = Instantiator<A> {
		                        __safeDI_aBuilder(renamed: renamed)
		                    }
		                    return Mid(renamed: renamed, bBuilder: bBuilder, aBuilder: aBuilder)
		                }
		                let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		                return B(renamed: renamed, midBuilder: midBuilder)
		            }
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(renamed: renamed)
		            }
		            return A(renamed: renamed, bBuilder: bBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        self.init(renamed: renamed, aBuilder: aBuilder)
		    }
		}
		""", mock: """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            renamed: ((X?) -> X)? = nil,
		            aBuilder: A.SafeDIMockConfiguration = .init()
		        ) {
		            self.renamed = renamed
		            self.aBuilder = aBuilder
		        }

		        private(set) var renamed: ((X?) -> X)?
		        private(set) var aBuilder: A.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let renamed = if let safeDIBuilder = safeDIOverrides.renamed { safeDIBuilder(nil) } else { X(renamed: nil) }
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_bBuilder(renamed: X?) -> B {
		                func __safeDI_midBuilder() -> Mid {
		                    let renamed = if let safeDIBuilder = safeDIOverrides.aBuilder.bBuilder.midBuilder.renamed { safeDIBuilder(nil) } else { X(renamed: nil) }
		                    let bBuilder = Instantiator<B> {
		                        __safeDI_bBuilder(renamed: renamed)
		                    }
		                    let aBuilder = Instantiator<A> {
		                        __safeDI_aBuilder(renamed: renamed)
		                    }
		                    return if let safeDIBuilder = safeDIOverrides.aBuilder.bBuilder.midBuilder.safeDIBuilder { safeDIBuilder(renamed, bBuilder, aBuilder) } else { Mid(renamed: renamed, bBuilder: bBuilder, aBuilder: aBuilder) }
		                }
		                let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.bBuilder.safeDIBuilder { safeDIBuilder(renamed, midBuilder) } else { B(renamed: renamed, midBuilder: midBuilder) }
		            }
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(renamed: renamed)
		            }
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(renamed, bBuilder) } else { A(renamed: renamed, bBuilder: bBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        return Root(renamed: renamed, aBuilder: aBuilder)
		    }
		}
		#endif
		""", buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func a(renamed: X?) -> A {
		            func b(renamed: X?) -> B {
		                B(renamed: renamed, midBuilder: Instantiator<Mid> {
		                    let renamed = X(renamed: nil)
		                    return Mid(renamed: renamed, bBuilder: Instantiator<B> { b(renamed: renamed) }, aBuilder: Instantiator<A> { a(renamed: renamed) })
		                })
		            }
		            return A(renamed: renamed, bBuilder: Instantiator<B> { b(renamed: renamed) })
		        }
		        let renamed = X(renamed: nil)
		        self.init(renamed: renamed, aBuilder: Instantiator<A> { a(renamed: renamed) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilToNestedClosedOnFunctionAndCreatesAliasInItsBody_whenScopeDeclaringItIsBuiltAsOuterFunctionsParameterLabel() async throws {
		// The `X` that `Mid` builds as `renamed` declares `bBuilder`, whose `B` receives `renamed` only if available, and `C`,
		// beneath `B`, declares an `onlyIfAvailable` alias `renamed` of its `source` before building `B` again: `B`'s builder
		// function takes `renamed`. `X` passes it `nil`, since `renamed` is still being built around it, so the parameter
		// keeps no alias of `renamed` from being created, and `C` creates its alias after `source`, as where the function takes
		// no parameter. Inside `B`'s function nothing is built as `renamed` yet, so `B`'s `Leaf` is passed the parameter: `nil`,
		// then `C`'s alias. The mock passes that `Leaf` `nil` even where `C` builds `B` again: its rule counts the `renamed: X`
		// still being built above `B`'s function as hiding every form of the label.
		let fixture = Self.typeBuiltAsParameterLabelFixture(
			rootDeclares: [],
			xDeclares: ["@Received(onlyIfAvailable: true) let renamed: X?", "@Instantiated let bBuilder: Instantiator<B>"],
			otherTypes: [
				seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let renamed: X?", "@Instantiated let leaf: Leaf", "@Instantiated let cBuilder: Instantiator<C>"]),
				seamFixtureType(named: "C", isFinalClass: true, declarations: [
					"@Instantiated let source: X",
					#"@Received(fulfilledByDependencyNamed: "source", ofType: X.self, onlyIfAvailable: true) let renamed: X?"#,
					"@Instantiated let bBuilder: Instantiator<B>",
				]),
				seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let renamed: X?"]),
			],
		)
		try await expectGeneratedTree(of: fixture, root: "Root", equals: { fixtures in """
		extension Root {
		    public convenience init() {
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                func __safeDI_renamed() -> X {
		                    func __safeDI_bBuilder(renamed: X?) -> B {
		                        let leaf = Leaf(renamed: renamed)
		                        func __safeDI_cBuilder() -> C {
		                            func __safeDI_source() -> X {
		                                let bBuilder = Instantiator<B> {
		                                    __safeDI_bBuilder(renamed: nil)
		                                }
		                                return X(renamed: nil, bBuilder: bBuilder)
		                            }
		                            let source: X = __safeDI_source()
		                            #sourceLocation(file: "\(fixtures["C.swift"])", line: 10)
		                            let renamed: X? = source
		                            #sourceLocation()
		                            let bBuilder = Instantiator<B> {
		                                __safeDI_bBuilder(renamed: renamed)
		                            }
		                            return C(source: source, renamed: renamed, bBuilder: bBuilder)
		                        }
		                        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
		                        return B(renamed: renamed, leaf: leaf, cBuilder: cBuilder)
		                    }
		                    let bBuilder = Instantiator<B> {
		                        __safeDI_bBuilder(renamed: nil)
		                    }
		                    return X(renamed: nil, bBuilder: bBuilder)
		                }
		                let renamed: X = __safeDI_renamed()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return Mid(renamed: renamed, aBuilder: aBuilder)
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return A(renamed: renamed, midBuilder: midBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: nil)
		        }
		        self.init(aBuilder: aBuilder)
		    }
		}
		""" }, mock: { fixtures in """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            aBuilder: A.SafeDIMockConfiguration = .init(),
		            renamed: X? = nil
		        ) {
		            self.aBuilder = aBuilder
		            self.renamed = renamed
		        }

		        private(set) var aBuilder: A.SafeDIMockConfiguration
		        private(set) var renamed: X?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let renamed: X? = safeDIOverrides.renamed
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                func __safeDI_renamed() -> X {
		                    func __safeDI_bBuilder(renamed: X?) -> B {
		                        let leaf = if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.renamed.bBuilder.leaf { safeDIBuilder(renamed) } else { Leaf(renamed: renamed) }
		                        func __safeDI_cBuilder() -> C {
		                            func __safeDI_source() -> X {
		                                let bBuilder = Instantiator<B> {
		                                    __safeDI_bBuilder(renamed: nil)
		                                }
		                                return X(renamed: nil, bBuilder: bBuilder)
		                            }
		                            let source: X = __safeDI_source()
		                            #sourceLocation(file: "\(fixtures["C.swift"])", line: 10)
		                            let renamed: X? = source
		                            #sourceLocation()
		                            let bBuilder = Instantiator<B> {
		                                __safeDI_bBuilder(renamed: renamed)
		                            }
		                            return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.renamed.bBuilder.cBuilder.safeDIBuilder { safeDIBuilder(source, renamed, bBuilder) } else { C(source: source, renamed: renamed, bBuilder: bBuilder) }
		                        }
		                        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
		                        return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.renamed.bBuilder.safeDIBuilder { safeDIBuilder(renamed, leaf, cBuilder) } else { B(renamed: renamed, leaf: leaf, cBuilder: cBuilder) }
		                    }
		                    let bBuilder = Instantiator<B> {
		                        __safeDI_bBuilder(renamed: nil)
		                    }
		                    return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.renamed.safeDIBuilder { safeDIBuilder(nil, bBuilder) } else { X(renamed: nil, bBuilder: bBuilder) }
		                }
		                let renamed: X = __safeDI_renamed()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(renamed, aBuilder) } else { Mid(renamed: renamed, aBuilder: aBuilder) }
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(renamed, midBuilder) } else { A(renamed: renamed, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        return Root(aBuilder: aBuilder)
		    }
		}
		#endif
		""" }, mockBuildsTheSameValues: false, buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func a(renamed: X?) -> A {
		            A(renamed: renamed, midBuilder: Instantiator<Mid> {
		                let renamed = X(renamed: nil, bBuilder: Instantiator<B> { b(renamed: nil) })
		                return Mid(renamed: renamed, aBuilder: Instantiator<A> { a(renamed: renamed) })
		            })
		        }
		        func b(renamed: X?) -> B {
		            B(renamed: renamed, leaf: Leaf(renamed: renamed), cBuilder: Instantiator<C> {
		                let source = X(renamed: nil, bBuilder: Instantiator<B> { b(renamed: nil) })
		                return C(source: source, renamed: source, bBuilder: Instantiator<B> { b(renamed: source) })
		            })
		        }
		        self.init(aBuilder: Instantiator<A> { a(renamed: nil) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_createsNoOnlyIfAvailableAliasOfParameterLabel_whenTypeDeclaringAliasIsBuiltAsLabel() async throws {
		// `X` receives `renamed` through an `onlyIfAvailable` alias, `previous`, whose fulfilling property `renamed: X` is still
		// being built around `X`, in every form the parameter provides: `X` is passed `nil`, as before.
		let fixture = Self.typeBuiltAsParameterLabelFixture(xDeclares: [#"@Received(fulfilledByDependencyNamed: "renamed", ofType: X.self, onlyIfAvailable: true) let previous: X?"#])
		try await expectGeneratedTree(of: fixture, root: "Root", equals: { fixtures in """
		extension Root {
		    public convenience init() {
		        func __safeDI_renamed() -> X {
		            #sourceLocation(file: "\(fixtures["X.swift"])", line: 7)
		            let previous: X? = nil
		            #sourceLocation()
		            return X(previous: previous)
		        }
		        let renamed: X = __safeDI_renamed()
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                func __safeDI_renamed() -> X {
		                    #sourceLocation(file: "\(fixtures["X.swift"])", line: 7)
		                    let previous: X? = nil
		                    #sourceLocation()
		                    return X(previous: previous)
		                }
		                let renamed: X = __safeDI_renamed()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return Mid(renamed: renamed, aBuilder: aBuilder)
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return A(renamed: renamed, midBuilder: midBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        self.init(renamed: renamed, aBuilder: aBuilder)
		    }
		}
		""" }, mock: { fixtures in """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            renamed: ((X?) -> X)? = nil,
		            aBuilder: A.SafeDIMockConfiguration = .init()
		        ) {
		            self.renamed = renamed
		            self.aBuilder = aBuilder
		        }

		        private(set) var renamed: ((X?) -> X)?
		        private(set) var aBuilder: A.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_renamed() -> X {
		            #sourceLocation(file: "\(fixtures["X.swift"])", line: 7)
		            let previous: X? = nil
		            #sourceLocation()
		            return if let safeDIBuilder = safeDIOverrides.renamed { safeDIBuilder(previous) } else { X(previous: previous) }
		        }
		        let renamed: X = __safeDI_renamed()
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                func __safeDI_renamed() -> X {
		                    #sourceLocation(file: "\(fixtures["X.swift"])", line: 7)
		                    let previous: X? = nil
		                    #sourceLocation()
		                    return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.renamed { safeDIBuilder(previous) } else { X(previous: previous) }
		                }
		                let renamed: X = __safeDI_renamed()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(renamed, aBuilder) } else { Mid(renamed: renamed, aBuilder: aBuilder) }
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(renamed, midBuilder) } else { A(renamed: renamed, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        return Root(renamed: renamed, aBuilder: aBuilder)
		    }
		}
		#endif
		""" }, buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func a(renamed: X?) -> A {
		            A(renamed: renamed, midBuilder: Instantiator<Mid> {
		                let renamed = X(previous: nil)
		                return Mid(renamed: renamed, aBuilder: Instantiator<A> { a(renamed: renamed) })
		            })
		        }
		        let renamed = X(previous: nil)
		        self.init(renamed: renamed, aBuilder: Instantiator<A> { a(renamed: renamed) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsAliasOfParameterLabelFromSiblingBuiltFirst_whenTypeDeclaringAliasIsBuiltInsideLabel() async throws {
		// Nothing above the function provides `renamed`. `X`'s `Leaf` declares an `onlyIfAvailable` alias `renamed` of
		// `source`, which `Leaf2` receives only if available and reads, as the nearest declaration of its label. So `Mid` builds
		// `source` first, inside which the alias is `nil`, then `renamed`, inside which it is bound from `source`.
		let fixture = Self.typeBuiltAsParameterLabelFixture(
			rootDeclares: [],
			midDeclares: ["@Instantiated let source: X", "@Instantiated let renamed: X"],
			xDeclares: ["@Instantiated let leaf: Leaf"],
			otherTypes: [
				seamFixtureType(named: "Leaf", isFinalClass: true, declarations: [
					#"@Received(fulfilledByDependencyNamed: "source", ofType: X.self, onlyIfAvailable: true) let renamed: X?"#,
					"@Instantiated let leaf2: Leaf2",
				]),
				seamFixtureType(named: "Leaf2", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let renamed: X?"]),
			],
		)
		try await expectGeneratedTree(of: fixture, root: "Root", equals: { fixtures in """
		extension Root {
		    public convenience init() {
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                func __safeDI_source() -> X {
		                    func __safeDI_leaf() -> Leaf {
		                        #sourceLocation(file: "\(fixtures["Leaf.swift"])", line: 8)
		                        let renamed: X? = nil
		                        #sourceLocation()
		                        let leaf2 = Leaf2(renamed: renamed)
		                        return Leaf(renamed: renamed, leaf2: leaf2)
		                    }
		                    let leaf: Leaf = __safeDI_leaf()
		                    return X(leaf: leaf)
		                }
		                let source: X = __safeDI_source()
		                func __safeDI_renamed() -> X {
		                    func __safeDI_leaf() -> Leaf {
		                        #sourceLocation(file: "\(fixtures["Leaf.swift"])", line: 8)
		                        let renamed: X? = source
		                        #sourceLocation()
		                        let leaf2 = Leaf2(renamed: renamed)
		                        return Leaf(renamed: renamed, leaf2: leaf2)
		                    }
		                    let leaf: Leaf = __safeDI_leaf()
		                    return X(leaf: leaf)
		                }
		                let renamed: X = __safeDI_renamed()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return Mid(source: source, renamed: renamed, aBuilder: aBuilder)
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return A(renamed: renamed, midBuilder: midBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: nil)
		        }
		        self.init(aBuilder: aBuilder)
		    }
		}
		""" }, mock: { fixtures in """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            aBuilder: A.SafeDIMockConfiguration = .init(),
		            renamed: X? = nil
		        ) {
		            self.aBuilder = aBuilder
		            self.renamed = renamed
		        }

		        private(set) var aBuilder: A.SafeDIMockConfiguration
		        private(set) var renamed: X?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let renamed: X? = safeDIOverrides.renamed
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                func __safeDI_source() -> X {
		                    func __safeDI_leaf() -> Leaf {
		                        #sourceLocation(file: "\(fixtures["Leaf.swift"])", line: 8)
		                        let renamed: X? = nil
		                        #sourceLocation()
		                        let leaf2 = if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.source.leaf.leaf2 { safeDIBuilder(renamed) } else { Leaf2(renamed: renamed) }
		                        return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.source.leaf.safeDIBuilder { safeDIBuilder(renamed, leaf2) } else { Leaf(renamed: renamed, leaf2: leaf2) }
		                    }
		                    let leaf: Leaf = __safeDI_leaf()
		                    return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.source.safeDIBuilder { safeDIBuilder(leaf) } else { X(leaf: leaf) }
		                }
		                let source: X = __safeDI_source()
		                func __safeDI_renamed() -> X {
		                    func __safeDI_leaf() -> Leaf {
		                        #sourceLocation(file: "\(fixtures["Leaf.swift"])", line: 8)
		                        let renamed: X? = source
		                        #sourceLocation()
		                        let leaf2 = if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.renamed.leaf.leaf2 { safeDIBuilder(renamed) } else { Leaf2(renamed: renamed) }
		                        return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.renamed.leaf.safeDIBuilder { safeDIBuilder(renamed, leaf2) } else { Leaf(renamed: renamed, leaf2: leaf2) }
		                    }
		                    let leaf: Leaf = __safeDI_leaf()
		                    return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.renamed.safeDIBuilder { safeDIBuilder(leaf) } else { X(leaf: leaf) }
		                }
		                let renamed: X = __safeDI_renamed()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(source, renamed, aBuilder) } else { Mid(source: source, renamed: renamed, aBuilder: aBuilder) }
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(renamed, midBuilder) } else { A(renamed: renamed, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        return Root(aBuilder: aBuilder)
		    }
		}
		#endif
		""" }, mockBuildsTheSameValues: false, buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func a(renamed: X?) -> A {
		            A(renamed: renamed, midBuilder: Instantiator<Mid> {
		                let source = X(leaf: Leaf(renamed: nil, leaf2: Leaf2(renamed: nil)))
		                let renamed = X(leaf: Leaf(renamed: source, leaf2: Leaf2(renamed: source)))
		                return Mid(source: source, renamed: renamed, aBuilder: Instantiator<A> { a(renamed: renamed) })
		            })
		        }
		        self.init(aBuilder: Instantiator<A> { a(renamed: nil) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesParameterToTypeBuiltAsParameterLabel_whenScopeBetweenDeclaresLabelInFormItReceives() async throws {
		// `Mid` declares `renamed: X?`, an `onlyIfAvailable` alias of its `x`, and instantiates `Inner`, whose `renamed: X`
		// receives `renamed` only if available. The alias is bound from `x`, built first, and is the nearest declaration of the
		// label for `Mid`'s children and the `A` built again. The `X` built as `Inner`'s `renamed` is passed `nil`, since that
		// `renamed` is still being built, as the mock passes it (see
		// `generate_passesParameterToTypeBuiltAsParameterLabel_whenScopeAboveFunctionDeclaresLabelInFormItReceives`).
		let fixture = Self.typeBuiltAsParameterLabelFixture(
			midDeclares: [
				"@Instantiated let x: X",
				#"@Received(fulfilledByDependencyNamed: "x", ofType: X.self, onlyIfAvailable: true) let renamed: X?"#,
				"@Instantiated let inner: Inner",
			],
			otherTypes: [seamFixtureType(named: "Inner", isFinalClass: true, declarations: ["@Instantiated let renamed: X"])],
		)
		try await expectGeneratedTree(of: fixture, root: "Root", equals: { fixtures in """
		extension Root {
		    public convenience init() {
		        let renamed = X(renamed: nil)
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                let x = X(renamed: nil)
		                #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 11)
		                let renamed: X? = x
		                #sourceLocation()
		                func __safeDI_inner() -> Inner {
		                    let renamed = X(renamed: nil)
		                    return Inner(renamed: renamed)
		                }
		                let inner: Inner = __safeDI_inner()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return Mid(x: x, renamed: renamed, inner: inner, aBuilder: aBuilder)
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return A(renamed: renamed, midBuilder: midBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        self.init(renamed: renamed, aBuilder: aBuilder)
		    }
		}
		""" }, mock: { fixtures in """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            renamed: ((X?) -> X)? = nil,
		            aBuilder: A.SafeDIMockConfiguration = .init()
		        ) {
		            self.renamed = renamed
		            self.aBuilder = aBuilder
		        }

		        private(set) var renamed: ((X?) -> X)?
		        private(set) var aBuilder: A.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let renamed = if let safeDIBuilder = safeDIOverrides.renamed { safeDIBuilder(nil) } else { X(renamed: nil) }
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                let x = if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.x { safeDIBuilder(nil) } else { X(renamed: nil) }
		                #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 11)
		                let renamed: X? = x
		                #sourceLocation()
		                func __safeDI_inner() -> Inner {
		                    let renamed = if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.inner.renamed { safeDIBuilder(nil) } else { X(renamed: nil) }
		                    return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.inner.safeDIBuilder { safeDIBuilder(renamed) } else { Inner(renamed: renamed) }
		                }
		                let inner: Inner = __safeDI_inner()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(x, renamed, inner, aBuilder) } else { Mid(x: x, renamed: renamed, inner: inner, aBuilder: aBuilder) }
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(renamed, midBuilder) } else { A(renamed: renamed, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        return Root(renamed: renamed, aBuilder: aBuilder)
		    }
		}
		#endif
		""" }, mockBuildsTheSameValues: false, buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func a(renamed: X?) -> A {
		            A(renamed: renamed, midBuilder: Instantiator<Mid> {
		                let x = X(renamed: nil)
		                return Mid(x: x, renamed: x, inner: Inner(renamed: X(renamed: nil)), aBuilder: Instantiator<A> { a(renamed: x) })
		            })
		        }
		        let renamed = X(renamed: nil)
		        self.init(renamed: renamed, aBuilder: Instantiator<A> { a(renamed: renamed) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsDependencyCycleError_whenTypeBuiltAsParameterLabelRequiresLabel() async {
		// `X` requires `renamed`, which it is built as: the error the tree without the cycle reports.
		let fixture = Self.typeBuiltAsParameterLabelFixture(xDeclares: ["@Received let renamed: X?"])
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["X.swift"]):7:5: error: Dependency cycle: @Instantiated `renamed: X` -> @Received `renamed: X?`. `renamed: X` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesParameterToTypeInClosedOnFunctionsBody_whenLabelIsStillBeingBuiltOnlyAboveFunction() async throws {
		// `Root`'s `renamed: X` declares `aBuilder`, so `renamed` is still being built around the whole function: `X` passes
		// it `nil`. `A` instantiates `Leaf`, which receives `renamed` only if available, and `Mid` passes the `A` it builds
		// again its alias `renamed` of `source`, which is not being built: `Leaf` is passed the parameter, as before, and so
		// the alias where `Mid` builds `A` again. The mock passes `Leaf` `nil` even there: its rule, unlike production's,
		// counts the `renamed: X` still being built above as hiding every form of the label.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let renamed: X"])
				.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: true)"),
			seamFixtureType(named: "X", isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let renamed: X?", "@Instantiated let leaf: Leaf", "@Instantiated let midBuilder: Instantiator<Mid>"]),
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let renamed: X?"]),
			seamFixtureType(named: "Mid", isFinalClass: true, declarations: [
				"@Instantiated let source: X",
				#"@Received(fulfilledByDependencyNamed: "source", ofType: X.self, onlyIfAvailable: true) let renamed: X?"#,
				"@Instantiated let aBuilder: Instantiator<A>",
			]),
		]
		try await expectGeneratedTree(of: fixture, root: "Root", equals: { fixtures in """
		extension Root {
		    public convenience init() {
		        func __safeDI_renamed() -> X {
		            func __safeDI_aBuilder(renamed: X?) -> A {
		                let leaf = Leaf(renamed: renamed)
		                func __safeDI_midBuilder() -> Mid {
		                    func __safeDI_source() -> X {
		                        let aBuilder = Instantiator<A> {
		                            __safeDI_aBuilder(renamed: nil)
		                        }
		                        return X(aBuilder: aBuilder)
		                    }
		                    let source: X = __safeDI_source()
		                    #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 10)
		                    let renamed: X? = source
		                    #sourceLocation()
		                    let aBuilder = Instantiator<A> {
		                        __safeDI_aBuilder(renamed: renamed)
		                    }
		                    return Mid(source: source, renamed: renamed, aBuilder: aBuilder)
		                }
		                let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		                return A(renamed: renamed, leaf: leaf, midBuilder: midBuilder)
		            }
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(renamed: nil)
		            }
		            return X(aBuilder: aBuilder)
		        }
		        let renamed: X = __safeDI_renamed()
		        self.init(renamed: renamed)
		    }
		}
		""" }, mock: { fixtures in """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            renamed: X.SafeDIMockConfiguration = .init()
		        ) {
		            self.renamed = renamed
		        }

		        private(set) var renamed: X.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_renamed() -> X {
		            func __safeDI_aBuilder(renamed: X?) -> A {
		                let leaf = Leaf(renamed: renamed)
		                func __safeDI_midBuilder() -> Mid {
		                    func __safeDI_source() -> X {
		                        let aBuilder = Instantiator<A> {
		                            __safeDI_aBuilder(renamed: nil)
		                        }
		                        return X(aBuilder: aBuilder)
		                    }
		                    let source: X = __safeDI_source()
		                    #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 10)
		                    let renamed: X? = source
		                    #sourceLocation()
		                    let aBuilder = Instantiator<A> {
		                        __safeDI_aBuilder(renamed: renamed)
		                    }
		                    return Mid(source: source, renamed: renamed, aBuilder: aBuilder)
		                }
		                let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		                return A(renamed: renamed, leaf: leaf, midBuilder: midBuilder)
		            }
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(renamed: nil)
		            }
		            return if let safeDIBuilder = safeDIOverrides.renamed.safeDIBuilder { safeDIBuilder(aBuilder) } else { X(aBuilder: aBuilder) }
		        }
		        let renamed: X = __safeDI_renamed()
		        return Root(renamed: renamed)
		    }
		}
		#endif
		""" }, mockBuildsTheSameValues: false, buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func a(renamed: X?) -> A {
		            A(renamed: renamed, leaf: Leaf(renamed: renamed), midBuilder: Instantiator<Mid> {
		                let source = X(aBuilder: Instantiator<A> { a(renamed: nil) })
		                return Mid(source: source, renamed: source, aBuilder: Instantiator<A> { a(renamed: source) })
		            })
		        }
		        self.init(renamed: X(aBuilder: Instantiator<A> { a(renamed: nil) }))
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesParameterToTypeBuiltAsParameterLabel_whenScopeAboveFunctionDeclaresLabelInFormItReceives() async throws {
		// `Root` declares `renamed: X?`, an alias of its `other`, but `X`, built as `Mid`'s `renamed: X`, receives `renamed`
		// only if available inside that `renamed`, the nearest declaration of the label, still being built: it is passed
		// `nil`, as the mock passes it, with or without the cycle.
		let fixture = Self.typeBuiltAsParameterLabelFixture(rootDeclares: [
			"@Instantiated let other: X",
			#"@Received(fulfilledByDependencyNamed: "other", ofType: X.self, onlyIfAvailable: true) let renamed: X?"#,
		])
		try await expectGeneratedTree(of: fixture, root: "Root", equals: { fixtures in """
		extension Root {
		    public convenience init() {
		        let other = X(renamed: nil)
		        #sourceLocation(file: "\(fixtures["Root.swift"])", line: 10)
		        let renamed: X? = other
		        #sourceLocation()
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                let renamed = X(renamed: nil)
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return Mid(renamed: renamed, aBuilder: aBuilder)
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return A(renamed: renamed, midBuilder: midBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        self.init(other: other, renamed: renamed, aBuilder: aBuilder)
		    }
		}
		""" }, mock: { fixtures in """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            other: ((X?) -> X)? = nil,
		            aBuilder: A.SafeDIMockConfiguration = .init()
		        ) {
		            self.other = other
		            self.aBuilder = aBuilder
		        }

		        private(set) var other: ((X?) -> X)?
		        private(set) var aBuilder: A.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let other = if let safeDIBuilder = safeDIOverrides.other { safeDIBuilder(nil) } else { X(renamed: nil) }
		        #sourceLocation(file: "\(fixtures["Root.swift"])", line: 10)
		        let renamed: X? = other
		        #sourceLocation()
		        func __safeDI_aBuilder(renamed: X?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                let renamed = if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.renamed { safeDIBuilder(nil) } else { X(renamed: nil) }
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(renamed, aBuilder) } else { Mid(renamed: renamed, aBuilder: aBuilder) }
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(renamed, midBuilder) } else { A(renamed: renamed, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        return Root(other: other, renamed: renamed, aBuilder: aBuilder)
		    }
		}
		#endif
		""" }, mockBuildsTheSameValues: false, buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func a(renamed: X?) -> A {
		            A(renamed: renamed, midBuilder: Instantiator<Mid> {
		                let x = X(renamed: nil)
		                return Mid(renamed: x, aBuilder: Instantiator<A> { a(renamed: x) })
		            })
		        }
		        let other = X(renamed: nil)
		        self.init(other: other, renamed: other, aBuilder: Instantiator<A> { a(renamed: other) })
		    }
		}
		""")
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
	mutating func generate_throwsCaptureError_whenSendableCycleClosingScopePassesInstantiatorAliasOfParameterLabelCreatedInClosedOnFunctionsBody() async {
		// Nothing above `A`'s builder function provides `renamed`, so `Mid` creates its `onlyIfAvailable` alias of `xBuilder`,
		// an `Instantiator`, and the cycle-closing scope's `SendableInstantiator` closure passes it: the capture error, at the
		// alias the closure captures.
		let fixture = Self.aliasOfParameterLabelFixture(
			wrapper: .sendableInstantiator,
			labelType: "Instantiator<X>",
			midFulfillingDeclaration: "@Instantiated let xBuilder: Instantiator<X>",
		)
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["A.swift"]):8:5: error: @Received property `renamed: Instantiator<X>?` cannot be received inside a `@Sendable` function in chain: Root -> A -> Mid -> A. SafeDI builds `aBuilder: SendableInstantiator<A>` on `Mid` in a `@Sendable` function, which cannot capture `renamed: Instantiator<X>?` on `Mid`, because `Instantiator<X>` is not `Sendable`. Declare `renamed` on `Mid`, and this property, as `SendableInstantiator<X>` to fix. `SendableInstantiator<X>` builds `X` in a `@Sendable` function, so what the tree of `X` receives from outside that function must be `Sendable` too.
			\(fixtures["Mid.swift"]):10:5: note: `renamed: Instantiator<X>?` is declared here
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

	// MARK: Tests – A cycle closed by another form of the declaration it repeats

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_settlesCycleParameters_whenLazilyInstantiatedDependencyClosesCycleOnConstantDeclaration() async throws {
		// The preview lazily opens an editor of its own, which receives the preview's theme. The walk that finds the editor
		// function's parameters meets the theme first at the lazy `editor`, which repeats the constant `editor` declaration.
		let fixture = [
			seamFixtureType(named: "App", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let editor: Editor"]),
			seamFixtureType(named: "Editor", isFinalClass: true, declarations: ["@Instantiated let previewBuilder: Instantiator<Preview>", "@Instantiated let toolbar: Toolbar"]),
			seamFixtureType(named: "Preview", isFinalClass: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let editor: LazilyInstantiated<Editor>"]),
			seamFixtureType(named: "Toolbar", isFinalClass: true, declarations: ["@Received let theme: Theme"]),
			seamFixtureType(named: "Theme", isFinalClass: true, declarations: []),
		]
		try await expectGeneratedTree(of: fixture, root: "App", equals: """
		extension App {
		    public convenience init() {
		        let theme = Theme()
		        func __safeDI_editor(theme: Theme) -> Editor {
		            func __safeDI_previewBuilder() -> Preview {
		                let theme = Theme()
		                let editor = LazilyInstantiated<Editor> {
		                    __safeDI_editor(theme: theme)
		                }
		                return Preview(theme: theme, editor: editor)
		            }
		            let previewBuilder = Instantiator<Preview>(__safeDI_previewBuilder)
		            let toolbar = Toolbar(theme: theme)
		            return Editor(previewBuilder: previewBuilder, toolbar: toolbar)
		        }
		        let editor: Editor = __safeDI_editor(theme: theme)
		        self.init(theme: theme, editor: editor)
		    }
		}
		""", buildsTheSameValuesAs: """
		extension App {
		    public convenience init() {
		        func editor(theme: Theme) -> Editor {
		            Editor(previewBuilder: Instantiator<Preview> {
		                let previewTheme = Theme()
		                return Preview(theme: previewTheme, editor: LazilyInstantiated<Editor> { editor(theme: previewTheme) })
		            }, toolbar: Toolbar(theme: theme))
		        }
		        let theme = Theme()
		        self.init(theme: theme, editor: editor(theme: theme))
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_settlesCycleParameters_whenConstantDependencyClosesCycleOnLazilyInstantiatedDeclaration() async throws {
		// The preview opens an editor of its own, which receives the preview's theme. The walk that finds the editor
		// function's parameters meets the theme first at the constant `editor`, which repeats the lazy `editor` declaration.
		let fixture = [
			seamFixtureType(named: "App", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let editor: LazilyInstantiated<Editor>"]),
			seamFixtureType(named: "Editor", isFinalClass: true, declarations: ["@Instantiated let previewBuilder: Instantiator<Preview>", "@Instantiated let toolbar: Toolbar"]),
			seamFixtureType(named: "Preview", isFinalClass: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let editor: Editor"]),
			seamFixtureType(named: "Toolbar", isFinalClass: true, declarations: ["@Received let theme: Theme"]),
			seamFixtureType(named: "Theme", isFinalClass: true, declarations: []),
		]
		try await expectGeneratedTree(of: fixture, root: "App", equals: """
		extension App {
		    public convenience init() {
		        let theme = Theme()
		        func __safeDI_editor(theme: Theme) -> Editor {
		            func __safeDI_previewBuilder() -> Preview {
		                let theme = Theme()
		                let editor: Editor = __safeDI_editor(theme: theme)
		                return Preview(theme: theme, editor: editor)
		            }
		            let previewBuilder = Instantiator<Preview>(__safeDI_previewBuilder)
		            let toolbar = Toolbar(theme: theme)
		            return Editor(previewBuilder: previewBuilder, toolbar: toolbar)
		        }
		        let editor = LazilyInstantiated<Editor> {
		            __safeDI_editor(theme: theme)
		        }
		        self.init(theme: theme, editor: editor)
		    }
		}
		""", buildsTheSameValuesAs: """
		extension App {
		    public convenience init() {
		        func editor(theme: Theme) -> Editor {
		            Editor(previewBuilder: Instantiator<Preview> {
		                let previewTheme = Theme()
		                return Preview(theme: previewTheme, editor: editor(theme: previewTheme))
		            }, toolbar: Toolbar(theme: theme))
		        }
		        let theme = Theme()
		        self.init(theme: theme, editor: LazilyInstantiated<Editor> { editor(theme: theme) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsCaptureErrorAtToolbar_whenSendableLazilyInstantiatedDependencyClosesCycleOnConstantDeclarationPassingInstantiatorDeclaredOutsideIt() async {
		// The preview's `SendableLazilyInstantiated` closure passes the preview's `themeBuilder`, declared outside it, to the
		// editor function: the capture error, reported where the function's body first receives `themeBuilder`, the toolbar,
		// through the chain from the editor the closure builds again.
		let fixture = [
			seamFixtureType(named: "App", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let themeBuilder: Instantiator<Theme>", "@Instantiated let editor: Editor"]),
			seamFixtureType(named: "Editor", isFinalClass: true, declarations: ["@Instantiated let previewBuilder: Instantiator<Preview>", "@Instantiated let toolbar: Toolbar"], conformances: ", @unchecked Sendable"),
			seamFixtureType(named: "Preview", isFinalClass: true, declarations: ["@Instantiated let themeBuilder: Instantiator<Theme>", "@Instantiated let editor: SendableLazilyInstantiated<Editor>"]),
			seamFixtureType(named: "Toolbar", isFinalClass: true, declarations: ["@Received let themeBuilder: Instantiator<Theme>"]),
			seamFixtureType(named: "Theme", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Toolbar.swift"]):7:5: error: @Received property `themeBuilder: Instantiator<Theme>` cannot be received inside a `@Sendable` function in chain: App -> Editor -> Preview -> Editor -> Toolbar. SafeDI builds `editor: SendableLazilyInstantiated<Editor>` on `Preview` in a `@Sendable` function, which cannot capture `themeBuilder: Instantiator<Theme>` on `Preview`, because `Instantiator<Theme>` is not `Sendable`. Declare `themeBuilder` on `Preview`, and this property, as `SendableInstantiator<Theme>` to fix. `SendableInstantiator<Theme>` builds `Theme` in a `@Sendable` function, so what the tree of `Theme` receives from outside that function must be `Sendable` too.
			\(fixtures["Preview.swift"]):8:5: note: `themeBuilder: Instantiator<Theme>` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Tests – A label received in unrelated forms

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearestDeclaration_whenTreeBuiltAgainReceivesLabelOnlyIfAvailableInOneForm() async throws {
		// Only `C` receives `x`, so the `C` that `S` builds again receives `S`'s `x`, and the first `C` gets `nil`.
		try await expectGeneratedTree(of: Self.unrelatedFormsFixture(rootDeclares: [], aDeclaresB: false), root: "Root", equals: """
		extension Root {
		    public convenience init() {
		        func __safeDI_aBuilder(x: Y?) -> A {
		            let c = C(x: x)
		            func __safeDI_sBuilder() -> S {
		                let x = Y()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(x: x)
		                }
		                return S(x: x, aBuilder: aBuilder)
		            }
		            let sBuilder = Instantiator<S>(__safeDI_sBuilder)
		            return A(c: c, sBuilder: sBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(x: nil)
		        }
		        self.init(aBuilder: aBuilder)
		    }
		}
		""", buildsTheSameValuesAs: """
		extension Root {
		    public convenience init() {
		        func a(x: Y?) -> A {
		            A(c: C(x: x), sBuilder: Instantiator<S> {
		                let sX = Y()
		                return S(x: sX, aBuilder: Instantiator<A> { a(x: sX) })
		            })
		        }
		        self.init(aBuilder: Instantiator<A> { a(x: nil) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearestDeclarationOfRequiredForm_whenSiblingReceivesLabelOnlyIfAvailableInUnrelatedForm() async throws {
		// `Root` and `S` each instantiate `x: X`; `B` requires `x: X`; `C`, its sibling, receives `x: Y?` only if available,
		// which no declaration of `x: X` provides. The `B` that `S` builds again receives `S`'s `x`, as it does without `C`,
		// and `C` gets `nil` throughout. A mock of this tree is rejected: a mock reports `C`'s receive as hidden (see
		// `ReceivedPropertyHiddenInMockTree`).
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let b: B", "@Instantiated let c: C", "@Instantiated let sBuilder: Instantiator<S>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let x: X"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: Y?"]),
			seamFixtureType(named: "S", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
		try await expectGeneratedTree(of: fixture, root: "Root", equals: """
		extension Root {
		    public convenience init() {
		        let x = X()
		        func __safeDI_aBuilder(x: X) -> A {
		            let b = B(x: x)
		            let c = C(x: nil)
		            func __safeDI_sBuilder() -> S {
		                let x = X()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(x: x)
		                }
		                return S(x: x, aBuilder: aBuilder)
		            }
		            let sBuilder = Instantiator<S>(__safeDI_sBuilder)
		            return A(b: b, c: c, sBuilder: sBuilder)
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
		            A(b: B(x: x), c: C(x: nil), sBuilder: Instantiator<S> {
		                let sX = X()
		                return S(x: sX, aBuilder: Instantiator<A> { a(x: sX) })
		            })
		        }
		        let x = X()
		        self.init(x: x, aBuilder: Instantiator<A> { a(x: x) })
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUnpassableLabelError_whenTreeBuiltAgainReceivesLabelOnlyIfAvailableInUnrelatedFormsNothingAboveProvides() async {
		// The `C` that `S` builds again would receive `S`'s `Y`, and every `B` `nil`, but `A` is handed one value of `x`.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["B.swift"]):7:5: error: @Received property `x: X?` is received in chain: A -> B. A dependency cycle builds `A` again beneath `S`, which declares `x: Y` with the same label, and SafeDI hands each `A` one value of `x`. `A` and the types it builds receive `x` as `x: X?` and `x: Y?`, which one value cannot carry together. Receive `x: X?` and `x: Y?` under different labels to fix.
			\(fixtures["S.swift"]):8:5: note: `x: Y` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: Self.unrelatedFormsFixture(rootDeclares: []), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUnpassableLabelError_whenRootDeclaresTheFormTheTypeBuiltAgainReads() async {
		// `Root` instantiates `x: Y`, which the first `C` receives; the `C` that `S` builds again would receive `S`'s.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["B.swift"]):7:5: error: @Received property `x: X?` is received in chain: A -> B. A dependency cycle builds `A` again beneath `S`, which declares `x: Y` with the same label, and SafeDI hands each `A` one value of `x`. `A` and the types it builds receive `x` as `x: X?` and `x: Y?`, which one value cannot carry together. Receive `x: X?` and `x: Y?` under different labels to fix.
			\(fixtures["S.swift"]):8:5: note: `x: Y` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: Self.unrelatedFormsFixture(rootDeclares: ["@Instantiated let x: Y"]), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenRootDeclaresFormOfLabelThatTypeBetweenHidesFromTypeBuiltAgain() async {
		// `Root` instantiates `x: X`, which `S`'s `x: Y` hides from the `B` built again beneath it, as on any other path.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["B.swift"]):7:5: error: @Received property `x: X?` is hidden in chain: Root -> Instantiator<A> -> Instantiator<S> -> Instantiator<A> -> B. `S` declares `x: Y` with the same label, so the types below `S` receive `x: Y` instead. Give `x: Y` on `S` a different label to fix.
			\(fixtures["S.swift"]):8:5: note: `x: Y` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: Self.unrelatedFormsFixture(rootDeclares: ["@Instantiated let x: X"]), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUnpassableLabelError_whenTreeBuiltAgainReceivesLabelOnlyIfAvailableAsInstanceAndInstantiator() async {
		// `B` receives `x: X?` and `C` receives `x: Instantiator<X>?`, each only if available; `S` instantiates `x: X`.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let b: B", "@Instantiated let c: C", "@Instantiated let sBuilder: Instantiator<S>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: Instantiator<X>?"]),
			seamFixtureType(named: "S", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["B.swift"]):7:5: error: @Received property `x: X?` is received in chain: A -> B. A dependency cycle builds `A` again beneath `S`, which declares `x: X` with the same label, and SafeDI hands each `A` one value of `x`. `A` and the types it builds receive `x` as `x: Instantiator<X>?` and `x: X?`, which one value cannot carry together. Receive `x: Instantiator<X>?` and `x: X?` under different labels to fix.
			\(fixtures["S.swift"]):8:5: note: `x: X` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUnpassableLabelErrorNotingDeclarationFirstInSourceOrder_whenSeveralTypesBetweenDeclareLabel() async {
		// Six types between `A` and the dependency that builds it again each declare `x: Y`, in an order unlike their names'
		// and in files whose order is unlike both: the first file declares `S5`.
		let chain = ["S4", "S2", "S6", "S1", "S5", "S3"]
		let inFileOrder = ["S5", "S3", "S1", "S6", "S2", "S4"]
		let fixture = Self.unrelatedFormsFixture(rootDeclares: [])
			.filter { !$0.contains(" S: Instantiable") }
			.map { $0.replacingOccurrences(of: "Instantiator<S>", with: "Instantiator<\(chain[0])>") }
		var swiftFileContentByFilePath = [String: String]()
		for (index, name) in chain.enumerated() {
			let next = index + 1 < chain.count ? "@Instantiated let next: Instantiator<\(chain[index + 1])>" : "@Instantiated let aBuilder: Instantiator<A>"
			let fileNumber = (inFileOrder.firstIndex(of: name) ?? 0) + 1
			swiftFileContentByFilePath["Declaration\(fileNumber).swift"] = seamFixtureType(named: name, isFinalClass: true, declarations: ["@Instantiated let x: Y", next])
		}
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["B.swift"]):7:5: error: @Received property `x: X?` is received in chain: A -> B. A dependency cycle builds `A` again beneath `S5`, which declares `x: Y` with the same label, and SafeDI hands each `A` one value of `x`. `A` and the types it builds receive `x` as `x: X?` and `x: Y?`, which one value cannot carry together. Receive `x: X?` and `x: Y?` under different labels to fix.
			\(fixtures["Declaration1.swift"]):8:5: note: `x: Y` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, swiftFileContentByFilePath: swiftFileContentByFilePath, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUnpassableLabelError_whenTreeBuiltAgainReceivesWrapperAndItsInstanceOnlyIfAvailable() async {
		// `S` declares `x: LazilyInstantiated<X>`, which provides both forms, but a value passed where nothing above declares
		// `x` is an optional wrapper, which offers no instance.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["B.swift"]):7:5: error: @Received property `x: LazilyInstantiated<X>` is received in chain: A -> B. A dependency cycle builds `A` again beneath `S`, which declares `x: LazilyInstantiated<X>` with the same label, and SafeDI hands each `A` one value of `x`. `A` and the types it builds receive `x` as `x: LazilyInstantiated<X>` and `x: X?`, which one value cannot carry together. Receive `x: LazilyInstantiated<X>` and `x: X?` under different labels to fix.
			\(fixtures["S.swift"]):8:5: note: `x: LazilyInstantiated<X>` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: Self.wrapperAndInstanceFixture(top: Self.rootDeclaringABuilder), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsUnpassableLabelError_whenMockedTypesTreeBuiltAgainReceivesWrapperAndItsInstanceOnlyIfAvailable() async {
		// No root: only the mock of `P`, which instantiates `A`, builds the cycle. A mock reports a receive beneath a
		// declaration of its label that does not provide it as hidden, so only forms one declaration provides reach here.
		let top = seamFixtureType(named: "P", isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"])
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n")
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["B.swift"]):7:5: error: @Received property `x: LazilyInstantiated<X>` is received in chain: A -> B. A dependency cycle builds `A` again beneath `S`, which declares `x: LazilyInstantiated<X>` with the same label, and SafeDI hands each `A` one value of `x`. `A` and the types it builds receive `x` as `x: LazilyInstantiated<X>` and `x: X?`, which one value cannot carry together. Receive `x: LazilyInstantiated<X>` and `x: X?` under different labels to fix.
			\(fixtures["S.swift"]):8:5: note: `x: LazilyInstantiated<X>` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: Self.wrapperAndInstanceFixture(top: top), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUnpassableLabelError_whenTreeBuiltAgainRequiresInstanceBesideOptionalWrapperOnlyIfAvailable() async {
		// `B` requires `x: X` and `C` receives `x: LazilyInstantiated<X>?` only if available. `Root` and `S` each declare
		// `x: LazilyInstantiated<X>`, which provides both, but a parameter `x: X` cannot carry the wrapper `C` would get.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["B.swift"]):7:5: error: @Received property `x: X` is received in chain: A -> B. A dependency cycle builds `A` again beneath `S`, which declares `x: LazilyInstantiated<X>` with the same label, and SafeDI hands each `A` one value of `x`. `A` and the types it builds receive `x` as `x: LazilyInstantiated<X>?` and `x: X`, which one value cannot carry together. Receive `x: LazilyInstantiated<X>?` and `x: X` under different labels to fix.
			\(fixtures["S.swift"]):8:5: note: `x: LazilyInstantiated<X>` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: Self.requiredInstanceBesideOptionalWrapperFixture(rootGeneratesMock: false), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsUnpassableLabelError_whenMockedTypesTreeBuiltAgainRequiresInstanceBesideOptionalWrapperOnlyIfAvailable() async {
		// As in production, a parameter `x: X` cannot carry the wrapper `C` would get from `S`.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["B.swift"]):7:5: error: @Received property `x: X` is received in chain: A -> B. A dependency cycle builds `A` again beneath `S`, which declares `x: LazilyInstantiated<X>` with the same label, and SafeDI hands each `A` one value of `x`. `A` and the types it builds receive `x` as `x: LazilyInstantiated<X>?` and `x: X`, which one value cannot carry together. Receive `x: LazilyInstantiated<X>?` and `x: X` under different labels to fix.
			\(fixtures["S.swift"]):8:5: note: `x: LazilyInstantiated<X>` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: Self.requiredInstanceBesideOptionalWrapperFixture(rootGeneratesMock: true), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsUnpassableLabelError_whenTreeBuiltAgainRequiresInstanceBesideAliasOfWrapperOnlyIfAvailable() async {
		// `Root` declares `x: X`, which gives `C`'s alias `nil`; `S` declares `x: LazilyInstantiated<X>`, which would give
		// the alias the wrapper that a parameter `x: X` cannot carry.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let b: B", "@Instantiated let c: C", "@Instantiated let sBuilder: Instantiator<S>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let x: X"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: [#"@Received(fulfilledByDependencyNamed: "x", ofType: LazilyInstantiated<X>.self, onlyIfAvailable: true) let lazyX: LazilyInstantiated<X>?"#]),
			seamFixtureType(named: "S", isFinalClass: true, declarations: ["@Instantiated let x: LazilyInstantiated<X>", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["B.swift"]):7:5: error: @Received property `x: X` is received in chain: A -> B. A dependency cycle builds `A` again beneath `S`, which declares `x: LazilyInstantiated<X>` with the same label, and SafeDI hands each `A` one value of `x`. `A` and the types it builds receive `x` as `x: LazilyInstantiated<X>` and `x: X`, which one value cannot carry together. Receive `x: LazilyInstantiated<X>` and `x: X` under different labels to fix.
			\(fixtures["S.swift"]):8:5: note: `x: LazilyInstantiated<X>` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsEachUnpassableLabelErrorOnce_whenTreesOfTwoMockedTypesShareUnpassableLabel() async {
		// The mocks of `P` and `Q` each build `A`, whose label `x` is unpassable; `P`'s also builds `D`, whose `z` is.
		let p = seamFixtureType(named: "P", isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let dBuilder: Instantiator<D>"])
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n")
		let fixture = Self.wrapperAndInstanceFixture(top: p) + [
			seamFixtureType(named: "Q", isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"])
				.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n"),
			seamFixtureType(named: "D", isFinalClass: true, declarations: ["@Instantiated let e: E", "@Instantiated let f: F", "@Instantiated let tBuilder: Instantiator<T>"]),
			seamFixtureType(named: "E", isFinalClass: true, declarations: [#"@Received(fulfilledByDependencyNamed: "z", ofType: LazilyInstantiated<Z>.self, onlyIfAvailable: true) let lazyZ: LazilyInstantiated<Z>?"#]),
			seamFixtureType(named: "F", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let z: Z?"]),
			seamFixtureType(named: "T", isFinalClass: true, declarations: ["@Instantiated let z: LazilyInstantiated<Z>", "@Instantiated let dBuilder: Instantiator<D>"]),
			seamFixtureType(named: "Z", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["B.swift"]):7:5: error: @Received property `x: LazilyInstantiated<X>` is received in chain: A -> B. A dependency cycle builds `A` again beneath `S`, which declares `x: LazilyInstantiated<X>` with the same label, and SafeDI hands each `A` one value of `x`. `A` and the types it builds receive `x` as `x: LazilyInstantiated<X>` and `x: X?`, which one value cannot carry together. Receive `x: LazilyInstantiated<X>` and `x: X?` under different labels to fix.
			\(fixtures["S.swift"]):8:5: note: `x: LazilyInstantiated<X>` is declared here
			\(fixtures["E.swift"]):7:5: error: @Received property `z: LazilyInstantiated<Z>` is received in chain: D -> E. A dependency cycle builds `D` again beneath `T`, which declares `z: LazilyInstantiated<Z>` with the same label, and SafeDI hands each `D` one value of `z`. `D` and the types it builds receive `z` as `z: LazilyInstantiated<Z>` and `z: Z?`, which one value cannot carry together. Receive `z: LazilyInstantiated<Z>` and `z: Z?` under different labels to fix.
			\(fixtures["T.swift"]):8:5: note: `z: LazilyInstantiated<Z>` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	/// `Root`, which instantiates `x: LazilyInstantiated<X>` and `aBuilder`, and generates a mock when
	/// `rootGeneratesMock`; `A` builds `B`, which requires `x: X`, `C`, which receives `x: LazilyInstantiated<X>?` only if
	/// available, and `sBuilder`; `S` instantiates `x: LazilyInstantiated<X>` and closes the cycle on `A`.
	private static func requiredInstanceBesideOptionalWrapperFixture(rootGeneratesMock: Bool) -> [String] {
		[
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: LazilyInstantiated<X>", "@Instantiated let aBuilder: Instantiator<A>"])
				.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: rootGeneratesMock ? "@Instantiable(isRoot: true, generateMock: true)" : "@Instantiable(isRoot: true)"),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let b: B", "@Instantiated let c: C", "@Instantiated let sBuilder: Instantiator<S>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let x: X"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: LazilyInstantiated<X>?"]),
			seamFixtureType(named: "S", isFinalClass: true, declarations: ["@Instantiated let x: LazilyInstantiated<X>", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		]
	}

	/// A root that instantiates `aBuilder: Instantiator<A>`.
	private static let rootDeclaringABuilder = seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"])

	/// `top`, which builds `A`; `A` builds `B`, which receives `x: LazilyInstantiated<X>` as `lazyX` only if available, `C`,
	/// which receives `x: X?` only if available, and `sBuilder`; `S` instantiates `x: LazilyInstantiated<X>` and closes the
	/// cycle on `A`.
	private static func wrapperAndInstanceFixture(top: String) -> [String] {
		[
			top,
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let b: B", "@Instantiated let c: C", "@Instantiated let sBuilder: Instantiator<S>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: [#"@Received(fulfilledByDependencyNamed: "x", ofType: LazilyInstantiated<X>.self, onlyIfAvailable: true) let lazyX: LazilyInstantiated<X>?"#]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "S", isFinalClass: true, declarations: ["@Instantiated let x: LazilyInstantiated<X>", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		]
	}

	/// `A` builds `B`, which receives `x: X?` only if available, `C`, which receives `x: Y?` only if available, and
	/// `sBuilder`; `S` instantiates `x: Y` and closes the cycle on `A`. `Root` declares `rootDeclares` and `aBuilder`.
	private static func unrelatedFormsFixture(rootDeclares: [String], aDeclaresB: Bool = true) -> [String] {
		[
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: rootDeclares + ["@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: (aDeclaresB ? ["@Instantiated let b: B"] : []) + ["@Instantiated let c: C", "@Instantiated let sBuilder: Instantiator<S>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: Y?"]),
			seamFixtureType(named: "S", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The wrapper of the property that closes the lazy cycle of `aliasOfParameterLabelFixture`.
	enum CycleClosingWrapper: CaseIterable, Sendable {
		case instantiator
		case sendableInstantiator
		case erasedInstantiator
		case sendableErasedInstantiator

		/// The declaration of `aBuilder`, which builds `A`.
		var aBuilderDeclaration: String {
			switch self {
			case .instantiator:
				"@Instantiated let aBuilder: Instantiator<A>"
			case .sendableInstantiator:
				"@Instantiated let aBuilder: SendableInstantiator<A>"
			case .erasedInstantiator:
				#"@Instantiated(fulfilledByType: "A", erasedToConcreteExistential: true) let aBuilder: ErasedInstantiator<(), AnyA>"#
			case .sendableErasedInstantiator:
				#"@Instantiated(fulfilledByType: "A", erasedToConcreteExistential: true) let aBuilder: SendableErasedInstantiator<(), AnyA>"#
			}
		}

		/// Whether the wrapper builds `A` in a `@Sendable` function, so that the cycle's other hops do too.
		var isSendable: Bool {
			switch self {
			case .instantiator, .erasedInstantiator:
				false
			case .sendableInstantiator, .sendableErasedInstantiator:
				true
			}
		}

		/// Whether the wrapper hands out `A` erased to `AnyA`.
		var isErased: Bool {
			switch self {
			case .instantiator, .sendableInstantiator:
				false
			case .erasedInstantiator, .sendableErasedInstantiator:
				true
			}
		}

		/// The type of `aBuilder`.
		var generatedType: String {
			switch self {
			case .instantiator:
				"Instantiator<A>"
			case .sendableInstantiator:
				"SendableInstantiator<A>"
			case .erasedInstantiator:
				"ErasedInstantiator<(), AnyA>"
			case .sendableErasedInstantiator:
				"SendableErasedInstantiator<(), AnyA>"
			}
		}

		/// The wrapper of the cycle's other hops.
		var hopWrapper: String {
			isSendable ? "SendableInstantiator" : "Instantiator"
		}

		/// A hand-built `aBuilder` that builds `A` with `call`.
		func handBuiltABuilder(calling call: String) -> String {
			switch self {
			case .instantiator:
				"Instantiator<A> { \(call) }"
			case .sendableInstantiator:
				"SendableInstantiator<A> { \(call) }"
			case .erasedInstantiator:
				"ErasedInstantiator<(), AnyA> { AnyA(\(call)) }"
			case .sendableErasedInstantiator:
				"SendableErasedInstantiator<(), AnyA> { AnyA(\(call)) }"
			}
		}
	}

	/// Where `aliasOfParameterLabelFixture` declares the alias, relative to the scope that closes its lazy cycle.
	enum AliasPosition: CaseIterable, Sendable {
		/// On `Mid`, which holds the scope that closes the cycle.
		case besideCycleClosingScope
		/// On `Mid`, which builds the `Inner` that holds the scope that closes the cycle.
		case aboveCycleClosingScopesType
	}

	/// A spelling of the type of `aliasOfParameterLabelFixture`'s label through a name other than the type's own.
	enum LabelSpelling: CaseIterable, Sendable {
		/// `Feature.X`: `X` nested in `Feature`.
		case nestedType
		/// `XAlias`, a typealias of `X`.
		case typeAlias

		/// The label's type.
		var labelType: String {
			switch self {
			case .nestedType:
				"Feature.X"
			case .typeAlias:
				"XAlias"
			}
		}

		/// The type an initializer call builds the label's type with.
		var constructedType: String {
			switch self {
			case .nestedType:
				"Feature.X"
			case .typeAlias:
				"X"
			}
		}

		/// `Mid`'s declaration of `x`, the alias's fulfilling property.
		var fulfillingDeclaration: String {
			switch self {
			case .nestedType:
				"@Instantiated let x: Feature.X"
			case .typeAlias:
				#"@Instantiated(fulfilledByType: "X") let x: XAlias"#
			}
		}

		/// The declaration that gives the label's type its name.
		var declaration: String {
			switch self {
			case .nestedType:
				"public enum Feature {}"
			case .typeAlias:
				"public typealias XAlias = X"
			}
		}
	}

	/// `Root`, which generates its mock, declares `rootDeclares` and instantiates `aBuilder`, which builds `A`; `A` declares
	/// `aReceives`, a receive of `renamed`, and instantiates `midBuilder`; `Mid` declares `midFulfillingDeclaration`, an
	/// `onlyIfAvailable` alias `renamed` of it, `midDeclaresBesideAlias`, and the `aBuilder` that builds `A` again, or, above
	/// the cycle-closing scope, `innerBuilder`, whose `Inner` declares that `aBuilder`; `X` declares `xReceives`, a receive of
	/// `renamed`, declared in an extension of `xEnclosingType` where it is not `nil`. `renamed` is a `labelType`, which
	/// `midFulfillingDeclaration` declares, made optional. Each type is `@unchecked Sendable` where `wrapper` is `Sendable`.
	private static func aliasOfParameterLabelFixture(
		wrapper: CycleClosingWrapper = .instantiator,
		aliasPosition: AliasPosition = .besideCycleClosingScope,
		rootDeclares: [String] = [],
		labelType: String = "X",
		aReceives: String? = nil,
		midFulfillingDeclaration: String = "@Instantiated let x: X",
		midDeclaresBesideAlias: [String] = [],
		xReceives: String? = nil,
		xEnclosingType: String? = nil,
		otherTypes: [String] = [],
	) -> [String] {
		let isExistential = labelType.hasPrefix("any ")
		let optionalLabelType = isExistential ? "(\(labelType))?" : "\(labelType)?"
		let labelMetatype = isExistential ? "(\(labelType)).self" : "\(labelType).self"
		let fulfillingLabel = midFulfillingDeclaration[midFulfillingDeclaration.range(of: " let ")!.upperBound...].prefix { $0 != ":" }
		let conformances = wrapper.isSendable ? ", @unchecked Sendable" : ""
		let cycleClosingDeclaration = switch aliasPosition {
		case .besideCycleClosingScope:
			wrapper.aBuilderDeclaration
		case .aboveCycleClosingScopesType:
			"@Instantiated let innerBuilder: \(wrapper.hopWrapper)<Inner>"
		}
		// Appended rather than joined with `+` around a ternary: Swift 6.2 on Linux can time out type-checking a `+` with a
		// ternary inside a larger expression; later Swift does not.
		var xConformances = conformances
		if isExistential {
			xConformances += ", XProtocol"
		}
		let x = seamFixtureType(named: "X", isFinalClass: true, declarations: [xReceives ?? "@Received(onlyIfAvailable: true) let renamed: \(optionalLabelType)"], conformances: xConformances)
			.replacingOccurrences(of: "@Instantiable\n", with: isExistential ? "@Instantiable(fulfillingAdditionalTypes: [XProtocol.self])\n" : "@Instantiable\n")
		var fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: rootDeclares + [wrapper.aBuilderDeclaration], conformances: conformances)
				.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: true)"),
			seamFixtureType(named: "A", isFinalClass: true, declarations: [aReceives ?? "@Received(onlyIfAvailable: true) let renamed: \(optionalLabelType)", "@Instantiated let midBuilder: \(wrapper.hopWrapper)<Mid>"], conformances: conformances),
			seamFixtureType(named: "Mid", isFinalClass: true, declarations: [
				midFulfillingDeclaration,
				#"@Received(fulfilledByDependencyNamed: "\#(fulfillingLabel)", ofType: \#(labelMetatype), onlyIfAvailable: true) let renamed: \#(optionalLabelType)"#,
			] + midDeclaresBesideAlias + [cycleClosingDeclaration], conformances: conformances),
			xEnclosingType.map { "extension \($0) {\n\(x)\n}" } ?? x,
		]
		switch aliasPosition {
		case .besideCycleClosingScope:
			break
		case .aboveCycleClosingScopesType:
			fixture.append(seamFixtureType(named: "Inner", isFinalClass: true, declarations: [wrapper.aBuilderDeclaration], conformances: conformances))
		}
		if isExistential {
			fixture.append("public protocol XProtocol: AnyObject {}")
		}
		if wrapper.isErased {
			fixture.append(erasedAFixture(isSendable: wrapper.isSendable))
		}
		return fixture + otherTypes
	}

	/// `AProtocol`, which `A` conforms to, and `AnyA`, which erases it: the type an erased `aBuilder` hands out.
	private static func erasedAFixture(isSendable: Bool) -> String {
		"""
		public protocol AProtocol: AnyObject {}
		public final class AnyA\(isSendable ? ": @unchecked Sendable" : "") {
		    public init(_ a: some AProtocol) {
		        self.a = a
		    }

		    public let a: any AProtocol
		}
		extension A: AProtocol {}
		"""
	}

	/// The expression a mock of `Root` reads the override at `path` beneath `safeDIOverrides.aBuilder` with: the override
	/// itself, or, where `wrapper` is `Sendable`, the local a `@Sendable` builder function reads it from, bound before the
	/// function and named after the override's path, ending in `safeDIBuilder`.
	private static func mockOverride(_ path: String, wrapper: CycleClosingWrapper) -> String {
		if !wrapper.isSendable {
			"safeDIOverrides.aBuilder.\(path)"
		} else if path == "safeDIBuilder" {
			"__safeDI_aBuilder__safeDIBuilder"
		} else {
			"__safeDI_aBuilder__aBuilder_\(path.replacingOccurrences(of: ".", with: "_"))\(path.hasSuffix("safeDIBuilder") ? "" : "_safeDIBuilder")"
		}
	}

	/// `Root`, which generates its mock, declares `rootDeclares` and instantiates `aBuilder`, which builds `A`; `A` declares
	/// `aReceives`, a receive of `renamed`, and instantiates `midBuilder`; `Mid` declares `midDeclares` and the `aBuilder`
	/// that builds `A` again; `X` declares `xDeclares`. Each type is `@unchecked Sendable` where `wrapper` is `Sendable`.
	private static func typeBuiltAsParameterLabelFixture(
		wrapper: CycleClosingWrapper = .instantiator,
		rootDeclares: [String] = ["@Instantiated let renamed: X"],
		aReceives: String = "@Received(onlyIfAvailable: true) let renamed: X?",
		midDeclares: [String] = ["@Instantiated let renamed: X"],
		xDeclares: [String] = ["@Received(onlyIfAvailable: true) let renamed: X?"],
		otherTypes: [String] = [],
	) -> [String] {
		let conformances = wrapper.isSendable ? ", @unchecked Sendable" : ""
		var fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: rootDeclares + [wrapper.aBuilderDeclaration], conformances: conformances)
				.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: true)"),
			seamFixtureType(named: "A", isFinalClass: true, declarations: [aReceives, "@Instantiated let midBuilder: \(wrapper.hopWrapper)<Mid>"], conformances: conformances),
			seamFixtureType(named: "Mid", isFinalClass: true, declarations: midDeclares + [wrapper.aBuilderDeclaration], conformances: conformances),
			seamFixtureType(named: "X", isFinalClass: true, declarations: xDeclares, conformances: conformances),
		]
		if wrapper.isErased {
			fixture.append(erasedAFixture(isSendable: wrapper.isSendable))
		}
		return fixture + otherTypes
	}

	/// The tree SafeDI generates for `Root` of `typeBuiltAsParameterLabelFixture` with `wrapper`, whose `A` receives
	/// `renamed` as `parameterType`: `X` is passed `nil` wherever it is built as `renamed`.
	private static func expectedTypeBuiltAsParameterLabelTree(wrapper: CycleClosingWrapper, parameterType: String) -> String {
		let sendable = wrapper.isSendable ? "@Sendable nonisolated " : ""
		let aBuiltWith = { (argument: String) in
			wrapper.isErased ? "AnyA(__safeDI_aBuilder(renamed: \(argument)))" : "__safeDI_aBuilder(renamed: \(argument))"
		}
		return """
		extension Root {
		    public convenience init() {
		        let renamed = X(renamed: nil)
		        \(sendable)func __safeDI_aBuilder(renamed: \(parameterType)) -> A {
		            \(sendable)func __safeDI_midBuilder() -> Mid {
		                let renamed = X(renamed: nil)
		                let aBuilder = \(wrapper.generatedType) {
		                    \(aBuiltWith("renamed"))
		                }
		                return Mid(renamed: renamed, aBuilder: aBuilder)
		            }
		            let midBuilder = \(wrapper.hopWrapper)<Mid>(__safeDI_midBuilder)
		            return A(renamed: renamed, midBuilder: midBuilder)
		        }
		        let aBuilder = \(wrapper.generatedType) {
		            \(aBuiltWith("renamed"))
		        }
		        self.init(renamed: renamed, aBuilder: aBuilder)
		    }
		}
		"""
	}

	/// The mock SafeDI generates for `Root` of `typeBuiltAsParameterLabelFixture` with `wrapper`, whose `A` receives `renamed`
	/// as `parameterType`.
	private static func expectedTypeBuiltAsParameterLabelMock(wrapper: CycleClosingWrapper, parameterType: String) -> String {
		let sendable = wrapper.isSendable ? "@Sendable nonisolated " : ""
		let overrideLocals = wrapper.isSendable ? ["midBuilder.safeDIBuilder", "midBuilder.renamed", "safeDIBuilder"] : []
		let aConstruction = { (construction: String) in wrapper.isErased ? "AnyA(\(construction))" : construction }
		return """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            renamed: ((X?) -> X)? = nil,
		            aBuilder: A.SafeDIMockConfiguration = .init()
		        ) {
		            self.renamed = renamed
		            self.aBuilder = aBuilder
		        }

		        private(set) var renamed: ((X?) -> X)?
		        private(set) var aBuilder: A.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let renamed = if let safeDIBuilder = safeDIOverrides.renamed { safeDIBuilder(nil) } else { X(renamed: nil) }
		\(overrideLocals.map { "        let \(mockOverride($0, wrapper: wrapper)) = safeDIOverrides.aBuilder.\($0)\n" }.joined())        \(sendable)func __safeDI_aBuilder(renamed: \(parameterType)) -> \(wrapper.isErased ? "AnyA" : "A") {
		            \(sendable)func __safeDI_midBuilder() -> Mid {
		                let renamed = if let safeDIBuilder = \(mockOverride("midBuilder.renamed", wrapper: wrapper)) { safeDIBuilder(nil) } else { X(renamed: nil) }
		                let aBuilder = \(wrapper.generatedType) {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return if let safeDIBuilder = \(mockOverride("midBuilder.safeDIBuilder", wrapper: wrapper)) { safeDIBuilder(renamed, aBuilder) } else { Mid(renamed: renamed, aBuilder: aBuilder) }
		            }
		            let midBuilder = \(wrapper.hopWrapper)<Mid>(__safeDI_midBuilder)
		            return if let safeDIBuilder = \(mockOverride("safeDIBuilder", wrapper: wrapper)) { \(aConstruction("safeDIBuilder(renamed, midBuilder)")) } else { \(aConstruction("A(renamed: renamed, midBuilder: midBuilder)")) }
		        }
		        let aBuilder = \(wrapper.generatedType) {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        return Root(renamed: renamed, aBuilder: aBuilder)
		    }
		}
		#endif
		"""
	}

	/// The tree `Root` of `typeBuiltAsParameterLabelFixture` with `wrapper` builds by hand, whose `A` receives `renamed` as
	/// `parameterType`: `X` is passed `nil`, since `renamed` is still being built around it, and the `A` that `Mid` builds
	/// again is passed `Mid`'s `renamed`.
	private static func handBuiltTypeBuiltAsParameterLabelTree(wrapper: CycleClosingWrapper, parameterType: String) -> String {
		"""
		extension Root {
		    public convenience init() {
		        \(wrapper.isSendable ? "@Sendable " : "")func a(renamed: \(parameterType)) -> A {
		            A(renamed: renamed, midBuilder: \(wrapper.hopWrapper)<Mid> {
		                let renamed = X(renamed: nil)
		                return Mid(renamed: renamed, aBuilder: \(wrapper.handBuiltABuilder(calling: "a(renamed: renamed)")))
		            })
		        }
		        let renamed = X(renamed: nil)
		        self.init(renamed: renamed, aBuilder: \(wrapper.handBuiltABuilder(calling: "a(renamed: renamed)")))
		    }
		}
		"""
	}

	/// The tree `Root` of `aliasOfParameterLabelFixture`, with nothing else declared, builds by hand: `Mid` creates its alias
	/// from `x`, built first and passed `nil`, and builds `A` again with it.
	private static func handBuiltAliasOfParameterLabelTree(wrapper: CycleClosingWrapper, aliasPosition: AliasPosition) -> String {
		let aBuiltAgain = wrapper.handBuiltABuilder(calling: "a(renamed: x)")
		let mid = switch aliasPosition {
		case .besideCycleClosingScope:
			"Mid(x: x, renamed: x, aBuilder: \(aBuiltAgain))"
		case .aboveCycleClosingScopesType:
			"Mid(x: x, renamed: x, innerBuilder: \(wrapper.hopWrapper)<Inner> { Inner(aBuilder: \(aBuiltAgain)) })"
		}
		return """
		extension Root {
		    public convenience init() {
		        \(wrapper.isSendable ? "@Sendable " : "")func a(renamed: X?) -> A {
		            A(renamed: renamed, midBuilder: \(wrapper.hopWrapper)<Mid> {
		                let x = X(renamed: nil)
		                return \(mid)
		            })
		        }
		        self.init(aBuilder: \(wrapper.handBuiltABuilder(calling: "a(renamed: nil)")))
		    }
		}
		"""
	}

	/// The tree SafeDI generates for `Root` of `aliasOfParameterLabelFixture` with the label spelled as `spelling` spells it.
	private static func expectedSpelledAliasOfParameterLabelTree(spelling: LabelSpelling, fixtures: FixturePaths) -> String {
		let type = spelling.labelType
		// `x` is annotated with its declared type where that is not the type built.
		let xAnnotation = type == spelling.constructedType ? "" : ": \(type)"
		return """
		extension Root {
		    public convenience init() {
		        func __safeDI_aBuilder(renamed: \(type)?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                let x\(xAnnotation) = \(spelling.constructedType)(renamed: nil)
		                #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 10)
		                let renamed: \(type)? = x
		                #sourceLocation()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return Mid(x: x, renamed: renamed, aBuilder: aBuilder)
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return A(renamed: renamed, midBuilder: midBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: nil)
		        }
		        self.init(aBuilder: aBuilder)
		    }
		}
		"""
	}

	/// The mock SafeDI generates for `Root` of `aliasOfParameterLabelFixture` with the label spelled as `spelling` spells it.
	private static func expectedSpelledAliasOfParameterLabelMock(spelling: LabelSpelling, fixtures: FixturePaths) -> String {
		let type = spelling.labelType
		// `x` is annotated with its declared type where that is not the type built.
		let xAnnotation = type == spelling.constructedType ? "" : ": \(type)"
		return """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            aBuilder: A.SafeDIMockConfiguration = .init(),
		            renamed: \(type)? = nil
		        ) {
		            self.aBuilder = aBuilder
		            self.renamed = renamed
		        }

		        private(set) var aBuilder: A.SafeDIMockConfiguration
		        private(set) var renamed: \(type)?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let renamed: \(type)? = safeDIOverrides.renamed
		        func __safeDI_aBuilder(renamed: \(type)?) -> A {
		            func __safeDI_midBuilder() -> Mid {
		                let x\(xAnnotation) = if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.x { safeDIBuilder(nil) } else { \(spelling.constructedType)(renamed: nil) }
		                #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 10)
		                let renamed: \(type)? = x
		                #sourceLocation()
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(renamed: renamed)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(x, renamed, aBuilder) } else { Mid(x: x, renamed: renamed, aBuilder: aBuilder) }
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(renamed, midBuilder) } else { A(renamed: renamed, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        return Root(aBuilder: aBuilder)
		    }
		}
		#endif
		"""
	}

	/// The tree SafeDI generates for `Root` of `aliasOfParameterLabelFixture`, with nothing else declared.
	private static func expectedAliasOfParameterLabelTree(wrapper: CycleClosingWrapper, aliasPosition: AliasPosition, fixtures: FixturePaths) -> String {
		let sendable = wrapper.isSendable ? "@Sendable nonisolated " : ""
		let aBuiltWith = { (argument: String) in
			wrapper.isErased ? "AnyA(__safeDI_aBuilder(renamed: \(argument)))" : "__safeDI_aBuilder(renamed: \(argument))"
		}
		let midConstruction = switch aliasPosition {
		case .besideCycleClosingScope:
			"""
			                let aBuilder = \(wrapper.generatedType) {
			                    \(aBuiltWith("renamed"))
			                }
			                return Mid(x: x, renamed: renamed, aBuilder: aBuilder)
			"""
		case .aboveCycleClosingScopesType:
			"""
			                \(sendable)func __safeDI_innerBuilder() -> Inner {
			                    let aBuilder = \(wrapper.generatedType) {
			                        \(aBuiltWith("renamed"))
			                    }
			                    return Inner(aBuilder: aBuilder)
			                }
			                let innerBuilder = \(wrapper.hopWrapper)<Inner>(__safeDI_innerBuilder)
			                return Mid(x: x, renamed: renamed, innerBuilder: innerBuilder)
			"""
		}
		return """
		extension Root {
		    public convenience init() {
		        \(sendable)func __safeDI_aBuilder(renamed: X?) -> A {
		            \(sendable)func __safeDI_midBuilder() -> Mid {
		                let x = X(renamed: nil)
		                #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 10)
		                let renamed: X? = x
		                #sourceLocation()
		\(midConstruction)
		            }
		            let midBuilder = \(wrapper.hopWrapper)<Mid>(__safeDI_midBuilder)
		            return A(renamed: renamed, midBuilder: midBuilder)
		        }
		        let aBuilder = \(wrapper.generatedType) {
		            \(aBuiltWith("nil"))
		        }
		        self.init(aBuilder: aBuilder)
		    }
		}
		"""
	}

	/// The mock SafeDI generates for `Root` of `aliasOfParameterLabelFixture`, with nothing else declared. `Root` binds
	/// `renamed` to an override, which `A`'s builder function is passed where it is declared.
	private static func expectedAliasOfParameterLabelMock(wrapper: CycleClosingWrapper, aliasPosition: AliasPosition, fixtures: FixturePaths) -> String {
		let sendable = wrapper.isSendable ? "@Sendable nonisolated " : ""
		let override = { (path: String) in mockOverride(path, wrapper: wrapper) }
		// Appended rather than joined with `+` around ternaries: Swift 6.2 on Linux can time out type-checking a `+` chain
		// of arrays with ternaries; later Swift does not.
		var overrideLocals = [String]()
		if wrapper.isSendable {
			overrideLocals.append(contentsOf: ["midBuilder.safeDIBuilder", "midBuilder.x"])
			if aliasPosition == .aboveCycleClosingScopesType {
				overrideLocals.append("midBuilder.innerBuilder.safeDIBuilder")
			}
			overrideLocals.append("safeDIBuilder")
		}
		let midConstruction = switch aliasPosition {
		case .besideCycleClosingScope:
			"""
			                let aBuilder = \(wrapper.generatedType) {
			                    __safeDI_aBuilder(renamed: renamed)
			                }
			                return if let safeDIBuilder = \(override("midBuilder.safeDIBuilder")) { safeDIBuilder(x, renamed, aBuilder) } else { Mid(x: x, renamed: renamed, aBuilder: aBuilder) }
			"""
		case .aboveCycleClosingScopesType:
			"""
			                \(sendable)func __safeDI_innerBuilder() -> Inner {
			                    let aBuilder = \(wrapper.generatedType) {
			                        __safeDI_aBuilder(renamed: renamed)
			                    }
			                    return if let safeDIBuilder = \(override("midBuilder.innerBuilder.safeDIBuilder")) { safeDIBuilder(aBuilder) } else { Inner(aBuilder: aBuilder) }
			                }
			                let innerBuilder = \(wrapper.hopWrapper)<Inner>(__safeDI_innerBuilder)
			                return if let safeDIBuilder = \(override("midBuilder.safeDIBuilder")) { safeDIBuilder(x, renamed, innerBuilder) } else { Mid(x: x, renamed: renamed, innerBuilder: innerBuilder) }
			"""
		}
		let aConstruction = { (construction: String) in wrapper.isErased ? "AnyA(\(construction))" : construction }
		return """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            aBuilder: A.SafeDIMockConfiguration = .init(),
		            renamed: X? = nil
		        ) {
		            self.aBuilder = aBuilder
		            self.renamed = renamed
		        }

		        private(set) var aBuilder: A.SafeDIMockConfiguration
		        private(set) var renamed: X?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let renamed: X? = safeDIOverrides.renamed
		\(overrideLocals.map { "        let \(override($0)) = safeDIOverrides.aBuilder.\($0)\n" }.joined())        \(sendable)func __safeDI_aBuilder(renamed: X?) -> \(wrapper.isErased ? "AnyA" : "A") {
		            \(sendable)func __safeDI_midBuilder() -> Mid {
		                let x = if let safeDIBuilder = \(override("midBuilder.x")) { safeDIBuilder(nil) } else { X(renamed: nil) }
		                #sourceLocation(file: "\(fixtures["Mid.swift"])", line: 10)
		                let renamed: X? = x
		                #sourceLocation()
		\(midConstruction)
		            }
		            let midBuilder = \(wrapper.hopWrapper)<Mid>(__safeDI_midBuilder)
		            return if let safeDIBuilder = \(override("safeDIBuilder")) { \(aConstruction("safeDIBuilder(renamed, midBuilder)")) } else { \(aConstruction("A(renamed: renamed, midBuilder: midBuilder)")) }
		        }
		        let aBuilder = \(wrapper.generatedType) {
		            __safeDI_aBuilder(renamed: renamed)
		        }
		        return Root(aBuilder: aBuilder)
		    }
		}
		#endif
		"""
	}

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
		\(rootYBuilderDeclaration)        @Sendable nonisolated func __safeDI_t3Builder(yBuilder: Instantiator<Y>?) -> T3 {
		            let w = W(yBuilder: yBuilder)
		            func __safeDI_t0Builder() -> T0 {
		                @Sendable nonisolated func __safeDI_zBuilder() -> Z {
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
	/// mock's, through `root.mock()`, with those of the hand-built tree, which a mock of the root builds alike, unless
	/// `mockBuildsTheSameValues` is `false`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectGeneratedTree(
		of fixture: [String],
		root: String,
		equals expectedTree: (FixturePaths) -> String,
		mock expectedMock: ((FixturePaths) -> String)? = nil,
		mockBuildsTheSameValues: Bool = true,
		buildsTheSameValuesAs handBuiltTree: String,
		probes: [DifferentialValueProbe]? = nil,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == ["\(root)+SafeDI.swift": generatedFileHeader + expectedTree(output.fixtures)], sourceLocation: sourceLocation)
		#expect(output.mockFiles == (expectedMock.map { ["\(root)+SafeDIMock.swift": generatedFileHeader + $0(output.fixtures)] } ?? [:]), sourceLocation: sourceLocation)
		let comparesMock = expectedMock != nil && mockBuildsTheSameValues
		try expectDifferentialValuesAgree(
			feature: DifferentialValuePath(fixtureFiles: Self.fixtureFiles(fixture), generatedFiles: output.generatedFiles ?? [:]),
			knownRight: DifferentialValuePath(fixtureFiles: Self.fixtureFiles(fixture), generatedFiles: [
				"\(root)+SafeDI.swift": handBuiltTree + (comparesMock ? "\n\nextension \(root) {\n    static func mock() -> \(root) {\n        \(root)()\n    }\n}" : ""),
			]),
			probes: (probes ?? [DifferentialValueProbe("\(root)()")]) + (comparesMock ? [DifferentialValueProbe("\(root).mock()")] : []),
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
		mockBuildsTheSameValues: Bool = true,
		buildsTheSameValuesAs handBuiltTree: String,
		probes: [DifferentialValueProbe]? = nil,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		try await expectGeneratedTree(
			of: fixture,
			root: root,
			equals: { _ in expectedTree },
			mock: expectedMock.map { expectedMock in { _ in expectedMock } },
			mockBuildsTheSameValues: mockBuildsTheSameValues,
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
