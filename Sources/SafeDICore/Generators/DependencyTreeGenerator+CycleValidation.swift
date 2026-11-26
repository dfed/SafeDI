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

extension DependencyTreeGenerator {
	/// Instantiated children of one scope that require one another in a cycle: each child's tree requires
	/// (not `onlyIfAvailable`) the next child, and the last child's tree requires the first.
	struct ChildrenRequiringEachOther {
		/// The first child in the cycle.
		let instantiated: Property
		/// The property through which each child's tree receives the next child, ending with the one through
		/// which the last child's tree receives the first: the next child's property, or an alias of it that
		/// the scope declares.
		let receivedPropertyChain: [Property]
		/// The receiver in the last child's tree through which that tree requires the first child, found by
		/// `requiredReceiver` for the last property in `receivedPropertyChain`.
		let closingReceiver: RequiredReceiver?
		/// The `onlyIfAvailable` aliases the scope declares that `receivedPropertyChain` holds, in chain order.
		let requiredOnlyIfAvailableAliases: [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias]

		/// The error reporting these children, at `closingReceiver`. When the last child's tree receives the
		/// first child through an alias or unwrapped, the chain ends with the first child's own property, so
		/// it reads back to where it started. The `onlyIfAvailable` aliases in the last child's tree through
		/// which the closing receive requires the first child follow the scope's own, in chain order.
		var error: DependencyTreeGeneratorError {
			DependencyTreeGeneratorError.dependencyReceivedInSameChainItIsInstantiated(
				instantiated: instantiated,
				receivedPropertyChain: receivedPropertyChain + (receivedPropertyChain[receivedPropertyChain.count - 1] == instantiated ? [] : [instantiated]),
				declarationLocation: closingReceiver?.dependency.declarationLocation,
				// The chain names every property as it is declared, so there is nothing to explain.
				lazilyInstantiatedProperties: [],
				requiredOnlyIfAvailableAliases: requiredOnlyIfAvailableAliases + (closingReceiver?.requiredOnlyIfAvailableAliases ?? []),
			)
		}
	}

	/// A dependency through which a tree requires a property from outside the tree, found by `requiredReceiver`.
	struct RequiredReceiver {
		let dependency: Dependency
		/// The `onlyIfAvailable` aliases the tree declares through which `dependency` requires the property, outermost
		/// first: each renames the property that the next, or `dependency`, requires. Empty when `dependency` receives
		/// the property itself.
		let requiredOnlyIfAvailableAliases: [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias]
	}

	/// A child of a scope that a property names, with how directly it names the child: the lower `directness`, the
	/// more directly.
	private struct NamedChild {
		let index: Int
		let directness: Int
	}

	/// The scopes `validateChildrenDoNotRequireEachOther` has validated across the trees it is given.
	struct ChildrenRequiringEachOtherValidation {
		/// The scopes whose children, and whose trees' children, are known not to require one another. Which children of
		/// a scope require one another depends on the scope's tree alone: a requirement through an `onlyIfAvailable` alias
		/// stops at the nearest declaration of its label, wherever the scope is built.
		var validatedScopes = Set<Scope>()
	}

	/// The instantiated children of `scope` that require one another in a cycle, if any:
	/// each child's tree requires (not `onlyIfAvailable`) a sibling that, directly or
	/// through other siblings, requires it. Such children cannot be ordered so that each
	/// is built after the siblings it receives — whatever their property types, since an
	/// `Instantiator` captures what its tree receives when it is created. A child's tree requires the
	/// property an `onlyIfAvailable` alias in it is bound from when a receiver requires the alias, where
	/// the nearest declaration of that property's label is a sibling (see
	/// `ScopeGenerator.requiredAliasFulfillingProperties`).
	static func childrenRequiringEachOther(
		in scope: Scope,
		cache: inout ReceivedPropertiesCache,
	) -> ChildrenRequiringEachOther? {
		var children = [(property: Property, scope: Scope)]()
		for case let .instantiated(property, childScope, _) in scope.propertiesToGenerate {
			children.append((property, childScope))
		}
		// A property names a child most directly as the child's own property, then as the property that receives
		// its instance when it is lazily instantiated, then as an alias the scope declares, in declaration order.
		var childByProperty = [Property: NamedChild]()
		for (index, child) in children.enumerated() {
			childByProperty[child.property] = NamedChild(index: index, directness: 0)
			// A lazily instantiated child is also received by value, as the instance it creates.
			if let instanceProperty = child.property.asLazilyInstantiatedInstanceProperty {
				childByProperty[instanceProperty] = NamedChild(index: index, directness: 1)
			}
		}
		/// The child that declares the label of `fulfillingProperty`, which an `onlyIfAvailable` alias of it is bound
		/// from where that child provides a form the alias reads (see `ScopeGenerator.provides(_:aFormReadBy:)`).
		func childBindingOnlyIfAvailableAlias(of fulfillingProperty: Property) -> NamedChild? {
			for (index, child) in children.enumerated()
				where child.property.label == fulfillingProperty.label && ScopeGenerator.provides(child.property, aFormReadBy: fulfillingProperty)
			{
				return NamedChild(index: index, directness: child.property == fulfillingProperty ? 0 : 1)
			}
			return nil
		}
		// A child's tree that requires an alias the scope declares requires the child the alias is assigned from. No
		// alias of the scope renames another (SafeDITool rejects that before it validates a tree that builds the
		// scope). An `onlyIfAvailable` alias is bound for a receiver that requires it from the child that declares
		// its fulfilling property's label, so it is assigned after that child too.
		var aliasCount = 0
		var onlyIfAvailableAliasFulfillingPropertyByProperty = [Property: Property]()
		var aliasedChildByProperty = [Property: NamedChild]()
		// A rename that erases an instantiator is no instantiator, nor is one only if available of anything but an
		// instantiator a child builds, which it is then always bound from: a value on a cycle through it.
		var valueAliasProperties = Set<Property>()
		for case let .aliased(property, fulfillingProperty, erasedToConcreteExistential, onlyIfAvailable, _) in scope.propertiesToGenerate {
			func isBoundFromBuilderChild() -> Bool {
				childBindingOnlyIfAvailableAlias(of: fulfillingProperty).map { ScopeGenerator.isBuilder(children[$0.index].property) } ?? false
			}
			if erasedToConcreteExistential || !ScopeGenerator.isBuilder(property) || onlyIfAvailable && !isBoundFromBuilderChild() {
				valueAliasProperties.insert(property)
			}
			let namedChild: NamedChild?
			if onlyIfAvailable {
				onlyIfAvailableAliasFulfillingPropertyByProperty[property] = fulfillingProperty
				namedChild = childBindingOnlyIfAvailableAlias(of: fulfillingProperty)
			} else {
				namedChild = childByProperty[fulfillingProperty]
			}
			if let namedChild {
				aliasedChildByProperty[property] = NamedChild(index: namedChild.index, directness: 2 + aliasCount)
			}
			aliasCount += 1
		}
		func namedChild(declaring property: Property) -> NamedChild? {
			childByProperty[property] ?? aliasedChildByProperty[property]
		}
		/// The child declaring the unwrapped form of `property`, which fulfills a required receive of `property`, and
		/// which `property` names less directly than any property the scope declares does.
		func namedChild(declaringUnwrapped property: Property) -> NamedChild? {
			namedChild(declaring: property.asUnwrappedProperty).map {
				NamedChild(index: $0.index, directness: $0.directness + 2 + aliasCount)
			}
		}
		// The siblings each child requires, in sibling order, each with the property through which it is received that
		// names it most directly. A child that receives its own property is reported by the received walk or the ancestor
		// check, but one that receives it through an alias or unwrapped requires itself here. Only the received properties
		// that name a sibling are kept, so nothing is sorted on the common path.
		let requiredSiblings = children.enumerated().map { index, child in
			let receivedProperties = collectReceivedProperties(from: child.scope, cache: &cache)
			var mostDirectReceivedPropertyBySiblingIndex = [Int: (property: Property, directness: Int)]()
			func recordRequiredProperty(_ property: Property) {
				// Two optional properties can name a child by one unwrapped form, so the property breaks the tie.
				if let namedChild = namedChild(declaring: property) ?? namedChild(declaringUnwrapped: property),
				   mostDirectReceivedPropertyBySiblingIndex[namedChild.index].map({ (namedChild.directness, property) < ($0.directness, $0.property) }) ?? true
				{
					mostDirectReceivedPropertyBySiblingIndex[namedChild.index] = (property, namedChild.directness)
				}
			}
			// A property received only if available is still required when an `onlyIfAvailable` alias that a receiver
			// requires is bound from it: the child's tree requires it through the alias where a sibling declares its label.
			for property in receivedProperties.received
				where property != child.property
				&& property != child.property.asLazilyInstantiatedInstanceProperty
				&& !receivedProperties.onlyIfAvailable.contains(property)
			{
				recordRequiredProperty(property)
			}
			// The child's tree requires the property an `onlyIfAvailable` alias in it is bound from, where a sibling declares
			// its label. The child's own property is still being built inside its tree, so an alias there is `nil` and
			// requires nothing of it.
			for property in receivedProperties.requiredAliasFulfillingProperties.sorted() {
				if let namedChild = childBindingOnlyIfAvailableAlias(of: property),
				   namedChild.index != index,
				   mostDirectReceivedPropertyBySiblingIndex[namedChild.index].map({ (namedChild.directness, property) < ($0.directness, $0.property) }) ?? true
				{
					mostDirectReceivedPropertyBySiblingIndex[namedChild.index] = (property, namedChild.directness)
				}
			}
			return mostDirectReceivedPropertyBySiblingIndex
				.map { (index: $0.key, receivedProperty: $0.value.property) }
				.sorted { $0.index < $1.index }
		}
		// Instantiators that require one another are accepted: each builder function on such a loop rebinds what its tree
		// receives inside the loop (see `ScopeGenerator.ReceivedBuilderLoops`). A cycle with any other property on it – a
		// child that is no instantiator, or a rename of one that is no instantiator – is rejected.
		let isBuilderChild = children.map { ScopeGenerator.isBuilder($0.property) }
		func holdsValue(cycleOf indices: some Sequence<Int>, receivedPropertyChain: [Property]) -> Bool {
			indices.contains { !isBuilderChild[$0] } || receivedPropertyChain.contains(where: valueAliasProperties.contains)
		}
		/// The error reporting the cycle that `path`, children each receiving the next through the property beside it,
		/// closes by the last child's receive of the first through `closingReceivedProperty`.
		func reportedCycle(
			path: [Int],
			pathReceivedProperties: [Property],
			closingReceivedProperty: Property,
		) -> ChildrenRequiringEachOther {
			let receivedPropertyChain = pathReceivedProperties + [closingReceivedProperty]
			return ChildrenRequiringEachOther(
				instantiated: children[path[0]].property,
				receivedPropertyChain: receivedPropertyChain,
				closingReceiver: requiredReceiver(
					of: closingReceivedProperty,
					inTreeOf: children[path[path.count - 1]].scope,
					cache: &cache,
				),
				requiredOnlyIfAvailableAliases: receivedPropertyChain.compactMap { property in
					onlyIfAvailableAliasFulfillingPropertyByProperty[property].map {
						.init(property: property, fulfillingProperty: $0)
					}
				},
			)
		}
		// Depth-first search, in sibling order, for a back edge that closes a cycle with a value on it. The search keeps its
		// own path, since a scope can have as many children requiring one another in turn as the module has types.
		var visitedIndices = Set<Int>()
		func cycleOfChildren(reachedFrom startIndex: Int) -> ChildrenRequiringEachOther? {
			visitedIndices.insert(startIndex)
			// Each child on the path, with the position in its `requiredSiblings` of the next sibling to search from.
			var path = [(index: startIndex, nextRequiredSiblingPosition: 0)]
			// The property through which each child on the path receives the next one.
			var pathReceivedProperties = [Property]()
			while let (index, requiredSiblingPosition) = path.last {
				if requiredSiblingPosition < requiredSiblings[index].count {
					path[path.count - 1].nextRequiredSiblingPosition += 1
					let requiredSibling = requiredSiblings[index][requiredSiblingPosition]
					if let pathPosition = path.firstIndex(where: { $0.index == requiredSibling.index }) {
						if holdsValue(
							cycleOf: path[pathPosition...].map(\.index),
							receivedPropertyChain: Array(pathReceivedProperties[pathPosition...]) + [requiredSibling.receivedProperty],
						) {
							return reportedCycle(
								path: path[pathPosition...].map(\.index),
								pathReceivedProperties: Array(pathReceivedProperties[pathPosition...]),
								closingReceivedProperty: requiredSibling.receivedProperty,
							)
						}
					} else if visitedIndices.insert(requiredSibling.index).inserted {
						pathReceivedProperties.append(requiredSibling.receivedProperty)
						path.append((index: requiredSibling.index, nextRequiredSiblingPosition: 0))
					}
				} else {
					path.removeLast()
					// The child the path started from was reached through no property.
					if !path.isEmpty {
						pathReceivedProperties.removeLast()
					}
				}
			}
			return nil
		}
		var foundCycle: ChildrenRequiringEachOther?
		for index in children.indices where foundCycle == nil && !visitedIndices.contains(index) {
			foundCycle = cycleOfChildren(reachedFrom: index)
		}
		guard foundCycle == nil else { return foundCycle }
		// The search above skips a cycle of instantiators, which can hide a cycle with a value on it that shares its
		// children. Every cycle lies inside one strongly connected component, so each component with a value on a cycle
		// inside it is searched for a path from the value back to it, values in sibling order: a child that is no
		// instantiator, then the child a rename that is none is fulfilled by.
		let componentByIndex = ScopeGenerator.stronglyConnectedComponents(of: requiredSiblings.map { Set($0.map(\.index)) })
		var searchStarts = [(start: Int, closesThrough: (Int, Property) -> Bool)]()
		for index in children.indices where !isBuilderChild[index] {
			searchStarts.append((start: index, closesThrough: { _, _ in true }))
		}
		for index in children.indices {
			for requiredSibling in requiredSiblings[index] where valueAliasProperties.contains(requiredSibling.receivedProperty) {
				searchStarts.append((start: requiredSibling.index, closesThrough: { closingIndex, receivedProperty in
					closingIndex == index && receivedProperty == requiredSibling.receivedProperty
				}))
			}
		}
		for (start, closesThrough) in searchStarts {
			var visitedIndices: Set<Int> = [start]
			var path = [(index: start, nextRequiredSiblingPosition: 0)]
			var pathReceivedProperties = [Property]()
			while let (index, requiredSiblingPosition) = path.last {
				if requiredSiblingPosition < requiredSiblings[index].count {
					path[path.count - 1].nextRequiredSiblingPosition += 1
					let requiredSibling = requiredSiblings[index][requiredSiblingPosition]
					guard componentByIndex[requiredSibling.index] == componentByIndex[start] else { continue }
					if requiredSibling.index == start, closesThrough(index, requiredSibling.receivedProperty) {
						return reportedCycle(
							path: path.map(\.index),
							pathReceivedProperties: pathReceivedProperties,
							closingReceivedProperty: requiredSibling.receivedProperty,
						)
					} else if visitedIndices.insert(requiredSibling.index).inserted {
						pathReceivedProperties.append(requiredSibling.receivedProperty)
						path.append((index: requiredSibling.index, nextRequiredSiblingPosition: 0))
					}
				} else {
					path.removeLast()
					if !path.isEmpty {
						pathReceivedProperties.removeLast()
					}
				}
			}
		}
		return nil
	}

	/// Validates that no scope in the trees rooted at `rootScopes` has instantiated
	/// children that require one another (see `childrenRequiringEachOther`). Such
	/// children would be generated with one of them referring to a sibling declared
	/// after it, which no compiler stage before SIL rejects. Each tree reports the first
	/// error it finds, and the errors of every tree are reported. Scopes in `validation`'s
	/// `validatedScopes` are skipped along with their trees, and every scope whose tree is
	/// validated without error is added to it. Each tree is validated depth first, in the
	/// order each scope declares its children, with a stack of the scopes left to validate,
	/// since a tree can be as deep as the module has types.
	static func validateChildrenDoNotRequireEachOther(
		inTreesRootedAt rootScopes: [Scope],
		cache: inout ReceivedPropertiesCache,
		validation: inout ChildrenRequiringEachOtherValidation,
	) throws {
		var treeErrors = [DependencyTreeGeneratorError]()
		for rootScope in rootScopes {
			// The scopes of this tree validated so far, each with the index here of the scope that instantiates it.
			var walkedScopes = [(scope: Scope, parentIndex: Int?)]()
			var scopesToValidate: [(scope: Scope, parentIndex: Int?)] = [(scope: rootScope, parentIndex: nil)]
			do {
				while let (scope, parentIndex) = scopesToValidate.popLast() {
					guard validation.validatedScopes.insert(scope).inserted else { continue }
					walkedScopes.append((scope: scope, parentIndex: parentIndex))
					let walkedScopeIndex = walkedScopes.count - 1
					if case let renamesContradictingOwnProperties = renamesContradictingOwnProperties(in: scope),
					   !renamesContradictingOwnProperties.isEmpty
					{
						// The walk in `validatePropertiesAreFulfillable` reports these for every scope it reaches, so only a
						// scope in the tree of a dependency a mock promotes, which that walk does not reach, reports them here.
						throw DependencyTreeGeneratorError.renamesContradictingOwnProperties(renamesContradictingOwnProperties)
					} else if let childrenRequiringEachOther = childrenRequiringEachOther(in: scope, cache: &cache) {
						throw childrenRequiringEachOther.error
					} else {
						let firstChildIndex = scopesToValidate.endIndex
						for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate {
							scopesToValidate.append((scope: childScope, parentIndex: walkedScopeIndex))
						}
						// The scope validated next is the last one on the stack, so the first child goes last.
						scopesToValidate.reverseElements(from: firstChildIndex)
					}
				}
			} catch let error as DependencyTreeGeneratorError {
				// The next tree that reaches a scope on the path to the error validates it again, and reports the same
				// error, rather than skipping it and validating what this tree did not reach because it stopped there.
				// The scope that reported the error was the last one walked.
				var walkedScopeIndex = walkedScopes.indices.last
				while let index = walkedScopeIndex {
					validation.validatedScopes.remove(walkedScopes[index].scope)
					walkedScopeIndex = walkedScopes[index].parentIndex
				}
				treeErrors.append(error)
			}
		}
		if let error = DependencyTreeGeneratorError.reportingAll(of: treeErrors) {
			throw error
		}
	}

	/// The renames of `scope`'s type, in declaration order, whose `fulfilledByDependencyNamed:` label the type also
	/// declares – as a property it instantiates or forwards – with a type their `ofType:` does not name. A rename
	/// refers to the property of that name on its own type. One whose `ofType:` names that property is built after it
	/// and assigned from it; one that names another type would be assigned from whichever declaration of its label is
	/// in scope where it is built, which depends on the order of the type's declarations. So `ofType:` must name the
	/// type's property exactly, or, when it is lazily instantiated, the instance it offers by value. A rename of
	/// another rename of the type is rejected before scopes are built (`RejectedRename`), and a rename of its own
	/// label refers to no other property.
	static func renamesContradictingOwnProperties(
		in scope: Scope,
	) -> [DependencyTreeGeneratorError.RenameContradictingOwnProperty] {
		// Most types rename nothing, and every walk of every tree asks of each of its scopes.
		guard scope.instantiable.dependencies.contains(where: { $0.source.fulfillingProperty != nil }) else { return [] }
		var ownDependencyByLabel = [String: Dependency]()
		for dependency in scope.instantiable.dependencies {
			switch dependency.source {
			case .instantiated, .forwarded:
				ownDependencyByLabel[dependency.property.label] = dependency
			case .aliased, .received:
				continue
			}
		}
		return scope.instantiable.dependencies.compactMap { dependency in
			guard case let .aliased(fulfillingProperty, _, _) = dependency.source,
			      let ownDependency = ownDependencyByLabel[fulfillingProperty.label],
			      !ownDependency.receivableProperties.contains(fulfillingProperty)
			else { return nil }
			return DependencyTreeGeneratorError.RenameContradictingOwnProperty(
				aliasProperty: dependency.property,
				fulfillingProperty: fulfillingProperty,
				declarationLocation: dependency.declarationLocation,
				ownProperty: ownDependency.property,
				ownPropertyDeclarationLocation: ownDependency.declarationLocation,
				renamingType: scope.instantiable.concreteInstantiable,
			)
		}
	}

	/// A scope whose tree `requiredReceiver` has searched for a receiver of a property.
	private struct SearchedScope: Hashable {
		let scope: ObjectIdentifier
		let property: Property
	}

	/// The first dependency, in declaration order and then child order, in the tree that
	/// `scope` creates that requires `property` from outside the tree — a dependency
	/// through which `collectReceivedProperties` finds the tree requires `property`,
	/// which lists `property` in `received` and not in `onlyIfAvailable`, or in
	/// `requiredAliasFulfillingProperties`: a dependency that requires an `onlyIfAvailable`
	/// alias bound from `property` (see `ScopeDeclarations.requiredOnlyIfAvailableAliases`).
	/// Such an alias counts: the tree is built after the property it is bound from (see
	/// `ScopeGenerator.orderedPropertiesToGenerate`), and the search goes on for the receiver of
	/// the alias's property beneath the scope, whose children's trees receive it: no alias of the
	/// scope renames another, since SafeDITool rejects that before it validates a tree that builds
	/// the scope. The tree is searched depth first with a stack of the scopes left to search, since
	/// it can be as deep as the module has types. `nil` when no dependency in the tree requires
	/// `property`, which `childrenRequiringEachOther` never asks about: the walk and the search
	/// decide what a scope provides by the same rules.
	private static func requiredReceiver(
		of property: Property,
		inTreeOf scope: Scope,
		cache: inout ReceivedPropertiesCache,
	) -> RequiredReceiver? {
		var searchedScopes = Set<SearchedScope>()
		var scopesToSearch = [(
			scope: scope,
			property: property,
			requiredOnlyIfAvailableAliases: [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias](),
		)]
		var receiver: RequiredReceiver?
		while receiver == nil, let (scope, property, requiredOnlyIfAvailableAliases) = scopesToSearch.popLast() {
			guard searchedScopes.insert(SearchedScope(scope: ObjectIdentifier(scope), property: property)).inserted else { continue }
			let declarations = ScopeDeclarations(scope: scope)
			/// The properties of the `onlyIfAvailable` aliases the scope declares that a receiver in a child's tree requires,
			/// as the walk finds them in `UnfinishedReceivedPropertiesWalk.finished`. Computed once, when the scope declares
			/// an `onlyIfAvailable` alias bound from the searched property.
			var computedRequiredAliasProperties: Set<Property>?
			func requiredAliasProperties() -> Set<Property> {
				if let computedRequiredAliasProperties {
					return computedRequiredAliasProperties
				} else {
					var childRequiredReceived = Set<Property>()
					var childRequiredAliasFulfillingProperties = Set<Property>()
					for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate {
						let childReceivedProperties = collectReceivedProperties(from: childScope, cache: &cache)
						childRequiredReceived.formUnion(childReceivedProperties.received.subtracting(childReceivedProperties.onlyIfAvailable))
						childRequiredAliasFulfillingProperties.formUnion(childReceivedProperties.requiredAliasFulfillingProperties)
					}
					let requiredAliasProperties = Set(declarations.requiredOnlyIfAvailableAliases(
						childRequiredReceived: childRequiredReceived,
						childRequiredAliasFulfillingProperties: childRequiredAliasFulfillingProperties,
					).map(\.property))
					computedRequiredAliasProperties = requiredAliasProperties
					return requiredAliasProperties
				}
			}
			// The property searched for beneath this scope: `property`, or the property of an `onlyIfAvailable` alias
			// bound from it that the scope declares and that is required, which the receiver then receives instead.
			var searchedProperty = property
			var searchedPropertyIsOwnAlias = false
			var requiredOnlyIfAvailableAliases = requiredOnlyIfAvailableAliases
			if let dependency = scope.instantiable.dependencies.first(where: { dependency in
				switch dependency.source {
				case let .received(onlyIfAvailable):
					!onlyIfAvailable && dependency.property == property
				case let .aliased(fulfillingProperty, _, onlyIfAvailable):
					// An alias of a property the scope declares or forwards refers to that property, as
					// `collectReceivedProperties` has it.
					!onlyIfAvailable
						&& fulfillingProperty == property
						&& !declarations.propertiesToDeclare.contains(fulfillingProperty)
						&& !declarations.forwardedProperties.contains(fulfillingProperty)
				case .instantiated, .forwarded:
					false
				}
			}) {
				receiver = RequiredReceiver(dependency: dependency, requiredOnlyIfAvailableAliases: requiredOnlyIfAvailableAliases)
			} else if let requiredAlias = declarations.onlyIfAvailableAliases.first(where: { alias in
				// An alias bound from a property the scope declares or forwards is bound from that declaration.
				alias.fulfillingProperty.label == property.label
					&& ScopeGenerator.provides(property, aFormReadBy: alias.fulfillingProperty)
					&& !declarations.declaredLabels.contains(property.label)
					&& requiredAliasProperties().contains(alias.property)
			}) {
				// The receiver that requires the alias receives the alias's property, which the scope declares.
				requiredOnlyIfAvailableAliases.append(requiredAlias)
				searchedProperty = requiredAlias.property
				searchedPropertyIsOwnAlias = true
			}
			// A scope that declares `property` is not searched beneath: the trees of its children receive its own.
			if receiver == nil, searchedPropertyIsOwnAlias || !declarations.provides(searchedProperty) {
				// The scope searched next is the last one on the stack, so the first child goes last.
				let firstChildIndex = scopesToSearch.endIndex
				for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate {
					scopesToSearch.append((childScope, searchedProperty, requiredOnlyIfAvailableAliases))
				}
				scopesToSearch.reverseElements(from: firstChildIndex)
			}
		}
		return receiver
	}

	/// What a scope declares, forwards, and aliases, as the walk of its received properties
	/// (`UnfinishedReceivedPropertiesWalk`) and the search of its tree (`requiredReceiver`) read it, with the rule by
	/// which both carry what its children's trees require through `onlyIfAvailable` aliases through it, which
	/// `ScopeGenerator` mirrors in `isRequiredByChild`, `requiredOnlyIfAvailableAliasProperties`, and
	/// `requiredAliasFulfillingProperties` to decide what each tree is built after.
	struct ScopeDeclarations {
		init(scope: Scope) {
			propertiesToDeclare = scope.propertiesToDeclare
			forwardedProperties = scope.instantiable.forwardedReceivableProperties
			var onlyIfAvailableAliases = [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias]()
			for case let (property, .aliased(fulfillingProperty, _, onlyIfAvailable: true)) in scope.instantiable.dependencies.lazy.map({ ($0.property, $0.source) }) {
				onlyIfAvailableAliases.append(.init(property: property, fulfillingProperty: fulfillingProperty))
			}
			self.onlyIfAvailableAliases = onlyIfAvailableAliases
			declaredLabels = Set(propertiesToDeclare.map(\.label)).union(forwardedProperties.map(\.label))
		}

		/// The properties the scope declares for its children: those it instantiates, whether or not a scope builds
		/// them, and the aliases it assigns (see `Scope.propertiesToDeclare`). A lazily instantiated property also
		/// declares the property that receives its instance by value.
		let propertiesToDeclare: Set<Property>
		/// The properties the scope forwards. A lazily instantiated one is also received by value.
		let forwardedProperties: Set<Property>
		/// The `onlyIfAvailable` aliases the scope declares, in declaration order.
		let onlyIfAvailableAliases: [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias]
		/// The labels of `propertiesToDeclare` and `forwardedProperties`: the scope's declaration of each is the nearest
		/// one for the scopes beneath it.
		let declaredLabels: Set<String>

		/// Whether the scope provides `property` to the scopes beneath it, as `ScopeGenerator.provides` has it: it
		/// declares or forwards the property or, for an optional property, its unwrapped form.
		func provides(_ property: Property) -> Bool {
			propertiesToDeclare.contains(property)
				|| forwardedProperties.contains(property)
				|| (property.typeDescription.isOptional
					&& (propertiesToDeclare.contains(property.asUnwrappedProperty) || forwardedProperties.contains(property.asUnwrappedProperty)))
		}

		/// Whether the scope declares or forwards a form of `property` that a receive of it only if available reads (see
		/// `Property.formsReadByOnlyIfAvailableReceive`), as `ScopeGenerator`'s
		/// `providesAFormReadByOnlyIfAvailableReceive(of:)` has it.
		func providesAFormReadByOnlyIfAvailableReceive(of property: Property) -> Bool {
			property.formsReadByOnlyIfAvailableReceive.contains { propertiesToDeclare.contains($0) || forwardedProperties.contains($0) }
		}

		/// Whether the scope provides `property`, which a call of another module's public mock in a tree beneath it passes
		/// (`ReceivedProperties.passedByPublicMockCalls`): the call is passed the scope's declaration, so nothing above
		/// the scope binds the property for it.
		func providesWhatPublicMockCallPasses(_ property: Property) -> Bool {
			propertiesToDeclare.contains(property.asUnwrappedProperty) || forwardedProperties.contains(property.asUnwrappedProperty)
		}

		/// Whether the scope provides `property`, which a call of another module's public mock in a tree beneath it builds
		/// when passed `nil` (`ReceivedProperties.builtWhenNilByPublicMockCalls`): the call is passed the scope's
		/// declaration, so no mock builds the property for it. A wrapper a called mock builds is passed by the instance
		/// it holds.
		func providesWhatPublicMockCallBuildsWhenNil(_ property: Property) -> Bool {
			let passedForm = (property.asLazilyInstantiatedInstanceProperty ?? property).asUnwrappedProperty
			return propertiesToDeclare.contains(passedForm) || forwardedProperties.contains(passedForm)
		}

		/// The `onlyIfAvailable` aliases the scope declares that a receiver in a child's tree requires, given what the
		/// children's trees require: `childRequiredReceived`, the properties they require, and
		/// `childRequiredAliasFulfillingProperties`, those they require through `onlyIfAvailable` aliases, which an alias
		/// here provides where it has their label and a form they read.
		func requiredOnlyIfAvailableAliases(
			childRequiredReceived: Set<Property>,
			childRequiredAliasFulfillingProperties: Set<Property>,
		) -> [DependencyTreeGeneratorError.RequiredOnlyIfAvailableAlias] {
			onlyIfAvailableAliases.filter { alias in
				childRequiredReceived.contains(alias.property)
					|| childRequiredAliasFulfillingProperties.contains { $0.label == alias.property.label && ScopeGenerator.provides(alias.property, aFormReadBy: $0) }
			}
		}

		/// The properties the scope's tree requires through `onlyIfAvailable` aliases of the scopes enclosing it, given
		/// what its children's trees require (see `requiredOnlyIfAvailableAliases`): those of the children's trees and the
		/// fulfilling properties of the scope's own required aliases, without those whose label the scope declares or
		/// forwards, whose nearest declaration is the scope's.
		func requiredAliasFulfillingProperties(
			childRequiredReceived: Set<Property>,
			childRequiredAliasFulfillingProperties: Set<Property>,
		) -> Set<Property> {
			var requiredAliasFulfillingProperties = childRequiredAliasFulfillingProperties
			for alias in requiredOnlyIfAvailableAliases(
				childRequiredReceived: childRequiredReceived,
				childRequiredAliasFulfillingProperties: childRequiredAliasFulfillingProperties,
			) {
				requiredAliasFulfillingProperties.insert(alias.fulfillingProperty)
			}
			return requiredAliasFulfillingProperties.filter { !declaredLabels.contains($0.label) }
		}
	}

	/// Judges a detected cycle, not the property that closes it, and throws the appropriate error, or returns silently if
	/// the cycle is valid. Called from both `validatePropertiesAreFulfillable` (production graph, and a mock root whose
	/// children require one another) and `validateMockRootScopeForCycles` (mock graph after `@Received` promotion).
	///
	/// Rejected:
	/// - A cycle closed by a receive (`closingReceive` is not `nil`) of a property that is no instantiator, whatever its
	///   hops: the property received is still being built → `.constantDependencyCycleDetected`. A receive of an
	///   instantiator still being built is accepted: its builder function wraps itself again for its tree (see
	///   `ScopeGenerator.ReceivedBuilderLoops`), and `childrenRequiringEachOther` rejects a loop through it with a
	///   property that is no instantiator on it.
	/// - A cycle closed by an instantiation along which no hop is deferred → `.constantDependencyCycleDetected`, naming
	///   the hops.
	///
	/// Accepted (returns without throwing): a cycle closed by an instantiation, of any kind, along which some hop is an
	/// instantiator (`Instantiator`, `ErasedInstantiator`, or a `Sendable` twin), wherever the tree enters it. A lazily
	/// instantiated hop is never deferred: validation holds it as the constant it stands for. Generation closes such a
	/// cycle at the same property, which calls the builder function of the declaration it repeats; pruning via
	/// `cycleEdges` is what breaks the self-referencing config-struct shape so the generated mocks typecheck.
	/// - Parameters:
	///   - propertiesInCycle: The cycle as validation sees it: the closing property, then the instantiation stack,
	///     innermost first, up to and including the entry it repeats (with the receives between, in the walk of
	///     received properties).
	///   - declaredProperty: The property of the dependency that closes the cycle, as declared at
	///     `declarationLocation`: the property instantiated, or the property received – the alias for an alias.
	func throwIfInvalidCycle(
		propertiesInCycle: [Property],
		declaredProperty: Property,
		declarationLocation: Dependency.DeclarationLocation?,
		directParent: TypeDescription,
		closingReceive: CycleClosingReceive?,
		lazilyInstantiatedProperties: @autoclosure () -> [Property],
	) throws {
		// A receive of an instantiator that is still being built reads a wrapper the instantiator's builder function makes
		// again of that function (see `ScopeGenerator.ReceivedBuilderLoops`): a loop through that instantiator alone, which
		// `childrenRequiringEachOther` rejects where a property that is not an instantiator is on it. The property received
		// is a form of the entry it repeats, so a receive of anything else receives a constant (a lazily instantiated
		// property is validated as the constant it stands for).
		if closingReceive != nil, let closedOnEntry = propertiesInCycle.last, ScopeGenerator.isBuilder(closedOnEntry) {
			return
		} else if closingReceive != nil || propertiesInCycle.allSatisfy(\.propertyType.isConstant) {
			throw invalidCycleError(
				propertiesInCycle: propertiesInCycle,
				declaredProperty: declaredProperty,
				declarationLocation: declarationLocation,
				directParent: directParent,
				closingReceive: closingReceive,
				lazilyInstantiatedProperties: lazilyInstantiatedProperties(),
			)
		}
	}

	/// The error `throwIfInvalidCycle` throws for a cycle through `property` that no instantiator defers or that a receive
	/// of a constant closes: a cycle naming its hops when an instantiation closes it, and otherwise a received constant
	/// cycle.
	/// - Parameters:
	///   - propertiesInCycle: See `throwIfInvalidCycle`.
	///   - declaredProperty: See `throwIfInvalidCycle`.
	///   - closingReceive: The receive that closes the cycle, or `nil` when an instantiation closes it.
	func invalidCycleError(
		propertiesInCycle: [Property],
		declaredProperty: Property,
		declarationLocation: Dependency.DeclarationLocation?,
		directParent: TypeDescription,
		closingReceive: CycleClosingReceive?,
		lazilyInstantiatedProperties: [Property],
	) -> DependencyTreeGeneratorError {
		let cycle = DependencyTreeGeneratorError.DependencyCycle(
			declarationLocation: declarationLocation,
			members: propertiesInCycle.map(\.typeDescription).map { typeDescription in
				DependencyTreeGeneratorError.DependencyCycle.Member(
					typeDescription: typeDescription,
					declarationLocation: typeDescriptionToFulfillingInstantiableMap[typeDescription.asInstantiatedType]?.declarationLocation,
				)
			},
			lazilyInstantiatedProperties: lazilyInstantiatedProperties,
		)
		if closingReceive == nil {
			// The walk lists the closing property first, then the stack up to the entry it repeats, which is the closing
			// property again: the hops, outermost first, are the stack's entries.
			return .constantDependencyCycleDetected(cycle, closingDependency: .instantiated(hops: propertiesInCycle.reversed().dropLast()))
		} else {
			return .constantDependencyCycleDetected(cycle, closingDependency: .received(declaredProperty, receiver: directParent))
		}
	}

	/// The repairs of an unfulfilled receive of `receivedProperty`, a non-optional `Instantiator` or `LazilyInstantiated`,
	/// inside the `@Sendable` function of the innermost `Sendable` wrapper on its chain, which cannot capture a declaration
	/// made outside it; `nil` where no such wrapper is on the chain. Each repair is offered only where it passes what it
	/// would meet: the wrapper's `Sendable` twin, declared beside the `Sendable` wrapper, where the tree of the type it
	/// builds, now built in a `@Sendable` function, receives no `Instantiator`, `ErasedInstantiator` or
	/// `LazilyInstantiated` it would capture; a declaration on a type inside the function where that tree requires no
	/// value of the chain that function is still building, which would close a dependency cycle. A receive of an
	/// optional wrapper, or of an `ErasedInstantiator`, whose declaration names the type it builds, keeps today's advice.
	/// - Parameters:
	///   - instantiationStack: The properties of `receiver` and of the scopes it is built inside, innermost first, each
	///     lazily instantiated one as declared.
	///   - parentTypeStack: The concrete types of the scopes `receiver` is built inside, innermost first.
	static func sendableBoundaryAdvice(
		for receivedProperty: Property,
		receivedBy receiver: Scope,
		instantiationStack: [Property],
		parentTypeStack: [TypeDescription],
		root: TypeDescription,
		typeDescriptionToFulfillingInstantiableMap: [TypeDescription: Instantiable],
	) -> DependencyTreeGeneratorError.UnfulfillableProperty.SendableBoundaryAdvice? {
		let sendableTwinName: String
		switch receivedProperty.propertyType {
		case .instantiator:
			sendableTwinName = Dependency.sendableInstantiatorType
		case .lazilyInstantiated:
			sendableTwinName = Dependency.sendableLazilyInstantiatedType
		case .constant, .erasedInstantiator, .sendableInstantiator, .sendableErasedInstantiator, .sendableLazilyInstantiated:
			return nil
		}
		guard case let .simple(_, generics) = receivedProperty.typeDescription,
		      let boundaryIndex = instantiationStack.firstIndex(where: \.propertyType.isSendable),
		      let builtInstantiable = typeDescriptionToFulfillingInstantiableMap[receivedProperty.typeDescription.asInstantiatedType]
		else { return nil }
		func builtType(at index: Int) -> TypeDescription {
			index == 0 ? receiver.instantiable.concreteInstantiable : parentTypeStack[index - 1]
		}
		let boundaryDeclaringType = boundaryIndex + 1 < instantiationStack.count ? builtType(at: boundaryIndex + 1) : root
		let builtTreeCapturesNothing = !treeReceivesNonSendableWrapper(from: builtInstantiable, typeDescriptionToFulfillingInstantiableMap: typeDescriptionToFulfillingInstantiableMap)
		let builtTreeRequiresNothingBeingBuilt = !instantiationStack[...boundaryIndex].contains { stackProperty in
			!stackProperty.propertyType.isInstantiator
				&& !stackProperty.propertyType.isErasedInstantiator
				&& treeRequires(stackProperty.asValidatedForDependencyCycles, from: builtInstantiable, typeDescriptionToFulfillingInstantiableMap: typeDescriptionToFulfillingInstantiableMap)
		}
		return .init(
			boundary: instantiationStack[boundaryIndex],
			boundaryDeclaringType: boundaryDeclaringType,
			builtType: builtType(at: boundaryIndex),
			sendableForm: builtTreeCapturesNothing ? .simple(name: sendableTwinName, generics: generics) : nil,
			typesInsideFunction: builtTreeRequiresNothingBeingBuilt ? (0...boundaryIndex).reversed().map(builtType(at:)) : [],
		)
	}

	/// Whether the tree of `instantiable` receives an `Instantiator`, `ErasedInstantiator` or `LazilyInstantiated`, in
	/// any form, that no type of the tree declares: a value a `@Sendable` function that builds `instantiable` would capture.
	private static func treeReceivesNonSendableWrapper(
		from instantiable: Instantiable,
		typeDescriptionToFulfillingInstantiableMap: [TypeDescription: Instantiable],
	) -> Bool {
		var reachedTypes: Set<TypeDescription> = [instantiable.concreteInstantiable]
		var instantiablesToVisit = [instantiable]
		var receivedWrappers = Set<Property>()
		var declaredProperties = Set<Property>()
		while let reachedInstantiable = instantiablesToVisit.popLast() {
			for dependency in reachedInstantiable.dependencies {
				switch dependency.source {
				case .received:
					receivedWrappers.insert(dependency.property.asUnwrappedProperty)
				case let .aliased(fulfillingProperty, _, _):
					receivedWrappers.insert(fulfillingProperty.asUnwrappedProperty)
					declaredProperties.insert(dependency.property.asUnwrappedProperty)
				case .instantiated:
					declaredProperties.insert(dependency.property)
					if let builtInstantiable = typeDescriptionToFulfillingInstantiableMap[dependency.asInstantiatedType],
					   reachedTypes.insert(builtInstantiable.concreteInstantiable).inserted
					{
						instantiablesToVisit.append(builtInstantiable)
					}
				case .forwarded:
					declaredProperties.insert(dependency.property.asUnwrappedProperty)
				}
			}
		}
		return receivedWrappers.subtracting(declaredProperties).contains { property in
			!property.propertyType.isConstant && !property.propertyType.isSendable
		}
	}

	/// Whether the tree of `instantiable` – the types it builds, constants and builders alike, and theirs – requires
	/// `property`, or its optional form, from above it: whether a type in it receives either without `onlyIfAvailable`, or
	/// renames either without it, beneath no type of the tree that declares either form, the nearer declaration such a
	/// receive resolves to. A declaration of `property` that builds `instantiable` is then still being
	/// built where the tree receives it.
	static func treeRequires(
		_ property: Property,
		from instantiable: Instantiable,
		typeDescriptionToFulfillingInstantiableMap: [TypeDescription: Instantiable],
	) -> Bool {
		let requiredForms: Set<Property> = [property, property.asOptionalProperty]
		var reachedTypes: Set<TypeDescription> = [instantiable.concreteInstantiable]
		var instantiablesToVisit = [instantiable]
		while let reachedInstantiable = instantiablesToVisit.popLast() {
			var instantiablesBuilt = [Instantiable]()
			var receivesProperty = false
			var renamesProperty = false
			var declaresForm = false
			var renamesToForm = false
			for dependency in reachedInstantiable.dependencies {
				switch dependency.source {
				case let .received(onlyIfAvailable):
					receivesProperty = receivesProperty || (!onlyIfAvailable && requiredForms.contains(dependency.property))
				case let .aliased(fulfillingProperty, _, onlyIfAvailable):
					renamesProperty = renamesProperty || (!onlyIfAvailable && requiredForms.contains(fulfillingProperty))
					renamesToForm = renamesToForm || requiredForms.contains(dependency.property)
				case .instantiated:
					if let builtInstantiable = typeDescriptionToFulfillingInstantiableMap[dependency.asInstantiatedType] {
						instantiablesBuilt.append(builtInstantiable)
					}
					declaresForm = declaresForm || requiredForms.contains(dependency.property)
				case .forwarded:
					declaresForm = declaresForm || requiredForms.contains(dependency.property)
				}
			}
			// A rename of a property its own type declares binds to that declaration.
			guard !receivesProperty, !renamesProperty || declaresForm else { return true }
			// A receive beneath a declaration of either form, or beneath a rename to one, resolves to that declaration. A
			// declaration of the label with another type does not: a receive matches label and type, so it passes it by.
			if !declaresForm, !renamesToForm {
				for builtInstantiable in instantiablesBuilt where reachedTypes.insert(builtInstantiable.concreteInstantiable).inserted {
					instantiablesToVisit.append(builtInstantiable)
				}
			}
		}
		return false
	}

	/// The receive that closes a cycle: a dependency that receives a property in the cycle that is still being built.
	struct CycleClosingReceive {}

	/// The receive by which `dependency` of `scope` closes a cycle through the property it is fulfilled by
	/// (`dependency.source.fulfillingProperty ?? dependency.property`), which is still being built, or `nil` when
	/// `dependency` does not receive that property. Production's walk of received properties counts a required
	/// alias the same way, since `Scope.requiredReceivedProperties` lists its fulfilling property unless `scope`
	/// instantiates or is forwarded it.
	static func closingReceive(of dependency: Dependency, in scope: Scope) -> CycleClosingReceive? {
		switch dependency.source {
		case .received:
			CycleClosingReceive()
		case let .aliased(fulfillingProperty, _, _):
			// An alias receives its fulfilling property, unless `scope` creates the property, which the alias then
			// refers to, so the dependency that creates it is what closes the cycle. An `onlyIfAvailable` alias closes
			// no cycle (`Dependency.canCloseDependencyCycle`).
			if scope.createdProperties.contains(fulfillingProperty) {
				nil
			} else {
				CycleClosingReceive()
			}
		case .instantiated, .forwarded:
			nil
		}
	}

	/// The index on `propertyStack` of the entry a dependency of `scope` closes a cycle on, or `nil` when it closes none. A cycle repeats a declaration: an instantiation repeats the entry of the same property, as
	/// cycle validation sees it, built for the same concrete type, so two declarations of one label and type that
	/// `fulfilledByType:` resolves to different types are two declarations. A receive repeats the entry of the property it
	/// receives, in any of `receivedForms`, only when that entry's declaration is the nearest declaration of the label: one
	/// nearer – a declaration that closes a cycle itself, or one built beside the tree being built – is what the generated
	/// code passes, so it fulfills the receive.
	/// - Parameters:
	///   - fulfillingProperty: The property `dependency` instantiates, or the property it receives: the fulfilling
	///     property of an alias.
	///   - receivedForms: The forms of `fulfillingProperty`, as cycle validation sees them, that a stack entry matches,
	///     the first the property itself.
	///   - closesByReceive: Whether `dependency` closes a cycle by receiving (see `closingReceive(of:in:)`).
	///   - propertyStack: The properties of `scope` and of the scopes it is built inside, innermost first, as cycle
	///     validation sees them.
	///   - concreteTypeOfEntry: The concrete type of the scope built for the entry at an index of `propertyStack`.
	///   - nearestDeclaration: The properties the nearest declarations of a label above `scope` declare, as cycle
	///     validation sees them – one, but for a mock root's promoted forms of one label – with how many scopes the declaring
	///     scope is built inside, or `nil` when no scope above declares the label. The entry at index `i` of `propertyStack`
	///     is declared by a scope built inside `propertyStack.count - 1 - i` scopes.
	static func indexOfEntryClosedOn(
		by fulfillingProperty: Property,
		of scope: Scope,
		receivedForms: [Property],
		closesByReceive: Bool,
		propertyStack: [Property],
		concreteTypeOfEntry: (Int) -> TypeDescription,
		nearestDeclaration: (String) -> (properties: [Property], depth: Int)?,
	) -> Int? {
		if closesByReceive {
			guard let index = propertyStack.firstIndex(where: receivedForms.contains),
			      !isFulfilledByNearerDeclaration(receivedForms, thanEntryAt: index, of: propertyStack, nearestDeclaration: nearestDeclaration)
			else { return nil }
			return index
		} else {
			// Nearly every dependency repeats no entry, so the type its scope builds is found only for one that might. A
			// dependency with no built scope matches no entry: no input has one beside an entry of its property, since an
			// instantiated type nothing fulfills is rejected before scopes exist, and a dependency a mock cannot build shares
			// no property with an entry built from a scope.
			guard propertyStack.contains(receivedForms[0]) else { return nil }
			let builtType = scope.propertiesToGenerate.first { $0.property == fulfillingProperty }?.builtScope?.instantiable.concreteInstantiable
			return propertyStack.indices.first { propertyStack[$0] == receivedForms[0] && concreteTypeOfEntry($0) == builtType }
		}
	}

	/// Whether a receive of `receivedForms`, the first the property received, as cycle validation sees them, resolves to a
	/// declaration nearer than the one the entry at `index` of `stack` is built for: the nearest declaration of the label
	/// declares one of `receivedForms` and is declared by a scope built inside more scopes than the one that declares the
	/// entry. See `indexOfEntryClosedOn`.
	static func isFulfilledByNearerDeclaration(
		_ receivedForms: [Property],
		thanEntryAt index: Int,
		of stack: [Property],
		nearestDeclaration: (String) -> (properties: [Property], depth: Int)?,
	) -> Bool {
		nearestDeclaration(receivedForms[0].label).map { $0.depth > stack.count - 1 - index && $0.properties.contains(where: receivedForms.contains) } ?? false
	}

	/// What a scope's subtree receives from its ancestors.
	struct ReceivedProperties {
		/// Every property the subtree needs from an ancestor.
		let received: Set<Property>
		/// Those of `received` that every receiver in the subtree receives only if available.
		/// A property some receiver requires is not in `onlyIfAvailable`.
		let onlyIfAvailable: Set<Property>
		/// The properties receivers in the subtree require through the `onlyIfAvailable` aliases declared in it, whose
		/// label no scope in the subtree declares: the nearest declaration of each is above the subtree, which is built
		/// after it where a scope builds both (see `ScopeDeclarations.requiredAliasFulfillingProperties`).
		let requiredAliasFulfillingProperties: Set<Property>
		/// The properties the calls of other modules' public mocks in the subtree, and in the trees of the fills its calls
		/// pass, receive only if available and pass, which are in none of the other sets: a mock that is itself public takes
		/// them as parameters (see `ScopeGenerator.receivedOnlyByPublicMockCallsLeftOut`).
		let passedByPublicMockCalls: Set<Property>
		/// Those of `passedByPublicMockCalls` some called mock builds when passed `nil`, which a mock that can build one
		/// builds once and passes to every call, as the inline mock promotes it (M8.8b).
		let builtWhenNilByPublicMockCalls: Set<Property>

		/// Whether `other` holds the same properties, and spells those of `received` as this does: `received` keeps the
		/// most explicit spelling of each property, which a pass over a cycle can change without changing the set.
		func isSpelled(as other: ReceivedProperties) -> Bool {
			received == other.received
				&& onlyIfAvailable == other.onlyIfAvailable
				&& requiredAliasFulfillingProperties == other.requiredAliasFulfillingProperties
				&& passedByPublicMockCalls == other.passedByPublicMockCalls
				&& builtWhenNilByPublicMockCalls == other.builtWhenNilByPublicMockCalls
				&& Set(received.map(\.typeDescription.asSource)) == Set(other.received.map(\.typeDescription.asSource))
		}
	}

	/// Memoizes `collectReceivedProperties` across the mock roots of one mock scope map.
	///
	/// A walk that re-enters a scope whose own walk is unfinished – a cycle of `Instantiator`s – takes
	/// nothing from it, since that scope's walk accounts for what it receives. A result computed that
	/// way lacks what the unfinished scope receives, so it is reused only until that scope's walk
	/// finishes. Reusing it later, from a subtree that reaches the cycle another way, would drop what
	/// the cycle receives from that subtree's view, and which subtree walks the cycle first can follow
	/// set iteration order.
	struct ReceivedPropertiesCache {
		/// Results that lack nothing, which are the same however the scope is reached.
		var complete = [ObjectIdentifier: ReceivedProperties]()
		/// The depth of each scope whose walk is unfinished.
		var unfinishedWalkDepths = [ObjectIdentifier: Int]()
		/// Results that lack what a scope whose walk is unfinished receives.
		var incomplete = [ObjectIdentifier: WalkedReceivedProperties]()
		/// Whether a walk enters the fills of a seam's call too, as it enters a public mock call's: what a fill of a seam's
		/// caller receives, its nested seam calls' fills included (`Scope.fillLabelsReadOnlyIfAvailable`).
		var walksSeamCallFills = false
		/// The scopes `completeReceivedPropertiesByComponent` leaves to the walk that re-enters them: those of a cycle
		/// in which a receiver requires an `onlyIfAvailable` alias a scope of the cycle declares, and those whose trees
		/// reach one.
		var scopesLeftToWalk = Set<ObjectIdentifier>()
		/// Whether a scope's received properties are completed by component before any walk, and what is told of each
		/// scope whose received properties are collected: both the tests', read once per cache.
		let completesByComponent = ValidationWalkObservation.completesReceivedPropertiesByComponent
		let observer = ValidationWalkObservation.observer
	}

	/// A scope's received properties as one walk found them.
	struct WalkedReceivedProperties {
		let receivedProperties: ReceivedProperties
		/// The depths of the scopes whose walks were unfinished when this walk re-entered them, and whose received
		/// properties `receivedProperties` therefore lacks: empty when it lacks none. The result is stale once any of
		/// them finishes, not only the shallowest, since it lacks what each of them receives.
		let unfinishedWalkDepthsReentered: Set<Int>
	}

	/// Mirrors ScopeGenerator's `receivedProperties` and `onlyIfAvailableUnwrappedReceivedProperties`
	/// computation but operates on Scope objects directly, with memoization for O(1) revisits.
	///
	/// - Returns: The subtree's received properties. Its `requiredAliasFulfillingProperties` mirror
	///   ScopeGenerator's.
	static func collectReceivedProperties(
		from scope: Scope,
		cache: inout ReceivedPropertiesCache,
	) -> ReceivedProperties {
		if let complete = cache.complete[ObjectIdentifier(scope)] {
			return complete
		} else {
			if cache.completesByComponent {
				completeReceivedPropertiesByComponent(from: scope, cache: &cache)
			}
			return walkReceivedProperties(from: scope, cache: &cache).receivedProperties
		}
	}

	/// Completes, in `cache`, the received properties of every scope of the tree `rootScope` creates that needs no walk
	/// per path: once per scope outside every cycle, and once per pass over a cycle's scopes until no scope's changes.
	///
	/// The walk that follows (`walkReceivedProperties`) takes nothing from a scope it re-enters, and keeps what it found
	/// beneath that scope only until the scope's walk finishes, so across a dense cycle of instantiators it walks every
	/// path through the cycle. What a scope receives is what its own dependencies receive and what each child's tree
	/// receives that the scope does not provide, each property judged by itself and by whether a receiver requires it,
	/// so a property that reaches a scope around a cycle has already reached it along the path without the cycle, and
	/// the scopes of a cycle (a strongly connected component of the scopes, found as Tarjan finds them, children in the
	/// walk's order) receive the least sets that satisfy that rule, whichever of them a walk enters first. The one part
	/// of a result that is not always judged property by property is what a tree requires through `onlyIfAvailable`
	/// aliases (`ReceivedProperties.requiredAliasFulfillingProperties`). While no receiver requires an alias a scope of
	/// the cycle declares, it is: a scope then only passes up what its children's trees require, less the labels it
	/// declares. A scope's alias becomes required by what its children's trees receive and require, which a walk that
	/// re-entered a scope lacks part of and the passes only add to, so an alias no pass finds required no walk finds
	/// required. Where the passes end with one required, which trees of the cycle require its fulfilling property
	/// depends on the scope a walk enters first: the passes' results are dropped, and the cycle, and every scope whose
	/// tree reaches it, is left to the walk (`ReceivedPropertiesCache.scopesLeftToWalk`).
	private static func completeReceivedPropertiesByComponent(
		from rootScope: Scope,
		cache: inout ReceivedPropertiesCache,
	) {
		guard !cache.scopesLeftToWalk.contains(ObjectIdentifier(rootScope)) else { return }
		struct Visit {
			let walk: UnfinishedReceivedPropertiesWalk
			let successors: [Scope]
			var nextSuccessorIndex = 0
			var lowestReachedIndex: Int
			var reachesScopeLeftToWalk = false
		}
		var visits = [Visit]()
		var visitIndexByScope = [ObjectIdentifier: Int]()
		// The visits whose component is not complete yet, and those whose successors are not all visited yet.
		var openComponentVisitIndices = [Int]()
		var unfinishedVisitIndices = [Int]()
		func visit(_ scope: Scope) {
			let walk = UnfinishedReceivedPropertiesWalk(scope: scope, walkDepth: 0, walksSeamCallFills: cache.walksSeamCallFills)
			visitIndexByScope[ObjectIdentifier(scope)] = visits.count
			openComponentVisitIndices.append(visits.count)
			unfinishedVisitIndices.append(visits.count)
			visits.append(Visit(walk: walk, successors: walk.scopesWalked, lowestReachedIndex: visits.count))
		}
		visit(rootScope)
		while let visitIndex = unfinishedVisitIndices.last {
			if visits[visitIndex].nextSuccessorIndex < visits[visitIndex].successors.count {
				let successor = visits[visitIndex].successors[visits[visitIndex].nextSuccessorIndex]
				visits[visitIndex].nextSuccessorIndex += 1
				let successorID = ObjectIdentifier(successor)
				if cache.complete[successorID] != nil {
					continue
				} else if cache.scopesLeftToWalk.contains(successorID) {
					visits[visitIndex].reachesScopeLeftToWalk = true
				} else if let successorVisitIndex = visitIndexByScope[successorID] {
					// Every visit whose component is closed is complete or left to the walk, so this one's is open.
					visits[visitIndex].lowestReachedIndex = min(visits[visitIndex].lowestReachedIndex, successorVisitIndex)
				} else {
					visit(successor)
				}
			} else {
				unfinishedVisitIndices.removeLast()
				if let parentVisitIndex = unfinishedVisitIndices.last {
					visits[parentVisitIndex].lowestReachedIndex = min(visits[parentVisitIndex].lowestReachedIndex, visits[visitIndex].lowestReachedIndex)
				}
				guard visits[visitIndex].lowestReachedIndex == visitIndex else { continue }
				// This visit is the first of its component: the component's visits are those opened since.
				var componentVisitIndices = [Int]()
				while let openVisitIndex = openComponentVisitIndices.popLast() {
					componentVisitIndices.append(openVisitIndex)
					if openVisitIndex == visitIndex {
						break
					}
				}
				// A scope that creates only itself again needs one pass, as a scope outside every cycle does: what it
				// receives from itself it has already received, less what it declares, and a walk that re-enters it
				// takes nothing from it either.
				let isCycle = componentVisitIndices.count > 1
				var isLeftToWalk = false
				for componentVisitIndex in componentVisitIndices {
					let componentVisit = visits[componentVisitIndex]
					if componentVisit.reachesScopeLeftToWalk {
						isLeftToWalk = true
					}
					for successor in componentVisit.successors where cache.scopesLeftToWalk.contains(ObjectIdentifier(successor)) {
						isLeftToWalk = true
					}
				}
				if !isLeftToWalk {
					// The component's visits, last visited first: children before the scopes that create them, but for
					// the edges that close its cycles, which the passes after the first settle.
					var changed = true
					while changed {
						changed = false
						isLeftToWalk = false
						for componentVisitIndex in componentVisitIndices {
							let completed = visits[componentVisitIndex].walk.completing(in: &cache)
							if completed.changed {
								changed = isCycle
							}
							if completed.requiresOwnOnlyIfAvailableAlias {
								// Only where the passes end does this decide: what the trees require grows with each pass.
								isLeftToWalk = isCycle
							}
						}
					}
				}
				if isLeftToWalk {
					// What the passes completed of a cycle whose own alias a receiver requires is no walk's result.
					for componentVisitIndex in componentVisitIndices {
						let scopeID = ObjectIdentifier(visits[componentVisitIndex].walk.scope)
						cache.complete[scopeID] = nil
						cache.scopesLeftToWalk.insert(scopeID)
					}
				}
			}
		}
	}

	/// Walks the tree `scope` creates, children before the scopes that create them, and the trees of the fills a call of
	/// another module's public mock passes after its children, with a stack of the scopes whose walk is unfinished, since
	/// a tree can be as deep as the module has types.
	private static func walkReceivedProperties(
		from scope: Scope,
		cache: inout ReceivedPropertiesCache,
	) -> WalkedReceivedProperties {
		var walks: [UnfinishedReceivedPropertiesWalk]
		switch startWalkingReceivedProperties(from: scope, cache: &cache) {
		case let .walked(walkedReceivedProperties):
			return walkedReceivedProperties
		case let .unfinished(walk):
			walks = [walk]
		}
		while true {
			let walkIndex = walks.count - 1
			let nextPropertyIndex = walks[walkIndex].nextPropertyIndex
			if nextPropertyIndex < walks[walkIndex].propertiesToGenerate.count {
				walks[walkIndex].nextPropertyIndex += 1
				// Aliases are handled in `UnfinishedReceivedPropertiesWalk.finished(cache:)`'s own-dependency loop.
				if case let .instantiated(_, childScope, _) = walks[walkIndex].propertiesToGenerate[nextPropertyIndex] {
					switch startWalkingReceivedProperties(from: childScope, cache: &cache) {
					case let .walked(walkedChild):
						walks[walkIndex].record(walkedChild)
					case let .unfinished(childWalk):
						walks.append(childWalk)
					}
				}
			} else if walks[walkIndex].nextFillIndex < walks[walkIndex].fills.count {
				let fillScope = walks[walkIndex].fills[walks[walkIndex].nextFillIndex].scope
				walks[walkIndex].nextFillIndex += 1
				switch startWalkingReceivedProperties(from: fillScope, cache: &cache) {
				case let .walked(walkedFill):
					walks[walkIndex].record(walkedFill)
				case let .unfinished(fillWalk):
					walks.append(fillWalk)
				}
			} else {
				var finishedWalk = walks.removeLast()
				let walkedReceivedProperties = finishedWalk.finished(cache: &cache)
				if walks.isEmpty {
					return walkedReceivedProperties
				} else {
					walks[walks.count - 1].record(walkedReceivedProperties)
				}
			}
		}
	}

	/// How a walk of a scope's received properties starts: with a result it needs no walk for, or with a walk
	/// of the scope's tree.
	private enum ReceivedPropertiesWalkStart {
		case walked(WalkedReceivedProperties)
		case unfinished(UnfinishedReceivedPropertiesWalk)
	}

	private static func startWalkingReceivedProperties(
		from scope: Scope,
		cache: inout ReceivedPropertiesCache,
	) -> ReceivedPropertiesWalkStart {
		let id = ObjectIdentifier(scope)
		if let complete = cache.complete[id] {
			return .walked(WalkedReceivedProperties(receivedProperties: complete, unfinishedWalkDepthsReentered: []))
		} else if let unfinishedWalkDepth = cache.unfinishedWalkDepths[id] {
			// A cycle re-entered this scope. Its unfinished walk accounts for what it receives.
			return .walked(WalkedReceivedProperties(
				receivedProperties: ReceivedProperties(received: [], onlyIfAvailable: [], requiredAliasFulfillingProperties: [], passedByPublicMockCalls: [], builtWhenNilByPublicMockCalls: []),
				unfinishedWalkDepthsReentered: [unfinishedWalkDepth],
			))
		} else if let incomplete = cache.incomplete[id] {
			return .walked(incomplete)
		} else {
			let walkDepth = cache.unfinishedWalkDepths.count
			cache.unfinishedWalkDepths[id] = walkDepth
			return .unfinished(UnfinishedReceivedPropertiesWalk(scope: scope, walkDepth: walkDepth, walksSeamCallFills: cache.walksSeamCallFills))
		}
	}

	/// A scope whose received properties `walkReceivedProperties` is collecting, with what it has collected from
	/// the trees of the children walked so far.
	private struct UnfinishedReceivedPropertiesWalk {
		init(scope: Scope, walkDepth: Int, walksSeamCallFills: Bool) {
			self.scope = scope
			self.walkDepth = walkDepth
			propertiesToGenerate = scope.propertiesToGenerate
			declarations = ScopeDeclarations(scope: scope)
			// A seam call's fills, in a production tree, call no public mock, so only a public mock call's are walked, unless the
			// walk asks what a seam's fill receives (`ReceivedPropertiesCache.walksSeamCallFills`).
			var fills = [(scope: Scope, fieldForms: Set<Property>)]()
			if scope.publicMockCall != nil || walksSeamCallFills && scope.seamCall != nil {
				let innerScopeReaders = scope.calledBuilders.map { InnerScopeReaders(enumsByKey: $0.enumsByKey) }
				for case let .fill(hole, fillScope) in scope.holeArguments {
					// A public mock takes no deferred parameter, so its fill binds every field, but one that a level of an inner
					// seam's enum holds on some route to the place and not on another, which the fill reads of the caller's scope
					// on that other route (`InnerScopeReaders.labelsSomeInnerRouteLacks(of:)`). A seam's fill reads a field bound
					// from a deferred parameter of the caller's scope too (`fillUnderConstruction`).
					let labelsSomeInnerRouteLacks = innerScopeReaders?.labelsSomeInnerRouteLacks(of: hole) ?? []
					let boundLabels = Set(hole.fields.filter { scope.publicMockCall != nil || !$0.isDeferredParameter }.map(\.property.label))
					// The fill declares the property it builds too (`ScopeGenerator.propertiesBeingBuilt(byFillOf:)`).
					fills.append((fillScope, ScopeGenerator.fieldForms(of: hole, boundLabels: boundLabels.subtracting(labelsSomeInnerRouteLacks)).union(ScopeGenerator.propertiesBeingBuilt(byFillOf: hole))))
				}
			}
			self.fills = fills
		}

		let scope: Scope
		let walkDepth: Int
		let propertiesToGenerate: [Scope.PropertyToGenerate]
		/// The index in `propertiesToGenerate` of the next property whose tree to walk.
		var nextPropertyIndex = 0
		/// The fills of the builders this scope's call of another module's public mock fills, each with the properties
		/// it declares (`ScopeGenerator.fieldForms(of:)`), whose trees are walked after every child's.
		let fills: [(scope: Scope, fieldForms: Set<Property>)]
		/// The index in `fills` of the next fill whose tree to walk.
		var nextFillIndex = 0

		/// The scopes whose trees the walk walks from this one, in its order: each instantiated child's, then each
		/// fill's.
		var scopesWalked: [Scope] {
			propertiesToGenerate.compactMap(\.builtScope) + fills.map(\.scope)
		}

		/// Completes this scope's received properties in `cache` from the complete ones of the scopes walked from it,
		/// taking nothing from one that has none yet, as a copy of this walk that has walked nothing finds them: one pass
		/// of `completeReceivedPropertiesByComponent`.
		/// - Returns: Whether the scope had none, or others, before, and whether a receiver in a child's tree then
		///   requires an `onlyIfAvailable` alias the scope declares.
		func completing(in cache: inout ReceivedPropertiesCache) -> (changed: Bool, requiresOwnOnlyIfAvailableAlias: Bool) {
			var walk = self
			func record(_ scope: Scope) {
				walk.record(WalkedReceivedProperties(
					receivedProperties: cache.complete[ObjectIdentifier(scope)]
						?? ReceivedProperties(received: [], onlyIfAvailable: [], requiredAliasFulfillingProperties: [], passedByPublicMockCalls: [], builtWhenNilByPublicMockCalls: []),
					unfinishedWalkDepthsReentered: [],
				))
			}
			for childScope in propertiesToGenerate.compactMap(\.builtScope) {
				record(childScope)
			}
			for fillIndex in fills.indices {
				walk.nextFillIndex = fillIndex + 1
				record(fills[fillIndex].scope)
			}
			let previous = cache.complete[ObjectIdentifier(scope)]
			let completed = walk.finished(cache: &cache).receivedProperties
			return (
				changed: previous.map { !$0.isSpelled(as: completed) } ?? true,
				requiresOwnOnlyIfAvailableAlias: !declarations.requiredOnlyIfAvailableAliases(
					childRequiredReceived: walk.childRequiredReceived,
					childRequiredAliasFulfillingProperties: walk.childRequiredAliasFulfillingProperties,
				).isEmpty,
			)
		}

		let declarations: ScopeDeclarations
		// Properties declared at this scope (instantiated/aliased children). A lazily instantiated
		// property also declares the property that receives its instance by value.
		var propertiesToDeclare: Set<Property> {
			declarations.propertiesToDeclare
		}

		// Forwarded properties at this scope. A lazily instantiated one is also received by value.
		var forwardedProperties: Set<Property> {
			declarations.forwardedProperties
		}

		var received = Set<Property>()
		var onlyIfAvailable = Set<Property>()
		// Received properties some receiver in this subtree requires. A property can be
		// received both ways — e.g. a required `x: X` and an `onlyIfAvailable` alias
		// fulfilled by `x: X` — and a required receive wins.
		var required = Set<Property>()
		var passedByPublicMockCalls = Set<Property>()
		var builtWhenNilByPublicMockCalls = Set<Property>()
		// Properties the instantiated children's subtrees require, including those this scope declares.
		var childRequiredReceived = Set<Property>()
		// The properties the instantiated children's subtrees require through `onlyIfAvailable` aliases.
		var childRequiredAliasFulfillingProperties = Set<Property>()
		var unfinishedWalkDepthsReentered = Set<Int>()

		/// Collects from an instantiated child — mirrors ScopeGenerator's receivedProperties aggregation.
		/// Aliases are handled in `finished(cache:)`'s own-dependency loop: alias children's receivedProperties
		/// = [fulfillingProperty], but the own-dependency union unconditionally adds the same
		/// fulfillingProperty, making the child-path subtraction/filter redundant.
		mutating func record(_ walkedChild: WalkedReceivedProperties) {
			unfinishedWalkDepthsReentered.formUnion(walkedChild.unfinishedWalkDepthsReentered)
			// Fills are walked after every child, so the tree walked last is a fill's once one is walked.
			guard nextFillIndex == 0 else {
				recordFill(walkedChild, fieldForms: fills[nextFillIndex - 1].fieldForms)
				return
			}
			let childReceived = walkedChild.receivedProperties.received
			let childOnlyIfAvailable = walkedChild.receivedProperties.onlyIfAvailable
			childRequiredReceived.formUnion(childReceived.subtracting(childOnlyIfAvailable))
			childRequiredAliasFulfillingProperties.formUnion(walkedChild.receivedProperties.requiredAliasFulfillingProperties)
			// A forwarded `x: X` fulfills an `x: X?` beneath it, as a declared one does. A receive only if available reads
			// any form of its label this scope declares that it reads, as `ScopeGenerator` has it.
			let childReceivedFromAncestors = childReceived
				.subtracting(propertiesToDeclare)
				.subtracting(forwardedProperties)
				.filter { property in
					(
						!property.typeDescription.isOptional
							|| (!propertiesToDeclare.contains(property.asUnwrappedProperty) && !forwardedProperties.contains(property.asUnwrappedProperty))
					) && (!childOnlyIfAvailable.contains(property) || !declarations.providesAFormReadByOnlyIfAvailableReceive(of: property))
				}
			received.formUnionKeepingMostExplicitSpelling(childReceivedFromAncestors)
			required.formUnion(childReceivedFromAncestors.subtracting(childOnlyIfAvailable))
			for property in walkedChild.receivedProperties.passedByPublicMockCalls where !declarations.providesWhatPublicMockCallPasses(property) {
				passedByPublicMockCalls.insert(property)
			}
			for property in walkedChild.receivedProperties.builtWhenNilByPublicMockCalls where !declarations.providesWhatPublicMockCallBuildsWhenNil(property) {
				builtWhenNilByPublicMockCalls.insert(property)
			}
			// Subtract by any form a receive only if available reads — a declared `x: X` satisfies onlyIfAvailable `x: X?`.
			onlyIfAvailable.formUnion(
				childOnlyIfAvailable.filter { property in
					!declarations.providesAFormReadByOnlyIfAvailableReceive(of: property)
				},
			)
		}

		/// Collects from the tree of a fill this scope's call passes what it receives beside `fieldForms`, the properties the
		/// fill declares (`ScopeGenerator.fieldForms(of:)`), as `ScopeGenerator`'s fill collects it: the fill reads it of the
		/// caller's scope, as production's fill of the same place does, so the mock binds it as it binds what a child
		/// receives. And what the calls of other modules' public mocks in it pass: a mock binds what it passes them, as it
		/// binds what such a call outside a fill passes.
		private mutating func recordFill(_ walkedFill: WalkedReceivedProperties, fieldForms: Set<Property>) {
			func isProvidedByFields(_ property: Property) -> Bool {
				fieldForms.contains(property) || fieldForms.contains(property.asUnwrappedProperty)
			}
			let fillOnlyIfAvailable = walkedFill.receivedProperties.onlyIfAvailable
			for property in walkedFill.receivedProperties.received where !isProvidedByFields(property) {
				received.insertKeepingMostExplicitSpelling(property)
				if fillOnlyIfAvailable.contains(property) {
					onlyIfAvailable.insert(property)
				} else {
					required.insert(property)
				}
			}
			for property in walkedFill.receivedProperties.passedByPublicMockCalls where !isProvidedByFields(property) {
				passedByPublicMockCalls.insert(property)
			}
			// A wrapper a called mock builds is passed by the instance it holds.
			for property in walkedFill.receivedProperties.builtWhenNilByPublicMockCalls
				where !isProvidedByFields(property.asLazilyInstantiatedInstanceProperty ?? property)
			{
				builtWhenNilByPublicMockCalls.insert(property)
			}
		}

		/// Ends the walk once every child's tree and every fill's is walked, recording its result in `cache`.
		mutating func finished(cache: inout ReceivedPropertiesCache) -> WalkedReceivedProperties {
			// This scope's own received/aliased dependencies.
			// Store exact properties (not unwrapped) in onlyIfAvailable. This avoids
			// collisions between a required `x: X` and an onlyIfAvailable `x: X?` —
			// they are distinct Properties. The subtraction in `record(_:)` uses unwrapped comparison
			// to correctly subtract when a declared property satisfies an optional one.
			// A leaf that calls another module's public mock passes a dependency it receives only if available where the
			// tree provides it, and `nil` elsewhere, so the mock binds no parameter or override for it: the public mock
			// builds what the call does not pass (see `Scope.publicMockCall`).
			if let publicMockCall = scope.publicMockCall {
				for parameter in publicMockCall.passedParameters where parameter.dependency.source == .received(onlyIfAvailable: true) {
					passedByPublicMockCalls.insert(parameter.dependency.property)
					if parameter.isBuiltWhenNil {
						// A lazily instantiated dependency is built as the wrapper the called mock builds, as the inline mock
						// promotes it, and the call is passed its instance.
						builtWhenNilByPublicMockCalls.insert(parameter.builtWrapper ?? parameter.dependency.property)
					}
				}
			}
			for dependency in scope.instantiable.dependencies where scope.publicMockCall == nil || dependency.source != .received(onlyIfAvailable: true) {
				switch dependency.source {
				case let .received(isOnlyIfAvailable):
					received.insertKeepingMostExplicitSpelling(dependency.property)
					if isOnlyIfAvailable {
						onlyIfAvailable.insert(dependency.property)
					} else {
						required.insert(dependency.property)
					}
				case let .aliased(fulfillingProperty, _, isOnlyIfAvailable):
					// If the fulfilling property is also locally declared here (e.g., as an
					// @Instantiated sibling) or forwarded, the alias resolves against that local
					// binding — it's not a received dependency that needs promoting. An
					// `onlyIfAvailable` alias binds a local of any form it reads.
					guard isOnlyIfAvailable
						? !declarations.providesAFormReadByOnlyIfAvailableReceive(of: fulfillingProperty)
						: !propertiesToDeclare.contains(fulfillingProperty) && !forwardedProperties.contains(fulfillingProperty)
					else { break }
					received.insertKeepingMostExplicitSpelling(ValueSpellings.fulfillingProperty(fulfillingProperty, spelledAsAlias: dependency.property))
					if isOnlyIfAvailable {
						onlyIfAvailable.insert(fulfillingProperty)
					} else {
						required.insert(fulfillingProperty)
					}
				case .instantiated, .forwarded:
					break
				}
			}
			// What this scope's tree requires through `onlyIfAvailable` aliases of the scopes enclosing it, through any chain
			// of aliases, given what the children's trees require. No scope this walk meets calls a seam: only
			// `createSeamScopeMapping` creates a `seamCall`, and validation walks every seam's tree inline, whose receivers
			// require what `ScopeGenerator` has a seam call require through `SeamCall.requiredThroughAliasProperties`.
			let requiredAliasFulfillingProperties = declarations.requiredAliasFulfillingProperties(
				childRequiredReceived: childRequiredReceived,
				childRequiredAliasFulfillingProperties: childRequiredAliasFulfillingProperties,
			)

			let id = ObjectIdentifier(scope)
			cache.observer?(.collectedReceivedPropertiesOfScope)
			cache.unfinishedWalkDepths[id] = nil
			if !cache.incomplete.isEmpty {
				// Results that lack what this scope receives are stale now that its walk has finished, whatever shallower
				// walks they re-entered too.
				let walkDepth = walkDepth
				cache.incomplete = cache.incomplete.filter { !$0.value.unfinishedWalkDepthsReentered.contains(walkDepth) }
			}
			let receivedProperties = ReceivedProperties(
				received: received,
				onlyIfAvailable: onlyIfAvailable.subtracting(required),
				requiredAliasFulfillingProperties: requiredAliasFulfillingProperties,
				passedByPublicMockCalls: passedByPublicMockCalls,
				builtWhenNilByPublicMockCalls: builtWhenNilByPublicMockCalls,
			)
			// This walk accounts for every walk that re-entered this scope, so the result lacks only what the walks above
			// it that this tree re-entered receive.
			unfinishedWalkDepthsReentered.remove(walkDepth)
			if !unfinishedWalkDepthsReentered.isEmpty {
				let walkedReceivedProperties = WalkedReceivedProperties(
					receivedProperties: receivedProperties,
					unfinishedWalkDepthsReentered: unfinishedWalkDepthsReentered,
				)
				cache.incomplete[id] = walkedReceivedProperties
				return walkedReceivedProperties
			} else {
				// Every walk that re-entered this scope is accounted for in this one.
				cache.complete[id] = receivedProperties
				return WalkedReceivedProperties(receivedProperties: receivedProperties, unfinishedWalkDepthsReentered: [])
			}
		}
	}
}
