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
	/// type the caller instantiates, or by the caller with the fill calling it again (`CallerLazyValue.Call`). Some graphs
	/// hold the place on the called type's root level instead (`CallerLazyValue.placeOnCalledTypesRoot`).
	case fillReceivesCallersLazyValueBelowCalledRoot

	static func < (lhs: Self, rhs: Self) -> Bool {
		allCases.firstIndex(of: lhs) ?? 0 < allCases.firstIndex(of: rhs) ?? 0
	}

	/// Whether production rejects the shape with an error of its own, which the calling mock must report too.
	var twinRejects: Bool {
		switch self {
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .fillReceivesValueBuildingTheCall, .fillInstantiatesTypeNoDeclarationCanFulfill, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive:
			true
		case .callersOwnValue, .noVisibleImplementation, .implementationReceivesWhatNothingProvides, .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot:
			false
		}
	}

	/// Whether the calling mock's values are compared with those of the same types built inline even where the twin is
	/// accepted: where the fill holds the caller's lazy wrapper, which value inline hands it is what the mock must build.
	var comparesValuesWithInline: Bool {
		switch self {
		case .fillReceivesCallersLazyValueBelowCalledRoot:
			true
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .noVisibleImplementation, .implementationReceivesWhatNothingProvides, .fillReceivesValueBuildingTheCall, .fillInstantiatesWhatNothingFulfills, .fillInstantiatesTypeNoDeclarationCanFulfill, .seamCallerFillSharesBuilder, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace:
			false
		}
	}

	/// Whether the calling mock's pass-ups must be exactly the graph's `expectedPassUpLabels`: the control's hole builder,
	/// the builders of what the fill instantiates that nothing fulfills, which are the twin's, and the place whose fill the
	/// tool does not check where the mock condition is inactive.
	var passesUpExactlyTheExpectedLabels: Bool {
		switch self {
		case .noVisibleImplementation, .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive:
			true
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .implementationReceivesWhatNothingProvides, .fillReceivesValueBuildingTheCall, .fillInstantiatesTypeNoDeclarationCanFulfill, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot:
			false
		}
	}

	var isControl: Bool {
		switch self {
		case .noVisibleImplementation:
			true
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .implementationReceivesWhatNothingProvides, .fillReceivesValueBuildingTheCall, .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder, .fillInstantiatesTypeNoDeclarationCanFulfill, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot:
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
	/// type's received value, for every caller and place; and the fill that receives the caller's lazy value below the
	/// called type's root, for every caller.
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
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .noVisibleImplementation, .implementationReceivesWhatNothingProvides, .fillReceivesValueBuildingTheCall, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot:
			nil
		}
		// Drawn after the fill's holes, and only for its shape.
		mockBuild = switch cell.shape {
		case .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive:
			random.element(of: [.debugWithoutMockCondition, .release])
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .noVisibleImplementation, .implementationReceivesWhatNothingProvides, .fillReceivesValueBuildingTheCall, .fillInstantiatesWhatNothingFulfills, .fillInstantiatesTypeNoDeclarationCanFulfill, .seamCallerFillSharesBuilder, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot:
			.compilesGeneratedMocks
		}
		// Drawn after everything else, and only for its shape.
		callerLazyValue = switch cell.shape {
		case .fillReceivesCallersLazyValueBelowCalledRoot:
			CallerLazyValue(random: &random)
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .noVisibleImplementation, .implementationReceivesWhatNothingProvides, .fillReceivesValueBuildingTheCall, .fillInstantiatesWhatNothingFulfills, .fillInstantiatesTypeNoDeclarationCanFulfill, .seamCallerFillSharesBuilder, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace:
			nil
		}
	}

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
			// Drawn after every other variation, and not where the fill calls the called type again: a place on the called mock's
			// root level whose fill builds the called type again is the third known defect of “The caller's own value”
			// (`public-mock-builders.md`), whose re-entered call is handed another wrapper than inline's.
			placeOnCalledTypesRoot = call == .fillCallsAgain ? false : random.element(of: [false, true])
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
		/// Whether the called type holds the place itself, on its root level, in place of the level between, which it then
		/// declares only where it builds that level inside a `SendableInstantiator` (`buildsPlaceInSendableFunctionToo`), so
		/// that the fill that reads the caller's value is on the root level while a second place's fill re-enters
		/// (`secondPlaceCallsAgain`).
		let placeOnCalledTypesRoot: Bool
	}

	/// How the caller and the called type's tree hold the value, for the shape whose fill receives the caller's lazy value
	/// below the called type's root, or `nil`.
	let callerLazyValue: CallerLazyValue?

	/// The build of the calling mock's module the tool is told of: one that compiles the generated mocks, but in the shape
	/// whose fill the tool does not check where the mock condition is inactive.
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
			valueProbes: valueProbes,
			mockBuild: mockBuild,
			twinErrorIsCheckedOnlyWhereMocksCompile: twinErrorIsCheckedOnlyWhereMocksCompile,
			comparesValuesWithInline: cell.shape.comparesValuesWithInline,
		)
	}

	let seed: UInt64
	let cell: GraphFuzzerCallingMockCell

	typealias Form = GraphFuzzerCallingMockGraph.Form

	/// The parameters of the calling mock's `mock()` that are values rather than builders: none of the draw's callers
	/// forwards a value, and the only received value a caller's tree cannot build is the one the fill of the
	/// nothing-builds shape receives.
	var flatParameterLabels: Set<String> {
		switch cell.shape {
		case .implementationReceivesWhatNothingProvides:
			[names.token.lowercasedFirst]
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .noVisibleImplementation, .fillReceivesValueBuildingTheCall, .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder, .fillInstantiatesTypeNoDeclarationCanFulfill, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot:
			[]
		}
	}

	/// Whether a type that fulfills the hole is visible from the calling mock's module.
	var implementationIsVisible: Bool {
		switch cell.shape {
		case .noVisibleImplementation, .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder:
			false
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .implementationReceivesWhatNothingProvides, .fillReceivesValueBuildingTheCall, .fillInstantiatesTypeNoDeclarationCanFulfill, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot:
			true
		}
	}

	/// The builder of the hole's place, as contract rule 8 labels it in the twin's seam initializer and the calling mock's
	/// `mock()`: `<filling type>Builder` when the filling type is the returned type, the hole, else
	/// `<filling type>_<returned type>Builder`, the filling type's leading capitals lowered.
	var holeBuilderLabel: String {
		let fillingType = switch cell.place {
		case .plain:
			names.hole
		case .deferred:
			names.fill
		}
		let stem = String(GraphFuzzerPublicMockDraw.builderLabel(ofTypeNamed: fillingType).dropLast("Builder".count))
		return stem + (fillingType == names.hole ? "" : "_\(names.hole)") + "Builder"
	}

	/// What the twin's seam initializer takes where production accepts the graph: nothing where its tree fills the place,
	/// the value the fill receives where nothing in the tree builds it, and the place's builder where no type that fulfills
	/// the place is visible.
	var expectedTwinInitializerLabels: [String]? {
		switch cell.shape {
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .fillReceivesValueBuildingTheCall, .fillInstantiatesTypeNoDeclarationCanFulfill, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive:
			nil
		case .callersOwnValue, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot:
			[]
		case .implementationReceivesWhatNothingProvides:
			[names.token.lowercasedFirst]
		case .noVisibleImplementation:
			[holeBuilderLabel]
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
	/// mock's. Where it is a seam, its own tree, which every build generates, reports the error.
	var twinErrorIsCheckedOnlyWhereMocksCompile: Bool {
		switch cell.shape {
		case .fillInstantiatesTypeNoDeclarationCanFulfill, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive:
			fillHoles?.fulfillerIsSeam == false
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .noVisibleImplementation, .implementationReceivesWhatNothingProvides, .fillReceivesValueBuildingTheCall, .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot:
			false
		}
	}

	/// The places the calling mock may pass up: the hole's builder where its module sees no type that fulfills the hole, or
	/// where the tool skips the twin's error in the mock, as a build that leaves the mock condition inactive skips a plain
	/// implementation's, and the builders of what the fill instantiates that nothing fulfills, as the twin takes them.
	var expectedPassUpLabels: [String] {
		switch cell.shape {
		case .noVisibleImplementation:
			[holeBuilderLabel]
		case .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive:
			twinErrorIsCheckedOnlyWhereMocksCompile ? [holeBuilderLabel] : []
		case .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder:
			expectedBuilders.map(\.label)
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .implementationReceivesWhatNothingProvides, .fillReceivesValueBuildingTheCall, .fillInstantiatesTypeNoDeclarationCanFulfill, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot:
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
		guard cell.shape != .fillReceivesCallersLazyValueBelowCalledRoot else { return callerLazyValueProbes }
		// Qualified by its module: Foundation, which the probe executable imports, declares `Host` on macOS.
		let caller = "\(names.callerModuleName).\(names.caller)"
		let token = names.token.lowercasedFirst
		let calls: (mock: String, twin: String)? = switch cell.shape {
		case .callersOwnValue, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace:
			("\(caller).mock()", "\(caller)()")
		case .implementationReceivesWhatNothingProvides:
			("\(caller).mock(\(token): \(names.token)())", "\(caller)(__safeDI_\(token): \(names.token)())")
		case .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder:
			fillHoles.map { _ in
				let builders = expectedBuilders
				let mockArguments = builders.map { "\($0.label): \($0.value(names.callerModuleName))" }
				let twinArguments = builders.map { "__safeDI_\($0.label): .init(__safeDI_noScope: \($0.value(names.callerModuleName)))" }
				return ("\(caller).mock(\(mockArguments.joined(separator: ", ")))", "\(caller)(\(twinArguments.joined(separator: ", ")))")
			}
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .noVisibleImplementation, .fillReceivesValueBuildingTheCall, .fillInstantiatesTypeNoDeclarationCanFulfill, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive, .fillReceivesCallersLazyValueBelowCalledRoot:
			nil
		}
		guard let calls else { return nil }
		let (mockCall, twinCall) = calls
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
			return [DifferentialValueProbe(
				name: "(\(caller), \(caller).\(place).instantiate(7))",
				expression: Self.callerAndFill(of: mockCall, place: place),
				knownRightExpression: Self.callerAndFill(of: twinCall, place: place),
			)]
		}
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
		// The place below the called type's root, or on it, from the called type.
		let placeInCalledType = callerLazyValue?.placeOnCalledTypesRoot == true ? placeLabel : "\(names.between.lowercasedFirst).\(placeLabel)"
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
		func holdsCallersInstance(_ call: String, fill filledExpression: String) -> String {
			"{ let caller = \(call); return (\(filledExpression) as! \(fill)).\(value).instance === caller.\(value).instance }()"
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
		if callerLazyValue?.secondPlaceCallsAgain == true {
			let reenteredThroughSecondPlace = "(caller.\(calledType).\(Self.secondLevelLabel).\(Self.secondPlaceLabel) as! \(names.callerModuleName).\(Self.secondFillName)).\(reenteredCalledType).\(placeInCalledType)\(instantiatedPlace)"
			probes.append(DifferentialValueProbe(
				name: "\(names.fill) re-entered through \(Self.secondFillName) holds \(names.caller).\(value)",
				expression: holdsCallersWrapper("\(caller).mock()", fill: reenteredThroughSecondPlace),
				knownRightExpression: holdsCallersWrapper("\(caller)()", fill: reenteredThroughSecondPlace),
			))
		}
		if callerLazyValue?.buildsPlaceInSendableFunctionToo == true {
			let builtInSendableFunction = "caller.\(calledType).\(names.between.lowercasedFirst)Builder.instantiate().\(placeLabel)\(instantiatedPlace)"
			probes.append(DifferentialValueProbe(
				name: "\(names.fill) built in a @Sendable function holds \(names.caller).\(value)",
				expression: holdsCallersWrapper("\(caller).mock()", fill: builtInSendableFunction),
				knownRightExpression: holdsCallersWrapper("\(caller)()", fill: builtInSendableFunction),
			))
		}
		return probes
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
		case .callersOwnValue, .noVisibleImplementation, .implementationReceivesWhatNothingProvides, .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder, .fillReceivesValueOnlyInnerMockRequires, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot:
			return nil
		}
	}

	typealias File = GraphFuzzerCallingMockGraph.File

	/// The draw's files, in dependency order, with each file's content by module and file name.
	func files(_ form: Form) -> [File] {
		switch cell.shape {
		case .outerSeamValue, .loopThroughInnerSeamBuilder, .callersOwnValue, .noVisibleImplementation, .implementationReceivesWhatNothingProvides, .fillReceivesValueBuildingTheCall, .fillInstantiatesWhatNothingFulfills, .seamCallerFillSharesBuilder, .fillInstantiatesTypeNoDeclarationCanFulfill, .fillInstantiatesTypeNoDeclarationCanFulfillWhereMockConditionIsInactive, .fillReceivesValueOnlyInnerMockRequires:
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
		switch cell.place {
		case .plain:
			(protocolName.lowercasedFirst, "any \(protocolName)", "@Instantiated")
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
		return """
		import SafeDI

		public protocol \(names.hole): AnyObject {}

		\(attribute)
		public final class \(names.inner): Instantiable {
		    init(\(place.label): \(place.type)) { self.\(place.label) = \(place.label) }
		    \(place.attribute) public let \(place.label): \(place.type)
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
		case .outerSeamValue, .callersOwnValue, .noVisibleImplementation, .implementationReceivesWhatNothingProvides, .appOnlyScreenInLoop, .seamBuiltAgain, .fillReceivesValueBuildingTheCall, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot:
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
	private func fillDeclaration(named fillName: String, protocolName: String, received: (label: String, type: String)?, instantiated: (label: String, type: String)? = nil, isPublic: Bool) -> String {
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
			properties.append("@Received let \(received.label): \(received.type)")
		}
		if let instantiated {
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

	/// The caller's declaration: its properties, each `@Instantiated`, with the ticker where the draw puts it.
	private func callerDeclaration(_ form: Form, properties: [(label: String, type: String)]) -> String {
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
		let parameters = properties.map { "\($0.label): \($0.type)" }.joined(separator: ", ")
		let assignments = properties.map { "self.\($0.label) = \($0.label)" }.joined(separator: "; ")
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
		case .callersOwnValue:
			declarations.append(fillDeclaration(named: names.fill, protocolName: names.hole, received: (names.value.lowercasedFirst, names.value), isPublic: callerIsPublic))
			declarations.append(callerDeclaration(form, properties: [(names.value.lowercasedFirst, names.value), (names.inner.lowercasedFirst, names.inner)]))
		case .fillReceivesValueOnlyInnerMockRequires:
			declarations.append(fillDeclaration(named: names.fill, protocolName: names.hole, received: (names.value.lowercasedFirst, names.value), isPublic: callerIsPublic))
			declarations.append(callerDeclaration(form, properties: [(names.value.lowercasedFirst, names.value), (names.outer.lowercasedFirst, names.outer)]))
		case .noVisibleImplementation:
			declarations.append(callerDeclaration(form, properties: [(names.value.lowercasedFirst, names.value), (names.inner.lowercasedFirst, names.inner)]))
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
		case .appOnlyScreenInLoop, .seamBuiltAgain, .calledTypesReceivedValueInSendablePlace, .fillReceivesCallersLazyValueBelowCalledRoot:
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
	/// or only if available, so the called type's tree binds it. Where the place is on the called type's root level, the
	/// called type holds it in place of the level between.
	private var lazyValueBelowCalledRootModuleContent: String {
		let place = holePlace(protocolName: names.hole, fillName: names.fill)
		let between = names.between.lowercasedFirst
		let sibling = names.sibling.lowercasedFirst
		let value = names.value.lowercasedFirst
		let receivesOnlyIfAvailable = callerLazyValue?.receivesOnlyIfAvailable == true
		let siblingValueType = receivesOnlyIfAvailable ? "\(names.value)?" : names.value
		let siblingAttribute = receivesOnlyIfAvailable ? "@Received(onlyIfAvailable: true)" : "@Received"
		var innerProperties = [(attribute: "@Instantiated", label: between, type: names.between), (attribute: "@Instantiated", label: sibling, type: names.sibling)]
		let placeIsOnRoot = callerLazyValue?.placeOnCalledTypesRoot == true
		if placeIsOnRoot {
			innerProperties[0] = (attribute: place.attribute, label: place.label, type: place.type)
		}
		var betweenDeclaration = """


		@Instantiable
		public final class \(names.between): Instantiable {
		    init(\(place.label): \(place.type)) { self.\(place.label) = \(place.label) }
		    \(place.attribute) public let \(place.label): \(place.type)
		}
		"""
		if placeIsOnRoot, callerLazyValue?.buildsPlaceInSendableFunctionToo != true {
			betweenDeclaration = ""
		}
		var secondLevel = ""
		if callerLazyValue?.secondPlaceCallsAgain == true {
			innerProperties.append((attribute: "@Instantiated", label: Self.secondLevelLabel, type: "Hub"))
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
			innerProperties.append((attribute: "@Instantiated", label: "\(between)Builder", type: "SendableInstantiator<\(names.between)>"))
		}
		let innerParameters = innerProperties.map { "\($0.label): \($0.type)" }.joined(separator: ", ")
		let innerAssignments = innerProperties.map { "self.\($0.label) = \($0.label)" }.joined(separator: "; ")
		let innerDeclarations = innerProperties.map { "    \($0.attribute) public let \($0.label): \($0.type)" }.joined(separator: "\n")
		return """
		import SafeDI

		public protocol \(names.hole): AnyObject {}

		@Instantiable
		public final class \(names.value): Instantiable, Sendable {
		    public init() {}
		}\(betweenDeclaration)

		@Instantiable
		public final class \(names.sibling): Instantiable {
		    init(\(value): \(siblingValueType)) { self.\(value) = \(value) }
		    \(siblingAttribute) public let \(value): \(siblingValueType)
		}

		@Instantiable(generateDependencyTree: true, generateMock: .public)
		public final class \(names.inner): Instantiable {
		    init(\(innerParameters)) { \(innerAssignments) }
		\(innerDeclarations)
		}\(secondLevel)
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
		let instantiated: (label: String, type: String)? = callerLazyValue?.call == .fillCallsAgain ? ("\(inner)Builder", "Instantiator<\(names.inner)>") : nil
		var declarations = [
			"import SafeDI\nimport \(names.innerModuleName)",
			fillDeclaration(named: names.fill, protocolName: names.hole, received: (value, wrapped), instantiated: instantiated, isPublic: callerIsPublic),
		]
		if callerLazyValue?.secondPlaceCallsAgain == true {
			declarations.append("""
			@Instantiable(fulfillingAdditionalTypes: [(any \(Self.secondPlaceProtocol)).self])
			\(callerAccess)final class \(Self.secondFillName): \(Self.secondPlaceProtocol), Instantiable {
			    \(callerAccess)init(\(inner)Builder: Instantiator<\(names.inner)>) { self.\(inner)Builder = \(inner)Builder }
			    @Instantiated let \(inner)Builder: Instantiator<\(names.inner)>
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
			declarations.append(callerDeclaration(form, properties: [(value, wrapped), (intermediate.lowercasedFirst, intermediate)]))
		} else {
			declarations.append(callerDeclaration(form, properties: [(value, wrapped), (inner, names.inner)]))
		}
		return declarations.joined(separator: "\n\n")
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

		var fileName: String {
			"\(module)Types.swift"
		}

		var relativePath: String {
			"\(module)/\(fileName)"
		}
	}

	/// The package every module belongs to.
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
	/// The `SafeDIConfiguration.swift` the calling mock's module holds beside its file, which the twin's does not: one that
	/// lists the caller in `additionalMocksToGenerate`, or `nil`.
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

	/// Whether the tool skips the twin's error in the mock: the error is one it checks only where the generated mocks
	/// compile, and `mockBuild` leaves the mock condition inactive. The mock must then be accepted, passing up
	/// `expectedPassUpLabels`, where its twin reports the error.
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
				packageName: Self.packageName,
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

	/// The configuration the caller's module holds in `form`.
	private func configuration(of form: Form) -> String? {
		switch form {
		case .mock:
			mockConfiguration
		case .twin:
			nil
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
		valueProbes: [DifferentialValueProbe]? = nil,
		mockBuild: MockBuild = .compilesGeneratedMocks,
		twinErrorIsCheckedOnlyWhereMocksCompile: Bool = false,
		comparesValuesWithInline: Bool = false,
	) {
		let twinFiles = mockFiles.enumerated().map { index, file in
			guard index == mockFiles.count - 1 else { return file }
			return File(
				module: file.module,
				dependencies: file.dependencies,
				content: file.content
					.replacingOccurrences(of: "@Instantiable(generateMock: true)", with: "@Instantiable(generateDependencyTree: true)")
					.replacingOccurrences(of: "@Instantiable(generateMock: .public)", with: "@Instantiable(generateDependencyTree: true)"),
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
			valueProbes: valueProbes,
			mockBuild: mockBuild,
			twinErrorIsCheckedOnlyWhereMocksCompile: twinErrorIsCheckedOnlyWhereMocksCompile,
			comparesValuesWithInline: comparesValuesWithInline,
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
		valueProbes: [DifferentialValueProbe]? = nil,
		mockBuild: MockBuild = .compilesGeneratedMocks,
		twinErrorIsCheckedOnlyWhereMocksCompile: Bool = false,
		comparesValuesWithInline: Bool = false,
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
		self.valueProbes = valueProbes
		self.mockBuild = mockBuild
		self.twinErrorIsCheckedOnlyWhereMocksCompile = twinErrorIsCheckedOnlyWhereMocksCompile
		self.comparesValuesWithInline = comparesValuesWithInline
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
/// the tool checks a fill production rejects only where the generated mocks compile.
enum GraphFuzzerCallingMockPassUpReason: String, CaseIterable, Comparable {
	/// No type that fulfills the place's type is visible from the mock's module.
	case noVisibleImplementation
	/// The build leaves the mock condition inactive (`GraphFuzzerCallingMockGraph.MockBuild`), so the tool does not check
	/// the fill production rejects, and passes its place up (`GraphFuzzerCallingMockGraph.mockSkipsTwinsError`).
	case mockConditionIsInactive

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
	/// the same types built inline too, rather than with the twin.
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
			GraphFuzzerFailure(
				seed: seed,
				kind: .callingMockRejectsWhereTwinAccepts,
				details: "\(graph.name): the twin is accepted and the calling mock reports \(mockDiagnostics)",
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

	/// Each parameter of the caller's `mock()` that is neither `safeDIOverrides` nor one of the graph's flat parameters: a
	/// place the mock passes up. It is classified only when the graph lists it among the places its module sees no type
	/// that fulfills; every other pass-up is unclassified. Throws when `generatedFile` declares no `mock()` in an extension of
	/// the caller, which a generated mock always has, so that a mock the parser misses is never read as one that passes
	/// nothing up.
	static func passUpsOf(_ graph: GraphFuzzerCallingMockGraph, inGeneratedFile generatedFile: String) throws -> [(label: String, reason: GraphFuzzerCallingMockPassUpReason?)] {
		guard let labels = mockParameterLabels(ofType: graph.callerTypeName, inGeneratedFile: generatedFile) else {
			throw HarnessError(description: "The calling mock of \(graph.name) is accepted, and its generated file declares no `mock()` in an extension of \(graph.callerTypeName)")
		}
		return labels
			.filter { $0 != "safeDIOverrides" && !graph.flatParameterLabels.contains($0) }
			.map { label in
				let reason: GraphFuzzerCallingMockPassUpReason? = if !graph.expectedPassUpLabels.contains(label) {
					nil
				} else if !graph.implementationIsVisible {
					.noVisibleImplementation
				} else if graph.mockSkipsTwinsError {
					.mockConditionIsInactive
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
		/// Whether a declaration of the kind was found, so that one without parameters is told from none.
		var matchedDeclaration = false

		override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
			guard declarationKind == .mockFunction, node.name.text == "mock", isInExtensionOfType(node) else { return .skipChildren }
			matchedDeclaration = true
			labels += node.signature.parameterClause.parameters.map(\.firstName.text)
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
