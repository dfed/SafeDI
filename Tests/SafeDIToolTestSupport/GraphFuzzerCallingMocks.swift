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
import SwiftParser
import SwiftSyntax
import Testing

// MARK: - Cells

/// The shape a calling-mock draw gives its graph: a calling mock is a generated `mock()` whose tree calls another
/// module's public mock, and each shape puts a place of that public mock's hole where production fills it from a value of
/// the calling tree or from a parameter, or, for the control, where its module sees no type that fills it.
enum GraphFuzzerCallingMockShape: String, CaseIterable, Comparable {
	/// The fill of an inner seam's hole receives a value the outer seam builds: production rejects it.
	case outerSeamValue
	/// An app-only screen in a loop of screens the seam declares: production rejects it.
	case appOnlyScreenInLoop
	/// A seam whose tree builds the seam again, with a fill that reads a value of the level in between: production rejects
	/// it.
	case seamBuiltAgain
	/// A seam holds a builder of an inner seam and a sibling that receives that builder, and the fill of the inner seam's
	/// hole receives the sibling: production rejects the loop.
	case loopThroughInnerSeamBuilder
	/// The fill receives a value the calling type itself builds: production fills the place.
	case callersOwnValue
	/// Control: no type that fulfills the hole is visible from the calling mock's module.
	case noVisibleImplementation
	/// The visible implementation receives a value nothing in the calling tree builds, which production takes as a
	/// parameter and fills the place from: the calling mock passes the place up, which no permanent reason explains (the
	/// reason that once did is withdrawn).
	case implementationReceivesWhatNothingProvides
	/// The fill receives the caller's own value whose tree calls the seam, which is still being built there: production
	/// reports the dependency cycle. Drawn with a plain place only: a deferred place's builder closes the cycle through an
	/// instantiator, which production accepts.
	case fillReceivesValueBuildingTheCall
	/// The visible implementation's tree instantiates types no declaration the calling mock's module sees fulfills:
	/// production fills the place and takes a builder for each of those types' hole types, which each type that instantiates
	/// one calls once per build. The draw varies whether the implementation is a seam (whose holes those types are) or a
	/// plain type, whether the called type is a seam as well as a public mock, whether the types are instantiated by the
	/// implementation or one level beneath it, inside a `@Sendable` function or not, as a plain value or an erased
	/// instantiator, and one or two places of one or two hole types (`FillHoles`).
	case fillInstantiatesWhatNothingFulfills
	/// As `fillInstantiatesWhatNothingFulfills`, with the implementation's tree also instantiating, with no declaration
	/// fulfilling it, a type spelled as no hole can be (`FillHoles.spellingNoHoleCanHave`: an array, a dictionary, a closure
	/// or a tuple): production reports that no declaration fulfills it, so the calling mock reports the same error.
	case fillInstantiatesTypeNoDeclarationCanFulfill
	/// As `fillInstantiatesWhatNothingFulfills`, with the caller a seam that generates its internal mock
	/// (`generateDependencyTree: true, generateMock: true`) and instantiates, itself, a place of each hole type the fill
	/// instantiates: the seam's own mock takes one builder for its own places and the fill's of one hole type and family,
	/// as its twin's initializer does.
	case seamCallerFillSharesBuilder
	/// As `fillInstantiatesTypeNoDeclarationCanFulfill`, in a build of the calling mock's module that does not tell the tool
	/// the mock condition is active (`GraphFuzzerCallingMockGraph.MockBuild`): a release build, which compiles no generated
	/// mock, or a debug build whose integration does not report `DEBUG`, which compiles the mock the tool generates. The tool
	/// checks the fill production rejects only where the build compiles the generated mocks, so where the implementation is
	/// a plain type the calling mock is accepted and passes the place up, where its twin reports the error; where it is a
	/// seam, the seam's own tree, which every build generates, reports the error in the mock's module too.
	case fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive
	/// The fill receives a value the calling type builds that, in the called type's tree, only a call of a third module's
	/// public mock requires, which builds it when passed `nil` (`Value`'s `Inner`, whose internal initializer the called
	/// type's module cannot call), beside a type that receives it only if available: the called type's public mock takes the
	/// value as `T? = nil` and binds the `T` it is passed or builds, and production, whose seam requires the value, fills
	/// the place.
	case fillReceivesValueOnlyInnerMockRequires
	/// The called type receives a value the caller builds and builds the place inside a `@Sendable` function, `Part`'s
	/// held in a `SendableInstantiator`; the fill receives that value: production fills the place from the caller's value,
	/// which the seam takes as a parameter, and the called mock binds at its root the value the calling mock passes it.
	case calledTypesReceivedValueInSendablePlace
	/// The called type's place is a level below its root, beneath a type the caller's module cannot build, and its fill
	/// receives the caller's own value in a lazy wrapper, `LazilyInstantiated` or `SendableLazilyInstantiated`, while another
	/// type of the called type's tree receives that value by value, or only if available (`CallerLazyValue`): production
	/// fills the place, handing the fill the wrapper the caller holds, so the calling mock must too, which its values,
	/// compared with the same types built inline, show. The called type is called by the caller, by a mocked intermediate
	/// type the caller instantiates, or by the caller with the fill calling it again (`CallerLazyValue.Call`).
	case fillReceivesCallersLazyValueBelowCalledRoot
	/// The fill builds a type of a third module whose public mock holds a builder of the enclosing called type, the one
	/// whose place the fill fills (`EnclosingBuilder`): the call inside the fill re-enters the enclosing call's root level
	/// function, as production's call re-enters the enclosing seam call's, and production fills the place.
	case fillHoldsBuilderOfEnclosingCalledType
	/// The called type's tree receives the caller's value only if available in a lazy wrapper, `LazilyInstantiated` or
	/// `SendableLazilyInstantiated`, the called type itself, a type it instantiates, or both (`OptionalWrapperValue`), and the fill
	/// requires its instance, by value, where the fill may also build the called type again: production's seam would take
	/// the label in two forms and reports it, so the calling mock reports at the same sites, rather than hand the fill the
	/// called mock's optional wrapper.
	case fillRequiresValueCalledTypeReceivesInOptionalWrapper
	/// As `callersOwnValue`, with the fill's hand-written mock, under `#if DEBUG`, taking a value the fill declares only
	/// inside an `#if` clause the build does not select (`GraphFuzzerCallingMockDraw.guardedValueCondition`), in a build of
	/// the calling mock's module that does not tell the tool the mock condition is active
	/// (`GraphFuzzerCallingMockGraph.MockBuild`). The tool reports such a parameter only where the generated mocks compile,
	/// so the calling mock is accepted and fills the place with a call of that mock, as production fills it with the
	/// fill's initializer; no build compiles that call.
	case fillCallsMockTakingGuardedValueWhereMockConditionIsInactive
	/// As `callersOwnValue`, with the fill's tree also instantiating a protocol only a type of the outer module fulfills,
	/// whose declaration the calling mock's module cannot reach: `internal`, where that module is in the caller's package,
	/// or `package`, where it is in another (`GraphFuzzerCallingMockDraw.UnreachableConstruction`). Production reports the
	/// access error, so the calling mock reports it at the same declarations in a build that compiles the generated mocks;
	/// a build that leaves the mock condition inactive never compiles the fill, so there the mock is accepted and passes the
	/// place up. In some graphs only the type's hand-written mock is out of reach: production, which calls the initializer,
	/// is accepted, and the calling mock, whose fill calls the mock, reports that mock's access instead (contract rule 7).
	case fillConstructsTypeCallerModuleCannotReach
	/// As `callersOwnValue`, with the called type, or `Gauge` beneath it, also receiving a value only if available that
	/// nothing in the calling tree provides (`GraphFuzzerCallingMockDraw.ValueNothingProvides`): production's seam takes it as
	/// a parameter, which it hands the called type, and the calling mock takes it too, an internal or listed one as an
	/// override, a `.public` one as a parameter, and passes it to the call, so a probe that hands it a value builds the
	/// twin's values.
	case calledTypeReceivesValueOnlyIfAvailableNothingProvides
	/// As `callersOwnValue`, with the called type holding its place in a lazy wrapper, `LazilyInstantiated` or
	/// `SendableLazilyInstantiated`, alone or beside a place of the hole by value (`GraphFuzzerCallingMockDraw.LazyPlace`):
	/// production fills the place, which the wrapper builds on first read, from the caller's value, and so must the calling
	/// mock. Drawn with a plain place only: a deferred place is an `ErasedInstantiator`, which no lazy wrapper holds.
	case calledTypeHoldsPlaceLazily
	/// As `callersOwnValue`, with the called type also holding a place of a second hole type
	/// (`GraphFuzzerCallingMockDraw.SecondHole`), before or after the first, whose fill in the caller's module reads the
	/// caller's value or nothing, or which no type the caller's module sees fulfills: production fills each place a visible
	/// type fulfills and takes a builder for the other, and so must the calling mock, which passes up exactly that builder.
	case calledTypeHoldsSecondHoleType
	/// As `callersOwnValue`, with the caller forwarding the value the fill reads rather than instantiating it
	/// (`GraphFuzzerCallingMockDraw.ForwardedValue`), now and then beside a value it instantiates: production's seam takes
	/// the forwarded value and fills the place from it, and the calling mock takes it as a parameter of `mock()` and must
	/// fill the place from it too.
	case callerForwardsValueFillReads
	/// As `callersOwnValue` or the control, with the called type instantiating its place only if available
	/// (`@Instantiated(onlyIfAvailable: true) let p: (any P)?`, `GraphFuzzerCallingMockDraw.OptionalPlace`): where the
	/// caller's module declares a type that fulfills the place, production's seam fills it and so must the calling mock,
	/// and where it declares none, both take the place's optional builder, which the twin's probe hands `{ nil }` and the
	/// mock defaults to it, so both hold `nil`.
	case placeInstantiatedOnlyIfAvailable

	static func < (lhs: Self, rhs: Self) -> Bool {
		allCases.firstIndex(of: lhs) ?? 0 < allCases.firstIndex(of: rhs) ?? 0
	}

	/// Whether production rejects the shape with an error of its own, which the calling mock must report too.
	var twinRejects: Bool {
		switch self {
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .fillReceivesValueBuildingTheCall, .fillInstantiatesTypeNoDeclarationCanFulfill, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive, .fillRequiresValueCalledTypeReceivesInOptionalWrapper, .fillConstructsTypeCallerModuleCannotReach:
			true
		case .callersOwnValue, .placeInstantiatedOnlyIfAvailable, .calledTypeHoldsPlaceLazily, .calledTypeHoldsSecondHoleType, .callerForwardsValueFillReads, .calledTypeReceivesValueOnlyIfAvailableNothingProvides, .noVisibleImplementation, .implementationReceivesWhatNothingProvides, .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot, .fillHoldsBuilderOfEnclosingCalledType, .fillCallsMockTakingGuardedValueWhereMockConditionIsInactive:
			false
		}
	}

	/// Whether the calling mock's values are compared with those of the same types built inline even where the twin is
	/// accepted: where the fill holds the caller's lazy wrapper, which value inline hands it is what the mock must build.
	var comparesValuesWithInline: Bool {
		switch self {
		case .fillReceivesCallersLazyValueBelowCalledRoot:
			true
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .placeInstantiatedOnlyIfAvailable, .calledTypeHoldsPlaceLazily, .calledTypeHoldsSecondHoleType, .callerForwardsValueFillReads, .calledTypeReceivesValueOnlyIfAvailableNothingProvides, .noVisibleImplementation, .implementationReceivesWhatNothingProvides, .fillReceivesValueBuildingTheCall, .fillInstantiatesWhatNothingFulfills, .fillInstantiatesTypeNoDeclarationCanFulfill, .seamCallerFillSharesBuilder, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillHoldsBuilderOfEnclosingCalledType, .fillRequiresValueCalledTypeReceivesInOptionalWrapper, .fillCallsMockTakingGuardedValueWhereMockConditionIsInactive, .fillConstructsTypeCallerModuleCannotReach:
			false
		}
	}

	/// Whether the calling mock's pass-ups must be exactly the graph's `expectedPassUpLabels`: the control's hole builder,
	/// the builders of what the fill instantiates that nothing fulfills, which are the twin's, and the place whose fill the
	/// tool does not check where the mock condition is inactive.
	var passesUpExactlyTheExpectedLabels: Bool {
		switch self {
		case .noVisibleImplementation, .placeInstantiatedOnlyIfAvailable, .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive, .fillCallsMockTakingGuardedValueWhereMockConditionIsInactive, .fillConstructsTypeCallerModuleCannotReach:
			true
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .calledTypeHoldsPlaceLazily, .calledTypeHoldsSecondHoleType, .callerForwardsValueFillReads, .calledTypeReceivesValueOnlyIfAvailableNothingProvides, .implementationReceivesWhatNothingProvides, .fillReceivesValueBuildingTheCall, .fillInstantiatesTypeNoDeclarationCanFulfill, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot, .fillHoldsBuilderOfEnclosingCalledType, .fillRequiresValueCalledTypeReceivesInOptionalWrapper:
			false
		}
	}

	var isControl: Bool {
		switch self {
		case .noVisibleImplementation:
			true
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .placeInstantiatedOnlyIfAvailable, .calledTypeHoldsPlaceLazily, .calledTypeHoldsSecondHoleType, .callerForwardsValueFillReads, .calledTypeReceivesValueOnlyIfAvailableNothingProvides, .implementationReceivesWhatNothingProvides, .fillReceivesValueBuildingTheCall, .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder, .fillInstantiatesTypeNoDeclarationCanFulfill, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot, .fillHoldsBuilderOfEnclosingCalledType, .fillRequiresValueCalledTypeReceivesInOptionalWrapper, .fillCallsMockTakingGuardedValueWhereMockConditionIsInactive, .fillConstructsTypeCallerModuleCannotReach:
			false
		}
	}
}

/// One cell of the calling-mock draw: a shape, with an internal, a `.public` or a listed calling mock, and a plain place
/// (`let api: any Api`) or a deferred one (an `ErasedInstantiator` whose fill forwards a value). The app-only screen's
/// loop closes only through builders, so there its plain place is the canonical one, a builder that forwards nothing
/// (`ErasedInstantiator<(), any SettingsPage>`).
struct GraphFuzzerCallingMockCell: Hashable, Comparable, CustomStringConvertible {
	enum Place: String, CaseIterable {
		case plain
		/// An `ErasedInstantiator<Int, any P>`: the forwarded variant of a deferred place, whose fill forwards `id: Int`.
		case deferred
	}

	/// How the caller's module asks for the calling mock.
	enum Caller: String, CaseIterable {
		/// `@Instantiable(generateMock: true)`.
		case `internal`
		/// `@Instantiable(generateMock: .public)`.
		case `public`
		/// A plain `@Instantiable` the caller's module lists in `additionalMocksToGenerate`, whose generated `mock()` is
		/// internal.
		case listed
	}

	let shape: GraphFuzzerCallingMockShape
	let caller: Caller
	let place: Place

	var callerIsPublic: Bool {
		caller == .public
	}

	static func < (lhs: Self, rhs: Self) -> Bool {
		let callerIndex = { (cell: Self) in Caller.allCases.firstIndex(of: cell.caller) ?? 0 }
		return (lhs.shape, callerIndex(lhs), lhs.place.rawValue) < (rhs.shape, callerIndex(rhs), rhs.place.rawValue)
	}

	var description: String {
		"\(shape.rawValue)/\(caller.rawValue)/\(place.rawValue)"
	}

	/// The cells of `shapes`, `callers` and `places`, shape by shape.
	private static func cells(of shapes: [GraphFuzzerCallingMockShape], callers: [Caller], places: [Place] = Place.allCases) -> [Self] {
		shapes.flatMap { shape in
			callers.flatMap { caller in
				places.map { Self(shape: shape, caller: caller, place: $0) }
			}
		}
	}

	/// The shapes drawn before the listed callers' block.
	private static let firstShapes: [GraphFuzzerCallingMockShape] = [.outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .noVisibleImplementation, .implementationReceivesWhatNothingProvides]

	/// The draw's blocks of cells, each drawn `graphsPerCell` times in a range of seeds of its own after the blocks before
	/// it, so a block added later draws no earlier seed anew: the internal and `.public` callers' cells; the listed
	/// callers'; the fill that receives the value building the call, for every caller, with a plain place; the fill that
	/// instantiates what nothing fulfills; the fill that instantiates a type no declaration can fulfill; the seam caller;
	/// that fill again where the mock condition is inactive, for every caller; the fill that receives the value only an
	/// inner public mock requires, for every caller; the place inside a `@Sendable` function whose fill reads the called
	/// type's received value, for every caller and place; the fill that receives the caller's lazy value below the called
	/// type's root, for every caller; the fill that holds a builder of the enclosing called type, for every caller and
	/// place; the fill that requires a value the called type receives only if available in a lazy wrapper, for every
	/// caller and place; the fill whose hand-written mock takes a value only an inactive clause declares, where the mock
	/// condition is inactive, for every caller and place; the fill whose tree constructs a type the caller's module cannot
	/// reach, for every caller and place; the called type that receives only if available a value nothing in the calling
	/// tree provides, for every caller and place; the called type that holds its place lazily, for every caller, with a
	/// plain place; the called type that holds a place of a second hole type, for every caller and place; the caller that
	/// forwards the value its fill reads, for every caller and place; and the called type that instantiates its place only
	/// if available, for every caller, with a plain place.
	static let blocks: [[Self]] = [
		cells(of: firstShapes, callers: [.internal, .public]),
		cells(of: firstShapes, callers: [.listed]),
		cells(of: [.fillReceivesValueBuildingTheCall], callers: Caller.allCases, places: [.plain]),
		cells(of: [.fillInstantiatesWhatNothingFulfills], callers: [.internal, .public]),
		cells(of: [.fillInstantiatesTypeNoDeclarationCanFulfill], callers: [.internal, .public]),
		cells(of: [.seamCallerFillSharesBuilder], callers: [.internal]),
		cells(of: [.fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive], callers: Caller.allCases),
		cells(of: [.fillReceivesValueOnlyInnerMockRequires], callers: Caller.allCases),
		cells(of: [.calledTypesReceivedValueInSendablePlace], callers: Caller.allCases),
		cells(of: [.fillReceivesCallersLazyValueBelowCalledRoot], callers: Caller.allCases),
		cells(of: [.fillHoldsBuilderOfEnclosingCalledType], callers: Caller.allCases),
		cells(of: [.fillRequiresValueCalledTypeReceivesInOptionalWrapper], callers: Caller.allCases),
		cells(of: [.fillCallsMockTakingGuardedValueWhereMockConditionIsInactive], callers: Caller.allCases),
		cells(of: [.fillConstructsTypeCallerModuleCannotReach], callers: Caller.allCases),
		cells(of: [.calledTypeReceivesValueOnlyIfAvailableNothingProvides], callers: Caller.allCases),
		cells(of: [.calledTypeHoldsPlaceLazily], callers: Caller.allCases, places: [.plain]),
		cells(of: [.calledTypeHoldsSecondHoleType], callers: Caller.allCases),
		cells(of: [.callerForwardsValueFillReads], callers: Caller.allCases),
		cells(of: [.placeInstantiatedOnlyIfAvailable], callers: Caller.allCases, places: [.plain]),
	]

	/// Every cell, block by block.
	static let all: [Self] = blocks.flatMap(\.self)

	/// The cells the draw fills, in order.
	static let drawnCells = all

	/// The graphs the corpus draws of each cell.
	static let graphsPerCell = 10

	/// The cell seed `seed` draws: in its block's range of seeds, `block[(seed - start) % block.count]`, so each block's
	/// first `block.count` seeds draw each of its cells once. A seed past the corpus wraps around it.
	static func cell(ofSeed seed: UInt64) -> Self {
		var offset = Int(seed % UInt64(all.count * graphsPerCell))
		for block in blocks {
			guard offset >= block.count * graphsPerCell else { return block[offset % block.count] }
			offset -= block.count * graphsPerCell
		}
		return all[offset % all.count]
	}

	/// Which of its cell's graphs `seed` draws, from 0 to `graphsPerCell - 1`.
	static func graphIndexInCell(ofSeed seed: UInt64) -> Int {
		var offset = Int(seed % UInt64(all.count * graphsPerCell))
		for block in blocks {
			guard offset >= block.count * graphsPerCell else { return offset / block.count }
			offset -= block.count * graphsPerCell
		}
		return offset / all.count
	}

	/// The first seed that draws each cell, in the order of `all`.
	static let firstSeeds: [UInt64] = {
		var seeds = [UInt64]()
		var start = 0
		for block in blocks {
			seeds += (start..<(start + block.count)).map { UInt64($0) }
			start += block.count * graphsPerCell
		}
		return seeds
	}()
}

// MARK: - Draw

/// A calling-mock graph: its modules as the calling mock's module declares the caller with `generateMock:` and as its
/// production twin declares it with `generateDependencyTree: true` in its place, and the draw's facts that classify what
/// the calling mock passes up. Drawn from a stream of its own, so no other corpus graph changes.
struct GraphFuzzerCallingMockDraw {
	init(seed: UInt64) {
		self.init(seed: seed, cell: GraphFuzzerCallingMockCell.cell(ofSeed: seed))
	}

	init(seed: UInt64, cell: GraphFuzzerCallingMockCell) {
		self.seed = seed
		self.cell = cell
		var random = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.callingMockRandomSeedMask)
		names = Names(random: &random)
		tickerPosition = random.element(of: TickerPosition.allCases)
		// Drawn after every other value, and only for its shape, so the other cells' graphs are drawn as before.
		fillHoles = switch cell.shape {
		case .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder:
			FillHoles(random: &random, drawsSpellingNoHoleCanHave: false)
		case .fillInstantiatesTypeNoDeclarationCanFulfill, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive:
			FillHoles(random: &random, drawsSpellingNoHoleCanHave: true)
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .placeInstantiatedOnlyIfAvailable, .calledTypeHoldsPlaceLazily, .calledTypeHoldsSecondHoleType, .callerForwardsValueFillReads, .calledTypeReceivesValueOnlyIfAvailableNothingProvides, .noVisibleImplementation, .implementationReceivesWhatNothingProvides, .fillReceivesValueBuildingTheCall, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot, .fillHoldsBuilderOfEnclosingCalledType, .fillRequiresValueCalledTypeReceivesInOptionalWrapper, .fillCallsMockTakingGuardedValueWhereMockConditionIsInactive, .fillConstructsTypeCallerModuleCannotReach:
			nil
		}
		// Drawn after the fill's holes, and only for the shapes drawn where the mock condition is inactive, and for the fill
		// whose tree constructs a type the caller's module cannot reach: in half its graphs a build that compiles the
		// generated mocks, whose mock reports the twin's error, and in the others one that leaves the mock condition inactive.
		mockBuild = switch cell.shape {
		case .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive, .fillCallsMockTakingGuardedValueWhereMockConditionIsInactive:
			random.element(of: [.debugWithoutMockCondition, .release])
		case .fillConstructsTypeCallerModuleCannotReach:
			random.element(of: [false, true]) ? .compilesGeneratedMocks : random.element(of: [.debugWithoutMockCondition, .release])
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .placeInstantiatedOnlyIfAvailable, .calledTypeHoldsPlaceLazily, .calledTypeHoldsSecondHoleType, .callerForwardsValueFillReads, .calledTypeReceivesValueOnlyIfAvailableNothingProvides, .noVisibleImplementation, .implementationReceivesWhatNothingProvides, .fillReceivesValueBuildingTheCall, .fillInstantiatesWhatNothingFulfills, .fillInstantiatesTypeNoDeclarationCanFulfill, .seamCallerFillSharesBuilder, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot, .fillHoldsBuilderOfEnclosingCalledType, .fillRequiresValueCalledTypeReceivesInOptionalWrapper:
			.compilesGeneratedMocks
		}
		// Drawn after everything else, and only for its shape.
		callerLazyValue = switch cell.shape {
		case .fillReceivesCallersLazyValueBelowCalledRoot:
			CallerLazyValue(random: &random)
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .placeInstantiatedOnlyIfAvailable, .calledTypeHoldsPlaceLazily, .calledTypeHoldsSecondHoleType, .callerForwardsValueFillReads, .calledTypeReceivesValueOnlyIfAvailableNothingProvides, .noVisibleImplementation, .implementationReceivesWhatNothingProvides, .fillReceivesValueBuildingTheCall, .fillInstantiatesWhatNothingFulfills, .fillInstantiatesTypeNoDeclarationCanFulfill, .seamCallerFillSharesBuilder, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillHoldsBuilderOfEnclosingCalledType, .fillRequiresValueCalledTypeReceivesInOptionalWrapper, .fillCallsMockTakingGuardedValueWhereMockConditionIsInactive, .fillConstructsTypeCallerModuleCannotReach:
			nil
		}
		// Drawn after everything else, and only for its shape. A `LazilyInstantiated` is drawn only for a deferred place:
		// beside a plain place, the enclosing called type, the fill and the third module's type form a cycle no
		// instantiator breaks, which the tool rejects in both forms (`cycle-validation.md`, "`LazilyInstantiated` is
		// generated like an `Instantiator` and validated like a constant").
		enclosingBuilder = switch cell.shape {
		case .fillHoldsBuilderOfEnclosingCalledType:
			random.element(of: cell.place == .deferred ? EnclosingBuilder.allCases : [.instantiator, .sendableInstantiator])
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .placeInstantiatedOnlyIfAvailable, .calledTypeHoldsPlaceLazily, .calledTypeHoldsSecondHoleType, .callerForwardsValueFillReads, .calledTypeReceivesValueOnlyIfAvailableNothingProvides, .noVisibleImplementation, .implementationReceivesWhatNothingProvides, .fillReceivesValueBuildingTheCall, .fillInstantiatesWhatNothingFulfills, .fillInstantiatesTypeNoDeclarationCanFulfill, .seamCallerFillSharesBuilder, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot, .fillRequiresValueCalledTypeReceivesInOptionalWrapper, .fillCallsMockTakingGuardedValueWhereMockConditionIsInactive, .fillConstructsTypeCallerModuleCannotReach:
			nil
		}
		// Drawn after the builder, and only for its shape, so no graph that draws no builder changes. Beside a
		// `SendableInstantiator`, the fill is built in that builder's `@Sendable` function, so the builder is of the
		// `@Sendable` family, and the plain struct of the fill's level holds a member that returns the third module's
		// `@Sendable` family's struct, whose no-scope initializer takes a `@Sendable` builder
		// (`ScopeGenerator.LevelBuilderForms.takesSendableBuilder(atLevel:)`).
		reenteringFillInstantiatesWhatNothingFulfills = enclosingBuilder != nil && random.element(of: [false, true])
		// Drawn after the shape's other draws, and only for its shape, so the graphs drawn before it keep their values.
		// Beside a `SendableInstantiator`, which builds the called type inside a `@Sendable` function, only the `Sendable`
		// wrapper: a `LazilyInstantiated` read there is an error, in production too.
		enclosingCalledTypeLazyValueWrapper = switch enclosingBuilder {
		case .instantiator?, .lazilyInstantiated?:
			random.element(of: [nil, "SendableLazilyInstantiated", "LazilyInstantiated"])
		case .sendableInstantiator?:
			random.element(of: [nil, "SendableLazilyInstantiated"])
		case nil:
			nil
		}
		// Drawn after everything else, and only for the control, so no other graph changes.
		callsMixedFormMock = cell.shape == .noVisibleImplementation && random.element(of: [false, true])
		// Drawn after everything else, and only for its shape, so no other graph changes.
		optionalWrapperValue = cell.shape == .fillRequiresValueCalledTypeReceivesInOptionalWrapper ? OptionalWrapperValue(random: &random) : nil
		// Drawn after everything else, and only for its shape, so no other graph changes.
		guardedValueCondition = cell.shape == .fillCallsMockTakingGuardedValueWhereMockConditionIsInactive
			? random.element(of: [Self.guardedValueClauseCondition, "DEBUG"])
			: nil
		// Drawn after everything else, and only for its shape, so no other graph changes.
		unreachableConstruction = cell.shape == .fillConstructsTypeCallerModuleCannotReach ? UnreachableConstruction(random: &random) : nil
		// Drawn after everything else, and only for its shape, so no other graph changes.
		valueNothingProvides = cell.shape == .calledTypeReceivesValueOnlyIfAvailableNothingProvides ? ValueNothingProvides(random: &random) : nil
		// Each drawn after everything else, and only for its shape, so no other graph changes.
		lazyPlace = cell.shape == .calledTypeHoldsPlaceLazily ? LazyPlace(graphIndexInCell: GraphFuzzerCallingMockCell.graphIndexInCell(ofSeed: seed)) : nil
		optionalPlace = cell.shape == .placeInstantiatedOnlyIfAvailable ? OptionalPlace(graphIndexInCell: GraphFuzzerCallingMockCell.graphIndexInCell(ofSeed: seed)) : nil
		secondHole = cell.shape == .calledTypeHoldsSecondHoleType ? SecondHole(random: &random) : nil
		forwardedValue = cell.shape == .callerForwardsValueFillReads ? ForwardedValue(random: &random) : nil
		// Drawn after everything else, and only for its shape, so no other graph changes, and no graph's files.
		filledHoleBuilderPass = cell.shape == .callersOwnValue ? random.element(of: FilledHoleBuilderPass.allCases) : nil
		// Drawn after everything else, and only where the second place's fill calls the called type again and the fill that
		// reads the caller's wrapper does not, so no other graph changes.
		joinsFilledCall = callerLazyValue.map { $0.secondPlaceCallsAgain && $0.reentersCalledType && $0.call != .fillCallsAgain } == true && random.element(of: [false, true])
		// Drawn after everything else, and only where a graph joins a filled call, so no other graph changes. A `.public` caller
		// calls `Dock`'s public mock all the same (`DependencyTreeGenerator.publicMockCalls`).
		buildsDockInline = joinsFilledCall && random.element(of: [false, true])
	}

	/// For the shape whose called type holds its place lazily, how.
	struct LazyPlace {
		/// Both follow the graph's index in its cell, so each value of each holds ten or more of the block's graphs, and every
		/// pair of them some: the block draws a plain place only, thirty graphs, too few for values drawn at random to keep ten
		/// each.
		init(graphIndexInCell: Int) {
			wrapper = graphIndexInCell.isMultiple(of: 2) ? "LazilyInstantiated" : "SendableLazilyInstantiated"
			besideByValuePlace = (graphIndexInCell / 2).isMultiple(of: 2)
		}

		/// The wrapper the called type holds the place in.
		let wrapper: String
		/// Whether the called type also holds a place of the hole by value, before the lazy one, which one fill fills.
		let besideByValuePlace: Bool

		/// Whether the fill reads the caller's value: a `SendableLazilyInstantiated` builds its place in a `@Sendable`
		/// function, which is handed no value of the caller, so there the fill reads nothing, in production too.
		var fillReadsValue: Bool {
			wrapper == "LazilyInstantiated"
		}
	}

	/// For the shape whose called type holds its place lazily, how, or `nil`.
	let lazyPlace: LazyPlace?

	/// For the shape whose called type instantiates its place only if available, whether the caller's module declares a
	/// type that fulfills it.
	struct OptionalPlace {
		/// Follows the graph's index in its cell, so each half holds five graphs of each caller's cell: the block draws a
		/// plain place only, thirty graphs, too few for a value drawn at random to keep ten each.
		init(graphIndexInCell: Int) {
			implementationIsVisible = graphIndexInCell.isMultiple(of: 2)
		}

		/// Whether the caller's module declares a type that fulfills the place, which its mock and production's seam then
		/// fill; where it declares none, both take the place's optional builder.
		let implementationIsVisible: Bool
	}

	let optionalPlace: OptionalPlace?

	/// For the shape whose called type holds a place of a second hole type, what fills it and where it is.
	struct SecondHole {
		enum Fill: String, CaseIterable {
			/// A type of the caller's module that reads the caller's value.
			case readsValue
			/// A type of the caller's module that reads nothing.
			case readsNothing
			/// No type the caller's module sees: production and the calling mock take a builder for the place.
			case invisible
		}

		init(random: inout GraphFuzzerRandomNumberGenerator) {
			fill = random.element(of: Fill.allCases)
			isBeforeFirstPlace = random.element(of: [false, true])
		}

		let fill: Fill
		/// Whether the called type declares the second place before the first hole's.
		let isBeforeFirstPlace: Bool

		/// The second hole type, the type of the caller's module that fills it, and the stub a probe's builder returns.
		static let protocolName = "MeterService"
		static let fillName = "LiveMeter"
		static let stubName = "MeterStub"
	}

	/// For the shape whose called type holds a place of a second hole type, what fills it and where it is, or `nil`.
	let secondHole: SecondHole?

	/// For the shape whose caller forwards the value its fill reads, how the fill reads it.
	struct ForwardedValue {
		init(random: inout GraphFuzzerRandomNumberGenerator) {
			fillReceivesOnlyIfAvailable = random.element(of: [false, true])
		}

		/// Whether the fill receives the forwarded value only if available, as an optional.
		let fillReceivesOnlyIfAvailable: Bool
	}

	/// For the shape whose caller forwards the value its fill reads, how the fill reads it, or `nil`.
	let forwardedValue: ForwardedValue?

	/// For the shape whose called type receives only if available a value nothing in the calling tree provides, where.
	struct ValueNothingProvides {
		init(random: inout GraphFuzzerRandomNumberGenerator) {
			receiverIsBeneathCalledType = random.element(of: [false, true])
		}

		/// Whether `Gauge`, which the called type instantiates, receives the value, rather than the called type itself.
		let receiverIsBeneathCalledType: Bool
	}

	/// For the shape whose called type receives only if available a value nothing in the calling tree provides, where, or
	/// `nil`.
	let valueNothingProvides: ValueNothingProvides?

	static let callingMockRandomSeedMask: UInt64 = 0x63616C6C6D6F636B

	/// For the shape whose fill receives the caller's lazy value below the called type's root, how the caller and the
	/// called type's tree hold the value.
	struct CallerLazyValue {
		init(random: inout GraphFuzzerRandomNumberGenerator) {
			receivesOnlyIfAvailable = random.element(of: [false, true])
			wrapper = random.element(of: ["LazilyInstantiated", "SendableLazilyInstantiated"])
			// Drawn after the wrapper, so the graphs keep the values drawn before it.
			call = random.element(of: Call.allCases)
			// Drawn last, and only where the call draws the type, so a variation added later leaves the earlier ones as they
			// were drawn.
			intermediate = switch call {
			case .mockedIntermediateCalls, .mockedIntermediateReceivingValueCalls:
				random.element(of: ["Router", "Flow"])
			case .callerCalls, .fillCallsAgain:
				nil
			}
			// Drawn after the intermediate type, so the graphs keep the values drawn before.
			secondPlaceCallsAgain = random.element(of: [false, true])
			// Drawn last, and only for the `Sendable` wrapper: a `LazilyInstantiated` a fill reads inside a `@Sendable` function is
			// an error, in production too (`SafeDIToolCallingMockMirrorsProductionTests`' `ReenteringWrapperPair`).
			buildsPlaceInSendableFunctionToo = wrapper == "SendableLazilyInstantiated" ? random.element(of: [false, true]) : false
			// Drawn after everything else, and only where the second place's fill, which reads nothing, calls the called type
			// again: the shape the gate for a value held lazily that such a fill does not read is for.
			fillReadsInstanceCalledTypeDoesNotHold = secondPlaceCallsAgain ? random.element(of: [false, true]) : false
			// Drawn after everything else, in half the graphs where the called type holds a copy and the fill that reads the
			// value does not call the called type itself: the shape in which the production twin's level of the place hands the
			// fill of the called type built again the memo of that build. Not where the place is also built in a `@Sendable`
			// function, which carries no field of the value: production rejects a fill there that reads a value a fill that
			// builds the called type again declares again (`declarationBoundOnPathToReenteringCall`).
			secondPlaceFillDeclaresValueAgain = !fillReadsInstanceCalledTypeDoesNotHold && call != .fillCallsAgain && !buildsPlaceInSendableFunctionToo ? random.element(of: [false, true]) : false
		}

		/// Which type of the caller's module calls the called type, and whether the fill calls it again.
		enum Call: String, CaseIterable {
			/// The caller instantiates the called type beside the value.
			case callerCalls
			/// A type of the caller's module that generates its own internal mock (`generateMock: true`), which the caller
			/// instantiates beside the value, instantiates the called type, so that type's mock, as well as the caller's,
			/// reaches the fill.
			case mockedIntermediateCalls
			/// As `mockedIntermediateCalls`, with the intermediate type also receiving the caller's wrapped value.
			case mockedIntermediateReceivingValueCalls
			/// The caller instantiates the called type, and the fill also instantiates an `Instantiator` of it, whose build
			/// re-enters the called type's tree and fills its place again.
			case fillCallsAgain
		}

		/// Whether the type of the called type's tree that receives the value receives it only if available, as an
		/// optional, rather than by value.
		let receivesOnlyIfAvailable: Bool
		/// The wrapper the caller instantiates the value in, which the fill receives.
		let wrapper: String
		/// Which type of the caller's module calls the called type, and whether the fill calls it again.
		let call: Call
		/// The name of the mocked intermediate type that calls the called type, or `nil` where the caller calls it.
		let intermediate: String?
		/// Whether the called type also instantiates a second level, `Hub`, holding a second place, `navigator`, of another
		/// protocol, whose fill reads nothing and instantiates an `Instantiator` of the called type, whose build re-enters the
		/// called type's tree from that fill and fills the first place again there.
		let secondPlaceCallsAgain: Bool
		/// Whether the called type also instantiates a `SendableInstantiator` of the level between, so it builds the place in
		/// plain code and inside that instantiator's `@Sendable` function, outside which the called mock binds the value.
		let buildsPlaceInSendableFunctionToo: Bool
		/// Whether the fill receives the value by value, the caller's wrapper's instance, rather than the wrapper, and the
		/// called type's sibling receives none of it, so the called type holds no copy: the re-entered call's root level
		/// function takes the value, which the second place's fill, reading none of it, holds only as the caller's wrapper,
		/// so the calling mock passes both places up (`DependencyTreeGenerator.holeTypesTheFillGatesPassUp(of:in:lazilyHeldValues:)`).
		/// Drawn only where `secondPlaceCallsAgain`.
		let fillReadsInstanceCalledTypeDoesNotHold: Bool
		/// Whether the called type holds the second level, `Hub`, whose place's fill builds the called type again and also
		/// instantiates a value of its own under the value's label, and the fill that reads the value reads its instance, by
		/// value or, where the sibling receives it only if available, only if available, while the called type keeps its copy:
		/// production then hands the called type built again the second place's value, whose memo the twin's level function
		/// of the place hands that build's fill, and the check compares the mock with the twin. Drawn only without
		/// `fillReadsInstanceCalledTypeDoesNotHold` and `buildsPlaceInSendableFunctionToo`, and where the fill that reads the
		/// value does not call the called type.
		let secondPlaceFillDeclaresValueAgain: Bool

		/// Whether the called type holds the second level, `Hub`, whose place's fill builds the called type again.
		var holdsSecondPlace: Bool {
			secondPlaceCallsAgain || secondPlaceFillDeclaresValueAgain
		}

		/// Whether a fill calls the called type again, the fill that receives the wrapper or the second place's, where a gate
		/// passes the place up: not where `secondPlaceFillDeclaresValueAgain`, whose places are filled. The fill
		/// that receives the wrapper reads it beside its place's fields, since the called mock binds the value by value, or,
		/// where `fillReadsInstanceCalledTypeDoesNotHold`, reads the instance, which the second place's fill does not read,
		/// so the calling mock passes the place up whole, and the second place, whose fill calls the called type, which then
		/// passes a builder up (`GraphFuzzerCallingMockGraph.fillGatePassesUp`).
		var reentersCalledType: Bool {
			(call == .fillCallsAgain || secondPlaceCallsAgain) && !secondPlaceFillDeclaresValueAgain
		}

		/// Whether the fill that reads the value reads its instance rather than the caller's wrapper.
		var fillReadsInstance: Bool {
			fillReadsInstanceCalledTypeDoesNotHold || secondPlaceFillDeclaresValueAgain
		}
	}

	/// How the caller and the called type's tree hold the value, for the shape whose fill receives the caller's lazy value
	/// below the called type's root, or `nil`.
	let callerLazyValue: CallerLazyValue?

	/// For the shape whose fill's tree constructs a type the caller's module cannot reach, that type, which the outer module
	/// declares, and where in the fill's tree it is instantiated.
	struct UnreachableConstruction {
		init(random: inout GraphFuzzerRandomNumberGenerator) {
			access = random.element(of: Access.allCases)
			protocolName = random.element(of: ["Clock", "Compass"])
			typeName = random.element(of: ["Meter", "Sensor"])
			isBeneathFill = random.element(of: [false, true])
		}

		/// How the outer module declares the type, and which package the module is in.
		enum Access: String, CaseIterable {
			/// `internal`, with the outer module in the caller's package: production asks for `package`.
			case internalInCallersPackage
			/// `package`, with the outer module in a package of its own: production asks for `public`.
			case packageInAnotherPackage
			/// `public`, with a `public` initializer and an `internal` hand-written mock, with the outer module in the caller's
			/// package: production calls the initializer and is accepted, and the calling mock, whose fill calls the mock,
			/// asks for `package` on the mock.
			case internalMockInCallersPackage

			/// What the type's declaration and its initializer spell before `final class` and `init`.
			var modifier: String {
				switch self {
				case .internalInCallersPackage:
					""
				case .packageInAnotherPackage:
					"package "
				case .internalMockInCallersPackage:
					"public "
				}
			}

			/// Whether production reports an access error: where the type or its initializer is out of reach, not only its
			/// hand-written mock.
			var twinReportsError: Bool {
				switch self {
				case .internalInCallersPackage, .packageInAnotherPackage:
					true
				case .internalMockInCallersPackage:
					false
				}
			}
		}

		let access: Access
		/// The public protocol the fill's tree instantiates, which only the type fulfills.
		let protocolName: String
		/// The type, which the outer module declares as `access` says.
		let typeName: String
		/// Whether `Part`, a type of the caller's module the fill instantiates, instantiates the protocol, rather than the fill.
		let isBeneathFill: Bool

		/// The package of the outer module, which declares the type.
		var outerModulePackageName: String {
			switch access {
			case .internalInCallersPackage, .internalMockInCallersPackage:
				GraphFuzzerCallingMockGraph.packageName
			case .packageInAnotherPackage:
				"Elsewhere"
			}
		}

		/// The line that declares the type, where production reports its first access error.
		var typeDeclarationLine: String {
			"\(access.modifier)final class \(typeName): \(protocolName), Instantiable {"
		}

		/// The line that declares the type's hand-written mock, where the calling mock reports its error, or `nil` where the
		/// type has none.
		var mockMethodLine: String? {
			switch access {
			case .internalInCallersPackage, .packageInAnotherPackage:
				nil
			case .internalMockInCallersPackage:
				"static func mock() -> \(typeName) { \(typeName)() }"
			}
		}

		/// The outer module's declarations of the protocol and the type.
		var declarations: String {
			"""
			public protocol \(protocolName): AnyObject {}

			@Instantiable(fulfillingAdditionalTypes: [\(protocolName).self])
			\(typeDeclarationLine)
			    \(access.modifier)init() {}\(mockMethodLine.map { "\n    \($0)" } ?? "")
			}
			"""
		}
	}

	/// The type the fill's tree constructs that the caller's module cannot reach, for the shape that draws one, or `nil`.
	let unreachableConstruction: UnreachableConstruction?

	/// Whether production rejects the graph with an error of its own: the shape's `twinRejects`, but where only the
	/// hand-written mock of the type the fill's tree builds is out of the caller's module's reach, which production does
	/// not call.
	var twinRejects: Bool {
		cell.shape.twinRejects && unreachableConstruction?.access.twinReportsError != false
	}

	/// How the third module's type, which the fill of the shape that holds a builder of the enclosing called type builds,
	/// holds that called type.
	enum EnclosingBuilder: String, CaseIterable {
		case instantiator
		case sendableInstantiator
		case lazilyInstantiated

		/// The wrapper type that holds `typeName`.
		func wrapperType(of typeName: String) -> String {
			switch self {
			case .instantiator:
				"Instantiator<\(typeName)>"
			case .sendableInstantiator:
				"SendableInstantiator<\(typeName)>"
			case .lazilyInstantiated:
				"LazilyInstantiated<\(typeName)>"
			}
		}

		/// The property's label: `<type>Builder` for an instantiator, and the type's own name, lowercased, for a lazily
		/// instantiated value.
		func label(of typeName: String) -> String {
			switch self {
			case .instantiator, .sendableInstantiator:
				"\(typeName.lowercasedFirst)Builder"
			case .lazilyInstantiated:
				typeName.lowercasedFirst
			}
		}

		/// An expression of the value `holder`'s property of this kind, `label`, holds: the instance an instantiator builds,
		/// or the one a `LazilyInstantiated` holds.
		func builtValue(of holder: String, label: String) -> String {
			switch self {
			case .instantiator, .sendableInstantiator:
				"\(holder).\(label).instantiate()"
			case .lazilyInstantiated:
				"\(holder).\(label).instance"
			}
		}
	}

	/// For the shape whose fill holds a builder of the enclosing called type, how the third module's type holds it.
	let enclosingBuilder: EnclosingBuilder?

	/// For the shape whose fill holds a builder of the enclosing called type, whether the fill also instantiates
	/// `beacon: any Beacon`, a type no declaration fulfills, which the twin takes a builder for: a `.public` caller hands the
	/// builder through the struct of its own level, which the call inside the fill hands on to the level function it
	/// re-enters (`PublicMockLevelFunctions.Member.reentry`).
	let reenteringFillInstantiatesWhatNothingFulfills: Bool

	/// For the shape whose fill holds a builder of the enclosing called type, the wrapper, `LazilyInstantiated` or
	/// `SendableLazilyInstantiated`, the caller instantiates `value` in, which the enclosing called type receives only if
	/// available as that wrapper's optional, or `nil` where it receives nothing. The called type's public mock takes that
	/// optional wrapper, which the call inside the fill, building the called type again through the third module's public
	/// mock, passes straight through, so the called type built again holds the caller's value, as inline.
	let enclosingCalledTypeLazyValueWrapper: String?

	/// The protocol no declaration fulfills that the fill instantiates where `reenteringFillInstantiatesWhatNothingFulfills`,
	/// and the plain class a probe hands its builder.
	static let beaconProtocol = "Beacon"
	static let beaconStub = "StubBeacon"

	/// The label of the builder of what the fill instantiates where `reenteringFillInstantiatesWhatNothingFulfills`: of the
	/// `@Sendable` family where the third module's type holds the enclosing called type in a `SendableInstantiator`, whose
	/// `@Sendable` builder function re-enters the fill.
	var beaconBuilderLabel: String {
		enclosingBuilder == .sendableInstantiator ? "beaconSendableBuilder" : "beaconBuilder"
	}

	/// For the control, whether the caller also calls a second public mock of the called type's module, `Echo`
	/// (`mixedFormTypeName`), which holds the hole in another form that forwards the same value: a plain place's beside an
	/// `ErasedInstantiator<(), any P>`, both filled by the fill type by name, and an `ErasedInstantiator<Int, any P>`'s
	/// beside an `ErasedInstantiator<Swift.Int, any P>`. The twin takes one builder for both calls' places, so the calling
	/// mock must too (`passesUpExactlyTheExpectedLabels`), whatever form each call passes it up in.
	let callsMixedFormMock: Bool

	/// The second public mock the control calls where `callsMixedFormMock`.
	static let mixedFormTypeName = "Echo"

	/// For the shape whose fill requires a value the called type receives only if available in a lazy wrapper, how the
	/// called type's tree receives it and whether the fill builds the called type again.
	struct OptionalWrapperValue {
		init(random: inout GraphFuzzerRandomNumberGenerator) {
			wrapper = random.element(of: ["LazilyInstantiated", "SendableLazilyInstantiated"])
			siblingReceives = random.element(of: [false, true])
			fillCallsAgain = random.element(of: [false, true])
			// Drawn last, and only beside a sibling, so the graphs drawn before it keep their values.
			calledTypeReceivesBesideSibling = siblingReceives && random.element(of: [false, true])
		}

		/// The wrapper the caller instantiates the value in, which the called type's tree receives optionally.
		let wrapper: String
		/// Whether a type the called type instantiates receives the value, rather than the called type itself, so the
		/// production twin's seam takes it as a pass-through.
		let siblingReceives: Bool
		/// Whether the fill also instantiates an `Instantiator` of the called type, whose build re-enters the called type's
		/// mock inside the fill.
		let fillCallsAgain: Bool
		/// Whether the called type receives the value too, beside the sibling, so the twin's seam takes it as the called
		/// type's own parameter, whose only receiver is the called type: the sibling receives it from the called type.
		let calledTypeReceivesBesideSibling: Bool
	}

	/// For the shape whose fill requires a value the called type receives only if available in a lazy wrapper, how its
	/// tree receives it, or `nil`.
	let optionalWrapperValue: OptionalWrapperValue?

	/// For the shape whose fill's hand-written mock takes a value only an inactive clause declares, the condition of that
	/// clause: `guardedValueClauseCondition`, which no build defines, or `DEBUG`, the mock condition, which the build leaves
	/// inactive. `nil` for every other shape.
	let guardedValueCondition: String?

	/// For the caller's own value's shape, what a probe hands the calling mock besides calling it: the optional builder it
	/// takes for the hole type its call of the called type's public mock fills, an override of the called type that calls
	/// the called mock with the builder the override is handed, or both (`public-mock-builders.md`, "Optional builders for
	/// filled places"). `nil` for every other shape.
	enum FilledHoleBuilderPass: CaseIterable, CustomStringConvertible {
		case none
		case builder
		case override
		case builderAndOverride

		var passesBuilder: Bool {
			switch self {
			case .builder, .builderAndOverride:
				true
			case .none, .override:
				false
			}
		}

		var passesOverride: Bool {
			switch self {
			case .override, .builderAndOverride:
				true
			case .none, .builder:
				false
			}
		}

		var description: String {
			switch self {
			case .none:
				"none"
			case .builder:
				"builder"
			case .override:
				"override"
			case .builderAndOverride:
				"builderAndOverride"
			}
		}
	}

	let filledHoleBuilderPass: FilledHoleBuilderPass?

	/// For the shape whose fill receives the caller's lazy value below the called type's root, where a gate passes the hole
	/// type of the called type up whole, whether the caller also instantiates a second called type, `Dock`, a seam and
	/// public mock of the called type's module whose root holds a place of the same hole type and form, which its fill
	/// fills: the calling mock then takes the one required builder of the hole type, which its call of `Dock` reads in
	/// place of an optional builder (the join, `public-mock-builders.md`, "Optional builders for filled places"), so the
	/// probe hands that builder a stub and reads whether `Dock`'s place holds it (`joinedCallProbes`).
	let joinsFilledCall: Bool

	/// Where the graph `joinsFilledCall`, whether `Dock` is a plain public mock whose initializer is public, so the calling
	/// mock builds it inline rather than calling its mock, and `Dock`'s place, a hole of its module, reads the required
	/// builder where it is built, by value, or wrapped in the `ErasedInstantiator` of a deferred place
	/// (`ScopeGenerator.holeBuildersByInlinePlace`). The same probe judges it (`joinedCallProbes`).
	let buildsDockInline: Bool

	/// The name and label of the second called type of `joinsFilledCall`.
	var dockName: String {
		"\(names.inner)Dock"
	}

	/// The condition of the clause that declares the guarded value, which no build of the calling-mock corpus defines.
	static let guardedValueClauseCondition = "FUZZ_GUARD"

	/// The place of the hole `mixedFormTypeName` holds, in the other form.
	private var mixedFormPlace: (label: String, type: String, attribute: String) {
		switch cell.place {
		case .plain:
			("\(names.hole.lowercasedFirst)Builder", "ErasedInstantiator<(), any \(names.hole)>", "@Instantiated(fulfilledByType: \"\(names.fill)\")")
		case .deferred:
			("\(names.hole.lowercasedFirst)Builder", "ErasedInstantiator<Swift.Int, any \(names.hole)>", "@Instantiated(fulfilledByType: \"\(names.fill)\")")
		}
	}

	/// The build of the calling mock's module the tool is told of: one that compiles the generated mocks, but in the shapes
	/// drawn where the mock condition is inactive: the one whose fill the tool does not check there, and the one whose
	/// fill's hand-written mock takes a value only an inactive clause declares.
	let mockBuild: GraphFuzzerCallingMockGraph.MockBuild

	/// The graph the check judges.
	var graph: GraphFuzzerCallingMockGraph {
		GraphFuzzerCallingMockGraph(
			name: "seed \(seed) (\(cell))",
			mockFiles: files(.mock),
			twinFiles: files(.twin),
			callerTypeName: names.caller,
			callerIsPublic: cell.callerIsPublic,
			mockConfiguration: mockConfiguration,
			flatParameterLabels: flatParameterLabels,
			implementationIsVisible: implementationIsVisible,
			expectedTwinInitializerLabels: expectedTwinInitializerLabels,
			expectedPassUpLabels: expectedPassUpLabels,
			expectedTwinErrorSite: expectedTwinErrorSite,
			expectedMockOwnErrorSite: unreachableConstruction.flatMap { construction in
				construction.mockMethodLine.map { ("\(names.outerModuleName)/\(names.outerModuleName)Types.swift", $0) }
			},
			valueProbes: valueProbes,
			mockBuild: mockBuild,
			twinErrorIsCheckedOnlyWhereMocksCompile: twinErrorIsCheckedOnlyWhereMocksCompile,
			// The twin of a second place's fill that declares the value again is compared too: its level function hands the fill
			// of the called type built again that build's memo, which only production code reads.
			comparesValuesWithInline: cell.shape.comparesValuesWithInline && callerLazyValue?.secondPlaceFillDeclaresValueAgain != true,
			fillGatePassesUp: callerLazyValue?.reentersCalledType == true,
		)
	}

	let seed: UInt64
	let cell: GraphFuzzerCallingMockCell

	typealias Form = GraphFuzzerCallingMockGraph.Form

	/// The parameters of the calling mock's `mock()` that are values rather than builders: the value a caller forwards,
	/// in the shape whose fill reads it, the value the fill of the nothing-builds shape receives, and a `.public` mock's
	/// value nothing provides, which an internal or listed mock takes as an override.
	var flatParameterLabels: Set<String> {
		switch cell.shape {
		case .implementationReceivesWhatNothingProvides:
			[names.token.lowercasedFirst]
		case .calledTypeReceivesValueOnlyIfAvailableNothingProvides:
			cell.callerIsPublic ? [names.token.lowercasedFirst] : []
		case .callerForwardsValueFillReads:
			[names.value.lowercasedFirst]
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .placeInstantiatedOnlyIfAvailable, .calledTypeHoldsPlaceLazily, .calledTypeHoldsSecondHoleType, .noVisibleImplementation, .fillReceivesValueBuildingTheCall, .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder, .fillInstantiatesTypeNoDeclarationCanFulfill, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot, .fillHoldsBuilderOfEnclosingCalledType, .fillRequiresValueCalledTypeReceivesInOptionalWrapper, .fillCallsMockTakingGuardedValueWhereMockConditionIsInactive, .fillConstructsTypeCallerModuleCannotReach:
			[]
		}
	}

	/// Whether the calling mock's pass-ups must be exactly `expectedPassUpLabels`: the shape's
	/// (`GraphFuzzerCallingMockShape.passesUpExactlyTheExpectedLabels`), and those the gate for a re-entered called type
	/// passes up (`CallerLazyValue.reentersCalledType`), and the builder of what a re-entering fill instantiates that
	/// nothing fulfills, the twin's (`reenteringFillInstantiatesWhatNothingFulfills`).
	var passesUpExactlyTheExpectedLabels: Bool {
		cell.shape.passesUpExactlyTheExpectedLabels || callerLazyValue?.reentersCalledType == true || reenteringFillInstantiatesWhatNothingFulfills || secondHole != nil
	}

	/// Whether a type that fulfills the hole is visible from the calling mock's module.
	var implementationIsVisible: Bool {
		switch cell.shape {
		case .noVisibleImplementation, .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder:
			false
		case .fillHoldsBuilderOfEnclosingCalledType:
			// The builder of what the fill instantiates that nothing fulfills is the place `mock()` takes.
			!reenteringFillInstantiatesWhatNothingFulfills
		case .calledTypeHoldsSecondHoleType:
			// The second hole's builder is the place `mock()` takes where no type of the caller's module fills it.
			secondHole?.fill != .invisible
		case .placeInstantiatedOnlyIfAvailable:
			optionalPlace?.implementationIsVisible != false
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .calledTypeHoldsPlaceLazily, .callerForwardsValueFillReads, .calledTypeReceivesValueOnlyIfAvailableNothingProvides, .implementationReceivesWhatNothingProvides, .fillReceivesValueBuildingTheCall, .fillInstantiatesTypeNoDeclarationCanFulfill, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot, .fillRequiresValueCalledTypeReceivesInOptionalWrapper, .fillCallsMockTakingGuardedValueWhereMockConditionIsInactive, .fillConstructsTypeCallerModuleCannotReach:
			true
		}
	}

	/// The builder of the hole's place, as contract rule 8 labels it in the twin's seam initializer and the calling mock's
	/// `mock()`: `<filling type>Builder` when the filling type is the returned type, the hole, else
	/// `<filling type>_<returned type>Builder`, the filling type's leading capitals lowered.
	var holeBuilderLabel: String {
		let fillingType = switch cell.place {
		case .plain:
			callsMixedFormMock ? names.fill : names.hole
		case .deferred:
			names.fill
		}
		let stem = String(GraphFuzzerPublicMockDraw.builderLabel(ofTypeNamed: fillingType).dropLast("Builder".count))
		// A place instantiated only if available takes a builder that returns the optional, its stem ending `Optional`.
		return stem + (fillingType == names.hole ? "" : "_\(names.hole)") + (optionalPlace == nil ? "" : "Optional") + "Builder"
	}

	/// The builder of the second hole type's place, labeled as `holeBuilderLabel` labels the first's, which the twin and the
	/// calling mock take where no type of the caller's module fills it.
	var secondHoleBuilderLabel: String {
		let fillingType = cell.place == .plain ? SecondHole.protocolName : SecondHole.fillName
		let stem = String(GraphFuzzerPublicMockDraw.builderLabel(ofTypeNamed: fillingType).dropLast("Builder".count))
		return stem + (fillingType == SecondHole.protocolName ? "" : "_\(SecondHole.protocolName)") + "Builder"
	}

	/// A builder of the second hole type's place that returns its stub, as a probe hands it.
	private var secondHoleStubBuilder: String {
		switch cell.place {
		case .plain:
			"{ \(names.innerModuleName).\(SecondHole.stubName)() }"
		case .deferred:
			"{ _ in \(names.innerModuleName).\(SecondHole.stubName)() }"
		}
	}

	/// What the twin's seam initializer takes where production accepts the graph: nothing where its tree fills the place,
	/// the value the fill receives where nothing in the tree builds it, and the place's builder where no type that fulfills
	/// the place is visible.
	var expectedTwinInitializerLabels: [String]? {
		switch cell.shape {
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .fillReceivesValueBuildingTheCall, .fillInstantiatesTypeNoDeclarationCanFulfill, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive, .fillRequiresValueCalledTypeReceivesInOptionalWrapper, .fillConstructsTypeCallerModuleCannotReach:
			nil
		case .calledTypeReceivesValueOnlyIfAvailableNothingProvides:
			[names.token.lowercasedFirst]
		case .callersOwnValue, .calledTypeHoldsPlaceLazily, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot, .fillCallsMockTakingGuardedValueWhereMockConditionIsInactive:
			[]
		case .fillHoldsBuilderOfEnclosingCalledType:
			reenteringFillInstantiatesWhatNothingFulfills ? [beaconBuilderLabel] : []
		case .implementationReceivesWhatNothingProvides:
			[names.token.lowercasedFirst]
		case .noVisibleImplementation:
			[holeBuilderLabel]
		case .placeInstantiatedOnlyIfAvailable:
			implementationIsVisible ? [] : [holeBuilderLabel]
		case .calledTypeHoldsSecondHoleType:
			secondHole?.fill == .invisible ? [secondHoleBuilderLabel] : []
		case .callerForwardsValueFillReads:
			[names.value.lowercasedFirst]
		case .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder:
			expectedBuilders.map(\.label)
		}
	}

	/// The builders the twin's seam initializer and the calling mock take where the fill instantiates what nothing
	/// fulfills, by label, each with the value a probe hands it: the fill's, and, for the seam caller, those of its own
	/// places, one builder for both where they are of one hole type and family.
	var expectedBuilders: [(label: String, value: (_ module: String) -> String)] {
		guard let fillHoles else { return [] }
		var builders = fillHoles.builders
		if cell.shape == .seamCallerFillSharesBuilder {
			for protocolName in fillHoles.protocols {
				let label = GraphFuzzerPublicMockDraw.builderLabel(ofTypeNamed: protocolName)
				guard !builders.contains(where: { $0.label == label }) else { continue }
				let stubName = fillHoles.stub(of: protocolName)
				builders.append((label, { module in "{ \(module).\(stubName)(id: 0) }" }))
			}
		}
		return builders.sorted { $0.label < $1.label }
	}

	/// Whether the twin's error is one the tool checks in the mock only where the generated mocks compile: the fill's
	/// implementation is a plain type, so the type it instantiates that no declaration can fulfill is in no tree but the
	/// mock's. Where it is a seam, its own tree, which every build generates, reports the error. A construction in the fill's
	/// tree that the caller's module cannot reach is in no tree but the mock's too, and so is the call of a hand-written
	/// mock the twin does not call, whose error is the mock's own (`GraphFuzzerCallingMockGraph.expectedMockOwnErrorSite`).
	var twinErrorIsCheckedOnlyWhereMocksCompile: Bool {
		switch cell.shape {
		case .fillConstructsTypeCallerModuleCannotReach:
			true
		case .fillInstantiatesTypeNoDeclarationCanFulfill, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive:
			fillHoles?.fulfillerIsSeam == false
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .placeInstantiatedOnlyIfAvailable, .calledTypeHoldsPlaceLazily, .calledTypeHoldsSecondHoleType, .callerForwardsValueFillReads, .calledTypeReceivesValueOnlyIfAvailableNothingProvides, .noVisibleImplementation, .implementationReceivesWhatNothingProvides, .fillReceivesValueBuildingTheCall, .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot, .fillHoldsBuilderOfEnclosingCalledType, .fillRequiresValueCalledTypeReceivesInOptionalWrapper, .fillCallsMockTakingGuardedValueWhereMockConditionIsInactive:
			false
		}
	}

	/// The places the calling mock may pass up: the hole's builder where its module sees no type that fulfills the hole, or
	/// where the tool skips the twin's error in the mock, as a build that leaves the mock condition inactive skips a plain
	/// implementation's, and the builders of what the fill instantiates that nothing fulfills, as the twin takes them; and,
	/// where a fill calls the called type again and the fill that receives the caller's wrapper reads it beside its
	/// place's fields, the place's builder and the second place's, in `mock()`'s order, by label
	/// (`CallerLazyValue.reentersCalledType`).
	var expectedPassUpLabels: [String] {
		if callerLazyValue?.reentersCalledType == true {
			var labels = [holeBuilderLabel]
			// A hole type is passed up whole: its `@Sendable` family's builder too, where the place is also built in a
			// `@Sendable` function.
			if callerLazyValue?.buildsPlaceInSendableFunctionToo == true {
				labels.append(String(holeBuilderLabel.dropLast("Builder".count)) + "SendableBuilder")
			}
			if callerLazyValue?.secondPlaceCallsAgain == true {
				labels.append(GraphFuzzerPublicMockDraw.builderLabel(ofTypeNamed: Self.secondPlaceProtocol))
			}
			return labels.sorted()
		}
		return switch cell.shape {
		case .noVisibleImplementation:
			[holeBuilderLabel]
		case .placeInstantiatedOnlyIfAvailable:
			implementationIsVisible ? [] : [holeBuilderLabel]
		case .calledTypeHoldsSecondHoleType:
			secondHole?.fill == .invisible ? [secondHoleBuilderLabel] : []
		case .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive:
			twinErrorIsCheckedOnlyWhereMocksCompile ? [holeBuilderLabel] : []
		case .fillConstructsTypeCallerModuleCannotReach:
			mockBuild.compilesGeneratedMocks ? [] : [holeBuilderLabel]
		case .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder:
			expectedBuilders.map(\.label)
		case .fillHoldsBuilderOfEnclosingCalledType:
			reenteringFillInstantiatesWhatNothingFulfills ? [beaconBuilderLabel] : []
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .calledTypeHoldsPlaceLazily, .callerForwardsValueFillReads, .calledTypeReceivesValueOnlyIfAvailableNothingProvides, .implementationReceivesWhatNothingProvides, .fillReceivesValueBuildingTheCall, .fillInstantiatesTypeNoDeclarationCanFulfill, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot, .fillRequiresValueCalledTypeReceivesInOptionalWrapper, .fillCallsMockTakingGuardedValueWhereMockConditionIsInactive:
			[]
		}
	}

	/// What the calling mock and its known-right path build where the mock fills the place: a probe calling the mock and the
	/// twin's seam initializer, or, for a deferred place, one describing that value and what the place's builder builds for
	/// `id` 7 as a tuple (`callerAndFill(of:place:)`), since the comparator calls no `ErasedInstantiator` and numbers
	/// identities per probe. For the seam built again, whose twin reports that the second build passes its builder on
	/// unchanged, the known-right path is the same types built inline (`seamBuiltAgainValueProbes`). `nil` where the twin
	/// rejects the graph otherwise or the mock passes the place up.
	var valueProbes: [DifferentialValueProbe]? {
		guard cell.shape != .seamBuiltAgain else { return seamBuiltAgainValueProbes }
		guard !joinsFilledCall else { return joinedCallProbes }
		// Where the mock passes the place up whole, `mock()` takes builders whose values only a test chooses.
		guard callerLazyValue?.reentersCalledType != true else { return nil }
		guard cell.shape != .fillReceivesCallersLazyValueBelowCalledRoot else { return callerLazyValueProbes }
		guard cell.shape != .fillHoldsBuilderOfEnclosingCalledType else { return enclosingBuilderProbes }
		// Qualified by its module: Foundation, which the probe executable imports, declares `Host` on macOS.
		let caller = "\(names.callerModuleName).\(names.caller)"
		let token = names.token.lowercasedFirst
		let calls: (mock: String, twin: String)? = switch cell.shape {
		case .callersOwnValue, .calledTypeHoldsPlaceLazily, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace:
			("\(caller).mock()", "\(caller)()")
		case .calledTypeHoldsSecondHoleType:
			// Where no type of the caller's module fills the second place, `mock()` and the twin take its builder, handed a stub.
			secondHole?.fill == .invisible
				? ("\(caller).mock(\(secondHoleBuilderLabel): \(secondHoleStubBuilder))", "\(caller)(\(secondHoleBuilderLabel): \(secondHoleStubBuilder))")
				: ("\(caller).mock()", "\(caller)()")
		case .placeInstantiatedOnlyIfAvailable:
			// Where no type of the caller's module fills the place, the mock's builder defaults to `{ nil }`, which the twin's
			// is handed, so both hold `nil`.
			implementationIsVisible
				? ("\(caller).mock()", "\(caller)()")
				: ("\(caller).mock()", "\(caller)(\(holeBuilderLabel): { nil })")
		case .callerForwardsValueFillReads:
			("\(caller).mock(\(names.value.lowercasedFirst): \(names.outerModuleName).\(names.value)())", "\(caller)(__safeDI_\(names.value.lowercasedFirst): \(names.outerModuleName).\(names.value)())")
		case .calledTypeReceivesValueOnlyIfAvailableNothingProvides:
			(
				cell.callerIsPublic
					? "\(caller).mock(\(token): \(names.innerModuleName).\(names.token)())"
					: "\(caller).mock(safeDIOverrides: .init(\(token): \(names.innerModuleName).\(names.token)()))",
				"\(caller)(__safeDI_\(token): \(names.innerModuleName).\(names.token)())",
			)
		case .implementationReceivesWhatNothingProvides:
			("\(caller).mock(\(token): \(names.token)())", "\(caller)(__safeDI_\(token): \(names.token)())")
		case .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder:
			fillHoles.map { _ in
				let builders = expectedBuilders
				let mockArguments = builders.map { "\($0.label): \($0.value(names.callerModuleName))" }
				let twinArguments = builders.map { "\($0.label): \($0.value(names.callerModuleName))" }
				return ("\(caller).mock(\(mockArguments.joined(separator: ", ")))", "\(caller)(\(twinArguments.joined(separator: ", ")))")
			}
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .noVisibleImplementation, .fillReceivesValueBuildingTheCall, .fillInstantiatesTypeNoDeclarationCanFulfill, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive, .fillReceivesCallersLazyValueBelowCalledRoot, .fillHoldsBuilderOfEnclosingCalledType, .fillRequiresValueCalledTypeReceivesInOptionalWrapper, .fillCallsMockTakingGuardedValueWhereMockConditionIsInactive, .fillConstructsTypeCallerModuleCannotReach:
			nil
		}
		guard let calls else { return nil }
		let (mockCall, twinCall) = calls
		if let filledHoleBuilderPass, filledHoleBuilderPass != .none {
			return filledHoleBuilderProbes(filledHoleBuilderPass, caller: caller, twinCall: twinCall)
		}
		switch cell.place {
		case .plain:
			return [DifferentialValueProbe(name: caller, expression: mockCall, knownRightExpression: twinCall)]
		case .deferred:
			let path = if cell.shape == .fillReceivesValueOnlyInnerMockRequires {
				// The called type holds the place where only an inner public mock requires the value the fill receives.
				names.outer.lowercasedFirst
			} else if cell.shape == .calledTypesReceivedValueInSendablePlace {
				// The place of the shape built inside a `@Sendable` function is `Part`'s, which the called type's
				// `SendableInstantiator` builds, and which the comparator calls.
				"\(names.inner.lowercasedFirst).\(names.between.lowercasedFirst)Builder.instantiate()"
			} else {
				names.inner.lowercasedFirst
			}
			let place = "\(path).\(holePlace(protocolName: names.hole, fillName: names.fill).label)"
			if secondHole != nil {
				// What both places' builders build for `id` 7, beside the caller.
				let secondPlace = "\(path).\(holePlace(protocolName: SecondHole.protocolName, fillName: SecondHole.fillName).label)"
				func callerAndFills(of call: String) -> String {
					"{ let caller = \(call); return (caller, caller.\(place).instantiate(7), caller.\(secondPlace).instantiate(7)) }()"
				}
				return [DifferentialValueProbe(
					name: "(\(caller), \(caller).\(place).instantiate(7), \(caller).\(secondPlace).instantiate(7))",
					expression: callerAndFills(of: mockCall),
					knownRightExpression: callerAndFills(of: twinCall),
				)]
			}
			return [DifferentialValueProbe(
				name: "(\(caller), \(caller).\(place).instantiate(7))",
				expression: Self.callerAndFill(of: mockCall, place: place),
				knownRightExpression: Self.callerAndFill(of: twinCall, place: place),
			)]
		}
	}

	/// The probes of the caller's own value's shape where a probe hands the calling mock the optional builder of the hole
	/// type its call fills, an override of the called type, or both (`filledHoleBuilderPass`). The override calls the
	/// called type's public mock with the builder it is handed, so the mock builds what the twin builds where it is handed
	/// the fill, and the place holds what the builder builds where it is handed that. Where the mock is passed the builder,
	/// the probe reads whether the place holds the instance a type declared in the probe builds, which the twin's place
	/// never holds, so the known-right expression is `true`.
	private func filledHoleBuilderProbes(_ pass: FilledHoleBuilderPass, caller: String, twinCall: String) -> [DifferentialValueProbe] {
		let label = holeBuilderLabel
		let place = "\(names.inner.lowercasedFirst).\(holePlace(protocolName: names.hole, fillName: names.fill).label)"
		let builtPlace = switch cell.place {
		case .plain:
			"caller.\(place)"
		case .deferred:
			"caller.\(place).instantiate(7)"
		}
		let stubBuilder = switch cell.place {
		case .plain:
			"{ stub }"
		case .deferred:
			"{ _ in stub }"
		}
		var arguments = [String]()
		if pass.passesBuilder {
			arguments.append("\(label): \(stubBuilder)")
		}
		if pass.passesOverride {
			arguments.append("safeDIOverrides: .init(\(names.inner.lowercasedFirst): { builder in \(names.innerModuleName).\(names.inner).mock(\(label): builder) })")
		}
		let mockCall = "\(caller).mock(\(arguments.joined(separator: ", ")))"
		guard pass.passesBuilder else {
			switch cell.place {
			case .plain:
				return [DifferentialValueProbe(name: "\(caller) with an override", expression: mockCall, knownRightExpression: twinCall)]
			case .deferred:
				return [DifferentialValueProbe(
					name: "(\(caller), \(caller).\(place).instantiate(7)) with an override",
					expression: Self.callerAndFill(of: mockCall, place: place),
					knownRightExpression: Self.callerAndFill(of: twinCall, place: place),
				)]
			}
		}
		return [DifferentialValueProbe(
			name: "\(caller).\(place) holds what the \(label) passed\(pass.passesOverride ? " beside an override" : "") builds",
			expression: "{ final class Stub: \(names.innerModuleName).\(names.hole) {}; let stub = Stub(); let caller = \(mockCall); return \(builtPlace) === stub }()",
			knownRightExpression: "true",
		)]
	}

	/// The probe of a graph that `joinsFilledCall`: the calling mock, handed a stub by every builder it takes, against
	/// `true`, reading whether `Dock`'s place, which its call fills, holds the stub the required builder of its hole type
	/// builds. Each stub is a type declared in the probe, `Sendable`, since a builder of the `@Sendable` family captures it.
	private var joinedCallProbes: [DifferentialValueProbe] {
		let caller = "\(names.callerModuleName).\(names.caller)"
		let place = holePlace(protocolName: names.hole, fillName: names.fill).label
		let stubBuilder = switch cell.place {
		case .plain:
			"{ stub }"
		case .deferred:
			"{ _ in stub }"
		}
		let arguments = expectedPassUpLabels.map { label in
			label == GraphFuzzerPublicMockDraw.builderLabel(ofTypeNamed: Self.secondPlaceProtocol) ? "\(label): { navigatorStub }" : "\(label): \(stubBuilder)"
		}
		let builtPlace = switch cell.place {
		case .plain:
			"caller.\(dockName.lowercasedFirst).\(place)"
		case .deferred:
			"caller.\(dockName.lowercasedFirst).\(place).instantiate(7)"
		}
		let module = names.innerModuleName
		return [DifferentialValueProbe(
			name: "\(caller).\(dockName.lowercasedFirst).\(place) holds what the required builder passed builds",
			expression: "{ final class Stub: \(module).\(names.hole), Sendable {}; final class NavigatorStub: \(module).\(Self.secondPlaceProtocol), Sendable {}; let stub = Stub(); let navigatorStub = NavigatorStub(); let caller = \(caller).mock(\(arguments.joined(separator: ", "))); return \(builtPlace) === stub }()",
			knownRightExpression: "true",
		)]
	}

	/// The seam built again's probes: the calling mock against the caller's root initializer in the same types built inline
	/// (`GraphFuzzerCallingMockGraph.inlineModules`), in module `App`. A plain place is reached through the instantiators
	/// the comparator calls, the outer place in the caller's seam and the inner one in the seam the level between builds
	/// again. A deferred place's probe is one tuple of the caller, what the outer place's builder builds for `id` 7, the
	/// level between built from the outer seam, and what the inner place's builder beneath it builds for `id` 7, so the
	/// comparator, which calls no `ErasedInstantiator`, sees whether each fill receives the value nearest it, the caller's
	/// or the level between's.
	private var seamBuiltAgainValueProbes: [DifferentialValueProbe] {
		let caller = "App.\(names.caller)"
		switch cell.place {
		case .plain:
			return [DifferentialValueProbe(name: caller, expression: "\(caller).mock()", knownRightExpression: "\(caller)()")]
		case .deferred:
			let repeated = names.repeated.lowercasedFirst
			let between = names.between.lowercasedFirst
			let place = holePlace(protocolName: names.hole, fillName: names.fill).label
			func fills(of call: String) -> String {
				"{ let caller = \(call); let between = caller.\(repeated).\(between)Builder.instantiate(); return (caller, caller.\(repeated).\(place).instantiate(7), between, between.\(repeated)Builder.instantiate().\(place).instantiate(7)) }()"
			}
			return [DifferentialValueProbe(
				name: "(\(caller), outer \(place).instantiate(7), level between, inner \(place).instantiate(7))",
				expression: fills(of: "\(caller).mock()"),
				knownRightExpression: fills(of: "\(caller)()"),
			)]
		}
	}

	/// The probes of the fill that receives the caller's lazy value below the called type's root: the calling mock against
	/// the caller's root initializer in the same types built inline (`GraphFuzzerCallingMockGraph.inlineModules`), where
	/// the fill holds the wrapper the caller holds, so the comparator, which numbers identities per probe, sees whether the
	/// mock's fill holds that wrapper or another. A plain place's probe describes the caller, a deferred place's one tuple of
	/// the caller and what the place's builder builds for `id` 7 (`callerAndFill(of:place:)`), since the comparator calls no
	/// `ErasedInstantiator`. A second probe reads whether that fill's wrapper holds the instance the caller's does. Where a
	/// mocked intermediate type calls the called type, the place is reached through it; where the fill calls the called
	/// type again, the deferred place's probe also holds what the re-entered place's builder builds for `id` 7, and a third
	/// probe reads whether the re-entered fill's wrapper holds the caller's instance too.
	private var callerLazyValueProbes: [DifferentialValueProbe] {
		let caller = "\(names.callerModuleName).\(names.caller)"
		let fill = "\(names.callerModuleName).\(names.fill)"
		let placeLabel = holePlace(protocolName: names.hole, fillName: names.fill).label
		// The place below the called type's root, from the called type.
		let placeInCalledType = "\(names.between.lowercasedFirst).\(placeLabel)"
		let calledType = if let intermediate = callerLazyValue?.intermediate {
			"\(intermediate.lowercasedFirst).\(names.inner.lowercasedFirst)"
		} else {
			names.inner.lowercasedFirst
		}
		let place = "\(calledType).\(placeInCalledType)"
		let reenteredCalledType = "\(names.inner.lowercasedFirst)Builder.instantiate()"
		let value = names.value.lowercasedFirst
		let callsAgain = callerLazyValue?.call == .fillCallsAgain
		let valueProbe: DifferentialValueProbe
		let filled: String
		switch cell.place {
		case .plain:
			valueProbe = DifferentialValueProbe(name: caller, expression: "\(caller).mock()", knownRightExpression: "\(caller)()")
			filled = "caller.\(place)"
		case .deferred:
			if callsAgain {
				func fills(of call: String) -> String {
					"{ let caller = \(call); let fill = caller.\(place).instantiate(7); return (caller, fill, (fill as! \(fill)).\(reenteredCalledType).\(placeInCalledType).instantiate(7)) }()"
				}
				valueProbe = DifferentialValueProbe(
					name: "(\(caller), \(caller).\(place).instantiate(7), re-entered \(placeInCalledType).instantiate(7))",
					expression: fills(of: "\(caller).mock()"),
					knownRightExpression: fills(of: "\(caller)()"),
				)
			} else {
				valueProbe = DifferentialValueProbe(
					name: "(\(caller), \(caller).\(place).instantiate(7))",
					expression: Self.callerAndFill(of: "\(caller).mock()", place: place),
					knownRightExpression: Self.callerAndFill(of: "\(caller)()", place: place),
				)
			}
			filled = "caller.\(place).instantiate(7)"
		}
		let reentered = switch cell.place {
		case .plain:
			"(\(filled) as! \(fill)).\(reenteredCalledType).\(placeInCalledType)"
		case .deferred:
			"(\(filled) as! \(fill)).\(reenteredCalledType).\(placeInCalledType).instantiate(7)"
		}
		// The instance the fill holds: its wrapper's, or the value itself where it reads the instance.
		let fillsInstance = callerLazyValue?.fillReadsInstance == true ? value : "\(value).instance"
		func holdsCallersInstance(_ call: String, fill filledExpression: String) -> String {
			"{ let caller = \(call); return (\(filledExpression) as! \(fill)).\(fillsInstance) === caller.\(value).instance }()"
		}
		var probes = [
			valueProbe,
			DifferentialValueProbe(
				name: "\(names.fill).\(value).instance === \(names.caller).\(value).instance",
				expression: holdsCallersInstance("\(caller).mock()", fill: filled),
				knownRightExpression: holdsCallersInstance("\(caller)()", fill: filled),
			),
		]
		if callsAgain {
			probes.append(DifferentialValueProbe(
				name: "re-entered \(names.fill).\(value).instance === \(names.caller).\(value).instance",
				expression: holdsCallersInstance("\(caller).mock()", fill: reentered),
				knownRightExpression: holdsCallersInstance("\(caller)()", fill: reentered),
			))
		}
		func holdsCallersWrapper(_ call: String, fill filledExpression: String) -> String {
			"{ let caller = \(call); return (\(filledExpression) as! \(fill)).\(value) === caller.\(value) }()"
		}
		let instantiatedPlace = switch cell.place {
		case .plain:
			""
		case .deferred:
			".instantiate(7)"
		}
		if callerLazyValue?.secondPlaceFillDeclaresValueAgain == true {
			// The called type the second place's fill builds again holds that fill's value, and so does the fill of its place.
			let secondFill = "(caller.\(calledType).\(Self.secondLevelLabel).\(Self.secondPlaceLabel) as! \(names.callerModuleName).\(Self.secondFillName))"
			func holdsSecondFillsValue(_ call: String, _ holder: String) -> String {
				"{ let caller = \(call); let secondFill = \(secondFill); let reentered = secondFill.\(reenteredCalledType); return \(holder) === secondFill.\(value) }()"
			}
			let reenteredFill = "(reentered.\(placeInCalledType)\(instantiatedPlace) as! \(fill)).\(value)"
			let reenteredCopy = "reentered.\(names.sibling.lowercasedFirst).\(value)"
			probes.append(DifferentialValueProbe(
				name: "\(names.fill) re-entered through \(Self.secondFillName) holds \(Self.secondFillName).\(value)",
				expression: holdsSecondFillsValue("\(caller).mock()", reenteredFill),
				knownRightExpression: holdsSecondFillsValue("\(caller)()", reenteredFill),
			))
			probes.append(DifferentialValueProbe(
				name: "\(names.sibling) re-entered through \(Self.secondFillName) holds \(Self.secondFillName).\(value)",
				expression: holdsSecondFillsValue("\(caller).mock()", reenteredCopy),
				knownRightExpression: holdsSecondFillsValue("\(caller)()", reenteredCopy),
			))
		} else if callerLazyValue?.secondPlaceCallsAgain == true {
			let reenteredThroughSecondPlace = "(caller.\(calledType).\(Self.secondLevelLabel).\(Self.secondPlaceLabel) as! \(names.callerModuleName).\(Self.secondFillName)).\(reenteredCalledType).\(placeInCalledType)\(instantiatedPlace)"
			probes.append(DifferentialValueProbe(
				name: "\(names.fill) re-entered through \(Self.secondFillName) holds \(names.caller).\(value)",
				expression: holdsCallersWrapper("\(caller).mock()", fill: reenteredThroughSecondPlace),
				knownRightExpression: holdsCallersWrapper("\(caller)()", fill: reenteredThroughSecondPlace),
			))
		}
		if callerLazyValue?.buildsPlaceInSendableFunctionToo == true {
			let builtInSendableFunction = "caller.\(calledType).\(names.between.lowercasedFirst)Builder.instantiate().\(placeLabel)\(instantiatedPlace)"
			if callerLazyValue?.fillReadsInstance == true {
				probes.append(DifferentialValueProbe(
					name: "\(names.fill) built in a @Sendable function holds \(names.caller).\(value).instance",
					expression: holdsCallersInstance("\(caller).mock()", fill: builtInSendableFunction),
					knownRightExpression: holdsCallersInstance("\(caller)()", fill: builtInSendableFunction),
				))
			} else {
				probes.append(DifferentialValueProbe(
					name: "\(names.fill) built in a @Sendable function holds \(names.caller).\(value)",
					expression: holdsCallersWrapper("\(caller).mock()", fill: builtInSendableFunction),
					knownRightExpression: holdsCallersWrapper("\(caller)()", fill: builtInSendableFunction),
				))
			}
		}
		return probes
	}

	/// The probe of the fill that holds a builder of the enclosing called type: the calling mock against the twin's seam
	/// initializer, as one tuple of the caller and the called type the third module's type builds through its builder, or
	/// holds, inside the fill of the caller's place (for a deferred place, the fill its builder builds for `id` 7, and,
	/// in the re-entered called type, what its own place's builder builds for `id` 7). The comparator follows no
	/// instantiator, so only building through the builder runs the level function the call inside the fill re-enters.
	private var enclosingBuilderProbes: [DifferentialValueProbe] {
		let caller = "\(names.callerModuleName).\(names.caller)"
		let fill = "\(names.callerModuleName).\(names.fill)"
		let builder = enclosingBuilder ?? .instantiator
		let placeLabel = holePlace(protocolName: names.hole, fillName: names.fill).label
		let place = "\(names.inner.lowercasedFirst).\(placeLabel)"
		let filled = switch cell.place {
		case .plain:
			"caller.\(place)"
		case .deferred:
			"caller.\(place).instantiate(7)"
		}
		let reentered = builder.builtValue(of: "(\(filled) as! \(fill)).\(names.outer.lowercasedFirst)", label: builder.label(of: names.inner))
		// Where the fill instantiates what nothing fulfills, both calls hand its builder the stub.
		let stub = "{ \(names.callerModuleName).\(Self.beaconStub)() }"
		let calls = if reenteringFillInstantiatesWhatNothingFulfills {
			(mock: "\(caller).mock(\(beaconBuilderLabel): \(stub))", twin: "\(caller)(\(beaconBuilderLabel): \(stub))")
		} else {
			(mock: "\(caller).mock()", twin: "\(caller)()")
		}
		func probe(of call: String) -> String {
			switch cell.place {
			case .plain:
				"{ let caller = \(call); return (caller, \(reentered)) }()"
			case .deferred:
				"{ let caller = \(call); let reentered = \(reentered); return (caller, \(filled), reentered, reentered.\(placeLabel).instantiate(7)) }()"
			}
		}
		let name = switch cell.place {
		case .plain:
			"(\(caller), re-entered \(names.inner))"
		case .deferred:
			"(\(caller), \(caller).\(place).instantiate(7), re-entered \(names.inner), its \(placeLabel).instantiate(7))"
		}
		let wholeProbe = DifferentialValueProbe(name: name, expression: probe(of: calls.mock), knownRightExpression: probe(of: calls.twin))
		guard let wrapper = enclosingCalledTypeLazyValueWrapper else { return [wholeProbe] }
		// Where the enclosing called type receives the caller's lazily held value, whether it and the one built again hold the
		// caller's instance, in a probe of its own, so its reads of the instances leave the first probe's wrappers unread.
		let value = names.value.lowercasedFirst
		let inner = names.inner.lowercasedFirst
		func instanceProbe(of call: String) -> String {
			"{ let caller = \(call); let reentered = \(reentered); return (caller.\(inner).\(value)?.instance === caller.\(value).instance, reentered.\(value)?.instance === caller.\(value).instance) }()"
		}
		let instanceProbe = DifferentialValueProbe(name: "(\(names.inner) holds the caller’s \(value), re-entered \(names.inner) holds it)", expression: instanceProbe(of: calls.mock), knownRightExpression: instanceProbe(of: calls.twin))
		// A `LazilyInstantiated`'s state, which the comparator describes, differs by two known differences of a call of a public
		// mock (`public-mock-builders.md`, "A lazy value a call hands over"): the call reads the caller's wrapper at the call,
		// and the called mock wraps the instance again, in a wrapper whose instance nothing has read. So beside it only the
		// instances are compared. A `SendableLazilyInstantiated` keeps its state where the comparator cannot see it.
		return wrapper == "LazilyInstantiated" ? [instanceProbe] : [wholeProbe, instanceProbe]
	}

	/// The second place's protocol, the label of the level that holds it and its own, and the type that fills it, of the
	/// shape whose fill receives the caller's lazy value below the called type's root (`CallerLazyValue.secondPlaceCallsAgain`).
	static let secondPlaceProtocol = "Navigator"
	static let secondLevelLabel = "hub"
	static let secondPlaceLabel = "navigator"
	static let secondFillName = "LiveNavigator"

	/// An expression of the caller `call` builds and the fill its deferred place `place` builds for `id` 7, as one tuple, so
	/// the comparator identifies a value the fill receives against the caller's own.
	static func callerAndFill(of call: String, place: String) -> String {
		"{ let caller = \(call); return (caller, caller.\(place).instantiate(7)) }()"
	}

	/// Where production reports the shape's own error: the module and file, and the declaration the error is at.
	var expectedTwinErrorSite: (file: String, declaration: String)? {
		let names = names
		switch cell.shape {
		case .outerSeamValue:
			return ("\(names.callerModuleName)/\(names.callerModuleName)Types.swift", "@Received let \(names.value.lowercasedFirst): \(names.value)")
		case .appOnlyScreenInLoop:
			return ("App/AppTypes.swift", "@Received private let \(names.feed.lowercasedFirst)Builder: ErasedInstantiator<(), any \(names.feedPage)>")
		case .seamBuiltAgain:
			return ("App/AppTypes.swift", "@Received let \(names.value.lowercasedFirst): \(names.value)")
		case .loopThroughInnerSeamBuilder:
			return ("\(names.outerModuleName)/\(names.outerModuleName)Types.swift", "@Received let \(names.inner.lowercasedFirst)Builder: Instantiator<\(names.inner)>")
		case .fillReceivesValueBuildingTheCall:
			return ("\(names.callerModuleName)/\(names.callerModuleName)Types.swift", "@Received let \(names.sibling.lowercasedFirst): \(names.sibling)")
		case .fillInstantiatesTypeNoDeclarationCanFulfill, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive:
			return fillHoles?.spellingNoHoleCanHave.map { ("\(names.callerModuleName)/\(names.callerModuleName)Types.swift", "@Instantiated let \($0.label): \($0.type)") }
		case .fillRequiresValueCalledTypeReceivesInOptionalWrapper:
			// The seam's tree receives the label in two forms, which production reports at the called type's declaration.
			return ("\(names.innerModuleName)/\(names.innerModuleName)Types.swift", "@Instantiable(generateDependencyTree: true, generateMock: .public)")
		case .fillConstructsTypeCallerModuleCannotReach:
			// The type's declaration, in the outer module's file, where production reports an error at all.
			return unreachableConstruction.flatMap { $0.access.twinReportsError ? ("\(names.outerModuleName)/\(names.outerModuleName)Types.swift", $0.typeDeclarationLine) : nil }
		case .callersOwnValue, .placeInstantiatedOnlyIfAvailable, .calledTypeHoldsPlaceLazily, .calledTypeHoldsSecondHoleType, .callerForwardsValueFillReads, .calledTypeReceivesValueOnlyIfAvailableNothingProvides, .noVisibleImplementation, .implementationReceivesWhatNothingProvides, .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot, .fillHoldsBuilderOfEnclosingCalledType, .fillCallsMockTakingGuardedValueWhereMockConditionIsInactive:
			return nil
		}
	}

	typealias File = GraphFuzzerCallingMockGraph.File

	/// The draw's files, in dependency order, with each file's content by module and file name.
	func files(_ form: Form) -> [File] {
		switch cell.shape {
		case .outerSeamValue, .loopThroughInnerSeamBuilder, .callersOwnValue, .placeInstantiatedOnlyIfAvailable, .calledTypeHoldsPlaceLazily, .calledTypeHoldsSecondHoleType, .callerForwardsValueFillReads, .calledTypeReceivesValueOnlyIfAvailableNothingProvides, .noVisibleImplementation, .implementationReceivesWhatNothingProvides, .fillReceivesValueBuildingTheCall, .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder, .fillInstantiatesTypeNoDeclarationCanFulfill, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive, .fillReceivesValueOnlyInnerMockRequires, .fillHoldsBuilderOfEnclosingCalledType, .fillCallsMockTakingGuardedValueWhereMockConditionIsInactive:
			[
				File(module: names.innerModuleName, dependencies: [], content: innerModuleContent(form)),
				File(module: names.outerModuleName, dependencies: [names.innerModuleName], content: outerModuleContent),
				File(module: names.callerModuleName, dependencies: [names.innerModuleName, names.outerModuleName], content: callerModuleContent(form)),
			]
		case .appOnlyScreenInLoop:
			[
				File(module: "Feature", dependencies: [], content: signedInModuleContent),
				File(module: "App", dependencies: ["Feature"], content: appOnlyScreenCallerContent(form)),
			]
		case .seamBuiltAgain:
			[
				File(module: "Feature", dependencies: [], content: reentrantSeamModuleContent),
				File(module: "App", dependencies: ["Feature"], content: reentrantSeamCallerContent(form)),
			]
		case .calledTypesReceivedValueInSendablePlace:
			[
				File(module: names.innerModuleName, dependencies: [], content: sendablePlaceModuleContent),
				File(module: names.callerModuleName, dependencies: [names.innerModuleName], content: sendablePlaceCallerContent(form)),
			]
		case .fillReceivesCallersLazyValueBelowCalledRoot:
			[
				File(module: names.innerModuleName, dependencies: [], content: lazyValueBelowCalledRootModuleContent),
				File(module: names.callerModuleName, dependencies: [names.innerModuleName], content: lazyValueBelowCalledRootCallerContent(form)),
			]
		case .fillRequiresValueCalledTypeReceivesInOptionalWrapper:
			[
				File(module: names.innerModuleName, dependencies: [], content: optionalWrapperValueModuleContent),
				File(module: names.callerModuleName, dependencies: [names.innerModuleName], content: optionalWrapperValueCallerContent(form)),
			]
		case .fillConstructsTypeCallerModuleCannotReach:
			// The outer module, which declares the type the caller's module cannot reach, is in the caller's package or in
			// another.
			[
				File(module: names.innerModuleName, dependencies: [], content: innerModuleContent(form)),
				File(module: names.outerModuleName, dependencies: [names.innerModuleName], content: outerModuleContent, packageName: unreachableConstruction?.outerModulePackageName ?? GraphFuzzerCallingMockGraph.packageName),
				File(module: names.callerModuleName, dependencies: [names.innerModuleName, names.outerModuleName], content: callerModuleContent(form)),
			]
		}
	}

	// MARK: Names

	/// The names a seed draws, so that ten graphs of a cell differ in everything but their shape.
	struct Names {
		init(random: inout GraphFuzzerRandomNumberGenerator) {
			let index = random.integer(in: 0...4)
			hole = ["Api", "Store", "Tracker", "Gateway", "Feed"][index] + "Service"
			fill = random.element(of: ["Fake", "Live", "Stub"]) + ["Api", "Store", "Tracker", "Gateway", "Feed"][index]
			inner = random.element(of: ["Inner", "Panel", "Widget"])
			outer = random.element(of: ["Feature", "Dashboard", "Profile"])
			value = random.element(of: ["Database", "Session", "Cache", "Logger"])
			caller = random.element(of: ["Host", "Shell", "Screen"])
			token = random.element(of: ["Token", "Secret"])
			ticker = random.element(of: ["Ticker", "Metronome"])
			sibling = random.element(of: ["Sibling", "Relay"])
			feedPage = random.element(of: ["FeedPage", "HomePage"])
			settingsPage = random.element(of: ["SettingsPage", "AccountPage"])
			feed = random.element(of: ["Feed", "Timeline"])
			settings = random.element(of: ["AppSettings", "AppAccount"])
			signedIn = random.element(of: ["SignedIn", "Session"])
			repeated = random.element(of: ["Service", "Coordinator"])
			between = random.element(of: ["Step", "Stage"])
		}

		let hole: String
		let fill: String
		let inner: String
		let outer: String
		let value: String
		let caller: String
		let token: String
		let ticker: String
		let sibling: String
		let feedPage: String
		let settingsPage: String
		let feed: String
		let settings: String
		let signedIn: String
		let repeated: String
		let between: String

		let innerModuleName = "InnerModule"
		let outerModuleName = "FeatureModule"
		let callerModuleName = "Tests"
	}

	let names: Names

	/// Where the caller declares a leaf of its own beside the property that leads to the hole, which changes no
	/// outcome.
	enum TickerPosition: CaseIterable {
		case none
		case before
		case after
	}

	let tickerPosition: TickerPosition

	/// For the shape whose fill instantiates what nothing fulfills, what it instantiates and where.
	struct FillHoles {
		init(random: inout GraphFuzzerRandomNumberGenerator, drawsSpellingNoHoleCanHave: Bool) {
			fulfillerIsSeam = random.element(of: [false, true])
			calledTypeIsSeam = random.element(of: [false, true])
			depth = random.integer(in: 1...2)
			isInsideSendableFunction = depth == 2 && random.element(of: [false, true])
			isErasedInstantiator = random.element(of: [false, true])
			placeCount = random.integer(in: 1...2)
			holeTypeCount = random.integer(in: 1...2)
			gizmo = random.element(of: ["Gizmo", "Gadget"])
			widget = random.element(of: ["Knob", "Dial"])
			// Drawn last, so the graphs that draw none are drawn as before it.
			spellingNoHoleCanHave = drawsSpellingNoHoleCanHave
				? random.element(of: [("names", "[String]"), ("lookup", "[String: Int]"), ("make", "() -> Int"), ("pair", "(Int, Int)")])
				: nil
		}

		/// Whether the implementation that fills the called mock's place is a seam, whose holes the types it instantiates
		/// are, or a plain type.
		let fulfillerIsSeam: Bool
		/// Whether the called type is declared a seam as well as a public mock in the calling mock's form (its twin's always is).
		let calledTypeIsSeam: Bool
		/// 1 where the implementation instantiates the types itself, 2 where `Part`, which it instantiates, does.
		let depth: Int
		/// Whether `Part` is held in a `SendableInstantiator`, so the types are built inside its `@Sendable` builder function.
		let isInsideSendableFunction: Bool
		/// Whether each type is instantiated as an `ErasedInstantiator<Int, any P>` that a type no declaration fulfills names,
		/// rather than as `any P`.
		let isErasedInstantiator: Bool
		/// The number of places of each hole type.
		let placeCount: Int
		/// The number of hole types: `gizmo`'s, and `widget`'s.
		let holeTypeCount: Int
		let gizmo: String
		let widget: String
		/// A property the types' instantiating type also instantiates, of a type spelled as no hole can be, which no
		/// declaration fulfills.
		let spellingNoHoleCanHave: (label: String, type: String)?

		/// The protocols the types are, in order.
		var protocols: [String] {
			Array([gizmo, widget].prefix(holeTypeCount))
		}

		/// The type an erased instantiator of `protocolName` names, and the stub a probe builds a value of it with.
		func stub(of protocolName: String) -> String {
			"Stub\(protocolName)"
		}

		/// The properties that instantiate the types: one or two per protocol.
		var properties: [(label: String, type: String, attribute: String)] {
			var properties = protocols.flatMap { protocolName in
				(1...placeCount).map { index in
					let suffix = index == 1 ? "" : "\(index)"
					return isErasedInstantiator
						? ("make\(protocolName)\(suffix)", "ErasedInstantiator<Int, any \(protocolName)>", "@Instantiated(fulfilledByType: \"\(stub(of: protocolName))\")")
						: ("\(protocolName.lowercasedFirst)\(suffix)", "any \(protocolName)", "@Instantiated")
				}
			}
			if let spellingNoHoleCanHave {
				properties.append((spellingNoHoleCanHave.label, spellingNoHoleCanHave.type, "@Instantiated"))
			}
			return properties
		}

		/// The builders the twin's seam initializer and the calling mock take, by label, each with the value a probe hands it.
		var builders: [(label: String, value: (_ module: String) -> String)] {
			protocols.map { protocolName in
				let stem = isErasedInstantiator
					? String(GraphFuzzerPublicMockDraw.builderLabel(ofTypeNamed: stub(of: protocolName)).dropLast("Builder".count)) + "_\(protocolName)"
					: String(GraphFuzzerPublicMockDraw.builderLabel(ofTypeNamed: protocolName).dropLast("Builder".count))
				let label = stem + (isInsideSendableFunction ? "SendableBuilder" : "Builder")
				let stubName = stub(of: protocolName)
				return (label, { module in isErasedInstantiator ? "{ \(module).\(stubName)(id: $0) }" : "{ \(module).\(stubName)(id: 0) }" })
			}
			.sorted { $0.label < $1.label }
		}
	}

	let fillHoles: FillHoles?

	// MARK: Content

	private var callerIsPublic: Bool {
		cell.callerIsPublic
	}

	/// What a public caller's declarations spell before `final class` and `init`.
	private var callerAccess: String {
		callerIsPublic ? "public " : ""
	}

	private func callerAttribute(_ form: Form) -> String {
		guard cell.shape != .seamCallerFillSharesBuilder || form == .twin else { return "@Instantiable(generateDependencyTree: true, generateMock: true)" }
		return switch (form, cell.caller) {
		case (.mock, .internal):
			"@Instantiable(generateMock: true)"
		case (.mock, .public):
			"@Instantiable(generateMock: .public)"
		case (.mock, .listed):
			"@Instantiable"
		case (.twin, .internal), (.twin, .public), (.twin, .listed):
			"@Instantiable(generateDependencyTree: true)"
		}
	}

	/// The `SafeDIConfiguration.swift` of the calling mock's module that lists a listed caller, or `nil`.
	var mockConfiguration: String? {
		switch cell.caller {
		case .listed:
			"import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"\(names.caller)\"])\n"
		case .internal, .public:
			nil
		}
	}

	/// The hole's place on a public mock: `p: any P`, or `pBuilder: ErasedInstantiator<Int, any P>` that the fill type
	/// fulfills by name.
	private func holePlace(protocolName: String, fillName: String) -> (label: String, type: String, attribute: String) {
		guard optionalPlace == nil else {
			return (protocolName.lowercasedFirst, "(any \(protocolName))?", "@Instantiated(onlyIfAvailable: true)")
		}
		return switch cell.place {
		case .plain:
			// Beside a place in another form, filled by the same type by name, as an erased instantiator's must be.
			(protocolName.lowercasedFirst, "any \(protocolName)", callsMixedFormMock ? "@Instantiated(fulfilledByType: \"\(fillName)\")" : "@Instantiated")
		case .deferred:
			("\(protocolName.lowercasedFirst)Builder", "ErasedInstantiator<Int, any \(protocolName)>", "@Instantiated(fulfilledByType: \"\(fillName)\")")
		}
	}

	private func innerModuleContent(_ form: Form) -> String {
		guard cell.shape != .fillReceivesValueOnlyInnerMockRequires else { return valueRequiringInnerModuleContent }
		let place = holePlace(protocolName: names.hole, fillName: names.fill)
		// A seam caller's own production tree calls the called type's seam, so its graphs declare the called type a seam.
		let attribute = form == .mock && fillHoles?.calledTypeIsSeam == false && cell.shape != .seamCallerFillSharesBuilder
			? "@Instantiable(generateMock: .public)"
			: "@Instantiable(generateDependencyTree: true, generateMock: .public)"
		var content: String
		if let wrapper = enclosingCalledTypeLazyValueWrapper {
			// The enclosing called type receives the caller's value only if available, as an optional wrapper.
			let value = names.value.lowercasedFirst
			content = """
			import SafeDI

			public protocol \(names.hole): AnyObject {}

			@Instantiable
			public final class \(names.value): Instantiable, Sendable {
			    public init() {}
			}

			\(attribute)
			public final class \(names.inner): Instantiable {
			    init(\(place.label): \(place.type), \(value): \(wrapper)<\(names.value)>?) { self.\(place.label) = \(place.label); self.\(value) = \(value) }
			    \(place.attribute) public let \(place.label): \(place.type)
			    @Received(onlyIfAvailable: true) public let \(value): \(wrapper)<\(names.value)>?
			}
			"""
		} else {
			content = """
			import SafeDI

			public protocol \(names.hole): AnyObject {}

			\(attribute)
			public final class \(names.inner): Instantiable {
			    init(\(place.label): \(place.type)) { self.\(place.label) = \(place.label) }
			    \(place.attribute) public let \(place.label): \(place.type)
			}
			"""
		}
		if let valueNothingProvides {
			// The called type, or `Gauge` beneath it, receives a value only if available that nothing declares.
			let token = names.token.lowercasedFirst
			let receive = "@Received(onlyIfAvailable: true) public let \(token): \(names.token)?"
			let declarations = if valueNothingProvides.receiverIsBeneathCalledType {
				"""
				@Instantiable
				public final class Gauge: Instantiable {
				    public init(\(token): \(names.token)?) { self.\(token) = \(token) }
				    \(receive)
				}

				\(attribute)
				public final class \(names.inner): Instantiable {
				    init(\(place.label): \(place.type), gauge: Gauge) { self.\(place.label) = \(place.label); self.gauge = gauge }
				    \(place.attribute) public let \(place.label): \(place.type)
				    @Instantiated public let gauge: Gauge
				}
				"""
			} else {
				"""
				\(attribute)
				public final class \(names.inner): Instantiable {
				    init(\(place.label): \(place.type), \(token): \(names.token)?) { self.\(place.label) = \(place.label); self.\(token) = \(token) }
				    \(place.attribute) public let \(place.label): \(place.type)
				    \(receive)
				}
				"""
			}
			content = """
			import SafeDI

			public protocol \(names.hole): AnyObject {}

			public final class \(names.token) {
			    public init() {}
			}

			\(declarations)
			"""
		}
		if let lazyPlace {
			// The called type holds its place lazily, now and then beside a place of the hole by value.
			var places = [(label: "\(place.label)Lazy", type: "\(lazyPlace.wrapper)<any \(names.hole)>", attribute: "@Instantiated")]
			if lazyPlace.besideByValuePlace {
				places.insert(place, at: 0)
			}
			// A `SendableLazilyInstantiated`'s instance is `Sendable`.
			let conformances = lazyPlace.wrapper == "SendableLazilyInstantiated" ? "AnyObject, Sendable" : "AnyObject"
			content = """
			import SafeDI

			public protocol \(names.hole): \(conformances) {}

			\(innerTypeDeclaration(attribute: attribute, places: places))
			"""
		}
		if let secondHole {
			// The called type also holds a place of a second hole type, before or after the first, and the module declares the
			// stub a probe's builder of that place returns.
			let secondPlace = holePlace(protocolName: SecondHole.protocolName, fillName: SecondHole.fillName)
			content = """
			import SafeDI

			public protocol \(names.hole): AnyObject {}

			public protocol \(SecondHole.protocolName): AnyObject {}

			public final class \(SecondHole.stubName): \(SecondHole.protocolName) {
			    public init() {}
			}

			\(innerTypeDeclaration(attribute: attribute, places: secondHole.isBeforeFirstPlace ? [secondPlace, place] : [place, secondPlace]))
			"""
		}
		if callsMixedFormMock {
			let mixedPlace = mixedFormPlace
			content += """


			\(attribute)
			public final class \(Self.mixedFormTypeName): Instantiable {
			    init(\(mixedPlace.label): \(mixedPlace.type)) { self.\(mixedPlace.label) = \(mixedPlace.label) }
			    \(mixedPlace.attribute) public let \(mixedPlace.label): \(mixedPlace.type)
			}
			"""
		}
		return content
	}

	/// The called type's declaration, holding `places` in order.
	private func innerTypeDeclaration(attribute: String, places: [(label: String, type: String, attribute: String)]) -> String {
		let parameters = places.map { "\($0.label): \($0.type)" }.joined(separator: ", ")
		let assignments = places.map { "self.\($0.label) = \($0.label)" }.joined(separator: "; ")
		return """
		\(attribute)
		public final class \(names.inner): Instantiable {
		    init(\(parameters)) { \(assignments) }
		\(places.map { "    \($0.attribute) public let \($0.label): \($0.type)" }.joined(separator: "\n"))
		}
		"""
	}

	/// The inner module where only an inner public mock requires the value the fill receives: the hole's protocol, the value,
	/// and the inner type, whose internal initializer the called type's module cannot call, which requires the value and
	/// instantiates a `Gauge`, so that it has a tree to build.
	private var valueRequiringInnerModuleContent: String {
		let value = names.value.lowercasedFirst
		return """
		import SafeDI

		public protocol \(names.hole): AnyObject {}

		@Instantiable
		public final class \(names.value): Instantiable {
		    public init() {}
		}

		@Instantiable
		public final class Gauge: Instantiable {
		    public init() {}
		}

		@Instantiable(generateDependencyTree: true, generateMock: .public)
		public final class \(names.inner): Instantiable {
		    init(\(value): \(names.value), gauge: Gauge) { self.\(value) = \(value); self.gauge = gauge }
		    @Received public let \(value): \(names.value)
		    @Instantiated public let gauge: Gauge
		}
		"""
	}

	private var outerModuleContent: String {
		switch cell.shape {
		case .loopThroughInnerSeamBuilder:
			let builder = "\(names.inner.lowercasedFirst)Builder"
			let sibling = names.sibling.lowercasedFirst
			return """
			import SafeDI
			import \(names.innerModuleName)

			@Instantiable(generateDependencyTree: true, generateMock: .public)
			public final class \(names.outer): Instantiable {
			    init(\(builder): Instantiator<\(names.inner)>, \(sibling): \(names.sibling)) { self.\(builder) = \(builder); self.\(sibling) = \(sibling) }
			    @Instantiated public let \(builder): Instantiator<\(names.inner)>
			    @Instantiated public let \(sibling): \(names.sibling)
			}

			@Instantiable
			public final class \(names.sibling): Instantiable {
			    init(\(builder): Instantiator<\(names.inner)>) { self.\(builder) = \(builder) }
			    @Received let \(builder): Instantiator<\(names.inner)>
			}
			"""
		case .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder, .fillInstantiatesTypeNoDeclarationCanFulfill, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive:
			// No seam of this module builds the called type, which the calling mock's form may declare a public mock only.
			return """
			import SafeDI
			import \(names.innerModuleName)

			@Instantiable
			public final class \(names.value): Instantiable {
			    public init() {}
			}
			"""
		case .fillReceivesValueOnlyInnerMockRequires:
			// The called type holds the place, a type that receives the value only if available, and the inner type, which
			// requires it.
			let place = holePlace(protocolName: names.hole, fillName: names.fill)
			let value = names.value.lowercasedFirst
			let sibling = names.sibling.lowercasedFirst
			let inner = names.inner.lowercasedFirst
			return """
			import SafeDI
			import \(names.innerModuleName)

			@Instantiable
			public final class \(names.sibling): Instantiable {
			    public init(\(value): \(names.value)?) { self.\(value) = \(value) }
			    @Received(onlyIfAvailable: true) public let \(value): \(names.value)?
			}

			@Instantiable(generateDependencyTree: true, generateMock: .public)
			public final class \(names.outer): Instantiable {
			    init(\(place.label): \(place.type), \(sibling): \(names.sibling), \(inner): \(names.inner)) { self.\(place.label) = \(place.label); self.\(sibling) = \(sibling); self.\(inner) = \(inner) }
			    \(place.attribute) public let \(place.label): \(place.type)
			    @Instantiated public let \(sibling): \(names.sibling)
			    @Instantiated public let \(inner): \(names.inner)
			}
			"""
		case .fillConstructsTypeCallerModuleCannotReach:
			// The value the caller builds, and the type the caller's module cannot reach, which alone fulfills a public protocol.
			return """
			import SafeDI
			import \(names.innerModuleName)

			@Instantiable
			public final class \(names.value): Instantiable {
			    public init() {}
			}

			\(unreachableConstruction?.declarations ?? "")
			"""
		case .fillHoldsBuilderOfEnclosingCalledType:
			// The type the fill builds, whose public mock holds a builder of the enclosing called type, the inner type, whose
			// place the fill fills.
			let builder = enclosingBuilder ?? .instantiator
			let label = builder.label(of: names.inner)
			let type = builder.wrapperType(of: names.inner)
			return """
			import SafeDI
			import \(names.innerModuleName)

			@Instantiable(generateDependencyTree: true, generateMock: .public)
			public final class \(names.outer): Instantiable {
			    init(\(label): \(type)) { self.\(label) = \(label) }
			    @Instantiated public let \(label): \(type)
			}
			"""
		case .outerSeamValue, .callersOwnValue, .placeInstantiatedOnlyIfAvailable, .calledTypeHoldsPlaceLazily, .calledTypeHoldsSecondHoleType, .callerForwardsValueFillReads, .calledTypeReceivesValueOnlyIfAvailableNothingProvides, .noVisibleImplementation, .implementationReceivesWhatNothingProvides, .appOnlyScreenInLoop, .seamBuiltAgain, .fillReceivesValueBuildingTheCall, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot, .fillRequiresValueCalledTypeReceivesInOptionalWrapper, .fillCallsMockTakingGuardedValueWhereMockConditionIsInactive:
			let value = names.value.lowercasedFirst
			let inner = names.inner.lowercasedFirst
			return """
			import SafeDI
			import \(names.innerModuleName)

			@Instantiable
			public final class \(names.value): Instantiable {
			    public init() {}
			}

			@Instantiable(generateDependencyTree: true, generateMock: .public)
			public final class \(names.outer): Instantiable {
			    init(\(value): \(names.value), \(inner): \(names.inner)) { self.\(value) = \(value); self.\(inner) = \(inner) }
			    @Instantiated public let \(value): \(names.value)
			    @Instantiated public let \(inner): \(names.inner)
			}
			"""
		}
	}

	/// The fill's declaration, receiving `received` (a label and type) when given, instantiating `instantiated` when given,
	/// forwarding `id: Int` for a deferred place, and fulfilling `protocolName` by name or through
	/// `fulfillingAdditionalTypes`.
	private func fillDeclaration(named fillName: String, protocolName: String, received: (label: String, type: String)?, receivedOnlyIfAvailable: Bool = false, instantiated: [(label: String, type: String)] = [], isPublic: Bool) -> String {
		var parameters = [String]()
		var assignments = [String]()
		var properties = [String]()
		if cell.place == .deferred {
			parameters.append("id: Int")
			assignments.append("self.id = id")
			properties.append("@Forwarded let id: Int")
		}
		if let received {
			parameters.append("\(received.label): \(received.type)")
			assignments.append("self.\(received.label) = \(received.label)")
			properties.append("\(receivedOnlyIfAvailable ? "@Received(onlyIfAvailable: true)" : "@Received") let \(received.label): \(received.type)")
		}
		for instantiated in instantiated {
			parameters.append("\(instantiated.label): \(instantiated.type)")
			assignments.append("self.\(instantiated.label) = \(instantiated.label)")
			properties.append("@Instantiated let \(instantiated.label): \(instantiated.type)")
		}
		let attribute = cell.place == .deferred ? "@Instantiable" : "@Instantiable(fulfillingAdditionalTypes: [(any \(protocolName)).self])"
		let access = isPublic ? "public " : ""
		let initializer = assignments.isEmpty ? "\(access)init() {}" : "\(access)init(\(parameters.joined(separator: ", "))) { \(assignments.joined(separator: "; ")) }"
		return """
		\(attribute)
		\(access)final class \(fillName): \(protocolName), Instantiable {
		    \(initializer)
		\(properties.map { "    \($0)" }.joined(separator: "\n"))
		}
		"""
		// An initializer with no properties leaves a blank line, which changes nothing the tool reads.
		.replacingOccurrences(of: "\n\n}", with: "\n}")
	}

	/// The fill's declaration of the shape whose fill's hand-written mock takes a value only an inactive clause declares: as
	/// `fillDeclaration`'s receiving the caller's value, with an `#if condition` block whose clause declares an initializer
	/// that also takes `guarded<Token>`, which the clause receives, and whose `#else` declares the initializer without it,
	/// and a hand-written mock under `#if DEBUG` that takes every value either clause declares and builds the fill as the
	/// clause the compiler selects does.
	private func guardedValueFillDeclaration(condition: String) -> String {
		let fill = names.fill
		let value = (label: names.value.lowercasedFirst, type: names.value)
		let guarded = (label: "guarded\(names.token)", type: names.token)
		var parameters = [String]()
		var properties = [String]()
		if cell.place == .deferred {
			parameters.append("id: Int")
			properties.append("@Forwarded let id: Int")
		}
		parameters.append("\(value.label): \(value.type)")
		properties.append("@Received let \(value.label): \(value.type)")
		let guardedParameters = parameters + ["\(guarded.label): \(guarded.type)"]
		let assignments = parameters.map { "self.\($0.prefix { $0 != ":" }) = \($0.prefix { $0 != ":" })" }
		let arguments = parameters.map { "\($0.prefix { $0 != ":" }): \($0.prefix { $0 != ":" })" }
		let attribute = cell.place == .deferred ? "@Instantiable" : "@Instantiable(fulfillingAdditionalTypes: [(any \(names.hole)).self])"
		return """
		\(attribute)
		\(callerAccess)final class \(fill): \(names.hole), Instantiable {
		    #if \(condition)
		    \(callerAccess)init(\(guardedParameters.joined(separator: ", "))) { \((assignments + ["self.\(guarded.label) = \(guarded.label)"]).joined(separator: "; ")) }
		    @Received let \(guarded.label): \(guarded.type)
		    #else
		    \(callerAccess)init(\(parameters.joined(separator: ", "))) { \(assignments.joined(separator: "; ")) }
		    #endif
		\(properties.map { "    \($0)" }.joined(separator: "\n"))

		    #if DEBUG
		    \(callerAccess)static func mock(\(guardedParameters.joined(separator: ", "))) -> \(fill) {
		        #if \(condition)
		        \(fill)(\((arguments + ["\(guarded.label): \(guarded.label)"]).joined(separator: ", ")))
		        #else
		        \(fill)(\(arguments.joined(separator: ", ")))
		        #endif
		    }
		    #endif
		}
		"""
	}

	/// The declarations of the shape whose fill instantiates what nothing fulfills: the protocols of the types nothing
	/// fulfills and their stubs, which are no SafeDI declarations, `Part` where the types are instantiated one level beneath
	/// the implementation, and the implementation, a seam or a plain type, that fills the called mock's place.
	private func fillHolesDeclarations(_ fillHoles: FillHoles) -> [String] {
		var declarations = [String]()
		for protocolName in fillHoles.protocols {
			declarations.append("""
			public protocol \(protocolName): AnyObject {}

			public final class \(fillHoles.stub(of: protocolName)): \(protocolName) {
			    public init(id: Int) {}
			}
			""")
		}
		let properties = fillHoles.properties
		let instantiating = """
		    public init(\(properties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) { \(properties.map { "self.\($0.label) = \($0.label)" }.joined(separator: "; ")) }
		\(properties.map { "    \($0.attribute) let \($0.label): \($0.type)" }.joined(separator: "\n"))
		"""
		var fillProperties = [(label: String, type: String, attribute: String)]()
		if fillHoles.depth == 2 {
			declarations.append("""
			@Instantiable
			public final class Part: Instantiable {
			\(instantiating)
			}
			""")
			fillProperties.append(("part", fillHoles.isInsideSendableFunction ? "SendableInstantiator<Part>" : "Part", "@Instantiated"))
		} else {
			fillProperties = properties
		}
		var parameters = [String]()
		var assignments = [String]()
		var lines = [String]()
		if cell.place == .deferred {
			parameters.append("id: Int")
			assignments.append("self.id = id")
			lines.append("@Forwarded let id: Int")
		}
		for property in fillProperties {
			parameters.append("\(property.label): \(property.type)")
			assignments.append("self.\(property.label) = \(property.label)")
			lines.append("\(property.attribute) let \(property.label): \(property.type)")
		}
		var arguments = fillHoles.fulfillerIsSeam ? ["generateDependencyTree: true"] : []
		if cell.place == .plain {
			arguments.append("fulfillingAdditionalTypes: [(any \(names.hole)).self]")
		}
		declarations.append("""
		\(arguments.isEmpty ? "@Instantiable" : "@Instantiable(\(arguments.joined(separator: ", ")))")
		\(callerAccess)final class \(names.fill): \(names.hole), Instantiable {
		    \(callerAccess)init(\(parameters.joined(separator: ", "))) { \(assignments.joined(separator: "; ")) }
		\(lines.map { "    \($0)" }.joined(separator: "\n"))
		}
		""")
		return declarations
	}

	/// The caller's declaration: `forwarded`, each `@Forwarded`, then its properties, each `@Instantiated`, with the ticker
	/// where the draw puts it.
	private func callerDeclaration(_ form: Form, properties: [(label: String, type: String)], forwarded: [(label: String, type: String)] = []) -> String {
		var properties = properties
		let ticker = (label: names.ticker.lowercasedFirst, type: names.ticker)
		switch tickerPosition {
		case .none:
			break
		case .before:
			properties.insert(ticker, at: 0)
		case .after:
			properties.append(ticker)
		}
		let parameters = (forwarded + properties).map { "\($0.label): \($0.type)" }.joined(separator: ", ")
		let assignments = (forwarded + properties).map { "self.\($0.label) = \($0.label)" }.joined(separator: "; ")
		var lines = [String]()
		if tickerPosition != .none {
			lines += [
				"@Instantiable",
				"\(callerAccess)final class \(names.ticker): Instantiable {",
				"    \(callerAccess)init() {}",
				"}",
				"",
			]
		}
		lines += [
			callerAttribute(form),
			"\(callerAccess)final class \(names.caller): Instantiable {",
			"    \(callerAccess)init(\(parameters)) { \(assignments) }",
		]
		lines += forwarded.map { "    @Forwarded let \($0.label): \($0.type)" }
		lines += properties.map { "    @Instantiated let \($0.label): \($0.type)" }
		lines.append("}")
		return lines.joined(separator: "\n")
	}

	private func callerModuleContent(_ form: Form) -> String {
		var declarations = [String]()
		switch cell.shape {
		case .outerSeamValue:
			declarations.append(fillDeclaration(named: names.fill, protocolName: names.hole, received: (names.value.lowercasedFirst, names.value), isPublic: callerIsPublic))
			declarations.append(callerDeclaration(form, properties: [(names.outer.lowercasedFirst, names.outer)]))
		case .loopThroughInnerSeamBuilder:
			declarations.append(fillDeclaration(named: names.fill, protocolName: names.hole, received: (names.sibling.lowercasedFirst, names.sibling), isPublic: callerIsPublic))
			declarations.append(callerDeclaration(form, properties: [(names.outer.lowercasedFirst, names.outer)]))
		case .callersOwnValue, .calledTypeReceivesValueOnlyIfAvailableNothingProvides:
			declarations.append(fillDeclaration(named: names.fill, protocolName: names.hole, received: (names.value.lowercasedFirst, names.value), isPublic: callerIsPublic))
			declarations.append(callerDeclaration(form, properties: [(names.value.lowercasedFirst, names.value), (names.inner.lowercasedFirst, names.inner)]))
		case .placeInstantiatedOnlyIfAvailable:
			if implementationIsVisible {
				declarations.append(fillDeclaration(named: names.fill, protocolName: names.hole, received: (names.value.lowercasedFirst, names.value), isPublic: callerIsPublic))
			}
			declarations.append(callerDeclaration(form, properties: [(names.value.lowercasedFirst, names.value), (names.inner.lowercasedFirst, names.inner)]))
		case .calledTypeHoldsPlaceLazily:
			// A fill a `@Sendable` function builds reads nothing.
			let received = lazyPlace?.fillReadsValue == false ? nil : (label: names.value.lowercasedFirst, type: names.value)
			declarations.append(fillDeclaration(named: names.fill, protocolName: names.hole, received: received, isPublic: callerIsPublic))
			declarations.append(callerDeclaration(form, properties: [(names.value.lowercasedFirst, names.value), (names.inner.lowercasedFirst, names.inner)]))
		case .calledTypeHoldsSecondHoleType:
			declarations.append(fillDeclaration(named: names.fill, protocolName: names.hole, received: (names.value.lowercasedFirst, names.value), isPublic: callerIsPublic))
			switch secondHole?.fill {
			case .readsValue?:
				declarations.append(fillDeclaration(named: SecondHole.fillName, protocolName: SecondHole.protocolName, received: (names.value.lowercasedFirst, names.value), isPublic: callerIsPublic))
			case .readsNothing?:
				declarations.append(fillDeclaration(named: SecondHole.fillName, protocolName: SecondHole.protocolName, received: nil, isPublic: callerIsPublic))
			case .invisible?, nil:
				break
			}
			declarations.append(callerDeclaration(form, properties: [(names.value.lowercasedFirst, names.value), (names.inner.lowercasedFirst, names.inner)]))
		case .callerForwardsValueFillReads:
			// The caller forwards the value the fill reads, required or only if available.
			let value = (label: names.value.lowercasedFirst, type: names.value)
			let receivesOnlyIfAvailable = forwardedValue?.fillReceivesOnlyIfAvailable == true
			declarations.append(fillDeclaration(named: names.fill, protocolName: names.hole, received: receivesOnlyIfAvailable ? (value.label, "\(value.type)?") : value, receivedOnlyIfAvailable: receivesOnlyIfAvailable, isPublic: callerIsPublic))
			declarations.append(callerDeclaration(form, properties: [(names.inner.lowercasedFirst, names.inner)], forwarded: [value]))
		case .fillConstructsTypeCallerModuleCannotReach:
			// The fill receives the caller's value and instantiates the protocol, itself or through `Part`.
			if let unreachable = unreachableConstruction {
				let instantiated = (label: unreachable.protocolName.lowercasedFirst, type: "any \(unreachable.protocolName)")
				if unreachable.isBeneathFill {
					declarations.append("""
					@Instantiable
					\(callerAccess)final class Part: Instantiable {
					    \(callerAccess)init(\(instantiated.label): \(instantiated.type)) { self.\(instantiated.label) = \(instantiated.label) }
					    @Instantiated let \(instantiated.label): \(instantiated.type)
					}
					""")
					declarations.append(fillDeclaration(named: names.fill, protocolName: names.hole, received: (names.value.lowercasedFirst, names.value), instantiated: [(label: "part", type: "Part")], isPublic: callerIsPublic))
				} else {
					declarations.append(fillDeclaration(named: names.fill, protocolName: names.hole, received: (names.value.lowercasedFirst, names.value), instantiated: [instantiated], isPublic: callerIsPublic))
				}
			}
			declarations.append(callerDeclaration(form, properties: [(names.value.lowercasedFirst, names.value), (names.inner.lowercasedFirst, names.inner)]))
		case .fillCallsMockTakingGuardedValueWhereMockConditionIsInactive:
			declarations.append("\(callerAccess)struct \(names.token) {}")
			declarations.append(guardedValueFillDeclaration(condition: guardedValueCondition ?? Self.guardedValueClauseCondition))
			declarations.append(callerDeclaration(form, properties: [(names.value.lowercasedFirst, names.value), (names.inner.lowercasedFirst, names.inner)]))
		case .fillReceivesValueOnlyInnerMockRequires:
			declarations.append(fillDeclaration(named: names.fill, protocolName: names.hole, received: (names.value.lowercasedFirst, names.value), isPublic: callerIsPublic))
			declarations.append(callerDeclaration(form, properties: [(names.value.lowercasedFirst, names.value), (names.outer.lowercasedFirst, names.outer)]))
		case .noVisibleImplementation:
			var properties = [(label: names.value.lowercasedFirst, type: names.value), (label: names.inner.lowercasedFirst, type: names.inner)]
			if callsMixedFormMock {
				properties.append((label: Self.mixedFormTypeName.lowercasedFirst, type: Self.mixedFormTypeName))
			}
			declarations.append(callerDeclaration(form, properties: properties))
		case .implementationReceivesWhatNothingProvides:
			declarations.append("public struct \(names.token) {}")
			declarations.append(fillDeclaration(named: names.fill, protocolName: names.hole, received: (names.token.lowercasedFirst, names.token), isPublic: callerIsPublic))
			declarations.append(callerDeclaration(form, properties: [(names.value.lowercasedFirst, names.value), (names.inner.lowercasedFirst, names.inner)]))
		case .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder, .fillInstantiatesTypeNoDeclarationCanFulfill, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive:
			var properties = [(label: names.value.lowercasedFirst, type: names.value), (label: names.inner.lowercasedFirst, type: names.inner)]
			if let fillHoles {
				declarations += fillHolesDeclarations(fillHoles)
				// The seam caller's own places, one of each hole type the fill instantiates.
				if cell.shape == .seamCallerFillSharesBuilder {
					properties += fillHoles.protocols.map { (label: "own\($0)", type: "any \($0)") }
				}
			}
			declarations.append(callerDeclaration(form, properties: properties))
		case .fillReceivesValueBuildingTheCall:
			let sibling = names.sibling.lowercasedFirst
			let inner = names.inner.lowercasedFirst
			declarations.append("""
			@Instantiable
			\(callerAccess)final class \(names.sibling): Instantiable {
			    \(callerAccess)init(\(inner): \(names.inner)) { self.\(inner) = \(inner) }
			    @Instantiated let \(inner): \(names.inner)
			}
			""")
			declarations.append(fillDeclaration(named: names.fill, protocolName: names.hole, received: (sibling, names.sibling), isPublic: callerIsPublic))
			declarations.append(callerDeclaration(form, properties: [(sibling, names.sibling)]))
		case .fillHoldsBuilderOfEnclosingCalledType:
			// The fill of the inner type's place builds the outer type, whose public mock holds a builder of the inner type, and,
			// where drawn, a type no declaration fulfills, whose stub a probe hands the builder.
			var instantiated = [(label: names.outer.lowercasedFirst, type: names.outer)]
			if reenteringFillInstantiatesWhatNothingFulfills {
				declarations.append("""
				public protocol \(Self.beaconProtocol): AnyObject {}

				public final class \(Self.beaconStub): \(Self.beaconProtocol) {
				    public init() {}
				}
				""")
				instantiated.append((label: Self.beaconProtocol.lowercasedFirst, type: "any \(Self.beaconProtocol)"))
			}
			declarations.append(fillDeclaration(named: names.fill, protocolName: names.hole, received: nil, instantiated: instantiated, isPublic: callerIsPublic))
			var properties = [(label: names.inner.lowercasedFirst, type: names.inner)]
			if let wrapper = enclosingCalledTypeLazyValueWrapper {
				// The value the enclosing called type receives only if available, which the caller holds lazily.
				properties.append((label: names.value.lowercasedFirst, type: "\(wrapper)<\(names.value)>"))
			}
			declarations.append(callerDeclaration(form, properties: properties))
		case .appOnlyScreenInLoop, .seamBuiltAgain, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot, .fillRequiresValueCalledTypeReceivesInOptionalWrapper:
			break
		}
		return """
		import SafeDI
		import \(names.innerModuleName)
		import \(names.outerModuleName)

		\(declarations.joined(separator: "\n\n"))
		"""
	}

	/// The seam's module of the app-only screen's loop. The place is the settings screen's builder: a plain place's forwards
	/// nothing (`ErasedInstantiator<(), any SettingsPage>`), and a deferred place's forwards `id`.
	private var signedInModuleContent: String {
		let feedBuilder = "\(names.feed.lowercasedFirst)Builder"
		let feedBuilderType = "ErasedInstantiator<(), any \(names.feedPage)>"
		let settingsBuilder = "\(names.settings.lowercasedFirst)Builder"
		let settingsBuilderType = switch cell.place {
		case .plain:
			"ErasedInstantiator<(), any \(names.settingsPage)>"
		case .deferred:
			"ErasedInstantiator<Int, any \(names.settingsPage)>"
		}
		let settingsAttribute = "@Instantiated(fulfilledByType: \"\(names.settings)\")"
		return """
		import SafeDI

		public protocol \(names.feedPage) {}
		public protocol \(names.settingsPage) {}

		public struct User {
		    public init(name: String) { self.name = name }
		    public let name: String
		}

		@Instantiable
		final class \(names.feed): \(names.feedPage), Instantiable {
		    init(user: User, \(settingsBuilder): \(settingsBuilderType)) { self.user = user; self.\(settingsBuilder) = \(settingsBuilder) }
		    @Received private let user: User
		    @Received private let \(settingsBuilder): \(settingsBuilderType)
		}

		@Instantiable(generateDependencyTree: true, generateMock: .public)
		public final class \(names.signedIn): Instantiable {
		    init(user: User, \(feedBuilder): \(feedBuilderType), \(settingsBuilder): \(settingsBuilderType)) { self.user = user; self.\(feedBuilder) = \(feedBuilder); self.\(settingsBuilder) = \(settingsBuilder) }
		    @Forwarded private let user: User
		    @Instantiated(fulfilledByType: "\(names.feed)") private let \(feedBuilder): \(feedBuilderType)
		    \(settingsAttribute) private let \(settingsBuilder): \(settingsBuilderType)
		}
		"""
	}

	private func appOnlyScreenCallerContent(_ form: Form) -> String {
		let feedBuilder = "\(names.feed.lowercasedFirst)Builder"
		let feedBuilderType = "ErasedInstantiator<(), any \(names.feedPage)>"
		let access = callerIsPublic ? "public " : ""
		let screen = switch cell.place {
		case .plain:
			"""
			@Instantiable
			\(access)final class \(names.settings): \(names.settingsPage), Instantiable {
			    \(access)init(\(feedBuilder): \(feedBuilderType)) { self.\(feedBuilder) = \(feedBuilder) }
			    @Received private let \(feedBuilder): \(feedBuilderType)
			}
			"""
		case .deferred:
			"""
			@Instantiable
			\(access)final class \(names.settings): \(names.settingsPage), Instantiable {
			    \(access)init(id: Int, \(feedBuilder): \(feedBuilderType)) { self.id = id; self.\(feedBuilder) = \(feedBuilder) }
			    @Forwarded let id: Int
			    @Received private let \(feedBuilder): \(feedBuilderType)
			}
			"""
		}
		return """
		import SafeDI
		import Feature

		\(screen)

		\(callerDeclaration(form, properties: [("\(names.signedIn.lowercasedFirst)Builder", "Instantiator<\(names.signedIn)>")]))
		"""
	}

	/// The called type's module of the place inside a `@Sendable` function: the called type receives the value and holds
	/// `Part`, whose type the place is on, in a `SendableInstantiator`. Its initializer and `Part` are internal, so the
	/// calling mock calls its public mock. The value is `Sendable`, which the fill's `@Sendable` builder captures.
	private var sendablePlaceModuleContent: String {
		let place = holePlace(protocolName: names.hole, fillName: names.fill)
		let value = names.value.lowercasedFirst
		let part = "\(names.between.lowercasedFirst)Builder"
		return """
		import SafeDI

		public protocol \(names.hole): AnyObject {}

		@Instantiable
		public final class \(names.value): Instantiable, Sendable {
		    public init() {}
		}

		@Instantiable
		final class \(names.between): Instantiable {
		    init(\(place.label): \(place.type)) { self.\(place.label) = \(place.label) }
		    \(place.attribute) let \(place.label): \(place.type)
		}

		@Instantiable(generateDependencyTree: true, generateMock: .public)
		public final class \(names.inner): Instantiable {
		    init(\(value): \(names.value), \(part): SendableInstantiator<\(names.between)>) { self.\(value) = \(value); self.\(part) = \(part) }
		    @Received let \(value): \(names.value)
		    @Instantiated let \(part): SendableInstantiator<\(names.between)>
		}
		"""
	}

	private func sendablePlaceCallerContent(_ form: Form) -> String {
		"""
		import SafeDI
		import \(names.innerModuleName)

		\(fillDeclaration(named: names.fill, protocolName: names.hole, received: (names.value.lowercasedFirst, names.value), isPublic: callerIsPublic))

		\(callerDeclaration(form, properties: [(names.value.lowercasedFirst, names.value), (names.inner.lowercasedFirst, names.inner)]))
		"""
	}

	private var reentrantSeamModuleContent: String {
		let place = holePlace(protocolName: names.hole, fillName: names.fill)
		let between = names.between.lowercasedFirst
		let value = names.value.lowercasedFirst
		let repeated = names.repeated.lowercasedFirst
		return """
		import SafeDI

		public protocol \(names.hole) {}

		@Instantiable
		public final class \(names.value): Instantiable {
		    public init() {}
		}

		@Instantiable(generateDependencyTree: true, generateMock: .public)
		public final class \(names.repeated): Instantiable {
		    init(\(place.label): \(place.type), \(between)Builder: Instantiator<\(names.between)>) { self.\(place.label) = \(place.label); self.\(between)Builder = \(between)Builder }
		    \(place.attribute) let \(place.label): \(place.type)
		    @Instantiated let \(between)Builder: Instantiator<\(names.between)>
		}

		@Instantiable
		public final class \(names.between): Instantiable {
		    init(\(value): \(names.value), \(repeated)Builder: Instantiator<\(names.repeated)>) { self.\(value) = \(value); self.\(repeated)Builder = \(repeated)Builder }
		    @Instantiated let \(value): \(names.value)
		    @Instantiated let \(repeated)Builder: Instantiator<\(names.repeated)>
		}
		"""
	}

	private func reentrantSeamCallerContent(_ form: Form) -> String {
		"""
		import SafeDI
		import Feature

		\(fillDeclaration(named: names.fill, protocolName: names.hole, received: (names.value.lowercasedFirst, names.value), isPublic: callerIsPublic))

		\(callerDeclaration(form, properties: [(names.value.lowercasedFirst, names.value), (names.repeated.lowercasedFirst, names.repeated)]))
		"""
	}

	/// The called type's module of the fill that receives the caller's lazy value below the called type's root. The called
	/// type, a seam and public mock, instantiates the level between, whose initializer the caller's module cannot call, so
	/// the place the level between holds is below the called type's root, and a sibling that receives the value by value,
	/// or only if available, so the called type's tree binds it.
	private var lazyValueBelowCalledRootModuleContent: String {
		let place = holePlace(protocolName: names.hole, fillName: names.fill)
		let between = names.between.lowercasedFirst
		let sibling = names.sibling.lowercasedFirst
		let value = names.value.lowercasedFirst
		let receivesOnlyIfAvailable = callerLazyValue?.receivesOnlyIfAvailable == true
		let siblingValueType = receivesOnlyIfAvailable ? "\(names.value)?" : names.value
		let siblingAttribute = receivesOnlyIfAvailable ? "@Received(onlyIfAvailable: true)" : "@Received"
		var siblingBody = "    init(\(value): \(siblingValueType)) { self.\(value) = \(value) }\n    \(siblingAttribute) public let \(value): \(siblingValueType)"
		if callerLazyValue?.fillReadsInstanceCalledTypeDoesNotHold == true {
			// The called type holds no copy of the value.
			siblingBody = "    init() {}"
		}
		var innerProperties = [(label: between, type: names.between), (label: sibling, type: names.sibling)]
		var secondLevel = ""
		if callerLazyValue?.holdsSecondPlace == true {
			innerProperties.append((label: Self.secondLevelLabel, type: "Hub"))
			secondLevel = """


			public protocol \(Self.secondPlaceProtocol): AnyObject {}

			@Instantiable
			public final class Hub: Instantiable {
			    init(\(Self.secondPlaceLabel): any \(Self.secondPlaceProtocol)) { self.\(Self.secondPlaceLabel) = \(Self.secondPlaceLabel) }
			    @Instantiated public let \(Self.secondPlaceLabel): any \(Self.secondPlaceProtocol)
			}
			"""
		}
		if callerLazyValue?.buildsPlaceInSendableFunctionToo == true {
			innerProperties.append((label: "\(between)Builder", type: "SendableInstantiator<\(names.between)>"))
		}
		let innerParameters = innerProperties.map { "\($0.label): \($0.type)" }.joined(separator: ", ")
		let innerAssignments = innerProperties.map { "self.\($0.label) = \($0.label)" }.joined(separator: "; ")
		let innerDeclarations = innerProperties.map { "    @Instantiated public let \($0.label): \($0.type)" }.joined(separator: "\n")
		return """
		import SafeDI

		public protocol \(names.hole): AnyObject {}

		@Instantiable
		public final class \(names.value): Instantiable, Sendable {
		    public init() {}
		}

		@Instantiable
		public final class \(names.between): Instantiable {
		    init(\(place.label): \(place.type)) { self.\(place.label) = \(place.label) }
		    \(place.attribute) public let \(place.label): \(place.type)
		}

		@Instantiable
		public final class \(names.sibling): Instantiable {
		\(siblingBody)
		}

		@Instantiable(generateDependencyTree: true, generateMock: .public)
		public final class \(names.inner): Instantiable {
		    init(\(innerParameters)) { \(innerAssignments) }
		\(innerDeclarations)
		}\(secondLevel)\(dockDeclaration)
		"""
	}

	/// `Dock`, where the graph `joinsFilledCall`: a seam and public mock whose root holds a place of the hole type in the
	/// cell's form, or, where the graph `buildsDockInline`, a public mock whose initializer is public. Empty elsewhere.
	private var dockDeclaration: String {
		guard joinsFilledCall else { return "" }
		let place = holePlace(protocolName: names.hole, fillName: names.fill)
		let attribute = buildsDockInline ? "@Instantiable(generateMock: .public)" : "@Instantiable(generateDependencyTree: true, generateMock: .public)"
		return """


		\(attribute)
		public final class \(dockName): Instantiable {
		    \(buildsDockInline ? "public " : "")init(\(place.label): \(place.type)) { self.\(place.label) = \(place.label) }
		    \(place.attribute) public let \(place.label): \(place.type)
		}
		"""
	}

	/// The caller's module of the fill that receives the caller's lazy value below the called type's root: the fill
	/// receives the value in the drawn wrapper, which the caller instantiates beside the called type, or beside the mocked
	/// intermediate type that instantiates the called type, receiving the wrapper too where the draw says so. Where the
	/// fill calls the called type again, it instantiates an `Instantiator` of it. The intermediate type generates its own
	/// internal mock in the calling mock's form and is a plain type in the twin's, which builds it inline in the caller's
	/// tree, as the same types built inline do.
	private func lazyValueBelowCalledRootCallerContent(_ form: Form) -> String {
		let value = names.value.lowercasedFirst
		let inner = names.inner.lowercasedFirst
		let wrapped = "\(callerLazyValue?.wrapper ?? "LazilyInstantiated")<\(names.value)>"
		let instantiated: [(label: String, type: String)] = callerLazyValue?.call == .fillCallsAgain ? [("\(inner)Builder", "Instantiator<\(names.inner)>")] : []
		var fillReceived = wrapped
		// The fill reads the value only if available where the called type's copy holds it so, which a read by value could not
		// be handed.
		let fillReadsOnlyIfAvailable = callerLazyValue?.secondPlaceFillDeclaresValueAgain == true && callerLazyValue?.receivesOnlyIfAvailable == true
		// The caller instantiates `Dock` last, where the graph `joinsFilledCall`.
		let dockProperty: [(label: String, type: String)] = joinsFilledCall ? [(dockName.lowercasedFirst, dockName)] : []
		if callerLazyValue?.fillReadsInstance == true {
			fillReceived = fillReadsOnlyIfAvailable ? "\(names.value)?" : names.value
		}
		var declarations = [
			"import SafeDI\nimport \(names.innerModuleName)",
			fillDeclaration(named: names.fill, protocolName: names.hole, received: (value, fillReceived), receivedOnlyIfAvailable: fillReadsOnlyIfAvailable, instantiated: instantiated, isPublic: callerIsPublic),
		]
		if callerLazyValue?.holdsSecondPlace == true {
			var properties = [(label: "\(inner)Builder", type: "Instantiator<\(names.inner)>")]
			if callerLazyValue?.secondPlaceFillDeclaresValueAgain == true {
				properties.insert((label: value, type: names.value), at: 0)
			}
			declarations.append("""
			@Instantiable(fulfillingAdditionalTypes: [(any \(Self.secondPlaceProtocol)).self])
			\(callerAccess)final class \(Self.secondFillName): \(Self.secondPlaceProtocol), Instantiable {
			    \(callerAccess)init(\(properties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) { \(properties.map { "self.\($0.label) = \($0.label)" }.joined(separator: "; ")) }
			\(properties.map { "    @Instantiated let \($0.label): \($0.type)" }.joined(separator: "\n"))
			}
			""")
		}
		if let intermediate = callerLazyValue?.intermediate {
			var properties = [(attribute: "@Instantiated", label: inner, type: names.inner)]
			if callerLazyValue?.call == .mockedIntermediateReceivingValueCalls {
				properties.append((attribute: "@Received", label: value, type: wrapped))
			}
			let attribute = switch form {
			case .mock:
				"@Instantiable(generateMock: true)"
			case .twin:
				"@Instantiable"
			}
			declarations.append("""
			\(attribute)
			\(callerAccess)final class \(intermediate): Instantiable {
			    \(callerAccess)init(\(properties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) { \(properties.map { "self.\($0.label) = \($0.label)" }.joined(separator: "; ")) }
			\(properties.map { "    \($0.attribute) let \($0.label): \($0.type)" }.joined(separator: "\n"))
			}
			""")
			declarations.append(callerDeclaration(form, properties: [(value, wrapped), (intermediate.lowercasedFirst, intermediate)] + dockProperty))
		} else {
			declarations.append(callerDeclaration(form, properties: [(value, wrapped), (inner, names.inner)] + dockProperty))
		}
		return declarations.joined(separator: "\n\n")
	}
}

extension GraphFuzzerCallingMockDraw {
	/// The called type's module of the fill that requires a value the called type receives only if available in a lazy
	/// wrapper: the hole's protocol, the value, and the called type, a seam and public mock, which holds the place and
	/// receives the wrapper only if available itself, through a sibling it instantiates, or both.
	private var optionalWrapperValueModuleContent: String {
		let place = holePlace(protocolName: names.hole, fillName: names.fill)
		let value = names.value.lowercasedFirst
		let sibling = names.sibling.lowercasedFirst
		let wrapped = "\(optionalWrapperValue?.wrapper ?? "LazilyInstantiated")<\(names.value)>"
		var innerProperties = [(attribute: place.attribute, label: place.label, type: place.type)]
		var siblingDeclaration = ""
		if optionalWrapperValue?.siblingReceives == true {
			innerProperties.append((attribute: "@Instantiated", label: sibling, type: names.sibling))
			if optionalWrapperValue?.calledTypeReceivesBesideSibling == true {
				innerProperties.append((attribute: "@Received(onlyIfAvailable: true)", label: value, type: "\(wrapped)?"))
			}
			siblingDeclaration = """


			@Instantiable
			public final class \(names.sibling): Instantiable {
			    init(\(value): \(wrapped)?) { self.\(value) = \(value) }
			    @Received(onlyIfAvailable: true) public let \(value): \(wrapped)?
			}
			"""
		} else {
			innerProperties.append((attribute: "@Received(onlyIfAvailable: true)", label: value, type: "\(wrapped)?"))
		}
		let parameters = innerProperties.map { "\($0.label): \($0.type)" }.joined(separator: ", ")
		let assignments = innerProperties.map { "self.\($0.label) = \($0.label)" }.joined(separator: "; ")
		let declarations = innerProperties.map { "    \($0.attribute) public let \($0.label): \($0.type)" }.joined(separator: "\n")
		return """
		import SafeDI

		public protocol \(names.hole): AnyObject {}

		@Instantiable
		public final class \(names.value): Instantiable, Sendable {
		    public init() {}
		}\(siblingDeclaration)

		@Instantiable(generateDependencyTree: true, generateMock: .public)
		public final class \(names.inner): Instantiable {
		    init(\(parameters)) { \(assignments) }
		\(declarations)
		}
		"""
	}

	/// The caller's module of the fill that requires a value the called type receives only if available in a lazy wrapper:
	/// the fill requires the value by value, and instantiates an `Instantiator` of the called type where the draw says so,
	/// and the caller instantiates the value in the drawn wrapper beside the called type.
	private func optionalWrapperValueCallerContent(_ form: Form) -> String {
		let value = names.value.lowercasedFirst
		let inner = names.inner.lowercasedFirst
		let wrapped = "\(optionalWrapperValue?.wrapper ?? "LazilyInstantiated")<\(names.value)>"
		let instantiated: [(label: String, type: String)] = optionalWrapperValue?.fillCallsAgain == true ? [("\(inner)Builder", "Instantiator<\(names.inner)>")] : []
		return [
			"import SafeDI\nimport \(names.innerModuleName)",
			fillDeclaration(named: names.fill, protocolName: names.hole, received: (value, names.value), instantiated: instantiated, isPublic: callerIsPublic),
			callerDeclaration(form, properties: [(value, wrapped), (inner, names.inner)]),
		].joined(separator: "\n\n")
	}
}

extension String {
	/// The string with its first character lowercased, as a label is spelled from a type's name.
	fileprivate var lowercasedFirst: String {
		prefix(1).lowercased() + dropFirst()
	}
}

/// `source` as a hand-written test's production twin declares it: each `@Instantiable(generateMock: true)` a seam, and
/// each `@Instantiable(generateMock: .public)` a seam that keeps its public mock, so the twin of a calling mock calls the
/// same types' seams.
func callingMockProductionTwin(of source: String) -> String {
	source
		.replacingOccurrences(of: "@Instantiable(generateMock: true)", with: "@Instantiable(generateDependencyTree: true)")
		.replacingOccurrences(of: "@Instantiable(generateMock: .public)", with: "@Instantiable(generateDependencyTree: true, generateMock: .public)")
}

// MARK: - Graph

/// A graph whose caller's generated `mock()` calls another module's public mock, in its two forms, with the facts the check
/// classifies the mock's pass-ups by. The draw makes one per seed; a hand-written test writes one.
struct GraphFuzzerCallingMockGraph {
	/// The two forms of the caller.
	enum Form {
		/// `generateMock: true`, or `.public` for a `.public` caller: the calling mock.
		case mock
		/// `generateDependencyTree: true`, the caller's access kept: the production twin.
		case twin
	}

	/// The build of the calling mock's module, as its integration tells the tool of it: whether the tool is told the mock
	/// condition, `DEBUG`, is active, which decides whether it checks what only a compiled generated mock needs
	/// (`compilesGeneratedMocks`), and whether the comparator's compile defines it. Every other module, and the twin's
	/// every module, is told no condition.
	enum MockBuild: CaseIterable {
		/// A debug build whose integration reports `DEBUG`: the tool checks the mock, and the compile compiles it.
		case compilesGeneratedMocks
		/// A debug build whose integration does not report `DEBUG`, as SwiftPM's native backend does not: the tool is told
		/// no condition, so it does not check the mock, which the compile, defining `DEBUG`, compiles.
		case debugWithoutMockCondition
		/// A release build: the tool is told `NDEBUG`, and the compile defines neither `DEBUG` nor the mock condition, so it
		/// compiles no generated mock.
		case release

		/// Whether the tool is told the mock condition is active.
		var compilesGeneratedMocks: Bool {
			switch self {
			case .compilesGeneratedMocks:
				true
			case .debugWithoutMockCondition, .release:
				false
			}
		}
	}

	/// One module's one file, named `<Module>Types.swift`.
	struct File {
		let module: String
		let dependencies: [String]
		let content: String
		/// The package the module belongs to.
		var packageName: String = GraphFuzzerCallingMockGraph.packageName

		var fileName: String {
			"\(module)Types.swift"
		}

		var relativePath: String {
			"\(module)/\(fileName)"
		}
	}

	/// The package every module belongs to, but a module a graph puts in another (`File.packageName`).
	static let packageName = "Probe"

	/// The name of the file that holds `mockConfiguration` in the caller's module.
	static let configurationFileName = "SafeDIConfiguration.swift"

	let name: String
	/// The modules' files in dependency order, the calling mock's module last.
	let mockFiles: [File]
	/// `mockFiles` with every `@Instantiable(generateMock: …)` of the last file, the caller's module, replaced by
	/// `@Instantiable(generateDependencyTree: true)`, so every line keeps its number.
	let twinFiles: [File]
	let callerTypeName: String
	let callerIsPublic: Bool
	/// The `SafeDIConfiguration.swift` the calling mock's module holds beside its file, in place of the twin's (which sets
	/// `generatePlainDependencyTreeInitializers`): one that lists the caller in `additionalMocksToGenerate`, or `nil`.
	let mockConfiguration: String?
	/// The parameters of the calling mock's `mock()` that its own `@Forwarded` values and the received values its tree
	/// cannot build account for: every other parameter but `safeDIOverrides` is a place it passes up.
	let flatParameterLabels: Set<String>
	/// Whether a type that fulfills the hole is visible from the calling mock's module.
	let implementationIsVisible: Bool
	/// The parameters of the twin's seam initializers, without the `__safeDI_` prefix of the one only generated code
	/// calls, in order, or `nil` when the graph does not state them: what production takes where it is accepted, which the
	/// check reads to see that production fills what the graph is drawn for it to fill.
	let expectedTwinInitializerLabels: [String]?
	/// The places the calling mock may pass up because its module sees no type that fulfills the place's type, or, where
	/// the tool skips the twin's error in the mock (`mockSkipsTwinsError`), because it does not check the fill production
	/// rejects: the only labels the check classifies.
	let expectedPassUpLabels: [String]
	/// Where production reports the graph's shape error, as the module's file and the declaration's line, or `nil` when
	/// production accepts the graph.
	let expectedTwinErrorSite: (file: String, declaration: String)?
	/// Where the calling mock reports an error of its own where production is accepted, as the module's file and the
	/// declaration's line, or `nil`: the access of a hand-written mock its fill calls, which the twin, calling the type's
	/// initializer, does not (contract rule 7). The tool checks it only where the generated mocks compile, so the graph
	/// also sets `twinErrorIsCheckedOnlyWhereMocksCompile`, and a build that leaves the mock condition inactive passes the
	/// place up (`mockSkipsTwinsError`).
	let expectedMockOwnErrorSite: (file: String, declaration: String)?
	/// What the differential value comparator describes where the mock passes up no place without a reason and mirrors its
	/// twin: each probe's expression calls the calling mock, and its known-right expression the twin's seam initializer
	/// where the twin is accepted, or the caller's root initializer in `inlineModules` where the twin reports that a seam
	/// built again passes its builder on unchanged. `nil` when the graph states none, which leaves that outcome unagreed.
	let valueProbes: [DifferentialValueProbe]?
	/// The build of the calling mock's module, as its integration tells the tool of it.
	let mockBuild: MockBuild
	/// Whether the twin's error is one the tool checks in the mock only where the generated mocks compile: a calling mock's
	/// fill that instantiates a type no declaration can fulfill, where no seam of the caller's module, whose own tree any
	/// build generates, instantiates the type.
	let twinErrorIsCheckedOnlyWhereMocksCompile: Bool
	/// Whether the value comparison's known-right path is the same types built inline (`inlineModules`) even where the twin
	/// is accepted, rather than the twin's seam initializer, so `valueProbes`' known-right expressions call the caller's
	/// root initializer there.
	let comparesValuesWithInline: Bool
	/// Whether the called type is re-entered – a fill of one of its places calls it again – and a fill of one of its places
	/// reads, beside the place's fields, a `LazilyInstantiated` or `SendableLazilyInstantiated` value, or, below the called
	/// type's root, the instance of one the module holds, which a fill that calls the called type again reads none of, so
	/// the calling mock passes `expectedPassUpLabels` up whole where the twin fills them: contract rule 7's listed difference
	/// (`DependencyTreeGenerator.holeTypesTheFillGatesPassUp(of:in:lazilyHeldValues:)`).
	let fillGatePassesUp: Bool

	/// Whether the tool skips the twin's error in the mock: the error is one it checks only where the generated mocks
	/// compile, and `mockBuild` leaves the mock condition inactive. The mock must then be accepted, passing up
	/// `expectedPassUpLabels`, where its twin reports the error, or, with `expectedMockOwnErrorSite`, where it would report
	/// its own.
	var mockSkipsTwinsError: Bool {
		twinErrorIsCheckedOnlyWhereMocksCompile && !mockBuild.compilesGeneratedMocks
	}

	var callerModule: String {
		mockFiles.last?.module ?? ""
	}

	func files(_ form: Form) -> [File] {
		switch form {
		case .mock:
			mockFiles
		case .twin:
			twinFiles
		}
	}

	func modules(_ form: Form) -> [ModuleFixture] {
		files(form).map { file in
			var contentByFileName = [file.fileName: file.content]
			if let configuration = configuration(of: form), file.module == callerModule {
				contentByFileName[Self.configurationFileName] = configuration
			}
			return ModuleFixture(
				name: file.module,
				packageName: file.packageName,
				swiftFileContentByFilePath: contentByFileName,
				dependencies: file.dependencies,
				activeCompilationConditions: activeCompilationConditions(of: form, module: file.module),
				isReleaseConfiguration: form == .mock && file.module == callerModule && mockBuild == .release,
			)
		}
	}

	/// The conditions the tool is told `module` builds under in `form`: `DEBUG`, the mock condition, for the calling mock's
	/// module where `mockBuild` compiles the generated mocks, so the tool checks its calls of hand-written mocks and its
	/// fills as a build that compiles the generated mocks does (`compilesGeneratedMocks`); none for every other module.
	private func activeCompilationConditions(of form: Form, module: String) -> [String] {
		switch form {
		case .mock:
			module == callerModule && mockBuild.compilesGeneratedMocks ? ["DEBUG"] : []
		case .twin:
			[]
		}
	}

	/// The configuration the caller's module holds in `form`. The twin's generates its seams' plain initializers, which
	/// the known-right probes call with a stub builder: a seam's levels declare no initializer that builds one from a
	/// builder alone, so only its plain initializer, which builds each level in a local function, takes the builder itself.
	private func configuration(of form: Form) -> String? {
		switch form {
		case .mock:
			mockConfiguration
		case .twin:
			"import SafeDI\n\n#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n"
		}
	}

	/// The same types built inline, the baseline the outcome rule 7 lists is judged against: the twin's files in one module
	/// named after the caller's, each file as `<Module>Types.swift` without its imports of the graph's other modules, the
	/// caller's module's seams roots (`@Instantiable(isRoot: true)`), and every other module's seams and public mocks plain
	/// `@Instantiable` types.
	var inlineModules: [ModuleFixture] {
		let moduleNames = Set(twinFiles.map(\.module))
		var contentByFileName = [String: String]()
		for file in twinFiles {
			var lines = file.content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
			lines.removeAll { line in
				line.hasPrefix("import ") && moduleNames.contains(String(line.dropFirst("import ".count)))
			}
			var content = lines.joined(separator: "\n")
			if file.module == callerModule {
				content = content.replacingOccurrences(of: "@Instantiable(generateDependencyTree: true)", with: "@Instantiable(isRoot: true)")
			} else {
				content = content
					.replacingOccurrences(of: "@Instantiable(generateDependencyTree: true, generateMock: .public)", with: "@Instantiable")
					.replacingOccurrences(of: "@Instantiable(generateDependencyTree: true)", with: "@Instantiable")
					.replacingOccurrences(of: "@Instantiable(generateMock: .public)", with: "@Instantiable")
			}
			contentByFileName[file.fileName] = content
		}
		return [ModuleFixture(name: callerModule, packageName: Self.packageName, swiftFileContentByFilePath: contentByFileName)]
	}

	func contentByRelativePath(_ form: Form) -> [String: String] {
		var contentByRelativePath = [String: String]()
		for file in files(form) {
			contentByRelativePath[file.relativePath] = file.content
		}
		if let configuration = configuration(of: form) {
			contentByRelativePath["\(callerModule)/\(Self.configurationFileName)"] = configuration
		}
		return contentByRelativePath
	}

	/// A hand-written graph: its twin replaces the line `@Instantiable(generateMock: true)` or
	/// `@Instantiable(generateMock: .public)` in the calling mock's module.
	init(
		handWrittenNamed name: String,
		mockFiles: [File],
		callerTypeName: String,
		callerIsPublic: Bool,
		mockConfiguration: String? = nil,
		flatParameterLabels: Set<String> = [],
		implementationIsVisible: Bool = true,
		expectedTwinInitializerLabels: [String]? = nil,
		expectedPassUpLabels: [String] = [],
		expectedTwinErrorSite: (file: String, declaration: String)?,
		expectedMockOwnErrorSite: (file: String, declaration: String)? = nil,
		valueProbes: [DifferentialValueProbe]? = nil,
		mockBuild: MockBuild = .compilesGeneratedMocks,
		twinErrorIsCheckedOnlyWhereMocksCompile: Bool = false,
		comparesValuesWithInline: Bool = false,
		fillGatePassesUp: Bool = false,
	) {
		let twinFiles = mockFiles.enumerated().map { index, file in
			guard index == mockFiles.count - 1 else { return file }
			return File(
				module: file.module,
				dependencies: file.dependencies,
				content: file.content
					.replacingOccurrences(of: "@Instantiable(generateMock: true)", with: "@Instantiable(generateDependencyTree: true)")
					.replacingOccurrences(of: "@Instantiable(generateMock: .public)", with: "@Instantiable(generateDependencyTree: true)"),
				packageName: file.packageName,
			)
		}
		self.init(
			name: name,
			mockFiles: mockFiles,
			twinFiles: twinFiles,
			callerTypeName: callerTypeName,
			callerIsPublic: callerIsPublic,
			mockConfiguration: mockConfiguration,
			flatParameterLabels: flatParameterLabels,
			implementationIsVisible: implementationIsVisible,
			expectedTwinInitializerLabels: expectedTwinInitializerLabels,
			expectedPassUpLabels: expectedPassUpLabels,
			expectedTwinErrorSite: expectedTwinErrorSite,
			expectedMockOwnErrorSite: expectedMockOwnErrorSite,
			valueProbes: valueProbes,
			mockBuild: mockBuild,
			twinErrorIsCheckedOnlyWhereMocksCompile: twinErrorIsCheckedOnlyWhereMocksCompile,
			comparesValuesWithInline: comparesValuesWithInline,
			fillGatePassesUp: fillGatePassesUp,
		)
	}

	init(
		name: String,
		mockFiles: [File],
		twinFiles: [File],
		callerTypeName: String,
		callerIsPublic: Bool,
		mockConfiguration: String? = nil,
		flatParameterLabels: Set<String>,
		implementationIsVisible: Bool,
		expectedTwinInitializerLabels: [String]?,
		expectedPassUpLabels: [String],
		expectedTwinErrorSite: (file: String, declaration: String)?,
		expectedMockOwnErrorSite: (file: String, declaration: String)? = nil,
		valueProbes: [DifferentialValueProbe]? = nil,
		mockBuild: MockBuild = .compilesGeneratedMocks,
		twinErrorIsCheckedOnlyWhereMocksCompile: Bool = false,
		comparesValuesWithInline: Bool = false,
		fillGatePassesUp: Bool = false,
	) {
		self.name = name
		self.mockFiles = mockFiles
		self.twinFiles = twinFiles
		self.callerTypeName = callerTypeName
		self.callerIsPublic = callerIsPublic
		self.mockConfiguration = mockConfiguration
		self.flatParameterLabels = flatParameterLabels
		self.implementationIsVisible = implementationIsVisible
		self.expectedTwinInitializerLabels = expectedTwinInitializerLabels
		self.expectedPassUpLabels = expectedPassUpLabels
		self.expectedTwinErrorSite = expectedTwinErrorSite
		self.expectedMockOwnErrorSite = expectedMockOwnErrorSite
		self.valueProbes = valueProbes
		self.mockBuild = mockBuild
		self.twinErrorIsCheckedOnlyWhereMocksCompile = twinErrorIsCheckedOnlyWhereMocksCompile
		self.comparesValuesWithInline = comparesValuesWithInline
		self.fillGatePassesUp = fillGatePassesUp
	}
}

// MARK: - Diagnostic sites

/// Where a diagnostic points, without its text: its severity, its file by module (`<Module>/<File>`), its line, and the
/// declaration on that line. Two runs of one graph in two forms report one error when their sites agree; the text is not
/// compared, since a fix may reword a remedy.
struct GraphFuzzerDiagnosticSite: Hashable, CustomStringConvertible {
	let severity: String
	let file: String
	let line: Int
	let declaration: String

	var description: String {
		"\(severity) at \(file):\(line) `\(declaration)`"
	}

	/// The sites of the errors and notes in `diagnostics`, as the tool formats them, in order: each line
	/// `<path>:<line>:<column>: <severity>: <message>` whose path ends in `<Module>/<File>` of `contentByRelativePath`.
	/// A line that names no such file keeps its whole path as its file and has no declaration.
	static func sites(inDiagnostics diagnostics: String, contentByRelativePath: [String: String]) -> [Self] {
		diagnostics.split(separator: "\n").compactMap { line -> Self? in
			let line = String(line)
			for severity in ["error", "note"] {
				guard let severityRange = line.range(of: ": \(severity): ") else { continue }
				let location = line[..<severityRange.lowerBound].split(separator: ":")
				guard location.count >= 3, let lineNumber = Int(location[location.count - 2]) else { continue }
				let path = location.dropLast(2).joined(separator: ":")
				let components = path.split(separator: "/")
				let relativePath = components.suffix(2).joined(separator: "/")
				guard let content = contentByRelativePath[relativePath] else {
					return Self(severity: severity, file: path, line: lineNumber, declaration: "")
				}
				let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
				let declaration = lineNumber >= 1 && lineNumber <= lines.count ? lines[lineNumber - 1].trimmingCharacters(in: .whitespaces) : ""
				return Self(severity: severity, file: relativePath, line: lineNumber, declaration: declaration)
			}
			return nil
		}
	}
}

// MARK: - Check

/// Why a calling mock passes a place up, of the permanent reasons contract rule 7's calling-mock clause names. The other
/// permanent reason, a name the mock's tree hides, has no computable definition yet, so a pass-up this one does not
/// explain is unclassified. A visible implementation that receives what nothing in the mock's tree builds is no reason:
/// production fills that place from a parameter. Beside rule 7's, a build that leaves the mock condition inactive is one:
/// the tool checks a fill production rejects only where the generated mocks compile; and so is rule 7's listed
/// difference for a re-entered called type whose fill reads a lazy value beside its place's fields.
enum GraphFuzzerCallingMockPassUpReason: String, CaseIterable, Comparable {
	/// No type that fulfills the place's type is visible from the mock's module.
	case noVisibleImplementation
	/// The build leaves the mock condition inactive (`GraphFuzzerCallingMockGraph.MockBuild`), so the tool does not check
	/// the fill production rejects, and passes its place up (`GraphFuzzerCallingMockGraph.mockSkipsTwinsError`).
	case mockConditionIsInactive
	/// The called type is re-entered, and a fill of one of its places reads a lazy value beside the place's fields, or the
	/// instance of one the module holds, which a fill that calls the called type again does not read, so the mock passes
	/// that place's hole type up whole, and every fill that calls the called type then, where the twin fills them: contract
	/// rule 7's listed difference (`GraphFuzzerCallingMockGraph.fillGatePassesUp`).
	case fillOfReenteredCallReadsLazyValue

	static func < (lhs: Self, rhs: Self) -> Bool {
		allCases.firstIndex(of: lhs) ?? 0 < allCases.firstIndex(of: rhs) ?? 0
	}
}

/// The check's verdict on one calling-mock graph.
struct GraphFuzzerCallingMockResult {
	/// The twin's error sites, or `nil` when the twin is accepted.
	let twinSites: [GraphFuzzerDiagnosticSite]?
	/// The calling mock's error sites, or `nil` when it is accepted.
	let mockSites: [GraphFuzzerDiagnosticSite]?
	/// The twin's diagnostics as the tool printed them, for a report.
	let twinDiagnostics: String?
	/// The parameters of the twin's seam initializers, without the `__safeDI_` prefix, or `nil` when the twin is rejected or
	/// its generated file declares no initializer in an extension of the caller.
	let twinInitializerLabels: [String]?
	/// Each place the accepted calling mock passes up, by its parameter's label, with its reason or `nil` when no reason
	/// explains it.
	let passUps: [(label: String, reason: GraphFuzzerCallingMockPassUpReason?)]
	/// Why the twin's outcome is not the one the graph is drawn for – a drawing defect, never a mirroring requirement – or
	/// `nil`.
	let drawingDefect: String?
	/// Whether the comparator compiled both forms and compared what they build: only where both are accepted, the mock
	/// passes up no place without a reason, the graph states probes, the run asked for it, and compile verification is on.
	let comparedValues: Bool
	/// The first way the calling mock fails to mirror its twin, or `nil`.
	let failure: GraphFuzzerFailure?

	/// Whether the twin's outcome is the one the graph is drawn for, which counts the graph toward its cell.
	var twinHasIntendedOutcome: Bool {
		drawingDefect == nil
	}
}

enum GraphFuzzerCallingMockCheck {
	/// Runs `graph` in both forms through the module-info flow (`generate` per module, as Bazel runs it) and judges the
	/// calling mock against its production twin: where the twin reports the graph's shape error, the mock reports the same
	/// error, at the same sites; where the twin is accepted, the mock is too, and each place it passes up has a permanent
	/// reason; and where it passes up none without one, when `comparesValues`, the mock compiles and builds what the twin
	/// builds (`valueFailure`). The one outcome rule 7 lists apart, a twin whose every error is that a seam built again
	/// passes its builder on unchanged while the mock is accepted, agrees only by values: the graph must state probes, and
	/// when `comparesValues`, the mock must compile and build what the same types build inline (`inlineModules`), a
	/// baseline that must build, as the twin must where it is accepted. Where values are not compared (`comparesValues` is
	/// `false`, or compile verification is off), nothing more is judged of that outcome, as of an accepted twin's. Where
	/// the tool skips the twin's error in the mock (`mockSkipsTwinsError`: an error it checks only where the generated mocks
	/// compile, in a build that leaves the mock condition inactive), the mock must be accepted, and the places it passes up
	/// are classified as that build's. Where the graph `comparesValuesWithInline`, an accepted twin's mock is compared with
	/// the same types built inline too, rather than with the twin. Where the graph states `expectedMockOwnErrorSite`, the
	/// mock reports that one error where the twin is accepted, in a build that compiles the generated mocks.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	static func run(_ graph: GraphFuzzerCallingMockGraph, seed: UInt64, comparesValues: Bool = true) async throws -> GraphFuzzerCallingMockResult {
		let twin = try await toolRun(of: graph, .twin)
		let mock = try await toolRun(of: graph, .mock)
		let twinSites = twin.diagnostics.map { GraphFuzzerDiagnosticSite.sites(inDiagnostics: $0, contentByRelativePath: graph.contentByRelativePath(.twin)) }
		let mockSites = mock.diagnostics.map { GraphFuzzerDiagnosticSite.sites(inDiagnostics: $0, contentByRelativePath: graph.contentByRelativePath(.mock)) }
		let twinInitializerLabels = twin.generatedCallerFile.flatMap { initializerParameterLabels(ofType: graph.callerTypeName, inGeneratedFile: $0) }
		let drawingDefect: String? = if graph.files(.twin).map(\.content) == graph.files(.mock).map(\.content) {
			"the twin of \(graph.name) is its calling mock: no line declares the caller `@Instantiable(generateMock: …)`"
		} else if let failingModule = twin.failingModule, failingModule != graph.callerModule {
			"the twin of \(graph.name) is rejected while module \(failingModule) generates, not the caller's module \(graph.callerModule): \(twin.diagnostics ?? "")"
		} else if let expected = graph.expectedTwinErrorSite {
			if let first = twinSites?.first, first.severity == "error", first.file == expected.file, first.declaration == expected.declaration {
				nil
			} else {
				"the twin of \(graph.name) does not report its shape's error at \(expected.file) `\(expected.declaration)`: \(twin.diagnostics ?? "it is accepted")"
			}
		} else if let diagnostics = twin.diagnostics {
			"the twin of \(graph.name) is rejected where the graph is drawn for production to accept it: \(diagnostics)"
		} else if let expected = graph.expectedTwinInitializerLabels, twinInitializerLabels != expected {
			if let twinInitializerLabels {
				"the twin of \(graph.name) takes \(twinInitializerLabels) where the graph is drawn for it to take \(expected)"
			} else {
				"the twin of \(graph.name) declares no initializer in an extension of \(graph.callerTypeName) where the graph is drawn for it to take \(expected)"
			}
		} else {
			nil
		}
		let passUps = try mock.generatedCallerFile.map { try passUpsOf(graph, inGeneratedFile: $0) } ?? []
		let missingFlatParameterLabels = mock.generatedCallerFile.map { generatedFile in
			graph.flatParameterLabels.subtracting(mockParameterLabels(ofType: graph.callerTypeName, inGeneratedFile: generatedFile) ?? []).sorted()
		} ?? []
		// The outcome rule 7 lists apart, judged by values below.
		let agreesByValuesWithInline = twinSites != nil && mockSites == nil && graph.valueProbes != nil && twin.diagnostics.map(reportsOnlySeamBuiltAgain) == true
		let mirroringFailure: GraphFuzzerFailure? = if graph.mockSkipsTwinsError, let mockDiagnostics = mock.diagnostics {
			GraphFuzzerFailure(
				seed: seed,
				kind: .callingMockRejectedWhereMockConditionIsInactive,
				details: "\(graph.name): the build leaves the mock condition inactive, and the calling mock reports \(mockDiagnostics)",
			)
		} else if let twinSites, let mockSites {
			mockSites == twinSites ? nil : GraphFuzzerFailure(
				seed: seed,
				kind: .callingMockReportsOtherErrorThanTwin,
				details: "\(graph.name): the twin reports \(twinSites), the calling mock \(mockSites)",
			)
		} else if let twinSites, !agreesByValuesWithInline, !graph.mockSkipsTwinsError {
			GraphFuzzerFailure(
				seed: seed,
				kind: .callingMockAcceptedWhereTwinReportsShapeError,
				details: "\(graph.name): the calling mock is accepted where the twin reports \(twinSites)",
			)
		} else if twinSites == nil, let mockDiagnostics = mock.diagnostics {
			if let expected = graph.expectedMockOwnErrorSite, let mockSites, mockSites.count == 1, let site = mockSites.first, site.severity == "error", site.file == expected.file, site.declaration == expected.declaration {
				nil
			} else {
				GraphFuzzerFailure(
					seed: seed,
					kind: .callingMockRejectsWhereTwinAccepts,
					details: "\(graph.name): the twin is accepted and the calling mock reports \(mockDiagnostics)",
				)
			}
		} else if let expected = graph.expectedMockOwnErrorSite, graph.mockBuild.compilesGeneratedMocks {
			GraphFuzzerFailure(
				seed: seed,
				kind: .callingMockAcceptedWhereItsFillCallsMockItCannotReach,
				details: "\(graph.name): the calling mock is accepted where its fill calls the hand-written mock at \(expected.file) `\(expected.declaration)`, which its module cannot reach",
			)
		} else if case let unclassified = passUps.filter({ $0.reason == nil }), !unclassified.isEmpty {
			GraphFuzzerFailure(
				seed: seed,
				kind: .callingMockPassesUpUnclassifiedPlace,
				details: "\(graph.name): the calling mock passes up \(unclassified.map(\.label).joined(separator: ", ")), which no permanent reason explains",
			)
		} else if !missingFlatParameterLabels.isEmpty {
			GraphFuzzerFailure(
				seed: seed,
				kind: .callingMockLacksFlatParameter,
				details: "\(graph.name): the calling mock takes no parameter \(missingFlatParameterLabels.joined(separator: ", ")), a value its tree cannot build",
			)
		} else {
			nil
		}
		let valueJudgment: (compared: Bool, failure: GraphFuzzerFailure?) = if mirroringFailure == nil, drawingDefect == nil, comparesValues, let probes = graph.valueProbes, let feature = mock.valuePath {
			// The twin is rejected only where the mock agrees by values with the same types built inline, which a graph may also
			// name as the known right where the twin is accepted.
			if let knownRight = twin.valuePath, !graph.comparesValuesWithInline {
				try await valueFailure(of: graph, seed: seed, feature: feature, knownRight: knownRight, probes: probes)
			} else {
				try await valueFailure(of: graph, seed: seed, feature: feature, knownRight: inlineValuePath(of: graph), knownRightIsInline: true, probes: probes)
			}
		} else {
			(false, nil)
		}
		return GraphFuzzerCallingMockResult(
			twinSites: twinSites,
			mockSites: mockSites,
			twinDiagnostics: twin.diagnostics,
			twinInitializerLabels: twinInitializerLabels,
			passUps: passUps,
			drawingDefect: drawingDefect,
			comparedValues: valueJudgment.compared,
			failure: mirroringFailure ?? valueJudgment.failure,
		)
	}

	/// The words of the error that a seam built again passes its builder on unchanged, by which a twin's error is recognized
	/// as the outcome rule 7 lists apart. A fix that rewords the error fails
	/// `callingMock_buildsInlineValues_whenFillReadsValueOfLevelBetweenBuildsOfSeam` rather than leaving the outcome unjudged.
	static let seamBuiltAgainMarker = "again, but that call passes the builder"

	/// Whether `diagnostics`, as the tool prints them, hold an error, and every error they hold is that a seam built again
	/// passes its builder on unchanged.
	static func reportsOnlySeamBuiltAgain(_ diagnostics: String) -> Bool {
		let errors = diagnostics.split(separator: "\n").filter { $0.contains(": error: ") }
		return !errors.isEmpty && errors.allSatisfy { $0.contains(seamBuiltAgainMarker) }
	}

	/// `graph`'s `inlineModules` run through the module-info flow, as the comparator compiles them. Throws where the tool
	/// rejects them: a baseline that does not build is the harness's to fix.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	static func inlineValuePath(of graph: GraphFuzzerCallingMockGraph) async throws -> DifferentialValuePath {
		var filesToDelete = [URL]()
		defer {
			for file in filesToDelete {
				try? FileManager.default.removeItem(at: file)
			}
		}
		do {
			let output = try await executeSafeDIToolMultiModuleTest(modules: graph.inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
			return try DifferentialValuePath(output: output, modules: graph.inlineModules)
		} catch let error as SafeDIToolMultiModuleTestError {
			throw HarnessError(description: "The tool rejects \(graph.name) built inline: \(error.underlyingError)")
		}
	}

	/// Compiles the calling mock's path, `feature`, and the known-right path, `knownRight` – its twin's, or the same types
	/// built inline where `knownRightIsInline` – with the differential value comparator, and compares what `probes` build in
	/// each: a mock that does not compile, that traps or does not finish when its probe runs, or that builds other values,
	/// fails. Returns whether the values were compared, which they are not when compile verification is off. Any other
	/// failure of the comparator, such as a known-right path that does not compile or run, or a probe that names no
	/// declaration, is the harness's and throws.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	static func valueFailure(
		of graph: GraphFuzzerCallingMockGraph,
		seed: UInt64,
		feature: DifferentialValuePath,
		knownRight: DifferentialValuePath,
		knownRightIsInline: Bool = false,
		probes: [DifferentialValueProbe],
	) async throws -> (compared: Bool, failure: GraphFuzzerFailure?) {
		var filesToDelete = [URL]()
		defer {
			for file in filesToDelete {
				try? FileManager.default.removeItem(at: file)
			}
		}
		do {
			guard let comparison = try await DifferentialValueOracle.compare(feature: feature, knownRight: knownRight, probes: probes, filesToDelete: &filesToDelete) else {
				return (false, nil)
			}
			guard !comparison.differences.isEmpty else { return (true, nil) }
			var failure = GraphFuzzerFailure(
				seed: seed,
				kind: knownRightIsInline ? .callingMockBuildsOtherValuesThanInline : .callingMockBuildsOtherValuesThanTwin,
				details: "\(graph.name): the calling mock builds other values than \(knownRightIsInline ? "the same types built inline" : "its twin") at \(comparison.differences.map(\.description).joined(separator: "\n"))\n\(comparison.report)",
			)
			failure.valueDifferences = comparison.differences.map(\.description)
			return (true, failure)
		} catch let error as DifferentialValueOracleError {
			if error.path == .feature, case .compilingModule = error.stage {
				return (true, GraphFuzzerFailure(seed: seed, kind: .callingMockDoesNotCompile, details: "\(graph.name): \(error)"))
			} else if error.path == .feature, error.stage == .runningProbes {
				return (true, GraphFuzzerFailure(seed: seed, kind: .callingMockFailsWhenRun, details: "\(graph.name): \(error)"))
			} else {
				throw HarnessError(description: "The value comparison of \(graph.name) could not run: \(error)")
			}
		}
	}

	/// Each parameter of the caller's `mock()` that is neither `safeDIOverrides`, one of the graph's flat parameters, nor an
	/// optional builder for places the mock's calls fill (`optionalBuilderLabels(ofType:inGeneratedFile:)`): a place the mock
	/// passes up. It is classified only when the graph lists it among the places its module sees no type
	/// that fulfills, the tool skips the twin's error for, or the gate for a re-entered called type passes up
	/// (`fillGatePassesUp`); every other pass-up is unclassified. Throws when `generatedFile` declares no `mock()` in an extension of
	/// the caller, which a generated mock always has, so that a mock the parser misses is never read as one that passes
	/// nothing up.
	static func passUpsOf(_ graph: GraphFuzzerCallingMockGraph, inGeneratedFile generatedFile: String) throws -> [(label: String, reason: GraphFuzzerCallingMockPassUpReason?)] {
		guard let labels = mockParameterLabels(ofType: graph.callerTypeName, inGeneratedFile: generatedFile) else {
			throw HarnessError(description: "The calling mock of \(graph.name) is accepted, and its generated file declares no `mock()` in an extension of \(graph.callerTypeName)")
		}
		let optionalBuilderLabels = optionalBuilderLabels(ofType: graph.callerTypeName, inGeneratedFile: generatedFile)
		return labels
			.filter { $0 != "safeDIOverrides" && !graph.flatParameterLabels.contains($0) && !optionalBuilderLabels.contains($0) }
			.map { label in
				let reason: GraphFuzzerCallingMockPassUpReason? = if !graph.expectedPassUpLabels.contains(label) {
					nil
				} else if !graph.implementationIsVisible {
					.noVisibleImplementation
				} else if graph.mockSkipsTwinsError {
					.mockConditionIsInactive
				} else if graph.fillGatePassesUp {
					.fillOfReenteredCallReadsLazyValue
				} else {
					nil
				}
				return (label, reason)
			}
	}

	/// The labels of the parameters of every `mock(…)` an extension of `typeName` declares in `generatedFile`, each once, in
	/// order, or `nil` when it declares none.
	static func mockParameterLabels(ofType typeName: String, inGeneratedFile generatedFile: String) -> [String]? {
		parameterLabels(of: .mockFunction, ofType: typeName, inGeneratedFile: generatedFile)
	}

	/// The labels of the optional builders every `mock(…)` an extension of `typeName` declares in `generatedFile` takes for the
	/// places its calls of other modules' public mocks fill: each parameter of an optional function type that defaults to
	/// `nil`.
	static func optionalBuilderLabels(ofType typeName: String, inGeneratedFile generatedFile: String) -> Set<String> {
		let visitor = ParameterLabelVisitor(declarationKind: .mockFunction, typeName: typeName)
		visitor.walk(Parser.parse(source: generatedFile))
		return visitor.optionalBuilderLabels
	}

	/// The labels of the parameters of every initializer an extension of `typeName` declares in `generatedFile`, without
	/// the `__safeDI_` prefix of the initializer only generated code calls, each once, in order, or `nil` when it declares
	/// none.
	static func initializerParameterLabels(ofType typeName: String, inGeneratedFile generatedFile: String) -> [String]? {
		parameterLabels(of: .initializer, ofType: typeName, inGeneratedFile: generatedFile)
	}

	private static func parameterLabels(of declarationKind: ParameterLabelVisitor.DeclarationKind, ofType typeName: String, inGeneratedFile generatedFile: String) -> [String]? {
		let visitor = ParameterLabelVisitor(declarationKind: declarationKind, typeName: typeName)
		visitor.walk(Parser.parse(source: generatedFile))
		guard visitor.matchedDeclaration else { return nil }
		var labels = [String]()
		for label in visitor.labels.map({ $0.hasPrefix("__safeDI_") ? String($0.dropFirst("__safeDI_".count)) : $0 }) where !labels.contains(label) {
			labels.append(label)
		}
		return labels
	}

	private final class ParameterLabelVisitor: SyntaxVisitor {
		enum DeclarationKind {
			case mockFunction
			case initializer
		}

		init(declarationKind: DeclarationKind, typeName: String) {
			self.declarationKind = declarationKind
			self.typeName = typeName
			super.init(viewMode: .sourceAccurate)
		}

		let declarationKind: DeclarationKind
		let typeName: String
		var labels = [String]()
		/// The labels of the parameters of an optional function type that default to `nil`.
		var optionalBuilderLabels = Set<String>()
		/// Whether a declaration of the kind was found, so that one without parameters is told from none.
		var matchedDeclaration = false

		override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
			guard declarationKind == .mockFunction, node.name.text == "mock", isInExtensionOfType(node) else { return .skipChildren }
			matchedDeclaration = true
			labels += node.signature.parameterClause.parameters.map(\.firstName.text)
			for parameter in node.signature.parameterClause.parameters {
				// A closure, `(() -> T)?` or `(@Sendable () -> T)?`, or the builder of an instantiator that forwards a value,
				// `ErasedInstantiator<Int, any T>.Builder?`.
				guard parameter.defaultValue?.value.trimmedDescription == "nil",
				      let optional = parameter.type.as(OptionalTypeSyntax.self),
				      optional.wrappedType.as(TupleTypeSyntax.self)?.elements.first?.type.is(FunctionTypeSyntax.self) == true
				      || optional.wrappedType.as(TupleTypeSyntax.self)?.elements.first?.type.as(AttributedTypeSyntax.self)?.baseType.is(FunctionTypeSyntax.self) == true
				      || optional.wrappedType.as(MemberTypeSyntax.self)?.name.text == "Builder"
				else { continue }
				optionalBuilderLabels.insert(parameter.firstName.text)
			}
			return .skipChildren
		}

		override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
			guard declarationKind == .initializer, isInExtensionOfType(node) else { return .skipChildren }
			matchedDeclaration = true
			labels += node.signature.parameterClause.parameters.map(\.firstName.text)
			return .skipChildren
		}

		/// Whether `node` is a member of an extension of the type itself, never of a type the extension nests, such as a
		/// seam's builder struct inside its scope enum, whose initializers are not the type's.
		private func isInExtensionOfType(_ node: some SyntaxProtocol) -> Bool {
			var parent = node.parent
			while let ancestor = parent {
				if let extensionDeclaration = ancestor.as(ExtensionDeclSyntax.self) {
					return extensionDeclaration.extendedType.trimmedDescription == typeName
				} else if ancestor.is(StructDeclSyntax.self) || ancestor.is(ClassDeclSyntax.self) || ancestor.is(EnumDeclSyntax.self) || ancestor.is(ActorDeclSyntax.self) {
					return false
				} else {
					parent = ancestor.parent
				}
			}
			return false
		}
	}

	/// A run the check cannot judge: a module the tool accepted generated no file for the caller's module, or the calling
	/// mock's generated file declares no `mock()` for the caller.
	struct HarnessError: Error, CustomStringConvertible {
		let description: String
	}

	/// One form's run: the tool's diagnostics and the module whose `generate` reported them when it rejects the graph, else
	/// the calling mock's module's generated file and the form's modules with their generated code, as the comparator
	/// compiles them.
	private struct ToolRun {
		let diagnostics: String?
		let failingModule: String?
		let generatedCallerFile: String?
		let valuePath: DifferentialValuePath?
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func toolRun(of graph: GraphFuzzerCallingMockGraph, _ form: GraphFuzzerCallingMockGraph.Form) async throws -> ToolRun {
		var filesToDelete = [URL]()
		defer {
			for file in filesToDelete {
				try? FileManager.default.removeItem(at: file)
			}
		}
		do {
			let output = try await executeSafeDIToolMultiModuleTest(
				modules: graph.modules(form),
				integration: .moduleInfo,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
			guard let generatedCallerFile = output.modules[graph.callerModule]?.generatedFiles["\(graph.callerModule).swift"] else {
				throw HarnessError(description: "The \(form) of \(graph.name) is accepted, and module \(graph.callerModule) generated no \(graph.callerModule).swift")
			}
			return try ToolRun(diagnostics: nil, failingModule: nil, generatedCallerFile: generatedCallerFile, valuePath: DifferentialValuePath(output: output, modules: graph.modules(form)))
		} catch let error as SafeDIToolMultiModuleTestError {
			return ToolRun(diagnostics: "\(error.underlyingError)", failingModule: error.moduleName, generatedCallerFile: nil, valuePath: nil)
		}
	}
}

// MARK: - The public mock corpus's calling mocks

/// What the production twins of the public mock corpus's calling mocks report: each mocked consumer of a graph the tool
/// accepts (`FuzzApp`'s and `FuzzOther`'s types with a generated mock), run as its twin, one at a time. Only reports: the
/// rule for mirrored rejections is applied to its count by hand before the change that makes a calling mock mirror its
/// production tree lands, which lands before 2.3.0.
enum GraphFuzzerCallingMockTwinReport {
	/// The text by which each shape's own error is recognized in a graph drawn without the shape's facts.
	static let shapeErrorMarkers: [(shape: GraphFuzzerCallingMockShape, marker: String)] = [
		(.outerSeamValue, "on from its own caller, which cannot hand it"),
		(.appOnlyScreenInLoop, "builds only after it calls the builder for"),
		(.seamBuiltAgain, GraphFuzzerCallingMockCheck.seamBuiltAgainMarker),
		(.loopThroughInnerSeamBuilder, "is received while it is still being instantiated"),
	]

	struct Finding: CustomStringConvertible {
		let seed: UInt64
		let consumer: String
		let shape: GraphFuzzerCallingMockShape?
		let firstErrorLine: String

		var description: String {
			"seed \(seed) \(consumer): \(shape?.rawValue ?? "other error"): \(firstErrorLine)"
		}
	}

	/// Each consumer whose twin `fixture` rejects while the tool accepts `fixture` itself.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	static func findings(in fixture: GraphFuzzerFixture) async throws -> [Finding] {
		guard case .accepted = try await GraphFuzzerOracle.toolOutcome(of: fixture), let modules = fixture.modules else { return [] }
		var findings = [Finding]()
		for (fileIndex, module) in modules.enumerated() where module == .samePackageCaller || module == .otherPackageCaller {
			let lines = fixture.swiftFileContent[fileIndex].split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
			for (lineIndex, line) in lines.enumerated() where line.hasPrefix("@Instantiable(") && line.contains("generateMock: ") {
				let consumer = lines.dropFirst(lineIndex + 1).first?.split(separator: " ").first { $0.hasPrefix(fixture.typeNamePrefix) }.map { String($0) } ?? "line \(lineIndex + 1)"
				var twinLines = lines
				twinLines[lineIndex] = line
					.replacingOccurrences(of: "generateMock: .public", with: "generateDependencyTree: true")
					.replacingOccurrences(of: "generateMock: true", with: "generateDependencyTree: true")
					.replacingOccurrences(of: ", customMockName: \"customMock\"", with: "")
				var twinContent = fixture.swiftFileContent
				twinContent[fileIndex] = twinLines.joined(separator: "\n")
				guard case let .rejected(diagnostics) = try await GraphFuzzerOracle.toolOutcome(of: GraphFuzzerFixture(seed: fixture.seed, swiftFileContent: twinContent)) else { continue }
				let firstErrorLine = diagnostics.split(separator: "\n").first { $0.contains(": error: ") }.map(String.init) ?? diagnostics
				findings.append(Finding(
					seed: fixture.seed,
					consumer: consumer.trimmingCharacters(in: CharacterSet(charactersIn: ":")),
					shape: shapeErrorMarkers.first { firstErrorLine.contains($0.marker) }?.shape,
					firstErrorLine: firstErrorLine,
				))
			}
		}
		return findings
	}
}
