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
@testable import SafeDIToolLibrary

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

	static func < (lhs: Self, rhs: Self) -> Bool {
		allCases.firstIndex(of: lhs) ?? 0 < allCases.firstIndex(of: rhs) ?? 0
	}

	/// Whether production rejects the shape with an error of its own, which the calling mock must report too.
	var twinRejects: Bool {
		switch self {
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder:
			true
		case .callersOwnValue, .noVisibleImplementation, .implementationReceivesWhatNothingProvides:
			false
		}
	}

	var isControl: Bool {
		switch self {
		case .noVisibleImplementation:
			true
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .implementationReceivesWhatNothingProvides:
			false
		}
	}
}

/// One cell of the calling-mock draw: a shape, with an internal or a `.public` calling mock, and a plain place
/// (`let api: any Api`) or a deferred one (an `ErasedInstantiator` whose fill forwards a value). The app-only screen's
/// loop closes only through builders, so there its plain place is the canonical one, a builder that forwards nothing
/// (`ErasedInstantiator<(), any SettingsPage>`).
struct GraphFuzzerCallingMockCell: Hashable, Comparable, CustomStringConvertible {
	enum Place: String, CaseIterable {
		case plain
		/// An `ErasedInstantiator<Int, any P>`: the forwarded variant of a deferred place, whose fill forwards `id: Int`.
		case deferred
	}

	let shape: GraphFuzzerCallingMockShape
	let callerIsPublic: Bool
	let place: Place

	static func < (lhs: Self, rhs: Self) -> Bool {
		(lhs.shape, lhs.callerIsPublic ? 1 : 0, lhs.place.rawValue) < (rhs.shape, rhs.callerIsPublic ? 1 : 0, rhs.place.rawValue)
	}

	var description: String {
		"\(shape.rawValue)/\(callerIsPublic ? "public" : "internal")/\(place.rawValue)"
	}

	/// Every cell, shape by shape.
	static let all: [Self] = GraphFuzzerCallingMockShape.allCases.flatMap { shape in
		[false, true].flatMap { callerIsPublic in
			Place.allCases.map { Self(shape: shape, callerIsPublic: callerIsPublic, place: $0) }
		}
	}

	/// The cells the draw fills, in order: a seed's cell is `drawnCells[seed % drawnCells.count]`.
	static let drawnCells = all
}

// MARK: - Draw

/// A calling-mock graph: its modules as the calling mock's module declares the caller with `generateMock:` and as its
/// production twin declares it with `generateDependencyTree: true` in its place, and the draw's facts that classify what
/// the calling mock passes up. Drawn from a stream of its own, so no other corpus graph changes.
struct GraphFuzzerCallingMockDraw {
	init(seed: UInt64) {
		self.init(seed: seed, cell: GraphFuzzerCallingMockCell.drawnCells[Int(seed % UInt64(GraphFuzzerCallingMockCell.drawnCells.count))])
	}

	init(seed: UInt64, cell: GraphFuzzerCallingMockCell) {
		self.seed = seed
		self.cell = cell
		var random = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.callingMockRandomSeedMask)
		names = Names(random: &random)
		tickerPosition = random.element(of: TickerPosition.allCases)
	}

	static let callingMockRandomSeedMask: UInt64 = 0x63616C6C6D6F636B

	/// The graph the check judges.
	var graph: GraphFuzzerCallingMockGraph {
		GraphFuzzerCallingMockGraph(
			name: "seed \(seed) (\(cell))",
			mockFiles: files(.mock),
			twinFiles: files(.twin),
			callerTypeName: names.caller,
			callerIsPublic: cell.callerIsPublic,
			flatParameterLabels: flatParameterLabels,
			implementationIsVisible: implementationIsVisible,
			expectedTwinInitializerLabels: expectedTwinInitializerLabels,
			expectedPassUpLabels: expectedPassUpLabels,
			expectedTwinErrorSite: expectedTwinErrorSite,
			valueProbes: valueProbes,
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
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .callersOwnValue, .noVisibleImplementation:
			[]
		}
	}

	/// Whether a type that fulfills the hole is visible from the calling mock's module.
	var implementationIsVisible: Bool {
		cell.shape != .noVisibleImplementation
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
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder:
			nil
		case .callersOwnValue:
			[]
		case .implementationReceivesWhatNothingProvides:
			[names.token.lowercasedFirst]
		case .noVisibleImplementation:
			[holeBuilderLabel]
		}
	}

	/// The places the calling mock may pass up: the hole's builder where its module sees no type that fulfills the hole.
	var expectedPassUpLabels: [String] {
		implementationIsVisible ? [] : [holeBuilderLabel]
	}

	/// What the calling mock and its twin build where the mock fills the place: a probe calling the mock and the twin's seam
	/// initializer, or, for a deferred place, one describing that value and what the place's builder builds for `id` 7 as a
	/// tuple (`callerAndFill(of:place:)`), since the comparator calls no `ErasedInstantiator` and numbers identities per
	/// probe. `nil` where the twin rejects the graph or the mock passes the place up.
	var valueProbes: [DifferentialValueProbe]? {
		// Qualified by its module: Foundation, which the probe executable imports, declares `Host` on macOS.
		let caller = "\(names.callerModuleName).\(names.caller)"
		let token = names.token.lowercasedFirst
		let calls: (mock: String, twin: String)? = switch cell.shape {
		case .callersOwnValue:
			("\(caller).mock()", "\(caller)()")
		case .implementationReceivesWhatNothingProvides:
			("\(caller).mock(\(token): \(names.token)())", "\(caller)(__safeDI_\(token): \(names.token)())")
		case .outerSeamValue, .appOnlyScreenInLoop, .seamBuiltAgain, .loopThroughInnerSeamBuilder, .noVisibleImplementation:
			nil
		}
		guard let calls else { return nil }
		let (mockCall, twinCall) = calls
		switch cell.place {
		case .plain:
			return [DifferentialValueProbe(name: caller, expression: mockCall, knownRightExpression: twinCall)]
		case .deferred:
			let place = "\(names.inner.lowercasedFirst).\(holePlace(protocolName: names.hole, fillName: names.fill).label)"
			return [DifferentialValueProbe(
				name: "(\(caller), \(caller).\(place).instantiate(7))",
				expression: Self.callerAndFill(of: mockCall, place: place),
				knownRightExpression: Self.callerAndFill(of: twinCall, place: place),
			)]
		}
	}

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
		case .callersOwnValue, .noVisibleImplementation, .implementationReceivesWhatNothingProvides:
			return nil
		}
	}

	typealias File = GraphFuzzerCallingMockGraph.File

	/// The draw's files, in dependency order, with each file's content by module and file name.
	func files(_ form: Form) -> [File] {
		switch cell.shape {
		case .outerSeamValue, .loopThroughInnerSeamBuilder, .callersOwnValue, .noVisibleImplementation, .implementationReceivesWhatNothingProvides:
			[
				File(module: names.innerModuleName, dependencies: [], content: innerModuleContent),
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

	// MARK: Content

	private var callerIsPublic: Bool {
		cell.callerIsPublic
	}

	/// What a public caller's declarations spell before `final class` and `init`.
	private var callerAccess: String {
		callerIsPublic ? "public " : ""
	}

	private func callerAttribute(_ form: Form) -> String {
		switch form {
		case .mock:
			callerIsPublic ? "@Instantiable(generateMock: .public)" : "@Instantiable(generateMock: true)"
		case .twin:
			"@Instantiable(generateDependencyTree: true)"
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

	private var innerModuleContent: String {
		let place = holePlace(protocolName: names.hole, fillName: names.fill)
		return """
		import SafeDI

		public protocol \(names.hole): AnyObject {}

		@Instantiable(generateDependencyTree: true, generateMock: .public)
		public final class \(names.inner): Instantiable {
		    init(\(place.label): \(place.type)) { self.\(place.label) = \(place.label) }
		    \(place.attribute) public let \(place.label): \(place.type)
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
		case .outerSeamValue, .callersOwnValue, .noVisibleImplementation, .implementationReceivesWhatNothingProvides, .appOnlyScreenInLoop, .seamBuiltAgain:
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

	/// The fill's declaration, receiving `received` (a label and type) when given, forwarding `id: Int` for a deferred
	/// place, and fulfilling `protocolName` by name or through `fulfillingAdditionalTypes`.
	private func fillDeclaration(named fillName: String, protocolName: String, received: (label: String, type: String)?, isPublic: Bool) -> String {
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
		case .noVisibleImplementation:
			declarations.append(callerDeclaration(form, properties: [(names.value.lowercasedFirst, names.value), (names.inner.lowercasedFirst, names.inner)]))
		case .implementationReceivesWhatNothingProvides:
			declarations.append("public struct \(names.token) {}")
			declarations.append(fillDeclaration(named: names.fill, protocolName: names.hole, received: (names.token.lowercasedFirst, names.token), isPublic: callerIsPublic))
			declarations.append(callerDeclaration(form, properties: [(names.value.lowercasedFirst, names.value), (names.inner.lowercasedFirst, names.inner)]))
		case .appOnlyScreenInLoop, .seamBuiltAgain:
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

	let name: String
	/// The modules' files in dependency order, the calling mock's module last.
	let mockFiles: [File]
	/// `mockFiles` with every `@Instantiable(generateMock: …)` of the last file, the caller's module, replaced by
	/// `@Instantiable(generateDependencyTree: true)`, so every line keeps its number.
	let twinFiles: [File]
	let callerTypeName: String
	let callerIsPublic: Bool
	/// The parameters of the calling mock's `mock()` that its own `@Forwarded` values and the received values its tree
	/// cannot build account for: every other parameter but `safeDIOverrides` is a place it passes up.
	let flatParameterLabels: Set<String>
	/// Whether a type that fulfills the hole is visible from the calling mock's module.
	let implementationIsVisible: Bool
	/// The parameters of the twin's seam initializers, without the `__safeDI_` prefix of the one only generated code
	/// calls, in order, or `nil` when the graph does not state them: what production takes where it is accepted, which the
	/// check reads to see that production fills what the graph is drawn for it to fill.
	let expectedTwinInitializerLabels: [String]?
	/// The places the calling mock may pass up because its module sees no type that fulfills the place's type: the only
	/// labels the check classifies.
	let expectedPassUpLabels: [String]
	/// Where production reports the graph's shape error, as the module's file and the declaration's line, or `nil` when
	/// production accepts the graph.
	let expectedTwinErrorSite: (file: String, declaration: String)?
	/// What the differential value comparator describes where both forms are accepted and the mock passes up no place
	/// without a reason: each probe's expression calls the calling mock, and its known-right expression the twin's seam
	/// initializer. `nil` when the graph states none.
	let valueProbes: [DifferentialValueProbe]?

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
			ModuleFixture(
				name: file.module,
				packageName: Self.packageName,
				swiftFileContentByFilePath: [file.fileName: file.content],
				dependencies: file.dependencies,
			)
		}
	}

	func contentByRelativePath(_ form: Form) -> [String: String] {
		var contentByRelativePath = [String: String]()
		for file in files(form) {
			contentByRelativePath[file.relativePath] = file.content
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
		flatParameterLabels: Set<String> = [],
		implementationIsVisible: Bool = true,
		expectedTwinInitializerLabels: [String]? = nil,
		expectedPassUpLabels: [String] = [],
		expectedTwinErrorSite: (file: String, declaration: String)?,
		valueProbes: [DifferentialValueProbe]? = nil,
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
			flatParameterLabels: flatParameterLabels,
			implementationIsVisible: implementationIsVisible,
			expectedTwinInitializerLabels: expectedTwinInitializerLabels,
			expectedPassUpLabels: expectedPassUpLabels,
			expectedTwinErrorSite: expectedTwinErrorSite,
			valueProbes: valueProbes,
		)
	}

	init(
		name: String,
		mockFiles: [File],
		twinFiles: [File],
		callerTypeName: String,
		callerIsPublic: Bool,
		flatParameterLabels: Set<String>,
		implementationIsVisible: Bool,
		expectedTwinInitializerLabels: [String]?,
		expectedPassUpLabels: [String],
		expectedTwinErrorSite: (file: String, declaration: String)?,
		valueProbes: [DifferentialValueProbe]? = nil,
	) {
		self.name = name
		self.mockFiles = mockFiles
		self.twinFiles = twinFiles
		self.callerTypeName = callerTypeName
		self.callerIsPublic = callerIsPublic
		self.flatParameterLabels = flatParameterLabels
		self.implementationIsVisible = implementationIsVisible
		self.expectedTwinInitializerLabels = expectedTwinInitializerLabels
		self.expectedPassUpLabels = expectedPassUpLabels
		self.expectedTwinErrorSite = expectedTwinErrorSite
		self.valueProbes = valueProbes
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
/// production fills that place from a parameter.
enum GraphFuzzerCallingMockPassUpReason: String, CaseIterable, Comparable {
	/// No type that fulfills the place's type is visible from the mock's module.
	case noVisibleImplementation

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
	/// builds (`valueFailure`).
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
		let mirroringFailure: GraphFuzzerFailure? = if let twinSites {
			if let mockSites {
				mockSites == twinSites ? nil : GraphFuzzerFailure(
					seed: seed,
					kind: .callingMockReportsOtherErrorThanTwin,
					details: "\(graph.name): the twin reports \(twinSites), the calling mock \(mockSites)",
				)
			} else {
				GraphFuzzerFailure(
					seed: seed,
					kind: .callingMockAcceptedWhereTwinReportsShapeError,
					details: "\(graph.name): the calling mock is accepted where the twin reports \(twinSites)",
				)
			}
		} else if let mockDiagnostics = mock.diagnostics {
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
		let valueJudgment: (compared: Bool, failure: GraphFuzzerFailure?) = if mirroringFailure == nil, drawingDefect == nil, comparesValues, let probes = graph.valueProbes, let feature = mock.valuePath, let knownRight = twin.valuePath {
			try await valueFailure(of: graph, seed: seed, feature: feature, knownRight: knownRight, probes: probes)
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

	/// Compiles the calling mock's path, `feature`, and its twin's, `knownRight`, with the differential value comparator,
	/// and compares what `probes` build in each: a mock that does not compile, that traps or does not finish when its probe
	/// runs, or that builds other values, fails. Returns whether the values were compared, which they are not when compile
	/// verification is off. Any other failure of the comparator, such as a twin that does not compile or run, or a probe
	/// that names no declaration, is the harness's and throws.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	static func valueFailure(
		of graph: GraphFuzzerCallingMockGraph,
		seed: UInt64,
		feature: DifferentialValuePath,
		knownRight: DifferentialValuePath,
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
				kind: .callingMockBuildsOtherValuesThanTwin,
				details: "\(graph.name): the calling mock builds other values than its twin at \(comparison.differences.map(\.description).joined(separator: "\n"))\n\(comparison.report)",
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
				(label, !graph.implementationIsVisible && graph.expectedPassUpLabels.contains(label) ? .noVisibleImplementation : nil)
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

		/// Whether `node` is a member of an extension of the type itself, not of a type nested in one, such as a builder struct
		/// a seam's enum declares, whose initializers no caller of the seam calls.
		private func isInExtensionOfType(_ node: some SyntaxProtocol) -> Bool {
			var parent = node.parent
			while let ancestor = parent {
				if let extensionDeclaration = ancestor.as(ExtensionDeclSyntax.self) {
					return extensionDeclaration.extendedType.trimmedDescription == typeName
				} else if ancestor.is(StructDeclSyntax.self) || ancestor.is(EnumDeclSyntax.self) || ancestor.is(ClassDeclSyntax.self) || ancestor.is(ActorDeclSyntax.self) {
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
		(.seamBuiltAgain, "again, but that call passes the builder"),
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
