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
import SwiftSyntax

/// A model capable of generating code for a scope’s dependency tree.
actor ScopeGenerator: CustomStringConvertible, Sendable {
	// MARK: Initialization

	init(
		instantiable: Instantiable,
		property: Property?,
		propertiesToGenerate: [ScopeGenerator],
		unavailableOptionalProperties: Set<Property>,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		forwardedLazilyInstantiatedInstanceProperties: [Property],
		erasedToConcreteExistential: Bool,
		isPropertyCycle: Bool,
	) {
		if let property {
			scopeData = .property(
				instantiable: instantiable,
				property: property,
				forwardedProperties: Set(
					instantiable
						.dependencies
						.filter { $0.source == .forwarded }
						.map(\.property),
				),
				erasedToConcreteExistential: erasedToConcreteExistential,
				isPropertyCycle: isPropertyCycle,
			)
			description = instantiable.concreteInstantiable.asSource
		} else {
			scopeData = .root(instantiable: instantiable)
			description = instantiable.concreteInstantiable.asSource
		}
		self.property = property
		self.propertiesToGenerate = propertiesToGenerate
		// This runs at every scope of every tree, and nearly every child is outside every cycle.
		var childCycleClosingProperties = Set<Property>()
		var childrenTakePartInCycle = false
		for child in propertiesToGenerate where child.isReferencedByCycleClosingScope || !child.cycleClosingProperties.isEmpty {
			childCycleClosingProperties.formUnion(child.cycleClosingProperties)
			childrenTakePartInCycle = true
		}
		self.childrenTakePartInCycle = childrenTakePartInCycle
		declaresBuilderFunction = property != nil && !isPropertyCycle
		if let property, isPropertyCycle {
			cycleClosingProperties = [property]
			isReferencedByCycleClosingScope = false
		} else if let property, childCycleClosingProperties.contains(property) {
			cycleClosingProperties = childCycleClosingProperties.subtracting([property])
			isReferencedByCycleClosingScope = true
		} else {
			cycleClosingProperties = childCycleClosingProperties
			isReferencedByCycleClosingScope = false
		}
		// A lazily instantiated property also declares the property that receives its instance by value.
		// This runs at every scope of every tree, so the set is filled without intermediate arrays.
		var propertiesToDeclare = Set<Property>(minimumCapacity: propertiesToGenerate.count)
		for child in propertiesToGenerate {
			if let property = child.property {
				propertiesToDeclare.insert(property)
			}
			if let instanceProperty = child.declaredLazilyInstantiatedInstanceProperty {
				propertiesToDeclare.insert(instanceProperty)
			}
		}
		self.propertiesToDeclare = propertiesToDeclare
		self.unavailableOptionalProperties = unavailableOptionalProperties
		self.lazilyInstantiatedInstanceProperties = lazilyInstantiatedInstanceProperties
		fulfillingPropertyIsLazilyInstantiatedInstance = false
		declaredLazilyInstantiatedInstanceProperty = property?.asLazilyInstantiatedInstanceProperty
		onlyIfAvailableDependencies = instantiable.dependencies.compactMap { dependency in
			switch dependency.source {
			case let .received(onlyIfAvailable):
				onlyIfAvailable
					? OnlyIfAvailableDependency(unwrappedFulfillingProperty: dependency.property.asUnwrappedProperty, unavailableProperties: [dependency.property])
					: nil
			case let .aliased(fulfillingProperty, _, onlyIfAvailable):
				onlyIfAvailable
					? OnlyIfAvailableDependency(unwrappedFulfillingProperty: fulfillingProperty.asUnwrappedProperty, unavailableProperties: [dependency.property, fulfillingProperty])
					: nil
			case .instantiated, .forwarded:
				nil
			}
		}
		aliasPropertyIsProvidedByEnclosingScope = false
		// A forwarded lazily instantiated property is also received by value, as the instance it creates.
		let forwardedProperties = if forwardedLazilyInstantiatedInstanceProperties.isEmpty {
			scopeData.forwardedProperties
		} else {
			scopeData.forwardedProperties.union(forwardedLazilyInstantiatedInstanceProperties)
		}
		/// Whether a property a child requires be passed in must be received by this scope too: this
		/// scope does not provide it.
		func isReceivedFromAncestors(_ property: Property) -> Bool {
			!Self.provides(property, declaredProperties: propertiesToDeclare, forwardedProperties: forwardedProperties)
		}
		// All the properties our children require be passed in, unioned with the properties we
		// require to fulfill our own dependencies, and those of them some receiver requires. A
		// child's required properties are among its received ones, so each child's received
		// properties are read once, with no intermediate sets: this runs at every scope of every tree.
		var receivedProperties = Set<Property>()
		var requiredReceivedProperties = Set<Property>()
		for child in propertiesToGenerate {
			for property in child.receivedProperties where isReceivedFromAncestors(property) {
				receivedProperties.insert(property)
				if child.requiredReceivedProperties.contains(property) {
					requiredReceivedProperties.insert(property)
				}
			}
		}
		for dependency in instantiable.dependencies {
			let receivedProperty: Property
			let onlyIfAvailable: Bool
			switch dependency.source {
			case .instantiated, .forwarded:
				continue
			case let .received(isOnlyIfAvailable):
				receivedProperty = dependency.property
				onlyIfAvailable = isOnlyIfAvailable
			case let .aliased(fulfillingProperty, _, isOnlyIfAvailable):
				// If the alias's fulfilling property is locally declared
				// (e.g., as an @Instantiated sibling) or forwarded, the alias
				// binds against that local — it doesn't need to be received.
				guard !propertiesToDeclare.contains(fulfillingProperty),
				      !forwardedProperties.contains(fulfillingProperty)
				else { continue }
				receivedProperty = fulfillingProperty
				onlyIfAvailable = isOnlyIfAvailable
			}
			receivedProperties.insert(receivedProperty)
			if !onlyIfAvailable {
				requiredReceivedProperties.insert(receivedProperty)
			}
		}
		self.receivedProperties = receivedProperties
		self.requiredReceivedProperties = requiredReceivedProperties
		var unwrappedOptionalRequiredReceivedProperties = Set<Property>()
		for property in requiredReceivedProperties where property.typeDescription.isOptional {
			unwrappedOptionalRequiredReceivedProperties.insert(property.asUnwrappedProperty)
		}
		self.unwrappedOptionalRequiredReceivedProperties = unwrappedOptionalRequiredReceivedProperties
		// An `onlyIfAvailable` alias a receiver in this subtree requires must be created, so its
		// fulfilling property is built before it, unless an enclosing scope provides the alias's
		// property in its place.
		func isRequiredByChild(_ property: Property) -> Bool {
			propertiesToGenerate.contains {
				$0.requiredReceivedProperties.contains(property) || $0.requiredAliasFulfillingProperties.contains(property)
			}
		}
		var requiredOnlyIfAvailableAliasProperties = Set<Property>()
		var requiredOnlyIfAvailableAliasFulfillingProperties = Set<Property>()
		for case let (aliasProperty?, fulfillingProperty?) in propertiesToGenerate.lazy.map({ ($0.property, $0.onlyIfAvailableAliasFulfillingProperty) })
			where isRequiredByChild(aliasProperty)
		{
			requiredOnlyIfAvailableAliasProperties.insert(aliasProperty)
			requiredOnlyIfAvailableAliasFulfillingProperties.insert(fulfillingProperty)
		}
		self.requiredOnlyIfAvailableAliasProperties = requiredOnlyIfAvailableAliasProperties
		requiredAliasFulfillingProperties = Set(propertiesToGenerate.flatMap(\.requiredAliasFulfillingProperties))
			.union(requiredOnlyIfAvailableAliasFulfillingProperties)
			.filter(isReceivedFromAncestors)
			// A receiver of an alias that is never created and that an enclosing scope provides
			// resolves to the enclosing scope's property, so it requires that property instead.
			.union(
				propertiesToGenerate
					.compactMap(\.uncreatedAliasPropertyProvidedByEnclosingScope)
					.filter(isRequiredByChild),
			)
		onlyIfAvailableAliasFulfillingProperty = nil
		uncreatedAliasPropertyProvidedByEnclosingScope = nil
		let onlyIfAvailableUnwrappedReceivedPropertiesIncludingRequired = Set(
			propertiesToGenerate.flatMap { propertyToGenerate in
				propertyToGenerate.onlyIfAvailableUnwrappedReceivedProperties
					.subtracting(propertiesToDeclare)
					.subtracting(forwardedProperties)
			},
		)
		.union(
			instantiable
				.dependencies
				.compactMap {
					switch $0.source {
					case .instantiated, .forwarded:
						nil
					case let .received(onlyIfAvailable):
						if onlyIfAvailable {
							$0.property.asUnwrappedProperty
						} else {
							nil
						}
					case let .aliased(fulfillingProperty, _, onlyIfAvailable):
						// Skip locally-declared and forwarded fulfilling properties —
						// the alias binds to the local, not to an ancestor.
						if onlyIfAvailable, !propertiesToDeclare.contains(fulfillingProperty), !forwardedProperties.contains(fulfillingProperty) {
							fulfillingProperty.asUnwrappedProperty
						} else {
							nil
						}
					}
				},
		)
		// A property some receiver requires is required, even where others receive
		// it only if available. Few subtrees receive anything only if available, so the
		// required properties are unwrapped only for those that do.
		onlyIfAvailableUnwrappedReceivedProperties = onlyIfAvailableUnwrappedReceivedPropertiesIncludingRequired.isEmpty
			? onlyIfAvailableUnwrappedReceivedPropertiesIncludingRequired
			: onlyIfAvailableUnwrappedReceivedPropertiesIncludingRequired.subtracting(requiredReceivedProperties.map(\.asUnwrappedProperty))
	}

	init(
		property: Property,
		fulfillingProperty: Property,
		fulfillingPropertyIsLazilyInstantiatedInstance: Bool,
		unavailableOptionalProperties: Set<Property>,
		erasedToConcreteExistential: Bool,
		onlyIfAvailable: Bool,
		isProvidedByEnclosingScope: Bool,
		declarationReference: AliasDeclarationReferences.Reference?,
	) {
		scopeData = .alias(
			property: property,
			fulfillingProperty: fulfillingProperty,
			erasedToConcreteExistential: erasedToConcreteExistential,
			onlyIfAvailable: onlyIfAvailable,
			declarationReference: declarationReference,
		)
		receivedProperties = [fulfillingProperty]
		if onlyIfAvailable {
			requiredReceivedProperties = []
			unwrappedOptionalRequiredReceivedProperties = []
			onlyIfAvailableUnwrappedReceivedProperties = [fulfillingProperty.asUnwrappedProperty]
			onlyIfAvailableDependencies = [OnlyIfAvailableDependency(unwrappedFulfillingProperty: fulfillingProperty.asUnwrappedProperty, unavailableProperties: [fulfillingProperty])]
		} else {
			requiredReceivedProperties = [fulfillingProperty]
			unwrappedOptionalRequiredReceivedProperties = fulfillingProperty.typeDescription.isOptional ? [fulfillingProperty.asUnwrappedProperty] : []
			onlyIfAvailableUnwrappedReceivedProperties = []
			onlyIfAvailableDependencies = []
		}
		onlyIfAvailableAliasFulfillingProperty = onlyIfAvailable && !isProvidedByEnclosingScope ? fulfillingProperty : nil
		uncreatedAliasPropertyProvidedByEnclosingScope = onlyIfAvailable
			&& isProvidedByEnclosingScope
			&& unavailableOptionalProperties.contains(fulfillingProperty)
			? property
			: nil
		requiredOnlyIfAvailableAliasProperties = []
		requiredAliasFulfillingProperties = []
		cycleClosingProperties = []
		isReferencedByCycleClosingScope = false
		declaresBuilderFunction = false
		childrenTakePartInCycle = false
		description = property.asSource
		propertiesToGenerate = []
		propertiesToDeclare = []
		self.unavailableOptionalProperties = unavailableOptionalProperties
		lazilyInstantiatedInstanceProperties = []
		self.fulfillingPropertyIsLazilyInstantiatedInstance = fulfillingPropertyIsLazilyInstantiatedInstance
		declaredLazilyInstantiatedInstanceProperty = property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding
		self.property = property
		aliasPropertyIsProvidedByEnclosingScope = isProvidedByEnclosingScope
	}

	// MARK: CustomStringConvertible

	let description: String

	// MARK: Internal

	/// Properties that we require in order to satisfy our (and our children's) dependencies.
	/// Used both to order child generation (dependencies before dependents) and by mock
	/// generation to surface dependencies the tree does not itself provide.
	let receivedProperties: Set<Property>

	/// Whether a scope that declares `declaredProperties` and forwards `forwardedProperties` provides
	/// `property` to the scopes beneath it, which then do not receive it from the scope's ancestors:
	/// the scope declares or forwards the property itself or, for an optional property, its unwrapped
	/// form (a declared form handles a non-optional version promoted to satisfy both required and
	/// onlyIfAvailable receivers; a forwarded `x: X` fulfills an `x: X?` beneath it). A scope declares a
	/// lazily instantiated property together with the property that receives its instance by value,
	/// and forwards it together with that property too.
	private static func provides(
		_ property: Property,
		declaredProperties: Set<Property>,
		forwardedProperties: Set<Property>,
	) -> Bool {
		declaredProperties.contains(property)
			|| forwardedProperties.contains(property)
			|| (property.typeDescription.isOptional
				&& (declaredProperties.contains(property.asUnwrappedProperty) || forwardedProperties.contains(property.asUnwrappedProperty)))
	}

	/// Generates the code of this scope as the root of what is generated, with nothing
	/// generated before it.
	func generateCode(
		codeGeneration: CodeGeneration = .dependencyTree,
	) async throws -> String {
		try await generateCode(
			codeGeneration: codeGeneration,
			unavailableProperties: unavailableProperties(
				isGeneratedBefore: { _ in false },
				propertiesGeneratedLater: [],
			),
			propertiesGeneratedLater: [],
			builderFunctionNames: BuilderFunctionNames(),
			leadingWhitespace: "",
		)
	}

	/// - Parameters:
	///   - unavailableProperties: This scope's `unavailableProperties`, given what an
	///     enclosing scope generates before it.
	///   - propertiesGeneratedLater: Unwrapped properties that this subtree
	///     receives `onlyIfAvailable` and that an enclosing scope declares but does not
	///     generate before this code — it generates them after this code (see
	///     `orderedPropertiesToGenerate`), or they are `onlyIfAvailable` aliases it does
	///     not create — so they are unavailable here. Restricting it to this subtree's
	///     `onlyIfAvailable` receives also drops a property a scope in this subtree
	///     declares itself, since that declaration fulfills the receives beneath it.
	///   - builderFunctionNames: The names this scope's code refers to builder functions by
	///     (see `builderFunctionNames(for:enclosingFunctionNames:)`).
	private func generateCode(
		codeGeneration: CodeGeneration,
		unavailableProperties: Set<Property>,
		propertiesGeneratedLater: Set<Property>,
		builderFunctionNames: BuilderFunctionNames,
		leadingWhitespace: String,
	) async throws -> String {
		let generatedCode: String
		// Mock code is not cached — the context varies per call site.
		// Dependency tree code is cached by the properties that are unavailable.
		switch codeGeneration {
		case .dependencyTree:
			let cacheKey = UnavailablePropertiesCacheKey(
				unavailableProperties: unavailableProperties,
				propertiesGeneratedLater: propertiesGeneratedLater,
				builderFunctionNames: builderFunctionNames,
			)
			if let generateCodeTask = unavailablePropertiesToGenerateCodeTask[cacheKey] {
				generatedCode = try await generateCodeTask.value
			} else {
				let generateCodeTask = Task {
					try await generatePropertyCode(
						codeGeneration: .dependencyTree,
						unavailableProperties: unavailableProperties,
						propertiesGeneratedLater: propertiesGeneratedLater,
						builderFunctionNames: builderFunctionNames,
					)
				}
				unavailablePropertiesToGenerateCodeTask[cacheKey] = generateCodeTask
				generatedCode = try await generateCodeTask.value
			}
		case .mock:
			generatedCode = try await generatePropertyCode(
				codeGeneration: codeGeneration,
				unavailableProperties: unavailableProperties,
				propertiesGeneratedLater: propertiesGeneratedLater,
				builderFunctionNames: builderFunctionNames,
			)
		}
		if leadingWhitespace.isEmpty {
			return generatedCode
		} else {
			return generatedCode
				.split(separator: "\n")
				.map { leadingWhitespace + $0 }
				.joined(separator: "\n")
		}
	}

	func generateDOT() async throws -> String {
		let orderedPropertiesToGenerate = orderedPropertiesToGenerate
		let instantiatedProperties = orderedPropertiesToGenerate.map(\.scopeData.asDOTNode)
		var childDOTs = [String]()
		for orderedPropertyToGenerate in orderedPropertiesToGenerate {
			let childDOT = try await orderedPropertyToGenerate.generateDOT()
			if !childDOT.isEmpty {
				childDOTs.append(childDOT)
			}
		}

		let root = scopeData.asDOTNode
		let forwardedProperties = scopeData.forwardedProperties.sorted().map { "\"\($0.asSource)\"" }
		return ((instantiatedProperties + forwardedProperties).map {
			"    \(root) -- \($0)"
		} + childDOTs).joined(separator: "\n")
	}

	// MARK: Private

	private enum ScopeData {
		case root(instantiable: Instantiable)
		case property(
			instantiable: Instantiable,
			property: Property,
			forwardedProperties: Set<Property>,
			erasedToConcreteExistential: Bool,
			isPropertyCycle: Bool,
		)
		case alias(
			property: Property,
			fulfillingProperty: Property,
			erasedToConcreteExistential: Bool,
			onlyIfAvailable: Bool,
			declarationReference: AliasDeclarationReferences.Reference?,
		)

		var forwardedProperties: Set<Property> {
			switch self {
			case let .property(_, _, forwardedProperties, _, _):
				forwardedProperties
			case .root, .alias:
				[]
			}
		}

		var asDOTNode: String {
			switch self {
			case let .root(instantiable):
				instantiable.concreteInstantiable.asSource
			case let .property(_, property, _, _, _):
				"\"\(property.asSource)\""
			case let .alias(property, fulfillingProperty, _, _, _):
				"\"\(property.asSource) <- \(fulfillingProperty.asSource)\""
			}
		}
	}

	/// The code generation mode.
	enum CodeGeneration {
		case dependencyTree
		case mock(MockContext)
	}

	/// Context for mock code generation, consumed by the mock root when emitting the
	/// `mock()` method and its conditional-compilation wrapper.
	struct MockContext {
		/// The conditional compilation flag for wrapping mock output (e.g. "DEBUG").
		let mockConditionalCompilation: String?
		/// Maps types with hand-written mock methods to their mock method name (e.g. "mock" or a custom name).
		/// Used to provide default values for forwarded dependencies whose type has a hand-written mock.
		let forwardedParameterMockDefaults: [TypeDescription: String]
		/// Globally-computed feedback arc set (see
		/// `DependencyTreeGenerator.computeCycleEdges`). Alphabetical-DFS
		/// selection makes every root walking the same graph agree on which
		/// back-edges are pruned — required because shared
		/// `SafeDIMockConfiguration` structs are emitted once per type and
		/// must have a consistent shape regardless of which root is being
		/// generated. Consumed by both struct generation and override-path
		/// navigation inside `mock()` bodies.
		///
		/// Contrast with `MockParameterNode.isPropertyCycle`, which is a
		/// per-root syntactic flag and differs between roots for the same
		/// underlying cycle.
		let cycleEdges: Set<CycleEdge>
	}

	private let scopeData: ScopeData
	/// The received properties that some receiver in this subtree requires — a `@Received`
	/// dependency, or the fulfilling property of an aliased one, that is not `onlyIfAvailable`.
	private let requiredReceivedProperties: Set<Property>
	/// The unwrapped forms of the optional `requiredReceivedProperties`, which a sibling of the
	/// non-optional form fulfills. Few receives are both required and optional, so this stays small.
	private let unwrappedOptionalRequiredReceivedProperties: Set<Property>
	/// Unwrapped versions of the received properties that every receiver in this subtree receives
	/// `@Received(onlyIfAvailable: true)`, directly or through an alias. A property some receiver
	/// requires is excluded: it must be built before this subtree, and a mock must be given it.
	/// Used to order children and by mock generation to identify dependencies that should become
	/// optional mock parameters (no guaranteed default).
	let onlyIfAvailableUnwrappedReceivedProperties: Set<Property>
	/// For an `@Received(onlyIfAvailable: true)` alias whose property no enclosing scope provides,
	/// the alias's fulfilling property; `nil` for every other scope. A receiver that requires such
	/// an alias can be handed it only if the alias is created.
	private let onlyIfAvailableAliasFulfillingProperty: Property?
	/// For an `@Received(onlyIfAvailable: true)` alias that is never created, because its fulfilling
	/// property is unavailable wherever the alias is built, and whose property an enclosing scope
	/// provides, the alias's property; `nil` for every other scope. A receiver of the property
	/// resolves to the enclosing scope's property, which must be built before the receiver.
	private let uncreatedAliasPropertyProvidedByEnclosingScope: Property?
	/// The `onlyIfAvailable` aliases among this scope's children that a receiver in this scope's
	/// subtree requires. Each is built after its fulfilling property, as a required alias would be.
	private let requiredOnlyIfAvailableAliasProperties: Set<Property>
	/// The fulfilling properties of the `onlyIfAvailable` aliases in this subtree that a receiver
	/// requires, which this subtree receives from an ancestor. This subtree is built after them,
	/// although it receives them only if available. Unlike `requiredReceivedProperties`, these do
	/// not make a mock parameter required: a mock binds such an alias to the optional parameter.
	private let requiredAliasFulfillingProperties: Set<Property>
	/// The properties of the cycle-closing scopes in this subtree (see `isPropertyCycle`) whose cycle
	/// closes on a scope enclosing this one. A cycle-closing scope declares no builder function: it
	/// refers by name to the builder function of the enclosing scope with its property, so no builder
	/// function declared between the two may share that name (see `builderFunctionNames`).
	private let cycleClosingProperties: Set<Property>
	/// Whether a cycle-closing scope in this subtree refers to this scope's builder function.
	private let isReferencedByCycleClosingScope: Bool
	/// Whether this scope may declare a builder function in its parent's body: it is a property's
	/// scope that is not a cycle-closing scope.
	private let declaresBuilderFunction: Bool
	/// Whether a child's subtree closes a cycle on a scope enclosing the child, or a child is the scope
	/// a cycle beneath it closes on. Only then can this scope's body need `builderFunctionNames` to
	/// rename a builder function or to refer to one by a name other than `functionName(toBuild:)`.
	private let childrenTakePartInCycle: Bool
	/// Received properties that are optional and not created by a parent.
	private let unavailableOptionalProperties: Set<Property>
	/// The `onlyIfAvailable` dependencies of this scope: for a type, those its declaration receives,
	/// directly or through an alias; for an `onlyIfAvailable` alias, the alias itself.
	private let onlyIfAvailableDependencies: [OnlyIfAvailableDependency]

	/// A dependency received only if available, which is passed `nil` when an enclosing scope generates
	/// the property that fulfills it after this scope.
	private struct OnlyIfAvailableDependency {
		/// The unwrapped form of the property that fulfills the dependency.
		let unwrappedFulfillingProperty: Property
		/// The properties that are unavailable when the fulfilling property is: the fulfilling property
		/// and, for an aliased dependency of a type, the alias, matching how `Scope.createScopeGenerator`
		/// marks a dependency no ancestor provides.
		let unavailableProperties: [Property]
	}

	/// Properties that will be generated as `let` constants.
	private let propertiesToGenerate: [ScopeGenerator]
	/// Properties that this scope declares as a `let` constant.
	private let propertiesToDeclare: Set<Property>
	/// The received properties that are in scope only as the instance of a `LazilyInstantiated` property created
	/// further up the tree. Passing one to this scope’s initializer reads that instance, which instantiates it.
	private let lazilyInstantiatedInstanceProperties: Set<Property>
	/// Whether the property an alias renames is in scope only as the instance of a `LazilyInstantiated` property.
	private let fulfillingPropertyIsLazilyInstantiatedInstance: Bool
	/// The by-value property with which this scope’s siblings and their subtrees receive the instance of the
	/// lazily instantiated property this scope declares. `nil` when it declares none.
	private let declaredLazilyInstantiatedInstanceProperty: Property?
	/// For an alias, whether a scope enclosing the alias's scope provides the alias's
	/// property too. When the alias is not created, a receiver of the property beneath
	/// it then resolves to that enclosing property, so the alias does not make the
	/// property unavailable. `false` for every other scope.
	private let aliasPropertyIsProvidedByEnclosingScope: Bool
	private let property: Property?

	private struct UnavailablePropertiesCacheKey: Hashable {
		let unavailableProperties: Set<Property>
		let propertiesGeneratedLater: Set<Property>
		let builderFunctionNames: BuilderFunctionNames
	}

	private var unavailablePropertiesToGenerateCodeTask = [UnavailablePropertiesCacheKey: Task<String, Error>]()
	/// The task that builds a mock root's parameter tree. Collecting configuration types, collecting
	/// sendable configuration type names, and generating the mock each read the same tree.
	private var rootMockParameterTreeTask: Task<[MockTreeItem], Never>?

	/// The mock parameter tree of this scope as a mock root, built once.
	private var rootMockParameterTree: [MockTreeItem] {
		get async {
			if let rootMockParameterTreeTask {
				return await rootMockParameterTreeTask.value
			} else {
				let rootMockParameterTreeTask = Task { await collectMockParameterTree() }
				self.rootMockParameterTreeTask = rootMockParameterTreeTask
				return await rootMockParameterTreeTask.value
			}
		}
	}

	/// The children of this scope in the order their code is emitted: every child
	/// follows the siblings it depends on.
	///
	/// A child depends on a sibling when the child's subtree receives the sibling.
	/// A required receive must be honored, and the subtree's receive is required when
	/// any receiver in it requires the sibling, or requires an `onlyIfAvailable` alias
	/// the sibling fulfills (see `requiredAliasFulfillingProperties`). A `@Received(onlyIfAvailable: true)`
	/// receive is honored only when it does not close a cycle among the siblings —
	/// e.g. when `b`'s subtree receives `c` only if available but `c` receives `b`,
	/// `c` cannot be built before `b`. A child whose `onlyIfAvailable` receive is
	/// not honored is ordered before that sibling, and its subtree is generated with
	/// the sibling unavailable (see `propertiesGeneratedLater`), exactly as when no
	/// ancestor provides it. Receives are considered in sibling order, so the result
	/// is deterministic, and it matches a plain topological order whenever every
	/// receive can be honored.
	private lazy var orderedPropertiesToGenerate: [ScopeGenerator] = {
		// A property can be listed more than once — a mock root promotes a received
		// property that a promoted scope receives even when the root already
		// instantiates it. Only the first child for each property is generated.
		// A lazily instantiated sibling is also received by value, as the instance it creates.
		var siblings = [(property: Property, instanceProperty: Property?, index: Int)]()
		var listedProperties = Set<Property>()
		for (index, scope) in propertiesToGenerate.enumerated() {
			if let property = scope.property, listedProperties.insert(property).inserted {
				siblings.append((property, scope.declaredLazilyInstantiatedInstanceProperty, index))
			}
		}
		// Required receives first: they are always honored. A required property whose unwrapped form is
		// the sibling's is the sibling's own non-optional property, which the first test finds, since
		// a required property is never received only if available, or an optional one, which
		// `unwrappedOptionalRequiredReceivedProperties` holds unwrapped.
		// Each child's properties are looked up among the siblings rather than every sibling tested
		// against each child, so a mock root with many children does not pay for every pair.
		var siblingIndexByProperty = [Property: Int]()
		for sibling in siblings {
			siblingIndexByProperty[sibling.property] = sibling.index
		}
		// A lazily instantiated sibling is also received by value, as the instance it creates, unless
		// another sibling declares that property itself.
		for case let (instanceProperty?, index) in siblings.lazy.map({ ($0.instanceProperty, $0.index) })
			where siblingIndexByProperty[instanceProperty] == nil
		{
			siblingIndexByProperty[instanceProperty] = index
		}
		var siblingDependencies = propertiesToGenerate.map { scope in
			var dependencies = Set<Int>()
			func isRequiredReceive(_ property: Property) -> Bool {
				!scope.onlyIfAvailableUnwrappedReceivedProperties.contains(property.asUnwrappedProperty)
			}
			// A subtree can receive far more properties than this scope has children, or far fewer.
			if scope.receivedProperties.count < siblings.count {
				for property in scope.receivedProperties where isRequiredReceive(property) {
					if let siblingIndex = siblingIndexByProperty[property] {
						dependencies.insert(siblingIndex)
					}
				}
			} else {
				func isReceivedAndRequired(_ property: Property) -> Bool {
					scope.receivedProperties.contains(property) && isRequiredReceive(property)
				}
				for sibling in siblings
					where isReceivedAndRequired(sibling.property)
					|| sibling.instanceProperty.map({ siblingIndexByProperty[$0] == sibling.index && isReceivedAndRequired($0) }) == true
				{
					dependencies.insert(sibling.index)
				}
			}
			// A required optional property can resolve to a sibling of its non-optional form:
			// in a mock, or through an `onlyIfAvailable` receive of it above the receiver.
			for property in scope.unwrappedOptionalRequiredReceivedProperties {
				if let siblingIndex = siblingIndexByProperty[property] {
					dependencies.insert(siblingIndex)
				}
			}
			// An alias's optional property is provided by a sibling of its non-optional form too.
			for property in scope.requiredAliasFulfillingProperties {
				for fulfillingProperty in [property, property.asUnwrappedProperty] {
					if let siblingIndex = siblingIndexByProperty[fulfillingProperty] {
						dependencies.insert(siblingIndex)
					}
				}
			}
			return dependencies
		}
		func dependsOn(_ dependencyIndex: Int, from dependentIndex: Int) -> Bool {
			var visitedIndices = Set<Int>()
			var indicesToVisit = [dependentIndex]
			while let index = indicesToVisit.popLast() {
				guard index != dependencyIndex else { return true }
				for siblingIndex in siblingDependencies[index] where visitedIndices.insert(siblingIndex).inserted {
					indicesToVisit.append(siblingIndex)
				}
			}
			return false
		}
		// An `onlyIfAvailable` alias a receiver requires is built after its fulfilling
		// sibling, as a required alias is. A sibling that receives the alias only if
		// available then waits on it only when that does not close a cycle (below).
		for case let (index, aliasProperty?) in propertiesToGenerate.map(\.property).enumerated()
			where requiredOnlyIfAvailableAliasProperties.contains(aliasProperty)
		{
			for sibling in siblings
				where propertiesToGenerate[index].receivedProperties.contains(sibling.property)
				|| sibling.instanceProperty.map(propertiesToGenerate[index].receivedProperties.contains) == true
			{
				siblingDependencies[index].insert(sibling.index)
			}
		}
		// Then each `onlyIfAvailable` receive, in sibling order, unless the sibling it
		// would wait on already waits on the receiver. The `onlyIfAvailable` aliases go
		// first: each waits on the sibling that fulfills it, so it is created once that
		// sibling is built, and a sibling whose tree receives the alias only if available
		// is then generated with the alias unavailable, as it is still being built.
		for considersAliases in [true, false] {
			for (index, scope) in propertiesToGenerate.enumerated()
				where (scope.onlyIfAvailableAliasFulfillingProperty != nil) == considersAliases
				&& !scope.onlyIfAvailableUnwrappedReceivedProperties.isEmpty
			{
				for sibling in siblings
					where (
						scope.onlyIfAvailableUnwrappedReceivedProperties.contains(sibling.property.asUnwrappedProperty)
							|| sibling.instanceProperty.map(scope.onlyIfAvailableUnwrappedReceivedProperties.contains) == true
					)
					&& !dependsOn(index, from: sibling.index)
				{
					siblingDependencies[index].insert(sibling.index)
				}
			}
		}

		var orderedPropertiesToGenerate = [ScopeGenerator]()
		var unfulfilledIndices = Set(siblings.map(\.index))
		func fulfill(_ index: Int) {
			// Mark as fulfilled before recursing to prevent cycles.
			guard unfulfilledIndices.remove(index) != nil else { return }
			// Fulfill the scopes we depend upon.
			for siblingIndex in siblingDependencies[index].sorted() {
				fulfill(siblingIndex)
			}
			orderedPropertiesToGenerate.append(propertiesToGenerate[index])
		}
		for index in propertiesToGenerate.indices {
			fulfill(index)
		}
		return orderedPropertiesToGenerate
	}()

	/// The index in `orderedPropertiesToGenerate` of the last child declaring each
	/// unwrapped property.
	private lazy var orderedIndexByUnwrappedProperty: [Property: Int] = orderedPropertiesToGenerate
		.enumerated()
		.reduce(into: [Property: Int]()) { partialResult, indexAndScope in
			if let property = indexAndScope.element.property {
				partialResult[property.asUnwrappedProperty] = indexAndScope.offset
				// A lazily instantiated property is also received by value, as the instance it creates.
				if let instanceProperty = indexAndScope.element.declaredLazilyInstantiatedInstanceProperty {
					partialResult[instanceProperty] = indexAndScope.offset
				}
			}
		}

	/// The properties `child`, at `index` in `orderedPropertiesToGenerate`, receives
	/// `onlyIfAvailable` but must treat as unavailable: those this scope's ancestors
	/// do not generate before this scope (`propertiesNotGeneratedBefore`) and those of
	/// the siblings generated after it. All are unwrapped, so they match a receive of
	/// `x: X?`.
	private func propertiesGeneratedLater(
		thanChildAt index: Int,
		receivedOnlyIfAvailableBy child: ScopeGenerator,
		propertiesNotGeneratedBefore: Set<Property>,
	) -> Set<Property> {
		child.onlyIfAvailableUnwrappedReceivedProperties.filter { property in
			if propertiesNotGeneratedBefore.contains(property) {
				true
			} else if let orderedIndex = orderedIndexByUnwrappedProperty[property] {
				orderedIndex > index
			} else {
				false
			}
		}
	}

	/// The index in `orderedPropertiesToGenerate` of the first child declaring each property.
	private lazy var firstOrderedIndexByProperty: [Property: Int] = orderedPropertiesToGenerate
		.enumerated()
		.reduce(into: [Property: Int]()) { partialResult, indexAndScope in
			if let property = indexAndScope.element.property, partialResult[property] == nil {
				partialResult[property] = indexAndScope.offset
			}
		}

	/// A child in `orderedPropertiesToGenerate`, with what it is generated with.
	private struct OrderedChild {
		let generator: ScopeGenerator
		/// The child's `unavailableProperties`, given the properties this scope generates before it.
		let unavailableProperties: Set<Property>
		/// The `propertiesGeneratedLater` to generate the child with (see `generateCode`).
		let propertiesGeneratedLater: Set<Property>
	}

	/// The children in `orderedPropertiesToGenerate`, each with its `unavailableProperties`
	/// given the properties this scope generates before it, and the `propertiesGeneratedLater`
	/// to generate it with (see `generateCode`). An `onlyIfAvailable` alias that is not created is
	/// unavailable to the children after it, exactly like a property generated later,
	/// and does not count as generated before them, unless a scope enclosing this one
	/// provides the same property: the children then resolve to that property. An
	/// enclosing provider that is itself unavailable here already arrives in
	/// `propertiesGeneratedLater`.
	private func orderedChildren(
		propertiesGeneratedLater: Set<Property>,
	) -> [OrderedChild] {
		var propertiesNotGeneratedBefore = propertiesGeneratedLater
		var uncreatedAliasProperties = Set<Property>()
		var orderedChildren = [OrderedChild]()
		for (index, childGenerator) in orderedPropertiesToGenerate.enumerated() {
			let childPropertiesGeneratedLater = self.propertiesGeneratedLater(
				thanChildAt: index,
				receivedOnlyIfAvailableBy: childGenerator,
				propertiesNotGeneratedBefore: propertiesNotGeneratedBefore,
			)
			// A property is generated before the child when a child ordered before it declares the property,
			// unless that child is an alias that is not created.
			let childUnavailableProperties = childGenerator.unavailableProperties(
				isGeneratedBefore: { property in
					firstOrderedIndexByProperty[property].map { $0 < index } == true && !uncreatedAliasProperties.contains(property)
				},
				propertiesGeneratedLater: childPropertiesGeneratedLater,
			)
			orderedChildren.append(OrderedChild(
				generator: childGenerator,
				unavailableProperties: childUnavailableProperties,
				propertiesGeneratedLater: childPropertiesGeneratedLater,
			))
			if !childGenerator.aliasPropertyIsProvidedByEnclosingScope,
			   let uncreatedAliasProperty = childGenerator.uncreatedAliasProperty(unavailableProperties: childUnavailableProperties)
			{
				uncreatedAliasProperties.insert(uncreatedAliasProperty)
				propertiesNotGeneratedBefore.insert(uncreatedAliasProperty.asUnwrappedProperty)
			}
		}
		return orderedChildren
	}

	/// The dependencies this scope's construction is passed `nil` for, and, for an
	/// alias, the fulfilling property whose absence means the alias is not created:
	/// the `onlyIfAvailable` dependencies `Scope.createScopeGenerator` found
	/// unavailable that no sibling generated before this scope provides, and those
	/// an enclosing scope does not generate before this scope.
	/// - Parameter isGeneratedBefore: Whether a sibling generated before this scope declares a property.
	nonisolated private func unavailableProperties(
		isGeneratedBefore: (Property) -> Bool,
		propertiesGeneratedLater: Set<Property>,
	) -> Set<Property> {
		let unavailableOptionalPropertiesNotGeneratedBefore = unavailableOptionalProperties
			.filter {
				!(isGeneratedBefore($0) || isGeneratedBefore($0.asUnwrappedProperty))
			}
		// Nearly every scope is generated with no properties generated later.
		return propertiesGeneratedLater.isEmpty
			? unavailableOptionalPropertiesNotGeneratedBefore
			: unavailableOptionalPropertiesNotGeneratedBefore.union(onlyIfAvailableDependencies(fulfilledByPropertiesGeneratedLater: propertiesGeneratedLater))
	}

	/// The alias this scope declares when it is an `onlyIfAvailable` alias that is not
	/// created because its fulfilling property is among `unavailableProperties`, and
	/// `nil` otherwise.
	nonisolated private func uncreatedAliasProperty(unavailableProperties: Set<Property>) -> Property? {
		switch scopeData {
		case let .alias(property, fulfillingProperty, _, onlyIfAvailable, _):
			if onlyIfAvailable, unavailableProperties.contains(fulfillingProperty) {
				property
			} else {
				nil
			}
		case .root, .property:
			nil
		}
	}

	/// The properties of this scope's `onlyIfAvailableDependencies` that are unavailable because an
	/// ancestor generates the properties fulfilling them after this scope.
	nonisolated private func onlyIfAvailableDependencies(
		fulfilledByPropertiesGeneratedLater propertiesGeneratedLater: Set<Property>,
	) -> Set<Property> {
		var unavailableProperties = Set<Property>()
		for onlyIfAvailableDependency in onlyIfAvailableDependencies
			where propertiesGeneratedLater.contains(onlyIfAvailableDependency.unwrappedFulfillingProperty)
		{
			unavailableProperties.formUnion(onlyIfAvailableDependency.unavailableProperties)
		}
		return unavailableProperties
	}

	/// - Parameter enclosingFunctionNames: This scope's `BuilderFunctionNames.enclosingFunctionNames`.
	private func generateProperties(
		codeGeneration: CodeGeneration = .dependencyTree,
		propertiesGeneratedLater: Set<Property>,
		enclosingFunctionNames: [Property: String],
		leadingMemberWhitespace: String,
	) async throws -> [String] {
		let orderedChildren = orderedChildren(propertiesGeneratedLater: propertiesGeneratedLater)
		// Nearly every body holds no scope of a cycle, and its children keep their names. Every child
		// is a property's scope, so each has a candidate.
		let childBuilderFunctionNames = childrenTakePartInCycle
			? Self.builderFunctionNames(
				for: orderedChildren.compactMap(\.generator.builderFunctionCandidate),
				enclosingFunctionNames: enclosingFunctionNames,
			)
			: nil
		var generatedProperties = [String]()
		for (index, child) in orderedChildren.enumerated() {
			try await generatedProperties.append(
				child.generator.generateCode(
					codeGeneration: codeGeneration,
					unavailableProperties: child.unavailableProperties,
					propertiesGeneratedLater: child.propertiesGeneratedLater,
					builderFunctionNames: childBuilderFunctionNames?[index] ?? BuilderFunctionNames(),
					leadingWhitespace: leadingMemberWhitespace,
				),
			)
		}
		return generatedProperties
	}

	private static func functionName(toBuild property: Property) -> String {
		functionName(toBuildPropertyNamed: property.label)
	}

	/// The name of the builder function for a property bound as `name`, which in a mock is the
	/// property's sibling-disambiguated label.
	private static func functionName(toBuildPropertyNamed name: String) -> String {
		"__safeDI_\(name)"
	}

	/// The names generated code refers to builder functions by, where they differ from `functionName(toBuild:)`.
	private struct BuilderFunctionNames: Hashable {
		/// The name of the scope's own builder function, or `nil` when it has the name it would have
		/// without renaming: `functionName(toBuild:)`, or in a mock its sibling-disambiguated name.
		var functionName: String?
		/// The names of the builder functions of enclosing scopes that a cycle-closing scope in the
		/// scope's subtree refers to, keyed by property, for those not named `functionName(toBuild:)`.
		var enclosingFunctionNames = [Property: String]()
	}

	/// A child scope that one generated body holds, as builder function naming sees it.
	private struct BuilderFunctionCandidate {
		/// The property the child scope builds.
		let property: Property
		/// The name of the child's builder function, unless it must be renamed, or `nil` when it is
		/// `functionName(toBuild:)`.
		let name: String?
		/// Whether the child may declare a builder function in the body: it is a property's scope
		/// that is not a cycle-closing scope. Renaming a child that declares none, such as a
		/// constant with nothing to build first, changes nothing it generates.
		let declaresFunction: Bool
		/// The child's `cycleClosingProperties`.
		let cycleClosingProperties: Set<Property>
		/// The child's `isReferencedByCycleClosingScope`.
		let isReferencedByCycleClosingScope: Bool
	}

	/// The builder function names to generate each of `children`, the child scopes one generated
	/// body holds, with.
	///
	/// A cycle-closing scope declares no builder function: it refers by name to the builder function
	/// of the enclosing scope with its property. Swift resolves that name to the innermost function of
	/// that name in scope, and a local function is in scope throughout the body that declares it, so a
	/// builder function declared in any body between the two must not share the name. A child that
	/// declares a function whose name a cycle-closing scope in this body refers to (from
	/// `enclosingFunctionNames`, or else `functionName(toBuild:)`) is therefore renamed
	/// `<name>_<type identifier>`, with the type it builds as sibling disambiguation names it (see
	/// `identifierSafeNames`), and underscores appended until neither another child nor a referenced
	/// function has that name. Every other child keeps its name, so a body with no such clash is
	/// generated as it was before. The names depend only on this body and the functions enclosing it.
	/// Callers skip a body that holds no scope of a cycle (see `childrenTakePartInCycle`), whose children
	/// all keep their names.
	///
	/// - Parameter enclosingFunctionNames: The `BuilderFunctionNames.enclosingFunctionNames` of the
	///   scope whose body holds `children`.
	private static func builderFunctionNames(
		for children: [BuilderFunctionCandidate],
		enclosingFunctionNames: [Property: String],
	) -> [BuilderFunctionNames] {
		var referencedProperties = Set<Property>()
		for child in children where !child.cycleClosingProperties.isEmpty {
			referencedProperties.formUnion(child.cycleClosingProperties)
		}
		let referencedFunctionNames = Set(referencedProperties.map {
			enclosingFunctionNames[$0, default: functionName(toBuild: $0)]
		})
		let childNames = children.map { $0.name ?? functionName(toBuild: $0.property) }
		let renamedIndices = children.indices.filter {
			children[$0].declaresFunction && referencedFunctionNames.contains(childNames[$0])
		}
		let renamedNames = identifierSafeNames(
			for: renamedIndices.map { index in
				let typeDescription = children[index].property.typeDescription
				return (
					label: childNames[index],
					suffixTypes: [typeDescription.asInstantiatedType.simplified, typeDescription.asInstantiatedType, typeDescription],
				)
			},
			reservedNames: referencedFunctionNames.union(childNames),
		)
		let renamedNameByIndex = Dictionary(uniqueKeysWithValues: zip(renamedIndices, renamedNames))
		return children.indices.map { index in
			let child = children[index]
			let renamedName = renamedNameByIndex[index]
			// A cycle-closing scope beneath the child refers to the functions enclosing it, and
			// to the child's own function when it is the one the cycle closes on.
			var childEnclosingFunctionNames = child.cycleClosingProperties.isEmpty ? [:] : enclosingFunctionNames
			let childFunctionName = renamedName ?? childNames[index]
			if child.isReferencedByCycleClosingScope, childFunctionName != functionName(toBuild: child.property) {
				childEnclosingFunctionNames[child.property] = childFunctionName
			}
			return BuilderFunctionNames(
				functionName: renamedName,
				enclosingFunctionNames: childEnclosingFunctionNames,
			)
		}
	}

	/// This scope as a child that a generated body holds, for `builderFunctionNames`, or `nil` for a
	/// root, which no body holds.
	nonisolated private var builderFunctionCandidate: BuilderFunctionCandidate? {
		property.map { property in
			BuilderFunctionCandidate(
				property: property,
				name: nil,
				declaresFunction: declaresBuilderFunction,
				cycleClosingProperties: cycleClosingProperties,
				isReferencedByCycleClosingScope: isReferencedByCycleClosingScope,
			)
		}
	}

	private static let standardIndent = "    "

	// MARK: Code Generation

	/// Generates code for this scope. Dependency-tree mode emits the full subtree
	/// recursively. Mock mode only reaches this function for `.root` scopes, which
	/// delegate to `generateMockRootCode`; non-root mock code is produced via
	/// `collectMockParameterTree` + `generateMockBodyBindings` instead.
	private func generatePropertyCode(
		codeGeneration: CodeGeneration,
		unavailableProperties: Set<Property>,
		propertiesGeneratedLater: Set<Property>,
		builderFunctionNames: BuilderFunctionNames,
	) async throws -> String {
		switch scopeData {
		case let .root(instantiable):
			switch codeGeneration {
			case .dependencyTree:
				let argumentList = try instantiable.generateArgumentList()
				if instantiable.dependencies.isEmpty {
					return ""
				} else {
					return try await """
					extension \(instantiable.concreteInstantiable.asSource) {
					    public \(instantiable.declarationType == .classType ? "convenience " : "")init() {
					\(generateProperties(propertiesGeneratedLater: propertiesGeneratedLater, enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames, leadingMemberWhitespace: "        ").joined(separator: "\n"))
					        self.init(\(argumentList))
					    }
					}
					"""
				}
			case let .mock(context):
				return try await generateMockRootCode(
					instantiable: instantiable,
					context: context,
				)
			}
		case let .property(
			instantiable,
			property,
			forwardedProperties,
			erasedToConcreteExistential,
			isPropertyCycle,
		):
			let argumentList = try instantiable.generateArgumentList(
				unavailableProperties: unavailableProperties,
				lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
			)
			let concreteTypeName = instantiable.concreteInstantiable.asSource
			let instantiationDeclaration = if instantiable.declarationType.isExtension {
				"\(concreteTypeName).\(InstantiableVisitor.instantiateMethodName)"
			} else {
				concreteTypeName
			}
			let returnLineSansReturn = "\(instantiationDeclaration)(\(argumentList))"

			let propertyType = property.propertyType
			if propertyType.isErasedInstantiator,
			   let firstForwardedProperty = forwardedProperties.first,
			   let forwardedArgument = property.generics?.first,
			   !(
			   	// The forwarded argument is the same type as our only `@Forwarded` property.
			   	(forwardedProperties.count == 1 && forwardedArgument == firstForwardedProperty.typeDescription)
			   		// The forwarded argument is the same as `InstantiableName.ForwardedProperties`.
			   		|| forwardedArgument == .nested(name: "ForwardedProperties", parentType: instantiable.concreteInstantiable)
			   		// The forwarded argument is the same as the tuple we generated for `InstantiableName.ForwardedProperties`.
			   		|| forwardedArgument == forwardedProperties.asTupleTypeDescription
			   )
			{
				throw GenerationError.erasedInstantiatorGenericDoesNotMatch(
					property: property,
					instantiable: instantiable,
				)
			}

			switch propertyType {
			case .instantiator,
			     .erasedInstantiator,
			     .sendableInstantiator,
			     .sendableErasedInstantiator:
				let forwardedProperties = forwardedProperties.sorted()
				let forwardedPropertiesHaveLabels = forwardedProperties.count > 1
				let forwardedArguments = forwardedProperties
					.map {
						if forwardedPropertiesHaveLabels {
							"\($0.label): $0.\($0.label)"
						} else {
							"\($0.label): $0"
						}
					}
					.joined(separator: ", ")
				let generatedProperties = try await generateProperties(
					codeGeneration: codeGeneration,
					propertiesGeneratedLater: propertiesGeneratedLater,
					enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames,
					leadingMemberWhitespace: Self.standardIndent,
				)
				let functionArguments = if forwardedProperties.isEmpty {
					""
				} else {
					forwardedProperties.initializerFunctionParameters.map(\.description).joined()
				}
				// A cycle-closing scope declares no function: it refers to the enclosing one with its property.
				let functionName = if isPropertyCycle {
					builderFunctionNames.enclosingFunctionNames[property, default: Self.functionName(toBuild: property)]
				} else {
					builderFunctionNames.functionName ?? Self.functionName(toBuild: property)
				}
				let functionDecorator = if propertyType.isSendable {
					"@Sendable "
				} else {
					""
				}
				let functionDeclaration = if isPropertyCycle {
					""
				} else {
					"""
					\(functionDecorator)func \(functionName)(\(functionArguments)) -> \(concreteTypeName) {
					\(generatedProperties.joined(separator: "\n"))
					\(Self.standardIndent)\(generatedProperties.isEmpty ? "" : "return ")\(returnLineSansReturn)
					}

					"""
				}

				let typeDescription = property.typeDescription.asSource
				let unwrappedTypeDescription = property
					.typeDescription
					.unwrapped
					.asSource
				let instantiatedTypeDescription = property
					.typeDescription
					.unwrapped
					.asInstantiatedType
					.asSource
				let propertyDeclaration = if !instantiable.declarationType.isExtension, typeDescription == unwrappedTypeDescription {
					"let \(property.label)"
				} else {
					"let \(property.asSource)"
				}
				let instantiatorInstantiation = if forwardedArguments.isEmpty, !erasedToConcreteExistential {
					"\(unwrappedTypeDescription)(\(functionName))"
				} else if erasedToConcreteExistential {
					"""
					\(unwrappedTypeDescription) {
					\(Self.standardIndent)\(instantiatedTypeDescription)(\(functionName)(\(forwardedArguments)))
					}
					"""
				} else {
					"""
					\(unwrappedTypeDescription) {
					\(Self.standardIndent)\(functionName)(\(forwardedArguments))
					}
					"""
				}

				return """
				\(functionDeclaration)\(propertyDeclaration) = \(instantiatorInstantiation)
				"""
			case .lazilyInstantiated,
			     .sendableLazilyInstantiated:
				// The builder function is the one a constant with children declares. A constant calls it
				// immediately; a lazily instantiated property hands it to its wrapper, which calls it the
				// first time the instance is requested. Dependency cycle validation treats the property
				// as a constant, so it is never the repeated property of a cycle.
				let generatedProperties = try await generateProperties(
					codeGeneration: codeGeneration,
					propertiesGeneratedLater: propertiesGeneratedLater,
					enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames,
					leadingMemberWhitespace: Self.standardIndent,
				)
				let functionName = builderFunctionNames.functionName ?? Self.functionName(toBuild: property)
				let functionDecorator = if propertyType.isSendable {
					"@Sendable "
				} else {
					""
				}
				// The wrapper is always spelled with its generic argument, so the declaration needs no type
				// annotation: an optional property receives the wrapper through optional promotion.
				let unwrappedTypeDescription = property
					.typeDescription
					.unwrapped
					.asSource
				let lazilyInstantiatedInstantiation = if erasedToConcreteExistential {
					"""
					\(unwrappedTypeDescription) {
					\(Self.standardIndent)\(property.typeDescription.asInstantiatedType.asSource)(\(functionName)())
					}
					"""
				} else {
					"\(unwrappedTypeDescription)(\(functionName))"
				}

				return """
				\(functionDecorator)func \(functionName)() -> \(concreteTypeName) {
				\(generatedProperties.joined(separator: "\n"))
				\(Self.standardIndent)\(generatedProperties.isEmpty ? "" : "return ")\(returnLineSansReturn)
				}
				let \(property.label) = \(lazilyInstantiatedInstantiation)
				"""
			case .constant:
				let generatedProperties = try await generateProperties(
					codeGeneration: codeGeneration,
					propertiesGeneratedLater: propertiesGeneratedLater,
					enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames,
					leadingMemberWhitespace: Self.standardIndent,
				)

				let nonEmptyGeneratedProperties = generatedProperties.filter { !$0.isEmpty }
				let hasGeneratedContent = !nonEmptyGeneratedProperties.isEmpty
				let propertyDeclaration = if erasedToConcreteExistential || (
					concreteTypeName == property.typeDescription.asSource
						&& !hasGeneratedContent
						&& !instantiable.declarationType.isExtension
				) {
					"let \(property.label)"
				} else {
					"let \(property.asSource)"
				}

				// Ideally we would be able to use an anonymous closure rather than a named function here.
				// Unfortunately, there's a bug in Swift Concurrency that prevents us from doing this: https://github.com/swiftlang/swift/issues/75003
				let functionName = builderFunctionNames.functionName ?? Self.functionName(toBuild: property)
				let functionDeclaration = if !hasGeneratedContent {
					""
				} else {
					"""
					func \(functionName)() -> \(concreteTypeName) {
					\(nonEmptyGeneratedProperties.joined(separator: "\n"))
					\(Self.standardIndent)return \(returnLineSansReturn)
					}

					"""
				}
				let existentialWrappedReturn = if erasedToConcreteExistential {
					"\(property.typeDescription.asSource)(\(returnLineSansReturn))"
				} else {
					returnLineSansReturn
				}
				let initializer = if !hasGeneratedContent {
					existentialWrappedReturn
				} else if erasedToConcreteExistential {
					"\(property.typeDescription.asSource)(\(functionName)())"
				} else {
					"\(functionName)()"
				}

				return "\(functionDeclaration)\(propertyDeclaration) = \(initializer)\n"
			}
		case let .alias(property, fulfillingProperty, erasedToConcreteExistential, _, declarationReference):
			if uncreatedAliasProperty(unavailableProperties: unavailableProperties) != nil {
				return "// Did not create `\(property.asSource)` because `\(fulfillingProperty.asSource)` is unavailable."
			} else {
				// The production tree binds an available fulfilling dependency as a non-optional value.
				return Self.referencingDeclaration(
					of: Self.aliasDeclaration(
						of: property,
						fulfilledBy: fulfillingPropertyIsLazilyInstantiatedInstance
							? "\(fulfillingProperty.label).\(Dependency.lazilyInstantiatedInstancePropertyName)"
							: fulfillingProperty.label,
						ofType: fulfillingProperty.typeDescription,
						erasedToConcreteExistential: erasedToConcreteExistential,
						fulfillingValueMayBeOptional: false,
					),
					by: declarationReference,
				)
			}
		}
	}

	/// The `let` that binds an alias's `property` to `fulfillingExpression`, a value of
	/// `fulfillingTypeDescription`. When `erasedToConcreteExistential` is set, the fulfilling
	/// value is wrapped in a no-label initializer of the property's type, unwrapped when the
	/// property is optional, as an `@Received(onlyIfAvailable: true)` alias's property must be.
	///
	/// Set `fulfillingValueMayBeOptional` when `fulfillingExpression` may name an optional
	/// binding: a mock binds an `onlyIfAvailable` alias's fulfilling dependency from an
	/// optional override where no enclosing scope provides it, and from a non-optional
	/// value where one does. The wrapper is then mapped over the fulfilling value promoted
	/// to an optional, which compiles either way and binds `nil` when the fulfilling value is `nil`.
	private static func aliasDeclaration(
		of property: Property,
		fulfilledBy fulfillingExpression: String,
		ofType fulfillingTypeDescription: TypeDescription,
		erasedToConcreteExistential: Bool,
		fulfillingValueMayBeOptional: Bool,
	) -> String {
		let existentialTypeSource = property.typeDescription.unwrapped.asSource
		let initializer = if !erasedToConcreteExistential {
			fulfillingExpression
		} else if fulfillingValueMayBeOptional {
			"(\(fulfillingExpression) as \(TypeDescription.optional(fulfillingTypeDescription).asSource)).map { \(existentialTypeSource)($0) }"
		} else {
			"\(existentialTypeSource)(\(fulfillingExpression))"
		}
		return "let \(property.asSource) = \(initializer)"
	}

	/// Points `code`, an alias's assignment, at its `@Received` declaration as `declarationReference` says:
	/// wrapped in `#sourceLocation` directives so that compiler diagnostics for it are reported at the
	/// declaration, or followed by a comment naming the declaration, which the compiler shows in the excerpt
	/// of a diagnostic it reports in the generated file. The trailing bare `#sourceLocation()` restores
	/// reporting against the generated file for the lines that follow.
	///
	/// SafeDI does not validate that an aliased dependency’s declared type can be fulfilled by
	/// the fulfilling dependency’s type; the Swift compiler checks the generated assignment.
	private static func referencingDeclaration(
		of code: String,
		by declarationReference: AliasDeclarationReferences.Reference?,
	) -> String {
		guard let declarationReference else { return code }
		return switch declarationReference {
		case let .sourceLocationDirective(filePath, line):
			"""
			#sourceLocation(file: \(StringLiteralExprSyntax(content: filePath).description), line: \(line))
			\(code)
			#sourceLocation()
			"""
		case let .comment(filePath, line):
			"\(code) // Declared at \(filePath):\(line)"
		}
	}

	// MARK: Mock Root Code Generation

	/// Generates the full mock extension code for a `.root` node in mock mode.
	private func generateMockRootCode(
		instantiable: Instantiable,
		context: MockContext,
	) async throws -> String {
		let typeName = instantiable.concreteInstantiable.asSource
		let mockAttributesPrefix = instantiable.mockAttributes.isEmpty ? "" : "\(instantiable.mockAttributes) "
		let indent = Self.standardIndent
		let bodyIndent = "\(indent)\(indent)"

		// The generated `mock()` method's return type matches the construction
		// call site: if `customMock` returns an additional type (e.g. the type
		// fulfills a protocol and `customMock` returns that protocol), returning
		// `typeName` here would be a type error because `customMock`'s result
		// cannot be downcast implicitly. Use `mockReturnType` for those cases,
		// and fall back to `typeName` when there is no custom mock or the custom
		// mock already returns the concrete type / `Self`.
		let mockMethodReturnType: String = {
			guard let mockReturnType = instantiable.mockReturnType,
			      !instantiable.mockReturnTypeIsCompatible(withPropertyType: instantiable.concreteInstantiable)
			else { return typeName }
			return mockReturnType.asSource
		}()

		// 1. Build the parameter tree.
		let parameterTree = await rootMockParameterTree

		// 2. Identify flat parameters.

		// Forwarded dependencies → flat parameters on mock(). Defaults may be supplied
		// from the construction initializer or from a hand-written mock on the forwarded type.
		let forwardedDependencies = instantiable.dependencies
			.filter { $0.source == .forwarded }
			.sorted { $0.property < $1.property }

		// Root type's own non-dependency defaults (from init or customMock).
		let rootConstructionInitializer: Initializer? = if let mockInitializer = instantiable.mockInitializer {
			mockInitializer
		} else {
			instantiable.initializer
		}
		let dependencyLabels = Set(instantiable.dependencies.map(\.property.label))
		var rootDefaultParameters = [(label: String, typeSource: String, defaultExpression: String)]()
		if let rootConstructionInitializer {
			for argument in rootConstructionInitializer.arguments {
				guard argument.hasDefaultValue,
				      !dependencyLabels.contains(argument.innerLabel),
				      argument.label != "_",
				      let defaultExpression = argument.defaultValueExpression
				else { continue }
				rootDefaultParameters.append((
					label: argument.label,
					typeSource: argument.typeDescription.asFunctionParameter.asSource,
					defaultExpression: defaultExpression,
				))
			}
		}

		// Non-instantiable received dependencies and uncovered @Instantiated dependencies → flat parameters.
		let treePropertyNodes = parameterTree.propertyNodes
		let treePropertyLabels = Set(treePropertyNodes.map(\.propertyLabel))
		let forwardedPropertySet = instantiable.forwardedReceivableProperties
		/// Whether a property the mocked type forwards fulfills a receive of `property`. A forwarded
		/// `x: X` fulfills an `x: X?` too.
		func isFulfilledByForwardedProperty(_ property: Property) -> Bool {
			forwardedPropertySet.contains(property) || forwardedPropertySet.contains(property.asUnwrappedProperty)
		}

		// The lazily instantiated dependencies the tree receives and the mock cannot build. The caller of
		// `mock()` passes the instance of such a dependency, exactly as for one received by value, and the
		// mock wraps it for the types that receive it as `LazilyInstantiated`.
		let lazilyInstantiatedReceivedProperties = receivedProperties
			.filter {
				$0.typeDescription.lazilyInstantiatedInstanceType != nil
					&& !treePropertyLabels.contains($0.label)
					&& !isFulfilledByForwardedProperty($0)
			}
			.sorted()
		// Received properties as the caller of `mock()` provides them: by value.
		let receivedParameterProperties: Set<Property>
		let onlyIfAvailableUnwrappedReceivedParameterProperties: Set<Property>
		if lazilyInstantiatedReceivedProperties.isEmpty {
			receivedParameterProperties = receivedProperties
			onlyIfAvailableUnwrappedReceivedParameterProperties = onlyIfAvailableUnwrappedReceivedProperties
		} else {
			// A `LazilyInstantiated` the mocked type forwards is passed on as it is, so it is not a parameter.
			receivedParameterProperties = Set(
				receivedProperties.lazy
					.filter { !isFulfilledByForwardedProperty($0) }
					.map(\.asValidatedForDependencyCycles),
			)
			// A dependency some receiver requires, as `LazilyInstantiated` or by value, is required.
			onlyIfAvailableUnwrappedReceivedParameterProperties = Set(onlyIfAvailableUnwrappedReceivedProperties.map(\.asValidatedForDependencyCycles))
				.subtracting(requiredReceivedProperties.map(\.asValidatedForDependencyCycles.asUnwrappedProperty))
		}
		// A tree node binds a non-optional value, even when it is promoted for a required `x: X?`.
		/// Whether the tree provides a received property, as a scope provides one to the scopes beneath it
		/// (`provides`). A promoted node also provides the non-optional form of its optional property: a
		/// mock builds it, so it binds a non-optional value even when it is promoted for a required `x: X?`.
		func isProvidedByTree(_ property: Property) -> Bool {
			Self.provides(property, declaredProperties: propertiesToDeclare, forwardedProperties: [])
				|| (!property.typeDescription.isOptional
					&& propertiesToDeclare.contains(Property(label: property.label, typeDescription: .optional(property.typeDescription))))
		}

		let receivedNonOptionalProperties = Set(
			receivedParameterProperties
				.filter { !$0.typeDescription.isOptional },
		)
		var flatReceivedProperties = [Property]()
		var onlyIfAvailableReceivedProperties = [Property]()
		for receivedProperty in receivedParameterProperties.sorted() {
			// A forwarded `x: X` fulfills an `x: X?` too.
			guard !forwardedPropertySet.contains(receivedProperty), !receivedProperty.typeDescription.isOptional
				|| (!receivedNonOptionalProperties.contains(receivedProperty.asUnwrappedProperty) && !forwardedPropertySet.contains(receivedProperty.asUnwrappedProperty))
			else { continue }
			// Optional, defaulting to `nil`, only when every receiver — directly or
			// through an alias, whose fulfilling property is non-optional — receives it
			// `onlyIfAvailable`. A property any receiver requires is a required parameter.
			// A receive of a property the tree provides is handed that node: the mock root's own
			// receive, or an alias's fulfilling property. A tree node with the label and another
			// type does not provide it: the receivers are handed a parameter or an override of
			// their own type, named apart from that node below.
			guard !isProvidedByTree(receivedProperty) else { continue }
			if onlyIfAvailableUnwrappedReceivedParameterProperties.contains(receivedProperty.asUnwrappedProperty) {
				onlyIfAvailableReceivedProperties.append(receivedProperty)
			} else {
				flatReceivedProperties.append(receivedProperty)
			}
		}

		var flatUncoveredParameters = [(label: String, typeSource: String)]()
		// Collect uncovered @Instantiated deps from the root type.
		for dependency in instantiable.dependencies {
			switch dependency.source {
			case .instantiated:
				guard !treePropertyLabels.contains(dependency.property.label) else { continue }
				let sourceType = dependency.property.propertyType.isConstant
					? dependency.property.typeDescription.asInstantiatedType.asFunctionParameter.asSource
					: dependency.property.typeDescription.asFunctionParameter.asSource
				flatUncoveredParameters.append((label: dependency.property.label, typeSource: sourceType))
			case .received, .aliased, .forwarded:
				break
			}
		}
		// Also collect uncovered @Instantiated deps from child types in the tree.
		// When a child has a custom mock method, its @Instantiated deps that aren't
		// in the scope map become builder arguments. These must surface as flat params
		// so the mock body can pass them.
		Self.collectUncoveredDependenciesFromTree(
			treePropertyNodes,
			into: &flatUncoveredParameters,
		)

		// Disambiguate flat received parameter labels when collisions exist.
		// Include onlyIfAvailable labels so flat params with the same label
		// get disambiguated: an onlyIfAvailable override keeps its label over
		// a flat received parameter.
		// Forwarded parameters keep their original labels (must match init signature).
		// A flat received parameter is named apart from the root's tree bindings too: a tree node with
		// its label and another type does not provide it, and the parameter would be hidden by it.
		let treeBindingNames = Self.bindingNames(of: treePropertyNodes, labels: treePropertyLabels)
		let allFlatLabels = forwardedDependencies.map(\.property.label)
			+ rootDefaultParameters.map(\.label)
			+ flatReceivedProperties.map(\.label)
			+ flatUncoveredParameters.map(\.label)
			+ onlyIfAvailableReceivedProperties.map(\.label)
		let collidingFlatLabels = Self.collidingLabels(in: allFlatLabels)
			.union(flatReceivedProperties.lazy.map(\.label).filter(treeBindingNames.contains))
		// Map of (label → (type → disambiguatedLabel)) for flat received
		// parameters whose label collided with another flat parameter. Builder calls
		// for child nodes that would reference the original label must substitute
		// the disambiguated name so the generated code references a real binding.
		let collidingFlatReceivedProperties = flatReceivedProperties.filter { collidingFlatLabels.contains($0.label) }
		let collidingFlatReceivedNames = Self.identifierSafeNames(
			for: collidingFlatReceivedProperties.map {
				(label: $0.label, suffixTypes: [$0.typeDescription.simplified, $0.typeDescription])
			},
			reservedNames: Set(allFlatLabels).union(treeBindingNames),
		)
		var flatParameterDisambiguationMap = [String: [TypeDescription: String]]()
		for (property, disambiguatedLabel) in zip(collidingFlatReceivedProperties, collidingFlatReceivedNames) {
			flatParameterDisambiguationMap[property.label, default: [:]][property.typeDescription] = disambiguatedLabel
		}
		let flatReceivedParameters = flatReceivedProperties.map { property in
			(
				label: flatParameterDisambiguationMap[property.label]?[property.typeDescription] ?? property.label,
				typeSource: property.typeDescription.asFunctionParameter.asSource,
			)
		}
		let onlyIfAvailableOverrides: [OnlyIfAvailableOverride] = if onlyIfAvailableReceivedProperties.isEmpty {
			[]
		} else {
			Self.onlyIfAvailableOverrides(
				for: onlyIfAvailableReceivedProperties,
				namesInMockScope: Set(forwardedDependencies.map(\.property.label))
					.union(rootDefaultParameters.map(\.label))
					.union(flatUncoveredParameters.map(\.label))
					.union(treeBindingNames),
				reservedNames: Set(flatReceivedParameters.map(\.label)),
			)
		}
		// Wrap the instance of each lazily instantiated dependency the mock cannot build, under a name of its
		// own. Types that receive the dependency as `LazilyInstantiated` are passed that name. Rebinding it
		// under the dependency's label where they are built would hide the parameter that holds the instance
		// from the types built there that receive it by value.
		var lazilyInstantiatedBindings = [String]()
		var lazilyInstantiatedBindingNameMap = [String: [TypeDescription: String]]()
		for receivedProperty in lazilyInstantiatedReceivedProperties {
			let lazilyInstantiatedProperty = receivedProperty.asUnwrappedProperty
			let bindingName = "\(receivedProperty.label)_\(lazilyInstantiatedProperty.propertyType.isSendable ? "sendableLazilyInstantiated" : "lazilyInstantiated")"
			if lazilyInstantiatedBindingNameMap[receivedProperty.label]?.values.contains(bindingName) != true {
				let instanceProperty = lazilyInstantiatedProperty.asValidatedForDependencyCycles
				let wrapperTypeSource = lazilyInstantiatedProperty.typeDescription.asSource
				if flatReceivedProperties.contains(instanceProperty) {
					let instanceName = flatParameterDisambiguationMap[instanceProperty.label]?[instanceProperty.typeDescription] ?? instanceProperty.label
					lazilyInstantiatedBindings.append("\(bodyIndent)let \(bindingName) = \(wrapperTypeSource) { \(instanceName) }")
				} else {
					// The instance is an `onlyIfAvailable` override, which may be named apart from its label.
					let instanceName = onlyIfAvailableOverrides.first { $0.receivedProperty.asUnwrappedProperty == instanceProperty }?.name ?? instanceProperty.label
					lazilyInstantiatedBindings.append("\(bodyIndent)let \(bindingName) = \(instanceName).map { instance in \(wrapperTypeSource) { instance } }")
				}
			}
			lazilyInstantiatedBindingNameMap[receivedProperty.label, default: [:]][receivedProperty.typeDescription] = bindingName
		}

		// 3. Simple mock case — no tree, no flat parameters.
		let hasTree = !parameterTree.isEmpty || !onlyIfAvailableOverrides.isEmpty
		// SafeDIOverrides is only needed when there are property children or
		// onlyIfAvailable entries. Alias-only trees emit `let` bindings directly
		// in the mock body and require no override storage.
		let hasOverridableTree = !treePropertyNodes.isEmpty || !onlyIfAvailableOverrides.isEmpty
		let hasFlatParameters = !forwardedDependencies.isEmpty
			|| !rootDefaultParameters.isEmpty
			|| !flatReceivedParameters.isEmpty
			|| !flatUncoveredParameters.isEmpty

		guard hasTree || hasFlatParameters else {
			let argumentList = try instantiable.generateArgumentList(
				unavailableProperties: unavailableOptionalProperties,
				forMockGeneration: true,
			)
			let mockMethodName = instantiable.customMockName ?? InstantiableVisitor.mockMethodName
			let construction = if instantiable.mockInitializer != nil {
				"\(typeName).\(mockMethodName)(\(argumentList))"
			} else if instantiable.declarationType.isExtension {
				"\(typeName).\(InstantiableVisitor.instantiateMethodName)(\(argumentList))"
			} else {
				"\(typeName)(\(argumentList))"
			}
			let code = """
			extension \(typeName) {
			    \(mockAttributesPrefix)static func mock() -> \(mockMethodReturnType) {
			        \(construction)
			    }
			}
			"""
			return wrapInConditionalCompilation(code, mockConditionalCompilation: context.mockConditionalCompilation)
		}

		// 4. Build the mock method.
		var lines = [String]()
		lines.append("extension \(typeName) {")

		if hasOverridableTree {
			lines.append(Self.generateSafeDIOverridesStruct(
				rootChildren: treePropertyNodes,
				onlyIfAvailableOverrides: onlyIfAvailableOverrides,
				indent: indent,
			))
			lines.append("")
		}

		// Build mock() signature.
		// Build a lookup of default values from the construction initializer
		// so forwarded deps with defaults on customMock preserve them.
		let constructionDefaults: [String: String] = {
			guard let rootConstructionInitializer else { return [:] }
			var defaults = [String: String]()
			for argument in rootConstructionInitializer.arguments {
				if let defaultExpression = argument.defaultValueExpression {
					defaults[argument.innerLabel] = defaultExpression
				}
			}
			return defaults
		}()
		var mockParameters = [String]()
		for dependency in forwardedDependencies {
			let typeSource = dependency.property.typeDescription.asFunctionParameter.asSource
			if let defaultExpression = constructionDefaults[dependency.property.label] {
				mockParameters.append("\(bodyIndent)\(dependency.property.label): \(typeSource) = \(defaultExpression)")
			} else if let mockMethodName = context.forwardedParameterMockDefaults[dependency.property.typeDescription] {
				let mockTypeName = dependency.property.typeDescription.asSource
				mockParameters.append("\(bodyIndent)\(dependency.property.label): \(typeSource) = \(mockTypeName).\(mockMethodName)()")
			} else {
				mockParameters.append("\(bodyIndent)\(dependency.property.label): \(typeSource)")
			}
		}
		for rootDefault in rootDefaultParameters {
			mockParameters.append("\(bodyIndent)\(rootDefault.label): \(rootDefault.typeSource) = \(rootDefault.defaultExpression)")
		}
		for flatReceived in flatReceivedParameters {
			mockParameters.append("\(bodyIndent)\(flatReceived.label): \(flatReceived.typeSource)")
		}
		for flatUncovered in flatUncoveredParameters {
			mockParameters.append("\(bodyIndent)\(flatUncovered.label): \(flatUncovered.typeSource)")
		}
		if hasOverridableTree {
			mockParameters.append("\(bodyIndent)safeDIOverrides: SafeDIOverrides = .init()")
		}

		lines.append("\(indent)\(mockAttributesPrefix)static func mock(")
		lines.append(mockParameters.joined(separator: ",\n"))
		lines.append("\(indent)) -> \(mockMethodReturnType) {")

		// Generate mock body.
		// Sibling-disambig map renames local `let` bindings when the root's own
		// `.instantiated` dep label collides with a promoted sibling — the return
		// call must reference the renamed local.
		var siblingDisambiguationMap = [String: [TypeDescription: String]]()
		Self.mergeSiblingDisambiguations(into: &siblingDisambiguationMap, for: treePropertyNodes)
		// `emitReceiverBindings` also needs the flat-received renames so it can
		// rebind disambiguated flat params back to their natural labels at child
		// scopes. The return call must NOT apply flat-received renames: they
		// target a separate mock parameter, and the root's own `.instantiated`
		// dep must reference its own parameter — not the renamed flat-received.
		// An `onlyIfAvailable` override named apart from its label is rebound to the label
		// by its receivers, as a renamed flat parameter is, at the root and in the tree.
		var renamedFlatParameterAndOverrideMap = flatParameterDisambiguationMap
		for onlyIfAvailableOverride in onlyIfAvailableOverrides
			where onlyIfAvailableOverride.name != onlyIfAvailableOverride.receivedProperty.label
		{
			renamedFlatParameterAndOverrideMap[onlyIfAvailableOverride.receivedProperty.label, default: [:]][onlyIfAvailableOverride.receivedProperty.typeDescription] = onlyIfAvailableOverride.name
		}
		var rootDisambiguationMap = renamedFlatParameterAndOverrideMap
		for (label, typeMap) in siblingDisambiguationMap {
			for (typeDescription, name) in typeMap {
				rootDisambiguationMap[label, default: [:]][typeDescription] = name
			}
		}

		// The root's own aliases are bound in the same scope as the dependencies promoted
		// to the root and the `onlyIfAvailable` override bindings. Bind an alias whose label
		// one of those already binds under a name of its own, and pass that name to the root
		// and to the alias's receivers in the tree.
		let rootBindingNames = Set(treePropertyNodes.map { node in
			siblingDisambiguationMap[node.propertyLabel]?[node.typeDescription] ?? node.propertyLabel
		})
		.union(onlyIfAvailableOverrides.map(\.name))
		.union(lazilyInstantiatedBindingNameMap.values.flatMap(\.values))
		let (rootItems, aliasBindingNames) = Self.renamingAliases(
			in: parameterTree,
			thatRedeclare: rootBindingNames,
			reservedNames: rootBindingNames
				.union(forwardedDependencies.map(\.property.label))
				.union(rootDefaultParameters.map(\.label))
				.union(flatReceivedParameters.map(\.label))
				.union(flatUncoveredParameters.map(\.label))
				.union(parameterTree.compactMap { item in
					guard case let .alias(alias) = item else { return nil }
					return alias.property.label
				}),
		)
		var treeDisambiguationMap = renamedFlatParameterAndOverrideMap
		for (label, typeMap) in aliasBindingNames {
			for (typeDescription, name) in typeMap {
				treeDisambiguationMap[label, default: [:]][typeDescription] = name
				siblingDisambiguationMap[label, default: [:]][typeDescription] = name
			}
		}
		// The root's own receive of a wrapped lazily instantiated dependency is passed its binding by name too.
		var returnDisambiguationMap = siblingDisambiguationMap
		for (label, typeMap) in lazilyInstantiatedBindingNameMap {
			for (typeDescription, name) in typeMap {
				returnDisambiguationMap[label, default: [:]][typeDescription] = name
			}
		}

		// A root's own received dependency whose label the root scope already binds – to a node
		// the mock builds for another receiver – cannot be rebound to its label without
		// redeclaring that binding, so the root is passed the dependency's binding by name.
		var rootDependenciesToRebind = [Dependency]()
		for dependency in instantiable.dependencies {
			if rootBindingNames.contains(dependency.property.label),
			   let binding = Self.disambiguatedBinding(
			   	ofReceived: dependency,
			   	unavailableProperties: [],
			   	lazilyInstantiatedInstanceProperties: [],
			   	flatParameterDisambiguationMap: rootDisambiguationMap,
			   )
			{
				returnDisambiguationMap[dependency.property.label, default: [:]][dependency.property.typeDescription] = binding.name
			} else {
				rootDependenciesToRebind.append(dependency)
			}
		}

		// Emit the root's own `.received` disambiguation rebinds before the tree
		// so any nested builder functions emitted within the tree can capture
		// them without forward-referencing. Root-level aliases flow through the
		// tree itself (as `MockTreeItem.alias` children of the root scope) in
		// production's topological order.
		let rootReceiverBindings = Self.emitReceiverBindings(
			for: rootDependenciesToRebind,
			unavailableProperties: [],
			flatParameterDisambiguationMap: rootDisambiguationMap,
			indent: bodyIndent,
		)

		if hasTree {
			// Bind onlyIfAvailable overrides first — tree bindings may reference them.
			for onlyIfAvailableOverride in onlyIfAvailableOverrides {
				lines.append("\(bodyIndent)let \(onlyIfAvailableOverride.name): \(onlyIfAvailableOverride.typeDescription.asSource) = safeDIOverrides.\(onlyIfAvailableOverride.name)")
			}
			lines.append(contentsOf: lazilyInstantiatedBindings)
			lines.append(contentsOf: rootReceiverBindings)
			let bodyBindings = Self.generateMockBodyBindings(
				items: rootItems,
				parentPath: "safeDIOverrides",
				indent: bodyIndent,
				flatParameterDisambiguationMap: treeDisambiguationMap,
				lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNameMap,
				parentConcreteType: nil,
				cycleEdges: context.cycleEdges,
				overridePathReachable: true,
			)
			lines.append(contentsOf: bodyBindings)
		} else {
			lines.append(contentsOf: lazilyInstantiatedBindings)
			lines.append(contentsOf: rootReceiverBindings)
		}

		// Generate return statement.
		let returnArgumentList = try generateReturnArgumentList(
			instantiable: instantiable,
			disambiguationMap: returnDisambiguationMap,
		)
		let mockMethodName = instantiable.customMockName ?? InstantiableVisitor.mockMethodName
		let returnConstruction = if instantiable.mockInitializer != nil {
			"\(typeName).\(mockMethodName)(\(returnArgumentList))"
		} else if instantiable.declarationType.isExtension {
			"\(typeName).\(InstantiableVisitor.instantiateMethodName)(\(returnArgumentList))"
		} else {
			"\(typeName)(\(returnArgumentList))"
		}
		lines.append("\(bodyIndent)return \(returnConstruction)")
		lines.append("\(indent)}")
		lines.append("}")

		let code = lines.joined(separator: "\n")
		return wrapInConditionalCompilation(code, mockConditionalCompilation: context.mockConditionalCompilation)
	}

	/// Generates the labeled argument list for the return statement in the mock body.
	/// Every dependency is resolved via its own label at the current scope —
	/// aliased deps have been emitted as `let <alias>: <Type> = <fulfilling>`
	/// bindings earlier in the body, so they reference the alias name directly.
	/// `disambiguationMap` must contain ONLY sibling-disambiguation entries
	/// (from `mergeSiblingDisambiguations`). When a root's own `.instantiated`
	/// dep label collided with a promoted sibling, the bound `let` uses the
	/// disambiguated name and this map remaps the reference. Flat-received
	/// parameter renames must NOT be merged in: they target a separate mock
	/// parameter, and the root's own dep must reference its own parameter.
	private func generateReturnArgumentList(
		instantiable: Instantiable,
		disambiguationMap: [String: [TypeDescription: String]] = [:],
	) throws -> String {
		let constructionInitializer: Initializer? = if let mockInitializer = instantiable.mockInitializer {
			mockInitializer
		} else {
			instantiable.initializer
		}
		guard let constructionInitializer else {
			return Instantiable.incorrectlyConfiguredComment
		}
		let dependenciesByLabel = Dictionary(
			uniqueKeysWithValues: instantiable.dependencies.map { ($0.property.label, $0) },
		)
		// A mock root that receives a dependency by value is passed the instance of the
		// `LazilyInstantiated` property promoted to its children, when the tree also receives that.
		let lazilyInstantiatedInstanceProperties = Set(propertiesToGenerate.compactMap(\.declaredLazilyInstantiatedInstanceProperty))
		var parts = [String]()
		for argument in constructionInitializer.arguments {
			if let dependency = dependenciesByLabel[argument.innerLabel] {
				// When the dep's label was sibling-disambiguated in the tree
				// (e.g. root's `service: TypeA` when a promoted sibling is also
				// labeled `service`), the bound `let` uses the disambiguated
				// name. Rewrite the reference so the Root init call finds it.
				if dependency.source.isReceived,
				   lazilyInstantiatedInstanceProperties.contains(dependency.property.asUnwrappedProperty)
				{
					let resolved = Self.disambiguatedLazilyInstantiatedBinding(
						named: dependency.property.label,
						withInstanceOfType: dependency.property.typeDescription.unwrapped,
						disambiguationMap: disambiguationMap,
					)?.name ?? argument.innerLabel
					parts.append("\(argument.label): \(resolved).\(Dependency.lazilyInstantiatedInstancePropertyName)")
				} else {
					let resolved = disambiguationMap[argument.innerLabel]?[dependency.property.typeDescription] ?? argument.innerLabel
					parts.append("\(argument.label): \(resolved)")
				}
			} else if argument.hasDefaultValue, argument.label != "_" {
				parts.append("\(argument.label): \(argument.label)")
			}
		}
		return parts.joined(separator: ", ")
	}

	// MARK: Mock scope context

	/// Emits the `let <label>: <Type> = <disambiguatedName>` rebinds a scope needs
	/// for `.received` dependencies whose flat mock parameter, `onlyIfAvailable`
	/// override, or sibling binding was renamed to disambiguate a collision. The
	/// alias becomes a real Swift binding so the
	/// scope's construction arguments can resolve the dep via its bare label.
	/// A dependency in `unavailableProperties` is passed `nil` and is not rebound,
	/// since the binding it would name is not declared at that point: it is
	/// declared later, or not at all.
	///
	/// `.aliased` dependencies are handled as `MockTreeItem.alias` children — they
	/// already flow through the mock body bindings in production's topological
	/// order and do not need a separate receiver pass. `.instantiated` is bound as
	/// a child `let` at the same scope; `.forwarded` is bound as a function
	/// parameter on the wrapping builder.
	///
	/// A dependency in `lazilyInstantiatedInstanceProperties` is received as the instance of a
	/// `LazilyInstantiated` property. When that property was renamed, it is rebound under the
	/// dependency's label, so the construction argument can read its instance from there.
	fileprivate static func emitReceiverBindings(
		for dependencies: [Dependency],
		unavailableProperties: Set<Property>,
		lazilyInstantiatedInstanceProperties: Set<Property> = [],
		flatParameterDisambiguationMap: [String: [TypeDescription: String]],
		indent: String,
	) -> [String] {
		dependencies.compactMap { dependency in
			disambiguatedBinding(
				ofReceived: dependency,
				unavailableProperties: unavailableProperties,
				lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
				flatParameterDisambiguationMap: flatParameterDisambiguationMap,
			).map {
				"\(indent)let \(dependency.property.label): \($0.typeDescription.asSource) = \($0.name)"
			}
		}
	}

	/// The disambiguated name of the binding a `.received` dependency resolves to, with the type
	/// to rebind it under the dependency's label with, or `nil` when the dependency is not
	/// received, is passed `nil` because it is in `unavailableProperties`, or its label was not
	/// disambiguated. The binding is looked up by the dependency's type and then by its unwrapped
	/// type, so an `onlyIfAvailable` receive of `x: X?` resolves to a disambiguated `x: X`. A
	/// dependency in `lazilyInstantiatedInstanceProperties` resolves to the `LazilyInstantiated`
	/// binding whose instance it receives.
	private static func disambiguatedBinding(
		ofReceived dependency: Dependency,
		unavailableProperties: Set<Property>,
		lazilyInstantiatedInstanceProperties: Set<Property>,
		flatParameterDisambiguationMap: [String: [TypeDescription: String]],
	) -> (name: String, typeDescription: TypeDescription)? {
		guard dependency.source.isReceived,
		      !unavailableProperties.contains(dependency.property),
		      let disambiguatedNames = flatParameterDisambiguationMap[dependency.property.label]
		else { return nil }
		if lazilyInstantiatedInstanceProperties.contains(dependency.property.asUnwrappedProperty) {
			return disambiguatedLazilyInstantiatedBinding(
				named: dependency.property.label,
				withInstanceOfType: dependency.property.typeDescription.unwrapped,
				disambiguationMap: flatParameterDisambiguationMap,
			)
		} else {
			return (
				disambiguatedNames[dependency.property.typeDescription]
					?? disambiguatedNames[dependency.property.asUnwrappedProperty.typeDescription],
			).map { ($0, dependency.property.typeDescription) }
		}
	}

	/// The name and type of the renamed `LazilyInstantiated` binding labeled `label` whose instance, of
	/// `instanceType`, is read by value, or `nil` when that binding kept its label.
	private static func disambiguatedLazilyInstantiatedBinding(
		named label: String,
		withInstanceOfType instanceType: TypeDescription,
		disambiguationMap: [String: [TypeDescription: String]],
	) -> (name: String, typeDescription: TypeDescription)? {
		guard let namesByTypeDescription = disambiguationMap[label] else { return nil }
		return [Dependency.lazilyInstantiatedType, Dependency.sendableLazilyInstantiatedType]
			.lazy
			.map { TypeDescription.simple(name: $0, generics: [instanceType]) }
			.compactMap { typeDescription in namesByTypeDescription[typeDescription].map { ($0, typeDescription) } }
			.first
	}

	/// Whether a node's construction references any `.received` dependency whose
	/// flat mock parameter was disambiguated by type. Such nodes need a wrapping
	/// scope to emit the `let <label>: <Type> = <disambiguatedName>` alias, so
	/// that `resolveBuilderArguments` can reference the bare label.
	private static func hasDisambiguatedReceiver(
		_ node: MockParameterNode,
		flatParameterDisambiguationMap: [String: [TypeDescription: String]],
	) -> Bool {
		guard !flatParameterDisambiguationMap.isEmpty else { return false }
		return node.dependencies.contains { dependency in
			disambiguatedBinding(
				ofReceived: dependency,
				unavailableProperties: node.unavailableProperties,
				lazilyInstantiatedInstanceProperties: node.lazilyInstantiatedInstanceProperties,
				flatParameterDisambiguationMap: flatParameterDisambiguationMap,
			) != nil
		}
	}

	// MARK: MockParameterNode

	/// A node in the mock parameter tree. Each node represents one property edge
	/// in the dependency tree and carries the metadata needed to generate its
	/// `SafeDIMockConfiguration` struct and builder call.
	///
	/// Explicit `Sendable` conformance (here and on `MockAliasNode` /
	/// `MockTreeItem`) is required because the mutual recursion through
	/// `MockTreeItem` blocks the compiler's implicit Sendable inference.
	struct MockParameterNode: Sendable {
		/// The property label on the parent type's init (e.g., "service", "childBuilder").
		let propertyLabel: String
		/// The full type description of the property (e.g., `Instantiator<Child>`).
		let typeDescription: TypeDescription
		/// The instantiated type — `typeDescription.asInstantiatedType` (e.g., `Child`).
		/// Used for the builder closure's return type, disambiguation keys, and
		/// cycle detection. Configuration struct nesting uses `concreteType` instead.
		let instantiatedTypeDescription: TypeDescription
		/// Whether this property is an Instantiator/ErasedInstantiator/Sendable variant.
		let isInstantiator: Bool
		/// Whether the concrete type uses extension-based `instantiate(...)` instead of `init(...)`.
		let isExtensionBased: Bool
		/// Whether this property requires erased-to-concrete existential wrapping.
		let erasedToConcreteExistential: Bool
		/// Child items in the dependency tree (instantiated sub-properties and aliased
		/// bindings declared at this scope). Ordered so that an alias always follows
		/// the child that fulfills it — mirrors production's `orderedPropertiesToGenerate`.
		let children: [MockTreeItem]
		/// Non-dependency default-valued parameters from this type's init or customMock.
		let defaultParameters: [DefaultParameter]
		/// All arguments from the init or customMock that will be used for construction.
		/// Determines the builder closure signature (positional unlabeled parameters).
		let constructionArguments: [Initializer.Argument]
		/// The type's declared dependencies.
		let dependencies: [Dependency]
		/// The received dependencies that are in scope only as the instance of a `LazilyInstantiated` property.
		/// Construction arguments for them read that instance.
		let lazilyInstantiatedInstanceProperties: Set<Property>
		/// The `onlyIfAvailable` dependencies that are unavailable where this node is
		/// built, because an ancestor is still building them or an enclosing scope does
		/// not build them before it. They are passed `nil`.
		let unavailableProperties: Set<Property>
		/// Whether a compatible user-defined mock method exists for this type.
		let useMockInitializer: Bool
		/// The custom mock method name (e.g., "customMock"), if any.
		let customMockName: String?
		/// The concrete type (e.g., `ConcreteService`), which may differ from `instantiatedTypeDescription`
		/// when the property uses an existential wrapper (e.g., `AnyService` fulfilled by `ConcreteService`).
		let concreteType: TypeDescription
		/// Forwarded properties on this type (relevant for Instantiator edges).
		let forwardedProperties: Set<Property>
		/// Set when this property's label repeats in the ancestor stack during
		/// scope construction (`Scope.createScopeGenerator`). Per-root and
		/// syntactic — different roots walking the same underlying cycle can
		/// see it at different edges. Terminates infinite descent by zeroing
		/// the cycle-closer's `propertiesToGenerate`.
		///
		/// For cross-root consistency (e.g., shared `SafeDIMockConfiguration`
		/// struct shapes), use `cycleEdges` — the globally-computed feedback
		/// arc set — instead.
		let isPropertyCycle: Bool
		/// The `cycleClosingProperties` of the scope this node was built from.
		let cycleClosingProperties: Set<Property>
		/// The `isReferencedByCycleClosingScope` of the scope this node was built from.
		let isReferencedByCycleClosingScope: Bool
		/// Whether this node is inside a sendable scope (descendant of SendableInstantiator).
		/// When `true`, the `safeDIBuilder` closure on `SafeDIMockConfiguration` is `@Sendable`.
		let requiresSendable: Bool

		/// The property this node builds.
		var property: Property {
			Property(label: propertyLabel, typeDescription: typeDescription)
		}

		/// The property-typed children of this node (filters out alias items).
		/// `SafeDIMockConfiguration`, `SafeDIOverrides`, and disambiguation only
		/// concern properties — aliases are plain `let` bindings emitted inline.
		var propertyChildren: [MockParameterNode] {
			children.compactMap {
				if case let .property(property) = $0 {
					property
				} else {
					nil
				}
			}
		}

		/// Whether this node needs a full `SafeDIMockConfiguration` struct or can be
		/// inlined as an optional builder closure on the parent. A node needs a struct
		/// when it has property children (subtree customization), non-dependency
		/// defaults, or is a property cycle (the struct may exist from a non-cycle
		/// instance of the same type).
		var needsConfigurationStruct: Bool {
			!propertyChildren.isEmpty || !defaultParameters.isEmpty || isPropertyCycle
		}

		/// True when this node must be wrapped in a `__safeDI_<label>()` helper
		/// function — either because it needs a configuration struct or because
		/// it has alias children whose bindings must live in a local scope.
		/// When `needsConfigurationStruct` is false, `propertyChildren` is empty, so
		/// any remaining children are aliases whose bindings require the function wrapper.
		var requiresFunctionWrapper: Bool {
			needsConfigurationStruct || !children.isEmpty
		}

		/// The nested configuration struct name (used in struct definitions).
		static let configurationStructName = "SafeDIMockConfiguration"

		/// The qualified configuration type name for references (e.g., `ChildA.SafeDIMockConfiguration`).
		/// Uses the concrete fulfilling type so the struct can be nested in a concrete type
		/// extension. Protocol extensions cannot contain nested type declarations.
		var configurationTypeName: String {
			"\(concreteType.asSource).\(Self.configurationStructName)"
		}

		/// Whether this argument is a non-dependency `_`-labeled defaulted
		/// parameter that the mock call site elides. Elided parameters are
		/// filled in by Swift's default-argument thunk in the callee's
		/// declaration context, which preserves `Self`-binding and unqualified
		/// name lookup inside the default expression. Dependency parameters
		/// (even when shaped `_ dep: Dep = …`) are never elided — the override
		/// flow must thread the resolved binding through to the callee.
		/// `validateUnlabeledDefaultShape` on the macro rejects the shapes
		/// where eliding would produce an uncallable signature (non-trailing
		/// `_`-labeled default).
		private func isElidedInCallSite(_ argument: Initializer.Argument, dependencyInnerLabels: Set<String>) -> Bool {
			argument.label == "_"
				&& argument.hasDefaultValue
				&& !dependencyInnerLabels.contains(argument.innerLabel)
		}

		/// Construction arguments surfaced at the mock call site, with elided
		/// non-dependency unlabeled defaults removed.
		var callSiteArguments: [Initializer.Argument] {
			let dependencyInnerLabels = Set(dependencies.map(\.property.label))
			return constructionArguments.filter { !isElidedInCallSite($0, dependencyInnerLabels: dependencyInnerLabels) }
		}

		/// The builder closure type as a Swift source string (unlabeled parameters).
		/// Uses the property type (not the concrete fulfilling type) so the override
		/// closure matches what the parent init expects. Swift covariant return types
		/// ensure a concrete builder (e.g., `ConcreteService.init`) is assignable to
		/// a closure returning the property type (e.g., `() -> ServiceProtocol`).
		var builderClosureType: String {
			let parameterTypes = callSiteArguments
				.map(\.typeDescription.asFunctionParameter.asSource)
				.joined(separator: ", ")
			return "(\(parameterTypes)) -> \(instantiatedTypeDescription.asSource)"
		}

		/// The builder closure type using the concrete type for the return.
		/// Used in `SafeDIMockConfiguration` structs which are deduplicated by
		/// concrete type and must have a single consistent builder signature.
		var concreteBuilderClosureType: String {
			let parameterTypes = callSiteArguments
				.map(\.typeDescription.asFunctionParameter.asSource)
				.joined(separator: ", ")
			return "(\(parameterTypes)) -> \(concreteType.asSource)"
		}

		/// Call-site arguments with labeled non-dependency defaults also elided,
		/// for the pruned-back-edge / unreachable-override case where Swift's
		/// default-argument thunk must fire in the callee's scope. Elided
		/// defaults preserve correct resolution of `Self.*`, private members,
		/// and file-scoped helpers in the default expression, which would
		/// otherwise resolve in the wrong context if inlined at the caller.
		var callSiteArgumentsForPrunedOverride: [Initializer.Argument] {
			let dependencyInnerLabels = Set(dependencies.map(\.property.label))
			return callSiteArguments.filter { argument in
				dependencyInnerLabels.contains(argument.innerLabel) || !argument.hasDefaultValue
			}
		}

		/// The Swift expression, for use inside a generated `mock()` body, that
		/// reads this node's optional override closure.
		///
		/// A caller of `mock()` overrides how a node is built by setting a closure
		/// on `SafeDIOverrides` (or on a nested `SafeDIMockConfiguration`). Where
		/// that closure lives depends on the node's shape: a node with a
		/// configuration struct keeps it in the struct's `safeDIBuilder` property,
		/// while a leaf node's entry is the optional closure itself.
		///
		/// - Parameter nodePath: The expression for this node's entry in its
		///   parent's overrides, e.g. `safeDIOverrides.service` or
		///   `safeDIOverrides.parent.child`.
		/// - Returns: An expression of optional closure type, e.g.
		///   `safeDIOverrides.service.safeDIBuilder` for a node with a
		///   configuration struct or `safeDIOverrides.service` for a leaf. Pass it
		///   as the `overrideExpression` of `constructionExpression`, which unwraps
		///   it and falls back to the node's default construction when it is `nil`.
		func overridePath(nodePath: String) -> String {
			if needsConfigurationStruct {
				"\(nodePath).safeDIBuilder"
			} else {
				nodePath
			}
		}

		/// For a node declared with `erasedToConcreteExistential: true`, the
		/// concrete existential type that erases the node's concrete type (e.g.,
		/// `AnyService` erasing `DefaultService`). Generated mock code wraps the
		/// concrete value in this type: `AnyService(DefaultService(…))`.
		/// Instantiator-family properties erase to the type they build, constant
		/// properties to the property type itself.
		var concreteExistentialType: TypeDescription {
			if isInstantiator {
				typeDescription.unwrapped.asInstantiatedType
			} else {
				typeDescription
			}
		}

		/// The type annotation (including the leading `: `) a `let` binding needs
		/// when it holds `constructionExpression(overrideExpression:…)` with a
		/// non-`nil` override, or the empty string when none is needed.
		///
		/// Each branch of an `if` expression is type-checked on its own, so when
		/// no contextual type is present the branches must produce the same type.
		/// The default branch returns the concrete type (or whatever a custom mock
		/// returns), while an override closure on a leaf returns the property type.
		/// Annotating with the property type gives both branches a common
		/// destination, matching the type the binding had when the two were
		/// unified through `??`. Erased nodes wrap both branches in the same
		/// eraser, so they only need the annotation when that eraser is not
		/// the property type.
		var overriddenBindingTypeAnnotation: String {
			let defaultBranchType = if erasedToConcreteExistential {
				concreteExistentialType
			} else {
				concreteType
			}
			if defaultBranchType == instantiatedTypeDescription {
				return ""
			} else {
				return ": \(instantiatedTypeDescription.asSource)"
			}
		}

		/// A single-line expression, emitted into a generated `mock()` body, that
		/// constructs this node — via the caller's override when one is set, and
		/// via the node's default construction otherwise.
		///
		/// When `overrideExpression` names an optional override closure, emits
		/// `if let safeDIBuilder = <override> { safeDIBuilder(<arguments>) } else { <default call> }`.
		/// When it is `nil` — a cycle node, or an override path pruned from the
		/// configuration struct — emits the default call alone.
		///
		/// Calling the default directly, rather than coalescing a function
		/// reference with `??` and applying the result, spares the compiler an
		/// autoclosure and reabstraction thunks per binding. Erased nodes wrap the
		/// default in the eraser, and wrap the override when it comes from a
		/// configuration struct (whose builder returns the concrete type).
		///
		/// The unwrapped override is bound to `safeDIBuilder` unless an argument
		/// is a dependency with that label, in which case underscores are
		/// appended so the binding does not shadow the argument.
		func constructionExpression(
			overrideExpression: String?,
			arguments: [String],
			overrideReachable: Bool,
		) -> String {
			let defaultCall = defaultBuilderCall(arguments: arguments, overrideReachable: overrideReachable)
			let defaultConstruction = if erasedToConcreteExistential {
				"\(concreteExistentialType.asSource)(\(defaultCall))"
			} else {
				defaultCall
			}
			guard let overrideExpression else {
				return defaultConstruction
			}
			var overrideName = "safeDIBuilder"
			while arguments.contains(overrideName) {
				overrideName += "_"
			}
			let overrideCall = "\(overrideName)(\(arguments.joined(separator: ", ")))"
			let overrideConstruction = if erasedToConcreteExistential, needsConfigurationStruct {
				"\(concreteExistentialType.asSource)(\(overrideCall))"
			} else {
				overrideCall
			}
			return "if let \(overrideName) = \(overrideExpression) { \(overrideConstruction) } else { \(defaultConstruction) }"
		}

		/// A direct call expression using the default builder with labeled arguments.
		/// e.g., `ConcreteService(helper: helper)` or `ConcreteService.instantiate(helper: helper)`.
		/// Non-dependency `_`-labeled defaults are absent from `callSiteArguments`,
		/// so the call omits them and Swift's default-argument thunk fills them
		/// in the callee's declaration context.
		///
		/// Pass `overrideReachable: false` when the call lives on a pruned
		/// back-edge path where `resolveBuilderArguments` returned values for
		/// `callSiteArgumentsForPrunedOverride` rather than `callSiteArguments`.
		/// Zipping against the wrong signature would shift labels for arguments
		/// that follow an elided default (e.g. `init(a: A, b: B = ..., c: C)`
		/// with `b` elided would emit `C`'s value under label `b`).
		private func defaultBuilderCall(arguments: [String], overrideReachable: Bool) -> String {
			let methodName: String = if useMockInitializer {
				customMockName ?? InstantiableVisitor.mockMethodName
			} else if isExtensionBased {
				InstantiableVisitor.instantiateMethodName
			} else {
				"init"
			}
			let surfacedArguments = overrideReachable ? callSiteArguments : callSiteArgumentsForPrunedOverride
			let labeledArguments = zip(surfacedArguments, arguments)
				.map { $0.0.label == "_" ? $0.1 : "\($0.0.label): \($0.1)" }
				.joined(separator: ", ")
			if methodName == "init" {
				return "\(concreteType.asSource)(\(labeledArguments))"
			} else {
				return "\(concreteType.asSource).\(methodName)(\(labeledArguments))"
			}
		}

		/// A non-dependency default-valued parameter from an init or customMock.
		struct DefaultParameter: Sendable {
			/// The parameter label (e.g., "theme", "isPro").
			let label: String
			/// The type of the parameter.
			let typeDescription: TypeDescription
			/// The default value expression (e.g., ".light", "false").
			let defaultExpression: String
			/// Whether the parameter type is a closure/function type.
			let isClosureType: Bool
		}
	}

	// MARK: MockAliasNode

	/// A `@Received(fulfilledByDependencyNamed:)` edge in the mock parameter tree.
	/// Represented directly as a tree item so mock emission can interleave
	/// aliases with property bindings using production's topological order.
	struct MockAliasNode: Sendable {
		/// The alias property as declared (e.g., `userNetworkService: NetworkService`).
		let property: Property
		/// Whether the fulfilling dependency is wrapped in the alias property's type.
		let erasedToConcreteExistential: Bool
		/// Whether the alias is received only if its fulfilling dependency is available.
		let onlyIfAvailable: Bool
		/// The label of the dependency that fulfills the alias (e.g., "networkService").
		let fulfillingLabel: String
		/// The fulfilling dependency's type — used to look up flat-parameter
		/// disambiguations when the fulfiller is a renamed mock parameter, and to
		/// spell the optional an erased `onlyIfAvailable` alias's wrapper is mapped over.
		let fulfillingTypeDescription: TypeDescription
		/// Whether the fulfilling dependency is in scope only as the instance of a `LazilyInstantiated` property.
		let fulfillingPropertyIsLazilyInstantiatedInstance: Bool
		/// How the emitted binding refers to the alias property's declaration.
		let declarationReference: AliasDeclarationReferences.Reference?
	}

	// MARK: OnlyIfAvailableOverride

	/// A property a mock root's tree receives only if available that nothing in the mock provides.
	/// The generated `mock()` reads it from an optional `SafeDIOverrides` field, which defaults to `nil`,
	/// into a binding of the same name, and hands it to the receivers of the property.
	private struct OnlyIfAvailableOverride {
		/// The property the tree receives: a `@Received(onlyIfAvailable: true)` property, or the
		/// non-optional fulfilling property of an `onlyIfAvailable` alias.
		let receivedProperty: Property
		/// The type of the field and the binding: `receivedProperty`'s type, made optional.
		let typeDescription: TypeDescription
		/// The name of the field and the binding (see `onlyIfAvailableOverrides(for:namesInMockScope:reservedNames:)`).
		let name: String
	}

	// MARK: MockTreeItem

	/// One entry in a scope's mock parameter tree. Properties carry the metadata
	/// needed for `SafeDIMockConfiguration` / `SafeDIOverrides`; aliases carry
	/// only what's needed to emit a `let <alias>: <Type> = <fulfilling>` line.
	enum MockTreeItem: Sendable {
		case property(MockParameterNode)
		case alias(MockAliasNode)
	}

	/// A directed edge in the global type-reference graph that, when removed,
	/// breaks a cycle. Computed once globally (one back-edge per strongly-connected
	/// component of size > 1) and applied uniformly when generating every type's
	/// configuration struct.
	struct CycleEdge: Hashable {
		let parent: String
		let child: String
	}

	/// Collects the nodes of all unique configuration types in this scope's mock parameter tree,
	/// in the order this root reaches them. `generateMockCode` keeps the first root's node for each
	/// type, in alphabetical root order, and generates its struct once with `generateConfigurationStruct`.
	func collectConfigurationTypes() async -> [MockParameterNode] {
		let parameterTree = await rootMockParameterTree
		return Self.collectUniqueConfigurationTypes(from: parameterTree.propertyNodes)
	}

	/// The `SafeDIMockConfiguration` struct of a node `collectConfigurationTypes` returned.
	/// Children edges are filtered against `cycleEdges` so the same back-edges are
	/// removed across every root's view of a given type — required for type-level
	/// consistency, since per-tree cycle detection (`isPropertyCycle`) breaks at
	/// different edges depending on which root is being walked.
	/// `sendableConfigurationTypeNames` lists the concrete types whose configuration
	/// struct must be `@Sendable`-typed because some root references them from a
	/// `SendableInstantiator` scope. The set is computed once across all roots so
	/// struct-per-type dedup remains consistent.
	static func generateConfigurationStruct(
		for node: MockParameterNode,
		cycleEdges: Set<CycleEdge>,
		sendableConfigurationTypeNames: Set<String>,
	) -> String {
		generateConfigurationStruct(
			for: node,
			indent: standardIndent,
			cycleEdges: cycleEdges,
			requiresSendable: sendableConfigurationTypeNames.contains(node.concreteType.asSource),
		)
	}

	/// Concrete type names referenced by this scope's mock parameter tree from a
	/// `SendableInstantiator` scope. Aggregated across all roots before generation
	/// so every root emits consistent `@Sendable`-ness for a given type's
	/// `SafeDIMockConfiguration` struct.
	func collectSendableConfigurationTypeNames() async -> Set<String> {
		let parameterTree = await rootMockParameterTree
		var result = Set<String>()

		func walk(_ node: MockParameterNode) {
			if node.requiresSendable, node.needsConfigurationStruct {
				result.insert(node.concreteType.asSource)
			}
			for child in node.propertyChildren {
				walk(child)
			}
		}

		for node in parameterTree.propertyNodes {
			walk(node)
		}
		return result
	}

	/// Walks the dependency tree and builds a `[MockTreeItem]` tree representing
	/// the direct children of the current scope. Property items recursively contain
	/// their own subtree, while alias items capture the bindings
	/// `@Received(fulfilledByDependencyNamed:)` needs. Items appear in production's
	/// `orderedPropertiesToGenerate` order, so an alias always sits after the
	/// sibling child that fulfills it.
	///
	/// `propertiesGeneratedLater` has the same meaning as in `generateCode`: an
	/// `onlyIfAvailable` receive of one of these properties is passed `nil`, and an
	/// `onlyIfAvailable` alias of one is not bound, as in the production tree. The
	/// same holds for a receive of an ancestor that is still being built (see
	/// `Scope.createScopeGenerator`).
	private func collectMockParameterTree(
		insideSendableScope: Bool = false,
		propertiesGeneratedLater: Set<Property> = [],
	) async -> [MockTreeItem] {
		var items = [MockTreeItem]()

		// Roots only appear at the top level, never as children here — so the
		// `.root` case is not part of the reachable pattern space and is omitted.
		for child in orderedChildren(propertiesGeneratedLater: propertiesGeneratedLater) {
			let childGenerator = child.generator
			let childPropertiesGeneratedLater = child.propertiesGeneratedLater
			let childUnavailableProperties = child.unavailableProperties
			if case let .alias(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable, declarationReference) = childGenerator.scopeData {
				// The dependency this alias binds is passed `nil` instead.
				guard childGenerator.uncreatedAliasProperty(unavailableProperties: childUnavailableProperties) == nil else { continue }
				items.append(.alias(MockAliasNode(
					property: property,
					erasedToConcreteExistential: erasedToConcreteExistential,
					onlyIfAvailable: onlyIfAvailable,
					fulfillingLabel: fulfillingProperty.label,
					fulfillingTypeDescription: fulfillingProperty.typeDescription,
					fulfillingPropertyIsLazilyInstantiatedInstance: childGenerator.fulfillingPropertyIsLazilyInstantiatedInstance,
					declarationReference: declarationReference,
				)))
			} else if case let .property(childInstantiable, childProperty, _, erasedToConcreteExistential, isPropertyCycle) = childGenerator.scopeData {
				let isInstantiator = !childProperty.propertyType.isConstant
				let childInsideSendable = insideSendableScope || childProperty.propertyType.isSendable

				// Recurse into children to build the subtree.
				let childItems = await childGenerator.collectMockParameterTree(
					insideSendableScope: childInsideSendable,
					propertiesGeneratedLater: childPropertiesGeneratedLater,
				)

				// Determine which initializer to use for construction arguments and defaults.
				// When the child has a compatible mock method, it fully controls the
				// construction signature — its parameter list wins even when empty.
				// Init-only default-valued parameters are intentionally hidden behind
				// the mock.
				// The mock is compatible when it returns the type the property builds — the
				// return type of the builder closure — rather than the property's own type, so
				// an `ErasedInstantiator<_, Protocol>` property, like a `Protocol` property, is
				// built with a mock that returns `Protocol`.
				let useMockInitializer = childInstantiable.mockReturnTypeIsCompatible(withPropertyType: childProperty.typeDescription.asInstantiatedType)
				let constructionInitializer: Initializer? = if useMockInitializer, let mockInitializer = childInstantiable.mockInitializer {
					mockInitializer
				} else {
					childInstantiable.initializer
				}

				// Collect non-dependency default-valued parameters and construction arguments.
				var defaultParameters = [MockParameterNode.DefaultParameter]()
				var constructionArguments = [Initializer.Argument]()
				if let constructionInitializer {
					constructionArguments = constructionInitializer.arguments
					let dependencyLabels = Set(childInstantiable.dependencies.map(\.property.label))
					for argument in constructionInitializer.arguments where argument.hasDefaultValue {
						guard !dependencyLabels.contains(argument.innerLabel),
						      argument.label != "_",
						      let defaultExpression = argument.defaultValueExpression
						else { continue }
						defaultParameters.append(MockParameterNode.DefaultParameter(
							label: argument.label,
							typeDescription: argument.typeDescription.strippingEscaping,
							defaultExpression: defaultExpression,
							isClosureType: argument.typeDescription.strippingEscaping.isClosure,
						))
					}
				}

				// Collect forwarded properties for Instantiator edges.
				let forwardedProperties = Set(
					childInstantiable.dependencies
						.filter { $0.source == .forwarded }
						.map(\.property),
				)

				items.append(.property(MockParameterNode(
					propertyLabel: childProperty.label,
					typeDescription: childProperty.typeDescription,
					instantiatedTypeDescription: childProperty.typeDescription.asInstantiatedType,
					isInstantiator: isInstantiator,
					isExtensionBased: childInstantiable.declarationType.isExtension,
					erasedToConcreteExistential: erasedToConcreteExistential,
					children: childItems,
					defaultParameters: defaultParameters,
					constructionArguments: constructionArguments,
					dependencies: childInstantiable.dependencies,
					lazilyInstantiatedInstanceProperties: childGenerator.lazilyInstantiatedInstanceProperties,
					unavailableProperties: childUnavailableProperties,
					useMockInitializer: useMockInitializer,
					customMockName: childInstantiable.customMockName,
					concreteType: childInstantiable.concreteInstantiable,
					forwardedProperties: forwardedProperties,
					isPropertyCycle: isPropertyCycle,
					cycleClosingProperties: childGenerator.cycleClosingProperties,
					isReferencedByCycleClosingScope: childGenerator.isReferencedByCycleClosingScope,
					requiresSendable: childInsideSendable,
				)))
			}
		}

		return items
	}

	/// Walks the parameter tree and collects `@Instantiated` dependencies from child
	/// types that aren't fulfilled by their own child nodes. These are deps that
	/// surface through builder arguments (especially via custom mock methods) but aren't
	/// fulfilled by any type in the scope map.
	private static func collectUncoveredDependenciesFromTree(
		_ nodes: [MockParameterNode],
		into flatUncoveredParameters: inout [(label: String, typeSource: String)],
	) {
		for node in nodes {
			let propertyChildren = node.propertyChildren
			let childLabels = Set(propertyChildren.map(\.propertyLabel))
			let collectedKeys = Set(flatUncoveredParameters.map { "\($0.label):\($0.typeSource)" })
			for dependency in node.dependencies {
				guard case .instantiated = dependency.source else { continue }
				// Skip deps that are covered by a child node in the tree.
				guard !childLabels.contains(dependency.property.label) else { continue }
				// Route through `asFunctionParameter` so closure types surface
				// as `@escaping` — matching the `rootDefaultParameters` and
				// flat-received emission conventions. Idempotent for non-closures.
				let sourceType = dependency.property.propertyType.isConstant
					? dependency.property.typeDescription.asInstantiatedType.asFunctionParameter.asSource
					: dependency.property.typeDescription.asFunctionParameter.asSource
				// Skip deps already collected (by label AND type).
				let key = "\(dependency.property.label):\(sourceType)"
				guard !collectedKeys.contains(key) else { continue }
				flatUncoveredParameters.append((label: dependency.property.label, typeSource: sourceType))
			}
			// Skip recursion into property cycle children — they're self-references
			// whose deps would incorrectly surface as uncovered.
			let nonCycleChildren = propertyChildren.filter { !$0.isPropertyCycle }
			collectUncoveredDependenciesFromTree(
				nonCycleChildren,
				into: &flatUncoveredParameters,
			)
		}
	}

	// MARK: SafeDIOverrides Generation

	/// Merges the sibling-level disambiguations for a given level of tree nodes
	/// into an existing receiver disambiguation map. Used at both the root scope
	/// and within `generateMockBodyBindings` so that consumers at the current
	/// scope can rebind disambiguated labels back to their natural labels via
	/// `emitReceiverBindings`, and so that the root's return call can reference
	/// disambiguated bindings when the root's own `.instantiated` dep label
	/// collides with a promoted sibling.
	private static func mergeSiblingDisambiguations(
		into map: inout [String: [TypeDescription: String]],
		for nodes: [MockParameterNode],
	) {
		let labelMap = disambiguatePropertyLabels(for: nodes)
		for node in nodes {
			let disambiguated = disambiguatedLabel(for: node, labelMap: labelMap)
			if disambiguated != node.propertyLabel {
				map[node.propertyLabel, default: [:]][node.typeDescription] = disambiguated
			}
		}
	}

	/// Computes disambiguated property labels for a list of nodes at the same scope level.
	/// Nodes that share a `propertyLabel` are named by `identifierSafeNames`, preferring the
	/// type each node builds and falling back to its property type: a mock root that declares
	/// `x: X` itself can also be given a promoted `x: Instantiator<X>` or `x: LazilyInstantiated<X>`,
	/// and each needs its own name.
	/// Returns a dictionary mapping each node's label and property type to its disambiguated label.
	private static func disambiguatePropertyLabels(
		for nodes: [MockParameterNode],
	) -> [String: [TypeDescription: String]] {
		let labels = nodes.map(\.propertyLabel)
		let collidingLabels = collidingLabels(in: labels)
		let collidingNodes = nodes.filter { collidingLabels.contains($0.propertyLabel) }
		let collidingNames = identifierSafeNames(
			for: collidingNodes.map {
				(
					label: $0.propertyLabel,
					suffixTypes: [$0.instantiatedTypeDescription.simplified, $0.instantiatedTypeDescription, $0.typeDescription],
				)
			},
			// Labels that don't need disambiguation stay as they are.
			reservedNames: Set(labels).subtracting(collidingLabels),
		)
		var result = [String: [TypeDescription: String]]()
		for node in nodes where !collidingLabels.contains(node.propertyLabel) {
			result[node.propertyLabel, default: [:]][node.typeDescription] = node.propertyLabel
		}
		for (node, name) in zip(collidingNodes, collidingNames) {
			result[node.propertyLabel, default: [:]][node.typeDescription] = name
		}
		return result
	}

	/// The names `nodes`, the property children of one scope whose labels are `labels`, are bound to:
	/// each node's label, disambiguated when siblings share it.
	private static func bindingNames(of nodes: [MockParameterNode], labels: Set<String>) -> Set<String> {
		// Most scopes have no two children with one label, which leaves every label as it is.
		guard labels.count < nodes.count else { return labels }
		let labelMap = disambiguatePropertyLabels(for: nodes)
		return Set(nodes.map { disambiguatedLabel(for: $0, labelMap: labelMap) })
	}

	/// The overrides of a mock root's `onlyIfAvailable` received properties, one per property, in the
	/// order of `receivedProperties`, each named for its `SafeDIOverrides` field and its `mock()` binding.
	///
	/// An override is named by its label, unless the label is one of `namesInMockScope` – a `mock()`
	/// parameter the binding would hide, or a binding of the root's tree it would redeclare – or another
	/// override has the same label. Those overrides are named apart by `identifierSafeNames`, as sibling
	/// entries are: by the label followed by the type of the field, never taking a name in
	/// `namesInMockScope`, in `reservedNames`, or that another override is named by. Every input is a label
	/// or a type of the mock root's scope, in an order fixed by them, so the names depend only on what the
	/// declarations say.
	private static func onlyIfAvailableOverrides(
		for receivedProperties: [Property],
		namesInMockScope: Set<String>,
		reservedNames: Set<String>,
	) -> [OnlyIfAvailableOverride] {
		let labels = receivedProperties.map(\.label)
		let typeDescriptions = receivedProperties.map { property in
			property.typeDescription.isOptional ? property.typeDescription : .optional(property.typeDescription)
		}
		let collidingLabels = collidingLabels(in: labels).union(namesInMockScope.intersection(labels))
		let collidingIndices = collidingLabels.isEmpty ? [] : receivedProperties.indices.filter { collidingLabels.contains(labels[$0]) }
		let collidingNames = collidingIndices.isEmpty ? [] : identifierSafeNames(
			for: collidingIndices.map { index in
				(label: labels[index], suffixTypes: [typeDescriptions[index].simplified, typeDescriptions[index]])
			},
			reservedNames: namesInMockScope.union(reservedNames).union(labels),
		)
		var names = labels
		for (index, name) in zip(collidingIndices, collidingNames) {
			names[index] = name
		}
		return receivedProperties.indices.map { index in
			OnlyIfAvailableOverride(
				receivedProperty: receivedProperties[index],
				typeDescription: typeDescriptions[index],
				name: names[index],
			)
		}
	}

	/// The labels that appear more than once in `labels`.
	private static func collidingLabels(in labels: [String]) -> Set<String> {
		var seenLabels = Set<String>()
		var collidingLabels = Set<String>()
		for label in labels where !seenLabels.insert(label).inserted {
			collidingLabels.insert(label)
		}
		return collidingLabels
	}

	/// Returns the disambiguated property label for a node, given a disambiguation map.
	private static func disambiguatedLabel(
		for node: MockParameterNode,
		labelMap: [String: [TypeDescription: String]],
	) -> String {
		labelMap[node.propertyLabel]![node.typeDescription]!
	}

	/// Names apart entries that share a label, deriving every name from type structure so that
	/// each is a valid Swift identifier no matter how its types are spelled.
	///
	/// Each entry lists suffix types in order of preference. An entry is named
	/// `<label>_<suffix type’s asIdentifier>` with the first suffix type whose `asIdentifier`
	/// no other entry with its label shares at the same position, or with its last suffix type
	/// when every position is shared. Then, in entry order, underscores are appended until the
	/// name is neither reserved nor already given to an earlier entry.
	private static func identifierSafeNames(
		for entries: [(label: String, suffixTypes: [TypeDescription])],
		reservedNames: Set<String>,
	) -> [String] {
		let suffixesPerEntry = entries.map { $0.suffixTypes.map(\.asIdentifier) }
		var takenNames = reservedNames
		return entries.indices.map { index in
			let suffixes = suffixesPerEntry[index]
			let suffix = suffixes.indices.first { position in
				!entries.indices.contains { otherIndex in
					otherIndex != index
						&& entries[otherIndex].label == entries[index].label
						&& suffixesPerEntry[otherIndex][position] == suffixes[position]
				}
			}.map { suffixes[$0] } ?? suffixes[suffixes.count - 1]
			var name = "\(entries[index].label)_\(suffix)"
			while takenNames.contains(name) {
				name += "_"
			}
			takenNames.insert(name)
			return name
		}
	}

	/// Collects all unique types from the `MockParameterNode` tree, deduplicated
	/// by `concreteType`. Returns nodes in depth-first order (children before
	/// parents) so that referenced types appear before their referrers.
	/// Uses `concreteType` (not `instantiatedTypeDescription`) because config
	/// structs are nested in concrete type extensions — protocol extensions
	/// cannot contain nested type declarations.
	/// When the same type appears in both sendable and non-sendable contexts,
	/// the sendable version is preferred (`@Sendable` closures work in both contexts).
	private static func collectUniqueConfigurationTypes(
		from nodes: [MockParameterNode],
	) -> [MockParameterNode] {
		var seen = Set<String>()
		var result = [MockParameterNode]()

		func walk(_ node: MockParameterNode, ancestorTypes: Set<String> = []) {
			let key = node.concreteType.asSource
			// Skip nodes whose type matches an ancestor — self-referencing cycle.
			guard !ancestorTypes.contains(key) else { return }
			var childAncestors = ancestorTypes
			childAncestors.insert(key)
			// Process children first (depth-first). Only property children
			// produce configuration structs; aliases are plain `let` bindings.
			for child in node.propertyChildren {
				walk(child, ancestorTypes: childAncestors)
			}
			// Skip leaf nodes that don't need a SafeDIMockConfiguration struct.
			guard node.needsConfigurationStruct else { return }
			// No cycle-closer guard here: a cycle-closer (isPropertyCycle == true)
			// is always reached at a deeper DFS level than its matching non-cycle
			// occurrence (the property must appear earlier in the stack for
			// `isPropertyCycle` to fire), so the `seen` dedup below catches it
			// after the real version has already been recorded.
			if seen.contains(key) {
				// If this node requires sendable and the existing one doesn't,
				// replace it — @Sendable closures are compatible in both contexts.
				if node.requiresSendable,
				   let existingIndex = result.firstIndex(where: {
				   	$0.concreteType.asSource == key && !$0.requiresSendable
				   })
				{
					result[existingIndex] = node
				}
				return
			}
			seen.insert(key)
			result.append(node)
		}

		for node in nodes {
			walk(node)
		}
		return result
	}

	/// Generates the `SafeDIOverrides` struct. Configuration type references
	/// use qualified names (e.g., `ChildA.SafeDIMockConfiguration`).
	private static func generateSafeDIOverridesStruct(
		rootChildren: [MockParameterNode],
		onlyIfAvailableOverrides: [OnlyIfAvailableOverride],
		indent: String,
	) -> String {
		let innerIndent = "\(indent)\(standardIndent)"
		let memberIndent = "\(innerIndent)\(standardIndent)"

		var lines = [String]()
		lines.append("\(indent)/// Overrides for the mock dependency tree.")
		lines.append("\(indent)struct SafeDIOverrides {")

		// Disambiguate root-level children property labels.
		let rootLabelMap = disambiguatePropertyLabels(for: rootChildren)

		// Generate SafeDIOverrides init with root-level children and onlyIfAvailable entries.
		lines.append("\(innerIndent)init(")
		var initParameters = rootChildren.map { child in
			let label = disambiguatedLabel(for: child, labelMap: rootLabelMap)
			if child.needsConfigurationStruct {
				return "\(memberIndent)\(label): \(child.configurationTypeName) = .init()"
			} else {
				let sendableAnnotation = child.requiresSendable ? "@Sendable " : ""
				return "\(memberIndent)\(label): (\(sendableAnnotation)\(child.builderClosureType))? = nil"
			}
		}
		for onlyIfAvailableOverride in onlyIfAvailableOverrides {
			initParameters.append("\(memberIndent)\(onlyIfAvailableOverride.name): \(onlyIfAvailableOverride.typeDescription.asSource) = nil")
		}
		lines.append(initParameters.joined(separator: ",\n"))
		lines.append("\(innerIndent)) {")
		for child in rootChildren {
			let label = disambiguatedLabel(for: child, labelMap: rootLabelMap)
			lines.append("\(memberIndent)self.\(label) = \(label)")
		}
		for onlyIfAvailableOverride in onlyIfAvailableOverrides {
			lines.append("\(memberIndent)self.\(onlyIfAvailableOverride.name) = \(onlyIfAvailableOverride.name)")
		}
		lines.append("\(innerIndent)}")

		// Generate stored properties.
		lines.append("")
		for child in rootChildren {
			let label = disambiguatedLabel(for: child, labelMap: rootLabelMap)
			if child.needsConfigurationStruct {
				lines.append("\(innerIndent)let \(label): \(child.configurationTypeName)")
			} else {
				let sendableAnnotation = child.requiresSendable ? "@Sendable " : ""
				lines.append("\(innerIndent)let \(label): (\(sendableAnnotation)\(child.builderClosureType))?")
			}
		}
		for onlyIfAvailableOverride in onlyIfAvailableOverrides {
			lines.append("\(innerIndent)let \(onlyIfAvailableOverride.name): \(onlyIfAvailableOverride.typeDescription.asSource)")
		}

		lines.append("\(indent)}")
		return lines.joined(separator: "\n")
	}

	/// Generates a single `SafeDIMockConfiguration` struct for a `MockParameterNode`.
	/// Closure fields are marked `@Sendable` only when `requiresSendable` is `true` —
	/// i.e., the struct's concrete type is referenced from a `SendableInstantiator`
	/// scope in at least one root. The flag is computed once across all roots so
	/// cross-root struct-per-type dedup produces a consistent annotation.
	private static func generateConfigurationStruct(
		for node: MockParameterNode,
		indent: String,
		cycleEdges: Set<CycleEdge>,
		requiresSendable: Bool,
	) -> String {
		let innerIndent = "\(indent)\(standardIndent)"
		let sendableAnnotation = requiresSendable ? "@Sendable " : ""
		var lines = [String]()

		lines.append("\(indent)/// Configuration for how this type is constructed within a mock tree.")
		lines.append("\(indent)struct \(MockParameterNode.configurationStructName) {")

		// Build init parameters in order: children, defaults, builder (last).
		var initParameters = [String]()
		var assignments = [String]()
		var storedProperties = [String]()

		// Child edge parameters (disambiguated if labels collide).
		// Exclude back-edges from `cycleEdges` — including them would nest a
		// configuration struct that transitively contains itself, which Swift
		// rejects as an infinite-size value type. `cycleEdges` is computed once
		// globally (one back-edge set per strongly-connected component), so the
		// same edges are filtered no matter which root contributes the struct —
		// every root produces the same struct shape for a given type.
		// Only property children surface on the configuration struct; aliases
		// are emitted as inline `let` bindings in the mock body.
		let parentTypeName = node.concreteType.asSource
		let nonCycleChildren = node.propertyChildren.filter { child in
			!cycleEdges.contains(CycleEdge(
				parent: parentTypeName,
				child: child.concreteType.asSource,
			))
		}
		let childLabelMap = disambiguatePropertyLabels(for: nonCycleChildren)
		for child in nonCycleChildren {
			let label = disambiguatedLabel(for: child, labelMap: childLabelMap)
			if child.needsConfigurationStruct {
				initParameters.append("\(innerIndent)\(standardIndent)\(label): \(child.configurationTypeName) = .init()")
				storedProperties.append("\(innerIndent)let \(label): \(child.configurationTypeName)")
			} else {
				// A leaf child field also needs `@Sendable` when the child itself
				// is reached sendably — e.g. a `SendableInstantiator` dependency on
				// a non-sendable parent. `generateInstantiatorBinding` later wraps
				// such children in a `@Sendable` local function, which would fail
				// to capture a non-sendable override closure.
				let childSendable = (requiresSendable || child.requiresSendable) ? "@Sendable " : ""
				initParameters.append("\(innerIndent)\(standardIndent)\(label): (\(childSendable)\(child.builderClosureType))? = nil")
				storedProperties.append("\(innerIndent)let \(label): (\(childSendable)\(child.builderClosureType))?")
			}
			assignments.append("\(innerIndent)\(standardIndent)self.\(label) = \(label)")
		}

		// Default-valued parameters.
		for defaultParameter in node.defaultParameters {
			let typeSource = defaultParameter.typeDescription.asSource
			// Only add @Sendable if this struct requires it AND the type doesn't already have it.
			let closureSendable = (requiresSendable && !typeSource.contains("@Sendable")) ? "@Sendable " : ""
			if defaultParameter.isClosureType {
				initParameters.append("\(innerIndent)\(standardIndent)\(defaultParameter.label): \(closureSendable)@escaping \(typeSource) = \(defaultParameter.defaultExpression)")
				storedProperties.append("\(innerIndent)let \(defaultParameter.label): \(closureSendable)\(typeSource)")
			} else {
				initParameters.append("\(innerIndent)\(standardIndent)\(defaultParameter.label): \(typeSource) = \(defaultParameter.defaultExpression)")
				storedProperties.append("\(innerIndent)let \(defaultParameter.label): \(typeSource)")
			}
			assignments.append("\(innerIndent)\(standardIndent)self.\(defaultParameter.label) = \(defaultParameter.label)")
		}

		// Builder parameter (always last, unlabeled). Optional with nil default so that
		// the default construction (which may be @MainActor) is called in mock()
		// rather than referenced in this nonisolated init.
		let closureType = node.concreteBuilderClosureType
		initParameters.append("\(innerIndent)\(standardIndent)_ safeDIBuilder: (\(sendableAnnotation)\(closureType))? = nil")
		assignments.append("\(innerIndent)\(standardIndent)self.safeDIBuilder = safeDIBuilder")
		storedProperties.append("\(innerIndent)/// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.")
		storedProperties.append("\(innerIndent)let safeDIBuilder: (\(sendableAnnotation)\(closureType))?")

		// Emit init.
		lines.append("\(innerIndent)init(")
		lines.append(initParameters.joined(separator: ",\n"))
		lines.append("\(innerIndent)) {")
		lines.append(contentsOf: assignments)
		lines.append("\(innerIndent)}")

		// Emit stored properties.
		lines.append("")
		lines.append(contentsOf: storedProperties)

		lines.append("\(indent)}")
		return lines.joined(separator: "\n")
	}

	// MARK: Mock Body Generation

	/// Reads `safeDIOverrides` values into locals declared before the outermost
	/// `@Sendable` builder function of a sendable subtree.
	///
	/// `SafeDIOverrides` is not `Sendable` whenever any of its stored closures
	/// is not, so code lexically inside a `@Sendable` function — at any depth,
	/// including inside builder functions of nested instantiators — must not
	/// reference it. Every value in a sendable subtree's configuration is
	/// `Sendable` (its closures are generated `@Sendable`), so each value is
	/// read into a local outside the function and the function captures the
	/// local instead.
	///
	/// The mock body walk asks the extractor for a local each time it would
	/// otherwise read `safeDIOverrides`, so every extracted local has exactly
	/// one reader. The builder that created the extractor then emits the
	/// recorded `let <localName> = <expression>` lines before its function.
	private final class SendableOverrideExtractor {
		init(functionName: String) {
			self.functionName = functionName
		}

		/// Records that `expression` is read into a local named after the
		/// outermost `@Sendable` function, and returns that local's name.
		func extract(_ expression: String, localNameSuffix: String) -> String {
			let localName = "\(functionName)__\(localNameSuffix)"
			extractions.append((localName: localName, expression: expression))
			return localName
		}

		/// The `(localName, expression)` pairs recorded so far, in the order
		/// they were extracted.
		private(set) var extractions = [(localName: String, expression: String)]()

		private let functionName: String
	}

	/// Generates the mock body bindings for the tree. Walks the items in
	/// production's topological order, emitting `let` bindings that call through
	/// `safeDIOverrides.path.safeDIBuilder(...)` for properties and
	/// `let <alias>: <Type> = <fulfilling>` for aliases.
	///
	/// For leaf constant nodes: `let {label} = if let safeDIBuilder = safeDIOverrides.{path} { safeDIBuilder({arguments}) } else { {Type}({labeled arguments}) }`
	/// For constant nodes with children: a nested helper function that returns the property type.
	/// For Instantiator nodes: an inner builder function plus `Instantiator<T>(...)` wrapping.
	/// When `sendableOverrideExtractor` is set, the bindings are lexically inside a
	/// `@Sendable` function, so every `safeDIOverrides` read is routed through the
	/// extractor and references the resulting local instead.
	/// `enclosingFunctionNames` is the `BuilderFunctionNames.enclosingFunctionNames` of the
	/// scope whose body holds `items`.
	private static func generateMockBodyBindings(
		items: [MockTreeItem],
		parentPath: String,
		indent: String,
		ancestorTypes: Set<String> = [],
		sendableOverrideExtractor: SendableOverrideExtractor? = nil,
		flatParameterDisambiguationMap: [String: [TypeDescription: String]] = [:],
		enclosingFunctionNames: [Property: String] = [:],
		lazilyInstantiatedBindingNames: [String: [TypeDescription: String]] = [:],
		parentConcreteType: String?,
		cycleEdges: Set<CycleEdge>,
		overridePathReachable: Bool,
	) -> [String] {
		var lines = [String]()

		// Disambiguate sibling labels at this level (property children only —
		// aliases don't participate in sibling disambiguation).
		let propertyNodes = items.propertyNodes
		let labelMap = disambiguatePropertyLabels(for: propertyNodes)
		// Each builder function is named after its disambiguated label, unless a cycle-closing
		// scope beneath this level refers to an enclosing function of that name.
		// Nearly every level holds no node of a cycle, and its nodes keep their names.
		let builderFunctionNamesByNode = propertyNodes.contains(where: { !$0.cycleClosingProperties.isEmpty || $0.isReferencedByCycleClosingScope })
			? builderFunctionNames(
				for: propertyNodes.map { node in
					let disambiguated = disambiguatedLabel(for: node, labelMap: labelMap)
					return BuilderFunctionCandidate(
						property: node.property,
						name: disambiguated == node.propertyLabel ? nil : Self.functionName(toBuildPropertyNamed: disambiguated),
						declaresFunction: !node.isPropertyCycle,
						cycleClosingProperties: node.cycleClosingProperties,
						isReferencedByCycleClosingScope: node.isReferencedByCycleClosingScope,
					)
				},
				enclosingFunctionNames: enclosingFunctionNames,
			)
			: nil
		var propertyNodeIndex = 0

		// Merge sibling-level disambiguations into the receiver-disambiguation
		// map so consumers can rebind colliding sibling names back to their raw
		// labels via `emitReceiverBindings`, and construction arguments resolve
		// via Swift lexical scoping inside a wrapper function body.
		var combinedDisambiguationMap = flatParameterDisambiguationMap
		mergeSiblingDisambiguations(into: &combinedDisambiguationMap, for: propertyNodes)

		for item in items {
			switch item {
			case let .alias(alias):
				lines.append(emitAliasBinding(
					alias,
					flatParameterDisambiguationMap: combinedDisambiguationMap,
					lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames,
					indent: indent,
				))
			case let .property(node):
				let nodeTypeKey = node.instantiatedTypeDescription.asSource
				let isCycleNode = ancestorTypes.contains(nodeTypeKey)
				let builderFunctionNames = builderFunctionNamesByNode?[propertyNodeIndex] ?? BuilderFunctionNames()
				propertyNodeIndex += 1

				// A back-edge from parentConcreteType to this node means this node
				// was filtered out of the parent's SafeDIMockConfiguration struct —
				// so its override path is unreachable here. Descendants of an
				// unreachable node stay unreachable (path can't be recovered).
				let nodeConcreteType = node.concreteType.asSource
				let isBackEdge = parentConcreteType.map {
					cycleEdges.contains(CycleEdge(parent: $0, child: nodeConcreteType))
				} ?? false
				let thisOverrideReachable = overridePathReachable && !isBackEdge

				let disambiguated = disambiguatedLabel(for: node, labelMap: labelMap)
				let nodePath = "\(parentPath).\(disambiguated)"
				// When this node's label collides with a sibling, use the
				// disambiguated label for the outer `let` binding and for the
				// inner `__safeDI_<name>` function so neither redeclares across
				// siblings. Consumer nodes reach the value either directly (when
				// the dep also resolves to this sibling) via a rebinding emitted
				// by `emitReceiverBindings` inside the consumer's wrapper.
				let outerBindingName = disambiguated
				// A cycle-closing node declares no function: it refers to the enclosing one with its property.
				let functionName = if node.isPropertyCycle {
					builderFunctionNames.enclosingFunctionNames[node.property, default: Self.functionName(toBuild: node.property)]
				} else {
					builderFunctionNames.functionName ?? Self.functionName(toBuildPropertyNamed: disambiguated)
				}

				let relativePath = nodePath
					.replacingOccurrences(of: "safeDIOverrides.", with: "")
					.replacingOccurrences(of: ".", with: "_")

				// The optional override closure to consult, or `nil` when there is
				// none to consult: a cycle node constructs itself directly, and a
				// node whose override path was pruned from its parent's
				// `SafeDIMockConfiguration` has no override slot to read. Inside a
				// `@Sendable` function the override is read into a local outside
				// that function, so reference that local instead.
				let overrideExpression: String? = if isCycleNode || !thisOverrideReachable {
					nil
				} else if let sendableOverrideExtractor {
					sendableOverrideExtractor.extract(
						node.overridePath(nodePath: nodePath),
						localNameSuffix: "\(relativePath)_safeDIBuilder",
					)
				} else {
					node.overridePath(nodePath: nodePath)
				}

				let arguments = resolveBuilderArguments(
					for: node,
					nodePath: nodePath,
					lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames,
					sendableOverrideExtractor: sendableOverrideExtractor,
					overrideReachable: thisOverrideReachable,
				)
				let constructionExpression = node.constructionExpression(
					overrideExpression: overrideExpression,
					arguments: arguments,
					overrideReachable: thisOverrideReachable,
				)

				if node.isInstantiator {
					// For Instantiator nodes, children are generated INSIDE the builder
					// function because they may depend on forwarded properties that are
					// only available as function parameters. This mirrors the production
					// code which builds the entire subtree inside the builder function.
					var childAncestors = ancestorTypes
					childAncestors.insert(nodeTypeKey)
					lines.append(contentsOf: generateInstantiatorBinding(
						for: node,
						outerBindingName: outerBindingName,
						functionName: functionName,
						enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames,
						nodePath: nodePath,
						overrideExpression: overrideExpression,
						arguments: arguments,
						indent: indent,
						ancestorTypes: childAncestors,
						sendableOverrideExtractor: sendableOverrideExtractor,
						flatParameterDisambiguationMap: combinedDisambiguationMap,
						lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames,
						cycleEdges: cycleEdges,
						overridePathReachable: thisOverrideReachable,
					))
				} else if node.requiresFunctionWrapper || hasDisambiguatedReceiver(node, flatParameterDisambiguationMap: combinedDisambiguationMap) {
					// Constant node that needs a dedicated Swift scope — either for its
					// own children/defaults/cycle, for aliased deps, or to host the
					// `let <label>: <Type> = <disambiguatedName>` binding that aliases a
					// disambiguated flat mock parameter back to its natural label. A
					// function scope keeps child bindings from colliding with siblings'
					// child bindings that share the same property label and gives these
					// receiver bindings a place to live.
					let propertyTypeName = node.instantiatedTypeDescription.asSource
					let innerIndent = "\(indent)\(standardIndent)"
					let functionDisambiguationMap = removingRenames(
						hiddenByDeclarationsOf: node.children,
						from: combinedDisambiguationMap,
					)

					let receiverBindings = emitReceiverBindings(
						for: node.dependencies,
						unavailableProperties: node.unavailableProperties,
						lazilyInstantiatedInstanceProperties: node.lazilyInstantiatedInstanceProperties,
						flatParameterDisambiguationMap: functionDisambiguationMap,
						indent: innerIndent,
					)

					var childAncestors = ancestorTypes
					childAncestors.insert(nodeTypeKey)
					let childBindings = generateMockBodyBindings(
						items: node.children,
						parentPath: nodePath,
						indent: innerIndent,
						ancestorTypes: childAncestors,
						sendableOverrideExtractor: sendableOverrideExtractor,
						flatParameterDisambiguationMap: functionDisambiguationMap,
						enclosingFunctionNames: builderFunctionNames.enclosingFunctionNames,
						lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames,
						parentConcreteType: node.concreteType.asSource,
						cycleEdges: cycleEdges,
						overridePathReachable: thisOverrideReachable,
					)

					// The function's return type gives both branches of the `if`
					// expression a contextual type, so no annotation is needed.
					lines.append("\(indent)func \(functionName)() -> \(propertyTypeName) {")
					lines.append(contentsOf: receiverBindings)
					lines.append(contentsOf: childBindings)
					lines.append("\(innerIndent)return \(constructionExpression)")
					lines.append("\(indent)}")
					lines.append("\(indent)let \(outerBindingName): \(propertyTypeName) = \(functionName)()")
				} else {
					// Leaf constant node — flat binding, no scoping needed.
					let typeAnnotation = overrideExpression == nil ? "" : node.overriddenBindingTypeAnnotation
					lines.append("\(indent)let \(outerBindingName)\(typeAnnotation) = \(constructionExpression)")
				}
			}
		}

		return lines
	}

	/// Emits a single `let <alias>: <Type> = <fulfillingLabel>` line, resolving
	/// the fulfilling label through `flatParameterDisambiguationMap` when the
	/// fulfiller is a renamed flat mock parameter or a disambiguated sibling.
	/// The line refers to the alias's declaration as the production
	/// dependency-tree output does.
	private static func emitAliasBinding(
		_ alias: MockAliasNode,
		flatParameterDisambiguationMap: [String: [TypeDescription: String]],
		lazilyInstantiatedBindingNames: [String: [TypeDescription: String]],
		indent: String,
	) -> String {
		let fulfillingLabel = alias.fulfillingLabel
		let fulfillingValue = if alias.fulfillingPropertyIsLazilyInstantiatedInstance {
			// The instance is read from the `LazilyInstantiated` binding, which a label collision may have renamed.
			"\(disambiguatedLazilyInstantiatedBinding(named: fulfillingLabel, withInstanceOfType: alias.fulfillingTypeDescription.unwrapped, disambiguationMap: flatParameterDisambiguationMap)?.name ?? fulfillingLabel).\(Dependency.lazilyInstantiatedInstancePropertyName)"
		} else {
			flatParameterDisambiguationMap[fulfillingLabel]?[alias.fulfillingTypeDescription]
				?? lazilyInstantiatedBindingNames[fulfillingLabel]?[alias.fulfillingTypeDescription]
				?? fulfillingLabel
		}
		return referencingDeclaration(
			of: aliasDeclaration(
				of: alias.property,
				fulfilledBy: fulfillingValue,
				ofType: alias.fulfillingTypeDescription,
				erasedToConcreteExistential: alias.erasedToConcreteExistential,
				fulfillingValueMayBeOptional: alias.onlyIfAvailable,
			),
			by: alias.declarationReference,
		)
		.split(separator: "\n")
		.map { "\(indent)\($0)" }
		.joined(separator: "\n")
	}

	/// Renames the aliases among `items` whose label is in `redeclaredNames`, so that their
	/// bindings do not redeclare a binding in the same scope.
	///
	/// Each renamed alias is bound as `<label>_<simplified type’s asIdentifier>`, with underscores
	/// appended until the name is neither in `reservedNames` nor given to an earlier alias.
	/// - Returns: `items` with those aliases renamed, and each new name keyed by the alias's
	///   label and type, the keys the disambiguation maps use.
	private static func renamingAliases(
		in items: [MockTreeItem],
		thatRedeclare redeclaredNames: Set<String>,
		reservedNames: Set<String>,
	) -> (items: [MockTreeItem], bindingNames: [String: [TypeDescription: String]]) {
		var takenNames = reservedNames
		var bindingNames = [String: [TypeDescription: String]]()
		let renamedItems = items.map { item -> MockTreeItem in
			guard case let .alias(alias) = item,
			      redeclaredNames.contains(alias.property.label)
			else { return item }
			var bindingName = "\(alias.property.label)_\(alias.property.typeDescription.simplified.asIdentifier)"
			while !takenNames.insert(bindingName).inserted {
				bindingName += "_"
			}
			bindingNames[alias.property.label, default: [:]][alias.property.typeDescription] = bindingName
			return .alias(MockAliasNode(
				property: Property(label: bindingName, typeDescription: alias.property.typeDescription),
				erasedToConcreteExistential: alias.erasedToConcreteExistential,
				onlyIfAvailable: alias.onlyIfAvailable,
				fulfillingLabel: alias.fulfillingLabel,
				fulfillingTypeDescription: alias.fulfillingTypeDescription,
				fulfillingPropertyIsLazilyInstantiatedInstance: alias.fulfillingPropertyIsLazilyInstantiatedInstance,
				declarationReference: alias.declarationReference,
			))
		}
		return (renamedItems, bindingNames)
	}

	/// `disambiguationMap` without the renames that a nested scope's declarations hide: those of the
	/// properties `children` declare – each property node's property and each alias's property – and of
	/// `parameters`, the forwarded properties a builder function is handed.
	///
	/// A receiver of `x: X` or `x: X?` in a scope that declares, or is handed as a parameter, `x: X` resolves
	/// to that declaration by its label, as in production, not to a renamed flat parameter or override of
	/// the same property that an enclosing scope binds.
	private static func removingRenames(
		hiddenByDeclarationsOf children: [MockTreeItem],
		parameters: [Property] = [],
		from disambiguationMap: [String: [TypeDescription: String]],
	) -> [String: [TypeDescription: String]] {
		guard !disambiguationMap.isEmpty else { return disambiguationMap }
		var disambiguationMap = disambiguationMap
		// Writing through a subscript copies the map even when nothing is removed, so look first.
		func removeRenames(of property: Property) {
			guard let renames = disambiguationMap[property.label] else { return }
			let optionalTypeDescription = TypeDescription.optional(property.typeDescription)
			guard renames[property.typeDescription] != nil || renames[optionalTypeDescription] != nil else { return }
			disambiguationMap[property.label]?[property.typeDescription] = nil
			disambiguationMap[property.label]?[optionalTypeDescription] = nil
		}
		for parameter in parameters {
			removeRenames(of: parameter)
		}
		for child in children {
			switch child {
			case let .property(node):
				removeRenames(of: Property(label: node.propertyLabel, typeDescription: node.typeDescription))
			case let .alias(alias):
				removeRenames(of: alias.property)
			}
		}
		return disambiguationMap
	}

	/// Resolves the positional arguments for a builder call.
	/// Every dependency is referenced by its bare property label at this scope —
	/// `.aliased` and disambiguated `.received` deps are bound as `let`s by
	/// `emitReceiverBindings` in the enclosing wrapper; `.instantiated` is bound
	/// as a sibling `let`; `.forwarded` is bound as a function parameter;
	/// undisambiguated `.received` labels reach a flat mock parameter (or
	/// ancestor tree binding) via Swift lexical scoping. The node's
	/// `unavailableProperties` are passed `nil` instead. Non-dependency
	/// arguments come from `SafeDIOverrides` storage. Unlabeled defaults are
	/// omitted entirely so Swift's default-argument thunk fires in the callee.
	private static func resolveBuilderArguments(
		for node: MockParameterNode,
		nodePath: String,
		lazilyInstantiatedBindingNames: [String: [TypeDescription: String]],
		sendableOverrideExtractor: SendableOverrideExtractor?,
		overrideReachable: Bool,
	) -> [String] {
		let dependenciesByLabel = Dictionary(
			uniqueKeysWithValues: node.dependencies.map { ($0.property.label, $0) },
		)
		let relativePath = nodePath
			.replacingOccurrences(of: "safeDIOverrides.", with: "")
			.replacingOccurrences(of: ".", with: "_")
		let argumentsToSurface = overrideReachable
			? node.callSiteArguments
			: node.callSiteArgumentsForPrunedOverride
		return argumentsToSurface.map { argument in
			if let dependency = dependenciesByLabel[argument.innerLabel] {
				if node.unavailableProperties.contains(dependency.property) {
					"nil"
				} else if dependency.source.isReceived,
				          node.lazilyInstantiatedInstanceProperties.contains(dependency.property.asUnwrappedProperty)
				{
					"\(argument.innerLabel).\(Dependency.lazilyInstantiatedInstancePropertyName)"
				} else if dependency.source.isReceived,
				          let bindingName = lazilyInstantiatedBindingNames[argument.innerLabel]?[dependency.property.typeDescription]
				{
					// The `LazilyInstantiated` the mock wrapped around the instance it was passed.
					bindingName
				} else {
					argument.innerLabel
				}
			} else if let sendableOverrideExtractor {
				sendableOverrideExtractor.extract(
					"\(nodePath).\(argument.label)",
					localNameSuffix: "\(relativePath)_\(argument.label)",
				)
			} else {
				"\(nodePath).\(argument.label)"
			}
		}
	}

	/// Generates the wrapping bindings for an Instantiator-family node
	/// (`Instantiator`, `SendableInstantiator`, `ErasedInstantiator`, or
	/// `SendableErasedInstantiator`). Produces an inner builder function plus a
	/// `let {label} = <WrapperType>(...)` construction.
	///
	/// `overrideExpression` is the optional override closure the inner builder
	/// consults, or `nil` when the node constructs itself directly (see
	/// `MockParameterNode.constructionExpression`). `sendableOverrideExtractor`
	/// is set when the binding is already inside a `@Sendable` function; a
	/// sendable binding outside one starts its own extractor and re-reads its
	/// override and `arguments` through it.
	private static func generateInstantiatorBinding(
		for node: MockParameterNode,
		outerBindingName: String,
		functionName: String,
		enclosingFunctionNames: [Property: String],
		nodePath: String,
		overrideExpression: String?,
		arguments: [String],
		indent: String,
		ancestorTypes: Set<String>,
		sendableOverrideExtractor: SendableOverrideExtractor?,
		flatParameterDisambiguationMap: [String: [TypeDescription: String]],
		lazilyInstantiatedBindingNames: [String: [TypeDescription: String]],
		cycleEdges: Set<CycleEdge>,
		overridePathReachable: Bool,
	) -> [String] {
		let forwardedProperties = node.forwardedProperties.sorted()
		let propertyType = node.typeDescription.propertyType
		let innerIndent = "\(indent)\(standardIndent)"
		// The builder function's parameters and bindings hide the renames of their properties.
		let builderDisambiguationMap = removingRenames(
			hiddenByDeclarationsOf: node.children,
			parameters: forwardedProperties,
			from: flatParameterDisambiguationMap,
		)

		// Emit disambiguated-receiver rebinds inside the inner builder function
		// so construction arguments resolve by bare label via Swift lexical
		// scoping. Aliases on this node are handled as child items in the tree
		// and emitted in production's topological order by
		// `generateMockBodyBindings` below.
		let receiverBindings = emitReceiverBindings(
			for: node.dependencies,
			unavailableProperties: node.unavailableProperties,
			lazilyInstantiatedInstanceProperties: node.lazilyInstantiatedInstanceProperties,
			flatParameterDisambiguationMap: builderDisambiguationMap,
			indent: innerIndent,
		)

		// Build the inner function parameter list (forwarded properties).
		let functionArguments = if forwardedProperties.isEmpty {
			""
		} else {
			forwardedProperties.initializerFunctionParameters.map(\.description).joined()
		}

		// Build the forwarded arguments for the Instantiator closure call.
		let forwardedPropertiesHaveLabels = forwardedProperties.count > 1
		let forwardedArguments = forwardedProperties
			.map {
				if forwardedPropertiesHaveLabels {
					"\($0.label): $0.\($0.label)"
				} else {
					"\($0.label): $0"
				}
			}
			.joined(separator: ", ")

		let functionDecorator = if propertyType.isSendable {
			"@Sendable "
		} else {
			""
		}

		var lines = [String]()

		// Emit the inner builder function (unless it's a property cycle).
		// Children are generated INSIDE the function body because they may
		// depend on forwarded properties that are only available as parameters.
		if !node.isPropertyCycle {
			// A `@Sendable` function that is not already inside another one
			// starts a new extraction: every `safeDIOverrides` read in its body,
			// including inside nested builder functions at any depth, becomes a
			// local declared before it. Inside an enclosing `@Sendable` function,
			// reads keep flowing to the outermost function's extractor, whose
			// locals are already in scope.
			let startedSendableOverrideExtractor: SendableOverrideExtractor? = if sendableOverrideExtractor == nil, propertyType.isSendable {
				SendableOverrideExtractor(functionName: functionName)
			} else {
				nil
			}

			// Generate children's bindings inside the function body.
			// Include this node's type in ancestors so self-referencing
			// cycles (e.g., Instantiator<Self>) are detected.
			var functionAncestors = ancestorTypes
			functionAncestors.insert(node.instantiatedTypeDescription.asSource)
			let childBindings = generateMockBodyBindings(
				items: node.children,
				parentPath: nodePath,
				indent: innerIndent,
				ancestorTypes: functionAncestors,
				sendableOverrideExtractor: sendableOverrideExtractor ?? startedSendableOverrideExtractor,
				flatParameterDisambiguationMap: builderDisambiguationMap,
				enclosingFunctionNames: enclosingFunctionNames,
				lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames,
				parentConcreteType: node.concreteType.asSource,
				cycleEdges: cycleEdges,
				overridePathReachable: overridePathReachable,
			)

			let functionOverrideExpression: String?
			let functionConstructionArguments: [String]
			if let startedSendableOverrideExtractor {
				// The caller read this node's own override and default arguments
				// from `safeDIOverrides` because it is outside any `@Sendable`
				// function; the construction below is inside this one, so read
				// them into locals too. Override closures are read as optionals;
				// the function body unwraps them and otherwise calls the default
				// construction directly.
				functionConstructionArguments = resolveBuilderArguments(
					for: node,
					nodePath: nodePath,
					lazilyInstantiatedBindingNames: lazilyInstantiatedBindingNames,
					sendableOverrideExtractor: startedSendableOverrideExtractor,
					overrideReachable: overridePathReachable,
				)
				functionOverrideExpression = overrideExpression.map {
					startedSendableOverrideExtractor.extract($0, localNameSuffix: "safeDIBuilder")
				}
				for extraction in startedSendableOverrideExtractor.extractions {
					lines.append("\(indent)let \(extraction.localName) = \(extraction.expression)")
				}
			} else {
				functionOverrideExpression = overrideExpression
				functionConstructionArguments = arguments
			}

			let functionReturnType = node.instantiatedTypeDescription.asSource
			lines.append("\(indent)\(functionDecorator)func \(functionName)(\(functionArguments)) -> \(functionReturnType) {")
			lines.append(contentsOf: receiverBindings)
			lines.append(contentsOf: childBindings)

			// Swift's implicit-return rule only applies when the function
			// body is a single expression. Receiver bindings and child
			// bindings both add extra statements, so either one forces an
			// explicit `return`. The function's return type gives both
			// branches of an `if` expression a contextual type.
			let returnKeyword = childBindings.isEmpty && receiverBindings.isEmpty ? "" : "return "
			let constructionExpression = node.constructionExpression(
				overrideExpression: functionOverrideExpression,
				arguments: functionConstructionArguments,
				overrideReachable: overridePathReachable,
			)
			lines.append("\(innerIndent)\(returnKeyword)\(constructionExpression)")
			lines.append("\(indent)}")
		}

		// Emit the Instantiator/ErasedInstantiator construction.
		let unwrappedTypeDescription = node.typeDescription.unwrapped.asSource

		// The builder function now returns the property type directly (including
		// wrapping for erasedToConcreteExistential), so no outer wrapping needed.
		let instantiatorConstruction = if forwardedArguments.isEmpty {
			"\(unwrappedTypeDescription)(\(functionName))"
		} else {
			"""
			\(unwrappedTypeDescription) {
			\(indent)\(standardIndent)\(functionName)(\(forwardedArguments))
			\(indent)}
			"""
		}

		lines.append("\(indent)let \(outerBindingName) = \(instantiatorConstruction)")

		return lines
	}

	private func wrapInConditionalCompilation(
		_ code: String,
		mockConditionalCompilation: String?,
	) -> String {
		if let mockConditionalCompilation {
			"#if \(mockConditionalCompilation)\n\(code)\n#endif"
		} else {
			code
		}
	}

	// MARK: GenerationError

	private enum GenerationError: Error, CustomStringConvertible {
		case erasedInstantiatorGenericDoesNotMatch(property: Property, instantiable: Instantiable)

		var description: String {
			switch self {
			case let .erasedInstantiatorGenericDoesNotMatch(property, instantiable):
				"Property `\(property.asSource)` on \(instantiable.concreteInstantiable.asSource) incorrectly configured. Property should instead be of type `\(Dependency.erasedInstantiatorType)<\(instantiable.concreteInstantiable.asSource).ForwardedProperties, \(property.typeDescription.asInstantiatedType.asSource)>`."
			}
		}
	}
}

// MARK: - [MockTreeItem]

extension [ScopeGenerator.MockTreeItem] {
	/// Property-typed children only. Aliases are plain `let` bindings and do
	/// not participate in `SafeDIMockConfiguration` / `SafeDIOverrides` or
	/// sibling disambiguation.
	fileprivate var propertyNodes: [ScopeGenerator.MockParameterNode] {
		compactMap {
			if case let .property(node) = $0 {
				node
			} else {
				nil
			}
		}
	}
}

// MARK: - Instantiable

extension Instantiable {
	fileprivate static let incorrectlyConfiguredComment = "/* @Instantiable type is incorrectly configured. Fix errors from @Instantiable macro to fix this error. */"

	fileprivate func generateArgumentList(
		unavailableProperties: Set<Property>? = nil,
		lazilyInstantiatedInstanceProperties: Set<Property> = [],
		forMockGeneration: Bool = false,
		useMockInitializer: Bool = true,
	) throws -> String {
		let initializerToUse: Initializer? = if forMockGeneration, useMockInitializer, let mockInitializer {
			// User-defined mock handles construction — use its parameter list
			// (may be empty for no-arg mock methods).
			mockInitializer
		} else {
			initializer
		}
		if forMockGeneration {
			// In the simple mock case (no dependencies, no tree), the initializer is always present
			// and covers all dependencies. The SafeDIOverrides pipeline handles complex cases.
			guard let initializerToUse else { return "" }
			return initializerToUse
				.createMockInitializerArgumentList(
					given: dependencies,
					unavailableProperties: unavailableProperties,
				)
		} else {
			return try initializerToUse?
				.createInitializerArgumentList(
					given: dependencies,
					unavailableProperties: unavailableProperties,
					lazilyInstantiatedInstanceProperties: lazilyInstantiatedInstanceProperties,
				) ?? Self.incorrectlyConfiguredComment
		}
	}
}
