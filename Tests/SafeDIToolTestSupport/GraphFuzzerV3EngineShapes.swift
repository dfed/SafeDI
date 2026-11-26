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

// MARK: - Draws

/// The shapes the shared layout engine must keep apart once `.v3Unstable` mocks are laid out on it, drawn into the API
/// version agreement corpus (`GraphFuzzerAPIVersionAgreement.fixture(forSeed:in:)`), each on a stream of its own and
/// appended after every type of the graph under names that sort after them (`<prefix>ZV3…`), so a graph without a draw is
/// drawn as before and `computeCycleEdges`, which walks types by name, enters the graph's own cycles where it did.
///
/// - **Two places of one configured type under different parents** (`configuredTypeUnderTwoParents`): `ZV3ShareHost`
///   builds `ZV3ShareLeft` and `ZV3ShareRight`, each of which builds `ZV3Shared`, a type with a child and its own
///   default `tag`, so the engine may share one builder function between the two places. The right place is now and then
///   held in an `Instantiator`, or one level deeper beneath `ZV3ShareMiddle`. The probe hands each place its own `tag`
///   through its parent's configuration, or only one of them, so each call of a shared function must pass its own
///   `parent.field ?? .init()`.
/// - **A value the mock cannot build, at two places** (`unbuildableValueAtTwoPlaces`): `ZV3GadgetOwner` instantiates
///   `ZV3Gadget`, which is not `@Instantiable`, and `ZV3GadgetHost` reaches the owner under two parents, the second now
///   and then through an `Instantiator`, so `mock()` takes one builder (D12) that a shared function must call once per
///   construction, never once per function.
/// - **Two closers of one cycle target** (`twoClosersOfOneCycleTarget`): `ZV3LoopTarget`, mocked, builds `ZV3LoopA` and
///   `ZV3LoopB`, each of which closes the cycle with `Instantiator<ZV3LoopTarget>`. The probe configures the root, and
///   now and then each closer's later pass, so each closer must pass its own `parent.field ?? nearest`.
///
/// Each probe is a pair in the `.v3Unstable` path: the mock called with the drawn overrides, against the tree built by
/// hand under the Manual's rule for v3 overrides (a child field left `nil` reads the configuration of the nearest
/// ancestor of the child's type on its path, or that type's defaults), so the pair agrees on the walk and on the engine,
/// and a layout that hands one place another's configuration or value differs.
struct GraphFuzzerV3EngineDraw: Equatable, Sendable {
	enum Shape: String, CaseIterable, Sendable {
		case configuredTypeUnderTwoParents
		case unbuildableValueAtTwoPlaces
		case twoClosersOfOneCycleTarget
	}

	/// How the right place of a two-place draw is held.
	enum RightPlace: String, CaseIterable, Sendable {
		/// `ZV3ShareRight` (or `ZV3GadgetRight`) instantiates the type by value.
		case byValue
		/// Through `Instantiator<T>`, which the comparator calls twice.
		case instantiator
		/// By value, beneath `ZV3ShareMiddle`, one level deeper than the left place.
		case deeper
	}

	/// Which places of the configured type the probe configures.
	enum ConfiguredPlaces: String, CaseIterable, Sendable {
		case both
		case leftOnly
		case rightOnly
	}

	/// What the probe hands `ZV3LoopB`'s closer.
	enum SecondCloser: String, CaseIterable, Sendable {
		/// No field: the closer reads the nearest `ZV3LoopTarget` configuration, the root's.
		case unconfigured
		/// `ZV3LoopB`'s own configuration without a closer field: the same read, through an explicit level.
		case emptyLevel
		/// A configuration of its own, `tag: 3`.
		case ownConfiguration
	}

	struct ConfiguredTypeUnderTwoParents: Equatable, Sendable {
		let rightPlace: RightPlace
		let configuredPlaces: ConfiguredPlaces
	}

	struct UnbuildableValueAtTwoPlaces: Equatable, Sendable {
		/// `.deeper` is not drawn here: the D12 builder's count does not depend on depth.
		let rightPlaceIsInstantiator: Bool
	}

	struct TwoClosersOfOneCycleTarget: Equatable, Sendable {
		let secondCloser: SecondCloser
		/// Whether the first closer's later pass configures `ZV3LoopB` again (`zV3LoopB: .init(zV3LoopTargetBuilder: .init(tag: 4))`),
		/// so the third pass reads a field two levels down rather than the nearest.
		let laterPassConfiguresSecondCloser: Bool
	}

	init(seed: UInt64) {
		var random = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.randomSeedMask)
		// Every roll is made whatever the draw, so one shape's rolls never move another's.
		let drawsShare = random.percentChance(30)
		let rightPlace = random.element(of: RightPlace.allCases)
		let configuredPlaces = random.element(of: ConfiguredPlaces.allCases)
		let drawsGadget = random.percentChance(30)
		let gadgetRightIsInstantiator = random.percentChance(50)
		let drawsLoop = random.percentChance(30)
		let secondCloser = random.element(of: SecondCloser.allCases)
		let laterPassConfiguresSecondCloser = random.percentChance(40)
		configuredTypeUnderTwoParents = drawsShare ? ConfiguredTypeUnderTwoParents(rightPlace: rightPlace, configuredPlaces: configuredPlaces) : nil
		unbuildableValueAtTwoPlaces = drawsGadget ? UnbuildableValueAtTwoPlaces(rightPlaceIsInstantiator: gadgetRightIsInstantiator) : nil
		twoClosersOfOneCycleTarget = drawsLoop ? TwoClosersOfOneCycleTarget(secondCloser: secondCloser, laterPassConfiguresSecondCloser: laterPassConfiguresSecondCloser) : nil
	}

	/// The stream of these draws, apart from every other stream of the fuzzer.
	static let randomSeedMask: UInt64 = 0x5633454E47494E45

	let configuredTypeUnderTwoParents: ConfiguredTypeUnderTwoParents?
	let unbuildableValueAtTwoPlaces: UnbuildableValueAtTwoPlaces?
	let twoClosersOfOneCycleTarget: TwoClosersOfOneCycleTarget?

	/// The shapes this seed draws, in `Shape` order.
	var shapes: [Shape] {
		var shapes = [Shape]()
		if configuredTypeUnderTwoParents != nil {
			shapes.append(.configuredTypeUnderTwoParents)
		}
		if unbuildableValueAtTwoPlaces != nil {
			shapes.append(.unbuildableValueAtTwoPlaces)
		}
		if twoClosersOfOneCycleTarget != nil {
			shapes.append(.twoClosersOfOneCycleTarget)
		}
		return shapes
	}

	// MARK: Sources

	/// The files the draw appends to a graph whose type names start with `prefix`, whose creation stamps count with
	/// `<prefix>CreationStamp` (a graph drawn storing every parameter).
	func swiftFileContent(prefix p: String) -> [String] {
		var files = [String]()
		if let share = configuredTypeUnderTwoParents {
			files.append(Self.type(
				"\(p)ZV3ShareHost",
				attribute: "@Instantiable(generateMock: true)",
				prefix: p,
				properties: [("zV3ShareLeft", "\(p)ZV3ShareLeft"), ("zV3ShareRight", "\(p)ZV3ShareRight")],
			))
			files.append(Self.type("\(p)ZV3ShareLeft", prefix: p, properties: [("zV3Shared", "\(p)ZV3Shared")]))
			switch share.rightPlace {
			case .byValue:
				files.append(Self.type("\(p)ZV3ShareRight", prefix: p, properties: [("zV3Shared", "\(p)ZV3Shared")]))
			case .instantiator:
				files.append(Self.type("\(p)ZV3ShareRight", prefix: p, properties: [("zV3SharedBuilder", "Instantiator<\(p)ZV3Shared>")]))
			case .deeper:
				files.append(Self.type("\(p)ZV3ShareRight", prefix: p, properties: [("zV3ShareMiddle", "\(p)ZV3ShareMiddle")]))
				files.append(Self.type("\(p)ZV3ShareMiddle", prefix: p, properties: [("zV3Shared", "\(p)ZV3Shared")]))
			}
			files.append(Self.type("\(p)ZV3Shared", prefix: p, properties: [("zV3ShareLeaf", "\(p)ZV3ShareLeaf")], tagDefault: 0))
			files.append(Self.type("\(p)ZV3ShareLeaf", prefix: p, properties: []))
		}
		if let gadget = unbuildableValueAtTwoPlaces {
			files.append("""
			public final class \(p)ZV3Gadget {
			\tlet differentialValueCreationStamp = \(p)CreationStamp.next()

			\tpublic init() {}
			}

			""")
			files.append(Self.type(
				"\(p)ZV3GadgetHost",
				attribute: "@Instantiable(generateMock: true)",
				prefix: p,
				properties: [("zV3GadgetLeft", "\(p)ZV3GadgetLeft"), ("zV3GadgetRight", "\(p)ZV3GadgetRight")],
			))
			files.append(Self.type("\(p)ZV3GadgetLeft", prefix: p, properties: [("zV3GadgetOwner", "\(p)ZV3GadgetOwner")]))
			files.append(Self.type(
				"\(p)ZV3GadgetRight",
				prefix: p,
				properties: [gadget.rightPlaceIsInstantiator ? ("zV3GadgetOwnerBuilder", "Instantiator<\(p)ZV3GadgetOwner>") : ("zV3GadgetOwner", "\(p)ZV3GadgetOwner")],
			))
			files.append(Self.type("\(p)ZV3GadgetOwner", prefix: p, properties: [("zV3Gadget", "\(p)ZV3Gadget")]))
		}
		if twoClosersOfOneCycleTarget != nil {
			files.append(Self.type(
				"\(p)ZV3LoopTarget",
				attribute: "@Instantiable(generateMock: true)",
				prefix: p,
				properties: [("zV3LoopA", "\(p)ZV3LoopA"), ("zV3LoopB", "\(p)ZV3LoopB")],
				tagDefault: 0,
			))
			files.append(Self.type("\(p)ZV3LoopA", prefix: p, properties: [("zV3LoopTargetBuilder", "Instantiator<\(p)ZV3LoopTarget>")]))
			files.append(Self.type("\(p)ZV3LoopB", prefix: p, properties: [("zV3LoopTargetBuilder", "Instantiator<\(p)ZV3LoopTarget>")]))
			files.append(loopKnownRightSource(prefix: p))
		}
		return files
	}

	/// A `final class` as the fuzzer writes one storing every parameter: a creation stamp, an initializer taking each
	/// property in order and then `tag` where it has a default, and each property `@Instantiated`.
	private static func type(_ name: String, attribute: String = "@Instantiable", prefix: String, properties: [(label: String, type: String)], tagDefault: Int? = nil) -> String {
		var parameters = properties.map { "\($0.label): \($0.type)" }
		var assignments = properties.map { "\t\tself.\($0.label) = \($0.label)" }
		if let tagDefault {
			parameters.append("tag: Int = \(tagDefault)")
			assignments.append("\t\tself.tag = tag")
		}
		var source = "\(attribute)\npublic final class \(name): Instantiable {\n"
		source += "\tlet differentialValueCreationStamp = \(prefix)CreationStamp.next()\n\n"
		source += "\tpublic init(\(parameters.joined(separator: ", "))) {\n"
		for assignment in assignments {
			source += assignment + "\n"
		}
		source += "\t}\n"
		for property in properties {
			source += "\n\t@Instantiated let \(property.label): \(property.type)"
		}
		if tagDefault != nil {
			source += "\n\tlet tag: Int"
		}
		source += "\n}\n"
		return source
	}

	/// The known-right build of `ZV3LoopTarget` under v3's rule for configurations: a hand-written model of the
	/// configurations the probe passes, and a function that builds the cycle from it, reading at each closer its own
	/// level's field or else the nearest configuration of its type on its path. The file declares no SafeDI marker, so
	/// the tool reads nothing of it.
	private func loopKnownRightSource(prefix p: String) -> String {
		"""
		// file: \(p)ZV3LoopKnownRight.swift

		enum \(p)ZV3LoopKnownRight {
		\tfinal class Target {
		\t\tinit(a: Closer? = nil, b: Closer? = nil, tag: Int? = nil) {
		\t\t\tself.a = a
		\t\t\tself.b = b
		\t\t\tself.tag = tag
		\t\t}

		\t\tlet a: Closer?
		\t\tlet b: Closer?
		\t\tlet tag: Int?
		\t}

		\tfinal class Closer {
		\t\tinit(target: Target? = nil) {
		\t\t\tself.target = target
		\t\t}

		\t\tlet target: Target?
		\t}

		\tstatic func build(_ configuration: Target, nearestA: Closer?, nearestB: Closer?) -> \(p)ZV3LoopTarget {
		\t\tlet aConfiguration = configuration.a ?? nearestA ?? Closer()
		\t\tlet bConfiguration = configuration.b ?? nearestB ?? Closer()
		\t\tlet zV3LoopA = \(p)ZV3LoopA(zV3LoopTargetBuilder: Instantiator<\(p)ZV3LoopTarget> {
		\t\t\tbuild(aConfiguration.target ?? configuration, nearestA: aConfiguration, nearestB: nearestB)
		\t\t})
		\t\tlet zV3LoopB = \(p)ZV3LoopB(zV3LoopTargetBuilder: Instantiator<\(p)ZV3LoopTarget> {
		\t\t\tbuild(bConfiguration.target ?? configuration, nearestA: nearestA, nearestB: bConfiguration)
		\t\t})
		\t\treturn \(p)ZV3LoopTarget(zV3LoopA: zV3LoopA, zV3LoopB: zV3LoopB, tag: configuration.tag ?? 0)
		\t}
		}

		"""
	}

	// MARK: Probes

	/// The probe pairs of the drawn shapes in a `.v3Unstable` path: each feature expression calls a generated mock with
	/// the drawn overrides, each known-right expression builds that tree by hand.
	func probePairs(prefix p: String) -> [DifferentialValueProbePair] {
		var pairs = [DifferentialValueProbePair]()
		if let share = configuredTypeUnderTwoParents {
			let leftTag = share.configuredPlaces == .rightOnly ? nil : 11
			let rightTag = share.configuredPlaces == .leftOnly ? nil : 22
			func sharedOverride(_ tag: Int?) -> String? {
				tag.map { ".init(tag: \($0))" }
			}
			var overrideArguments = [String]()
			if let left = sharedOverride(leftTag) {
				overrideArguments.append("zV3ShareLeft: .init(zV3Shared: \(left))")
			}
			if let right = sharedOverride(rightTag) {
				switch share.rightPlace {
				case .byValue:
					overrideArguments.append("zV3ShareRight: .init(zV3Shared: \(right))")
				case .instantiator:
					overrideArguments.append("zV3ShareRight: .init(zV3SharedBuilder: \(right))")
				case .deeper:
					overrideArguments.append("zV3ShareRight: .init(zV3ShareMiddle: .init(zV3Shared: \(right)))")
				}
			}
			func shared(_ tag: Int?) -> String {
				"\(p)ZV3Shared(zV3ShareLeaf: \(p)ZV3ShareLeaf(), tag: \(tag ?? 0))"
			}
			let right = switch share.rightPlace {
			case .byValue:
				"\(p)ZV3ShareRight(zV3Shared: \(shared(rightTag)))"
			case .instantiator:
				"\(p)ZV3ShareRight(zV3SharedBuilder: Instantiator<\(p)ZV3Shared> { \(shared(rightTag)) })"
			case .deeper:
				"\(p)ZV3ShareRight(zV3ShareMiddle: \(p)ZV3ShareMiddle(zV3Shared: \(shared(rightTag))))"
			}
			pairs.append(DifferentialValueProbePair(
				name: "\(p)ZV3ShareHost.mock(safeDIOverrides:) [\(share.rightPlace.rawValue), \(share.configuredPlaces.rawValue)]",
				featureExpression: "\(p)ZV3ShareHost.mock(safeDIOverrides: .init(\(overrideArguments.joined(separator: ", "))))",
				knownRightExpression: "\(p)ZV3ShareHost(zV3ShareLeft: \(p)ZV3ShareLeft(zV3Shared: \(shared(leftTag))), zV3ShareRight: \(right))",
			))
		}
		if let gadget = unbuildableValueAtTwoPlaces {
			let owner = "\(p)ZV3GadgetOwner(zV3Gadget: \(p)ZV3Gadget())"
			let right = gadget.rightPlaceIsInstantiator
				? "\(p)ZV3GadgetRight(zV3GadgetOwnerBuilder: Instantiator<\(p)ZV3GadgetOwner> { \(owner) })"
				: "\(p)ZV3GadgetRight(zV3GadgetOwner: \(owner))"
			pairs.append(DifferentialValueProbePair(
				name: "\(p)ZV3GadgetHost.mock(zV3Gadget: builder) [\(gadget.rightPlaceIsInstantiator ? "instantiator" : "byValue")]",
				featureExpression: "\(p)ZV3GadgetHost.mock(zV3Gadget: { \(p)ZV3Gadget() })",
				knownRightExpression: "\(p)ZV3GadgetHost(zV3GadgetLeft: \(p)ZV3GadgetLeft(zV3GadgetOwner: \(owner)), zV3GadgetRight: \(right))",
			))
		}
		if let loop = twoClosersOfOneCycleTarget {
			// The first closer's later pass: tag 2, and now and then a field for the second closer two levels down.
			let laterPassOverride = loop.laterPassConfiguresSecondCloser ? ".init(zV3LoopB: .init(zV3LoopTargetBuilder: .init(tag: 4)), tag: 2)" : ".init(tag: 2)"
			let laterPassModel = loop.laterPassConfiguresSecondCloser ? ".init(b: .init(target: .init(tag: 4)), tag: 2)" : ".init(tag: 2)"
			var overrideArguments = ["zV3LoopA: .init(zV3LoopTargetBuilder: \(laterPassOverride))"]
			var modelArguments = ["a: .init(target: \(laterPassModel))"]
			switch loop.secondCloser {
			case .unconfigured:
				break
			case .emptyLevel:
				overrideArguments.append("zV3LoopB: .init()")
				modelArguments.append("b: .init()")
			case .ownConfiguration:
				overrideArguments.append("zV3LoopB: .init(zV3LoopTargetBuilder: .init(tag: 3))")
				modelArguments.append("b: .init(target: .init(tag: 3))")
			}
			overrideArguments.append("tag: 1")
			modelArguments.append("tag: 1")
			pairs.append(DifferentialValueProbePair(
				name: "\(p)ZV3LoopTarget.mock(safeDIOverrides:) [\(loop.secondCloser.rawValue)\(loop.laterPassConfiguresSecondCloser ? ", laterPassConfiguresSecondCloser" : "")]",
				featureExpression: "\(p)ZV3LoopTarget.mock(safeDIOverrides: .init(\(overrideArguments.joined(separator: ", "))))",
				knownRightExpression: "\(p)ZV3LoopKnownRight.build(.init(\(modelArguments.joined(separator: ", "))), nearestA: nil, nearestB: nil)",
			))
		}
		return pairs
	}

	/// How many of `seeds` draw each shape, read from the draw alone, without the tool.
	static func drawnCounts(forSeeds seeds: some Sequence<UInt64>) -> [Shape: Int] {
		var counts = Dictionary(uniqueKeysWithValues: Shape.allCases.map { ($0, 0) })
		for seed in seeds {
			for shape in GraphFuzzerV3EngineDraw(seed: seed).shapes {
				counts[shape, default: 0] += 1
			}
		}
		return counts
	}
}

extension GraphFuzzerFixture {
	/// The graph with its v3 engine draws (`GraphFuzzerV3EngineDraw`) appended, as the API version agreement corpus draws it.
	var addingV3EngineShapes: GraphFuzzerFixture {
		let files = GraphFuzzerV3EngineDraw(seed: seed).swiftFileContent(prefix: typeNamePrefix)
		guard !files.isEmpty else { return self }
		return GraphFuzzerFixture(seed: seed, swiftFileContent: swiftFileContent + files)
	}
}

// MARK: - O3: layout parity

/// O3, layout parity: the type key must lay out the same mocks of a graph under `.v3Unstable` as under `.v2`. Each side's
/// tool run reports, per internal mock root, `laidOut` or why the root keeps the walk's body
/// (`MockLowering.typeKeyLayoutObserver`); the oracle fails a graph where a root's outcome differs between the two, or a
/// root reports under one version only. v3 prunes no cycle edge where `.v2` does, so a v3 root may in principle lay out
/// where `.v2` falls back: that difference is reported too, with its direction, so the step that makes it says so.
///
/// Hand mutation that must make it fire: force one `.v3Unstable` place's record to fall back (`v3FallsBackWhereV2LaysOut`).
enum GraphFuzzerV3LayoutParity {
	struct Difference: Equatable, Sendable, CustomStringConvertible {
		enum Kind: String, Sendable {
			case v3FallsBackWhereV2LaysOut
			case v3LaysOutWhereV2FallsBack
			case fallbackReasonsDiffer
			case mockReportedUnderOneVersionOnly
		}

		let kind: Kind
		let mockedType: String
		let v2Outcome: String?
		let v3Outcome: String?

		var description: String {
			"\(kind.rawValue): `\(mockedType).mock()` is \(v2Outcome ?? "not reported") under .v2 and \(v3Outcome ?? "not reported") under .v3Unstable"
		}
	}

	/// The layout outcome of each internal mock root the tool generates for `fixture`, by mocked type. A root reported
	/// twice keeps both outcomes, joined, so a run that lays one root out in two ways shows.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	static func layoutOutcomes(of fixture: GraphFuzzerFixture) async throws -> (outcomes: [String: String], toolAccepted: Bool) {
		let (stream, continuation) = AsyncStream<(String, String)>.makeStream()
		let toolOutcome = try await MockLowering.$typeKeyLayoutObserver.withValue({ mockedType, outcome in continuation.yield((mockedType, outcome)) }) {
			try await GraphFuzzerOracle.toolOutcome(of: fixture)
		}
		continuation.finish()
		var outcomes = [String: [String]]()
		for await (mockedType, outcome) in stream {
			outcomes[mockedType, default: []].append(outcome)
		}
		let accepted = switch toolOutcome {
		case .accepted: true
		case .rejected: false
		}
		return (outcomes.mapValues { $0.sorted().joined(separator: " | ") }, accepted)
	}

	/// The differences between `v2` and `v3`, each side's outcomes by mocked type, in mocked type order.
	static func differences(v2: [String: String], v3: [String: String]) -> [Difference] {
		let laidOut = "laidOut"
		return Set(v2.keys).union(v3.keys).sorted().compactMap { mockedType in
			let v2Outcome = v2[mockedType]
			let v3Outcome = v3[mockedType]
			guard let v2Outcome, let v3Outcome else {
				return Difference(kind: .mockReportedUnderOneVersionOnly, mockedType: mockedType, v2Outcome: v2Outcome, v3Outcome: v3Outcome)
			}
			guard v2Outcome != v3Outcome else { return nil }
			let kind: Difference.Kind = if v2Outcome == laidOut {
				.v3FallsBackWhereV2LaysOut
			} else if v3Outcome == laidOut {
				.v3LaysOutWhereV2FallsBack
			} else {
				.fallbackReasonsDiffer
			}
			return Difference(kind: kind, mockedType: mockedType, v2Outcome: v2Outcome, v3Outcome: v3Outcome)
		}
	}

	/// One seed's parity verdict: both sides run on the agreement corpus's fixture (`GraphFuzzerAPIVersionAgreement`), each
	/// with the type key on. `nil` outcomes where either side's tool rejects the graph, which O1 classes.
	struct SeedParity: Sendable {
		let seed: UInt64
		let judged: Bool
		let laidOutUnderV2: Int
		let laidOutUnderV3: Int
		let differences: [Difference]
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	static func parity(ofSeed seed: UInt64, in corpus: GraphFuzzerReleaseAcceptanceCorpus = .base) async throws -> SeedParity {
		let v2Fixture = GraphFuzzerAPIVersionAgreement.fixture(forSeed: seed, in: corpus)
		let v3Fixture = v2Fixture.selectingAPIVersion(.v3Unstable)
		let v2 = try await layoutOutcomes(of: v2Fixture)
		let v3 = try await layoutOutcomes(of: v3Fixture)
		guard v2.toolAccepted, v3.toolAccepted else {
			return SeedParity(seed: seed, judged: false, laidOutUnderV2: 0, laidOutUnderV3: 0, differences: [])
		}
		return SeedParity(
			seed: seed,
			judged: true,
			laidOutUnderV2: v2.outcomes.values.count { $0 == "laidOut" },
			laidOutUnderV3: v3.outcomes.values.count { $0 == "laidOut" },
			differences: differences(v2: v2.outcomes, v3: v3.outcomes),
		)
	}
}

// MARK: - The draws' configured probes

/// The v3 engine draws' configured probes, compared with the trees built by hand under the Manual's rule for v3 overrides
/// beside the agreement oracle's comparison with `.v2` (`GraphFuzzerAPIVersionAgreement`). They need neither side to be
/// right, so they judge the walk and the engine alike. Hand mutations that must make them fire: share two places whose
/// configurations differ (drop the per-type key check), which `configuredTypeUnderTwoParents`'s `both` probes see as the
/// right `ZV3Shared` holding the left's `tag`; make a closer pass `nearest` instead of `parent.field ?? nearest`, which
/// `twoClosersOfOneCycleTarget`'s later pass sees as `tag: 1` where `tag: 2` is due; and read a D12 builder once per
/// function, which `unbuildableValueAtTwoPlaces` sees as one `ZV3Gadget` where two are due.
enum GraphFuzzerV3DrawnProbes {
	/// The draws' own value graph of `seed`'s `.v3Unstable` generated files: each configured probe against the tree built
	/// by hand (`GraphFuzzerV3EngineDraw.probePairs(prefix:)`), or `nil` where the seed draws none.
	static func valueGraph(ofSeed seed: UInt64, v3Fixture: GraphFuzzerFixture, v3GeneratedFiles: [String: String]) -> DifferentialValueGraph? {
		let pairs = GraphFuzzerV3EngineDraw(seed: seed).probePairs(prefix: v3Fixture.typeNamePrefix)
		guard !pairs.isEmpty else { return nil }
		return DifferentialValueGraph(
			name: "seed \(seed) v3 draws",
			path: DifferentialValuePath(fixture: v3Fixture, generatedFiles: v3GeneratedFiles),
			probePairs: pairs,
		)
	}
}
