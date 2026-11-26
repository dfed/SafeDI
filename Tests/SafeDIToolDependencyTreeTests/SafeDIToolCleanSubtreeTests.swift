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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_stopsKeyingScope_whenScreensOpenEachOtherWithoutLayersAndNoKeyOfItIsFoundAgain() async throws {
		// The screens are in no layers and differ in what they do with `context`, so each is reached along paths whose keys
		// nearly all differ. A scope keyed eight
		// times in a row with no remembered walk of an equal key is keyed no more, so the keys built stay a small part of
		// the scopes walked; the walk reports what it reports without the skip. Keyed wherever they were reached, the same
		// walks built 90 and 270 keys and skipped nothing more.
		var keyedCounts = [Int]()
		var validatedCounts = [Int]()
		for screenCount in [8, 10] {
			let fixture = [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let context: Context", "@Instantiated let screen0Builder: Instantiator<Screen0>"]),
				seamFixtureType(named: "Context", isFinalClass: true, declarations: []),
			] + Self.screensOpeningEachOtherWithoutLayers(screenCount: screenCount)
			let skipping = try await run(fixture, skippingCleanSubtrees: true)
			let walking = try await run(fixture, skippingCleanSubtrees: false)
			#expect(skipping.outcome == walking.outcome)
			#expect(walking.keyedSubtreeCount == 0)
			keyedCounts.append(skipping.keyedSubtreeCount)
			validatedCounts.append(skipping.validatedScopeCount)
		}
		#expect(keyedCounts == [66, 123])
		#expect(validatedCounts == [83, 223])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorsOfWalkWithoutSkip_whateverOrderRootsThatShareScopesNoLongerKeyedAreDeclaredIn() async throws {
		// Four roots open four of eight screens that open each other without layers, where `Screen5` declares `x: Y` and
		// hides the `x: X` that `Leaf`, beneath `Screen2`, receives from a root. The roots share the count that stops a
		// scope being keyed, so which root is walked first decides which walks are remembered, and nothing of the errors.
		var outcomes = [Outcome]()
		for rootNames in [["RootA", "RootB", "RootC", "RootD"], ["RootD", "RootC", "RootB", "RootA"], ["RootC", "RootA", "RootD", "RootB"]] {
			let roots = zip(rootNames, [0, 3, 5, 6]).map { name, screen in
				seamFixtureType(named: name, isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let context: Context", "@Instantiated let screen\(screen)Builder: Instantiator<Screen\(screen)>"])
			}
			let fixture = roots.sorted() + Self.screensOpeningEachOtherWithoutLayers(
				screenCount: 8,
				additionalDeclarations: [5: ["@Instantiated let x: Y"], 2: ["@Instantiated let leafBuilder: Instantiator<Leaf>"]],
			) + [
				seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Received let x: X"]),
				seamFixtureType(named: "Context", isFinalClass: true, declarations: []),
				seamFixtureType(named: "X", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
			]
			let skipping = try await run(fixture, skippingCleanSubtrees: true)
			let walking = try await run(fixture, skippingCleanSubtrees: false)
			#expect(skipping.outcome == walking.outcome, "Roots \(rootNames)")
			#expect(skipping.keyedSubtreeCount < skipping.validatedScopeCount, "Roots \(rootNames)")
			outcomes.append(skipping.outcome)
		}
		#expect(outcomes.allSatisfy {
			if case .error = $0 {
				true
			} else {
				false
			}
		})
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_stopsKeyingScope_whenScreensInLayersWithoutCyclesReceiveWhatOnlyTheirPathDeclares() async throws {
		// Layers of four screens, each opening three screens of the next layer, with no cycle: every screen declares a mark
		// of its own, and receives, only if available, the mark of every screen of the layers above. Which marks are
		// available differs on every path, so every key of a screen differs. A scope keyed eight times in a row with no
		// remembered walk of an equal key is keyed no more, whether or not it reaches a cycle, so fewer keys are built for
		// the same scopes walked; the walk reports what it reports without the skip. Keyed wherever they were reached again,
		// the same walks built 303 and 947 keys.
		var keyedCounts = [Int]()
		var validatedCounts = [Int]()
		for layerCount in [4, 5] {
			let fixture = Self.layeredScreensReceivingMarksOfTheirPath(layerCount: layerCount)
			let skipping = try await run(fixture, skippingCleanSubtrees: true)
			let walking = try await run(fixture, skippingCleanSubtrees: false)
			#expect(skipping.outcome == walking.outcome)
			keyedCounts.append(skipping.keyedSubtreeCount)
			validatedCounts.append(skipping.validatedScopeCount)
		}
		#expect(keyedCounts == [231, 587])
		#expect(validatedCounts == [177, 505])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_validatesScopesInNumbersThatGrowLinearlyWithLayers_whenErasedScreensEachDeclareOneLabelWithModelOfTheirOwn() async throws {
		// Layers of four seams, each in a module of its own and opening three screens of the next layer through erased
		// instantiators, with no cycle: every screen declares `model` with a model type of its own, which only that model's
		// tree is built for and nothing receives. The app's walk reaches a screen of a deep layer along every path through
		// the layers above, each with other `model`s receivable; no walk of the screen's subtree looks one up, so its key
		// holds none and all but one walk of each screen are skipped.
		var skippingCounts = [Int]()
		var walkingCounts = [Int]()
		for layerCount in [3, 4, 5, 6] {
			let modules = Self.layeredErasedSeamModules(layerCount: layerCount)
			let skipping = try await run(modules, skippingCleanSubtrees: true)
			let walking = try await run(modules, skippingCleanSubtrees: false)
			#expect(skipping.outcome == walking.outcome)
			skippingCounts.append(skipping.validatedScopeCount)
			walkingCounts.append(walking.validatedScopeCount)
		}
		for (smaller, larger) in zip(walkingCounts, walkingCounts.dropFirst()) {
			#expect(Double(larger) / Double(smaller) > 2, "Without the skip the walk validates \(walkingCounts) scopes")
		}
		// Each layer adds four screens, each walked once with its model and its session, and skipped where it is reached again.
		#expect(skippingCounts == [136, 192, 248, 304])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_validatesScopesInNumbersThatGrowLinearlyWithLayers_whenErasedScreensNameTheirBuildersAlikeInEveryLayer() async throws {
		// The same layers, each screen naming the builder of a screen for that screen's position in its layer: every path
		// to a screen holds, layer after layer, entries of the labels the screen's own builders have, built for screens of
		// the layers above. No scope beneath receives one, and none builds those screens again, so the screen's key holds
		// a gap for them and all but one walk of each screen are skipped.
		var skippingCounts = [Int]()
		var walkingCounts = [Int]()
		for layerCount in [3, 4, 5, 6] {
			let modules = Self.layeredErasedSeamModules(layerCount: layerCount, namingBuildersByPosition: true)
			let skipping = try await run(modules, skippingCleanSubtrees: true)
			let walking = try await run(modules, skippingCleanSubtrees: false)
			#expect(skipping.outcome == walking.outcome)
			skippingCounts.append(skipping.validatedScopeCount)
			walkingCounts.append(walking.validatedScopeCount)
		}
		for (smaller, larger) in zip(walkingCounts, walkingCounts.dropFirst()) {
			#expect(Double(larger) / Double(smaller) > 2, "Without the skip the walk validates \(walkingCounts) scopes")
		}
		#expect(skippingCounts == [136, 192, 248, 304])
	}

	// MARK: Tests – A label declared with different types

	@Test(arguments: LabelAbove.allCases, LabelBeneath.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsWhatWalkWithoutSkipReports_whenPathsToSharedSubtreeDeclareOneLabelWithDifferentTypes(above: LabelAbove, beneath: LabelBeneath) async throws {
		// `Shared` is built beneath `A`, `B`, `C` and `D`, whose paths differ only in the type they declare `x` with, or in
		// whether they declare it. Where no scope beneath `Shared` reads what is receivable under `x`, the key of `Shared`
		// holds none of it, and the walks beneath `C` and `D` are skipped; where one does, each walk is skipped only after a
		// walk the same `x` was receivable in, and the errors of the paths that hide it or lack it are reported as the walk
		// without the skip reports them.
		let fixture = Self.sharedSubtree(above: above, beneath: beneath)
		let skipping = try await run(fixture, skippingCleanSubtrees: true)
		let walking = try await run(fixture, skippingCleanSubtrees: false)
		#expect(skipping.outcome == walking.outcome)
		#expect(walking.skippedSubtreeCount == 0)
		let expected = Self.expectedOutcome(above: above, beneath: beneath)
		#expect(skipping.skippedSubtreeCount == expected.skippedSubtreeCount)
		switch skipping.outcome {
		case .generated:
			#expect(expected.error == nil)
		case let .error(description):
			#expect(description.split(separator: "\n").first.map(String.init) == expected.error)
		}
	}

	@Test(arguments: [false, true], BuilderLabelBeneath.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsWhatWalkWithoutSkipReports_whenPathsToSharedSubtreeBuildDifferentTypesForOneLabel(everyOtherPathNamesItsBuilderApart: Bool, beneath: BuilderLabelBeneath) async throws {
		// `Shared` is built beneath `A0` to `A5`, each built for a builder named `link` (or, on every other path, `other`)
		// that a type of its own path declares. Where `Shared` only declares a `link` of its own, no entry above it is
		// compared with anything, and it is skipped beneath every parent after the second; where a scope beneath builds
		// `A0` again for `link`, or receives `link`, the entry is held and a walk is skipped only after one of an equal
		// entry.
		let fixture = Self.sharedSubtreeBeneathBuildersOfOneLabel(everyOtherPathNamesItsBuilderApart: everyOtherPathNamesItsBuilderApart, beneath: beneath)
		let skipping = try await run(fixture, skippingCleanSubtrees: true)
		let walking = try await run(fixture, skippingCleanSubtrees: false)
		#expect(skipping.outcome == walking.outcome)
		#expect(walking.skippedSubtreeCount == 0)
		let expected = Self.expectedOutcome(everyOtherPathNamesItsBuilderApart: everyOtherPathNamesItsBuilderApart, beneath: beneath)
		#expect(skipping.skippedSubtreeCount == expected.skippedSubtreeCount)
		#expect(skipping.validatedScopeCount == expected.validatedScopeCount)
		switch skipping.outcome {
		case .generated:
			#expect(expected.error == nil)
		case let .error(description):
			#expect(description.split(separator: "\n").first.map(String.init) == expected.error)
		}
	}

	// MARK: Tests – A receive inside a cycle of instantiators

	@Test(arguments: ReceiveInsideCycle.allCases, DeclarationOrder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsWhatWalkWithoutSkipReports_whenTypeInsideCycleOfInstantiatorsReceivesWhatOnlySomePathsToCycleDeclare(graph: ReceiveInsideCycle, order: DeclarationOrder) async throws {
		// A type on a cycle of instantiators receives a property, so every type of the cycle reads that label from above
		// wherever the cycle is entered: the key of each holds the label's closest declaration. The paths into the cycle
		// declare the label, declare it with another type, or do not declare it, so a walk of the cycle found clean beneath
		// one must not be skipped beneath another, whichever type of the cycle a path enters at and whatever order the
		// declarations are in. With the labels a type on a cycle reads taken from a walk that stops at a type whose own
		// walk is in progress, a type's key lacked the label and the error of a path was lost.
		let fixture = graph.fixture(order: order)
		let skipping = try await run(fixture, skippingCleanSubtrees: true)
		let walking = try await run(fixture, skippingCleanSubtrees: false)
		#expect(skipping.outcome == walking.outcome)
		switch walking.outcome {
		case .generated:
			#expect(!graph.isInvalid)
		case .error:
			#expect(graph.isInvalid)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsWhatWalkWithoutSkipReports_whenRingOfBuildersWithReceiveInsideIsDrawnFromEachSeed() async throws {
		// A draw of the shape the handwritten graphs above take four orders of: types that build each other in a ring, some
		// of which receive, rename, declare or forward one label, entered at any of them by paths that declare the label,
		// declare it with another type or declare nothing, with every type's declarations and the files in a drawn order.
		// Every graph is run with the skip and without it. The counts show the draw reaches what it is for: graphs the tool
		// accepts, graphs it rejects, and graphs whose walk skipped a subtree. With a cycle's types answered one at a time
		// from a walk in progress, the two runs of seeds 27 and 65 differ.
		var acceptedCount = 0
		var rejectedCount = 0
		var skippingCount = 0
		for seed in 0..<Self.ringDrawSeedCount {
			let fixture = Self.ringOfBuildersWithReceiveInside(seed: seed)
			let skipping = try await run(fixture, skippingCleanSubtrees: true)
			let walking = try await run(fixture, skippingCleanSubtrees: false)
			#expect(skipping.outcome == walking.outcome, "seed \(seed)")
			switch walking.outcome {
			case .generated:
				acceptedCount += 1
			case .error:
				rejectedCount += 1
			}
			if skipping.skippedSubtreeCount > 0 {
				skippingCount += 1
			}
		}
		let counts = [acceptedCount, rejectedCount, skippingCount]
		#expect(counts == [72, 128, 149])
	}

	// MARK: Tests – One graph for each part of the key

	@Test(arguments: GraphForKeyPart.allCases, DeclarationOrder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsWhatWalkWithoutSkipReports_whenGraphNeedsOnePartOfKey(graph: GraphForKeyPart, order: DeclarationOrder) async throws {
		// Each graph is one a search over seeded graphs found and shrank: with the part of the key its case names left out
		// by hand, the run that skips reports other diagnostics than the run that skips nothing, in the order the
		// declarations are written in. The other orders are run too, since which path reaches a scope first follows them.
		let fixture = graph.fixture(order: order)
		let skipping = try await run(fixture, skippingCleanSubtrees: true)
		let walking = try await run(fixture, skippingCleanSubtrees: false)
		#expect(skipping.outcome == walking.outcome)
		guard case let .error(description) = walking.outcome else {
			Issue.record("Every graph of this test holds an error the walk reports")
			return
		}
		#expect(description.components(separatedBy: "error: ").count - 1 == graph.errorCount)
		// The key was asked, and told the paths apart.
		#expect(skipping.keyedSubtreeCount > 0)
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
		let keyedSubtreeCount: Int
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func run(_ fixture: [String], skippingCleanSubtrees: Bool) async throws -> Run {
		try await Self.observingValidationWalk(skippingCleanSubtrees: skippingCleanSubtrees) {
			do {
				return try await .generated((executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete).generatedFiles ?? [:]).mapValues(Self.withFixtureNames))
			} catch let error as SafeDIToolTestError {
				return .error(Self.withFixtureNames(error.description))
			}
		}
	}

	/// Generates `modules` in order, as Bazel does, with every module's generated files keyed by the module's name and
	/// the file's.
	private mutating func run(_ modules: [ModuleFixture], skippingCleanSubtrees: Bool) async throws -> Run {
		try await Self.observingValidationWalk(skippingCleanSubtrees: skippingCleanSubtrees) {
			let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
			var generatedFiles = [String: String]()
			for (moduleName, module) in output.modules {
				for (fileName, file) in module.generatedFiles {
					generatedFiles["\(moduleName)/\(fileName)"] = file
				}
			}
			return .generated(generatedFiles)
		}
	}

	private static func observingValidationWalk(skippingCleanSubtrees: Bool, _ generate: () async throws -> Outcome) async throws -> Run {
		let (stream, continuation) = AsyncStream.makeStream(of: ValidationWalkObservation.self)
		let outcome = try await ValidationWalkObservation.$skipsCleanSubtrees.withValue(skippingCleanSubtrees) {
			try await ValidationWalkObservation.$observer.withValue({ continuation.yield($0) }) {
				try await generate()
			}
		}
		continuation.finish()
		var validatedScopeCount = 0
		var skippedSubtreeCount = 0
		var keyedSubtreeCount = 0
		for await observation in stream {
			switch observation {
			case .validatedScope:
				validatedScopeCount += 1
			case .skippedCleanSubtree:
				skippedSubtreeCount += 1
			case .collectedReceivedPropertiesOfScope:
				break
			case .keyedSubtree:
				keyedSubtreeCount += 1
			}
		}
		return Run(outcome: outcome, validatedScopeCount: validatedScopeCount, skippedSubtreeCount: skippedSubtreeCount, keyedSubtreeCount: keyedSubtreeCount)
	}

	/// `description` with each fixture's directory left out of a diagnostic's location and of a `#sourceLocation`, so two
	/// runs' diagnostics, or generated files, compare equal.
	private static func withFixtureNames(_ description: String) -> String {
		description.split(separator: "\n", omittingEmptySubsequences: false).map { line in
			if let swiftRange = line.range(of: ".swift:"), let slash = line[..<swiftRange.lowerBound].lastIndex(of: "/") {
				String(line[line.index(after: slash)...])
			} else if let fileRange = line.range(of: "#sourceLocation(file: \""), let slash = line.lastIndex(of: "/") {
				String(line[..<fileRange.upperBound]) + line[line.index(after: slash)...]
			} else {
				String(line)
			}
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

	/// `layerCount` layers of four screens beneath a root: each declares a mark of its own, receives only if available the
	/// mark of every screen of the layers above, and opens the three screens of the next layer but the one at its own
	/// position through an `Instantiator`.
	private static func layeredScreensReceivingMarksOfTheirPath(layerCount: Int) -> [String] {
		var fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: (0..<4).map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" }),
			seamFixtureType(named: "Mark", isFinalClass: true, declarations: []),
		]
		for index in 0..<(layerCount * 4) {
			let layer = index / 4
			let opened = layer < layerCount - 1 ? (0..<4).filter { $0 != index % 4 }.map { (layer + 1) * 4 + $0 } : []
			fixture.append(seamFixtureType(
				named: "Screen\(index)",
				isFinalClass: true,
				declarations: ["@Instantiated let mark\(index): Mark"]
					+ (0..<(layer * 4)).map { "@Received(onlyIfAvailable: true) let mark\($0): Mark?" }
					+ opened.map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" },
			))
		}
		return fixture
	}

	/// `Core`, a module for each of `layerCount` layers of four seams, and `App`: each screen opens the three screens of the
	/// next layer but the one at its own position through erased instantiators, and builds an internal model that receives
	/// the screen's forwarded `id` and lazily builds a session; `App`'s root opens the first layer. The shape of the
	/// erased-screens benchmark. A builder is named for the screen it opens, or, with `namingBuildersByPosition`, for that
	/// screen's position in its layer, so that every layer declares the same four labels.
	private static func layeredErasedSeamModules(layerCount: Int, namingBuildersByPosition: Bool = false) -> [ModuleFixture] {
		func erasedBuilder(of screen: Int) -> String {
			"@Instantiated(fulfilledByType: \"Screen\(screen)\", erasedToConcreteExistential: true) public let \(namingBuildersByPosition ? "child\(screen % 4)" : "screen\(screen)")Builder: ErasedInstantiator<Int, AnyScreen>"
		}
		let screenCount = layerCount * 4
		var modules = [ModuleFixture]()
		for index in (0..<screenCount).reversed() {
			let layer = index / 4
			let opened = layer < layerCount - 1 ? (0..<4).filter { $0 != index % 4 }.map { (layer + 1) * 4 + $0 } : []
			let imports = (["Core"] + opened.map { "Screen\($0)Module" }).map { "import \($0)\n" }.joined()
			modules.append(ModuleFixture(
				name: "Screen\(index)Module",
				packageName: "Shop",
				swiftFileContent: [
					imports + "\n" + seamFixtureType(
						named: "Screen\(index)",
						isSeam: true,
						isFinalClass: true,
						declarations: ["@Forwarded public let id: Int", "@Received public let service: Service", "@Instantiated let model: Model\(index)"] + opened.map(erasedBuilder(of:)),
					),
					"import Core\n\n" + seamFixtureType(named: "Model\(index)", isFinalClass: true, declarations: ["@Received public let id: Int", "@Received public let service: Service", "@Instantiated public let session: LazilyInstantiated<Session>"]),
				],
				dependencies: ["Core"] + opened.map { "Screen\($0)Module" },
			))
		}
		return [
			ModuleFixture(
				name: "Core",
				packageName: "Shop",
				swiftFileContent: [
					"""
					public final class AnyScreen {
					    public init(_ screen: AnyObject) {
					        self.screen = screen
					    }

					    public let screen: AnyObject
					}
					""",
					seamFixtureType(named: "Service", isFinalClass: true, declarations: []),
					seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
				],
			),
		] + modules + [
			ModuleFixture(
				name: "App",
				packageName: "Shop",
				swiftFileContent: [(["Core"] + modules.map(\.name)).map { "import \($0)\n" }.joined() + "\n" + seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let service: Service"] + (0..<4).map(erasedBuilder(of:)))],
				dependencies: ["Core"] + modules.map(\.name),
			),
		]
	}

	/// Screen `i` of `screenCount` opens screens `i + 1`, `2i + 3` and `3i + 5` (modulo the count; itself and a screen
	/// twice left out) through `Instantiator`s, after its `additionalDeclarations`. Every fourth screen declares
	/// `context: Context`, the one after it receives it and the one after that receives it only if available, so what a
	/// screen's subtree is handed differs with the screens it is built inside.
	private static func screensOpeningEachOtherWithoutLayers(screenCount: Int, additionalDeclarations: [Int: [String]] = [:]) -> [String] {
		(0..<screenCount).map { screen in
			var opened = [Int]()
			for other in [screen + 1, 2 * screen + 3, 3 * screen + 5].map({ $0 % screenCount }) where other != screen && !opened.contains(other) {
				opened.append(other)
			}
			let context = [["@Instantiated let context: Context"], ["@Received let context: Context"], ["@Received(onlyIfAvailable: true) let context: Context?"], []][screen % 4]
			return seamFixtureType(named: "Screen\(screen)", isFinalClass: true, declarations: context + additionalDeclarations[screen, default: []] + opened.map {
				"@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>"
			})
		}
	}

	/// What the paths to `Shared` declare `x` as: `Root` first, then each of `A` to `F`, which `Root` builds in that order.
	enum LabelAbove: CaseIterable {
		case parentsAlternateTypes
		case parentsDeclareOneTypeOrOtherOrNothing
		case rootDeclaresAndEveryOtherParentDeclaresAnotherType
		case rootDeclaresAnotherTypeThanEveryOtherParent

		var typesDeclared: (root: String?, parents: [String?]) {
			switch self {
			case .parentsAlternateTypes:
				(nil, ["X", "Y", "X", "Y", "X", "Y"])
			case .parentsDeclareOneTypeOrOtherOrNothing:
				(nil, [nil, "X", "Y", nil, "X", "Y"])
			case .rootDeclaresAndEveryOtherParentDeclaresAnotherType:
				("X", [nil, "Y", nil, "Y", nil, "Y"])
			case .rootDeclaresAnotherTypeThanEveryOtherParent:
				("Y", ["X", nil, "X", nil, "X", nil])
			}
		}
	}

	/// What `Shared`, and `Leaf` beneath it, do with `x`.
	enum LabelBeneath: CaseIterable {
		case sharedDeclaresAgain
		case leafReceives
		case leafReceivesOnlyIfAvailable
		case leafRenames
		case leafRenamesOnlyIfAvailable
		case sharedForwardsAndLeafReceives
		case sharedForwardsAndLeafReceivesOnlyIfAvailable
		case sharedDeclaresAgainAndLeafReceives

		var declarations: (shared: [String], leaf: [String]) {
			switch self {
			case .sharedDeclaresAgain:
				(["@Instantiated let x: X"], [])
			case .leafReceives:
				([], ["@Received let x: X"])
			case .leafReceivesOnlyIfAvailable:
				([], ["@Received(onlyIfAvailable: true) let x: X?"])
			case .leafRenames:
				([], ["@Received(fulfilledByDependencyNamed: \"x\", ofType: X.self) let renamed: X"])
			case .leafRenamesOnlyIfAvailable:
				([], ["@Received(fulfilledByDependencyNamed: \"x\", ofType: X.self, onlyIfAvailable: true) let renamed: X?"])
			case .sharedForwardsAndLeafReceives:
				(["@Forwarded let x: X"], ["@Received let x: X"])
			case .sharedForwardsAndLeafReceivesOnlyIfAvailable:
				(["@Forwarded let x: X"], ["@Received(onlyIfAvailable: true) let x: X?"])
			case .sharedDeclaresAgainAndLeafReceives:
				(["@Instantiated let x: X"], ["@Received let x: X"])
			}
		}
	}

	/// What `Shared`, and `Leaf` beneath it, do with `link`, the label of the builder each path to `Shared` builds an `A`
	/// for.
	enum BuilderLabelBeneath: CaseIterable {
		case sharedBuildsLeafForIt
		case sharedBuildsFirstParentForIt
		case leafReceivesFirstParentBuilder
		case leafReceivesFirstParentBuilderOnlyIfAvailable
		case leafRenamesFirstParentBuilder

		var declarations: (shared: [String], leaf: [String]) {
			switch self {
			case .sharedBuildsLeafForIt:
				(["@Instantiated let link: Instantiator<Leaf>"], [])
			case .sharedBuildsFirstParentForIt:
				(["@Instantiated let link: Instantiator<A0>", "@Instantiated let leafBuilder: Instantiator<Leaf>"], [])
			case .leafReceivesFirstParentBuilder:
				(["@Instantiated let leafBuilder: Instantiator<Leaf>"], ["@Received let link: Instantiator<A0>"])
			case .leafReceivesFirstParentBuilderOnlyIfAvailable:
				(["@Instantiated let leafBuilder: Instantiator<Leaf>"], ["@Received(onlyIfAvailable: true) let link: Instantiator<A0>?"])
			case .leafRenamesFirstParentBuilder:
				(["@Instantiated let leafBuilder: Instantiator<Leaf>"], ["@Received(fulfilledByDependencyNamed: \"link\", ofType: Instantiator<A0>.self) let renamed: Instantiator<A0>"])
			}
		}
	}

	/// `Root` builds `Middle0` to `Middle5` in that order; `Middle<i>` builds `A<i>` for a builder named `link`, or `other`
	/// on every other path where `everyOtherPathNamesItsBuilderApart`; every `A<i>` builds `Shared`.
	private static func sharedSubtreeBeneathBuildersOfOneLabel(everyOtherPathNamesItsBuilderApart: Bool, beneath: BuilderLabelBeneath) -> [String] {
		let (sharedDeclarations, leafDeclarations) = beneath.declarations
		return [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: (0..<6).map { "@Instantiated let middle\($0)Builder: Instantiator<Middle\($0)>" }),
		] + (0..<6).flatMap { index in
			[
				seamFixtureType(named: "Middle\(index)", isFinalClass: true, declarations: ["@Instantiated let \(everyOtherPathNamesItsBuilderApart && index % 2 == 1 ? "other" : "link"): Instantiator<A\(index)>"]),
				seamFixtureType(named: "A\(index)", isFinalClass: true, declarations: ["@Instantiated let sharedBuilder: Instantiator<Shared>"]),
			]
		} + [
			seamFixtureType(named: "Shared", isFinalClass: true, declarations: sharedDeclarations),
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: leafDeclarations),
		]
	}

	/// The subtrees the walk skips, the scopes it validates, and the first line of what it reports, for each graph of
	/// `sharedSubtreeBeneathBuildersOfOneLabel(everyOtherPathNamesItsBuilderApart:beneath:)`: of 25 scopes along every
	/// path, `Shared` and what it builds are validated beneath two parents where the others are skipped. Where `Shared` builds for
	/// `link` itself, it is skipped beneath `A2` to `A5`, and `A0`, built again beneath it, once more. Where `Leaf` reads
	/// `link` from above, the entry of each path's `link` is held: no walk is skipped but the two beneath paths that
	/// declare no `link`, after the first of them, where the receive is only if available; a required one is reported
	/// beneath `A1`, the first path that provides no builder of `A0`.
	private static func expectedOutcome(everyOtherPathNamesItsBuilderApart: Bool, beneath: BuilderLabelBeneath) -> (skippedSubtreeCount: Int, validatedScopeCount: Int, error: String?) {
		let unfulfillable = "Leaf.swift:7:5: error: @Received property `link: Instantiator<A0>` is not @Instantiated or @Forwarded in chain: Root -> Instantiator<Middle1> -> Instantiator<A1> -> Instantiator<Shared> -> Leaf. "
			+ (everyOtherPathNamesItsBuilderApart ? "Declare `@Instantiated let link: Instantiator<A0>` on `Root` or on another type in the chain to fix." : "Did you mean `link: Instantiator<A1>`?")
		return switch beneath {
		case .sharedBuildsLeafForIt:
			(4, 17, nil)
		case .sharedBuildsFirstParentForIt:
			(5, 15, nil)
		case .leafReceivesFirstParentBuilder, .leafRenamesFirstParentBuilder:
			(0, 25, unfulfillable)
		case .leafReceivesFirstParentBuilderOnlyIfAvailable:
			everyOtherPathNamesItsBuilderApart ? (2, 21, nil) : (0, 25, nil)
		}
	}

	/// `Shared`, which builds `Leaf`, beneath `A` to `F`, which `Root` builds in that order.
	private static func sharedSubtree(above: LabelAbove, beneath: LabelBeneath) -> [String] {
		let parentNames = ["A", "B", "C", "D", "E", "F"]
		let (rootType, parentTypes) = above.typesDeclared
		let (sharedDeclarations, leafDeclarations) = beneath.declarations
		return [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: (rootType.map { ["@Instantiated let x: \($0)"] } ?? []) + parentNames.map { "@Instantiated let \($0.lowercased())Builder: Instantiator<\($0)>" }),
		] + zip(parentNames, parentTypes).map { name, type in
			seamFixtureType(named: name, isFinalClass: true, declarations: (type.map { ["@Instantiated let x: \($0)"] } ?? []) + ["@Instantiated let sharedBuilder: Instantiator<Shared>"])
		} + [
			seamFixtureType(named: "Shared", isFinalClass: true, declarations: sharedDeclarations + ["@Instantiated let leafBuilder: Instantiator<Leaf>"]),
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: leafDeclarations),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
	}

	/// The subtrees the walk skips, and the first line of what it reports, for each graph of `sharedSubtree(above:beneath:)`.
	/// The counts are of every scope skipped: `Shared` and `Leaf` after a walk of an equal key that found nothing, and the
	/// constants `X` and `Y`, built on several paths. Where `Shared` only declares `x`, or forwards it to a `Leaf` that
	/// requires it, `Shared` is skipped beneath every parent after `B`, whatever the parent declares `x` as. Where `Leaf`
	/// reads `x` from above, the paths that lack `x: X` or hide it are never remembered, and the first of them is reported.
	private static func expectedOutcome(above: LabelAbove, beneath: LabelBeneath) -> (skippedSubtreeCount: Int, error: String?) {
		let skippedSubtreeCounts: [Int] = switch above {
		case .parentsAlternateTypes:
			[8, 3, 5, 3, 5, 6, 5, 8]
		case .parentsDeclareOneTypeOrOtherOrNothing:
			[6, 1, 2, 1, 2, 4, 3, 7]
		case .rootDeclaresAndEveryOtherParentDeclaresAnotherType:
			[6, 2, 2, 2, 2, 5, 4, 6]
		case .rootDeclaresAnotherTypeThanEveryOtherParent:
			[7, 2, 4, 2, 4, 5, 5, 8]
		}
		let readsFromAbove: (required: Bool, received: String)? = switch beneath {
		case .leafReceives, .leafRenames:
			(true, "x: X")
		case .leafReceivesOnlyIfAvailable:
			(false, "x: X?")
		case .leafRenamesOnlyIfAvailable:
			(false, "x: X")
		case .sharedDeclaresAgain, .sharedForwardsAndLeafReceives, .sharedForwardsAndLeafReceivesOnlyIfAvailable, .sharedDeclaresAgainAndLeafReceives:
			nil
		}
		let error: String? = readsFromAbove.flatMap { required, received in
			switch above {
			case .parentsAlternateTypes, .rootDeclaresAnotherTypeThanEveryOtherParent:
				required ? "Leaf.swift:7:5: error: @Received property `x: X` is not @Instantiated or @Forwarded in chain: Root -> Instantiator<B> -> Instantiator<Shared> -> Leaf. Did you mean `x: Y`?" : nil
			case .parentsDeclareOneTypeOrOtherOrNothing:
				required ? "Leaf.swift:7:5: error: @Received property `x: X` is not @Instantiated or @Forwarded in chain: Root -> Instantiator<A> -> Instantiator<Shared> -> Leaf. Declare `@Instantiated let x: X` on `Root` or on another type in the chain to fix." : nil
			case .rootDeclaresAndEveryOtherParentDeclaresAnotherType:
				"Leaf.swift:7:5: error: @Received property `\(received)` is hidden in chain: Root -> Instantiator<B> -> Instantiator<Shared> -> Leaf. `B` declares `x: Y` with the same label, so the types below `B` receive `x: Y` instead. Give `x: Y` on `B` a different label to fix."
			}
		}
		return (skippedSubtreeCounts[LabelBeneath.allCases.firstIndex(of: beneath) ?? 0], error)
	}

	/// The order each type of a graph declares its properties in: the walk takes a scope's children last first, so which
	/// path reaches a shared scope first follows it.
	enum DeclarationOrder: CaseIterable {
		case written
		case reversed
		case rootRotated
		case rootRotatedAndOthersReversed

		func ordered(_ declarations: [String], ofRoot isRoot: Bool) -> [String] {
			switch self {
			case .written:
				declarations
			case .reversed:
				declarations.reversed()
			case .rootRotated:
				isRoot ? Array(declarations.dropFirst() + declarations.prefix(1)) : declarations
			case .rootRotatedAndOthersReversed:
				isRoot ? Array(declarations.dropFirst() + declarations.prefix(1)) : declarations.reversed()
			}
		}
	}

	/// Graphs in which a type on a cycle of instantiators receives a property that the paths into the cycle declare
	/// differently.
	enum ReceiveInsideCycle: CaseIterable {
		/// `A` and `B` build each other; `B` receives `y: Y`. `One` and `Third` declare `y` and enter the cycle at `A` and at
		/// `B`; `Two` enters at `A` and declares nothing.
		case requiredAndOnePathDeclaresNothing
		/// The same, with `B` receiving `y` only if available: `nil` beneath `Two`.
		case onlyIfAvailableAndOnePathDeclaresNothing
		/// The same, with `B` renaming `y`.
		case renamedAndOnePathDeclaresNothing
		/// `A` and `B` build each other; `A` receives `x: X`, and `B` builds `C`, which forwards `x`. `Flow` and `Flow2`
		/// declare `x` and enter at `A`; `Middle` enters at `B` and declares nothing.
		case requiredBesideForwarderAndOnePathDeclaresNothing
		/// `A` and `B` build each other; `A` receives `x: X`, which `Root` declares. `P` and `Q` each declare `x: Y` and
		/// build, for one label, a type that enters the cycle at `B`: `N`, which declares `x: X` again, and `M`, which
		/// declares `x: Y`, which hides `Root`'s.
		case requiredAndOnePathHides
		/// The same, with `A` receiving `x` only if available.
		case onlyIfAvailableAndOnePathHides
		/// `Screen1`, `Screen3` and `Screen4` build each other, one through an erased instantiator; `Screen1` receives
		/// `y: X`, which `Root` declares. `Root` enters the cycle at `Screen1` and, through `Screen2`, at `Screen4`; `Screen0`
		/// declares `y: Y`, which hides `Root`'s, and enters through `Screen2` too.
		case requiredInsideCycleThroughErasedInstantiatorAndOnePathHides

		var isInvalid: Bool {
			switch self {
			case .requiredAndOnePathDeclaresNothing, .renamedAndOnePathDeclaresNothing, .requiredBesideForwarderAndOnePathDeclaresNothing, .requiredAndOnePathHides, .onlyIfAvailableAndOnePathHides, .requiredInsideCycleThroughErasedInstantiatorAndOnePathHides:
				true
			case .onlyIfAvailableAndOnePathDeclaresNothing:
				false
			}
		}

		private var types: [(name: String, declarations: [String])] {
			switch self {
			case .requiredAndOnePathDeclaresNothing, .onlyIfAvailableAndOnePathDeclaresNothing, .renamedAndOnePathDeclaresNothing:
				let receive = switch self {
				case .onlyIfAvailableAndOnePathDeclaresNothing:
					"@Received(onlyIfAvailable: true) let y: Y?"
				case .renamedAndOnePathDeclaresNothing:
					"@Received(fulfilledByDependencyNamed: \"y\", ofType: Y.self) let renamed: Y"
				case .requiredAndOnePathDeclaresNothing, .requiredBesideForwarderAndOnePathDeclaresNothing, .requiredAndOnePathHides, .onlyIfAvailableAndOnePathHides, .requiredInsideCycleThroughErasedInstantiatorAndOnePathHides:
					"@Received let y: Y"
				}
				return [
					("Root", ["@Instantiated let one: Instantiator<One>", "@Instantiated let two: Instantiator<Two>", "@Instantiated let third: Instantiator<Third>"]),
					("One", ["@Instantiated let y: Y", "@Instantiated let aBuilder: Instantiator<A>"]),
					("Two", ["@Instantiated let aBuilder: Instantiator<A>"]),
					("Third", ["@Instantiated let y: Y", "@Instantiated let bBuilder: Instantiator<B>"]),
					("A", ["@Instantiated let bBuilder: Instantiator<B>"]),
					("B", [receive, "@Instantiated let aBuilder: Instantiator<A>"]),
					("Y", []),
				]
			case .requiredBesideForwarderAndOnePathDeclaresNothing:
				return [
					("Root", ["@Instantiated let flow: Flow", "@Instantiated let middle: Middle", "@Instantiated let flow2: Flow2"]),
					("Flow", ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"]),
					("Flow2", ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"]),
					("Middle", ["@Instantiated let bBuilder: Instantiator<B>"]),
					("A", ["@Received let x: X", "@Instantiated let bBuilder: Instantiator<B>"]),
					("B", ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let cBuilder: Instantiator<C>"]),
					("C", ["@Forwarded let x: X"]),
					("X", []),
				]
			case .requiredAndOnePathHides, .onlyIfAvailableAndOnePathHides:
				return [
					("Root", ["@Instantiated let x: X", "@Instantiated let p: P", "@Instantiated let q: Q", "@Instantiated let aBuilder: Instantiator<A>"]),
					("P", ["@Instantiated let x: Y", "@Instantiated let link: N"]),
					("Q", ["@Instantiated let link: M"]),
					("N", ["@Instantiated let x: X", "@Instantiated let bBuilder: Instantiator<B>"]),
					("M", ["@Instantiated let x: Y", "@Instantiated let bBuilder: Instantiator<B>"]),
					("A", [self == .requiredAndOnePathHides ? "@Received let x: X" : "@Received(onlyIfAvailable: true) let x: X?", "@Instantiated let link: Leaf", "@Instantiated let bBuilder: Instantiator<B>"]),
					("B", ["@Instantiated let aBuilder: Instantiator<A>"]),
					("Leaf", []),
					("X", []),
					("Y", []),
				]
			case .requiredInsideCycleThroughErasedInstantiatorAndOnePathHides:
				return [
					("Root", ["@Instantiated let y: X", "@Instantiated(fulfilledByType: \"Screen2\", erasedToConcreteExistential: true) let root2: ErasedInstantiator<(), AnyScreen>", "@Instantiated let root0: Instantiator<Screen0>", "@Instantiated let root1: Instantiator<Screen1>"]),
					("Screen0", ["@Instantiated let y: Y", "@Instantiated let builder0: Instantiator<Screen2>"]),
					("Screen1", ["@Instantiated(fulfilledByType: \"Screen3\", erasedToConcreteExistential: true) let builder0: ErasedInstantiator<(), AnyScreen>", "@Received let y: X"]),
					("Screen2", ["@Instantiated let builder0: Instantiator<Screen4>"]),
					("Screen3", ["@Instantiated let builder0: Instantiator<Screen4>"]),
					("Screen4", ["@Instantiated let builder1: Instantiator<Screen1>"]),
					("X", []),
					("Y", []),
				]
			}
		}

		func fixture(order: DeclarationOrder) -> [String] {
			types.map { name, declarations in
				seamFixtureType(named: name, isRoot: name == "Root", isFinalClass: true, declarations: order.ordered(declarations, ofRoot: name == "Root"))
			} + [
				"""
				public final class AnyScreen {
				    public init(_ screen: AnyObject) {
				        self.screen = screen
				    }

				    public let screen: AnyObject
				}
				""",
			]
		}
	}

	private static let ringDrawSeedCount: UInt64 = 200

	/// The graph of `seed`: two to four `Ring` types that each build the next through an `Instantiator`, now and then with
	/// one more builder across the ring. One drawn type of the ring receives `mark` (required, only if available, or
	/// renamed); each other now and then receives it too, declares it, or builds a leaf that forwards or receives it. One
	/// to three roots, which may declare `mark`, each build one to three entries by value or through an `Instantiator`; an
	/// entry declares `mark`, declares it with another type, or declares nothing, and builds one type of the ring. A root
	/// may build a type of the ring itself. Each type's declarations and the files are shuffled.
	private static func ringOfBuildersWithReceiveInside(seed: UInt64) -> [String] {
		var random = GraphFuzzerRandomNumberGenerator(seed: seed ^ 0x52696E6752656376)
		func shuffled<Element>(_ elements: [Element]) -> [Element] {
			var elements = elements
			for index in elements.indices.dropLast() {
				elements.swapAt(index, random.integer(in: index...elements.count - 1))
			}
			return elements
		}
		let receives = [
			"@Received let mark: Mark",
			"@Received(onlyIfAvailable: true) let mark: Mark?",
			"@Received(fulfilledByDependencyNamed: \"mark\", ofType: Mark.self) let renamedMark: Mark",
		]
		let ringCount = random.integer(in: 2...4)
		let receiverIndex = random.integer(in: 0...ringCount - 1)
		func ringBuilder(_ index: Int) -> String {
			"@Instantiated let ring\(index)Builder: Instantiator<Ring\(index)>"
		}
		var types = [(name: String, isRoot: Bool, declarations: [String])]()
		for index in 0..<ringCount {
			var declarations = [ringBuilder((index + 1) % ringCount)]
			if ringCount > 2, random.percentChance(25) {
				declarations.append(ringBuilder((index + 2) % ringCount))
			}
			if index == receiverIndex {
				declarations.append(random.element(of: receives))
			} else {
				switch random.integer(in: 0...9) {
				case 0:
					declarations.append(random.element(of: receives))
				case 1:
					declarations.append("@Instantiated let mark: Mark")
				case 2:
					declarations.append("@Instantiated let forwarderBuilder: Instantiator<Forwarder>")
				case 3:
					declarations.append("@Instantiated let leaf: Leaf")
				default:
					break
				}
			}
			types.append(("Ring\(index)", false, declarations))
		}
		var entryCount = 0
		for rootIndex in 0..<random.integer(in: 1...3) {
			var rootDeclarations = [String]()
			if random.percentChance(50) {
				rootDeclarations.append("@Instantiated let mark: Mark")
			}
			if random.percentChance(30) {
				rootDeclarations.append(ringBuilder(random.integer(in: 0...ringCount - 1)))
			}
			for _ in 0..<random.integer(in: 1...3) {
				var entryDeclarations = [ringBuilder(random.integer(in: 0...ringCount - 1))]
				switch random.integer(in: 0...9) {
				case 0...4:
					entryDeclarations.append("@Instantiated let mark: Mark")
				case 5:
					entryDeclarations.append("@Instantiated let mark: OtherMark")
				default:
					break
				}
				types.append(("Entry\(entryCount)", false, entryDeclarations))
				rootDeclarations.append(random.percentChance(50)
					? "@Instantiated let entry\(entryCount): Entry\(entryCount)"
					: "@Instantiated let entry\(entryCount)Builder: Instantiator<Entry\(entryCount)>")
				entryCount += 1
			}
			types.append(("Root\(rootIndex)", true, rootDeclarations))
		}
		types += [
			("Forwarder", false, ["@Forwarded let mark: Mark"]),
			("Leaf", false, ["@Received let mark: Mark"]),
			("Mark", false, []),
			("OtherMark", false, []),
		]
		return shuffled(types).map { name, isRoot, declarations in
			seamFixtureType(named: name, isRoot: isRoot, isFinalClass: true, declarations: shuffled(declarations))
		}
	}

	/// Graphs that each need one part of the key (`CleanSubtreeKey`, `cleanSubtreeKeyLabels(of:)`) or of the bookkeeping
	/// of subtrees found clean beneath a scope still being walked.
	enum GraphForKeyPart: CaseIterable {
		/// A label that only one non-optional property is received under beneath a scope still keeps its receivable
		/// properties in the key while a type beneath reads it from above the scope. `Screen` receives `b: Screen`, which
		/// nothing declares, and is reached beneath `Direct` and, through a cycle of builders, beneath `Loop`: each path
		/// reports the receive. With the label left out as "fulfilled beneath", the path through `Loop` is skipped.
		case labelReadFromAboveKeepsItsReceivableProperties
		/// The key holds the root's context: which checks its walk runs. `MockedFlow`'s mock is a root of its own, whose walk
		/// reports that `Hider`'s `f0: Shadow` hides the `f0: Value?` that `MockedLeaf` receives only if available; the walk
		/// of `Root`, which reaches the same types first, does not judge that. With one context for every root, the
		/// subtree found clean beneath `Root` is skipped beneath the mock and the error is lost.
		case rootContext
		/// A subtree skipped because it was found clean beneath a scope still being walked hands that scope's depth up, so
		/// that what is above it is kept only once that scope's walk completes clean. `Leaf` receives `x: Value?`, which
		/// nothing declares, beneath `D`, which the cycles through `A`, `B` and `C` reach along four paths. With the depth
		/// not handed up, a path is skipped and its diagnostic is lost.
		case pendingSubtreeHandsItsDepthUp

		/// The number of errors the walk reports.
		var errorCount: Int {
			switch self {
			case .labelReadFromAboveKeepsItsReceivableProperties: 2
			case .rootContext: 1
			case .pendingSubtreeHandsItsDepthUp: 4
			}
		}

		private var types: [(name: String, arguments: String, declarations: [String])] {
			switch self {
			case .labelReadFromAboveKeepsItsReceivableProperties:
				[
					("Root", "(isRoot: true)", ["@Instantiated let c: Direct", "@Instantiated let a: Instantiator<Loop>"]),
					("Loop", "", ["@Instantiated let c: Instantiator<Screen>"]),
					("Direct", "", ["@Instantiated let a: Screen"]),
					("Screen", "", ["@Received let b: Screen", "@Instantiated let a: Instantiator<Loop>"]),
				]
			case .rootContext:
				[
					("Root", "(isRoot: true)", ["@Instantiated let child3: Instantiator<Entry>"]),
					("Entry", "", ["@Instantiated let child3: Instantiator<MockedFlow>"]),
					("MockedFlow", "(generateMock: true)", ["@Instantiated let child3: Step"]),
					("Step", "", ["@Instantiated let child3: Instantiator<Fork>"]),
					("Fork", "", ["@Instantiated let child3: Plain", "@Instantiated let child2: Instantiator<Hider>"]),
					("Plain", "", ["@Instantiated let child3: Instantiator<MockedLeaf>"]),
					("Hider", "", ["@Instantiated let child1: MockedLeaf", "@Instantiated let f0: Shadow"]),
					("MockedLeaf", "(generateMock: true)", ["@Received(onlyIfAvailable: true) let f0: Value?"]),
					("Shadow", "", []),
					("Value", "", []),
				]
			case .pendingSubtreeHandsItsDepthUp:
				[
					("Root", "(isRoot: true)", ["@Instantiated let r2: Instantiator<C>", "@Instantiated let r3: Instantiator<D>"]),
					("A", "", ["@Instantiated let b1: Instantiator<B>"]),
					("B", "", ["@Instantiated let b3: Instantiator<C>", "@Instantiated let b2: Instantiator<A>"]),
					("C", "", ["@Instantiated let b2: Instantiator<D>"]),
					("D", "", ["@Instantiated let b0: Instantiator<B>", "@Instantiated let b2: Instantiator<Leaf>"]),
					("Leaf", "", ["@Received let x: Value?"]),
					("Value", "", []),
				]
			}
		}

		func fixture(order: DeclarationOrder) -> [String] {
			types.map { name, arguments, declarations in
				let ordered = order.ordered(declarations, ofRoot: name == "Root")
				let properties = ordered.map { declaration -> (label: String, type: String) in
					let property = declaration[declaration.range(of: " let ")!.upperBound...]
					return (String(property.prefix { $0 != ":" }), property.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces))
				}
				return """
				@Instantiable\(arguments)
				public final class \(name): Instantiable {
				    public init(\(properties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {
				\(properties.map { "        self.\($0.label) = \($0.label)" }.joined(separator: "\n"))
				    }

				\(ordered.map { "    \($0)" }.joined(separator: "\n"))
				}
				"""
			}
		}
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
