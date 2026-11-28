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

/// The fold of received properties (`ReceivedCycleFold`) answers, once for a validation's trees, whether the walk of
/// received properties can find anything at any place. Each test runs `generate` with the walk run either way
/// (`ValidationWalkObservation.foldComparison`, which the test executor sets and which fails a test whose trees the
/// fold clears and the walk rejects), and reads what the fold answered beside what the walk found.
struct SafeDIToolReceivedCycleFoldTests: ~Copyable {
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
	mutating func generate_findsNoRouteThatMayFail_whenNoPlaceIsBuiltInsideWhatItsScopeReaches() async throws {
		// Four screens beneath a root, each receiving the root's `store` and `service` and building a model that receives
		// the store, which receives the service: every place requires a property, and none is built inside one it reaches.
		var fixture = [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service", "@Instantiated let store: Store"] + (0..<4).map { "@Instantiated let screen\($0): Screen\($0)" }),
			seamFixtureType(named: "Service", declarations: []),
			seamFixtureType(named: "Store", declarations: ["@Received let service: Service"]),
		]
		for index in 0..<4 {
			fixture.append(seamFixtureType(named: "Screen\(index)", declarations: ["@Received let store: Store", "@Received let service: Service", "@Instantiated let model: Model\(index)"]))
			fixture.append(seamFixtureType(named: "Model\(index)", declarations: ["@Received let store: Store"]))
		}
		let run = try await run(fixture)
		#expect(run.isGenerated)
		#expect(run.routesThatMayFail == [])
	}

	@Test(arguments: [0, 70])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_findsNoRouteThatMayFail_whenScreenReceivesInstantiatorBeingBuiltAboveIt(storeCount: Int) async throws {
		// `Screen1` is built inside `screen0Builder`, which it receives to open the first screen again: the walk accepts a
		// receive of an instantiator still being built and does not follow it, so it has nothing to find. With 70 stores
		// received beside it, the scope's row holds more than one word.
		let stores = Self.stores(count: storeCount)
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let service: Service", "@Instantiated let screen0Builder: Instantiator<Screen0>"] + stores.instantiated),
			seamFixtureType(named: "Service", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Screen0", isFinalClass: true, declarations: ["@Received let service: Service", "@Instantiated let screen1Builder: Instantiator<Screen1>"]),
			seamFixtureType(named: "Screen1", isFinalClass: true, declarations: stores.received + ["@Received let service: Service", "@Received let screen0Builder: Instantiator<Screen0>"]),
		] + stores.types
		let run = try await run(fixture)
		#expect(run.isGenerated)
		#expect(run.routesThatMayFail == [])
	}

	@Test(arguments: ReceivedForm.allCases, [0, 70])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_findsReceivedCycle_whenPlaceIsBuiltInsideValueItsScopeReachesThroughAnotherValue(form: ReceivedForm, storeCount: Int) async throws {
		// `Reader` is built inside `account`, and receives `session`, whose type receives `account`: the scope reaches a value
		// still being built only through another property. Each form is one in which the walk and the fold must find the
		// same property: the value itself, a rename of the property on the way, and a value declared lazily, which the
		// stack holds as the constant it stands for.
		let stores = Self.stores(count: storeCount)
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, declarations: stores.instantiated + [form.accountDeclaration, "@Instantiated let session: Session"]),
			seamFixtureType(named: "Account", declarations: ["@Instantiated let reader: Reader"]),
			seamFixtureType(named: "Reader", declarations: stores.received + [form.sessionReceive]),
			seamFixtureType(named: "Session", declarations: ["@Received let account: Account"]),
		] + stores.types
		let run = try await run(fixture)
		#expect(run.errorDescription?.contains("error: Dependency cycle") == true)
		#expect(run.routesThatMayFail == ["receivedCycle"])
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_findsNoRouteThatMayFail_whenReceiveInsideValueOfItsLabelIsBeneathTypeThatDeclaresLabelAgain(withLazyTwin: Bool) async throws {
		// `Host` builds `model` and `screen`, which receives `model`; `Model` builds `hostBuilder`, so a `Screen` is built
		// inside a `model` still being built, beneath a `Host` that declares `model` again: the screen reads that nearer
		// declaration. With the lazy twin, `First` declares the same label and type as a `LazilyInstantiated`, which cycle
		// validation sees as the same `model: Model`, and builds a `Host` inside it too.
		var rootDeclarations = ["@Instantiated let hostBuilder: Instantiator<Host>"]
		var fixture = [
			seamFixtureType(named: "Host", declarations: ["@Instantiated let model: Model", "@Instantiated let screen: Screen"]),
			seamFixtureType(named: "Model", declarations: ["@Instantiated let hostBuilder: Instantiator<Host>"]),
			seamFixtureType(named: "Screen", declarations: ["@Received let model: Model"]),
		]
		if withLazyTwin {
			rootDeclarations.append("@Instantiated let first: First")
			fixture.append(seamFixtureType(named: "First", declarations: ["@Instantiated let model: LazilyInstantiated<Model>", "@Instantiated let screen: Screen"]))
		}
		fixture.append(seamFixtureType(named: "Root", isRoot: true, declarations: rootDeclarations))
		let run = try await run(fixture)
		#expect(run.isGenerated)
		#expect(run.routesThatMayFail == [])
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_findsReceivedCycle_whenTypeThatDeclaresLabelAgainReceivesValueWhoseTypeReadsLabel(withLazyTwin: Bool) async throws {
		// The shape above with `Host` receiving the root's `session`, whose type receives `model`: `Host`'s own receives
		// are judged against the declarations above `Host`, not its own, so through `session` the `Host` built inside the
		// root's `model` reads that `model` while it is still being built. The walk rejects the trees, and the fold must
		// send them to it, though `Host` declares `model` again for the types it builds.
		var rootDeclarations = ["@Instantiated let model: Model", "@Instantiated let session: Session", "@Instantiated let hostBuilder: Instantiator<Host>"]
		var fixture = [
			seamFixtureType(named: "Host", declarations: ["@Received let session: Session", "@Instantiated let model: Model", "@Instantiated let screen: Screen"]),
			seamFixtureType(named: "Model", declarations: ["@Instantiated let hostBuilder: Instantiator<Host>"]),
			seamFixtureType(named: "Screen", declarations: ["@Received let model: Model"]),
			seamFixtureType(named: "Session", declarations: ["@Received let model: Model"]),
		]
		if withLazyTwin {
			rootDeclarations.append("@Instantiated let first: First")
			fixture.append(seamFixtureType(named: "First", declarations: ["@Instantiated let model: LazilyInstantiated<Model>", "@Instantiated let screen: Screen"]))
		}
		fixture.append(seamFixtureType(named: "Root", isRoot: true, declarations: rootDeclarations))
		let run = try await run(fixture)
		#expect(run.errorDescription?.contains("error: Dependency cycle") == true)
		#expect(run.routesThatMayFail == ["receivedCycle"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_findsReceivedCycle_whenRenameOnlyIfAvailableBeneathTypeThatDeclaresLabelAgainIsBoundFromValueWhoseTypeReadsLabel() async throws {
		// `Screen`, built beneath a `Host` that declares `model` again, renames the root's `session` only if available, and
		// `Panel` requires the rename. The walk of what the rename is bound from starts where `Screen` declares it, where it
		// has no nearest declarations, so `Session`'s receive of `model` is judged as the root's `model`, which is still
		// being built around `Screen`: the walk rejects the trees, and `Host`'s declaration must hide nothing from it.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let model: Model", "@Instantiated let session: Session"]),
			seamFixtureType(named: "Model", declarations: ["@Instantiated let hostBuilder: Instantiator<Host>"]),
			seamFixtureType(named: "Host", declarations: ["@Instantiated let model: Model", "@Instantiated let screen: Screen"]),
			seamFixtureType(named: "Screen", declarations: ["@Received(fulfilledByDependencyNamed: \"session\", ofType: Session.self, onlyIfAvailable: true) let renamedSession: Session?", "@Instantiated let panel: Panel"]),
			seamFixtureType(named: "Panel", declarations: ["@Received let renamedSession: Session?"]),
			seamFixtureType(named: "Session", declarations: ["@Received let model: Model"]),
		]
		let run = try await run(fixture)
		#expect(run.errorDescription?.contains("error: Dependency cycle") == true)
		#expect(run.routesThatMayFail == ["receivedCycle"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_findsRenamedReceive_whenRenameIsReceivedInsideSiblingItIsFulfilledBy() async throws {
		// `Root` renames the `service` it builds as `renamedService`, and `Reader`, built inside `service`, requires
		// `renamedService`: the rename is received while the value it is bound from is still being built. No property
		// `Reader` reaches is `service` itself, so only the rename's question sends the trees to the walk.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let service: Service", "@Received(fulfilledByDependencyNamed: \"service\", ofType: Service.self) let renamedService: Service"]),
			seamFixtureType(named: "Service", declarations: ["@Instantiated let reader: Reader"]),
			seamFixtureType(named: "Reader", declarations: ["@Received let renamedService: Service"]),
		]
		let run = try await run(fixture)
		#expect(run.errorDescription?.contains("error: Dependency cycle") == true)
		#expect(run.routesThatMayFail == ["renamedReceive"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_clearsOnlyTreesTheWalkAccepts_whenScreensWithOnlyIfAvailableAliasesAreDrawnFromEachSeed() async throws {
		// The draw of `SafeDIToolReceivedPropertiesByComponentTests`, whose graphs close cycles through values, through
		// instantiators and through renames, required or only if available. The counts are the validations the walk
		// rejects, those the fold finds a received cycle or a renamed receive in, and those it finds no route that may fail
		// in; none of the last is rejected. A fold that asks only what a place's own scope requires, by hand, clears
		// rejected trees at seeds 10, 79, 96, 108 and 127.
		var rejectedCount = 0
		var receivedCycleCount = 0
		var clearedCount = 0
		for seed in 0..<150 as Range<UInt64> {
			for comparison in try await run(SafeDIToolReceivedPropertiesByComponentTests.screensWithOnlyIfAvailableAliases(seed: seed)).comparisons {
				if comparison.walkRejected {
					rejectedCount += 1
				}
				switch comparison.routeThatMayFail {
				case "receivedCycle", "renamedReceive":
					receivedCycleCount += 1
				case nil:
					#expect(!comparison.walkRejected, "seed \(seed)")
					clearedCount += 1
				default:
					break
				}
			}
		}
		let counts: [Int] = [rejectedCount, receivedCycleCount, clearedCount]
		#expect(counts == [103, 50, 180])
	}

	// MARK: Internal

	/// How the value a place is built inside is declared, and how the place's scope reaches it.
	enum ReceivedForm: CaseIterable {
		case value
		case renamedOnTheWay
		case declaredLazily

		var accountDeclaration: String {
			switch self {
			case .value, .renamedOnTheWay:
				"@Instantiated let account: Account"
			case .declaredLazily:
				"@Instantiated let account: LazilyInstantiated<Account>"
			}
		}

		var sessionReceive: String {
			switch self {
			case .value, .declaredLazily:
				"@Received let session: Session"
			case .renamedOnTheWay:
				"@Received(fulfilledByDependencyNamed: \"session\", ofType: Session.self) let renamedSession: Session"
			}
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private struct Run {
		/// The tool's diagnostics, or `nil` where it generated code.
		let errorDescription: String?
		/// What the fold answered for each validation of the run, beside what the walk found.
		let comparisons: [FulfillmentFoldComparison]

		var isGenerated: Bool {
			errorDescription == nil
		}

		/// The judgements the fold found some route may fail, over the validations of the run, each once, in name order.
		var routesThatMayFail: [String] {
			Set(comparisons.compactMap(\.routeThatMayFail)).sorted()
		}
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func run(_ fixture: [String]) async throws -> Run {
		let (stream, continuation) = AsyncStream.makeStream(of: FulfillmentFoldComparison.self)
		let errorDescription: String? = try await ValidationWalkObservation.$foldComparison.withValue({ continuation.yield($0) }) {
			do {
				_ = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
				return nil
			} catch let error as SafeDIToolTestError {
				return error.description
			}
		}
		continuation.finish()
		var comparisons = [FulfillmentFoldComparison]()
		for await comparison in stream {
			comparisons.append(comparison)
		}
		return Run(errorDescription: errorDescription, comparisons: comparisons)
	}

	/// `count` stores that receive nothing: their types, the declarations that instantiate them and those that receive them.
	private static func stores(count: Int) -> (types: [String], instantiated: [String], received: [String]) {
		(
			(0..<count).map { seamFixtureType(named: "Store\($0)", isFinalClass: true, declarations: []) },
			(0..<count).map { "@Instantiated let store\($0): Store\($0)" },
			(0..<count).map { "@Received let store\($0): Store\($0)" },
		)
	}
}
