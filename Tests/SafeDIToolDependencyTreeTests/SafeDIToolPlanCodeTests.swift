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

/// The code the type key lays out of a production root's per-type plan (`PlanCodeObservation`): one function per body,
/// declared in the root's body, called at each call place.
struct SafeDIToolPlanCodeTests: ~Copyable {
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
	mutating func generate_declaresOneFunctionPerBody_whenScreensOpenEachOther() async throws {
		// `Screen` and `Next` open each other beneath `Shell`, which is on no cycle: the plan has one body of each, whose
		// functions capture what their trees read from above, `clock`, which every call resolves to the root's.
		let codes = try await planCodes(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let clock: Clock
		    @Instantiated let shell: Shell
		    public init(clock: Clock, shell: Shell) { self.clock = clock; self.shell = shell }
		}

		@Instantiable public final class Clock: Instantiable { public init() {} }

		@Instantiable public final class Shell: Instantiable {
		    @Instantiated let screenBuilder: Instantiator<Screen>
		    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
		}

		@Instantiable public final class Screen: Instantiable {
		    @Received let clock: Clock
		    @Instantiated let nextBuilder: Instantiator<Next>
		    public init(clock: Clock, nextBuilder: Instantiator<Next>) { self.clock = clock; self.nextBuilder = nextBuilder }
		}

		@Instantiable public final class Next: Instantiable {
		    @Instantiated let screenBuilder: Instantiator<Screen>
		    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
		}
		""")

		#expect(codes == ["Root": """
		extension Root {
		    public convenience init() {
		        let clock = Clock()
		        func __safeDI_screenBuilder() -> Screen {
		            let nextBuilder = Instantiator<Next>(__safeDI_nextBuilder)
		            return Screen(clock: clock, nextBuilder: nextBuilder)
		        }
		        func __safeDI_nextBuilder() -> Next {
		            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		            return Next(screenBuilder: screenBuilder)
		        }
		        func __safeDI_shell() -> Shell {
		            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		            return Shell(screenBuilder: screenBuilder)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(clock: clock, shell: shell)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_marksFunctionSendable_whenItIsCalledInsideSendableFunction() async throws {
		// `Next` is built in a `@Sendable` function, from which its body calls `Screen`'s: both functions are `@Sendable`,
		// and `Shell`'s, which calls `Screen`'s outside every `@Sendable` function, is not.
		let codes = try await planCodes(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let shell: Shell
		    public init(shell: Shell) { self.shell = shell }
		}

		@Instantiable public final class Shell: Instantiable {
		    @Instantiated let screenBuilder: Instantiator<Screen>
		    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
		}

		@Instantiable public final class Screen: Instantiable {
		    @Instantiated let nextBuilder: SendableInstantiator<Next>
		    public init(nextBuilder: SendableInstantiator<Next>) { self.nextBuilder = nextBuilder }
		}

		@Instantiable public final class Next: Instantiable {
		    @Instantiated let screenBuilder: Instantiator<Screen>
		    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
		}
		""")

		#expect(codes == ["Root": """
		extension Root {
		    public convenience init() {
		        @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
		            let nextBuilder = SendableInstantiator<Next>(__safeDI_nextBuilder)
		            return Screen(nextBuilder: nextBuilder)
		        }
		        @Sendable nonisolated func __safeDI_nextBuilder() -> Next {
		            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		            return Next(screenBuilder: screenBuilder)
		        }
		        func __safeDI_shell() -> Shell {
		            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		            return Shell(screenBuilder: screenBuilder)
		        }
		        let shell: Shell = __safeDI_shell()
		        self.init(shell: shell)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresOneFunctionPerAnswer_whenBodiesOfOneTypeAreAnsweredApart() async throws {
		// `Home` receives `context` only if available: `Plain` builds it again beneath no `Context`, and `Scoped` beneath
		// its own. Each `Home` and `Plain` the plan answers apart gets a function of its own, which takes `context` where
		// its answer declares it.
		let codes = try await planCodes(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let home: Home
		    public init(home: Home) { self.home = home }
		}

		@Instantiable public final class Context: Instantiable { public init() {} }

		@Instantiable public final class Home: Instantiable {
		    @Received(onlyIfAvailable: true) let context: Context?
		    @Instantiated let plainBuilder: Instantiator<Plain>
		    @Instantiated let scopedBuilder: Instantiator<Scoped>
		    public init(context: Context?, plainBuilder: Instantiator<Plain>, scopedBuilder: Instantiator<Scoped>) { self.context = context; self.plainBuilder = plainBuilder; self.scopedBuilder = scopedBuilder }
		}

		@Instantiable public final class Plain: Instantiable {
		    @Instantiated let homeBuilder: Instantiator<Home>
		    public init(homeBuilder: Instantiator<Home>) { self.homeBuilder = homeBuilder }
		}

		@Instantiable public final class Scoped: Instantiable {
		    @Instantiated let context: Context
		    @Instantiated let homeBuilder: Instantiator<Home>
		    public init(context: Context, homeBuilder: Instantiator<Home>) { self.context = context; self.homeBuilder = homeBuilder }
		}
		""")

		#expect(codes == ["Root": """
		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            let plainBuilder = Instantiator<Plain>(__safeDI_plainBuilder)
		            let scopedBuilder = Instantiator<Scoped>(__safeDI_scopedBuilder)
		            return Home(context: nil, plainBuilder: plainBuilder, scopedBuilder: scopedBuilder)
		        }
		        func __safeDI_plainBuilder() -> Plain {
		            let homeBuilder = Instantiator<Home>(__safeDI_home)
		            return Plain(homeBuilder: homeBuilder)
		        }
		        func __safeDI_scopedBuilder() -> Scoped {
		            let context = Context()
		            let homeBuilder = Instantiator<Home> {
		                __safeDI_homeBuilder(context: context)
		            }
		            return Scoped(context: context, homeBuilder: homeBuilder)
		        }
		        func __safeDI_homeBuilder(context: Context) -> Home {
		            let plainBuilder = Instantiator<Plain> {
		                __safeDI_plainBuilder_(context: context)
		            }
		            let scopedBuilder = Instantiator<Scoped>(__safeDI_scopedBuilder)
		            return Home(context: context, plainBuilder: plainBuilder, scopedBuilder: scopedBuilder)
		        }
		        func __safeDI_plainBuilder_(context: Context) -> Plain {
		            let homeBuilder = Instantiator<Home> {
		                __safeDI_homeBuilder(context: context)
		            }
		            return Plain(homeBuilder: homeBuilder)
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsPathKeysBody_whenABodyHoldsLoopOfBuilders() async throws {
		// `Screen`'s builders receive each other, a loop the type key does not plan, so `Screen`'s body is written per
		// path and the root keeps the path key's body.
		let codes = try await planCodes(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let screenBuilder: Instantiator<Screen>
		    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
		}

		@Instantiable public final class Screen: Instantiable {
		    @Instantiated let aBuilder: Instantiator<A>
		    @Instantiated let bBuilder: Instantiator<B>
		    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) { self.aBuilder = aBuilder; self.bBuilder = bBuilder }
		}

		@Instantiable public final class A: Instantiable {
		    @Received let bBuilder: Instantiator<B>
		    @Instantiated let screenBuilder: Instantiator<Screen>
		    public init(bBuilder: Instantiator<B>, screenBuilder: Instantiator<Screen>) { self.bBuilder = bBuilder; self.screenBuilder = screenBuilder }
		}

		@Instantiable public final class B: Instantiable {
		    @Received let aBuilder: Instantiator<A>
		    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
		}
		""")

		#expect(codes == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsLazilyInstantiatedInstanceOnlyAtItsReader_whenOnlyATypeBuiltBeneathCallReadsIt() async throws {
		// `Home`, built by value in `Root`'s initializer, reads nothing of `logger`; `Detail`, which `Home` opens, reads its
		// instance. The functions hold the root's wrapper (captured, since every call passes it), so `Logger` is created
		// where a `Detail` is first built, as today.
		let codes = try await planCodes(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let logger: LazilyInstantiated<Logger>
		    @Instantiated let home: Home
		    public init(logger: LazilyInstantiated<Logger>, home: Home) { self.logger = logger; self.home = home }
		}

		@Instantiable public final class Logger: Instantiable { public init() {} }

		@Instantiable public final class Home: Instantiable {
		    @Instantiated let detailBuilder: Instantiator<Detail>
		    public init(detailBuilder: Instantiator<Detail>) { self.detailBuilder = detailBuilder }
		}

		@Instantiable public final class Detail: Instantiable {
		    @Received let logger: Logger
		    @Instantiated let homeBuilder: Instantiator<Home>
		    public init(logger: Logger, homeBuilder: Instantiator<Home>) { self.logger = logger; self.homeBuilder = homeBuilder }
		}
		""")

		#expect(codes == ["Root": """
		extension Root {
		    public convenience init() {
		        func __safeDI_logger() -> Logger {
		            Logger()
		        }
		        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
		        func __safeDI_home() -> Home {
		            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		            return Home(detailBuilder: detailBuilder)
		        }
		        func __safeDI_detailBuilder() -> Detail {
		            let homeBuilder = Instantiator<Home>(__safeDI_home)
		            return Detail(logger: logger.instance, homeBuilder: homeBuilder)
		        }
		        let home: Home = __safeDI_home()
		        self.init(logger: logger, home: home)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsLazilyInstantiatedInstanceOnlyAtItsReader_whenOnlyTheScreenOpenedNextReadsIt() async throws {
		// `Screen` reads nothing of `logger`; `Next`, which it opens, reads the instance. Opening a `Screen` creates no
		// `Logger`.
		let codes = try await planCodes(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let logger: LazilyInstantiated<Logger>
		    @Instantiated let screenBuilder: Instantiator<Screen>
		    public init(logger: LazilyInstantiated<Logger>, screenBuilder: Instantiator<Screen>) { self.logger = logger; self.screenBuilder = screenBuilder }
		}

		@Instantiable public final class Logger: Instantiable { public init() {} }

		@Instantiable public final class Screen: Instantiable {
		    @Instantiated let nextBuilder: Instantiator<Next>
		    public init(nextBuilder: Instantiator<Next>) { self.nextBuilder = nextBuilder }
		}

		@Instantiable public final class Next: Instantiable {
		    @Received let logger: Logger
		    @Instantiated let screenBuilder: Instantiator<Screen>
		    public init(logger: Logger, screenBuilder: Instantiator<Screen>) { self.logger = logger; self.screenBuilder = screenBuilder }
		}
		""")

		#expect(codes == ["Root": """
		extension Root {
		    public convenience init() {
		        func __safeDI_logger() -> Logger {
		            Logger()
		        }
		        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
		        func __safeDI_screenBuilder() -> Screen {
		            let nextBuilder = Instantiator<Next>(__safeDI_nextBuilder)
		            return Screen(nextBuilder: nextBuilder)
		        }
		        func __safeDI_nextBuilder() -> Next {
		            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		            return Next(logger: logger.instance, screenBuilder: screenBuilder)
		        }
		        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		        self.init(logger: logger, screenBuilder: screenBuilder)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsRenameThroughLazilyInstantiatedWrapper_whenTwoTypesOfCycleDeclareIt() async throws {
		// `Root` and `B` each declare `logger`, and `A`, which both open, renames its instance: `A`'s function takes the
		// wrapper, so the rename reads `.instance` of a wrapper. The plan's code is compiled.
		let (codes, fixtures) = try await planCodesAndFixtures(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let logger: LazilyInstantiated<Logger>
		    @Instantiated let aBuilder: Instantiator<A>
		    public init(logger: LazilyInstantiated<Logger>, aBuilder: Instantiator<A>) { self.logger = logger; self.aBuilder = aBuilder }
		}

		@Instantiable public final class Logger: Instantiable { public init() {} }

		@Instantiable public final class A: Instantiable {
		    @Received(fulfilledByDependencyNamed: "logger", ofType: Logger.self) let log: Logger
		    @Instantiated let bBuilder: Instantiator<B>
		    public init(log: Logger, bBuilder: Instantiator<B>) { self.log = log; self.bBuilder = bBuilder }
		}

		@Instantiable public final class B: Instantiable {
		    @Instantiated let logger: LazilyInstantiated<Logger>
		    @Instantiated let aBuilder: Instantiator<A>
		    public init(logger: LazilyInstantiated<Logger>, aBuilder: Instantiator<A>) { self.logger = logger; self.aBuilder = aBuilder }
		}
		""")

		#expect(codes == ["Root": """
		extension Root {
		    public convenience init() {
		        func __safeDI_logger() -> Logger {
		            Logger()
		        }
		        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
		        func __safeDI_aBuilder(logger: LazilyInstantiated<Logger>) -> A {
		            #sourceLocation(file: "\(fixtures["Root.swift"])", line: 10)
		            let log: Logger = logger.instance
		            #sourceLocation()
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            return A(log: log, bBuilder: bBuilder)
		        }
		        func __safeDI_bBuilder() -> B {
		            let logger = LazilyInstantiated<Logger>(__safeDI_logger)
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(logger: logger)
		            }
		            return B(logger: logger, aBuilder: aBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(logger: logger)
		        }
		        self.init(logger: logger, aBuilder: aBuilder)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsRenameOnlyIfAvailableThroughLazilyInstantiatedWrapper_whenTwoTypesOfCycleDeclareIt() async throws {
		// As above, with the rename only if available.
		let (codes, fixtures) = try await planCodesAndFixtures(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let logger: LazilyInstantiated<Logger>
		    @Instantiated let aBuilder: Instantiator<A>
		    public init(logger: LazilyInstantiated<Logger>, aBuilder: Instantiator<A>) { self.logger = logger; self.aBuilder = aBuilder }
		}

		@Instantiable public final class Logger: Instantiable { public init() {} }

		@Instantiable public final class A: Instantiable {
		    @Received(fulfilledByDependencyNamed: "logger", ofType: Logger.self, onlyIfAvailable: true) let log: Logger?
		    @Instantiated let bBuilder: Instantiator<B>
		    public init(log: Logger?, bBuilder: Instantiator<B>) { self.log = log; self.bBuilder = bBuilder }
		}

		@Instantiable public final class B: Instantiable {
		    @Instantiated let logger: LazilyInstantiated<Logger>
		    @Instantiated let aBuilder: Instantiator<A>
		    public init(logger: LazilyInstantiated<Logger>, aBuilder: Instantiator<A>) { self.logger = logger; self.aBuilder = aBuilder }
		}
		""")

		#expect(codes == ["Root": """
		extension Root {
		    public convenience init() {
		        func __safeDI_logger() -> Logger {
		            Logger()
		        }
		        let logger = LazilyInstantiated<Logger>(__safeDI_logger)
		        func __safeDI_aBuilder(logger: LazilyInstantiated<Logger>) -> A {
		            #sourceLocation(file: "\(fixtures["Root.swift"])", line: 10)
		            let log: Logger? = logger.instance
		            #sourceLocation()
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            return A(log: log, bBuilder: bBuilder)
		        }
		        func __safeDI_bBuilder() -> B {
		            let logger = LazilyInstantiated<Logger>(__safeDI_logger)
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(logger: logger)
		            }
		            return B(logger: logger, aBuilder: aBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(logger: logger)
		        }
		        self.init(logger: logger, aBuilder: aBuilder)
		    }
		}
		"""])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The code each root of `swiftFileContent` that reaches a cycle lays out of its plan, by root, `nil` where the type
	/// key keeps the path key's body, each compiled in place of the root's generated extension with the fixtures beside
	/// it, as every test's generated code is compiled.
	private mutating func planCodes(of swiftFileContent: String) async throws -> [String: String?] {
		try await planCodesAndFixtures(of: swiftFileContent).codes
	}

	/// `planCodes(of:)`, with the fixtures' paths, which a `#sourceLocation` of the code names.
	private mutating func planCodesAndFixtures(of swiftFileContent: String) async throws -> (codes: [String: String?], fixtures: FixturePaths) {
		let (stream, continuation) = AsyncStream.makeStream(of: (String, String?).self)
		let output = try await PlanCodeObservation.$observer.withValue({ root, code in
			continuation.yield((root, code))
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [swiftFileContent],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var codes = [String: String?]()
		for await (root, code) in stream {
			codes[root] = code
		}
		for (root, code) in codes.sorted(by: { $0.key < $1.key }) {
			guard let code else { continue }
			var generatedFiles = output.generatedFiles ?? [:]
			// Each root's extension ends the file generated for it, after the file's header and imports.
			let rootExtension = "extension \(root) {"
			let fileName = try #require(generatedFiles.keys.sorted().first { generatedFiles[$0]?.contains(rootExtension) == true })
			let generatedFile = try #require(generatedFiles[fileName])
			let start = try #require(generatedFile.range(of: rootExtension))
			generatedFiles[fileName] = String(generatedFile[..<start.lowerBound]) + code + "\n"
			try await verifyGeneratedCodeCompiles(
				inputSwiftFiles: output.fixtures.writtenPaths.map(URL.init(fileURLWithPath:)),
				additionalDirectorySwiftFiles: [],
				generatedFiles: generatedFiles,
				mockConditionalCompilation: nil,
				filesToDelete: &filesToDelete,
			)
		}
		return (codes, output.fixtures)
	}
}
