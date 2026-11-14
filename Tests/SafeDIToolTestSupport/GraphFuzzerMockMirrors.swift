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

// MARK: - Properties and types as a fixture spells them

/// A property as SafeDI keys one: its label and its type, spelled as the base corpus's fixtures spell types, which
/// spell each type one way and never with `any`, so that two spellings are one type exactly when they are equal.
struct GraphFuzzerMirrorProperty: Hashable, Comparable, CustomStringConvertible {
	let label: String
	let type: String

	var description: String {
		"\(label): \(type)"
	}

	var isOptional: Bool {
		type.hasSuffix("?")
	}

	/// The property without its optional, as `Property.asUnwrappedProperty`.
	var unwrapped: GraphFuzzerMirrorProperty {
		isOptional ? GraphFuzzerMirrorProperty(label: label, type: String(type.dropLast())) : self
	}

	/// The by-value property that receives the instance of a lazily instantiated property, optional or not, as
	/// `Property.asLazilyInstantiatedInstanceProperty`: `nil` for any other property.
	var lazilyInstantiatedInstance: GraphFuzzerMirrorProperty? {
		guard let instanceType = GraphFuzzerMirrorTypes.lazilyInstantiatedInstanceType(of: unwrapped.type), !instanceType.hasSuffix("?") else { return nil }
		return GraphFuzzerMirrorProperty(label: label, type: instanceType)
	}

	/// The by-value property a forwarded or aliased lazily instantiated property offers, as
	/// `Property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding`: none for an optional one.
	var lazilyInstantiatedInstanceOfDeclaredBinding: GraphFuzzerMirrorProperty? {
		isOptional ? nil : lazilyInstantiatedInstance
	}

	/// The property as dependency cycle validation sees it, as `Property.asValidatedForDependencyCycles`: a lazily
	/// instantiated property as the constant it stands for, optional when the property is.
	var validatedForDependencyCycles: GraphFuzzerMirrorProperty {
		guard let instanceType = GraphFuzzerMirrorTypes.lazilyInstantiatedInstanceType(of: unwrapped.type) else { return self }
		return GraphFuzzerMirrorProperty(label: label, type: instanceType + (isOptional ? "?" : ""))
	}

	static func < (lhs: GraphFuzzerMirrorProperty, rhs: GraphFuzzerMirrorProperty) -> Bool {
		lhs.label != rhs.label ? lhs.label < rhs.label : lhs.type < rhs.type
	}

	/// `Property.precedesInMockOrder`: label, then the kind of property in `PropertyType`'s order, then type.
	func precedesInMockOrder(_ other: GraphFuzzerMirrorProperty) -> Bool {
		if label != other.label {
			label < other.label
		} else if GraphFuzzerMirrorTypes.kindOrder(of: type) != GraphFuzzerMirrorTypes.kindOrder(of: other.type) {
			GraphFuzzerMirrorTypes.kindOrder(of: type) < GraphFuzzerMirrorTypes.kindOrder(of: other.type)
		} else {
			self < other
		}
	}
}

/// What the mirror model reads from a type spelled as the base corpus spells it.
enum GraphFuzzerMirrorTypes {
	/// The wrapper's name and its generic arguments, split at the commas between them, or `nil` for a type that is not
	/// generic.
	static func generic(_ type: String) -> (name: String, arguments: [String])? {
		guard let open = type.firstIndex(of: "<"), type.hasSuffix(">") else { return nil }
		let inner = type[type.index(after: open)..<type.index(before: type.endIndex)]
		var arguments = [String]()
		var depth = 0
		var current = ""
		for character in inner {
			switch character {
			case "<", "(":
				depth += 1
				current.append(character)
			case ">" where current.hasSuffix("-"):
				// A function type's arrow closes nothing.
				current.append(character)
			case ">", ")":
				depth -= 1
				current.append(character)
			case "," where depth == 0:
				arguments.append(current.trimmingCharacters(in: .whitespaces))
				current = ""
			default:
				current.append(character)
			}
		}
		arguments.append(current.trimmingCharacters(in: .whitespaces))
		return (String(type[..<open]), arguments)
	}

	/// The label and type of each element of `tuple`, a tuple type whose every element is labeled.
	static func tupleElements(of tuple: String) -> [(label: String, type: String)] {
		// The same split as of generic arguments, inside parentheses rather than angle brackets.
		guard let elements = generic("<\(tuple.dropFirst().dropLast())>")?.arguments else { return [] }
		return elements.compactMap { element in
			guard let colon = element.firstIndex(of: ":") else { return nil }
			return (String(element[..<colon]), element[element.index(after: colon)...].trimmingCharacters(in: .whitespaces))
		}
	}

	/// The type the property builds, as `TypeDescription.asInstantiatedType`: without its optional, and the generic
	/// argument of a SafeDI wrapper, the second of an erased instantiator.
	static func instantiatedType(of type: String) -> String {
		let unwrapped = type.hasSuffix("?") ? String(type.dropLast()) : type
		guard let (name, arguments) = generic(unwrapped) else { return unwrapped }
		switch name {
		case "Instantiator", "SendableInstantiator", "LazilyInstantiated", "SendableLazilyInstantiated":
			return arguments.first.map(instantiatedType(of:)) ?? unwrapped
		case "ErasedInstantiator", "SendableErasedInstantiator":
			return arguments.count == 2 ? arguments[1] : unwrapped
		default:
			return unwrapped
		}
	}

	/// The instance type of a `LazilyInstantiated` or `SendableLazilyInstantiated`, which is not itself optional.
	static func lazilyInstantiatedInstanceType(of type: String) -> String? {
		guard let (name, arguments) = generic(type), name == "LazilyInstantiated" || name == "SendableLazilyInstantiated", arguments.count == 1 else { return nil }
		return arguments[0]
	}

	/// Whether a property of `type` is a constant or lazily instantiated, which a mock cannot build for a type with
	/// forwarded properties.
	static func isConstantOrLazilyInstantiated(_ type: String) -> Bool {
		let order = kindOrder(of: type)
		return order == 0 || order >= 5
	}

	static func isErasedInstantiator(_ type: String) -> Bool {
		let order = kindOrder(of: type)
		return order == 2 || order == 4
	}

	/// The position of the kind of a property of `type` in `Property.PropertyType`'s order.
	static func kindOrder(of type: String) -> Int {
		let unwrapped = type.hasSuffix("?") ? String(type.dropLast()) : type
		switch generic(unwrapped)?.name {
		case "Instantiator":
			return 1
		case "ErasedInstantiator":
			return 2
		case "SendableInstantiator":
			return 3
		case "SendableErasedInstantiator":
			return 4
		case "LazilyInstantiated":
			return 5
		case "SendableLazilyInstantiated":
			return 6
		default:
			return 0
		}
	}
}

// MARK: - The mirror model

/// The mock root a generated `mock()` builds for a mocked type of a base corpus graph, modeled from the fixture's
/// declarations: which dependencies the mock builds beside the mocked type, and in what order, by the rules the Manual
/// and CLAUDE.md state for `createMockRootScopeGenerator` and `inOrderTheMockTreeFirstReceives`. It decides only which
/// siblings exist and their base order; what each receiver is handed is decided by the production generator, which
/// builds the mirror (`GraphFuzzerMockMirror`). A change to what a mock promotes, or to the order it promotes in,
/// changes this model in the same pull request: the oracle cross-checks the model against every generated mock it
/// compares (`mirrorModelDisagreesWithMock`), so a model left behind fails at once.
struct GraphFuzzerMockMirrorModel {
	/// `readsExistentialAndQualifiedSpellings` finds the scope of a type spelled `any P` or `Namespace.T` by `P` or `T`,
	/// as the seam and public mock corpora spell types: the base corpus spells neither, so its model leaves it `false`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	init(fixture: GraphFuzzerFixture, readsExistentialAndQualifiedSpellings: Bool = false) {
		self.readsExistentialAndQualifiedSpellings = readsExistentialAndQualifiedSpellings
		var types = [String: TypeDeclaration]()
		var typeOrder = [String]()
		var pendingArguments: String?
		var currentTypeName: String?
		for content in fixture.swiftFileContent {
			for line in GraphFuzzerSourceLine.lines(of: content) {
				switch line {
				case let .instantiableAttribute(arguments):
					pendingArguments = arguments
					currentTypeName = nil
				case let .typeDeclaration(name):
					let arguments = pendingArguments ?? ""
					pendingArguments = nil
					currentTypeName = name
					var additionalTypes = [String]()
					if let range = arguments.range(of: "fulfillingAdditionalTypes: [") {
						additionalTypes = arguments[range.upperBound...].prefix { $0 != "]" }
							.split(separator: ",")
							.map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".self", with: "") }
					}
					types[name] = TypeDeclaration(
						name: name,
						dependencies: [],
						isRoot: arguments.contains("isRoot: true"),
						generatesMock: arguments.contains("generateMock: true"),
						isExtension: false,
						additionalTypes: additionalTypes,
					)
					typeOrder.append(name)
				case let .instantiateMethod(parameters):
					guard let currentTypeName else { continue }
					types[currentTypeName]?.isExtension = true
					types[currentTypeName]?.instantiateParameters = GraphFuzzerOracle.topLevelParameters(parameters)
					for parameter in GraphFuzzerOracle.topLevelParameters(parameters) where !parameter.contains(" = ") {
						guard let colon = parameter.firstIndex(of: ":") else { continue }
						let names = parameter[..<colon].split(separator: " ")
						let property = GraphFuzzerMirrorProperty(
							label: String(names.last ?? ""),
							type: parameter[parameter.index(after: colon)...].trimmingCharacters(in: .whitespaces),
						)
						types[currentTypeName]?.dependencies.append(Dependency(property: property, attribute: "@Received", source: .received(onlyIfAvailable: false)))
					}
				case let .property(attribute, label, type):
					guard let currentTypeName else { continue }
					types[currentTypeName]?.dependencies.append(Dependency(
						property: GraphFuzzerMirrorProperty(label: label, type: type),
						attribute: attribute,
						source: Self.source(ofAttribute: attribute),
					))
				case .other:
					pendingArguments = nil
				}
			}
			currentTypeName = nil
		}
		self.types = types
		self.typeOrder = typeOrder
		var scopeTypeNameByType = [String: String]()
		for name in typeOrder {
			scopeTypeNameByType[name] = name
		}
		for name in typeOrder {
			for additionalType in types[name]?.additionalTypes ?? [] where scopeTypeNameByType[additionalType] == nil {
				scopeTypeNameByType[additionalType] = name
			}
		}
		self.scopeTypeNameByType = scopeTypeNameByType
		var concreteTypesByErasedType = [String: Set<String>]()
		for name in typeOrder {
			for dependency in types[name]?.dependencies ?? [] {
				guard case let .instantiated(fulfilledByType?, isErased) = dependency.source, isErased else { continue }
				let concreteType = GraphFuzzerMirrorTypes.instantiatedType(of: fulfilledByType)
				concreteTypesByErasedType[dependency.property.type, default: []].insert(concreteType)
				if let instance = dependency.property.lazilyInstantiatedInstance {
					concreteTypesByErasedType[instance.type, default: []].insert(concreteType)
				}
			}
		}
		erasedToConcreteType = concreteTypesByErasedType.compactMapValues { $0.count == 1 ? $0.first : nil }
	}

	/// How a dependency is declared.
	enum Source: Equatable {
		case instantiated(fulfilledByType: String?, isErased: Bool)
		case received(onlyIfAvailable: Bool)
		case aliased(fulfillingProperty: GraphFuzzerMirrorProperty, onlyIfAvailable: Bool)
		case forwarded
	}

	struct Dependency: Equatable {
		let property: GraphFuzzerMirrorProperty
		/// The attribute as the fixture spells it, which the mirror copies.
		let attribute: String
		let source: Source

		/// The properties the dependency puts in scope, as `Dependency.receivableProperties`.
		var receivableProperties: [GraphFuzzerMirrorProperty] {
			switch source {
			case .instantiated:
				[property] + [property.lazilyInstantiatedInstance].compactMap(\.self)
			case .aliased, .forwarded:
				[property] + [property.lazilyInstantiatedInstanceOfDeclaredBinding].compactMap(\.self)
			case .received:
				[property]
			}
		}
	}

	struct TypeDeclaration {
		let name: String
		var dependencies: [Dependency]
		let isRoot: Bool
		let generatesMock: Bool
		var isExtension: Bool
		let additionalTypes: [String]
		/// The parameters of an extension's `instantiate(…)`, each as declared.
		var instantiateParameters = [String]()

		var forwardedReceivableProperties: Set<GraphFuzzerMirrorProperty> {
			Set(dependencies.filter { $0.source == .forwarded }.flatMap(\.receivableProperties))
		}
	}

	/// A property a scope generates: a child it builds, or an alias it binds.
	enum PropertyToGenerate: Equatable {
		case instantiated(GraphFuzzerMirrorProperty, scopeTypeName: String, isErased: Bool)
		case aliased(GraphFuzzerMirrorProperty, fulfillingProperty: GraphFuzzerMirrorProperty, onlyIfAvailable: Bool)

		var property: GraphFuzzerMirrorProperty {
			switch self {
			case let .instantiated(property, _, _), let .aliased(property, _, _):
				property
			}
		}

		/// The by-value property of a lazily instantiated child or alias, as `Scope.PropertyToGenerate.lazilyInstantiatedInstanceProperty`.
		var lazilyInstantiatedInstance: GraphFuzzerMirrorProperty? {
			switch self {
			case let .instantiated(property, _, _):
				property.lazilyInstantiatedInstance
			case let .aliased(property, _, _):
				property.lazilyInstantiatedInstanceOfDeclaredBinding
			}
		}

		var receivableProperties: [GraphFuzzerMirrorProperty] {
			[property] + [lazilyInstantiatedInstance].compactMap(\.self)
		}
	}

	let types: [String: TypeDeclaration]
	/// The `@Instantiable` types in declaration order.
	let typeOrder: [String]
	/// The concrete type whose scope builds each type the module's declarations fulfill.
	let scopeTypeNameByType: [String: String]
	/// The concrete type a mock builds for an erased type, as `erasedToConcreteTypeMap`: the one concrete type the
	/// module's `erasedToConcreteExistential` declarations erase to it, keyed by both forms of a lazily instantiated one.
	let erasedToConcreteType: [String: String]
	let readsExistentialAndQualifiedSpellings: Bool

	/// The concrete type whose scope builds `type`, or `nil` when no declaration fulfills it.
	func scopeTypeName(of type: String) -> String? {
		if let scopeTypeName = scopeTypeNameByType[type] {
			scopeTypeName
		} else if readsExistentialAndQualifiedSpellings {
			scopeTypeNameByType[Self.unqualifiedName(of: type)]
		} else {
			nil
		}
	}

	/// `type` without `any` and, unless it is generic, without the types it is nested in.
	static func unqualifiedName(of type: String) -> String {
		let withoutAny = type.hasPrefix("any ") ? String(type.dropFirst("any ".count)) : type
		guard !withoutAny.contains("<") else { return withoutAny }
		return String(withoutAny.split(separator: ".").last ?? Substring(withoutAny))
	}

	/// The properties the scope of `typeName` generates, in declaration order, as `createMockTypeDescriptionToScopeMapping`
	/// populates them: each instantiated dependency some scope builds, and each alias.
	func propertiesToGenerate(ofTypeNamed typeName: String) -> [PropertyToGenerate] {
		(types[typeName]?.dependencies ?? []).compactMap { dependency in
			switch dependency.source {
			case let .instantiated(fulfilledByType, isErased):
				let declaredType = GraphFuzzerMirrorTypes.instantiatedType(of: dependency.property.type)
				let builtScopeTypeName = fulfilledByType.map { scopeTypeName(of: declaredType) ?? scopeTypeName(of: GraphFuzzerMirrorTypes.instantiatedType(of: $0)) } ?? scopeTypeName(of: declaredType)
				return builtScopeTypeName.map { .instantiated(dependency.property, scopeTypeName: $0, isErased: isErased) }
			case let .aliased(fulfillingProperty, onlyIfAvailable):
				return .aliased(dependency.property, fulfillingProperty: fulfillingProperty, onlyIfAvailable: onlyIfAvailable)
			case .received, .forwarded:
				return nil
			}
		}
	}

	/// The properties a scope declares for the scopes beneath it, as `Scope.propertiesToDeclare`: those it generates
	/// and the instantiated dependencies no scope builds, each with the by-value form of a lazily instantiated one.
	func propertiesToDeclare(ofTypeNamed typeName: String, generating propertiesToGenerate: [PropertyToGenerate]) -> Set<GraphFuzzerMirrorProperty> {
		let generated = propertiesToGenerate.flatMap(\.receivableProperties)
		let notGenerated = (types[typeName]?.dependencies ?? []).filter { dependency in
			guard case .instantiated = dependency.source else { return false }
			return !propertiesToGenerate.contains { $0.property == dependency.property || $0.lazilyInstantiatedInstance == dependency.property }
		}
		return Set(generated + notGenerated.flatMap(\.receivableProperties))
	}

	// MARK: Received properties

	/// What a scope's tree receives from above it, as `collectReceivedProperties` collects it.
	struct ReceivedProperties {
		var received = Set<GraphFuzzerMirrorProperty>()
		/// The received properties every receiver receives only if available.
		var onlyIfAvailable = Set<GraphFuzzerMirrorProperty>()
	}

	/// Memoizes `receivedProperties(ofTypeNamed:)` as `ReceivedPropertiesCache` does: a walk that re-enters a scope
	/// whose walk is unfinished takes nothing from it, and a result that lacks what such a scope receives is reused only
	/// until that scope's walk finishes.
	struct ReceivedPropertiesCache {
		var complete = [String: ReceivedProperties]()
		var unfinishedWalkDepths = [String: Int]()
		var incomplete = [String: (receivedProperties: ReceivedProperties, shallowestUnfinishedWalkDepth: Int)]()

		/// The walk of `typeName` the cache answers, or `nil`: a finished walk, nothing from a walk still unfinished, with
		/// its depth, or a walk that lacks what a scope still being walked receives, until that scope's walk finishes.
		func walk(ofTypeNamed typeName: String) -> (receivedProperties: ReceivedProperties, shallowestUnfinishedWalkDepth: Int?)? {
			if let complete = complete[typeName] {
				(complete, nil)
			} else if let unfinishedWalkDepth = unfinishedWalkDepths[typeName] {
				(ReceivedProperties(), unfinishedWalkDepth)
			} else if let incomplete = incomplete[typeName] {
				(incomplete.receivedProperties, incomplete.shallowestUnfinishedWalkDepth)
			} else {
				nil
			}
		}
	}

	func receivedProperties(ofTypeNamed typeName: String, cache: inout ReceivedPropertiesCache) -> ReceivedProperties {
		walkReceivedProperties(ofTypeNamed: typeName, cache: &cache).receivedProperties
	}

	private func walkReceivedProperties(ofTypeNamed typeName: String, cache: inout ReceivedPropertiesCache) -> (receivedProperties: ReceivedProperties, shallowestUnfinishedWalkDepth: Int?) {
		if let cachedWalk = cache.walk(ofTypeNamed: typeName) {
			cachedWalk
		} else {
			walkReceivedPropertiesUncached(ofTypeNamed: typeName, cache: &cache)
		}
	}

	private func walkReceivedPropertiesUncached(ofTypeNamed typeName: String, cache: inout ReceivedPropertiesCache) -> (receivedProperties: ReceivedProperties, shallowestUnfinishedWalkDepth: Int?) {
		let walkDepth = cache.unfinishedWalkDepths.count
		cache.unfinishedWalkDepths[typeName] = walkDepth
		let propertiesToGenerate = propertiesToGenerate(ofTypeNamed: typeName)
		let propertiesToDeclare = propertiesToDeclare(ofTypeNamed: typeName, generating: propertiesToGenerate)
		let forwardedProperties = types[typeName]?.forwardedReceivableProperties ?? []
		var received = Set<GraphFuzzerMirrorProperty>()
		var onlyIfAvailable = Set<GraphFuzzerMirrorProperty>()
		var required = Set<GraphFuzzerMirrorProperty>()
		var shallowestUnfinishedWalkDepth: Int?
		for case let .instantiated(_, childTypeName, _) in propertiesToGenerate {
			let walkedChild = walkReceivedProperties(ofTypeNamed: childTypeName, cache: &cache)
			shallowestUnfinishedWalkDepth = [shallowestUnfinishedWalkDepth, walkedChild.shallowestUnfinishedWalkDepth].compactMap(\.self).min()
			let childReceived = walkedChild.receivedProperties.received
			let childOnlyIfAvailable = walkedChild.receivedProperties.onlyIfAvailable
			// A forwarded `x: X` fulfills an `x: X?` beneath it, as a declared one does.
			let childReceivedFromAncestors = childReceived
				.subtracting(propertiesToDeclare)
				.subtracting(forwardedProperties)
				.filter { property in
					!property.isOptional || (!propertiesToDeclare.contains(property.unwrapped) && !forwardedProperties.contains(property.unwrapped))
				}
			received.formUnion(childReceivedFromAncestors)
			required.formUnion(childReceivedFromAncestors.subtracting(childOnlyIfAvailable))
			onlyIfAvailable.formUnion(childOnlyIfAvailable.filter { property in
				!propertiesToDeclare.contains(property.unwrapped) && !forwardedProperties.contains(property.unwrapped)
			})
		}
		for dependency in types[typeName]?.dependencies ?? [] {
			switch dependency.source {
			case let .received(isOnlyIfAvailable):
				received.insert(dependency.property)
				if isOnlyIfAvailable {
					onlyIfAvailable.insert(dependency.property)
				} else {
					required.insert(dependency.property)
				}
			case let .aliased(fulfillingProperty, isOnlyIfAvailable):
				guard !propertiesToDeclare.contains(fulfillingProperty), !forwardedProperties.contains(fulfillingProperty) else { continue }
				received.insert(fulfillingProperty)
				if isOnlyIfAvailable {
					onlyIfAvailable.insert(fulfillingProperty)
				} else {
					required.insert(fulfillingProperty)
				}
			case .instantiated, .forwarded:
				continue
			}
		}
		cache.unfinishedWalkDepths[typeName] = nil
		if !cache.incomplete.isEmpty {
			cache.incomplete = cache.incomplete.filter { $0.value.shallowestUnfinishedWalkDepth != walkDepth }
		}
		let receivedProperties = ReceivedProperties(received: received, onlyIfAvailable: onlyIfAvailable.subtracting(required))
		if let shallowestUnfinishedWalkDepth, shallowestUnfinishedWalkDepth < walkDepth {
			cache.incomplete[typeName] = (receivedProperties, shallowestUnfinishedWalkDepth)
			return (receivedProperties, shallowestUnfinishedWalkDepth)
		} else {
			cache.complete[typeName] = receivedProperties
			return (receivedProperties, nil)
		}
	}

	// MARK: The mock root

	/// What a mock builds beside its mocked type, as `createMockRootScopeGenerator` builds it.
	struct MockRoot {
		/// The mock root's children: the mocked type's own, with a property its tree receives lazily rebuilt as that
		/// wrapper, then the promoted dependencies in the order the tree first receives them.
		let children: [PropertyToGenerate]
		/// How many of `children` are the mocked type's own.
		let ownChildCount: Int
		/// The received properties the tree requires.
		let required: Set<GraphFuzzerMirrorProperty>
		/// Every received property of the tree and of the promoted dependencies' trees.
		let received: Set<GraphFuzzerMirrorProperty>
		/// The types of the scopes the mock's tree reaches: the mocked type's, its children's, and the promoted
		/// dependencies' trees.
		let typeNamesInTree: [String]

		var promotedChildren: ArraySlice<PropertyToGenerate> {
			children[ownChildCount...]
		}
	}

	/// The mock root of the mocked type `typeName`.
	func mockRoot(ofTypeNamed typeName: String, cache: inout ReceivedPropertiesCache) -> MockRoot {
		let initial = receivedProperties(ofTypeNamed: typeName, cache: &cache)
		var allReceived = initial.received
		var allOnlyIfAvailable = initial.onlyIfAvailable
		var allRequired = initial.received.subtracting(initial.onlyIfAvailable)
		var visitedScopes = Set<String>()
		var worklist = allRequired.sorted()
		let forwardedProperties = types[typeName]?.forwardedReceivableProperties ?? []
		func isForwarded(_ property: GraphFuzzerMirrorProperty) -> Bool {
			forwardedProperties.contains(property) || forwardedProperties.contains(property.unwrapped)
		}
		// The mocked type's own aliases, which a receive they provide reads: the alias's exact property, or the unwrapped
		// form of an optional receive (`ScopeGenerator.provides`). Nothing is promoted for such a receive.
		var mockedTypeAliasProperties = Set<GraphFuzzerMirrorProperty>()
		for case let .aliased(aliasProperty, _, _) in propertiesToGenerate(ofTypeNamed: typeName) {
			mockedTypeAliasProperties.insert(aliasProperty)
		}
		func isProvidedByMockedTypeAlias(_ property: GraphFuzzerMirrorProperty) -> Bool {
			mockedTypeAliasProperties.contains(property) || (property.isOptional && mockedTypeAliasProperties.contains(property.unwrapped))
		}
		var scopesBuiltForRequiredProperties = [GraphFuzzerMirrorProperty: String]()
		while let property = worklist.popLast() {
			guard !isForwarded(property),
			      !isProvidedByMockedTypeAlias(property),
			      let promotedScope = scopeToPromote(for: property)?.scopeTypeName
			else { continue }
			scopesBuiltForRequiredProperties[property] = promotedScope
			guard visitedScopes.insert(promotedScope).inserted else { continue }
			let scopeReceived = receivedProperties(ofTypeNamed: promotedScope, cache: &cache)
			allReceived.formUnion(scopeReceived.received)
			allOnlyIfAvailable.formUnion(scopeReceived.onlyIfAvailable)
			for newProperty in scopeReceived.received.subtracting(scopeReceived.onlyIfAvailable).sorted() where allRequired.insert(newProperty).inserted {
				worklist.append(newProperty)
			}
		}
		allOnlyIfAvailable.subtract(allRequired)

		// The mocked type's own property that its tree receives lazily is built as that wrapper.
		let lazilyInstantiatedPropertiesReceived = allReceived.map(\.unwrapped).filter { $0.lazilyInstantiatedInstance != nil }
		let ownChildren = propertiesToGenerate(ofTypeNamed: typeName).map { propertyToGenerate -> PropertyToGenerate in
			guard case let .instantiated(property, scopeTypeName, isErased) = propertyToGenerate,
			      let lazilyInstantiatedProperty = lazilyInstantiatedPropertiesReceived
			      	.filter({ $0.lazilyInstantiatedInstance == property })
			      	.min(by: { $0.precedesInMockOrder($1) })
			else { return propertyToGenerate }
			return .instantiated(lazilyInstantiatedProperty, scopeTypeName: scopeTypeName, isErased: isErased)
		}

		// One wrapper for both forms of a lazily instantiated label.
		var lazilyInstantiatedPropertiesToPromote = Set<GraphFuzzerMirrorProperty>()
		var instancesOfLazilyInstantiatedProperties = Set(ownChildren.compactMap(\.lazilyInstantiatedInstance))
		for receivedProperty in allReceived {
			guard let instanceProperty = receivedProperty.lazilyInstantiatedInstance else { continue }
			let lazilyInstantiatedProperty = receivedProperty.unwrapped
			let optionalInstanceProperty = GraphFuzzerMirrorProperty(label: instanceProperty.label, type: instanceProperty.type + "?")
			guard allRequired.contains(lazilyInstantiatedProperty)
				|| (allRequired.contains(instanceProperty) && !isForwarded(instanceProperty))
				|| (allRequired.contains(optionalInstanceProperty) && !isForwarded(optionalInstanceProperty)),
				scopeToPromote(for: lazilyInstantiatedProperty) != nil
			else { continue }
			lazilyInstantiatedPropertiesToPromote.insert(lazilyInstantiatedProperty)
			instancesOfLazilyInstantiatedProperties.insert(instanceProperty)
		}
		// Each other form of a label on its own, but an optional form beside its non-optional form.
		let propertiesToPromote = allReceived.union(lazilyInstantiatedPropertiesToPromote).filter { receivedProperty in
			(lazilyInstantiatedPropertiesToPromote.contains(receivedProperty) || !allOnlyIfAvailable.contains(receivedProperty))
				&& !isForwarded(receivedProperty)
				&& !isProvidedByMockedTypeAlias(receivedProperty)
				&& !instancesOfLazilyInstantiatedProperties.contains(receivedProperty.unwrapped)
		}
		var promotedChildren = [PropertyToGenerate]()
		for receivedProperty in propertiesToPromote.sorted() where receivedProperty.unwrapped == receivedProperty || !propertiesToPromote.contains(receivedProperty.unwrapped) {
			guard let (scopeTypeName, isErased) = scopeToPromote(for: receivedProperty) else { continue }
			promotedChildren.append(.instantiated(receivedProperty, scopeTypeName: scopeTypeName, isErased: isErased))
		}
		let orderedPromotedChildren = inOrderTheMockTreeFirstReceives(promotedChildren, walkingFrom: typeName, scopesBuiltForRequiredProperties: scopesBuiltForRequiredProperties)
		// The mock root can list a property twice – the mocked type's own, rebuilt as the wrapper a promoted dependency
		// receives, and that wrapper promoted – and builds only the first child for each property.
		let ownProperties = Set(ownChildren.map(\.property))
		let children = ownChildren + orderedPromotedChildren.filter { !ownProperties.contains($0.property) }

		var typeNamesInTree = [String]()
		var visitedTypeNames = Set<String>()
		var typeNamesToVisit = [typeName] + children.compactMap { child -> String? in
			guard case let .instantiated(_, scopeTypeName, _) = child else { return nil }
			return scopeTypeName
		}.reversed()
		while let typeNameToVisit = typeNamesToVisit.popLast() {
			guard visitedTypeNames.insert(typeNameToVisit).inserted else { continue }
			typeNamesInTree.append(typeNameToVisit)
			for case let .instantiated(_, childTypeName, _) in propertiesToGenerate(ofTypeNamed: typeNameToVisit).reversed() {
				typeNamesToVisit.append(childTypeName)
			}
		}
		return MockRoot(
			children: children,
			ownChildCount: ownChildren.count,
			required: allRequired,
			received: allReceived,
			typeNamesInTree: typeNamesInTree,
		)
	}

	/// The scope a mock builds a received `property` from when it promotes it, and whether it erases it, or `nil` when
	/// the mock cannot build it, as `scopeToPromote(for:)` and `mockCanBuild` decide.
	func scopeToPromote(for property: GraphFuzzerMirrorProperty) -> (scopeTypeName: String, isErased: Bool)? {
		let dependencyType = GraphFuzzerMirrorTypes.instantiatedType(of: property.type)
		let scope: (scopeTypeName: String, isErased: Bool)? = if let builtScopeTypeName = scopeTypeName(of: dependencyType) {
			(builtScopeTypeName, false)
		} else if let concreteType = erasedToConcreteType[property.type] ?? property.lazilyInstantiatedInstance.flatMap({ erasedToConcreteType[$0.type] }),
		          let builtScopeTypeName = scopeTypeName(of: concreteType)
		{
			(builtScopeTypeName, true)
		} else {
			nil
		}
		guard let scope, let builtType = types[scope.scopeTypeName] else { return nil }
		let builtTypeForwardedProperties = builtType.dependencies.filter { $0.source == .forwarded }
		if GraphFuzzerMirrorTypes.isErasedInstantiator(property.type), !builtTypeForwardedProperties.isEmpty {
			// A mock builds an erased instantiator whose first generic argument is the type of the only forwarded property
			// or names the typealias. The tuples the fuzzer draws have elements that are not one bare name, and a mock takes
			// an erased instantiator of such a tuple as a parameter.
			guard let firstArgument = GraphFuzzerMirrorTypes.generic(property.unwrapped.type)?.arguments.first,
			      builtTypeForwardedProperties.count == 1
			      ? firstArgument == builtTypeForwardedProperties[0].property.type
			      : firstArgument == "\(scope.scopeTypeName).ForwardedProperties"
			else { return nil }
		}
		guard !GraphFuzzerMirrorTypes.isConstantOrLazilyInstantiated(property.type) || builtTypeForwardedProperties.isEmpty else { return nil }
		return scope
	}

	/// The promoted children in the order the mock's tree first receives them, as `inOrderTheMockTreeFirstReceives`
	/// orders them: a walk of the mocked type's dependencies in declaration order, then each child's tree depth first,
	/// each scope once, then the trees of the scopes the mock builds for required receives, in the order the walk met
	/// those receives.
	private func inOrderTheMockTreeFirstReceives(
		_ promotedChildren: [PropertyToGenerate],
		walkingFrom mockedTypeName: String,
		scopesBuiltForRequiredProperties: [GraphFuzzerMirrorProperty: String],
	) -> [PropertyToGenerate] {
		var promotedChildIndexByReceivedProperty = [GraphFuzzerMirrorProperty: Int]()
		for (index, promotedChild) in promotedChildren.enumerated() {
			for receivableProperty in promotedChild.receivableProperties {
				promotedChildIndexByReceivedProperty[receivableProperty.unwrapped] = index
			}
		}
		var orderedIndices = [Int]()
		var orderedIndexSet = Set<Int>()
		var walkedScopes = Set<String>()
		var receivedProperties = [GraphFuzzerMirrorProperty]()
		func walk(_ rootTypeName: String) {
			var scopesToWalk = [rootTypeName]
			while let scope = scopesToWalk.popLast() {
				guard orderedIndices.count < promotedChildren.count else { return }
				guard walkedScopes.insert(scope).inserted else { continue }
				for dependency in types[scope]?.dependencies ?? [] {
					let receivedProperty: GraphFuzzerMirrorProperty? = switch dependency.source {
					case .received:
						dependency.property
					case let .aliased(fulfillingProperty, _):
						fulfillingProperty
					case .instantiated, .forwarded:
						nil
					}
					if let receivedProperty {
						receivedProperties.append(receivedProperty)
						if let index = promotedChildIndexByReceivedProperty[receivedProperty.unwrapped], orderedIndexSet.insert(index).inserted {
							orderedIndices.append(index)
						}
					}
				}
				let firstChildIndex = scopesToWalk.endIndex
				for case let .instantiated(_, childTypeName, _) in propertiesToGenerate(ofTypeNamed: scope) {
					scopesToWalk.append(childTypeName)
				}
				scopesToWalk[firstChildIndex...].reverse()
			}
		}
		walk(mockedTypeName)
		var receivedPropertyIndex = 0
		while orderedIndices.count < promotedChildren.count, receivedPropertyIndex < receivedProperties.count {
			if let builtScope = scopesBuiltForRequiredProperties[receivedProperties[receivedPropertyIndex]] {
				walk(builtScope)
			}
			receivedPropertyIndex += 1
		}
		return orderedIndices.map { promotedChildren[$0] }
	}

	private static func source(ofAttribute attribute: String) -> Source {
		if attribute.hasPrefix("@Instantiated") {
			let fulfilledByType = attribute.range(of: "fulfilledByType: \"").map { range in
				String(attribute[range.upperBound...].prefix { $0 != "\"" })
			}
			return .instantiated(fulfilledByType: fulfilledByType, isErased: attribute.contains("erasedToConcreteExistential: true"))
		} else if attribute.hasPrefix("@Forwarded") {
			return .forwarded
		} else if let labelRange = attribute.range(of: "fulfilledByDependencyNamed: \""), let typeRange = attribute.range(of: "ofType: ") {
			let label = String(attribute[labelRange.upperBound...].prefix { $0 != "\"" })
			var type = String(attribute[typeRange.upperBound...].prefix { $0 != "," && $0 != ")" })
			if type.hasSuffix(".self") {
				type.removeLast(".self".count)
			}
			return .aliased(fulfillingProperty: GraphFuzzerMirrorProperty(label: label, type: type), onlyIfAvailable: attribute.contains("onlyIfAvailable: true"))
		} else {
			return .received(onlyIfAvailable: attribute.contains("onlyIfAvailable: true"))
		}
	}
}

// MARK: - Mirrors

/// Why the value oracle compares no mirror for a type of an accepted base corpus graph whose `mock()` the tool
/// generated, each pinned by count (`SafeDIToolGraphFuzzerTests.corpusValueOracleSkipCounts`).
enum GraphFuzzerMirrorSkip: String, CaseIterable, Comparable {
	/// The mock takes a parameter without a default value that the mirror cannot forward as the mock binds it – one
	/// that is neither a value the mocked type forwards nor a dependency its tree receives by that label and type, such
	/// as an instance of an unbuildable type the mocked type instantiates – or of a type the harness has no sample of
	/// (`GraphFuzzerSampleValues`).
	case requiredParameter
	/// The mock root's scope holds two forms of one label, which the mock names apart (`x_X`, `x_Instantiator__X`),
	/// and one production scope cannot declare.
	case twoFormsOfOneLabel
	/// A type in the mock's tree requires the optional form of a property, by a receive or by a required alias, whose
	/// closest declaration, in the mock root's scope or beneath it, is the non-optional form: a mock hands it the
	/// non-optional value it binds, as the Manual states for a promoted dependency, while production fulfills a required
	/// optional receive only with an optional property or a forwarded one, which a root does not have, so no production
	/// scope builds the tree.
	case requiredOptionalReceiveOfNonOptionalDeclaration
	/// A type in the mock's tree requires an `onlyIfAvailable` alias whose fulfilling property, or that of an alias in
	/// its chain, nothing builds: a mock binds every property its tree receives only if available, to an override, so
	/// it creates the alias, which production does not create, and rejects the receive.
	case requiredReceiveOfUncreatedAlias

	static func < (lhs: GraphFuzzerMirrorSkip, rhs: GraphFuzzerMirrorSkip) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

/// A shape a compared pair shows, read from the mirror model (mirrored pairs) or from the root's production tree (root
/// pairs), each pinned by the number of compared pairs that show it (`SafeDIToolGraphFuzzerTests.corpusValueOracleShapeCounts`):
/// the evidence that the corpus judges the combination by value, not only each of its features.
enum GraphFuzzerValueOracleShape: String, CaseIterable, Comparable {
	/// Root pairs: a type the root's tree builds is received by two or more types beneath its declaration.
	case rootTreePropertyReceivedByTwoOrMoreTypes
	/// Root pairs: a label and type declared by two scopes of the root's tree, one beneath the other, with a receiver of
	/// it beneath both, which must get the nearer one.
	case rootTreeLabelDeclaredAtTwoDepthsAboveReceiver
	/// Mirrored pairs: a dependency the mock builds beside the mocked type that two or more types of its tree receive.
	case promotedDependencyReceivedByTwoOrMoreTypes
	/// Mirrored pairs: an `onlyIfAvailable` alias in the mock's tree whose fulfilling property the mock builds beside the
	/// mocked type.
	case onlyIfAvailableAliasOfPromotedDependency
	/// Mirrored pairs: a required alias in the mock's tree whose fulfilling property the mock builds beside the mocked
	/// type.
	case requiredAliasOfPromotedDependency
	/// Mirrored pairs: a lazily instantiated dependency the mock builds beside the mocked type whose label its tree also
	/// receives in another form: by value, optional, or only if available.
	case promotedWrapperReceivedInAnotherForm
	/// Mirrored pairs: the mocked type's own property, which a dependency the mock builds beside it receives lazily,
	/// built as that wrapper.
	case ownPropertyRebuiltAsWrapper
	/// Mirrored pairs: the mocked type receives by value the instance of a lazily instantiated dependency the mock
	/// builds beside it.
	case instanceOfPromotedWrapperPassedToMockedType
	/// Mirrored pairs: an `onlyIfAvailable` receive in a type of the mock's tree other than the mocked type – its own
	/// children's trees or a promoted dependency's – of a property nothing in the tree declares and no promoted dependency
	/// provides, so the mock binds it to an `onlyIfAvailable` override and the receiver gets `nil`.
	case onlyIfAvailableReceiveInMockedTypesTreeLeftUnbuilt

	static func < (lhs: GraphFuzzerValueOracleShape, rhs: GraphFuzzerValueOracleShape) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

/// A root of the value-oracle fixture whose production tree is a mocked type's mock root: it declares what the
/// generated `mock()` builds beside the mocked type – the mocked type's own children and aliases, then the dependencies
/// the mock builds for its tree, in the order the tree first receives them – and builds the mocked type by hand from
/// them, storing it as `differentialMirrorValue`. The production generator builds the declarations, so each receiver
/// is handed what production hands it, which the comparator then compares with what the mock hands it.
struct GraphFuzzerMockMirror: Equatable {
	struct Declaration: Equatable {
		/// The property an alias declaration refers to, as the mirror writes it, and whether it is `onlyIfAvailable`.
		struct Alias: Equatable {
			let fulfillingProperty: GraphFuzzerMirrorProperty
			let onlyIfAvailable: Bool
		}

		let attribute: String
		let property: GraphFuzzerMirrorProperty
		/// `nil` for a declaration that is not an alias.
		var alias: Alias?
		/// The concrete type whose scope builds the declaration, `nil` for an alias.
		var builtTypeName: String?
	}

	let mockedTypeName: String
	let name: String
	let declarations: [Declaration]
	/// The expression building the mocked type from the declarations.
	let construction: String
	let shapes: Set<GraphFuzzerValueOracleShape>
	/// The arguments of the mock's required parameters, each a sample value, in the mock's order: empty for a mock that
	/// takes none.
	var mockArguments = [String]()
	/// The sample of the mirror's `ForwardedProperties`, the same values the mock is handed, or `nil` for a mirror that
	/// forwards nothing.
	var forwardedPropertiesSample: String?

	/// Whether the mirror forwards the mock's required parameters, so that a root of its own builds it.
	var isForwarding: Bool {
		declarations.contains { $0.attribute == "@Forwarded" }
	}

	/// The probe expression of the feature side of the mirror's pair.
	var featureExpression: String {
		"\(mockedTypeName).mock(\(mockArguments.joined(separator: ", ")))"
	}

	/// The probe expression of the known-right side of the mirror's pair: the mirror's value.
	var knownRightExpression: String {
		"\(knownRightConstruction).\(Self.valueLabel)"
	}

	/// The expression that builds the mirror: the mirror itself, a root, or, when it forwards the mock's required
	/// parameters, a root of its own, with the sample values the mock takes.
	var knownRightConstruction: String {
		if let forwardedPropertiesSample {
			"\(hostName)().\(Self.builderLabel).instantiate(\(forwardedPropertiesSample))"
		} else {
			"\(name)()"
		}
	}

	/// The root that builds a forwarding mirror through an instantiator.
	var hostName: String {
		"\(name)Host"
	}

	/// The label of the stored property that holds the mocked type the mirror builds.
	static let valueLabel = "differentialMirrorValue"

	/// The label of the forwarding mirror's instantiator its root holds.
	static let builderLabel = "mirrorBuilder"

	/// The mirror's file: a root, or, when the mirror forwards the mock's required parameters, the mirror and a root of
	/// its own that holds an instantiator of it.
	/// - Parameters:
	///   - conformance: What the mirror conforms to beyond `Instantiable`, as the graph's roots and types do.
	///   - stamp: The creation stamp's stored property, in a fixture that stamps every class.
	func source(conformance: String, stamp: String?) -> String {
		var lines = [isForwarding ? "@Instantiable" : "@Instantiable(isRoot: true)", "public final class \(name): Instantiable\(conformance) {"]
		if let stamp {
			lines += ["\t\(stamp)", ""]
		}
		lines.append("\tpublic init(\(declarations.map { "\($0.property.label): \(GraphFuzzerSpelling.escapingType(of: $0.property.type))" }.joined(separator: ", "))) {")
		lines += declarations.map { "\t\tself.\($0.property.label) = \($0.property.label)" }
		lines.append("\t\t\(Self.valueLabel) = \(construction)")
		lines.append("\t}")
		lines.append("")
		lines += declarations.map { "\t\($0.attribute) let \($0.property.label): \($0.property.type)" }
		lines.append("\tlet \(Self.valueLabel): \(mockedTypeName)")
		lines.append("}")
		if isForwarding {
			// A `Sendable` root stores only `Sendable` wrappers.
			let builderType = "\(conformance == ", Sendable" ? "SendableInstantiator" : "Instantiator")<\(name)>"
			lines += ["", "@Instantiable(isRoot: true)", "public final class \(hostName): Instantiable\(conformance) {"]
			if let stamp {
				lines += ["\t\(stamp)", ""]
			}
			lines += [
				"\tpublic init(\(Self.builderLabel): \(builderType)) {",
				"\t\tself.\(Self.builderLabel) = \(Self.builderLabel)",
				"\t}",
				"",
				"\t@Instantiated let \(Self.builderLabel): \(builderType)",
				"}",
			]
		}
		return lines.joined(separator: "\n") + "\n"
	}
}

/// What the mirror model says a mocked type's generated `mock()` builds beside the mocked type, which the oracle checks
/// against the mock's `SafeDIOverrides` before it decides whether to compare the mock (R4).
struct GraphFuzzerMockRootExpectation: Equatable {
	let mockedTypeName: String
	/// The types the mock builds beside the mocked type – its own children and the promoted dependencies – each by its
	/// concrete type's name, sorted.
	let builtTypeNames: [String]
	/// How many `onlyIfAvailable` overrides the mock takes: one per dependency its tree receives only if available that
	/// nothing in the tree provides and no forwarded property fulfills, by the form the caller passes.
	let onlyIfAvailableOverrideCount: Int
}

extension GraphFuzzerMockMirrorModel {
	/// What the generated `mock()` of `mockedTypeName`, whose mock root is `mockRoot`, builds beside the mocked type.
	func expectation(of mockRoot: MockRoot, mockedTypeName: String) -> GraphFuzzerMockRootExpectation {
		GraphFuzzerMockRootExpectation(
			mockedTypeName: mockedTypeName,
			builtTypeNames: mockRoot.children.compactMap { child -> String? in
				guard case let .instantiated(_, scopeTypeName, _) = child else { return nil }
				return scopeTypeName
			}.sorted(),
			onlyIfAvailableOverrideCount: onlyIfAvailableOverrideCount(of: mockRoot, mockedTypeName: mockedTypeName),
		)
	}

	/// The mirror of the mocked type `typeName`, named `name`, or why none is compared.
	/// - Parameter cache: Shared by the mocked types of one graph in type order, as the tool shares it across mock roots.
	func mirror(ofMockedTypeNamed typeName: String, named name: String, forwarding requiredParameters: [GraphFuzzerMirrorProperty] = [], cache: inout ReceivedPropertiesCache) -> Result<GraphFuzzerMockMirror, GraphFuzzerMirrorFailure> {
		mirror(of: mockRoot(ofTypeNamed: typeName, cache: &cache), mockedTypeName: typeName, named: name, forwarding: requiredParameters)
	}

	/// The mirror of the mocked type `typeName`, whose mock root is `mockRoot`, named `name`, or why none is compared.
	/// - Parameter requiredParameters: The mock's parameters without a default value, which the mirror forwards: values
	///   the mocked type forwards, and dependencies its tree receives that the mock cannot build.
	func mirror(of mockRoot: MockRoot, mockedTypeName typeName: String, named name: String, forwarding requiredParameters: [GraphFuzzerMirrorProperty] = []) -> Result<GraphFuzzerMockMirror, GraphFuzzerMirrorFailure> {
		guard let mockedType = types[typeName] else {
			return .failure(.modelDisagrees("The model holds no declaration of `\(typeName)`."))
		}
		// A required parameter the mirror forwards as the mock binds it: a value the mocked type forwards, or a dependency
		// its tree receives by that label and type that the mocked type does not instantiate itself. The mock takes others
		// – an instance it cannot build that the mocked type or its tree instantiates, the instance of a lazily instantiated
		// receive, a parameter it names apart from another of its label – which no forwarded declaration stands for.
		for parameter in requiredParameters {
			let isForwardedByMockedType = mockedType.dependencies.contains { $0.source == .forwarded && $0.property == parameter }
			let isReceivedByTree = mockRoot.received.contains(parameter) && !mockedType.dependencies.contains { $0.property.label == parameter.label && $0.attribute.hasPrefix("@Instantiated") }
			guard isForwardedByMockedType || isReceivedByTree else {
				return .failure(.skipped(.requiredParameter))
			}
		}
		var declaredProperties = Set<GraphFuzzerMirrorProperty>()
		for child in mockRoot.children {
			if case .instantiated = child {
				declaredProperties.formUnion(child.receivableProperties.map(\.unwrapped))
				declaredProperties.formUnion(child.receivableProperties)
			}
		}
		func isDeclared(_ property: GraphFuzzerMirrorProperty) -> Bool {
			declaredProperties.contains(property) || (property.isOptional && declaredProperties.contains(property.unwrapped))
		}
		// The mocked type's aliases the mirror declares: those whose fulfilling property it declares, found to a fixed
		// point for an alias of another of the type's aliases.
		var declaredAliases = Set<GraphFuzzerMirrorProperty>()
		var foundAlias = true
		while foundAlias {
			foundAlias = false
			for case let .aliased(property, fulfillingProperty, _) in mockRoot.children where !declaredAliases.contains(property) && isDeclared(fulfillingProperty) {
				declaredAliases.insert(property)
				declaredProperties.insert(property)
				if let instance = property.lazilyInstantiatedInstanceOfDeclaredBinding {
					declaredProperties.insert(instance)
				}
				foundAlias = true
			}
		}
		// What the mirror's declarations put in scope, as production reads them: each child it builds by its non-optional
		// form, with the instance of a lazily instantiated one, and each alias it declares.
		var mirrorDeclaredProperties = Set<GraphFuzzerMirrorProperty>()
		for child in mockRoot.children {
			switch child {
			case let .instantiated(property, _, _):
				mirrorDeclaredProperties.formUnion([property.unwrapped] + [property.unwrapped.lazilyInstantiatedInstance].compactMap(\.self))
			case let .aliased(property, _, _) where declaredAliases.contains(property):
				mirrorDeclaredProperties.formUnion([property] + [property.lazilyInstantiatedInstanceOfDeclaredBinding].compactMap(\.self))
			case .aliased:
				break
			}
		}
		var promotedDeclaredProperties = Set<GraphFuzzerMirrorProperty>()
		for case let .instantiated(property, _, _) in mockRoot.promotedChildren {
			promotedDeclaredProperties.formUnion([property.unwrapped] + [property.unwrapped.lazilyInstantiatedInstance].compactMap(\.self))
		}
		// The mock's required parameters, which the mirror forwards, then what the mock builds beside the mocked type.
		var declarations = requiredParameters.map { GraphFuzzerMockMirror.Declaration(attribute: "@Forwarded", property: $0) }
		for child in mockRoot.children {
			switch child {
			case let .instantiated(property, scopeTypeName, isErased):
				// A promoted optional form is built as its non-optional value.
				declarations.append(GraphFuzzerMockMirror.Declaration(
					attribute: isErased ? "@Instantiated(fulfilledByType: \"\(scopeTypeName)\", erasedToConcreteExistential: true)" : "@Instantiated",
					property: property.unwrapped,
					builtTypeName: scopeTypeName,
				))
			case let .aliased(property, fulfillingProperty, onlyIfAvailable):
				guard declaredAliases.contains(property), let dependency = mockedType.dependencies.first(where: { $0.property == property }) else {
					// A required alias the mirror cannot declare, of a mock that takes no required parameter, is fulfilled
					// through an alias the mock creates from an override it binds, which production does not create.
					guard onlyIfAvailable else {
						return .failure(.skipped(.requiredReceiveOfUncreatedAlias))
					}
					continue
				}
				// An alias of the optional form of a property the mock promotes and builds non-optional refers to that
				// property, as the mock hands it the non-optional value it binds. The mirror, which declares the property
				// itself, names the declaration's type, since production reads a rename of a property its own type
				// declares as a rename of exactly that property. An alias of the optional form of the mocked type's own
				// property is copied as it is: production rejects it wherever a tree builds the type.
				var attribute = dependency.attribute
				var writtenFulfillingProperty = fulfillingProperty
				if fulfillingProperty.isOptional, !mirrorDeclaredProperties.contains(fulfillingProperty), promotedDeclaredProperties.contains(fulfillingProperty.unwrapped) {
					let ofType = "ofType: \(fulfillingProperty.type).self"
					guard attribute.components(separatedBy: ofType).count == 2 else {
						return .failure(.modelDisagrees("The mirror cannot find `\(ofType)` in `\(attribute)` to retype the alias `\(property)`."))
					}
					attribute = attribute.replacingOccurrences(of: ofType, with: "ofType: \(fulfillingProperty.unwrapped.type).self")
					writtenFulfillingProperty = fulfillingProperty.unwrapped
				}
				declarations.append(GraphFuzzerMockMirror.Declaration(
					attribute: attribute,
					property: property,
					alias: GraphFuzzerMockMirror.Declaration.Alias(fulfillingProperty: writtenFulfillingProperty, onlyIfAvailable: onlyIfAvailable),
				))
			}
		}
		guard Set(declarations.map(\.property.label)).count == declarations.count else {
			return .failure(.skipped(.twoFormsOfOneLabel))
		}
		switch productionResolutionSkip(of: mockRoot, mockedTypeName: typeName, declarations: declarations) {
		case let skip?:
			return .failure(.skipped(skip))
		case nil:
			break
		}
		var arguments = [String]()
		for dependency in mockedType.dependencies {
			let argument: String? = switch dependency.source {
			case .instantiated:
				Self.argument(for: dependency.property, isRequired: true, from: declarations)
			case let .aliased(_, onlyIfAvailable):
				Self.argument(for: dependency.property, isRequired: !onlyIfAvailable, from: declarations)
			case let .received(onlyIfAvailable):
				Self.argument(for: dependency.property, isRequired: !onlyIfAvailable, from: declarations)
			case .forwarded:
				Self.argument(for: dependency.property, isRequired: true, from: declarations)
			}
			guard let argument else {
				return .failure(.modelDisagrees("The mirror declares nothing it can pass `\(typeName)` for `\(dependency.property)`, which the mock passes without a required parameter."))
			}
			arguments.append("\(dependency.property.label): \(argument)")
		}
		let construction = mockedType.isExtension
			? "\(typeName).instantiate(\(arguments.joined(separator: ", ")))"
			: "\(typeName)(\(arguments.joined(separator: ", ")))"
		return .success(GraphFuzzerMockMirror(
			mockedTypeName: typeName,
			name: name,
			declarations: declarations,
			construction: construction,
			shapes: shapes(of: mockRoot, mockedTypeName: typeName),
		))
	}

	/// What the mirror passes the mocked type for `property`: the declaration of it, the instance of a lazily
	/// instantiated declaration of its by-value form, the non-optional declaration of an optional property, or `nil` for
	/// a property received only if available that the mirror does not declare. `nil` when there is nothing to pass.
	private static func argument(for property: GraphFuzzerMirrorProperty, isRequired: Bool, from declarations: [GraphFuzzerMockMirror.Declaration]) -> String? {
		let declaredArgument = [property, property.unwrapped].lazy.compactMap { candidate -> String? in
			if let declaration = declarations.first(where: { $0.property == candidate }) {
				declaration.property.label
			} else if let declaration = declarations.first(where: { $0.property.lazilyInstantiatedInstance == candidate }) {
				"\(declaration.property.label).instance"
			} else {
				nil
			}
		}.first
		return declaredArgument ?? (isRequired ? nil : "nil")
	}

	/// A property a scope of the mirror's production tree declares, and whether production creates it: an
	/// `onlyIfAvailable` alias whose fulfilling property nothing above it declares is not created.
	private struct ProductionDeclaration: Hashable {
		let property: GraphFuzzerMirrorProperty
		let isCreated: Bool
	}

	/// Why the production generator would build the mirror's tree otherwise than the mock builds the mock root's, as the
	/// Manual and CLAUDE.md state for a mock, or `nil`: each alias the mirror declares, found among the mirror's own
	/// declarations, and each receive and alias in the trees the mock root builds, found by its label in the closest scope
	/// above it that declares the label, as production resolves it, where an `onlyIfAvailable` alias is created only when
	/// its fulfilling property is declared above it. A mock binds every property its tree receives only if available, so
	/// it creates every such alias. A receive whose closest declaration of its label has another type is no reason to
	/// skip: production passes `nil` for one received only if available, as the mock's override of its own type does,
	/// and rejects a required one, as the mock does.
	private func productionResolutionSkip(of mockRoot: MockRoot, mockedTypeName: String, declarations: [GraphFuzzerMockMirror.Declaration]) -> GraphFuzzerMirrorSkip? {
		var rootDeclarations = [String: Set<ProductionDeclaration>]()
		for declaration in declarations {
			for property in [declaration.property] + [declaration.attribute.hasPrefix("@Instantiated") ? declaration.property.lazilyInstantiatedInstance : declaration.property.lazilyInstantiatedInstanceOfDeclaredBinding].compactMap(\.self) {
				rootDeclarations[property.label, default: []].insert(ProductionDeclaration(property: property, isCreated: true))
			}
		}
		// The mocked type's aliases the mirror does not declare, which production does not create.
		for case let .aliased(property, _, _) in mockRoot.children[..<mockRoot.ownChildCount] where !declarations.contains(where: { $0.property == property }) {
			rootDeclarations[property.label, default: []].insert(ProductionDeclaration(property: property, isCreated: false))
		}
		/// The closest declaration on `path` of the label of `property`, nearest last, and whether it provides `property`:
		/// exactly, or, for an optional property, by its non-optional form.
		func resolution(of property: GraphFuzzerMirrorProperty, in declarationsOnPath: [[String: Set<ProductionDeclaration>]]) -> (declaration: ProductionDeclaration?, isExact: Bool)? {
			guard let nearest = declarationsOnPath.last(where: { $0[property.label] != nil })?[property.label] else { return nil }
			if let exact = nearest.first(where: { $0.property == property }) {
				return (exact, true)
			} else if property.isOptional, let unwrapped = nearest.first(where: { $0.property == property.unwrapped }) {
				return (unwrapped, false)
			} else {
				return (nil, false)
			}
		}
		/// Why a receive of `receivedProperty`, required or only if available, resolves otherwise in production than in the
		/// mock, or `nil`.
		func skipReason(receiving receivedProperty: GraphFuzzerMirrorProperty, isRequired: Bool, in declarationsOnPath: [[String: Set<ProductionDeclaration>]]) -> GraphFuzzerMirrorSkip? {
			guard isRequired else { return nil }
			guard let (declaration, isExact) = resolution(of: receivedProperty, in: declarationsOnPath) else {
				// Nothing above declares it: a required receive the mock fulfills without a parameter is one of a property
				// the mock binds to an override, through an alias production does not create.
				return .requiredReceiveOfUncreatedAlias
			}
			guard let declaration else {
				// A declaration of the label with another type: production rejects the receive as hidden, as the mock does.
				return nil
			}
			if !declaration.isCreated {
				return .requiredReceiveOfUncreatedAlias
			} else if !isExact {
				// A required receive or alias of the optional form, which production does not fulfill with the
				// non-optional declaration.
				return .requiredOptionalReceiveOfNonOptionalDeclaration
			} else {
				return nil
			}
		}
		// The mirror's own aliases, the mocked type's, refer to the mirror's declarations, as a root's aliases must.
		for declaration in declarations {
			guard let alias = declaration.alias, let aliasSkip = skipReason(receiving: alias.fulfillingProperty, isRequired: !alias.onlyIfAvailable, in: [rootDeclarations]) else { continue }
			return aliasSkip
		}
		var skip: GraphFuzzerMirrorSkip?
		// The walk visits each path of the trees, so it stops after 10,000 visits rather than grow with the paths of a
		// dense graph. A corpus graph holds at most about a dozen sparsely connected types, far fewer paths than that. A
		// truncated walk would miss a reason to skip, and so show as the tool's rejection of the value-oracle fixture
		// naming the mirror, never as a silent pass.
		var visits = 0
		/// The declarations of each scope on the path, nearest last.
		func visit(_ typeName: String, path: [String], declarationsOnPath: [[String: Set<ProductionDeclaration>]]) {
			visits += 1
			guard skip == nil, visits < 10_000 else { return }
			let propertiesToGenerate = propertiesToGenerate(ofTypeNamed: typeName)
			// The scope's own declarations, its aliases created when what they refer to is: among its own declarations
			// first, then above it, found to a fixed point for a chain of aliases on one scope.
			var scopeDeclarations = [String: Set<ProductionDeclaration>]()
			for property in propertiesToDeclare(ofTypeNamed: typeName, generating: propertiesToGenerate).union(types[typeName]?.forwardedReceivableProperties ?? []) {
				scopeDeclarations[property.label, default: []].insert(ProductionDeclaration(property: property, isCreated: true))
			}
			var uncreatedAliases = Set<GraphFuzzerMirrorProperty>()
			var aliasesChanged = true
			while aliasesChanged {
				aliasesChanged = false
				for case let .aliased(property, fulfillingProperty, onlyIfAvailable) in propertiesToGenerate where onlyIfAvailable && !uncreatedAliases.contains(property) {
					let fulfilling = resolution(of: fulfillingProperty, in: declarationsOnPath + [scopeDeclarations.filter { $0.key != property.label }])
					let isCreated = fulfilling.flatMap(\.declaration).map { $0.isCreated && !uncreatedAliases.contains($0.property) } ?? false
					if !isCreated {
						uncreatedAliases.insert(property)
						aliasesChanged = true
					}
				}
			}
			for alias in uncreatedAliases {
				scopeDeclarations[alias.label]?.remove(ProductionDeclaration(property: alias, isCreated: true))
				scopeDeclarations[alias.label, default: []].insert(ProductionDeclaration(property: alias, isCreated: false))
			}
			for dependency in types[typeName]?.dependencies ?? [] where skip == nil {
				switch dependency.source {
				case let .received(onlyIfAvailable):
					skip = skipReason(receiving: dependency.property, isRequired: !onlyIfAvailable, in: declarationsOnPath)
				case let .aliased(fulfillingProperty, onlyIfAvailable):
					// An alias of a property its own scope declares refers to that property, which, as another of the scope's
					// `onlyIfAvailable` aliases, may not be created.
					if dependencies(ofTypeNamed: typeName, declare: fulfillingProperty) {
						if !onlyIfAvailable, resolution(of: fulfillingProperty, in: [scopeDeclarations])?.declaration?.isCreated == false {
							skip = .requiredReceiveOfUncreatedAlias
						}
					} else {
						skip = skipReason(receiving: fulfillingProperty, isRequired: !onlyIfAvailable, in: declarationsOnPath)
					}
				case .instantiated, .forwarded:
					continue
				}
			}
			for case let .instantiated(_, childTypeName, _) in propertiesToGenerate where !path.contains(childTypeName) {
				visit(childTypeName, path: path + [childTypeName], declarationsOnPath: declarationsOnPath + [scopeDeclarations])
			}
		}
		for case let .instantiated(_, childTypeName, _) in mockRoot.children {
			visit(childTypeName, path: [mockedTypeName, childTypeName], declarationsOnPath: [rootDeclarations])
		}
		return skip
	}

	/// Whether the type `typeName` declares `property` itself – instantiates, forwards, or aliases it – or its
	/// non-optional form.
	private func dependencies(ofTypeNamed typeName: String, declare property: GraphFuzzerMirrorProperty) -> Bool {
		(types[typeName]?.dependencies ?? []).contains { dependency in
			switch dependency.source {
			case .instantiated, .forwarded, .aliased:
				dependency.receivableProperties.contains(property) || dependency.receivableProperties.contains(property.unwrapped)
			case .received:
				false
			}
		}
	}

	/// The `onlyIfAvailable` overrides the mock takes, as `mockRootParameters` classifies the received properties: by
	/// value, each that nothing the mock root declares provides and that every receiver receives only if available.
	private func onlyIfAvailableOverrideCount(of mockRoot: MockRoot, mockedTypeName: String) -> Int {
		let declaredProperties = propertiesToDeclare(ofTypeNamed: mockedTypeName, generating: mockRoot.children)
		// A property the mocked type forwards is a parameter of `mock()`, which fulfills a receive of it or of its optional
		// form anywhere in the tree.
		let forwardedProperties = types[mockedTypeName]?.forwardedReceivableProperties ?? []
		func isFulfilledByForwardedProperty(_ property: GraphFuzzerMirrorProperty) -> Bool {
			forwardedProperties.contains(property) || forwardedProperties.contains(property.unwrapped)
		}
		/// As `isProvidedByTree`: the tree declares the property, or the optional form's non-optional form, or, for a
		/// non-optional property, a node of its optional form, which a mock builds non-optional.
		func isProvidedByTree(_ property: GraphFuzzerMirrorProperty) -> Bool {
			declaredProperties.contains(property)
				|| (property.isOptional && declaredProperties.contains(property.unwrapped))
				|| (!property.isOptional && declaredProperties.contains(GraphFuzzerMirrorProperty(label: property.label, type: property.type + "?")))
		}
		// The mocked type's instantiated dependencies no scope builds, which `mock()` takes. The instance of such a wrapper
		// provides only that wrapper, so a receive of the other wrapper kind takes the instance as a parameter or an
		// override (`isProvidedByTreeByValue`).
		let uncoveredProperties = Set((types[mockedTypeName]?.dependencies ?? []).compactMap { dependency -> GraphFuzzerMirrorProperty? in
			guard case .instantiated = dependency.source,
			      !mockRoot.children.contains(where: { $0.property == dependency.property || $0.lazilyInstantiatedInstance == dependency.property })
			else { return nil }
			return dependency.property
		})
		let uncoveredWrapperInstances = Set(uncoveredProperties.compactMap(\.lazilyInstantiatedInstance))
		func isProvidedByTreeByValue(_ property: GraphFuzzerMirrorProperty) -> Bool {
			isProvidedByTree(property) && !uncoveredWrapperInstances.contains(property.unwrapped)
		}
		// As `mockRootParameters`: the lazily instantiated dependencies the tree receives and the mock cannot build are
		// classified by their instances, and so then is every received property. The generator also keeps the instance of
		// a received wrapper beside a forwarded property of its label (`isBesideForwardedProperty`), which this count
		// drops with every property a forwarded one fulfills: no corpus graph forwards a property whose label its tree
		// receives as a wrapper, and such a mock takes a required parameter, so a divergence would show only as
		// `mirrorModelDisagreesWithMock`. Port the term when the fuzzer draws that shape.
		let lazilyInstantiatedReceivedProperties = mockRoot.received.filter { property in
			GraphFuzzerMirrorTypes.lazilyInstantiatedInstanceType(of: property.unwrapped.type) != nil
				&& !isProvidedByTree(property)
				&& (!isProvidedByTreeByValue(property.validatedForDependencyCycles) || uncoveredProperties.contains(property.validatedForDependencyCycles.unwrapped))
				&& !isFulfilledByForwardedProperty(property)
		}
		let receivedParameterProperties = lazilyInstantiatedReceivedProperties.isEmpty
			? mockRoot.received
			: Set(mockRoot.received.filter { !isFulfilledByForwardedProperty($0) }.map(\.validatedForDependencyCycles))
		let requiredUnwrappedProperties = Set(mockRoot.required.filter { !isFulfilledByForwardedProperty($0) }.map(\.validatedForDependencyCycles.unwrapped))
		var overrideCount = 0
		for property in receivedParameterProperties
			where !forwardedProperties.contains(property)
			&& (!property.isOptional || (!receivedParameterProperties.contains(property.unwrapped) && !forwardedProperties.contains(property.unwrapped)))
			&& !isProvidedByTreeByValue(property)
			&& !requiredUnwrappedProperties.contains(property.validatedForDependencyCycles.unwrapped)
		{
			overrideCount += 1
		}
		return overrideCount
	}

	/// The shapes the mock root shows.
	private func shapes(of mockRoot: MockRoot, mockedTypeName: String) -> Set<GraphFuzzerValueOracleShape> {
		var shapes = Set<GraphFuzzerValueOracleShape>()
		let promotedProperties = mockRoot.promotedChildren.map(\.property)
		let promotedReceivable = Set(mockRoot.promotedChildren.flatMap(\.receivableProperties).map(\.unwrapped))
		var receiverCountByPromotedProperty = [GraphFuzzerMirrorProperty: Set<String>]()
		for typeName in mockRoot.typeNamesInTree {
			for dependency in types[typeName]?.dependencies ?? [] {
				switch dependency.source {
				case .received:
					if let promoted = mockRoot.promotedChildren.first(where: { $0.receivableProperties.map(\.unwrapped).contains(dependency.property.unwrapped) }) {
						receiverCountByPromotedProperty[promoted.property, default: []].insert(typeName)
						if typeName == mockedTypeName, promoted.property.lazilyInstantiatedInstance == dependency.property.unwrapped {
							shapes.insert(.instanceOfPromotedWrapperPassedToMockedType)
						}
					} else if dependency.source == .received(onlyIfAvailable: true), typeName != mockedTypeName,
					          // The tree's received properties, from which each scope subtracts what it declares: a receive the
					          // mocked type's own child or a scope above the receiver provides is not among them.
					          mockRoot.received.contains(dependency.property) || mockRoot.received.contains(dependency.property.unwrapped)
					{
						shapes.insert(.onlyIfAvailableReceiveInMockedTypesTreeLeftUnbuilt)
					}
				case let .aliased(fulfillingProperty, onlyIfAvailable):
					if promotedReceivable.contains(fulfillingProperty.unwrapped) {
						shapes.insert(onlyIfAvailable ? .onlyIfAvailableAliasOfPromotedDependency : .requiredAliasOfPromotedDependency)
					}
				case .instantiated, .forwarded:
					break
				}
			}
		}
		if receiverCountByPromotedProperty.values.contains(where: { $0.count >= 2 }) {
			shapes.insert(.promotedDependencyReceivedByTwoOrMoreTypes)
		}
		for property in promotedProperties where property.lazilyInstantiatedInstance != nil {
			let otherForms = mockRoot.received.filter { $0.label == property.label && $0 != property }
			if !otherForms.isEmpty {
				shapes.insert(.promotedWrapperReceivedInAnotherForm)
			}
		}
		for case let .instantiated(property, _, _) in mockRoot.children[..<mockRoot.ownChildCount]
			where !(types[mockedTypeName]?.dependencies.contains { $0.property == property } ?? true)
		{
			shapes.insert(.ownPropertyRebuiltAsWrapper)
		}
		return shapes
	}
}

/// Why the value oracle compares no mirror for a mocked type: a stated skip, or a model that disagrees with the mock,
/// which is a failure.
enum GraphFuzzerMirrorFailure: Error, Equatable {
	case skipped(GraphFuzzerMirrorSkip)
	case modelDisagrees(String)
}

// MARK: - The value-oracle fixture

/// What the base corpus's value oracle compares for one accepted graph: each root's generated `mock()` with the root's
/// production build (`Root.mock()` against `Root()`), and each mocked type's parameterless `mock()` with its mirror's
/// production build, both of which the value-oracle fixture holds side by side. The fixture is the graph with
/// `generateMock: true` on every root and one mirror root per compared mocked type, each in a file of its own; it only
/// feeds the oracle, so the corpus, its hashes and its pins are the graph's.
struct GraphFuzzerValueOraclePlan {
	/// Plans the comparison of `fixture`, a base corpus graph the tool accepted, from the files the tool generated for it.
	/// - Parameter storingFixture: The same graph storing every parameter, which the comparator compiles, or `nil` for
	///   the corpus graph of `fixture`'s seed drawn so (`GraphFuzzerGenerator.fixture(forSeed:storingEveryParameter:)`).
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	init(fixture: GraphFuzzerFixture, generatedFiles: [String: String], storingFixture: GraphFuzzerFixture? = nil) {
		let model = GraphFuzzerMockMirrorModel(fixture: fixture)
		self.fixture = fixture
		self.storingFixture = storingFixture ?? GraphFuzzerGenerator.fixture(forSeed: fixture.seed, storingEveryParameter: true)
		rootTypeNames = model.typeOrder.filter { model.types[$0]?.isRoot == true }
		let mockFileSuffix = "+SafeDIMock.swift"
		var mirrors = [GraphFuzzerMockMirror]()
		var skips = [(typeName: String, skip: GraphFuzzerMirrorSkip)]()
		var modelFailures = [String]()
		var cache = GraphFuzzerMockMirrorModel.ReceivedPropertiesCache()
		let samples = GraphFuzzerSampleValues(fixture: fixture, model: model)
		// The tool creates mock roots in type order, sharing what it collects of each scope's received properties.
		for typeName in model.typeOrder.sorted() where model.types[typeName]?.generatesMock == true && model.types[typeName]?.isRoot == false {
			guard let mockFile = generatedFiles[typeName + mockFileSuffix] else {
				modelFailures.append("The tool generated no `\(typeName)\(mockFileSuffix)` for `\(typeName)`, which generates a mock.")
				continue
			}
			// The model's mock root is checked against the mock before any skip is decided, since every skip reads it (R4).
			let mockRoot = model.mockRoot(ofTypeNamed: typeName, cache: &cache)
			if let disagreement = GraphFuzzerMockOverrides.disagreement(between: model.expectation(of: mockRoot, mockedTypeName: typeName), andMockFile: mockFile, typeNamePrefix: fixture.typeNamePrefix) {
				modelFailures.append(disagreement)
				continue
			}
			// The mock's required parameters are handed sample values, which the mirror forwards.
			let requiredParameters = GraphFuzzerMockOverrides.requiredParameters(mockFile)
			let mockArguments = requiredParameters.map { parameter in samples.expression(ofType: parameter.type).map { "\(parameter.label): \($0)" } }
			guard mockArguments.allSatisfy({ $0 != nil }) else {
				skips.append((typeName, .requiredParameter))
				continue
			}
			switch model.mirror(of: mockRoot, mockedTypeName: typeName, named: "\(fixture.typeNamePrefix)ZMirror\(mirrors.count)", forwarding: requiredParameters) {
			case var .success(mirror):
				mirror.mockArguments = mockArguments.compactMap(\.self)
				mirror.forwardedPropertiesSample = requiredParameters.isEmpty ? nil : samples.forwardedPropertiesExpression(of: requiredParameters)
				mirrors.append(mirror)
			case let .failure(.skipped(skip)):
				skips.append((typeName, skip))
			case let .failure(.modelDisagrees(reason)):
				modelFailures.append("`\(typeName).mock()`: \(reason)")
			}
		}
		self.mirrors = mirrors
		forwardedPropertiesSamples = samples.forwardedPropertiesSamples
		self.skips = skips
		self.modelFailures = modelFailures
		drawnMockFiles = generatedFiles.filter { $0.key.hasSuffix(mockFileSuffix) }
		rootShapes = Self.rootShapes(of: model, rootTypeNames: rootTypeNames)
		mirrorNamesSortingBeforeTypeNames = Self.typeNamesSortingAfterMirrors(in: fixture, mirrors: mirrors)
		var rootOverrideCandidates = [String: [GraphFuzzerOverrideCandidate]]()
		for rootTypeName in rootTypeNames {
			rootOverrideCandidates[rootTypeName] = model.propertiesToGenerate(ofTypeNamed: rootTypeName).compactMap { propertyToGenerate in
				guard case let .instantiated(property, scopeTypeName, isErased) = propertyToGenerate,
				      !isErased,
				      GraphFuzzerMirrorTypes.kindOrder(of: property.type) == 0,
				      !property.isOptional
				else { return nil }
				return GraphFuzzerOverrideCandidate(label: property.label, builtTypeName: scopeTypeName)
			}
		}
		self.rootOverrideCandidates = rootOverrideCandidates
		var instantiateParametersByExtensionTypeName = [String: [String]]()
		for typeName in model.typeOrder {
			guard let type = model.types[typeName], type.isExtension else { continue }
			instantiateParametersByExtensionTypeName[typeName] = type.instantiateParameters
		}
		self.instantiateParametersByExtensionTypeName = instantiateParametersByExtensionTypeName
	}

	let fixture: GraphFuzzerFixture
	/// The same graph storing every parameter, with a creation stamp in every class when the generator drew it.
	let storingFixture: GraphFuzzerFixture
	/// The graph's roots, in declaration order.
	let rootTypeNames: [String]
	/// The mock files the tool generated for the graph as drawn, by name, which the value-oracle run must generate alike
	/// (R6).
	let drawnMockFiles: [String: String]
	/// The mirror of each compared mocked type, in type order.
	let mirrors: [GraphFuzzerMockMirror]
	/// The sample value of each type's `ForwardedProperties` that has one, which the describer calls an instantiator of
	/// the type with.
	let forwardedPropertiesSamples: [DifferentialValueSample]
	/// Each mocked type of the graph the oracle compares no mirror for, and why.
	let skips: [(typeName: String, skip: GraphFuzzerMirrorSkip)]
	/// Where the mirror model disagrees with a generated mock (`mirrorModelDisagreesWithMock`): a model left behind by a
	/// change to what a mock promotes, or a mock that promotes another set than the rules state.
	let modelFailures: [String]
	/// The shapes each root's production tree shows, by root.
	let rootShapes: [String: Set<GraphFuzzerValueOracleShape>]
	/// The type names of the graph that sort after a mirror's name, which would let a mirror change the order of the
	/// tool's alphabetical walks: always empty, by the mirrors' names.
	let mirrorNamesSortingBeforeTypeNames: [String]
	/// The dependencies of each root whose override the override oracle may pass the root's mock, in declaration order.
	let rootOverrideCandidates: [String: [GraphFuzzerOverrideCandidate]]
	/// The parameters of each of the graph's extensions' `instantiate(…)`, each as declared, by the type it builds.
	let instantiateParametersByExtensionTypeName: [String: [String]]

	/// The value-oracle fixture: `fixture`, or the same graph drawn storing every parameter, with `generateMock: true`
	/// on every root and the mirrors' files after the graph's own, and, in the fixture the comparator compiles, the file
	/// of the override oracle's record (`GraphFuzzerOverrideSentinel`), which the tool does not read.
	func valueOracleFixture(storingEveryParameter: Bool) -> GraphFuzzerFixture {
		let base = storingEveryParameter ? storingFixture : fixture
		let counterName = "\(fixture.typeNamePrefix)CreationStamp"
		// A fixture whose classes store creation stamps declares their counter, and so does each mirror.
		let stamp = storingEveryParameter && base.swiftFileContent.contains(where: { $0.contains("enum \(counterName)") })
			? DifferentialValueCreationStamp.property(counterNamed: counterName)
			: nil
		let conformance = Self.mirrorConformance(of: fixture)
		return GraphFuzzerFixture(
			seed: fixture.seed,
			swiftFileContent: base.swiftFileContent.map { $0.replacingOccurrences(of: "@Instantiable(isRoot: true)\n", with: "@Instantiable(isRoot: true, generateMock: true)\n") }
				+ mirrors.map { $0.source(conformance: conformance, stamp: stamp) }
				+ (storingEveryParameter ? [GraphFuzzerOverrideSentinel.source(typeNamePrefix: fixture.typeNamePrefix)] : []),
		)
	}

	/// The pairs the oracle compares: each root's mock with its production build, then each mirrored mock with its
	/// mirror's value. Never a mirror itself, which builds the mocked type's dependencies the mocked type does not hold.
	var probePairs: [DifferentialValueProbePair] {
		rootTypeNames.map { DifferentialValueProbePair(name: "\($0).mock()", featureExpression: "\($0).mock()", knownRightExpression: "\($0)()") }
			+ mirrors.map { DifferentialValueProbePair(name: "\($0.mockedTypeName).mock()", featureExpression: $0.featureExpression, knownRightExpression: $0.knownRightExpression) }
	}

	/// The shapes the compared pairs show, each with the number of pairs that show it.
	var shapeCounts: [GraphFuzzerValueOracleShape: Int] {
		var counts = [GraphFuzzerValueOracleShape: Int]()
		for shapes in rootShapes.values {
			for shape in shapes {
				counts[shape, default: 0] += 1
			}
		}
		for mirror in mirrors {
			for shape in mirror.shapes {
				counts[shape, default: 0] += 1
			}
		}
		return counts
	}

	/// What the mirror conforms to beyond `Instantiable`, as the graph's types do: `Sendable` in a graph whose roots are
	/// `Sendable`, `@unchecked Sendable` in a graph that mixes `Sendable` wrappers with others, since it stores wrappers,
	/// and nothing in a graph of wrappers that are not `Sendable`.
	private static func mirrorConformance(of fixture: GraphFuzzerFixture) -> String {
		let rootDeclaration = "final class \(fixture.typeNamePrefix)Root0: Instantiable, Sendable {"
		if fixture.swiftFileContent.contains(where: { $0.contains(rootDeclaration) }) {
			return ", Sendable"
		} else if fixture.swiftFileContent.contains(where: { $0.contains("Protocol, @unchecked Sendable {") }) {
			return ", @unchecked Sendable"
		} else {
			return ""
		}
	}

	/// The type names the fixture declares that do not sort before every mirror's name.
	private static func typeNamesSortingAfterMirrors(in fixture: GraphFuzzerFixture, mirrors: [GraphFuzzerMockMirror]) -> [String] {
		guard let firstMirrorName = mirrors.map(\.name).min() else { return [] }
		var names = Set<String>()
		for content in fixture.swiftFileContent {
			for keyword in ["class ", "protocol ", "enum ", "struct ", "extension "] {
				var searchStart = content.startIndex
				while let range = content.range(of: keyword + fixture.typeNamePrefix, range: searchStart..<content.endIndex) {
					let nameStart = content.index(range.lowerBound, offsetBy: keyword.count)
					names.insert(String(content[nameStart...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }))
					searchStart = range.upperBound
				}
			}
		}
		return names.filter { $0 >= firstMirrorName }.sorted()
	}

	/// The shapes each root's production tree shows.
	private static func rootShapes(of model: GraphFuzzerMockMirrorModel, rootTypeNames: [String]) -> [String: Set<GraphFuzzerValueOracleShape>] {
		var shapesByRoot = [String: Set<GraphFuzzerValueOracleShape>]()
		for rootTypeName in rootTypeNames {
			var shapes = Set<GraphFuzzerValueOracleShape>()
			var receiversByProperty = [GraphFuzzerMirrorProperty: Set<String>]()
			var declaredProperties = Set<GraphFuzzerMirrorProperty>()
			// The walk visits each path of the root's tree, so it stops after 10,000 visits rather than grow with the paths
			// of a dense graph. A corpus graph holds at most about a dozen sparsely connected types, far fewer paths than
			// that. A truncated walk would count fewer shapes, which moves a pin (`corpusValueOracleCounts`).
			var visits = 0
			/// Walks each path of the root's tree, with the properties each scope on the path declares, nearest last.
			func visit(_ typeName: String, path: [String], declarationsOnPath: [Set<GraphFuzzerMirrorProperty>]) {
				visits += 1
				guard visits < 10_000 else { return }
				for dependency in model.types[typeName]?.dependencies ?? [] {
					let receivedProperty: GraphFuzzerMirrorProperty
					switch dependency.source {
					case .received:
						receivedProperty = dependency.property
					case let .aliased(fulfillingProperty, _):
						receivedProperty = fulfillingProperty
					case .instantiated, .forwarded:
						continue
					}
					receiversByProperty[receivedProperty.validatedForDependencyCycles.unwrapped, default: []].insert(typeName)
					let declaringScopeCount = declarationsOnPath.count { declarations in
						declarations.contains(receivedProperty) || declarations.contains(receivedProperty.unwrapped)
					}
					if declaringScopeCount >= 2 {
						shapes.insert(.rootTreeLabelDeclaredAtTwoDepthsAboveReceiver)
					}
				}
				let propertiesToGenerate = model.propertiesToGenerate(ofTypeNamed: typeName)
				let declarations = model.propertiesToDeclare(ofTypeNamed: typeName, generating: propertiesToGenerate)
					.union(model.types[typeName]?.forwardedReceivableProperties ?? [])
				declaredProperties.formUnion(declarations.map(\.validatedForDependencyCycles.unwrapped))
				for case let .instantiated(_, childTypeName, _) in propertiesToGenerate where !path.contains(childTypeName) {
					visit(childTypeName, path: path + [childTypeName], declarationsOnPath: declarationsOnPath + [declarations])
				}
			}
			visit(rootTypeName, path: [rootTypeName], declarationsOnPath: [])
			if receiversByProperty.contains(where: { $0.value.count >= 2 && declaredProperties.contains($0.key) }) {
				shapes.insert(.rootTreePropertyReceivedByTwoOrMoreTypes)
			}
			shapesByRoot[rootTypeName] = shapes
		}
		return shapesByRoot
	}
}

/// What the value oracle reads from a generated mock: whether it takes a required parameter, and what its
/// `SafeDIOverrides` says it builds beside the mocked type, which the mirror model must agree with.
enum GraphFuzzerMockOverrides {
	/// Whether the generated `mock()` in `contents` takes no parameter without a default value. A mock without
	/// parameters is declared on one line, `static func mock() -> T {`; one with parameters lists them a line each.
	static func takesNoRequiredParameter(_ contents: String) -> Bool {
		mockParameters(contents).allSatisfy { $0.contains(" = ") }
	}

	/// The parameters of the generated `mock()` in `contents` without a default value, in the mock's order, each as the
	/// property it takes: its label, and its type without `@escaping`.
	static func requiredParameters(_ contents: String) -> [GraphFuzzerMirrorProperty] {
		mockParameters(contents).filter { !$0.contains(" = ") }.compactMap { parameter in
			let declaration = parameter.hasSuffix(",") ? parameter.dropLast() : Substring(parameter)
			guard let colon = declaration.firstIndex(of: ":") else { return nil }
			let type = declaration[declaration.index(after: colon)...].trimmingCharacters(in: .whitespaces)
			return GraphFuzzerMirrorProperty(
				label: String(declaration[..<colon]),
				type: type.replacingOccurrences(of: "@escaping ", with: ""),
			)
		}
	}

	/// The parameters of the generated `mock()` in `contents`, one per line as declared.
	static func mockParameters(_ contents: String) -> [String] {
		let lines = contents.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
		let signature = lines.drop { !$0.contains("static func mock(") }
		guard signature.first?.hasSuffix("static func mock(") == true else { return [] }
		return Array(signature.dropFirst().prefix { !$0.hasPrefix(")") })
	}

	/// The parameters of the `SafeDIOverrides` initializer in `contents`, as `(label, type)`.
	static func overrideFields(_ contents: String) -> [(label: String, type: String)] {
		let lines = contents.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
		guard let structStart = lines.firstIndex(of: "struct SafeDIOverrides {"),
		      let initializerStart = lines[structStart...].firstIndex(of: "init(")
		else { return [] }
		return lines[(initializerStart + 1)...].prefix { !$0.hasPrefix(")") }.compactMap { line in
			guard let colon = line.firstIndex(of: ":") else { return nil }
			var type = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
			if let defaultStart = type.range(of: " = ", options: .backwards) {
				type = String(type[..<defaultStart.lowerBound])
			}
			return (String(line[..<colon]), type)
		}
	}

	/// The type each field of `fields` builds beside the mocked type, by its concrete type's name: the configured type
	/// of a configuration field, or the return type of a builder closure field, with an erased type `AnyT<n>` named by
	/// the concrete type it erases, `T<n>`, as every erasure of the base corpus does.
	static func builtTypeNames(of fields: [(label: String, type: String)], typeNamePrefix: String) -> [String] {
		fields.compactMap { field -> String? in
			let builtType: String
			if field.type.hasSuffix(".SafeDIMockConfiguration") {
				builtType = String(field.type.dropLast(".SafeDIMockConfiguration".count))
			} else if field.type.hasPrefix("("), field.type.hasSuffix(")?"), let arrow = field.type.range(of: " -> ", options: .backwards) {
				builtType = String(field.type[arrow.upperBound...].dropLast(")?".count))
			} else {
				return nil
			}
			return builtType.replacingOccurrences(of: "\(typeNamePrefix)AnyT", with: "\(typeNamePrefix)T")
		}.sorted()
	}

	/// How many of `fields` are `onlyIfAvailable` overrides: an optional value that is neither a builder closure nor a
	/// configuration.
	static func onlyIfAvailableOverrideCount(of fields: [(label: String, type: String)]) -> Int {
		fields.count { field in
			field.type.hasSuffix("?") && !(field.type.hasPrefix("(") && field.type.contains(" -> "))
		}
	}

	/// How the generated mock in `contents` disagrees with `expectation`, what the model says the mock of the same type
	/// builds, or `nil`: the types it builds beside the mocked type, as multisets, and the number of its `onlyIfAvailable`
	/// overrides. Labels are not compared, since sibling disambiguation renames them.
	static func disagreement(between expectation: GraphFuzzerMockRootExpectation, andMockFile contents: String, typeNamePrefix: String) -> String? {
		let fields = overrideFields(contents)
		let builtTypeNames = builtTypeNames(of: fields, typeNamePrefix: typeNamePrefix)
		let overrideCount = onlyIfAvailableOverrideCount(of: fields)
		guard builtTypeNames != expectation.builtTypeNames || overrideCount != expectation.onlyIfAvailableOverrideCount else { return nil }
		return """
		`\(expectation.mockedTypeName).mock()` builds \(builtTypeNames) beside `\(expectation.mockedTypeName)` and takes \(overrideCount) onlyIfAvailable overrides; the mirror model builds \(expectation.builtTypeNames) and expects \(expectation.onlyIfAvailableOverrideCount).
		"""
	}
}

/// The value oracle's run of a base corpus graph the tool accepts: its plan, and the tool's outcome over the
/// value-oracle fixture, which the oracle compiles from the same graph drawn storing every parameter, since storing
/// changes nothing the tool generates. The outcome is `nil` when the model disagrees with a generated mock, which
/// fails the graph before the tool runs again.
struct GraphFuzzerValueOracleRun {
	let plan: GraphFuzzerValueOraclePlan
	let outcome: GraphFuzzerToolOutcome?

	/// The graph the comparator compares: the value-oracle fixture drawn storing every parameter, with what the tool
	/// generated for it, and the plan's pairs followed by the override oracle's, or `nil` when the tool did not accept the
	/// fixture.
	var valueGraph: DifferentialValueGraph? {
		guard case let .accepted(generatedFiles, _) = outcome else { return nil }
		return DifferentialValueGraph(
			name: "seed \(plan.fixture.seed), value oracle",
			path: DifferentialValuePath(fixture: plan.valueOracleFixture(storingEveryParameter: true), generatedFiles: generatedFiles),
			probePairs: plan.probePairs + overrideProbes.map(\.pair),
			samples: plan.forwardedPropertiesSamples,
		)
	}

	/// The override oracle's probes of the value-oracle run's mocks (`GraphFuzzerValueOraclePlan.overrideProbes`), none
	/// when the tool did not accept the fixture.
	var overrideProbes: [GraphFuzzerOverrideProbe] {
		guard case let .accepted(generatedFiles, _) = outcome else { return [] }
		return plan.overrideProbes(generatedFiles: generatedFiles)
	}

	/// The drawn graph's mock files, by name, that the value-oracle run generates otherwise even once both are read as
	/// `GraphFuzzerMockOverrides.comparableWithAnotherRunsMocks` reads them, or not at all (R6): the oracle would judge
	/// other code than the corpus's.
	var drawnMockFileNamesChanged: [String] {
		guard case let .accepted(valueOracleFiles, _) = outcome else { return [] }
		return plan.drawnMockFiles.keys.sorted().filter { fileName in
			valueOracleFiles[fileName].map(GraphFuzzerMockOverrides.comparableWithAnotherRunsMocks) != plan.drawnMockFiles[fileName].map(GraphFuzzerMockOverrides.comparableWithAnotherRunsMocks)
		}
	}

	/// The drawn graph's mock files, by name, that the value-oracle run generates otherwise, but alike once both are read
	/// as `GraphFuzzerMockOverrides.comparableWithAnotherRunsMocks` reads them: the files R6's allowance passes, which the
	/// corpus pins by count so that the allowance stays visible when a generator change widens it.
	var drawnMockFileNamesMatchingOnlyAfterNormalization: [String] {
		guard case let .accepted(valueOracleFiles, _) = outcome else { return [] }
		return plan.drawnMockFiles.keys.sorted().filter { fileName in
			guard let valueOracleFile = valueOracleFiles[fileName], let drawnFile = plan.drawnMockFiles[fileName] else { return false }
			return valueOracleFile != drawnFile
				&& GraphFuzzerMockOverrides.comparableWithAnotherRunsMocks(valueOracleFile) == GraphFuzzerMockOverrides.comparableWithAnotherRunsMocks(drawnFile)
		}
	}
}

extension GraphFuzzerMockOverrides {
	/// `contents`, a generated mock file, without the blocks that declare a type's `SafeDIMockConfiguration` and no
	/// `mock()`.
	static func removingConfigurations(from contents: String) -> String {
		contents.components(separatedBy: "\n#if DEBUG\n").enumerated().compactMap { index, block in
			index > 0 && block.contains("struct SafeDIMockConfiguration {") && !block.contains("static func mock(") ? nil : block
		}.joined(separator: "\n#if DEBUG\n").trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// `contents`, a generated mock file, as the corpus run and the value-oracle run of one graph both generate it: without
	/// its configuration blocks (`removingConfigurations(from:)`), and reading a configuration's default-valued field as a
	/// value where a configuration that is `@Sendable`-typed calls its `@Sendable` autoclosure
	/// (`safeDIOverrides.ext.retryCount()`). A root's mock that builds a type inside a `Sendable` builder makes the type's
	/// configuration `@Sendable`-typed for every mock, so a drawn mock reads the same default through the autoclosure.
	static func comparableWithAnotherRunsMocks(_ contents: String) -> String {
		removingConfigurations(from: contents).replacingOccurrences(of: #"(safeDIOverrides(\.[A-Za-z0-9_]+)+)\(\)"#, with: "$1", options: .regularExpression)
	}
}

// MARK: - Pins

/// What the base corpus's value oracle compared and skipped, which the long run reports per shard and pins over the
/// whole corpus: the compared root pairs and mirrored pairs, each as a count and as a set sum over `<seed>:<type>`, so
/// that a pair that drops out while another drops in still moves a pin; each mocked type compared with no mirror, by
/// reason; the compared pairs that show each shape; the drawn mock files that R6 finds alike only once its allowance
/// normalizes them (`GraphFuzzerValueOracleRun.drawnMockFileNamesMatchingOnlyAfterNormalization`); and, of the
/// compared graphs, the mirrored pairs whose mock takes sample values, the types whose `ForwardedProperties` have a
/// sample the describer calls their instantiators with, and the override oracle's pairs, as a count, as a set sum over
/// `<seed>:<type>:<label>`, and per field kind.
struct GraphFuzzerValueOracleCounts: Equatable {
	var rootPairCount = 0
	var rootPairsSum = GraphFuzzerSeedSetSum()
	var mirroredPairCount = 0
	var mirroredPairsSum = GraphFuzzerSeedSetSum()
	var skipCounts = [GraphFuzzerMirrorSkip: Int]()
	var shapeCounts = [GraphFuzzerValueOracleShape: Int]()
	var drawnMocksMatchingOnlyAfterNormalizationCount = 0
	var mirroredPairsTakingSamplesCount = 0
	var forwardedPropertiesSampleCount = 0
	var overridePairCount = 0
	var overridePairsSum = GraphFuzzerSeedSetSum()
	var overrideFieldKindCounts = [GraphFuzzerOverrideFieldKind: Int]()

	/// Counts the skips and the drawn mock files R6 normalizes of a graph the value oracle inspected and, when its
	/// value-oracle graph was compared, its pairs and their shapes.
	mutating func add(_ valueOracle: GraphFuzzerValueOracleRun, isCompared: Bool) {
		let plan = valueOracle.plan
		for (_, skip) in plan.skips {
			skipCounts[skip, default: 0] += 1
		}
		drawnMocksMatchingOnlyAfterNormalizationCount += valueOracle.drawnMockFileNamesMatchingOnlyAfterNormalization.count
		guard isCompared else { return }
		for rootTypeName in plan.rootTypeNames {
			rootPairCount += 1
			rootPairsSum.add(member: "\(plan.fixture.seed):\(rootTypeName)")
		}
		for mirror in plan.mirrors {
			mirroredPairCount += 1
			mirroredPairsSum.add(member: "\(plan.fixture.seed):\(mirror.mockedTypeName)")
			if !mirror.mockArguments.isEmpty {
				mirroredPairsTakingSamplesCount += 1
			}
		}
		forwardedPropertiesSampleCount += plan.forwardedPropertiesSamples.count
		for (shape, count) in plan.shapeCounts {
			shapeCounts[shape, default: 0] += count
		}
		for probe in valueOracle.overrideProbes {
			overridePairCount += 1
			overridePairsSum.add(member: "\(plan.fixture.seed):\(probe.mockedTypeName):\(probe.label)")
			overrideFieldKindCounts[probe.fieldKind, default: 0] += 1
		}
	}

	/// The counts as one report field, `key=value` separated by commas, every key present: what
	/// `combine-graph-fuzzer-reports.py` adds up across shards, sums wrapping.
	var reportField: String {
		var fields = [
			"rootPairs=\(rootPairCount)",
			"rootPairsSum=0x\(String(rootPairsSum.value, radix: 16, uppercase: true))",
			"mirroredPairs=\(mirroredPairCount)",
			"mirroredPairsSum=0x\(String(mirroredPairsSum.value, radix: 16, uppercase: true))",
		]
		fields += GraphFuzzerMirrorSkip.allCases.map { "skip.\($0.rawValue)=\(skipCounts[$0, default: 0])" }
		fields += GraphFuzzerValueOracleShape.allCases.map { "shape.\($0.rawValue)=\(shapeCounts[$0, default: 0])" }
		fields.append("drawnMocksMatchingOnlyAfterNormalization=\(drawnMocksMatchingOnlyAfterNormalizationCount)")
		fields.append("mirroredPairsTakingSamples=\(mirroredPairsTakingSamplesCount)")
		fields.append("forwardedPropertiesSamples=\(forwardedPropertiesSampleCount)")
		fields.append("overridePairs=\(overridePairCount)")
		fields.append("overridePairsSum=0x\(String(overridePairsSum.value, radix: 16, uppercase: true))")
		fields += GraphFuzzerOverrideFieldKind.allCases.map { "override.\($0.rawValue)=\(overrideFieldKindCounts[$0, default: 0])" }
		return fields.joined(separator: ",")
	}

	static func == (lhs: GraphFuzzerValueOracleCounts, rhs: GraphFuzzerValueOracleCounts) -> Bool {
		lhs.reportField == rhs.reportField
	}
}
