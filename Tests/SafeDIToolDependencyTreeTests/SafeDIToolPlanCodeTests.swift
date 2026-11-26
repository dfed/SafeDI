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
		// functions take what their trees read from above, `clock`, and capture nothing.
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
		        func __safeDI_screenBuilder(clock: Clock) -> Screen {
		            let nextBuilder = Instantiator<Next> {
		                __safeDI_nextBuilder(clock: clock)
		            }
		            return Screen(clock: clock, nextBuilder: nextBuilder)
		        }
		        func __safeDI_nextBuilder(clock: Clock) -> Next {
		            let screenBuilder = Instantiator<Screen> {
		                __safeDI_screenBuilder(clock: clock)
		            }
		            return Next(screenBuilder: screenBuilder)
		        }
		        func __safeDI_shell() -> Shell {
		            let screenBuilder = Instantiator<Screen> {
		                __safeDI_screenBuilder(clock: clock)
		            }
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

	// MARK: Private

	private var filesToDelete: [URL]

	/// The code each root of `swiftFileContent` that reaches a cycle lays out of its plan, by root, `nil` where the type
	/// key keeps the path key's body.
	private mutating func planCodes(of swiftFileContent: String) async throws -> [String: String?] {
		let (stream, continuation) = AsyncStream.makeStream(of: (String, String?).self)
		try await PlanCodeObservation.$observer.withValue({ root, code in
			continuation.yield((root, code))
		}) {
			_ = try await executeSafeDIToolTest(
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
		return codes
	}
}
