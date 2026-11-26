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

/// Whether the scopes a root reaches let the capture walk run (`DependencyTreeGenerator.treeMayCaptureNonSendableWrapper(rootedAt:)`),
/// read before any tree is built, beside whether today's walk finds a capture.
struct SafeDIToolSendableCaptureGateTests: ~Copyable {
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
	mutating func generate_letsCaptureWalkRun_whenRootsTreeHoldsCapture() async throws {
		// `Settings` is built in the `@Sendable` function of `settingsBuilder` and receives `childBuilder`, an
		// `Instantiator` `Root` declares outside it: today's walk finds the capture, so the gate must let it run.
		let (gates, error) = await gates(of:
			"""
			@Instantiable(isRoot: true) public final class Root: Instantiable {
			    @Instantiated let childBuilder: Instantiator<Child>
			    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
			    public init(childBuilder: Instantiator<Child>, settingsBuilder: SendableInstantiator<Settings>) { self.childBuilder = childBuilder; self.settingsBuilder = settingsBuilder }
			}

			@Instantiable public final class Settings: Instantiable {
			    @Received let childBuilder: Instantiator<Child>
			    public init(childBuilder: Instantiator<Child>) { self.childBuilder = childBuilder }
			}

			@Instantiable public final class Child: Instantiable {
			    public init() {}
			}
			""")

		#expect(error != nil)
		#expect(gates == [Gate(root: "Root", letsWalkRun: true, todaysWalkFindsCapture: true)])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsCaptureWalkBackForEachRoot_whenModuleNamesBothKindsOfWrapper() async throws {
		// The module names both kinds of wrapper, so its gate lets the walk run. `SendableRoot`'s scopes name only
		// `SendableInstantiator`s, and `MixedRoot`'s `Instantiator` is of a label no scope built in a `@Sendable` function
		// reads: neither root's tree can hold a capture.
		let (gates, error) = await gates(of:
			"""
			@Instantiable(isRoot: true) public final class SendableRoot: Instantiable {
			    @Instantiated let screenBuilder: SendableInstantiator<Screen>
			    public init(screenBuilder: SendableInstantiator<Screen>) { self.screenBuilder = screenBuilder }
			}

			@Instantiable(isRoot: true) public final class MixedRoot: Instantiable {
			    @Instantiated let screenBuilder: SendableInstantiator<Screen>
			    @Instantiated let childBuilder: Instantiator<Child>
			    public init(screenBuilder: SendableInstantiator<Screen>, childBuilder: Instantiator<Child>) { self.screenBuilder = screenBuilder; self.childBuilder = childBuilder }
			}

			@Instantiable public final class Screen: Instantiable {
			    @Instantiated let detailBuilder: SendableInstantiator<Screen>
			    public init(detailBuilder: SendableInstantiator<Screen>) { self.detailBuilder = detailBuilder }
			}

			@Instantiable public final class Child: Instantiable {
			    public init() {}
			}
			""")

		#expect(error == nil)
		#expect(gates == [
			Gate(root: "MixedRoot", letsWalkRun: false, todaysWalkFindsCapture: false),
			Gate(root: "SendableRoot", letsWalkRun: false, todaysWalkFindsCapture: false),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_letsCaptureWalkRun_whenSendableFunctionRenamesNonSendableWrapper() async throws {
		// `Settings`, built in the `@Sendable` function of `settingsBuilder`, renames `childBuilder`, an `Instantiator`
		// `Root` declares outside it: the alias reads the wrapper there, so the gate must let the walk run.
		let (gates, error) = await gates(of:
			"""
			@Instantiable(isRoot: true) public final class Root: Instantiable {
			    @Instantiated let childBuilder: Instantiator<Child>
			    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
			    public init(childBuilder: Instantiator<Child>, settingsBuilder: SendableInstantiator<Settings>) { self.childBuilder = childBuilder; self.settingsBuilder = settingsBuilder }
			}

			@Instantiable public final class Settings: Instantiable {
			    @Received(fulfilledByDependencyNamed: "childBuilder", ofType: Instantiator<Child>.self) let renamedChildBuilder: Instantiator<Child>
			    public init(renamedChildBuilder: Instantiator<Child>) { self.renamedChildBuilder = renamedChildBuilder }
			}

			@Instantiable public final class Child: Instantiable {
			    public init() {}
			}
			""")

		#expect(error != nil)
		#expect(gates == [Gate(root: "Root", letsWalkRun: true, todaysWalkFindsCapture: true)])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_holdsCaptureWalkBack_whenSendableFunctionReadsNoLabelOfNonSendableWrapper() async throws {
		// `Root` declares an `Instantiator` and builds `Settings` in a `@Sendable` function, but `Settings` forwards
		// `name` and receives only `theme`, a constant: no read inside the function names the wrapper's label.
		let (gates, error) = await gates(of:
			"""
			@Instantiable(isRoot: true) public final class Root: Instantiable {
			    @Instantiated let childBuilder: Instantiator<Child>
			    @Instantiated let theme: Theme
			    @Instantiated let settingsBuilder: SendableInstantiator<Settings>
			    public init(childBuilder: Instantiator<Child>, theme: Theme, settingsBuilder: SendableInstantiator<Settings>) { self.childBuilder = childBuilder; self.theme = theme; self.settingsBuilder = settingsBuilder }
			}

			@Instantiable public final class Settings: Instantiable {
			    @Forwarded let name: String
			    @Received let theme: Theme
			    public init(name: String, theme: Theme) { self.name = name; self.theme = theme }
			}

			@Instantiable public final class Theme: Instantiable, Sendable {
			    public init() {}
			}

			@Instantiable public final class Child: Instantiable {
			    public init() {}
			}
			""")

		#expect(error == nil)
		#expect(gates == [Gate(root: "Root", letsWalkRun: false, todaysWalkFindsCapture: false)])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_letsCaptureWalkRun_whenCycleOfSendableInstantiatorsReceivesInstanceOfRootsLazilyInstantiated() async throws {
		// The cycle plan review's capture graph: a plan of `A`'s body would take `theme` as the instance of `Root`'s
		// `LazilyInstantiated`, read inside `aBuilder`'s `@Sendable` function. Today's walk reports the capture, so the
		// gate must keep today's tree.
		let (gates, error) = await gates(of:
			"""
			@Instantiable(isRoot: true) public final class Root: Instantiable {
			    @Instantiated let theme: LazilyInstantiated<Theme>
			    @Instantiated let aBuilder: SendableInstantiator<A>
			    public init(theme: LazilyInstantiated<Theme>, aBuilder: SendableInstantiator<A>) { self.theme = theme; self.aBuilder = aBuilder }
			}

			@Instantiable public final class A: Instantiable {
			    @Received let theme: Theme
			    @Instantiated let bBuilder: SendableInstantiator<B>
			    public init(theme: Theme, bBuilder: SendableInstantiator<B>) { self.theme = theme; self.bBuilder = bBuilder }
			}

			@Instantiable public final class B: Instantiable {
			    @Instantiated let aBuilder: SendableInstantiator<A>
			    public init(aBuilder: SendableInstantiator<A>) { self.aBuilder = aBuilder }
			}

			@Instantiable public final class Theme: Instantiable {
			    public init() {}
			}
			""")

		#expect(error != nil)
		#expect(gates == [Gate(root: "Root", letsWalkRun: true, todaysWalkFindsCapture: true)])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_letsCaptureWalkRun_whenTypeBuiltAgainByCycleDeclaresLazilyInstantiatedItsSendableFunctionReads() async throws {
		// The review's second capture graph: the wrapper is declared in `A`, a body the cycle calls, not in the root's
		// body, so a walk of the root body's own tree would not see it. `B`, built in `A`'s `@Sendable` function,
		// receives its instance, and builds `A` again.
		let (gates, error) = await gates(of:
			"""
			@Instantiable(isRoot: true) public final class Root: Instantiable {
			    @Instantiated let aBuilder: Instantiator<A>
			    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
			}

			@Instantiable public final class A: Instantiable {
			    @Instantiated let theme: LazilyInstantiated<Theme>
			    @Instantiated let bBuilder: SendableInstantiator<B>
			    public init(theme: LazilyInstantiated<Theme>, bBuilder: SendableInstantiator<B>) { self.theme = theme; self.bBuilder = bBuilder }
			}

			@Instantiable public final class B: Instantiable {
			    @Received let theme: Theme
			    @Instantiated let aBuilder: Instantiator<A>
			    public init(theme: Theme, aBuilder: Instantiator<A>) { self.theme = theme; self.aBuilder = aBuilder }
			}

			@Instantiable public final class Theme: Instantiable {
			    public init() {}
			}
			""")

		#expect(error != nil)
		#expect(gates == [Gate(root: "Root", letsWalkRun: true, todaysWalkFindsCapture: true)])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private struct Gate: Equatable {
		let root: String
		let letsWalkRun: Bool
		let todaysWalkFindsCapture: Bool
	}

	/// What the gate says of each root of `swiftFileContent`, beside what today's walk finds, in root order, and the error
	/// the run throws, if any.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func gates(of swiftFileContent: String) async -> (gates: [Gate], error: (any Error)?) {
		let (stream, continuation) = AsyncStream.makeStream(of: Gate.self)
		var error: (any Error)?
		do {
			try await SendableCaptureGateObservation.$observer.withValue({ root, gateLetsWalkRun, todaysWalkFindsCapture in
				continuation.yield(Gate(root: root, letsWalkRun: gateLetsWalkRun, todaysWalkFindsCapture: todaysWalkFindsCapture))
			}) {
				_ = try await executeSafeDIToolTest(
					swiftFileContent: [swiftFileContent],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
		} catch let thrownError {
			error = thrownError
		}
		continuation.finish()
		var gates = [Gate]()
		for await gate in stream where !gates.contains(gate) {
			gates.append(gate)
		}
		return (gates, error)
	}
}
