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
		let properties: [PropertyDeclaration]
		let declaresHelperTypes: Bool
	}

	/// How an `@Instantiated` property builds its target.
	private enum InstantiationKind {
		case constant
		case erasedConstant
		case instantiator
		case erasedInstantiator

		var isLazy: Bool {
			switch self {
			case .constant, .erasedConstant:
				false
			case .instantiator, .erasedInstantiator:
				true
			}
		}

		var lazyKind: InstantiationKind {
			switch self {
			case .constant, .instantiator:
				.instantiator
			case .erasedConstant, .erasedInstantiator:
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
			prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: seed)
			isSendable = random.percentChance(15)
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
					add(property(for: InstantiationEdge(sourceIndex: nil, targetIndex: random.integer(in: 0...(typeCount - 1)), kind: .instantiator, labelIndex: random.integer(in: 0...(typeCount - 1)))))
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
			return declarations.map(source(of:))
		}

		private var random: GraphFuzzerRandomNumberGenerator
		private let prefix: String
		private let isSendable: Bool
		private let typeCount: Int
		private let lazyPercent: Int
		private var rootCount = 0
		private var forwardedProperties = [PropertyDeclaration?]()
		private var edges = [InstantiationEdge]()
		/// `dominators[index]` holds the types on every path from a root to the type at `index`, or every type
		/// when no root reaches it.
		private var dominators = [Set<Int>]()
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
				forwardedProperties.append(PropertyDeclaration(
					attribute: "@Forwarded",
					label: "t\(borrowedLabelIndex(for: target))",
					type: typeName(target) + (random.percentChance(30) ? "?" : ""),
				))
			}

			rootCount = random.integer(in: 1...3)
			for _ in 0..<random.integer(in: 1...4) {
				let target = random.integer(in: 0...(typeCount - 1))
				appendEdgeUnlessLabelIsTaken(InstantiationEdge(sourceIndex: nil, targetIndex: target, kind: instantiationKind(target: target, isLazy: nil), labelIndex: borrowedLabelIndex(for: target)))
			}
			for index in 0..<typeCount {
				for _ in 0..<random.integer(in: 0...2) {
					let target = random.integer(in: 0...(typeCount - 1))
					// Only an instantiator can build an earlier type, or this type, without a constant cycle.
					let isBackward = target <= index
					guard !isBackward || random.percentChance(40) else { continue }
					appendEdgeUnlessLabelIsTaken(InstantiationEdge(
						sourceIndex: index,
						targetIndex: target,
						kind: instantiationKind(target: target, isLazy: isBackward ? true : nil),
						labelIndex: borrowedLabelIndex(for: target),
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
				return random.percentChance(15) ? .erasedConstant : .constant
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
			let reachableFromRoots = reachable(from: rootTargets, excluding: nil)
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

		/// Makes `property` receivable below `providerIndex`. The macro rejects a received erased instantiator,
		/// which only `@Instantiated(fulfilledByType:)` can declare, so such a property is never received.
		private mutating func provide(_ property: PropertyDeclaration, providerIndex: Int?, builtIndex: Int?) {
			guard !property.type.contains("ErasedInstantiator<") else { return }
			provided.append(ProvidedProperty(label: property.label, type: property.type, providerIndex: providerIndex, builtIndex: builtIndex))
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
			if !candidates.isEmpty, random.percentChance(98) {
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
				let wrapper = isSendable ? "SendableInstantiator" : "Instantiator"
				return PropertyDeclaration(attribute: "@Instantiated", label: "t\(label)Builder", type: "\(wrapper)<\(typeName(target))>")
			case .erasedInstantiator:
				let wrapper = isSendable ? "SendableErasedInstantiator" : "ErasedInstantiator"
				let forwardedPropertiesType = forwardedProperties[target]?.type ?? "()"
				return PropertyDeclaration(attribute: erasedAttribute, label: "anyT\(label)Builder", type: "\(wrapper)<\(forwardedPropertiesType), \(erasedTypeName(target))>")
			}
		}

		private func source(of declaration: TypeDeclaration) -> String {
			let instantiableAttribute = declaration.instantiableArguments.isEmpty
				? "@Instantiable"
				: "@Instantiable(\(declaration.instantiableArguments.joined(separator: ", ")))"
			let protocolName = declaration.name + "Protocol"
			let conformances = if declaration.declaresHelperTypes {
				"Instantiable, \(protocolName)"
			} else {
				isSendable ? "Instantiable, Sendable" : "Instantiable"
			}
			var lines = [instantiableAttribute, "public final class \(declaration.name): \(conformances) {"]
			if declaration.properties.isEmpty {
				lines.append("\tpublic init() {}")
			} else {
				let parameters = declaration.properties.map { "\($0.label): \($0.type)" }.joined(separator: ", ")
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
					"public protocol \(protocolName): AnyObject\(isSendable ? ", Sendable" : "") {}",
					"",
					"public final class \(erasedName)\(isSendable ? ": Sendable" : "") {",
					"\tpublic init(_ value: \(declaration.name)) {",
					"\t\tself.value = value",
					"\t}",
					"",
					"\tpublic let value: \(declaration.name)",
					"}",
				]
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
	case instantiatorProperty
	case sendableInstantiatorProperty
	case erasedInstantiatorProperty
	case forwardedProperty
	case requiredReceive
	case requiredOptionalReceive
	case onlyIfAvailableReceive
	case requiredAlias
	case onlyIfAvailableAlias
	case erasedToConcreteExistential
	case multipleRoots
	case generateMock
	case lazyCycle
	case sameLabelWithDifferentTypes

	static func < (lhs: GraphFuzzerFeature, rhs: GraphFuzzerFeature) -> Bool {
		lhs.rawValue < rhs.rawValue
	}

	static func features(of fixture: GraphFuzzerFixture) -> Set<GraphFuzzerFeature> {
		var features = Set<GraphFuzzerFeature>()
		var rootCount = 0
		var typesByLabel = [String: Set<String>]()
		var instantiationEdges = [GraphFuzzerInstantiationEdge]()
		for content in fixture.swiftFileContent {
			var currentTypeName: String?
			for line in GraphFuzzerSourceLine.lines(of: content) {
				switch line {
				case let .instantiableAttribute(arguments):
					if arguments.contains("isRoot: true") {
						rootCount += 1
					}
					if arguments.contains("generateMock: true") {
						features.insert(.generateMock)
					}
				case let .typeDeclaration(name):
					currentTypeName = name
				case let .property(attribute, label, type):
					// A receive of `x: T?` names the same type as `x: T` does.
					typesByLabel[label, default: []].insert(type.hasSuffix("?") ? String(type.dropLast()) : type)
					features.formUnion(Self.features(ofPropertyWithAttribute: attribute, type: type))
					if attribute.hasPrefix("@Instantiated"), let currentTypeName {
						instantiationEdges.append(GraphFuzzerInstantiationEdge(
							source: currentTypeName,
							target: Self.instantiatedTypeName(attribute: attribute, type: type),
							isLazy: type.contains("<"),
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
		if GraphFuzzerInstantiationEdge.containsLazyCycle(instantiationEdges) {
			features.insert(.lazyCycle)
		}
		return features
	}

	private static func features(ofPropertyWithAttribute attribute: String, type: String) -> Set<GraphFuzzerFeature> {
		var features = Set<GraphFuzzerFeature>()
		if attribute.contains("erasedToConcreteExistential: true") {
			features.insert(.erasedToConcreteExistential)
		}
		if type.hasPrefix("Instantiator<") {
			features.insert(.instantiatorProperty)
		} else if type.hasPrefix("SendableInstantiator<") {
			features.insert(.sendableInstantiatorProperty)
		} else if type.hasPrefix("ErasedInstantiator<") {
			features.insert(.erasedInstantiatorProperty)
		}
		if attribute == "@Instantiated", !type.contains("<") {
			features.insert(.constantProperty)
		} else if attribute == "@Forwarded" {
			features.insert(.forwardedProperty)
		} else if attribute == "@Received" {
			features.insert(type.hasSuffix("?") ? .requiredOptionalReceive : .requiredReceive)
		} else if attribute == "@Received(onlyIfAvailable: true)" {
			features.insert(.onlyIfAvailableReceive)
		} else if attribute.hasPrefix("@Received(fulfilledByDependencyNamed:") {
			features.insert(attribute.contains("onlyIfAvailable: true") ? .onlyIfAvailableAlias : .requiredAlias)
		}
		return features
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

	private static func reaches(from start: String, to destination: String, through edges: [GraphFuzzerInstantiationEdge]) -> Bool {
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
	case typeDeclaration(name: String)
	case property(attribute: String, label: String, type: String)
	case other

	var declaredTypeName: String? {
		switch self {
		case let .typeDeclaration(name):
			name
		case .instantiableAttribute, .property, .other:
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
/// does not compile (a defect in the fuzzer), or two runs of the tool differ.
struct GraphFuzzerFailure: Equatable {
	enum Kind: String, Equatable {
		case generatedCodeDoesNotCompile = "generated code does not compile"
		case fixtureDoesNotCompile = "fixture does not compile on its own"
		case runsDiffer = "two runs of the tool differ"
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
	let fixture: GraphFuzzerFixture
	let outcome: GraphFuzzerToolOutcome
	let failure: GraphFuzzerFailure?

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
struct GraphFuzzerKnownIssue {
	let reason: String
	/// In increasing order. The ordinary suite checks the first; the long run checks every one it reaches.
	let seeds: [UInt64]
}

/// A graph with what two runs of the tool produced for it.
struct GraphFuzzerToolRuns {
	let fixture: GraphFuzzerFixture
	let firstOutcome: GraphFuzzerToolOutcome
	let secondOutcome: GraphFuzzerToolOutcome

	var runsDifferFailure: GraphFuzzerFailure? {
		guard firstOutcome != secondOutcome else { return nil }
		return GraphFuzzerFailure(
			seed: fixture.seed,
			kind: .runsDiffer,
			details: "First run:\n\(firstOutcome.description)\nSecond run:\n\(secondOutcome.description)",
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
		willRunSeed: (UInt64) -> Void = { _ in },
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
			GraphFuzzerResult(
				fixture: runs.fixture,
				outcome: runs.firstOutcome,
				failure: runs.runsDifferFailure ?? compilationFailures[runs.fixture.seed],
			)
		}
	}

	static func toolRuns(of fixture: GraphFuzzerFixture) async throws -> GraphFuzzerToolRuns {
		try await GraphFuzzerToolRuns(
			fixture: fixture,
			firstOutcome: toolOutcome(of: fixture),
			secondOutcome: toolOutcome(of: fixture),
		)
	}

	/// Runs SafeDITool once over `fixture`, as `executeSafeDIToolTest` runs it for every other generator test.
	private static func toolOutcome(of fixture: GraphFuzzerFixture) async throws -> GraphFuzzerToolOutcome {
		var filesToDelete = [URL]()
		defer {
			for fileToDelete in filesToDelete {
				try? FileManager.default.removeItem(at: fileToDelete)
			}
		}
		do {
			let output = try await executeSafeDIToolTest(
				swiftFileContent: fixture.swiftFileContent,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				skipCompileVerification: true,
			)
			let normalize = normalizer(fixtureDirectory: fixtureDirectory(of: fixture, in: output.fixtures))
			return .accepted(
				generatedFiles: (output.generatedFiles ?? [:]).mapValues(normalize),
				warnings: output.warnings.map { normalize("\($0)") },
			)
		} catch let error as SafeDIToolTestError {
			let directory = fixtureDirectory(of: fixture, in: error.fixtures)
			// `executeSafeDIToolTest` schedules the fixture directory for deletion only when `generate` succeeds.
			filesToDelete.append(URL(fileURLWithPath: directory))
			return .rejected(diagnostics: normalizer(fixtureDirectory: directory)("\(error.underlyingError)"))
		}
	}

	private static func fixtureDirectory(of fixture: GraphFuzzerFixture, in fixtures: FixturePaths) -> String {
		(fixtures[fixture.fileNames[0]] as NSString).deletingLastPathComponent
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
			failures[seed] = GraphFuzzerFailure(
				seed: seed,
				kind: fixtureFails ? .fixtureDoesNotCompile : .generatedCodeDoesNotCompile,
				details: inputOnlyFailures[seed] ?? diagnostics,
			)
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
	private static func diagnosticsOfFailingUnits(
		_ units: [CompilationUnit],
		outputDirectory: URL,
		artifacts: SafeDIBuildArtifacts,
	) throws -> [UInt64: String] {
		var remainingUnits = units
		var diagnosticsBySeed = [UInt64: String]()
		while !remainingUnits.isEmpty {
			let result = try compileSwift(
				sources: remainingUnits.flatMap(\.sources),
				outputDirectory: outputDirectory,
				artifacts: artifacts,
			)
			guard result.exitCode != 0 else { break }
			let errorLines = result.stderr.split(separator: "\n").filter { $0.contains(": error: ") }
			var attributedSeeds = Set<UInt64>()
			for unit in remainingUnits {
				let unitErrorLines = errorLines.filter { line in
					// The file name: the last path component of the location that begins the line.
					let fileName = line.prefix { $0 != ":" }.split(separator: "/").last ?? ""
					return unit.contains(fileName: fileName)
				}
				guard !unitErrorLines.isEmpty else { continue }
				attributedSeeds.insert(unit.seed)
				diagnosticsBySeed[unit.seed] = unitErrorLines.joined(separator: "\n")
			}
			if attributedSeeds.isEmpty {
				// No error names a graph, so compile each graph on its own to find the failing ones.
				for unit in remainingUnits {
					let unitResult = try compileSwift(sources: unit.sources, outputDirectory: outputDirectory, artifacts: artifacts)
					if unitResult.exitCode != 0 {
						diagnosticsBySeed[unit.seed] = unitResult.stderr
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
