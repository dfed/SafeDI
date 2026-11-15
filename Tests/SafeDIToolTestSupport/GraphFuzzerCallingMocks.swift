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
/// the calling tree, or, for the controls, where nothing can fill it.
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
/// (`let api: any Api`) or a deferred one (an `ErasedInstantiator` whose fill forwards a value).
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
			expectedTwinErrorSite: expectedTwinErrorSite,
		)
	}

	let seed: UInt64
	let cell: GraphFuzzerCallingMockCell

	typealias Form = GraphFuzzerCallingMockGraph.Form

	/// The parameters of the calling mock's `mock()` that are values rather than builders: none of the draw's callers
	/// forwards a value, and the only received value a caller's tree cannot build is the second control's.
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
			value = random.element(of: ["Db", "Session", "Cache", "Logger"])
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

		let innerModuleName = "In"
		let outerModuleName = "Feat"
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

	/// The seam's module of the app-only screen's loop. A deferred place is the settings screen's builder, which forwards
	/// `id`; a plain place is the screen itself, which closes the loop through the feed's builder as a constant cycle.
	private var signedInModuleContent: String {
		let feedBuilder = "\(names.feed.lowercasedFirst)Builder"
		let feedBuilderType = "ErasedInstantiator<(), any \(names.feedPage)>"
		let settingsBuilder: String
		let settingsBuilderType: String
		let settingsAttribute: String
		switch cell.place {
		case .plain:
			settingsBuilder = names.settings.lowercasedFirst
			settingsBuilderType = "any \(names.settingsPage)"
			settingsAttribute = "@Instantiated"
		case .deferred:
			settingsBuilder = "\(names.settings.lowercasedFirst)Builder"
			settingsBuilderType = "ErasedInstantiator<Int, any \(names.settingsPage)>"
			settingsAttribute = "@Instantiated(fulfilledByType: \"\(names.settings)\")"
		}
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
			@Instantiable(fulfillingAdditionalTypes: [(any \(names.settingsPage)).self])
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
	/// `mockFiles` with the caller's `@Instantiable(generateMock: …)` line replaced by
	/// `@Instantiable(generateDependencyTree: true)`, so every line keeps its number.
	let twinFiles: [File]
	let callerTypeName: String
	let callerIsPublic: Bool
	/// The parameters of the calling mock's `mock()` that its own `@Forwarded` values and the received values its tree
	/// cannot build account for: every other parameter but `safeDIOverrides` is a place it passes up.
	let flatParameterLabels: Set<String>
	/// Whether a type that fulfills the hole is visible from the calling mock's module.
	let implementationIsVisible: Bool
	/// Where production reports the graph's shape error, as the module's file and the declaration's line, or `nil` when
	/// production accepts the graph.
	let expectedTwinErrorSite: (file: String, declaration: String)?

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
		expectedTwinErrorSite: (file: String, declaration: String)?,
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
			expectedTwinErrorSite: expectedTwinErrorSite,
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
		expectedTwinErrorSite: (file: String, declaration: String)?,
	) {
		self.name = name
		self.mockFiles = mockFiles
		self.twinFiles = twinFiles
		self.callerTypeName = callerTypeName
		self.callerIsPublic = callerIsPublic
		self.flatParameterLabels = flatParameterLabels
		self.implementationIsVisible = implementationIsVisible
		self.expectedTwinErrorSite = expectedTwinErrorSite
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
	/// Each place the accepted calling mock passes up, by its parameter's label, with its reason or `nil` when no reason
	/// explains it.
	let passUps: [(label: String, reason: GraphFuzzerCallingMockPassUpReason?)]
	/// Why the twin's outcome is not the one the graph is drawn for – a drawing defect, never a mirroring requirement – or
	/// `nil`.
	let drawingDefect: String?
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
	/// reason.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	static func run(_ graph: GraphFuzzerCallingMockGraph, seed: UInt64) async throws -> GraphFuzzerCallingMockResult {
		let twin = try await toolRun(of: graph, .twin)
		let mock = try await toolRun(of: graph, .mock)
		let twinSites = twin.diagnostics.map { GraphFuzzerDiagnosticSite.sites(inDiagnostics: $0, contentByRelativePath: graph.contentByRelativePath(.twin)) }
		let mockSites = mock.diagnostics.map { GraphFuzzerDiagnosticSite.sites(inDiagnostics: $0, contentByRelativePath: graph.contentByRelativePath(.mock)) }
		let drawingDefect: String? = if let expected = graph.expectedTwinErrorSite {
			if let first = twinSites?.first, first.severity == "error", first.file == expected.file, first.declaration == expected.declaration {
				nil
			} else {
				"the twin of \(graph.name) does not report its shape's error at \(expected.file) `\(expected.declaration)`: \(twin.diagnostics ?? "it is accepted")"
			}
		} else if let diagnostics = twin.diagnostics {
			"the twin of \(graph.name) is rejected where the graph is drawn for production to accept it: \(diagnostics)"
		} else {
			nil
		}
		let passUps = mock.generatedCallerFile.map { passUpsOf(graph, inGeneratedFile: $0) } ?? []
		let failure: GraphFuzzerFailure? = if let twinSites {
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
		} else {
			nil
		}
		return GraphFuzzerCallingMockResult(
			twinSites: twinSites,
			mockSites: mockSites,
			twinDiagnostics: twin.diagnostics,
			passUps: passUps,
			drawingDefect: drawingDefect,
			failure: failure,
		)
	}

	/// Each parameter of the caller's `mock()` that is neither `safeDIOverrides` nor one of the graph's flat parameters: a
	/// place the mock passes up, classified by the graph's facts. Each graph has one hole type, so every pass-up is a place
	/// of it.
	static func passUpsOf(_ graph: GraphFuzzerCallingMockGraph, inGeneratedFile generatedFile: String) -> [(label: String, reason: GraphFuzzerCallingMockPassUpReason?)] {
		let labels = mockParameterLabels(ofType: graph.callerTypeName, inGeneratedFile: generatedFile)
		let reason: GraphFuzzerCallingMockPassUpReason? = graph.implementationIsVisible ? nil : .noVisibleImplementation
		return labels
			.filter { $0 != "safeDIOverrides" && !graph.flatParameterLabels.contains($0) }
			.map { ($0, reason) }
	}

	/// The labels of the parameters of every `mock(…)` an extension of `typeName` declares in `generatedFile`, each once, in
	/// order.
	static func mockParameterLabels(ofType typeName: String, inGeneratedFile generatedFile: String) -> [String] {
		let visitor = MockParameterLabelVisitor(typeName: typeName)
		visitor.walk(Parser.parse(source: generatedFile))
		var labels = [String]()
		for label in visitor.labels where !labels.contains(label) {
			labels.append(label)
		}
		return labels
	}

	private final class MockParameterLabelVisitor: SyntaxVisitor {
		init(typeName: String) {
			self.typeName = typeName
			super.init(viewMode: .sourceAccurate)
		}

		let typeName: String
		var labels = [String]()

		override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
			guard node.name.text == "mock", isInExtensionOfType(node) else { return .skipChildren }
			labels += node.signature.parameterClause.parameters.map(\.firstName.text)
			return .skipChildren
		}

		private func isInExtensionOfType(_ node: some SyntaxProtocol) -> Bool {
			var parent = node.parent
			while let ancestor = parent {
				if let extensionDeclaration = ancestor.as(ExtensionDeclSyntax.self) {
					return extensionDeclaration.extendedType.trimmedDescription == typeName
				}
				parent = ancestor.parent
			}
			return false
		}
	}

	/// One form's run: the tool's diagnostics when it rejects the graph, else the calling mock's module's generated file.
	private struct ToolRun {
		let diagnostics: String?
		let generatedCallerFile: String?
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
			return ToolRun(diagnostics: nil, generatedCallerFile: output.modules[graph.callerModule]?.generatedFiles["\(graph.callerModule).swift"])
		} catch let error as SafeDIToolMultiModuleTestError {
			return ToolRun(diagnostics: "\(error.underlyingError)", generatedCallerFile: nil)
		}
	}
}

// MARK: - The public mock corpus's calling mocks

/// What the production twins of the public mock corpus's calling mocks report: each mocked consumer of a graph the tool
/// accepts (`FuzzApp`'s and `FuzzOther`'s types with a generated mock), run as its twin, one at a time. Only reports: the
/// rule for mirrored rejections is applied to its count by hand before the mock work lands.
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
