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
import Testing

// MARK: - Random number generator

/// SplitMix64: a small pseudo-random generator whose output depends only on its seed, so a seed reproduces a
/// graph exactly on any machine, platform, and Swift version. It deliberately does not conform to
/// `RandomNumberGenerator`, so the standard library's range-reduction algorithms, which may change between
/// releases, never shape a graph.
struct GraphFuzzerRandomNumberGenerator {
	init(seed: UInt64) {
		state = seed
	}

	mutating func next() -> UInt64 {
		state &+= 0x9E3779B97F4A7C15
		var value = state
		value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
		value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
		return value ^ (value >> 31)
	}

	/// An integer in `range`. The modulo bias is irrelevant at these range sizes, and keeps the reduction trivially portable.
	mutating func integer(in range: ClosedRange<Int>) -> Int {
		let count = UInt64(range.upperBound - range.lowerBound + 1)
		return range.lowerBound + Int(next() % count)
	}

	/// `true` with a probability of `percent` out of 100.
	mutating func percentChance(_ percent: Int) -> Bool {
		integer(in: 0...99) < percent
	}

	mutating func element<Element>(of elements: [Element]) -> Element {
		elements[integer(in: 0...(elements.count - 1))]
	}

	private var state: UInt64
}

// MARK: - Fixture generation

/// A randomly generated, macro-valid SafeDI module: one Swift file per `@Instantiable` type.
struct GraphFuzzerFixture: Equatable {
	let seed: UInt64
	/// The contents of each file, in declaration order. Every type name begins with `typeNamePrefix`, so the
	/// fixtures of several seeds compile together as one module.
	let swiftFileContent: [String]

	var typeNamePrefix: String {
		Self.typeNamePrefix(forSeed: seed)
	}

	/// The names of the files `executeSafeDIToolTest` writes for `swiftFileContent`, which it names after the
	/// `@Instantiable` type each declares.
	var fileNames: [String] {
		swiftFileContent.compactMap { content in
			Self.markedFileName(in: content)
				?? GraphFuzzerSourceLine.lines(of: content).lazy.compactMap(\.declaredTypeName).first.map { "\($0).swift" }
		}
	}

	/// What precedes a file's name on one of its first lines, for a file whose name is not its first `@Instantiable`
	/// type's: one that declares none, or a `SafeDIConfiguration.swift`, which `GraphFuzzerPublicMockDraw` places in a
	/// directory of its own so that a renaming that prefixes file names keeps the name the tool reads it by.
	static let fileNameMarker = "// file: "

	/// The name `content` gives itself on one of its first lines (`fileNameMarker`), if it does.
	private static func markedFileName(in content: String) -> String? {
		content.split(separator: "\n").prefix(2).first { $0.hasPrefix(fileNameMarker) }.map { String($0.dropFirst(fileNameMarker.count)) }
	}

	var description: String {
		swiftFileContent.joined(separator: "\n")
	}

	/// The module of each file, in `swiftFileContent`'s order, when the graph is split across modules: the module its
	/// first line names (`GraphFuzzerModule.marker`), every other file belonging to `GraphFuzzerModule.samePackageCaller`.
	/// `nil` for a graph in one module.
	var modules: [GraphFuzzerModule]? {
		guard swiftFileContent.contains(where: { GraphFuzzerModule(declaredIn: $0) != nil }) else { return nil }
		return swiftFileContent.map { GraphFuzzerModule(declaredIn: $0) ?? .samePackageCaller }
	}

	/// The modules of a split graph the tool runs over without their package's name, which their files' first lines say.
	var modulesOmittingPackageName: Set<GraphFuzzerModule> {
		Set(swiftFileContent.filter(GraphFuzzerModule.omitsPackageName(declaredIn:)).compactMap(GraphFuzzerModule.init(declaredIn:)))
	}

	static func typeNamePrefix(forSeed seed: UInt64) -> String {
		"S\(seed)_"
	}

	/// The name of each type declared as a seam: the type an `@Instantiable(generateDependencyTree: true…)`
	/// attribute decorates.
	var seamTypeNames: [String] {
		swiftFileContent.flatMap { content -> [String] in
			let lines = GraphFuzzerSourceLine.lines(of: content)
			return zip(lines, lines.dropFirst()).compactMap { line, nextLine in
				guard case let .instantiableAttribute(arguments) = line, arguments.contains("generateDependencyTree: true") else { return nil }
				return nextLine.declaredTypeName
			}
		}
	}

	/// The access level each seam's declaration spells, by the seam's name: `public`, `package` or `internal`.
	var seamTypeAccess: [String: String] {
		var accessByName = [String: String]()
		for content in swiftFileContent {
			var nextTypeIsSeam = false
			for rawLine in content.split(separator: "\n") {
				let line = rawLine.trimmingCharacters(in: .whitespaces)
				if line.hasPrefix("@Instantiable") {
					nextTypeIsSeam = line.contains("generateDependencyTree: true")
				} else if nextTypeIsSeam, let classRange = line.range(of: "final class ") {
					let access = ["public", "package"].first { line.hasPrefix($0 + " ") } ?? "internal"
					accessByName[String(line[classRange.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" })] = access
					nextTypeIsSeam = false
				} else {
					nextTypeIsSeam = false
				}
			}
		}
		return accessByName
	}

	/// Whether a type of the graph is declared as a seam.
	var declaresSeam: Bool {
		swiftFileContent.contains { $0.contains("generateDependencyTree: true") }
	}

	/// Whether the graph declares a type that fills a hole of a seam whose module cannot see it (`addingHoleShapes`).
	var drawsHole: Bool {
		swiftFileContent.contains(where: GraphFuzzerModule.fillsHole(declaredIn:))
	}

	/// The visible build of a graph with a hole: every file whose first line says it fills a hole declared in the seam's
	/// module instead, which can then see the fulfilling type and builds it inline, so the seam takes no builder.
	var withoutHoles: GraphFuzzerFixture {
		let seamModuleHeader = GraphFuzzerModule.seamModule.fileHeader(omitsPackageName: modulesOmittingPackageName.contains(.seamModule))
		return GraphFuzzerFixture(
			seed: seed,
			swiftFileContent: swiftFileContent.map { content in
				guard GraphFuzzerModule.fillsHole(declaredIn: content), let headerEnd = content.range(of: "\n\n") else { return content }
				return seamModuleHeader + content[headerEnd.upperBound...]
			},
		)
	}

	/// The same graph with no type declared as a seam, so every tree is built inline: what SafeDI accepted before
	/// seams existed, which a seam's own errors may reject.
	var withoutSeams: GraphFuzzerFixture {
		GraphFuzzerFixture(
			seed: seed,
			swiftFileContent: swiftFileContent.map {
				$0.replacingOccurrences(of: "@Instantiable(generateDependencyTree: true, ", with: "@Instantiable(")
					.replacingOccurrences(of: "@Instantiable(generateDependencyTree: true)", with: "@Instantiable")
			},
		)
	}

	/// The same graph renamed by `renaming`, with its files listed in reverse order. A tool whose output depends
	/// only on what a graph declares gives the renamed graph the output it gives this one, renamed.
	func renamed(by renaming: GraphFuzzerRenaming) -> GraphFuzzerFixture {
		GraphFuzzerFixture(
			seed: seed,
			swiftFileContent: swiftFileContent.reversed().map { renaming.rename($0, typeNamePrefix: typeNamePrefix) },
		)
	}
}

/// A module of a graph split across modules. Every split graph uses the same module names and packages, so the modules
/// of one role of many graphs compile as one module, kept apart by the per-seed type-name prefix: the seam's module
/// in package `shop`, a caller in the same package that holds the rest of the graph, and a caller in package `other`.
/// A file names its module on its first line, as `// module: <name>`, so every renaming and `withoutSeams` keep it.
enum GraphFuzzerModule: String, CaseIterable, Comparable {
	case seamModule = "FuzzFeature"
	case samePackageCaller = "FuzzApp"
	case otherPackageCaller = "FuzzOther"

	init?(declaredIn content: String) {
		guard content.hasPrefix(Self.marker) else { return nil }
		self.init(rawValue: String(content.dropFirst(Self.marker.count).prefix { $0 != "\n" && $0 != "," }))
	}

	static let marker = "// module: "

	/// What follows the module's name on a file's first line when the tool runs over the module without its package's
	/// name, as Bazel without `package_name` and Tuist without `SWIFT_PACKAGE_NAME` do; the compiler still gets it.
	static let packageNameOmittedMarker = ", run without its package name"

	/// Whether `content`'s first line names its module and says the tool runs over it without its package's name.
	static func omitsPackageName(declaredIn content: String) -> Bool {
		content.hasPrefix(marker) && content.prefix { $0 != "\n" }.contains(packageNameOmittedMarker)
	}

	/// What follows the module's name, and any `packageNameOmittedMarker`, on the first line of a file declaring a type
	/// that fills a hole of a seam whose module cannot see it, or that such a type instantiates, which the visible build
	/// (`GraphFuzzerFixture.withoutHoles`) declares in the seam's module.
	static let holeFulfillerMarker = ", fills a hole"

	/// Whether `content`'s first line says its file declares a type that fills a hole.
	static func fillsHole(declaredIn content: String) -> Bool {
		content.hasPrefix(marker) && content.prefix { $0 != "\n" }.hasSuffix(holeFulfillerMarker)
	}

	var name: String {
		rawValue
	}

	var packageName: String {
		switch self {
		case .seamModule, .samePackageCaller:
			"shop"
		case .otherPackageCaller:
			"other"
		}
	}

	/// The modules this one imports: a caller imports the seam's module.
	var dependencies: [GraphFuzzerModule] {
		switch self {
		case .seamModule:
			[]
		case .samePackageCaller, .otherPackageCaller:
			[.seamModule]
		}
	}

	/// The order the modules are run and compiled in: dependencies first.
	static func < (lhs: GraphFuzzerModule, rhs: GraphFuzzerModule) -> Bool {
		lhs.order < rhs.order
	}

	private var order: Int {
		switch self {
		case .seamModule:
			0
		case .samePackageCaller:
			1
		case .otherPackageCaller:
			2
		}
	}

	/// The first lines of a file of this module: the marker, and the import of each module it depends on.
	func fileHeader(omitsPackageName: Bool, fillsHole: Bool = false) -> String {
		([Self.marker + name + (omitsPackageName ? Self.packageNameOmittedMarker : "") + (fillsHole ? Self.holeFulfillerMarker : "")] + dependencies.map { "import \($0.name)" }).joined(separator: "\n") + "\n\n"
	}
}

/// A renaming of a graph that changes no declaration's meaning but changes an order SafeDI could depend on: the order
/// of its type names, of its property labels, of its file names, or all three at once, or where its type names sort
/// among the names of the wrappers SafeDI provides. The rename-invariance oracle runs each graph under every renaming
/// and requires the same results once the renaming is undone: the same verdict, the same diagnostics in any order
/// (each list of suggestions in a diagnostic in any order, too), and byte-identical generated files.
///
/// Type names `<prefix>T<i>`, `<prefix>AnyT<i>`, `<prefix>Root<i>`, and `<prefix>Missing<i>` – with any suffix, such
/// as `Protocol` – and labels `t<i>`, `anyT<i>`, `lazyT<i>`, `lazyAnyT<i>`, and `missing<i>` – with any suffix, such
/// as `Builder` – are renamed by replacing index `i` with `9 - i`, wherever they appear, including inside generated
/// names that embed them. Every index the generator writes is a single digit, so each name keeps its length and
/// every other character, the names of each kind sort in reverse order, and no renamed name becomes another's
/// prefix. Both maps are their own inverse. File order is reversed by naming each file `F<99 - rank>_<name>`.
///
/// Every type name begins with the prefix `S<seed>_`, and reversing indices keeps it, so the reversals alone always
/// sort a type's name after `ErasedInstantiator<`, `Instantiator<`, and `LazilyInstantiated<`, and before
/// `SendableErasedInstantiator<`, `SendableInstantiator<`, and `SendableLazilyInstantiated<` (a digit sorts before
/// `e`): no reversal changes whether `x: X` or `x: Instantiator<X>` sorts first. Moving type names across wrapper
/// names replaces the prefix's `S` with `A`, which sorts before every wrapper's name, or with `Z`, which sorts after
/// every one, wherever a type name appears, including inside generated names that embed it. Which letter a name
/// gets is drawn from the seed and the name's kind and index (`T3`, `AnyT3`, `Value`), so it is the same on every
/// run, a type and its `Protocol` move together, and most graphs get both letters, which also reorders the names
/// that get different ones. Restoring replaces either letter with `S`.
struct GraphFuzzerRenaming: Equatable, CustomStringConvertible {
	init(reversesTypeNames: Bool, reversesLabels: Bool, reversesFileNames: Bool, movesTypeNamesAcrossWrapperNames: Bool = false) {
		self.reversesTypeNames = reversesTypeNames
		self.reversesLabels = reversesLabels
		self.reversesFileNames = reversesFileNames
		self.movesTypeNamesAcrossWrapperNames = movesTypeNamesAcrossWrapperNames
	}

	let reversesTypeNames: Bool
	let reversesLabels: Bool
	let reversesFileNames: Bool
	let movesTypeNamesAcrossWrapperNames: Bool

	/// Every renaming the oracle runs. A seed's first renamed failure is the one its known issue matches, so a new
	/// renaming goes last: the seeds the earlier ones already list keep their entries.
	static let all = [
		GraphFuzzerRenaming(reversesTypeNames: true, reversesLabels: false, reversesFileNames: false),
		GraphFuzzerRenaming(reversesTypeNames: false, reversesLabels: true, reversesFileNames: false),
		GraphFuzzerRenaming(reversesTypeNames: false, reversesLabels: false, reversesFileNames: true),
		GraphFuzzerRenaming(reversesTypeNames: true, reversesLabels: true, reversesFileNames: true),
		GraphFuzzerRenaming(reversesTypeNames: false, reversesLabels: false, reversesFileNames: false, movesTypeNamesAcrossWrapperNames: true),
	]

	var description: String {
		let reversedOrders = [
			reversesTypeNames ? "type names" : nil,
			reversesLabels ? "labels" : nil,
			reversesFileNames ? "file names" : nil,
		].compactMap(\.self)
		let reversal: String? = switch reversedOrders.count {
		case 0:
			nil
		case 1:
			"reversing its \(reversedOrders[0])"
		default:
			"reversing its \(reversedOrders.dropLast().joined(separator: ", ")), and \(reversedOrders[reversedOrders.count - 1])"
		}
		let move = movesTypeNamesAcrossWrapperNames ? "moving its type names across wrapper names" : nil
		let changes = [reversal, move].compactMap(\.self)
		return changes.isEmpty ? "reversing nothing" : changes.joined(separator: " and ")
	}

	/// `text` with the type names and labels this renaming changes renamed.
	func rename(_ text: String, typeNamePrefix: String) -> String {
		var text = reversingOrders(in: text, typeNamePrefix: typeNamePrefix)
		if movesTypeNamesAcrossWrapperNames {
			text = Self.movingTypeNamesAcrossWrapperNames(in: text, typeNamePrefix: typeNamePrefix)
		}
		return text
	}

	/// `text`, from the tool's run over a graph this renaming renamed, with the renaming undone.
	func restore(_ text: String, typeNamePrefix: String) -> String {
		var text = text
		if movesTypeNamesAcrossWrapperNames {
			text = text.replacingOccurrences(
				of: "(?<![A-Za-z0-9])[AZ](?=" + NSRegularExpression.escapedPattern(for: String(typeNamePrefix.dropFirst())) + "[A-Za-z])",
				with: String(typeNamePrefix.prefix(1)),
				options: .regularExpression,
			)
		}
		if reversesFileNames {
			text = text.replacingOccurrences(
				of: "F[0-9]{2}_(?=" + NSRegularExpression.escapedPattern(for: typeNamePrefix) + ")",
				with: "",
				options: .regularExpression,
			)
		}
		// A path to a fixture file holds no name the renaming changed but the file's own name, so restoring the
		// whole text renames nothing else.
		return reversingOrders(in: text, typeNamePrefix: typeNamePrefix)
	}

	/// `text` with the indices of the type names and labels this renaming reverses reversed, which undoes itself.
	private func reversingOrders(in text: String, typeNamePrefix: String) -> String {
		var text = text
		if reversesTypeNames {
			text = Self.reversingIndices(in: text, pattern: NSRegularExpression.escapedPattern(for: typeNamePrefix) + "(?:Root|AnyT|T|Missing)([0-9])")
		}
		if reversesLabels {
			text = Self.reversingIndices(in: text, pattern: "(?<![A-Za-z0-9])(?:lazyAnyT|lazyT|anyT|t|missing)([0-9])")
		}
		return text
	}

	/// `outcome`, from the tool's run over a graph this renaming renamed, with the renaming undone.
	func restore(_ outcome: GraphFuzzerToolOutcome, typeNamePrefix: String) -> GraphFuzzerToolOutcome {
		switch outcome {
		case let .rejected(diagnostics):
			.rejected(diagnostics: restore(diagnostics, typeNamePrefix: typeNamePrefix))
		case let .accepted(generatedFiles, warnings):
			.accepted(
				generatedFiles: Dictionary(uniqueKeysWithValues: generatedFiles.map {
					(restore($0.key, typeNamePrefix: typeNamePrefix), restore($0.value, typeNamePrefix: typeNamePrefix))
				}),
				warnings: warnings.map { restore($0, typeNamePrefix: typeNamePrefix) },
			)
		}
	}

	/// The names to give the files of `fixture`, in its order: their own names or, when this renaming reverses
	/// file names, the same names with a prefix that reverses their order.
	func fileNames(of fixture: GraphFuzzerFixture) -> [String]? {
		guard reversesFileNames else { return nil }
		let fileNames = fixture.fileNames
		let rankByFileName = Dictionary(uniqueKeysWithValues: fileNames.sorted().enumerated().map { ($1, $0) })
		return fileNames.map { "F\(99 - rankByFileName[$0]!)_\($0)" }
	}

	/// `text` with each path to a fixture file reduced to the file's name, so that the oracle compares no part of a
	/// path but the name a renaming may change and restore.
	static func reducingFixturePathsToFileNames(in text: String) -> String {
		text.replacingOccurrences(of: #"[^\s"'`(]*<fixture-directory>/"#, with: "", options: .regularExpression)
	}

	/// `text` with the `S` that begins each type name's `typeNamePrefix` replaced by `A` or `Z`, chosen by the
	/// letters and index that follow the prefix: the type's kind and index, without a suffix such as `Protocol`.
	private static func movingTypeNamesAcrossWrapperNames(in text: String, typeNamePrefix: String) -> String {
		let expression = try! NSRegularExpression(pattern: "(?<![A-Za-z0-9])" + NSRegularExpression.escapedPattern(for: typeNamePrefix) + "([A-Za-z]+[0-9]?)")
		let source = text as NSString
		var result = ""
		var location = 0
		for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
			let kindAndIndex = source.substring(with: match.range(at: 1))
			var hash = GraphFuzzerHash()
			hash.combine(typeNamePrefix + kindAndIndex)
			var random = GraphFuzzerRandomNumberGenerator(seed: hash.value)
			result += source.substring(with: NSRange(location: location, length: match.range.location - location))
			result += random.percentChance(50) ? "A" : "Z"
			location = match.range.location + 1
		}
		return result + source.substring(from: location)
	}

	private static func reversingIndices(in text: String, pattern: String) -> String {
		let expression = try! NSRegularExpression(pattern: pattern)
		let source = text as NSString
		var result = ""
		var location = 0
		for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
			let digitRange = match.range(at: 1)
			result += source.substring(with: NSRange(location: location, length: digitRange.location - location))
			result += String(9 - Int(source.substring(with: digitRange))!)
			location = digitRange.location + digitRange.length
		}
		return result + source.substring(from: location)
	}
}

/// A feature of the generator that is off by default, so the corpus is drawn as it was before the feature existed.
/// Each feature draws from a stream of its own, seeded from the seed and the feature, which is consumed only when the
/// feature is on, and has a seed range and pins of its own in `SafeDIToolGraphFuzzerTests`.
enum GraphFuzzerGeneratorFeature: String, CaseIterable, Comparable {
	/// One type a root reaches is a seam, declared with `generateDependencyTree: true`, whose tree SafeDI generates
	/// in an initializer of its own that the trees reaching it call, with receives beneath it of properties
	/// provided above it, and a rename of one on the seam, which that initializer passes through.
	case generateDependencyTree
	/// A graph of its own (`GraphFuzzerPublicMockDraw`): types declared with `generateMock: .public` in a declaring
	/// module, and mocked types in a module of the same package and of another package that reach them.
	case generateMockPublic

	static func < (lhs: GraphFuzzerGeneratorFeature, rhs: GraphFuzzerGeneratorFeature) -> Bool {
		lhs.rawValue < rhs.rawValue
	}

	/// The generator features `fixture` was drawn with, read from its source: a seam is drawn only with
	/// `generateDependencyTree` on, and a public mock only with `generateMockPublic` on.
	static func features(drawnIn fixture: GraphFuzzerFixture) -> Set<GraphFuzzerGeneratorFeature> {
		if fixture.swiftFileContent.contains(where: { $0.contains("generateMock: .public") }) {
			[.generateMockPublic]
		} else {
			GraphFuzzerFeature.features(of: fixture).contains(.generateDependencyTree) ? [.generateDependencyTree] : []
		}
	}
}

/// What a seam's generated initializer takes, read from the generated code of a graph the tool accepts, which the
/// seam smoke batch must exercise.
enum GraphFuzzerSeamOutputFeature: String, CaseIterable, Comparable {
	/// A parameter defaulting to `nil`: a property the seam's tree receives only if available.
	case optionalPassThrough
	/// A required parameter the seam does not declare: a property a receiver in its tree requires.
	case requiredPassThrough
	/// A call of a generated initializer passing `.instance` of a wrapper the caller holds for a by-value parameter.
	case instanceReadAtCall
	/// A parameter spelled `@escaping`: a closure the seam's tree receives, which every call passes by name.
	case escapingSeamParameter
	/// A parameter spelled `@escaping` with another attribute: a `@Sendable` closure.
	case escapingAttributedSeamParameter
	/// A parameter of an optional closure type, which is not `@escaping`.
	case optionalClosureSeamParameter

	static func < (lhs: GraphFuzzerSeamOutputFeature, rhs: GraphFuzzerSeamOutputFeature) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

/// What the code generated for a graph with a hole shows, read from an accepted graph's generated files, every one of
/// which the seam smoke batch must show (`seamSmokeSeeds_exerciseSeamFeature_inGraphsTheToolAccepts`).
enum GraphFuzzerHoleOutputFeature: String, CaseIterable, Comparable {
	/// A seam's generated initializer takes a builder for a hole, under an internal name.
	case builderParameter
	/// A builder that takes a `@Sendable` builder function's values in a later stage.
	case stagedBuilder
	/// A seam's builder of another seam's scope struct, which it passes up.
	case passedUpBuilder
	/// A function a caller generates to fill a builder.
	case fill
	/// A fill declared `@Sendable`.
	case sendableFill
	/// A call inside a fill of the seam whose builder it fills, which passes the fill itself.
	case fillPassedToItsSeam
	/// A call inside the fill of a passed-up builder of the inner seam the builder is of, which passes the fill (C1.23).
	case fillOfPassedUpBuilderPassedToItsSeam

	static func < (lhs: GraphFuzzerHoleOutputFeature, rhs: GraphFuzzerHoleOutputFeature) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

/// The shapes `addingSeam` draws, read from a fixture's source, so that a draw that stops landing fails
/// `seamCorpus_drawsEachShapeInAtLeastThePinnedShareOfGraphs` rather than a review.
enum GraphFuzzerSeamDrawFeature: String, CaseIterable, Comparable {
	/// A leaf given a `SeamChild` to build, so that it has a tree.
	case synthesizedChild
	/// Every root instantiating `SeamShared` under `seamShared`: declared, once, by whichever draw first finds no
	/// source of its own – a child's plain receive with no plain property provided above every path to the child, a
	/// rename on the seam with none above the seam, a rename above the seam with none above the renaming type, and
	/// the lazy draw whenever it synthesizes `seamLazy`, whose instance it is.
	case synthesizedSharedProvider
	/// Every root instantiating `SeamShared` lazily under `seamLazy`, where no wrapper is provided above.
	case synthesizedLazyProvider
	/// Every root instantiating `SeamHeld` under `seamHeld`, by value, which a child receives only if available as a
	/// wrapper: a label of the draw's own, which nothing else receives, so the caller passes `nil` rather than the
	/// receive colliding with a by-value form of the label.
	case synthesizedHeldProvider
	/// A seam's child receiving a required non-optional wrapper whose label a type in the seam's tree – another
	/// child, or a `SeamLink` beneath the receiver – receives by value: the one parameter that provides the instance.
	case requiredWrapperProvidingByValueForm
	/// A rename of a provided property on the seam or on a child (`<label>Seam`).
	case renameOnSeamOrChild
	/// A rename above the seam (`<label>Above`), received by the new label beneath it.
	case renameAboveSeam
	/// A seam's child receiving a `LazilyInstantiated` or `SendableLazilyInstantiated` property the graph holds as
	/// that wrapper, required or only if available.
	case wrapperReceiveBeneathSeam
	/// A seam's child receiving, by value, the instance of a lazily instantiated property, which the caller passes
	/// as `.instance`.
	case instanceReceiveBeneathSeam
	/// A seam's child receiving, only if available, a wrapper of a property the graph holds by value, which no type
	/// of the seam's children receives or aliases by value, so the caller passes `nil`.
	case instanceHeldByCaller
	/// A seam's child receiving, only if available, a wrapper of the other kind than the one the graph holds the
	/// property as, so the caller passes `nil`.
	case otherKindWrapperReceiveBeneathSeam
	/// A seam's child receiving a label as an optional wrapper while a child receives or aliases it by value, or the
	/// seam aliases it: the label collision the seam reports, drawn in a known share.
	case collidingFormsBeneathSeam
	/// Two seams, one beneath the other.
	case innerSeam
	/// `addingSpelledProperties`' value spelled as each `GraphFuzzerSpelling`, read from the type it is forwarded as.
	case spelledClosure
	case spelledClosureWithParameterAndReturn
	case spelledSendableClosure
	case spelledOptionalClosure
	case spelledOptionalSendableClosure
	case spelledTupleWithClosure
	case spelledExistential
	case spelledClosureTakingExistential
	case spelledNestedType
	case spelledArray
	case spelledResult
	case spelledTypealias
	/// The spelled value as the seam's own `@Forwarded` property.
	case spelledOwnForwarded
	/// The spelled value as the seam's own `@Received` property.
	case spelledOwnReceived
	/// The spelled value as a pass-through a type in the seam's tree requires.
	case spelledRequiredPassThrough
	/// The spelled value as a pass-through every type in the seam's tree receives only if available.
	case spelledOnlyIfAvailablePassThrough
	/// The spelled value as the property a rename on the seam or in its tree fulfills.
	case spelledAliasFulfillingProperty
	/// The spelled value's optional form received only if available by a second child, `SpellSibling`, beside the
	/// form `SpellChild` receives.
	case spelledOptionalFormOnSibling
	/// `SpellChild` or `SpellSeam` declared with `generateMock: true`, so the spelled value reaches a generated mock.
	case spelledTreeMocked
	/// `addingUncreatedAliasShapes`' receive of the alias's property beneath the type that declares the
	/// `onlyIfAvailable` alias, which the seam rejects wherever the alias may not be created.
	case uncreatedAliasReader
	/// The type that builds the alias's declaring type also instantiates the alias's property.
	case uncreatedAliasSamePropertyBeside
	/// The type that builds the alias's declaring type instantiates the alias's label as another type.
	case uncreatedAliasOtherTypeBeside
	/// The type that builds the alias's declaring type instantiates an instantiator under the alias's label.
	case uncreatedAliasWrapperBeside
	/// The seam instantiates a property under the alias's label, above the type that builds the declaring type.
	case uncreatedAliasDeclarationAbove
	/// The seam takes a parameter under the alias's label: its own receive, or a pass-through another child receives.
	case uncreatedAliasLabelParameter
	/// The alias's declaring type also declares an `onlyIfAvailable` alias of the alias.
	case uncreatedAliasAliasOfAlias
	/// The caller holds the alias's label in the alias's unwrapped type.
	case uncreatedAliasLabelHeldByCaller
	/// The type that builds the alias's declaring type instantiates the alias's fulfilling property, the closest
	/// declaration of it on that path, while another child of the seam receives it only if available.
	case uncreatedAliasFulfillingPropertyPruned
	/// The caller holds the alias's fulfilling property.
	case uncreatedAliasFulfillingPropertyHeldByCaller
	/// A receive of the alias's property beneath its declaring type that requires it.
	case uncreatedAliasRequiredReader
	/// An alias beneath the declaring type that keeps the alias's label and retypes it to an existential.
	case uncreatedAliasLabelKeepingAliasReader
	/// The reader built through an `Instantiator` or a `LazilyInstantiated` wrapper.
	case uncreatedAliasReaderInsideWrapper
	/// The reader reached through a nested seam, `AliasPanel`, whose pass-through stands for its receive.
	case uncreatedAliasReaderInsideNestedSeam
	/// The reader beneath `AliasMid`, a type between it and the alias's declaring type.
	case uncreatedAliasDeeperReader
	/// The alias's declaring type also declares a required alias of the alias.
	case uncreatedAliasRequiredAliasOfAlias
	/// The seam itself declares the alias.
	case uncreatedAliasOnSeamItself
	/// The alias keeps the label of its fulfilling property and only makes it optional (`aliasToken: AliasValue?` of
	/// `aliasToken`), a redundant spelling of a plain receive, which is not an alias of itself.
	case uncreatedAliasLabelKeepingOptionalAlias
	/// The label-keeping alias declared where its fulfilling property is `AliasLeft`'s own sibling of `AliasDetail`,
	/// generated after it because `AliasValue` receives `aliasDetail`: the sibling is the alias's own fulfilling
	/// property, not a declaration of its label, so the alias is passed `nil`, as inline.
	case uncreatedAliasFulfillingPropertyGeneratedAfterLabelKeepingAlias
	/// The alias declared where its fulfilling property is still being built: `AliasDetail` is built inside
	/// `aliasToken`'s builder.
	case uncreatedAliasFulfillingPropertyBeingBuilt
	/// The alias declared where its fulfilling property is generated later: `aliasToken` receives `AliasA` only if
	/// available, and `AliasA` builds `AliasDetail`.
	case uncreatedAliasFulfillingPropertyGeneratedLater
	/// The alias's fulfilling property is a required optional parameter of the seam – its own `@Received` or
	/// `@Forwarded` property, or a property `AliasLeft` requires – which every caller holds a value for.
	case uncreatedAliasRequiredOptionalParameter
	/// The alias spelled with the exact optional form of its fulfilling property, `ofType: AliasValue?.self`.
	case uncreatedAliasExactFormAlias
	/// A reader, alias-of-alias or same-property draw replaced by its accepted twin: the reader or the second alias
	/// reads the fulfilling property, or the alias is made required.
	case uncreatedAliasAcceptedTwin
	/// `addingAccessProofShapes`' seam, `ProofSeam`, declared `package` or `internal`.
	case seamTypeNarrowerThanPublic
	/// A receiver, `ProofBadge`, whose initializer is narrower than the declaration of its parameter's type.
	case receiverNarrowerThanType
	/// A receiver type, `ProofVault`, declared `package` with a `public` initializer, which the type caps.
	case receiverTypeNarrowerThanItsInitializer
	/// The seam's own initializer narrower than its type, its tree passing nothing through (`ProofCog`).
	case ownInitializerNarrowerWithNoPassThrough
	/// The seam's own initializer narrower than its type, with only optional pass-throughs as narrow (`ProofVane`).
	case ownInitializerNarrowerWithOnlyOptionalNarrowerPassThroughs
	/// The seam's own initializer `internal`, beneath a public required pass-through and a package optional one, both
	/// held by the caller (`ProofGauge`, `ProofDial`).
	case ownInitializerNarrowerThanTwoParameterLevels
	/// A required parameter, received by `ProofLock`, of a type narrower than the seam's type.
	case requiredParameterNarrowerThanSeamType
	/// The seam's own `@Received(onlyIfAvailable: true)` property, `proofOwn`.
	case ownOnlyIfAvailableParameter
	/// The seam's own only-if-available property of a type narrower than the seam.
	case ownOnlyIfAvailableParameterNarrowerThanSeam
	/// A plain public model type only a package initializer mentions (`ProofPanel`'s `proofModel`), held by a caller.
	case providedValueHeldByCaller
	/// The plain public model type held by no caller.
	case providedValueHeldByNoCaller
	/// A required alias, on `ProofConsumer`, whose fulfilling property's type is a plain type no declaration proves.
	case unprovenAliasType
	/// The alias of a plain type no declaration proves, only if available.
	case unprovenAliasTypeOnlyIfAvailable
	/// The alias's fulfilling type a package `@Instantiable` type instead, which its own declaration proves.
	case aliasOfNarrowerInstantiableType
	/// A package initializer, `ProofLedger`'s, which no tree reaches, receiving the alias's package fulfilling type itself.
	case aliasFulfillingTypeAlsoReceived
	/// An `@Instantiable` type, `ProofSpace.ProofShelf`, and a plain type declared in an extension of a namespace enum
	/// narrower than them that spells no access level.
	case namespaceExtensionUnspelled
	/// The namespace's extension spelled at the namespace's access level, its members unspelled.
	case namespaceExtensionSpelled
	/// The namespace's `@Instantiable` type reached only through an existential, which no initializer names it in.
	case namespaceTypeOnlyThroughExistential
	/// The namespace enum declared `public`, so callers in other modules construct its types inline.
	case publicNamespace
	/// An `@Instantiable` extension of a narrower type, `ProofRack`, whose `public` `instantiate(…)` receives a package type.
	case instantiableExtensionOfNarrowerType
	/// A parameter type spelled `Swift.`-qualified, received only if available by a package initializer (`ProofMeter`).
	case qualifiedAllowlistMention
	/// A hand-written public mock, whose argument is a dependency, beside `ProofRack`'s `instantiate(…)`.
	case mockInInstantiableExtension
	/// A public mock beside the `instantiate(…)` of an unspelled `@Instantiable` extension of a package plain type,
	/// `ProofShed`, whose argument is the widest mention of the type an internal receiver, `ProofBeam`, receives.
	case mockCappedByItsExtension
	/// `ProofShed` raised to `package` by the initializer of `ProofYard`, which no tree reaches.
	case mockCapRaisedByUnreachedMention
	/// An `@Instantiable` type, `ProofHelper`, declared in an extension that spells no access level of the seam.
	case typeInExtensionOfSeam
	/// `ProofHelper` declared in an extension that spells no access level of a package `@Instantiable` type narrower
	/// than the seam, `ProofSettings`.
	case typeInExtensionOfNarrowerRecordedType
	/// An `@Instantiable` value a host instantiates declared after the seam.
	case valueDeclaredAfterSeam
	/// The graph split across modules: the seam's tree in package `shop`, its caller in the same package.
	case moduleSplit
	/// A second caller of the seam, in package `other`.
	case otherPackageCaller
	/// The caller in the seam's package run over without its package's name, which then cannot tell it shares one.
	case samePackageCallerRunWithoutPackageName
	/// The seam's module run over without its package's name, which no caller can then tell it shares.
	case seamModuleRunWithoutPackageName
	/// A seam, `HoleSeam`, whose module cannot see `HoleImpl`, the type that fulfills `HoleService`, which a property of
	/// its tree instantiates: the seam takes a builder for it, which the roots' module fills.
	case hole
	/// The hole's property is the seam's own.
	case holeOwnedBySeam
	/// The hole's owner, `HoleOwner`, which the seam instantiates by value.
	case holeBeneathConstant
	/// The hole's owner, which the seam instantiates through an `Instantiator`.
	case holeBeneathInstantiator
	/// The hole's owner, which the seam instantiates through a `SendableInstantiator`: a staged builder.
	case holeBeneathSendableInstantiator
	/// The hole's owner, which the seam instantiates through a `LazilyInstantiated`.
	case holeBeneathLazilyInstantiated
	/// The hole's owner, which the seam instantiates through a `SendableLazilyInstantiated`: a staged builder.
	case holeBeneathSendableLazilyInstantiated
	/// The seam instantiates the hole's owner a second time, a second site with a builder of its own.
	case holeOwnerReachedAtTwoSites
	/// `HoleImpl` reads a field of the scope struct, `holeAnalytics`.
	case holeReadsField
	/// `HoleImpl` reads `holeLogger`, which only the root holds.
	case holeReadsCallerValue
	/// `HoleOuter`, a second seam of the seam's module, calls `HoleSeam` and passes its builder up.
	case holePassedUp
	/// `HoleImpl` instantiates `HoleSeam` again, so its fill passes itself to the re-entering call.
	case holeReentersSeam
	/// `HoleImpl` instantiates `HoleSeam` again through `HoleMiddle`, which declares `holeLogger` above the call while
	/// `HoleImpl` reads the root's: rejected, since the fill reads the outer call's value (C1.27).
	case holeReentersSeamBeneathRedeclaredLabel
	/// A re-entry of `HoleSeam` inside the fill of `HoleOuter`'s passed-up builder, which passes that fill (C1.23).
	case holeReentersInnerSeamOfPassedUpBuilder
	/// The seam's own tree reaches the seam again through `HoleLoop`, so the re-entering call is handed the seam's own
	/// builder (G4).
	case holeSeamReentersItself
	/// `HoleLoop` binds `holeLogger` on the re-entry path while `HoleImpl` reads the root's: rejected (C8.14).
	case holeSeamReentersItselfBeneathBoundLabel

	static func < (lhs: GraphFuzzerSeamDrawFeature, rhs: GraphFuzzerSeamDrawFeature) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

/// A spelling of the type of the value `addingSpelledProperties` draws, which a seam's generated initializer, and every
/// call of it, must spell as a parsed initializer does: a closure is `@escaping` there, an optional closure is not.
enum GraphFuzzerSpelling: CaseIterable {
	case closure
	case closureWithParameterAndReturn
	case sendableClosure
	case optionalClosure
	case optionalSendableClosure
	case tupleWithClosure
	case existential
	case closureTakingExistential
	case nestedType
	case array
	case result
	case nonFunctionTypealias

	/// The label of the drawn value wherever it is declared or received.
	static let label = "spelled"

	/// Whether the spelling can be drawn in a graph whose types are all `Sendable`, which stores only `Sendable`
	/// values: a closure is then `@Sendable`, which `sendableClosure` and `optionalSendableClosure` already spell.
	var hasSendableSpelling: Bool {
		switch self {
		case .closure, .optionalClosure:
			false
		case .closureWithParameterAndReturn, .sendableClosure, .optionalSendableClosure, .tupleWithClosure, .existential, .closureTakingExistential, .nestedType, .array, .result, .nonFunctionTypealias:
			true
		}
	}

	/// Whether a rename can name the value's type in `ofType:`: neither an optional, which `Type.self` cannot spell
	/// plainly, nor a tuple, whose labeled elements `.self` would read as an expression.
	var canBeRenamed: Bool {
		switch self {
		case .optionalClosure, .optionalSendableClosure, .tupleWithClosure:
			false
		case .closure, .closureWithParameterAndReturn, .sendableClosure, .existential, .closureTakingExistential, .nestedType, .array, .result, .nonFunctionTypealias:
			true
		}
	}

	/// The type of the value in a graph whose type names begin with `prefix`, with every closure `@Sendable` when
	/// `isSendable`.
	func spelledType(prefix: String, isSendable: Bool) -> String {
		let sendable = isSendable ? "@Sendable " : ""
		return switch self {
		case .closure:
			"() -> Void"
		case .closureWithParameterAndReturn:
			"\(sendable)(Int) -> String"
		case .sendableClosure:
			"@Sendable () -> Void"
		case .optionalClosure:
			"(() -> Void)?"
		case .optionalSendableClosure:
			"(@Sendable () -> Void)?"
		case .tupleWithClosure:
			"(onTap: \(sendable)() -> Void, count: Int)"
		case .existential:
			"any \(prefix)SpellProtocol"
		case .closureTakingExistential:
			"\(sendable)(any \(prefix)SpellProtocol) -> Void"
		case .nestedType:
			"\(prefix)SpellOuter.Item"
		case .array:
			"[\(prefix)Value]"
		case .result:
			"Result<\(prefix)Value, any Error>"
		case .nonFunctionTypealias:
			"\(prefix)SpellIdentifier"
		}
	}

	/// A value of the spelled type, which a probe of the value comparator passes to a builder that forwards it.
	func sampleExpression(prefix: String) -> String {
		switch self {
		case .closure, .sendableClosure, .optionalClosure, .optionalSendableClosure:
			"{}"
		case .closureWithParameterAndReturn:
			"{ _ in \"\" }"
		case .tupleWithClosure:
			"(onTap: {}, count: 1)"
		case .existential:
			"\(prefix)SpellConformer()"
		case .closureTakingExistential:
			"{ _ in }"
		case .nestedType:
			"\(prefix)SpellOuter.Item()"
		case .array:
			"[\(prefix)Value()]"
		case .result:
			".success(\(prefix)Value())"
		case .nonFunctionTypealias:
			"\"id\""
		}
	}

	/// The declarations the spelled type names, beside the graph's own `Value`: `Sendable` where the graph's helper
	/// types are, so that a `Sendable` type can store the value. The existential spellings declare a conformer, the
	/// value `sampleExpression` passes.
	func helperDeclarations(prefix: String, areSendable: Bool) -> [String] {
		switch self {
		case .existential, .closureTakingExistential:
			["public protocol \(prefix)SpellProtocol\(areSendable ? ": Sendable" : "") {}", "public final class \(prefix)SpellConformer: \(prefix)SpellProtocol\(areSendable ? ", Sendable" : "") {\n\tpublic init() {}\n}"]
		case .nestedType:
			["public enum \(prefix)SpellOuter {\n\tpublic final class Item\(areSendable ? ": Sendable" : "") {\n\t\tpublic init() {}\n\t}\n}"]
		case .nonFunctionTypealias:
			["public typealias \(prefix)SpellIdentifier = String"]
		case .closure, .closureWithParameterAndReturn, .sendableClosure, .optionalClosure, .optionalSendableClosure, .tupleWithClosure, .array, .result:
			[]
		}
	}

	/// The seam draw feature of the spelling.
	var drawFeature: GraphFuzzerSeamDrawFeature {
		switch self {
		case .closure: .spelledClosure
		case .closureWithParameterAndReturn: .spelledClosureWithParameterAndReturn
		case .sendableClosure: .spelledSendableClosure
		case .optionalClosure: .spelledOptionalClosure
		case .optionalSendableClosure: .spelledOptionalSendableClosure
		case .tupleWithClosure: .spelledTupleWithClosure
		case .existential: .spelledExistential
		case .closureTakingExistential: .spelledClosureTakingExistential
		case .nestedType: .spelledNestedType
		case .array: .spelledArray
		case .result: .spelledResult
		case .nonFunctionTypealias: .spelledTypealias
		}
	}

	/// The spelling of `type`, a type `spelledType(prefix:isSendable:)` returned, read back from its structure.
	static func spelling(ofType type: String) -> GraphFuzzerSpelling? {
		if type.hasSuffix("?"), type.contains("->") {
			type.contains("@Sendable") ? .optionalSendableClosure : .optionalClosure
		} else if type.hasPrefix("(onTap: ") {
			.tupleWithClosure
		} else if type.contains("(any "), type.contains("->") {
			.closureTakingExistential
		} else if type.contains("(Int) -> String") {
			.closureWithParameterAndReturn
		} else if type == "@Sendable () -> Void" {
			.sendableClosure
		} else if type == "() -> Void" {
			.closure
		} else if type.hasPrefix("any "), type.hasSuffix("SpellProtocol") {
			.existential
		} else if type.hasSuffix("SpellOuter.Item") {
			.nestedType
		} else if type.hasPrefix("["), type.hasSuffix("Value]") {
			.array
		} else if type.hasPrefix("Result<") {
			.result
		} else if type.hasSuffix("SpellIdentifier") {
			.nonFunctionTypealias
		} else {
			nil
		}
	}

	/// The optional form of `type`: itself when it is optional, else `type?`, parenthesized when `?` would bind to a
	/// part of it – a function's result, or an existential's protocol.
	static func optionalForm(of type: String) -> String {
		if type.hasSuffix("?") {
			type
		} else if isFunctionType(type) || type.hasPrefix("any ") {
			"(\(type))?"
		} else {
			"\(type)?"
		}
	}

	/// `type` as `ofType:` spells it before `.self`: parenthesized when `.self` would bind to a part of it.
	static func ofTypeSpelling(of type: String) -> String {
		isFunctionType(type) || type.hasPrefix("any ") ? "(\(type))" : type
	}

	/// Whether `type` is a function type – after its attributes, a parenthesized parameter list followed by ` -> ` –
	/// rather than a type merely holding one, such as an optional closure or a tuple.
	static func isFunctionType(_ type: String) -> Bool {
		var remainder = Substring(type)
		while remainder.hasPrefix("@") {
			remainder = remainder.drop { $0 != " " }.dropFirst()
		}
		guard remainder.hasPrefix("(") else { return false }
		var depth = 0
		for index in remainder.indices {
			switch remainder[index] {
			case "(":
				depth += 1
			case ")":
				depth -= 1
				if depth == 0 {
					return remainder[remainder.index(after: index)...].hasPrefix(" -> ")
				}
			default:
				break
			}
		}
		return false
	}
}

/// Generates graphs of `final class` `@Instantiable` types in two passes.
///
/// The first pass decides what instantiates what. Types are ordered: a type mostly instantiates later types,
/// and instantiates an earlier type (or itself) only through an instantiator, which makes lazy cycles; most
/// such cycles are then made lazy throughout, which SafeDI accepts. The second pass adds received properties
/// and aliases, mostly drawn from properties provided above every path to the receiver – by the roots, which
/// share their properties, or by a type that dominates the receiver – and not by a property whose own subtree
/// holds the receiver. So many graphs are accepted, while the rest exercise SafeDI's validation.
enum GraphFuzzerGenerator {
	/// - Parameter storingEveryParameter: Whether each type stores every parameter it takes, so that the differential
	///   value comparator sees the values the generated code passes and the defaults it leaves in place: the
	///   default-valued parameters of a type's initializer, and the parameters of an extension's `instantiate(…)`,
	///   which the type it returns then takes and stores. Every class of the graph also stores a creation stamp
	///   (`DifferentialValueCreationStamp`) from a counter the first file declares. It changes how a type is written,
	///   never what the seed draws, so the corpus and its pins are those of `false`.
	static func fixture(forSeed seed: UInt64, features: Set<GraphFuzzerGeneratorFeature> = [], storingEveryParameter: Bool = false) -> GraphFuzzerFixture {
		guard !features.contains(.generateMockPublic) else {
			return GraphFuzzerFixture(seed: seed, swiftFileContent: GraphFuzzerPublicMockDraw(seed: seed).swiftFileContent(storingEveryParameter: storingEveryParameter, isKnownRight: false))
		}
		var builder = Builder(seed: seed, features: features, storesEveryParameter: storingEveryParameter)
		return GraphFuzzerFixture(seed: seed, swiftFileContent: builder.build())
	}

	/// The known-right path of the `generateMockPublic` feature's value differential for `seed`: its graph with every
	/// declaration `public` and every `generateMock: .public` turned into `true`, so that every consumer constructs
	/// everything and inlines today's internal mock of each `.public` type.
	static func knownRightPublicMockFixture(forSeed seed: UInt64, storingEveryParameter: Bool = false) -> GraphFuzzerFixture {
		GraphFuzzerFixture(seed: seed, swiftFileContent: GraphFuzzerPublicMockDraw(seed: seed).swiftFileContent(storingEveryParameter: storingEveryParameter, isKnownRight: true))
	}

	/// The access the generator gave each type of the graph it draws for `seed` and `features` that is narrower than
	/// `public` – its spelled level capped by the type its extension extends – by the name the fixture spells it with
	/// (`S1_ProofSpace.S1_ProofShelf` for a nested type): the ground truth a seam's generated tiers are checked
	/// against. Every other type a graph declares is `public`.
	static func narrowerTypeAccess(forSeed seed: UInt64, features: Set<GraphFuzzerGeneratorFeature>) -> [String: AccessLevel] {
		guard !features.contains(.generateMockPublic) else {
			return GraphFuzzerPublicMockDraw(seed: seed).typeAccess
		}
		var builder = Builder(seed: seed, features: features, storesEveryParameter: false)
		_ = builder.build()
		return builder.narrowerTypeAccess
	}

	private struct PropertyDeclaration {
		let attribute: String
		let label: String
		let type: String
	}

	private struct TypeDeclaration {
		let name: String
		var instantiableArguments: [String]
		var properties: [PropertyDeclaration]
		let declaresHelperTypes: Bool
		/// Protocols the type conforms to beyond those every type of its kind does.
		var additionalConformances = [String]()
		/// Declarations written after the type's own.
		var additionalDeclarations = [String]()
		/// Parameters of the initializer after those of `properties`, each with a default value, which the initializer
		/// stores only when the builder stores every parameter. A default-valued parameter is not a dependency.
		var defaultValuedParameters = [ParameterDeclaration]()
		/// The type's spelled access level.
		var access = AccessLevel.public
		/// The initializer's spelled access level, or `nil` for the type's. Either is capped by the narrowest type the
		/// initializer names that `addingAccessProofShapes` declares narrower (`proofTypeAccess`), so the fixture compiles.
		var initializerAccess: AccessLevel?
		/// The module the type belongs to in a graph split across modules, which its file's first lines name, or `nil`
		/// for the module of the graph's roots, `GraphFuzzerModule.samePackageCaller` when the graph is split.
		var module: GraphFuzzerModule?
		/// Whether the type is one `addingHoleShapes` declares beside the roots that fills a hole, or that such a type
		/// instantiates, which `GraphFuzzerFixture.withoutHoles` moves into the seam's module.
		var fillsHole = false
		/// The extension the type is declared in, such as `extension S1_ProofSpace` or `package extension S1_ProofSpace`,
		/// or `nil` for a type declared at top level.
		var enclosingExtension: String?
		/// The access of the type the enclosing extension extends, which caps the type's own.
		var enclosingTypeAccess = AccessLevel.public

		/// The type's access as the compiler reads it: its own, capped by the type its extension extends.
		var effectiveAccess: AccessLevel {
			min(access, enclosingTypeAccess)
		}
	}

	/// An access level a fixture spells, narrowest first. `internal` is spelled by leaving the modifier out.
	enum AccessLevel: Int, Comparable, CaseIterable {
		case `internal`
		case package
		case `public`

		var spelling: String {
			switch self {
			case .internal:
				"internal"
			case .package:
				"package"
			case .public:
				"public"
			}
		}

		/// The modifier with the space after it, or nothing for `internal`.
		var modifier: String {
			switch self {
			case .internal:
				""
			case .package:
				"package "
			case .public:
				"public "
			}
		}

		static func < (lhs: AccessLevel, rhs: AccessLevel) -> Bool {
			lhs.rawValue < rhs.rawValue
		}
	}

	/// A parameter of an initializer or of an extension's `instantiate(…)` that is not a decorated property.
	private struct ParameterDeclaration: Equatable {
		/// The argument label when it differs from `name`: `_` for an unlabeled parameter.
		var argumentLabel: String?
		let name: String
		let type: String
		var defaultValue: String?

		/// The parameter as declared: `title: String = "default"`, `_ note: String = ""`.
		var declaration: String {
			"\(argumentLabel.map { "\($0) " } ?? "")\(name): \(type)\(defaultValue.map { " = \($0)" } ?? "")"
		}

		/// The parameter as a type that takes and stores it declares it: `title: String`.
		var storedDeclaration: String {
			"\(name): \(type)"
		}

		/// The parameter passed on to that type: `title: title`.
		var argument: String {
			"\(name): \(name)"
		}
	}

	/// How an `@Instantiated` property builds its target.
	private enum InstantiationKind {
		case constant
		case erasedConstant
		/// Created once, when its instance is first read. SafeDI validates it exactly as a constant: it does not
		/// break a dependency cycle, and its type cannot have forwarded properties.
		case lazilyInstantiated
		case erasedLazilyInstantiated
		case instantiator
		case erasedInstantiator

		/// Whether the property breaks a dependency cycle, as only an instantiator does.
		var isLazy: Bool {
			switch self {
			case .constant, .erasedConstant, .lazilyInstantiated, .erasedLazilyInstantiated:
				false
			case .instantiator, .erasedInstantiator:
				true
			}
		}

		var lazyKind: InstantiationKind {
			switch self {
			case .constant, .lazilyInstantiated, .instantiator:
				.instantiator
			case .erasedConstant, .erasedLazilyInstantiated, .erasedInstantiator:
				.erasedInstantiator
			}
		}
	}

	/// An `@Instantiated` property of a root (`sourceIndex` is `nil`) or of the type at `sourceIndex`.
	private struct InstantiationEdge {
		let sourceIndex: Int?
		let targetIndex: Int
		var kind: InstantiationKind
		/// The type whose label the property borrows, so that one label names properties of different types.
		let labelIndex: Int
		/// Whether the property is a `SendableInstantiator`, `SendableErasedInstantiator`, or
		/// `SendableLazilyInstantiated` when its kind wraps its target. A constant ignores it.
		let isSendable: Bool
	}

	/// Which wrappers a graph's properties use.
	private enum Sendability {
		/// Every wrapper is `Instantiator`, `ErasedInstantiator`, or `LazilyInstantiated`.
		case nonSendable
		/// Every wrapper is `Sendable`, and so is every type.
		case sendable
		/// Each wrapper is `Sendable` or not at random, so a `Sendable` builder's subtree can receive a
		/// `LazilyInstantiated` declared outside it. Every type is `@unchecked Sendable`, so that receiving one of
		/// them by value inside a `@Sendable` builder function is never what fails to compile.
		case mixed
	}

	/// A property that a type below its provider can receive.
	private struct ProvidedProperty {
		let label: String
		let type: String
		/// The type that declares the property, or `nil` for a property every root declares.
		let providerIndex: Int?
		/// The type the property builds, whose subtree must not receive it.
		let builtIndex: Int?

		var isOptional: Bool {
			type.hasSuffix("?")
		}
	}

	private struct Builder {
		init(seed: UInt64, features: Set<GraphFuzzerGeneratorFeature>, storesEveryParameter: Bool) {
			self.features = features
			self.storesEveryParameter = storesEveryParameter
			random = GraphFuzzerRandomNumberGenerator(seed: seed)
			seamRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.seamRandomSeedMask)
			spellingRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.spellingRandomSeedMask)
			uncreatedAliasRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.uncreatedAliasRandomSeedMask)
			labelKeepingAliasRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.labelKeepingAliasRandomSeedMask)
			generatedNameRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.generatedNameRandomSeedMask)
			unbuildableDependencyRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.unbuildableDependencyRandomSeedMask)
			unbuildableDependencyReceiverRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.unbuildableDependencyReceiverRandomSeedMask)
			unbuildableDependencySiblingReceiverRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.unbuildableDependencySiblingReceiverRandomSeedMask)
			aliasChainRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.aliasChainRandomSeedMask)
			siblingAliasChainRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.siblingAliasChainRandomSeedMask)
			proofRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.proofRandomSeedMask)
			holeRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.holeRandomSeedMask)
			holePassUpRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.holePassUpRandomSeedMask)
			holeReentryRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.holeReentryRandomSeedMask)
			holeSelfReentryRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.holeSelfReentryRandomSeedMask)
			prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: seed)
			// One draw decides, so graphs that are not mixed draw exactly what they drew before mixed graphs existed.
			let sendabilityRoll = random.integer(in: 0...99)
			sendability = if sendabilityRoll < 15 {
				.sendable
			} else if sendabilityRoll < 40 {
				.mixed
			} else {
				.nonSendable
			}
			typeCount = random.integer(in: 3...7)
			lazyPercent = random.element(of: [25, 50, 75])
		}

		mutating func build() -> [String] {
			buildInstantiationStructure()
			computeDominatorsAndDependencies()

			var declarations = [TypeDeclaration]()
			let rootPool = edges.filter { $0.sourceIndex == nil }
			for edge in rootPool {
				provide(property(for: edge), providerIndex: nil, builtIndex: edge.targetIndex)
			}
			for rootIndex in 0..<rootCount {
				var properties = [PropertyDeclaration]()
				func add(_ property: PropertyDeclaration) {
					guard !properties.contains(where: { $0.label == property.label }) else { return }
					properties.append(property)
				}
				for edge in rootPool {
					add(property(for: edge))
				}
				// Now and then a root declares a property the others do not, which a shared type may then miss.
				if random.percentChance(20) {
					let targetIndex = random.integer(in: 0...(typeCount - 1))
					let labelIndex = random.integer(in: 0...(typeCount - 1))
					add(property(for: InstantiationEdge(sourceIndex: nil, targetIndex: targetIndex, kind: .instantiator, labelIndex: labelIndex, isSendable: wrapperIsSendable())))
				}
				declarations.append(TypeDeclaration(
					name: "\(prefix)Root\(rootIndex)",
					instantiableArguments: ["isRoot: true"],
					properties: properties,
					declaresHelperTypes: false,
				))
			}

			for index in 0..<typeCount {
				if let forwardedProperty = forwardedProperties[index] {
					provide(forwardedProperty, providerIndex: index, builtIndex: nil)
				}
				for edge in edges where edge.sourceIndex == index {
					provide(property(for: edge), providerIndex: index, builtIndex: edge.targetIndex)
				}
			}
			for index in 0..<typeCount {
				declarations.append(typeDeclaration(index: index))
			}
			appendMotif(to: &declarations)
			// Decided last, so that the rest of a seed's graph does not depend on whether it has the extension.
			let extensionSource = random.percentChance(25) ? extensionDeclarationSource(addingPropertyToOneOf: &declarations) : nil
			var finalDeclarations = addingHoleShapes(to: addingAccessProofShapes(to: addingUncreatedAliasShapes(to: addingSpelledProperties(to: addingSeam(
				to: addingReceiversOfDependenciesMocksCannotBuild(
					to: addingSiblingAliasChains(to: addingAliasChains(to: addingDependenciesMocksCannotBuild(to: addingPropertiesLabeledAsGeneratedNames(to: declarations)))),
				),
			)))))
			// In a graph split across modules, every file names its module and imports the seam's, so that a type of the
			// caller can name what the seam's module declares, such as the creation stamps' counter.
			let isSplit = finalDeclarations.contains { $0.module == .seamModule }
			if isSplit {
				for index in finalDeclarations.indices where finalDeclarations[index].module == nil {
					finalDeclarations[index].module = .samePackageCaller
				}
			}
			let sources = finalDeclarations.map(source(of:))
				+ [extensionSource.map { isSplit ? GraphFuzzerModule.samePackageCaller.fileHeader(omitsPackageName: modulesOmittingPackageName.contains(.samePackageCaller)) + $0 : $0 }].compactMap(\.self)
			return storesEveryParameter ? addingCreationStamps(to: sources) : sources
		}

		/// `sources` with the creation stamps of `DifferentialValueCreationStamp`: the counter, at the end of the first
		/// file, which is `Root0`'s, and a stamp as the first stored property of every class the graph declares, each of
		/// which begins a line, after its indentation (a nested class's, such as a spelling's `SpellOuter.Item`), with
		/// `final class`, after a `public` or `package` modifier if it spells one, and ends it with ` {` or, for a class
		/// without a body, ` {}`. A graph split across modules declares the counter in the seam's module, which the
		/// others import.
		private func addingCreationStamps(to sources: [String]) -> [String] {
			let counterName = "\(prefix)CreationStamp"
			let stamp = DifferentialValueCreationStamp.property(counterNamed: counterName)
			// The counter is declared in the first file of the module every other module imports: the seam's module in a
			// graph split across modules.
			let counterIndex = sources.firstIndex { GraphFuzzerModule(declaredIn: $0) == .seamModule } ?? 0
			return sources.enumerated().map { index, source in
				let lines = source.split(separator: "\n", omittingEmptySubsequences: false).flatMap { line -> [String] in
					let indentation = line.prefix { $0 == "\t" }
					let declaration = line.dropFirst(indentation.count)
					guard ["public ", "package ", ""].contains(where: { declaration.hasPrefix($0 + "final class ") }) else { return [String(line)] }
					if line.hasSuffix(" {}") {
						return [String(line.dropLast("}".count)), "\(indentation)\t\(stamp)", "\(indentation)}"]
					} else {
						return [String(line), "\(indentation)\t\(stamp)", ""]
					}
				}
				let stampedSource = lines.joined(separator: "\n")
				return index == counterIndex ? stampedSource + "\n" + DifferentialValueCreationStamp.counterDeclaration(named: counterName) + "\n" : stampedSource
			}
		}

		/// A quarter of graphs end with a motif: a few more types, in a shape whose generated code or diagnostics
		/// SafeDI must choose among equals for, so that a choice made by name, label, or file order shows up under the
		/// rename-invariance oracle. The motif's types take the indices past every graph's own, 7 through 9, which
		/// no other type refers to. It is drawn after the graph's own types, so a graph without one is drawn exactly as before.
		private mutating func appendMotif(to declarations: inout [TypeDeclaration]) {
			let instantiator = sendability == .sendable ? "SendableInstantiator" : "Instantiator"
			func motifType(_ index: Int, arguments: [String] = [], properties: [PropertyDeclaration]) -> TypeDeclaration {
				TypeDeclaration(name: typeName(index), instantiableArguments: arguments, properties: properties, declaresHelperTypes: true)
			}
			let roll = random.integer(in: 0...99)
			if roll < 5 {
				// A lazy cycle of two or three mocked types: which edge closes it decides which configuration lacks a field.
				let length = random.integer(in: 2...3)
				for position in 0..<length {
					let next = 7 + (position + 1) % length
					declarations.append(motifType(7 + position, arguments: ["generateMock: true"], properties: [
						PropertyDeclaration(attribute: "@Instantiated", label: "t\(next)Builder", type: "\(instantiator)<\(typeName(next))>"),
					]))
				}
			} else if roll < 10 {
				// A mocked type whose mock promotes two siblings that receive each other only if available: only one can see the other.
				declarations.append(motifType(7, arguments: ["generateMock: true"], properties: [
					PropertyDeclaration(attribute: "@Received", label: "t8", type: typeName(8)),
					PropertyDeclaration(attribute: "@Received", label: "t9", type: typeName(9)),
				]))
				declarations.append(motifType(8, properties: [PropertyDeclaration(attribute: "@Received(onlyIfAvailable: true)", label: "t9", type: typeName(9) + "?")]))
				declarations.append(motifType(9, properties: [PropertyDeclaration(attribute: "@Received(onlyIfAvailable: true)", label: "t8", type: typeName(8) + "?")]))
			} else if roll < 15 {
				// A mocked type whose tree receives one label as an instance and as an instantiator, which its mock names apart.
				declarations.append(motifType(7, arguments: ["generateMock: true"], properties: [
					PropertyDeclaration(attribute: "@Received", label: "t9", type: "\(instantiator)<\(typeName(9))>"),
					PropertyDeclaration(attribute: "@Instantiated", label: "t8", type: typeName(8)),
				]))
				declarations.append(motifType(8, properties: [PropertyDeclaration(attribute: "@Received", label: "t9", type: typeName(9))]))
				declarations.append(motifType(9, properties: []))
			} else if roll < 20, rootCount > 1 {
				// Roots that are each invalid on their own: each instantiates a type that is not `@Instantiable`.
				for rootIndex in 0..<rootCount {
					let missingTypeName = "\(prefix)Missing\(rootIndex)"
					declarations[rootIndex].properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "missing\(rootIndex)", type: missingTypeName))
					declarations[rootIndex].additionalDeclarations.append("public final class \(missingTypeName)\(helperTypesAreSendable ? ": Sendable" : "") {}")
				}
			} else if roll >= 20, roll < 25 {
				// Two types, in two files, that both fulfill one protocol.
				let sharedProtocol = protocolName(7)
				declarations.append(motifType(7, arguments: ["fulfillingAdditionalTypes: [\(sharedProtocol).self]"], properties: []))
				var duplicate = motifType(8, arguments: ["fulfillingAdditionalTypes: [\(sharedProtocol).self]"], properties: [])
				duplicate.additionalConformances.append(sharedProtocol)
				declarations.append(duplicate)
			} else if roll >= 25, roll < 30 {
				// A mocked type that builds a type through a `Sendable` wrapper, whose subtree has values production
				// creates inside the `@Sendable` builder function and a mock is handed: a labeled default-valued
				// initializer parameter of a type that is not `Sendable`, and a dependency the mock cannot build, of a
				// type that is not `Sendable`. The wrapper is `Sendable` whatever the graph's wrappers are, so the types
				// it builds are `@unchecked Sendable` in a `Sendable` graph, where their protocols are `Sendable`.
				var owner = motifType(8, properties: [PropertyDeclaration(attribute: "@Instantiated", label: "t9", type: typeName(9))])
				owner.defaultValuedParameters = [ParameterDeclaration(name: "formatter", type: nonSendableHelperTypeName("Formatter"), defaultValue: "\(nonSendableHelperTypeName("Formatter"))()")]
				owner.additionalDeclarations.append("public final class \(nonSendableHelperTypeName("Formatter")) {\n\tpublic init() {}\n}")
				var leaf = motifType(9, properties: [PropertyDeclaration(attribute: "@Instantiated", label: "engine", type: nonSendableHelperTypeName("Engine"))])
				leaf.additionalDeclarations.append("public final class \(nonSendableHelperTypeName("Engine")) {\n\tpublic init() {}\n}")
				if sendability == .sendable {
					owner.additionalConformances.append("@unchecked Sendable")
					leaf.additionalConformances.append("@unchecked Sendable")
				}
				declarations.append(motifType(7, arguments: ["generateMock: true"], properties: [
					PropertyDeclaration(attribute: "@Instantiated", label: "t8Builder", type: "SendableInstantiator<\(typeName(8))>"),
				]))
				declarations.append(owner)
				declarations.append(leaf)
				sendableBuilderMotifMockedTypeName = typeName(7)
			}
		}

		/// The name of a helper type the `Sendable` builder motif declares, which is never `Sendable`.
		private func nonSendableHelperTypeName(_ name: String) -> String {
			"\(prefix)\(name)"
		}

		private var random: GraphFuzzerRandomNumberGenerator
		/// Draws only the choices of `addingPropertiesLabeledAsGeneratedNames`, so that every other choice is the
		/// one `random` makes for the seed without them.
		private var generatedNameRandom: GraphFuzzerRandomNumberGenerator
		/// Draws only the choices of `addingDependenciesMocksCannotBuild`, as `generatedNameRandom` does for its pass.
		private var unbuildableDependencyRandom: GraphFuzzerRandomNumberGenerator
		/// Draws only the choices of `addingReceiversOfDependenciesMocksCannotBuild`, as `generatedNameRandom` does for its pass.
		private var unbuildableDependencyReceiverRandom: GraphFuzzerRandomNumberGenerator
		/// Draws only the receives beside an owner that `addingReceiversOfDependenciesMocksCannotBuild` adds.
		private var unbuildableDependencySiblingReceiverRandom: GraphFuzzerRandomNumberGenerator
		/// Draws only the choices of `addingAliasChains`, as `generatedNameRandom` does for its pass.
		private var aliasChainRandom: GraphFuzzerRandomNumberGenerator
		/// Draws only the choices of `addingSiblingAliasChains`, as `generatedNameRandom` does for its pass.
		private var siblingAliasChainRandom: GraphFuzzerRandomNumberGenerator
		/// Draws only the choices of `addingSeam`, which draws only with the `generateDependencyTree` feature on, so
		/// every graph without it is drawn as before.
		private var seamRandom: GraphFuzzerRandomNumberGenerator
		/// Draws only the choices of `addingSpelledProperties`, which draws only with the `generateDependencyTree`
		/// feature on, after `addingSeam` and before `addingUncreatedAliasShapes`, so every graph without it is drawn as
		/// before and a seam graph it leaves plain is drawn as it was before the pass existed.
		private var spellingRandom: GraphFuzzerRandomNumberGenerator
		/// Draws only the choices of `addingUncreatedAliasShapes`, which draws only with the `generateDependencyTree`
		/// feature on, last of every pass, so a seam graph it leaves plain is drawn as it was before the pass existed.
		private var uncreatedAliasRandom: GraphFuzzerRandomNumberGenerator
		/// Draws only the choices of `addingAccessProofShapes`, which draws only with the `generateDependencyTree` feature
		/// on, after every other pass, so a seam graph it leaves plain is drawn as it was before the pass existed.
		private var proofRandom: GraphFuzzerRandomNumberGenerator
		/// Draws only the choices of `addingHoleShapes`, which draws only with the `generateDependencyTree` feature on,
		/// after every other pass, so a seam graph it leaves plain is drawn as it was before the pass existed; each of
		/// its three further draws has a generator of its own.
		private var holeRandom: GraphFuzzerRandomNumberGenerator
		private var holePassUpRandom: GraphFuzzerRandomNumberGenerator
		private var holeReentryRandom: GraphFuzzerRandomNumberGenerator
		private var holeSelfReentryRandom: GraphFuzzerRandomNumberGenerator
		/// The access of each type `addingAccessProofShapes` declares narrower than `public`, by the name the fixture
		/// spells it with (`S1_ProofSpace.S1_ProofShelf` for a nested type), which caps every initializer naming it.
		private var proofTypeAccess = [String: AccessLevel]()

		/// The modules of a split graph the tool runs over without their package's name.
		private var modulesOmittingPackageName = Set<GraphFuzzerModule>()

		/// `proofTypeAccess`, once `build()` has drawn the graph.
		var narrowerTypeAccess: [String: AccessLevel] {
			proofTypeAccess
		}

		/// Draws only whether `addingUncreatedAliasShapes`' alias keeps its fulfilling property's label, and then whether
		/// that property is `AliasLeft`'s own sibling generated after `AliasDetail`: rolls added after the pass's other draws
		/// were pinned, so that every other graph of the pass is drawn as before.
		private var labelKeepingAliasRandom: GraphFuzzerRandomNumberGenerator
		private let features: Set<GraphFuzzerGeneratorFeature>
		/// How many types that are not `@Instantiable` `addingDependenciesMocksCannotBuild` instantiates.
		private var unbuildableTypeCount = 0
		/// The mocked type of the `Sendable` builder motif, when `appendMotif` drew it. It gets no dependency a mock
		/// cannot build: it is outside the `@Sendable` builder function, so a receiver of the dependency that
		/// `addingReceiversOfDependenciesMocksCannotBuild` adds beneath it, inside the function, would be handed a
		/// value from outside the `Sendable` wrapper's subtree, which SafeDI leaves to the compiler to reject.
		private var sendableBuilderMotifMockedTypeName: String?
		/// Whether each type stores every parameter it takes; see `GraphFuzzerGenerator.fixture(forSeed:storingEveryParameter:)`.
		private let storesEveryParameter: Bool
		private let prefix: String
		private let sendability: Sendability
		private let typeCount: Int
		private let lazyPercent: Int
		private var rootCount = 0
		private var forwardedProperties = [PropertyDeclaration?]()
		private var edges = [InstantiationEdge]()
		/// `dominators[index]` holds the types on every path from a root to the type at `index`, or every type
		/// when no root reaches it.
		private var dominators = [Set<Int>]()
		/// The types a root reaches.
		private var reachableFromRoots = Set<Int>()
		/// `dependencyEdges[index]` holds the types that must be built before the type at `index` can be: those it
		/// instantiates, and those whose property it requires.
		private var dependencyEdges = [[Int]]()
		private var provided = [ProvidedProperty]()

		// MARK: First pass

		private mutating func buildInstantiationStructure() {
			for _ in 0..<typeCount {
				guard random.percentChance(20) else {
					forwardedProperties.append(nil)
					continue
				}
				let target = random.integer(in: 0...(typeCount - 1))
				let labelIndex = borrowedLabelIndex(for: target)
				let roll = random.integer(in: 0...99)
				if roll < 8 {
					// A forwarded `LazilyInstantiated` of a type that is not `@Instantiable`, under one label every
					// type shares: a mock that receives it cannot build the instance, so it takes the instance and
					// wraps it, while types below it forward their own.
					let wrapper = lazilyInstantiatedWrapper(isSendable: wrapperIsSendable())
					forwardedProperties.append(PropertyDeclaration(
						attribute: "@Forwarded",
						label: "lazyValue",
						type: "\(wrapper)<\(valueTypeName)>",
					))
				} else if roll < 15 {
					// A forwarded `LazilyInstantiated`, whose instance receivers can also receive.
					let wrapper = lazilyInstantiatedWrapper(isSendable: wrapperIsSendable())
					forwardedProperties.append(PropertyDeclaration(
						attribute: "@Forwarded",
						label: "lazyT\(labelIndex)",
						type: "\(wrapper)<\(typeName(target))>",
					))
				} else if roll >= 45, roll < 52 {
					// A forwarded erased instantiator, which the type passes through to the types below it. It draws
					// nothing, as the forwarded constant it replaces draws nothing, so the rest of the graph is drawn
					// as before.
					let wrapper = forwardedErasedInstantiatorIsSendable(labelIndex: labelIndex) ? "SendableErasedInstantiator" : "ErasedInstantiator"
					forwardedProperties.append(PropertyDeclaration(
						attribute: "@Forwarded",
						label: "anyT\(labelIndex)Builder",
						type: "\(wrapper)<(), \(erasedTypeName(target))>",
					))
				} else {
					forwardedProperties.append(PropertyDeclaration(
						attribute: "@Forwarded",
						label: "t\(labelIndex)",
						type: typeName(target) + (roll < 45 ? "?" : ""),
					))
				}
			}

			rootCount = random.integer(in: 1...3)
			for _ in 0..<random.integer(in: 1...4) {
				let target = random.integer(in: 0...(typeCount - 1))
				let kind = instantiationKind(target: target, isLazy: nil)
				let labelIndex = borrowedLabelIndex(for: target)
				appendEdgeUnlessLabelIsTaken(InstantiationEdge(sourceIndex: nil, targetIndex: target, kind: kind, labelIndex: labelIndex, isSendable: wrapperIsSendable()))
			}
			for index in 0..<typeCount {
				for _ in 0..<random.integer(in: 0...2) {
					let target = random.integer(in: 0...(typeCount - 1))
					// Only an instantiator can build an earlier type, or this type, without a constant cycle.
					let isBackward = target <= index
					guard !isBackward || random.percentChance(40) else { continue }
					let kind = instantiationKind(target: target, isLazy: isBackward ? true : nil)
					let labelIndex = borrowedLabelIndex(for: target)
					appendEdgeUnlessLabelIsTaken(InstantiationEdge(
						sourceIndex: index,
						targetIndex: target,
						kind: kind,
						labelIndex: labelIndex,
						isSendable: wrapperIsSendable(),
					))
				}
			}

			// SafeDI rejects a cycle that mixes constant and lazy properties, so make most cycles lazy throughout.
			for backwardEdge in edges where backwardEdge.kind.isLazy {
				guard let sourceIndex = backwardEdge.sourceIndex,
				      backwardEdge.targetIndex <= sourceIndex,
				      random.percentChance(80),
				      let path = edgePath(from: backwardEdge.targetIndex, to: sourceIndex)
				else { continue }
				for edgeIndex in path {
					edges[edgeIndex].kind = edges[edgeIndex].kind.lazyKind
				}
			}
		}

		/// Appends `edge` unless its source already declares a property with the same label.
		private mutating func appendEdgeUnlessLabelIsTaken(_ edge: InstantiationEdge) {
			let label = property(for: edge).label
			let forwardedLabel = edge.sourceIndex.flatMap { forwardedProperties[$0]?.label }
			guard label != forwardedLabel,
			      !edges.contains(where: { $0.sourceIndex == edge.sourceIndex && property(for: $0).label == label })
			else { return }
			edges.append(edge)
		}

		/// The indices in `edges` of a path from the type at `start` to the type at `destination`.
		private func edgePath(from start: Int, to destination: Int) -> [Int]? {
			var predecessorEdgeByType = [Int: Int]()
			var queue = [start]
			var visited: Set = [start]
			while !queue.isEmpty {
				let current = queue.removeFirst()
				guard current != destination else {
					var path = [Int]()
					var type = destination
					while type != start, let edgeIndex = predecessorEdgeByType[type] {
						path.append(edgeIndex)
						type = edges[edgeIndex].sourceIndex ?? start
					}
					return path
				}
				for (edgeIndex, edge) in edges.enumerated() where edge.sourceIndex == current && visited.insert(edge.targetIndex).inserted {
					predecessorEdgeByType[edge.targetIndex] = edgeIndex
					queue.append(edge.targetIndex)
				}
			}
			return nil
		}

		private mutating func instantiationKind(target: Int, isLazy: Bool?) -> InstantiationKind {
			// A type with a forwarded property can only be built through an instantiator.
			let isLazy = isLazy ?? (forwardedProperties[target] != nil || random.percentChance(lazyPercent))
			if isLazy {
				return random.percentChance(20) ? .erasedInstantiator : .instantiator
			} else {
				let roll = random.integer(in: 0...99)
				if roll < 12 {
					return .erasedConstant
				} else if roll < 26 {
					return .lazilyInstantiated
				} else if roll < 32 {
					return .erasedLazilyInstantiated
				} else {
					return .constant
				}
			}
		}

		/// Whether a wrapper is `Sendable`: always in a `Sendable` graph, never in a non-`Sendable` one, and at
		/// random in a mixed one, which alone draws for it.
		private mutating func wrapperIsSendable() -> Bool {
			switch sendability {
			case .nonSendable:
				false
			case .sendable:
				true
			case .mixed:
				random.percentChance(50)
			}
		}

		/// Whether a forwarded erased instantiator is `Sendable`. A mixed graph decides by the label, rather than by a
		/// draw, so that adding forwarded erased instantiators left every other graph drawn as before.
		private func forwardedErasedInstantiatorIsSendable(labelIndex: Int) -> Bool {
			switch sendability {
			case .nonSendable:
				false
			case .sendable:
				true
			case .mixed:
				labelIndex.isMultiple(of: 2)
			}
		}

		/// The target's own index, or now and then another type's, whose label the property then borrows.
		private mutating func borrowedLabelIndex(for target: Int) -> Int {
			guard random.percentChance(8) else { return target }
			return (target + random.integer(in: 1...(typeCount - 1))) % typeCount
		}

		private mutating func computeDominatorsAndDependencies() {
			let rootTargets = Set(edges.filter { $0.sourceIndex == nil }.map(\.targetIndex))
			func reachable(from starts: Set<Int>, excluding excludedIndex: Int?) -> Set<Int> {
				var visited = Set<Int>()
				var stack = starts.filter { $0 != excludedIndex }.sorted()
				while let current = stack.popLast() {
					guard visited.insert(current).inserted else { continue }
					stack += edges.filter { $0.sourceIndex == current && $0.targetIndex != excludedIndex }.map(\.targetIndex)
				}
				return visited
			}
			reachableFromRoots = reachable(from: rootTargets, excluding: nil)
			dependencyEdges = (0..<typeCount).map { index in
				edges.filter { $0.sourceIndex == index }.map(\.targetIndex)
			}
			dominators = (0..<typeCount).map { index in
				guard reachableFromRoots.contains(index) else { return Set(0..<typeCount) }
				return Set((0..<typeCount).filter { candidate in
					candidate == index || !reachable(from: rootTargets, excluding: candidate).contains(index)
				})
			}
		}

		// MARK: Second pass

		/// Makes `property` receivable below `providerIndex`. An erased instantiator is received with exactly the
		/// type its provider declares, including the forwarded properties its first generic names.
		private mutating func provide(_ property: PropertyDeclaration, providerIndex: Int?, builtIndex: Int?) {
			provided.append(ProvidedProperty(label: property.label, type: property.type, providerIndex: providerIndex, builtIndex: builtIndex))
			// A `LazilyInstantiated` property also provides its instance under its label. An optional one does not.
			for wrapper in ["SendableLazilyInstantiated<", "LazilyInstantiated<"] where property.type.hasPrefix(wrapper) && property.type.hasSuffix(">") {
				let instanceType = String(property.type.dropFirst(wrapper.count).dropLast())
				provided.append(ProvidedProperty(label: property.label, type: instanceType, providerIndex: providerIndex, builtIndex: builtIndex))
				break
			}
		}

		private mutating func typeDeclaration(index: Int) -> TypeDeclaration {
			var properties = [PropertyDeclaration]()
			func add(_ property: PropertyDeclaration) {
				guard !properties.contains(where: { $0.label == property.label }) else { return }
				properties.append(property)
			}

			if let forwardedProperty = forwardedProperties[index] {
				add(forwardedProperty)
			}
			for edge in edges where edge.sourceIndex == index {
				add(property(for: edge))
			}
			if random.percentChance(25), let alias = aliasProperty(receiverIndex: index) {
				add(alias)
			}
			for _ in 0..<random.integer(in: 0...2) {
				if let receivedProperty = receivedProperty(receiverIndex: index) {
					add(receivedProperty)
				}
			}

			return TypeDeclaration(
				name: typeName(index),
				instantiableArguments: random.percentChance(30) ? ["generateMock: true"] : [],
				properties: properties,
				declaresHelperTypes: true,
			)
		}

		/// The provided properties the type at `receiverIndex` can receive: those provided above every path to it,
		/// other than its own and those whose subtree holds it. Now and then, any provided property.
		private mutating func receivableProperties(receiverIndex: Int) -> [ProvidedProperty] {
			guard random.percentChance(90) else { return provided }
			return propertiesProvidedAboveEveryPath(to: receiverIndex)
		}

		/// The provided properties that are provided above every path to the type at `receiverIndex`, other than
		/// its own and those whose subtree holds it.
		private func propertiesProvidedAboveEveryPath(to receiverIndex: Int) -> [ProvidedProperty] {
			// A label that names a property built only after the receiver resolves, along some path, to that
			// property, and SafeDI rejects the receive as a cycle.
			let labelsBuiltAround = Set(provided.filter { property in
				property.builtIndex.map { dependsOn(receiverIndex, from: $0) } ?? false
			}.map(\.label))
			return provided.filter { property in
				let isProvidedAbove = property.providerIndex.map { $0 != receiverIndex && dominators[receiverIndex].contains($0) } ?? true
				return isProvidedAbove && !labelsBuiltAround.contains(property.label)
			}
		}

		/// Whether the type at `start` cannot be built before the type at `destination`.
		private func dependsOn(_ destination: Int, from start: Int) -> Bool {
			var visited = Set<Int>()
			var stack = [start]
			while let current = stack.popLast() {
				guard current != destination else { return true }
				guard visited.insert(current).inserted else { continue }
				stack += dependencyEdges[current]
			}
			return false
		}

		/// Records that the type at `receiverIndex` requires `property`, so must be built after what builds it.
		private mutating func recordRequirement(of property: ProvidedProperty, receiverIndex: Int) {
			guard let builtIndex = property.builtIndex else { return }
			dependencyEdges[receiverIndex].append(builtIndex)
		}

		/// A `@Received(fulfilledByDependencyNamed:ofType:)` property that renames, retypes, or erases a receivable property.
		private mutating func aliasProperty(receiverIndex: Int) -> PropertyDeclaration? {
			// An `ofType:` argument is spelled `Type.self`, which suits neither optionals nor tuple-typed generics.
			// SafeDI leaves it to the compiler to check that `ofType:` matches the property the label resolves to,
			// and the compiler reports a mismatch at the alias, as the manual documents. So alias only labels that
			// name one type throughout the graph, where a compiler error is a defect rather than that diagnostic.
			let candidates = receivableProperties(receiverIndex: receiverIndex).filter { candidate in
				!candidate.isOptional
					&& !candidate.type.contains("(")
					&& !candidate.type.contains("ErasedInstantiator<")
					&& provided.allSatisfy { $0.label != candidate.label || $0.type == candidate.type }
			}
			guard !candidates.isEmpty else { return nil }
			let source = random.element(of: candidates)
			let isOnlyIfAvailable = random.percentChance(40)
			let graphTypeIndex = (0..<typeCount).first { typeName($0) == source.type }
			var arguments = ["fulfilledByDependencyNamed: \"\(source.label)\"", "ofType: \(source.type).self"]
			let label: String
			let type: String
			if let graphTypeIndex, random.percentChance(30) {
				arguments.append("erasedToConcreteExistential: true")
				label = "anyT\(graphTypeIndex)Alias"
				type = erasedTypeName(graphTypeIndex)
			} else if let graphTypeIndex, random.percentChance(50) {
				label = "t\(graphTypeIndex)Protocol"
				type = protocolName(graphTypeIndex)
			} else {
				label = "\(source.label)Alias"
				type = source.type
			}
			if isOnlyIfAvailable {
				arguments.append("onlyIfAvailable: true")
			} else {
				recordRequirement(of: source, receiverIndex: receiverIndex)
			}
			provide(PropertyDeclaration(attribute: "", label: label, type: type + (isOnlyIfAvailable ? "?" : "")), providerIndex: receiverIndex, builtIndex: source.builtIndex)
			return PropertyDeclaration(
				attribute: "@Received(\(arguments.joined(separator: ", ")))",
				label: label,
				type: type + (isOnlyIfAvailable ? "?" : ""),
			)
		}

		/// A received property, mostly of a receivable property. When none is receivable, usually none.
		private mutating func receivedProperty(receiverIndex: Int) -> PropertyDeclaration? {
			let candidates = receivableProperties(receiverIndex: receiverIndex)
			let source: ProvidedProperty
			if !reachableFromRoots.contains(receiverIndex), random.percentChance(25) {
				// A wrapper of a type that is not `@Instantiable`, which nothing in the graph provides, under one label
				// every type shares, with a wrapper chosen for each receive. Only a type no root reaches receives one, so
				// only mocks build its tree: a mock cannot build the wrapper, so it takes each wrapper the label is
				// received as as a parameter of its own. Graphs whose every type a root reaches draw nothing for it.
				source = ProvidedProperty(label: Self.unbuildableWrapperLabel, type: "\(random.element(of: unbuildableWrappers))<\(valueTypeName)>", providerIndex: nil, builtIndex: nil)
			} else if !candidates.isEmpty, random.percentChance(98) {
				source = random.element(of: candidates)
			} else if random.percentChance(70) {
				return nil
			} else {
				// Likely unfulfillable, so the tool's validation is exercised too.
				let target = random.integer(in: 0...(typeCount - 1))
				source = ProvidedProperty(label: "t\(random.integer(in: 0...(typeCount - 1)))", type: typeName(target), providerIndex: nil, builtIndex: target)
			}
			let roll = random.integer(in: 0...99)
			let required = "@Received"
			let onlyIfAvailable = "@Received(onlyIfAvailable: true)"
			let property = if source.isOptional {
				// A required receive of an optional property, an `onlyIfAvailable` one, or a required receive of
				// its non-optional form, which only an `onlyIfAvailable` alias's fulfilling property provides.
				if roll < 50 {
					PropertyDeclaration(attribute: required, label: source.label, type: source.type)
				} else if roll < 80 {
					PropertyDeclaration(attribute: onlyIfAvailable, label: source.label, type: source.type)
				} else {
					PropertyDeclaration(attribute: required, label: source.label, type: String(source.type.dropLast()))
				}
			} else if roll < 60 {
				PropertyDeclaration(attribute: required, label: source.label, type: source.type)
			} else if roll < 90 {
				PropertyDeclaration(attribute: onlyIfAvailable, label: source.label, type: source.type + "?")
			} else {
				// A required receive of the optional form, which only an optional property fulfills.
				PropertyDeclaration(attribute: required, label: source.label, type: source.type + "?")
			}
			if property.attribute == required {
				recordRequirement(of: source, receiverIndex: receiverIndex)
			}
			return property
		}

		/// Now and then, before a property a type instantiates, gives the type properties labeled with the names a
		/// generated mock binds under names of its own for what the types beneath that property receive: a flat
		/// parameter, an override, or a promoted sibling named apart by its type (`t1_S0_T1`), or the wrapper around
		/// the instance of a lazily instantiated dependency the mock cannot build (`lazyValue_lazilyInstantiated`). A
		/// mock root above the type may bind such a name for a receiver built inside the type's builder function, where
		/// the type's property of that name is declared first. No other label holds an underscore, so without these
		/// properties no graph declares a name a mock generates. They build `leafTypeName`, a type with no dependencies
		/// that the graph then declares.
		private mutating func addingPropertiesLabeledAsGeneratedNames(to declarations: [TypeDeclaration]) -> [TypeDeclaration] {
			let declarationsByName = Dictionary(uniqueKeysWithValues: declarations.map { ($0.name, $0) })
			/// The name of the type `property` builds, when it is a type of the graph.
			func builtTypeName(of property: PropertyDeclaration) -> String? {
				let name = Self.builtTypeName(of: property)
				return declarationsByName[name] == nil ? nil : name
			}
			/// The properties received in the subtree of the type named `typeName`, to `depth` types deep.
			func receivedProperties(beneath typeName: String, depth: Int) -> [PropertyDeclaration] {
				guard depth > 0, let declaration = declarationsByName[typeName] else { return [] }
				return declaration.properties.flatMap { property -> [PropertyDeclaration] in
					if property.attribute == "@Received" || property.attribute == "@Received(onlyIfAvailable: true)" {
						[property]
					} else if property.attribute.hasPrefix("@Instantiated"), let builtTypeName = builtTypeName(of: property) {
						receivedProperties(beneath: builtTypeName, depth: depth - 1)
					} else {
						[]
					}
				}
			}
			var declaresLeafType = false
			var declarations = declarations.map { declaration in
				var properties = declaration.properties
				for property in declaration.properties where property.attribute.hasPrefix("@Instantiated") {
					guard let builtTypeName = builtTypeName(of: property) else { continue }
					// Only a property the type does not declare itself reaches the receiver from above the type. The name of
					// a binding named apart by its type is spelled with that type, so the type must be an identifier.
					let receivedProperties = receivedProperties(beneath: builtTypeName, depth: 3).filter { receivedProperty in
						!declaration.properties.contains { $0.label == receivedProperty.label }
							&& (receivedProperty.type.hasPrefix("LazilyInstantiated<") || receivedProperty.type.hasPrefix("SendableLazilyInstantiated<") || !receivedProperty.type.contains("<"))
					}
					guard !receivedProperties.isEmpty, generatedNameRandom.percentChance(50) else { continue }
					for receivedProperty in receivedProperties {
						let receivedType = receivedProperty.type.hasSuffix("?") ? String(receivedProperty.type.dropLast()) : receivedProperty.type
						let suffix = if receivedType.hasPrefix("SendableLazilyInstantiated<") {
							"sendableLazilyInstantiated"
						} else if receivedType.hasPrefix("LazilyInstantiated<") {
							"lazilyInstantiated"
						} else {
							receivedType
						}
						let label = "\(receivedProperty.label)_\(suffix)"
						guard !properties.contains(where: { $0.label == label }) else { continue }
						// Declared before the property that builds the receiver, so that it is bound before the receiver is built.
						properties.insert(
							PropertyDeclaration(attribute: "@Instantiated", label: label, type: leafTypeName),
							at: properties.firstIndex { $0.label == property.label } ?? properties.endIndex,
						)
						declaresLeafType = true
					}
				}
				var declaration = declaration
				declaration.properties = properties
				return declaration
			}
			if declaresLeafType {
				declarations.append(TypeDeclaration(name: leafTypeName, instantiableArguments: [], properties: [], declaresHelperTypes: false))
			}
			return declarations
		}

		/// A type with no dependencies, which `addingPropertiesLabeledAsGeneratedNames` instantiates.
		private var leafTypeName: String {
			"\(prefix)Leaf"
		}

		private static let generatedNameRandomSeedMask: UInt64 = 0x6E616D6573417061

		/// Now and then gives a type that no root reaches a constant of a type that is not `@Instantiable`, as a type
		/// in a module the graph's module does not depend on would be. The mock of a type that builds it cannot build
		/// the constant, so `mock()` takes it as a parameter. Its label is one the graph's other types use, and its
		/// type one of two, so that two such constants can share a label with different types, and a type built around
		/// one can declare its label. A root could not build the constant, so no type a root reaches gets one.
		private mutating func addingDependenciesMocksCannotBuild(to declarations: [TypeDeclaration]) -> [TypeDeclaration] {
			let reachedNames = Self.namesReachedFromRoots(in: declarations)
			return declarations.map { declaration in
				guard !reachedNames.contains(declaration.name),
				      declaration.declaresHelperTypes,
				      declaration.name != sendableBuilderMotifMockedTypeName,
				      unbuildableDependencyRandom.percentChance(40)
				else {
					return declaration
				}
				let label = "t\(unbuildableDependencyRandom.integer(in: 0...(typeCount - 1)))"
				let typeIndex = unbuildableDependencyRandom.integer(in: 0...1)
				guard !declaration.properties.contains(where: { $0.label == label }) else { return declaration }
				unbuildableTypeCount = max(unbuildableTypeCount, typeIndex + 1)
				var declaration = declaration
				declaration.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: label, type: unbuildableTypeName(typeIndex)))
				return declaration
			}
		}

		private func unbuildableTypeName(_ index: Int) -> String {
			"\(prefix)Unbuildable\(index)"
		}

		private static let unbuildableDependencyRandomSeedMask: UInt64 = 0x756E6275696C6461

		/// The names of the types a root reaches through the properties `declarations` instantiate.
		private static func namesReachedFromRoots(in declarations: [TypeDeclaration]) -> Set<String> {
			let declarationsByName = Dictionary(uniqueKeysWithValues: declarations.map { ($0.name, $0) })
			var reachedNames = Set<String>()
			var namesToVisit = declarations.filter { $0.instantiableArguments.contains("isRoot: true") }.map(\.name)
			while let name = namesToVisit.popLast() {
				guard reachedNames.insert(name).inserted, let declaration = declarationsByName[name] else { continue }
				namesToVisit += declaration.properties.filter { $0.attribute.hasPrefix("@Instantiated") }.map(Self.builtTypeName(of:))
			}
			return reachedNames
		}

		/// Now and then gives a receive of a constant that `addingDependenciesMocksCannotBuild` gave a type, of a type that
		/// is not `@Instantiable`, to a type built beneath that owner: a type the owner instantiates or, now and then, one
		/// that type instantiates in turn, through any kind of property. The receive is required, or `onlyIfAvailable` in
		/// its optional form. As in production, a mock passes the receiver the parameter it takes for the constant, which is
		/// named apart where a builder function around the owner declares the constant's label. A type between the owner
		/// and the receiver that declares the label with another type hides the constant, which the tool must reject. No
		/// root reaches the receiver, so no production tree rejects it for receiving a property nothing above it provides.
		/// It is drawn after every other base pass (only the `generateDependencyTree` feature's passes follow it), and
		/// `unbuildableDependencyReceiverRandom` draws only for it, so every other graph is drawn as before.
		///
		/// Now and then, too, an owner with `generateMock: true` receives a type of the graph that no root reaches, that has
		/// no forwarded properties, and that it does not instantiate, which its mock builds beside it. Mostly that type
		/// receives the constant, required or only if available: by value or as its `LazilyInstantiated` (or
		/// `SendableLazilyInstantiated`), which the mock wraps the parameter it takes for the constant to make, since the
		/// owner's own properties are one instance in its mock; or, in a mixed graph, the owner lazily instantiates the
		/// constant as one wrapper and the type receives the other kind, which that parameter cannot make, so the mock takes
		/// the instance as well. Now and then, instead, the type instantiates a type of the graph under the constant's label
		/// and a type it instantiates receives the constant, which that declaration hides, as the tool must report.
		/// `unbuildableDependencySiblingReceiverRandom` draws only for these receives, so a graph without one is drawn as
		/// before.
		private mutating func addingReceiversOfDependenciesMocksCannotBuild(to declarations: [TypeDeclaration]) -> [TypeDeclaration] {
			let reachedNames = Self.namesReachedFromRoots(in: declarations)
			let declarationIndexByName = Dictionary(uniqueKeysWithValues: declarations.enumerated().map { ($1.name, $0) })
			let unbuildableTypeNamePrefix = "\(prefix)Unbuildable"
			/// The indices in `declarations` of the types the declaration at `index` instantiates that may receive the
			/// constant: types no root reaches, other than the type that declares the constant.
			func candidateReceiverIndices(instantiatedBy index: Int, declaringIndex: Int) -> [Int] {
				declarations[index].properties
					.filter { $0.attribute.hasPrefix("@Instantiated") && !$0.type.hasPrefix(unbuildableTypeNamePrefix) }
					.compactMap { declarationIndexByName[Self.builtTypeName(of: $0)] }
					.filter { $0 != declaringIndex && declarations[$0].declaresHelperTypes && !reachedNames.contains(declarations[$0].name) }
			}
			var declarations = declarations
			/// Gives a type beneath the owner at `declaringIndex` a receive of `unbuildableProperty`, now and then.
			func addReceiverBeneathOwner(at declaringIndex: Int, of unbuildableProperty: PropertyDeclaration) {
				guard unbuildableDependencyReceiverRandom.percentChance(60) else { return }
				let childIndices = candidateReceiverIndices(instantiatedBy: declaringIndex, declaringIndex: declaringIndex)
				guard !childIndices.isEmpty else { return }
				var receiverIndex = unbuildableDependencyReceiverRandom.element(of: childIndices)
				if unbuildableDependencyReceiverRandom.percentChance(30) {
					let grandchildIndices = candidateReceiverIndices(instantiatedBy: receiverIndex, declaringIndex: declaringIndex)
					if !grandchildIndices.isEmpty {
						receiverIndex = unbuildableDependencyReceiverRandom.element(of: grandchildIndices)
					}
				}
				let isOnlyIfAvailable = unbuildableDependencyReceiverRandom.percentChance(30)
				guard !declarations[receiverIndex].properties.contains(where: { $0.label == unbuildableProperty.label }) else { return }
				declarations[receiverIndex].properties.append(PropertyDeclaration(
					attribute: isOnlyIfAvailable ? "@Received(onlyIfAvailable: true)" : "@Received",
					label: unbuildableProperty.label,
					type: isOnlyIfAvailable ? unbuildableProperty.type + "?" : unbuildableProperty.type,
				))
			}
			/// Gives the owner at `declaringIndex` a receive of a type of the graph that receives `unbuildableProperty`,
			/// now and then.
			func addReceiverBesideOwner(at declaringIndex: Int, of unbuildableProperty: PropertyDeclaration) {
				guard declarations[declaringIndex].instantiableArguments.contains("generateMock: true"),
				      unbuildableDependencySiblingReceiverRandom.percentChance(50)
				else { return }
				let siblingTypeIndices = (0..<typeCount).filter { typeIndex in
					guard let index = declarationIndexByName[typeName(typeIndex)] else { return false }
					return index != declaringIndex
						&& forwardedProperties[typeIndex] == nil
						&& declarations[index].declaresHelperTypes
						&& !reachedNames.contains(declarations[index].name)
						&& !declarations[index].properties.contains { $0.label == unbuildableProperty.label }
						&& !declarations[declaringIndex].properties.contains {
							$0.label == "t\(typeIndex)" || ($0.attribute.hasPrefix("@Instantiated") && Self.builtTypeName(of: $0) == typeName(typeIndex))
						}
				}
				guard !siblingTypeIndices.isEmpty else { return }
				let siblingTypeIndex = unbuildableDependencySiblingReceiverRandom.element(of: siblingTypeIndices)
				let siblingIndex = declarationIndexByName[typeName(siblingTypeIndex)]!
				let isOnlyIfAvailable = unbuildableDependencySiblingReceiverRandom.percentChance(30)
				let receiveAttribute = isOnlyIfAvailable ? "@Received(onlyIfAvailable: true)" : "@Received"
				let variantRoll = unbuildableDependencySiblingReceiverRandom.integer(in: 0...99)
				if variantRoll < 25 {
					// The sibling instantiates a buildable type under the constant's label, and a type it instantiates
					// receives the constant: that declaration hides it there, which the tool must reject.
					let hidingTypeIndex = unbuildableDependencySiblingReceiverRandom.integer(in: 0...(typeCount - 1))
					let receiverIndices = declarations[siblingIndex].properties
						.filter { $0.attribute.hasPrefix("@Instantiated") }
						.compactMap { declarationIndexByName[Self.builtTypeName(of: $0)] }
						.filter { $0 != siblingIndex && declarations[$0].declaresHelperTypes && !declarations[$0].properties.contains { $0.label == unbuildableProperty.label } }
					guard forwardedProperties[hidingTypeIndex] == nil, !receiverIndices.isEmpty else { return }
					let receiverIndex = unbuildableDependencySiblingReceiverRandom.element(of: receiverIndices)
					declarations[declaringIndex].properties.append(PropertyDeclaration(attribute: "@Received", label: "t\(siblingTypeIndex)", type: typeName(siblingTypeIndex)))
					declarations[siblingIndex].properties.append(PropertyDeclaration(attribute: "@Instantiated", label: unbuildableProperty.label, type: typeName(hidingTypeIndex)))
					declarations[receiverIndex].properties.append(PropertyDeclaration(
						attribute: receiveAttribute,
						label: unbuildableProperty.label,
						type: isOnlyIfAvailable ? unbuildableProperty.type + "?" : unbuildableProperty.type,
					))
				} else if variantRoll < 50, sendability == .mixed {
					// The owner lazily instantiates the constant as one wrapper and the sibling receives the other kind, which
					// the parameter the mock takes for the owner's wrapper cannot make.
					let ownerWrapperIsSendable = unbuildableDependencySiblingReceiverRandom.percentChance(50)
					guard let unbuildablePropertyIndex = declarations[declaringIndex].properties.firstIndex(where: { $0.label == unbuildableProperty.label }) else { return }
					declarations[declaringIndex].properties[unbuildablePropertyIndex] = PropertyDeclaration(
						attribute: unbuildableProperty.attribute,
						label: unbuildableProperty.label,
						type: "\(lazilyInstantiatedWrapper(isSendable: ownerWrapperIsSendable))<\(unbuildableProperty.type)>",
					)
					let receivedType = "\(lazilyInstantiatedWrapper(isSendable: !ownerWrapperIsSendable))<\(unbuildableProperty.type)>"
					declarations[declaringIndex].properties.append(PropertyDeclaration(attribute: "@Received", label: "t\(siblingTypeIndex)", type: typeName(siblingTypeIndex)))
					declarations[siblingIndex].properties.append(PropertyDeclaration(
						attribute: receiveAttribute,
						label: unbuildableProperty.label,
						type: isOnlyIfAvailable ? receivedType + "?" : receivedType,
					))
				} else {
					let wrapper = switch sendability {
					case .nonSendable:
						"LazilyInstantiated"
					case .sendable:
						"SendableLazilyInstantiated"
					case .mixed:
						unbuildableDependencySiblingReceiverRandom.percentChance(50) ? "SendableLazilyInstantiated" : "LazilyInstantiated"
					}
					let receivedType = unbuildableDependencySiblingReceiverRandom.percentChance(50) ? "\(wrapper)<\(unbuildableProperty.type)>" : unbuildableProperty.type
					declarations[declaringIndex].properties.append(PropertyDeclaration(attribute: "@Received", label: "t\(siblingTypeIndex)", type: typeName(siblingTypeIndex)))
					declarations[siblingIndex].properties.append(PropertyDeclaration(
						attribute: receiveAttribute,
						label: unbuildableProperty.label,
						type: isOnlyIfAvailable ? receivedType + "?" : receivedType,
					))
				}
			}
			for declaringIndex in declarations.indices {
				guard let unbuildableProperty = declarations[declaringIndex].properties.first(where: {
					$0.attribute == "@Instantiated" && $0.type.hasPrefix(unbuildableTypeNamePrefix)
				}) else { continue }
				addReceiverBeneathOwner(at: declaringIndex, of: unbuildableProperty)
				addReceiverBesideOwner(at: declaringIndex, of: unbuildableProperty)
			}
			return declarations
		}

		private static let unbuildableDependencyReceiverRandomSeedMask: UInt64 = 0x756E627265636569
		private static let unbuildableDependencySiblingReceiverRandomSeedMask: UInt64 = 0x756E627369626C69

		/// Now and then adds a chain of aliases through an `onlyIfAvailable` alias to a type of the graph: a second
		/// alias, required or `onlyIfAvailable`, of an `onlyIfAvailable` alias the type declares (or is given here, of a
		/// property provided above it), on the same type or on a type it instantiates; now and then a third alias of
		/// the second; and, usually, a receive of the last alias, required or `onlyIfAvailable`, on a type the alias's
		/// type instantiates. A receiver that requires the last alias needs every alias in the chain created, so the
		/// first alias's fulfilling property must be built before the receiver, which the rest of the graph can make
		/// impossible. `aliasProperty` never aliases an optional property, so no pass before this one draws such a
		/// chain, and only `addingSiblingAliasChains`, which runs after it, draws one too. `aliasChainRandom` draws only
		/// for this pass, so every other graph is drawn as before.
		private mutating func addingAliasChains(to declarations: [TypeDeclaration]) -> [TypeDeclaration] {
			guard aliasChainRandom.percentChance(10) else { return declarations }
			var declarations = declarations
			let graphTypeNames = Set((0..<typeCount).map(typeName))
			/// The index in `declarations` of a type of the graph that the declaration at `index` instantiates, other
			/// than itself, chosen at random; `nil` when it instantiates none.
			func instantiatedDeclarationIndex(of index: Int) -> Int? {
				let candidates = declarations[index].properties
					.filter { $0.attribute.hasPrefix("@Instantiated") }
					.map(Self.builtTypeName(of:))
					.filter { $0 != declarations[index].name && graphTypeNames.contains($0) }
					.compactMap { name in declarations.firstIndex { $0.name == name } }
				guard !candidates.isEmpty else { return nil }
				return aliasChainRandom.element(of: candidates)
			}
			let hostTypeIndex = aliasChainRandom.integer(in: 0...(typeCount - 1))
			guard let hostIndex = declarations.firstIndex(where: { $0.name == typeName(hostTypeIndex) }) else { return declarations }
			// The first alias: an `onlyIfAvailable` alias the host declares, or one it is given of a property it can
			// receive, chosen as `aliasProperty` chooses.
			let firstAlias: PropertyDeclaration
			if let declaredAlias = declarations[hostIndex].properties.first(where: {
				$0.attribute.hasPrefix("@Received(fulfilledByDependencyNamed:") && $0.attribute.contains("onlyIfAvailable: true")
			}) {
				firstAlias = declaredAlias
			} else {
				let candidates = propertiesProvidedAboveEveryPath(to: hostTypeIndex).filter { candidate in
					!candidate.isOptional
						&& !candidate.type.contains("(")
						&& !candidate.type.contains("ErasedInstantiator<")
						&& provided.allSatisfy { $0.label != candidate.label || $0.type == candidate.type }
						&& !declarations[hostIndex].properties.contains { $0.label == candidate.label + "Alias" }
				}
				guard !candidates.isEmpty else { return declarations }
				let source = aliasChainRandom.element(of: candidates)
				firstAlias = PropertyDeclaration(
					attribute: "@Received(fulfilledByDependencyNamed: \"\(source.label)\", ofType: \(source.type).self, onlyIfAvailable: true)",
					label: source.label + "Alias",
					type: source.type + "?",
				)
				declarations[hostIndex].properties.append(firstAlias)
			}
			// Then one alias of it, and now and then one of that, each on the type declaring what it renames or on a
			// type that type instantiates.
			var aliasDeclarationIndex = hostIndex
			var alias = firstAlias
			for _ in 0..<(aliasChainRandom.percentChance(25) ? 2 : 1) {
				let declaringIndex = aliasChainRandom.percentChance(50)
					? aliasDeclarationIndex
					: instantiatedDeclarationIndex(of: aliasDeclarationIndex) ?? aliasDeclarationIndex
				let isOnlyIfAvailable = aliasChainRandom.percentChance(50)
				let label = alias.label + "Alias"
				guard !declarations[declaringIndex].properties.contains(where: { $0.label == label }) else { break }
				let nextAlias = PropertyDeclaration(
					attribute: "@Received(fulfilledByDependencyNamed: \"\(alias.label)\", ofType: \(alias.type).self\(isOnlyIfAvailable ? ", onlyIfAvailable: true" : ""))",
					label: label,
					type: alias.type,
				)
				declarations[declaringIndex].properties.append(nextAlias)
				aliasDeclarationIndex = declaringIndex
				alias = nextAlias
			}
			// Usually, a receive of the last alias on a type the alias's type instantiates.
			if aliasChainRandom.percentChance(80),
			   let receiverIndex = instantiatedDeclarationIndex(of: aliasDeclarationIndex),
			   !declarations[receiverIndex].properties.contains(where: { $0.label == alias.label })
			{
				declarations[receiverIndex].properties.append(PropertyDeclaration(
					attribute: aliasChainRandom.percentChance(70) ? "@Received" : "@Received(onlyIfAvailable: true)",
					label: alias.label,
					type: alias.type,
				))
			}
			return declarations
		}

		private static let aliasChainRandomSeedMask: UInt64 = 0x616C696173436861

		/// Now and then adds a chain of aliases through an `onlyIfAvailable` alias of one sibling property beneath the
		/// other, and usually makes the first sibling's type receive the other. A scope – a root, or a type on every
		/// path to the chain – instantiates `x: X`, a constant of a type of the graph, and another type `B` without an
		/// instantiator. `B`, or a type a few such steps beneath it that each step dominates, declares an
		/// `onlyIfAvailable` alias of `x`, mostly spelled with its optional form (`ofType: X?.self`) and otherwise with
		/// `X.self`; now and then one or two aliases of that alias follow, each required or `onlyIfAvailable`, on the
		/// same type or on a type beneath it, so that the chain crosses scopes; usually a type beneath the last alias's
		/// type receives the alias, mostly required, or a required alias of it on the same type does instead; and
		/// usually `X` receives `b`. A type beneath another is a child it dominates – counting every root's properties,
		/// including one the other roots lack – or, where it has none, which is most often, a new type that only it
		/// instantiates (`Link0`, `Link1`, …), so that no receiver is rejected merely because another path from a root
		/// reaches it without the alias. A receiver that requires the chain needs every alias created, so
		/// `x` built before `b`, while `X` receiving `b` needs `b` built first: SafeDI must reject the graph through the
		/// chain. Without the receive of `b`, the chain must be built after `x`, which the compiled output shows.
		/// `addingAliasChains` never draws a source built around its host, so no other pass draws the cycle, and
		/// `siblingAliasChainRandom` draws only for this one, so every other graph is drawn as before.
		private mutating func addingSiblingAliasChains(to declarations: [TypeDeclaration]) -> [TypeDeclaration] {
			guard siblingAliasChainRandom.percentChance(30) else { return declarations }
			var declarations = declarations
			let graphTypeIndexByName = Dictionary(uniqueKeysWithValues: (0..<typeCount).map { (typeName($0), $0) })
			let declarationIndexByName = Dictionary(uniqueKeysWithValues: declarations.enumerated().map { ($1.name, $0) })
			/// The index in `declarations` of the type of the graph `property` instantiates, or `nil` when it instantiates
			/// another type or `onlyWithoutInstantiator` and it instantiates through an instantiator.
			func instantiatedDeclarationIndex(of property: PropertyDeclaration, onlyWithoutInstantiator: Bool) -> Int? {
				guard property.attribute.hasPrefix("@Instantiated"),
				      !(onlyWithoutInstantiator && property.type.contains("Instantiator<")),
				      let index = graphTypeIndexByName[Self.builtTypeName(of: property)]
				else { return nil }
				return declarationIndexByName[typeName(index)]
			}
			/// Whether the declaration at `start` instantiates, through any chain of properties, the one at `destination`.
			func instantiates(_ destination: Int, from start: Int) -> Bool {
				var visited = Set<Int>()
				var stack = declarations[start].properties.compactMap { instantiatedDeclarationIndex(of: $0, onlyWithoutInstantiator: false) }
				while let current = stack.popLast() {
					guard current != destination else { return true }
					guard visited.insert(current).inserted else { continue }
					stack += declarations[current].properties.compactMap { instantiatedDeclarationIndex(of: $0, onlyWithoutInstantiator: false) }
				}
				return false
			}
			func declaresProperty(labeled label: String, at index: Int) -> Bool {
				declarations[index].properties.contains { $0.label == label }
			}
			// Which declaration is on every path to which, read from the declarations rather than from `dominators`:
			// a root may declare a property the other roots do not, which is not among the graph's `edges`. No pass
			// before this one instantiates a type of the graph, and the links this one adds are not types of the graph.
			let rootIndices = declarations.indices.filter { declarations[$0].instantiableArguments.contains("isRoot: true") }
			let childIndicesByDeclaration = declarations.map { declaration in
				declaration.properties.compactMap { instantiatedDeclarationIndex(of: $0, onlyWithoutInstantiator: false) }
			}
			/// The declarations a root reaches without passing through the one at `excludedIndex`.
			func reachableFromRoots(excluding excludedIndex: Int?) -> Set<Int> {
				var reached = Set<Int>()
				var stack = rootIndices.flatMap { childIndicesByDeclaration[$0] }.filter { $0 != excludedIndex }
				while let current = stack.popLast() {
					guard reached.insert(current).inserted else { continue }
					stack += childIndicesByDeclaration[current].filter { $0 != excludedIndex }
				}
				return reached
			}
			let reachedFromRoots = reachableFromRoots(excluding: nil)
			/// Whether the declaration at `providerIndex` is on every path from a root to the type at `index`, so that
			/// what it provides is available wherever the type is built: it is a root, whose properties every root
			/// declares here, or it dominates the type, or no root reaches the type, which only mocks then build.
			func isOnEveryPath(from providerIndex: Int, to index: Int) -> Bool {
				guard !rootIndices.contains(providerIndex), reachedFromRoots.contains(index) else { return true }
				return providerIndex == index || !reachableFromRoots(excluding: providerIndex).contains(index)
			}
			/// The types of the graph the declaration at `index` instantiates, other than itself, that it is on every
			/// path to, so that a receiver among them is handed what the declaration provides wherever it is built.
			func dominatedChildren(of index: Int, onlyWithoutInstantiator: Bool) -> [Int] {
				declarations[index].properties
					.compactMap { instantiatedDeclarationIndex(of: $0, onlyWithoutInstantiator: onlyWithoutInstantiator) }
					.filter { $0 != index && isOnEveryPath(from: index, to: $0) }
			}
			// The siblings: `x`, a constant whose label names its type, or its optional form, throughout the graph, as
			// `aliasProperty` requires of a label it aliases, so that the compiler agrees with `ofType:`; and `b`, built
			// without an instantiator, on every path to which the scope lies, and whose tree does not instantiate `X`.
			// A root's are the ones every root declares.
			struct Siblings {
				let scopeIndex: Int
				let x: PropertyDeclaration
				let b: PropertyDeclaration
			}
			var candidates = [Siblings]()
			for (scopeIndex, scope) in declarations.enumerated() where scope.instantiableArguments.contains("isRoot: true") || graphTypeIndexByName[scope.name] != nil {
				func isDeclaredByEveryRoot(_ property: PropertyDeclaration) -> Bool {
					rootIndices.allSatisfy { rootIndex in declarations[rootIndex].properties.contains { $0.label == property.label && $0.type == property.type } }
				}
				let isRoot = rootIndices.contains(scopeIndex)
				for x in scope.properties where x.attribute == "@Instantiated" && graphTypeIndexByName[x.type] != nil && (!isRoot || isDeclaredByEveryRoot(x)) {
					guard declarations.allSatisfy({ $0.properties.allSatisfy { $0.label != x.label || $0.type == x.type || $0.type == x.type + "?" } }),
					      let xDeclarationIndex = declarationIndexByName[x.type]
					else { continue }
					for b in scope.properties where b.label != x.label && (!isRoot || isDeclaredByEveryRoot(b)) {
						guard let bDeclarationIndex = instantiatedDeclarationIndex(of: b, onlyWithoutInstantiator: true),
						      bDeclarationIndex != xDeclarationIndex,
						      isOnEveryPath(from: scopeIndex, to: bDeclarationIndex),
						      !instantiates(xDeclarationIndex, from: bDeclarationIndex)
						else { continue }
						candidates.append(Siblings(scopeIndex: scopeIndex, x: x, b: b))
					}
				}
			}
			guard !candidates.isEmpty else { return declarations }
			let siblings = siblingAliasChainRandom.element(of: candidates)
			// The host of the first alias: `B`, or a type a few steps beneath it that each step is on every path to,
			// none of which declares `x`, so that the alias is fulfilled by the scope's `x` wherever the host is built.
			var hostIndex = declarationIndexByName[Self.builtTypeName(of: siblings.b)]!
			var hostPath = [hostIndex]
			for _ in 0..<siblingAliasChainRandom.integer(in: 0...2) {
				let children = dominatedChildren(of: hostIndex, onlyWithoutInstantiator: true)
				guard !children.isEmpty else { break }
				hostIndex = siblingAliasChainRandom.element(of: children)
				hostPath.append(hostIndex)
			}
			let firstAliasLabel = siblings.x.label + "Alias"
			guard !hostPath.contains(where: { declaresProperty(labeled: siblings.x.label, at: $0) }),
			      !declaresProperty(labeled: firstAliasLabel, at: hostIndex)
			else { return declarations }
			let spellsOptionalForm = siblingAliasChainRandom.percentChance(60)
			var alias = PropertyDeclaration(
				attribute: "@Received(fulfilledByDependencyNamed: \"\(siblings.x.label)\", ofType: \(siblings.x.type)\(spellsOptionalForm ? "?" : "").self, onlyIfAvailable: true)",
				label: firstAliasLabel,
				type: siblings.x.type + "?",
			)
			declarations[hostIndex].properties.append(alias)
			var aliasDeclarationIndex = hostIndex
			/// Most types of these graphs dominate none of the types they instantiate, so a step beneath a type that has
			/// no such child takes a new type, `Link<n>`, that only the type at `parentIndex` instantiates.
			var linkCount = 0
			func appendLink(beneath parentIndex: Int) -> Int {
				let linkTypeName = "\(prefix)Link\(linkCount)"
				declarations[parentIndex].properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "link\(linkCount)", type: linkTypeName))
				declarations.append(TypeDeclaration(name: linkTypeName, instantiableArguments: [], properties: [], declaresHelperTypes: false))
				linkCount += 1
				return declarations.count - 1
			}
			// Then, now and then, one or two aliases of it, each on the type declaring what it renames or on a type beneath
			// it: one of its dominated children or, where it has none, a new link, so that a chain crosses scopes as often
			// as it stays on one.
			for _ in 0..<siblingAliasChainRandom.integer(in: 0...2) {
				let declaringIndex: Int
				if siblingAliasChainRandom.percentChance(50) {
					declaringIndex = aliasDeclarationIndex
				} else {
					let children = dominatedChildren(of: aliasDeclarationIndex, onlyWithoutInstantiator: false)
					declaringIndex = children.isEmpty ? appendLink(beneath: aliasDeclarationIndex) : siblingAliasChainRandom.element(of: children)
				}
				let isOnlyIfAvailable = siblingAliasChainRandom.percentChance(50)
				let label = alias.label + "Alias"
				guard !declaresProperty(labeled: label, at: declaringIndex) else { break }
				let nextAlias = PropertyDeclaration(
					attribute: "@Received(fulfilledByDependencyNamed: \"\(alias.label)\", ofType: \(alias.type).self\(isOnlyIfAvailable ? ", onlyIfAvailable: true" : ""))",
					label: label,
					type: alias.type,
				)
				declarations[declaringIndex].properties.append(nextAlias)
				aliasDeclarationIndex = declaringIndex
				alias = nextAlias
			}
			// Usually, a receive of the last alias, mostly required, on one of its type's dominated children or, where it
			// has none, half the time on a new link; otherwise a required alias of the last alias on the same type, which
			// is created whether or not anything receives it.
			if siblingAliasChainRandom.percentChance(85) {
				let receivers = dominatedChildren(of: aliasDeclarationIndex, onlyWithoutInstantiator: false)
					.filter { !declaresProperty(labeled: alias.label, at: $0) }
				let requiredAliasLabel = alias.label + "Alias"
				let receiverIndex: Int? = if !receivers.isEmpty {
					siblingAliasChainRandom.element(of: receivers)
				} else if siblingAliasChainRandom.percentChance(50) {
					appendLink(beneath: aliasDeclarationIndex)
				} else {
					nil
				}
				if let receiverIndex {
					declarations[receiverIndex].properties.append(PropertyDeclaration(
						attribute: siblingAliasChainRandom.percentChance(80) ? "@Received" : "@Received(onlyIfAvailable: true)",
						label: alias.label,
						type: alias.type,
					))
				} else if alias.attribute.contains("onlyIfAvailable: true"), !declaresProperty(labeled: requiredAliasLabel, at: aliasDeclarationIndex) {
					declarations[aliasDeclarationIndex].properties.append(PropertyDeclaration(
						attribute: "@Received(fulfilledByDependencyNamed: \"\(alias.label)\", ofType: \(alias.type).self)",
						label: requiredAliasLabel,
						type: alias.type,
					))
				}
			}
			// Usually, `X` receives `b`, so that `b` must be built before `x`, where the scope is on every path to `X`.
			let xDeclarationIndex = declarationIndexByName[siblings.x.type]!
			if siblingAliasChainRandom.percentChance(70),
			   isOnEveryPath(from: siblings.scopeIndex, to: xDeclarationIndex),
			   !declaresProperty(labeled: siblings.b.label, at: xDeclarationIndex)
			{
				declarations[xDeclarationIndex].properties.append(PropertyDeclaration(attribute: "@Received", label: siblings.b.label, type: siblings.b.type))
			}
			return declarations
		}

		private static let siblingAliasChainRandomSeedMask: UInt64 = 0x7369626C696E6741

		/// The name of the type `property` builds: its `fulfilledByType:`, the generic of its wrapper, or its type.
		private static func builtTypeName(of property: PropertyDeclaration) -> String {
			if let fulfilledByTypeRange = property.attribute.range(of: "fulfilledByType: \"") {
				String(property.attribute[fulfilledByTypeRange.upperBound...].prefix { $0 != "\"" })
			} else if let genericStart = property.type.firstIndex(of: "<"), let genericEnd = property.type.lastIndex(of: ">") {
				String(property.type[property.type.index(after: genericStart)..<genericEnd])
			} else {
				property.type
			}
		}

		// MARK: Seam

		/// With the `generateDependencyTree` feature on, marks one type a root reaches as a seam – a type whose tree
		/// SafeDI generates in an initializer of its own, which the trees reaching it call – drawn among the types
		/// with an `@Instantiated` child, and gives its tree the shapes a seam's initializer must pass: a child's
		/// receive of a property provided above every path to the child, required or `onlyIfAvailable`; a rename of
		/// one on the seam or on a child; a rename above the seam that a child it is on every path to receives by
		/// the new label; the forms of one label a seam's tree can receive a lazily instantiated property in – the
		/// required wrapper, with a by-value form beneath it on a second child, or on a `SeamLink` beneath the
		/// receiver when the seam has one child; the instance by value, which the caller passes as `.instance`; the
		/// optional wrapper only if available, of the kind the
		/// graph holds or, in a mixed graph, of the other kind, which the caller passes `nil`; and, in a known share,
		/// a by-value form beside the optional wrapper, which the seam rejects as a label collision – a child's
		/// `onlyIfAvailable` receive of a wrapper of a property the caller holds by value, which the caller passes
		/// `nil`; and, a quarter of the time, a second seam beneath the first. Where no plain property is provided
		/// above every path to a drawn child, or above the seam for a rename on it, every root instantiates a
		/// `SeamShared` type under one label, so a receive of it can always be drawn, and where no wrapper is
		/// provided above, every root instantiates one of `SeamShared` under `seamLazy`. `seamRandom` draws only for
		/// this pass, so every graph without the feature is drawn as before.
		private mutating func addingSeam(to declarations: [TypeDeclaration]) -> [TypeDeclaration] {
			guard features.contains(.generateDependencyTree) else { return declarations }
			var declarations = declarations
			func childTypeIndices(of index: Int) -> [Int] {
				Set(edges.filter { $0.sourceIndex == index }.map(\.targetIndex)).subtracting([index]).sorted()
			}
			let rootIndices = declarations.indices.filter { declarations[$0].instantiableArguments.contains("isRoot: true") }
			var candidates = reachableFromRoots.filter { !childTypeIndices(of: $0).isEmpty }.sorted()
			/// The declarations of the seam's children, by index in `declarations`: a child the graph's edges name, or
			/// the `SeamChild` type a leaf is given when no reachable type has a child.
			var childDeclarationIndices = [Int]()
			if candidates.isEmpty {
				guard let leaf = reachableFromRoots.sorted().first else { return declarations }
				// Every reachable type is a leaf: one gains a child to build, so that it has a tree of its own.
				let childName = "\(prefix)SeamChild"
				let conformances = sendability == .mixed ? ["@unchecked Sendable"] : []
				declarations.append(TypeDeclaration(name: childName, instantiableArguments: [], properties: [], declaresHelperTypes: false, additionalConformances: conformances))
				if let leafIndex = declarations.firstIndex(where: { $0.name == typeName(leaf) }) {
					declarations[leafIndex].properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "seamChild", type: childName))
				}
				childDeclarationIndices = [declarations.count - 1]
				candidates = [leaf]
			}
			let seamTypeIndex = seamRandom.element(of: candidates)
			func markSeam(_ typeIndex: Int) {
				guard let index = declarations.firstIndex(where: { $0.name == typeName(typeIndex) }),
				      !declarations[index].instantiableArguments.contains("generateDependencyTree: true")
				else { return }
				// The macro's arguments are ordered: `generateDependencyTree` precedes `generateMock`.
				declarations[index].instantiableArguments.insert("generateDependencyTree: true", at: 0)
			}
			markSeam(seamTypeIndex)
			if childDeclarationIndices.isEmpty {
				childDeclarationIndices = childTypeIndices(of: seamTypeIndex).compactMap { child in declarations.firstIndex { $0.name == typeName(child) } }
			}
			func add(_ property: PropertyDeclaration, toDeclarationAt index: Int) {
				guard !declarations[index].properties.contains(where: { $0.label == property.label }) else { return }
				declarations[index].properties.append(property)
			}
			func add(_ property: PropertyDeclaration, toTypeAt typeIndex: Int) {
				guard let index = declarations.firstIndex(where: { $0.name == typeName(typeIndex) }) else { return }
				add(property, toDeclarationAt: index)
			}
			/// The index of the type the declaration at `index` declares, or `nil` for the synthesized `SeamChild`,
			/// which only the seam reaches.
			func typeIndex(ofDeclarationAt index: Int) -> Int? {
				childTypeIndices(of: seamTypeIndex).first { typeName($0) == declarations[index].name }
			}
			/// Whether `candidate` is provided above every path to the child declared at `childIndex`: a receive drawn
			/// on the child must resolve on each, since another root's path can reach the child without the seam.
			func isProvidedAboveEveryPath(_ candidate: ProvidedProperty, toChildAt childIndex: Int) -> Bool {
				guard let childTypeIndex = typeIndex(ofDeclarationAt: childIndex) else { return true }
				return propertiesProvidedAboveEveryPath(to: childTypeIndex).contains { $0.label == candidate.label && $0.type == candidate.type }
			}
			/// The properties provided above every path to the seam that a receive or rename can name plainly: not
			/// optional, not a wrapper, and of one type throughout the graph, as `aliasProperty` requires of what it
			/// aliases; the seam itself provides none of them.
			let plainSources = propertiesProvidedAboveEveryPath(to: seamTypeIndex).filter { candidate in
				candidate.providerIndex != seamTypeIndex
					&& !candidate.isOptional
					&& !candidate.type.contains("<")
					&& !candidate.type.contains("(")
					&& provided.allSatisfy { $0.label != candidate.label || $0.type == candidate.type }
			}
			let sharedTypeName = "\(prefix)SeamShared"
			let sharedSource = ProvidedProperty(label: "seamShared", type: sharedTypeName, providerIndex: nil, builtIndex: nil)
			/// Declares the `SeamShared` type, once, and has every root instantiate it under `seamShared`: a receive
			/// of it beneath the seam passes through the seam whatever the graph provides above. Its triggers are
			/// listed on `GraphFuzzerSeamDrawFeature.synthesizedSharedProvider`.
			func ensureSharedProvider() {
				guard !declarations.contains(where: { $0.name == sharedTypeName }) else { return }
				// Conforming as the graph's other types do, so a `@Sendable` builder can capture it where they can: a
				// mixed graph's types are `@unchecked Sendable`, and `source(of:)` marks a type without helper types so
				// only in an all-`Sendable` graph.
				let conformances = sendability == .mixed ? ["@unchecked Sendable"] : []
				declarations.append(TypeDeclaration(name: sharedTypeName, instantiableArguments: [], properties: [], declaresHelperTypes: false, additionalConformances: conformances))
				for rootIndex in rootIndices {
					declarations[rootIndex].properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "seamShared", type: sharedTypeName))
				}
			}
			/// A plain source provided above every path to the child declared at `childIndex`, drawing `SeamShared`
			/// where the graph provides none.
			func plainSource(forChildAt childIndex: Int) -> ProvidedProperty {
				let childSources = plainSources.filter { isProvidedAboveEveryPath($0, toChildAt: childIndex) }
				guard !childSources.isEmpty else {
					ensureSharedProvider()
					return sharedSource
				}
				return seamRandom.element(of: childSources)
			}
			/// Declares the `SeamHeld` type, once, and has every root instantiate it by value under `seamHeld`.
			func ensureHeldProvider() {
				let heldTypeName = "\(prefix)SeamHeld"
				guard !declarations.contains(where: { $0.name == heldTypeName }) else { return }
				let conformances = sendability == .mixed ? ["@unchecked Sendable"] : []
				declarations.append(TypeDeclaration(name: heldTypeName, instantiableArguments: [], properties: [], declaresHelperTypes: false, additionalConformances: conformances))
				for rootIndex in rootIndices {
					declarations[rootIndex].properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "seamHeld", type: heldTypeName))
				}
			}
			/// A new type, `SeamLink`, that only the declaration at `parentIndex` instantiates, beneath which a by-value
			/// form of a wrapper the parent receives can be drawn when the seam has no second child.
			func appendSeamLink(beneath parentIndex: Int) -> Int {
				let linkTypeName = "\(prefix)SeamLink"
				let conformances = sendability == .mixed ? ["@unchecked Sendable"] : []
				declarations[parentIndex].properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "seamLink", type: linkTypeName))
				declarations.append(TypeDeclaration(name: linkTypeName, instantiableArguments: [], properties: [], declaresHelperTypes: false, additionalConformances: conformances))
				return declarations.count - 1
			}
			let children = childDeclarationIndices
			// A child's receive of a property provided above the seam: the initializer's pass-through.
			if seamRandom.percentChance(85) {
				let child = seamRandom.element(of: children)
				let source = plainSource(forChildAt: child)
				if seamRandom.percentChance(50) {
					add(PropertyDeclaration(attribute: "@Received(onlyIfAvailable: true)", label: source.label, type: source.type + "?"), toDeclarationAt: child)
				} else {
					add(PropertyDeclaration(attribute: "@Received", label: source.label, type: source.type), toDeclarationAt: child)
				}
			}
			// A rename of a property provided above, on the seam or on a child: the parameter is the property before it.
			if seamRandom.percentChance(40) {
				let hostDeclarationIndex = seamRandom.percentChance(50)
					? declarations.firstIndex { $0.name == typeName(seamTypeIndex) }
					: seamRandom.element(of: children)
				if let hostDeclarationIndex {
					let source = hostDeclarationIndex == declarations.firstIndex(where: { $0.name == typeName(seamTypeIndex) })
						? (plainSources.isEmpty ? { ensureSharedProvider(); return sharedSource }() : seamRandom.element(of: plainSources))
						: plainSource(forChildAt: hostDeclarationIndex)
					add(PropertyDeclaration(
						attribute: "@Received(fulfilledByDependencyNamed: \"\(source.label)\", ofType: \(source.type).self)",
						label: "\(source.label)Seam",
						type: source.type,
					), toDeclarationAt: hostDeclarationIndex)
				}
			}
			// A rename above the seam, received by its new label beneath it by a child the renaming type is on every
			// path to: the parameter is the renamed property. Which declaration is on every path to which is read
			// from the declarations rather than from `dominators`, which a root's extra property, not among the
			// graph's `edges`, is missing from; the source must be provided above every path to the renaming type.
			let declarationIndexByName = Dictionary(uniqueKeysWithValues: declarations.enumerated().map { ($1.name, $0) })
			let rootDeclarationIndices = Set(rootIndices)
			let childIndicesByDeclaration = declarations.map { declaration in
				declaration.properties.compactMap { property -> Int? in
					guard property.attribute.hasPrefix("@Instantiated") else { return nil }
					return declarationIndexByName[Self.builtTypeName(of: property)]
				}
			}
			func declarationsReachableFromRoots(excluding excludedIndex: Int?) -> Set<Int> {
				var reached = Set<Int>()
				var stack = rootIndices.flatMap { childIndicesByDeclaration[$0] }.filter { $0 != excludedIndex }
				while let current = stack.popLast() {
					guard reached.insert(current).inserted else { continue }
					stack += childIndicesByDeclaration[current].filter { $0 != excludedIndex }
				}
				return reached
			}
			let declarationsReachedFromRoots = declarationsReachableFromRoots(excluding: nil)
			/// Whether the declaration at `providerIndex` is on every path from a root to the declaration at `index`.
			func isOnEveryPath(from providerIndex: Int, to index: Int) -> Bool {
				guard !rootDeclarationIndices.contains(providerIndex), declarationsReachedFromRoots.contains(index) else { return true }
				return providerIndex == index || !declarationsReachableFromRoots(excluding: providerIndex).contains(index)
			}
			let seamDeclarationIndex = declarationIndexByName[typeName(seamTypeIndex)]!
			let declarationsAboveSeam = (0..<typeCount).filter { typeIndex in
				guard typeIndex != seamTypeIndex, let index = declarationIndexByName[typeName(typeIndex)] else { return false }
				return declarationsReachedFromRoots.contains(index) && isOnEveryPath(from: index, to: seamDeclarationIndex)
			}
			if seamRandom.percentChance(40), !declarationsAboveSeam.isEmpty {
				let above = seamRandom.element(of: declarationsAboveSeam)
				let aboveDeclarationIndex = declarationIndexByName[typeName(above)]!
				let receivers = children.filter { isOnEveryPath(from: aboveDeclarationIndex, to: $0) }
				let aboveSources = propertiesProvidedAboveEveryPath(to: above).filter { candidate in
					plainSources.contains { $0.label == candidate.label && $0.type == candidate.type }
						&& candidate.providerIndex.map { provider in declarationIndexByName[typeName(provider)].map { isOnEveryPath(from: $0, to: aboveDeclarationIndex) } ?? false } ?? true
				}
				if !receivers.isEmpty {
					let receiver = seamRandom.element(of: receivers)
					let source = aboveSources.isEmpty ? { ensureSharedProvider(); return sharedSource }() : seamRandom.element(of: aboveSources)
					add(PropertyDeclaration(
						attribute: "@Received(fulfilledByDependencyNamed: \"\(source.label)\", ofType: \(source.type).self)",
						label: "\(source.label)Above",
						type: source.type,
					), toTypeAt: above)
					add(PropertyDeclaration(attribute: "@Received", label: "\(source.label)Above", type: source.type), toDeclarationAt: receiver)
				}
			}
			// The forms a seam's tree receives a lazily instantiated property provided above in, under the rule that a
			// required wrapper provides every form beneath it, an optional wrapper nothing but itself, and the rest is a
			// label collision.
			if seamRandom.percentChance(50) {
				let child = seamRandom.element(of: children)
				let lazySources = propertiesProvidedAboveEveryPath(to: seamTypeIndex).filter { candidate in
					candidate.providerIndex != seamTypeIndex
						&& !candidate.isOptional
						&& (candidate.type.hasPrefix("LazilyInstantiated<") || candidate.type.hasPrefix("SendableLazilyInstantiated<"))
						&& isProvidedAboveEveryPath(candidate, toChildAt: child)
				}
				let source: ProvidedProperty
				if let lazySource = lazySources.isEmpty ? nil : seamRandom.element(of: lazySources) {
					source = lazySource
				} else {
					// Every root instantiates `SeamShared` lazily under one label, so a wrapper receive can always be drawn.
					// A mixed graph's wrapper is `Sendable`, so a child beneath a `Sendable` builder can read it too.
					ensureSharedProvider()
					let wrapper = sendability == .nonSendable ? "LazilyInstantiated" : "SendableLazilyInstantiated"
					for rootIndex in rootIndices {
						add(PropertyDeclaration(attribute: "@Instantiated", label: "seamLazy", type: "\(wrapper)<\(sharedTypeName)>"), toDeclarationAt: rootIndex)
					}
					source = ProvidedProperty(label: "seamLazy", type: "\(wrapper)<\(sharedTypeName)>", providerIndex: nil, builtIndex: nil)
				}
				let instanceType = String(source.type.drop { $0 != "<" }.dropFirst().dropLast())
				let wrapperKind = String(source.type.prefix { $0 != "<" })
				let otherKind = wrapperKind.hasPrefix("Sendable") ? String(wrapperKind.dropFirst("Sendable".count)) : "Sendable\(wrapperKind)"
				let secondChild = children.filter { $0 != child }
				func byValueForm(toDeclarationAt index: Int) {
					if seamRandom.percentChance(50) {
						add(PropertyDeclaration(attribute: "@Received", label: source.label, type: instanceType), toDeclarationAt: index)
					} else {
						add(PropertyDeclaration(attribute: "@Received(onlyIfAvailable: true)", label: source.label, type: instanceType + "?"), toDeclarationAt: index)
					}
				}
				switch seamRandom.integer(in: 0...9) {
				case 0, 1:
					// The required wrapper, which provides a by-value form beneath it: on another child, or, where the
					// seam has one, on a link beneath the receiver.
					add(PropertyDeclaration(attribute: "@Received", label: source.label, type: source.type), toDeclarationAt: child)
					if seamRandom.percentChance(70) {
						byValueForm(toDeclarationAt: secondChild.isEmpty ? appendSeamLink(beneath: child) : seamRandom.element(of: secondChild))
					}
				case 2, 3:
					// The instance by value, which the caller passes as `.instance`.
					byValueForm(toDeclarationAt: child)
				case 4, 5:
					// The optional wrapper, which the caller passes as it holds it.
					add(PropertyDeclaration(attribute: "@Received(onlyIfAvailable: true)", label: source.label, type: source.type + "?"), toDeclarationAt: child)
				case 6, 7:
					// The optional wrapper of the other kind, which the caller passes `nil`: in a mixed graph, whose
					// types can hold either kind; elsewhere the graph's own kind.
					let kind = sendability == .mixed ? otherKind : wrapperKind
					add(PropertyDeclaration(attribute: "@Received(onlyIfAvailable: true)", label: source.label, type: "\(kind)<\(instanceType)>?"), toDeclarationAt: child)
				default:
					// A by-value form beside the optional wrapper, on two children: the label collision the seam
					// reports, drawn one lazy draw in five; with one child, the optional wrapper alone.
					add(PropertyDeclaration(attribute: "@Received(onlyIfAvailable: true)", label: source.label, type: source.type + "?"), toDeclarationAt: child)
					if !secondChild.isEmpty {
						byValueForm(toDeclarationAt: seamRandom.element(of: secondChild))
					}
				}
			}
			// A child's `onlyIfAvailable` receive of a wrapper of a property the caller holds by value: the caller
			// passes `nil`, as it does inline, since an instance is no wrapper. The property is the draw's own
			// (`seamHeld`), which nothing else receives, so no by-value form of the label collides with it. A
			// `Sendable` graph's types hold only `Sendable` wrappers, a non-`Sendable` graph's only
			// `LazilyInstantiated`, and a mixed graph's either, as its other wrappers are drawn.
			if seamRandom.percentChance(35) {
				let child = seamRandom.element(of: children)
				ensureHeldProvider()
				let source = ProvidedProperty(label: "seamHeld", type: "\(prefix)SeamHeld", providerIndex: nil, builtIndex: nil)
				let drawsSendableWrapper = seamRandom.percentChance(50)
				let wrapper = switch sendability {
				case .nonSendable:
					"LazilyInstantiated"
				case .sendable:
					"SendableLazilyInstantiated"
				case .mixed:
					drawsSendableWrapper ? "SendableLazilyInstantiated" : "LazilyInstantiated"
				}
				add(PropertyDeclaration(attribute: "@Received(onlyIfAvailable: true)", label: source.label, type: "\(wrapper)<\(source.type)>?"), toDeclarationAt: child)
			}
			// A seam beneath the seam, so that a seam reaches a seam.
			let innerCandidates = childTypeIndices(of: seamTypeIndex).filter { !childTypeIndices(of: $0).isEmpty }
			if seamRandom.percentChance(25), !innerCandidates.isEmpty {
				markSeam(seamRandom.element(of: innerCandidates))
			}
			return declarations
		}

		private static let seamRandomSeedMask: UInt64 = 0x7365616D5F747265

		// MARK: Spelled properties

		/// With the `generateDependencyTree` feature on, seven graphs in ten gain a small seam tree of their own whose
		/// one value, `spelled`, has a type drawn from `GraphFuzzerSpelling`: a closure, a closure with a parameter and
		/// a return, a `@Sendable` closure, the optional forms of both closures, a tuple holding a closure, an
		/// existential, a closure taking one, a nested type, an array, a `Result`, or a typealias of a type that is not
		/// a function. No `@Instantiable` type provides such a value, so it is `@Forwarded`: by `SpellSeam` itself, a
		/// seam the first root builds through an instantiator, or by `SpellHost`, which the first root builds through
		/// an instantiator and which instantiates `SpellSeam`. The seam's tree then takes it in each way a seam's
		/// signature can: the seam's own `@Forwarded` or `@Received` property, a pass-through its child `SpellChild`
		/// requires or receives only if available, the optional form beside the required one on a second child
		/// `SpellSibling`, and a rename of it on the seam or on the child. A graph whose wrappers are all `Sendable`
		/// draws only `Sendable` values, its closures `@Sendable`, since its types are `Sendable` and its builders
		/// `@Sendable`; every other graph builds the tree through `Instantiator`, which captures any value. Now and then
		/// the child or the seam generates a mock. `spellingRandom` draws only for this pass.
		private mutating func addingSpelledProperties(to declarations: [TypeDeclaration]) -> [TypeDeclaration] {
			guard features.contains(.generateDependencyTree), spellingRandom.percentChance(70) else { return declarations }
			var declarations = declarations
			let spelling = spellingRandom.element(of: GraphFuzzerSpelling.allCases.filter { sendability != .sendable || $0.hasSendableSpelling })
			let type = spelling.spelledType(prefix: prefix, isSendable: sendability == .sendable)
			let optionalForm = GraphFuzzerSpelling.optionalForm(of: type)
			let instantiator = sendability == .sendable ? "SendableInstantiator" : "Instantiator"
			let conformances = sendability == .mixed ? ["@unchecked Sendable"] : []
			let seamName = "\(prefix)SpellSeam"
			let childName = "\(prefix)SpellChild"
			let label = GraphFuzzerSpelling.label
			var seam = TypeDeclaration(name: seamName, instantiableArguments: ["generateDependencyTree: true"], properties: [], declaresHelperTypes: false, additionalConformances: conformances)
			seam.additionalDeclarations = spelling.helperDeclarations(prefix: prefix, areSendable: helperTypesAreSendable)
			var child = TypeDeclaration(name: childName, instantiableArguments: [], properties: [], declaresHelperTypes: false, additionalConformances: conformances)
			var newDeclarations = [TypeDeclaration]()
			if spellingRandom.percentChance(35) {
				// The seam forwards the value, so the first root builds the seam through an instantiator.
				seam.properties.append(PropertyDeclaration(attribute: "@Forwarded", label: label, type: type))
				declarations[0].properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "spellSeamBuilder", type: "\(instantiator)<\(seamName)>"))
			} else {
				// A host forwards the value and instantiates the seam, which now and then receives the value itself.
				let hostName = "\(prefix)SpellHost"
				var host = TypeDeclaration(name: hostName, instantiableArguments: [], properties: [], declaresHelperTypes: false, additionalConformances: conformances)
				host.properties.append(PropertyDeclaration(attribute: "@Forwarded", label: label, type: type))
				host.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "spellSeam", type: seamName))
				newDeclarations.append(host)
				declarations[0].properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "spellHostBuilder", type: "\(instantiator)<\(hostName)>"))
				if spellingRandom.percentChance(40) {
					seam.properties.append(spellingRandom.percentChance(70) || type.hasSuffix("?")
						? PropertyDeclaration(attribute: "@Received", label: label, type: type)
						: PropertyDeclaration(attribute: "@Received(onlyIfAvailable: true)", label: label, type: optionalForm))
				}
			}
			seam.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "spellChild", type: childName))
			// The child receives the value, required or only if available; an existential is now and then received
			// spelled without `any`, which names the same type.
			let receivedType = spelling == .existential && spellingRandom.percentChance(50) ? String(type.dropFirst("any ".count)) : type
			let childIsRequired = spellingRandom.percentChance(65)
			child.properties.append(childIsRequired
				? PropertyDeclaration(attribute: "@Received", label: label, type: receivedType)
				: PropertyDeclaration(attribute: "@Received(onlyIfAvailable: true)", label: label, type: GraphFuzzerSpelling.optionalForm(of: receivedType)))
			// A second child receiving the optional form only if available, beside the child's form of the label.
			if spellingRandom.percentChance(30) {
				let siblingName = "\(prefix)SpellSibling"
				seam.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "spellSibling", type: siblingName))
				newDeclarations.append(TypeDeclaration(
					name: siblingName,
					instantiableArguments: [],
					properties: [PropertyDeclaration(attribute: "@Received(onlyIfAvailable: true)", label: label, type: optionalForm)],
					declaresHelperTypes: false,
					additionalConformances: conformances,
				))
			}
			// A rename of the value on the seam or on the child, which the seam's signature takes before the rename.
			if spelling.canBeRenamed, !type.hasSuffix("?"), spellingRandom.percentChance(30) {
				let alias = PropertyDeclaration(
					attribute: "@Received(fulfilledByDependencyNamed: \"\(label)\", ofType: \(GraphFuzzerSpelling.ofTypeSpelling(of: type)).self)",
					label: "\(label)Alias",
					type: type,
				)
				if spellingRandom.percentChance(50) {
					seam.properties.append(alias)
				} else {
					child.properties.append(alias)
				}
			}
			if spellingRandom.percentChance(20) {
				child.instantiableArguments.append("generateMock: true")
			} else if spellingRandom.percentChance(15) {
				seam.instantiableArguments.append("generateMock: true")
			}
			return declarations + [seam, child] + newDeclarations
		}

		private static let spellingRandomSeedMask: UInt64 = 0x7370656C6C696E67

		// MARK: Uncreated aliases

		/// With the `generateDependencyTree` feature on, four graphs in ten gain a small seam tree of their own whose
		/// `onlyIfAvailable` alias may not be created, in the shapes the uncreated-alias walk decides: `AliasSeam`, which
		/// the first root instantiates, instantiates `AliasLeft`, which instantiates `AliasDetail`, which declares
		/// `aliasAuth`, an `onlyIfAvailable` alias of `aliasToken` – usually a pass-through received only if available,
		/// and now and then a required optional parameter (the seam's own `@Received` or `@Forwarded` property, or a
		/// property `AliasLeft` requires), whose exact-form alias (`ofType: AliasValue?.self`) is always created and
		/// whose unwrapped-form alias is not; one graph in ten declares the alias on the seam itself. Now and then a
		/// reader beneath the alias reads its property: `AliasReader` receives it, only if available or required,
		/// declares a label-keeping alias of it retyped to an existential, is built through a wrapper, is reached
		/// through a nested seam `AliasPanel`, or sits beneath `AliasMid`; `AliasDetail` aliases the alias as
		/// `aliasBearer`, only if available or required; a declaration of the alias's label is placed beside
		/// `AliasDetail` (on `AliasLeft`), above it (on the seam), or as a parameter of the seam (its own receive, or
		/// `AliasClient`'s pass-through) – the alias's own property, another type, or an instantiator; the caller holds
		/// `aliasAuth` or `aliasToken`; `AliasLeft` instantiates `aliasToken` itself, which creates the alias on that
		/// path while `AliasRight` beside it receives `aliasToken` only if available, or declares it so that the alias
		/// is statically uncreated – `AliasDetail` built inside `aliasToken`'s builder, or `aliasToken` generated after
		/// `AliasA`, which builds `AliasDetail`; beside an alias that keeps its label, `AliasLeft` now and then
		/// instantiates `aliasToken` itself while `AliasValue` receives `aliasDetail`, so the alias's own fulfilling
		/// property is the sibling generated after it. About half of the reader, alias-of-alias and same-property draws
		/// produce the accepted twin instead – the reader or the second alias reads the fulfilling property, or the
		/// alias is made required – so the rest of the graph stays accepted and value-checked. `uncreatedAliasRandom`
		/// draws only for this pass.
		private mutating func addingUncreatedAliasShapes(to declarations: [TypeDeclaration]) -> [TypeDeclaration] {
			guard features.contains(.generateDependencyTree), uncreatedAliasRandom.percentChance(40) else { return declarations }
			var declarations = declarations
			let conformances = sendability == .mixed ? ["@unchecked Sendable"] : []
			func type(_ suffix: String, arguments: [String] = [], properties: [PropertyDeclaration] = []) -> TypeDeclaration {
				TypeDeclaration(name: "\(prefix)\(suffix)", instantiableArguments: arguments, properties: properties, declaresHelperTypes: false, additionalConformances: conformances)
			}
			let valueType = "\(prefix)AliasValue"
			let labelType = "\(prefix)AliasLabel"
			let protocolName = "\(prefix)AliasProto"
			let instantiator = sendability == .sendable ? "SendableInstantiator" : "Instantiator"
			let lazyWrapper = sendability == .sendable ? "SendableLazilyInstantiated" : "LazilyInstantiated"
			var seam = type("AliasSeam", arguments: ["generateDependencyTree: true"])
			var left = type("AliasLeft")
			var detail = type("AliasDetail")
			var value = type("AliasValue")
			value.additionalConformances.append(protocolName)
			value.additionalDeclarations.append("public protocol \(protocolName)\(helperTypesAreSendable ? ": Sendable" : "") {}")
			var newDeclarations = [type("AliasLabel")]

			// How `aliasToken` reaches the seam: a pass-through received only if available, which the seam takes as
			// `AliasValue? = nil`, or a required optional parameter – the seam's own receive, its own forwarded property,
			// or a property `AliasLeft` requires – which every caller holds a value for.
			enum ParameterKind {
				case onlyIfAvailablePassThrough
				case ownRequiredOptionalReceive
				case ownRequiredOptionalForwarded
				case requiredOptionalPassThrough
			}
			let parameterKind: ParameterKind = switch uncreatedAliasRandom.integer(in: 0...9) {
			case 0...6:
				.onlyIfAvailablePassThrough
			case 7:
				.ownRequiredOptionalReceive
			case 8:
				.ownRequiredOptionalForwarded
			default:
				.requiredOptionalPassThrough
			}
			let isRequiredOptionalParameter = parameterKind != .onlyIfAvailablePassThrough
			// The alias's `ofType:` spelling: the exact optional form of the parameter, which a required optional
			// parameter always creates, or the unwrapped form.
			var aliasFulfillingType = uncreatedAliasRandom.percentChance(isRequiredOptionalParameter ? 60 : 20) ? "\(valueType)?" : valueType
			let aliasOnSeam = uncreatedAliasRandom.percentChance(10)
			// The alias keeping its fulfilling property's label and only making it optional – a redundant spelling of a
			// plain receive, which is not an alias of itself – where its declaring type does not declare `aliasToken`
			// itself; every reader then reads the alias, and nothing beside it is drawn under `aliasAuth`.
			let aliasKeepsLabel = !(aliasOnSeam && (parameterKind == .ownRequiredOptionalReceive || parameterKind == .ownRequiredOptionalForwarded)) && labelKeepingAliasRandom.percentChance(10)
			if aliasKeepsLabel {
				aliasFulfillingType = valueType
			}
			// Whether the alias is required rather than `onlyIfAvailable`: the accepted twin of a declaration of its
			// property beside its declaring type, drawn below.
			var aliasIsRequired = false
			func aliasDeclaration() -> PropertyDeclaration {
				PropertyDeclaration(
					attribute: "@Received(fulfilledByDependencyNamed: \"aliasToken\", ofType: \(aliasFulfillingType).self\(aliasIsRequired ? "" : ", onlyIfAvailable: true"))",
					label: aliasKeepsLabel ? "aliasToken" : "aliasAuth",
					type: valueType + "?",
				)
			}
			switch parameterKind {
			case .onlyIfAvailablePassThrough:
				if uncreatedAliasRandom.percentChance(40) {
					declarations[0].properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "aliasToken", type: valueType))
				}
			case .ownRequiredOptionalReceive, .requiredOptionalPassThrough:
				// A required `aliasToken: AliasValue?` is fulfilled by its exact form alone, which the root declares as
				// an alias of the value it instantiates.
				declarations[0].properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "aliasSource", type: valueType))
				declarations[0].properties.append(PropertyDeclaration(attribute: "@Received(fulfilledByDependencyNamed: \"aliasSource\", ofType: \(valueType).self, onlyIfAvailable: true)", label: "aliasToken", type: valueType + "?"))
				if parameterKind == .ownRequiredOptionalReceive {
					seam.properties.append(PropertyDeclaration(attribute: "@Received", label: "aliasToken", type: valueType + "?"))
				} else {
					left.properties.append(PropertyDeclaration(attribute: "@Received", label: "aliasToken", type: valueType + "?"))
				}
			case .ownRequiredOptionalForwarded:
				seam.properties.append(PropertyDeclaration(attribute: "@Forwarded", label: "aliasToken", type: valueType + "?"))
			}
			if uncreatedAliasRandom.percentChance(30) {
				declarations[0].properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "aliasAuth", type: valueType))
			}
			declarations[0].properties.append(parameterKind == .ownRequiredOptionalForwarded
				? PropertyDeclaration(attribute: "@Instantiated", label: "aliasSeamBuilder", type: "\(instantiator)<\(seam.name)>")
				: PropertyDeclaration(attribute: "@Instantiated", label: "aliasSeam", type: seam.name))
			func declarationOfAliasLabel() -> PropertyDeclaration {
				switch uncreatedAliasRandom.integer(in: 0...2) {
				case 0:
					PropertyDeclaration(attribute: "@Instantiated", label: "aliasAuth", type: valueType)
				case 1:
					PropertyDeclaration(attribute: "@Instantiated", label: "aliasAuth", type: labelType)
				default:
					PropertyDeclaration(attribute: "@Instantiated", label: "aliasAuth", type: "\(instantiator)<\(valueType)>")
				}
			}
			// Drawn whether or not the alias keeps its label, so that the graphs it does not touch are drawn as before.
			let labelDeclarationDraw = uncreatedAliasRandom.integer(in: 0...19)
			switch aliasKeepsLabel ? 19 : labelDeclarationDraw {
			case 0...4:
				// Beside the alias's declaring type: on the type that builds it, declared before it. Half the time the
				// accepted twin: the alias made required, which is created wherever its declaring type is built, with
				// the caller holding its fulfilling property, which the required alias makes a required parameter.
				let sameProperty = declarationOfAliasLabel()
				if sameProperty.type == valueType, !aliasOnSeam, parameterKind == .onlyIfAvailablePassThrough, uncreatedAliasRandom.percentChance(50) {
					aliasIsRequired = true
					aliasFulfillingType = valueType
					if !declarations[0].properties.contains(where: { $0.label == "aliasToken" }) {
						declarations[0].properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "aliasToken", type: valueType))
					}
				}
				left.properties.append(sameProperty)
			case 5...7 where !aliasOnSeam:
				// Above the type that builds the alias's declaring type.
				seam.properties.append(declarationOfAliasLabel())
			case 8...11:
				// A parameter of the seam: its own receive, where the seam does not declare the alias itself, or a
				// pass-through another child receives.
				if !aliasOnSeam, uncreatedAliasRandom.percentChance(50) {
					seam.properties.append(PropertyDeclaration(attribute: "@Received(onlyIfAvailable: true)", label: "aliasAuth", type: valueType + "?"))
				} else {
					let clientType = uncreatedAliasRandom.percentChance(50) ? valueType : labelType
					newDeclarations.append(type("AliasClient", properties: [PropertyDeclaration(attribute: "@Received(onlyIfAvailable: true)", label: "aliasAuth", type: clientType + "?")]))
					seam.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "aliasClient", type: "\(prefix)AliasClient"))
				}
			default:
				break
			}
			// How `AliasLeft` reaches `AliasDetail`, and whether it declares `aliasToken` itself: instantiated beside
			// `AliasDetail`, which creates the alias on that path; instantiated as the owner of `AliasDetail`'s builder, so
			// that the alias is declared where `aliasToken` is still being built; or generated after `AliasA`, which
			// builds `AliasDetail`, so that the alias is declared where `aliasToken` is generated later. Only a pass-through
			// received only if available leaves `aliasToken` for `AliasLeft` to declare.
			var leftBuildsDetailDirectly = true
			if parameterKind == .onlyIfAvailablePassThrough {
				switch uncreatedAliasRandom.integer(in: 0...19) {
				case 0...3:
					left.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "aliasToken", type: valueType))
					newDeclarations.append(type("AliasRight", properties: [PropertyDeclaration(attribute: "@Received(onlyIfAvailable: true)", label: "aliasToken", type: valueType + "?")]))
					seam.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "aliasRight", type: "\(prefix)AliasRight"))
				case 4...5:
					left.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "aliasToken", type: valueType))
					value.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "aliasDetailBuilder", type: "\(instantiator)<\(detail.name)>"))
					leftBuildsDetailDirectly = false
				case 6...7:
					left.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "aliasToken", type: valueType))
					left.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "aliasA", type: "\(prefix)AliasA"))
					value.properties.append(PropertyDeclaration(attribute: "@Received(onlyIfAvailable: true)", label: "aliasA", type: "\(prefix)AliasA?"))
					newDeclarations.append(type("AliasA", properties: [PropertyDeclaration(attribute: "@Instantiated", label: "aliasDetail", type: detail.name)]))
					leftBuildsDetailDirectly = false
				default:
					break
				}
			}
			// A second alias of the alias on its declaring type, only if available or required; half the time the
			// accepted twin, an alias of the fulfilling property instead.
			if !aliasOnSeam, uncreatedAliasRandom.percentChance(20) {
				// Beside an alias that keeps its label, the label names the alias, so the second alias reads it under the
				// alias's own type.
				let readsAlias = uncreatedAliasRandom.percentChance(50) || aliasKeepsLabel
				let readLabel = readsAlias && !aliasKeepsLabel ? "aliasAuth" : "aliasToken"
				let bearerIsRequired = uncreatedAliasRandom.percentChance(30)
				detail.properties.append(PropertyDeclaration(
					attribute: "@Received(fulfilledByDependencyNamed: \"\(readLabel)\", ofType: \(readsAlias ? valueType + "?" : valueType).self\(bearerIsRequired && readsAlias ? "" : ", onlyIfAvailable: true"))",
					label: "aliasBearer",
					type: valueType + "?",
				))
			}
			// A reader beneath the alias, in one of the shapes the walk decides; half the time the accepted twin, which
			// reads the fulfilling property instead.
			if uncreatedAliasRandom.percentChance(50) {
				let readsAlias = uncreatedAliasRandom.percentChance(50) && !aliasKeepsLabel
				let readLabel = readsAlias ? "aliasAuth" : "aliasToken"
				var reader = type("AliasReader")
				switch uncreatedAliasRandom.integer(in: 0...9) {
				case 0...4:
					reader.properties.append(PropertyDeclaration(attribute: "@Received(onlyIfAvailable: true)", label: readLabel, type: valueType + "?"))
				case 5:
					reader.properties.append(PropertyDeclaration(attribute: "@Received", label: readLabel, type: valueType + "?"))
				default:
					// A label-keeping alias retyped to an existential, or, as the twin, an alias of the fulfilling property.
					reader.properties.append(readsAlias
						? PropertyDeclaration(attribute: "@Received(fulfilledByDependencyNamed: \"aliasAuth\", ofType: \(valueType)?.self, onlyIfAvailable: true)", label: "aliasAuth", type: "(any \(protocolName))?")
						: PropertyDeclaration(attribute: "@Received(fulfilledByDependencyNamed: \"aliasToken\", ofType: \(valueType).self, onlyIfAvailable: true)", label: "aliasBearer", type: "(any \(protocolName))?"))
				}
				newDeclarations.append(reader)
				var readerHolder = aliasOnSeam && uncreatedAliasRandom.percentChance(50) ? seam : detail
				switch uncreatedAliasRandom.integer(in: 0...9) {
				case 0...5:
					readerHolder.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "aliasReader", type: reader.name))
				case 6:
					readerHolder.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "aliasReaderBuilder", type: "\(uncreatedAliasRandom.percentChance(50) ? instantiator : lazyWrapper)<\(reader.name)>"))
				case 7:
					// A nested seam, whose pass-through stands for the reader's receive.
					newDeclarations.append(type("AliasPanel", arguments: ["generateDependencyTree: true"], properties: [PropertyDeclaration(attribute: "@Instantiated", label: "aliasReader", type: reader.name)]))
					readerHolder.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "aliasPanel", type: "\(prefix)AliasPanel"))
				default:
					newDeclarations.append(type("AliasMid", properties: [PropertyDeclaration(attribute: "@Instantiated", label: "aliasReader", type: reader.name)]))
					readerHolder.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "aliasMid", type: "\(prefix)AliasMid"))
				}
				if readerHolder.name == seam.name {
					seam = readerHolder
				} else {
					detail = readerHolder
				}
			}
			// Beside an alias that keeps its label and whose property is an only-if-available pass-through nothing else
			// declares, `AliasLeft` now and then instantiates `aliasToken` itself while `AliasValue` receives `aliasDetail`:
			// the alias's own fulfilling property is then the sibling generated after `AliasDetail`, which creates no alias
			// and passes `AliasDetail` nothing but `nil`, inline and in the seam alike.
			if aliasKeepsLabel, parameterKind == .onlyIfAvailablePassThrough, leftBuildsDetailDirectly,
			   !left.properties.contains(where: { $0.label == "aliasToken" }),
			   !declarations[0].properties.contains(where: { $0.type == valueType }),
			   labelKeepingAliasRandom.percentChance(40)
			{
				left.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "aliasToken", type: valueType))
				value.properties.append(PropertyDeclaration(attribute: "@Received", label: "aliasDetail", type: detail.name))
			}
			if aliasOnSeam {
				seam.properties.insert(aliasDeclaration(), at: 0)
			} else {
				detail.properties.insert(aliasDeclaration(), at: 0)
			}
			if leftBuildsDetailDirectly {
				left.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "aliasDetail", type: detail.name))
			}
			seam.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "aliasLeft", type: left.name))
			return declarations + [seam, left, detail, value] + newDeclarations
		}

		private static let uncreatedAliasRandomSeedMask: UInt64 = 0x756E637265617465
		private static let labelKeepingAliasRandomSeedMask: UInt64 = 0x6B6565704C61626C

		// MARK: Access proof

		/// With the `generateDependencyTree` feature on, four graphs in five gain a small seam tree of their own,
		/// `ProofSeam`, whose parameters' types are narrower, or wider, than the access levels of the declarations that
		/// name them, so that a tier whose access a seam reads from the wrong declaration fails to compile: the seam
		/// type at `package` or `internal`; and either one of three shapes of the seam's own initializer narrower than
		/// its type – with no pass-through (`ProofCog`), with only optional narrower ones (`ProofVane`), or narrower than
		/// two parameter levels (`ProofGauge` requiring a public value, `ProofDial` receiving a package one only if
		/// available) – or any of the facets: a receiver whose initializer is narrower than its parameter's type
		/// (`ProofBadge`); a receiver type narrower than its spelled initializer (`ProofVault`); a required parameter
		/// narrower than the seam's type (`ProofLock`); the seam's own only-if-available receive (`proofOwn`); a plain
		/// public model type only package initializers mention (`ProofPanel`); an alias of a plain type nothing proves
		/// (`ProofConsumer`), now and then a narrower `@Instantiable` type, or one a declaration no tree reaches receives
		/// (`ProofLedger`); an `@Instantiable` type and a plain type declared in an extension of a namespace enum,
		/// narrower than them or public, the extension spelled or not, reached by value or only through an existential
		/// (`ProofSpace.ProofShelf`); an `@Instantiable` extension of a narrower type whose `instantiate(…)` is public
		/// (`ProofRack`), now and then with a hand-written public mock beside it; a public mock beside the
		/// `instantiate(…)` of an extension of a package type, the widest mention of what an internal receiver receives
		/// (`ProofShed`, `ProofBeam`); an `@Instantiable` type declared in an extension that spells no access level of the
		/// seam or of a package `@Instantiable` type (`ProofHelper`); and a `Swift.`-qualified parameter type
		/// (`ProofMeter`). A host, `ProofHost`, which the first root builds, holds most of the values the tree receives
		/// and instantiates the seam, with an `@Instantiable` value now and then declared after the seam. Half of the
		/// graphs whose seam is not `internal` are split across modules (`GraphFuzzerModule`): the seam's tree in
		/// package `shop`, the host and the rest of the graph in a caller in the same package, and, when the seam is
		/// `public`, a second root and host in package `other` holding the public values. A sixth of the split graphs
		/// run their same-package caller, and another sixth their seam's module, without the package's name
		/// (`ModuleFixture.omitsPackageName`), as Bazel without `package_name` does, so the caller cannot tell the two
		/// share a package. `proofRandom` draws only for this pass.
		private mutating func addingAccessProofShapes(to declarations: [TypeDeclaration]) -> [TypeDeclaration] {
			guard features.contains(.generateDependencyTree), proofRandom.percentChance(80) else { return declarations }
			var declarations = declarations
			let instantiator = sendability == .sendable ? "SendableInstantiator" : "Instantiator"
			let conformances = sendability == .mixed ? ["@unchecked Sendable"] : []
			func name(_ suffix: String) -> String {
				"\(prefix)\(suffix)"
			}
			func register(_ typeName: String, _ access: AccessLevel) {
				if access < .public {
					proofTypeAccess[typeName] = access
				}
			}
			func instantiable(_ suffix: String, access: AccessLevel = .public, initializerAccess: AccessLevel? = nil, properties: [PropertyDeclaration] = []) -> TypeDeclaration {
				var declaration = TypeDeclaration(name: name(suffix), instantiableArguments: [], properties: properties, declaresHelperTypes: false, additionalConformances: conformances)
				declaration.access = access
				declaration.initializerAccess = initializerAccess
				register(declaration.name, access)
				return declaration
			}
			/// A plain type declared `access`, which no `@Instantiable` declaration fulfills.
			func plainType(_ typeName: String, access: AccessLevel, conformingTo protocols: [String] = []) -> String {
				let inheritance = (protocols + (helperTypesAreSendable ? ["Sendable"] : [])).joined(separator: ", ")
				return "\(access.modifier)final class \(typeName)\(inheritance.isEmpty ? "" : ": \(inheritance)") {\n\t\(access.modifier)init() {}\n}"
			}
			/// An access level narrower than `access`, which is wider than `internal`.
			func narrower(than access: AccessLevel) -> AccessLevel {
				access == .public && proofRandom.percentChance(60) ? .package : .internal
			}

			// The seam, a third of the time narrower than public.
			let seamAccessRoll = proofRandom.integer(in: 0...5)
			let seamAccess: AccessLevel = seamAccessRoll < 4 ? .public : seamAccessRoll == 4 ? .package : .internal
			var seam = instantiable("ProofSeam", access: seamAccess)
			seam.instantiableArguments = ["generateDependencyTree: true"]
			let isSplit = seamAccess > .internal && proofRandom.percentChance(50)
			let seamModule: GraphFuzzerModule? = isSplit ? .seamModule : nil
			var treeDeclarations = [TypeDeclaration]()

			/// A value the seam's tree receives that a caller can hold: a plain type, which a host forwards, or an
			/// `@Instantiable` one, which a host instantiates.
			struct ProofValue {
				let label: String
				let type: String
				let access: AccessLevel
				let isInstantiable: Bool
			}
			var heldValues = [ProofValue]()
			/// Whether the same-package host can name a type of this access: any in one module, `package` or wider across modules.
			func isVisibleToHost(_ access: AccessLevel) -> Bool {
				!isSplit || access > .internal
			}
			/// Has the caller hold `value`, with a chance of `percent` out of 100, when its host can name the value's type.
			func hold(_ value: ProofValue, percent: Int = 75) {
				guard isVisibleToHost(value.access), proofRandom.percentChance(percent) else { return }
				heldValues.append(value)
			}
			/// Declares a value type of the seam's tree: plain, in the file of `owner`, the type that receives it, or
			/// `@Instantiable`, in a file of its own.
			func valueType(_ suffix: String, access: AccessLevel, isInstantiable: Bool, declaredIn owner: inout TypeDeclaration, conformingTo protocols: [String] = []) -> ProofValue {
				let typeName = name(suffix)
				if isInstantiable {
					var declaration = instantiable(suffix, access: access)
					declaration.additionalConformances += protocols
					declaration.module = seamModule
					treeDeclarations.append(declaration)
				} else {
					register(typeName, access)
					owner.additionalDeclarations.append(plainType(typeName, access: access, conformingTo: protocols))
				}
				let label = "proof" + suffix.dropFirst("Proof".count)
				return ProofValue(label: label, type: typeName, access: access, isInstantiable: isInstantiable)
			}
			func receive(_ value: ProofValue, isRequired: Bool) -> PropertyDeclaration {
				isRequired
					? PropertyDeclaration(attribute: "@Received", label: value.label, type: value.type)
					: PropertyDeclaration(attribute: "@Received(onlyIfAvailable: true)", label: value.label, type: value.type + "?")
			}
			func addChild(_ child: TypeDeclaration, label: String) {
				var child = child
				child.module = seamModule
				seam.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: label, type: child.name))
				treeDeclarations.append(child)
			}

			// The seam's own initializer narrower than its type, in one of three shapes, or the facets.
			let modeRoll = proofRandom.integer(in: 0...99)
			if seamAccess > .internal, modeRoll < 12 {
				// No pass-through: the seam's only child receives nothing.
				seam.initializerAccess = narrower(than: seamAccess)
				addChild(instantiable("ProofCog"), label: "proofCog")
			} else if seamAccess > .internal, modeRoll < 24 {
				// Only optional pass-throughs, each of a type as narrow as the seam's own initializer.
				let ownAccess = narrower(than: seamAccess)
				seam.initializerAccess = ownAccess
				var vane = instantiable("ProofVane", initializerAccess: ownAccess)
				let draft = valueType("ProofDraft", access: ownAccess, isInstantiable: false, declaredIn: &vane)
				vane.properties.append(receive(draft, isRequired: false))
				hold(draft)
				addChild(vane, label: "proofVane")
			} else if seamAccess == .public, modeRoll < 34 {
				// An internal own initializer, a public required pass-through and a package optional one, both held.
				seam.initializerAccess = .internal
				var gauge = instantiable("ProofGauge")
				let label = valueType("ProofLabel", access: .public, isInstantiable: proofRandom.percentChance(50), declaredIn: &gauge)
				gauge.properties.append(receive(label, isRequired: true))
				hold(label, percent: 100)
				var dial = instantiable("ProofDial", initializerAccess: .package)
				let note = valueType("ProofNote", access: .package, isInstantiable: false, declaredIn: &dial)
				dial.properties.append(receive(note, isRequired: false))
				hold(note, percent: 100)
				addChild(gauge, label: "proofGauge")
				addChild(dial, label: "proofDial")
			} else {
				// A receiver whose initializer is narrower than its parameter's type.
				if proofRandom.percentChance(55) {
					let themeAccess: AccessLevel = proofRandom.percentChance(75) ? .public : .package
					var badge = instantiable("ProofBadge", initializerAccess: narrower(than: themeAccess))
					let theme = valueType("ProofTheme", access: themeAccess, isInstantiable: proofRandom.percentChance(40), declaredIn: &badge)
					let isRequired = proofRandom.percentChance(15)
					badge.properties.append(receive(theme, isRequired: isRequired))
					hold(theme, percent: isRequired ? 100 : 75)
					addChild(badge, label: "proofBadge")
				}
				// A receiver type narrower than its spelled initializer, which the type caps.
				if proofRandom.percentChance(15) {
					var vault = instantiable("ProofVault", access: .package, initializerAccess: .public)
					let key = valueType("ProofKey", access: .package, isInstantiable: false, declaredIn: &vault)
					let isRequired = proofRandom.percentChance(10)
					vault.properties.append(receive(key, isRequired: isRequired))
					hold(key, percent: isRequired ? 100 : 70)
					addChild(vault, label: "proofVault")
				}
				// A required parameter narrower than the seam's type.
				if proofRandom.percentChance(12), seamAccess > .internal {
					let pinAccess = narrower(than: seamAccess)
					var lock = instantiable("ProofLock", initializerAccess: pinAccess)
					let pin = valueType("ProofPin", access: pinAccess, isInstantiable: false, declaredIn: &lock)
					lock.properties.append(receive(pin, isRequired: true))
					hold(pin, percent: 100)
					addChild(lock, label: "proofLock")
				}
				// The seam's own only-if-available receive, half the time of a type narrower than the seam.
				if proofRandom.percentChance(20) {
					let ownAccess = seamAccess > .internal && proofRandom.percentChance(50) ? narrower(than: seamAccess) : seamAccess
					let own = valueType("ProofOwn", access: ownAccess, isInstantiable: false, declaredIn: &seam)
					seam.properties.insert(receive(own, isRequired: false), at: 0)
					hold(own, percent: 70)
				}
				// A plain public model type only package initializers mention, which the caller holds or does not.
				if proofRandom.percentChance(20) {
					var panel = instantiable("ProofPanel", initializerAccess: .package)
					let model = valueType("ProofModel", access: .public, isInstantiable: false, declaredIn: &panel)
					panel.properties.append(receive(model, isRequired: false))
					hold(model, percent: 75)
					addChild(panel, label: "proofPanel")
				}
				// An alias of a plain type no declaration proves, required or only if available; now and then the type is a
				// narrower `@Instantiable` one, and now and then a package initializer also receives the type itself.
				if proofRandom.percentChance(12) {
					var consumer = instantiable("ProofConsumer")
					let authName = name("ProofAuth")
					consumer.additionalDeclarations.append("public protocol \(authName)\(helperTypesAreSendable ? ": Sendable" : "") {}")
					let sessionIsInstantiable = proofRandom.percentChance(35)
					let sessionAccess: AccessLevel = sessionIsInstantiable || proofRandom.percentChance(60) ? .package : .public
					let session = valueType("ProofSession", access: sessionAccess, isInstantiable: sessionIsInstantiable, declaredIn: &consumer, conformingTo: [authName])
					if sessionAccess == .package, proofRandom.percentChance(30) {
						// A declaration no tree reaches, which mentions the type at `package`.
						var ledger = instantiable("ProofLedger", initializerAccess: .package)
						ledger.properties.append(receive(session, isRequired: true))
						ledger.module = seamModule
						treeDeclarations.append(ledger)
					}
					let sessionType = session.type
					consumer.properties.append(proofRandom.percentChance(50)
						? PropertyDeclaration(attribute: "@Received(fulfilledByDependencyNamed: \"\(session.label)\", ofType: \(sessionType).self)", label: "proofAuth", type: "any \(authName)")
						: PropertyDeclaration(attribute: "@Received(fulfilledByDependencyNamed: \"\(session.label)\", ofType: \(sessionType).self, onlyIfAvailable: true)", label: "proofAuth", type: "(any \(authName))?"))
					hold(session, percent: 100)
					addChild(consumer, label: "proofConsumer")
				}
				// An `@Instantiable` type and a plain type declared in an extension of a narrower namespace enum, or now and
				// then of a public one: SafeDI records no namespace, so it reads either the same way, and a type reached
				// only through an existential is then proven narrower than every caller in another module reaches,
				// which still constructs it inline.
				if proofRandom.percentChance(16) {
					let namespaceRoll = proofRandom.integer(in: 0...99)
					let namespaceAccess: AccessLevel = namespaceRoll < 55 ? .package : namespaceRoll < 80 ? .internal : .public
					let namespace = name("ProofSpace")
					let isSpelled = proofRandom.percentChance(50)
					// Unspelled, the members are spelled wider than the namespace; spelled, they are left unspelled.
					let memberAccess: AccessLevel = isSpelled ? .internal : .public
					let shelfName = "\(namespace).\(name("ProofShelf"))"
					let crateName = "\(namespace).\(name("ProofCrate"))"
					let shelvingName = name("ProofShelving")
					var shelf = TypeDeclaration(name: name("ProofShelf"), instantiableArguments: [], properties: [], declaresHelperTypes: false, additionalConformances: conformances + [shelvingName])
					shelf.access = memberAccess
					shelf.enclosingExtension = "\(isSpelled ? namespaceAccess.modifier : "")extension \(namespace)"
					shelf.enclosingTypeAccess = namespaceAccess
					register(shelfName, namespaceAccess)
					register(crateName, namespaceAccess)
					register(namespace, namespaceAccess)
					shelf.properties.append(PropertyDeclaration(attribute: "@Received(onlyIfAvailable: true)", label: "proofCrate", type: crateName + "?"))
					let crateDeclaration = plainType(name("ProofCrate"), access: memberAccess).split(separator: "\n").map { "\t" + $0 }.joined(separator: "\n")
					shelf.additionalDeclarations += [
						"\(namespaceAccess.modifier)enum \(namespace) {}",
						"\(isSpelled ? namespaceAccess.modifier : "")extension \(namespace) {\n\(crateDeclaration)\n}",
						"public protocol \(shelvingName)\(helperTypesAreSendable ? ": Sendable" : "") {}",
					]
					hold(ProofValue(label: "proofCrate", type: crateName, access: namespaceAccess, isInstantiable: false), percent: 70)
					shelf.module = seamModule
					treeDeclarations.append(shelf)
					if proofRandom.percentChance(50) {
						seam.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "proofShelf", type: shelfName))
					} else {
						// Only through an existential, which no initializer names the namespace's type in.
						let erasedName = name("AnyProofShelf")
						seam.additionalDeclarations.append("public final class \(erasedName)\(helperTypesAreSendable ? ": Sendable" : "") {\n\tpublic init(_ shelf: any \(shelvingName)) {}\n}")
						seam.properties.append(PropertyDeclaration(attribute: "@Instantiated(fulfilledByType: \"\(shelfName)\", erasedToConcreteExistential: true)", label: "proofShelf", type: erasedName))
					}
				}
				// An `@Instantiable` extension of a narrower type, whose public `instantiate(…)` receives a package type,
				// reached through an existential.
				if proofRandom.percentChance(10) {
					let rackAccess: AccessLevel = proofRandom.percentChance(50) ? .internal : .package
					let rackName = name("ProofRack")
					let rackingName = name("ProofRacking")
					let erasedName = name("AnyProofRack")
					register(rackName, rackAccess)
					var bolt = instantiable("ProofBolt", access: .package)
					bolt.module = seamModule
					let boltValue = ProofValue(label: "proofBolt", type: bolt.name, access: .package, isInstantiable: true)
					treeDeclarations.append(bolt)
					hold(boltValue, percent: 100)
					// Now and then with a hand-written public mock beside `instantiate(…)`, whose argument is the dependency.
					let mock = proofRandom.percentChance(50) ? "\n\n\tpublic static func mock(proofBolt: \(bolt.name)) -> \(rackName) {\n\t\t\(rackName)()\n\t}" : ""
					seam.additionalDeclarations += [
						"public protocol \(rackingName)\(helperTypesAreSendable ? ": Sendable" : "") {}",
						"\(rackAccess.modifier)final class \(rackName): \(rackingName) {\n\tinit() {}\n}",
						"@Instantiable\nextension \(rackName): Instantiable {\n\tpublic static func instantiate(proofBolt: \(bolt.name)) -> \(rackName) {\n\t\t\(rackName)()\n\t}\(mock)\n}",
						"public final class \(erasedName)\(helperTypesAreSendable ? ": Sendable" : "") {\n\tpublic init(_ rack: any \(rackingName)) {}\n}",
					]
					seam.properties.append(PropertyDeclaration(attribute: "@Instantiated(fulfilledByType: \"\(rackName)\", erasedToConcreteExistential: true)", label: "proofRack", type: erasedName))
				}
				// An `@Instantiable` type declared in an extension, spelling no access level, of a type the graph records:
				// the seam itself, or a package `@Instantiable` type narrower than the seam.
				if proofRandom.percentChance(14) {
					let extendsSeam = proofRandom.percentChance(50)
					var extendedName = seam.name
					var extendedAccess = seamAccess
					if !extendsSeam {
						var settings = instantiable("ProofSettings", access: .package)
						settings.module = seamModule
						treeDeclarations.append(settings)
						extendedName = settings.name
						extendedAccess = .package
					}
					var helper = TypeDeclaration(name: name("ProofHelper"), instantiableArguments: [], properties: [], declaresHelperTypes: false, additionalConformances: conformances)
					helper.enclosingExtension = "extension \(extendedName)"
					helper.enclosingTypeAccess = extendedAccess
					let helperName = "\(extendedName).\(helper.name)"
					register(helperName, extendedAccess)
					var toneHost = helper
					let tone = valueType("ProofTone", access: .public, isInstantiable: false, declaredIn: &toneHost)
					helper.additionalDeclarations = toneHost.additionalDeclarations
					let isRequired = proofRandom.percentChance(50)
					helper.properties.append(receive(tone, isRequired: isRequired))
					hold(tone, percent: isRequired ? 100 : 75)
					helper.module = seamModule
					treeDeclarations.append(helper)
					seam.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "proofHelper", type: helperName))
				}
				// A mock whose argument is the only mention wider than an internal receiver's: a public mock beside the
				// `instantiate(…)` of an extension of a package plain type, which caps it, now and then raised to `package`
				// by an initializer no tree reaches.
				if proofRandom.percentChance(10) {
					let shedName = name("ProofShed")
					register(shedName, .package)
					var beam = instantiable("ProofBeam", initializerAccess: .internal)
					let plank = valueType("ProofPlank", access: .package, isInstantiable: false, declaredIn: &beam)
					beam.properties.append(receive(plank, isRequired: false))
					beam.additionalDeclarations += [
						"package final class \(shedName)\(helperTypesAreSendable ? ": Sendable" : "") {\n\tinit() {}\n}",
						"@Instantiable\nextension \(shedName): Instantiable {\n\tstatic func instantiate(proofPlank: \(plank.type)) -> \(shedName) {\n\t\t\(shedName)()\n\t}\n\n\tpublic static func mock(proofPlank: \(plank.type)) -> \(shedName) {\n\t\t\(shedName)()\n\t}\n}",
					]
					if proofRandom.percentChance(50) {
						var yard = instantiable("ProofYard", initializerAccess: .package)
						yard.properties.append(PropertyDeclaration(attribute: "@Received", label: "proofShed", type: shedName))
						yard.module = seamModule
						treeDeclarations.append(yard)
					}
					hold(plank, percent: 75)
					addChild(beam, label: "proofBeam")
				}
				// A `Swift.`-qualified parameter type, which a package initializer receives only if available.
				if proofRandom.percentChance(6) {
					var meter = instantiable("ProofMeter", initializerAccess: .package)
					let count = ProofValue(label: "proofCount", type: proofRandom.percentChance(50) ? "Swift.Int" : "Swift.String", access: .public, isInstantiable: false)
					meter.properties.append(receive(count, isRequired: false))
					hold(count, percent: 75)
					addChild(meter, label: "proofMeter")
				}
				// A tree with no facet still has a child, so that the seam has a signature.
				if seam.properties.allSatisfy({ !$0.attribute.hasPrefix("@Instantiated") }) {
					addChild(instantiable("ProofCog"), label: "proofCog")
				}
			}
			seam.module = seamModule

			// The host, which the first root builds, holds the values and instantiates the seam: through an instantiator
			// when it forwards a plain value, else as a constant. An `@Instantiable` value is now and then declared after
			// the seam.
			func host(_ suffix: String, holding values: [ProofValue], module: GraphFuzzerModule?) -> TypeDeclaration {
				var host = instantiable(suffix, access: ([seamAccess] + values.map(\.access)).min() ?? seamAccess)
				host.module = module
				var valuesAfterSeam = [PropertyDeclaration]()
				for value in values {
					if value.isInstantiable {
						let property = PropertyDeclaration(attribute: "@Instantiated", label: value.label, type: value.type)
						if proofRandom.percentChance(30) {
							valuesAfterSeam.append(property)
						} else {
							host.properties.append(property)
						}
					} else {
						host.properties.append(PropertyDeclaration(attribute: "@Forwarded", label: value.label, type: value.type))
					}
				}
				host.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "proofSeam", type: seam.name))
				host.properties += valuesAfterSeam
				return host
			}
			func hostProperty(of host: TypeDeclaration) -> PropertyDeclaration {
				host.properties.contains { $0.attribute == "@Forwarded" }
					? PropertyDeclaration(attribute: "@Instantiated", label: "proofHostBuilder", type: "\(instantiator)<\(host.name)>")
					: PropertyDeclaration(attribute: "@Instantiated", label: "proofHost", type: host.name)
			}
			// A split graph's caller in the same package, or its seam's module, now and then run over without its
			// package's name, so the caller cannot tell whether the two share a package and assumes they do (with the
			// seam's module unnamed, there is then no caller in another package, for which that assumption is wrong).
			if isSplit {
				let packageNameRoll = proofRandom.integer(in: 0...5)
				if packageNameRoll == 0 {
					modulesOmittingPackageName.insert(.samePackageCaller)
				} else if packageNameRoll == 1 {
					modulesOmittingPackageName.insert(.seamModule)
				}
			}
			let sameModuleHost = host("ProofHost", holding: heldValues, module: isSplit ? .samePackageCaller : nil)
			declarations[0].properties.append(hostProperty(of: sameModuleHost))
			var callerDeclarations = [sameModuleHost]
			if isSplit, seamAccess == .public, !modulesOmittingPackageName.contains(.seamModule) {
				// A caller in another package, which can name only the public values.
				let otherHost = host("ProofOtherHost", holding: heldValues.filter { $0.access == .public }, module: .otherPackageCaller)
				var otherRoot = instantiable("ProofOtherRoot", properties: [hostProperty(of: otherHost)])
				otherRoot.instantiableArguments = ["isRoot: true"]
				otherRoot.module = .otherPackageCaller
				callerDeclarations += [otherRoot, otherHost]
			}
			return declarations + [seam] + treeDeclarations + callerDeclarations
		}

		private static let proofRandomSeedMask: UInt64 = 0x70726F6F665F6163

		// MARK: Holes

		/// With the `generateDependencyTree` feature on, a third of the graphs gain a seam, `HoleSeam`, whose module
		/// cannot see the type that fulfills a property its tree instantiates – a hole – which the roots' module fills:
		/// the graph is split across modules (`GraphFuzzerModule`), the seam's tree and `HoleService`, a protocol, in the
		/// seam's module, and `HoleImpl`, which fulfills `HoleService`, beside the roots. The first root instantiates the
		/// seam. The property's owner is the seam itself, or `HoleOwner`, which the seam reaches by value or through a
		/// wrapper the graph's sendability allows (a `Sendable` one stages the builder), now and then at a second site.
		/// `HoleImpl` reads a field of the scope struct (`holeAnalytics`, which the seam builds before the owner) and now
		/// and then a value only the root holds (`holeLogger`). Three further draws, each with a generator of its own,
		/// so that each draws as it did whatever the others draw: a second seam of the seam's module, `HoleOuter`,
		/// calls `HoleSeam` and passes its builder up, and the root fills `HoleOuter`'s (`holePassUpRandom`); where the seam
		/// builds the owner, at its one site, through an instantiator, at which the cycle a re-entry makes then closes, `HoleImpl`
		/// instantiates `HoleSeam` again, so its fill passes itself to the re-entering call, a quarter of those through
		/// `HoleMiddle`, which declares `holeLogger` above the call while `HoleImpl` reads the root's, which the tool
		/// rejects (`holeReentryRandom`); and the seam's own tree reaches the seam again through `HoleLoop`, a tenth of
		/// those binding `holeLogger` on the way while `HoleImpl` reads the root's, which the tool rejects
		/// (`holeSelfReentryRandom`). The files declaring `HoleImpl` and `HoleMiddle` say on their first line that they
		/// fill a hole, so that `GraphFuzzerFixture.withoutHoles` can declare them in the seam's module instead: the
		/// visible build the value oracle compares with. `holeRandom` draws only for this pass, which runs last.
		private mutating func addingHoleShapes(to declarations: [TypeDeclaration]) -> [TypeDeclaration] {
			guard features.contains(.generateDependencyTree), holeRandom.percentChance(33) else { return declarations }
			var declarations = declarations
			let conformances = sendability == .mixed ? ["@unchecked Sendable"] : []
			func name(_ suffix: String) -> String {
				"\(prefix)\(suffix)"
			}
			func instantiable(_ suffix: String, module: GraphFuzzerModule, properties: [PropertyDeclaration] = []) -> TypeDeclaration {
				var declaration = TypeDeclaration(name: name(suffix), instantiableArguments: [], properties: properties, declaresHelperTypes: false, additionalConformances: conformances)
				declaration.module = module
				return declaration
			}
			/// The wrappers a type of the graph can hold, as its sendability allows.
			let instantiators = switch sendability {
			case .nonSendable:
				["Instantiator"]
			case .sendable:
				["SendableInstantiator"]
			case .mixed:
				["Instantiator", "SendableInstantiator"]
			}
			let lazyWrappers = switch sendability {
			case .nonSendable:
				["LazilyInstantiated"]
			case .sendable:
				["SendableLazilyInstantiated"]
			case .mixed:
				["LazilyInstantiated", "SendableLazilyInstantiated"]
			}
			let serviceName = name("HoleService")
			let analyticsName = name("HoleAnalytics")
			let loggerName = name("HoleLogger")
			let seamName = name("HoleSeam")
			var seam = instantiable("HoleSeam", module: .seamModule, properties: [PropertyDeclaration(attribute: "@Instantiated", label: "holeAnalytics", type: analyticsName)])
			seam.instantiableArguments = ["generateDependencyTree: true"]
			seam.additionalDeclarations.append("public protocol \(serviceName)\(helperTypesAreSendable ? ": Sendable" : "") {}")
			var seamModuleDeclarations = [instantiable("HoleAnalytics", module: .seamModule), instantiable("HoleLogger", module: .seamModule)]
			let holeProperty = PropertyDeclaration(attribute: "@Instantiated", label: "holeService", type: "any \(serviceName)")
			// The owner: the seam itself, or `HoleOwner`, reached by value or through a wrapper, now and then at two sites.
			// A tree that reaches the seam again closes the cycle at the first property it repeats, which must be an
			// instantiator, so a re-entry is drawn only where the seam builds the owner through one.
			var ownerIsBuiltByInstantiator = false
			if holeRandom.percentChance(25) {
				seam.properties.append(holeProperty)
			} else {
				let owner = instantiable("HoleOwner", module: .seamModule, properties: [holeProperty, PropertyDeclaration(attribute: "@Received", label: "holeAnalytics", type: analyticsName)])
				seamModuleDeclarations.append(owner)
				let wrapperRoll = holeRandom.integer(in: 0...3)
				ownerIsBuiltByInstantiator = wrapperRoll == 1 || wrapperRoll == 2
				let ownerProperty = switch wrapperRoll {
				case 0:
					PropertyDeclaration(attribute: "@Instantiated", label: "holeOwner", type: owner.name)
				case 1, 2:
					PropertyDeclaration(attribute: "@Instantiated", label: "holeOwnerBuilder", type: "\(holeRandom.element(of: instantiators))<\(owner.name)>")
				default:
					PropertyDeclaration(attribute: "@Instantiated", label: "holeOwner", type: "\(holeRandom.element(of: lazyWrappers))<\(owner.name)>")
				}
				seam.properties.append(ownerProperty)
				if holeRandom.percentChance(20) {
					// A second site, built by value, at which a re-entry from its fill would close a constant cycle.
					seam.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "holeSecondOwner", type: owner.name))
					ownerIsBuiltByInstantiator = false
				}
			}
			var impl = instantiable("HoleImpl", module: .samePackageCaller)
			impl.instantiableArguments = ["fulfillingAdditionalTypes: [\(serviceName).self]"]
			impl.additionalConformances.append(serviceName)
			impl.fillsHole = true
			if holeRandom.percentChance(50) {
				impl.properties.append(PropertyDeclaration(attribute: "@Received", label: "holeAnalytics", type: analyticsName))
			}
			var readsRootLogger = holeRandom.percentChance(25)
			var callerDeclarations = [TypeDeclaration]()

			// A second seam of the seam's module that calls `HoleSeam`, whose builder it passes up.
			var calledSeamName = seamName
			if holePassUpRandom.percentChance(25) {
				var outer = instantiable("HoleOuter", module: .seamModule, properties: [PropertyDeclaration(attribute: "@Instantiated", label: "holeSeam", type: seamName)])
				outer.instantiableArguments = ["generateDependencyTree: true"]
				seamModuleDeclarations.append(outer)
				calledSeamName = outer.name
			}
			// `HoleImpl` instantiates `HoleSeam` again, directly or, a quarter of the time, through `HoleMiddle`, which
			// declares `holeLogger` above the call while `HoleImpl` reads the root's. Every roll is made whatever the base
			// draw, so the draw's generator is consumed the same way in every graph.
			let drawsReentry = holeReentryRandom.percentChance(40)
			let reentry = PropertyDeclaration(attribute: "@Instantiated", label: "holeSeamBuilder", type: "\(holeReentryRandom.element(of: instantiators))<\(seamName)>")
			let reentersThroughMiddle = holeReentryRandom.percentChance(25)
			if drawsReentry, ownerIsBuiltByInstantiator {
				if reentersThroughMiddle {
					var middle = instantiable("HoleMiddle", module: .samePackageCaller, properties: [PropertyDeclaration(attribute: "@Instantiated", label: "holeLogger", type: loggerName), reentry])
					middle.fillsHole = true
					callerDeclarations.append(middle)
					impl.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "holeMiddle", type: middle.name))
					readsRootLogger = true
				} else {
					impl.properties.append(reentry)
				}
			}
			// The seam's own tree reaches the seam again through `HoleLoop`, a tenth of the time binding `holeLogger`.
			if holeSelfReentryRandom.percentChance(5) {
				var loop = instantiable("HoleLoop", module: .seamModule, properties: [PropertyDeclaration(attribute: "@Instantiated", label: "holeSeamBuilder", type: "\(holeSelfReentryRandom.element(of: instantiators))<\(seamName)>")])
				if holeSelfReentryRandom.percentChance(10) {
					loop.properties.insert(PropertyDeclaration(attribute: "@Instantiated", label: "holeLogger", type: loggerName), at: 0)
					readsRootLogger = true
				}
				seamModuleDeclarations.append(loop)
				seam.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "holeLoopBuilder", type: "\(holeSelfReentryRandom.element(of: instantiators))<\(loop.name)>"))
			}
			if readsRootLogger {
				impl.properties.append(PropertyDeclaration(attribute: "@Received", label: "holeLogger", type: loggerName))
				declarations[0].properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "holeLogger", type: loggerName))
			}
			declarations[0].properties.append(PropertyDeclaration(attribute: "@Instantiated", label: calledSeamName == seamName ? "holeSeam" : "holeOuter", type: calledSeamName))
			return declarations + [seam] + seamModuleDeclarations + [impl] + callerDeclarations
		}

		private static let holeRandomSeedMask: UInt64 = 0x686F6C655F726E64
		private static let holePassUpRandomSeedMask: UInt64 = 0x686F6C6550617373
		private static let holeReentryRandomSeedMask: UInt64 = 0x686F6C6552656E74
		private static let holeSelfReentryRandomSeedMask: UInt64 = 0x686F6C6553656C66

		// MARK: Extension

		/// An `@Instantiable` extension of a type that is not itself `@Instantiable`, whose `instantiate(…)` has
		/// default-valued parameters and now and then receives a property, and an `@Instantiated` property of it on
		/// one of `declarations`, a root or a type of the graph. A default-valued parameter is not a dependency.
		private mutating func extensionDeclarationSource(addingPropertyToOneOf declarations: inout [TypeDeclaration]) -> String {
			// A root or a type of the graph, never a motif type, which `appendMotif` adds after them.
			let hostIndex = random.integer(in: 0...(rootCount + typeCount - 1))
			declarations[hostIndex].properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "ext", type: extensionTypeName))
			// The roots come first among the declarations. A root's properties are receivable below it.
			let candidates = hostIndex < rootCount
				? provided.filter { $0.providerIndex == nil }
				: receivableProperties(receiverIndex: hostIndex - rootCount)
			var parameters = [ParameterDeclaration]()
			if !candidates.isEmpty, random.percentChance(50) {
				let receivedProperty = random.element(of: candidates)
				parameters.append(ParameterDeclaration(name: receivedProperty.label, type: receivedProperty.type))
			}
			let defaultValuedParameters = [
				ParameterDeclaration(name: "title", type: "String", defaultValue: "\"default\""),
				ParameterDeclaration(name: "retryCount", type: "Int", defaultValue: "3"),
				ParameterDeclaration(name: "isEnabled", type: "Bool", defaultValue: "false"),
			]
			for _ in 0..<random.integer(in: 1...2) {
				let parameter = random.element(of: defaultValuedParameters)
				if !parameters.contains(parameter) {
					parameters.append(parameter)
				}
			}
			// An unlabeled default-valued parameter last, which a generated call leaves to its default.
			if random.percentChance(20) {
				parameters.append(ParameterDeclaration(argumentLabel: "_", name: "note", type: "String", defaultValue: "\"\""))
			}
			let instantiableAttribute = random.percentChance(30) ? "@Instantiable(generateMock: true)" : "@Instantiable"
			// When every parameter is stored, the extended type takes and stores what `instantiate(…)` is passed. In a
			// mixed graph that can be a wrapper that is not `Sendable`, so the type is then `@unchecked Sendable`, as the
			// graph's types are.
			let storedParameters = storesEveryParameter ? parameters : []
			let sendableConformance = switch (sendability, storedParameters.isEmpty) {
			case (.nonSendable, _):
				""
			case (.sendable, _), (.mixed, true):
				": Sendable"
			case (.mixed, false):
				": @unchecked Sendable"
			}
			var lines = [
				instantiableAttribute,
				"extension \(extensionTypeName): Instantiable {",
				"\tpublic static func instantiate(\(parameters.map(\.declaration).joined(separator: ", "))) -> \(extensionTypeName) {",
				"\t\t\(extensionTypeName)(\(storedParameters.map(\.argument).joined(separator: ", ")))",
				"\t}",
				"}",
				"",
				"public final class \(extensionTypeName)\(sendableConformance) {",
			]
			if storedParameters.isEmpty {
				lines.append("\tpublic init() {}")
			} else {
				lines.append("\tpublic init(\(storedParameters.map(\.storedDeclaration).joined(separator: ", "))) {")
				lines += storedParameters.map { "\t\tself.\($0.name) = \($0.name)" }
				lines.append("\t}")
				lines.append("")
				lines += storedParameters.map { "\tpublic let \($0.storedDeclaration)" }
			}
			lines.append("}")
			return lines.joined(separator: "\n") + "\n"
		}

		private var extensionTypeName: String {
			"\(prefix)Ext"
		}

		// MARK: Emission

		private func typeName(_ index: Int) -> String {
			"\(prefix)T\(index)"
		}

		private func protocolName(_ index: Int) -> String {
			"\(prefix)T\(index)Protocol"
		}

		private func erasedTypeName(_ index: Int) -> String {
			"\(prefix)AnyT\(index)"
		}

		private func property(for edge: InstantiationEdge) -> PropertyDeclaration {
			let target = edge.targetIndex
			let erasedAttribute = "@Instantiated(fulfilledByType: \"\(typeName(target))\", erasedToConcreteExistential: true)"
			let label = edge.labelIndex
			switch edge.kind {
			case .constant:
				return PropertyDeclaration(attribute: "@Instantiated", label: "t\(label)", type: typeName(target))
			case .erasedConstant:
				return PropertyDeclaration(attribute: erasedAttribute, label: "anyT\(label)", type: erasedTypeName(target))
			case .instantiator:
				let wrapper = edge.isSendable ? "SendableInstantiator" : "Instantiator"
				return PropertyDeclaration(attribute: "@Instantiated", label: "t\(label)Builder", type: "\(wrapper)<\(typeName(target))>")
			case .erasedInstantiator:
				let wrapper = edge.isSendable ? "SendableErasedInstantiator" : "ErasedInstantiator"
				let forwardedPropertiesType = forwardedProperties[target]?.type ?? "()"
				return PropertyDeclaration(attribute: erasedAttribute, label: "anyT\(label)Builder", type: "\(wrapper)<\(forwardedPropertiesType), \(erasedTypeName(target))>")
			case .lazilyInstantiated:
				return PropertyDeclaration(attribute: "@Instantiated", label: "lazyT\(label)", type: "\(lazilyInstantiatedWrapper(isSendable: edge.isSendable))<\(typeName(target))>")
			case .erasedLazilyInstantiated:
				return PropertyDeclaration(attribute: erasedAttribute, label: "lazyAnyT\(label)", type: "\(lazilyInstantiatedWrapper(isSendable: edge.isSendable))<\(erasedTypeName(target))>")
			}
		}

		/// A type of the graph's that is not `@Instantiable`, which only a forwarded property can provide. It conforms
		/// to `Instantiable`, so that an `Instantiator` of it compiles.
		private var valueTypeName: String {
			"\(prefix)Value"
		}

		/// The label of the unprovided wrappers of `valueTypeName` that types receive.
		static let unbuildableWrapperLabel = "items"

		/// The wrappers a type can receive `valueTypeName` in under `unbuildableWrapperLabel`. A
		/// `SendableLazilyInstantiated` requires a `Sendable` instance, which only a graph with `Sendable` helper
		/// types declares, and a `Sendable` graph's types store only `Sendable` wrappers.
		private var unbuildableWrappers: [String] {
			switch sendability {
			case .nonSendable:
				["Instantiator", "LazilyInstantiated"]
			case .sendable:
				["SendableInstantiator", "SendableLazilyInstantiated"]
			case .mixed:
				["Instantiator", "LazilyInstantiated", "SendableInstantiator", "SendableLazilyInstantiated"]
			}
		}

		private func lazilyInstantiatedWrapper(isSendable: Bool) -> String {
			isSendable ? "SendableLazilyInstantiated" : "LazilyInstantiated"
		}

		/// Whether the graph's helper types are `Sendable`, as a `SendableLazilyInstantiated` of them requires.
		private var helperTypesAreSendable: Bool {
			switch sendability {
			case .nonSendable:
				false
			case .sendable, .mixed:
				true
			}
		}

		private func source(of declaration: TypeDeclaration) -> String {
			let instantiableAttribute = declaration.instantiableArguments.isEmpty
				? "@Instantiable"
				: "@Instantiable(\(declaration.instantiableArguments.joined(separator: ", ")))"
			let protocolName = declaration.name + "Protocol"
			let baseConformances = switch (sendability, declaration.declaresHelperTypes) {
			case (.nonSendable, true), (.sendable, true):
				"Instantiable, \(protocolName)"
			case (.mixed, true):
				// The type stores wrappers that are not `Sendable`.
				"Instantiable, \(protocolName), @unchecked Sendable"
			case (.sendable, false):
				"Instantiable, Sendable"
			case (.nonSendable, false), (.mixed, false):
				"Instantiable"
			}
			let conformances = ([baseConformances] + declaration.additionalConformances).joined(separator: ", ")
			var lines = [instantiableAttribute, "\(declaration.access.modifier)final class \(declaration.name): \(conformances) {"]
			// A function-typed parameter is stored, so it escapes.
			let parameters = (declaration.properties.map { "\($0.label): \(GraphFuzzerSpelling.isFunctionType($0.type) ? "@escaping " : "")\($0.type)" } + declaration.defaultValuedParameters.map(\.declaration)).joined(separator: ", ")
			// The initializer is no wider, once its type caps it, than the narrowest type it names, so that the fixture
			// compiles; a spelled access its type already caps is kept.
			let spelledInitializerAccess = declaration.initializerAccess ?? declaration.access
			let narrowestNamedAccess = (declaration.properties.map(\.type) + declaration.defaultValuedParameters.map(\.type)).map(narrowestProofTypeAccess(in:)).min() ?? .public
			let initializerAccess = min(spelledInitializerAccess, declaration.effectiveAccess) <= narrowestNamedAccess ? spelledInitializerAccess : narrowestNamedAccess
			let storedParameters = storesEveryParameter ? declaration.defaultValuedParameters : []
			if declaration.properties.isEmpty, storedParameters.isEmpty {
				lines.append("\t\(initializerAccess.modifier)init(\(parameters)) {}")
			} else {
				lines.append("\t\(initializerAccess.modifier)init(\(parameters)) {")
				lines += declaration.properties.map { "\t\tself.\($0.label) = \($0.label)" }
				lines += storedParameters.map { "\t\tself.\($0.name) = \($0.name)" }
				lines.append("\t}")
				lines.append("")
				lines += declaration.properties.map { "\t\($0.attribute) let \($0.label): \($0.type)" }
				lines += storedParameters.map { "\tlet \($0.storedDeclaration)" }
			}
			lines.append("}")
			if let enclosingExtension = declaration.enclosingExtension {
				lines = ["\(enclosingExtension) {"] + lines.map { $0.isEmpty ? $0 : "\t" + $0 } + ["}"]
			}
			if declaration.declaresHelperTypes {
				let erasedName = declaration.name.replacingOccurrences(of: "\(prefix)T", with: "\(prefix)AnyT")
				lines += [
					"",
					"public protocol \(protocolName): AnyObject\(helperTypesAreSendable ? ", Sendable" : "") {}",
					"",
					"public final class \(erasedName)\(helperTypesAreSendable ? ": Sendable" : "") {",
					"\tpublic init(_ value: \(declaration.name)) {",
					"\t\tself.value = value",
					"\t}",
					"",
					"\tpublic let value: \(declaration.name)",
					"}",
				]
			} else if declaration.name == "\(prefix)Root0" {
				lines += ["", "public final class \(valueTypeName): Instantiable\(helperTypesAreSendable ? ", Sendable" : "") {}"]
				for index in 0..<unbuildableTypeCount {
					lines += ["", "public final class \(unbuildableTypeName(index))\(helperTypesAreSendable ? ": Sendable" : "") {}"]
				}
			}
			for additionalDeclaration in declaration.additionalDeclarations {
				lines += ["", additionalDeclaration]
			}
			return (declaration.module.map { $0.fileHeader(omitsPackageName: modulesOmittingPackageName.contains($0), fillsHole: declaration.fillsHole) } ?? "") + lines.joined(separator: "\n") + "\n"
		}

		/// The narrowest access of the types `addingAccessProofShapes` declares narrower than `public` that `type` names,
		/// or `public` when it names none.
		private func narrowestProofTypeAccess(in type: String) -> AccessLevel {
			guard !proofTypeAccess.isEmpty else { return .public }
			var narrowest = AccessLevel.public
			var name = ""
			for character in type + " " {
				if character.isLetter || character.isNumber || character == "_" || character == "." {
					name.append(character)
				} else {
					if let access = proofTypeAccess[name] {
						narrowest = min(narrowest, access)
					}
					name = ""
				}
			}
			return narrowest
		}
	}
}

// MARK: - Feature detection

/// The kinds of declarations a batch of graphs must exercise. They are detected from the emitted source, not
/// from the generator's own bookkeeping, so a generator that stops emitting a kind cannot hide it.
enum GraphFuzzerFeature: String, CaseIterable, Comparable {
	case constantProperty
	case erasedConstantProperty
	case instantiatorProperty
	case sendableInstantiatorProperty
	case erasedInstantiatorProperty
	case sendableErasedInstantiatorProperty
	case lazilyInstantiatedProperty
	case sendableLazilyInstantiatedProperty
	case erasedLazilyInstantiatedProperty
	case forwardedLazilyInstantiatedProperty
	/// A receive of the instance a `LazilyInstantiated` property under the same label creates.
	case receivedLazilyInstantiatedInstance
	case forwardedProperty
	case optionalForwardedProperty
	case requiredReceive
	case requiredOptionalReceive
	case onlyIfAvailableReceive
	case requiredAlias
	case onlyIfAvailableAlias
	/// An alias, required or `onlyIfAvailable`, of an `onlyIfAvailable` alias, which a receiver that requires it needs
	/// created in turn.
	case aliasOfOnlyIfAvailableAlias
	/// An alias whose `ofType:` is the optional form of a property declared with the label it names (`ofType: X?.self`
	/// of `x: X`), which validation resolves to that property by its unwrapped form.
	case aliasOfOptionalFormOfProperty
	case erasedAlias
	case multipleRoots
	case generateMock
	case lazyCycle
	case sameLabelWithDifferentTypes
	/// An instantiated property labeled as a name a generated mock gives a binding of its own, such as `t1_S0_T1`.
	case labelSpelledAsGeneratedName
	/// An instantiated property of a type that is not `@Instantiable`, which a mock takes as a parameter.
	case dependencyMockCannotBuild
	/// A receive of such a property beneath the type that instantiates it, which a mock passes the same parameter.
	case dependencyMockCannotBuildReceivedBeneathItsOwner
	/// A receive of such a property as a `LazilyInstantiated` or `SendableLazilyInstantiated`, by a type a mocked owner
	/// of the property receives, whose mock wraps the parameter it takes for the property.
	case dependencyMockCannotBuildReceivedLazilyBesideItsMockedOwner
	/// A mocked owner's lazily instantiated property of a type that is not `@Instantiable`, which a type the owner
	/// receives receives as the other wrapper kind, which the owner's parameter cannot make.
	case dependencyMockCannotBuildLazilyInstantiatedReceivedAsOtherKindBesideItsMockedOwner
	/// A graph whose properties use both `Sendable` wrappers and wrappers that are not `Sendable`.
	case sendableAndNonSendableWrappers
	/// A type with `generateMock: true` on a cycle that an instantiator makes lazy.
	case mockedTypeOnLazyCycle
	/// Two types that each receive the other only if available.
	case typesReceivingEachOtherOnlyIfAvailable
	/// One label received as a type and as an instantiator of that type.
	case labelReceivedAsInstanceAndAsInstantiator
	/// One label received as two different wrappers of a type that is not `@Instantiable`.
	case sameLabelReceivedAsDifferentUnbuildableWrappers
	/// A received `ErasedInstantiator` or `SendableErasedInstantiator`.
	case receivedErasedInstantiator
	/// A forwarded `ErasedInstantiator` or `SendableErasedInstantiator`.
	case forwardedErasedInstantiator
	/// A default-valued parameter of an extension's `instantiate(…)` method.
	case defaultValuedInstantiateParameter
	/// A type built through a `Sendable` wrapper whose subtree has a labeled default-valued initializer parameter and
	/// a dependency the mock cannot build, both of types that are not `Sendable`.
	case nonSendableValuesInsideSendableBuilder
	/// A type declared with `generateDependencyTree: true`, whose tree SafeDI generates in an initializer of its own
	/// that every tree reaching it calls. Drawn only with the `generateDependencyTree` generator feature on; what its
	/// initializer takes is a `GraphFuzzerSeamOutputFeature`, read from the generated code.
	case generateDependencyTree

	/// The features only a graph drawn with the `generateDependencyTree` generator feature has.
	static let seamCases: [GraphFuzzerFeature] = [.generateDependencyTree]

	/// The features a graph drawn without any generator feature can have, which the smoke batch must exercise.
	static var baseCases: [GraphFuzzerFeature] {
		allCases.filter { !seamCases.contains($0) }
	}

	static func < (lhs: GraphFuzzerFeature, rhs: GraphFuzzerFeature) -> Bool {
		lhs.rawValue < rhs.rawValue
	}

	static func features(of fixture: GraphFuzzerFixture) -> Set<GraphFuzzerFeature> {
		var features = Set<GraphFuzzerFeature>()
		var rootCount = 0
		var typesByLabel = [String: Set<String>]()
		var lazilyInstantiatedInstanceTypesByLabel = [String: Set<String>]()
		var receivedTypesByLabel = [String: Set<String>]()
		var instantiationEdges = [GraphFuzzerInstantiationEdge]()
		var unbuildableWrapperTypesByLabel = [String: Set<String>]()
		var usesSendableWrapper = false
		var usesNonSendableWrapper = false
		var mockedTypeNames = Set<String>()
		var onlyIfAvailableReceivedTypesByTypeName = [String: Set<String>]()
		var onlyIfAvailableAliasLabels = Set<String>()
		var aliasFulfillingLabels = Set<String>()
		/// The non-optional types of the instantiated and forwarded properties under each label.
		var nonOptionalTypesByLabel = [String: Set<String>]()
		/// The types whose optional form an alias names as its `ofType:`, by the label the alias is fulfilled by.
		var aliasedOptionalFormTypesByLabel = [String: Set<String>]()
		/// The properties of types that are not `@Instantiable` each type instantiates, and those each type receives, in
		/// their non-optional form, spelled `label: Type`.
		var unbuildablePropertiesInstantiatedByTypeName = [String: Set<String>]()
		var unbuildablePropertiesReceivedByTypeName = [String: Set<String>]()
		/// The properties of types that are not `@Instantiable` each type receives as a lazily instantiated wrapper,
		/// spelled `label: Type` with the wrapped type, and the types each type receives.
		var unbuildablePropertiesReceivedLazilyByTypeName = [String: Set<String>]()
		/// The same receives, spelled `label: Wrapper<Type>`.
		var unbuildableWrapperPropertiesReceivedByTypeName = [String: Set<String>]()
		var receivedTypeNamesByTypeName = [String: Set<String>]()
		for content in fixture.swiftFileContent {
			var currentTypeName: String?
			var nextTypeIsMocked = false
			for line in GraphFuzzerSourceLine.lines(of: content) {
				switch line {
				case let .instantiableAttribute(arguments):
					if arguments.contains("isRoot: true") {
						rootCount += 1
					}
					if arguments.contains("generateDependencyTree: true") {
						features.insert(.generateDependencyTree)
					}
					nextTypeIsMocked = arguments.contains("generateMock: true")
					if nextTypeIsMocked {
						features.insert(.generateMock)
					}
				case let .typeDeclaration(name):
					currentTypeName = name
					if nextTypeIsMocked {
						mockedTypeNames.insert(name)
					}
				case let .instantiateMethod(parameters):
					if parameters.contains(" = ") {
						features.insert(.defaultValuedInstantiateParameter)
					}
				case let .property(attribute, label, type):
					// A receive of `x: T?` names the same type as `x: T` does, and so does a receive of the instance of
					// `x: LazilyInstantiated<T>`.
					let nonOptionalType = type.hasSuffix("?") ? String(type.dropLast()) : type
					let instanceType = Self.lazilyInstantiatedInstanceType(of: nonOptionalType)
					typesByLabel[label, default: []].insert(instanceType ?? nonOptionalType)
					if let instanceType, attribute.hasPrefix("@Instantiated") || attribute == "@Forwarded" {
						lazilyInstantiatedInstanceTypesByLabel[label, default: []].insert(instanceType)
					}
					if attribute == "@Received(onlyIfAvailable: true)", let currentTypeName {
						onlyIfAvailableReceivedTypesByTypeName[currentTypeName, default: []].insert(nonOptionalType)
					}
					if attribute.hasPrefix("@Instantiated") || attribute == "@Forwarded", !type.hasSuffix("?") {
						nonOptionalTypesByLabel[label, default: []].insert(type)
					}
					if let fulfillingLabelRange = attribute.range(of: "fulfilledByDependencyNamed: \"") {
						let fulfillingLabel = String(attribute[fulfillingLabelRange.upperBound...].prefix { $0 != "\"" })
						aliasFulfillingLabels.insert(fulfillingLabel)
						if attribute.contains("onlyIfAvailable: true") {
							onlyIfAvailableAliasLabels.insert(label)
						}
						// The `ofType:` argument is spelled `Type.self`, and no type the generator emits contains a period.
						if let fulfillingTypeRange = attribute.range(of: "ofType: ") {
							let fulfillingType = attribute[fulfillingTypeRange.upperBound...].prefix { $0 != "." }
							if fulfillingType.hasSuffix("?") {
								aliasedOptionalFormTypesByLabel[fulfillingLabel, default: []].insert(String(fulfillingType.dropLast()))
							}
						}
					}
					if attribute == "@Received" || attribute == "@Received(onlyIfAvailable: true)" {
						receivedTypesByLabel[label, default: []].insert(nonOptionalType)
						if nonOptionalType.hasSuffix("<\(fixture.typeNamePrefix)Value>") {
							unbuildableWrapperTypesByLabel[label, default: []].insert(nonOptionalType)
						}
					}
					features.formUnion(Self.features(ofPropertyWithAttribute: attribute, type: type))
					if ["SendableInstantiator<", "SendableErasedInstantiator<", "SendableLazilyInstantiated<"].contains(where: type.hasPrefix) {
						usesSendableWrapper = true
					} else if ["Instantiator<", "ErasedInstantiator<", "LazilyInstantiated<"].contains(where: type.hasPrefix) {
						usesNonSendableWrapper = true
					}
					if attribute.hasPrefix("@Instantiated"), label.contains("_") {
						features.insert(.labelSpelledAsGeneratedName)
					}
					if attribute.hasPrefix("@Instantiated"), type.contains("Unbuildable") {
						features.insert(.dependencyMockCannotBuild)
						if let currentTypeName {
							unbuildablePropertiesInstantiatedByTypeName[currentTypeName, default: []].insert("\(label): \(type)")
						}
					}
					if attribute == "@Received" || attribute == "@Received(onlyIfAvailable: true)", nonOptionalType.contains("Unbuildable"), let currentTypeName {
						if let instanceType {
							unbuildablePropertiesReceivedLazilyByTypeName[currentTypeName, default: []].insert("\(label): \(instanceType)")
							unbuildableWrapperPropertiesReceivedByTypeName[currentTypeName, default: []].insert("\(label): \(nonOptionalType)")
						} else {
							unbuildablePropertiesReceivedByTypeName[currentTypeName, default: []].insert("\(label): \(nonOptionalType)")
						}
					}
					if attribute == "@Received", let currentTypeName {
						receivedTypeNamesByTypeName[currentTypeName, default: []].insert(type)
					}
					// Only the `Sendable` builder motif declares an `Engine`, beneath a type a `SendableInstantiator` builds.
					if attribute.hasPrefix("@Instantiated"), type == "\(fixture.typeNamePrefix)Engine" {
						features.insert(.nonSendableValuesInsideSendableBuilder)
					}
					if attribute.hasPrefix("@Instantiated"), let currentTypeName {
						instantiationEdges.append(GraphFuzzerInstantiationEdge(
							source: currentTypeName,
							target: Self.instantiatedTypeName(attribute: attribute, type: type),
							// Only an instantiator breaks a cycle; a `LazilyInstantiated` is validated as a constant.
							isLazy: type.contains("Instantiator<"),
						))
					}
				case .other:
					break
				}
			}
		}
		if rootCount > 1 {
			features.insert(.multipleRoots)
		}
		if typesByLabel.values.contains(where: { $0.count > 1 }) {
			features.insert(.sameLabelWithDifferentTypes)
		}
		if receivedTypesByLabel.contains(where: { label, types in
			!types.isDisjoint(with: lazilyInstantiatedInstanceTypesByLabel[label] ?? [])
		}) {
			features.insert(.receivedLazilyInstantiatedInstance)
		}
		if GraphFuzzerInstantiationEdge.containsLazyCycle(instantiationEdges) {
			features.insert(.lazyCycle)
		}
		if unbuildableWrapperTypesByLabel.values.contains(where: { $0.count > 1 }) {
			features.insert(.sameLabelReceivedAsDifferentUnbuildableWrappers)
		}
		if usesSendableWrapper, usesNonSendableWrapper {
			features.insert(.sendableAndNonSendableWrappers)
		}
		if mockedTypeNames.contains(where: { GraphFuzzerInstantiationEdge.isOnLazyCycle($0, edges: instantiationEdges) }) {
			features.insert(.mockedTypeOnLazyCycle)
		}
		if onlyIfAvailableReceivedTypesByTypeName.contains(where: { typeName, receivedTypes in
			receivedTypes.contains { onlyIfAvailableReceivedTypesByTypeName[$0]?.contains(typeName) == true }
		}) {
			features.insert(.typesReceivingEachOtherOnlyIfAvailable)
		}
		if receivedTypesByLabel.values.contains(where: { types in
			types.contains { types.contains("Instantiator<\($0)>") || types.contains("SendableInstantiator<\($0)>") }
		}) {
			features.insert(.labelReceivedAsInstanceAndAsInstantiator)
		}
		if !aliasFulfillingLabels.isDisjoint(with: onlyIfAvailableAliasLabels) {
			features.insert(.aliasOfOnlyIfAvailableAlias)
		}
		if aliasedOptionalFormTypesByLabel.contains(where: { label, types in
			!types.isDisjoint(with: nonOptionalTypesByLabel[label] ?? [])
		}) {
			features.insert(.aliasOfOptionalFormOfProperty)
		}
		if unbuildablePropertiesInstantiatedByTypeName.contains(where: { ownerName, instantiatedProperties in
			unbuildablePropertiesReceivedByTypeName.contains { receiverName, receivedProperties in
				receiverName != ownerName
					&& !receivedProperties.isDisjoint(with: instantiatedProperties)
					&& GraphFuzzerInstantiationEdge.reaches(from: ownerName, to: receiverName, through: instantiationEdges)
			}
		}) {
			features.insert(.dependencyMockCannotBuildReceivedBeneathItsOwner)
		}
		if unbuildablePropertiesInstantiatedByTypeName.contains(where: { ownerName, instantiatedProperties in
			mockedTypeNames.contains(ownerName) && receivedTypeNamesByTypeName[ownerName, default: []].contains { receivedTypeName in
				!unbuildablePropertiesReceivedLazilyByTypeName[receivedTypeName, default: []].isDisjoint(with: instantiatedProperties)
			}
		}) {
			features.insert(.dependencyMockCannotBuildReceivedLazilyBesideItsMockedOwner)
		}
		/// `label: Wrapper<Type>` with the other wrapper kind, or `nil` when `property` is not so spelled.
		func otherWrapperKind(of property: String) -> String? {
			if property.contains(": SendableLazilyInstantiated<") {
				property.replacingOccurrences(of: ": SendableLazilyInstantiated<", with: ": LazilyInstantiated<")
			} else if property.contains(": LazilyInstantiated<") {
				property.replacingOccurrences(of: ": LazilyInstantiated<", with: ": SendableLazilyInstantiated<")
			} else {
				nil
			}
		}
		if unbuildablePropertiesInstantiatedByTypeName.contains(where: { ownerName, instantiatedProperties in
			mockedTypeNames.contains(ownerName) && receivedTypeNamesByTypeName[ownerName, default: []].contains { receivedTypeName in
				!unbuildableWrapperPropertiesReceivedByTypeName[receivedTypeName, default: []].isDisjoint(with: instantiatedProperties.compactMap(otherWrapperKind(of:)))
			}
		}) {
			features.insert(.dependencyMockCannotBuildLazilyInstantiatedReceivedAsOtherKindBesideItsMockedOwner)
		}
		return features
	}

	/// The seam shapes drawn in `fixture`, read from its source: the seams, their `@Instantiated` children, and the
	/// properties of each.
	static func seamDrawFeatures(of fixture: GraphFuzzerFixture) -> Set<GraphFuzzerSeamDrawFeature> {
		var seamNames = Set<String>()
		var mockedTypeNames = Set<String>()
		var childNamesBySeam = [String: Set<String>]()
		var propertiesByType = [String: [(attribute: String, label: String, type: String)]]()
		for content in fixture.swiftFileContent {
			var nextTypeIsSeam = false
			var nextTypeIsMocked = false
			var currentType: String?
			for line in GraphFuzzerSourceLine.lines(of: content) {
				switch line {
				case let .instantiableAttribute(arguments):
					nextTypeIsSeam = arguments.contains("generateDependencyTree: true")
					nextTypeIsMocked = arguments.contains("generateMock: true")
				case let .typeDeclaration(name):
					currentType = name
					propertiesByType[name, default: []] += []
					if nextTypeIsSeam {
						seamNames.insert(name)
					}
					if nextTypeIsMocked {
						mockedTypeNames.insert(name)
					}
					nextTypeIsSeam = false
					nextTypeIsMocked = false
				case let .property(attribute, label, type):
					guard let currentType else { continue }
					propertiesByType[currentType, default: []].append((attribute, label, type))
					if seamNames.contains(currentType), attribute.hasPrefix("@Instantiated") {
						childNamesBySeam[currentType, default: []].insert(builtTypeName(ofPropertyWithAttribute: attribute, type: type))
					}
				case .instantiateMethod, .other:
					break
				}
			}
		}
		var features = Set<GraphFuzzerSeamDrawFeature>()
		let allProperties = propertiesByType.values.flatMap(\.self)
		func isWrapper(_ type: String) -> Bool {
			type.hasPrefix("LazilyInstantiated<") || type.hasPrefix("SendableLazilyInstantiated<")
		}
		for property in allProperties {
			if property.label == "seamChild" {
				features.insert(.synthesizedChild)
			} else if property.label == "seamShared", property.attribute == "@Instantiated" {
				features.insert(.synthesizedSharedProvider)
			} else if property.label == "seamLazy", property.attribute == "@Instantiated" {
				features.insert(.synthesizedLazyProvider)
			} else if property.label == "seamHeld", property.attribute == "@Instantiated" {
				features.insert(.synthesizedHeldProvider)
			} else if property.attribute.contains("fulfilledByDependencyNamed"), property.label.hasSuffix("Seam") {
				features.insert(.renameOnSeamOrChild)
			} else if property.attribute.contains("fulfilledByDependencyNamed"), property.label.hasSuffix("Above") {
				features.insert(.renameAboveSeam)
			}
		}
		func otherKind(of wrapperType: String) -> String {
			wrapperType.hasPrefix("Sendable") ? String(wrapperType.dropFirst("Sendable".count)) : "Sendable\(wrapperType)"
		}
		/// The label an alias renames: the `fulfilledByDependencyNamed:` argument of `attribute`, or `nil`.
		func aliasedLabel(of attribute: String) -> String? {
			guard let range = attribute.range(of: "fulfilledByDependencyNamed: \"") else { return nil }
			return String(attribute[range.upperBound...].prefix { $0 != "\"" })
		}
		/// The names of every type beneath `childNames`, those types included, followed through `@Instantiated`.
		func treeTypeNames(beneath childNames: Set<String>) -> Set<String> {
			var treeTypeNames = Set<String>()
			var typeNamesToVisit = Array(childNames)
			while let typeName = typeNamesToVisit.popLast() {
				guard treeTypeNames.insert(typeName).inserted else { continue }
				for property in propertiesByType[typeName] ?? [] where property.attribute.hasPrefix("@Instantiated") {
					typeNamesToVisit.append(builtTypeName(ofPropertyWithAttribute: property.attribute, type: property.type))
				}
			}
			return treeTypeNames
		}
		for (seamName, childNames) in childNamesBySeam {
			if !treeTypeNames(beneath: childNames).isDisjoint(with: seamNames.subtracting([seamName])) {
				features.insert(.innerSeam)
			}
			// The labels the seam's children receive by value, whatever the type, or alias, or the seam aliases: a
			// by-value form of the label beside an optional wrapper receive, which collides.
			var byValueLabels = Set<String>()
			for property in propertiesByType[seamName] ?? [] {
				if let aliasedLabel = aliasedLabel(of: property.attribute) {
					byValueLabels.insert(aliasedLabel)
				}
			}
			for childName in childNames {
				for property in propertiesByType[childName] ?? [] where property.attribute.hasPrefix("@Received") {
					if let aliasedLabel = aliasedLabel(of: property.attribute) {
						byValueLabels.insert(aliasedLabel)
					} else if !isWrapper(property.type) {
						byValueLabels.insert(property.label)
					}
				}
			}
			let byValueLabelsInTree = Set(treeTypeNames(beneath: childNames).flatMap { typeName in
				(propertiesByType[typeName] ?? []).filter { $0.attribute.hasPrefix("@Received") && !$0.attribute.contains("fulfilledByDependencyNamed") && !isWrapper($0.type) }.map(\.label)
			})
			var optionalWrapperLabels = Set<String>()
			for childName in childNames {
				for property in propertiesByType[childName] ?? [] where property.attribute.hasPrefix("@Received") && !property.attribute.contains("fulfilledByDependencyNamed") {
					let instanceType = String(property.type.dropLast(property.type.hasSuffix("?") ? 1 : 0))
					if isWrapper(property.type) {
						let unwrapped = String(instanceType.drop { $0 != "<" }.dropFirst().dropLast())
						let isOnlyIfAvailable = property.attribute.contains("onlyIfAvailable")
						if isOnlyIfAvailable {
							optionalWrapperLabels.insert(property.label)
						}
						// Held by value somewhere, as a non-optional wrapper's instance would not be.
						if isOnlyIfAvailable, allProperties.contains(where: { $0.attribute == "@Instantiated" && $0.label == property.label && $0.type == unwrapped }) {
							if !byValueLabels.contains(property.label) {
								features.insert(.instanceHeldByCaller)
							}
						} else if isOnlyIfAvailable, allProperties.contains(where: { $0.attribute == "@Instantiated" && $0.label == property.label && $0.type == otherKind(of: instanceType) }) {
							features.insert(.otherKindWrapperReceiveBeneathSeam)
						} else {
							features.insert(.wrapperReceiveBeneathSeam)
							if !isOnlyIfAvailable, !property.type.hasSuffix("?"), byValueLabelsInTree.contains(property.label) {
								features.insert(.requiredWrapperProvidingByValueForm)
							}
						}
					} else if allProperties.contains(where: { $0.attribute == "@Instantiated" && $0.label == property.label && isWrapper($0.type) }) {
						features.insert(.instanceReceiveBeneathSeam)
					}
				}
			}
			if !byValueLabels.intersection(optionalWrapperLabels).isEmpty {
				features.insert(.collidingFormsBeneathSeam)
			}
			// The spelled value: which way the seam's signature takes it.
			let label = GraphFuzzerSpelling.label
			let ownProperties = (propertiesByType[seamName] ?? []).filter { $0.label == label }
			if ownProperties.contains(where: { $0.attribute == "@Forwarded" }) {
				features.insert(.spelledOwnForwarded)
			}
			if ownProperties.contains(where: { $0.attribute.hasPrefix("@Received") }) {
				features.insert(.spelledOwnReceived)
			}
			let treeReceives = treeTypeNames(beneath: childNames).flatMap { propertiesByType[$0] ?? [] }.filter {
				$0.label == label && $0.attribute.hasPrefix("@Received")
			}
			if ownProperties.isEmpty, !treeReceives.isEmpty {
				features.insert(treeReceives.contains { !$0.attribute.contains("onlyIfAvailable") } ? .spelledRequiredPassThrough : .spelledOnlyIfAvailablePassThrough)
			}
		}
		for property in allProperties {
			if property.label == GraphFuzzerSpelling.label, property.attribute == "@Forwarded", let spelling = GraphFuzzerSpelling.spelling(ofType: property.type) {
				features.insert(spelling.drawFeature)
			}
			if aliasedLabel(of: property.attribute) == GraphFuzzerSpelling.label {
				features.insert(.spelledAliasFulfillingProperty)
			}
		}
		// `addingSpelledProperties`' second child and mocked tree.
		if propertiesByType.keys.contains(where: { $0.hasSuffix("SpellSibling") }) {
			features.insert(.spelledOptionalFormOnSibling)
		}
		if mockedTypeNames.contains(where: { $0.hasSuffix("SpellChild") || $0.hasSuffix("SpellSeam") }) {
			features.insert(.spelledTreeMocked)
		}
		// `addingUncreatedAliasShapes`' shapes, read from its types, which only that pass declares.
		func properties(ofTypeNamed suffix: String) -> [(attribute: String, label: String, type: String)] {
			propertiesByType.first { $0.key.hasSuffix(suffix) }?.value ?? []
		}
		func declaresType(named suffix: String) -> Bool {
			propertiesByType.keys.contains { $0.hasSuffix(suffix) }
		}
		let aliasProperties = (properties(ofTypeNamed: "AliasDetail") + properties(ofTypeNamed: "AliasSeam")).filter {
			($0.label == "aliasAuth" || $0.label == "aliasToken") && aliasedLabel(of: $0.attribute) == "aliasToken"
		}
		let aliasKeepsLabel = aliasProperties.contains { $0.label == "aliasToken" }
		if aliasKeepsLabel {
			features.insert(.uncreatedAliasLabelKeepingOptionalAlias)
		}
		if !aliasProperties.isEmpty {
			if properties(ofTypeNamed: "AliasSeam").contains(where: { ($0.label == "aliasAuth" || $0.label == "aliasToken") && aliasedLabel(of: $0.attribute) == "aliasToken" }) {
				features.insert(.uncreatedAliasOnSeamItself)
			}
			if aliasProperties.contains(where: { $0.attribute.contains("AliasValue?.self") }) {
				features.insert(.uncreatedAliasExactFormAlias)
			}
			if aliasProperties.contains(where: { !$0.attribute.contains("onlyIfAvailable") }) {
				features.insert(.uncreatedAliasAcceptedTwin)
			}
		}
		let readerProperties = properties(ofTypeNamed: "AliasReader")
		// Beneath an alias the seam declares, `AliasLeft`'s own `aliasToken` is nearer to a reader `AliasDetail` builds.
		let readerIsBeneathLeftsToken = properties(ofTypeNamed: "AliasSeam").contains { $0.label == "aliasToken" && aliasedLabel(of: $0.attribute) == "aliasToken" }
			&& properties(ofTypeNamed: "AliasLeft").contains { $0.label == "aliasToken" && $0.attribute == "@Instantiated" }
			&& !properties(ofTypeNamed: "AliasSeam").contains { ["aliasReader", "aliasReaderBuilder", "aliasPanel", "aliasMid"].contains($0.label) }
		for property in readerProperties {
			if property.label == "aliasAuth", aliasedLabel(of: property.attribute) == "aliasAuth" {
				features.insert(.uncreatedAliasLabelKeepingAliasReader)
			} else if property.label == "aliasAuth", property.attribute == "@Received" {
				features.insert(.uncreatedAliasRequiredReader)
			} else if property.label == "aliasAuth" {
				features.insert(.uncreatedAliasReader)
			} else if aliasKeepsLabel {
				// Beneath an alias that keeps its fulfilling property's label, a receive of that label reads the alias,
				// where no declaration of the label is nearer; an alias of `aliasToken: AliasValue` is hidden by it.
				if property.label == "aliasToken", aliasedLabel(of: property.attribute) == nil, !readerIsBeneathLeftsToken {
					features.insert(property.attribute == "@Received" ? .uncreatedAliasRequiredReader : .uncreatedAliasReader)
				}
			} else if property.label == "aliasToken" || aliasedLabel(of: property.attribute) == "aliasToken" {
				features.insert(.uncreatedAliasAcceptedTwin)
			}
		}
		if !readerProperties.isEmpty {
			for property in properties(ofTypeNamed: "AliasDetail") + properties(ofTypeNamed: "AliasSeam") where property.label == "aliasReaderBuilder" {
				features.insert(.uncreatedAliasReaderInsideWrapper)
			}
			if declaresType(named: "AliasPanel") {
				features.insert(.uncreatedAliasReaderInsideNestedSeam)
			}
			if declaresType(named: "AliasMid") {
				features.insert(.uncreatedAliasDeeperReader)
			}
		}
		for property in properties(ofTypeNamed: "AliasDetail") where property.label == "aliasBearer" {
			if aliasedLabel(of: property.attribute) == "aliasToken", !aliasKeepsLabel {
				features.insert(.uncreatedAliasAcceptedTwin)
			} else if property.attribute.contains("onlyIfAvailable") {
				features.insert(.uncreatedAliasAliasOfAlias)
			} else {
				features.insert(.uncreatedAliasRequiredAliasOfAlias)
			}
		}
		for property in properties(ofTypeNamed: "AliasLeft") {
			if property.label == "aliasToken", property.attribute == "@Instantiated" {
				if properties(ofTypeNamed: "AliasValue").contains(where: { $0.label == "aliasDetailBuilder" }) {
					features.insert(.uncreatedAliasFulfillingPropertyBeingBuilt)
				} else if properties(ofTypeNamed: "AliasValue").contains(where: { $0.label == "aliasA" }) {
					features.insert(.uncreatedAliasFulfillingPropertyGeneratedLater)
				} else if aliasKeepsLabel, properties(ofTypeNamed: "AliasValue").contains(where: { $0.label == "aliasDetail" && $0.attribute == "@Received" }) {
					features.insert(.uncreatedAliasFulfillingPropertyGeneratedAfterLabelKeepingAlias)
				} else {
					features.insert(.uncreatedAliasFulfillingPropertyPruned)
				}
			} else if property.label == "aliasToken", aliasedLabel(of: property.attribute) == nil {
				features.insert(.uncreatedAliasRequiredOptionalParameter)
			} else if property.label == "aliasAuth", property.type.hasSuffix("AliasValue") {
				features.insert(.uncreatedAliasSamePropertyBeside)
			} else if property.label == "aliasAuth", property.type.hasSuffix("AliasLabel") {
				features.insert(.uncreatedAliasOtherTypeBeside)
			} else if property.label == "aliasAuth" {
				features.insert(.uncreatedAliasWrapperBeside)
			}
		}
		for property in properties(ofTypeNamed: "AliasSeam") {
			if property.label == "aliasAuth", aliasedLabel(of: property.attribute) == nil {
				features.insert(property.attribute.hasPrefix("@Instantiated") ? .uncreatedAliasDeclarationAbove : .uncreatedAliasLabelParameter)
			} else if property.label == "aliasToken", aliasedLabel(of: property.attribute) == nil {
				features.insert(.uncreatedAliasRequiredOptionalParameter)
			}
		}
		if properties(ofTypeNamed: "AliasClient").contains(where: { $0.label == "aliasAuth" }) {
			features.insert(.uncreatedAliasLabelParameter)
		}
		if !aliasProperties.isEmpty {
			for (typeName, typeProperties) in propertiesByType where typeName.contains("Root") {
				if typeProperties.contains(where: { $0.label == "aliasAuth" && $0.type.hasSuffix("AliasValue") }) {
					features.insert(.uncreatedAliasLabelHeldByCaller)
				}
				if typeProperties.contains(where: { $0.label == "aliasToken" }) {
					features.insert(.uncreatedAliasFulfillingPropertyHeldByCaller)
				}
			}
		}
		return features.union(accessProofDrawFeatures(of: fixture)).union(holeDrawFeatures(of: fixture))
	}

	/// The shapes `addingHoleShapes` draws, read from the properties the fixture declares on the `Hole` types.
	private static func holeDrawFeatures(of fixture: GraphFuzzerFixture) -> Set<GraphFuzzerSeamDrawFeature> {
		guard fixture.drawsHole else { return [] }
		let prefix = fixture.typeNamePrefix
		var propertiesByType = [String: [(attribute: String, label: String, type: String)]]()
		for content in fixture.swiftFileContent {
			var currentType: String?
			for line in GraphFuzzerSourceLine.lines(of: content) {
				switch line {
				case let .typeDeclaration(name):
					currentType = name
					propertiesByType[name, default: []] += []
				case let .property(attribute, label, type):
					if let currentType {
						propertiesByType[currentType, default: []].append((attribute, label, type))
					}
				case .instantiableAttribute, .instantiateMethod, .other:
					break
				}
			}
		}
		func properties(of suffix: String) -> [(attribute: String, label: String, type: String)] {
			propertiesByType[prefix + suffix] ?? []
		}
		func declares(_ suffix: String) -> Bool {
			propertiesByType[prefix + suffix] != nil
		}
		var features: Set<GraphFuzzerSeamDrawFeature> = [.hole]
		let seamProperties = properties(of: "HoleSeam")
		if seamProperties.contains(where: { $0.label == "holeService" }) {
			features.insert(.holeOwnedBySeam)
		}
		for property in seamProperties where property.type.hasSuffix("<\(prefix)HoleOwner>") || property.type == "\(prefix)HoleOwner" {
			if property.label == "holeSecondOwner" {
				features.insert(.holeOwnerReachedAtTwoSites)
			} else if property.type.hasPrefix("Instantiator<") {
				features.insert(.holeBeneathInstantiator)
			} else if property.type.hasPrefix("SendableInstantiator<") {
				features.insert(.holeBeneathSendableInstantiator)
			} else if property.type.hasPrefix("LazilyInstantiated<") {
				features.insert(.holeBeneathLazilyInstantiated)
			} else if property.type.hasPrefix("SendableLazilyInstantiated<") {
				features.insert(.holeBeneathSendableLazilyInstantiated)
			} else {
				features.insert(.holeBeneathConstant)
			}
		}
		let implProperties = properties(of: "HoleImpl")
		if implProperties.contains(where: { $0.label == "holeAnalytics" }) {
			features.insert(.holeReadsField)
		}
		if implProperties.contains(where: { $0.label == "holeLogger" }) {
			features.insert(.holeReadsCallerValue)
		}
		if declares("HoleOuter") {
			features.insert(.holePassedUp)
		}
		if implProperties.contains(where: { $0.label == "holeSeamBuilder" }) || declares("HoleMiddle") {
			features.insert(.holeReentersSeam)
			if declares("HoleOuter") {
				features.insert(.holeReentersInnerSeamOfPassedUpBuilder)
			}
		}
		if declares("HoleMiddle") {
			features.insert(.holeReentersSeamBeneathRedeclaredLabel)
		}
		if declares("HoleLoop") {
			features.insert(.holeSeamReentersItself)
			if properties(of: "HoleLoop").contains(where: { $0.label == "holeLogger" }) {
				features.insert(.holeSeamReentersItselfBeneathBoundLabel)
			}
		}
		return features
	}

	/// The shapes `addingAccessProofShapes` draws, read from the access levels the fixture spells on the `Proof` types'
	/// declarations and initializers, and from their properties.
	private static func accessProofDrawFeatures(of fixture: GraphFuzzerFixture) -> Set<GraphFuzzerSeamDrawFeature> {
		let prefix = fixture.typeNamePrefix
		/// Each class's spelled access and its initializer's, by name, and each extension line, from every file.
		var classAccess = [String: String]()
		var initializerAccess = [String: String]()
		var extensionLines = [String]()
		var currentClass: String?
		for content in fixture.swiftFileContent {
			for rawLine in content.split(separator: "\n") {
				let line = rawLine.trimmingCharacters(in: .whitespaces)
				let access = ["public", "package"].first { line.hasPrefix($0 + " ") } ?? "internal"
				let declaration = access == "internal" ? Substring(line) : line.dropFirst(access.count + 1)
				if declaration.hasPrefix("final class ") {
					let name = String(declaration.dropFirst("final class ".count).prefix { $0.isLetter || $0.isNumber || $0 == "_" })
					classAccess[name] = access
					currentClass = name
				} else if declaration.hasPrefix("init("), let currentClass, initializerAccess[currentClass] == nil {
					initializerAccess[currentClass] = access
				} else if declaration.hasPrefix("extension ") {
					extensionLines.append(line)
				}
			}
		}
		func properties(of typeSuffix: String) -> [(attribute: String, label: String, type: String)] {
			fixture.swiftFileContent.flatMap { content -> [(attribute: String, label: String, type: String)] in
				var isInType = false
				var properties = [(attribute: String, label: String, type: String)]()
				for line in GraphFuzzerSourceLine.lines(of: content) {
					switch line {
					case let .typeDeclaration(name):
						isInType = name == prefix + typeSuffix
					case let .property(attribute, label, type) where isInType:
						properties.append((attribute, label, type))
					case .instantiableAttribute, .instantiateMethod, .property, .other:
						break
					}
				}
				return properties
			}
		}
		let order = ["internal", "package", "public"]
		func isNarrower(_ access: String?, than otherAccess: String?) -> Bool {
			guard let access, let otherAccess, let index = order.firstIndex(of: access), let otherIndex = order.firstIndex(of: otherAccess) else { return false }
			return index < otherIndex
		}
		var features = Set<GraphFuzzerSeamDrawFeature>()
		let seamName = prefix + "ProofSeam"
		guard classAccess[seamName] != nil else { return features }
		if classAccess[seamName] != "public" {
			features.insert(.seamTypeNarrowerThanPublic)
		}
		let seamProperties = properties(of: "ProofSeam")
		let seamInitializerIsNarrower = isNarrower(initializerAccess[seamName], than: classAccess[seamName])
		if seamInitializerIsNarrower, classAccess[prefix + "ProofCog"] != nil, seamProperties.allSatisfy({ $0.label == "proofCog" }) {
			features.insert(.ownInitializerNarrowerWithNoPassThrough)
		}
		if seamInitializerIsNarrower, classAccess[prefix + "ProofVane"] != nil {
			features.insert(.ownInitializerNarrowerWithOnlyOptionalNarrowerPassThroughs)
		}
		if seamInitializerIsNarrower, classAccess[prefix + "ProofDial"] != nil {
			features.insert(.ownInitializerNarrowerThanTwoParameterLevels)
		}
		if isNarrower(initializerAccess[prefix + "ProofBadge"], than: classAccess[prefix + "ProofTheme"]) {
			features.insert(.receiverNarrowerThanType)
		}
		if isNarrower(classAccess[prefix + "ProofVault"], than: initializerAccess[prefix + "ProofVault"]) {
			features.insert(.receiverTypeNarrowerThanItsInitializer)
		}
		if properties(of: "ProofLock").contains(where: { $0.attribute == "@Received" }), isNarrower(classAccess[prefix + "ProofPin"], than: classAccess[seamName]) {
			features.insert(.requiredParameterNarrowerThanSeamType)
		}
		if seamProperties.contains(where: { $0.label == "proofOwn" && $0.attribute == "@Received(onlyIfAvailable: true)" }) {
			features.insert(.ownOnlyIfAvailableParameter)
			if isNarrower(classAccess[prefix + "ProofOwn"], than: classAccess[seamName]) {
				features.insert(.ownOnlyIfAvailableParameterNarrowerThanSeam)
			}
		}
		let hostProperties = properties(of: "ProofHost") + properties(of: "ProofOtherHost")
		if classAccess[prefix + "ProofPanel"] != nil {
			features.insert(hostProperties.contains { $0.label == "proofModel" } ? .providedValueHeldByCaller : .providedValueHeldByNoCaller)
		}
		if let alias = properties(of: "ProofConsumer").first(where: { $0.label == "proofAuth" }) {
			if fixture.swiftFileContent.contains(where: { $0.contains("@Instantiable\npackage final class \(prefix)ProofSession:") }) {
				features.insert(.aliasOfNarrowerInstantiableType)
			} else {
				features.insert(alias.attribute.contains("onlyIfAvailable: true") ? .unprovenAliasTypeOnlyIfAvailable : .unprovenAliasType)
			}
		}
		if properties(of: "ProofLedger").contains(where: { $0.label == "proofSession" }) {
			features.insert(.aliasFulfillingTypeAlsoReceived)
		}
		let namespaceExtensions = extensionLines.filter { $0.contains(prefix + "ProofSpace ") || $0.contains(prefix + "ProofSpace{") }
		if namespaceExtensions.contains(where: { $0.hasPrefix("extension ") }) {
			features.insert(.namespaceExtensionUnspelled)
		}
		if namespaceExtensions.contains(where: { !$0.hasPrefix("extension ") }) {
			features.insert(.namespaceExtensionSpelled)
		}
		if seamProperties.contains(where: { $0.label == "proofShelf" && $0.attribute.contains("erasedToConcreteExistential: true") }) {
			features.insert(.namespaceTypeOnlyThroughExistential)
		}
		if fixture.swiftFileContent.contains(where: { $0.contains("public enum \(prefix)ProofSpace {}") }) {
			features.insert(.publicNamespace)
		}
		if extensionLines.contains("extension \(prefix)ProofRack: Instantiable {") {
			features.insert(.instantiableExtensionOfNarrowerType)
		}
		if properties(of: "ProofMeter").contains(where: { $0.type.hasPrefix("Swift.") }) {
			features.insert(.qualifiedAllowlistMention)
		}
		if fixture.swiftFileContent.contains(where: { $0.contains("public static func mock(proofBolt: ") }) {
			features.insert(.mockInInstantiableExtension)
		}
		if extensionLines.contains("extension \(prefix)ProofShed: Instantiable {"), fixture.swiftFileContent.contains(where: { $0.contains("public static func mock(proofPlank: ") }) {
			features.insert(.mockCappedByItsExtension)
		}
		if properties(of: "ProofYard").contains(where: { $0.label == "proofShed" }) {
			features.insert(.mockCapRaisedByUnreachedMention)
		}
		if extensionLines.contains("extension \(seamName) {") {
			features.insert(.typeInExtensionOfSeam)
		}
		if extensionLines.contains("extension \(prefix)ProofSettings {"), classAccess[prefix + "ProofSettings"] == "package" {
			features.insert(.typeInExtensionOfNarrowerRecordedType)
		}
		for hostSuffix in ["ProofHost", "ProofOtherHost"] {
			let hostProperties = properties(of: hostSuffix)
			if let seamIndex = hostProperties.firstIndex(where: { $0.label == "proofSeam" }), hostProperties[(seamIndex + 1)...].contains(where: { $0.attribute == "@Instantiated" }) {
				features.insert(.valueDeclaredAfterSeam)
			}
		}
		if fixture.modules != nil {
			features.insert(.moduleSplit)
		}
		if classAccess[prefix + "ProofOtherRoot"] != nil {
			features.insert(.otherPackageCaller)
		}
		if fixture.modulesOmittingPackageName.contains(.samePackageCaller) {
			features.insert(.samePackageCallerRunWithoutPackageName)
		}
		if fixture.modulesOmittingPackageName.contains(.seamModule) {
			features.insert(.seamModuleRunWithoutPackageName)
		}
		return features
	}

	/// The name of the type an `@Instantiated` property of `type` with `attribute` builds: its `fulfilledByType:`,
	/// the generic of its wrapper, or its type.
	private static func builtTypeName(ofPropertyWithAttribute attribute: String, type: String) -> String {
		if let fulfilledByTypeRange = attribute.range(of: "fulfilledByType: \"") {
			String(attribute[fulfilledByTypeRange.upperBound...].prefix { $0 != "\"" })
		} else if let genericStart = type.firstIndex(of: "<"), let genericEnd = type.lastIndex(of: ">") {
			String(type[type.index(after: genericStart)..<genericEnd])
		} else {
			type
		}
	}

	/// What a seam's generated initializer takes, read from the widest tier in the seam's generated file, so that a
	/// generator which stops drawing a shape cannot hide it: `generatedFiles` is an accepted graph's output and
	/// `fixture` the graph, whose seams declare the labels that are not pass-throughs.
	static func seamOutputFeatures(of fixture: GraphFuzzerFixture, generatedFiles: [String: String]) -> Set<GraphFuzzerSeamOutputFeature> {
		var ownLabelsBySeam = [String: Set<String>]()
		for content in fixture.swiftFileContent {
			var nextTypeIsSeam = false
			var currentSeam: String?
			for line in GraphFuzzerSourceLine.lines(of: content) {
				switch line {
				case let .instantiableAttribute(arguments):
					nextTypeIsSeam = arguments.contains("generateDependencyTree: true")
				case let .typeDeclaration(name):
					currentSeam = nextTypeIsSeam ? name : nil
					nextTypeIsSeam = false
					if let currentSeam {
						ownLabelsBySeam[currentSeam] = []
					}
				case let .property(attribute, label, _):
					if let currentSeam, attribute.hasPrefix("@Received") || attribute == "@Forwarded" {
						ownLabelsBySeam[currentSeam, default: []].insert(label)
					}
				case .instantiateMethod, .other:
					break
				}
			}
		}
		var features = Set<GraphFuzzerSeamOutputFeature>()
		// The widest tier of each seam: the first of its initializers a file declares.
		var widestTiers = [(seamTypeName: String, parameters: [String])]()
		for contents in generatedFiles.values where contents.contains("enum __safeDI_") {
			for initializer in GraphFuzzerOracle.seamInitializerParameters(inGeneratedFile: contents) where !widestTiers.contains(where: { $0.seamTypeName == initializer.seamTypeName }) {
				widestTiers.append(initializer)
			}
		}
		for (seamTypeName, parameters) in widestTiers {
			// A builder for a hole is no pass-through: `holeOutputFeatures` reads it.
			for parameter in parameters where !parameter.contains("SafeDIScope_") {
				let label = parameter.prefix { $0 != ":" }.trimmingCharacters(in: .whitespaces)
				if parameter.contains("= nil") {
					features.insert(.optionalPassThrough)
				} else if !(ownLabelsBySeam[seamTypeName] ?? []).contains(label) {
					features.insert(.requiredPassThrough)
				}
				let type = parameter.drop { $0 != ":" }.dropFirst().prefix { $0 != "=" }.trimmingCharacters(in: .whitespaces)
				if type.hasPrefix("@escaping @") {
					features.insert(.escapingAttributedSeamParameter)
				} else if type.hasPrefix("@escaping ") {
					features.insert(.escapingSeamParameter)
				} else if type.hasSuffix("?"), type.contains("->") {
					features.insert(.optionalClosureSeamParameter)
				}
			}
		}
		// A call of a generated initializer follows the line referring to its guard enum.
		for contents in generatedFiles.values {
			let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
			for (line, nextLine) in zip(lines, lines.dropFirst()) where line.contains(".__safeDI_") && nextLine.contains(".instance") {
				features.insert(.instanceReadAtCall)
			}
		}
		return features
	}

	/// What the code generated for a graph with a hole shows (`GraphFuzzerHoleOutputFeature`), read from
	/// `generatedFiles`, an accepted graph's output.
	static func holeOutputFeatures(generatedFiles: [String: String]) -> Set<GraphFuzzerHoleOutputFeature> {
		var features = Set<GraphFuzzerHoleOutputFeature>()
		let builderParameter = try! NSRegularExpression(pattern: #"\b\w+Builder\w* __safeDI_\w+: @escaping (@Sendable )?\((\w+\.)?SafeDIScope_"#)
		let otherSeamsStruct = try! NSRegularExpression(pattern: #"@escaping (?:@Sendable )?\((\w+)\.SafeDIScope_"#)
		let fillDeclaration = try! NSRegularExpression(pattern: #"^( *)(@Sendable )?func (__safeDI_\w+)\(_ scope: (\w+)\.SafeDIScope_"#)
		func firstMatch(_ expression: NSRegularExpression, in line: String) -> [String]? {
			let range = NSRange(line.startIndex..., in: line)
			guard let match = expression.firstMatch(in: line, range: range) else { return nil }
			return (0..<match.numberOfRanges).map { index in
				Range(match.range(at: index), in: line).map { String(line[$0]) } ?? ""
			}
		}
		for (_, contents) in generatedFiles.sorted(by: { $0.key < $1.key }) where !contents.isEmpty {
			let lines = contents.components(separatedBy: "\n")
			var extendedType: String?
			for (index, line) in lines.enumerated() {
				if line.hasPrefix("extension "), line.hasSuffix(" {") {
					extendedType = String(line.dropFirst("extension ".count).dropLast(2))
				} else if line.hasPrefix("}") {
					extendedType = nil
				}
				if line.contains("init("), firstMatch(builderParameter, in: line) != nil {
					features.insert(.builderParameter)
					if line.contains(") -> @Sendable (") {
						features.insert(.stagedBuilder)
					}
					if let extendedType, let match = firstMatch(otherSeamsStruct, in: line), match[1] != extendedType {
						features.insert(.passedUpBuilder)
					}
				}
				guard let fill = firstMatch(fillDeclaration, in: line) else { continue }
				features.insert(.fill)
				if !fill[2].isEmpty {
					features.insert(.sendableFill)
				}
				// The fill's body, up to the line closing it at its indentation, and the call that passes it after it.
				let indentation = fill[1]
				let fillName = fill[3]
				let scopeSeam = fill[4]
				guard let end = lines[(index + 1)...].firstIndex(of: indentation + "}") else { continue }
				let passesFill = { (body: String) in body.contains(": \(fillName))") || body.contains(": \(fillName),") }
				let callsInside = lines[(index + 1)..<end].filter { $0.contains("return ") && passesFill($0) }
				guard !callsInside.isEmpty else { continue }
				features.insert(.fillPassedToItsSeam)
				let calledInside = callsInside.compactMap { call in call.range(of: "return ").map { String(call[$0.upperBound...].prefix { $0 != "(" }) } }
				let callAfter = lines[(end + 1)...].first { $0.contains("return ") && passesFill($0) }
				if let callAfter, calledInside.contains(scopeSeam), !callAfter.contains("return \(scopeSeam)(") {
					features.insert(.fillOfPassedUpBuilderPassedToItsSeam)
				}
			}
		}
		return features
	}

	private static func features(ofPropertyWithAttribute attribute: String, type: String) -> Set<GraphFuzzerFeature> {
		var features = Set<GraphFuzzerFeature>()
		let isErased = attribute.contains("erasedToConcreteExistential: true")
		if type.hasPrefix("Instantiator<") {
			features.insert(.instantiatorProperty)
		} else if type.hasPrefix("SendableInstantiator<") {
			features.insert(.sendableInstantiatorProperty)
		} else if type.hasPrefix("ErasedInstantiator<") {
			features.insert(.erasedInstantiatorProperty)
		} else if type.hasPrefix("SendableErasedInstantiator<") {
			features.insert(.sendableErasedInstantiatorProperty)
		} else if type.hasPrefix("LazilyInstantiated<") || type.hasPrefix("SendableLazilyInstantiated<") {
			if attribute.hasPrefix("@Instantiated") {
				features.insert(isErased ? .erasedLazilyInstantiatedProperty : type.hasPrefix("Sendable") ? .sendableLazilyInstantiatedProperty : .lazilyInstantiatedProperty)
			} else if attribute == "@Forwarded" {
				features.insert(.forwardedLazilyInstantiatedProperty)
			}
		}
		if type.hasPrefix("ErasedInstantiator<") || type.hasPrefix("SendableErasedInstantiator<") {
			if attribute.hasPrefix("@Received") {
				features.insert(.receivedErasedInstantiator)
			} else if attribute == "@Forwarded" {
				features.insert(.forwardedErasedInstantiator)
			}
		}
		if attribute.hasPrefix("@Instantiated"), !type.contains("<") {
			features.insert(isErased ? .erasedConstantProperty : .constantProperty)
		} else if attribute == "@Forwarded" {
			features.insert(type.hasSuffix("?") ? .optionalForwardedProperty : .forwardedProperty)
		} else if attribute == "@Received" {
			features.insert(type.hasSuffix("?") ? .requiredOptionalReceive : .requiredReceive)
		} else if attribute == "@Received(onlyIfAvailable: true)" {
			features.insert(.onlyIfAvailableReceive)
		} else if attribute.hasPrefix("@Received(fulfilledByDependencyNamed:") {
			features.insert(attribute.contains("onlyIfAvailable: true") ? .onlyIfAvailableAlias : .requiredAlias)
			if isErased {
				features.insert(.erasedAlias)
			}
		}
		return features
	}

	/// `T` for `LazilyInstantiated<T>` or `SendableLazilyInstantiated<T>`, and otherwise `nil`.
	private static func lazilyInstantiatedInstanceType(of type: String) -> String? {
		for wrapper in ["SendableLazilyInstantiated<", "LazilyInstantiated<"] where type.hasPrefix(wrapper) && type.hasSuffix(">") {
			return String(type.dropFirst(wrapper.count).dropLast())
		}
		return nil
	}

	private static func instantiatedTypeName(attribute: String, type: String) -> String {
		if let fulfilledByTypeRange = attribute.range(of: "fulfilledByType: \"") {
			String(attribute[fulfilledByTypeRange.upperBound...].prefix { $0 != "\"" })
		} else if let genericStart = type.firstIndex(of: "<"), let genericEnd = type.lastIndex(of: ">") {
			String(type[type.index(after: genericStart)..<genericEnd])
		} else {
			type
		}
	}
}

private struct GraphFuzzerInstantiationEdge {
	let source: String
	let target: String
	let isLazy: Bool

	/// Whether a lazy edge closes a cycle: its target reaches its source.
	static func containsLazyCycle(_ edges: [GraphFuzzerInstantiationEdge]) -> Bool {
		edges.contains { edge in
			edge.isLazy && reaches(from: edge.target, to: edge.source, through: edges)
		}
	}

	/// Whether `typeName` is on a cycle that a lazy edge closes.
	static func isOnLazyCycle(_ typeName: String, edges: [GraphFuzzerInstantiationEdge]) -> Bool {
		edges.contains { edge in
			edge.isLazy && reaches(from: edge.target, to: typeName, through: edges) && reaches(from: typeName, to: edge.source, through: edges)
		}
	}

	fileprivate static func reaches(from start: String, to destination: String, through edges: [GraphFuzzerInstantiationEdge]) -> Bool {
		var visited = Set<String>()
		var stack = [start]
		while let current = stack.popLast() {
			guard current != destination else { return true }
			guard visited.insert(current).inserted else { continue }
			stack += edges.filter { $0.source == current }.map(\.target)
		}
		return false
	}
}

/// One line of a generated fixture, in the shape `GraphFuzzerGenerator` emits it.
enum GraphFuzzerSourceLine: Equatable {
	case instantiableAttribute(arguments: String)
	/// A `public final class` or an `extension … : Instantiable` that an `@Instantiable` attribute decorates.
	case typeDeclaration(name: String)
	/// An extension's `instantiate(…)` method, with the source of its parameters.
	case instantiateMethod(parameters: String)
	case property(attribute: String, label: String, type: String)
	case other

	var declaredTypeName: String? {
		switch self {
		case let .typeDeclaration(name):
			name
		case .instantiableAttribute, .instantiateMethod, .property, .other:
			nil
		}
	}

	/// `line` without the access modifier it begins with, or `line` itself when it begins with none. `nil` never: the
	/// optional lets a condition bind it.
	private static func droppingAccessModifier(from line: String) -> Substring? {
		// A global actor precedes the access modifier, as `GraphFuzzerPublicMockDraw` spells it.
		let line = line.hasPrefix("@MainActor ") ? String(line.dropFirst("@MainActor ".count)) : line
		for modifier in ["public ", "package ", "internal "] where line.hasPrefix(modifier) {
			return line.dropFirst(modifier.count)
		}
		return Substring(line)
	}

	static func lines(of content: String) -> [GraphFuzzerSourceLine] {
		var lines = [GraphFuzzerSourceLine]()
		var previousLineWasInstantiableAttribute = false
		for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
			let line = rawLine.trimmingCharacters(in: .whitespaces)
			let parsedLine: GraphFuzzerSourceLine
			if line.hasPrefix("@Instantiable") {
				parsedLine = .instantiableAttribute(arguments: String(line.dropFirst("@Instantiable".count)))
			} else if previousLineWasInstantiableAttribute, let declaration = droppingAccessModifier(from: line), declaration.hasPrefix("final class ") {
				let name = declaration.dropFirst("final class ".count).prefix { $0.isLetter || $0.isNumber || $0 == "_" }
				parsedLine = .typeDeclaration(name: String(name))
			} else if previousLineWasInstantiableAttribute, let declaration = droppingAccessModifier(from: line), declaration.hasPrefix("extension ") {
				// The extended type's last component: a nested extended type's file is named after it.
				let extendedType = declaration.dropFirst("extension ".count).prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
				parsedLine = .typeDeclaration(name: String(extendedType.split(separator: ".").last ?? extendedType))
			} else if let declaration = droppingAccessModifier(from: line), declaration.hasPrefix("static func instantiate("), let parametersEnd = declaration.range(of: ") -> ", options: .backwards) {
				parsedLine = .instantiateMethod(parameters: String(declaration[declaration.index(declaration.startIndex, offsetBy: "static func instantiate(".count)..<parametersEnd.lowerBound]))
			} else if line.hasPrefix("@Instantiated") || line.hasPrefix("@Received") || line.hasPrefix("@Forwarded"),
			          let letRange = line.range(of: " let ", options: .backwards),
			          let colonIndex = line[letRange.upperBound...].firstIndex(of: ":")
			{
				parsedLine = .property(
					attribute: String(line[..<letRange.lowerBound]),
					label: String(line[letRange.upperBound..<colonIndex]),
					type: line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces),
				)
			} else {
				parsedLine = .other
			}
			lines.append(parsedLine)
			if case .instantiableAttribute = parsedLine {
				previousLineWasInstantiableAttribute = true
			} else {
				previousLineWasInstantiableAttribute = false
			}
		}
		return lines
	}
}

// MARK: - Oracle

/// What one run of SafeDITool did with a graph, with the per-run fixture directory replaced by a placeholder so
/// two runs compare equal exactly when they produced the same diagnostics and code.
enum GraphFuzzerToolOutcome: Equatable {
	case rejected(diagnostics: String)
	case accepted(generatedFiles: [String: String], warnings: [String])

	/// The first aspect in which two outcomes differ, or `nil` when they agree: their verdict, their diagnostics
	/// or warnings in any order, the names of their generated files, or one file's code, byte for byte. Paths to
	/// fixture files are compared by file name, and the suggestions a diagnostic lists ("Did you mean one of …"), and
	/// the declarations it lists as proving a type's access, in any order: the order inside a message is presentation and changes nothing a user does.
	static func difference(between outcome: GraphFuzzerToolOutcome, and otherOutcome: GraphFuzzerToolOutcome) -> String? {
		// A seam's guard enum is named after a hash of its signature, which names its parameters' types, so a
		// renaming changes it as it changes the types: a hash restored textually cannot match, and is reduced away.
		let reduce = { (text: String) in
			GraphFuzzerRenaming.reducingFixturePathsToFileNames(in: text)
				.replacingOccurrences(of: #"(__safeDI_[A-Za-z0-9_]+_)[0-9A-F]{16}\b"#, with: "$1<hash>", options: .regularExpression)
		}
		switch (outcome, otherOutcome) {
		case let (.rejected(diagnostics), .rejected(otherDiagnostics)):
			return diagnosticEntries(of: reduce(diagnostics)) == diagnosticEntries(of: reduce(otherDiagnostics)) ? nil : "its diagnostics"
		case let (.accepted(generatedFiles, warnings), .accepted(otherGeneratedFiles, otherWarnings)):
			if Set(generatedFiles.keys) != Set(otherGeneratedFiles.keys) {
				return "the names of its generated files"
			}
			for fileName in generatedFiles.keys.sorted() {
				let code = reduce(generatedFiles[fileName, default: ""])
				let otherCode = reduce(otherGeneratedFiles[fileName, default: ""])
				guard code != otherCode else { continue }
				let kind = if fileName.hasSuffix("+SafeDIMock.swift") {
					"its generated mock code"
				} else if fileName.hasSuffix("SafeDIMockConfiguration.swift") {
					"its generated mock configuration code"
				} else {
					"its generated dependency tree code"
				}
				let orderOnly = declarationsInAnyOrder(code) == declarationsInAnyOrder(otherCode) ? " (the order of its extensions only)" : ""
				return "\(kind)\(orderOnly), in \(fileName)"
			}
			return warnings.sorted() == otherWarnings.sorted() ? nil : "its warnings"
		case (.accepted, .rejected), (.rejected, .accepted):
			return "its verdict"
		}
	}

	/// The diagnostics, each with the notes after it and with its suggestions sorted, sorted.
	private static func diagnosticEntries(of diagnostics: String) -> [String] {
		var entries = [[Substring]]()
		for line in diagnostics.split(separator: "\n", omittingEmptySubsequences: false) {
			if line.contains(": error: ") || line.contains(": warning: ") || entries.isEmpty {
				entries.append([line])
			} else {
				entries[entries.count - 1].append(line)
			}
		}
		return entries.map { sortingSuggestions(in: $0.joined(separator: "\n")) }.sorted()
	}

	/// `diagnostic` with the items of each list of suggestions it makes – "Did you mean one of `a: A`, `b: B`?",
	/// which SafeDI sorts by `Property.<` – and of each parenthesized list of the declarations that prove a seam
	/// parameter's access – "(`Host.init(key:seam:)`, `Vault.init(key:)`)", which SafeDI lists in source order, so a
	/// file-name reversal reorders them – sorted as text, so two diagnostics that list the same items in another order
	/// compare equal, and any other difference, including an item added, removed or changed, still tells them apart.
	private static func sortingSuggestions(in diagnostic: String) -> String {
		// Each item is a property's or a declaration's source between backticks, and no fuzzer label or type contains one.
		let expression = try! NSRegularExpression(pattern: "(?<=Did you mean one of )`[^`]*`(?:, `[^`]*`)+(?=\\?)|(?<=\\()`[^`]*`(?:, `[^`]*`)+(?=\\))")
		let source = diagnostic as NSString
		var result = ""
		var location = 0
		for match in expression.matches(in: diagnostic, range: NSRange(location: 0, length: source.length)) {
			let suggestions = source.substring(with: match.range).dropFirst().dropLast().components(separatedBy: "`, `")
			result += source.substring(with: NSRange(location: location, length: match.range.location - location))
			result += "`" + suggestions.sorted().joined(separator: "`, `") + "`"
			location = match.range.location + match.range.length
		}
		return result + source.substring(from: location)
	}

	/// `code` with each run of consecutive top-level extensions sorted, which says whether two files differ only
	/// in the order they declare their extensions.
	private static func declarationsInAnyOrder(_ code: String) -> String {
		var lines = [String]()
		var extensions = [String]()
		var currentExtension: [Substring]?
		func endExtension() {
			if let currentExtension {
				extensions.append(currentExtension.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
			}
			currentExtension = nil
		}
		func endExtensions() {
			endExtension()
			lines += extensions.sorted()
			extensions = []
		}
		for line in code.split(separator: "\n", omittingEmptySubsequences: false) {
			// A public mock's module-level configuration and a forwarder of its default are declarations of their own.
			if line.hasPrefix("extension ") || line.hasPrefix("/// Configuration for how ") || line.hasPrefix("@usableFromInline ") {
				endExtension()
				currentExtension = [line]
			} else if line.hasPrefix("#") {
				endExtensions()
				lines.append(String(line))
			} else if currentExtension != nil {
				currentExtension?.append(line)
			} else if !line.isEmpty {
				lines.append(String(line))
			}
		}
		endExtensions()
		return lines.joined(separator: "\n")
	}

	var description: String {
		switch self {
		case let .rejected(diagnostics):
			"rejected:\n\(diagnostics)"
		case let .accepted(generatedFiles, warnings):
			"accepted with warnings \(warnings):\n"
				+ generatedFiles.keys.sorted().map { "// \($0)\n\(generatedFiles[$0, default: ""])" }.joined(separator: "\n")
		}
	}
}

/// A graph the oracle does not accept: the tool succeeded and the output does not compile or draws a compiler
/// warning, the fixture itself does not compile (a defect in the fuzzer), or two runs of the tool differ.
struct GraphFuzzerFailure: Equatable {
	enum Kind: String, Equatable {
		case generatedCodeDoesNotCompile = "generated code does not compile"
		/// The generated code compiles, and the compiler reports a warning in it that the fixture does not draw
		/// itself: a build that treats warnings as errors fails on it, and its author cannot edit generated code.
		case generatedCodeDrawsWarning = "generated code draws a compiler warning"
		case fixtureDoesNotCompile = "fixture does not compile on its own"
		case runsDiffer = "two runs of the tool differ"
		case runsDifferAcrossProcesses = "the tool's output differs between two processes"
		case compilerCrashedOnGeneratedCode = "the Swift compiler crashed on generated code"
		case renamedGraphDiffers = "the graph renamed to change an order gives other results"
		case mockTakesWrapperParameterForReceive = "a generated mock takes a LazilyInstantiated parameter for a receive"
		case seamRejectsGraphInlineAccepts = "the tool rejects the graph with an error that is not a seam's own, and accepts it with no seam"
		case seamPassesNilWhereInlinePassesValue = "the generated code passes a literal nil more often with the seam than without it"
		case seamReadsUncreatedAliasBinding = "a seam's generated code reads the binding of an only-if-available alias of a parameter that may be nil other than as its declaring type's argument"
		case uncreatedAliasSeamRejectedOtherwise = "the tool rejects the uncreated-alias draw's seam with an error that is not the uncreated alias's"
		/// The exact-form alias of a required optional parameter is always created, so an uncreated-alias error naming
		/// it rejects a graph the rule accepts.
		case uncreatedAliasExactFormAliasRejected = "the tool rejects the exact-form alias of a required optional parameter, which is always created"
		/// A type's own declaration of an alias's label is not a declaration of the label the alias reads, so an
		/// uncreated-alias error saying a type's alias reads an alias of that label the same type declares rejects an
		/// alias as an alias of itself.
		case uncreatedAliasReadsItself = "the tool rejects an alias as an alias of itself"
		/// The differential value comparator describes other values for a probe of the seam build than for the same
		/// probe of the inline build, beyond the documented divergences.
		case seamBuildsOtherValuesThanInline = "the seam build constructs other values than the inline build"
		/// The comparator could not describe the seam build or the inline build: a path or its probes did not compile
		/// or run.
		case valueComparatorCouldNotDescribeGraph = "the differential value comparator could not describe the graph"
		/// A seam's generated tier is wider than a type one of its parameters names, by the access the generator gave
		/// the type: a tier SafeDI proved from the wrong declaration, which the seam's own module may not compile.
		case seamTierWiderThanParameterType = "a seam's generated tier is wider than a type one of its parameters names"
		/// A caller in another module calls a tier that omits a parameter some receiver of which the caller's module's
		/// inline build passes a value, and the tool reports no error: the seam passes `nil` where inline passes a value.
		case seamTierOmitsValueInlinePasses = "a caller's tier omits a parameter its inline build passes a receiver a value for, with no error"
		/// The tool reports that a caller holds a value its tier omits, where the caller's module's inline build passes
		/// every receiver of that parameter `nil`.
		case seamTierOmitsProvidedValueReportedWhereInlinePassesNil = "the tool reports a value a caller's tier omits where its inline build passes every receiver nil"
		/// The differential value comparator describes other values for a probe of a graph whose seam takes a builder
		/// for a hole than for the same probe of its visible build (`GraphFuzzerFixture.withoutHoles`), in which the
		/// seam's module sees the fulfilling type and builds it inline.
		case holeBuildsOtherValuesThanVisibleBuild = "the build that fills a hole constructs other values than the visible build"
		/// The tool accepts a graph whose seam takes a builder for a hole and rejects its visible build: the fill
		/// accepts what the seam's module, building the fulfilling type inline, rejects.
		case holeAcceptedWhereVisibleBuildRejects = "the tool accepts a graph with a hole and rejects its visible build"
		/// The tool rejects a `generateMockPublic` graph with an error that is not a public mock's own, and accepts its
		/// known-right path: the same graph with every declaration `public` and every `.public` mock `true`.
		case publicMockRejectsGraphKnownRightAccepts = "the tool rejects the graph with an error that is not a public mock's own, and accepts its known-right path"
		/// The tool accepts a `generateMockPublic` graph and rejects its known-right path.
		case knownRightRejectsGraphPublicMockAccepts = "the tool accepts the graph and rejects its known-right path"
		/// A `public` or `package` declaration in generated code names a type narrower than the declaration, by the access
		/// the generator gave the type: a public mock, override or configuration SafeDI proved from the wrong declaration.
		case publicMockDeclarationWiderThanNamedType = "a generated public or package declaration is wider than a type it names"
		/// The differential value comparator describes other values for a probe of a `generateMockPublic` graph than for
		/// the same probe of its known-right path, beyond the stated divergences.
		case publicMockBuildsOtherValuesThanKnownRight = "the graph builds other values than its known-right path"
	}

	let seed: UInt64
	let kind: Kind
	let details: String
	/// For `seamBuildsOtherValuesThanInline`, each difference's description: a known issue of that kind documents
	/// the failure only when every one of them matches one of its signatures.
	var valueDifferences: [String] = []

	static func reproductionCommand(forSeed seed: UInt64, features: Set<GraphFuzzerGeneratorFeature>) -> String {
		let featuresVariable = features.isEmpty ? "" : "SAFEDI_GRAPH_FUZZER_FEATURES=\(features.sorted().map(\.rawValue).joined(separator: ",")) "
		return "\(featuresVariable)SAFEDI_GRAPH_FUZZER_STARTING_SEED=\(seed) SAFEDI_GRAPH_FUZZER_ITERATIONS=1 swift test --traits sourceBuild --filter SafeDIToolGraphFuzzerTests/longRun"
	}

	func issueComment(fixture: GraphFuzzerFixture) -> Comment {
		"""
		Graph fuzzer seed \(seed): \(kind.rawValue).
		Reproduce with: \(Self.reproductionCommand(forSeed: seed, features: GraphFuzzerGeneratorFeature.features(drawnIn: fixture)))
		\(details)
		Fixture:
		\(fixture.description)
		"""
	}
}

/// The oracle's verdict on one graph.
struct GraphFuzzerResult {
	init(fixture: GraphFuzzerFixture, outcome: GraphFuzzerToolOutcome, failure: GraphFuzzerFailure?, laterFailures: [GraphFuzzerFailure] = [], renamedGraphFailures: [GraphFuzzerFailure] = [], isInspectedByValueOracle: Bool = false, isComparedByValueOracle: Bool = false) {
		self.fixture = fixture
		self.outcome = outcome
		self.failure = failure
		self.laterFailures = laterFailures
		self.renamedGraphFailures = renamedGraphFailures
		self.isInspectedByValueOracle = isInspectedByValueOracle
		self.isComparedByValueOracle = isComparedByValueOracle
	}

	let fixture: GraphFuzzerFixture
	let outcome: GraphFuzzerToolOutcome
	/// The first way the graph fails the oracle: its runs differ, it does not compile or its generated code draws a
	/// compiler warning, a generated mock takes a `LazilyInstantiated` parameter for a receive, or, failing none of
	/// those ways, a renamed graph gives other results.
	let failure: GraphFuzzerFailure?
	/// The ways the graph fails after `failure` in the oracle's chain, which a known value failure does not mask.
	let laterFailures: [GraphFuzzerFailure]
	/// How each renamed graph that gives other results differs, in the order of `GraphFuzzerRenaming.all`, whether
	/// or not the graph also fails another way.
	let renamedGraphFailures: [GraphFuzzerFailure]
	/// Whether the value oracle compared the graph's generated code with its inline build's: the tool accepts the
	/// graph with its seam and without it.
	let isInspectedByValueOracle: Bool
	/// Whether the comparator did compare the two builds: the graph is inspected, its runs agree, and its generated
	/// code compiles cleanly, since `results(of:)` hands the comparator no graph with a compilation failure.
	let isComparedByValueOracle: Bool

	var isAccepted: Bool {
		switch outcome {
		case .accepted:
			true
		case .rejected:
			false
		}
	}
}

/// A known open defect: the seeds whose graphs fail today with one shape, and a one-line reason naming it.
struct GraphFuzzerKnownIssue: Equatable {
	/// How a failure of a known shape shows itself. Toolchains word the same defect differently, or crash on it,
	/// so a shape lists each way it is known to fail; a known seed that fails any other way is a new failure.
	enum Signature: Equatable {
		/// The generated code fails to compile with an error whose message contains this text.
		case compilerError(containing: String)
		/// The generated code compiles, drawing a warning whose message contains this text.
		case compilerWarning(containing: String)
		/// The Swift compiler crashes while compiling a generated mock.
		case compilerCrashInGeneratedMock
		/// A renamed graph gives other results, in the aspect whose description contains this text.
		case renamedGraphDiffers(containing: String)
		/// The fixture itself fails to compile, with an error whose message contains this text: the macro rejects
		/// a shape the generator emits before the macro accepts it.
		case macroRejectsFixture(containing: String)
		/// The tool rejects the graph with the seam, with an error whose text contains this, and accepts it without.
		case seamRejectsGraphInlineAccepts(containing: String)
		/// The generated code passes a literal `nil` more often with the seam than without it, to an argument whose
		/// description contains this text.
		case seamPassesNilWhereInlinePassesValue(containing: String)
		/// The seam build constructs other values than the inline build, with a difference whose description
		/// contains this text.
		case seamBuildsOtherValuesThanInline(containing: String)
		/// The value comparator could not describe the graph, with details containing this text, such as the error of
		/// an inline build that does not compile.
		case valueComparatorCouldNotDescribeGraph(containing: String)
		/// The tool rejects a `generateMockPublic` graph, with an error whose text contains this, and accepts its
		/// known-right path.
		case publicMockRejectsGraphKnownRightAccepts(containing: String)
		/// A `generateMockPublic` graph builds other values than its known-right path, with a difference whose
		/// description contains this text.
		case publicMockBuildsOtherValuesThanKnownRight(containing: String)
	}

	let reason: String
	let signatures: [Signature]
	/// In increasing order. The ordinary suite checks the first; the long run checks every one it reaches.
	let seeds: [UInt64]

	/// Whether `failure` is the failure this issue documents.
	func matches(_ failure: GraphFuzzerFailure) -> Bool {
		signatures.contains { signature in
			switch signature {
			case let .compilerError(text):
				failure.kind == .generatedCodeDoesNotCompile && failure.details.contains(text)
			case let .compilerWarning(text):
				failure.kind == .generatedCodeDrawsWarning && failure.details.contains(text)
			case .compilerCrashInGeneratedMock:
				failure.kind == .compilerCrashedOnGeneratedCode && failure.details.contains("+SafeDIMock.swift")
			case let .renamedGraphDiffers(text):
				failure.kind == .renamedGraphDiffers && failure.details.prefix { $0 != "\n" }.contains(text)
			case let .macroRejectsFixture(text):
				failure.kind == .fixtureDoesNotCompile && failure.details.contains(text)
			case let .seamRejectsGraphInlineAccepts(text):
				failure.kind == .seamRejectsGraphInlineAccepts && failure.details.contains(text)
			case let .seamPassesNilWhereInlinePassesValue(text):
				failure.kind == .seamPassesNilWhereInlinePassesValue && failure.details.contains(text)
			case let .valueComparatorCouldNotDescribeGraph(text):
				failure.kind == .valueComparatorCouldNotDescribeGraph && failure.details.contains(text)
			case .seamBuildsOtherValuesThanInline:
				// Every difference must match one of the shape's value signatures: a documented divergence beside an
				// undocumented difference is a new failure, not a known one.
				failure.kind == .seamBuildsOtherValuesThanInline && !failure.valueDifferences.isEmpty && failure.valueDifferences.allSatisfy { difference in
					signatures.contains { signature in
						if case let .seamBuildsOtherValuesThanInline(text) = signature {
							difference.contains(text)
						} else {
							false
						}
					}
				}
			case let .publicMockRejectsGraphKnownRightAccepts(text):
				failure.kind == .publicMockRejectsGraphKnownRightAccepts && failure.details.contains(text)
			case .publicMockBuildsOtherValuesThanKnownRight:
				// As for the seam's value signatures, every difference must match one.
				failure.kind == .publicMockBuildsOtherValuesThanKnownRight && !failure.valueDifferences.isEmpty && failure.valueDifferences.allSatisfy { difference in
					signatures.contains { signature in
						if case let .publicMockBuildsOtherValuesThanKnownRight(text) = signature {
							difference.contains(text)
						} else {
							false
						}
					}
				}
			}
		}
	}
}

/// A crash of the Swift compiler, read from its standard error.
struct GraphFuzzerCompilerCrash: Equatable {
	/// The file holding the declaration the compiler was compiling when it crashed, from the stack dump's
	/// `for '<declaration>' (at <path>:<line>:<column>)` line, if the dump names one.
	let fileName: String?
	/// What the compiler was doing when it crashed, without the stack frames.
	let summary: String

	/// `nil` unless `standardError` holds a compiler stack dump.
	init?(standardError: String) {
		guard standardError.contains("Stack dump:") else { return nil }
		let lines = standardError.split(separator: "\n", omittingEmptySubsequences: false)
		var summaryLines = ["The Swift compiler crashed."]
		var fileName: String?
		for line in lines {
			let trimmedLine = line.trimmingCharacters(in: .whitespaces)
			if trimmedLine.hasPrefix("for '"), let locationStart = trimmedLine.range(of: "' (at ") {
				let location = trimmedLine[locationStart.upperBound...].prefix { $0 != ")" }
				let path = location.prefix { $0 != ":" }
				fileName = path.split(separator: "/").last.map(String.init)
				summaryLines.append("In \(trimmedLine[..<locationStart.lowerBound].dropFirst("for '".count)) at \(fileName ?? String(path))\(location.dropFirst(path.count)).")
			} else if let first = trimmedLine.first, first.isNumber, trimmedLine.contains(".\t") || trimmedLine.contains(". "),
			          !trimmedLine.hasPrefix("0.")
			{
				// The numbered lines after `Stack dump:`, other than the program arguments: the compiler version and
				// what it was doing.
				summaryLines.append(String(trimmedLine))
			}
		}
		self.fileName = fileName
		summary = summaryLines.joined(separator: "\n")
	}
}

/// What the fuzzer concludes about one graph, given the known issue listing its seed, if any.
enum GraphFuzzerFinding: Equatable {
	case passed
	/// The graph fails the way its known issue documents.
	case knownIssue(GraphFuzzerKnownIssue, GraphFuzzerFailure)
	/// The graph's seed is a known issue, but the graph no longer fails.
	case staleKnownIssue(GraphFuzzerKnownIssue)
	/// The graph fails, and no known issue documents that failure: either its seed is not a known issue, or
	/// it fails another way than its known issue documents.
	case failure(GraphFuzzerFailure)

	/// - Parameter laterFailures: The ways the graph fails after `failure` in the oracle's chain. A known value
	///   failure masks none of them: the first the known issue does not document is the finding.
	init(failure: GraphFuzzerFailure?, laterFailures: [GraphFuzzerFailure] = [], knownIssue: GraphFuzzerKnownIssue?) {
		switch (failure, knownIssue) {
		case (nil, nil):
			self = .passed
		case let (nil, knownIssue?):
			self = .staleKnownIssue(knownIssue)
		case let (failure?, knownIssue?) where knownIssue.matches(failure):
			if failure.kind == .seamBuildsOtherValuesThanInline || failure.kind == .publicMockBuildsOtherValuesThanKnownRight, let unmasked = laterFailures.first(where: { !knownIssue.matches($0) }) {
				self = .failure(unmasked)
			} else {
				self = .knownIssue(knownIssue, failure)
			}
		case let (failure?, _):
			self = .failure(failure)
		}
	}

	/// The line the long run appends to its report, which `graph-fuzzer.yml` reads.
	func reportLine(seed: UInt64) -> String? {
		switch self {
		case .passed:
			nil
		case let .knownIssue(knownIssue, _):
			"known \(seed) \(knownIssue.reason)"
		case let .staleKnownIssue(knownIssue):
			"stale \(seed) \(knownIssue.reason)"
		case let .failure(failure):
			"failure \(seed) \(failure.kind.rawValue)"
		}
	}
}

/// A set of seeds as one number that does not depend on the order seeds are added in, so that the parts shards of
/// the corpus report add up to the whole: the sum, wrapping, of each seed's `GraphFuzzerHash`.
struct GraphFuzzerSeedSetSum {
	private(set) var value: UInt64 = 0

	mutating func add(_ seed: UInt64) {
		var hash = GraphFuzzerHash()
		hash.combine(String(seed))
		value &+= hash.value
	}
}

/// FNV-1a over strings, so a pinned value names the same content on every platform.
struct GraphFuzzerHash {
	private(set) var value: UInt64 = 0xCBF29CE484222325

	mutating func combine(_ string: String) {
		for byte in string.utf8 {
			value = (value ^ UInt64(byte)) &* 0x00000100000001B3
		}
		// Separate consecutive strings, so that "ab" then "c" differs from "a" then "bc".
		value = (value ^ 0xFF) &* 0x00000100000001B3
	}
}

/// A graph with what two runs of the tool produced for it.
struct GraphFuzzerToolRuns {
	/// - Parameters:
	///   - renamedOutcomes: The outcome of the graph renamed by each renaming, with the renaming undone.
	///   - inlineOutcome: The outcome of the graph with no seam, when the graph declares one and the tool rejected it.
	///   - visibleOutcome: The outcome of the graph's visible build (`GraphFuzzerFixture.withoutHoles`), when the graph
	///     draws a hole.
	///   - knownRightOutcome: The outcome of the known-right path of a graph drawn with `generateMockPublic`
	///     (`GraphFuzzerGenerator.knownRightPublicMockFixture(forSeed:)`).
	init(
		fixture: GraphFuzzerFixture,
		firstOutcome: GraphFuzzerToolOutcome,
		secondOutcome: GraphFuzzerToolOutcome,
		renamedOutcomes: [(renaming: GraphFuzzerRenaming, outcome: GraphFuzzerToolOutcome)] = [],
		inlineOutcome: GraphFuzzerToolOutcome? = nil,
		visibleOutcome: GraphFuzzerToolOutcome? = nil,
		knownRightOutcome: GraphFuzzerToolOutcome? = nil,
	) {
		self.fixture = fixture
		self.firstOutcome = firstOutcome
		self.secondOutcome = secondOutcome
		self.renamedOutcomes = renamedOutcomes
		self.inlineOutcome = inlineOutcome
		self.visibleOutcome = visibleOutcome
		self.knownRightOutcome = knownRightOutcome
	}

	let fixture: GraphFuzzerFixture
	let firstOutcome: GraphFuzzerToolOutcome
	let secondOutcome: GraphFuzzerToolOutcome
	let renamedOutcomes: [(renaming: GraphFuzzerRenaming, outcome: GraphFuzzerToolOutcome)]
	let inlineOutcome: GraphFuzzerToolOutcome?
	let visibleOutcome: GraphFuzzerToolOutcome?
	let knownRightOutcome: GraphFuzzerToolOutcome?

	/// The failure of a graph whose seam takes a builder for a hole that the tool accepts while it rejects the graph's
	/// visible build, or `nil`: a fill may be rejected where inline would read another value, but what the seam's module
	/// rejects building inline, a fill must reject too.
	var visibleBuildFailure: GraphFuzzerFailure? {
		guard case .accepted = firstOutcome, case let .rejected(diagnostics) = visibleOutcome else { return nil }
		return GraphFuzzerFailure(
			seed: fixture.seed,
			kind: .holeAcceptedWhereVisibleBuildRejects,
			details: "With the hole:\n\(firstOutcome.description)\nThe visible build:\n\(diagnostics)",
		)
	}

	/// The failure of a graph the tool rejects with the seam declared and accepts without it, where the rejection
	/// is not one of a seam's own errors (`GraphFuzzerOracle.isSeamOnlyRejection`) but an error of the inlined
	/// validation, which the seam world should not add, or `nil`. A seam's own error is what the seam rules reject
	/// that inline accepts; any other error is a shape the seam world sees differently than inline, a defect.
	var differentialFailure: GraphFuzzerFailure? {
		// In a graph split across modules, a caller's error that it holds a value its tier omits is a seam's own, which
		// `omittedValueFailure` judges; in a graph in one module, whose seams are called at their narrowest tier, it is
		// never one.
		guard case let .rejected(diagnostics) = firstOutcome, case .accepted = inlineOutcome,
		      !GraphFuzzerOracle.isSeamOnlyRejection(diagnostics: diagnostics, seamTypeNames: fixture.seamTypeNames, excusingOmittedValues: fixture.modules != nil)
		else { return nil }
		return GraphFuzzerFailure(
			seed: fixture.seed,
			kind: .seamRejectsGraphInlineAccepts,
			details: "With the seam:\n\(diagnostics)\nWithout it, the tool accepts the graph.",
		)
	}

	/// The failure of a graph whose `addingUncreatedAliasShapes` seam the tool rejects, where it accepts the graph with
	/// no seam, with an error about that seam that is not one of the uncreated alias's, or `nil`. That seam's tree has
	/// no shape any other seam rule rejects.
	var uncreatedAliasRejectionFailure: GraphFuzzerFailure? {
		guard case let .rejected(diagnostics) = firstOutcome, case .accepted = inlineOutcome else { return nil }
		let aliasSeamName = "dependency tree of `\(fixture.typeNamePrefix)AliasSeam`"
		let errors = diagnostics.split(separator: "\n").filter { $0.contains(": error: ") && $0.contains(aliasSeamName) }
		let uncreatedAliasErrors = errors.filter { line in GraphFuzzerOracle.uncreatedAliasErrorMarkers.contains { line.contains($0) } }
		if errors.count > uncreatedAliasErrors.count {
			return GraphFuzzerFailure(
				seed: fixture.seed,
				kind: .uncreatedAliasSeamRejectedOtherwise,
				details: "With the seam:\n\(diagnostics)\nWithout it, the tool accepts the graph.",
			)
		}
		if uncreatedAliasErrors.contains(where: GraphFuzzerOracle.isUncreatedAliasErrorOfAliasReadingItself) {
			return GraphFuzzerFailure(
				seed: fixture.seed,
				kind: .uncreatedAliasReadsItself,
				details: "With the seam:\n\(diagnostics)\nWithout it, the tool accepts the graph.",
			)
		}
		// The exact-form alias of a required optional parameter is always created: the walk names an alias that may
		// be uncreated, so an uncreated-alias error naming this one is an over-rejection. The static shapes, where
		// the alias is uncreated whatever the parameter, are drawn only for the only-if-available pass-through.
		let drawFeatures = GraphFuzzerFeature.seamDrawFeatures(of: fixture)
		if drawFeatures.contains(.uncreatedAliasExactFormAlias), drawFeatures.contains(.uncreatedAliasRequiredOptionalParameter),
		   uncreatedAliasErrors.contains(where: { $0.contains("`aliasAuth`") })
		{
			return GraphFuzzerFailure(
				seed: fixture.seed,
				kind: .uncreatedAliasExactFormAliasRejected,
				details: "With the seam:\n\(diagnostics)\nWithout it, the tool accepts the graph.",
			)
		}
		return nil
	}

	/// The failure of a graph the tool accepts whose seam's generated code reads the binding of an `onlyIfAvailable`
	/// alias bound from a parameter that defaults to `nil` anywhere but as the argument of the construction of the
	/// type that declares the alias, or `nil`. Inline, that alias is not created where the parameter's property is
	/// unavailable, and any other read finds whatever declaration of the alias's label encloses it, so the seam must
	/// reject every such read. The literal-`nil` oracle cannot see these: their `nil` is the seam call's.
	var uncreatedAliasReadFailure: GraphFuzzerFailure? {
		// A public mock graph's generated mocks are judged by the public mock's own oracles.
		guard knownRightOutcome == nil, case let .accepted(seamFiles, _) = firstOutcome else { return nil }
		// The unwrapped-form alias of a required optional parameter may be uncreated as an alias of a parameter that
		// defaults to `nil` may, so its binding is read the same way; the exact-form alias is always created.
		let drawFeatures = GraphFuzzerFeature.seamDrawFeatures(of: fixture)
		let requiredOptionalParameters: Set<String> = drawFeatures.contains(.uncreatedAliasRequiredOptionalParameter) && !drawFeatures.contains(.uncreatedAliasExactFormAlias) ? ["aliasToken"] : []
		let reads = GraphFuzzerOracle.uncreatedAliasBindingReads(in: seamFiles, requiredOptionalParameters: requiredOptionalParameters)
		guard !reads.isEmpty else { return nil }
		return GraphFuzzerFailure(
			seed: fixture.seed,
			kind: .seamReadsUncreatedAliasBinding,
			details: "\(reads.joined(separator: "\n"))\nThis graph:\n\(firstOutcome.description)",
		)
	}

	/// The failure of a graph the tool accepts whose generated seam tier is wider than a type one of its parameters
	/// names, by the access the generator gave each type it drew (`GraphFuzzerGenerator.narrowerTypeAccess`), or `nil`.
	var tierAccessFailure: GraphFuzzerFailure? {
		// A public mock graph's generated declarations are judged by `publicMockAccessFailure`.
		guard knownRightOutcome == nil, case let .accepted(seamFiles, _) = firstOutcome else { return nil }
		let findings = GraphFuzzerOracle.tiersWiderThanParameterTypes(
			in: seamFiles,
			typeAccess: GraphFuzzerGenerator.narrowerTypeAccess(forSeed: fixture.seed, features: GraphFuzzerGeneratorFeature.features(drawnIn: fixture)),
		)
		guard !findings.isEmpty else { return nil }
		return GraphFuzzerFailure(seed: fixture.seed, kind: .seamTierWiderThanParameterType, details: "\(findings.joined(separator: "\n"))\nThis graph:\n\(firstOutcome.description)")
	}

	/// The failure of a graph split across modules whose `ProofSeam` call in a caller's module omits a parameter
	/// against what the caller's inline build does, or `nil`. Inline, each type of the seam's tree is built in the
	/// caller's module, so the inline build shows which receivers the caller hands a value. The tool must report an
	/// error exactly where a tier a caller calls omits a parameter some receiver of which the inline build passes a
	/// value – a binding, rather than `nil` – so an accepted graph whose call omits such a parameter fails, as does an
	/// error that a caller holds a value its tier omits where the inline build passes every receiver of it `nil`.
	/// Judged only where the tool accepts the graph inline; an alias's receiver is not followed.
	var omittedValueFailure: GraphFuzzerFailure? {
		guard fixture.modules != nil, case let .accepted(inlineFiles, _) = inlineOutcome else { return nil }
		let seamName = fixture.typeNamePrefix + "ProofSeam"
		var receiversByLabel = [String: Set<String>]()
		for content in fixture.swiftFileContent {
			var currentType: String?
			for line in GraphFuzzerSourceLine.lines(of: content) {
				switch line {
				case let .typeDeclaration(name):
					currentType = name
				case let .property(attribute, label, _):
					if let currentType, attribute == "@Received" || attribute == "@Received(onlyIfAvailable: true)" {
						receiversByLabel[label, default: []].insert(currentType)
					}
				case .instantiableAttribute, .instantiateMethod, .other:
					break
				}
			}
		}
		/// Whether the inline build of `module` passes some receiver of `label` a value.
		func inlinePassesValue(for label: String, in module: GraphFuzzerModule) -> Bool {
			inlineFiles.contains { fileName, contents in
				fileName.hasPrefix(module.name + "/") && (receiversByLabel[label] ?? []).contains { receiver in
					GraphFuzzerOracle.initializerCalls(of: receiver, in: contents).contains { call in
						call.contains { $0.label == label && $0.value != "nil" }
					}
				}
			}
		}
		var findings = [String]()
		let kind: GraphFuzzerFailure.Kind
		switch firstOutcome {
		case let .accepted(seamFiles, _):
			kind = .seamTierOmitsValueInlinePasses
			let parameterLabels = Set(seamFiles.values.flatMap(GraphFuzzerOracle.seamInitializers(inGeneratedFile:)).filter { $0.seamTypeName == seamName }.flatMap { tier in
				tier.parameters.map { $0.prefix { $0 != ":" }.trimmingCharacters(in: .whitespaces) }
			})
			for module in [GraphFuzzerModule.samePackageCaller, .otherPackageCaller] {
				for (fileName, contents) in seamFiles.sorted(by: { $0.key < $1.key }) where fileName.hasPrefix(module.name + "/") && !fileName.hasSuffix("+SafeDISeamCaller.swift") {
					for call in GraphFuzzerOracle.initializerCalls(of: seamName, in: contents) {
						for label in parameterLabels.subtracting(call.map(\.label)).sorted() where inlinePassesValue(for: label, in: module) {
							findings.append("\(fileName) calls `\(seamName)` without `\(label)`, which the inline build of \(module.name) passes a receiver a value for, and the tool reports no error.")
						}
					}
				}
			}
		case let .rejected(diagnostics):
			kind = .seamTierOmitsProvidedValueReportedWhereInlinePassesNil
			for error in diagnostics.split(separator: "\n") where error.contains(": error: ") {
				guard let label = GraphFuzzerOracle.omittedValueLabel(of: error),
				      let module = [GraphFuzzerModule.samePackageCaller, .otherPackageCaller].first(where: { error.contains("/Sources/\($0.name)/") }),
				      !inlinePassesValue(for: label, in: module)
				else { continue }
				findings.append("The tool reports that \(module.name) holds `\(label)`, but the inline build of \(module.name) passes every receiver of it `nil`: \(error)")
			}
		}
		guard !findings.isEmpty else { return nil }
		return GraphFuzzerFailure(seed: fixture.seed, kind: kind, details: "\(findings.joined(separator: "\n"))\nThis graph:\n\(firstOutcome.description)\nInline:\n\(inlineOutcome?.description ?? "")")
	}

	/// Whether the value oracle inspected the graph: the tool accepts it with the seam and without it, or accepts a
	/// `generateMockPublic` graph and its known-right path.
	var isInspectedByValueOracle: Bool {
		guard case .accepted = firstOutcome else { return false }
		switch (inlineOutcome, knownRightOutcome) {
		case (.accepted?, _), (_, .accepted?):
			return true
		case (.rejected?, _), (_, .rejected?), (nil, nil):
			return false
		}
	}

	/// The failure of a graph the tool accepts with the seam and without it, whose generated code, over the whole
	/// module, passes a literal `nil` to some argument of some type's construction more often with the seam than
	/// without it, or `nil`. A seam that passes `nil` where inline passes a value loses a value a receiver gets today.
	/// The constructions of a seam type itself are not compared: its own tiers and the calls of them pass `nil` for
	/// what a tier omits, which inline has no counterpart of. A seam that reads a value inline does not (the
	/// documented divergences) lowers its count, which is no failure.
	var nilArgumentFailure: GraphFuzzerFailure? {
		guard case let .accepted(seamFiles, _) = firstOutcome, case let .accepted(inlineFiles, _) = inlineOutcome else { return nil }
		let seamTypeNames = Set(fixture.swiftFileContent.flatMap { content -> [String] in
			var nextTypeIsSeam = false
			var names = [String]()
			for line in GraphFuzzerSourceLine.lines(of: content) {
				switch line {
				case let .instantiableAttribute(arguments):
					nextTypeIsSeam = arguments.contains("generateDependencyTree: true")
				case let .typeDeclaration(name):
					if nextTypeIsSeam {
						names.append(name)
					}
					nextTypeIsSeam = false
				case .instantiateMethod, .property, .other:
					break
				}
			}
			return names
		})
		let differences = GraphFuzzerOracle.nilArgumentCountsExceeding(
			GraphFuzzerOracle.nilArgumentCounts(in: seamFiles, typeNamePrefix: fixture.typeNamePrefix, excluding: seamTypeNames),
			GraphFuzzerOracle.nilArgumentCounts(in: inlineFiles, typeNamePrefix: fixture.typeNamePrefix, excluding: seamTypeNames),
		)
		guard !differences.isEmpty else { return nil }
		return GraphFuzzerFailure(
			seed: fixture.seed,
			kind: .seamPassesNilWhereInlinePassesValue,
			details: "\(differences.joined(separator: "\n"))\nWith the seam:\n\(firstOutcome.description)\nWithout it:\n\(inlineOutcome?.description ?? "")",
		)
	}

	/// The failure of each renamed graph that, with its renaming undone, gives another verdict, other
	/// diagnostics or warnings in any order (the tool sorts them by file, and the files are renamed), each
	/// diagnostic's suggestions in any order, other generated file names, or generated code that is not
	/// byte-identical.
	var renamedGraphFailures: [GraphFuzzerFailure] {
		renamedOutcomes.compactMap { renaming, outcome in
			guard let difference = GraphFuzzerToolOutcome.difference(between: firstOutcome, and: outcome) else { return nil }
			return GraphFuzzerFailure(
				seed: fixture.seed,
				kind: .renamedGraphDiffers,
				details: "\(renaming.description.prefix(1).uppercased())\(renaming.description.dropFirst()) changes \(difference).\nThis graph:\n\(firstOutcome.description)\nThe renamed graph, with its renaming undone:\n\(outcome.description)",
			)
		}
	}

	var runsDifferFailure: GraphFuzzerFailure? {
		guard firstOutcome != secondOutcome else { return nil }
		return GraphFuzzerFailure(
			seed: fixture.seed,
			kind: .runsDiffer,
			details: "First run:\n\(firstOutcome.description)\nSecond run:\n\(secondOutcome.description)",
		)
	}

	/// The failure of a graph whose generated `mock()` takes a `LazilyInstantiated` or `SendableLazilyInstantiated`
	/// parameter that is not a property the mocked type forwards or instantiates, or `nil` when none does. A mock takes
	/// the instance of a dependency its tree receives as a wrapper it cannot build, and wraps the instance for the
	/// receivers, so a type's mock has the same parameters whether the dependencies it receives are lazily
	/// instantiated or not.
	var wrapperParameterFailure: GraphFuzzerFailure? {
		var wrapperPropertyTypesByTypeName = [String: Set<String>]()
		for content in fixture.swiftFileContent {
			var currentTypeName: String?
			for line in GraphFuzzerSourceLine.lines(of: content) {
				switch line {
				case let .typeDeclaration(name):
					currentTypeName = name
				case let .property(attribute, _, type):
					if let currentTypeName, attribute == "@Forwarded" || attribute.hasPrefix("@Instantiated") {
						wrapperPropertyTypesByTypeName[currentTypeName, default: []].insert(type)
					}
				case .instantiableAttribute, .instantiateMethod, .other:
					break
				}
			}
		}
		let mockFileSuffix = "+SafeDIMock.swift"
		var wrapperParameters = [String]()
		for (fileName, contents) in generatedFiles.sorted(by: { $0.key < $1.key }) where fileName.hasSuffix(mockFileSuffix) {
			// A split graph's generated files are keyed by their module's name.
			let mockedTypeName = String(fileName.dropLast(mockFileSuffix.count).split(separator: "/").last ?? "")
			let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
			guard let signatureStart = lines.firstIndex(where: { $0.hasSuffix("static func mock(") }) else { continue }
			for line in lines[(signatureStart + 1)...].prefix(while: { !$0.hasPrefix(")") }) {
				guard let typeStart = line.range(of: ": ") else { continue }
				let type = String(line[typeStart.upperBound...].prefix { $0 != "=" && $0 != "," }).trimmingCharacters(in: .whitespaces)
				if type.hasPrefix("LazilyInstantiated<") || type.hasPrefix("SendableLazilyInstantiated<"),
				   wrapperPropertyTypesByTypeName[mockedTypeName]?.contains(type) != true
				{
					wrapperParameters.append("`\(mockedTypeName).mock` takes `\(line[..<typeStart.lowerBound]): \(type)`.")
				}
			}
		}
		guard !wrapperParameters.isEmpty else { return nil }
		return GraphFuzzerFailure(
			seed: fixture.seed,
			kind: .mockTakesWrapperParameterForReceive,
			details: "\(wrapperParameters.joined(separator: "\n"))\nThis graph:\n\(firstOutcome.description)",
		)
	}

	var generatedFiles: [String: String] {
		switch firstOutcome {
		case let .accepted(generatedFiles, _):
			generatedFiles
		case .rejected:
			[:]
		}
	}
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
enum GraphFuzzerOracle {
	/// Runs each seed's graph through SafeDITool twice, then compiles every graph's fixture, with the generated
	/// code of each graph the tool accepted, in as few `swiftc` invocations as attribution allows. Compilation is
	/// skipped when `compileVerificationIsEnabled` is `false`.
	///
	/// - Parameter willRunSeed: Called before the tool first runs a seed's graph, so that a long run can record
	///   which seed was running if the tool crashes the process.
	static func results(
		forSeeds seeds: [UInt64],
		features: Set<GraphFuzzerGeneratorFeature> = [],
		willRunSeed: @Sendable (UInt64) -> Void = { _ in },
	) async throws -> [GraphFuzzerResult] {
		var toolRuns = [GraphFuzzerToolRuns]()
		for seed in seeds {
			willRunSeed(seed)
			await toolRuns.append(try self.toolRuns(of: GraphFuzzerGenerator.fixture(forSeed: seed, features: features)))
		}
		return try results(of: toolRuns)
	}

	/// The oracle's verdict on graphs the tool already ran.
	static func results(of toolRuns: [GraphFuzzerToolRuns]) throws -> [GraphFuzzerResult] {
		let compilationFailures = compileVerificationIsEnabled
			? try compilationFailures(of: toolRuns.filter { $0.runsDifferFailure == nil })
			: [:]
		let valueFailures = try valueFailures(of: toolRuns.filter { $0.runsDifferFailure == nil && compilationFailures[$0.fixture.seed] == nil })
		return toolRuns.map { runs in
			let renamedGraphFailures = runs.renamedGraphFailures
			let failures = [runs.runsDifferFailure, runs.differentialFailure, runs.visibleBuildFailure, runs.publicMockAcceptanceFailure, runs.uncreatedAliasRejectionFailure, runs.nilArgumentFailure, runs.uncreatedAliasReadFailure, runs.tierAccessFailure, runs.publicMockAccessFailure, runs.omittedValueFailure, compilationFailures[runs.fixture.seed], valueFailures[runs.fixture.seed], runs.wrapperParameterFailure, renamedGraphFailures.first].compactMap(\.self)
			return GraphFuzzerResult(
				fixture: runs.fixture,
				outcome: runs.firstOutcome,
				failure: failures.first,
				laterFailures: Array(failures.dropFirst()),
				renamedGraphFailures: renamedGraphFailures,
				isInspectedByValueOracle: runs.isInspectedByValueOracle,
				isComparedByValueOracle: compileVerificationIsEnabled && runs.isInspectedByValueOracle && runs.runsDifferFailure == nil && compilationFailures[runs.fixture.seed] == nil,
			)
		}
	}

	/// The failure of each graph of `toolRuns` the tool accepts with its seam and without it whose seam build
	/// constructs other values than its inline build, or whose two builds the differential value comparator could
	/// not describe, keyed by seed. The seam path is the graph with its seams and the files the tool generated for it,
	/// the known-right path the same graph with no seam and the files the tool generated for that; the probes are the
	/// graph's roots and the generated mocks that take no required parameter. Each path is built from the graph drawn
	/// storing every parameter, so the comparator sees every value the generated code passes; storing changes nothing
	/// the tool generates. Each graph exempts its documented divergences (`documentedSeamValueDivergences`). The graphs
	/// of one call are compared in one batch. Nothing is compared when `compileVerificationIsEnabled` is `false`.
	static func valueFailures(of toolRuns: [GraphFuzzerToolRuns]) throws -> [UInt64: GraphFuzzerFailure] {
		let inspectedRuns = toolRuns.filter(\.isInspectedByValueOracle)
		// A graph with a hole is compared with its visible build too, in which the seam builds the fulfilling type.
		let visibleRuns = toolRuns.filter { runs in
			guard case .accepted = runs.firstOutcome, case .accepted = runs.visibleOutcome else { return false }
			return true
		}
		guard !inspectedRuns.isEmpty || !visibleRuns.isEmpty, compileVerificationIsEnabled else { return [:] }
		var filesToDelete = [URL]()
		defer {
			for fileToDelete in filesToDelete {
				try? FileManager.default.removeItem(at: fileToDelete)
			}
		}
		// Each graph beside the runs it judges: a public mock graph's against its known-right path
		// (`publicMockValueGraph(of:)`), a seam graph's against its inline build.
		let graphs = inspectedRuns.compactMap { runs -> (runs: GraphFuzzerToolRuns, graph: DifferentialValueGraph)? in
			if let graph = publicMockValueGraph(of: runs) {
				return (runs, graph)
			}
			guard case let .accepted(seamFiles, _) = runs.firstOutcome, case let .accepted(inlineFiles, _) = runs.inlineOutcome else { return nil }
			let storingFixture = GraphFuzzerGenerator.fixture(forSeed: runs.fixture.seed, features: GraphFuzzerGeneratorFeature.features(drawnIn: runs.fixture), storingEveryParameter: true)
			return (runs, DifferentialValueGraph(
				name: "seed \(runs.fixture.seed)",
				feature: DifferentialValuePath(fixture: storingFixture, generatedFiles: seamFiles),
				knownRight: DifferentialValuePath(fixture: storingFixture.withoutSeams, generatedFiles: inlineFiles),
				probes: storingFixture.differentialValueProbes(generatedFiles: seamFiles),
				exemptions: Self.documentedSeamValueDivergences(of: runs.fixture),
			))
		}
		let visibleGraphs = visibleRuns.compactMap { runs -> DifferentialValueGraph? in
			guard case let .accepted(holeFiles, _) = runs.firstOutcome, case let .accepted(visibleFiles, _) = runs.visibleOutcome else { return nil }
			let storingFixture = GraphFuzzerGenerator.fixture(forSeed: runs.fixture.seed, features: GraphFuzzerGeneratorFeature.features(drawnIn: runs.fixture), storingEveryParameter: true)
			return DifferentialValueGraph(
				name: "seed \(runs.fixture.seed), visible build",
				feature: DifferentialValuePath(fixture: storingFixture, generatedFiles: holeFiles),
				knownRight: DifferentialValuePath(fixture: storingFixture.withoutHoles, generatedFiles: visibleFiles),
				probes: storingFixture.differentialValueProbes(generatedFiles: holeFiles),
			)
		}
		guard let comparisons = try DifferentialValueOracle.compare(graphs: graphs.map(\.graph) + visibleGraphs, filesToDelete: &filesToDelete) else { return [:] }
		var failures = [UInt64: GraphFuzzerFailure]()
		for (runs, comparison) in zip(visibleRuns, comparisons.dropFirst(graphs.count)) {
			switch comparison.result {
			case let .success(valueComparison):
				let differences = valueComparison.differences
				guard !differences.isEmpty else { continue }
				failures[runs.fixture.seed] = GraphFuzzerFailure(
					seed: runs.fixture.seed,
					kind: .holeBuildsOtherValuesThanVisibleBuild,
					details: "\(differences.map(\.description).joined(separator: "\n"))\n\(valueComparison.report)With the hole:\n\(runs.firstOutcome.description)\nThe visible build:\n\(runs.visibleOutcome?.description ?? "")",
					valueDifferences: differences.map(\.description),
				)
			case let .failure(error):
				failures[runs.fixture.seed] = GraphFuzzerFailure(
					seed: runs.fixture.seed,
					kind: .valueComparatorCouldNotDescribeGraph,
					details: "\(error)\nWith the hole:\n\(runs.firstOutcome.description)\nThe visible build:\n\(runs.visibleOutcome?.description ?? "")",
				)
			}
		}
		// A difference from the visible build is reported before one from the inline build. The visible build is the
		// reference for the hole draw's seam re-entered inside its tree (`holeSeamBuilder`): the inline reference closes
		// that lazy cycle on the outer builder function, a main defect (the shape of seed 662), and hands the second
		// round the outer seam's values, where the hole build and the visible build both build the seam afresh.
		let visiblyComparedSeeds = Set(visibleRuns.map(\.fixture.seed))
		for ((runs, _), comparison) in zip(graphs, comparisons) where failures[runs.fixture.seed] == nil {
			let isPublicMockGraph = runs.knownRightOutcome != nil
			let builds = isPublicMockGraph
				? "As drawn:\n\(runs.firstOutcome.description)\nKnown right:\n\(runs.knownRightOutcome?.description ?? "")"
				: "With the seam:\n\(runs.firstOutcome.description)\nWithout it:\n\(runs.inlineOutcome?.description ?? "")"
			switch comparison.result {
			case let .success(valueComparison):
				// A public mock graph exempts the shape matrix's stated divergences, derived from its leaf calls.
				let statedDivergences = isPublicMockGraph ? Self.statedPublicMockValueDivergences(in: valueComparison, of: runs) : []
				let differences = valueComparison.differences.filter { difference in
					(!visiblyComparedSeeds.contains(runs.fixture.seed) || !difference.path.contains("holeSeamBuilder"))
						&& !statedDivergences.contains(difference)
				}
				guard !differences.isEmpty else { continue }
				failures[runs.fixture.seed] = GraphFuzzerFailure(
					seed: runs.fixture.seed,
					kind: isPublicMockGraph ? .publicMockBuildsOtherValuesThanKnownRight : .seamBuildsOtherValuesThanInline,
					details: "\(differences.map(\.description).joined(separator: "\n"))\n\(valueComparison.report)\(builds)",
					valueDifferences: differences.map(\.description),
				)
			case let .failure(error):
				failures[runs.fixture.seed] = GraphFuzzerFailure(
					seed: runs.fixture.seed,
					kind: .valueComparatorCouldNotDescribeGraph,
					details: "\(error)\n\(builds)",
				)
			}
		}
		return failures
	}

	/// The differences between a seam build and its inline build that the Manual documents, stated exactly, which the
	/// comparison of `fixture`'s graph exempts. They are the first divergence of the graphs that also fail an inherited
	/// known-issue shape, so that the shape's seed stays listed there (the graphs that show the first or second
	/// divergence and nothing else are known issues of the divergence's shape, which matches every difference of a
	/// failure), and every eager read of the third, one exemption per read: a seam call passes `.instance` of a
	/// wrapper its caller holds, where inline the receiver inside the seam's tree reads it when it is built, so the
	/// seam build's description marks the instance `(built before the probe's value)`. Observed from the corpus run,
	/// as `seamCorpusSeedsOfOtherShapes` is.
	static func documentedSeamValueDivergences(of fixture: GraphFuzzerFixture) -> [DifferentialValueDifference] {
		switch fixture.seed {
		case 239:
			// The third documented divergence: each root calls the seam `S239_T2` with `seamLazy.instance`, where inline
			// `S239_T1`, built by an instantiator in the seam's tree, reads it.
			[
				DifferentialValueDifference(
					probe: "S239_Root0()",
					path: ["<11>.instance"],
					feature: "<11>.instance: <8> S239_SeamShared (built before the probe's value) (seen, first at <1> S239_Root0 > t0 > anyT2 > value > t1Builder > instantiate() > seamLazy)",
					knownRight: "<11>.instance: <8> S239_SeamShared (seen, first at <1> S239_Root0 > t0 > anyT2 > value > t1Builder > instantiate() > seamLazy)",
				),
				DifferentialValueDifference(
					probe: "S239_Root1()",
					path: ["<12>.instance"],
					feature: "<12>.instance: <8> S239_SeamShared (built before the probe's value) (seen, first at <1> S239_Root1 > t0 > anyT2 > value > t1Builder > instantiate() > seamLazy)",
					knownRight: "<12>.instance: <8> S239_SeamShared (seen, first at <1> S239_Root1 > t0 > anyT2 > value > t1Builder > instantiate() > seamLazy)",
				),
			]
		case 240:
			// The third documented divergence: the root calls the seam `S240_T3` with `seamLazy.instance`, where inline
			// `S240_T5`, built by an instantiator in the seam's tree, reads it.
			[
				DifferentialValueDifference(
					probe: "S240_Root0()",
					path: ["<68>.instance"],
					feature: "<68>.instance: <28> S240_SeamShared (built before the probe's value) (seen, first at <1> S240_Root0 > t3 > t5Builder > instantiate() > t3Builder > instantiate() > t5Builder > instantiate() > seamLazy)",
					knownRight: "<68>.instance: <28> S240_SeamShared (seen, first at <1> S240_Root0 > t3 > t5Builder > instantiate() > t3Builder > instantiate() > t5Builder > instantiate() > seamLazy)",
				),
			]
		case 298:
			// The third documented divergence: the root calls the seam `S298_T4` with `seamLazy.instance`, where inline
			// `S298_T2`, built by an instantiator in the seam's tree, reads it.
			[
				DifferentialValueDifference(
					probe: "S298_Root1()",
					path: ["<16>.instance"],
					feature: "<16>.instance: <5> S298_SeamShared (built before the probe's value) (seen, first at <1> S298_Root1 > t2Builder > instantiate() > seamLazy)",
					knownRight: "<16>.instance: <5> S298_SeamShared (seen, first at <1> S298_Root1 > t2Builder > instantiate() > seamLazy)",
				),
			]
		case 358:
			// The third documented divergence: each root calls the seam `S358_T1` with `seamLazy.instance`, where inline
			// `S358_T2`, built by an erased instantiator the comparator does not traverse, reads it.
			[
				DifferentialValueDifference(
					probe: "S358_Root0()",
					path: ["<5>.instance"],
					feature: "<5>.instance: <8> S358_SeamShared (built before the probe's value)",
					knownRight: "<5>.instance: <8> S358_SeamShared",
				),
				DifferentialValueDifference(
					probe: "S358_Root1()",
					path: ["<5>.instance"],
					feature: "<5>.instance: <6> S358_SeamShared (built before the probe's value)",
					knownRight: "<5>.instance: <6> S358_SeamShared",
				),
				DifferentialValueDifference(
					probe: "S358_Root2()",
					path: ["<5>.instance"],
					feature: "<5>.instance: <6> S358_SeamShared (built before the probe's value)",
					knownRight: "<5>.instance: <6> S358_SeamShared",
				),
			]
		case 833:
			// The first documented divergence: the caller holds only the optional form of the alias's fulfilling
			// property, and the seam creates the alias from it.
			[DifferentialValueDifference(
				probe: "S833_Root0()",
				path: ["<1> S833_Root0", "aliasSeam", "aliasLeft", "aliasDetail", "aliasAuth"],
				feature: "aliasAuth: <13> S833_AliasValue (seen, first at <1> S833_Root0 > aliasSource)",
				knownRight: "aliasAuth: nil",
			)]
		default:
			[]
		}
	}

	/// How many times the code in `generatedFiles` passes a literal `nil` to each argument of each construction of a
	/// type whose name begins with `typeNamePrefix`, but those of `excludedTypeNames`, keyed by the type and the
	/// argument's label, as `Type(label:)`. The oracle's own seam callers are not generated code and are skipped.
	static func nilArgumentCounts(in generatedFiles: [String: String], typeNamePrefix: String, excluding excludedTypeNames: Set<String>) -> [String: Int] {
		var counts = [String: Int]()
		let expression = try! NSRegularExpression(pattern: "(?<![A-Za-z0-9_.])(" + NSRegularExpression.escapedPattern(for: typeNamePrefix) + "[A-Za-z0-9_]+)\\(")
		for (fileName, contents) in generatedFiles where !fileName.hasSuffix("+SafeDISeamCaller.swift") {
			let source = contents as NSString
			for match in expression.matches(in: contents, range: NSRange(location: 0, length: source.length)) {
				let typeName = source.substring(with: match.range(at: 1))
				guard !excludedTypeNames.contains(typeName) else { continue }
				// The arguments run from after the opening parenthesis to the one that closes it.
				let start = match.range.location + match.range.length
				var depth = 1
				var end = start
				while end < source.length, depth > 0 {
					switch source.character(at: end) {
					case 0x28, 0x5B, 0x7B: // ( [ {
						depth += 1
					case 0x29, 0x5D, 0x7D: // ) ] }
						depth -= 1
					default:
						break
					}
					end += 1
				}
				let arguments = source.substring(with: NSRange(location: start, length: max(0, end - start - 1)))
				for argument in topLevelParameters(arguments) {
					let parts = argument.split(separator: ":", maxSplits: 1)
					guard parts.count == 2, parts[1].trimmingCharacters(in: .whitespacesAndNewlines) == "nil" else { continue }
					counts["\(typeName)(\(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)):)", default: 0] += 1
				}
			}
		}
		return counts
	}

	/// A line for each construction argument `seamCounts` passes a literal `nil` more often than `inlineCounts`, in
	/// order.
	static func nilArgumentCountsExceeding(_ seamCounts: [String: Int], _ inlineCounts: [String: Int]) -> [String] {
		seamCounts.keys.sorted().compactMap { key in
			let seamCount = seamCounts[key] ?? 0
			let inlineCount = inlineCounts[key] ?? 0
			return seamCount > inlineCount ? "`\(key)` is passed `nil` \(seamCount) times with the seam and \(inlineCount) without it." : nil
		}
	}

	/// Whether `error`, an uncreated-alias error, says a type aliases a property under the label of the uncreated
	/// alias it reads, and that the reading type declares that alias itself – the message names another declaring
	/// type only where it is not the reader. A type cannot declare two properties of one label, so that alias reads
	/// itself, which an alias that keeps its fulfilling property's label does not.
	static func isUncreatedAliasErrorOfAliasReadingItself(_ error: Substring) -> Bool {
		let pattern = #"aliases `[^`]+` as `([^`]+)`, and `\1` is an `onlyIfAvailable` alias that is not created "#
		guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
		let text = String(error)
		return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
	}

	/// What each error of a seam's uncreated `onlyIfAvailable` alias says: a receive beneath it, an alias of it, or a
	/// declaration of its property beside its declaring type.
	static let uncreatedAliasErrorMarkers = [
		"` beneath the `onlyIfAvailable` alias `",
		"` is an `onlyIfAvailable` alias ",
		": the `onlyIfAvailable` alias `",
	]

	/// Each read, in `generatedFiles`, of the binding of an `onlyIfAvailable` alias bound from a parameter of a seam's
	/// generated initializer that defaults to `nil` – `let <alias>: T? = <parameter>`, or an erased alias mapping it –
	/// other than as the argument of the construction that ends the body declaring the binding (`return` or
	/// `self.init`), which is the type that declares the alias. A binding from a nearer declaration of the parameter's
	/// name is not such an alias, and a read beneath a nearer declaration of the alias's name reads that one. The
	/// generated code is indented by four spaces a level and opens each body on the line that declares it.
	///
	/// - Parameter requiredOptionalParameters: The labels of required parameters of optional type whose aliases are
	///   read as those of a parameter defaulting to `nil` are: the unwrapped-form alias of such a parameter may be
	///   uncreated too.
	static func uncreatedAliasBindingReads(in generatedFiles: [String: String], requiredOptionalParameters: Set<String> = []) -> [String] {
		var reads = [String]()
		let declaration = try! NSRegularExpression(pattern: #"^let (`[^`]+`|[A-Za-z_][A-Za-z0-9_]*)(?:: [^=]+)? = (.*)$"#)
		let function = try! NSRegularExpression(pattern: #"^(?:@Sendable )?func [^(]+\((.*)\) -> .* \{$"#)
		func match(_ expression: NSRegularExpression, _ line: String) -> [String]? {
			let source = line as NSString
			guard let result = expression.firstMatch(in: line, range: NSRange(location: 0, length: source.length)) else { return nil }
			return (1..<result.numberOfRanges).map { result.range(at: $0).location == NSNotFound ? "" : source.substring(with: result.range(at: $0)) }
		}
		/// The labels of `parameters`, a parameter list's text, whose parameters default to `nil` when `defaultingToNil`,
		/// or are among `requiredOptionalParameters` and are of optional type.
		func labels(of parameters: String, defaultingToNil: Bool) -> [String] {
			topLevelParameters(parameters).compactMap { parameter in
				let parts = parameter.split(separator: ":", maxSplits: 1)
				guard parts.count == 2 else { return nil }
				let label = parts[0].trimmingCharacters(in: .whitespaces)
				let isRequiredOptional = requiredOptionalParameters.contains(label) && parts[1].trimmingCharacters(in: .whitespaces).hasSuffix("?")
				guard !defaultingToNil || parameter.hasSuffix("= nil") || isRequiredOptional else { return nil }
				return label
			}
		}
		func references(_ name: String, in line: String) -> Bool {
			let expression = try! NSRegularExpression(pattern: "(?<![A-Za-z0-9_.`])" + NSRegularExpression.escapedPattern(for: name) + "(?![A-Za-z0-9_`])(?!\\s*:)")
			return expression.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
		}
		for (fileName, contents) in generatedFiles.sorted(by: { $0.key < $1.key }) {
			let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
			var lineIndex = 0
			while lineIndex < lines.count {
				let initializerLine = lines[lineIndex]
				let trimmed = initializerLine.trimmingCharacters(in: .whitespaces)
				lineIndex += 1
				// A tier may carry attributes before its modifier, with spaces inside them (`@available(iOS 17, *)`).
				guard trimmed.hasSuffix(") {"),
				      let parametersStart = trimmed.range(of: "init("),
				      ["public ", "package ", "internal "].contains(where: { modifier in
				      	trimmed.range(of: "\(modifier)init(")?.upperBound == parametersStart.upperBound
				      		|| trimmed.range(of: "\(modifier)convenience init(")?.upperBound == parametersStart.upperBound
				      })
				else { continue }
				let parameters = String(trimmed[parametersStart.upperBound..<trimmed.index(trimmed.endIndex, offsetBy: -3)])
				let defaultingToNil = Set(labels(of: parameters, defaultingToNil: true))
				guard !defaultingToNil.isEmpty else { continue }
				let initializerIndent = initializerLine.prefix { $0 == " " }.count
				// Each open body's indent and the names it declares; the initializer's body first.
				var scopes = [(indent: Int, names: Set<String>)]()
				scopes.append((initializerIndent + 4, []))
				// The bindings of aliases of a parameter defaulting to `nil`: the name and the scope declaring it.
				var bindings = [(name: String, scopeIndex: Int)]()
				while lineIndex < lines.count {
					let line = lines[lineIndex]
					lineIndex += 1
					let indent = line.prefix { $0 == " " }.count
					let code = line.trimmingCharacters(in: .whitespaces)
					if code == "}", indent == initializerIndent {
						break
					}
					guard !code.isEmpty, !code.hasPrefix("#sourceLocation"), !code.hasPrefix("//") else { continue }
					while let last = scopes.last, indent < last.indent, scopes.count > 1 {
						scopes.removeLast()
						bindings.removeAll { $0.scopeIndex >= scopes.count }
					}
					let statement = code.components(separatedBy: " // Declared at ").first ?? code
					let declared = match(declaration, statement)
					// A read of a binding – in a declaration, in its value – is the declaring type's construction, which ends
					// the body that declares the binding, or a read the seam should have rejected.
					for binding in bindings where references(binding.name, in: declared?[1] ?? statement) {
						let isShadowed = scopes[(binding.scopeIndex + 1)...].contains { $0.names.contains(binding.name) }
						let isDeclaringConstruction = indent == scopes[binding.scopeIndex].indent && (statement.hasPrefix("return ") || statement.hasPrefix("self.init("))
						if !isShadowed, !isDeclaringConstruction {
							reads.append("\(fileName): `\(statement)` reads `\(binding.name)`.")
						}
					}
					if let parts = declared {
						let name = parts[0]
						let value = parts[1]
						let source = value.hasPrefix("(") ? String(value.dropFirst().prefix { $0 != " " }) : value
						let resolvesToParameter = defaultingToNil.contains(source) && !scopes.contains { $0.names.contains(source) }
						scopes[scopes.count - 1].names.insert(name)
						if resolvesToParameter {
							bindings.append((name, scopes.count - 1))
						}
					}
					if statement.hasSuffix("{") {
						var names = Set<String>()
						if let parts = match(function, statement) {
							names = Set(labels(of: parts[0], defaultingToNil: false))
						}
						scopes.append((indent + 4, names))
					}
				}
			}
		}
		return reads
	}

	/// Whether every error in `diagnostics`, a seam-world rejection, is one of a seam's own: reported at the seam
	/// about its generated initializer or a call of it, which no inlined tree has. The inlined validation's errors
	/// name a property or a type; a seam's name the dependency tree of the seam, or the call of its initializer.
	static func isSeamOnlyRejection(diagnostics: String, seamTypeNames: [String], excusingOmittedValues: Bool = false) -> Bool {
		let markers = seamOnlyErrorMarkers + seamTypeNames.map { "` is hidden in chain: \($0) -> " }
		let errors = diagnostics.split(separator: "\n").filter { $0.contains(": error: ") }
		return !errors.isEmpty && errors.allSatisfy { error in
			markers.contains { error.contains($0) } || excusingOmittedValues && isOmittedValueError(error)
		}
	}

	/// Whether `error`, a diagnostic line, reports a caller holding a value for a parameter the seam tier it calls
	/// omits: "`Host` provides `theme: Theme`, but …", or, where the provider's file cannot be read, "`Host` in module
	/// `Base` provides `theme: Theme`, but …".
	static func isOmittedValueError(_ error: Substring) -> Bool {
		guard let message = error.range(of: ": error: ").map({ error[$0.upperBound...] }) else { return false }
		return message.hasPrefix("`") && message.contains("` provides `") && message.contains("`, but ")
	}

	/// The label of the parameter an omitted-value error names: `theme` of "`Host` provides `theme: Theme`, but …".
	static func omittedValueLabel(of error: Substring) -> String? {
		guard isOmittedValueError(error), let provides = error.range(of: "` provides `") else { return nil }
		return String(error[provides.upperBound...].prefix { $0 != ":" })
	}

	/// The access levels SafeDI and Swift spell, narrowest first, as `GraphFuzzerGenerator.AccessLevel` orders them.
	static func accessLevel(spelled spelling: String) -> GraphFuzzerGenerator.AccessLevel {
		switch spelling {
		case "public", "open":
			.public
		case "package":
			.package
		default:
			.internal
		}
	}

	/// Each generated tier in `generatedFiles` wider than a type one of its parameters names, by `typeAccess` – the
	/// access of each type narrower than `public`, by the name its fixture spells it with – as a line naming the seam,
	/// the tier, the parameter and the type. Every type `typeAccess` does not name is `public`.
	static func tiersWiderThanParameterTypes(in generatedFiles: [String: String], typeAccess: [String: GraphFuzzerGenerator.AccessLevel]) -> [String] {
		var findings = [String]()
		for (fileName, contents) in generatedFiles.sorted(by: { $0.key < $1.key }) where !fileName.hasSuffix("+SafeDISeamCaller.swift") {
			for tier in seamInitializers(inGeneratedFile: contents) {
				let tierAccess = accessLevel(spelled: tier.access)
				for parameter in tier.parameters {
					let type = parameter.drop { $0 != ":" }.dropFirst().prefix { $0 != "=" }
					for name in typeNames(in: type) {
						guard let typeLevel = typeAccess[name], typeLevel < tierAccess else { continue }
						findings.append("\(fileName): `\(tier.seamTypeName)`'s `\(tier.access)` initializer takes `\(parameter.trimmingCharacters(in: .whitespaces))`, but `\(name)` is `\(typeLevel.spelling)`.")
					}
				}
			}
		}
		return findings
	}

	/// The names `type` spells: each run of identifier characters and dots, so a nested type is one name.
	private static func typeNames(in type: some StringProtocol) -> [String] {
		var names = [String]()
		var name = ""
		for character in type + " " {
			if character.isLetter || character.isNumber || character == "_" || character == "." {
				name.append(character)
			} else if !name.isEmpty {
				names.append(name)
				name = ""
			}
		}
		return names
	}

	/// The arguments of each call of `typeName`'s initializer in `contents` – `typeName(` not part of a longer name, and
	/// after the type that encloses it when it is a nested type's name – each as its label and the text it passes, in
	/// the order the code calls them.
	static func initializerCalls(of typeName: String, in contents: String) -> [[(label: String, value: String)]] {
		var calls = [[(label: String, value: String)]]()
		var searchStart = contents.startIndex
		while let range = contents.range(of: typeName + "(", range: searchStart..<contents.endIndex) {
			searchStart = range.upperBound
			if range.lowerBound > contents.startIndex {
				let previous = contents[contents.index(before: range.lowerBound)]
				guard !(previous.isLetter || previous.isNumber || previous == "_") else { continue }
			}
			var depth = 1
			var end = range.upperBound
			while depth > 0, end < contents.endIndex {
				switch contents[end] {
				case "(", "[":
					depth += 1
				case ")", "]":
					depth -= 1
				default:
					break
				}
				end = contents.index(after: end)
			}
			let arguments = topLevelParameters(String(contents[range.upperBound..<contents.index(before: end)])).compactMap { argument -> (label: String, value: String)? in
				guard let colon = argument.firstIndex(of: ":") else { return nil }
				return (argument[..<colon].trimmingCharacters(in: .whitespaces), argument[argument.index(after: colon)...].trimmingCharacters(in: .whitespaces))
			}
			calls.append(arguments)
		}
		return calls
	}

	/// What each of a seam's own errors says after the location: the label collision, the tier that cannot take a
	/// parameter, the redeclared initializer, the declaration the callers cannot see, the read of an uncreated
	/// `onlyIfAvailable` alias, and the signatures that do not settle all open with the first; a missing module info with the second; and a `@Sendable` builder inside the
	/// seam capturing a wrapper parameter – declared outside every builder function of the generated initializer,
	/// whatever the caller would pass – contains the third. An inlined tree's capture names the declaring type
	/// instead; a mock root's capture of a wrapper it is handed prints the same words, and cannot make a differential
	/// failure, since a mock is built the same with and without the seam, so inline rejects it too. A receive hidden
	/// inside a seam's tree is reported hidden in a chain that starts at the seam, on every path and whatever a caller
	/// holds, where inline reports it only in a chain from a root that provides the property (`isSeamOnlyRejection`
	/// adds that marker per seam type).
	private static let seamOnlyErrorMarkers = [
		"error: SafeDI cannot generate the dependency tree of `",
		"error: SafeDI cannot generate a call to the initializer SafeDI generated for `",
		"` receives from outside it, because `",
		// A fill's own errors: what the struct does not carry, or what a re-entering call or a passing-up seam hides.
		"the builder for `",
		"but that call passes the builder `",
	]

	/// Runs the tool twice over `fixture`, and once over it renamed by each of `renamings`.
	static func toolRuns(of fixture: GraphFuzzerFixture, renamings: [GraphFuzzerRenaming] = GraphFuzzerRenaming.all) async throws -> GraphFuzzerToolRuns {
		var renamedOutcomes = [(renaming: GraphFuzzerRenaming, outcome: GraphFuzzerToolOutcome)]()
		for renaming in renamings {
			let renamedFixture = fixture.renamed(by: renaming)
			let outcome = try await toolOutcome(of: renamedFixture, fileNames: renaming.fileNames(of: renamedFixture))
			renamedOutcomes.append((renaming, renaming.restore(outcome, typeNamePrefix: fixture.typeNamePrefix)))
		}
		let firstOutcome = try await toolOutcome(of: fixture)
		// A graph with a seam is run again with no seam: a rejection inline does not make is either a seam's own error
		// or a defect (`differentialFailure`), and an accepted graph must pass no receiver `nil` that inline passes a
		// value (`nilArgumentFailure`).
		let inlineOutcome: GraphFuzzerToolOutcome? = fixture.declaresSeam ? try await toolOutcome(of: fixture.withoutSeams) : nil
		// A graph with a hole is run again with the fulfilling type in the seam's module, whose values a fill must equal.
		let visibleOutcome: GraphFuzzerToolOutcome? = fixture.drawsHole ? try await toolOutcome(of: fixture.withoutHoles) : nil
		// A graph with a public mock is run again as its known-right path, every declaration `public` and every `.public`
		// mock `true`: the two must accept the same graphs but for a public mock's own errors
		// (`publicMockAcceptanceFailure`), and build the same values (`valueFailures`).
		let knownRightOutcome: GraphFuzzerToolOutcome? = GraphFuzzerGeneratorFeature.features(drawnIn: fixture).contains(.generateMockPublic)
			? try await toolOutcome(of: GraphFuzzerGenerator.knownRightPublicMockFixture(forSeed: fixture.seed))
			: nil
		return try await GraphFuzzerToolRuns(
			fixture: fixture,
			firstOutcome: firstOutcome,
			secondOutcome: toolOutcome(of: fixture),
			renamedOutcomes: renamedOutcomes,
			inlineOutcome: inlineOutcome,
			visibleOutcome: visibleOutcome,
			knownRightOutcome: knownRightOutcome,
		)
	}

	/// Runs SafeDITool once over `fixture`, as `executeSafeDIToolTest` runs it for every other generator test.
	/// - Parameter fileNames: The names to give the fixture's files, in its order, or `nil` to name each after the
	///   type it declares, as `executeSafeDIToolTest` does.
	static func toolOutcome(of fixture: GraphFuzzerFixture, fileNames: [String]? = nil) async throws -> GraphFuzzerToolOutcome {
		if let modules = fixture.modules {
			return try await splitToolOutcome(of: fixture, modules: modules, fileNames: fileNames ?? fixture.fileNames)
		}
		var filesToDelete = [URL]()
		defer {
			for fileToDelete in filesToDelete {
				try? FileManager.default.removeItem(at: fileToDelete)
			}
		}
		do {
			let output = try await executeSafeDIToolTest(
				swiftFileContent: fileNames == nil ? fixture.swiftFileContent : [],
				swiftFileContentByFilePath: fileNames.map { Dictionary(uniqueKeysWithValues: zip($0, fixture.swiftFileContent)) } ?? [:],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				skipCompileVerification: true,
			)
			let normalize = normalizer(fixtureDirectory: fixtureDirectory(of: fileNames ?? fixture.fileNames, in: output.fixtures))
			return .accepted(
				generatedFiles: addingSeamCallers(to: (output.generatedFiles ?? [:]).mapValues(normalize), seamTypeAccess: fixture.seamTypeAccess),
				warnings: output.warnings.map { normalize("\($0)") },
			)
		} catch let error as SafeDIToolTestError {
			let directory = fixtureDirectory(of: fileNames ?? fixture.fileNames, in: error.fixtures)
			// `executeSafeDIToolTest` schedules the fixture directory for deletion only when `generate` succeeds.
			filesToDelete.append(URL(fileURLWithPath: directory))
			return .rejected(diagnostics: normalizer(fixtureDirectory: directory)("\(error.underlyingError)"))
		} catch {
			// `executeSafeDIToolTest` wraps every error `generate` throws, so this is the harness failing, such as a
			// fixture it could not write: not the tool rejecting the graph.
			throw GraphFuzzerInfrastructureError(description: "The test harness failed for seed \(fixture.seed) before or after SafeDITool ran: \(error)")
		}
	}

	/// Runs SafeDITool over `fixture`, a graph split across modules, as Bazel runs it: one `generate` per module, in
	/// dependency order, each reading the `.safedi` files of the modules it depends on and naming its module and package
	/// (`executeSafeDIToolMultiModuleTest`'s `.moduleInfo`). Each generated file is keyed by its module's name and its
	/// own (`FuzzFeature/FuzzFeature.swift`), and the outcome is the first module's error, if any.
	private static func splitToolOutcome(of fixture: GraphFuzzerFixture, modules: [GraphFuzzerModule], fileNames: [String]) async throws -> GraphFuzzerToolOutcome {
		var filesToDelete = [URL]()
		defer {
			for fileToDelete in filesToDelete {
				try? FileManager.default.removeItem(at: fileToDelete)
			}
		}
		let presentModules = Set(modules)
		let moduleFixtures = GraphFuzzerModule.allCases.filter(presentModules.contains).map { module in
			ModuleFixture(
				name: module.name,
				packageName: module.packageName,
				swiftFileContentByFilePath: Dictionary(uniqueKeysWithValues: modules.indices.filter { modules[$0] == module }.map { (fileNames[$0], fixture.swiftFileContent[$0]) }),
				dependencies: module.dependencies.filter(presentModules.contains).map(\.name),
				omitsPackageName: fixture.modulesOmittingPackageName.contains(module),
			)
		}
		do {
			let output = try await executeSafeDIToolMultiModuleTest(modules: moduleFixtures, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
			let normalize = normalizer(fixtureDirectory: output.fixtureRoot.path)
			var generatedFiles = [String: String]()
			var warnings = [String]()
			for moduleName in output.moduleNames {
				guard let moduleOutput = output.modules[moduleName] else { continue }
				for (_, contents) in moduleOutput.generatedFiles {
					for (fileName, fileContents) in decomposingCombinedOutput(normalize(contents)) {
						generatedFiles["\(moduleName)/\(fileName)"] = fileContents
					}
				}
				warnings += moduleOutput.warnings.map { normalize("\($0)") }
			}
			return .accepted(
				generatedFiles: addingPublicMockCallers(
					to: addingSeamCallers(to: generatedFiles, seamTypeAccess: fixture.seamTypeAccess, modules: presentModules),
					of: fixture,
				),
				warnings: warnings,
			)
		} catch let error as SafeDIToolMultiModuleTestError {
			// The harness registers the fixture root for deletion before it writes anything.
			let normalize = normalizer(fixtureDirectory: filesToDelete.first?.path ?? "")
			return .rejected(diagnostics: normalize("\(error.underlyingError)"))
		} catch {
			throw GraphFuzzerInfrastructureError(description: "The test harness failed for seed \(fixture.seed) before or after SafeDITool ran: \(error)")
		}
	}

	/// `contents`, a module's combined output, as the files `executeSafeDIToolTest` writes for one module, each with the
	/// combined output's header and imports: each type's extensions, `<Type>+SafeDI.swift`; each type's mock, the
	/// conditional block declaring `mock()`, `<Type>+SafeDIMock.swift`; and the mock configurations, the conditional block
	/// declaring none, `SafeDIMockConfiguration.swift`, which a public mock's module-level configurations open with their
	/// documentation. A combined output declares its files' extensions in the files' path order, which a file-name
	/// reversal reverses; one file per type compares, compiles, and is probed as the per-file outputs of a graph in one
	/// module are.
	static func decomposingCombinedOutput(_ contents: String) -> [String: String] {
		let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
		/// Whether a block begins at `index`: an extension, or a conditional block whose first declaration is one or a
		/// public mock's module-level configuration.
		func beginsBlock(at index: Int) -> Bool {
			lines[index].hasPrefix("extension ")
				|| beginsPublicConfigurationDeclaration(at: index)
				|| lines[index].hasPrefix("#if ") && lines[(index + 1)...].first { !$0.isEmpty }.map { firstLine in
					firstLine.hasPrefix("extension ") || firstLine.hasPrefix("/// Configuration for how ")
				} == true
		}
		/// Whether an unconditional public mock's module-level configuration, or a forwarder of a default, begins at `index`.
		func beginsPublicConfigurationDeclaration(at index: Int) -> Bool {
			lines[index].hasPrefix("/// Configuration for how ") || lines[index].hasPrefix("@usableFromInline ")
		}
		guard let firstBlock = lines.indices.first(where: beginsBlock(at:)) else { return ["Combined.swift": contents] }
		let header = lines[..<firstBlock].joined(separator: "\n")
		var blocksByFileName = [String: [String]]()
		var index = firstBlock
		while index < lines.count {
			guard beginsBlock(at: index) else {
				index += 1
				continue
			}
			let isConditional = lines[index].hasPrefix("#if ")
			let isForwarder = lines[index].hasPrefix("@usableFromInline ")
			let end = isForwarder ? index : lines[(index + 1)...].firstIndex { isConditional ? $0.hasPrefix("#endif") : $0.hasPrefix("}") } ?? (lines.count - 1)
			let block = lines[index...end]
			let extendedType = block.first { $0.hasPrefix("extension ") }.map { String($0.dropFirst("extension ".count).prefix { $0 != " " && $0 != ":" }) } ?? "Combined"
			let fileName = if beginsPublicConfigurationDeclaration(at: index) {
				"SafeDIMockConfiguration.swift"
			} else if !isConditional {
				"\(extendedType)+SafeDI.swift"
			} else if block.contains(where: { $0.contains("static func mock(") }) {
				"\(extendedType)+SafeDIMock.swift"
			} else {
				"SafeDIMockConfiguration.swift"
			}
			blocksByFileName[fileName, default: []].append(block.joined(separator: "\n"))
			index = end + 1
		}
		return blocksByFileName.mapValues { header + "\n" + $0.joined(separator: "\n\n") + "\n" }
	}

	/// The failure of a graph whose `SafeDITool generate` output differs between two processes, which seed their
	/// hashing differently, or `nil` when both processes give the same output.
	///
	/// `toolRuns(of:)` runs the tool twice in this process, which shares one hash seed, so it cannot see output
	/// that depends on the iteration order of a `Set` or `Dictionary` of hashed values. This runs the
	/// `SafeDITool` executable twice over the same fixture files and compares its exit status, diagnostics, and
	/// combined output.
	static func crossProcessFailure(of fixture: GraphFuzzerFixture) throws -> GraphFuzzerFailure? {
		guard let artifacts = SafeDIBuildArtifactLocator.locate() else {
			throw GraphFuzzerInfrastructureError(description: "Could not locate SafeDI build artifacts to find the SafeDITool executable.")
		}
		let toolURL = artifacts.safeDIMacrosToolPath.deletingLastPathComponent().appendingPathComponent("SafeDITool")
		guard FileManager.default.isExecutableFile(atPath: toolURL.path) else {
			throw GraphFuzzerInfrastructureError(description: "No SafeDITool executable at \(toolURL.path). Build the package with `swift build --build-tests`.")
		}
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent("safedi-graph-fuzzer-processes-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let fixtureFiles = try zip(fixture.fileNames, fixture.swiftFileContent).map { fileName, content in
			let fileURL = directory.appendingPathComponent(fileName.replacingOccurrences(of: "/", with: "_"))
			try content.write(to: fileURL, atomically: true, encoding: .utf8)
			return fileURL
		}
		let inputsFile = directory.appendingPathComponent("inputs.csv")
		try fixtureFiles.map(\.path).joined(separator: ",").write(to: inputsFile, atomically: true, encoding: .utf8)
		let outputs = try (0..<2).map { run in
			let outputFile = directory.appendingPathComponent("Generated\(run).swift")
			let result = try runProcess(toolURL, arguments: ["generate", inputsFile.path, "--combined-output", outputFile.path])
			let output = (try? String(contentsOf: outputFile, encoding: .utf8)) ?? ""
			return "exit \(result.exitCode)\n\(result.stderr)\n\(output)"
		}
		guard outputs[0] != outputs[1] else { return nil }
		return GraphFuzzerFailure(seed: fixture.seed, kind: .runsDifferAcrossProcesses, details: "First process:\n\(outputs[0])\nSecond process:\n\(outputs[1])")
	}

	/// `generatedFiles` with, for each seam whose initializer the tool generated – a file that holds the enum generated
	/// beside it – a file holding hand-written calls of that initializer: functions that take a tier's parameters and
	/// pass each on. The oracle compiles them with the rest, so a generated initializer a caller outside SafeDI's
	/// generation cannot call fails there. Each function is spelled at the narrower of its tier's access and the seam
	/// type's (`seamTypeAccess`, read from the fixture), as a caller in the seam's module must spell it. In a graph split
	/// across modules, the callers in the seam's module are joined by a caller in each other module of the graph, which
	/// calls the narrowest tier its package can reach. Derived from the generated files, so the renamed graphs' callers
	/// are restored with their files.
	static func addingSeamCallers(to generatedFiles: [String: String], seamTypeAccess: [String: String] = [:], modules: Set<GraphFuzzerModule> = []) -> [String: String] {
		var generatedFiles = generatedFiles
		for (fileName, contents) in generatedFiles where contents.contains("enum __safeDI_") {
			let initializersBySeam = seamInitializersBySeam(inGeneratedFile: contents)
			// One file per seam, beside the file that generated it, so that a file's contents never depend on the order
			// a module's combined output declares its seams in.
			let directory = fileName.contains("/") ? String(fileName.prefix { $0 != "/" }) + "/" : ""
			for (seamTypeName, initializers) in initializersBySeam {
				generatedFiles["\(directory)\(seamTypeName)+SafeDISeamCaller.swift"] = seamCaller(named: "\(seamTypeName)SeamCaller", of: seamTypeName, calling: Array(initializers.enumerated()), seamTypeAccess: seamTypeAccess[seamTypeName] ?? "public")
			}
			// The callers in the other modules of a split graph, of each seam the seam's module generated.
			guard fileName.hasPrefix(GraphFuzzerModule.seamModule.name + "/") else { continue }
			for (seamTypeName, initializers) in initializersBySeam {
				let seamAccess = seamTypeAccess[seamTypeName] ?? "public"
				for (module, reachableAccesses, callerName) in [
					(GraphFuzzerModule.samePackageCaller, ["public", "package"], "SamePackageCaller"),
					(GraphFuzzerModule.otherPackageCaller, ["public"], "OtherPackageCaller"),
				] where modules.contains(module) && reachableAccesses.contains(seamAccess) {
					guard let tierIndex = initializers.lastIndex(where: { reachableAccesses.contains($0.access) }) else { continue }
					generatedFiles["\(module.name)/\(seamTypeName)+SafeDISeamCaller.swift"] = "import \(GraphFuzzerModule.seamModule.name)\n\n"
						+ seamCaller(named: "\(seamTypeName)\(callerName)", of: seamTypeName, calling: [(tierIndex, initializers[tierIndex])], seamTypeAccess: seamAccess)
				}
			}
		}
		return generatedFiles
	}

	/// What the name of each file `addingPublicMockCallers(to:of:)` adds ends with.
	static let publicMockCallerFileSuffix = "+SafeDIPublicMockCaller.swift"

	/// `generatedFiles` with, for each hand-written call of a public mock the fixture holds in a file that declares a
	/// `.public` mock – `GraphFuzzerPublicMockDraw.publicMockCallerMarker`, then the caller's module and the call – a file
	/// in that module holding a function that makes the call, `<Type>+SafeDIPublicMockCaller.swift`. The oracle compiles
	/// it with the rest, so a public mock a caller outside SafeDI's generation cannot call, with the builders the draw
	/// expects, fails there. The known-right path declares no `.public` mock, so it gets none. Read from the fixture's
	/// text, so a renamed graph's caller is renamed with it and restored with its files.
	static func addingPublicMockCallers(to generatedFiles: [String: String], of fixture: GraphFuzzerFixture) -> [String: String] {
		var generatedFiles = generatedFiles
		for content in fixture.swiftFileContent where content.contains("generateMock: .public") {
			for line in content.split(separator: "\n") where line.hasPrefix(GraphFuzzerPublicMockDraw.publicMockCallerMarker) {
				let moduleAndCall = line.dropFirst(GraphFuzzerPublicMockDraw.publicMockCallerMarker.count)
				guard let colon = moduleAndCall.firstIndex(of: ":"), let callee = moduleAndCall[moduleAndCall.index(after: colon)...].trimmingCharacters(in: .whitespaces).components(separatedBy: ".mock(").first else { continue }
				let moduleName = String(moduleAndCall[..<colon])
				let call = moduleAndCall[moduleAndCall.index(after: colon)...].trimmingCharacters(in: .whitespaces)
				generatedFiles["\(moduleName)/\(callee)\(publicMockCallerFileSuffix)"] = """
				import \(GraphFuzzerModule.seamModule.name)

				#if DEBUG
				public enum \(callee)PublicMockCaller {
				\tpublic static func call() -> \(callee) {
				\t\t\(call)
				\t}
				}
				#endif

				"""
			}
		}
		return generatedFiles
	}

	/// The generated initializers in `contents` – one seam's generated file, or a module's combined output – of each
	/// seam whose guard enum the file declares, in the order the file declares them, widest tier first, with each
	/// tier's access and parameters, each parameter the text of one: every initializer an extension of the seam
	/// declares as its own member, not a member of a type nested in it.
	static func seamInitializers(inGeneratedFile contents: String) -> [(seamTypeName: String, access: String, parameters: [String])] {
		var extendedType: String?
		var guardedTypes = Set<String>()
		var initializers = [(seamTypeName: String, access: String, parameters: [String])]()
		for line in contents.split(separator: "\n") {
			if line.hasPrefix("extension "), line.hasSuffix(" {") {
				extendedType = String(line.dropFirst("extension ".count).dropLast(2))
			} else if line.hasPrefix("}") {
				extendedType = nil
			} else if let extendedType, line.hasPrefix("    "), !line.hasPrefix("     ") {
				let trimmedLine = line.trimmingCharacters(in: .whitespaces)
				if trimmedLine.contains("enum __safeDI_") {
					guardedTypes.insert(extendedType)
				} else if let parametersStart = trimmedLine.range(of: "init("), trimmedLine.hasSuffix(") {") {
					let modifiers = trimmedLine[..<parametersStart.lowerBound].split(separator: " ")
					let access = modifiers.first { ["public", "package", "internal", "fileprivate", "private"].contains($0) }.map(String.init) ?? "internal"
					let parameters = String(trimmedLine[parametersStart.upperBound..<trimmedLine.index(trimmedLine.endIndex, offsetBy: -3)])
					initializers.append((extendedType, access, topLevelParameters(parameters).map { callerSpelling(ofParameter: $0, of: extendedType) }))
				}
			}
		}
		return initializers.filter { guardedTypes.contains($0.seamTypeName) }
	}

	/// `parameter`, a parameter of a generated initializer of `seamTypeName`, as code outside the seam's extension spells
	/// it: a builder for a hole (`userServiceBuilder __safeDI_userServiceBuilder: @escaping (SafeDIScope_Profile_userService)
	/// -> any UserService`) without its internal name, and with its scope struct, which the extension names unqualified,
	/// qualified by the seam. Any other parameter as written.
	static func callerSpelling(ofParameter parameter: String, of seamTypeName: String) -> String {
		let parameter = parameter.trimmingCharacters(in: .whitespaces)
		let label = parameter.prefix { $0 != ":" }
		guard label.contains(" ") else { return parameter }
		let type = parameter.dropFirst(label.count)
		return String(label.prefix { $0 != " " }) + type.replacingOccurrences(of: #"(?<![A-Za-z0-9_.])SafeDIScope_"#, with: "\(seamTypeName).SafeDIScope_", options: .regularExpression)
	}

	/// `seamInitializers(inGeneratedFile:)` without each tier's access.
	static func seamInitializerParameters(inGeneratedFile contents: String) -> [(seamTypeName: String, parameters: [String])] {
		seamInitializers(inGeneratedFile: contents).map { ($0.seamTypeName, $0.parameters) }
	}

	/// `seamInitializers(inGeneratedFile:)` grouped by seam, in the order the file first declares each.
	private static func seamInitializersBySeam(inGeneratedFile contents: String) -> [(seamTypeName: String, initializers: [(access: String, parameters: [String])])] {
		var grouped = [(seamTypeName: String, initializers: [(access: String, parameters: [String])])]()
		for initializer in seamInitializers(inGeneratedFile: contents) {
			if let index = grouped.firstIndex(where: { $0.seamTypeName == initializer.seamTypeName }) {
				grouped[index].initializers.append((initializer.access, initializer.parameters))
			} else {
				grouped.append((initializer.seamTypeName, [(initializer.access, initializer.parameters)]))
			}
		}
		return grouped
	}

	/// An enum named `callerName` whose functions call each of `tiers` of the seam `seamTypeName`, indexed by the tier's
	/// position among the seam's tiers: for each tier, one call passing every parameter and one passing only those
	/// without a default, each spelled at the narrower of the tier's access and the seam type's.
	private static func seamCaller(named callerName: String, of seamTypeName: String, calling tiers: [(offset: Int, element: (access: String, parameters: [String]))], seamTypeAccess: String) -> String {
		let accessOrder = ["private", "fileprivate", "internal", "package", "public"]
		var functions = [String]()
		for (index, tier) in tiers {
			let access = [tier.access, seamTypeAccess].min { (accessOrder.firstIndex(of: $0) ?? 2) < (accessOrder.firstIndex(of: $1) ?? 2) } ?? "internal"
			let labels = tier.parameters.map { $0.prefix { $0 != ":" }.trimmingCharacters(in: .whitespaces) }
			let requiredParameters = tier.parameters.filter { !$0.contains("= nil") }
			let requiredLabels = requiredParameters.map { $0.prefix { $0 != ":" }.trimmingCharacters(in: .whitespaces) }
			functions.append("""
			    \(access) static func callTier\(index)(\(tier.parameters.joined(separator: ", "))) -> \(seamTypeName) {
			        \(seamTypeName)(\(labels.map { "\($0): \($0)" }.joined(separator: ", ")))
			    }
			""")
			functions.append("""
			    \(access) static func callTier\(index)Omitting(\(requiredParameters.joined(separator: ", "))) -> \(seamTypeName) {
			        \(seamTypeName)(\(requiredLabels.map { "\($0): \($0)" }.joined(separator: ", ")))
			    }
			""")
		}
		return """
		public enum \(callerName) {
		\(functions.joined(separator: "\n"))
		}

		"""
	}

	/// `parameters`, the text between an initializer's parentheses, split at the commas outside any brackets. The `>`
	/// of a function type's `->` closes no bracket.
	static func topLevelParameters(_ parameters: String) -> [String] {
		var topLevelParameters = [String]()
		var current = ""
		var depth = 0
		for character in parameters {
			switch character {
			case "<", "(", "[":
				depth += 1
				current.append(character)
			case ">" where current.last == "-":
				current.append(character)
			case ">", ")", "]":
				depth -= 1
				current.append(character)
			case "," where depth == 0:
				topLevelParameters.append(current)
				current = ""
			default:
				current.append(character)
			}
		}
		if !current.trimmingCharacters(in: .whitespaces).isEmpty {
			topLevelParameters.append(current)
		}
		return topLevelParameters
	}

	private static func fixtureDirectory(of fileNames: [String], in fixtures: FixturePaths) -> String {
		(fixtures[fileNames[0]] as NSString).deletingLastPathComponent
	}

	/// Replaces the fixture directory, whose last component is a fresh UUID each run, however the path is spelled.
	/// It appears in generated code only in `#sourceLocation` paths and comments, so the code still compiles.
	private static func normalizer(fixtureDirectory: String) -> (String) -> String {
		let uniqueComponent = (fixtureDirectory as NSString).lastPathComponent
		return { $0.replacingOccurrences(of: uniqueComponent, with: "<fixture-directory>") }
	}

	/// Compiles each graph's fixture, with the generated code when the tool accepted it, and returns the failure
	/// of each graph that does not compile, or whose generated code draws a compiler warning, keyed by seed.
	///
	/// Every graph in one module, and the seam's module of every graph split across modules, compile in one `swiftc`
	/// invocation, as `verifyGeneratedCodeCompiles` compiles one test's fixture and output, as the module
	/// `GraphFuzzerModule.seamModule` in its package; distinct type-name prefixes keep the graphs apart. The split
	/// graphs' callers then compile by module, in dependency order, each module of every graph in one invocation
	/// against the modules before it. When an invocation fails, each error is attributed to a graph by the prefix in
	/// its file name. Those graphs fail, and the rest are compiled again without them, because a type error stops the
	/// compiler before the SIL passes that report errors such as a closure that captures a later local; a graph that
	/// fails in one module is left out of the modules after it. A failing graph is then compiled without its
	/// generated code, module by module, to tell a generator defect from a fixture the fuzzer got wrong. A graph that
	/// compiles fails when a compile it passed reports a warning in its generated code – the seam callers among it –
	/// that its fixture does not draw, as `verifyGeneratedCodeCompiles` fails a test (`warningsOnlyGeneratedCodeDraws`).
	static func compilationFailures(of toolRuns: [GraphFuzzerToolRuns]) throws -> [UInt64: GraphFuzzerFailure] {
		guard !toolRuns.isEmpty else { return [:] }
		guard let artifacts = SafeDIBuildArtifactLocator.locate() else {
			throw GraphFuzzerInfrastructureError(
				description: "Could not locate SafeDI build artifacts for compilation verification. Build the package before running the fuzzer.",
			)
		}
		var filesToDelete = [URL]()
		defer {
			for fileToDelete in filesToDelete {
				try? FileManager.default.removeItem(at: fileToDelete)
			}
		}
		let fixtureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("safedi-graph-fuzzer-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
		filesToDelete.append(fixtureDirectory)

		var combinedUnitsByModule = [GraphFuzzerModule: [CompilationUnit]]()
		var inputOnlyUnitsBySeed = [UInt64: [(module: GraphFuzzerModule, unit: CompilationUnit)]]()
		var seedsWithGeneratedCode = Set<UInt64>()
		for runs in toolRuns {
			let fileModules = runs.fixture.modules ?? Array(repeating: .seamModule, count: runs.fixture.swiftFileContent.count)
			for module in GraphFuzzerModule.allCases where fileModules.contains(module) {
				let moduleDirectory = fixtureDirectory.appendingPathComponent(module.name)
				try FileManager.default.createDirectory(at: moduleDirectory, withIntermediateDirectories: true)
				let fixtureFiles = try zip(zip(runs.fixture.fileNames, runs.fixture.swiftFileContent), fileModules).filter { $0.1 == module }.map { file, _ in
					// A file name that names a directory, as a `SafeDIConfiguration.swift` does, is flattened, so that the
					// files of the graphs one invocation compiles keep names of their own.
					let fileURL = moduleDirectory.appendingPathComponent(file.0.replacingOccurrences(of: "/", with: "_"))
					try file.1.write(to: fileURL, atomically: true, encoding: .utf8)
					return fileURL
				}
				// A graph in one module compiles every generated file there; a split graph's are keyed by module. The mock
				// configuration file has the same name in every graph, so name each file after its graph's prefix.
				var generatedFiles = [String: String]()
				for (fileName, contents) in runs.generatedFiles {
					let moduleFileName: String
					if runs.fixture.modules == nil {
						moduleFileName = fileName
					} else if fileName.hasPrefix(module.name + "/") {
						moduleFileName = String(fileName.dropFirst(module.name.count + 1))
					} else {
						continue
					}
					let stagedFileName = moduleFileName.hasPrefix(runs.fixture.typeNamePrefix) ? moduleFileName : runs.fixture.typeNamePrefix + moduleFileName
					generatedFiles[stagedFileName] = contents
				}
				let combined = try stageCompileSources(inputSwiftFiles: fixtureFiles, generatedFiles: generatedFiles, filesToDelete: &filesToDelete)
				combinedUnitsByModule[module, default: []].append(CompilationUnit(
					seed: runs.fixture.seed,
					inputFiles: combined.inputFiles,
					generatedFiles: combined.generatedFiles.sorted { $0.path < $1.path },
				))
				inputOnlyUnitsBySeed[runs.fixture.seed, default: []].append((module, CompilationUnit(seed: runs.fixture.seed, inputFiles: combined.inputFiles, generatedFiles: [])))
				if !generatedFiles.isEmpty {
					seedsWithGeneratedCode.insert(runs.fixture.seed)
				}
			}
		}

		// Each module of every graph, in dependency order, each graph left out of the modules after one it fails in.
		var combinedFailures = [UInt64: UnitDiagnostics]()
		var generatedCodeWarnings = [UInt64: [String]]()
		var moduleOutputDirectories = [GraphFuzzerModule: URL]()
		let laterModulesAreCompiled = combinedUnitsByModule.keys.contains { $0 != .seamModule }
		for module in GraphFuzzerModule.allCases {
			let units = (combinedUnitsByModule[module] ?? []).filter { combinedFailures[$0.seed] == nil }
			guard !units.isEmpty else { continue }
			let outputDirectory = fixtureDirectory.appendingPathComponent("compiled-\(module.name)")
			try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
			let moduleCompilation = try compilation(
				of: units,
				outputDirectory: outputDirectory,
				artifacts: artifacts,
				module: module,
				emitsModule: laterModulesAreCompiled,
				moduleSearchPaths: module.dependencies.compactMap { moduleOutputDirectories[$0] },
			)
			moduleOutputDirectories[module] = outputDirectory
			combinedFailures.merge(moduleCompilation.failures) { first, _ in first }
			generatedCodeWarnings.merge(moduleCompilation.generatedCodeWarnings) { $0 + $1 }
		}
		// Each failing graph's fixture alone, module by module. These units hold no generated code, so they record no
		// warnings.
		var inputOnlyFailures = [UInt64: UnitDiagnostics]()
		for seed in combinedFailures.keys.sorted() where seedsWithGeneratedCode.contains(seed) {
			let seedDirectory = fixtureDirectory.appendingPathComponent("inputs-only-\(seed)")
			var seedModuleDirectories = [GraphFuzzerModule: URL]()
			for (module, unit) in inputOnlyUnitsBySeed[seed] ?? [] {
				let outputDirectory = seedDirectory.appendingPathComponent(module.name)
				try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
				let unitCompilation = try compilation(
					of: [unit],
					outputDirectory: outputDirectory,
					artifacts: artifacts,
					module: module,
					emitsModule: true,
					moduleSearchPaths: module.dependencies.compactMap { seedModuleDirectories[$0] },
				)
				seedModuleDirectories[module] = outputDirectory
				if let failure = unitCompilation.failures[seed] {
					inputOnlyFailures[seed] = failure
					break
				}
			}
		}
		var failures = [UInt64: GraphFuzzerFailure]()
		for (seed, warnings) in generatedCodeWarnings where combinedFailures[seed] == nil {
			failures[seed] = GraphFuzzerFailure(seed: seed, kind: .generatedCodeDrawsWarning, details: warnings.joined(separator: "\n"))
		}
		for (seed, diagnostics) in combinedFailures {
			// A graph the tool rejected is compiled without generated code, so its failure is the fixture's own.
			let fixtureFails = !seedsWithGeneratedCode.contains(seed) || inputOnlyFailures[seed] != nil
			let kind: GraphFuzzerFailure.Kind = if fixtureFails {
				.fixtureDoesNotCompile
			} else if diagnostics.isCompilerCrash {
				.compilerCrashedOnGeneratedCode
			} else {
				.generatedCodeDoesNotCompile
			}
			failures[seed] = GraphFuzzerFailure(seed: seed, kind: kind, details: (inputOnlyFailures[seed] ?? diagnostics).text)
		}
		return failures
	}

	private struct CompilationUnit {
		let seed: UInt64
		let inputFiles: [URL]
		let generatedFiles: [URL]

		var sources: [URL] {
			inputFiles + generatedFiles
		}

		/// Whether `fileName` belongs to this unit: a fixture staged as `input_<index>_<prefix>…`, a generated file
		/// named `<prefix>…`, or a fixture named in a `#sourceLocation` directive.
		func contains(fileName: Substring) -> Bool {
			let typeNamePrefix = GraphFuzzerFixture.typeNamePrefix(forSeed: seed)
			return fileName.hasPrefix(typeNamePrefix) || fileName.contains("_\(typeNamePrefix)")
		}
	}

	/// Why a unit failed to compile: its compiler errors, or a summary of the compiler's crash.
	private struct UnitDiagnostics {
		let text: String
		let isCompilerCrash: Bool

		init(standardError: String) {
			if let crash = GraphFuzzerCompilerCrash(standardError: standardError) {
				text = crash.summary
				isCompilerCrash = true
			} else {
				text = standardError
				isCompilerCrash = false
			}
		}

		init(errorLines: [Substring]) {
			text = errorLines.joined(separator: "\n")
			isCompilerCrash = false
		}
	}

	/// How a set of units compiled: why each unit that fails to compile fails, and the warnings each other unit's
	/// generated code draws, each keyed by seed.
	private struct UnitsCompilation {
		var failures = [UInt64: UnitDiagnostics]()
		var generatedCodeWarnings = [UInt64: [String]]()

		/// Records the warnings `unit`'s generated code draws in `compilerOutput`, the output of a compile that
		/// `unit` passed, which reports every warning in `unit`'s files.
		mutating func recordGeneratedCodeWarnings(of unit: CompilationUnit, inCompilerOutput compilerOutput: String) throws {
			let warnings = try warningsOnlyGeneratedCodeDraws(
				inCompilerOutput: compilerOutput,
				generatedFiles: unit.generatedFiles,
				inputFiles: unit.inputFiles,
			)
			guard !warnings.isEmpty else { return }
			generatedCodeWarnings[unit.seed] = warnings
		}
	}

	/// Compiles `units` together, then again without each unit an error is attributed to, until the rest compile.
	/// A unit's warnings are read from the last compile it is part of, the one that passes, so a warning reported
	/// only by a SIL pass that a type error elsewhere stopped is still read.
	private static func compilation(
		of units: [CompilationUnit],
		outputDirectory: URL,
		artifacts: SafeDIBuildArtifacts,
		module: GraphFuzzerModule,
		emitsModule: Bool,
		moduleSearchPaths: [URL],
	) throws -> UnitsCompilation {
		func compile(_ units: [CompilationUnit]) throws -> SwiftCompileResult {
			try compileSwift(
				sources: units.flatMap(\.sources),
				outputDirectory: outputDirectory,
				artifacts: artifacts,
				moduleName: module.name,
				packageName: module.packageName,
				emitsModule: emitsModule,
				moduleSearchPaths: moduleSearchPaths,
			)
		}
		var remainingUnits = units
		var compilation = UnitsCompilation()
		while !remainingUnits.isEmpty {
			let result = try compile(remainingUnits)
			guard result.exitCode != 0 else {
				for unit in remainingUnits {
					try compilation.recordGeneratedCodeWarnings(of: unit, inCompilerOutput: result.stderr)
				}
				break
			}
			let errorLines = result.stderr.split(separator: "\n").filter { $0.contains(": error: ") }
			let crash = GraphFuzzerCompilerCrash(standardError: result.stderr)
			var attributedSeeds = Set<UInt64>()
			for unit in remainingUnits {
				let unitErrorLines = errorLines.filter { line in
					// The file name: the last path component of the location that begins the line.
					let fileName = line.prefix { $0 != ":" }.split(separator: "/").last ?? ""
					return unit.contains(fileName: fileName)
				}
				if let crash, let fileName = crash.fileName, unit.contains(fileName: Substring(fileName)) {
					attributedSeeds.insert(unit.seed)
					compilation.failures[unit.seed] = UnitDiagnostics(standardError: result.stderr)
				} else if !unitErrorLines.isEmpty {
					attributedSeeds.insert(unit.seed)
					compilation.failures[unit.seed] = UnitDiagnostics(errorLines: unitErrorLines)
				}
			}
			if attributedSeeds.isEmpty, remainingUnits.count == 1 {
				compilation.failures[remainingUnits[0].seed] = UnitDiagnostics(standardError: result.stderr)
				break
			} else if attributedSeeds.isEmpty {
				// Nothing names a graph, so compile each graph on its own to find the failing ones.
				var compilingUnits = [CompilationUnit]()
				for unit in remainingUnits {
					let unitResult = try compile([unit])
					if unitResult.exitCode != 0 {
						compilation.failures[unit.seed] = UnitDiagnostics(standardError: unitResult.stderr)
					} else {
						try compilation.recordGeneratedCodeWarnings(of: unit, inCompilerOutput: unitResult.stderr)
						compilingUnits.append(unit)
					}
				}
				// The modules compiled after this one import the graphs that compile, together.
				if emitsModule, !compilingUnits.isEmpty {
					let result = try compile(compilingUnits)
					if result.exitCode != 0 {
						for unit in compilingUnits {
							compilation.failures[unit.seed] = UnitDiagnostics(standardError: result.stderr)
						}
					}
				}
				break
			} else {
				remainingUnits.removeAll { attributedSeeds.contains($0.seed) }
			}
		}
		return compilation
	}
}

struct GraphFuzzerInfrastructureError: Error, CustomStringConvertible {
	let description: String
}
