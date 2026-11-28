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

/// What each place of a mock root's tree passes `nil`, beside what a body passes `nil` that is built from the scope's
/// copy with call places beneath the answers the place's path gives (`MockVariantBodyObservation`), and the bodies a mock
/// root's plan builds.
struct SafeDIToolMockVariantBodyTests: ~Copyable {
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
	mutating func mock_buildsBodyReadingMockParameter_whenTypeOnCycleReceivesValueMockTakes() async throws {
		// `Next` reads the `logger` `mock()` takes: a body built beneath no binding of the mock root would pass it `nil`.
		let bodies = try await bodies(of:
			"""
			@Instantiable(generateMock: true) public final class Screen: Instantiable {
			    @Received let logger: Logger
			    @Instantiated let nextBuilder: Instantiator<Next>
			    public init(logger: Logger, nextBuilder: Instantiator<Next>) { self.logger = logger; self.nextBuilder = nextBuilder }
			}

			public final class Logger {}

			@Instantiable public final class Next: Instantiable {
			    @Received(onlyIfAvailable: true) let logger: Logger?
			    @Instantiated let screenBuilder: Instantiator<Screen>
			    public init(logger: Logger?, screenBuilder: Instantiator<Screen>) { self.logger = logger; self.screenBuilder = screenBuilder }
			}
			""")

		#expect(bodies == [
			Bodies(place: "\"nextBuilder: Instantiator<Next>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"screenBuilder: Instantiator<Screen>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"nextBuilder: Instantiator<Next>\" called by \"nextBuilder: Instantiator<Next>\" in \"screenBuilder: Instantiator<Screen>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"screenBuilder: Instantiator<Screen>\" called by \"nextBuilder: Instantiator<Next>\" in \"screenBuilder: Instantiator<Screen>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsBodyReadingOverrideBesidePromotedForm_whenMockRootJoinsItsDeclarations() async throws {
		// `Detail` reads the override of `value: Draft?` the mock root binds beside the `value: Value` it promotes for `Next`:
		// the root joins its declarations to its bindings, so a body built beneath declarations that replace them reads `nil`.
		let bodies = try await bodies(of:
			"""
			@Instantiable(generateMock: true) public final class Screen: Instantiable {
			    @Instantiated let detail: Detail
			    @Instantiated let nextBuilder: Instantiator<Next>
			    public init(detail: Detail, nextBuilder: Instantiator<Next>) { self.detail = detail; self.nextBuilder = nextBuilder }
			}

			@Instantiable public final class Value: Instantiable { public init() {} }

			public final class Draft {}

			@Instantiable public final class Detail: Instantiable {
			    @Received(onlyIfAvailable: true) let value: Draft?
			    public init(value: Draft?) { self.value = value }
			}

			@Instantiable public final class Next: Instantiable {
			    @Received let value: Value
			    @Instantiated let otherBuilder: Instantiator<Other>
			    public init(value: Value, otherBuilder: Instantiator<Other>) { self.value = value; self.otherBuilder = otherBuilder }
			}

			@Instantiable public final class Other: Instantiable {
			    @Instantiated let nextBuilder: Instantiator<Next>
			    public init(nextBuilder: Instantiator<Next>) { self.nextBuilder = nextBuilder }
			}
			""")

		#expect(bodies == [
			Bodies(place: "\"detail: Detail\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"value: Value\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"nextBuilder: Instantiator<Next>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"otherBuilder: Instantiator<Other>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"nextBuilder: Instantiator<Next>\" called by \"nextBuilder: Instantiator<Next>\" in \"otherBuilder: Instantiator<Other>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"otherBuilder: Instantiator<Other>\" called by \"nextBuilder: Instantiator<Next>\" in \"otherBuilder: Instantiator<Other>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsBodyPassingNil_whenRequiredReceiveBeneathPinsReceiveWhereverItsTypeIsBuilt() async throws {
		// `Leaf`, beneath `Detail`, requires `value: Value`, so production passes `Detail` `nil` wherever it is built, the
		// place a cycle builds again included, while `Other` reads the override: the declarations a body is built beneath keep
		// what the mock root’s bindings pass `nil`.
		let bodies = try await bodies(of:
			"""
			@Instantiable(generateMock: true) public final class Screen: Instantiable {
			    @Instantiated let detail: Detail
			    @Instantiated let other: Other
			    @Instantiated let nextBuilder: Instantiator<Next>
			    public init(detail: Detail, other: Other, nextBuilder: Instantiator<Next>) { self.detail = detail; self.other = other; self.nextBuilder = nextBuilder }
			}

			@Instantiable public final class Value: Instantiable { public init() {} }

			public final class Draft {}

			@Instantiable public final class Detail: Instantiable {
			    @Received(onlyIfAvailable: true) let value: Draft?
			    @Instantiated let leaf: Leaf
			    public init(value: Draft?, leaf: Leaf) { self.value = value; self.leaf = leaf }
			}

			@Instantiable public final class Leaf: Instantiable {
			    @Received let value: Value
			    public init(value: Value) { self.value = value }
			}

			@Instantiable public final class Other: Instantiable {
			    @Received(onlyIfAvailable: true) let value: Draft?
			    public init(value: Draft?) { self.value = value }
			}

			@Instantiable public final class Next: Instantiable {
			    @Instantiated let screenBuilder: Instantiator<Screen>
			    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
			}
			""")

		#expect(bodies == [
			Bodies(place: "\"value: Value\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"detail: Detail\"", todaysUnavailableProperties: ["value: Draft?"], bodysUnavailableProperties: ["value: Draft?"]),
			Bodies(place: "\"other: Other\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"nextBuilder: Instantiator<Next>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"screenBuilder: Instantiator<Screen>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"detail: Detail\"", todaysUnavailableProperties: ["value: Draft?"], bodysUnavailableProperties: ["value: Draft?"]),
			Bodies(place: "\"other: Other\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"nextBuilder: Instantiator<Next>\" called by \"nextBuilder: Instantiator<Next>\" in \"screenBuilder: Instantiator<Screen>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"screenBuilder: Instantiator<Screen>\" called by \"nextBuilder: Instantiator<Next>\" in \"screenBuilder: Instantiator<Screen>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"detail: Detail\" called by \"nextBuilder: Instantiator<Next>\" in \"screenBuilder: Instantiator<Screen>\"", todaysUnavailableProperties: ["value: Draft?"], bodysUnavailableProperties: ["value: Draft?"]),
			Bodies(place: "\"other: Other\" called by \"nextBuilder: Instantiator<Next>\" in \"screenBuilder: Instantiator<Screen>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"leaf: Leaf\" called by \"nextBuilder: Instantiator<Next>\" in \"screenBuilder: Instantiator<Screen>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"leaf: Leaf\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"leaf: Leaf\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsBodyPassingNil_whenRequiredReceiveAbovePinsReceive() async throws {
		// `Next` requires `value: Value`, which pins the `value: Draft?` of the `Detail` it builds and of the `Other` its
		// `Screen` builds, at every lap of the cycle, while the mocked type’s own `Other` reads the override: each place
		// records its required receives.
		let bodies = try await bodies(of:
			"""
			@Instantiable(generateMock: true) public final class Screen: Instantiable {
			    @Instantiated let other: Other
			    @Instantiated let nextBuilder: Instantiator<Next>
			    public init(other: Other, nextBuilder: Instantiator<Next>) { self.other = other; self.nextBuilder = nextBuilder }
			}

			@Instantiable public final class Value: Instantiable { public init() {} }

			public final class Draft {}

			@Instantiable public final class Next: Instantiable {
			    @Received let value: Value
			    @Instantiated let detail: Detail
			    @Instantiated let screenBuilder: Instantiator<Screen>
			    public init(value: Value, detail: Detail, screenBuilder: Instantiator<Screen>) { self.value = value; self.detail = detail; self.screenBuilder = screenBuilder }
			}

			@Instantiable public final class Detail: Instantiable {
			    @Received(onlyIfAvailable: true) let value: Draft?
			    public init(value: Draft?) { self.value = value }
			}

			@Instantiable public final class Other: Instantiable {
			    @Received(onlyIfAvailable: true) let value: Draft?
			    public init(value: Draft?) { self.value = value }
			}
			""")

		#expect(bodies == [
			Bodies(place: "\"other: Other\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"value: Value\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"nextBuilder: Instantiator<Next>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"detail: Detail\"", todaysUnavailableProperties: ["value: Draft?"], bodysUnavailableProperties: ["value: Draft?"]),
			Bodies(place: "\"screenBuilder: Instantiator<Screen>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"other: Other\"", todaysUnavailableProperties: ["value: Draft?"], bodysUnavailableProperties: ["value: Draft?"]),
			Bodies(place: "\"nextBuilder: Instantiator<Next>\" called by \"nextBuilder: Instantiator<Next>\" in \"screenBuilder: Instantiator<Screen>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"detail: Detail\" called by \"nextBuilder: Instantiator<Next>\" in \"screenBuilder: Instantiator<Screen>\"", todaysUnavailableProperties: ["value: Draft?"], bodysUnavailableProperties: ["value: Draft?"]),
			Bodies(place: "\"screenBuilder: Instantiator<Screen>\" called by \"nextBuilder: Instantiator<Next>\" in \"screenBuilder: Instantiator<Screen>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"other: Other\" called by \"nextBuilder: Instantiator<Next>\" in \"screenBuilder: Instantiator<Screen>\"", todaysUnavailableProperties: ["value: Draft?"], bodysUnavailableProperties: ["value: Draft?"]),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsBodyWithoutAnswer_whenCallPassesNilForLabelBuiltAfterIt() async throws {
		// `Logger` receives `t3Builder` only if available, so `Home` and `T0` each build `logger` after `t3Builder`, whose
		// function takes `logger` as a parameter of the cycle: each call passes `nil`, and every receive of `logger`
		// beneath the call is `nil`, as in a body no declaration answers `logger` for.
		let bodies = try await bodies(of:
			"""
			@Instantiable(generateMock: true) public final class Home: Instantiable {
			    @Instantiated let session: Session
			    @Instantiated let logger: Logger
			    @Instantiated let t3Builder: Instantiator<T3>
			    public init(session: Session, logger: Logger, t3Builder: Instantiator<T3>) { self.session = session; self.logger = logger; self.t3Builder = t3Builder }
			}

			@Instantiable public final class T3: Instantiable {
			    @Received(onlyIfAvailable: true) let session: Session?
			    @Received(onlyIfAvailable: true) let logger: Logger?
			    @Instantiated let t0Builder: Instantiator<T0>
			    @Instantiated let t4Builder: Instantiator<T4>
			    public init(session: Session?, logger: Logger?, t0Builder: Instantiator<T0>, t4Builder: Instantiator<T4>) { self.session = session; self.logger = logger; self.t0Builder = t0Builder; self.t4Builder = t4Builder }
			}

			@Instantiable public final class T0: Instantiable {
			    @Instantiated let session: Session
			    @Instantiated let logger: Logger
			    @Instantiated let t3Builder: Instantiator<T3>
			    public init(session: Session, logger: Logger, t3Builder: Instantiator<T3>) { self.session = session; self.logger = logger; self.t3Builder = t3Builder }
			}

			@Instantiable public final class T4: Instantiable {
			    @Instantiated let t3Builder: Instantiator<T3>
			    public init(t3Builder: Instantiator<T3>) { self.t3Builder = t3Builder }
			}

			@Instantiable public final class Session: Instantiable { public init() {} }

			@Instantiable public final class Logger: Instantiable {
			    @Received(onlyIfAvailable: true) let t3Builder: Instantiator<T3>?
			    public init(t3Builder: Instantiator<T3>?) { self.t3Builder = t3Builder }
			}
			""")

		#expect(bodies == [
			Bodies(place: "\"session: Session\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"t3Builder: Instantiator<T3>\"", todaysUnavailableProperties: ["logger: Logger?"], bodysUnavailableProperties: ["logger: Logger?"]),
			Bodies(place: "\"logger: Logger\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"t0Builder: Instantiator<T0>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"t4Builder: Instantiator<T4>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"t3Builder: Instantiator<T3>\" called by \"t3Builder: Instantiator<T3>\" in \"t4Builder: Instantiator<T4>\"", todaysUnavailableProperties: ["logger: Logger?"], bodysUnavailableProperties: ["logger: Logger?"]),
			Bodies(place: "\"t0Builder: Instantiator<T0>\" called by \"t3Builder: Instantiator<T3>\" in \"t4Builder: Instantiator<T4>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"t4Builder: Instantiator<T4>\" called by \"t3Builder: Instantiator<T3>\" in \"t4Builder: Instantiator<T4>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"session: Session\" called by \"t3Builder: Instantiator<T3>\" in \"t4Builder: Instantiator<T4>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"logger: Logger\" called by \"t3Builder: Instantiator<T3>\" in \"t4Builder: Instantiator<T4>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"session: Session\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"logger: Logger\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsBodyOfPromotedTreeBeneathDeclarationsMockedTypePinsNothingIn_whenMockedTypeRequiresLabel() async throws {
		// The mocked type requires `value: Value`, which pins its own `Detail`, but not the `Detail` of the `Feed` it promotes,
		// whose tree production builds above it: a promoted tree’s bodies are built beneath the bindings alone.
		let bodies = try await bodies(of:
			"""
			@Instantiable(generateMock: true) public final class Screen: Instantiable {
			    @Received let value: Value
			    @Received let feed: Feed
			    @Instantiated let detail: Detail
			    public init(value: Value, feed: Feed, detail: Detail) { self.value = value; self.feed = feed; self.detail = detail }
			}

			@Instantiable public final class Value: Instantiable { public init() {} }

			public final class Draft {}

			@Instantiable public final class Detail: Instantiable {
			    @Received(onlyIfAvailable: true) let value: Draft?
			    public init(value: Draft?) { self.value = value }
			}

			@Instantiable public final class Feed: Instantiable {
			    @Instantiated let detail: Detail
			    @Instantiated let nextBuilder: Instantiator<Next>
			    public init(detail: Detail, nextBuilder: Instantiator<Next>) { self.detail = detail; self.nextBuilder = nextBuilder }
			}

			@Instantiable public final class Next: Instantiable {
			    @Instantiated let feedBuilder: Instantiator<Feed>
			    public init(feedBuilder: Instantiator<Feed>) { self.feedBuilder = feedBuilder }
			}
			""")

		#expect(bodies == [
			Bodies(place: "\"detail: Detail\"", todaysUnavailableProperties: ["value: Draft?"], bodysUnavailableProperties: ["value: Draft?"]),
			Bodies(place: "\"value: Value\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"feed: Feed\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"detail: Detail\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"nextBuilder: Instantiator<Next>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"feedBuilder: Instantiator<Feed>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"detail: Detail\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"nextBuilder: Instantiator<Next>\" called by \"nextBuilder: Instantiator<Next>\" in \"feedBuilder: Instantiator<Feed>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"feedBuilder: Instantiator<Feed>\" called by \"nextBuilder: Instantiator<Next>\" in \"feedBuilder: Instantiator<Feed>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"detail: Detail\" called by \"nextBuilder: Instantiator<Next>\" in \"feedBuilder: Instantiator<Feed>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_comparesNoBody_whenTreeBuildsValueAndItsLazilyInstantiatedTwinAndOnlyAdmittedRootsAreCompared() async throws {
		// `A` and `C` build `t0: T0`, and `B` builds `t0: LazilyInstantiated<T0>`: twins, which a mock gives one slot. The
		// place `B` enters as the wrapper beneath the value's function takes a body the plan of a mock does not build, so
		// the checks every test runs, which compare only the roots the plan admits, leave the mock of `Hub` its tree.
		let bodies = try await bodies(comparingOnlyRootsThePlanAdmits: true, of:
			"""
			@Instantiable(generateMock: true) public final class Hub: Instantiable {
			    @Instantiated let aBuilder: Instantiator<A>
			    @Instantiated let bBuilder: Instantiator<B>
			    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) { self.aBuilder = aBuilder; self.bBuilder = bBuilder }
			}

			@Instantiable public final class A: Instantiable {
			    @Instantiated let t0: T0
			    @Instantiated let cBuilder: Instantiator<C>
			    public init(t0: T0, cBuilder: Instantiator<C>) { self.t0 = t0; self.cBuilder = cBuilder }
			}

			@Instantiable public final class B: Instantiable {
			    @Instantiated let t0: LazilyInstantiated<T0>
			    @Instantiated let cBuilder: Instantiator<C>
			    public init(t0: LazilyInstantiated<T0>, cBuilder: Instantiator<C>) { self.t0 = t0; self.cBuilder = cBuilder }
			}

			@Instantiable public final class C: Instantiable {
			    @Instantiated let t0: T0
			    public init(t0: T0) { self.t0 = t0 }
			}

			@Instantiable public final class T0: Instantiable {
			    @Instantiated let aBuilder: Instantiator<A>
			    @Instantiated let bBuilder: Instantiator<B>
			    @Instantiated let again: Instantiator<A>
			    @Instantiated let other: Instantiator<B>
			    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>, again: Instantiator<A>, other: Instantiator<B>) {
			        self.aBuilder = aBuilder; self.bBuilder = bBuilder; self.again = again; self.other = other
			    }
			}
			""")

		#expect(bodies == [])
	}

	// MARK: Private

	private struct Bodies: Equatable {
		let place: String
		let todaysUnavailableProperties: [String]
		let bodysUnavailableProperties: [String]
	}

	private var filesToDelete: [URL]

	/// Each comparison the tool hands on while it generates from `swiftFileContent`, in the order handed on.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func bodies(comparingOnlyRootsThePlanAdmits: Bool = false, of swiftFileContent: String) async throws -> [Bodies] {
		let (stream, continuation) = AsyncStream.makeStream(of: Bodies.self)
		// A test that observes a comparison compares every root; one that asks compares as the checks every test runs do.
		try await RootTreeChoiceObservation.$comparesOnlyRootsThePlanAdmits.withValue(comparingOnlyRootsThePlanAdmits) {
			try await MockVariantBodyObservation.$observer.withValue({ _, place, todaysUnavailableProperties, bodysUnavailableProperties in
				continuation.yield(Bodies(place: place, todaysUnavailableProperties: todaysUnavailableProperties, bodysUnavailableProperties: bodysUnavailableProperties))
			}) {
				_ = try await executeSafeDIToolTest(
					swiftFileContent: [swiftFileContent],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
		}
		continuation.finish()
		var bodies = [Bodies]()
		for await body in stream {
			bodies.append(body)
		}
		return bodies
	}
}
