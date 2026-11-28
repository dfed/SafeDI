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
	mutating func generate_declaresOneFunctionTakingOptionalParameter_whenCallsAnswerLabelReceivedOnlyIfAvailableApart() async throws {
		// `Home` receives `context` only if available: `Plain` builds it again beneath no `Context`, and `Scoped` beneath
		// its own. A body per answer would double with each such label a path around the cycle can declare, so `Home`'s
		// and `Plain`'s functions take `context` optionally, as today's do, and each call passes its own declaration or
		// `nil`. `Home` built as `home` and as `homeBuilder` lay out alike, so they share one function.
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
		        func __safeDI_home(context: Context?) -> Home {
		            let plainBuilder = Instantiator<Plain> {
		                __safeDI_plainBuilder(context: context)
		            }
		            let scopedBuilder = Instantiator<Scoped>(__safeDI_scopedBuilder)
		            return Home(context: context, plainBuilder: plainBuilder, scopedBuilder: scopedBuilder)
		        }
		        func __safeDI_plainBuilder(context: Context?) -> Plain {
		            let homeBuilder = Instantiator<Home> {
		                __safeDI_home(context: context)
		            }
		            return Plain(homeBuilder: homeBuilder)
		        }
		        func __safeDI_scopedBuilder() -> Scoped {
		            let context = Context()
		            let homeBuilder = Instantiator<Home> {
		                __safeDI_home(context: context)
		            }
		            return Scoped(context: context, homeBuilder: homeBuilder)
		        }
		        let home: Home = __safeDI_home(context: nil)
		        self.init(home: home)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilToOptionalParameter_whenNearestDeclarationOfLabelIsOfAnotherForm() async throws {
		// `Detail` receives `mark: Stamp?` only if available, so its function takes `mark` optionally, as `Flow`, another
		// scope of the cycle, declares it. `Flow` forwards `mark: Mark?`: hiding is by label, so the call beneath `Flow`
		// passes what its nearest declaration of `mark` provides of `Stamp?`, which is nothing, and passes `nil`, as today's
		// tree does.
		let codes = try await planCodes(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let screenBuilder: Instantiator<Screen>
		    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
		}

		@Instantiable public final class Screen: Instantiable {
		    @Instantiated let flowBuilder: Instantiator<Flow>
		    public init(flowBuilder: Instantiator<Flow>) { self.flowBuilder = flowBuilder }
		}

		@Instantiable public final class Flow: Instantiable {
		    @Forwarded let mark: Mark?
		    @Instantiated let detailBuilder: Instantiator<Detail>
		    public init(mark: Mark?, detailBuilder: Instantiator<Detail>) { self.mark = mark; self.detailBuilder = detailBuilder }
		}

		@Instantiable public final class Detail: Instantiable {
		    @Received(onlyIfAvailable: true) let mark: Stamp?
		    @Instantiated let screenBuilder: Instantiator<Screen>
		    public init(mark: Stamp?, screenBuilder: Instantiator<Screen>) { self.mark = mark; self.screenBuilder = screenBuilder }
		}

		public final class Mark {}

		public final class Stamp {}
		""")

		#expect(codes == ["Root": """
		extension Root {
		    public convenience init() {
		        func __safeDI_screenBuilder() -> Screen {
		            let flowBuilder = Instantiator<Flow> {
		                __safeDI_flowBuilder(mark: $0)
		            }
		            return Screen(flowBuilder: flowBuilder)
		        }
		        func __safeDI_flowBuilder(mark: Mark?) -> Flow {
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(mark: nil)
		            }
		            return Flow(mark: mark, detailBuilder: detailBuilder)
		        }
		        func __safeDI_detailBuilder(mark: Stamp?) -> Detail {
		            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		            return Detail(mark: mark, screenBuilder: screenBuilder)
		        }
		        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		        self.init(screenBuilder: screenBuilder)
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
	mutating func generate_declaresParameterEscaping_whenBodyOnlyPassesOnTypealiasedClosureItsTreeTakesEscaping() async throws {
		// `A` only passes `callback` on to `B`, whose initializer takes it `@escaping`: SafeDI cannot see that `Callback` is a
		// function type, so `A`'s function learns it from the tree it builds, which a call place of `B` stands for.
		let codes = try await planCodes(of: """
		public typealias Callback = () -> Void

		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let sessionBuilder: Instantiator<Session>
		    public init(sessionBuilder: Instantiator<Session>) { self.sessionBuilder = sessionBuilder }
		}

		@Instantiable public final class Session: Instantiable {
		    @Forwarded let callback: Callback
		    @Instantiated let aBuilder: Instantiator<A>
		    public init(callback: @escaping Callback, aBuilder: Instantiator<A>) { self.callback = callback; self.aBuilder = aBuilder }
		}

		@Instantiable public final class A: Instantiable {
		    @Instantiated let bBuilder: Instantiator<B>
		    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
		}

		@Instantiable public final class B: Instantiable {
		    @Received let callback: Callback
		    @Instantiated let aBuilder: Instantiator<A>
		    public init(callback: @escaping Callback, aBuilder: Instantiator<A>) { self.callback = callback; self.aBuilder = aBuilder }
		}
		""")

		#expect(codes == ["Root": """
		extension Root {
		    public convenience init() {
		        func __safeDI_aBuilder(callback: @escaping Callback) -> A {
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(callback: callback)
		            }
		            return A(bBuilder: bBuilder)
		        }
		        func __safeDI_bBuilder(callback: @escaping Callback) -> B {
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(callback: callback)
		            }
		            return B(callback: callback, aBuilder: aBuilder)
		        }
		        func __safeDI_sessionBuilder(callback: @escaping Callback) -> Session {
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(callback: callback)
		            }
		            return Session(callback: callback, aBuilder: aBuilder)
		        }
		        let sessionBuilder = Instantiator<Session> {
		            __safeDI_sessionBuilder(callback: $0)
		        }
		        self.init(sessionBuilder: sessionBuilder)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsRenameSourceFirst_whenCalledTreeRequiresRenameOnlyIfAvailable() async throws {
		// `Detail` requires `y`, which `Screen` renames from `x` only if available, so `x` is built before `screenBuilder`,
		// as today: `X` is passed `nil` for the builder it receives only if available, and `Screen` and `Detail` read `x`.
		let (codes, fixtures) = try await planCodesAndFixtures(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let x: X
		    @Instantiated let screenBuilder: Instantiator<Screen>
		    public init(x: X, screenBuilder: Instantiator<Screen>) { self.x = x; self.screenBuilder = screenBuilder }
		}

		@Instantiable public final class X: Instantiable {
		    @Received(onlyIfAvailable: true) let screenBuilder: Instantiator<Screen>?
		    public init(screenBuilder: Instantiator<Screen>?) { self.screenBuilder = screenBuilder }
		}

		@Instantiable public final class Screen: Instantiable {
		    @Received(fulfilledByDependencyNamed: "x", ofType: X.self, onlyIfAvailable: true) let y: X?
		    @Instantiated let nextBuilder: Instantiator<Next>
		    @Instantiated let detailBuilder: Instantiator<Detail>
		    public init(y: X?, nextBuilder: Instantiator<Next>, detailBuilder: Instantiator<Detail>) { self.y = y; self.nextBuilder = nextBuilder; self.detailBuilder = detailBuilder }
		}

		@Instantiable public final class Detail: Instantiable {
		    @Received let y: X?
		    public init(y: X?) { self.y = y }
		}

		@Instantiable public final class Next: Instantiable {
		    @Instantiated let screenBuilder: Instantiator<Screen>
		    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
		}
		""")

		#expect(codes == ["Root": """
		extension Root {
		    public convenience init() {
		        let x = X(screenBuilder: nil)
		        func __safeDI_screenBuilder() -> Screen {
		            #sourceLocation(file: "\(fixtures["Root.swift"])", line: 13)
		            let y: X? = x
		            #sourceLocation()
		            let nextBuilder = Instantiator<Next>(__safeDI_nextBuilder)
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(y: y)
		            }
		            return Screen(y: y, nextBuilder: nextBuilder, detailBuilder: detailBuilder)
		        }
		        func __safeDI_nextBuilder() -> Next {
		            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		            return Next(screenBuilder: screenBuilder)
		        }
		        func __safeDI_detailBuilder(y: X?) -> Detail {
		            Detail(y: y)
		        }
		        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		        self.init(x: x, screenBuilder: screenBuilder)
		    }
		}
		"""])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The code each root of `swiftFileContent` that reaches a cycle lays out of its plan, by root, `nil` where the type
	/// key keeps the path key's body.
	/// The code the type key lays out of each root's plan, compiled in place of the root's generated extension with the
	/// fixtures beside it, as every test's generated code is compiled.
	private mutating func planCodes(of swiftFileContent: String) async throws -> [String: String?] {
		try await planCodesAndFixtures(of: swiftFileContent).codes
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func planCodesAndFixtures(of swiftFileContent: String) async throws -> (codes: [String: String?], fixtures: FixturePaths) {
		let (stream, continuation) = AsyncStream.makeStream(of: (String, String?).self)
		let output = try await PlanCodeObservation.$observer.withValue(TaskLocalFunction { root, code in
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
