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

/// The validation walk skips a subtree whose walk along a path that gives it an equal context completed and found nothing
/// (`cycle-validation.md`, "Clean subtrees"). Each test runs `generate` with the skip and without it and requires the same
/// outcome, the generated code or the diagnostics, byte for byte; each counts the subtrees skipped, so that a test of a
/// shape the skip must not change also shows the skip ran beside it.
struct SafeDIToolCleanSubtreeTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Scaling

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_validatesScopesInNumbersThatGrowLinearlyWithLayers_whenEveryScreenIsSeamOpeningThreeScreensOfNextLayer() async throws {
		// N5 without its hole: layers of four seams, each opening the three screens of the next layer but the one at its own
		// position, so a screen of the last layer is reached along 3^(layers - 1) paths. Each walk of a screen's tree along
		// another path sees the same context, so all but one are skipped.
		var skippingCounts = [Int]()
		var walkingCounts = [Int]()
		for layerCount in [3, 4, 5] {
			let fixture = Self.layeredSeams(layerCount: layerCount)
			let skipping = try await run(fixture, skippingCleanSubtrees: true)
			let walking = try await run(fixture, skippingCleanSubtrees: false)
			#expect(skipping.outcome == walking.outcome)
			#expect(walking.skippedSubtreeCount == 0)
			skippingCounts.append(skipping.validatedScopeCount)
			walkingCounts.append(walking.validatedScopeCount)
		}
		for (smaller, larger) in zip(walkingCounts, walkingCounts.dropFirst()) {
			// Every walk without the skip is exponential in the layers: each layer triples the paths beneath the seam above it.
			#expect(Double(larger) / Double(smaller) > 2.5, "Without the skip the walk validates \(walkingCounts) scopes")
		}
		for (smaller, larger) in zip(skippingCounts, skippingCounts.dropFirst()) {
			// Each layer adds four screens and four models, each validated a fixed number of times.
			#expect(larger - smaller <= skippingCounts[0], "With the skip the walk validates \(skippingCounts) scopes")
		}
	}

	// MARK: Tests – Diagnostics

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorOfHidingPath_whenSharedSubtreeIsCleanOnEveryOtherPath() async throws {
		// `Shared` is built beneath `A`, `C`, `B` and `D`, in that order; only `B` declares `x: Y`, which hides the `x: X`
		// `Leaf` receives. `D`'s walk of `Shared` is skipped, `B`'s is not.
		let result = try await run(Self.hiddenOnOnePath(order: ["aBuilder", "cBuilder", "bBuilder", "dBuilder"]), skippingCleanSubtrees: true)
		#expect(result.skippedSubtreeCount > 0)
		#expect(result.outcome == .error(Self.hiddenOnOnePathError))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorOfPathWhoseClosestDeclarationHides_whenEveryPathReceivablePropertiesAreEqual() async throws {
		// Every path to `Shared` declares `x: X` and `x: Y`, `A`'s in the opposite order, so `Shared` is reached with the same
		// receivable properties and the same stack on each; only the closest declaration of `x` differs. `B`'s path, walked
		// first, is not keyed, and `C`'s is walked clean and kept, so `D`'s is skipped; `A`'s, where `A2`'s `x: Y` hides the
		// `x: X` `Leaf` receives, must not be. With the key's closest declarations dropped, `A`'s walk is skipped and the
		// error is lost.
		let result = try await run(Self.closestDeclarationDiffersOnly, skippingCleanSubtrees: true)
		let unskipped = try await run(Self.closestDeclarationDiffersOnly, skippingCleanSubtrees: false)
		#expect(result.outcome == unskipped.outcome)
		#expect(result.outcome == .error(Self.closestDeclarationDiffersOnlyError))
		#expect(result.skippedSubtreeCount > 0)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorOfPathWhoseFartherDeclarationIsHidden_whenEveryPathClosestDeclarationsAreEqual() async throws {
		// Every path to `Shared` declares `y: Y` at the same depth, so `Shared` is reached with the same closest declarations
		// and the same stack on each; only `A`'s path also declares `y: Z`, farther up, so only its receivable properties
		// differ. `Leaf` receives `y: Z?` only if available: passed `nil` where nothing provides `y: Z`, and hidden by
		// `A2`'s `y: Y` on `A`'s path. `B`'s path is not keyed, `C`'s is walked clean and kept, so `D`'s is skipped; `A`'s
		// must not be. With the key's receivable properties dropped, `A`'s walk is skipped and the error is lost.
		let result = try await run(Self.receivablePropertyDiffersOnly, skippingCleanSubtrees: true)
		let unskipped = try await run(Self.receivablePropertyDiffersOnly, skippingCleanSubtrees: false)
		#expect(result.outcome == unskipped.outcome)
		#expect(result.outcome == .error(Self.receivablePropertyDiffersOnlyError))
		#expect(result.skippedSubtreeCount > 0)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSameHiddenError_whateverPathTheHidingDeclarationIsOn() async throws {
		// Which path walks `Shared` first, and so which walk a later one is skipped after, follows the order of `Root`'s
		// children; the error does not.
		for order in [
			["bBuilder", "aBuilder", "cBuilder", "dBuilder"],
			["aBuilder", "bBuilder", "cBuilder", "dBuilder"],
			["aBuilder", "cBuilder", "dBuilder", "bBuilder"],
		] {
			let result = try await run(Self.hiddenOnOnePath(order: order), skippingCleanSubtrees: true)
			#expect(result.outcome == .error(Self.hiddenOnOnePathError), "Root builds \(order)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsCycleError_whenSharedSubtreeReceivesAncestorBeingBuiltOnOnePath() async throws {
		// `Leaf`, beneath `Shared`, receives `a: A`. Beneath `C`, `D` and `E` it is `Root`'s `a`, built; beneath `A` it is
		// the `a` being built, which closes a received cycle. `E`'s walk of `Shared` is skipped, `A`'s is not.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let cBuilder: Instantiator<C>", "@Instantiated let dBuilder: Instantiator<D>", "@Instantiated let eBuilder: Instantiator<E>", "@Instantiated let a: A"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "D", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "E", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "Shared", isFinalClass: true, declarations: ["@Instantiated let leaf: Leaf"]),
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Received let a: A"]),
		]
		let skipping = try await run(fixture, skippingCleanSubtrees: true)
		let walking = try await run(fixture, skippingCleanSubtrees: false)
		#expect(skipping.skippedSubtreeCount > 0)
		#expect(skipping.outcome == walking.outcome)
		#expect(skipping.outcome == .error(Self.receivedCycleError))
	}

	// MARK: Tests – Dependency trees

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilOnlyWhereNothingProvidesReceive_whenSharedSubtreeReceivesOnlyIfAvailable() async throws {
		// `Leaf` receives `y: Y?` only if available: `B` declares `y`, `A`, `C` and `D` do not, so `Leaf` is passed `nil`
		// beneath them and `B`'s `y` beneath `B`. `D`'s walk of `Shared` is skipped.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let cBuilder: Instantiator<C>", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let dBuilder: Instantiator<D>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let y: Y", "@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "D", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "Shared", isFinalClass: true, declarations: ["@Instantiated let leafBuilder: Instantiator<Leaf>"]),
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let y: Y?"]),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
		let skipping = try await run(fixture, skippingCleanSubtrees: true)
		let walking = try await run(fixture, skippingCleanSubtrees: false)
		#expect(skipping.skippedSubtreeCount > 0)
		#expect(skipping.outcome == walking.outcome)
	}

	// MARK: Tests – Cycles of instantiators

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_validatesScopesInNumbersThatGrowLinearlyWithLayers_whenLastLayerOpensFirstLayerAgain() async throws {
		// Layers of four screens in one module, each opening the three screens of the next layer but the one at its own
		// position, and the last layer opening `Screen0` and the first layer's screen at its own position again: every
		// screen is built inside every set of screens a path through the cycles holds, 3,856 places at twelve screens and
		// 60,394 at sixteen. A screen reads nothing of the screens it is built inside but that an instantiator of one of them
		// closes a cycle, so each is walked once beneath the root's context and once beneath a screen's, and every other
		// walk is skipped.
		var skippingCounts = [Int]()
		var walkingCounts = [Int]()
		for layerCount in [3, 4] {
			let fixture = Self.layeredScreensOpeningFirstLayerAgain(layerCount: layerCount)
			let skipping = try await run(fixture, skippingCleanSubtrees: true)
			let walking = try await run(fixture, skippingCleanSubtrees: false)
			#expect(skipping.outcome == walking.outcome)
			#expect(walking.skippedSubtreeCount == 0)
			skippingCounts.append(skipping.validatedScopeCount)
			walkingCounts.append(walking.validatedScopeCount)
		}
		#expect(walkingCounts == [3_280, 48_634])
		#expect(skippingCounts == [40, 57])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_skipsSharedSubtree_whenItsInstantiatorClosesCycleOnIt() async throws {
		// `Shared` builds itself again through `Inner`, whose `sharedBuilder` closes the cycle on a `Shared` that is given
		// what a `Shared` built there would be: nothing above reads that it closed. `A`'s walk of `Shared` is kept once it
		// completes, and `B`'s and `C`'s are skipped.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let cBuilder: Instantiator<C>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "Shared", isFinalClass: true, declarations: ["@Instantiated let innerBuilder: Instantiator<Inner>"]),
			seamFixtureType(named: "Inner", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
		]
		let skipping = try await run(fixture, skippingCleanSubtrees: true)
		let walking = try await run(fixture, skippingCleanSubtrees: false)
		#expect(skipping.skippedSubtreeCount == 2)
		#expect(skipping.outcome == walking.outcome)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_skipsSubtreeFoundCleanBeneathScopeStillWalked_whenItsCycleClosesOnThatScope() async throws {
		// `Hub` opens `Left` and `Right`, which each open `Leaf`, which opens `Hub` again. `Leaf`'s walk beneath `Left` finds
		// nothing, but closed its cycle on `Hub`, whose walk is still in progress: `Leaf` beneath `Right` is skipped on that
		// account, and both are kept only once `Hub`'s walk completes clean. `Other` reaches `Hub` again, which is skipped.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let hubBuilder: Instantiator<Hub>", "@Instantiated let otherBuilder: Instantiator<Other>"]),
			seamFixtureType(named: "Other", isFinalClass: true, declarations: ["@Instantiated let hubBuilder: Instantiator<Hub>"]),
			seamFixtureType(named: "Hub", isFinalClass: true, declarations: ["@Instantiated let leftBuilder: Instantiator<Left>", "@Instantiated let rightBuilder: Instantiator<Right>"]),
			seamFixtureType(named: "Left", isFinalClass: true, declarations: ["@Instantiated let leafBuilder: Instantiator<Leaf>"]),
			seamFixtureType(named: "Right", isFinalClass: true, declarations: ["@Instantiated let leafBuilder: Instantiator<Leaf>"]),
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Instantiated let hubBuilder: Instantiator<Hub>"]),
		]
		let skipping = try await run(fixture, skippingCleanSubtrees: true)
		let walking = try await run(fixture, skippingCleanSubtrees: false)
		#expect(skipping.skippedSubtreeCount == 2)
		#expect(skipping.outcome == walking.outcome)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorOfHidingPath_whenSharedSubtreeClosesCycleOfInstantiators() async throws {
		// As `generate_throwsHiddenErrorOfHidingPath_whenSharedSubtreeIsCleanOnEveryOtherPath`, with `Shared` opening itself
		// again through `Inner`: only `B` declares `x: Y`, which hides the `x: X` `Inner` receives. `C`'s walk of `Shared`
		// is skipped after `A`'s, `B`'s is not.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let cBuilder: Instantiator<C>", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "Shared", isFinalClass: true, declarations: ["@Instantiated let innerBuilder: Instantiator<Inner>"]),
			seamFixtureType(named: "Inner", isFinalClass: true, declarations: ["@Received let x: X", "@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
		let skipping = try await run(fixture, skippingCleanSubtrees: true)
		let walking = try await run(fixture, skippingCleanSubtrees: false)
		#expect(skipping.skippedSubtreeCount == 1)
		#expect(skipping.outcome == walking.outcome)
		#expect(skipping.outcome == .error("""
		Inner.swift:8:5: error: @Received property `x: X` is hidden in chain: Root -> Instantiator<B> -> Instantiator<Shared> -> Inner. `B` declares `x: Y` with the same label, so the types below `B` receive `x: Y` instead. Give `x: Y` on `B` a different label to fix.
		B.swift:8:5: note: `x: Y` is declared here
		"""))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorOfTreeBuiltAgain_whenScopeInsideCycleDeclaresLabelTheTreeReceives() async throws {
		// `Inner` declares `x: Y` between `Shared` and the `sharedBuilder` that closes the cycle on it, so the `Shared` built
		// again receives `Inner`'s `x`, which hides the `x: X` `Shared` receives. A scope beneath `Shared` declares a label
		// its tree is judged for, so no entry is left out of a key, the cycle-closing scope is judged on every path, and no
		// walk above it is kept.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "Shared", isFinalClass: true, declarations: ["@Received let x: X", "@Instantiated let innerBuilder: Instantiator<Inner>"]),
			seamFixtureType(named: "Inner", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
		let skipping = try await run(fixture, skippingCleanSubtrees: true)
		let walking = try await run(fixture, skippingCleanSubtrees: false)
		#expect(skipping.skippedSubtreeCount == 0)
		#expect(skipping.outcome == walking.outcome)
		#expect(skipping.outcome == .error("""
		Shared.swift:8:5: error: @Received property `x: X` is hidden in chain: Root -> Instantiator<A> -> Instantiator<Shared> -> Instantiator<Inner> -> Shared. `Inner` declares `x: Y` with the same label, so the types below `Inner` receive `x: Y` instead. Give `x: Y` on `Inner` a different label to fix.
		Inner.swift:8:5: note: `x: Y` is declared here
		"""))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNilOnlyWhereNothingProvidesReceive_whenSharedSubtreeClosesCycleOfInstantiators() async throws {
		// `Inner` receives `y: Y?` only if available: `B` declares `y`, `A` and `C` do not, so `Shared`'s key differs beneath
		// `B`, whose walk is not skipped, and `C`'s is skipped after `A`'s.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let cBuilder: Instantiator<C>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let y: Y", "@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "Shared", isFinalClass: true, declarations: ["@Instantiated let innerBuilder: Instantiator<Inner>"]),
			seamFixtureType(named: "Inner", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let y: Y?", "@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
		let skipping = try await run(fixture, skippingCleanSubtrees: true)
		let walking = try await run(fixture, skippingCleanSubtrees: false)
		#expect(skipping.skippedSubtreeCount == 1)
		#expect(skipping.outcome == walking.outcome)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_skipsNoSubtreeInsideCycle_whenCycleHoldsConstant() async throws {
		// `Shared` builds `inner` as a constant, whose `sharedBuilder` closes the cycle: a scope beneath `Shared` could
		// receive `inner` while it is built, so its entry stays in every key beneath it, `Inner`'s walk is never kept, and
		// neither is a walk of `Shared`.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "Shared", isFinalClass: true, declarations: ["@Instantiated let inner: Inner"]),
			seamFixtureType(named: "Inner", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
		]
		let skipping = try await run(fixture, skippingCleanSubtrees: true)
		let walking = try await run(fixture, skippingCleanSubtrees: false)
		#expect(skipping.skippedSubtreeCount == 0)
		#expect(skipping.outcome == walking.outcome)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// What `generate` produced: its generated files, or its diagnostics.
	private enum Outcome: Equatable {
		case generated([String: String])
		case error(String)
	}

	private struct Run {
		let outcome: Outcome
		let validatedScopeCount: Int
		let skippedSubtreeCount: Int
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func run(_ fixture: [String], skippingCleanSubtrees: Bool) async throws -> Run {
		let (stream, continuation) = AsyncStream.makeStream(of: ValidationWalkObservation.self)
		let outcome: Outcome
		do {
			let output = try await ValidationWalkObservation.$skipsCleanSubtrees.withValue(skippingCleanSubtrees) {
				try await ValidationWalkObservation.$observer.withValue({ continuation.yield($0) }) {
					try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
				}
			}
			outcome = .generated(output.generatedFiles ?? [:])
		} catch let error as SafeDIToolTestError {
			outcome = .error(Self.withFixtureNames(error.description))
		}
		continuation.finish()
		var validatedScopeCount = 0
		var skippedSubtreeCount = 0
		for await observation in stream {
			switch observation {
			case .validatedScope:
				validatedScopeCount += 1
			case .skippedCleanSubtree:
				skippedSubtreeCount += 1
			}
		}
		return Run(outcome: outcome, validatedScopeCount: validatedScopeCount, skippedSubtreeCount: skippedSubtreeCount)
	}

	/// `description` with each fixture's directory left out, so two runs' diagnostics compare equal.
	private static func withFixtureNames(_ description: String) -> String {
		description.split(separator: "\n", omittingEmptySubsequences: false).map { line in
			guard let swiftRange = line.range(of: ".swift:"), let slash = line[..<swiftRange.lowerBound].lastIndex(of: "/") else { return String(line) }
			return String(line[line.index(after: slash)...])
		}.joined(separator: "\n")
	}

	/// `layerCount` layers of four screens beneath a root: each forwards an `id`, receives the root's `Service`, instantiates
	/// a model of its own and opens the three screens of the next layer but the one at its own position through an
	/// `Instantiator`; a screen of the last layer opens `Screen0` and the first layer's screen at its own position.
	private static func layeredScreensOpeningFirstLayerAgain(layerCount: Int) -> [String] {
		var fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let service: Service"] + (0..<4).map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" }),
			seamFixtureType(named: "Service", isFinalClass: true, declarations: []),
		]
		for index in 0..<(layerCount * 4) {
			let layer = index / 4
			let opened = layer < layerCount - 1 ? (0..<4).filter { $0 != index % 4 }.map { (layer + 1) * 4 + $0 } : Set([0, index % 4]).sorted()
			fixture.append(seamFixtureType(
				named: "Screen\(index)",
				isFinalClass: true,
				declarations: ["@Forwarded let id: Int", "@Received let service: Service", "@Instantiated let model\(index): Model\(index)"]
					+ opened.map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" },
			))
			fixture.append(seamFixtureType(named: "Model\(index)", isFinalClass: true, declarations: ["@Received let id: Int", "@Received let service: Service"]))
		}
		return fixture
	}

	/// N5 without its hole, in one module, with `layerCount` layers of four screens.
	private static func layeredSeams(layerCount: Int) -> [String] {
		var fixture = [String]()
		let screenCount = layerCount * 4
		for index in 0..<screenCount {
			let layer = index / 4
			let opened = layer < layerCount - 1 ? (0..<4).filter { $0 != index % 4 }.map { (layer + 1) * 4 + $0 } : []
			fixture.append(seamFixtureType(
				named: "Screen\(index)",
				isSeam: true,
				isFinalClass: true,
				declarations: ["@Forwarded let id: Int", "@Received let service: Service", "@Instantiated let model\(index): Model\(index)"]
					+ opened.map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" },
			))
			fixture.append(seamFixtureType(named: "Model\(index)", isFinalClass: true, declarations: ["@Received let id: Int", "@Received let service: Service"]))
		}
		fixture.append(seamFixtureType(named: "Service", isFinalClass: true, declarations: []))
		fixture.append(seamFixtureType(named: "Home", isSeam: true, isFinalClass: true, declarations: (0..<4).map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" }))
		fixture.append(seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let service: Service", "@Instantiated let home: Home"]))
		return fixture
	}

	/// `Shared` beneath `A`, `B`, `C` and `D`, which `Root` builds in `order`: only `B` declares `x: Y`, which hides the `x: X`
	/// that `Leaf`, beneath `Shared`, receives.
	private static func hiddenOnOnePath(order: [String]) -> [String] {
		[
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X"] + order.map { "@Instantiated let \($0): Instantiator<\($0.prefix(1).uppercased())>" }),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "D", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			seamFixtureType(named: "Shared", isFinalClass: true, declarations: ["@Instantiated let leafBuilder: Instantiator<Leaf>"]),
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Received let x: X"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
	}

	/// `Shared` beneath `B2`, beneath `B`, and beneath `A2`, beneath `A`, which `Root` builds after `B`: `A` declares `x: X`
	/// and `A2` `x: Y`, while `B` declares `x: Y` and `B2` `x: X`, so only on `A`'s path does `x: Y` hide the `x: X` that
	/// `Leaf`, beneath `Shared`, receives.
	private static let closestDeclarationDiffersOnly = [
		seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let cBuilder: Instantiator<C>", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let dBuilder: Instantiator<D>"]),
		seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let a2Builder: Instantiator<A2>"]),
		seamFixtureType(named: "A2", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let sharedBuilder: Instantiator<Shared>"]),
		seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let b2Builder: Instantiator<B2>"]),
		seamFixtureType(named: "B2", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let sharedBuilder: Instantiator<Shared>"]),
		seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let c2Builder: Instantiator<C2>"]),
		seamFixtureType(named: "C2", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let sharedBuilder: Instantiator<Shared>"]),
		seamFixtureType(named: "D", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let d2Builder: Instantiator<D2>"]),
		seamFixtureType(named: "D2", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let sharedBuilder: Instantiator<Shared>"]),
		seamFixtureType(named: "Shared", isFinalClass: true, declarations: ["@Instantiated let leafBuilder: Instantiator<Leaf>"]),
		seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Received let x: X"]),
		seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
	]

	private static let receivablePropertyDiffersOnly = [
		seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let cBuilder: Instantiator<C>", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let dBuilder: Instantiator<D>"]),
		seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let y: Z", "@Instantiated let a2Builder: Instantiator<A2>"]),
		seamFixtureType(named: "A2", isFinalClass: true, declarations: ["@Instantiated let y: Y", "@Instantiated let sharedBuilder: Instantiator<Shared>"]),
		seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let b2Builder: Instantiator<B2>"]),
		seamFixtureType(named: "B2", isFinalClass: true, declarations: ["@Instantiated let y: Y", "@Instantiated let sharedBuilder: Instantiator<Shared>"]),
		seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let c2Builder: Instantiator<C2>"]),
		seamFixtureType(named: "C2", isFinalClass: true, declarations: ["@Instantiated let y: Y", "@Instantiated let sharedBuilder: Instantiator<Shared>"]),
		seamFixtureType(named: "D", isFinalClass: true, declarations: ["@Instantiated let d2Builder: Instantiator<D2>"]),
		seamFixtureType(named: "D2", isFinalClass: true, declarations: ["@Instantiated let y: Y", "@Instantiated let sharedBuilder: Instantiator<Shared>"]),
		seamFixtureType(named: "Shared", isFinalClass: true, declarations: ["@Instantiated let leafBuilder: Instantiator<Leaf>"]),
		seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let y: Z?"]),
		seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		seamFixtureType(named: "Z", isFinalClass: true, declarations: []),
	]

	private static let receivablePropertyDiffersOnlyError = """
	Leaf.swift:7:5: error: @Received property `y: Z?` is hidden in chain: Root -> Instantiator<A> -> Instantiator<A2> -> Instantiator<Shared> -> Leaf. `A2` declares `y: Y` with the same label, so the types below `A2` receive `y: Y` instead. Give `y: Y` on `A2` a different label to fix.
	A2.swift:8:5: note: `y: Y` is declared here
	"""

	private static let closestDeclarationDiffersOnlyError = """
	Leaf.swift:7:5: error: @Received property `x: X` is hidden in chain: Root -> Instantiator<A> -> Instantiator<A2> -> Instantiator<Shared> -> Leaf. `A2` declares `x: Y` with the same label, so the types below `A2` receive `x: Y` instead. Give `x: Y` on `A2` a different label to fix.
	A2.swift:8:5: note: `x: Y` is declared here
	"""

	private static let hiddenOnOnePathError = """
	Leaf.swift:7:5: error: @Received property `x: X` is hidden in chain: Root -> Instantiator<B> -> Instantiator<Shared> -> Leaf. `B` declares `x: Y` with the same label, so the types below `B` receive `x: Y` instead. Give `x: Y` on `B` a different label to fix.
	B.swift:8:5: note: `x: Y` is declared here
	"""
	private static let receivedCycleError = """
	Leaf.swift:7:5: error: Dependency cycle: `A` -> `Instantiator<Shared>` -> `Leaf` -> `A`. `Leaf` receives `a: A`, which is still being built when `Leaf` is built. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
	A.swift:1:1: note: `A` is part of the cycle
	Shared.swift:1:1: note: `Shared` is part of the cycle
	Leaf.swift:1:1: note: `Leaf` is part of the cycle
	"""
}
