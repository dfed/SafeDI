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
	/// Creates a mock-root ScopeGenerator using the production Scope tree.
	/// Unsatisfied received dependencies are promoted as root-level children
	/// on a NEW Scope (the shared Scope is never mutated).
	/// - Parameter cache: The results of `collectReceivedProperties` for scopes of `typeDescriptionToScopeMap`,
	///   shared across mock roots. The mock root's own scope never enters it: nothing instantiates the mock
	///   root, so only its children's results are collected.
	/// - Parameter childrenRequiringEachOtherValidation: The scopes whose children are already known not to
	///   require one another; see `validateChildrenDoNotRequireEachOther`.
	/// - Parameter promotedScopesValidatedForHiddenReceives: The scopes of `typeDescriptionToScopeMap` whose trees are
	///   already known to hide no received dependency, shared across mock roots: a scope's tree is validated the same
	///   way whichever mock root promotes it.
	/// - Parameter scopesWithValidatedDeclarations: The scopes of `typeDescriptionToScopeMap` whose trees' declarations are
	///   already known to repeat no dependency label and to declare no rename the macro rejects, shared across mock roots:
	///   a scope's tree is the same whichever mock root builds it, so a tree validated once is not walked again.
	/// - Parameter publicMockContext: The context the module's public mocks share (`makePublicMockContext()`), which a public
	///   mock's root reads, or `nil` when the module declares no public mock.
	/// - Parameter emittingModule: The module the mock's code compiles in, whose access to each type the mock constructs
	///   is checked, or `nil` to check none. It also decides which dependencies the mock promotes: one the calls in its
	///   tree build when passed `nil` is promoted only where the module can construct it.
	/// - Parameter checksConstructions: Whether an inaccessible construction is an error. A module that computes the plan
	///   of another module's public mock passes `false` with that module: the declaring module's own run checked its
	///   constructions, and the plan must promote what that run promoted.
	func createMockRootScopeGenerator(
		for instantiable: Instantiable,
		scope: Scope,
		typeDescriptionToScopeMap: [TypeDescription: Scope],
		frozenScopeMap: FrozenScopeMap,
		flatParameterMockDefaults: [TypeDescription: ScopeGenerator.FlatParameterMockDefault],
		erasedToConcreteTypeMap: [TypeDescription: TypeDescription],
		publicMockContext: PublicMockContext?,
		emittingModule: EmittingModule?,
		checksConstructions: Bool = true,
		receivedPropertiesCache cache: inout ReceivedPropertiesCache,
		childrenRequiringEachOtherValidation: inout ChildrenRequiringEachOtherValidation,
		promotedScopesValidatedForHiddenReceives: inout Set<ObjectIdentifier>,
		scopesWithValidatedDeclarations: inout Set<ObjectIdentifier>,
		constructionMemo: inout ConstructionMemo,
	) async throws -> ScopeGenerator {
		// Recursively collect all transitive received properties from the scope tree
		// and any promoted scopes' subtrees. Results are cached per Scope identity
		// (via ObjectIdentifier) so each scope outside a cycle is visited at most once.
		let initialReceivedProperties = Self.collectReceivedProperties(
			from: scope,
			cache: &cache,
		)
		let initialReceived = initialReceivedProperties.received
		let initialOnlyIfAvailable = initialReceivedProperties.onlyIfAvailable
		// What the calls of other modules' public mocks in the tree and in the promoted scopes' trees pass, and, of that,
		// how many calls pass each the called mock builds when passed `nil`.
		var passedByPublicMockCalls = initialReceivedProperties.passedByPublicMockCalls
		var builtWhenNilByPublicMockCalls = initialReceivedProperties.builtWhenNilByPublicMockCalls
		// A promoted scope is built beside the mocked type's own children, so a call in its tree is passed what the mocked
		// type declares, as a call in the mocked type's own tree is, whose walk above leaves it out. The walk of a promoted
		// scope's tree does not, so its results leave it out here: otherwise the mock would build a second instance of
		// what the mocked type creates for the call, or a public mock would take it as a parameter.
		let mockRootDeclarations = ScopeDeclarations(scope: scope)

		// Worklist: promoted scopes may introduce additional transitive received properties.
		// Only required properties are walked: a property received only if available becomes
		// an optional mock parameter with no default construction, so its transitive
		// dependencies don't need promoting. A property is required when any receiver in the
		// root's tree or in a promoted scope's tree requires it, even if others receive it
		// only if available.
		var allReceived = initialReceived
		var allOnlyIfAvailable = initialOnlyIfAvailable
		var allRequired = initialReceived.subtracting(initialOnlyIfAvailable)
		var visitedScopes = Set<ObjectIdentifier>()
		var worklist = Array(allRequired)

		func concreteTypeErased(to property: Property) -> TypeDescription? {
			Self.concreteTypeErased(to: property, in: erasedToConcreteTypeMap)
		}

		// A forwarded property is a bare mock parameter: the mock is passed it, so it neither promotes it nor walks the
		// tree of its type. `collectReceivedProperties` subtracts the mock root's forwarded properties only from the trees
		// of the mock root's own children, so the tree of a promoted scope can still receive one; the worklist and the
		// promotion below skip it instead. A forwarded lazily instantiated property also provides the by-value property
		// that reads its instance.
		let forwardedProperties = instantiable.forwardedReceivableProperties
		func isForwarded(_ property: Property) -> Bool {
			// A forwarded `x: X` fulfills an `x: X?` too.
			forwardedProperties.contains(property) || forwardedProperties.contains(property.asUnwrappedProperty)
		}

		// The mocked type's own aliases are bound at the mock root, beside the dependencies it promotes, so a receive in a
		// promoted tree that one of them provides, as a scope provides a property to the scopes beneath it, reads that
		// alias: its exact property, or the unwrapped form of an optional receive. The mock promotes nothing for such a
		// receive, which would build a node and an override nothing reads, nor walks the tree of its type.
		var mockedTypeAliasProperties = Set<Property>()
		for case let .aliased(aliasProperty, _, _, _, _) in scope.propertiesToGenerate {
			mockedTypeAliasProperties.insert(aliasProperty)
		}
		func isProvidedByMockedTypeAlias(_ property: Property) -> Bool {
			!mockedTypeAliasProperties.isEmpty
				&& ScopeGenerator.provides(property, declaredProperties: mockedTypeAliasProperties, forwardedProperties: [])
		}

		/// The scope that builds a received property promoted to the mock root, when the mock can build one.
		/// A received dependency the mock cannot build stays received: the root's `mock()` takes it as a parameter.
		func scopeToPromote(for receivedProperty: Property) -> (scope: Scope, erasedToConcreteExistential: Bool)? {
			let dependencyType = receivedProperty.typeDescription.asInstantiatedType
			let scopeOfReceivedProperty: (scope: Scope, erasedToConcreteExistential: Bool)? = if let receivedScope = typeDescriptionToScopeMap[dependencyType] {
				(receivedScope, false)
			} else if let concreteType = concreteTypeErased(to: receivedProperty),
			          let receivedScope = typeDescriptionToScopeMap[concreteType]
			{
				(receivedScope, true)
			} else {
				nil
			}
			guard let scopeOfReceivedProperty, Self.mockCanBuild(receivedProperty, from: scopeOfReceivedProperty.scope) else {
				return nil
			}
			return scopeOfReceivedProperty
		}

		// The scope the mock builds for each required property, which `inOrderTheMockTreeFirstReceives` walks too.
		var scopesBuiltForRequiredProperties = [Property: Scope]()
		repeat {
			while let property = worklist.popLast() {
				guard !isForwarded(property),
				      !isProvidedByMockedTypeAlias(property),
				      let promotedScope = scopeToPromote(for: property)?.scope
				else { continue }
				scopesBuiltForRequiredProperties[property] = promotedScope
				guard visitedScopes.insert(ObjectIdentifier(promotedScope)).inserted else { continue }

				let scopeReceivedProperties = Self.collectReceivedProperties(
					from: promotedScope,
					cache: &cache,
				)
				let scopeReceived = scopeReceivedProperties.received
				let scopeOnlyIfAvailable = scopeReceivedProperties.onlyIfAvailable
				allReceived.formUnionKeepingMostExplicitSpelling(scopeReceived)
				allOnlyIfAvailable.formUnion(scopeOnlyIfAvailable)
				for newProperty in scopeReceived.subtracting(scopeOnlyIfAvailable) where allRequired.insert(newProperty).inserted {
					worklist.append(newProperty)
				}
				passedByPublicMockCalls.formUnion(scopeReceivedProperties.passedByPublicMockCalls.filter { !mockRootDeclarations.providesWhatPublicMockCallPasses($0) })
				builtWhenNilByPublicMockCalls.formUnion(scopeReceivedProperties.builtWhenNilByPublicMockCalls.filter { !mockRootDeclarations.providesWhatPublicMockCallBuildsWhenNil($0) })
			}
			// A dependency the public mock another module generated builds when its call passes `nil` is built once here
			// and passed to every call – each call an `Instantiator` makes included – and every receiver that receives it
			// only if available, as the inline mock promotes it, where this module can build it (M8.8b): its whole tree,
			// with the fills of the public mock calls in it where the build compiles the generated mocks, as the mock root's
			// own access check walks them, so a promotion never brings in an error the called mock's module would not have.
			// One this module cannot build is each called mock's to build.
			for property in builtWhenNilByPublicMockCalls.sorted() where !allRequired.contains(property) {
				guard !isForwarded(property), let promotedScope = scopeToPromote(for: property)?.scope else { continue }
				if let emittingModule {
					let constructions = Self.constructions(
						inTreeRootedAt: promotedScope,
						rootIsConstructedWithMockMethod: promotedScope.instantiable.mockReturnTypeIsCompatible(withPropertyType: property.typeDescription.asInstantiatedType),
						rootReferenceLocation: nil,
						isMock: true,
						emittingModule: emittingModule,
						extendedTypes: extendedTypeDeclarations,
						walksFillsOfPublicMockCalls: compilesGeneratedMocks,
					)
					guard Self.inaccessibleConstructions(constructions, from: emittingModule, extendedTypes: extendedTypeDeclarations).isEmpty else { continue }
				}
				allReceived.insertKeepingMostExplicitSpelling(property)
				allRequired.insert(property)
				worklist.append(property)
			}
		} while !worklist.isEmpty
		// A mock takes what the calls of other modules' public mocks in its tree pass and nothing else in its tree receives,
		// as a receive only if available, which it passes on: a public mock as a parameter that defaults to `nil`, and an
		// internal one as an override that does, as it takes its own tree's receive only if available.
		// A wrapper promoted for them stands for its instance too.
		let surfacedByPublicMockCalls = passedByPublicMockCalls.subtracting(allReceived).subtracting(allReceived.compactMap(\.asLazilyInstantiatedInstanceProperty))
		allReceived.formUnion(surfacedByPublicMockCalls)
		allOnlyIfAvailable.formUnion(surfacedByPublicMockCalls)
		allOnlyIfAvailable.subtract(allRequired)

		// Promote all received properties that have scopes.
		// onlyIfAvailable dependencies are NOT promoted — they become optional
		// mock parameters with no default. Nor are forwarded properties.
		let mockRootScope = Scope(instantiable: instantiable)
		// A property the tree creates is the instance of a `LazilyInstantiated` of its label that the tree receives, as in
		// production: the mocked type's own `x: X` and an `x: LazilyInstantiated<X>` its tree receives are one instance. The
		// mock builds that child as the `LazilyInstantiated`, whose instance it passes the mocked type. A forwarded `x: X`
		// comes from outside the tree, so it is never the instance of one.
		let lazilyInstantiatedPropertiesReceived = allReceived.lazy
			.map(\.asUnwrappedProperty)
			.filter { $0.typeDescription.lazilyInstantiatedInstanceType != nil }
		mockRootScope.propertiesToGenerate = scope.propertiesToGenerate.map { propertyToGenerate in
			guard case let .instantiated(property, childScope, erasedToConcreteExistential) = propertyToGenerate,
			      let lazilyInstantiatedProperty = lazilyInstantiatedPropertiesReceived
			      	.filter({ $0.asLazilyInstantiatedInstanceProperty == property })
			      	.min(by: { $0.precedesInMockOrder($1) })
			else { return propertyToGenerate }
			return .instantiated(lazilyInstantiatedProperty, childScope, erasedToConcreteExistential: erasedToConcreteExistential)
		}

		// A dependency the tree receives both as `LazilyInstantiated` and by value is one dependency. It is
		// promoted once, as the lazily instantiated property, whenever any receiver requires it or its instance,
		// optional or not; receivers of its instance, and of the optional instance, read it from that property.
		// The same holds for a lazily instantiated property the mock root declares itself, which needs no promotion.
		// A receive of the instance, or of the optional instance, that a forwarded property fulfills does not count:
		// the forwarded value comes from outside the tree. A required `x: LazilyInstantiated<X>?` beside no required
		// instance is promoted below as it is, as any optional form is when nothing requires its non-optional form.
		// A required wrapper provides its instance, so where the tree requires one wrapper kind, a requirement of the
		// instance promotes no wrapper of the other kind: a receive of that kind only if available is then not promoted,
		// as production passes it no value of that wrapper's own (`MockReceivesPassedNil`, where the required wrapper pins it).
		var requiredWrappersByInstanceProperty = [Property: Set<Property>]()
		for requiredProperty in allRequired where !requiredProperty.typeDescription.isOptional {
			guard let instanceProperty = requiredProperty.asLazilyInstantiatedInstanceProperty else { continue }
			requiredWrappersByInstanceProperty[instanceProperty, default: []].insert(requiredProperty)
		}
		var lazilyInstantiatedPropertiesToPromote = Set<Property>()
		var instancePropertiesOfLazilyInstantiatedProperties = Set(mockRootScope.propertiesToGenerate.compactMap(\.lazilyInstantiatedInstanceProperty))
		for receivedProperty in allReceived {
			guard let instanceProperty = receivedProperty.asLazilyInstantiatedInstanceProperty else { continue }
			let lazilyInstantiatedProperty = receivedProperty.asUnwrappedProperty
			let optionalInstanceProperty = Property(label: instanceProperty.label, typeDescription: .optional(instanceProperty.typeDescription))
			let otherKindIsRequired = requiredWrappersByInstanceProperty[instanceProperty]?.contains { $0 != lazilyInstantiatedProperty } == true
			guard allRequired.contains(lazilyInstantiatedProperty)
				|| (!otherKindIsRequired && allRequired.contains(instanceProperty) && !isForwarded(instanceProperty))
				|| (!otherKindIsRequired && allRequired.contains(optionalInstanceProperty) && !isForwarded(optionalInstanceProperty)),
				scopeToPromote(for: lazilyInstantiatedProperty) != nil
			else { continue }
			lazilyInstantiatedPropertiesToPromote.insert(lazilyInstantiatedProperty)
			instancePropertiesOfLazilyInstantiatedProperties.insert(instanceProperty)
		}

		// Each form of a dependency the tree receives under one label is promoted on its own: `x: X`,
		// `x: Instantiator<X>` and `x: ErasedInstantiator<(), AnyX>` are each built, under a name of its own, for
		// the receivers of that form. Only an optional form is not promoted beside its non-optional form: the
		// mock binds what it builds to a non-optional value, which a receive of the optional form is handed too.
		// Nor is the instance of a promoted lazily instantiated property, optional or not.
		let propertiesToPromote = allReceived.union(lazilyInstantiatedPropertiesToPromote).filter { receivedProperty in
			(lazilyInstantiatedPropertiesToPromote.contains(receivedProperty) || !allOnlyIfAvailable.contains(receivedProperty))
				&& !isForwarded(receivedProperty)
				&& !isProvidedByMockedTypeAlias(receivedProperty)
				&& !instancePropertiesOfLazilyInstantiatedProperties.contains(receivedProperty.asUnwrappedProperty)
		}
		// A promoted dependency the mocked type receives takes its spelling, in the override and the binding, and any other
		// the most explicit of its receivers' spellings in the tree, as `ScopeGenerator.mockRootParameters` spells the rest.
		let mockedTypeSpellings = ScopeGenerator.MockedTypeSpellings(of: instantiable, treeReceivedProperties: allReceived)
		var promotedPropertiesToGenerate = [Scope.PropertyToGenerate]()
		for receivedProperty in propertiesToPromote.sorted()
			where receivedProperty.asUnwrappedProperty == receivedProperty || !propertiesToPromote.contains(receivedProperty.asUnwrappedProperty)
		{
			guard let (receivedScope, erasedToConcreteExistential) = scopeToPromote(for: receivedProperty) else {
				continue
			}
			promotedPropertiesToGenerate.append(.instantiated(
				mockedTypeSpellings.spelling(of: receivedProperty),
				receivedScope,
				erasedToConcreteExistential: erasedToConcreteExistential,
			))
		}
		// The mock declares and validates the promoted children in the order its tree first receives them, after its
		// own children, so which promoted sibling is passed `nil` when two receive each other only if available, the
		// order of their overrides, and which error the mock root reports depend on where properties are declared,
		// never on their labels or type names.
		mockRootScope.propertiesToGenerate += Self.inOrderTheMockTreeFirstReceives(
			promotedPropertiesToGenerate,
			walkingFrom: scope,
			scopesBuiltForRequiredProperties: scopesBuiltForRequiredProperties,
		)

		// The mock's tree builds the type of each scope the mock root's scope reaches. Each constant or lazily instantiated
		// `@Instantiated` dependency it builds, at any depth – beneath the mocked type's own children, beneath a promoted
		// dependency, inside an instantiator – must build a type without `@Forwarded` properties, as production requires of
		// the trees its roots reach (`createTypeDescriptionToScopeMapping`). A type no root reaches is checked only here,
		// where a mock builds it. The scope each dependency is built with is the mock's (`mockScope(instantiating:as:in:)`),
		// and every such dependency is reported, in source order, as production reports them.
		var instantiablesInMockTree = [Instantiable]()
		var visitedScopesInMockTree = Set<ObjectIdentifier>()
		var scopesInMockTreeToVisit = [mockRootScope]
		var forwardedPropertyErrors = [DependencyTreeGeneratorError]()
		while let scopeToVisit = scopesInMockTreeToVisit.popLast() {
			// A tree an earlier mock root's walk validated is not walked again.
			guard !scopesWithValidatedDeclarations.contains(ObjectIdentifier(scopeToVisit)),
			      visitedScopesInMockTree.insert(ObjectIdentifier(scopeToVisit)).inserted
			else { continue }
			instantiablesInMockTree.append(scopeToVisit.instantiable)
			for case let .instantiated(property, childScope, _) in scopeToVisit.propertiesToGenerate {
				scopesInMockTreeToVisit.append(childScope)
				// A promoted dependency is one the mocked type receives, which production builds above it.
				if let dependency = scopeToVisit.instantiable.dependencies.first(where: { $0.property == property && $0.source.isInstantiated }),
				   let error = forwardedPropertyError(for: dependency, instantiable: childScope.instantiable, parent: scopeToVisit.instantiable)
				{
					forwardedPropertyErrors.append(error)
				}
			}
		}
		if let error = DependencyTreeGeneratorError.reportingAll(of: forwardedPropertyErrors) {
			throw error
		}
		try Self.validateDependencyLabelsAreDistinct(in: instantiablesInMockTree)
		try Self.validateRenamesAreSpelledAsTheMacroAccepts(in: instantiablesInMockTree)
		// The generated mocks are under the module's mock condition, so a build that leaves it inactive never compiles the
		// call of a hand-written mock that the check rejects, and the shape builds there, inside a fill too
		// (`Initializer.createHandWrittenMockArgumentList`).
		if compilesGeneratedMocks {
			try Self.validateHandWrittenMocksTakeOnlyFulfilledParameters(inMockTreeRootedAt: mockRootScope)
		}
		// Only a walk that completed is kept, as every memo shared across roots keeps them. The mock root's own scope is
		// made for this root alone, and once released its identifier can name another scope, so it is never kept.
		visitedScopesInMockTree.remove(ObjectIdentifier(mockRootScope))
		scopesWithValidatedDeclarations.formUnion(visitedScopesInMockTree)

		// Validate the promoted mock scope for cycles before generating code.
		// This catches cycles that only become visible after @Received dependencies
		// are promoted to the mock root (e.g., B @Receives Instantiator<A> where A
		// instantiates B — the promotion creates a cycle in the mock root scope).
		try validateMockRootScopeForCycles(mockRootScope)
		// Promotion can also make the mock root's children require one another
		// (e.g., C @Receives B while B's subtree @Receives C — each must be built
		// first), which no ancestor stack shows. Detecting that is cheap; production's
		// walk, which follows received dependencies between scopes, then reports the
		// cycle. Running that walk on every mock root instead would add a
		// received-dependency walk for every node of every mock tree.
		let mockRootChildrenRequiringEachOther = Self.childrenRequiringEachOther(in: mockRootScope, cache: &cache)
		try validatePropertiesAreFulfillable(
			onRootScopes: mockRootChildrenRequiringEachOther != nil
				? [ValidatedRootScope(scope: mockRootScope, boundProperties: allReceived, isMock: !instantiable.isRoot)]
				: [],
			typeDescriptionToScopeMap: typeDescriptionToScopeMap,
			cyclesOnly: true,
		)
		// That walk does not follow a received `Instantiator` to the scope it builds, and
		// promoted scopes' trees are walked by no cycle validation (below, each is walked for
		// hidden received dependencies alone), so report what it leaves: children, here or
		// anywhere in the mock tree, that require one another, in the order
		// `validateChildrenDoNotRequireEachOther` checks them. The mock root's own children
		// were checked above, so only their trees are left.
		if let mockRootChildrenRequiringEachOther {
			throw mockRootChildrenRequiringEachOther.error
		} else {
			var mockRootChildScopes = [Scope]()
			for case let .instantiated(_, childScope, _) in mockRootScope.propertiesToGenerate {
				mockRootChildScopes.append(childScope)
			}
			try Self.validateChildrenDoNotRequireEachOther(
				inTreesRootedAt: mockRootChildScopes,
				cache: &cache,
				validation: &childrenRequiringEachOtherValidation,
			)
		}

		// A forwarded parameter keeps its label, so the mock binds every other property of that label under a name of its
		// own, and a type that receives one is passed it under the label inside the function that builds it. A type built
		// in that function that receives the forwarded property would read that binding instead. Only a promoted
		// dependency's tree can hold such a pair, and only when some type in it receives a forwarded label in another
		// form, which is rare, so the trees are walked only then. A `LazilyInstantiated` the mock does not build is passed
		// by name, never under its label.
		let promotedProperties = Set(promotedPropertiesToGenerate.map(\.property))
		func isReceivedUnderItsLabel(_ property: Property) -> Bool {
			property.typeDescription.lazilyInstantiatedInstanceType == nil || promotedProperties.contains(property.asUnwrappedProperty)
		}
		let forwardedDependencies = instantiable.dependencies.filter { dependency in
			dependency.isForwarded && allReceived.contains { receivedProperty in
				receivedProperty.label == dependency.property.label && !isForwarded(receivedProperty) && isReceivedUnderItsLabel(receivedProperty)
			}
		}
		if let forwardedPropertyHiddenInPromotedTree = Self.forwardedPropertyHiddenInPromotedTree(
			forwardedDependencies: forwardedDependencies,
			of: instantiable,
			promotedChildren: mockRootScope.propertiesToGenerate[scope.propertiesToGenerate.count...],
			isReceivedUnderItsLabel: isReceivedUnderItsLabel,
		) {
			throw DependencyTreeGeneratorError.forwardedPropertyHiddenInPromotedTree(forwardedPropertyHiddenInPromotedTree)
		}
		// Every receive of a label in a mock's tree, back to a type in it that declares the label, resolves in production to
		// the one declaration of the label above that tree – above the mocked type for its own tree, and above the tree of a
		// promoted dependency, which is built above the mocked type. A required receive there pins that declaration to its
		// type. So two required receives of it, one beneath or beside the other, must be fulfillable by one declaration,
		// through an alias or by name alike, or production cannot build the tree, while the mock binds the forms of the
		// label apart and passes one form under the label where the other would read it. A receive only if available that
		// a required receive pins to a form it cannot read is always passed `nil` in production, so the mock passes it `nil`
		// too and offers it nothing, though it binds that form for other receivers. Two `onlyIfAvailable` receives pin
		// nothing: production fulfills each where it is built beneath a declaration of its type, and the mock offers each
		// its own override, as it does for siblings. One rule covers every tree the mock builds inline, at every depth, so
		// whether a mock is accepted never depends on how it binds names. Only a label the mock binds in several forms can
		// hold such a pair, so the trees are walked only for those.
		var formsByLabel = [String: Set<Property>]()
		for receivedProperty in allReceived {
			formsByLabel[receivedProperty.label, default: []].insert(receivedProperty.asUnwrappedProperty)
		}
		for dependency in instantiable.dependencies where !dependency.source.isReceived {
			formsByLabel[dependency.property.label, default: []].insert(dependency.property.asUnwrappedProperty)
		}
		let labelsBoundInSeveralForms = Set(formsByLabel.lazy.filter { $0.value.count > 1 }.map(\.key))
		let receivesPassedNil = labelsBoundInSeveralForms.isEmpty
			? MockReceivesPassedNil()
			: try Self.receivesPassedNilInMockTree(
				labels: labelsBoundInSeveralForms,
				of: instantiable,
				scope: scope,
				promotedChildren: mockRootScope.propertiesToGenerate[scope.propertiesToGenerate.count...],
			)

		// A promoted dependency stands for one the mocked type receives from above it, so in production its tree is built
		// above the mocked type, wherever the dependency is built. A receive in that tree that a closer declaration in it
		// hides is rejected there, so the mock rejects it too, as it rejects one in the mocked type's own tree: the
		// validation of an additional mock's tree, run from the promoted dependency as from that mock's type, which
		// declares nothing above it, so that the mocked type's own declarations hide nothing in it, and whose tree's
		// received properties the mock binds. Each promoted scope's tree that passes is validated once; one that fails
		// is walked again by every mock root that promotes it, so that each reports the error whatever order the mock
		// roots are created in.
		var promotedScopesToValidate = [ValidatedRootScope]()
		var promotedScopeIdentifiersToValidate = Set<ObjectIdentifier>()
		for case let .instantiated(_, promotedScope, _) in mockRootScope.propertiesToGenerate[scope.propertiesToGenerate.count...]
			where !promotedScopesValidatedForHiddenReceives.contains(ObjectIdentifier(promotedScope))
			&& promotedScopeIdentifiersToValidate.insert(ObjectIdentifier(promotedScope)).inserted
		{
			promotedScopesToValidate.append(ValidatedRootScope(
				scope: promotedScope,
				boundProperties: Self.collectReceivedProperties(from: promotedScope, cache: &cache).received,
				isMock: true,
			))
		}
		if !promotedScopesToValidate.isEmpty {
			try validatePropertiesAreFulfillable(
				onRootScopes: [],
				additionalMockRootScopes: promotedScopesToValidate,
				typeDescriptionToScopeMap: typeDescriptionToScopeMap,
				cyclesOnly: true,
			)
			promotedScopesValidatedForHiddenReceives.formUnion(promotedScopeIdentifiersToValidate)
		}

		// `mock()` defaults a flat parameter only to a hand-written mock this module can call
		// (`flatParameterMockDefaults(in:emittingModule:)`), so the defaults construct nothing that is checked here.
		if checksConstructions, let emittingModule {
			// The mock of a type declared in this module refers to its tree from the type's declaration; the mock of a
			// type this module lists in `additionalMocksToGenerate`, from the `#SafeDIConfiguration` that lists it.
			let rootReferenceLocation = instantiable.sourceFilePath.map(emittingModule.isOwnFile) ?? false
				? instantiable.declarationLocation
				: emittingModule.additionalMocksToGenerateLocation
			// A mock constructs its root with the root's hand-written mock whenever it has one. The fills of the calls its tree
			// makes are constructions of its code too, which `holesFilled(byCallsOf:in:)` left to this check in a build that
			// compiles the generated mocks; elsewhere it made only fills whose every construction this module can reach.
			let constructions = Self.constructions(
				inTreeRootedAt: mockRootScope,
				rootIsConstructedWithMockMethod: instantiable.mockInitializer != nil,
				rootReferenceLocation: rootReferenceLocation,
				isMock: true,
				emittingModule: emittingModule,
				extendedTypes: extendedTypeDeclarations,
				walksFillsOfPublicMockCalls: compilesGeneratedMocks,
			)
			let inaccessibleConstructions = Self.inaccessibleConstructions(
				constructions,
				from: emittingModule,
				extendedTypes: extendedTypeDeclarations,
				mockRoot: DependencyTreeGeneratorError.InaccessibleConstruction.MockRoot(type: instantiable.concreteInstantiable, declarationLocation: instantiable.declarationLocation),
			)
			guard inaccessibleConstructions.isEmpty else {
				throw DependencyTreeGeneratorError.inaccessibleConstructions(inaccessibleConstructions)
			}
		}

		// Build the final ScopeGenerator once. The mock root binds every received
		// property it does not promote — as a `mock()` parameter or a `SafeDIOverrides`
		// entry — so each is receivable throughout the tree.
		// The instances the tree reads by value through a wrapper a public mock takes as a parameter, which it reads as
		// `<label>.instance` when it builds the type that reads it, as production reads a received wrapper's instance.
		var instancesReadThroughWrapperParameters = Set<Property>()
		let (mockRootTable, mockRootRecord) = MockRootPlan(mockRootScope: mockRootScope, frozenScopeMap: frozenScopeMap).freezingRoot()
		// A public mock's tree built with builders has holes, whose places no memo holds, so only the tree built without
		// them shares the mock roots' memo.
		func mockRootGenerator(builders: ShapedBuilders?, constructionMemo: inout ConstructionMemo) throws -> ScopeGenerator {
			try mockRootRecord.createScopeGenerator(
				in: mockRootTable,
				// The mock root binds every received property it does not promote, which encloses its whole tree.
				nearestDeclarations: .binding(allReceived, passingNilTo: receivesPassedNil),
				lazilyInstantiatedInstanceProperties: instancesReadThroughWrapperParameters,
				mockBuilders: builders,
				erasedToConcreteExistential: false,
				forMockGeneration: true,
				declaredTypeNames: declaredTypeNames,
				constructionMemo: &constructionMemo,
			)
		}
		func mockRootGeneratorWithHoles(builders: ShapedBuilders) throws -> ScopeGenerator {
			var memoOfTreeWithHoles = ConstructionMemo()
			return try mockRootGenerator(builders: builders, constructionMemo: &memoOfTreeWithHoles)
		}
		var generator = try mockRootGenerator(builders: nil, constructionMemo: &constructionMemo)
		// An internal mock binds no override for a value only the calls of other modules' public mocks receive where a call
		// reads it inside a `@Sendable` function (`ScopeGenerator.passedByPublicMockCallLabelsReadInsideSendableFunctions(of:)`,
		// a deliberate gap): which calls read it there is decided by the tree the generator holds, so a tree with one is built
		// again without binding the value, and its calls pass `nil`.
		if !surfacedByPublicMockCalls.isEmpty {
			let labelsReadInsideSendableFunctions = generator.passedByPublicMockCallLabelsReadInsideSendableFunctions(of: instantiable)
			if !labelsReadInsideSendableFunctions.isEmpty {
				for property in surfacedByPublicMockCalls where labelsReadInsideSendableFunctions.contains(property.label) {
					allReceived.remove(property)
				}
				generator = try mockRootGenerator(builders: nil, constructionMemo: &constructionMemo)
			}
		}
		if instantiable.generateMock == .public, allReceived.contains(where: \.propertyType.isLazilyInstantiated) {
			// A public mock takes a value its tree receives lazily as the wrapper (`ScopeGenerator.publicMockWrapperParameters`),
			// which a type of the tree that receives the value by value reads the instance of. Which values it takes so is
			// decided by the tree the generator holds, so a tree that reads one is built again. The memo keys each place by
			// the instances it reads through a wrapper, so the second build shares only what it reads alike.
			instancesReadThroughWrapperParameters = await generator.instancesReadThroughPublicMockWrapperParameters(of: instantiable, mockDefaults: flatParameterMockDefaults)
			if !instancesReadThroughWrapperParameters.isEmpty {
				generator = try mockRootGenerator(builders: nil, constructionMemo: &constructionMemo)
			}
		}
		try Self.validateCycleLabelsArePassable(inTreesRootedAt: [generator])
		// An internal mock takes one builder for the places of one hole type and family its calls of other modules' public
		// mocks pass up, as its production tree's initializer does (`ScopeGenerator.seamMockBuilders`), so those places must
		// forward one value, as that initializer's places must.
		if instantiable.generateMock != .public, generator.passesUpBuilder {
			var placesByFamily = [ScopeGenerator.MockRootParameters.SeamMockBuilder.Family: [SeamSignature.Hole]]()
			var familiesInOrder = [ScopeGenerator.MockRootParameters.SeamMockBuilder.Family]()
			for place in Self.placesPassedUp(inMockTreeOf: instantiable, generator: generator) {
				let family = ScopeGenerator.MockRootParameters.SeamMockBuilder.Family(holeType: place.holeType, isSendable: place.isSendable)
				if placesByFamily[family] == nil {
					familiesInOrder.append(family)
				}
				placesByFamily[family, default: []].append(place)
			}
			let errors = familiesInOrder.flatMap { family in
				Self.placesForwardingOtherValuesErrors(of: instantiable, places: placesByFamily[family, default: []], holeType: family.holeType, isSendable: family.isSendable, instantiables: typeDescriptionToFulfillingInstantiableMap, declaredTypeNames: declaredTypeNames)
			}
			if let error = DependencyTreeGeneratorError.reportingAll(of: errors) {
				throw error
			}
		}
		// A public mock's tree holds a site for each hole (see `createMockTypeDescriptionToScopeMapping`), and a call of
		// another module's public mock passes up the places it cannot fill: `mock()` takes builders for them, shaped as a
		// seam's are. The sites' fields are what is in scope there, read from the tree as a seam's are, and the tree is built
		// again so that each site calls its builder, and each call hands its builders up.
		guard instantiable.generateMock == .public, let publicMockContext, generator.containsBuildSite || generator.passesUpBuilder else { return generator }
		// The root level holds what `mock()` binds under its bare label before its tree, as a seam's holds its parameters; the
		// builders do not change what it binds, so the generator built without them gives it.
		let rootLevel = await Self.publicMockRootLevel(
			of: instantiable,
			parameters: generator.mockRootParameters(instantiable: instantiable, mockDefaults: flatParameterMockDefaults),
			generator: generator,
			context: publicMockContext,
		)
		let holes = Self.holes(
			of: instantiable,
			generator: generator,
			bindsReceivesAgain: true,
			namesApartAtRoot: rootLevel.namesApart,
			parameters: rootLevel.parameters,
			receiversByParameter: rootLevel.receiversByField,
			proof: publicMockContext.proof,
			instantiables: typeDescriptionToFulfillingInstantiableMap,
		)
		let treeFunctionNames = Self.builderFunctionNamesOfProperties(in: generator, includingHoleSites: false)
		let rootLevelLabels = Set(rootLevel.parameters.map(\.property.label))
		func shapedBuilders(namedApartFrom otherParameters: [(label: String, access: AccessLevel)]) -> ShapedBuilders {
			Self.shapedBuilders(
				of: instantiable,
				generator: generator,
				holes: holes,
				parameters: rootLevel.parameters,
				// The root level's fields are parameters of `mock()` already named apart by `parameters`.
				otherParameters: otherParameters.filter { !rootLevelLabels.contains($0.label) },
				treeFunctionNames: treeFunctionNames,
				proof: publicMockContext.proof,
				instantiables: typeDescriptionToFulfillingInstantiableMap,
				ownScopeEnums: [:],
				scopeTypeNames: .publicMock,
				bindsReceivesAgain: true,
				namesApartAtRoot: rootLevel.namesApart,
			)
		}
		let builders = shapedBuilders(namedApartFrom: [])
		let builtGenerator = try mockRootGeneratorWithHoles(builders: builders)
		// The builders follow every other parameter, and each tier's are named apart from the parameters it takes as a seam's
		// are. A builder's name changes no other parameter's, so the tree is built again only when a builder takes another
		// name in some tier.
		let parameters = await builtGenerator.mockRootParameters(instantiable: instantiable, mockDefaults: flatParameterMockDefaults)
		let otherParameters = ScopeGenerator.publicMockPlan(
			of: instantiable,
			parameters: parameters,
			parameterNames: ScopeGenerator.mockRootParameterNames(of: parameters),
			context: publicMockContext,
		).parameters.filter { $0.builder == nil }.map { (label: $0.name, access: $0.access) }
		let buildersNamedApart = shapedBuilders(namedApartFrom: otherParameters)
		// The places of one builder must forward one value, as a seam's must.
		let enumsByKey = Dictionary(buildersNamedApart.scopeEnums.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
		let errors = buildersNamedApart.builders.flatMap { builder in
			let reachedSites = SeamSignature.ScopeEnum.sitesReached(from: builder.enumKey, in: enumsByKey)
			return Self.placesForwardingOtherValuesErrors(of: instantiable, places: holes.filter { reachedSites.contains($0.site) }, holeType: builder.enumKey.holeType, isSendable: builder.enumKey.isSendable, instantiables: typeDescriptionToFulfillingInstantiableMap, declaredTypeNames: declaredTypeNames)
		}
		if let error = DependencyTreeGeneratorError.reportingAll(of: errors) {
			throw error
		}
		guard buildersNamedApart.builders.map(SeamSignature.CallShape.Builder.init) != builders.builders.map(SeamSignature.CallShape.Builder.init) else { return builtGenerator }
		return try mockRootGeneratorWithHoles(builders: buildersNamedApart)
	}

	/// What a public mock's root level holds beside the root's children: the payload of every case of its root enums, and the
	/// first level on the route to every place beneath.
	struct PublicMockRootLevel {
		/// The fields `mock()`'s own bindings give the root level, before the root's children, each a binding `mock()` holds
		/// under its bare label before it builds its tree, as a seam's root level holds the seam's parameters: each `@Forwarded`
		/// property, in declaration order; each received dependency the mock cannot build, then each received only if
		/// available, as `T?`, then each closure, tuple, array or optional the mocked type itself instantiates that nothing
		/// builds, each in `mock()`'s order. One field per label. A received instance a type in the tree receives as a
		/// `LazilyInstantiated` is held as the wrapper `mock()` binds around it.
		let parameters: [SeamSignature.Parameter]
		/// What the root binds only under names apart.
		let namesApart: NamesApart
		/// The declarations in the mock's tree that receive each of `parameters`' own forms, in tree order, by the parameter's
		/// property: what a seam's parameter records as its receivers, which a fill's diagnostic names as the twin's does
		/// (`SeamSignature.Hole.Field.seamParameterOrigin`). A parameter no declaration receives in its own form has none.
		let receiversByField: [Property: [SeamSignature.Receiver]]

		/// What a public mock's root binds only under names apart, which no field of its root level holds.
		struct NamesApart {
			/// The labels the root binds only under names apart (`user_User` and `user_Draft`, `id_Badge` and `id_Token`): every
			/// receive of one beneath the root is bound again from the binding of its form, and its type's level carries it.
			var labels = Set<String>()
			/// The wrappers `mock()` builds around the instances it takes and binds under names apart (`session_lazilyInstantiated`
			/// beside the instance `session`), which it hands each receiver of one by that name: no scope binds one again. Where
			/// the instance keeps its label, the root level's field of it is the wrapper, which provides both forms. Where
			/// `mock()` names the instance apart too, no field holds the label, so a fill beneath that reads the wrapper finds
			/// no field of it, and the place is passed up.
			var wrappers = Set<Property>()
		}
	}

	/// The root level of `instantiable`'s public mock, whose `mock()` takes `parameters` and whose tree is `generator`'s.
	///
	/// A parameter `mock()` names apart has no field: the other holder of its label keeps the field, and a type beneath that
	/// receives the named-apart form binds it again (`mockBindsAgain(receiving:beneath:)`), or, where no binding holds the
	/// bare label, from the binding of its form (`NamesApart.labels`). A fill whose own receive is of a named-apart form that
	/// no type on its path receives is not filled: the place is passed up, as for a label the root's children share, and the
	/// caller's builder can capture the value instead. `fields(of:)` and `receivesBoundAgainOfAnyBuild` say so too.
	static func publicMockRootLevel(
		of instantiable: Instantiable,
		parameters: ScopeGenerator.MockRootParameters,
		generator: ScopeGenerator,
		context: PublicMockContext,
	) -> PublicMockRootLevel {
		let parameterNames = ScopeGenerator.mockRootParameterNames(of: parameters)
		let mockedTypeAccess = parameterAccess(instantiable.effectiveTypeAccess)
		let receiverModulesByLabel = ScopeGenerator.receiverModules(in: parameters.treeNames.propertyNodes, context: context)
		// The wrapper `mock()` binds around each instance it takes for a type that receives a `LazilyInstantiated`, by the
		// instance's property, the first `mock()` binds where wrappers of two kinds share an instance.
		var wrapperByInstance = [Property: Property]()
		for wrapper in parameters.lazilyInstantiatedReceivedProperties.map(\.asUnwrappedProperty) where wrapperByInstance[wrapper.asValidatedForDependencyCycles] == nil {
			wrapperByInstance[wrapper.asValidatedForDependencyCycles] = wrapper
		}
		// The field of a binding `mock()` holds under its bare label, which takes `parameter`: as visible as the parameter,
		// capped at the mocked type, as a seam's parameter field is. Where a type in the tree receives the instance the
		// parameter holds as a `LazilyInstantiated`, the field is the wrapper `mock()` binds around it, which a seam's
		// root level holds where its tree receives the wrapper, and generated code reads it from the binding `mock()` names
		// apart (`SeamHoles.valuesArguments`).
		func field(takenBy parameter: Property, receivedAs receivedLabel: String?, isOnlyIfAvailable: Bool) -> SeamSignature.Parameter {
			let access = ScopeGenerator.publicMockParameterAccess(ofType: parameter.typeDescription, receivedAs: receivedLabel, mockedType: instantiable, receiverModulesByLabel: receiverModulesByLabel, context: context)
			let fieldProperty = if let wrapper = wrapperByInstance[parameter.asUnwrappedProperty] {
				// `mock()` wraps an optional instance only where it holds one, so the wrapper is as optional as the parameter.
				parameter.typeDescription == wrapper.asValidatedForDependencyCycles.typeDescription ? wrapper : Property(label: wrapper.label, typeDescription: .optional(wrapper.typeDescription))
			} else {
				parameter
			}
			return SeamSignature.Parameter(
				property: fieldProperty,
				isPassThrough: false,
				access: access.level,
				tierAccess: min(access.level, mockedTypeAccess),
				isOnlyIfAvailable: isOnlyIfAvailable,
				accessCause: access.cause,
			)
		}
		// Each binding `mock()` holds under its bare label, in the root level's order; `mock()`'s parameters have distinct
		// names, so each label is held once.
		var fields = [SeamSignature.Parameter]()
		var labelsBoundApart = Set<String>()
		for dependency in instantiable.dependencies where dependency.source == .forwarded {
			fields.append(field(takenBy: dependency.property, receivedAs: nil, isOnlyIfAvailable: false))
		}
		for (property, name) in zip(parameters.flatReceivedProperties, parameterNames.flatReceivedNames) {
			if name == property.label {
				fields.append(field(takenBy: property, receivedAs: property.label, isOnlyIfAvailable: false))
			} else {
				labelsBoundApart.insert(property.label)
			}
		}
		// A field received only if available is `T?`, which fills no fulfiller's required receive of `T`. Where a call beneath
		// requires `T` that this module cannot build, the twin's seam requires it and fills such a receive, and a calling
		// mock's fill is rejected, a breach `public-mocks.md` states. What a call requires that this module builds when passed
		// `nil` is a child instead, held as the `T` it binds (`mockRootBinding(ofChild:of:)`).
		for override in parameterNames.onlyIfAvailableOverrides {
			if override.name == override.receivedProperty.label {
				fields.append(field(takenBy: Property(label: override.name, typeDescription: override.typeDescription), receivedAs: override.name, isOnlyIfAvailable: true))
			} else {
				labelsBoundApart.insert(override.receivedProperty.label)
			}
		}
		// What the mocked type instantiates that nothing can build and no builder builds – a closure, a tuple, an array or an
		// optional – is a parameter of `mock()`, by value, which the type's tree receives. One a type built inside a `@Sendable`
		// function instantiates is taken as a closure, which binds no value. A hole is a parameter of the tree built without
		// builders only. Only the mocked type's own: one a type in its tree instantiates is a parameter `mock()` binds at its
		// root too, but on no level, so a fill beneath that type that reads it is passed up, a written limit
		// `public-mocks.md` states.
		let holeSiteProperties = Set(generator.children.compactMap { child in child.holeSite == nil ? nil : child.property })
		let mockedTypeInstantiatedProperties = Set(instantiable.dependencies.compactMap { dependency -> Property? in
			if case .instantiated = dependency.source, !holeSiteProperties.contains(dependency.property) {
				dependency.property
			} else {
				nil
			}
		})
		for uncovered in parameters.flatUncoveredParameters where mockedTypeInstantiatedProperties.contains(uncovered.property) && !uncovered.isSendableAutoclosure {
			if uncovered.label == uncovered.property.label {
				fields.append(field(takenBy: uncovered.property, receivedAs: uncovered.property.label, isOnlyIfAvailable: false))
			} else {
				labelsBoundApart.insert(uncovered.property.label)
			}
		}
		let fieldLabels = Set(fields.map(\.property.label))
		// A child holds its label bare unless the root's children share it, or a field holds it.
		let labelsChildrenShare = generator.labelsChildrenShare
		let labelsChildrenHoldBare = Set(generator.children.compactMap(\.property?.label)).subtracting(labelsChildrenShare)
		// The declarations in the tree that receive each field's own form, in tree order, as a seam's parameter records them. A
		// form the mocked type's own received or forwarded property provides is received by the mocked type alone, as the
		// twin's seam takes that property as its own parameter, whose receiver is the seam: the types beneath it receive the
		// form from the mocked type.
		let accessByField = Dictionary(fields.map { ($0.property, $0.access) }, uniquingKeysWith: { first, _ in first })
		var formsMockedTypeProvides = Set<Property>()
		for dependency in instantiable.dependencies where dependency.source.isReceived || dependency.source == .forwarded {
			formsMockedTypeProvides.formUnion(Self.formsProvided(by: dependency.property))
		}
		var receiversByField = [Property: [SeamSignature.Receiver]]()
		for (index, receiver) in ScopeGenerator.treeReceivers(in: parameters.treeNames.propertyNodes, mockedType: instantiable).enumerated() {
			// An alias received only if available spells its fulfilling property non-optional, as its receiver records it, and
			// receives the field's optional form.
			let (receivedProperty, receivedForm, aliasProperty): (Property?, Property?, Property?) = switch receiver.dependency.source {
			case .received:
				(receiver.dependency.property, receiver.dependency.property, nil)
			case let .aliased(fulfillingProperty, _, onlyIfAvailable):
				(fulfillingProperty, onlyIfAvailable ? fulfillingProperty.asOptionalProperty : fulfillingProperty, receiver.dependency.property)
			case .instantiated, .forwarded:
				(nil, nil, nil)
			}
			// The mocked type's own dependencies come first.
			let isMockedTypesOwn = index < instantiable.dependencies.count
			guard let receivedProperty, let receivedForm, let access = accessByField[receivedForm], isMockedTypesOwn || !formsMockedTypeProvides.contains(receivedForm) else { continue }
			receiversByField[receivedForm, default: []].append(SeamSignature.Receiver(property: receivedProperty, declaringType: receiver.declaringType, declarationLocation: receiver.dependency.declarationLocation, access: access, aliasProperty: aliasProperty))
		}
		return PublicMockRootLevel(
			parameters: fields,
			namesApart: PublicMockRootLevel.NamesApart(
				labels: labelsBoundApart.union(labelsChildrenShare).subtracting(fieldLabels).subtracting(labelsChildrenHoldBare),
				wrappers: Set(parameters.lazilyInstantiatedReceivedProperties),
			),
			receiversByField: receiversByField,
		)
	}

	/// The names `instantiables` and `plainTypeDeclarations` declare types by at file scope. A type of such a name hides the
	/// standard library's type or the module of that name, so comparing an erased instantiator's first generic argument with
	/// a built type's forwarded properties does not see through it. An extension declares no type of the name it extends.
	static func namesOfTypesDeclaredAtFileScope(instantiables: [Instantiable], plainTypeDeclarations: [PlainTypeDeclaration]) -> DeclaredTypeNames {
		var moduleNamesByTypeName = [String: Set<String?>]()
		for instantiable in instantiables where !instantiable.declarationType.isExtension {
			if case let .simple(name, _) = instantiable.concreteInstantiable {
				moduleNamesByTypeName[name, default: []].insert(instantiable.moduleName)
			}
		}
		for declaration in plainTypeDeclarations where declaration.extendedType == nil {
			if case let .simple(name, _) = declaration.typeDescription {
				moduleNamesByTypeName[name, default: []].insert(declaration.moduleName)
			}
		}
		return DeclaredTypeNames(moduleNamesByTypeName: moduleNamesByTypeName)
	}

	/// The concrete type a mock builds `property` from when no `@Instantiable` fulfills its type, or `nil` when
	/// `erasedToConcreteTypeMap` names none. A lazily instantiated property is built from the type its instance
	/// is erased from, whichever form declares the erasure and whether or not the property is optional.
	static func concreteTypeErased(to property: Property, in erasedToConcreteTypeMap: [TypeDescription: TypeDescription]) -> TypeDescription? {
		erasedToConcreteTypeMap[property.typeDescription]
			?? property.asLazilyInstantiatedInstanceProperty.flatMap { erasedToConcreteTypeMap[$0.typeDescription] }
	}

	/// Whether a mock can build the received `property` from `scope` when it promotes the property to a
	/// child of the mock root. A type with `@Forwarded` properties can be built only by an `Instantiator`
	/// that is handed the forwarded values, so a mock cannot build a constant of that type, or lazily
	/// instantiate one: as in production, where such a property is never `@Instantiated`, it must be received.
	/// Nor can it build an erased instantiator whose first generic argument is not the type's `@Forwarded`
	/// properties, or is a tuple of them whose elements are not each one bare name (`Property.mockBuildsFirstGeneric(of:)`).
	/// Such a received property stays a `mock()` parameter; an `@Instantiated` declaration of a mismatched type is reported
	/// where a tree builds that declaration, and the tuple is built where a tree declares it.
	static func mockCanBuild(_ property: Property, from scope: Scope) -> Bool {
		guard property.mockBuildsFirstGeneric(of: scope.instantiable) else { return false }
		return !(property.propertyType.isConstant || property.propertyType.isLazilyInstantiated)
			|| !scope.instantiable.dependencies.contains(where: \.isForwarded)
	}

	/// A scope that `forwardedPropertyHiddenInPromotedTree` has yet to walk.
	private struct ScopeToWalkForHiddenForwardedProperty {
		let scope: Scope
		/// The receive of the forwarded label in another form that hides the forwarded property in `scope`, with the
		/// types from the one that declares it to `scope`, or `nil` when none does.
		let hidingReceive: (dependency: Dependency, chain: [TypeDescription])?
	}

	/// The first receive, walking the trees of a mock root's promoted children depth first in declaration order, of a
	/// property in `forwardedDependencies` beneath a type that receives its label in another form. The mock binds that
	/// form under a name of its own and passes it to the type under the label, inside the function that builds the type
	/// and the types it builds, where the label then names that form rather than the forwarded parameter. `nil` when
	/// there is none. Production rejects the same pair of receives under any root, since the closer of the two
	/// declarations they need hides the other.
	/// - Parameters:
	///   - forwardedDependencies: The mocked type's `@Forwarded` dependencies to look for.
	///   - instantiable: The mocked type.
	///   - promotedChildren: The mock root's promoted children, in the order the mock declares them.
	///   - isReceivedUnderItsLabel: Whether the mock passes a receive of a property under its label, rather than by name.
	static func forwardedPropertyHiddenInPromotedTree(
		forwardedDependencies: [Dependency],
		of instantiable: Instantiable,
		promotedChildren: ArraySlice<Scope.PropertyToGenerate>,
		isReceivedUnderItsLabel: (Property) -> Bool,
	) -> DependencyTreeGeneratorError.ForwardedPropertyHiddenInPromotedTree? {
		let forwardedProperties = instantiable.forwardedReceivableProperties
		/// The property a dependency receives from the scopes above it: the fulfilling property of an alias, the declared
		/// property of a receive, and `nil` for a property the type declares.
		func receivedProperty(of dependency: Dependency) -> Property? {
			switch dependency.source {
			case .received:
				dependency.property
			case let .aliased(fulfillingProperty, _, _):
				fulfillingProperty
			case .instantiated, .forwarded:
				nil
			}
		}
		for forwardedDependency in forwardedDependencies {
			let label = forwardedDependency.property.label
			/// Whether a receive of `property` is passed the forwarded property: its label's, of its type or of the
			/// optional form of its type, or the instance of a forwarded lazily instantiated property.
			func isForwardedProperty(_ property: Property) -> Bool {
				property.label == label && (forwardedProperties.contains(property) || forwardedProperties.contains(property.asUnwrappedProperty))
			}
			// Each scope is walked once beneath a hiding receive and once beneath none, which also ends a walk around a
			// cycle of `Instantiator`s.
			var walkedScopes = Set<ScopeVisit>()
			var promotedScopesToWalk = [ScopeToWalkForHiddenForwardedProperty]()
			for case let .instantiated(_, promotedScope, _) in promotedChildren
				where walkedScopes.insert(ScopeVisit(scope: ObjectIdentifier(promotedScope), isBeneathHidingReceive: false)).inserted
			{
				promotedScopesToWalk.append(ScopeToWalkForHiddenForwardedProperty(scope: promotedScope, hidingReceive: nil))
			}
			// The scope walked next is the last one on the stack, so the first goes last.
			var scopesToWalk = Array(promotedScopesToWalk.reversed())
			while let scopeToWalk = scopesToWalk.popLast() {
				let scope = scopeToWalk.scope
				if let hidingReceive = scopeToWalk.hidingReceive,
				   let hiddenReceive = scope.instantiable.dependencies.lazy
				   	.compactMap({ dependency in receivedProperty(of: dependency).map { (dependency: dependency, property: $0) } })
				   	.first(where: { isForwardedProperty($0.property) })
				{
					return .init(
						property: hiddenReceive.property,
						declarationLocation: hiddenReceive.dependency.declarationLocation,
						mockedType: instantiable.concreteInstantiable,
						forwardedProperty: forwardedDependency.property,
						hidingProperty: hidingReceive.dependency.property,
						hidingDeclarationLocation: hidingReceive.dependency.declarationLocation,
						chain: hidingReceive.chain,
					)
				} else {
					// The closest receive of the label in another form is what the types this scope builds read under it.
					let hidingReceive = scope.instantiable.dependencies
						.first { dependency in
							dependency.source.isReceived
								&& dependency.property.label == label
								&& !isForwardedProperty(dependency.property)
								&& isReceivedUnderItsLabel(dependency.property)
						}
						.map { (dependency: $0, chain: [scope.instantiable.concreteInstantiable]) }
						?? scopeToWalk.hidingReceive
					// A type that declares the label itself is what the types it builds receive under it, as in production.
					let declaresLabel = scope.instantiable.dependencies.contains { !$0.source.isReceived && $0.property.label == label }
					let firstChildIndex = scopesToWalk.endIndex
					for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate
						where !declaresLabel
						&& walkedScopes.insert(ScopeVisit(scope: ObjectIdentifier(childScope), isBeneathHidingReceive: hidingReceive != nil)).inserted
					{
						scopesToWalk.append(ScopeToWalkForHiddenForwardedProperty(
							scope: childScope,
							hidingReceive: hidingReceive.map { ($0.dependency, $0.chain + [childScope.instantiable.concreteInstantiable]) },
						))
					}
					// The scope walked next is the last one on the stack, so the first child goes last.
					scopesToWalk.reverseElements(from: firstChildIndex)
				}
			}
		}
		return nil
	}

	/// A visit of a scope by `forwardedPropertyHiddenInPromotedTree`.
	private struct ScopeVisit: Hashable {
		let scope: ObjectIdentifier
		let isBeneathHidingReceive: Bool
	}

	/// A receive of a label, in a mock's tree, from above the type that declares it.
	private struct HidingReceive {
		let dependency: Dependency
		/// The property received: the fulfilling property for an aliased dependency, the declared property otherwise.
		let property: Property
		/// Whether `dependency` requires `property`: it is not `onlyIfAvailable`.
		let isRequired: Bool
		/// The type that declares `dependency`.
		let hidingType: TypeDescription

		/// What `dependency` reads, which decides what it hides.
		var propertiesRead: Set<Property> {
			DependencyTreeGenerator.propertiesRead(byReceiveOf: dependency)
		}
	}

	/// A scope that `receivesPassedNilInMockTree` has yet to walk.
	private struct ScopeToWalkForHiddenReceivedProperty {
		let scope: Scope
		/// The tree of the mock that holds `scope`.
		let tree: DependencyTreeGeneratorError.ReceivedPropertyHiddenInMockTree.Tree
		/// The types from the type at the top of `tree` to the type of `scope`.
		let chain: [TypeDescription]
		/// The receives of each label walked by the closest type above `scope` that receives it, when no type between
		/// declares it, in declaration order.
		let hidingReceivesByLabel: [String: [HidingReceive]]
		/// The required receives of each label walked by every type above `scope`, back to the closest type that declares
		/// it, in the order they are walked: each pins the one declaration every receive of the label there reads.
		let requiredReceivesAboveByLabel: [String: [HidingReceive]]
		/// The labels walked that a type above `scope` declares, whose receives beneath resolve to that declaration.
		let declaredLabels: Set<String>
	}

	/// A visit of a scope by `receivesPassedNilInMockTree`: what the walk carries into it decides what it finds.
	private struct HiddenReceivedPropertyScopeVisit: Hashable {
		let scope: ObjectIdentifier
		let hidingPropertiesReadByLabel: [String: [Set<Property>]]
		let requiredPropertiesReadAboveByLabel: [String: [Set<Property>]]
		let declaredLabels: Set<String>
	}

	/// The labels the type of `scope` declares, which the types it builds receive under them and which its own aliases
	/// of them rename, and the receives of its dependencies from above it, as `receivesPassedNilInMockTree` walks them.
	/// A builder passed up to the mock's own parameter is read there, which the mock names apart from every label.
	private static func declaredLabelsAndReceivesFromAbove(of scope: Scope) -> (declaredLabels: Set<String>, receives: [HidingReceive]) {
		declaredLabelsAndReceivesFromAbove(of: scope.instantiable, publicMockCall: scope.publicMockCall)
	}

	/// See `declaredLabelsAndReceivesFromAbove(of:)`: of the type `instantiable` declares, built by `publicMockCall`.
	private static func declaredLabelsAndReceivesFromAbove(of instantiable: Instantiable, publicMockCall: PublicMockCall?) -> (declaredLabels: Set<String>, receives: [HidingReceive]) {
		let scopeType = instantiable.concreteInstantiable
		let declaredLabels = Set(instantiable.dependencies.lazy.filter { !$0.source.isReceived }.map(\.property.label))
		let receives = instantiable.dependencies.compactMap { dependency -> HidingReceive? in
			guard !(publicMockCall?.passesUpBuilder(receivedAs: dependency.property) ?? false) else { return nil }
			return Self.propertyReceivedFromAbove(byReceiveOf: dependency, onTypeDeclaring: declaredLabels).map {
				HidingReceive(dependency: dependency, property: $0.property, isRequired: $0.isRequired, hidingType: scopeType)
			}
		}
		return (declaredLabels, receives)
	}

	/// The properties each required receive of `label` beneath `scope` reads, in the trees of the types `scope` builds,
	/// back to a type that declares the label: every receive there resolves to the declaration `scope`'s receives of
	/// the label resolve to.
	private static func propertiesReadByRequiredReceives(of label: String, beneath scope: Scope) -> [Set<Property>] {
		var propertiesRead = [Set<Property>]()
		var visitedScopes: Set<ObjectIdentifier> = [ObjectIdentifier(scope)]
		var scopesToVisit = [scope]
		while let scopeToVisit = scopesToVisit.popLast() {
			for case let .instantiated(_, childScope, _) in scopeToVisit.propertiesToGenerate
				where visitedScopes.insert(ObjectIdentifier(childScope)).inserted
			{
				let (declaredLabels, receives) = declaredLabelsAndReceivesFromAbove(of: childScope)
				for receive in receives where receive.isRequired && receive.property.label == label {
					propertiesRead.append(receive.propertiesRead)
				}
				if !declaredLabels.contains(label) {
					scopesToVisit.append(childScope)
				}
			}
		}
		return propertiesRead
	}

	/// The receives only if available that a mock passes `nil`, as production does wherever its trees are built. In
	/// production every receive of a label in the mocked type's own tree, or in a promoted dependency's tree, back to a
	/// type in it that declares the label, resolves to the one declaration of the label above that tree – above the mocked
	/// type for its own tree, and above a promoted dependency's tree, which is built above the mocked type. A required
	/// receive of one of `labels` there, above a receive only if available, on its type, or beneath it, pins that
	/// declaration to its form, so the receive only if available, which reads no form one declaration provides together
	/// with it, is passed `nil` wherever the tree is built. The mock root binds the other form for the receivers that read
	/// it, so the mock passes the receive `nil` itself, and offers it nothing where no other receive reads that form.
	///
	/// A required receive on the receiving type, or beneath it, pins the receive wherever the type is built, so the walk
	/// lists those by the concrete type that declares each (`MockReceivesPassedNil.pinnedWhereverBuilt`). One above it
	/// pins it only in the places beneath that required receive, so the walk lists only its label
	/// (`MockReceivesPassedNil.labelsPinnedFromAbove`), and the mock judges each place of a receive of the label against
	/// the required receives above that place (`NearestDeclarations.recordRequiredReceives(of:)`): a type the trees build
	/// twice, pinned in one place and not in the other, is passed `nil` in the one and keeps what the mock binds in the
	/// other, as in production.
	///
	/// Two required receives of a label that no one declaration provides together pin it to two forms, so production can
	/// build neither one beneath or beside the other: the walk throws for the first such receive, walking the mocked
	/// type's own tree and then the trees of a mock root's promoted children, each depth first in declaration order. The
	/// mock binds the forms of the label apart and would pass one of the two under the label where the other would read
	/// it, or bind it in a scope where the other is read. A type that declares the label is what the types it builds
	/// receive under it, as in production, and the validation of each tree reports what that declaration hides.
	/// - Parameters:
	///   - labels: The labels the mock binds in several forms, the only ones that can hold such a pair.
	///   - instantiable: The mocked type.
	///   - scope: The scope of the mocked type, without the promoted children.
	///   - promotedChildren: The mock root's promoted children, in the order the mock declares them.
	private static func receivesPassedNilInMockTree(
		labels: Set<String>,
		of instantiable: Instantiable,
		scope mockedTypeScope: Scope,
		promotedChildren: ArraySlice<Scope.PropertyToGenerate>,
	) throws -> MockReceivesPassedNil {
		var walkedScopes = Set<HiddenReceivedPropertyScopeVisit>()
		var scopesToWalk = [ScopeToWalkForHiddenReceivedProperty]()
		// The mocked type's own tree is walked first: it is what the mock builds above its promoted children's trees.
		walkedScopes.insert(HiddenReceivedPropertyScopeVisit(scope: ObjectIdentifier(mockedTypeScope), hidingPropertiesReadByLabel: [:], requiredPropertiesReadAboveByLabel: [:], declaredLabels: []))
		scopesToWalk.append(ScopeToWalkForHiddenReceivedProperty(
			scope: mockedTypeScope,
			tree: .mockedType,
			chain: [mockedTypeScope.instantiable.concreteInstantiable],
			hidingReceivesByLabel: [:],
			requiredReceivesAboveByLabel: [:],
			declaredLabels: [],
		))
		for case let .instantiated(_, promotedScope, _) in promotedChildren
			where walkedScopes.insert(HiddenReceivedPropertyScopeVisit(scope: ObjectIdentifier(promotedScope), hidingPropertiesReadByLabel: [:], requiredPropertiesReadAboveByLabel: [:], declaredLabels: [])).inserted
		{
			let promotedType = promotedScope.instantiable.concreteInstantiable
			scopesToWalk.append(ScopeToWalkForHiddenReceivedProperty(
				scope: promotedScope,
				tree: .promotedDependency(promotedType),
				chain: [promotedType],
				hidingReceivesByLabel: [:],
				requiredReceivesAboveByLabel: [:],
				declaredLabels: [],
			))
		}
		var receivesPassedNil = MockReceivesPassedNil()
		// The scope walked next is the last one on the stack, so the first goes last.
		scopesToWalk.reverse()
		while let scopeToWalk = scopesToWalk.popLast() {
			let scope = scopeToWalk.scope
			let (labelsDeclaredByScope, receives) = Self.declaredLabelsAndReceivesFromAbove(of: scope)
			var receivesByLabel = [String: [HidingReceive]]()
			for receive in receives
				where labels.contains(receive.property.label) && !scopeToWalk.declaredLabels.contains(receive.property.label)
			{
				// Every receive of the label above, back to the closest type that declares it, and every earlier receive
				// of it on this type, resolve to the declaration this receive resolves to. Two required receives pin that
				// declaration to the forms both read, which no one declaration may provide. The closest type above that
				// receives the label and this type's earlier receives are compared first, then every required receive above.
				let receivesAbove = scopeToWalk.hidingReceivesByLabel[receive.property.label, default: []]
				let earlierReceives = receivesAbove + receivesByLabel[receive.property.label, default: []]
				let propertiesRead = receive.propertiesRead
				func isHiddenBy(_ earlierReceive: HidingReceive) -> Bool {
					earlierReceive.isRequired && !Self.oneDeclarationFulfills(propertiesRead, and: earlierReceive.propertiesRead)
				}
				let hidingReceive: (receive: HidingReceive, isOnItsOwnType: Bool)? = if !receive.isRequired {
					nil
				} else if let hidingReceiveIndex = earlierReceives.firstIndex(where: isHiddenBy) {
					(earlierReceives[hidingReceiveIndex], hidingReceiveIndex >= receivesAbove.count)
				} else {
					scopeToWalk.requiredReceivesAboveByLabel[receive.property.label]?.first(where: isHiddenBy).map { ($0, false) }
				}
				if let hidingReceive {
					throw DependencyTreeGeneratorError.receivedPropertyHiddenInMockTree(.init(
						property: receive.property,
						declarationLocation: receive.dependency.declarationLocation,
						mockedType: instantiable.concreteInstantiable,
						tree: scopeToWalk.tree,
						hidingProperty: hidingReceive.receive.property,
						hidingDeclarationLocation: hidingReceive.receive.dependency.declarationLocation,
						hidingType: hidingReceive.receive.hidingType,
						isHiddenOnItsOwnType: hidingReceive.isOnItsOwnType,
						chain: scopeToWalk.chain,
					))
				} else {
					receivesByLabel[receive.property.label, default: []].append(receive)
				}
			}
			// A receive only if available beneath, beside or above a required receive of its label in a form no one
			// declaration provides together with it is always passed `nil` in production. Two receives only if available
			// pin nothing: production fulfills each where it is built beneath a declaration of its type, and the mock
			// offers each its own override, as it does for siblings.
			let scopeType = scope.instantiable.concreteInstantiable
			for (label, receivesOfLabel) in receivesByLabel {
				var requiredPropertiesReadBeneath: [Set<Property>]?
				for receive in receivesOfLabel where !receive.isRequired {
					let propertiesRead = receive.propertiesRead
					func pins(_ requiredReceivePropertiesRead: Set<Property>) -> Bool {
						!Self.oneDeclarationFulfills(propertiesRead, and: requiredReceivePropertiesRead)
					}
					let isPinnedWhereverBuilt: Bool
					if receivesOfLabel.contains(where: { $0.isRequired && pins($0.propertiesRead) }) {
						isPinnedWhereverBuilt = true
					} else {
						let propertiesReadBeneath = requiredPropertiesReadBeneath ?? Self.propertiesReadByRequiredReceives(of: label, beneath: scope)
						requiredPropertiesReadBeneath = propertiesReadBeneath
						isPinnedWhereverBuilt = propertiesReadBeneath.contains(where: pins)
					}
					if isPinnedWhereverBuilt {
						receivesPassedNil.pinnedWhereverBuilt[label, default: [:]][scopeType, default: []].insert(receive.property)
					} else if scopeToWalk.requiredReceivesAboveByLabel[label, default: []].contains(where: { pins($0.propertiesRead) }) {
						receivesPassedNil.labelsPinnedFromAbove.insert(label)
					}
				}
			}
			var hidingReceivesByLabel = scopeToWalk.hidingReceivesByLabel.merging(receivesByLabel) { _, receivesOfScope in receivesOfScope }
			// Each form is kept once, the receive highest above first, so the walk of a tree a cycle builds again meets each
			// scope with what it carried there before and ends.
			var requiredReceivesAboveByLabel = scopeToWalk.requiredReceivesAboveByLabel
			for (label, receivesOfLabel) in receivesByLabel {
				for receive in receivesOfLabel where receive.isRequired {
					let propertiesRead = receive.propertiesRead
					if !requiredReceivesAboveByLabel[label, default: []].contains(where: { $0.propertiesRead == propertiesRead }) {
						requiredReceivesAboveByLabel[label, default: []].append(receive)
					}
				}
			}
			var declaredLabels = scopeToWalk.declaredLabels
			for label in labelsDeclaredByScope where labels.contains(label) {
				// A type that declares the label is what the types it builds receive under it, as in production.
				declaredLabels.insert(label)
				hidingReceivesByLabel[label] = nil
				requiredReceivesAboveByLabel[label] = nil
			}
			let hidingPropertiesReadByLabel = hidingReceivesByLabel.mapValues { $0.map(\.propertiesRead) }
			let requiredPropertiesReadAboveByLabel = requiredReceivesAboveByLabel.mapValues { $0.map(\.propertiesRead) }
			let firstChildIndex = scopesToWalk.endIndex
			for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate
				where walkedScopes.insert(HiddenReceivedPropertyScopeVisit(scope: ObjectIdentifier(childScope), hidingPropertiesReadByLabel: hidingPropertiesReadByLabel, requiredPropertiesReadAboveByLabel: requiredPropertiesReadAboveByLabel, declaredLabels: declaredLabels)).inserted
			{
				scopesToWalk.append(ScopeToWalkForHiddenReceivedProperty(
					scope: childScope,
					tree: scopeToWalk.tree,
					chain: scopeToWalk.chain + [childScope.instantiable.concreteInstantiable],
					hidingReceivesByLabel: hidingReceivesByLabel,
					requiredReceivesAboveByLabel: requiredReceivesAboveByLabel,
					declaredLabels: declaredLabels,
				))
			}
			// The scope walked next is the last one on the stack, so the first child goes last.
			scopesToWalk.reverseElements(from: firstChildIndex)
		}
		if !receivesPassedNil.labelsPinnedFromAbove.isEmpty {
			// The mocked type's own receives are above its own children, not above the children it promotes, whose trees
			// production builds above it.
			for case let .instantiated(promotedProperty, _, _) in promotedChildren {
				receivesPassedNil.promotedProperties.insert(promotedProperty)
			}
		}
		return receivesPassedNil
	}

	/// The properties each required receive of the type of `scope` reads from above it, by label, as
	/// `receivesPassedNilInMockTree` walks them: each pins the declaration of its label that every receive of it beneath
	/// the type reads, back to a type that declares the label.
	static func propertiesReadByRequiredReceivesFromAbove(of scope: ConstructionScope) -> [(label: String, propertiesRead: Set<Property>)] {
		declaredLabelsAndReceivesFromAbove(of: scope.instantiable, publicMockCall: scope.publicMockCall).receives.compactMap { receive in
			receive.isRequired ? (receive.property.label, receive.propertiesRead) : nil
		}
	}

	/// Whether a required receive that reads `requiredReceivePropertiesRead` pins the declaration a receive only if
	/// available of `dependency` reads to a form it cannot read, so that production passes it `nil`, as
	/// `receivesPassedNilInMockTree` judges it.
	static func requiredReceive(reading requiredReceivePropertiesRead: Set<Property>, pinsReceiveOf dependency: Dependency) -> Bool {
		!oneDeclarationFulfills(propertiesRead(byReceiveOf: dependency), and: requiredReceivePropertiesRead)
	}

	/// The property a receive of `dependency` reads from above the type that declares it, which declares
	/// `labelsDeclaredByType`: the received property, or an alias's fulfilling property, with whether the receive
	/// requires it. `nil` for a dependency the type creates, and for an alias of a label the type declares, which renames
	/// that property, unless the alias keeps the label it renames.
	private static func propertyReceivedFromAbove(
		byReceiveOf dependency: Dependency,
		onTypeDeclaring labelsDeclaredByType: Set<String>,
	) -> (property: Property, isRequired: Bool)? {
		switch dependency.source {
		case let .received(onlyIfAvailable):
			(dependency.property, !onlyIfAvailable)
		case let .aliased(fulfillingProperty, _, onlyIfAvailable):
			fulfillingProperty.label == dependency.property.label || !labelsDeclaredByType.contains(fulfillingProperty.label)
				? (fulfillingProperty, !onlyIfAvailable)
				: nil
		case .instantiated, .forwarded:
			nil
		}
	}

	/// The properties a receive of `dependency` reads, as the validation of hidden received properties judges them: a
	/// receive of an optional property reads its non-optional form too, and an `onlyIfAvailable` alias reads the
	/// optional form of its fulfilling property.
	private static func propertiesRead(byReceiveOf dependency: Dependency) -> Set<Property> {
		switch dependency.source {
		case let .aliased(fulfillingProperty, _, onlyIfAvailable):
			onlyIfAvailable
				? Set(fulfillingProperty.formsReadByOnlyIfAvailableReceive)
				: [fulfillingProperty, fulfillingProperty.asUnwrappedProperty]
		case .received, .instantiated, .forwarded:
			[dependency.property, dependency.property.asUnwrappedProperty]
		}
	}

	/// Whether one declaration can fulfill two receives that read `properties` and `otherProperties`: a declaration
	/// fulfills a receive that reads it, or, when it is lazily instantiated, the instance it provides. A declaration that
	/// fulfills both is therefore among the properties one of them reads.
	private static func oneDeclarationFulfills(_ properties: Set<Property>, and otherProperties: Set<Property>) -> Bool {
		func fulfills(_ declaredProperty: Property, _ propertiesRead: Set<Property>) -> Bool {
			propertiesRead.contains(declaredProperty)
				|| declaredProperty.asLazilyInstantiatedInstanceProperty.map(propertiesRead.contains) ?? false
		}
		return properties.union(otherProperties).contains { fulfills($0, properties) && fulfills($0, otherProperties) }
	}

	/// A scope that `validateMockRootScopeForCycles` has yet to walk.
	private struct ScopeToWalkForCycles {
		let scope: Scope
		/// The properties of the scopes `scope` is built inside, innermost first, as cycle validation sees them.
		let propertyStack: [Property]
		/// The scopes built for the entries of `propertyStack`, beside it: `scope` first, then the scopes it is built
		/// inside, up to the mock root's child.
		let scopeStack: [Scope]
		/// The lazily instantiated properties on `propertyStack`, keyed by the constant each is validated as.
		let lazilyInstantiatedDeclarations: [Property: Property]

		/// The properties the nearest declaration of `label` above `scope` declares, as cycle validation sees them, with how
		/// many scopes the declaring scope is built inside, or `nil` when no scope above declares the label. Each scope
		/// above declares, for the scopes it builds, the properties it creates and, at the mock root, which is built inside
		/// no scope, the dependencies it promotes, several forms of one label among them. Asked only of a dependency that
		/// might close a cycle, so nothing is gathered for any other.
		func nearestDeclaration(of label: String, mockRootScope: Scope) -> (properties: [Property], depth: Int)? {
			for index in scopeStack.indices.dropFirst() {
				let properties = Self.declarations(of: label, by: scopeStack[index])
				guard properties.isEmpty else { return (properties, scopeStack.count - index) }
			}
			let properties = Self.declarations(of: label, by: mockRootScope)
			return properties.isEmpty ? nil : (properties, 0)
		}

		/// The properties of `label` that `scope` declares for the scopes it builds, as cycle validation sees them, in the
		/// order it declares them.
		private static func declarations(of label: String, by scope: Scope) -> [Property] {
			var properties = [Property]()
			for dependency in scope.instantiable.dependencies where dependency.property.label == label && scope.createdProperties.contains(dependency.property) {
				properties.append(dependency.property.asValidatedForDependencyCycles)
			}
			for propertyToGenerate in scope.propertiesToGenerate where propertyToGenerate.property.label == label && !scope.createdProperties.contains(propertyToGenerate.property) {
				properties.append(propertyToGenerate.property.asValidatedForDependencyCycles)
			}
			return properties
		}
	}

	/// The children a mock root promotes, in the order its tree first receives them: the order in which a walk first
	/// meets a receive of each. The walk visits the mock root's own dependencies in declaration order, then the tree of
	/// each child it instantiates, depth first, each type's dependencies before its children's trees, all in
	/// declaration order. It then walks, in the order it first met them, the trees of the dependencies the mock builds
	/// for what its receivers require, which are where the mock tree receives the rest, and, once those are walked, the
	/// trees of the fills the calls of other modules' public mocks it met pass, in the order it met the calls: a call
	/// inside a fill can be the only receiver of a dependency its called mock builds when passed `nil`, which the mock
	/// promotes (`builtWhenNilByPublicMockCalls`). A receive of a promoted child is one of its property, of the property's
	/// optional form, or of the instance of a lazily instantiated property.
	///
	/// The order depends only on where properties are declared and how they are nested, never on their labels or type
	/// names: when two promoted children receive each other only if available, the one received first is built second,
	/// as the property declared first is in production.
	/// - Parameters:
	///   - promotedChildren: The children the mock root promotes. The walk meets a receive of each, since each is a
	///     dependency that the mock root's tree, the tree of a dependency the mock builds for a receiver, or the tree of a
	///     fill in either, receives.
	///   - mockRootScope: The scope of the mocked type, without the promoted children.
	///   - scopesBuiltForRequiredProperties: The scope from which the mock builds each received property that a
	///     receiver requires, when it builds one: the scopes whose trees the promotion worklist walks.
	private static func inOrderTheMockTreeFirstReceives(
		_ promotedChildren: [Scope.PropertyToGenerate],
		walkingFrom mockRootScope: Scope,
		scopesBuiltForRequiredProperties: [Property: Scope],
	) -> [Scope.PropertyToGenerate] {
		var promotedChildIndexByReceivedProperty = [Property: Int]()
		for (index, promotedChild) in promotedChildren.enumerated() {
			for receivableProperty in promotedChild.receivableProperties {
				promotedChildIndexByReceivedProperty[receivableProperty.asUnwrappedProperty] = index
			}
		}
		var orderedIndices = [Int]()
		var orderedIndexSet = Set<Int>()
		var walkedScopes = Set<ObjectIdentifier>()
		// Every receive the walk meets, in order. The trees of the dependencies the mock builds for them are walked in
		// that order once the trees met before are walked, and only while a promoted child is left to order.
		var receivedProperties = [Property]()
		// The fills of the calls of other modules' public mocks the walk meets, in order, whose trees are walked last.
		var fillScopes = [Scope]()
		/// Walks the tree of `rootScope` depth first, each scope's dependencies before its children's trees, with a
		/// stack of the scopes left to walk, since a tree can be as deep as the module has types.
		func walk(_ rootScope: Scope) {
			var scopesToWalk = [rootScope]
			while let scope = scopesToWalk.popLast() {
				// Once every promoted child is ordered, nothing further can change the order.
				guard orderedIndices.count < promotedChildren.count else { return }
				guard walkedScopes.insert(ObjectIdentifier(scope)).inserted else { continue }
				for dependency in scope.instantiable.dependencies {
					let receivedProperty: Property? = switch dependency.source {
					case .received:
						dependency.property
					case let .aliased(fulfillingProperty, _, _):
						fulfillingProperty
					case .instantiated, .forwarded:
						nil
					}
					if let receivedProperty {
						receivedProperties.append(receivedProperty)
						if let index = promotedChildIndexByReceivedProperty[receivedProperty.asUnwrappedProperty],
						   orderedIndexSet.insert(index).inserted
						{
							orderedIndices.append(index)
						}
					}
				}
				let firstChildIndex = scopesToWalk.endIndex
				for case let .instantiated(_, childScope, _) in scope.propertiesToGenerate {
					scopesToWalk.append(childScope)
				}
				// The scope walked next is the last one on the stack, so the first child goes last.
				scopesToWalk.reverseElements(from: firstChildIndex)
				if scope.publicMockCall != nil {
					for case let .fill(_, fillScope) in scope.holeArguments {
						fillScopes.append(fillScope)
					}
				}
			}
		}
		walk(mockRootScope)
		var receivedPropertyIndex = 0
		var fillScopeIndex = 0
		while orderedIndices.count < promotedChildren.count,
		      receivedPropertyIndex < receivedProperties.count || fillScopeIndex < fillScopes.count
		{
			if receivedPropertyIndex < receivedProperties.count {
				if let builtScope = scopesBuiltForRequiredProperties[receivedProperties[receivedPropertyIndex]] {
					walk(builtScope)
				}
				receivedPropertyIndex += 1
			} else {
				walk(fillScopes[fillScopeIndex])
				fillScopeIndex += 1
			}
		}
		return orderedIndices.map { promotedChildren[$0] }
	}

	/// Walks a post-promotion mock root scope for dependency cycles.
	/// The mock root scope has @Received dependencies promoted as children,
	/// which can create cycles not visible in the pre-promotion scope.
	/// The walk goes depth first, in the order each scope declares its children, and keeps its own stack of
	/// the scopes left to walk, since a tree can be as deep as the module has types.
	private func validateMockRootScopeForCycles(_ mockRootScope: Scope) throws {
		var scopesToWalk = [ScopeToWalkForCycles(scope: mockRootScope, propertyStack: [], scopeStack: [], lazilyInstantiatedDeclarations: [:])]
		while let scopeToWalk = scopesToWalk.popLast() {
			let scope = scopeToWalk.scope
			let propertyStack = scopeToWalk.propertyStack
			// Check dependencies for cycles (catches @Received references back to ancestors).
			for dependency in scope.instantiable.dependencies where !dependency.isForwarded {
				let declaredPropertyForDependency = dependency.source.fulfillingProperty ?? dependency.property
				let propertyForDependency = declaredPropertyForDependency.asValidatedForDependencyCycles
				// An `onlyIfAvailable` dependency is passed `nil` instead (`Dependency.canCloseDependencyCycle`), and an
				// `onlyIfAvailable` alias is bound to `nil`, which a receive of it reads.
				guard dependency.canCloseDependencyCycle,
				      // Every form a stack entry can match has the property's label, and nearly every dependency's label is on no
				      // entry, so the forms are made only for one whose label is.
				      propertyStack.contains(where: { $0.label == propertyForDependency.label })
				else { continue }
				let closingReceive = Self.closingReceive(of: dependency, in: scope)
				// `throwIfInvalidCycle` throws for an instantiation only when every property on the cycle, its own included, is
				// constant, so an instantiation of an instantiator closes no cycle it could report.
				guard closingReceive != nil || propertyForDependency.propertyType.isConstant else { continue }
				// A mock promotes a received optional property as the non-optional value it builds, so a receive of the
				// non-optional form inside the tree it builds reaches it too.
				let receivedForms: [Property] = if dependency.isInstantiated {
					[propertyForDependency]
				} else {
					[propertyForDependency, Property(label: propertyForDependency.label, typeDescription: .optional(propertyForDependency.typeDescription))]
				}
				guard let cycleIndex = Self.indexOfEntryClosedOn(
					by: declaredPropertyForDependency,
					of: scope,
					receivedForms: receivedForms,
					closesByReceive: closingReceive != nil,
					propertyStack: propertyStack,
					concreteTypeOfEntry: { scopeToWalk.scopeStack[$0].instantiable.concreteInstantiable },
					nearestDeclaration: { scopeToWalk.nearestDeclaration(of: $0, mockRootScope: mockRootScope) },
				) else {
					continue
				}
				let propertiesInCycle = [propertyForDependency] + propertyStack[0...cycleIndex]
				try throwIfInvalidCycle(
					propertiesInCycle: propertiesInCycle,
					// A receive is reported as declared; an instantiation as the property it instantiates.
					declaredProperty: closingReceive == nil ? declaredPropertyForDependency : dependency.property,
					declarationLocation: dependency.declarationLocation,
					directParent: scope.instantiable.concreteInstantiable,
					closingReceive: closingReceive,
					lazilyInstantiatedProperties: Self.lazilyInstantiatedProperties(
						closingCycleWith: declaredPropertyForDependency,
						validatedPropertiesInCycle: propertiesInCycle,
						lazilyInstantiatedDeclarations: scopeToWalk.lazilyInstantiatedDeclarations,
					),
				)
			}

			// Walk the children next.
			let firstChildIndex = scopesToWalk.endIndex
			for childPropertyToGenerate in scope.propertiesToGenerate {
				switch childPropertyToGenerate {
				case let .instantiated(declaredChildProperty, childScope, _):
					let childProperty = declaredChildProperty.asValidatedForDependencyCycles
					guard !propertyStack.indices.contains(where: {
						propertyStack[$0] == childProperty && scopeToWalk.scopeStack[$0].instantiable.concreteInstantiable == childScope.instantiable.concreteInstantiable
					}) else { continue }
					scopesToWalk.append(ScopeToWalkForCycles(
						scope: childScope,
						propertyStack: [childProperty] + propertyStack,
						scopeStack: [childScope] + scopeToWalk.scopeStack,
						lazilyInstantiatedDeclarations: scopeToWalk.lazilyInstantiatedDeclarations.recordingLazilyInstantiated(declaredChildProperty),
					))
				case .aliased, .hole:
					// A hole's tree is a fill's, which a mock never builds: a mock's scopes hold no hole.
					break
				}
			}
			// The scope walked next is the last one on the stack, so the first child goes last.
			scopesToWalk.reverseElements(from: firstChildIndex)
		}
	}
}

/// A mock root whose own checks have passed: the cycles and hidden receives of the trees of the dependencies it
/// promotes, and the access of every construction its mock makes. Made only in this file, where
/// `createMockRootScopeGenerator` runs those checks, and the one way that function freezes the root's tree, so no other
/// mock root's outcome decides whether this one is built. As `ValidatedWorld` is, a convention the compiler enforces by
/// access.
struct MockRootPlan {
	fileprivate init(mockRootScope: Scope, frozenScopeMap: FrozenScopeMap) {
		self.mockRootScope = mockRootScope
		self.frozenScopeMap = frozenScopeMap
	}

	/// The root's record, and the table its tree is found in.
	func freezingRoot() -> (table: ScopeTable, record: ScopeRecord) {
		frozenScopeMap.freezing(rootScope: mockRootScope)
	}

	private let mockRootScope: Scope
	private let frozenScopeMap: FrozenScopeMap
}
