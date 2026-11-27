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

/// The shapes the capture check's fold over the per-type facts must judge as the walk of each chain judges them today
/// (`ScopeGenerator.nonSendableWrapperCaptures`): one declaration's `@Sendable` builder function reached from parents
/// that each declare the wrapper it captures, which are two bodies and two errors; a type built inside a `@Sendable`
/// function at one place and outside every one at another, which only the first place reports; and a receive only if
/// available of a sibling built after the receiver's type, which is passed `nil` and captures nothing.
struct SafeDIToolSendableCaptureShapeTests: ~Copyable {
	// MARK: Initialization

	init() throws {
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
	mutating func run_reportsEachParentsDeclaration_whenParentsOfOneSendableBuilderEachDeclareWrapperItCaptures() async {
		// `ScreenA` and `ScreenB` declare one `settingsBuilder`, whose function captures each parent's own `childBuilder`:
		// the function is two bodies, one per declaration it captures, so each is reported along its own chain.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `childBuilder: Instantiator<Child>` cannot be received inside a `@Sendable` function in chain: Root -> ScreenA -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `ScreenA` in a `@Sendable` function, which cannot capture `childBuilder: Instantiator<Child>` on `ScreenA`, because `Instantiator<Child>` is not `Sendable`. Declare `childBuilder` on `ScreenA` and `ScreenB`, and this property, as `SendableInstantiator<Child>` to fix. `SendableInstantiator<Child>` builds `Child` in a `@Sendable` function, so what the tree of `Child` receives from outside that function must be `Sendable` too.
				\(fixtures["ScreenA.swift"]):7:5: note: `childBuilder: Instantiator<Child>` is declared here
				\(fixtures["Settings.swift"]):7:5: error: @Received property `childBuilder: Instantiator<Child>` cannot be received inside a `@Sendable` function in chain: Root -> ScreenB -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `ScreenB` in a `@Sendable` function, which cannot capture `childBuilder: Instantiator<Child>` on `ScreenB`, because `Instantiator<Child>` is not `Sendable`. Declare `childBuilder` on `ScreenA` and `ScreenB`, and this property, as `SendableInstantiator<Child>` to fix. `SendableInstantiator<Child>` builds `Child` in a `@Sendable` function, so what the tree of `Child` receives from outside that function must be `Sendable` too.
				\(fixtures["ScreenB.swift"]):7:5: note: `childBuilder: Instantiator<Child>` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(screenA: ScreenA, screenB: ScreenB) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let screenA: ScreenA
					    @Instantiated let screenB: ScreenB
					}
					""",
					"""
					@Instantiable
					public final class ScreenA: Instantiable {
					    public init(childBuilder: Instantiator<Child>, settingsBuilder: SendableInstantiator<Settings>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let childBuilder: Instantiator<Child>
					    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
					}
					""",
					"""
					@Instantiable
					public final class ScreenB: Instantiable {
					    public init(childBuilder: Instantiator<Child>, settingsBuilder: SendableInstantiator<Settings>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let childBuilder: Instantiator<Child>
					    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
					}
					""",
					Self.child,
					Self.settings,
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_reportsOnlySendablePlace_whenTypeIsBuiltInsideSendableFunctionAtOnePlaceAndOutsideAtAnother() async {
		// `Settings` is built in a `@Sendable` function under `ScreenA` and in a plain one under `ScreenB`: the two places
		// are two families of one declaration's body, and only the `@Sendable` one captures `childBuilder`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Settings.swift"]):7:5: error: @Received property `childBuilder: Instantiator<Child>` cannot be received inside a `@Sendable` function in chain: Root -> ScreenA -> Settings. SafeDI builds `settingsBuilder: SendableInstantiator<Settings>` on `ScreenA` in a `@Sendable` function, which cannot capture `childBuilder: Instantiator<Child>` on `Root`, because `Instantiator<Child>` is not `Sendable`. Declare `childBuilder` on `Root`, and this property, as `SendableInstantiator<Child>` to fix. `SendableInstantiator<Child>` builds `Child` in a `@Sendable` function, so what the tree of `Child` receives from outside that function must be `Sendable` too.
				\(fixtures["Root.swift"]):7:5: note: `childBuilder: Instantiator<Child>` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(childBuilder: Instantiator<Child>, screenA: ScreenA, screenB: ScreenB) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let childBuilder: Instantiator<Child>
					    @Instantiated let screenA: ScreenA
					    @Instantiated let screenB: ScreenB
					}
					""",
					"""
					@Instantiable
					public final class ScreenA: Instantiable {
					    public init(settingsBuilder: SendableInstantiator<Settings>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
					}
					""",
					"""
					@Instantiable
					public final class ScreenB: Instantiable {
					    public init(settingsBuilder: Instantiator<Settings>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let settingsBuilder: Instantiator<Settings>
					}
					""",
					Self.child,
					Self.settings,
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_generatesCode_whenSendableBuilderReceivesOnlyIfAvailableWrapperOfSiblingBuiltAfterIt() async throws {
		// `childBuilder`'s tree requires `log`, whose tree requires `settingsBuilder`, so `settingsBuilder` is built first,
		// and its receive of `childBuilder` only if available is passed `nil`: the loop it would close holds a value, `log`,
		// so no rebinding hands it the wrapper, and its `@Sendable` function captures nothing.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(childBuilder: Instantiator<Child>, log: Log, settingsBuilder: SendableInstantiator<Settings>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let childBuilder: Instantiator<Child>
				    @Instantiated let log: Log
				    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(log: Log) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let log: Log
				}
				""",
				"""
				@Instantiable
				public final class Log: Instantiable {
				    public init(settingsBuilder: SendableInstantiator<Settings>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let settingsBuilder: SendableInstantiator<Settings>
				}
				""",
				"""
				@Instantiable
				public final class Settings: Instantiable {
				    public init(childBuilder: Instantiator<Child>?) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received(onlyIfAvailable: true) let childBuilder: Instantiator<Child>?
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        @Sendable nonisolated func __safeDI_settingsBuilder() -> Settings {
			            Settings(childBuilder: nil)
			        }
			        let settingsBuilder = SendableInstantiator<Settings>(__safeDI_settingsBuilder)
			        let log = Log(settingsBuilder: settingsBuilder)
			        func __safeDI_childBuilder() -> Child {
			            Child(log: log)
			        }
			        let childBuilder = Instantiator<Child>(__safeDI_childBuilder)
			        self.init(childBuilder: childBuilder, log: log, settingsBuilder: settingsBuilder)
			    }
			}
			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let child = """
	@Instantiable
	public final class Child: Instantiable {
	    public init() {}
	}
	"""

	private static let settings = """
	@Instantiable
	public final class Settings: Instantiable {
	    public init(childBuilder: Instantiator<Child>) {
	        fatalError("SafeDI doesn't inspect the initializer body")
	    }

	    @Received let childBuilder: Instantiator<Child>
	}
	"""
}
