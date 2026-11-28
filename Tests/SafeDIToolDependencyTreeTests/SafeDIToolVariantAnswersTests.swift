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

/// The judgements a body needs beyond the nearest declaration of each label (`VariantAnswers`): the order the scope that
/// makes a call builds its children in, whether its function is `@Sendable`, and which function a call of a twin value
/// runs.
struct SafeDIToolVariantAnswersTests: ~Copyable {
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
	mutating func generate_buildsBodyAnsweringSiblingBuiltAfterCallNil_whenScopesBuildSiblingsInOtherOrders() async throws {
		// `P1` and `P2` each build `cBuilder` and `x`, which receive each other only if available, so each builds first
		// the one it declares first. `P1` builds `x` before `cBuilder`, so `C` reads `P1`'s `x`; `P2` builds it after, so
		// `C` reads `nil` there whatever declares `x`: two bodies of `C`, one of them answering `x` with `nil`.
		let plans = try await plans(of:
			"""
			@Instantiable(isRoot: true) public final class Root: Instantiable {
			    @Instantiated let p1: P1
			    @Instantiated let p2: P2
			    public init(p1: P1, p2: P2) { self.p1 = p1; self.p2 = p2 }
			}

			@Instantiable public final class P1: Instantiable {
			    @Instantiated let cBuilder: Instantiator<C>
			    @Instantiated let x: X
			    public init(cBuilder: Instantiator<C>, x: X) { self.cBuilder = cBuilder; self.x = x }
			}

			@Instantiable public final class P2: Instantiable {
			    @Instantiated let x: X
			    @Instantiated let cBuilder: Instantiator<C>
			    public init(x: X, cBuilder: Instantiator<C>) { self.x = x; self.cBuilder = cBuilder }
			}

			@Instantiable public final class X: Instantiable {
			    @Received(onlyIfAvailable: true) let cBuilder: Instantiator<C>?
			    public init(cBuilder: Instantiator<C>?) { self.cBuilder = cBuilder }
			}

			@Instantiable public final class C: Instantiable {
			    @Received(onlyIfAvailable: true) let x: X?
			    @Instantiated let dBuilder: Instantiator<D>
			    public init(x: X?, dBuilder: Instantiator<D>) { self.x = x; self.dBuilder = dBuilder }
			}

			@Instantiable public final class D: Instantiable {
			    @Instantiated let cBuilder: Instantiator<C>
			    public init(cBuilder: Instantiator<C>) { self.cBuilder = cBuilder }
			}
			""")

		#expect(plans == [
			Plan(
				root: "Root",
				bodiesOfPlan: [
					"C as cBuilder: Instantiator<C> [cBuilder = cBuilder: Instantiator<C>, being built] [x = nil]",
					"C as cBuilder: Instantiator<C> [cBuilder = cBuilder: Instantiator<C>, being built] [x = x: X]",
					"D as dBuilder: Instantiator<D> [dBuilder = dBuilder: Instantiator<D>, being built] [x = x: X]",
					"D as dBuilder: Instantiator<D> [dBuilder = dBuilder: Instantiator<D>, being built] [x = nil]",
				],
				todaysBodiesPlanLacks: [],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_marksBodySendable_whenOneCallOfItIsMadeInsideSendableFunction() async throws {
		// `A` is built in the `@Sendable` function of a `SendableInstantiator` and `B` in a plain one; each builds
		// `cBuilder`, on a cycle through `D`. As today's tree writes one `@Sendable` function for both, the plan builds one
		// body of `C`, `@Sendable` since `A`'s call of it is made inside a `@Sendable` function, and one of `D`, which that
		// body calls.
		let plans = try await plans(of:
			"""
			@Instantiable(isRoot: true) public final class Root: Instantiable {
			    @Instantiated let aBuilder: SendableInstantiator<A>
			    @Instantiated let bBuilder: Instantiator<B>
			    public init(aBuilder: SendableInstantiator<A>, bBuilder: Instantiator<B>) { self.aBuilder = aBuilder; self.bBuilder = bBuilder }
			}

			@Instantiable public final class A: Instantiable {
			    @Instantiated let cBuilder: Instantiator<C>
			    public init(cBuilder: Instantiator<C>) { self.cBuilder = cBuilder }
			}

			@Instantiable public final class B: Instantiable {
			    @Instantiated let cBuilder: Instantiator<C>
			    public init(cBuilder: Instantiator<C>) { self.cBuilder = cBuilder }
			}

			@Instantiable public final class C: Instantiable {
			    @Instantiated let dBuilder: Instantiator<D>
			    public init(dBuilder: Instantiator<D>) { self.dBuilder = dBuilder }
			}

			@Instantiable public final class D: Instantiable {
			    @Instantiated let cBuilder: Instantiator<C>
			    public init(cBuilder: Instantiator<C>) { self.cBuilder = cBuilder }
			}
			""")

		#expect(plans == [
			Plan(
				root: "Root",
				bodiesOfPlan: [
					"C as cBuilder: Instantiator<C> [cBuilder = cBuilder: Instantiator<C>, being built] [@Sendable]",
					"D as dBuilder: Instantiator<D> [dBuilder = dBuilder: Instantiator<D>, being built] [@Sendable]",
				],
				todaysBodiesPlanLacks: [],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsFunctionOfTwinPlanNamesAndPlanNamesNoTwins_whenConstantTwinIsOffCycleOfLazyTwin() async throws {
		// `Root` builds `home: Home` and `Panel` builds `home: LazilyInstantiated<Home>`: one identity, so the order shadow
		// names them twins. The plan's twins are declarations of one component, and `Root`'s constant is off the cycle
		// `Panel`'s wrapper is on, so the plan names none. `Panel`'s call of the value runs the function of `Root`'s
		// constant, the twin its path is building, as the plan's call does.
		var observations = [TwinObservation]()
		let (stream, continuation) = AsyncStream.makeStream(of: TwinObservation.self)
		try await TwinIdentityObservation.$observer.withValue(TaskLocalFunction { root, shadowsTwinValues, plansTwinValues, callsOfOtherFunction in
			continuation.yield(TwinObservation(root: root, shadowsTwinValues: shadowsTwinValues, plansTwinValues: plansTwinValues, callsOfOtherFunction: callsOfOtherFunction))
		}) {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let home: Home
					    public init(home: Home) { self.home = home }
					}

					@Instantiable public final class Home: Instantiable {
					    @Instantiated let panelBuilder: Instantiator<Panel>
					    public init(panelBuilder: Instantiator<Panel>) { self.panelBuilder = panelBuilder }
					}

					@Instantiable public final class Panel: Instantiable {
					    @Instantiated let home: LazilyInstantiated<Home>
					    public init(home: LazilyInstantiated<Home>) { self.home = home }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		for await observation in stream {
			observations.append(observation)
		}

		#expect(observations == [
			TwinObservation(root: "Root", shadowsTwinValues: ["Home as home: Home"], plansTwinValues: [], callsOfOtherFunction: []),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsBodyAnsweringLoopMemberBuiltAfterCall_whenFunctionOfLoopMemberRebindsIt() async throws {
		// `Flow` builds `screenBuilder` and `peerBuilder`, a loop of builders: `Screen` receives `peerBuilder` only if
		// available and `Peer` requires `screenBuilder`. `Flow` builds `screenBuilder` first, and `Screen`’s function makes
		// `peerBuilder` again at its top, so `Screen` reads it though `Flow` builds it after the call (base corpus seeds
		// 575 and 2103).
		let plans = try await plans(of:
			"""
			@Instantiable(isRoot: true) public final class Root: Instantiable {
			    @Instantiated let flowBuilder: Instantiator<Flow>
			    public init(flowBuilder: Instantiator<Flow>) { self.flowBuilder = flowBuilder }
			}

			@Instantiable public final class Screen: Instantiable {
			    @Received(onlyIfAvailable: true) let peerBuilder: Instantiator<Peer>?
			    @Instantiated let flowBuilder: Instantiator<Flow>
			    public init(peerBuilder: Instantiator<Peer>?, flowBuilder: Instantiator<Flow>) { self.peerBuilder = peerBuilder; self.flowBuilder = flowBuilder }
			}

			@Instantiable public final class Flow: Instantiable {
			    @Instantiated let screenBuilder: Instantiator<Screen>
			    @Instantiated let peerBuilder: Instantiator<Peer>
			    public init(screenBuilder: Instantiator<Screen>, peerBuilder: Instantiator<Peer>) { self.screenBuilder = screenBuilder; self.peerBuilder = peerBuilder }
			}

			@Instantiable public final class Peer: Instantiable {
			    @Received let screenBuilder: Instantiator<Screen>
			    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
			}
			""")

		#expect(plans == [
			Plan(
				root: "Root",
				bodiesOfPlan: [
					"Flow as flowBuilder: Instantiator<Flow> [flowBuilder = flowBuilder: Instantiator<Flow>, being built]",
					"Screen as screenBuilder: Instantiator<Screen> [peerBuilder = peerBuilder: Instantiator<Peer>?, optional] [screenBuilder = screenBuilder: Instantiator<Screen>, being built]",
				],
				todaysBodiesPlanLacks: [],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsBodyAnsweringLoopMemberBuiltAfterCall_whenFunctionOfLoopMemberTakesItAsParameter() async throws {
		// As above, but `Root` builds `screenBuilder` and `peerBuilder` too, so the cycle closes on `Screen`’s function, which
		// takes `peerBuilder` as a parameter: each scope that declares the loop calls it through a function that makes
		// `peerBuilder` again and passes it, so `Screen` reads it at every call.
		let plans = try await plans(of:
			"""
			@Instantiable(isRoot: true) public final class Root: Instantiable {
			    @Instantiated let screenBuilder: Instantiator<Screen>
			    @Instantiated let peerBuilder: Instantiator<Peer>
			    public init(screenBuilder: Instantiator<Screen>, peerBuilder: Instantiator<Peer>) { self.screenBuilder = screenBuilder; self.peerBuilder = peerBuilder }
			}

			@Instantiable public final class Screen: Instantiable {
			    @Received(onlyIfAvailable: true) let peerBuilder: Instantiator<Peer>?
			    @Instantiated let flowBuilder: Instantiator<Flow>
			    public init(peerBuilder: Instantiator<Peer>?, flowBuilder: Instantiator<Flow>) { self.peerBuilder = peerBuilder; self.flowBuilder = flowBuilder }
			}

			@Instantiable public final class Flow: Instantiable {
			    @Instantiated let screenBuilder: Instantiator<Screen>
			    @Instantiated let peerBuilder: Instantiator<Peer>
			    public init(screenBuilder: Instantiator<Screen>, peerBuilder: Instantiator<Peer>) { self.screenBuilder = screenBuilder; self.peerBuilder = peerBuilder }
			}

			@Instantiable public final class Peer: Instantiable {
			    @Received let screenBuilder: Instantiator<Screen>
			    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
			}
			""")

		#expect(plans == [
			Plan(
				root: "Root",
				bodiesOfPlan: [
					"Screen as screenBuilder: Instantiator<Screen> [peerBuilder = peerBuilder: Instantiator<Peer>?, optional] [screenBuilder = screenBuilder: Instantiator<Screen>, being built]",
					"Flow as flowBuilder: Instantiator<Flow> [flowBuilder = flowBuilder: Instantiator<Flow>, being built]",
				],
				todaysBodiesPlanLacks: [],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesLoopMemberMadeAgainAtCall_whenScopeBuildsItAfterCallOfLoopMate() async throws {
		// `Flow` builds `screenBuilder` before `peerBuilder`, its loop mate, which `Screen`’s body takes as a parameter:
		// `Flow`’s call cannot read a declaration it has not made, so it passes the wrapper made again.
		let calls = try await calls(of:
			"""
			@Instantiable(isRoot: true) public final class Root: Instantiable {
			    @Instantiated let flowBuilder: Instantiator<Flow>
			    public init(flowBuilder: Instantiator<Flow>) { self.flowBuilder = flowBuilder }
			}

			@Instantiable public final class Screen: Instantiable {
			    @Received(onlyIfAvailable: true) let peerBuilder: Instantiator<Peer>?
			    @Instantiated let flowBuilder: Instantiator<Flow>
			    public init(peerBuilder: Instantiator<Peer>?, flowBuilder: Instantiator<Flow>) { self.peerBuilder = peerBuilder; self.flowBuilder = flowBuilder }
			}

			@Instantiable public final class Flow: Instantiable {
			    @Instantiated let screenBuilder: Instantiator<Screen>
			    @Instantiated let peerBuilder: Instantiator<Peer>
			    public init(screenBuilder: Instantiator<Screen>, peerBuilder: Instantiator<Peer>) { self.screenBuilder = screenBuilder; self.peerBuilder = peerBuilder }
			}

			@Instantiable public final class Peer: Instantiable {
			    @Received let screenBuilder: Instantiator<Screen>
			    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
			}
			""")

		#expect(calls == [[
			"Root",
			"Root [4] at [0] calls [0] as flowBuilder: Instantiator<Flow> (flowBuilder: flowBuilder: Instantiator<Flow>, being built)",
			"\"flowBuilder: Instantiator<Flow>\" [0] at [0] calls [2] as screenBuilder: Instantiator<Screen> (screenBuilder: screenBuilder: Instantiator<Screen>, being built; peerBuilder: peerBuilder: Instantiator<Peer>, made again at the call)",
			"\"screenBuilder: Instantiator<Screen>\" [2] at [0] calls [0] as flowBuilder: Instantiator<Flow> (flowBuilder: flowBuilder: Instantiator<Flow>, being built)",
		]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesLoopMemberMadeAgainAtEachCall_whenCycleClosesOnFunctionOfLoopMate() async throws {
		// `Root` and `Flow` each build `screenBuilder` before `peerBuilder`: the root’s call and the call that closes the
		// cycle each pass the wrapper made again.
		let calls = try await calls(of:
			"""
			@Instantiable(isRoot: true) public final class Root: Instantiable {
			    @Instantiated let screenBuilder: Instantiator<Screen>
			    @Instantiated let peerBuilder: Instantiator<Peer>
			    public init(screenBuilder: Instantiator<Screen>, peerBuilder: Instantiator<Peer>) { self.screenBuilder = screenBuilder; self.peerBuilder = peerBuilder }
			}

			@Instantiable public final class Screen: Instantiable {
			    @Received(onlyIfAvailable: true) let peerBuilder: Instantiator<Peer>?
			    @Instantiated let flowBuilder: Instantiator<Flow>
			    public init(peerBuilder: Instantiator<Peer>?, flowBuilder: Instantiator<Flow>) { self.peerBuilder = peerBuilder; self.flowBuilder = flowBuilder }
			}

			@Instantiable public final class Flow: Instantiable {
			    @Instantiated let screenBuilder: Instantiator<Screen>
			    @Instantiated let peerBuilder: Instantiator<Peer>
			    public init(screenBuilder: Instantiator<Screen>, peerBuilder: Instantiator<Peer>) { self.screenBuilder = screenBuilder; self.peerBuilder = peerBuilder }
			}

			@Instantiable public final class Peer: Instantiable {
			    @Received let screenBuilder: Instantiator<Screen>
			    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
			}
			""")

		#expect(calls == [[
			"Root",
			"Root [4] at [0] calls [1] as screenBuilder: Instantiator<Screen> (screenBuilder: screenBuilder: Instantiator<Screen>, being built; peerBuilder: peerBuilder: Instantiator<Peer>, made again at the call)",
			"\"screenBuilder: Instantiator<Screen>\" [1] at [0] calls [3] as flowBuilder: Instantiator<Flow> (flowBuilder: flowBuilder: Instantiator<Flow>, being built)",
			"\"flowBuilder: Instantiator<Flow>\" [3] at [0] calls [1] as screenBuilder: Instantiator<Screen> (screenBuilder: screenBuilder: Instantiator<Screen>, being built; peerBuilder: peerBuilder: Instantiator<Peer>, made again at the call)",
		]])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private struct Plan: Equatable {
		let root: String
		let bodiesOfPlan: [String]
		let todaysBodiesPlanLacks: [String]
	}

	private struct TwinObservation: Equatable {
		let root: String
		let shadowsTwinValues: [String]
		let plansTwinValues: [String]
		let callsOfOtherFunction: [String]
	}

	/// The bodies the plan builds for each root of `swiftFileContent`, and those today's places take that it lacks.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func plans(of swiftFileContent: String) async throws -> [Plan] {
		let (stream, continuation) = AsyncStream.makeStream(of: Plan.self)
		try await PlanBodiesObservation.$observer.withValue(TaskLocalFunction { root, bodiesOfPlan, todaysBodiesPlanLacks, _ in
			continuation.yield(Plan(root: root, bodiesOfPlan: bodiesOfPlan, todaysBodiesPlanLacks: todaysBodiesPlanLacks))
		}) {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: [swiftFileContent],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var plans = [Plan]()
		for await plan in stream where !plans.contains(plan) {
			plans.append(plan)
		}
		return plans
	}

	/// The calls each body of the plan of each root of `swiftFileContent` makes: the root, then a line per call.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func calls(of swiftFileContent: String) async throws -> [[String]] {
		let (stream, continuation) = AsyncStream.makeStream(of: [String].self)
		try await PlanCallsObservation.$observer.withValue(TaskLocalFunction { root, calls in
			continuation.yield([root] + calls)
		}) {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: [swiftFileContent],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var calls = [[String]]()
		for await call in stream where !calls.contains(call) {
			calls.append(call)
		}
		return calls
	}
}
