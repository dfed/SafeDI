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

/// What each place of a production root's tree passes `nil`, beside what a body passes `nil` that is built from the
/// scope's copy with call places beneath the answers the place's path gives (`VariantBodyObservation`).
struct SafeDIToolVariantBodyTests: ~Copyable {
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
	mutating func generate_buildsBodyThatPassesNilWhereTodaysPlaceDoes_whenReceiveIsOfBuilderStillBeingBuilt() async throws {
		// `Detail` receives `detail` only if available while it is the `detail` being built, so today's place and
		// the body built from its answers both pass it `nil`; no other place is passed `nil` in either build. The places
		// of `screenBuilder`'s function are compared again with what the call in `nextBuilder` gives them.
		let bodies = try await bodies(of:
			"""
			@Instantiable(isRoot: true) public final class Root: Instantiable {
			    @Instantiated let logger: Logger
			    @Instantiated let screenBuilder: Instantiator<Screen>
			    public init(logger: Logger, screenBuilder: Instantiator<Screen>) { self.logger = logger; self.screenBuilder = screenBuilder }
			}

			@Instantiable public final class Logger: Instantiable {
			    public init() {}
			}

			@Instantiable public final class Screen: Instantiable {
			    @Received(onlyIfAvailable: true) let logger: Logger?
			    @Instantiated let detail: Detail
			    @Instantiated let nextBuilder: Instantiator<Next>
			    public init(logger: Logger?, detail: Detail, nextBuilder: Instantiator<Next>) { self.logger = logger; self.detail = detail; self.nextBuilder = nextBuilder }
			}

			@Instantiable public final class Detail: Instantiable {
			    @Received(onlyIfAvailable: true) let detail: Detail?
			    public init(detail: Detail?) { self.detail = detail }
			}

			@Instantiable public final class Next: Instantiable {
			    @Instantiated let screenBuilder: Instantiator<Screen>
			    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
			}
			""")

		#expect(bodies == [
			Bodies(place: "\"logger: Logger\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"screenBuilder: Instantiator<Screen>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"detail: Detail\"", todaysUnavailableProperties: ["detail: Detail?"], bodysUnavailableProperties: ["detail: Detail?"]),
			Bodies(place: "\"nextBuilder: Instantiator<Next>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"screenBuilder: Instantiator<Screen>\" called by \"screenBuilder: Instantiator<Screen>\" in \"nextBuilder: Instantiator<Next>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"detail: Detail\" called by \"screenBuilder: Instantiator<Screen>\" in \"nextBuilder: Instantiator<Next>\"", todaysUnavailableProperties: ["detail: Detail?"], bodysUnavailableProperties: ["detail: Detail?"]),
			Bodies(place: "\"nextBuilder: Instantiator<Next>\" called by \"screenBuilder: Instantiator<Screen>\" in \"nextBuilder: Instantiator<Next>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsOneBodyPerTypeOnCycle_whenEveryCallOfTypeIsAnsweredAlike() async throws {
		// `Screen` and `Next` open each other. The plan builds `Root`'s body, then one body for `screenBuilder` and one for
		// `nextBuilder`, since the call of `screenBuilder` inside `nextBuilder` is answered as `Root`'s call is: `logger`
		// by `Root`, and `screenBuilder` being built. Every place of today's tree takes one of them.
		var plans = [Plan]()
		let (stream, continuation) = AsyncStream.makeStream(of: Plan.self)
		try await PlanBodiesObservation.$observer.withValue(TaskLocalFunction { root, bodiesOfPlan, todaysBodiesPlanLacks, twinValues in
			continuation.yield(Plan(root: root, bodiesOfPlan: bodiesOfPlan, todaysBodiesPlanLacks: todaysBodiesPlanLacks, twinValues: twinValues))
		}) {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let logger: Logger
					    @Instantiated let screenBuilder: Instantiator<Screen>
					    public init(logger: Logger, screenBuilder: Instantiator<Screen>) { self.logger = logger; self.screenBuilder = screenBuilder }
					}

					@Instantiable public final class Logger: Instantiable { public init() {} }

					@Instantiable public final class Screen: Instantiable {
					    @Received let logger: Logger
					    @Instantiated let nextBuilder: Instantiator<Next>
					    public init(logger: Logger, nextBuilder: Instantiator<Next>) { self.logger = logger; self.nextBuilder = nextBuilder }
					}

					@Instantiable public final class Next: Instantiable {
					    @Instantiated let screenBuilder: Instantiator<Screen>
					    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		for await plan in stream where !plans.contains(plan) {
			plans.append(plan)
		}

		#expect(plans == [
			Plan(
				root: "Root",
				bodiesOfPlan: [
					"Screen as screenBuilder: Instantiator<Screen> [logger = logger: Logger] [screenBuilder = screenBuilder: Instantiator<Screen>, being built]",
					"Next as nextBuilder: Instantiator<Next> [logger = logger: Logger] [nextBuilder = nextBuilder: Instantiator<Next>, being built]",
				],
				todaysBodiesPlanLacks: [],
				twinValues: [],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_listsEachBodysCallsWithTheirAnswers_whenScreensOpenEachOtherBeneathTypeOnNoCycle() async throws {
		// `Shell` is on no cycle, so `Root`'s body builds it and holds one call, two scopes down, of `screenBuilder`.
		// `Screen` and `Next` open each other, so each of their bodies holds one call. `Screen`'s tree reads `logger`
		// through `Root`'s `LazilyInstantiated`, `clock` from `Root`, and `theme`, which nothing declares.
		var calls = [[String]]()
		let (stream, continuation) = AsyncStream.makeStream(of: [String].self)
		try await PlanCallsObservation.$observer.withValue(TaskLocalFunction { root, calls in
			continuation.yield([root] + calls)
		}) {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let logger: LazilyInstantiated<Logger>
					    @Instantiated let clock: Clock
					    @Instantiated let shell: Shell
					    public init(logger: LazilyInstantiated<Logger>, clock: Clock, shell: Shell) { self.logger = logger; self.clock = clock; self.shell = shell }
					}

					@Instantiable public final class Logger: Instantiable { public init() {} }

					@Instantiable public final class Clock: Instantiable { public init() {} }

					public final class Theme {}

					@Instantiable public final class Shell: Instantiable {
					    @Instantiated let screenBuilder: Instantiator<Screen>
					    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
					}

					@Instantiable public final class Screen: Instantiable {
					    @Received let logger: Logger
					    @Received let clock: Clock
					    @Received(onlyIfAvailable: true) let theme: Theme?
					    @Instantiated let nextBuilder: Instantiator<Next>
					    public init(logger: Logger, clock: Clock, theme: Theme?, nextBuilder: Instantiator<Next>) { self.logger = logger; self.clock = clock; self.theme = theme; self.nextBuilder = nextBuilder }
					}

					@Instantiable public final class Next: Instantiable {
					    @Instantiated let screenBuilder: Instantiator<Screen>
					    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		for await call in stream where !calls.contains(call) {
			calls.append(call)
		}

		// Each line: the calling body's generator and position, the call place's path among `propertiesToGenerate`, the
		// position of the body called, and that body's answers in the order its function takes them: the label it is built
		// as, then the labels in the order its tree first receives them.
		#expect(calls == [[
			"Root",
			"Root [5] at [2, 0] calls [3] as screenBuilder: Instantiator<Screen> (screenBuilder: screenBuilder: Instantiator<Screen>, being built; logger: instance of logger: LazilyInstantiated<Logger>; clock: clock: Clock; theme: nil)",
			"\"screenBuilder: Instantiator<Screen>\" [3] at [0] calls [4] as nextBuilder: Instantiator<Next> (nextBuilder: nextBuilder: Instantiator<Next>, being built; logger: instance of logger: LazilyInstantiated<Logger>; clock: clock: Clock; theme: nil)",
			"\"nextBuilder: Instantiator<Next>\" [4] at [0] calls [3] as screenBuilder: Instantiator<Screen> (screenBuilder: screenBuilder: Instantiator<Screen>, being built; logger: instance of logger: LazilyInstantiated<Logger>; clock: clock: Clock; theme: nil)",
		]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsFunctionOfTwinPathIsBuilding_whenLazilyInstantiatedDependencyClosesCycleOnConstant() async throws {
		// `Root` and `Detail` build `home: Home` and `Panel` builds `home: LazilyInstantiated<Home>`, twins: `Panel`'s
		// closes the cycle on the function of `Root`'s constant, the twin its path is building. The plan's call there is
		// of that property, beneath `Panel`'s declarations, as today's place for the call is: a second body of `Home`,
		// since the nearest declaration of `home` there is `Panel`'s. `Detail`'s call is answered as `Root`'s is.
		var plans = [Plan]()
		let (stream, continuation) = AsyncStream.makeStream(of: Plan.self)
		try await PlanBodiesObservation.$observer.withValue(TaskLocalFunction { root, bodiesOfPlan, todaysBodiesPlanLacks, twinValues in
			continuation.yield(Plan(root: root, bodiesOfPlan: bodiesOfPlan, todaysBodiesPlanLacks: todaysBodiesPlanLacks, twinValues: twinValues))
		}) {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let home: Home
					    public init(home: Home) { self.home = home }
					}

					@Instantiable public final class Home: Instantiable {
					    @Instantiated let detailBuilder: Instantiator<Detail>
					    public init(detailBuilder: Instantiator<Detail>) { self.detailBuilder = detailBuilder }
					}

					@Instantiable public final class Detail: Instantiable {
					    @Instantiated let panelBuilder: Instantiator<Panel>
					    @Instantiated let home: Home
					    public init(panelBuilder: Instantiator<Panel>, home: Home) { self.panelBuilder = panelBuilder; self.home = home }
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
		for await plan in stream {
			plans.append(plan)
		}
		#expect(plans == [
			Plan(
				root: "Root",
				bodiesOfPlan: [
					"Home as home: Home [home = home: Home, being built] [building home: Home]",
					"Detail as detailBuilder: Instantiator<Detail> [detailBuilder = detailBuilder: Instantiator<Detail>, being built] [building home: Home]",
					"Panel as panelBuilder: Instantiator<Panel> [panelBuilder = panelBuilder: Instantiator<Panel>, being built] [building home: Home]",
					"Home as home: Home [home = home: LazilyInstantiated<Home>, being built] [building home: Home]",
				],
				todaysBodiesPlanLacks: [],
				twinValues: ["Home as home: Home"],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsOneBodyPerScreen_whenScreensOpenEachOtherAtTwoSizes() async throws {
		// Each screen opens three others, so the paths through the screens grow with every screen added, and the type
		// key's views with them: 133 at eight screens and 1,918 at twelve (`SafeDIToolTypeKeyViewTests`). Every call of a
		// screen is answered alike, `service` and `context` by a declaration of the same property and its own builder
		// being built, so the plan builds one body per screen, and every place of today's tree takes one of them. Run
		// once by hand without the walk of today's places, sixteen screens gave 16 bodies and twenty gave 20; generating
		// today's tree for those takes minutes, so they are not sizes of this test.
		var counts = [Int]()
		for screenCount in [8, 12] {
			let roles = (0..<screenCount).map { ContextRole.allCases[$0 % ContextRole.allCases.count] }
			let targets = (0..<screenCount).map { screen in [1, 3, 7].map { (screen + $0) % screenCount }.sorted() }
			let (stream, continuation) = AsyncStream.makeStream(of: Plan.self)
			try await PlanBodiesObservation.$observer.withValue(TaskLocalFunction { root, bodiesOfPlan, todaysBodiesPlanLacks, twinValues in
				continuation.yield(Plan(root: root, bodiesOfPlan: bodiesOfPlan, todaysBodiesPlanLacks: todaysBodiesPlanLacks, twinValues: twinValues))
			}) {
				_ = try await executeSafeDIToolTest(
					swiftFileContent: Self.screensOpeningEachOther(roles: roles, targets: targets),
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
					// The code is what the type key's tests compare; this one counts the bodies of the plan.
					skipCompileVerification: true,
				)
			}
			continuation.finish()
			for await plan in stream {
				#expect(plan.todaysBodiesPlanLacks.isEmpty)
				counts.append(plan.bodiesOfPlan.count)
			}
		}
		#expect(counts == [8, 12])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsOneBodyPerTypeOnCycle_whenEachMemberDeclaresLabelHubReceivesOnlyIfAvailable() async throws {
		// A hub opens n members, each of which declares its own label and opens the hub again, and the hub's leaf receives
		// every member's label only if available. A path around the cycle can declare any subset of the labels, so a body
		// per set of answers would be 2^n hubs and n·2^(n-1) members. Today's tree writes one function per type, which takes
		// each label as an optional parameter, so the plan builds one body per type: n + 1.
		var counts = [Int]()
		for memberCount in [8, 16] {
			let (stream, continuation) = AsyncStream.makeStream(of: Plan.self)
			try await PlanBodiesObservation.$observer.withValue(TaskLocalFunction { root, bodiesOfPlan, todaysBodiesPlanLacks, twinValues in
				continuation.yield(Plan(root: root, bodiesOfPlan: bodiesOfPlan, todaysBodiesPlanLacks: todaysBodiesPlanLacks, twinValues: twinValues))
			}) {
				_ = try await executeSafeDIToolTest(
					swiftFileContent: Self.hubOpeningMembers(count: memberCount),
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
					// This test counts the bodies of the plan; the code is today's.
					skipCompileVerification: true,
				)
			}
			continuation.finish()
			for await plan in stream {
				#expect(plan.todaysBodiesPlanLacks.isEmpty)
				counts.append(plan.bodiesOfPlan.count)
			}
		}
		#expect(counts == [9, 17])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootPerPath_whenBodiesOfOneDeclarationPassTheirBound() async throws {
		// The hub's members declare their labels lazily, which a receive only if available reads through the wrapper's
		// instance, so no optional parameter takes them and the hub's bodies double with each member: 8 at three members,
		// which the plan builds, and 16 at four, past the bound, where the root keeps today's tree and builds no plan.
		var hubBodyCounts = [Int?]()
		for memberCount in [3, 4] {
			let (stream, continuation) = AsyncStream.makeStream(of: Plan.self)
			try await PlanBodiesObservation.$observer.withValue(TaskLocalFunction { root, bodiesOfPlan, todaysBodiesPlanLacks, twinValues in
				continuation.yield(Plan(root: root, bodiesOfPlan: bodiesOfPlan, todaysBodiesPlanLacks: todaysBodiesPlanLacks, twinValues: twinValues))
			}) {
				_ = try await executeSafeDIToolTest(
					swiftFileContent: Self.hubOpeningMembers(count: memberCount, declaringLabelsLazily: true),
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
					// This test counts the bodies of the plan; the code is today's.
					skipCompileVerification: true,
				)
			}
			continuation.finish()
			var hubBodyCount: Int?
			for await plan in stream {
				hubBodyCount = plan.bodiesOfPlan.count { $0.hasPrefix("Hub ") }
			}
			hubBodyCounts.append(hubBodyCount)
		}
		#expect(hubBodyCounts == [8, nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsBodyForEachPath_whenTypeReachedLaterBuildsTypeReachedEarlierAboveCycle() async throws {
		// The root reaches `Flow` before `Detail`, which builds `Flow` again beneath a forwarded `mark`: the plan walks the
		// path through `Detail` too, so `Screen`'s cycle gets a body that reads `Detail`'s `mark` beside the one that reads `nil`.
		let (stream, continuation) = AsyncStream.makeStream(of: Plan.self)
		try await PlanBodiesObservation.$observer.withValue({ root, bodiesOfPlan, todaysBodiesPlanLacks, twinValues in
			continuation.yield(Plan(root: root, bodiesOfPlan: bodiesOfPlan, todaysBodiesPlanLacks: todaysBodiesPlanLacks, twinValues: twinValues))
		}) {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let flow: Flow
					    @Instantiated let detailBuilder: Instantiator<Detail>
					    public init(flow: Flow, detailBuilder: Instantiator<Detail>) { self.flow = flow; self.detailBuilder = detailBuilder }
					}

					@Instantiable public final class Flow: Instantiable {
					    @Instantiated let screenBuilder: Instantiator<Screen>
					    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
					}

					@Instantiable public final class Screen: Instantiable {
					    @Received(onlyIfAvailable: true) let mark: Mark?
					    @Instantiated let nextScreenBuilder: Instantiator<Screen>
					    public init(mark: Mark?, nextScreenBuilder: Instantiator<Screen>) { self.mark = mark; self.nextScreenBuilder = nextScreenBuilder }
					}

					@Instantiable public final class Detail: Instantiable {
					    @Forwarded let mark: Mark
					    @Instantiated let flowBuilder: Instantiator<Flow>
					    public init(mark: Mark, flowBuilder: Instantiator<Flow>) { self.mark = mark; self.flowBuilder = flowBuilder }
					}

					public final class Mark {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var plans = [Plan]()
		for await plan in stream {
			plans.append(plan)
		}
		#expect(plans == [
			Plan(
				root: "Root",
				bodiesOfPlan: [
					"Screen as screenBuilder: Instantiator<Screen> [mark = mark: Mark] [screenBuilder = screenBuilder: Instantiator<Screen>, being built]",
					"Screen as screenBuilder: Instantiator<Screen> [mark = nil] [screenBuilder = screenBuilder: Instantiator<Screen>, being built]",
					"Screen as nextScreenBuilder: Instantiator<Screen> [mark = nil] [nextScreenBuilder = nextScreenBuilder: Instantiator<Screen>, being built]",
					"Screen as nextScreenBuilder: Instantiator<Screen> [mark = mark: Mark] [nextScreenBuilder = nextScreenBuilder: Instantiator<Screen>, being built]",
				],
				todaysBodiesPlanLacks: [],
				twinValues: [],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsPlan_whenBodyCalledBeneathOptionalParameterDeclaresLabelInAnotherForm() async throws {
		// `Flow` forwards `mark: Mark?` on the cycle, above `Detail`'s receive of `mark: Stamp?` only if available. Hiding is
		// by label, so `Detail` reads `Flow`'s declaration, which provides no `Stamp?`, and nothing above `Flow` answers a
		// read: neither `Screen` nor `Flow` is keyed by `mark`, and only `Detail` takes it, optionally.
		let (stream, continuation) = AsyncStream.makeStream(of: Plan.self)
		try await PlanBodiesObservation.$observer.withValue(TaskLocalFunction { root, bodiesOfPlan, todaysBodiesPlanLacks, twinValues in
			continuation.yield(Plan(root: root, bodiesOfPlan: bodiesOfPlan, todaysBodiesPlanLacks: todaysBodiesPlanLacks, twinValues: twinValues))
		}) {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
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
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var plans = [Plan]()
		for await plan in stream {
			plans.append(plan)
		}
		#expect(plans == [
			Plan(
				root: "Root",
				bodiesOfPlan: [
					"Screen as screenBuilder: Instantiator<Screen> [screenBuilder = screenBuilder: Instantiator<Screen>, being built]",
					"Flow as flowBuilder: Instantiator<Flow> [flowBuilder = flowBuilder: Instantiator<Flow>, being built]",
					"Detail as detailBuilder: Instantiator<Detail> [detailBuilder = detailBuilder: Instantiator<Detail>, being built] [mark = mark: Stamp?, optional]",
				],
				todaysBodiesPlanLacks: [],
				twinValues: [],
			),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesRenamedValueOptionally_whenAliasReceivesLabelOnlyIfAvailableThatCycleDeclares() async throws {
		// `Screen` renames `context: Context` only if available, and `Flow`, on its cycle, instantiates `context`: the root
		// opens `Screen` beneath no `Context`, and `Flow` beneath its own. `Screen`'s body takes `context` optionally, as
		// the value the alias reads, so both calls share it.
		let (stream, continuation) = AsyncStream.makeStream(of: Plan.self)
		try await PlanBodiesObservation.$observer.withValue(TaskLocalFunction { root, bodiesOfPlan, todaysBodiesPlanLacks, twinValues in
			continuation.yield(Plan(root: root, bodiesOfPlan: bodiesOfPlan, todaysBodiesPlanLacks: todaysBodiesPlanLacks, twinValues: twinValues))
		}) {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let screenBuilder: Instantiator<Screen>
					    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
					}

					@Instantiable public final class Screen: Instantiable {
					    @Received(fulfilledByDependencyNamed: "context", ofType: Context.self, onlyIfAvailable: true) let renamedContext: Context?
					    @Instantiated let flowBuilder: Instantiator<Flow>
					    public init(renamedContext: Context?, flowBuilder: Instantiator<Flow>) { self.renamedContext = renamedContext; self.flowBuilder = flowBuilder }
					}

					@Instantiable public final class Flow: Instantiable {
					    @Instantiated let context: Context
					    @Instantiated let screenBuilder: Instantiator<Screen>
					    public init(context: Context, screenBuilder: Instantiator<Screen>) { self.context = context; self.screenBuilder = screenBuilder }
					}

					@Instantiable public final class Context: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var plans = [Plan]()
		for await plan in stream {
			plans.append(plan)
		}
		#expect(plans == [
			Plan(
				root: "Root",
				bodiesOfPlan: [
					"Screen as screenBuilder: Instantiator<Screen> [context = context: Context?, optional] [screenBuilder = screenBuilder: Instantiator<Screen>, being built]",
					"Flow as flowBuilder: Instantiator<Flow> [flowBuilder = flowBuilder: Instantiator<Flow>, being built]",
				],
				todaysBodiesPlanLacks: [],
				twinValues: [],
			),
		])
	}

	// MARK: Private

	/// How a screen of `screensOpeningEachOther(roles:targets:)` takes the root's `Context`.
	private enum ContextRole: CaseIterable {
		case declares
		case receives
		case receivesIfAvailable
		case none
	}

	/// Screens that each forward an `id`, receive the root's `Service`, take a `Context` in `roles`' way and open the
	/// screens `targets` names through an `Instantiator`, beneath a root that declares both and opens the first screen:
	/// the fixture `SafeDIToolTypeKeyViewTests` counts the type key's views of.
	private static func screensOpeningEachOther(roles: [ContextRole], targets: [[Int]]) -> [String] {
		var files = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let service: Service", "@Instantiated let context: Context", "@Instantiated let screen0Builder: Instantiator<Screen0>"]),
			seamFixtureType(named: "Service", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Context", isFinalClass: true, declarations: []),
		]
		for (screen, role) in roles.enumerated() {
			var declarations = ["@Forwarded let id: String", "@Received let service: Service"]
			switch role {
			case .declares:
				declarations.append("@Instantiated let context: Context")
			case .receives:
				declarations.append("@Received let context: Context")
			case .receivesIfAvailable:
				declarations.append("@Received(onlyIfAvailable: true) let context: Context?")
			case .none:
				break
			}
			declarations += targets[screen].map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" }
			files.append(seamFixtureType(named: "Screen\(screen)", isFinalClass: true, declarations: declarations))
		}
		return files
	}

	/// A root that opens a hub, which opens `count` members and builds a leaf that receives each member's label only if
	/// available; each member declares its own label, lazily where `declaringLabelsLazily`, and opens the hub again.
	private static func hubOpeningMembers(count: Int, declaringLabelsLazily: Bool = false) -> [String] {
		var files = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let hubBuilder: Instantiator<Hub>"]),
			seamFixtureType(named: "Hub", isFinalClass: true, declarations: (0..<count).map { "@Instantiated let member\($0)Builder: Instantiator<Member\($0)>" } + ["@Instantiated let leaf: Leaf"]),
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: (0..<count).map { "@Received(onlyIfAvailable: true) let label\($0): Label\($0)?" }),
		]
		for member in 0..<count {
			let label = declaringLabelsLazily ? "LazilyInstantiated<Label\(member)>" : "Label\(member)"
			files.append(seamFixtureType(named: "Member\(member)", isFinalClass: true, declarations: ["@Instantiated let label\(member): \(label)", "@Instantiated let hubBuilder: Instantiator<Hub>"]))
			files.append(seamFixtureType(named: "Label\(member)", isFinalClass: true, declarations: []))
		}
		return files
	}

	private struct Bodies: Equatable {
		let place: String
		let todaysUnavailableProperties: [String]
		let bodysUnavailableProperties: [String]
	}

	private struct Plan: Equatable {
		let root: String
		let bodiesOfPlan: [String]
		let todaysBodiesPlanLacks: [String]
		let twinValues: [String]
	}

	private var filesToDelete: [URL]

	/// Each distinct comparison the tool hands on while it generates from `swiftFileContent`, in the order first handed on.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func bodies(of swiftFileContent: String) async throws -> [Bodies] {
		let (stream, continuation) = AsyncStream.makeStream(of: Bodies.self)
		try await VariantBodyObservation.$observer.withValue(TaskLocalFunction { place, todaysUnavailableProperties, bodysUnavailableProperties in
			continuation.yield(Bodies(place: place, todaysUnavailableProperties: todaysUnavailableProperties, bodysUnavailableProperties: bodysUnavailableProperties))
		}) {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: [swiftFileContent],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var bodies = [Bodies]()
		for await body in stream where !bodies.contains(body) {
			bodies.append(body)
		}
		return bodies
	}
}
