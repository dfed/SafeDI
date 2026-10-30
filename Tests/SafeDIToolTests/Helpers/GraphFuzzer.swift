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
			GraphFuzzerSourceLine.lines(of: content).lazy.compactMap(\.declaredTypeName).first.map { "\($0).swift" }
		}
	}

	var description: String {
		swiftFileContent.joined(separator: "\n")
	}

	static func typeNamePrefix(forSeed seed: UInt64) -> String {
		"S\(seed)_"
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

/// Generates graphs of `final class` `@Instantiable` types in two passes.
///
/// The first pass decides what instantiates what. Types are ordered: a type mostly instantiates later types,
/// and instantiates an earlier type (or itself) only through an instantiator, which makes lazy cycles; most
/// such cycles are then made lazy throughout, which SafeDI accepts. The second pass adds received properties
/// and aliases, mostly drawn from properties provided above every path to the receiver – by the roots, which
/// share their properties, or by a type that dominates the receiver – and not by a property whose own subtree
/// holds the receiver. So many graphs are accepted, while the rest exercise SafeDI's validation.
enum GraphFuzzerGenerator {
	static func fixture(forSeed seed: UInt64) -> GraphFuzzerFixture {
		var builder = Builder(seed: seed)
		return GraphFuzzerFixture(seed: seed, swiftFileContent: builder.build())
	}

	private struct PropertyDeclaration {
		let attribute: String
		let label: String
		let type: String
	}

	private struct TypeDeclaration {
		let name: String
		let instantiableArguments: [String]
		var properties: [PropertyDeclaration]
		let declaresHelperTypes: Bool
		/// Protocols the type conforms to beyond those every type of its kind does.
		var additionalConformances = [String]()
		/// Declarations written after the type's own.
		var additionalDeclarations = [String]()
		/// Parameters of the initializer after those of `properties`, each with a default value, which the initializer
		/// does not store. A default-valued parameter is not a dependency.
		var defaultValuedParameters = [String]()
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
		init(seed: UInt64) {
			random = GraphFuzzerRandomNumberGenerator(seed: seed)
			generatedNameRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.generatedNameRandomSeedMask)
			unbuildableDependencyRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.unbuildableDependencyRandomSeedMask)
			unbuildableDependencyReceiverRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.unbuildableDependencyReceiverRandomSeedMask)
			unbuildableDependencySiblingReceiverRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.unbuildableDependencySiblingReceiverRandomSeedMask)
			aliasChainRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.aliasChainRandomSeedMask)
			siblingAliasChainRandom = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.siblingAliasChainRandomSeedMask)
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
			return addingReceiversOfDependenciesMocksCannotBuild(
				to: addingSiblingAliasChains(to: addingAliasChains(to: addingDependenciesMocksCannotBuild(to: addingPropertiesLabeledAsGeneratedNames(to: declarations)))),
			)
			.map(source(of:))
			+ [extensionSource].compactMap(\.self)
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
				owner.defaultValuedParameters = ["formatter: \(nonSendableHelperTypeName("Formatter")) = \(nonSendableHelperTypeName("Formatter"))()"]
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
		/// How many types that are not `@Instantiable` `addingDependenciesMocksCannotBuild` instantiates.
		private var unbuildableTypeCount = 0
		/// The mocked type of the `Sendable` builder motif, when `appendMotif` drew it. It gets no dependency a mock
		/// cannot build: it is outside the `@Sendable` builder function, so a receiver of the dependency that
		/// `addingReceiversOfDependenciesMocksCannotBuild` adds beneath it, inside the function, would be handed a
		/// value from outside the `Sendable` wrapper's subtree, which SafeDI leaves to the compiler to reject.
		private var sendableBuilderMotifMockedTypeName: String?
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
		/// It is drawn after every other pass, and `unbuildableDependencyReceiverRandom` draws only for it, so every other
		/// graph is drawn as before.
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
			var parameters = [String]()
			if !candidates.isEmpty, random.percentChance(50) {
				let receivedProperty = random.element(of: candidates)
				parameters.append("\(receivedProperty.label): \(receivedProperty.type)")
			}
			let defaultValuedParameters = ["title: String = \"default\"", "retryCount: Int = 3", "isEnabled: Bool = false"]
			for _ in 0..<random.integer(in: 1...2) {
				let parameter = random.element(of: defaultValuedParameters)
				if !parameters.contains(parameter) {
					parameters.append(parameter)
				}
			}
			// An unlabeled default-valued parameter last, which a generated call leaves to its default.
			if random.percentChance(20) {
				parameters.append("_ note: String = \"\"")
			}
			let instantiableAttribute = random.percentChance(30) ? "@Instantiable(generateMock: true)" : "@Instantiable"
			return [
				instantiableAttribute,
				"extension \(extensionTypeName): Instantiable {",
				"\tpublic static func instantiate(\(parameters.joined(separator: ", "))) -> \(extensionTypeName) {",
				"\t\t\(extensionTypeName)()",
				"\t}",
				"}",
				"",
				"public final class \(extensionTypeName)\(helperTypesAreSendable ? ": Sendable" : "") {",
				"\tpublic init() {}",
				"}",
			].joined(separator: "\n") + "\n"
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
			var lines = [instantiableAttribute, "public final class \(declaration.name): \(conformances) {"]
			let parameters = (declaration.properties.map { "\($0.label): \($0.type)" } + declaration.defaultValuedParameters).joined(separator: ", ")
			if declaration.properties.isEmpty {
				lines.append("\tpublic init(\(parameters)) {}")
			} else {
				lines.append("\tpublic init(\(parameters)) {")
				lines += declaration.properties.map { "\t\tself.\($0.label) = \($0.label)" }
				lines.append("\t}")
				lines.append("")
				lines += declaration.properties.map { "\t\($0.attribute) let \($0.label): \($0.type)" }
			}
			lines.append("}")
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
			return lines.joined(separator: "\n") + "\n"
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
enum GraphFuzzerSourceLine {
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

	static func lines(of content: String) -> [GraphFuzzerSourceLine] {
		var lines = [GraphFuzzerSourceLine]()
		var previousLineWasInstantiableAttribute = false
		for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
			let line = rawLine.trimmingCharacters(in: .whitespaces)
			let parsedLine: GraphFuzzerSourceLine
			if line.hasPrefix("@Instantiable") {
				parsedLine = .instantiableAttribute(arguments: String(line.dropFirst("@Instantiable".count)))
			} else if previousLineWasInstantiableAttribute, line.hasPrefix("public final class ") {
				let name = line.dropFirst("public final class ".count).prefix { $0.isLetter || $0.isNumber || $0 == "_" }
				parsedLine = .typeDeclaration(name: String(name))
			} else if previousLineWasInstantiableAttribute, line.hasPrefix("extension ") {
				let name = line.dropFirst("extension ".count).prefix { $0.isLetter || $0.isNumber || $0 == "_" }
				parsedLine = .typeDeclaration(name: String(name))
			} else if line.hasPrefix("public static func instantiate("), let parametersEnd = line.range(of: ") -> ", options: .backwards) {
				parsedLine = .instantiateMethod(parameters: String(line[line.index(line.startIndex, offsetBy: "public static func instantiate(".count)..<parametersEnd.lowerBound]))
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
	/// fixture files are compared by file name, and the suggestions a diagnostic lists ("Did you mean one of …") in
	/// any order: the order inside a message is presentation and changes nothing a user does.
	static func difference(between outcome: GraphFuzzerToolOutcome, and otherOutcome: GraphFuzzerToolOutcome) -> String? {
		let reduce = GraphFuzzerRenaming.reducingFixturePathsToFileNames(in:)
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
				} else if fileName == "SafeDIMockConfiguration.swift" {
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
	/// which SafeDI sorts by `Property.<` – sorted as text, so two diagnostics that suggest the same properties in
	/// another order compare equal, and any other difference, including a suggestion added, removed or changed,
	/// still tells them apart.
	private static func sortingSuggestions(in diagnostic: String) -> String {
		// Each suggestion is a property's source between backticks, and no fuzzer label or type contains one.
		let expression = try! NSRegularExpression(pattern: "(?<=Did you mean one of )`[^`]*`(?:, `[^`]*`)+(?=\\?)")
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
			if line.hasPrefix("extension ") {
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

/// A graph the oracle does not accept: the tool succeeded and the output does not compile, the fixture itself
/// does not compile (a defect in the fuzzer), two runs of the tool differ, a renamed graph gives other results, or
/// the graph split across modules gives other results under one multi-module integration than under the other.
struct GraphFuzzerFailure: Equatable {
	enum Kind: String, Equatable {
		case generatedCodeDoesNotCompile = "generated code does not compile"
		case fixtureDoesNotCompile = "fixture does not compile on its own"
		case runsDiffer = "two runs of the tool differ"
		case runsDifferAcrossProcesses = "the tool's output differs between two processes"
		case compilerCrashedOnGeneratedCode = "the Swift compiler crashed on generated code"
		case renamedGraphDiffers = "the graph renamed to change an order gives other results"
		case mockTakesWrapperParameterForReceive = "a generated mock takes a LazilyInstantiated parameter for a receive"
		case integrationsDiffer = "the graph split across modules gives other results under the two multi-module integrations"
	}

	let seed: UInt64
	let kind: Kind
	let details: String

	static func reproductionCommand(forSeed seed: UInt64) -> String {
		"SAFEDI_GRAPH_FUZZER_STARTING_SEED=\(seed) SAFEDI_GRAPH_FUZZER_ITERATIONS=1 swift test --traits sourceBuild --filter SafeDIToolGraphFuzzerTests/longRun"
	}

	func issueComment(fixture: GraphFuzzerFixture) -> Comment {
		"""
		Graph fuzzer seed \(seed): \(kind.rawValue).
		Reproduce with: \(Self.reproductionCommand(forSeed: seed))
		\(details)
		Fixture:
		\(fixture.description)
		"""
	}
}

/// The oracle's verdict on one graph.
struct GraphFuzzerResult {
	init(
		fixture: GraphFuzzerFixture,
		outcome: GraphFuzzerToolOutcome,
		failure: GraphFuzzerFailure?,
		renamedGraphFailures: [GraphFuzzerFailure] = [],
		multiModuleRuns: [GraphFuzzerMultiModuleRuns] = [],
	) {
		self.fixture = fixture
		self.outcome = outcome
		self.failure = failure
		self.renamedGraphFailures = renamedGraphFailures
		self.multiModuleRuns = multiModuleRuns
	}

	let fixture: GraphFuzzerFixture
	let outcome: GraphFuzzerToolOutcome
	/// The first way the graph fails the oracle: its runs differ, it does not compile, a generated mock takes a
	/// `LazilyInstantiated` parameter for a receive, the graph split across modules gives other results under one
	/// multi-module integration than under the other, or, failing none of those ways, a renamed graph gives other results.
	let failure: GraphFuzzerFailure?
	/// How each renamed graph that gives other results differs, in the order of `GraphFuzzerRenaming.all`, whether
	/// or not the graph also fails another way.
	let renamedGraphFailures: [GraphFuzzerFailure]
	/// What the two multi-module integrations produced for the graph split across modules, in the order of
	/// `GraphFuzzerOracle.multiModuleRenamings`.
	let multiModuleRuns: [GraphFuzzerMultiModuleRuns]

	/// How each partitioned run that gives other results under the two multi-module integrations differs, whether or
	/// not the graph also fails another way.
	var multiModuleFailures: [GraphFuzzerFailure] {
		multiModuleRuns.compactMap(\.failure)
	}

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
		/// The Swift compiler crashes while compiling a generated mock.
		case compilerCrashInGeneratedMock
		/// A renamed graph gives other results, in the aspect whose description contains this text.
		case renamedGraphDiffers(containing: String)
		/// The fixture itself fails to compile, with an error whose message contains this text: the macro rejects
		/// a shape the generator emits before the macro accepts it.
		case macroRejectsFixture(containing: String)
		/// The graph split across modules gives other results under the two multi-module integrations, in the
		/// aspect whose description contains this text.
		case integrationsDiffer(containing: String)
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
			case .compilerCrashInGeneratedMock:
				failure.kind == .compilerCrashedOnGeneratedCode && failure.details.contains("+SafeDIMock.swift")
			case let .renamedGraphDiffers(text):
				failure.kind == .renamedGraphDiffers && failure.details.prefix { $0 != "\n" }.contains(text)
			case let .macroRejectsFixture(text):
				failure.kind == .fixtureDoesNotCompile && failure.details.contains(text)
			case let .integrationsDiffer(text):
				failure.kind == .integrationsDiffer && failure.details.prefix { $0 != "\n" }.contains(text)
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

	init(failure: GraphFuzzerFailure?, knownIssue: GraphFuzzerKnownIssue?) {
		switch (failure, knownIssue) {
		case (nil, nil):
			self = .passed
		case let (nil, knownIssue?):
			self = .staleKnownIssue(knownIssue)
		case let (failure?, knownIssue?) where knownIssue.matches(failure):
			self = .knownIssue(knownIssue, failure)
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
	///   - multiModuleRuns: What the two multi-module integrations produced for the graph split across modules.
	init(
		fixture: GraphFuzzerFixture,
		firstOutcome: GraphFuzzerToolOutcome,
		secondOutcome: GraphFuzzerToolOutcome,
		renamedOutcomes: [(renaming: GraphFuzzerRenaming, outcome: GraphFuzzerToolOutcome)] = [],
		multiModuleRuns: [GraphFuzzerMultiModuleRuns] = [],
	) {
		self.fixture = fixture
		self.firstOutcome = firstOutcome
		self.secondOutcome = secondOutcome
		self.renamedOutcomes = renamedOutcomes
		self.multiModuleRuns = multiModuleRuns
	}

	let fixture: GraphFuzzerFixture
	let firstOutcome: GraphFuzzerToolOutcome
	let secondOutcome: GraphFuzzerToolOutcome
	let renamedOutcomes: [(renaming: GraphFuzzerRenaming, outcome: GraphFuzzerToolOutcome)]
	let multiModuleRuns: [GraphFuzzerMultiModuleRuns]

	/// The failure of each partitioned run whose two integrations give other results, in the order the runs were made.
	var multiModuleFailures: [GraphFuzzerFailure] {
		multiModuleRuns.compactMap(\.failure)
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
			let mockedTypeName = String(fileName.dropLast(mockFileSuffix.count))
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
	/// Runs each seed's graph through SafeDITool twice, renamed by each renaming, and split across modules through
	/// both multi-module integrations (`GraphFuzzerMultiModuleProperty`), then compiles every graph's fixture, with
	/// the generated code of each graph the tool accepted, in as few `swiftc` invocations as attribution allows.
	/// Compilation is skipped when `compileVerificationIsEnabled` is `false`.
	///
	/// - Parameter willRunSeed: Called before the tool first runs a seed's graph, so that a long run can record
	///   which seed was running if the tool crashes the process.
	static func results(
		forSeeds seeds: [UInt64],
		willRunSeed: @Sendable (UInt64) -> Void = { _ in },
	) async throws -> [GraphFuzzerResult] {
		var toolRuns = [GraphFuzzerToolRuns]()
		for seed in seeds {
			willRunSeed(seed)
			await toolRuns.append(try self.toolRuns(of: GraphFuzzerGenerator.fixture(forSeed: seed)))
		}
		return try results(of: toolRuns)
	}

	/// The oracle's verdict on graphs the tool already ran.
	static func results(of toolRuns: [GraphFuzzerToolRuns]) throws -> [GraphFuzzerResult] {
		let compilationFailures = compileVerificationIsEnabled
			? try compilationFailures(of: toolRuns.filter { $0.runsDifferFailure == nil })
			: [:]
		return toolRuns.map { runs in
			let renamedGraphFailures = runs.renamedGraphFailures
			return GraphFuzzerResult(
				fixture: runs.fixture,
				outcome: runs.firstOutcome,
				failure: runs.runsDifferFailure ?? compilationFailures[runs.fixture.seed] ?? runs.wrapperParameterFailure ?? runs.multiModuleFailures.first ?? renamedGraphFailures.first,
				renamedGraphFailures: renamedGraphFailures,
				multiModuleRuns: runs.multiModuleRuns,
			)
		}
	}

	/// The renamings the graph is split across modules under, besides the graph as generated (`nil`). See
	/// `GraphFuzzerPartition`.
	static let multiModuleRenamings: [GraphFuzzerRenaming?] = [nil]

	/// Runs the tool twice over `fixture`, once over it renamed by each of `renamings`, and, split across modules by
	/// `GraphFuzzerPartition` and renamed by each of `multiModuleRenamings`, once through each multi-module integration.
	static func toolRuns(
		of fixture: GraphFuzzerFixture,
		renamings: [GraphFuzzerRenaming] = GraphFuzzerRenaming.all,
		multiModuleRenamings: [GraphFuzzerRenaming?] = multiModuleRenamings,
	) async throws -> GraphFuzzerToolRuns {
		var renamedOutcomes = [(renaming: GraphFuzzerRenaming, outcome: GraphFuzzerToolOutcome)]()
		for renaming in renamings {
			let renamedFixture = fixture.renamed(by: renaming)
			let outcome = try await toolOutcome(of: renamedFixture, fileNames: renaming.fileNames(of: renamedFixture))
			renamedOutcomes.append((renaming, renaming.restore(outcome, typeNamePrefix: fixture.typeNamePrefix)))
		}
		let partition = GraphFuzzerPartition.partition(of: fixture)
		var multiModuleRuns = [GraphFuzzerMultiModuleRuns]()
		for renaming in multiModuleRenamings {
			multiModuleRuns.append(try await GraphFuzzerMultiModuleProperty.runs(of: fixture, partition: partition, renaming: renaming))
		}
		return try await GraphFuzzerToolRuns(
			fixture: fixture,
			firstOutcome: toolOutcome(of: fixture),
			secondOutcome: toolOutcome(of: fixture),
			renamedOutcomes: renamedOutcomes,
			multiModuleRuns: multiModuleRuns,
		)
	}

	/// Runs SafeDITool once over `fixture`, as `executeSafeDIToolTest` runs it for every other generator test.
	/// - Parameter fileNames: The names to give the fixture's files, in its order, or `nil` to name each after the
	///   type it declares, as `executeSafeDIToolTest` does.
	static func toolOutcome(of fixture: GraphFuzzerFixture, fileNames: [String]? = nil) async throws -> GraphFuzzerToolOutcome {
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
				generatedFiles: (output.generatedFiles ?? [:]).mapValues(normalize),
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
			let fileURL = directory.appendingPathComponent(fileName)
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

	private static func runProcess(_ executable: URL, arguments: [String]) throws -> SwiftCompileResult {
		let process = Process()
		process.executableURL = executable
		process.arguments = arguments
		let standardOutput = FileManager.default.temporaryDirectory.appendingPathComponent("safedi-graph-fuzzer-output-\(UUID().uuidString)")
		let standardError = FileManager.default.temporaryDirectory.appendingPathComponent("safedi-graph-fuzzer-error-\(UUID().uuidString)")
		FileManager.default.createFile(atPath: standardOutput.path, contents: nil)
		FileManager.default.createFile(atPath: standardError.path, contents: nil)
		defer {
			try? FileManager.default.removeItem(at: standardOutput)
			try? FileManager.default.removeItem(at: standardError)
		}
		process.standardOutput = try FileHandle(forWritingTo: standardOutput)
		process.standardError = try FileHandle(forWritingTo: standardError)
		try process.run()
		process.waitUntilExit()
		return SwiftCompileResult(
			exitCode: process.terminationStatus,
			stdout: (try? String(contentsOf: standardOutput, encoding: .utf8)) ?? "",
			stderr: (try? String(contentsOf: standardError, encoding: .utf8)) ?? "",
		)
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
	/// of each graph that does not compile, keyed by seed.
	///
	/// Every graph is compiled in one `swiftc` invocation, as `verifyGeneratedCodeCompiles` compiles one test's
	/// fixture and output; distinct type-name prefixes keep the graphs apart. When that fails, each error is
	/// attributed to a graph by the prefix in its file name. Those graphs fail, and the rest are compiled again
	/// without them, because a type error stops the compiler before the SIL passes that report errors such as a
	/// closure that captures a later local. A failing graph is then compiled without its generated code, to tell
	/// a generator defect from a fixture the fuzzer got wrong.
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

		var combinedUnits = [CompilationUnit]()
		var inputOnlyUnitsBySeed = [UInt64: CompilationUnit]()
		for runs in toolRuns {
			let fixtureFiles = try zip(runs.fixture.fileNames, runs.fixture.swiftFileContent).map { fileName, content in
				let fileURL = fixtureDirectory.appendingPathComponent(fileName)
				try content.write(to: fileURL, atomically: true, encoding: .utf8)
				return fileURL
			}
			// The mock configuration file has the same name in every graph, so name each file after its graph's prefix.
			var generatedFiles = [String: String]()
			for (fileName, contents) in runs.generatedFiles {
				let stagedFileName = fileName.hasPrefix(runs.fixture.typeNamePrefix) ? fileName : runs.fixture.typeNamePrefix + fileName
				generatedFiles[stagedFileName] = contents
			}
			let combined = try stageCompileSources(inputSwiftFiles: fixtureFiles, generatedFiles: generatedFiles, filesToDelete: &filesToDelete)
			combinedUnits.append(CompilationUnit(seed: runs.fixture.seed, sources: combined.inputFiles + combined.generatedFiles.sorted { $0.path < $1.path }))
			if !generatedFiles.isEmpty {
				inputOnlyUnitsBySeed[runs.fixture.seed] = CompilationUnit(seed: runs.fixture.seed, sources: combined.inputFiles)
			}
		}

		let combinedFailures = try diagnosticsOfFailingUnits(combinedUnits, outputDirectory: fixtureDirectory, artifacts: artifacts)
		let inputOnlyFailures = try diagnosticsOfFailingUnits(
			toolRuns.compactMap { combinedFailures[$0.fixture.seed] == nil ? nil : inputOnlyUnitsBySeed[$0.fixture.seed] },
			outputDirectory: fixtureDirectory,
			artifacts: artifacts,
		)
		var failures = [UInt64: GraphFuzzerFailure]()
		for (seed, diagnostics) in combinedFailures {
			// A graph the tool rejected is compiled without generated code, so its failure is the fixture's own.
			let fixtureFails = inputOnlyUnitsBySeed[seed] == nil || inputOnlyFailures[seed] != nil
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
		let sources: [URL]

		/// Whether `fileName` belongs to this unit: a fixture staged as `input_<index>_<prefix>…`, a generated file
		/// named `<prefix>…`, or a fixture named in a `#sourceLocation` directive.
		func contains(fileName: Substring) -> Bool {
			let typeNamePrefix = GraphFuzzerFixture.typeNamePrefix(forSeed: seed)
			return fileName.hasPrefix(typeNamePrefix) || fileName.contains("_\(typeNamePrefix)")
		}
	}

	/// The compiler errors of each unit that fails to compile, keyed by seed.
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

	private static func diagnosticsOfFailingUnits(
		_ units: [CompilationUnit],
		outputDirectory: URL,
		artifacts: SafeDIBuildArtifacts,
	) throws -> [UInt64: UnitDiagnostics] {
		var remainingUnits = units
		var diagnosticsBySeed = [UInt64: UnitDiagnostics]()
		while !remainingUnits.isEmpty {
			let result = try compileSwift(
				sources: remainingUnits.flatMap(\.sources),
				outputDirectory: outputDirectory,
				artifacts: artifacts,
			)
			guard result.exitCode != 0 else { break }
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
					diagnosticsBySeed[unit.seed] = UnitDiagnostics(standardError: result.stderr)
				} else if !unitErrorLines.isEmpty {
					attributedSeeds.insert(unit.seed)
					diagnosticsBySeed[unit.seed] = UnitDiagnostics(errorLines: unitErrorLines)
				}
			}
			if attributedSeeds.isEmpty, remainingUnits.count == 1 {
				diagnosticsBySeed[remainingUnits[0].seed] = UnitDiagnostics(standardError: result.stderr)
				break
			} else if attributedSeeds.isEmpty {
				// Nothing names a graph, so compile each graph on its own to find the failing ones.
				for unit in remainingUnits {
					let unitResult = try compileSwift(sources: unit.sources, outputDirectory: outputDirectory, artifacts: artifacts)
					if unitResult.exitCode != 0 {
						diagnosticsBySeed[unit.seed] = UnitDiagnostics(standardError: unitResult.stderr)
					}
				}
				break
			} else {
				remainingUnits.removeAll { attributedSeeds.contains($0.seed) }
			}
		}
		return diagnosticsBySeed
	}
}

struct GraphFuzzerInfrastructureError: Error, CustomStringConvertible {
	let description: String
}
